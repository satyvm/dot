#!/usr/bin/env bash
# Fast local iteration on the T3 Code container.
#
# Two things make a naive loop slow: emulating arm64 on an x86 workstation
# (measured ~4.5x on CPU-bound work) and re-provisioning a cold Homebrew prefix
# on every run. Provisioning logic — chezmoi templates, shell scripts, package
# resolution — is architecture-independent, so iterate natively and keep the
# prefix warm. Verify on arm64 only before pushing.
#
#   ./dev-loop.sh build            rebuild the native dev image
#   ./dev-loop.sh warm             first boot, cold volumes (slow, once)
#   ./dev-loop.sh run              boot against the warm volumes (fast)
#   ./dev-loop.sh reprovision      re-run provisioning only, warm prefix
#   ./dev-loop.sh shell            interactive shell in the running container
#   ./dev-loop.sh verify-arm64     full cold arm64 run, for release
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
name=t3code-dev
image=t3code:amd64-dev
platform=linux/amd64
fixture=/tmp/t3code-dev-fixture

# The container clones committed history, never the working tree, so an
# uncommitted change is invisible to it. Fail loudly rather than test stale code.
require_committed() {
  if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
    printf 'dev-loop: uncommitted changes — the container clones committed history only.\n' >&2
    git -C "$repo_root" status --short >&2
    exit 1
  fi
}

prepare_fixture() {
  mkdir -p "$fixture/dev/sample"
  [[ -f "$fixture/dev/sample/README.md" ]] || echo '# sample' >"$fixture/dev/sample/README.md"
  [[ -f "$fixture/key" ]] || ssh-keygen -q -t ed25519 -f "$fixture/key" -N "" -C t3code-dev
}

start() {
  prepare_fixture
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker run -d --name "$name" --platform "$platform" \
    -e DEV_SSH_PUBLIC_KEY="$(cat "$fixture/key.pub")" \
    -e REMOTE_DOTFILES_REPO=/srv/dotfiles \
    -v "$repo_root:/srv/dotfiles:ro" \
    -v "$fixture/dev:/home/ubuntu/dev" \
    -v t3dev-home:/home/ubuntu \
    -v t3dev-brew:/home/linuxbrew \
    -v t3dev-npm:/home/ubuntu/.npm-global \
    -v t3dev-state:/home/ubuntu/.t3 \
    "$image" >/dev/null
}

follow_until() {
  local pattern="$1" limit="${2:-600}" waited=0
  while ((waited < limit)); do
    if docker logs "$name" 2>&1 | grep -qE "$pattern"; then return 0; fi
    [[ "$(docker inspect -f '{{.State.Status}}' "$name")" == running ]] || return 1
    sleep 5; waited=$((waited + 5))
  done
  return 1
}

case "${1:-run}" in
  build)
    docker buildx build --platform "$platform" \
      --build-arg REMOTE_UID=1000 --build-arg REMOTE_GID=1000 \
      --tag "$image" --load -f "$repo_root/t3code/Dockerfile" "$repo_root/t3code"
    ;;
  warm)
    require_committed
    docker volume rm t3dev-home t3dev-brew t3dev-npm t3dev-state >/dev/null 2>&1 || true
    start
    printf 'dev-loop: cold provisioning; this is the slow one.\n'
    follow_until 'provisioning complete|PROVISIONING INCOMPLETE' 3600 || true
    docker logs "$name" 2>&1 | grep -E 'boot complete|provisioning complete|PROVISIONING INCOMPLETE|t3code:   -'
    ;;
  run)
    require_committed
    start
    follow_until 'boot complete|BOOT INCOMPLETE' 120 || true
    docker logs "$name" 2>&1 | grep -E 'boot complete|BOOT INCOMPLETE|t3code:   -'
    ;;
  reprovision)
    require_committed
    docker exec "$name" /usr/local/bin/t3code-entrypoint provision
    ;;
  shell)
    docker exec -it -u ubuntu -e HOME=/home/ubuntu "$name" /bin/zsh -l
    ;;
  verify-arm64)
    require_committed
    docker buildx build --platform linux/arm64 \
      --build-arg REMOTE_UID=1001 --build-arg REMOTE_GID=1001 \
      --tag t3code:arm64-verify --load -f "$repo_root/t3code/Dockerfile" "$repo_root/t3code"
    printf 'dev-loop: built arm64. Run a cold container against it before release.\n'
    ;;
  *)
    printf 'usage: dev-loop.sh {build|warm|run|reprovision|shell|verify-arm64}\n' >&2
    exit 64
    ;;
esac
