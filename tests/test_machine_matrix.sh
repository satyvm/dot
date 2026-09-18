#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-matrix.XXXXXX")"
host_cache="$fixture_root/chezmoi-cache"
trap 'rm -rf "$fixture_root"' EXIT
export MISE_CACHE_DIR="$fixture_root/mise-cache"
export MISE_STATE_DIR="$fixture_root/mise-state"
export MISE_DATA_DIR="$fixture_root/mise-data"
mkdir -p "$MISE_CACHE_DIR" "$MISE_STATE_DIR" "$MISE_DATA_DIR"

pass_count=0
fail_count=0

pass() {
  pass_count=$((pass_count + 1))
  printf 'ok %d - %s\n' "$((pass_count + fail_count))" "$1"
}

fail() {
  fail_count=$((fail_count + 1))
  printf 'not ok %d - %s\n' "$((pass_count + fail_count))" "$1"
  [[ -z "${2:-}" ]] || printf '%s\n' "$2" | sed 's/^/  # /'
}

assert_has() {
  local content="$1" pattern="$2" label="$3"
  if grep -qxF "$pattern" <<<"$content"; then
    pass "$label"
  else
    fail "$label" "missing exact managed path: $pattern"
  fi
}

assert_lacks() {
  local content="$1" pattern="$2" label="$3"
  if grep -qxF "$pattern" <<<"$content"; then
    fail "$label" "unexpected managed path: $pattern"
  else
    pass "$label"
  fi
}

make_config() {
  local path="$1" preset="$2" os="$3" arch="$4"
  local distro prefix
  if [[ "$os" == "darwin" ]]; then
    distro="macos"
    if [[ "$arch" == "arm64" ]]; then
      prefix="/opt/homebrew"
    else
      prefix="/usr/local"
    fi
  else
    distro="debian"
    prefix="/home/linuxbrew/.linuxbrew"
  fi
  jq -n \
    --arg preset "$preset" \
    --arg os "$os" \
    --arg arch "$arch" \
    --arg distro "$distro" \
    --arg prefix "$prefix" \
    --arg dev_root "$fixture_root/home/dev" \
    '{
      data: {
        machine: {
          schemaVersion: 1,
          preset: $preset,
          os: $os,
          arch: $arch,
          distro: $distro,
          homebrewPrefix: $prefix,
          devRoot: $dev_root,
          customize: false,
          overrides: {}
        },
        name: "Matrix Test",
        email: "matrix@example.com"
      }
    }' >"$path"
}

render_managed() {
  local config="$1" destination="$2"
  mkdir -p "$destination"
  HOME="$destination" chezmoi managed \
    --config "$config" \
    --config-format json \
    --source "$repo_root" \
    --destination "$destination" \
    --cache "$host_cache" \
    --exclude=externals \
    --refresh-externals=never
}

render_template() {
  local config="$1" template="$2"
  chezmoi execute-template \
    --config "$config" \
    --config-format json \
    --source "$repo_root" \
    <"$repo_root/$template"
}

printf 'TAP version 13\n'

