#!/usr/bin/env python3
import argparse
import json
import os
import socket
import sys


def request(action, payload):
    path = os.environ.get("T3_SHARE_SOCKET_PATH", "/run/t3-share/control.sock")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(30)
        client.connect(path)
        client.sendall(
            json.dumps({"action": action, "payload": payload}).encode() + b"\n"
        )
        with client.makefile("rb") as handle:
            response = json.loads(handle.readline(1048576))
    if not response.get("success"):
        raise RuntimeError(response.get("error", "Sidecar request failed"))
    return response["data"]


def main():
    parser = argparse.ArgumentParser(
        description="Discover and share T3 apps on the private tailnet"
    )
    parser.add_argument(
        "--json", action="store_true", help="Print machine-readable JSON"
    )
    commands = parser.add_subparsers(dest="command", required=True)
    for name, help_text in {
        "status": "Node identity, connection state, and health",
        "hostname": "Actual MagicDNS hostname",
        "ip": "Tailnet IP addresses",
        "list": "T3 URL and shared app routes",
        "ports": "Listening TCP ports in the shared network namespace",
        "peers": "Visible tailnet peers and direct/relay addresses",
        "doctor": "Check node, Serve configuration, and local app backends",
    }.items():
        commands.add_parser(name, help=help_text)
    for name in ("share", "remove", "url", "check"):
        sub = commands.add_parser(name)
        sub.add_argument("port", type=int, help="App's local TCP port")
        if name == "share":
            sub.add_argument(
                "--listen",
                type=int,
                help="Tailnet listener port (default: free port 8443–8499)",
            )
            sub.add_argument(
                "--tcp", action="store_true", help="Raw TCP forwarding instead of HTTPS"
            )
    arguments = sys.argv[1:]
    position = 1 if arguments and arguments[0] == "--json" else 0
    if len(arguments) > position and arguments[position].isdigit():
        arguments.insert(position, "share")
    args = parser.parse_args(arguments)
    action = "status" if args.command in ("hostname", "ip") else args.command
    payload = {"port": args.port} if hasattr(args, "port") else {}
    if args.command == "share":
        payload.update(listen=args.listen, protocol="tcp" if args.tcp else "https")
    try:
        result = request(action, payload)
        if args.command == "hostname":
            result = result["hostname"]
            if not result:
                raise RuntimeError("Tailscale hostname is not available yet")
        elif args.command == "ip":
            result = result["ips"]
        if args.json:
            print(json.dumps(result, indent=2))
        elif args.command in ("share", "url"):
            print(result["url"])
        elif isinstance(result, str):
            print(result)
        elif args.command in ("ip", "ports"):
            print("\n".join(str(item) for item in result))
        else:
            print(json.dumps(result, indent=2))
        if args.command == "check" and not result["reachable"]:
            return 1
        if args.command == "doctor":
            healthy = (
                result["tailscale"]["state"] == "Running"
                and not result["tailscale"]["health"]
                and result["routes_applied"]
                and result["t3_backend"]["reachable"]
                and all(app["reachable"] for app in result["apps"])
            )
            return 0 if healthy else 1
        return 0
    except (OSError, ValueError, RuntimeError) as error:
        print(f"t3-share: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
