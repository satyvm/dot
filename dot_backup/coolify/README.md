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
   - Permissions: `repository` (read/write), `issue` (write), `pull_request` (write).
   - Copy the generated token string.

---

### Phase 2: Deploy in Coolify

1. **Create Docker Compose Application**:
   - In Coolify, create a new **Docker Compose** service connected to your Git repository (`satyvm/dot`).
   - Base Directory: `dot_backup/coolify`
   - Docker Compose File: `hermes_docker_compose.yaml`

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
   - Click **Deploy** in Coolify. The initial deployment clones dotfiles and initializes persistent volumes.

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
   SSH into the container and set up your CLIProxyAPI provider OAuth channels:
   ```bash
   ssh hermes-dev
   ax auth setup
   ```

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

5. **Local Stack Validation Script**:
   ```bash
   bash tests/test_stack.sh
   ```