for os in darwin linux; do
  for arch in amd64 arm64; do
    for preset in minimal workstation server container t3; do
      case_name="${os}-${arch}-${preset}"
      config="$fixture_root/${case_name}.json"
      destination="$fixture_root/${case_name}-home"
      make_config "$config" "$preset" "$os" "$arch"
      managed="$(render_managed "$config" "$destination")"

      assert_lacks "$managed" "backup/scripts/backup-local.sh" "$case_name excludes repository-only backup scripts"
      assert_lacks "$managed" "t3code/t3code_docker_compose.yaml" "$case_name excludes the repository-only T3 Code platform"

      if [[ "$preset" == "container" ]]; then
        assert_lacks "$managed" "install-homebrew-packages.sh" "$case_name skips host Brew packages"
        assert_lacks "$managed" "install-system-packages.sh" "$case_name skips system packages"
        assert_lacks "$managed" "install-developer-tools.sh" "$case_name uses image-baked developer tools"
      elif [[ "$preset" == "t3" ]]; then
        # System packages need root and land outside every volume, so they stay
        # the image's job. Homebrew sits in a persistent volume, so chezmoi owns
        # it from the same catalog as every other machine.
        assert_has  "$managed" "install-homebrew-packages.sh" "$case_name manages Brew packages through chezmoi"
        assert_lacks "$managed" "install-system-packages.sh" "$case_name leaves system packages to the image"
        assert_has  "$managed" "install-developer-tools.sh" "$case_name manages pinned developer tools"
      else
        assert_has "$managed" "install-homebrew-packages.sh" "$case_name manages portable Brew packages"
        if [[ "$os" == "linux" ]]; then
          assert_has "$managed" "install-system-packages.sh" "$case_name manages apt packages"
        else
          assert_lacks "$managed" "install-system-packages.sh" "$case_name has no apt installer"
        fi
        if [[ "$preset" == "workstation" || "$preset" == "server" ]]; then
          assert_has "$managed" "install-developer-tools.sh" "$case_name manages pinned developer tools"
        else
          assert_lacks "$managed" "install-developer-tools.sh" "$case_name omits developer tools"
        fi
      fi

      if [[ "$preset" == "workstation" || "$preset" == "t3" ]]; then
        assert_has "$managed" "setup-ai-agent-platform.sh" "$case_name enables its AI profile"
        assert_has "$managed" ".config/agents/context/base.md" "$case_name deploys the base context layer"
        assert_has "$managed" ".config/agents/context/environment.md" "$case_name deploys the environment context layer"
        assert_has "$managed" ".config/agents/context/ax-context.md" "$case_name deploys the ax session context layer"
        assert_has "$managed" ".claude/CLAUDE.md" "$case_name gives Claude its native global context"
        assert_has "$managed" ".codex/AGENTS.md" "$case_name gives Codex its native global context"
        assert_has "$managed" ".kimi/AGENTS.md" "$case_name gives Kimi its native global context"
        assert_has "$managed" ".grok/AGENTS.md" "$case_name gives Grok its native global context"
        assert_has "$managed" ".gemini/GEMINI.md" "$case_name gives Antigravity its native global context"
        assert_has "$managed" ".cursor/rules/environment.mdc" "$case_name gives Cursor an always-applied user rule"
        assert_has "$managed" ".config/nono/profiles/default-codex.json" "$case_name ships the Codex sandbox profile"
      else
        assert_lacks "$managed" "setup-ai-agent-platform.sh" "$case_name disables AI"
        assert_lacks "$managed" ".config/agents/context/base.md" "$case_name omits agent context layers"
        assert_lacks "$managed" ".codex/AGENTS.md" "$case_name omits Codex context"
      fi

      # The shims are gone: nothing may shadow a real agent binary on PATH.
      for shimmed in claude codex omp opencode crush; do
        assert_lacks "$managed" ".local/bin/$shimmed" "$case_name does not shadow the real $shimmed binary"
      done

      if [[ "$preset" == "workstation" ]]; then
        assert_has "$managed" ".config/cli-proxy-api/config.yaml" "$case_name manages a local AI gateway"
      else
        assert_lacks "$managed" ".config/cli-proxy-api/config.yaml" "$case_name omits a local AI gateway"
      fi

      if [[ "$os" == "darwin" && "$preset" == "minimal" ]]; then
        assert_has "$managed" ".config/ghostty/config.ghostty" "$case_name includes minimum GUI config"
        assert_lacks "$managed" ".config/alacritty/alacritty.toml" "$case_name excludes all-tier GUI config"
      elif [[ "$os" == "darwin" && "$preset" == "workstation" ]]; then
        assert_has "$managed" ".config/ghostty/config.ghostty" "$case_name includes minimum GUI config"
        assert_has "$managed" ".config/alacritty/alacritty.toml" "$case_name includes all-tier GUI config"
      else
        assert_lacks "$managed" ".config/ghostty/config.ghostty" "$case_name excludes GUI config"
        assert_lacks "$managed" ".config/alacritty/alacritty.toml" "$case_name excludes all-tier GUI config"
      fi

      if [[ "$os" == "linux" && "$preset" == "server" ]]; then
        assert_has "$managed" "configure-linux-hardening.sh" "$case_name enables Linux hardening"
      else
        assert_lacks "$managed" "configure-linux-hardening.sh" "$case_name does not enable Linux hardening"
      fi

      if [[ "$os" == "darwin" && ( "$preset" == "minimal" || "$preset" == "workstation" ) ]]; then
        assert_has "$managed" "configure-macos-defaults.sh" "$case_name enables macOS defaults"
      else
        assert_lacks "$managed" "configure-macos-defaults.sh" "$case_name omits macOS defaults"
      fi

      if [[ "$os" == "darwin" ]]; then
        assert_has "$managed" ".local/bin/dotfiles-macos-cleanup" "$case_name exposes explicit macOS cleanup"
      else
        assert_lacks "$managed" ".local/bin/dotfiles-macos-cleanup" "$case_name excludes macOS-only commands"
      fi
      if [[ "$preset" == "workstation" || "$preset" == "server" ]]; then
        assert_has "$managed" ".local/bin/dotfiles-ssh-enroll" "$case_name exposes explicit SSH enrollment"
      else
        assert_lacks "$managed" ".local/bin/dotfiles-ssh-enroll" "$case_name excludes SSH enrollment"
      fi

      if [[ "$os" == "linux" && "$preset" != "container" && "$preset" != "t3" ]]; then
        assert_has "$managed" "setup-shell.sh" "$case_name manages login shell"
      else
        assert_lacks "$managed" "setup-shell.sh" "$case_name excludes login shell setup"
      fi

      if [[ "$preset" == "workstation" || "$preset" == "t3" ]]; then
        if [[ "$os" == "darwin" ]]; then
          assert_has "$managed" ".zed/settings.json" "$case_name uses local Zed settings"
          assert_lacks "$managed" ".config/zed/settings.json" "$case_name excludes Linux Zed settings"
        else
          assert_has "$managed" ".config/zed/settings.json" "$case_name uses Linux Zed settings"
          assert_lacks "$managed" ".zed/settings.json" "$case_name excludes macOS Zed settings"
        fi
      else
        assert_lacks "$managed" ".zed/settings.json" "$case_name excludes macOS Zed settings"
        assert_lacks "$managed" ".config/zed/settings.json" "$case_name excludes Linux Zed settings"
      fi
    done
  done
