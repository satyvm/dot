# AGENTS.md — satyvm / dot

Personal dotfiles managed with [chezmoi](https://chezmoi.io). Primary target is **macOS** (dev/personal profiles), with **Linux** (Debian/Ubuntu server profile) support.

## Quick Reference

| Command | What it does |
|---------|-------------|
| `chezmoi update` | Pull latest and apply |
| `chezmoi diff` | Preview pending changes |
| `chezmoi edit ~/.zshrc` | Edit a managed file |
| `chezmoi cd` | Jump to source directory |
| `chezmoi apply` | Apply pending changes |
| `chezmoi state delete-bucket --bucket=scriptState && chezmoi apply` | Re-run `run_once_*` scripts |

## Directory Structure

```
~/.local/share/chezmoi/
├── .chezmoi.json.tmpl           # Config: encryption, age keys, profile/git prompts
├── .chezmoiignore.tmpl          # Platform/profile ignore rules (uses Go templates)
├── .chezmoiexternal.toml        # External archives (agent skills from GitHub)
├── .setup.sh                    # Bootstrap: installs deps, runs chezmoi init
├── dot_zshrc                    # → ~/.zshrc
├── dot_zshenv                   # → ~/.zshenv (disables macOS session restoration)
├── dot_dotfiles/                # → ~/.dotfiles/ (sourced by .zshrc in order)
│   ├── dot_exports.tmpl         #   PATH, XDG, env vars, Rust/Bun/Go
│   ├── dot_aliases.tmpl         #   ls→eza, cat→bat, cd→z, lg→lazygit, etc.
│   ├── dot_functions.tmpl       #   mcd, extract, search, AI agent wrappers
│   └── dot_extra.tmpl           #   zsh plugins, fnm, mise, zoxide, fzf, thefuck
├── dot_config/                  # → ~/.config/
│   ├── nvim/                    #   Neovim (lazy.nvim, satyvm namespace)
│   ├── tmux/tmux.conf.tmpl      #   tmux (C-a prefix, vi mode, undercurl)
│   ├── starship/starship.toml   #   Starship prompt
│   ├── ghostty/config.ghostty   #   Ghostty terminal
│   ├── git/config.tmpl          #   Git config (delta, SSH signing, rebase)
│   ├── nono/profiles/           #   Nono sandbox profiles for AI agents
│   ├── agents/skills/           #   AI agent skills (downloaded via external archives)
│   └── ...                      #   alacritty, herdr, pet, cli-proxy-api
├── run_once_after_*.sh.tmpl     # Setup scripts (run once on first apply)
├── run_onchange_*.sh.tmpl       # Package installers (re-run on change)
└── dot_backup/                  # Backup scripts + encrypted assets
    └── scripts/
        ├── executable_backup-local.sh   # → backup-local.sh
        └── executable_restore-local.sh  # → restore-local.sh
```

## Machine Profiles

Set during `chezmoi init`. Controls which packages/scripts are applied via Go template conditionals (`{{ .profile }}`).

| Profile | macOS | Linux |
|---------|-------|-------|
| `personal` | Essential GUIs + CLI tools | CLI tools only |
| `dev` | Full desktop — all apps, Cursor profile, macOS defaults | CLI + Docker + server hardening |
| `server` | CLI + Docker (Colima) — no GUIs | CLI + Docker + UFW/fail2ban |

## Template System

All `.tmpl` files are [chezmoi Go templates](https://chezmoi.io/reference/templates/). Key variables:

| Variable | Source | Example |
|----------|--------|---------|
| `.chezmoi.os` | chezmoi built-in | `"darwin"` / `"linux"` |
| `.profile` | `.chezmoi.json.tmpl` prompt | `"personal"` / `"dev"` / `"server"` |
| `.name` | `.chezmoi.json.tmpl` prompt | Git user name |
| `.email` | `.chezmoi.json.tmpl` prompt | Git email |
| `.setupSshKey` | `.chezmoi.json.tmpl` prompt | boolean |

Common patterns: `{{- if eq .chezmoi.os "darwin" }}`, `{{- if eq .profile "dev" }}`, `{{- end }}`.

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
- `dot_backup/scripts/` (run from source via `"$(chezmoi source-path)/scripts/backup-local.sh"`)
- `dot_backup/encrypted_cursor-default.code-profile.age`

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

**Key gotcha**: `dot_functions.tmpl` wraps all four AI tools. When `HERDR_ENV=1` is set, session resume/subcommands are intercepted to run inside `ax <profile> auto safe` (nono sandbox). Otherwise they call the real binary. This means agent session resume in herdr context is transparently sandboxed.

### Nono Sandbox Profiles
Located in `dot_config/nono/profiles/`. Each agent has a profile:
- `default-crush.json` extends `default-claude.json` — adds Crush config paths + read access to skills, fnm, mise dirs
- Nono controls filesystem access, network, workdir permissions for sandboxed AI agents

## Shell Initialization Order

`dot_zshrc` sources `~/.dotfiles/` files in this exact order:

1. `exports` — PATH, XDG dirs, environment variables
2. `aliases` — ls→eza, cat→bat, cd→z, etc.
3. `functions` — mcd, extract, search, AI wrappers
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

## Package Management

- **macOS**: Homebrew (Brewfile in `run_onchange_brew-packages.sh.tmpl`)
- **Linux**: apt packages (in `run_onchange_apt-packages.sh.tmpl`)

Package sets vary by profile — dev profile gets the most, server skips GUIs. Docker included on dev + server profiles.

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

External SSD sync scripts at `dot_backup/scripts/`:

```bash
"$(chezmoi source-path)/scripts/backup-local.sh"
"$(chezmoi source-path)/scripts/restore-local.sh" /Volumes/MyDrive/mac_backup/local_310526
```

Backups are timestamped (`local_DDMMYY`). Auto-detects first non-system volume if no path given. Restore backs up existing data before overwriting.

## Important Gotchas

1. **`.tmpl` files are Go templates** — don't edit them as plain config files. Pay attention to template conditionals.
2. **`run_once_after_*` scripts won't re-run** unless you clear state: `chezmoi state delete-bucket --bucket=scriptState`
3. **`HERDR_ENV=1` intercepts AI CLI tools** — calling `claude --resume` in herdr context wraps in `ax` sandbox. To bypass, use `command claude` (the wrapper uses `command` to call the real binary).
4. **External skills are refreshed weekly** — if editing local skills in `~/.config/agents/skills/`, be aware they may get overwritten by chezmoi external sync.
5. **Sensitive data is not in this repo** — SSH keys, browser profiles, personal docs are backed up separately to external SSD.
6. **Platform-sensitive files** may not be present (e.g., macOS scripts are ignored entirely on Linux via `.chezmoiignore.tmpl`).
7. **No tests** — this is a configuration repository. Validate by running `chezmoi diff` or `chezmoi apply --dry-run`.
8. **Docker on macOS** uses Colima, not Docker Desktop.
9. **fzf initialization is deferred** via precmd hook for faster shell startup.
