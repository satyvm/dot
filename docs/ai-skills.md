# Manage skills with ax

`ax skills` saves reusable workflows in the dotfiles repository and installs a
shared library for local agents and remote T3 Code. Agents still launch using
their real upstream binaries. Skills do not require the ax sandbox or gateway.

## Everyday workflow

```bash
ax skills list
ax skills new release-check
# Edit skills/owned/release-check/SKILL.md in your source checkout.
ax skills save ./my-skill
ax skills import https://github.com/owner/repository.git --path skills/example
ax skills sync --source --dry-run
ax skills sync --source
ax skills doctor --source
```

Source-changing commands use `chezmoi source-path`, or `AX_SKILLS_SOURCE_ROOT` for
an explicit checkout/worktree. They change files for review; they do not commit,
push, install dependencies, configure credentials, or apply unrelated dotfiles.
Commit the owned bundle and `.chezmoidata/ai-skills.yaml`, then run
`chezmoi update` on your other machines. `chezmoi apply` renders the registry,
records the owned source path, and runs `ax skills sync` on AI-enabled modern presets.
Legacy configurations retain their existing provisioning behavior: run
`ax skills sync` explicitly after applying.

`sync` uses the deployed registry and repository-owned bundles. `--source` instead uses
the current source checkout plus the deployed machine selection, so you can
try changes before applying them. `list --json` exposes the full registry.

## Storage and selection

| Location | Purpose |
| --- | --- |
| `.chezmoidata/ai-skills.yaml` | Canonical registry; JSON syntax, valid YAML, writable without another dependency |
| `skills/owned/` | Git-owned authored skills; repository-only, copied by ax |
| `~/.config/ax/skills.json` | Rendered registry and resolved machine selection |
| `~/.cache/ax/skills/<hash>/` | Verified third-party bundles pinned to exact Git commits |
| `~/.config/agents/skills/` | Installed shared library, managed by ax rather than chezmoi |
| `~/.local/state/ax/skills.json` | Installed source identities and content fingerprints |

The configuration/cache/state locations respect XDG variables; the managed
agent discovery links use the repository's conventional `~/.config` layout.
Use `AX_SKILLS_REGISTRY_PATH` only when explicitly testing another rendered registry.

Each registry entry declares `enabled`, `agents`, `presets`, `source`, and
`requires.commands`/`requires.mcp`. `presets: ["*"]` selects all machines with
the existing AI feature enabled. An explicit preset list further restricts
selection; it does not turn on the machine's AI feature. `agents` documents
tested compatibility; the common library is advertised to every linked agent.
Agent-specific filtering is not performed.

```json
{
  "source": {"type": "owned", "path": "release-check"},
  "enabled": true,
  "agents": ["claude", "codex", "omp", "opencode"],
  "presets": ["workstation", "t3"],
  "requires": {"commands": ["git"], "mcp": []}
}
```

Authored bundles live outside chezmoi deployment, so filenames such as
`run_eval.py` and `template.tmpl` are copied literally and executable bits are
preserved. The rendered registry records this checkout's absolute `ownedRoot`;
keep the source checkout available. Never store credentials in a skill.

## Updates and preserving edits

```bash
ax skills update frontend-design                 # resolve upstream HEAD to a commit
ax skills update frontend-design --ref <commit>  # choose a specific version
ax skills disable frontend-design
ax skills enable frontend-design
```

Review the registry diff, commit it, then apply or sync with `--source`. Ordinary
sync never follows a moving branch. Import/update validate the manifest before
recording a pin and do not run downloaded scripts. Archives with symlinks,
special files, or traversal paths are rejected. Bundles and their cache contents
are fingerprinted; concurrent mutations are serialized with a local lock.

`sync --dry-run` does not fetch or change installed files. Uncached Git bundles
must be downloaded by a regular sync/import first. Import/update dry runs may
resolve remote refs, but require the resolved bundle to be cached for validation.

Sync preflights every managed destination. It preserves unregistered skills and
refuses to replace modified bundles, symlinks, or unrelated files. Disabling a
skill removes only an unchanged bundle previously installed by ax. When an
installed skill was edited, preserve it explicitly:

```bash
ax skills save ~/.config/agents/skills/my-skill --replace
ax skills sync --source
```

`--replace` overwrites that skill's authored source, so review existing source
edits first. Saving an imported skill converts it to an owned skill; subsequent
upstream updates no longer apply. Migration adopts exact known former dotfiles
bundles and exact matches to the desired bundle. Unknown/older downloaded or
edited bundles are preserved and reported for an explicit save decision.

## Agent and T3 Code discovery

Codex discovers `~/.agents/skills`, Claude discovers `~/.claude/skills`, and OMP
discovers `~/.omp/agent/skills`; managed links point to the shared library.
OpenCode also discovers `~/.agents/skills`. The OMP gateway directory receives a
skill link when ax prepares it, because `PI_CODING_AGENT_DIR` changes its native
discovery location. Existing user paths are not overwritten by that gateway step.

T3 Code's provider-specific `CODEX_HOME` settings retain the home-wide Codex
library. Remote T3 provisioning runs chezmoi and the synchronization script;
the library, source checkout, cache, and ownership state live in its existing
persistent home volume. After an explicit remote dotfiles update, restart an
agent session if its skill list has not refreshed. No new agent wrappers or
dedicated skill-sync service are installed.

`doctor` checks manifests, cached revisions, authored/installed fingerprints,
discovery links, command dependencies, and stale selection. It lists MCP
dependencies for session verification; it cannot establish that a live
connector is authenticated or that an agent has loaded a skill. When nono is
available it probes the current process's library access, but a separate agent
launch profile still needs its own session check. Skills install no capability
grants. `what-skill` reads a catalog generated from the enabled registry and
also considers project/plugin skills advertised in the current session.

Official discovery references:
[Codex](https://learn.chatgpt.com/docs/build-skills),
[OMP](https://github.com/can1357/oh-my-pi/blob/main/docs/skills.md), and
[OpenCode](https://opencode.ai/docs/skills/).

## Validation

```bash
python3 dot_local/bin/tests/test_ax_skills.py
bash tests/test_machine_matrix.sh
bash dot_local/bin/tests/test_ax.sh
bash t3code/tests/test_stack.sh
```

The skill suite uses temporary homes and local Git remotes to cover saving,
selection, pinning, updates, tamper detection, collision protection, and safe
migration without touching an installed user library.