done

linux_config="$fixture_root/linux-workstation.json"
make_config "$linux_config" workstation linux amd64
linux_brew="$(render_template "$linux_config" run_onchange_before_install-homebrew-packages.sh.tmpl)"
linux_apt="$(render_template "$linux_config" run_onchange_before_install-system-packages.sh.tmpl)"
linux_developer="$(render_template "$linux_config" run_onchange_after_install-developer-tools.sh.tmpl)"
if grep -q '^brew "ripgrep"$' <<<"$linux_brew"; then
  pass "Linux renders portable CLI tools through Brew"
else
  fail "Linux renders portable CLI tools through Brew"
fi
if grep -q '^brew "git"$' <<<"$linux_brew" || grep -q '^brew "curl"$' <<<"$linux_brew"; then
  fail "Linux does not duplicate system Git and curl through Brew"
else
  pass "Linux does not duplicate system Git and curl through Brew"
fi
for package in git curl zsh docker.io; do
  if grep -q "^  \"$package\"$" <<<"$linux_apt"; then
    pass "Linux apt inventory includes $package"
  else
    fail "Linux apt inventory includes $package"
  fi
done
if grep -q '^brew trust --formula "charmbracelet/tap/crush"$' <<<"$linux_brew"; then
  pass "Crush formula is trusted before Brew bundle evaluation"
else
  fail "Crush formula is trusted before Brew bundle evaluation"
fi

linux_server_config="$fixture_root/linux-server.json"
make_config "$linux_server_config" server linux amd64
linux_hardening="$(render_template "$linux_server_config" run_onchange_after_configure-linux-hardening.sh.tmpl)"
hardening_path_setup="$(grep -m1 '^export PATH=' <<<"$linux_hardening" || true)"
hardening_path="$({ PATH=/usr/bin:/bin bash -c "${hardening_path_setup:-:}; printf '%s' \"\$PATH\""; })"
if [[ ":$hardening_path:" == *:/usr/sbin:* && ":$hardening_path:" == *:/sbin:* ]]; then
  pass "Linux hardening resolves administrative commands outside a user PATH"
else
  fail "Linux hardening resolves administrative commands outside a user PATH" \
    "rendered PATH: $hardening_path"
fi
# shellcheck disable=SC2016 # These are literal rendered-code assertions.
if grep -qF 'ssh_port="${SSH_CONNECTION##* }"' <<<"$linux_hardening" &&
   grep -qF 'ufw allow "${ssh_port}/tcp"' <<<"$linux_hardening"; then
  pass "Linux hardening preserves the active SSH server port"
else
  fail "Linux hardening preserves the active SSH server port"
fi

linux_shell="$(render_template "$linux_config" run_onchange_after_setup-shell.sh.tmpl)"
if grep -qF 'getent passwd' <<<"$linux_shell" &&
   grep -qF 'sudo -n usermod' <<<"$linux_shell"; then
  pass "Linux shell setup uses noninteractive usermod with getent passwd"
