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

# --- build context ---------------------------------------------------------
# Compose resolves a relative build context against the project directory, which
# under Coolify is the repository root rather than this folder. Every COPY source
# must therefore exist inside the declared context, or the build fails at solve
# time with "failed to compute cache key".
check "the image build context is the t3code directory" 'context: ./t3code' "$compose"
for df in "$repo_root"/t3code/Dockerfile*; do
  while read -r src; do
    label="$(basename "$df") copies $src from inside its build context"
    if [[ -e "$repo_root/t3code/$src" ]]; then pass "$label"; else fail "$label" "not found: t3code/$src"; fi
  done < <(awk '$1 == "COPY" && $2 !~ /^--/ { print $2 }' "$df")
done

# --- pinned images actually exist for arm64 --------------------------------
# Two deploys have now failed on a pin that resolved nowhere. Network-gated so
# the default offline run stays green: T3_CHECK_IMAGES=1 to enable.
if [[ "${T3_CHECK_IMAGES:-0}" == "1" ]]; then
  while read -r ref; do
    name="${ref%%@*}"; repo="${name%:*}"; tag="${name##*:}"
    [[ "$repo" == */* ]] || repo="library/$repo"
    archs=$(curl -sS --max-time 20 "https://hub.docker.com/v2/repositories/$repo/tags/$tag" \
      | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
print(" ".join(sorted({i["architecture"] for i in d.get("images",[]) if i.get("architecture")})))' 2>/dev/null)
    if [[ "$archs" == *arm64* ]]; then
      pass "$name resolves and ships arm64"
    else
      fail "$name resolves and ships arm64" "registry returned: ${archs:-<no such tag>}"
    fi
  done < <(awk '$1 == "image:" { print $2 }' "$compose")
else
  printf '# skipped image-registry checks (set T3_CHECK_IMAGES=1 to enable)\n'
fi

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
