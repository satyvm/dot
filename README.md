# satyvm / dot

Personal macOS and Debian/Ubuntu dotfiles managed with
[Chezmoi](https://www.chezmoi.io/). The same source supports `amd64` and
`arm64`, interactive setup, and explicit unattended machine configs.

## Goals and guarantees

- Preserve an existing macOS installation unless its config is explicitly
  migrated to the new machine model.
- Reproduce laptop, workstation, server, and container profiles on macOS or
  Debian/Ubuntu without duplicating platform logic.
- Keep package selection in one inventory and render the appropriate apt,
  Homebrew, cask, mise, npm, uv, or cargo provider.
- Keep account enrollment, key upload, App Store installation, and destructive
  cleanup out of automatic `chezmoi apply`.
- Reject unsupported operating systems, distributions, architectures, and real
  provisioning failures instead of silently continuing.

Old-style configs form a compatibility lane: their existing managed files
render byte-for-byte as before, and they do not select the new provisioning
scripts or explicit helper commands. A normal update therefore cannot replay
package installation or macOS defaults on an existing Mac. Migration is an
explicit, reviewable operation described below.

## Quick start

```bash
bash -c "$(curl -fsLS https://raw.githubusercontent.com/satyvm/dot/main/.setup.sh)"
```

Run Linux setup as a regular sudo-capable user; Linuxbrew refuses to run as
root. The bootstrap:

1. validates macOS or Debian/Ubuntu and `amd64` or `arm64`;
2. installs the OS bootstrap dependencies;
3. installs or discovers Homebrew through `brew shellenv`;
4. installs Chezmoi and initializes or updates this source;
5. fails immediately on a real bootstrap or package error.

## Machine model

Setup starts with one preset:

| Preset | Default intent |
|---|---|
| `laptop` | CLI, development, local AI, focused GUI, OS defaults, SSH signing |
| `workstation` | CLI, development, local AI, full GUI, OS defaults, SSH signing |
| `server` | Headless CLI, Linux hardening, SSH signing |
| `container` | Image-baked development and remote AI; no host package installers |

The next question offers feature overrides for CLI, developer tools, AI and its
mode, GUI tier, OS customization, Linux hardening, and SSH signing.

`.chezmoi.json.tmpl` records host facts and choices. The reusable
`.chezmoitemplates/machine` template resolves them into one object containing:

- OS, architecture, distro, Homebrew prefix, package mode, and development root;
- feature values;
- predicates such as `manageHostPackages`, `manageSystemPackages`, `manageGui`,
  `manageShell`, and `manageLocalProxy`.

Templates consume this resolved object instead of inventing platform or profile
logic independently. Substantially different platform behavior stays in
separate rendered scripts, while shared configuration consumes readable
machine predicates.

## Package providers

`.chezmoidata/packages.yaml` is the canonical application inventory:

- `apt` installs Debian/Ubuntu system dependencies, services, hardening tools,
  Zsh, and the Linux Docker packages;
- Homebrew installs portable CLI applications on macOS and Linux;
- casks install macOS GUI applications;
- mise, npm, uv, and cargo entries carry exact versions;
- third-party Homebrew formulae carry tap and trust metadata.

The Brew renderer taps and grants formula-level trust before evaluating its
Brewfile. This is how `charmbracelet/tap/crush` works on Linux without trusting
the entire tap implicitly.

Chezmoi `run_onchange` scripts render the selected inventory. `run_once` is
reserved for genuine migrations, not mutable package versions.

Provider order on Linux is intentional:

- apt owns bootstrap packages, Zsh, Docker packages, firewall tools, and system
  services;
- Linuxbrew owns portable user-facing CLI applications;
- pinned secondary providers own developer runtimes and tools.

## Debian/Ubuntu behavior

Linux hosts must be Debian or Ubuntu. Both `amd64` and `arm64` are supported.
Homebrew is installed at the prefix reported by `brew shellenv`; templates use
the derived prefix rather than assuming an Apple Silicon Mac.
Run the bootstrap as a regular sudo-capable user because Linuxbrew does not
support running as root.

The `server` preset installs UFW and fail2ban through apt before applying their
configuration. The firewall preserves the active SSH connection's server port,
falls back to the configured `sshd` port, and finally to port 22. Set
`DOTFILES_SSH_PORT` during apply to override detection. Hardening is disabled in
containers. Portable tools remain Linuxbrew packages so their names and
versions track the macOS CLI setup.

The Crush trust failure is handled before Brew evaluates the generated
Brewfile:

```bash
brew tap charmbracelet/tap
brew trust --formula charmbracelet/tap/crush
```

Only the formula is trusted; the entire third-party tap is not granted blanket
trust.

## Unattended setup

Example configs live in [`examples/configs`](examples/configs). Copy the closest
one, then change identity, home paths, OS facts, preset, and overrides:

- `linux-server-amd64.json`
- `linux-laptop-arm64.json`
- `linux-container-amd64.json`
- `macos-workstation-arm64.json`
- `macos-server-amd64.json`

To bootstrap from a local explicit config:

```bash
DOTFILES_CONFIG=/absolute/path/to/linux-server-amd64.json \
  bash .setup.sh
```

The bootstrap installs that file as the persistent Chezmoi JSON config and
applies it without prompts.

To render an example without changing the machine:

```bash
chezmoi managed \
  --config examples/configs/linux-server-amd64.json \
  --config-format json \
  --source . \
  --destination /tmp/dotfiles-preview \
  --refresh-externals=never
```

## Explicit user-presence commands

Automatic `chezmoi apply` does not authenticate accounts, upload SSH keys, or
delete applications.

```bash
dotfiles-ssh-enroll       # generate/add the key, authenticate gh, upload key
dotfiles-macos-apps       # install the selected Mac App Store applications
dotfiles-macos-cleanup    # confirmed removal of selected stock macOS apps
```

After SSH enrollment, run `chezmoi apply` to enable signing when the machine's
SSH feature is selected and the public key exists.

## Secrets and authentication

Credentials, OAuth state, SSH private keys, and agent sessions are never stored
in this repository. Age-encrypted source material is only deployed when the
local Chezmoi identity exists.

For local AI mode, complete provider authentication after applying:

```bash
ax auth setup
ax auth status
```

## Add an application

The managed `add-dotfiles-app` skill lives at
`~/.config/agents/skills/add-dotfiles-app`. It is shared by the configured agent
and Claude skill directories.

Example request:

```text
Add atuin as a CLI app on macOS and Debian/Ubuntu, including its shell config.
```

The skill will:

1. classify the app as CLI, GUI, developer tool, service, AI tool, configuration,
   or enrollment workflow;
2. update the canonical provider and platform metadata;
3. add formula-level trust for third-party Homebrew formulae;
4. scope configuration with resolved machine predicates;
5. add focused matrix coverage and render the affected profiles.

The core rule is simple: package choices belong in
`.chezmoidata/packages.yaml`; generic installers should not accumulate
app-specific branches.

## Cleanup CLI

`one` is the managed cleanup command for developer caches and project build
artifacts:

```bash
one system [--dry-run] [--yes] [--only NAME...]
one project [PATH] [--dry-run] [--yes] [--node|--rust|--all]
one all [PATH] [--dry-run] [--yes]
one list
one doctor
```

Use `--dry-run` before removing data. System cleaners cover package managers
and runtime caches; project cleaners cover Node and Rust build artifacts.

## Validation

```bash
bash tests/test_machine_matrix.sh
bash dot_local/bin/tests/test_ax.sh
bash dot_local/bin/tests/test_one.sh
bash dot_backup/coolify/tests/test_stack.sh
chezmoi managed --refresh-externals=never
chezmoi diff
chezmoi apply --dry-run
```

The current machine matrix contains 228 assertions. It covers all four presets
across macOS/Linux and `amd64`/`arm64`, including:

- provider and package-schema validation;
- GUI, AI proxy, hardening, service, and explicit-command boundaries;
- Homebrew prefixes and third-party formula trust ordering;
- unattended examples and invalid configurations;
- legacy compatibility, including suppression of new provisioning work.

The Linux path has also been exercised in disposable Ubuntu containers:

- Ubuntu 24.04 ARM64 passed the full matrix;
- Ubuntu AMD64 passed under emulation with the repository minimum Chezmoi
  version;
- the server apt renderer installed Zsh, UFW, and fail2ban successfully;
- a clean Linuxbrew environment trusted, installed, and launched Crush.

## Migrating an existing config

Existing old-style setup keys remain supported. To adopt the preset schema,
back up the current config and re-run initialization:

```bash
cp ~/.config/chezmoi/chezmoi.json ~/.config/chezmoi/chezmoi.json.before-machine-model
chezmoi init --force --source "$(chezmoi source-path)"
chezmoi diff
```

Review the diff before applying. Disabling a feature stops future management; it
does not uninstall packages or delete existing configuration.
