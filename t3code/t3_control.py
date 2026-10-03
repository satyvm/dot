#!/usr/bin/env python3
"""Run the T3 platform's private networking and Gitea socket APIs."""

import argparse
import asyncio
import json
import os
import signal
import socket
import sys

import t3_share_cli
import tailscale_sidecar
import tea_sidecar


def healthcheck():
    # Reconciliation verifies that the private HTTPS route has been applied.
    t3_share_cli.request("list", {})
    path = os.environ.get("TEA_SOCKET_PATH", "/run/tea/tea.sock")
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(5)
        client.connect(path)
        client.sendall(b'{"action":"ping","payload":{}}\n')
        with client.makefile("rb") as handle:
            response = json.loads(handle.readline(65536))
    if not response.get("success") or response.get("data", {}).get("status") != "ok":
        raise RuntimeError("Gitea socket API did not respond to ping")


async def run_api(name, coroutine):
    await coroutine
    raise RuntimeError(f"{name} socket API stopped unexpectedly")


async def serve():
    loop = asyncio.get_running_loop()
    task = asyncio.current_task()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, task.cancel)
    try:
        # Failure in either API cancels the other and exits for Docker to restart.
        async with asyncio.TaskGroup() as group:
            group.create_task(run_api("Tailscale", tailscale_sidecar.serve()))
            group.create_task(run_api("Gitea", tea_sidecar.main()))
    except asyncio.CancelledError:
        pass
    finally:
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.remove_signal_handler(sig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--healthcheck", action="store_true")
    args = parser.parse_args()
    if args.healthcheck:
        try:
            healthcheck()
        except Exception as error:
            print(f"t3-control: {error}", file=sys.stderr)
            return 1
        return 0
    asyncio.run(serve())
    return 0


if __name__ == "__main__":
    sys.exit(main())
