---
name: add-dotfiles-app
description: Add, replace, upgrade, or remove applications and system dependencies in the satyvm/dot Chezmoi repository. Use this skill whenever a request changes installed software, Homebrew formulae or casks, apt packages, mise/npm/uv/cargo tools, third-party taps, GUI apps, Linux services, enrollment steps, or an app's managed configuration. Route every app through the canonical cross-platform inventory and machine matrix, even when the request mentions only one operating system.
compatibility: Requires chezmoi, jq, Bash, and the satyvm/dot repository layout.
---

# Add a dotfiles application

Keep software selection declarative and cross-platform. The package inventory is
the source of truth; installer scripts are generic renderers and should not gain
app-specific commands.

## Start with repository context

1. Read the repository `AGENTS.md`.
2. Read `.chezmoidata/machine.yaml`, `.chezmoidata/packages.yaml`,
   `.chezmoitemplates/machine`, and `tests/test_machine_matrix.sh`.
3. Inspect existing app configuration, `.chezmoiignore.tmpl`, package renderers,
   and explicit enrollment commands that are relevant to the requested app.
4. Check the worktree and preserve unrelated user changes.

Read [references/package-schema.md](references/package-schema.md) before editing
package metadata.

## Classify the app

Determine which roles apply:

- portable CLI application;
- macOS GUI application;
- developer runtime or tool;
- Linux system package or service;
- AI application;
- configuration-only application;
- enrollment or destructive maintenance step.

Infer obvious classifications from official package metadata and existing repo
patterns. Ask the user only when choosing the scope would materially change the
result, such as whether a server service should be enabled automatically.

Record:

- feature: `base`, `cli`, `developer`, `ai`, `ai-local`, `gui-minimum`,
  `gui-all`, or `hardening`;
- providers for macOS and Debian/Ubuntu;
- supported operating systems and architectures;
- an exact version for mise, npm, uv, or cargo;
- Homebrew tap and trust policy, if third-party;
- whether configuration or an explicit enrollment command is needed.

## Update the canonical inventory

Add one entry under `packages.inventory` in
`.chezmoidata/packages.yaml`. Reuse an existing entry when the logical
application already exists.

Provider policy:

- Use `apt` for Debian/Ubuntu system dependencies, daemons, firewall tools, and
  the host's core system packages.
- Use `brew` for portable CLI applications on macOS and Linux.
- Use `cask` only for macOS GUI applications.
- Use versioned `mise`, `npm`, `uv`, or `cargo` metadata for secondary tool
  providers. Do not add `latest`, floating LTS aliases, or unversioned installs.
- Add `os` and `arch` restrictions only when the provider or application truly
  requires them.

For a third-party Homebrew formula, use its fully qualified formula name and add:

```yaml
homebrew:
  tap: owner/tap
  trust: formula
```

Formula-level trust limits the trusted surface. Do not add a handwritten
`brew tap`, `brew trust`, or `brew install` command elsewhere; the generic Brew
renderer establishes trust before evaluating its Brewfile.

## Add configuration safely

Place managed configuration at the normal Chezmoi source path. If deployment
depends on a feature or platform, update `.chezmoiignore.tmpl` using fields from
the resolved `machine` object:

- `$machine.features.*` for selected features;
- `$machine.predicates.*` for management decisions;
- `$machine.os` and `$machine.arch` for platform selection.

Do not introduce new independent setup booleans or use `.chezmoi.os` directly in
source templates. Resolve the machine once:

```gotemplate
{{- $machine := includeTemplate "machine" . | fromJson -}}
```

Keep authentication, account enrollment, key upload, destructive cleanup, and
other user-presence workflows out of automatic apply scripts. Implement those
as clearly named commands under `dot_local/bin/`, with confirmation for
destructive actions.

## Choose the script lifecycle

- Prefer inventory-only changes; the generic installers should render them.
- Use `run_onchange` for mutable packages, versions, and convergent settings.
- Reserve `run_once` for a genuine migration that must happen once per content
  version.
- Keep scripts idempotent and fail on real installation errors.
- Never suppress a package/bootstrap failure with `|| true`.

## Extend the matrix

Add a focused assertion to `tests/test_machine_matrix.sh` when the change
introduces a new provider, feature boundary, OS/architecture constraint, trust
rule, service, or managed path. An ordinary package using an already-covered
provider still needs inventory validation but does not need 16 repetitive
assertions.

For image-baked container packages, update the image and assert that every
selected package is represented by the canonical inventory. Containers do not
run host package installers.

## Verify

Run from the repository root:

```bash
bash -n .setup.sh
bash tests/test_machine_matrix.sh
bash dot_local/bin/tests/test_ax.sh
bash dot_local/bin/tests/test_one.sh
chezmoi managed --refresh-externals=never
chezmoi diff
chezmoi apply --dry-run
```

Also render any changed template with the closest unattended example config in
`examples/configs/` and syntax-check the output. If Docker/Coolify changed, run:

```bash
bash dot_backup/coolify/tests/test_stack.sh
```

Do not run a live apply, package install, enrollment command, or destructive
command unless the user explicitly requests it.

## Handoff

Report:

- the app classification and feature;
- providers and platform/architecture constraints;
- version or tap trust decision;
- configuration and matrix changes;
- verification commands and any checks that could not run.
