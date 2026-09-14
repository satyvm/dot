# Manual Runbook — T3 Code + Tailscale Migration

Everything in this repository is code. Everything in this file is not: it is the
set of steps that need a human, a browser, a secret, or a decision.

Work top to bottom. Each phase has a **gate** — do not start the next phase
until the gate passes.

Legend: 🖥️ VPS host · 🐳 container · 💻 Mac · 🌐 browser

---

## Phase A — Tailscale on the VPS host (exit node)

> Goal: one tailnet node on the host, advertising an exit node, so your phone
> and Mac can route their internet traffic through it.

### A1 🌐 Prepare the tailnet

1. Sign in at `login.tailscale.com`.
2. **DNS → MagicDNS**: enable.
3. **DNS → HTTPS Certificates**: enable. *(The container's `tailscale serve`
   cannot issue a certificate without this.)*
4. **Access controls**: add a tag for the container node so its key never
   expires, and grant yourself the right to apply it:

   ```jsonc
   "tagOwners": {
     "tag:t3": ["autogroup:admin"]
   }
   ```

### A2 🖥️ Install and start

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

### A3 🖥️ Enable IP forwarding — **this is silently required**

Without it the exit node accepts traffic and drops it.

```bash
printf 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n' \
  | sudo tee /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
```

Throughput tuning (optional but recommended for an exit node):

```bash
NETDEV=$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")
sudo ethtool -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
```

### A4 🖥️ Advertise the exit node

```bash
sudo tailscale set --advertise-exit-node
```

### A5 🌐 Approve it

Tailscale admin console → **Machines** → the VPS → **Edit route settings** →
approve the exit node. Also **Disable key expiry** on this machine.

### A6 🖥️ Open UDP 41641 — in *both* places

Oracle Cloud has two independent firewalls and people routinely forget the second.

1. OCI console → VCN → Security List → **Ingress rule**: UDP, source
   `0.0.0.0/0`, destination port `41641`.
2. On the instance:

   ```bash
   sudo iptables -I INPUT 1 -p udp --dport 41641 -j ACCEPT
   sudo netfilter-persistent save
   ```

### A7 💻📱 Test from a real network

On the iPhone: Tailscale app → **Exit Node** → the VPS. Then, **on public
Wi-Fi, not your home network**:

```bash
tailscale status   # on the Mac, with the exit node selected
```

**Gate A:** the connection reads `direct`, not `relay`, and you can browse.

> ⚠️ **Live with this for a day before Phase B.** A datacenter IP attracts
> CAPTCHAs and soft blocks from Google, banks, and shopping sites. This is the
> single most likely reason to abandon the exit-node idea, and it is much
> cheaper to discover now than after the Proton work.

---

## Phase B — ProtonVPN behind the exit node (optional)

> Goal: your exit traffic leaves from a Proton IP, not Oracle's, which removes
> most of the CAPTCHA friction from Phase A.
>
> Skip this entirely if Gate A felt fine.

**Why this is needed at all:** iOS allows only one active VPN at a time, so you
cannot run Tailscale and ProtonVPN together on the iPhone. Chaining them on the
server is the documented way around it.

### B1 🛟 Set a dead-man switch first

This phase can lock you out of your own server. Do not skip this.

```bash
tmux new -s vpn
# inside tmux:
( sleep 600; sudo wg-quick down wg0 ) &
```

If anything goes wrong, wait ten minutes and the server heals itself.

### B2 🌐 Get a config

`account.protonvpn.com` → **Downloads → WireGuard configuration**. Choose a
server **near Mumbai**; pick a P2P server if you ever want NAT-PMP port
forwarding. Configs expire after one year — note the date somewhere.

### B3 🖥️ Install with a *separate* routing table

Edit the downloaded config before using it. In `[Interface]`, add:

```ini
Table = 51820
```

**This line is the whole trick.** Without it, `AllowedIPs = 0.0.0.0/0` installs
a default route that captures replies to inbound Coolify and SSH traffic, and
your server disappears.

```bash
sudo cp proton.conf /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf
sudo apt install -y wireguard
sudo wg-quick up wg0
```

### B4 🖥️ Policy-route only forwarded tailnet traffic

