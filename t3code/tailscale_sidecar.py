#!/usr/bin/env python3
import asyncio
import concurrent.futures
import http.client
import json
import os
from pathlib import Path
import socket
import tempfile

SOCKET_PATH = os.environ.get("T3_SHARE_SOCKET_PATH", "/run/t3-share/control.sock")
TS_SOCKET = os.environ.get("TS_SOCKET", "/run/tailscale/tailscaled.sock")
STATE_PATH = Path(
    os.environ.get("T3_SHARE_STATE_PATH", "/var/lib/t3-share/routes.json")
)
RESERVED = {22, 443, 3773, 8317, 41642}


class LocalAPI(http.client.HTTPConnection):
    def __init__(self):
        super().__init__("local-tailscaled.sock", timeout=5)

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(TS_SOCKET)


def local_api(path, method="GET", data=None, headers=None):
    conn = LocalAPI()
    try:
        conn.request(
            method,
            "/localapi/v0/" + path,
            body=json.dumps(data) if data is not None else None,
            headers={"Content-Type": "application/json", **(headers or {})},
        )
        response = conn.getresponse()
        body = response.read(1048576)
        if response.status != 200:
            raise RuntimeError(f"Tailscale LocalAPI {response.status}: {body.decode()}")
        return json.loads(body) if body else None, response.getheader("ETag", "")
    finally:
        conn.close()


def port_number(value):
    if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= 65535:
        raise ValueError("Port must be an integer from 1 to 65535")
    return value


def check_port(port):
    port_number(port)
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=2):
            return {"port": port, "reachable": True}
    except OSError as error:
        return {"port": port, "reachable": False, "error": str(error)}


def listening_ports():
    ports = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(path, encoding="utf-8") as handle:
            for line in handle.readlines()[1:]:
                fields = line.split()
                if fields[3] == "0A":
                    ports.add(int(fields[1].split(":")[1], 16))
    return sorted(ports)