else
  fail "Linux shell setup uses noninteractive usermod with getent passwd"
fi
if grep -qF 'chsh' <<<"$linux_shell"; then
  fail "Linux shell setup contains no chsh calls"
else
  pass "Linux shell setup contains no chsh calls"
fi
if bash -n <<<"$linux_shell"; then
  pass "Linux shell setup script syntax is valid"
else
  fail "Linux shell setup script syntax is valid"
fi

mac_config="$fixture_root/mac-workstation.json"
make_config "$mac_config" workstation darwin arm64
mac_brew="$(render_template "$mac_config" run_onchange_before_install-homebrew-packages.sh.tmpl)"
mac_developer="$(render_template "$mac_config" run_onchange_after_install-developer-tools.sh.tmpl)"
if grep -q '^brew "git"$' <<<"$mac_brew"; then
  pass "macOS renders Git through Brew"
else
  fail "macOS renders Git through Brew"
fi
if grep -q '^cask "ghostty"$' <<<"$mac_brew"; then
  pass "macOS workstation renders GUI casks"
else
  fail "macOS workstation renders GUI casks"
fi

# Codex ships as a Homebrew cask, not a formula. Requesting it as a formula
# fails `brew bundle` on macOS and cannot work at all on Linux, where casks do
# not exist — npm is the only provider there.
# Homebrew 5 refuses to load formulae from untrusted taps, and `brew tap`
# readalls the whole tap — so trusting after tapping never runs, and the tap's
# other formulae make it exit non-zero. Trust must come first and the tap must
# be best effort, or a fresh machine cannot install crush at all.
trust_line=$(grep -n 'brew trust --formula "charmbracelet/tap/crush"' <<<"$mac_brew" | cut -d: -f1)
tap_line=$(grep -n 'brew tap "charmbracelet/tap"' <<<"$mac_brew" | cut -d: -f1)
if [[ -n "$trust_line" && -n "$tap_line" && "$trust_line" -lt "$tap_line" ]]; then
  pass "third-party taps are trusted before they are tapped"
else
  fail "third-party taps are trusted before they are tapped" "trust=$trust_line tap=$tap_line"
fi
if grep -q 'brew tap "charmbracelet/tap" || true' <<<"$mac_brew"; then
  pass "tapping tolerates untrusted formulae elsewhere in the tap"
else
  fail "tapping tolerates untrusted formulae elsewhere in the tap"
fi

if grep -q '^cask "codex"$' <<<"$mac_brew"; then
  pass "macOS renders Codex as the cask it actually is"
else
  fail "macOS renders Codex as the cask it actually is"
fi
if grep -q '^brew "codex"$' <<<"$mac_brew" || grep -q '^brew "codex"$' <<<"$linux_brew"; then
  fail "Codex is never requested as a Homebrew formula"
else
  pass "Codex is never requested as a Homebrew formula"
fi
if grep -qF 'npm install --global "@openai/codex@latest"' <<<"$linux_developer"; then
  pass "Linux installs Codex from npm, its only provider there"
else
  fail "Linux installs Codex from npm, its only provider there"
fi
if grep -qxF 'cargo install "cargo-clean-all" --version "0.6.4" --locked' <<<"$mac_developer"; then
  pass "developer tools render a published cargo-clean-all release"
else
  fail "developer tools render a published cargo-clean-all release"
fi

if grep -qF 'npm install --global "@oh-my-pi/pi-coding-agent@18.2.2"' <<<"$linux_developer"; then
  pass "Linux installs the pinned Oh My Pi replacement"
else
  fail "Linux installs the pinned Oh My Pi replacement" "$linux_developer"
fi
native_ai="$(render_template "$linux_config" run_onchange_after_install-ai-native-tools.sh.tmpl)"
if grep -qF 'https://cursor.com/install' <<<"$native_ai" &&
   grep -qF 'https://antigravity.google/cli/install.sh' <<<"$native_ai"; then
  pass "AI native installer renders Cursor and Antigravity from canonical inventory"
else
  fail "AI native installer renders Cursor and Antigravity from canonical inventory" "$native_ai"
fi
if grep -Eq -- '--skip-aliases|--skip-path' <<<"$native_ai"; then
  fail "Antigravity installer receives only currently supported arguments" "$native_ai"
else
  pass "Antigravity installer receives only currently supported arguments"
fi

