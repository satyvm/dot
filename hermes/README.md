# Hermes Remote Development Platform on Coolify

Deployable Docker Compose application featuring Hermes WebUI, SSH container development, isolated CLIProxyAPI, and a Gitea `ai` forge API sidecar.

---

## Deployment & Configuration Guide

### Phase 1: Pre-Deployment Setup (Host & Local Machine)

1. **Prepare Host Workspace Directory**:
   On your host server, create `/home/ubuntu/dev` and verify ownership:
   ```bash
   sudo install -d -o ubuntu -g ubuntu -m 0755 /home/ubuntu/dev
   stat -c '%u:%g %n' /home/ubuntu/dev
   ```

2. **Generate Dedicated Container SSH Key (Local Machine)**:
   Generate a key pair on your local Mac/machine to access the container via SSH ProxyJump:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/hermes_dev_ed25519 -C "hermes-dev"
   cat ~/.ssh/hermes_dev_ed25519.pub
   ```

3. **Generate Gitea API Token**:
   Log into your self-hosted Gitea (`https://gitea.satyvm.com`) as user `ai`:
   - Navigate to **Settings -> Applications -> Generate New Token**.
   - Name: `tea-sidecar`
   - Permissions: `user` (read/write), `repository` (read/write), `issue` (write), `pull_request` (write).
   - Copy the generated token string.

---

### Phase 2: Deploy in Coolify

1. **Create Docker Compose Application**:
   - In Coolify, create a new **Docker Compose** service connected to your Git repository (`satyvm/dot`).
   - Base Directory: `/` (repository root)
   - Docker Compose File: `/hermes/hermes_docker_compose.yaml`
   - Keep the repository root as Coolify's project directory. Both image build contexts are intentionally repository-root-relative.
   - `/home/ubuntu/dev` is the only host bind. `/home/ubuntu` and all service state use Docker-managed named volumes; the Coolify host user's dotfiles are never mounted into the container.

2. **Set Environment Variables in Coolify**:
   Fill in the required runtime secrets (refer to `.env.example`):

   | Variable | Value / Example | Description |
   |---|---|---|
   | `REMOTE_UID` | `1000` | Host `ubuntu` UID (`id -u ubuntu`) |
   | `REMOTE_GID` | `1000` | Host `ubuntu` GID (`id -g ubuntu`) |
   | `DEV_SSH_PORT` | `22223` | Published host loopback SSH port |
   | `DEV_SSH_PUBLIC_KEY` | `ssh-ed25519 AAA... hermes-dev` | Public key contents from Step 2 |
   | `CLIPROXY_CLIENT_KEY` | `<long-random-string>` | Internal client token for CLIProxyAPI |
   | `CLIPROXY_MANAGEMENT_KEY` | `<long-random-string>` | Management key for CLIProxyAPI |
   | `HERMES_WEBUI_PASSWORD` | `<long-random-password>` | WebUI login password |
   | `GITEA_TOKEN` | `<gitea-ai-token>` | API token for `ai` Gitea user |
   | `GITEA_URL` | `https://gitea.satyvm.com` | Self-hosted Gitea base URL |

3. **Configure Ingress Domain**:
   - Assign your public domain (e.g., `https://hermes.yourdomain.com`) strictly to service `hermes-dev` port `8787`.
   - Do **not** assign any domain or external port to `cliproxyapi` or `tea-sidecar`.

4. **Deploy**:
   - Click **Deploy** in Coolify. The initial deployment initializes the Docker-managed home, runs the repository's noninteractive chezmoi profile with `aiMode=remote`, and applies the dotfiles as the container `ubuntu` user.
   - On every later restart, the entrypoint fast-forward pulls the existing checkout, regenerates the fixed `container` profile, and force-applies managed files without a TTY. Startup therefore cannot block on an interactive Chezmoi conflict.
   - Pi's mutable model catalog and settings are seeded with Chezmoi `create_` entries and remain runtime-owned after creation. Make durable changes to genuinely managed files in this repository; mutable runtime state and the named volumes remain persistent across restarts.

