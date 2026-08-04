#!/usr/bin/env python3
import json
import os
import socket
import sys

SOCKET_PATH = os.environ.get("TEA_SOCKET_PATH", "/run/tea/tea.sock")

def send_request(action, payload=None):
    if not os.path.exists(SOCKET_PATH):
        print(f"Error: Tea sidecar socket not found at {SOCKET_PATH}", file=sys.stderr)
        sys.exit(1)
        
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(SOCKET_PATH)
        req = json.dumps({"action": action, "payload": payload or {}})
        s.sendall(req.encode("utf-8"))
        s.shutdown(socket.SHUT_WR)
        
        chunks = []
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
        
        res_data = b"".join(chunks).decode("utf-8")
        res = json.loads(res_data)
        if not res.get("success"):
            print(f"Error from Tea sidecar: {res.get('error')}", file=sys.stderr)
            sys.exit(1)
        return res.get("data")
    except Exception as e:
        print(f"Connection error to Tea socket: {str(e)}", file=sys.stderr)
        sys.exit(1)
    finally:
        s.close()

def main():
    if len(sys.argv) < 2:
        print("Usage: gitea-ai <command> [args...]\n")
        print("Commands:")
        print("  ping                            Test connection to sidecar")
        print("  create-repo <name> [desc]       Create a public repository under 'ai'")
        print("  list-repos                      List repositories under 'ai'")
        print("  create-issue <repo> <title> [body]")
        print("  create-pr <repo> <title> <head> [base] [body]")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "ping":
        res = send_request("ping")
        print(json.dumps(res, indent=2))

    elif cmd == "create-repo":
        if len(sys.argv) < 3:
            print("Usage: gitea-ai create-repo <name> [description]")
            sys.exit(1)
        name = sys.argv[2]
        desc = sys.argv[3] if len(sys.argv) > 3 else "Created by AI Agent"
        res = send_request("create_repo", {"name": name, "description": desc})
        print(json.dumps(res, indent=2))

    elif cmd == "list-repos":
        res = send_request("list_repos")
        print(json.dumps(res, indent=2))

    elif cmd == "create-issue":
        if len(sys.argv) < 4:
            print("Usage: gitea-ai create-issue <repo> <title> [body]")
            sys.exit(1)
        repo = sys.argv[2]
        title = sys.argv[3]
        body = sys.argv[4] if len(sys.argv) > 4 else ""
        res = send_request("create_issue", {"repo": repo, "title": title, "body": body})
        print(json.dumps(res, indent=2))

    elif cmd == "create-pr":
        if len(sys.argv) < 5:
            print("Usage: gitea-ai create-pr <repo> <title> <head> [base] [body]")
            sys.exit(1)
        repo = sys.argv[2]
        title = sys.argv[3]
        head = sys.argv[4]
        base = sys.argv[5] if len(sys.argv) > 5 else "main"
        body = sys.argv[6] if len(sys.argv) > 6 else ""
        res = send_request("create_pr", {"repo": repo, "title": title, "head": head, "base": base, "body": body})
        print(json.dumps(res, indent=2))

    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