if grep -qF "alias ls='eza -l --group-directories-first --icons --hyperlink=auto'" \
  "$repo_root/dot_dotfiles/dot_aliases.tmpl"; then
  pass "the eza hyperlink option cannot consume the first ls pathname"
else
  fail "the eza hyperlink option cannot consume the first ls pathname"
fi

t3_config="$fixture_root/t3.json"
make_config "$t3_config" t3 linux arm64
t3_ax="$(render_template "$t3_config" dot_config/ax/models.json.tmpl)"
if jq -e '.proxy.url == "http://cliproxyapi:8317" and .proxy.mode == "sidecar"' <<<"$t3_ax" >/dev/null; then
  pass "t3 renders the sidecar gateway URL"
else
  fail "t3 renders the sidecar gateway URL"
fi

workstation_config="$fixture_root/workstation-gw.json"
make_config "$workstation_config" workstation darwin arm64
workstation_ax="$(render_template "$workstation_config" dot_config/ax/models.json.tmpl)"
if jq -e '.proxy.url == "http://127.0.0.1:8317" and .proxy.mode == "local"' <<<"$workstation_ax" >/dev/null; then
  pass "workstation renders the loopback gateway URL"
else
  fail "workstation renders the loopback gateway URL"
fi
if jq -e '.agents | has("codex")' <<<"$workstation_ax" >/dev/null; then
  pass "the model registry knows about codex"
else
  fail "the model registry knows about codex"
fi

# AI-feature npm packages must not reach a machine with ai disabled.
server_devtools="$(render_template "$fixture_root/linux-amd64-server.json" run_onchange_after_install-developer-tools.sh.tmpl)"
if grep -q 'npm install --global "@openai/codex' <<<"$server_devtools" ||
   grep -q 'npm install --global "@anthropic-ai/claude-code' <<<"$server_devtools"; then
  fail "AI npm packages are withheld from AI-disabled machines" "$server_devtools"
else
  pass "AI npm packages are withheld from AI-disabled machines"
fi
workstation_devtools="$(render_template "$fixture_root/darwin-arm64-workstation.json" run_onchange_after_install-developer-tools.sh.tmpl)"
if grep -q 'npm install --global "@openai/codex' <<<"$workstation_devtools"; then
  pass "AI npm packages reach AI-enabled machines"
else
  fail "AI npm packages reach AI-enabled machines" "$workstation_devtools"
fi

tmux_linux="$(render_template "$linux_config" dot_config/tmux/tmux.conf.tmpl)"
if grep -q '/home/linuxbrew/.linuxbrew/opt/tpm' <<<"$tmux_linux"; then
  pass "Linux tmux config uses the derived Homebrew prefix"
else
  fail "Linux tmux config uses the derived Homebrew prefix"
fi
tmux_mac="$(render_template "$mac_config" dot_config/tmux/tmux.conf.tmpl)"
if grep -q '/opt/homebrew/opt/tpm' <<<"$tmux_mac"; then
  pass "Apple Silicon tmux config uses the derived Homebrew prefix"
else
  fail "Apple Silicon tmux config uses the derived Homebrew prefix"
fi

inventory="$(
  chezmoi data \
    --config "$linux_config" \
    --config-format json \
    --source "$repo_root" \
    --format json
)"
if jq -e '
  [.packages.inventory[].id] as $ids |
  ($ids | length) == ($ids | unique | length)
' <<<"$inventory" >/dev/null; then
  pass "canonical package IDs are unique"
else
  fail "canonical package IDs are unique"
fi
if jq -e '
  (.packages.schemaVersion == 1) and
  all(
    .packages.inventory[];
    (.id | type == "string" and length > 0) and
    (.feature | IN("base", "cli", "developer", "ai", "ai-local", "gui-minimum", "gui-all", "hardening")) and
    (.providers | type == "object" and length > 0)
  )
' <<<"$inventory" >/dev/null; then
  pass "canonical package entries use the supported schema and features"
else
  fail "canonical package entries use the supported schema and features"
