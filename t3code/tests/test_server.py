import configparser
import http.server
import importlib.util
import json
import os
from pathlib import Path
import signal
import shlex
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("t3_server", ROOT / "server.py")
server = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = server
spec.loader.exec_module(server)


class ServerRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.starts = self.root / "starts"
        self.state = "200"
        self.requests = 0
        self.release = threading.Event()
        owner = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_GET(self):
                owner.requests += 1
                if owner.state == "hang":
                    owner.release.wait(3)
                    return
                status = int(owner.state)
                self.send_response(status)
                if status == 302:
                    self.send_header("Location", "/")
                self.send_header("Content-Length", "2")
                self.end_headers()
                try:
                    self.wfile.write(b"ok")
                except BrokenPipeError:
                    pass

        self.http = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.http.server_port}/"
        threading.Thread(target=self.http.serve_forever, daemon=True).start()
        self.addCleanup(self.http.server_close)
        self.addCleanup(self.http.shutdown)
        self.addCleanup(self.release.set)

    def wait_for(self, predicate, timeout=4):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.01)
        self.fail("timed out waiting for test process state")

    def pids(self):
        return [int(p) for p in self.starts.read_text().split()] if self.starts.exists() else []

    def launch(self, code=None, supervised=False, **overrides):
        code = code or "import time; time.sleep(60)"
        child = (
            "import os; from pathlib import Path; "
            f"p=Path({str(self.starts)!r}); "
            "f=p.open('a'); f.write(str(os.getpid())+'\\n'); f.close(); "
            + code
        )
        settings = dict(
            url=self.url, interval=0.03, startup_grace=0.3, failure_limit=3,
            max_restarts=2, retry_delay=0.01, stop_timeout=0.1, probe_timeout=0.1,
        )
        settings.update(overrides)
        bootstrap = (
            "import json,sys; "
            f"sys.path.insert(0,{str(ROOT)!r}); "
            "from server import Settings,run; "
            "sys.exit(run(json.loads(sys.argv[1]),Settings(**json.loads(sys.argv[2]))))"
        )
        self.output = self.root / "runner.log"
        command = [sys.executable, "-c", bootstrap,
                   json.dumps([sys.executable, "-c", child]), json.dumps(settings)]
        if supervised:
            config = configparser.ConfigParser(interpolation=None)
            config.read(ROOT / "supervisord.conf")
            section = dict(config["program:t3code"])
            for key in ("user", "directory", "environment"):
                section.pop(key, None)
            section.update(command=shlex.join(command), stdout_logfile=str(self.output),
                           redirect_stderr="true", stopwaitsecs="2")
            isolated = configparser.ConfigParser(interpolation=None)
            isolated["supervisord"] = dict(nodaemon="true", logfile="/dev/null",
                                           pidfile=str(self.root / "supervisord.pid"))
            isolated["program:t3code"] = section
            config_path = self.root / "supervisord.conf"
            with config_path.open("w") as handle:
                isolated.write(handle)
            command = ["/usr/bin/supervisord", "-c", str(config_path)]
        with (self.root / "supervisor.log" if supervised else self.output).open("w") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)

        def cleanup():
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)
            for pid in self.pids():
                try:
                    os.killpg(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

        self.addCleanup(cleanup)
        return process

    def test_success_requires_http_200_and_bypasses_proxy(self):
        from unittest.mock import patch
        with patch.dict(os.environ, {"http_proxy": "http://127.0.0.1:1", "no_proxy": ""}):
            self.assertTrue(server.healthy(self.url, 0.2))
        for status in ("302", "401", "503"):
            self.state = status
            self.assertFalse(server.healthy(self.url, 0.2), status)

    def test_tcp_accepting_but_silent_application_fails_within_deadline(self):
        self.state = "hang"
        with socket.create_connection(("127.0.0.1", self.http.server_port), timeout=0.2):
            pass
        started = time.monotonic()
        self.assertFalse(server.healthy(self.url, 0.1))
        self.assertLess(time.monotonic() - started, 1)

    def test_connection_refused_is_unhealthy(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            url = f"http://127.0.0.1:{listener.getsockname()[1]}/"
            self.assertFalse(server.healthy(url, 0.1))

    def test_startup_and_transient_failures_do_not_restart(self):
        self.state = "503"
        process = self.launch(startup_grace=2)
        self.wait_for(lambda: self.requests >= 3)
        self.assertEqual(len(self.pids()), 1)
        self.state = "200"
        self.wait_for(lambda: "HTTP ready" in self.output.read_text())
        self.state = "503"
        before = self.requests
        self.wait_for(lambda: self.requests > before)
        self.state = "200"
        self.wait_for(lambda: self.requests > before + 3)
        self.assertEqual(len(self.pids()), 1)
        self.assertIsNone(process.poll())

    def test_persistent_http_failure_stops_at_restart_budget(self):
        self.state = "503"
        process = self.launch(startup_grace=0)
        self.assertEqual(process.wait(timeout=4), 78)
        self.assertEqual(len(self.pids()), 3)
        self.assertIn("restart budget exhausted", self.output.read_text())

    def test_hung_application_consumes_finite_restart_budget(self):
        self.state = "hang"
        process = self.launch(startup_grace=0, failure_limit=1, max_restarts=1)
        self.assertEqual(process.wait(timeout=4), 78)
        self.assertEqual(len(self.pids()), 2)

    def test_child_crashes_also_consume_restart_budget(self):
        process = self.launch("raise SystemExit(7)")
        self.assertEqual(process.wait(timeout=4), 78)
        self.assertEqual(len(self.pids()), 3)

    def test_sigterm_stops_child_without_restarting(self):
        process = self.launch()
        self.wait_for(lambda: len(self.pids()) == 1)
        pid = self.pids()[0]
        process.terminate()
        self.assertEqual(process.wait(timeout=3), 0)
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)
        self.assertEqual(len(self.pids()), 1)

    def test_sigterm_ignoring_child_is_killed_before_exit(self):
        process = self.launch(
            "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); "
            f"Path({str(self.root / 'ready')!r}).touch(); time.sleep(60)"
        )
        self.wait_for(lambda: (self.root / "ready").exists())
        pid = self.pids()[0]
        process.terminate()
        self.assertEqual(process.wait(timeout=3), 0)
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_supervisor_cannot_reset_the_recovery_budget(self):
        config = configparser.ConfigParser(interpolation=None)
        config.read(ROOT / "supervisord.conf")
        section = config["program:t3code"]
        self.assertEqual(section["autorestart"], "false")
        self.assertEqual(section["startsecs"], "0")
        self.assertIn("/usr/local/bin/t3code-server", section["command"])
        self.assertGreater(int(section["stopwaitsecs"]), server.Settings().stop_timeout + 5)

    @unittest.skipUnless(Path("/usr/bin/supervisord").exists(), "requires Supervisor")
    def test_real_supervisor_leaves_exhausted_runner_stopped(self):
        process = self.launch("raise SystemExit(7)", supervised=True)
        self.wait_for(lambda: self.output.exists() and "restart budget exhausted" in self.output.read_text())
        time.sleep(0.4)
        self.assertEqual(len(self.pids()), 3)
        self.assertIsNone(process.poll())

    def test_replacement_can_recover_and_remain_healthy(self):
        self.state = "503"
        process = self.launch(startup_grace=0)
        self.wait_for(lambda: len(self.pids()) == 2)
        self.state = "200"
        before = self.requests
        self.wait_for(lambda: self.requests >= before + 6)
        self.assertIsNone(process.poll())
        self.assertEqual(len(self.pids()), 2)

    def test_shutdown_kills_remaining_process_group_members(self):
        grandchild = self.root / "grandchild"
        child_code = (
            "import os,signal,time; from pathlib import Path; "
            "signal.signal(signal.SIGTERM,signal.SIG_IGN); "
            f"Path({str(grandchild)!r}).write_text(str(os.getpid())); time.sleep(60)"
        )
        process = self.launch(
            f"import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',{child_code!r}]); "
            "time.sleep(60)"
        )
        self.wait_for(lambda: grandchild.exists() and grandchild.read_text())
        pid = int(grandchild.read_text())
        process.terminate()
        self.assertEqual(process.wait(timeout=3), 0)

        def stopped():
            result = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)],
                                    capture_output=True, text=True, timeout=2)
            return not result.stdout.strip() or result.stdout.strip().startswith("Z")

        self.wait_for(stopped)

    def test_descendant_gets_shutdown_grace_after_leader_exits(self):
        ready = self.root / "descendant-ready"
        finished = self.root / "descendant-finished"
        child_code = (
            "import signal,sys,time; from pathlib import Path; "
            "signal.signal(signal.SIGTERM, lambda *_: "
            f"(time.sleep(0.2),Path({str(finished)!r}).touch(),sys.exit(0))); "
            f"Path({str(ready)!r}).touch(); time.sleep(60)"
        )
        process = self.launch(
            f"import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',{child_code!r}]); "
            "time.sleep(60)", stop_timeout=0.8,
        )
        self.wait_for(ready.exists)
        process.terminate()
        self.assertEqual(process.wait(timeout=3), 0)
        self.assertTrue(finished.exists(), "descendant was killed before completing graceful shutdown")

    def test_missing_executable_stops_without_restart_loop(self):
        from unittest.mock import patch
        with patch("signal.signal"):
            self.assertEqual(server.run(["/missing-t3-executable"], server.Settings()), 78)


if __name__ == "__main__":
    unittest.main()
