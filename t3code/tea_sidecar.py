#!/usr/bin/env python3
import asyncio
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

SOCKET_PATH = os.environ.get("TEA_SOCKET_PATH", "/run/tea/tea.sock")
GITEA_URL = os.environ.get("GITEA_URL", "https://gitea.satyvm.com").rstrip("/")
SECRET_FILE = "/secrets/gitea-token"

def get_token():
    if os.path.isfile(SECRET_FILE):
        with open(SECRET_FILE, "r") as f:
            return f.read().strip()
    return os.environ.get("GITEA_TOKEN", "").strip()

def gitea_api_request(endpoint, method="GET", data=None):
    token = get_token()
    if not token:
        raise ValueError("Gitea API token is missing or empty")
    
    url = f"{GITEA_URL}/api/v1{endpoint}"
    headers = {
        "Authorization": f"token {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    
    body = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            resp_body = resp.read().decode("utf-8")
            return json.loads(resp_body) if resp_body else {}
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        raise RuntimeError(f"HTTP {e.code}: {err_body}")
    except Exception as e:
        raise RuntimeError(f"API request failed: {str(e)}")

def handle_action(action, payload):
    if action == "create_repo":
        name = payload.get("name")
        if not name or not isinstance(name, str):
            raise ValueError("Repository 'name' is required")
        
        # Enforce target owner = ai, public = true (private = false)
        req_data = {
            "name": name,
            "description": payload.get("description", "Created by AI Agent"),
            "private": False,
            "auto_init": payload.get("auto_init", True),
            "gitignores": payload.get("gitignores", ""),
            "license": payload.get("license", "MIT"),
            "readme": payload.get("readme", "Default"),
        }
        res = gitea_api_request("/user/repos", method="POST", data=req_data)
        return {
            "name": res.get("name"),
            "full_name": res.get("full_name"),
            "clone_url": f"git@gitea.satyvm.com:22222/{res.get('full_name', f'ai/{name}')}.git",
            "html_url": res.get("html_url"),
        }

    elif action == "list_repos":
        res = gitea_api_request("/user/repos?limit=50", method="GET")
        repos = []
        for r in res:
            if isinstance(r, dict):
                repos.append({
                    "name": r.get("name"),
                    "full_name": r.get("full_name"),
                    "ssh_url": f"git@gitea.satyvm.com:22222/{r.get('full_name')}.git",
                    "private": r.get("private"),
                })
        return repos

    elif action == "create_issue":
        repo = payload.get("repo")
        title = payload.get("title")
        if not repo or not title:
            raise ValueError("'repo' (e.g. ai/myrepo) and 'title' are required")
        if not repo.startswith("ai/"):
            raise ValueError("Operations are restricted to 'ai/*' repositories")
        
        owner, repo_name = repo.split("/", 1)
        req_data = {
            "title": title,
            "body": payload.get("body", ""),
        }
        res = gitea_api_request(f"/repos/{owner}/{repo_name}/issues", method="POST", data=req_data)
        return {"number": res.get("number"), "html_url": res.get("html_url")}

    elif action == "create_pr":
        repo = payload.get("repo")
        title = payload.get("title")
        head = payload.get("head")
        base = payload.get("base", "main")
        if not repo or not title or not head:
            raise ValueError("'repo', 'title', and 'head' branch are required")
        if not repo.startswith("ai/"):
            raise ValueError("Operations are restricted to 'ai/*' repositories")
        
        owner, repo_name = repo.split("/", 1)
        req_data = {
            "title": title,
            "body": payload.get("body", ""),
            "head": head,
            "base": base,
        }
        res = gitea_api_request(f"/repos/{owner}/{repo_name}/pulls", method="POST", data=req_data)
        return {"number": res.get("number"), "html_url": res.get("html_url")}

    elif action == "ping":
        return {"status": "ok", "gitea_url": GITEA_URL}

    else:
        raise ValueError(f"Unknown action: '{action}'")

async def handle_client(reader, writer):
    try:
        data = await reader.read(65536)
        if not data:
            writer.close()
            await writer.wait_closed()
            return
        
        try:
            req = json.loads(data.decode("utf-8"))
            action = req.get("action")
            payload = req.get("payload", {})
            result = handle_action(action, payload)
            response = {"success": True, "data": result}
        except Exception as e:
            response = {"success": False, "error": str(e)}
        
        writer.write(json.dumps(response).encode("utf-8") + b"\n")
        await writer.drain()
    except Exception:
        pass
    finally:
        writer.close()
        await writer.wait_closed()

async def main():
    if os.path.exists(SOCKET_PATH):
        try:
            os.unlink(SOCKET_PATH)
        except OSError:
            pass

    socket_dir = os.path.dirname(SOCKET_PATH)
    if socket_dir:
        os.makedirs(socket_dir, exist_ok=True)

    server = await asyncio.start_unix_server(handle_client, path=SOCKET_PATH)
    
    # Set socket permissions to 0666 so container users in mounted volume can connect
    os.chmod(SOCKET_PATH, 0o666)
    
    print(f"Tea sidecar running on Unix socket: {SOCKET_PATH}", flush=True)
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        pass
