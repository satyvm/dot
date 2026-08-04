# AGENTS.md — satyvm / dot

Personal dotfiles managed with [chezmoi](https://chezmoi.io). Supports macOS
and Debian/Ubuntu on `amd64` and `arm64`.

## Quick Reference

| Command | What it does |
|---------|-------------|
| `chezmoi update` | Pull latest and apply |
| `chezmoi diff` | Preview pending changes |
| `chezmoi edit ~/.zshrc` | Edit a managed file |
| `chezmoi cd` | Jump to source directory |
| `chezmoi apply` | Apply pending changes |
| `bash tests/test_machine_matrix.sh` | Validate every platform/preset combination |

## Directory Structure

```
~/.local/share/chezmoi/
├── .chezmoi.json.tmpl           # Config: preset, host facts, overrides, identity
├── .chezmoidata/                # Machine presets, packages, AI registries
├── .chezmoitemplates/machine    # Canonical resolved machine object
├── .chezmoiignore.tmpl          # Deployment rules using machine predicates
├── .setup.sh                    # Bootstrap: installs deps, runs chezmoi init
├── dot_zshrc.tmpl               # → ~/.zshrc
├── dot_zshenv                   # → ~/.zshenv (disables macOS session restoration)
├── dot_dotfiles/                # → ~/.dotfiles/ (sourced by .zshrc in order)
│   ├── dot_exports.tmpl         #   PATH, XDG, env vars, Rust/Bun/Go
│   ├── dot_aliases.tmpl         #   ls→eza, cat→bat, cd→z, lg→lazygit, etc.
│   ├── dot_functions.tmpl       #   mcd, extract, search, charm compatibility
│   └── dot_extra.tmpl           #   zsh plugins, fnm, mise, zoxide, fzf, thefuck
├── dot_config/                  # → ~/.config/
│   ├── nvim/                    #   Neovim (lazy.nvim, satyvm namespace)
│   ├── tmux/tmux.conf.tmpl      #   tmux (C-a prefix, vi mode, undercurl)
│   ├── starship/starship.toml   #   Starship prompt
│   ├── ghostty/config.ghostty   #   Ghostty terminal
│   ├── git/config.tmpl          #   Git config (delta, SSH signing, rebase)
│   ├── nono/profiles/           #   Nono sandbox profiles for AI agents
│   ├── ax/models.json.tmpl      #   Rendered canonical agent/model registry
│   ├── agents/skills/           #   AI agent skills (downloaded via external archives)
│   └── ...                      #   alacritty, herdr, pet, cli-proxy-api
├── dot_local/bin/               # → ~/.local/bin/ (`ax` + managed agent shims)
├── run_onchange_*.sh.tmpl       # Providers and convergent setup
├── examples/configs/            # Explicit unattended machine configs
├── tests/test_machine_matrix.sh # macOS/Linux × amd64/arm64 × four presets
├── backup/                      # Repository-only backup assets and scripts
│   └── scripts/
│       ├── executable_backup-local.sh
│       └── executable_restore-local.sh
└── hermes/                      # Repository-only Coolify remote-development platform
```

## Machine Profiles

`chezmoi init` first selects `laptop`, `workstation`, `server`, or `container`,
then offers optional feature overrides. Host facts and choices are persisted
under `data.machine`. `.chezmoidata/machine.yaml` owns preset defaults and
`.chezmoitemplates/machine` derives the resolved features and predicates.
Legacy configs with the former top-level setup booleans still render.

## Template System

All `.tmpl` files are [chezmoi Go templates](https://chezmoi.io/reference/templates/). Key variables:

| Variable | Source | Example |
|----------|--------|---------|
| `$machine.os` | resolved machine template | `"darwin"` / `"linux"` |
| `$machine.arch` | resolved machine template | `"amd64"` / `"arm64"` |
| `$machine.features` | preset plus overrides | CLI/developer/AI/GUI/etc. |
| `$machine.predicates` | derived policy | host packages/GUI/proxy/etc. |
| `.name` | `.chezmoi.json.tmpl` prompt | Git user name |
| `.email` | `.chezmoi.json.tmpl` prompt | Git email |

Start platform-sensitive templates with
`{{- $machine := includeTemplate "machine" . | fromJson -}}`. Do not add new
independent setup booleans.

## Chezmoi Naming Conventions

| Prefix | Effect |
|--------|--------|
| `dot_` | File becomes `.` (hidden) in home: `dot_zshrc` → `~/.zshrc` |
| `private_dot_` | Hidden + restricted permissions (600/700) |
| `executable_` | File gets executable bit |
| `run_once_after_` | Runs once on first `chezmoi apply` after addition |
| `run_onchange_` | Runs on every `chezmoi apply` if file has changed |
| `symlink_` | Creates a symlink instead of copying |
| `encrypted_` | Encrypted with `age` (key at `~/.config/chezmoi/key.txt`) |

Path mapping: `dot_config/nvim/init.lua` → `~/.config/nvim/init.lua`. The directory tree under `dot_config/` mirrors `~/.config/` exactly.

## Repo-Only Files (not deployed)

Listed in `.chezmoiignore.tmpl`. These files stay in the source directory only:

- `README.md`, `AGENTS.md`, `.setup.sh`
- `examples/`, `tests/`, `backup/`, and `hermes/`

## AI Agent Infrastructure

### Agent Skills
Skills are downloaded from GitHub archives via `.chezmoiexternal.toml`:
- **mattpocock/skills**: code-review, codebase-design, diagnose, domain-modeling, grill-with-docs, implement, prototype, research, resolving-merge-conflicts, setup-pre-commit, skill-creator, tdd, triage, wayfinder, and writing/content skills
- **anthropics/claude-code**: frontend-design (from plugins/frontend-design)
- **anthropics/skills**: skill-creator
- **vercel-labs/agent-skills**: vercel-react-best-practices

Skills are refreshed every 168h (7 days) and symlinked from `dot_agents/symlink_skills` → `private_dot_claude/symlink_skills`.

### AI CLI Tools & Sandboxing
These AI CLI tools are all installed:
- **Crush** (`crush` / `charm`): Personal AI assistant
- **Claude Code** (`claude`): Anthropic's CLI agent
- **PI Coding Agent** (`pi`): @earendil-works agent
- **OpenCode** (`opencode`): Open-source CLI agent

On macOS `dev`, managed PATH shims for all four native command names always
delegate to `ax`. `ax` is the single policy gateway: Nono is the default,
`--direct` is the explicit escape hatch, and Herdr resume arguments pass through
unchanged. The real binaries are resolved with `~/.local/bin` removed from the
search path so the shims cannot recurse.

### Nono Sandbox Profiles
Located in `dot_config/nono/profiles/`. Each agent has a profile:
- `default-agent.json` holds the shared developer network, worktree, runtime-read,
  and credential-deny boundary; `ax` grants the resolved Herdr socket dynamically
- `default-claude.json`, `default-pi.json`, `default-opencode.json`, and
  `default-crush.json` add only the state paths required by each client
- Nono controls filesystem access, network, workdir permissions for sandboxed AI agents

## Shell Initialization Order

`dot_zshrc` sources `~/.dotfiles/` files in this exact order:

1. `exports` — PATH, XDG dirs, environment variables
2. `aliases` — ls→eza, cat→bat, cd→z, etc.
3. `functions` — mcd, extract, search, charm compatibility
4. `extra` — zsh plugins, fnm, mise, zoxide, fzf (deferred), thefuck, completions, starship (last)

Starship must be last — it replaces PS1.

## Key Commands from Aliases

| Alias | Expands to |
|-------|-----------|
| `ls` | `eza -l --group-directories-first --icons --hyperlink` |
| `lt` | `eza --tree --level=2 --long --icons --git` |
| `cat` | `bat --paging=never` |
| `cd` | `z` (zoxide) |
| `lg` | `lazygit` |
| `gfast` | `git add . && git commit -m "update" && git push` |
| `dot` | Bootstrap via curl: `curl -sfL https://raw.githubusercontent.com/satyvm/dot/main/.setup.sh \| bash` |
| `ec` | `$EDITOR ~/.local/share/chezmoi` (edit dotfiles) |
| `vec` | `$VISUAL ~/.local/share/chezmoi` |

## Package & Toolchain Management

- **Canonical inventory**: `.chezmoidata/packages.yaml`
- **macOS**: Homebrew formulae and casks
- **Linux**: apt for system packages/services; Linuxbrew for portable CLI tools
- **Third-party taps**: formula-level trust metadata is rendered before Brewfile evaluation
- **Versioned tools**: pinned mise/npm/uv/cargo entries; no moving `latest` installs
- **Docker**: Container engine on macOS is started and managed via **Colima** (`colima start`, `docker context use colima`), not Docker Desktop.

## Git Configuration

- **Default branch**: `main`
- **Pull strategy**: `rebase` (always rebase, not merge)
- **Diff pager**: `delta` (side-by-side, line numbers, navigation)
- **Signing**: SSH key (`~/.ssh/gh_personal.pub`), GPG format SSH
- **Signing is conditional**: only enabled if SSH key was set up
- **Merge conflict style**: `diff3`

## Neovim Setup

- Plugin manager: **lazy.nvim** (auto-installs on first launch)
- LSP on LspAttach with telescope-based keybindings
- 2-space indentation (prettier default)
- Colorscheme: tokyonight (dark), requires true color terminal
- Lua source in `lua/satyvm/` namespace

## Backup & Restore

External SSD sync scripts under the repository-only `backup/scripts/` directory:

```bash
bash "$(chezmoi source-path)/backup/scripts/executable_backup-local.sh"
bash "$(chezmoi source-path)/backup/scripts/executable_restore-local.sh" \
  /Volumes/MyDrive/mac_backup/local_310526
```

Backups are timestamped (`local_DDMMYY`). Auto-detects first non-system volume if no path given. Restore backs up existing data before overwriting.

## Important Gotchas

1. **`.tmpl` files are Go templates** — don't edit them as plain config files. Pay attention to template conditionals.
2. **App additions belong in `.chezmoidata/packages.yaml`** — use the
   `add-dotfiles-app` skill; don't hardcode installs in provider scripts.
3. **Agent names are managed shims** — `claude`, `pi`, `opencode`, and `crush`
   always enter `ax`, including through `command`. Use `ax <agent> --direct`
   only for an explicit diagnostic sandbox bypass.
4. **External skills are refreshed weekly** — repo-owned skills such as
   `add-dotfiles-app` are tracked here; upstream archive targets may be replaced
   on external refresh.
5. **Sensitive data is not in this repo** — SSH keys, browser profiles, personal docs are backed up separately to external SSD.
6. **Platform-sensitive files** may not be present (e.g., macOS scripts are ignored entirely on Linux via `.chezmoiignore.tmpl`).
7. **Platform tests are shell-based** — run `bash tests/test_machine_matrix.sh`
   and `bash dot_local/bin/tests/test_ax.sh`; also validate with `chezmoi diff`
   or `chezmoi apply --dry-run`.
8. **Docker on macOS** is started and managed with Colima (`colima start`), not Docker Desktop.
9. **fzf initialization is deferred** via precmd hook for faster shell startup.
