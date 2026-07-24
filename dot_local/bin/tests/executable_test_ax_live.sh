#!/usr/bin/env bash
set -euo pipefail

if [[ "${AX_LIVE_SMOKE:-0}" != "1" ]]; then
  printf 'Live smoke test skipped. Run explicitly with AX_LIVE_SMOKE=1.\n'
  exit 77
fi

required_roles=(frontier balanced fast light)
catalog="$(ax models live)"
for role in "${required_roles[@]}"; do
  grep -Eq "^${role}[[:space:]]" <<<"$catalog" || {
    printf 'missing live proxy alias: %s\n' "$role" >&2
    exit 1
  }
done

integration_status="$(herdr integration status)"
for agent in claude pi opencode; do
  grep -Eq "^${agent}: current" <<<"$integration_status" || {
    printf 'missing or stale Herdr integration: %s\n' "$agent" >&2
    exit 1
  }
done

prompt="Reply with exactly AX_SMOKE_OK and no other text."
ax claude --print "$prompt"
ax pi --print --no-session --no-tools "$prompt"
ax opencode run "$prompt"
ax crush run --quiet "$prompt"

printf 'Live client calls and Herdr integration checks passed.\n'
printf 'Manual acceptance still required: restart Herdr and confirm Claude, Pi, and OpenCode resume their native sessions.\n'