```bash
# Tailnet clients (100.64.0.0/10) exit via Proton.
sudo ip rule add from 100.64.0.0/10 lookup 51820 priority 5000

# Tailscale's own control and DERP traffic must NOT go through Proton,
# or the tunnel that carries your clients tries to ride inside itself.
sudo ip rule add fwmark 0x80000 lookup main priority 4000
```

Persist these (systemd unit, `/etc/networkd-dispatcher/`, or `PostUp` lines in
`wg0.conf`) once they are proven.

### B5 Test, in this order

```bash
# 1. The server can still be reached from outside — check from the Mac:
ssh <vps>                      # must still work
curl -I https://<one-of-your-coolify-sites>   # must still work

# 2. Tailnet still up:
sudo tailscale status

# 3. Exit traffic now leaves via Proton — from the iPhone with the exit node on:
#    visit an IP-echo site; it should show Proton, not Oracle.
```

**Gate B:** all three pass. Only then kill the dead-man switch (`tmux kill-session -t vpn`)
and make the rules persistent.

> If this turns into a weekend, Tailscale sells a Mullvad exit-node add-on
> (~$5/mo) that needs none of this routing surgery.

---

## Phase C — Deploy the T3 Code stack

### C1 🖥️ Prepare the workspace directory

```bash
sudo install -d -o ubuntu -g ubuntu -m 0755 /home/ubuntu/dev
id -u ubuntu; id -g ubuntu          # note these two numbers
stat -c '%u:%g %n' /home/ubuntu/dev
```

### C2 💻 Create a dedicated container SSH key

```bash
ssh-keygen -t ed25519 -f ~/.ssh/t3_dev_ed25519 -C t3-dev
cat ~/.ssh/t3_dev_ed25519.pub
```

Do **not** reuse your Coolify host key.

### C3 🌐 Create a Tailscale auth key

Admin console → **Settings → Keys → Generate auth key**:

- **Reusable**: yes *(so redeploys reuse the node)*
- **Ephemeral**: **no** *(ephemeral nodes vanish on restart)*
- **Pre-approved**: yes
- **Tags**: `tag:t3`

### C4 🌐 Create the GitHub fine-grained PAT

GitHub → **Settings → Developer settings → Personal access tokens → Fine-grained
tokens → Generate new token**:

| Field | Value |
|---|---|
| Repository access | **Only select repositories** — never "All" |
| Contents | Read and write |
| Pull requests | Read and write |
| Issues | Read and write |
| Metadata | Read |
| Administration / Actions / Secrets / Workflows / Webhooks / Members | **No access** |
| Expiration | 90 days |

This is the structural guarantee you asked for: a fine-grained token cannot
perform admin actions because the permission was never granted, not because
something declines it at runtime.

### C5 🌐 Create the Gitea token

`gitea.satyvm.com` as user `ai` → **Settings → Applications → Generate token**.
Scopes: `write:repository`, `write:issue`. **Not** `write:user`, and the `ai`
account must not be a site administrator or organisation owner.

### C6 🌐 Turn on branch protection — both forges

On every repository agents will touch, protect `main`: require a pull request,
block force-push, block deletion. This is the layer that still holds if a token
leaks.

### C7 🌐 Create the Coolify application

- Type: **Docker Compose**, from `satyvm/dot`
- Base directory: `/`
- Compose file: `/t3code/t3code_docker_compose.yaml`
- **Do not assign a domain.** The whole point is that there is no public ingress.

Environment variables (see `t3code/.env.example`):

| Variable | Value |
|---|---|
| `REMOTE_UID` / `REMOTE_GID` | the numbers from C1 |
| `DEV_SSH_PUBLIC_KEY` | the public key from C2 |
| `TS_AUTHKEY` | the auth key from C3 |
| `GITEA_TOKEN` / `GITEA_URL` | from C5 |
| `CLIPROXY_CLIENT_KEY` / `CLIPROXY_MANAGEMENT_KEY` | two *different* long random strings, only if using the gateway |

### C8 Deploy

First boot is slow: it clones the dotfiles and runs a full `chezmoi apply`.

**Gate C:**

```bash
sudo tailscale status | grep t3-dev        # 🖥️ the node registered
ssh ubuntu@t3-dev                          # 💻 SSH over the tailnet
```

---

## Phase D — First-run setup inside the container

All 🐳, over `ssh ubuntu@t3-dev`.

### D1 Authenticate the agents