fi
if jq -e '
  all(
    .packages.inventory[];
    all((.os? // ["darwin", "linux"])[]; IN("darwin", "linux")) and
    all((.arch? // ["amd64", "arm64"])[]; IN("amd64", "arm64")) and
    ((.providers.cask? // {}) | keys | all(.[]; IN("darwin")))
  )
' <<<"$inventory" >/dev/null; then
  pass "package platform and architecture constraints are supported"
else
  fail "package platform and architecture constraints are supported"
fi
if jq -e '
  all(
    .packages.inventory[];
    all(
      [(.providers.mise? // {}), (.providers.npm? // {}),
       (.providers.uv? // {}), (.providers.cargo? // {})][];
      (length == 0) or
      ((.name | type == "string" and length > 0) and
       (.version | type == "string" and length > 0))
    )
  )
' <<<"$inventory" >/dev/null; then
  pass "secondary package providers use explicit versions"
else
  fail "secondary package providers use explicit versions"
fi
legacy_config="$fixture_root/legacy.json"
jq -n '{
  data: {
    setupCli: true,
    setupDeveloper: true,
    setupAi: true,
    aiMode: "local",
    guiTier: "all",
    setupMacos: true,
    setupLinuxHardening: false,
    setupSshKey: false,
    name: "Legacy Test",
    email: "legacy@example.com"
  }
}' >"$legacy_config"
legacy_managed="$(render_managed "$legacy_config" "$fixture_root/legacy-home")"
legacy_scripts="$(
  HOME="$fixture_root/legacy-home" chezmoi managed \
    --config "$legacy_config" \
    --config-format json \
    --source "$repo_root" \
    --destination "$fixture_root/legacy-home" \
    --cache "$host_cache" \
    --include=scripts \
    --exclude=externals \
    --refresh-externals=never
)"
if [[ -z "$legacy_scripts" ]]; then
  pass "legacy configs do not replay the new provisioning pipeline"
else
  fail "legacy configs do not replay the new provisioning pipeline" "$legacy_scripts"
fi
if grep -q '^.local/bin/dotfiles-' <<<"$legacy_managed"; then
  fail "legacy configs do not add new explicit helper commands"
else
  pass "legacy configs do not add new explicit helper commands"
fi

if jq -e '
  all(
    .packages.inventory[];
    . as $pkg |
      [($pkg.providers.brew? // {})[]] |
      all(
        .[];
        if contains("/") then
          ((split("/")[0:2] | join("/")) == ($pkg.homebrew.tap? // "")) and
          (($pkg.homebrew.trust? // "") == "formula")
        else true
        end
      )
  )
' <<<"$inventory" >/dev/null; then
  pass "third-party Brew formulae declare formula-level trust metadata"
else
  fail "third-party Brew formulae declare formula-level trust metadata"
fi

for example in "$repo_root"/examples/configs/*.json; do
  if render_managed "$example" "$fixture_root/example-$(basename "$example" .json)" >/dev/null; then
    pass "$(basename "$example") renders unattended"
  else
    fail "$(basename "$example") renders unattended"
  fi
done

invalid_config="$fixture_root/invalid.json"
make_config "$invalid_config" invalid linux amd64
if render_managed "$invalid_config" "$fixture_root/invalid-home" >/dev/null 2>&1; then
  fail "unknown presets are rejected"
else
  pass "unknown presets are rejected"
fi

unsupported_config="$fixture_root/unsupported.json"
make_config "$unsupported_config" server linux amd64
jq '.data.machine.distro = "fedora"' "$unsupported_config" >"$unsupported_config.tmp"
mv "$unsupported_config.tmp" "$unsupported_config"
if render_managed "$unsupported_config" "$fixture_root/unsupported-home" >/dev/null 2>&1; then
  fail "unsupported Linux distributions are rejected"
else
  pass "unsupported Linux distributions are rejected"
fi

override_config="$fixture_root/override.json"
make_config "$override_config" workstation linux arm64
jq '
  .data.machine.customize = true |
  .data.machine.overrides = {
    cli: false,
    developer: true,
    ai: false,
    aiMode: "local",
    guiTier: "all",
    osCustomization: true,
    hardening: false,
    ssh: false
  }
' "$override_config" >"$override_config.tmp"
mv "$override_config.tmp" "$override_config"
override_machine="$(
  chezmoi execute-template \
    --config "$override_config" \
    --config-format json \
    --source "$repo_root" \
    '{{ includeTemplate "machine" . }}'
)"
if jq -e '
  (.features.cli == false) and
  (.features.developer == false) and
  (.features.guiTier == "none") and
  (.features.osCustomization == false)
' <<<"$override_machine" >/dev/null; then
  pass "invalid dependent overrides are normalized safely"
else
  fail "invalid dependent overrides are normalized safely"
fi

if [[ "$fail_count" -ne 0 ]]; then
  printf '1..%d\n' "$((pass_count + fail_count))"
  printf '%d test(s) failed.\n' "$fail_count" >&2
  exit 1
fi
printf '1..%d\n' "$pass_count"
