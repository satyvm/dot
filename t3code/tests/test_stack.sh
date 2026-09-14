#!/usr/bin/env bash
# Static validation of the T3 Code Compose stack. No Docker daemon required
# beyond `docker compose config`.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
compose="$repo_root/t3code/t3code_docker_compose.yaml"
pass_count=0
fail_count=0

pass() { pass_count=$((pass_count + 1)); printf 'ok %d - %s\n' "$((pass_count + fail_count))" "$1"; }
fail() { fail_count=$((fail_count + 1)); printf 'not ok %d - %s\n' "$((pass_count + fail_count))" "$1"; [[ -z "${2:-}" ]] || printf '%s\n' "$2" | sed 's/^/  # /'; }

check() { # label, pattern, file
  if grep -qF -e "$2" "$3"; then pass "$1"; else fail "$1" "missing: $2"; fi
}
refute() {
  if grep -qF -e "$2" "$3"; then fail "$1" "unexpected: $2"; else pass "$1"; fi
}

# --- ingress posture -------------------------------------------------------
refute "no Coolify domain is implied by a published HTTP port" '"3773:' "$compose"
refute "the T3 server port is never published to the host" '3773:3773' "$compose"
check   "the only published port is the Tailscale UDP endpoint" '41642:41642/udp' "$compose"
check   "t3code shares the Tailscale network namespace" 'network_mode: service:tailscale' "$compose"

# --- the DNS setting that keeps Compose service names resolvable -----------
check "tailnet DNS is not accepted inside the shared namespace" 'TS_ACCEPT_DNS: "false"' "$compose"

# --- node identity durability ---------------------------------------------
check "tailscale state is persisted"        'ts-state:/var/lib/tailscale' "$compose"
check "the node is tagged so its key never expires" '--advertise-tags=tag:t3' "$compose"
check "a distinct UDP port avoids host contention"  '--port=41642' "$compose"

# --- persistence contract --------------------------------------------------
check "T3 Code state has a durable volume"  't3-state:/home/ubuntu/.t3' "$compose"
check "the home directory has a durable volume" 't3-home:/home/ubuntu' "$compose"
check "the npm prefix is volume-backed for rebuild-free upgrades" 'npm-global:/home/ubuntu/.npm-global' "$compose"
check "the workspace is the only host bind" '/home/ubuntu/dev:/home/ubuntu/dev' "$compose"

# --- gateway containment ---------------------------------------------------
check  "the gateway is opt-in behind a profile" 'profiles: ["gateway"]' "$compose"
check  "the gateway root filesystem is read-only" 'read_only: true' "$compose"
check  "the gateway drops all capabilities" 'cap_drop: [ALL]' "$compose"
check  "the gateway cannot escalate privileges" 'no-new-privileges:true' "$compose"
check  "the gateway keeps its remote control panel disabled" 'disable-control-panel: true' "$compose"
check  "the gateway refuses remote management" 'allow-remote: false' "$compose"

# --- no Hermes remnants ----------------------------------------------------
refute "no Hermes WebUI service remains"  'hermes' "$compose"
refute "no port 8787 ingress remains"     '8787' "$compose"

# --- image ----------------------------------------------------------------
dockerfile="$repo_root/t3code/Dockerfile"
check "the image provides the build toolchain T3 Code compiles against" 'g++' "$dockerfile"
check "Node is new enough for T3 Code"   'node:22.19.0' "$dockerfile"
refute "the image no longer carries the Hermes runtime" 'hermes' "$dockerfile"

# --- compose is syntactically valid ---------------------------------------
if TS_AUTHKEY=x DEV_SSH_PUBLIC_KEY="ssh-ed25519 AAAA t" \
   CLIPROXY_CLIENT_KEY=a CLIPROXY_MANAGEMENT_KEY=b \
   docker compose --project-directory "$repo_root" -f "$compose" config >/dev/null 2>&1; then
  pass "docker compose config parses the stack"
else
  fail "docker compose config parses the stack"
fi

printf '\n%d passed, %d failed\n' "$pass_count" "$fail_count"
((fail_count == 0))
