import concurrent.futures
import http.server
import json
import socket
import subprocess
import sys
import threading
import unittest

import test_tailscale_control as sharing


class PlatformControlIntegrationTests(sharing.ControlIntegrationTests):
    # Run the existing routing suite against the combined service too.
    BROKER_SCRIPT = "t3_control.py"

    def start_broker(self):
        self.env["TEA_SOCKET_PATH"] = str(self.directory / "tea.sock")
        super().start_broker()

    def tea(self, action):
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(5)
            client.connect(self.env["TEA_SOCKET_PATH"])
            client.sendall(json.dumps({"action": action, "payload": {}}).encode())
            with client.makefile("rb") as handle:
                return json.loads(handle.readline())

    def healthcheck(self):
        return subprocess.run(
            [sys.executable, str(sharing.ROOT / self.BROKER_SCRIPT), "--healthcheck"],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=5,
        )

    def test_health_requires_both_socket_apis_and_applied_routes(self):
        self.assertTrue(self.tea("ping")["success"])
        self.assertEqual(self.healthcheck().returncode, 0)
        path = self.directory / "tea.sock"
        path.rename(self.directory / "tea-offline.sock")
        self.assertNotEqual(self.healthcheck().returncode, 0)
        (self.directory / "tea-offline.sock").rename(path)
        self.daemon.running = False
        self.assertNotEqual(self.healthcheck().returncode, 0)
        self.daemon.running = True
        self.assertEqual(self.healthcheck().returncode, 0)

    def test_failed_socket_startup_exits_instead_of_serving_half_the_apis(self):
        self.stop_broker()
        blocker = self.directory / "not-a-directory"
        blocker.write_text("block socket startup")
        env = {**self.env, "TEA_SOCKET_PATH": str(blocker / "tea.sock")}
        result = subprocess.run(
            [sys.executable, str(sharing.ROOT / self.BROKER_SCRIPT)],
            env=env,
            capture_output=True,
            text=True,
            timeout=5,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(str(blocker), result.stderr)

    def test_slow_gitea_request_does_not_block_sharing(self):
        started = threading.Event()
        release = threading.Event()

        class SlowGitea(http.server.BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_GET(self):
                if self.path != "/api/v1/user/repos?limit=50":
                    self.send_error(404)
                    return
                started.set()
                release.wait(10)
                body = b'[{"name":"demo","full_name":"ai/demo","private":false}]'
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), SlowGitea)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.addCleanup(release.set)
        self.stop_broker()
        self.env.update(
            GITEA_URL=f"http://127.0.0.1:{server.server_port}",
            GITEA_TOKEN="test-token",
        )
        self.start_broker()
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            pending = pool.submit(self.tea, "list_repos")
            try:
                self.assertTrue(started.wait(2), "Gitea request did not start")
                result = subprocess.run(
                    [sys.executable, str(sharing.ROOT / "t3_share_cli.py"), "--json", "list"],
                    env=self.env,
                    capture_output=True,
                    text=True,
                    timeout=2,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    json.loads(result.stdout)["t3_url"],
                    "https://t3-dev-2.example.ts.net",
                )
            finally:
                release.set()
            response = pending.result(timeout=5)
        self.assertTrue(response["success"])
        self.assertEqual(response["data"][0]["full_name"], "ai/demo")


if __name__ == "__main__":
    unittest.main()
