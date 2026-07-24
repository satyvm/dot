# Universal Developer Environment Context

This system operates within a managed macOS/Linux developer profile using **chezmoi**.

## Essential Baseline

This file is the mandatory global instruction layer for every `ax`-managed agent. Agent startup must fail with an actionable error if this file is missing or unreadable; silently launching without it is not allowed.

Apply this baseline alongside the nearest project `AGENTS.md`. Project instructions may specialize repository behavior, but they must not bypass the `ax`/`nono` policy boundary or relocate agent-owned state outside the project `.local/` layout.

## Developer Setup & System Architecture

- **Shell**: Zsh (interactive), Bash (scripts).
- **PATH**: `~/.local/bin` contains managed shims (`claude`, `pi`, `opencode`, `crush`) and precedes package-manager paths.
- **Core CLI Replacement Tools**:
  - `ls` → `eza` (`eza -l --group-directories-first --icons --hyperlink`)
  - `cat` → `bat` (`bat --paging=never`)
  - `cd` → `z` (zoxide)
  - `lg` → `lazygit`
- **Architecture & Infrastructure**:
  - **`ax`**: Central policy gateway and router. Configures environment variables, injects system prompt contexts, validates model registries (`~/.config/ax/models.json`), and executes agents through `nono`.
  - **`nono`**: System sandbox runner enforcing per-agent security boundaries (`~/.config/nono/profiles/`).
  - **`herdr`**: Multi-agent session orchestrator. When active, `HERDR_SOCKET_PATH` is dynamically granted to the `nono` sandbox.
  - **`cliproxyapi`**: Local API proxy running on port 8317 to route requests to backend model channels securely.

## Sandbox Boundary & Security Policy

- **Sandbox Enforcement**: All CLI agent invocations must run under `nono` sandboxing via `ax`.
- **Direct Escape Prohibition**: Agents are strictly forbidden from executing or recommending the `--direct` flag unless explicitly instructed by the user for diagnostic purposes.
- **Credential & State Isolation**: Secrets, SSH keys (`~/.ssh`), GPG keys (`~/.gnupg`), cloud credentials (`~/.aws`, `~/.cargo/credentials`), proxy keys (`~/.config/cli-proxy-api`), browser data, and shell history are denied read access within the sandbox profile.
- **Socket & Network Policy**: Workdir access is read-write. Network is restricted to developer profile with localhost proxy (port 8317). Herdr Unix socket (`HERDR_SOCKET_PATH`) is allowed dynamically when Herdr orchestrates the session.

## Context & Multi-Session State Conventions

- **`./AGENTS.md`**: Project-specific development rules, test commands, linting rules, and stack details.
- **`./.local/`**: Mandatory, strictly scoped directory for multi-cycle session state and skill-managed context across task cycles:
  - `./.local/CONTEXT.md`: Dynamic domain language, concepts, and architectural vocabulary glossary.
  - `./.local/adr/`: Architecture Decision Records (`0001-*.md`).
  - `./.local/specs/`: Feature specifications and requirements files (`to-spec`).
  - `./.local/tickets/`: Tracer-bullet actionable task breakdown files (`to-tickets`).
  - `./.local/handoffs/`: Context handoff files for multi-agent or multi-session continuity (`handoff`).
  - `./.local/reports/`: Diagnostic logs, analysis summaries, and architecture reports (`improve-codebase-architecture`, `diagnose`).
  - `./.local/prototypes/`: Prototype code, logic tests, and UI scratchpad experiments (`prototype`).
  - `./.local/triage/`: Triage briefs and durable rejection records.

Read `./AGENTS.md` before project work. Inspect existing `./.local/CONTEXT.md` and relevant ADRs before changing domain behavior or module boundaries. Check for previous session state in `./.local/` on startup. Create `.local` subdirectories lazily only when writing artifacts. Never write agent state outside `./.local/`.

Use UTC timestamps in filenames as `YYYYMMDDTHHMMSSZ`. Preserve existing project policy on whether `.local/` is committed or ignored; do not change that policy implicitly. User-authored deliverables are not agent state and stay at the path chosen by the user.

## Tool Behavior & Execution Guidelines

- **Code Editing Conventions**: Always inspect existing code conventions, imports, formatting, and surrounding context before editing. Do not add unnecessary code comments unless explicitly requested.
- **Verification Requirement**: Run linting and typecheck commands (e.g. `npm run lint`, `npm run typecheck`, `pytest`, `cargo check`) after making changes to verify correctness.
- **Git Policy**: Never commit changes, amend commits, or push code unless explicitly requested by the user.
- **CLI Replacement Usage**: Prefer `eza` for directory listing, `bat` for viewing files, `z` for navigation, and `lazygit` for git operations in user suggestions.

## Chezmoi Source Safety

Inside a chezmoi source tree, basename prefixes such as `run_`, `dot_`, `private_`, and `executable_` are attributes, not literal filename text. When a deployed payload must retain a reserved prefix, escape the source basename with `literal_` (for example, `literal_run_eval.py` deploys as `run_eval.py`). Check `chezmoi target-path <source-path>` for new payloads before applying.
