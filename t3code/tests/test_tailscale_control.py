import concurrent.futures
import http.server
import json
import os
from pathlib import Path
import socket
import socketserver
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FakeDaemon(socketserver.UnixStreamServer):
    def __init__(self, path):
        super().__init__(str(path), DaemonHandler)
        self.hostname = "t3-dev-2.example.ts.net"
        self.config = None
        self.etag = 0
        self.fail_updates = False
        self.running = True
        self.certificates = True


class DaemonHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def reply(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("ETag", f'"{self.server.etag}"')
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.headers["Host"] != "local-tailscaled.sock":
            self.reply({"error": "Invalid LocalAPI host"}, 403)
        elif self.path == "/localapi/v0/status":
            self.reply(
                {
                    "BackendState": "Running" if self.server.running else "NeedsLogin",
                    "TailscaleIPs": ["100.100.1.2", "fd7a:115c:a1e0::1"],
                    "Self": {"DNSName": self.server.hostname + ".", "Online": True},
                    "CertDomains": (
                        [self.server.hostname] if self.server.certificates else []
                    ),
                    "Health": [],
                    "Peer": {
                        "node-key": {
                            "DNSName": "laptop.example.ts.net.",
                            "Online": True,
                            "TailscaleIPs": ["100.100.1.3"],
                            "Relay": "lhr",
                        }
                    },
                }
            )
        elif self.path == "/localapi/v0/serve-config":
            self.reply(self.server.config)
        else:
            self.reply({"error": "Unknown API"}, 404)

    def do_POST(self):
        if self.path != "/localapi/v0/serve-config":
            self.reply({"error": "Unknown API"}, 404)
        elif self.server.fail_updates:
            self.reply({"error": "Injected rejection"}, 500)
        elif self.headers["If-Match"] != f'"{self.server.etag}"':
            self.reply({"error": "Concurrent configuration change"}, 412)
        else:
            data = self.rfile.read(int(self.headers["Content-Length"]))
            self.server.config = json.loads(data)
            self.server.etag += 1
            self.reply(None)


class ControlIntegrationTests(unittest.TestCase):
    BROKER_SCRIPT = "tailscale_sidecar.py"

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.daemon = FakeDaemon(self.directory / "daemon.sock")
        self.thread = threading.Thread(target=self.daemon.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop_daemon)
        self.env = {
            **os.environ,
            "TS_SOCKET": str(self.directory / "daemon.sock"),
            "T3_SHARE_SOCKET_PATH": str(self.directory / "control.sock"),
            "T3_SHARE_STATE_PATH": str(self.directory / "routes.json"),
            "REMOTE_GID": str(os.getgid()),
            "PYTHONDONTWRITEBYTECODE": "1",
        }
        self.process = None
        self.addCleanup(self.stop_broker)
        self.start_broker()

    def stop_daemon(self):
        self.daemon.shutdown()
        self.daemon.server_close()
        self.thread.join(timeout=2)

    def start_broker(self):
        (self.directory / "control.sock").unlink(missing_ok=True)
        self.process = subprocess.Popen(
            [sys.executable, str(ROOT / self.BROKER_SCRIPT)],
            env=self.env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        for _ in range(100):
            if (self.directory / "control.sock").exists():
                self.cli("list")
                return
            if self.process.poll() is not None:
                self.fail("Broker exited during startup")
            time.sleep(0.02)
        self.fail("Broker socket did not become available")

    def stop_broker(self):
        if self.process is not None:
            self.process.terminate()
            self.process.wait(timeout=5)
            self.process = None

    def cli(self, *args, success=True, json_output=True):
        result = subprocess.run(
            [
                sys.executable,
                str(ROOT / "t3_share_cli.py"),
                *(["--json"] if json_output else []),
                *map(str, args),
            ],
            env=self.env,
            text=True,
            capture_output=True,
            timeout=10,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout) if json_output else result.stdout.strip()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def backend(self):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen(100)
        self.addCleanup(listener.close)
        return listener.getsockname()[1]

    def test_identity_uses_actual_name_and_socket_is_group_restricted(self):
        self.assertEqual(self.cli("hostname"), "t3-dev-2.example.ts.net")
        self.assertEqual(self.cli("ip"), ["100.100.1.2", "fd7a:115c:a1e0::1"])
        self.assertEqual(self.cli("peers")[0]["hostname"], "laptop.example.ts.net")
        self.assertEqual(
            stat.S_IMODE((self.directory / "control.sock").stat().st_mode), 0o660
        )

    def test_share_is_idempotent_persistent_and_remove_preserves_t3(self):
        port = self.backend()
        first = self.cli("share", port)
        self.assertEqual(first["url"], "https://t3-dev-2.example.ts.net:8443")
        self.assertEqual(self.cli("share", port), first)
        self.assertEqual(self.cli("url", port, json_output=False), first["url"])
        self.stop_broker()
        self.start_broker()
        self.assertEqual(self.cli("list")["routes"], [first])
        self.cli("remove", port)
        self.assertEqual(self.cli("list")["routes"], [])
        self.assertEqual(self.daemon.config["TCP"], {"443": {"HTTPS": True}})
        self.assertEqual(
            self.daemon.config["Web"][f"{self.daemon.hostname}:443"]["Handlers"]["/"],
            {"Proxy": "http://127.0.0.1:3773"},
        )
        self.assertFalse(self.daemon.config.get("AllowFunnel"))

    def test_tcp_forwarding_explicit_listener_and_conflicts(self):
        port = self.backend()
        route = self.cli("share", port, "--tcp", "--listen", 9443)
        self.assertEqual(route["url"], "tcp://t3-dev-2.example.ts.net:9443")
        self.assertEqual(
            self.daemon.config["TCP"]["9443"], {"TCPForward": f"127.0.0.1:{port}"}
        )
        self.cli("share", self.backend(), "--listen", 9443, success=False)
        self.cli("share", port, "--listen", 9444, success=False)

    def test_rejects_platform_ports_invalid_ports_and_closed_backends(self):
        for port in (22, 443, 3773, 8317, 41642, 0, 65536):
            with self.subTest(port=port):
                self.cli("share", port, success=False)
        port = self.backend()
        for listen in (443, 22, 3773, 0, 65536):
            self.cli("share", port, "--listen", listen, success=False)
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            closed_port = listener.getsockname()[1]
        self.cli("check", closed_port, success=False)
        self.cli("share", closed_port, success=False)
        self.assertEqual(self.cli("list")["routes"], [])

    def test_failed_update_rolls_back_persistent_state(self):
        port = self.backend()
        self.daemon.fail_updates = True
        self.cli("share", port, success=False)
        self.daemon.fail_updates = False
        self.assertEqual(json.loads((self.directory / "routes.json").read_text()), [])
        self.assertEqual(self.cli("list")["routes"], [])

    def test_concurrent_agents_get_distinct_listener_ports(self):
        ports = [self.backend() for _ in range(5)]
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
            routes = list(pool.map(lambda port: self.cli("share", port), ports))
        self.assertEqual(len({route["listen"] for route in routes}), len(ports))
        self.assertEqual(len(self.cli("list")["routes"]), len(ports))

    def test_reconciles_daemon_reset_and_hostname_change(self):
        port = self.backend()
        self.cli("share", port)
        self.daemon.hostname = "t3-dev-3.example.ts.net"
        self.daemon.config = None
        self.daemon.etag += 1
        self.assertEqual(
            self.cli("url", port),
            {
                "port": port,
                "listen": 8443,
                "protocol": "https",
                "url": "https://t3-dev-3.example.ts.net:8443",
            },
        )
        self.assertIn("t3-dev-3.example.ts.net:443", self.daemon.config["Web"])

    def test_missing_login_or_https_configuration_is_actionable(self):
        self.daemon.running = False
        self.assertEqual(self.cli("status")["state"], "NeedsLogin")
        self.assertIn("not ready", self.cli("list", success=False).stderr)
        self.daemon.running = True
        self.daemon.certificates = False
        self.assertIn(
            "Enable HTTPS", self.cli("share", self.backend(), success=False).stderr
        )

    def test_checks_ports_and_reports_local_diagnostic_failure(self):
        port = self.backend()
        self.assertIn(port, self.cli("ports"))
        self.assertTrue(self.cli("check", port)["reachable"])
        self.daemon.running = False
        self.cli("doctor", success=False)
        self.cli("reset", success=False)

    def test_malformed_and_oversized_requests_do_not_stop_broker(self):
        for data in (b"[]\n", b"{bad json}\n", b"x" * 9000 + b"\n"):
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(5)
                client.connect(self.env["T3_SHARE_SOCKET_PATH"])
                client.sendall(data)
                with client.makefile("rb") as handle:
                    response = json.loads(handle.readline())
                self.assertFalse(response["success"])
        self.assertEqual(self.cli("status")["state"], "Running")

    def test_numeric_shorthand_prints_url_and_supports_json(self):
        port = self.backend()
        self.assertEqual(
            self.cli(port, json_output=False), "https://t3-dev-2.example.ts.net:8443"
        )
        self.assertEqual(self.cli(port)["listen"], 8443)


if __name__ == "__main__":
    unittest.main()
