---
name: nono-init
description: "Interactively inspect project toolchains and generate a per-project .nono.json profile for sandboxed agent runs."
---

# `nono-init` Skill: Interactive Per-Project Nono Profile Generator

Use this skill when the user asks to "set up sandbox", "initialize nono", "configure sandbox for this project", or runs `/nono-init`.

## Workflow

### 1. Inspect Project Toolchains
Read `AGENTS.md`, `.local/CONTEXT.md`, and relevant `.local/adr/` records when present. Then analyze files in the current working directory (`$PWD`) to identify project stack and runtime requirements:
- **Node.js / Web**: `package.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb`
- **Rust**: `Cargo.toml`, `Cargo.lock`
- **Go**: `go.mod`, `go.sum`
- **Python**: `pyproject.toml`, `requirements.txt`, `Pipfile`, `setup.py`
- **.NET / C#**: `*.csproj`, `*.sln`
- **Docker / K8s**: `Dockerfile`, `docker-compose.yml`, `*.k8s.yaml`
- **Build / Tooling**: `Makefile`, `Justfile`, `CMakeLists.txt`

### 2. Formulate Nono Profile Configuration
Base the configuration on the `default-claude` profile (`"extends": "default-claude"`):
- **Workdir Access**: Set `"workdir": { "access": "readwrite" }`.
- **Undo Exclusions**: Include toolchain build outputs:
  - Node: `node_modules`, `.next`, `dist`, `build`
  - Rust: `target`
  - Python: `__pycache__`, `.venv`, `.pytest_cache`
  - Go/C#: `bin`, `obj`
- **Filesystem Allow**: Add specific runtime cache/config directories needed by toolchains (e.g., `~/.cargo/registry`, `~/.cache/go-build`, `~/.npm`).
- **Network & System Permissions**: Ensure `"network": { "block": false }` for web/API operations unless strict offline isolation is requested.

### 3. Generate `.nono.json`
Write the generated JSON configuration to `$PWD/.nono.json`.

`.nono.json` is runtime configuration, not skill state, so it intentionally remains at the project root rather than under `.local/`.

Example template:
```json
{
  "$schema": "https://nono.sh/schemas/profile.json",
  "meta": {
    "name": "project-sandbox",
    "version": "1.0.0",
    "description": "Per-project nono sandbox profile"
  },
  "extends": "default-claude",
  "workdir": {
    "access": "readwrite"
  },
  "undo": {
    "exclude_patterns": [
      "node_modules",
      ".next",
      "target",
      "dist",
      "bin",
      "obj",
      "__pycache__"
    ]
  },
  "interactive": true
}
```

### 4. Confirm Setup
Summarize the rules written to `.nono.json` and inform the user that subsequent runs of `ax` in this directory will automatically pick up `.nono.json` in `safe` mode.
