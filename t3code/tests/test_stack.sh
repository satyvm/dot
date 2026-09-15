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

# --- resource limits fit the host -----------------------------------------
# Docker refuses to create a container whose cpus limit exceeds the host core
# count; the Ampere A1 running Coolify has 2. Resolve the rendered config and
# check every limit, so a future bump cannot silently exceed the box again.
host_cpus=2
while read -r svc cpus; do
  if awk -v c="$cpus" -v h="$host_cpus" 'BEGIN{exit !(c<=h)}'; then
    pass "$svc cpus limit ($cpus) fits a ${host_cpus}-core host"
  else
    fail "$svc cpus limit ($cpus) fits a ${host_cpus}-core host" "docker will refuse to create it"
  fi
done < <(TS_AUTHKEY=x DEV_SSH_PUBLIC_KEY="ssh-ed25519 AAAA t" \
         CLIPROXY_CLIENT_KEY=x CLIPROXY_MANAGEMENT_KEY=x \
           docker compose -f "$compose" --profile gateway config 2>/dev/null \
         | awk '/^  [a-z][a-z0-9-]*:$/{svc=$1; sub(":","",svc)} /cpus:/{gsub(/[",]/,"",$2); print svc, $2}')
check "the workspace limits can be raised without editing the file" 'T3CODE_CPUS' "$compose"

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

# --- the entrypoint can never withhold the shell ---------------------------
# This container is the only way into the machine, so a failed bootstrap step
# must degrade the environment rather than stop supervisord from starting.
entrypoint="$repo_root/t3code/entrypoint.sh"

if bash -n "$entrypoint" 2>/dev/null; then pass "the entrypoint parses"; else fail "the entrypoint parses"; fi
check "every bootstrap step runs through attempt" 'attempt "bootstrap dotfiles" bootstrap_dotfiles' "$entrypoint"
check "the entrypoint always reaches supervisord" 'exec /usr/bin/supervisord' "$entrypoint"
check "failures are recorded where they can be read later" 'bootstrap-failures.log' "$entrypoint"
refute "no bootstrap step aborts the entrypoint outright" 'exit 1' "$entrypoint"

# Every attempt target must name a function that exists.
while read -r fn; do
  if grep -qE "^${fn}\(\) \{" "$entrypoint"; then
    pass "attempt target $fn is defined"
  else
    fail "attempt target $fn is defined" "no such function"
  fi
done < <(grep -oE '^  attempt "[^"]+" [a-z_]+' "$entrypoint" | awk '{print $NF}')

# Bash disables errexit for the whole duration of a call made in a condition
# context, and subshells inherit that suppression. A step function that relies
# on `set -e` alone would run past its own failure and be reported as passing,
# so each must propagate explicitly. Verify against the real `attempt`.
probe="$(mktemp "${TMPDIR:-/tmp}/t3-attempt.XXXXXX")"
{
  printf 'set -euo pipefail\n'
  sed -n '/^failed_steps=()/,/^}/p' "$entrypoint"
  printf 'log() { :; }\n'
  printf 'good() { true; }\n'
  printf 'bad_propagating() { false || return 1; echo RAN_ON; }\n'
  printf 'attempt ok good\n'
  printf 'attempt broken bad_propagating\n'
  printf 'printf "reached_end:%%s\\n" "${#failed_steps[@]}"\n'
} >"$probe"
probe_out="$(bash "$probe" 2>&1)"
rm -f "$probe"
if [[ "$probe_out" == *"reached_end:1"* && "$probe_out" != *RAN_ON* ]]; then
  pass "attempt records a failed step and still reaches the end"
else
  fail "attempt records a failed step and still reaches the end" "got: $probe_out"
fi

# --- the image provides what the t3 preset assumes -------------------------
# `t3` is image-provisioned, so chezmoi never runs install-developer-tools.sh.
# Anything the preset's ai feature needs must be baked into the image, or
# sync-nono-packs.sh aborts chezmoi apply on first boot.
for tool in nono herdr opencode uv; do
  check "the image brew-installs $tool for the ai feature" "$tool" "$dockerfile"
done
check "the image installs Claude Code, which has no Linux formula" '@anthropic-ai/claude-code' "$dockerfile"
check "the image installs Codex, which has no Homebrew formula at all" '@openai/codex' "$dockerfile"
# Homebrew's pi-coding-agent depends on `node`, which would duplicate the
# runtime this image is built on. npm reuses it.
check "Pi comes from npm, not the node-duplicating formula" '@earendil-works/pi-coding-agent' "$dockerfile"
refute "the node-duplicating Pi formula is not brew-installed" 'brew install nono herdr opencode pi-coding-agent' "$dockerfile"
check "the image fails the build if a required agent is missing" 'required tools missing' "$dockerfile"
check "the entrypoint reconciles npm agents past the home volume" 'ensure_npm_agents' "$entrypoint"

# ax is deployed by chezmoi to ~/.local/bin, and T3 Code spawns provider CLIs
# off the PATH it inherits from supervisord. If that directory is missing from
# either PATH, ax is unreachable from a T3 Code session.
check "the image PATH includes the chezmoi-managed bin directory" 'PATH=/home/ubuntu/.local/bin:' "$dockerfile"
check "t3 serve inherits the chezmoi-managed bin directory" 'PATH="/home/ubuntu/.local/bin:' "$repo_root/t3code/supervisord.conf"

# sshd does not inherit the image environment and the managed .zshrc only runs
# for interactive shells, so without SetEnv an `ssh t3-dev <cmd>` finds nothing
# and even an interactive login misses the npm-installed agents.
check "sshd sessions get the full PATH" 'SetEnv PATH=/home/ubuntu/.local/bin:/home/ubuntu/.npm-global/bin:' "$dockerfile"

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
  done < <( { awk '$1 == "image:" { print $2 }' "$compose"
              awk 'toupper($1) == "FROM" { print $2 }' "$repo_root"/t3code/Dockerfile*; } | sort -u)
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