These are the **real** CLIs with their own auth — there is no wrapper:

```bash
claude          # follow its login flow
codex login
```

Both need a headless/device-code flow. If a browser callback cannot reach the
container, use the paste-back option each CLI offers.

### D2 Register the SSH keys with the forges

```bash
cat ~/.ssh/github_ai_ed25519.pub    # → GitHub → Settings → SSH keys
cat ~/.ssh/gitea_ai_ed25519.pub     # → Gitea → Settings → SSH keys (user ai)

ssh -T git@github.com
ssh -T -p 22222 git@gitea.satyvm.com
```

### D3 Authenticate `gh`

```bash
gh auth login --with-token < /dev/stdin   # paste the C4 token
gh auth status
```

### D4 Register projects — **CLI only**

The GUI cannot add projects to a remote environment.

```bash
t3 project add /home/ubuntu/dev/<repo>
t3 project list
```

*(The entrypoint auto-registers existing top-level directories; this is for new ones.)*

### D5 Verify

```bash
ax doctor
gitea-ai ping
```

`ax doctor` reporting `gateway: disabled` is correct if you have not enabled the
gateway profile.

---

## Phase E — Connect your clients

### E1 💻 Desktop app

T3 Code desktop → **Settings → Connections**. Use the tailnet HTTPS address that
`tailscale serve status` prints inside the container, or pair from a link:

```bash
ssh ubuntu@t3-dev 't3 pair'
```

### E2 📱 Phone

Same `t3 pair` output — scan the QR with the Tailscale VPN active.

> Treat pairing URLs like passwords. They are valid until they expire or you
> revoke them, and anyone holding one can try to pair.

### E3 💻 VS Code

`~/.ssh/config` on the Mac — note there is **no ProxyJump and no port**, because
the container is a tailnet node in its own right:

```sshconfig
Host t3-dev
    HostName t3-dev.<your-tailnet>.ts.net
    User ubuntu
    IdentityFile ~/.ssh/t3_dev_ed25519
    IdentitiesOnly yes
    ServerAliveInterval 30
```

Then: Remote-SSH → Connect to Host → `t3-dev` → open `/home/ubuntu/dev/<repo>`.

---

## Phase F — Optional: the model gateway

Only needed if you want `ax` to route through CLIProxyAPI instead of each
agent's own subscription.

```bash
# 🖥️
docker compose --profile gateway up -d

# 🐳 or 🖥️ — log a provider in; auth lives in a volume, so no rebuild
docker exec -it $(docker ps -qf name=cliproxyapi) /CLIProxyAPI/CLIProxyAPI \
  -config /config/config.yaml -no-browser -antigravity-login
```

> **Use a burner Google account for Antigravity.** Driving subscription OAuth
> through a third-party proxy is against provider terms and subscription bans
> are documented. Keep it away from the account your real subscriptions live on.

---

## Phase G — Decommission

Only after a week of the new stack working.

```bash
# 🖥️
docker compose -f <old-hermes-compose> down
docker volume rm remote-home hermes-state cliproxy-auth cliproxy-config \
  platform-secrets ssh-host-keys tea-socket     # ⚠️ check each first
sudo systemctl disable --now wg-quick@wg0       # the OLD wireguard, not Proton's
sudo systemctl disable --now cloudflared
```

Delete the Hermes application in Coolify. Revoke the old T3 Connect relay.

---

## Recurring maintenance

| When | What |
|---|---|
| Every ~30 days | T3 pairing expires. `ssh ubuntu@t3-dev 't3 pair'` and re-pair. Not a lockout — SSH always gets you back in. |
| Every 90 days | GitHub PAT expires. Regenerate at C4, re-run D3. |
| Yearly | Proton WireGuard config expires. Redo B2. |
| On dotfile changes | `ssh ubuntu@t3-dev 'chezmoi update'` |

## If you are locked out of T3 Code

Four independent ways back in, in order of preference:

1. `ssh ubuntu@t3-dev` over the tailnet → `t3 pair`
2. Tailscale SSH, if sshd itself is broken
3. `docker exec -it <t3code> bash` from the VPS host
4. Coolify's own terminal

The tailnet node is tagged `tag:t3`, so its key never expires, and `ts-state`
is a volume, so redeploys keep its identity. Path 1 should always work.
