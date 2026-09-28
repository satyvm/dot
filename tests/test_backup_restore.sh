#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/home/Downloads" "$test_root/backup/Downloads" \
  "$test_root/backup/Documents" "$test_root/backup/t3" \
  "$test_root/backup/apps/preferences"
printf 'local\n' > "$test_root/home/Downloads/existing.txt"
printf 'backup\n' > "$test_root/backup/Downloads/existing.txt"
printf 'new download\n' > "$test_root/backup/Downloads/new.txt"
printf 'document\n' > "$test_root/backup/Documents/report.txt"
printf 't3 data\n' > "$test_root/backup/t3/settings.json"
printf 'complete\n' > "$test_root/backup/BACKUP_COMPLETE"

HOME="$test_root/home" bash "$repo_root/backup/scripts/executable_restore-local.sh" \
  "$test_root/backup" > "$test_root/output"

[[ "$(< "$test_root/home/Downloads/existing.txt")" == local ]]
[[ "$(< "$test_root/home/Downloads/new.txt")" == 'new download' ]]
[[ "$(< "$test_root/home/Documents/report.txt")" == document ]]
[[ "$(< "$test_root/home/.t3/settings.json")" == 't3 data' ]]
rg -q 'Existing files differ' "$test_root/output"
[[ ! -e "$test_root/home/.gemini" ]]

mkdir -p "$test_root/legacy/local" "$test_root/legacy/common/.t3" "$test_root/home2"
printf 'legacy t3\n' > "$test_root/legacy/common/.t3/session.json"
HOME="$test_root/home2" bash "$repo_root/backup/scripts/executable_restore-local.sh" \
  "$test_root/legacy/local" > "$test_root/legacy-output" 2>&1
[[ "$(< "$test_root/home2/.t3/session.json")" == 'legacy t3' ]]
rg -q 'Using legacy T3 Code backup' "$test_root/legacy-output"
printf 'Restore merge, conflict reporting, and T3 recovery passed.\n'