---

### Phase 3: Post-Deployment Configuration

1. **Configure Local SSH Config (`~/.ssh/config`)**:
   Add the following entry on your local machine:
   ```sshconfig
   Host coolify
       HostName your-server.example.com
       User ubuntu
       IdentityFile ~/.ssh/coolify_ed25519
       IdentitiesOnly yes
       ServerAliveInterval 30
       ServerAliveCountMax 3

   Host hermes-dev
       HostName 127.0.0.1
       Port 22223
       User ubuntu
       ProxyJump coolify
       IdentityFile ~/.ssh/hermes_dev_ed25519
       IdentitiesOnly yes
       ForwardAgent no
       ServerAliveInterval 30
       ServerAliveCountMax 3
   ```

2. **Register Container SSH Key with Gitea**:
   SSH into the container and output its auto-generated Gitea deploy key:
   ```bash
   ssh hermes-dev 'cat ~/.ssh/gitea_ai_ed25519.pub'
   ```
   Add this public key to `https://gitea.satyvm.com` under **User Settings -> SSH / GPG Keys** for user `ai`.

3. **Authenticate AI Model Providers**:
   Provider OAuth state belongs to the CLIProxyAPI sidecar. From the Docker host, run both login flows:
   ```bash
   proxy_id=$(docker ps -qf 'name=cliproxyapi-')
   docker exec -it "$proxy_id" \
     /CLIProxyAPI/CLIProxyAPI -config /config/config.yaml -no-browser -antigravity-login
   docker exec -it "$proxy_id" \
     /CLIProxyAPI/CLIProxyAPI -config /config/config.yaml -no-browser -codex-login
   ```
   If the browser callback cannot reach the container, paste the complete final localhost callback URL into the waiting command. Inside `hermes-dev`, `ax auth setup antigravity` or `ax auth setup codex` prints the corresponding Docker-host command.

---

### Phase 4: Verification & Usage

1. **Run Diagnostics**:
   ```bash
   ssh hermes-dev 'ax doctor'
   ```

2. **Verify Gitea Sidecar Socket**:
   ```bash
   ssh hermes-dev 'gitea-ai ping'
   ssh hermes-dev 'gitea-ai list-repos'
   ```

3. **Verify Git SSH Transport**:
   ```bash
   ssh hermes-dev 'ssh -T -p 22222 git@gitea.satyvm.com'
   ```

4. **Access Hermes WebUI**:
   Open `https://hermes.yourdomain.com` in your browser and log in with your `HERMES_WEBUI_PASSWORD`.

5. **Local Colima Build Test (from repository root)**:
   ```bash
   colima start
   docker context use colima
   docker buildx version

   export DEV_SSH_PUBLIC_KEY="$(cat ~/.ssh/hermes_dev_ed25519.pub)"
   export CLIPROXY_CLIENT_KEY="local-test-client-key"
   export CLIPROXY_MANAGEMENT_KEY="local-test-management-key"
   export HERMES_WEBUI_PASSWORD="local-test-webui-password"
   export GITEA_TOKEN=""
   export GITEA_URL="https://gitea.satyvm.com"
   export REMOTE_UID="$(id -u)"
   export REMOTE_GID="$(id -g)"

   docker compose \
     --project-directory . \
     -f hermes/hermes_docker_compose.yaml \
     config

   docker compose \
     --project-directory . \
     -f hermes/hermes_docker_compose.yaml \
     build --pull --progress=plain tea-sidecar hermes-dev
   ```

   Run these commands from the repository root, not from `hermes`.
   The explicit `--project-directory .` reproduces Coolify's path resolution.

6. **Static Validation**:
   ```bash
   bash hermes/tests/test_stack.sh
   bash dot_local/bin/tests/test_ax.sh
   ```
