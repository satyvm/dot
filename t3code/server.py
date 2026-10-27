#!/usr/bin/python3

import argparse
from dataclasses import dataclass
import os
import signal
import subprocess
import sys
import threading
import time


@dataclass
class Settings:
    url: str = "http://127.0.0.1:3773/"
    interval: float = 30
    startup_grace: float = 180
    failure_limit: int = 3
    max_restarts: int = 3
    retry_delay: float = 5
    stop_timeout: float = 20
    probe_timeout: float = 5


def log(message):
    print(f"t3code-server: {message}", flush=True)


def healthy(url, timeout):
    try:
        result = subprocess.run(
            ["curl", "--silent", "--show-error", "--noproxy", "*",
             "--connect-timeout", str(timeout), "--max-time", str(timeout),
             "--output", "/dev/null", "--write-out", "%{http_code}", url],
            capture_output=True, text=True, timeout=timeout + 1,
        )
        return result.returncode == 0 and result.stdout == "200"
    except (OSError, subprocess.TimeoutExpired):
        return False


def stop_process(process, timeout):
    deadline = time.monotonic() + timeout
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    while time.monotonic() < deadline:
        process.poll()
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            process.wait(timeout=5)
            return
        time.sleep(min(0.05, max(0, deadline - time.monotonic())))
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait(timeout=5)


def run(command, settings):
    stopping = threading.Event()
    previous = {}
    for sig in (signal.SIGTERM, signal.SIGINT):
        previous[sig] = signal.signal(sig, lambda *_args: stopping.set())
    process = None
    restarts = 0
    try:
        while not stopping.is_set():
            try:
                process = subprocess.Popen(command, start_new_session=True)
            except OSError as error:
                log(f"cannot start T3: {error}; manual restart required")
                return 78
            log(f"started T3 pid {process.pid}")
            started = time.monotonic()
            ready = False
            failures = 0
            while not stopping.is_set():
                status = process.poll()
                if status is not None:
                    reason = f"T3 exited with status {status}"
                    break
                if healthy(settings.url, settings.probe_timeout):
                    failures = 0
                    if not ready:
                        log("HTTP ready")
                    ready = True
                elif ready or time.monotonic() - started >= settings.startup_grace:
                    failures += 1
                    log(f"HTTP check failed ({failures}/{settings.failure_limit})")
                    if failures >= settings.failure_limit:
                        reason = "T3 failed consecutive HTTP checks"
                        break
                stopping.wait(settings.interval)
            try:
                stop_process(process, settings.stop_timeout)
            except subprocess.TimeoutExpired:
                log("T3 could not be stopped; refusing to start a duplicate")
                return 78
            process = None
            if stopping.is_set():
                return 0
            if restarts >= settings.max_restarts:
                log(f"{reason}; restart budget exhausted; manual restart required")
                return 78
            restarts += 1
            log(f"{reason}; restarting T3 ({restarts}/{settings.max_restarts})")
            stopping.wait(settings.retry_delay)
        return 0
    finally:
        if process is not None:
            try:
                stop_process(process, settings.stop_timeout)
            except subprocess.TimeoutExpired:
                log("T3 process remains unresponsive to SIGKILL")
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def main():
    parser = argparse.ArgumentParser(description="Run T3 with bounded HTTP recovery")
    parser.add_argument("--healthcheck", action="store_true")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    settings = Settings()
    if args.healthcheck:
        if healthy(settings.url, settings.probe_timeout):
            return 0
        print("t3code-server: local HTTP response check failed", file=sys.stderr)
        return 1
    if not args.command:
        parser.error("a T3 server command is required")
    return run(args.command, settings)


if __name__ == "__main__":
    sys.exit(main())
