# satyvm / dot

Personal macOS and Linux dotfiles managed with [chezmoi](https://chezmoi.io).

## Setup choices

`chezmoi init` asks for independent, opt-in categories. There are no machine
profiles and every selection defaults to off:

| Choice | What it manages |
|---|---|
| Core CLI | Shell, Git workflow, Neovim, tmux, and terminal utilities |
| Developer toolchain | Runtimes, Docker, PostgreSQL, compilers, cloud and Kubernetes tools; requires CLI |
| AI setup | Claude Code, OpenCode, Pi, Crush, Nono, `ax`, skills, and model configuration |
| AI mode | `local` manages CLIProxyAPI locally; `remote` uses `http://cliproxyapi:8317` supplied by the environment |
| GUI tier (macOS) | `none`, `minimum` (Raycast, Ice, Shottr, Hyperkey, Ghostty, font), or `all` |
| macOS customization | Existing macOS defaults, Dock rewrite, and stock-app cleanup |
| SSH setup | Generates `gh_personal`, uploads it through GitHub CLI, and enables Git SSH signing |
| Linux hardening | UFW and fail2ban; never enabled implicitly |

Homebrew is a prerequisite on both macOS and Linux. The repository prints a
clear message and skips package installation if it is unavailable.

```bash
chezmoi init --apply satyvm/dot
chezmoi diff
chezmoi apply
```

To change choices later, use `chezmoi edit-config`, update the `data` values,
then run `chezmoi apply`. Disabling a category stops future management; it never
deletes existing files.

## Secrets and migration

Credentials, OAuth state, SSH keys, and agent sessions are never stored in this
repository. Complete local AI authentication with `ax auth setup` after applying
local AI mode.

Existing profile-based installations should remove `data.profile` and add the
new category keys through `chezmoi edit-config`. Start all categories as `false`
(`guiTier: "none"`, `aiMode: "local"`) and explicitly opt into the desired setup.
Identity and the existing `setupSshKey` value can be retained.

## Validation

```bash
bash dot_local/bin/tests/test_ax.sh
chezmoi apply --dry-run
```

`.gitignore` excludes local/sensitive source-state only. `.chezmoiignore.tmpl`
is the deployment matrix for platforms and choices.