class Broker:
    def __init__(self):
        self.routes = (
            json.loads(STATE_PATH.read_text(encoding="utf-8"))
            if STATE_PATH.exists()
            else []
        )
        if not isinstance(self.routes, list):
            raise ValueError("Invalid saved route state")
        if len(self.routes) > 57:
            raise ValueError("At most 57 app routes may be registered")
        for route in self.routes:
            self.validate_route(route)
        if len({route["port"] for route in self.routes}) != len(self.routes):
            raise ValueError("Duplicate saved app ports")
        if len({route["listen"] for route in self.routes}) != len(self.routes):
            raise ValueError("Duplicate saved listener ports")

    @staticmethod
    def validate_route(route):
        for key in ("port", "listen"):
            port = port_number(route[key])
            if port in RESERVED or (key == "listen" and port < 1024):
                raise ValueError(f"{key} {port} is reserved for the platform")
        if route["protocol"] not in ("https", "tcp"):
            raise ValueError("Protocol must be https or tcp")

    @staticmethod
    def status():
        raw, _ = local_api("status")
        own = raw.get("Self") or {}
        return {
            "state": raw.get("BackendState"),
            "hostname": own.get("DNSName", "").rstrip("."),
            "ips": raw.get("TailscaleIPs") or [],
            "online": own.get("Online", False),
            "health": raw.get("Health") or [],
            "certificate_domains": raw.get("CertDomains") or [],
        }

    @staticmethod
    def hostname(status):
        name = status["hostname"]
        if status["state"] != "Running" or not name:
            raise RuntimeError("Tailscale is not ready; run t3-share status")
        if name not in status["certificate_domains"]:
            raise RuntimeError(
                "Enable HTTPS certificates in the tailnet to use T3 Serve"
            )
        return name

    def config(self, hostname):
        config = {
            "TCP": {"443": {"HTTPS": True}},
            "Web": {
                f"{hostname}:443": {
                    "Handlers": {"/": {"Proxy": "http://127.0.0.1:3773"}}
                }
            },
        }
        for route in self.routes:
            port, listen = route["port"], str(route["listen"])
            if route["protocol"] == "https":
                config["TCP"][listen] = {"HTTPS": True}
                config["Web"][f"{hostname}:{listen}"] = {
                    "Handlers": {"/": {"Proxy": f"http://127.0.0.1:{port}"}}
                }
            else:
                config["TCP"][listen] = {"TCPForward": f"127.0.0.1:{port}"}
        return config

    def reconcile(self):
        status = self.status()
        desired = self.config(self.hostname(status))
        current, etag = local_api("serve-config")
        if (current or {}) != desired:
            local_api("serve-config", "POST", desired, {"If-Match": etag})
        return status

    def save(self):
        STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=STATE_PATH.parent, delete=False
        ) as handle:
            temporary = Path(handle.name)
            try:
                json.dump(self.routes, handle)
                handle.flush()
                os.fsync(handle.fileno())
                os.replace(temporary, STATE_PATH)
            finally:
                temporary.unlink(missing_ok=True)

    def change(self, routes):
        if len(routes) > 57:
            raise ValueError("At most 57 app routes may be registered")
        previous = self.routes
        self.routes = routes
        try:
            self.save()
            return self.reconcile()
        except Exception:
            self.routes = previous
            self.save()
            try:
                self.reconcile()
            except (OSError, RuntimeError, http.client.HTTPException):
                pass
            raise

    @staticmethod
    def describe(route, hostname):
        return {**route, "url": f"{route['protocol']}://{hostname}:{route['listen']}"}

    def handle(self, action, payload):
        if action == "ports":
            return listening_ports()
        if action == "check":
            return check_port(payload.get("port"))
        if action == "status":
            return self.status()
        if action == "peers":
            raw, _ = local_api("status")
            return [
                {
                    "hostname": peer.get("DNSName", "").rstrip("."),
                    "ips": peer.get("TailscaleIPs") or [],
                    "online": peer.get("Online", False),
                    "relay": peer.get("Relay", ""),
                    "direct_address": peer.get("CurAddr", ""),
                }
                for peer in (raw.get("Peer") or {}).values()
            ]
        if action == "doctor":
            status = self.status()
            current, _ = local_api("serve-config")
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                apps = list(
                    pool.map(check_port, [route["port"] for route in self.routes])
                )
            return {
                "tailscale": status,
                "routes_applied": current == self.config(status["hostname"]),
                "t3_backend": check_port(3773),
                "apps": apps,
                "note": "Local checks cannot verify remote tailnet ACLs or browser connectivity.",
            }
        if action == "list":
            status = self.reconcile()
            return {
                "t3_url": f"https://{status['hostname']}",
                "routes": [
                    self.describe(route, status["hostname"]) for route in self.routes
                ],
            }
        if action == "share":
            port = port_number(payload.get("port"))
            existing = next(
                (route for route in self.routes if route["port"] == port), None
            )
            used = {route["listen"] for route in self.routes}
            listen = payload.get("listen")
            if listen is None:
                listen = (
                    existing["listen"]
                    if existing
                    else next(
                        (
                            candidate
                            for candidate in range(8443, 8500)
                            if candidate not in used
                        ),
                        None,
                    )
                )
            route = {
                "port": port,
                "listen": listen,
                "protocol": payload.get("protocol", "https"),
            }
            self.validate_route(route)
            if existing and existing != route:
                raise ValueError(
                    "App already shared with different settings; remove its route first"
                )
            if not existing and listen in used:
                raise ValueError("Listener port already in use")
            checked = check_port(port)
            if not checked["reachable"]:
                raise ValueError(f"App is not listening at 127.0.0.1:{port}")
            status = (
                self.reconcile() if existing else self.change([*self.routes, route])
            )
            return self.describe(route, status["hostname"])
        if action in ("remove", "url"):
            port = port_number(payload.get("port"))
            route = next(
                (route for route in self.routes if route["port"] == port), None
            )
            if not route:
                raise ValueError("No shared route for that app port")
            if action == "url":
                return self.describe(route, self.reconcile()["hostname"])
            self.change([item for item in self.routes if item != route])
            return {"removed": port}
        raise ValueError(f"Unknown command: {action}")


async def serve():
    broker = Broker()
    lock = asyncio.Lock()

    async def client(reader, writer):
        try:
            data = await asyncio.wait_for(reader.readuntil(b"\n"), timeout=5)
            request = json.loads(data)
            if not isinstance(request, dict) or not isinstance(
                request.get("payload", {}), dict
            ):
                raise ValueError("Expected a JSON object with an object payload")
            async with lock:
                result = await asyncio.to_thread(
                    broker.handle, request.get("action"), request.get("payload", {})
                )
            response = {"success": True, "data": result}
        except Exception as error:
            response = {"success": False, "error": str(error)}
        try:
            writer.write(json.dumps(response).encode() + b"\n")
            await asyncio.wait_for(writer.drain(), timeout=5)
        finally:
            writer.close()
            await writer.wait_closed()

    async def reconcile():
        while True:
            try:
                async with lock:
                    await asyncio.to_thread(broker.reconcile)
            except Exception as error:
                print(f"Tailscale route reconciliation: {error}", flush=True)
            await asyncio.sleep(5)

    path = Path(SOCKET_PATH)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.unlink(missing_ok=True)
    server = await asyncio.start_unix_server(client, path=SOCKET_PATH, limit=8192)
    os.chown(path, os.getuid(), int(os.environ.get("REMOTE_GID", "1000")))
    os.chmod(path, 0o660)
    async with server:
        await asyncio.gather(server.serve_forever(), reconcile())


if __name__ == "__main__":
    asyncio.run(serve())
