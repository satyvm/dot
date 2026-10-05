#!/usr/bin/env python3
"""Declarative skill management for ax. Uses Python's stdlib, Git and chezmoi."""

import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

AGENTS = ("claude", "codex", "omp", "opencode")
NAME = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
REVISION = re.compile(r"[0-9a-f]{40}\Z")


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs).stdout.strip()


def read_json(path):
    return json.loads(path.read_text())


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        temp = Path(stream.name)
        json.dump(data, stream, indent=2, sort_keys=True)
        stream.write("\n")
    try:
        temp.replace(path)
    finally:
        temp.unlink(missing_ok=True)


def relative(value):
    if not isinstance(value, str) or not value or value.startswith("-"):
        raise ValueError(f"invalid relative skill path: {value!r}")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or ".git" in path.parts:
        raise ValueError(f"unsafe skill path: {value}")
    return value


def validate(registry):
    if registry.get("version") != 1 or not isinstance(registry.get("skills"), dict):
        raise ValueError("expected skills registry version 1")
    for name, item in registry["skills"].items():
        if not NAME.fullmatch(name):
            raise ValueError(f"invalid skill name: {name}")
        if not isinstance(item.get("enabled"), bool):
            raise ValueError(f"{name}: enabled must be boolean")
        agents = item.get("agents", [])
        presets = item.get("presets", [])
        if not isinstance(agents, list) or not agents or any(a not in AGENTS for a in agents):
            raise ValueError(f"{name}: unknown or empty agents")
        if not isinstance(presets, list) or not presets or any(p not in ("*", "legacy", "minimal", "workstation", "server", "container", "t3") for p in presets):
            raise ValueError(f"{name}: unknown or empty presets")
        for key in ("commands", "mcp"):
            values = item.get("requires", {}).get(key, [])
            if not isinstance(values, list) or any(not isinstance(v, str) or not v for v in values):
                raise ValueError(f"{name}: requires.{key} must contain strings")
        source = item["source"]
        relative(source["path"])
        if source["type"] == "git":
            if not REVISION.fullmatch(source.get("revision", "")):
                raise ValueError(f"{name}: Git source must pin a full commit SHA")
            url = source.get("url", "")
            if not isinstance(url, str) or not url.startswith("https://"):
                raise ValueError(f"{name}: Git source must use an HTTPS URL")
        elif source["type"] != "owned":
            raise ValueError(f"{name}: unsupported source type")
    return registry


def manifest(directory):
    text = (directory / "SKILL.md").read_text()
    parts = re.split(r"^---\s*$", text, maxsplit=2, flags=re.MULTILINE)
    if len(parts) != 3 or parts[0].strip():
        raise ValueError(f"{directory}: SKILL.md needs YAML front matter")
    # Reuse chezmoi's YAML parser; no extra Python dependencies or partial YAML parser.
    template = "{{ " + json.dumps(parts[1], ensure_ascii=False) + " | fromYaml | toJson }}"
    metadata = json.loads(run("chezmoi", "execute-template", input=template))
    if not isinstance(metadata, dict) or not isinstance(metadata.get("name"), str) or not NAME.fullmatch(metadata["name"]):
        raise ValueError(f"{directory}: invalid manifest name")
    if not isinstance(metadata.get("description"), str) or not metadata["description"].strip():
        raise ValueError(f"{directory}: description is required")
    return metadata


def files(directory):
    """Validate symlink containment and reject special files before copying."""
    root = directory.resolve(strict=True)
    for parent, dirs, names in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in (".git", "__pycache__"))
        for name in sorted(dirs + names):
            path = Path(parent) / name
            if path.is_symlink():
                raise ValueError(f"skill bundles must not contain symlinks: {path}")
            if not path.is_file() and not path.is_dir():
                raise ValueError(f"unsupported special file: {path}")
        for name in sorted(names):
            path = Path(parent) / name
            if name.endswith(".pyc"):
                continue
            yield path.relative_to(root), path


def digest(directory):
    checksum = hashlib.sha256()
    entries = []
    for relative_path, path in files(directory):
        entries.append((relative_path, path))
    for relative_path, path in sorted(entries, key=lambda entry: str(entry[0])):
        checksum.update(str(relative_path).encode() + b"\0")
        checksum.update(str(path.stat().st_mode & 0o111).encode() + b"\0")
        checksum.update(path.read_bytes() + b"\0")
    return checksum.hexdigest()


def copy_bundle(source, target):
    for relative_path, path in files(source):
        destination = target / relative_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, destination)


class Skills:
    def __init__(self, args):
        self.args = args
        self.home = Path.home()
        self.config = Path(os.environ.get("XDG_CONFIG_HOME", self.home / ".config"))
        self.library = self.config / "agents/skills"
        self.cache = Path(os.environ.get("XDG_CACHE_HOME", self.home / ".cache")) / "ax/skills"
        self.state = Path(os.environ.get("XDG_STATE_HOME", self.home / ".local/state")) / "ax/skills.json"
        self.deployed = Path(os.environ.get("AX_SKILLS_REGISTRY_PATH", self.config / "ax/skills.json"))

    def source_root(self):
        root = os.environ.get("AX_SKILLS_SOURCE_ROOT")
        return Path(root if root else run("chezmoi", "source-path")).resolve(strict=True)

    def load(self, source=False):
        if source:
            root = self.source_root()
            registry = read_json(root / ".chezmoidata/ai-skills.yaml")["aiSkills"]
            machine = read_json(self.deployed).get("machine", {}) if self.deployed.exists() else {}
            registry["machine"] = machine
            owned = root / "skills/owned"
        else:
            registry = read_json(self.deployed)
            owned = Path(registry["ownedRoot"])
        if not registry.get("machine"):
            raise ValueError("machine selection missing; run chezmoi apply before syncing")
        return validate(registry), owned

    def selected(self, registry):
        machine = registry["machine"]
        return {name: item for name, item in registry["skills"].items()
                if machine["ai"] and item["enabled"] and
                ("*" in item["presets"] or machine["preset"] in item["presets"])}

    def checkout(self, source, fetch=True):
        key = hashlib.sha256(json.dumps(source, sort_keys=True).encode()).hexdigest()
        destination = self.cache / key
        if destination.exists():
            recorded = read_json(destination / "metadata.json")
            if recorded["source"] != source or digest(destination / "skill") != recorded["digest"]:
                raise ValueError(f"download cache was modified: {destination}; remove this cache entry and retry")
            return destination / "skill"
        if not fetch:
            raise ValueError(f"commit {source['revision']} is not cached; run ax skills sync")
        self.cache.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=self.cache) as temporary:
            temporary = Path(temporary)
            repo = temporary / "repo"
            run("git", "init", "--quiet", str(repo))
            run("git", "-C", str(repo), "fetch", "--quiet", "--depth=1", "--", source["url"], source["revision"])
            commit = run("git", "-C", str(repo), "rev-parse", "FETCH_HEAD")
            if commit != source["revision"]:
                raise ValueError("downloaded commit does not match the registry")
            archive = temporary / "skill.tar"
            run("git", "-C", str(repo), "archive", "--format=tar", "-o", str(archive), commit, "--", source["path"])
            extracted = temporary / "extracted"
            extracted.mkdir()
            with tarfile.open(archive) as stream:
                members = stream.getmembers()
                for member in members:
                    relative(member.name)
                    if not member.isfile() and not member.isdir():
                        raise ValueError(f"unsupported archive entry: {member.name}")
                # Every member above is a validated relative regular file/directory.
                # Do not require extractall(filter=...), absent in older Debian Python.
                stream.extractall(extracted, members=members)
            staging = temporary / "staging"
            staging.mkdir()
            copy_bundle(extracted / source["path"], staging / "skill")
            write_json(staging / "metadata.json", {"source": source, "digest": digest(staging / "skill")})
            staging.rename(destination)
        return destination / "skill"

    def bundles(self, registry, owned, fetch):
        result = {}
        for name, item in sorted(self.selected(registry).items()):
            source = item["source"]
            path = owned / source["path"] if source["type"] == "owned" else self.checkout(source, fetch)
            if source["type"] == "owned" and not path.resolve().is_relative_to(owned.resolve()):
                raise ValueError(f"owned skill escapes source directory: {name}")
            metadata = manifest(path)
            if metadata["name"] != name:
                raise ValueError(f"{name}: manifest name is {metadata['name']}; names must match")
            digest(path)
            result[name] = (path, metadata)
        return result

    def list(self):
        registry, _ = self.load(self.args.source)
        selected = self.selected(registry)
        if self.args.json:
            print(json.dumps(registry, indent=2))
            return
        print("NAME\tSTATUS\tSOURCE\tAGENTS")
        for name, item in sorted(registry["skills"].items()):
            source = item["source"]
            revision = source.get("revision", "owned")
            print(f"{name}\t{'enabled' if name in selected else 'disabled'}\t{revision}\t{','.join(item['agents'])}")

    def sync(self):
        registry, owned = self.load(self.args.source)
        # A dry run never fetches or changes persistent state. Missing cache entries are reported.
        bundles = self.bundles(registry, owned, fetch=not self.args.dry_run)
        if self.library.is_symlink():
            raise ValueError(f"refusing to manage a symlinked library: {self.library}")
        previous = read_json(self.state) if self.state.exists() else {"skills": {}}
        selected = self.selected(registry)
        catalog = "# Enabled skills\n\n" + "\n".join(
            f"- **{name}**: {metadata['description'].strip()} (agents: {', '.join(selected[name]['agents'])})"
            for name, (_, metadata) in bundles.items()) + "\n"
        with tempfile.TemporaryDirectory(prefix="ax-skills-") as temporary:
            staging = Path(temporary)
            desired = {}
            for name, (path, _) in bundles.items():
                copy_bundle(path, staging / name)
                if name == "what-skill":
                    reference = staging / name / "references/catalog.md"
                    reference.parent.mkdir(parents=True, exist_ok=True)
                    reference.write_text(catalog)
                desired[name] = {"digest": digest(staging / name), "bundleDigest": digest(path), "source": selected[name]["source"]}
            actions = []
            for name, item in selected.items():
                for legacy_name in item.get("legacyNames", []):
                    if not NAME.fullmatch(legacy_name) or legacy_name in desired:
                        raise ValueError(f"invalid legacy name: {legacy_name}")
                    target = self.library / legacy_name
                    if target.exists() or target.is_symlink():
                        if target.is_symlink() or not target.is_dir():
                            raise ValueError(f"unmanaged legacy path: {target}")
                        if digest(target) not in item.get("legacyDigests", []) + [desired[name]["bundleDigest"]]:
                            raise ValueError(f"edited legacy skill: {target}; save it with ax skills save --replace before syncing")
                        actions.append((legacy_name, "remove"))
            # Preflight everything before changing any installed bundle.
            for name in sorted(set(previous["skills"]) | set(desired)):
                if not NAME.fullmatch(name):
                    raise ValueError("invalid installed skill state")
                target = self.library / name
                before = previous["skills"].get(name, {}).get("digest")
                after = desired.get(name, {}).get("digest")
                if target.is_symlink() or (target.exists() and not target.is_dir()):
                    raise ValueError(f"refusing to replace unmanaged path: {target}")
                current = digest(target) if target.exists() else None
                if current is not None and current not in (before, after):
                    # Migration may adopt the exact former chezmoi bundle before adding its catalog.
                    original = digest(bundles[name][0]) if name in bundles else None
                    legacy = selected.get(name, {}).get("legacyDigests", [])
                    if before is not None or (current != original and current not in legacy):
                        raise ValueError(f"edited or unmanaged skill: {target}; save it with ax skills save before syncing")
                if current != after:
                    actions.append((name, "install" if after else "remove"))
            for name, action in actions:
                print(f"{action}: {name}")
            if self.args.dry_run:
                return
            self.library.mkdir(parents=True, exist_ok=True)
            for name, action in dict(actions).items():
                target = self.library / name
                if action == "remove":
                    shutil.rmtree(target)
                else:
                    with tempfile.TemporaryDirectory(prefix=".ax-", dir=self.library) as temporary_bundle:
                        prepared = Path(temporary_bundle) / "skill"
                        copy_bundle(staging / name, prepared)
                        backup = Path(temporary_bundle) / "previous"
                        if target.exists():
                            target.rename(backup)
                        try:
                            prepared.rename(target)
                        except OSError:
                            if backup.exists():
                                backup.rename(target)
                            raise
            write_json(self.state, {"version": 1, "skills": desired})
            print(f"skills: synchronized {len(desired)} bundles; unmanaged skills preserved")

    def mutate(self):
        root = self.source_root()
        registry_path = root / ".chezmoidata/ai-skills.yaml"
        document = read_json(registry_path)
        registry = validate(document["aiSkills"])
        items = registry["skills"]
        command = self.args.command
        if command in ("enable", "disable", "update"):
            name = self.args.name
            if name not in items:
                raise ValueError(f"unknown skill: {name}")
            if command == "update":
                source = items[name]["source"]
                if source["type"] != "git":
                    raise ValueError("owned skills are edited in the source repository")
                new_source = {**source, "revision": self.resolve(source["url"], self.args.ref)}
                metadata = manifest(self.checkout(new_source, fetch=not self.args.dry_run))
                if metadata["name"] != name:
                    raise ValueError("updated manifest name differs from registered name")
                print(f"{name}: {source['revision']} -> {new_source['revision']}")
                items[name]["source"] = new_source
            else:
                items[name]["enabled"] = command == "enable"
        else:
            if command == "new":
                name = self.args.name
                bundle = None
                source = {"type": "owned", "path": name}
            elif command == "save":
                bundle = Path(self.args.directory).resolve(strict=True)
                name = manifest(bundle)["name"]
                digest(bundle)
                source = {"type": "owned", "path": name}
            else:
                source = {"type": "git", "url": self.args.url, "path": relative(self.args.path),
                          "revision": self.resolve(self.args.url, self.args.ref)}
                # Validate URL and commit before making a network request.
                validate({"version": 1, "skills": {"import": self.entry(source)}})
                bundle = self.checkout(source, fetch=not self.args.dry_run)
                name = manifest(bundle)["name"]
            if not NAME.fullmatch(name):
                raise ValueError(f"invalid skill name: {name}")
            if name in items and not (command == "save" and self.args.replace):
                raise ValueError(f"already registered: {name}; use save --replace to preserve an edited skill")
            target = root / "skills/owned" / name
            if target.is_symlink():
                raise ValueError(f"refusing to replace symlinked source: {target}")
            if source["type"] == "owned" and target.exists() and not (command == "save" and self.args.replace):
                raise ValueError(f"source directory already exists: {target}")
            items[name] = {**items.get(name, self.entry(source)), "source": source}
            if not self.args.dry_run and source["type"] == "owned":
                with tempfile.TemporaryDirectory(prefix="ax-save-") as temporary:
                    prepared = Path(temporary) / "skill"
                    if bundle:
                        copy_bundle(bundle, prepared)
                        # The installed catalog is generated, not authored content.
                        if name == "what-skill":
                            (prepared / "references/catalog.md").unlink(missing_ok=True)
                    else:
                        prepared.mkdir()
                        (prepared / "SKILL.md").write_text(
                            f"---\nname: {name}\ndescription: Describe when to use this skill.\n---\n\n# {name}\n\nDescribe the workflow.\n")
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if target.exists():
                        shutil.rmtree(target)
                    shutil.copytree(prepared, target)
                    print(f"source: {target}")
        validate(registry)
        if not self.args.dry_run:
            write_json(registry_path, document)
        print(f"{'preview' if self.args.dry_run else 'registered'}: {command}; review git diff, then run chezmoi apply")

    @staticmethod
    def entry(source):
        return {"source": source, "enabled": True, "agents": list(AGENTS), "presets": ["*"],
                "requires": {"commands": [], "mcp": []}}

    @staticmethod
    def resolve(url, ref):
        if not url.startswith("https://"):
            raise ValueError("imports require an HTTPS Git URL")
        if ref.startswith("-"):
            raise ValueError("invalid Git ref")
        if REVISION.fullmatch(ref):
            return ref
        candidates = (ref, f"refs/heads/{ref}", f"refs/tags/{ref}", f"refs/tags/{ref}^{{}}")
        output = run("git", "ls-remote", "--", url, *candidates)
        matches = [line.split() for line in output.splitlines()]
        if not matches:
            raise ValueError(f"Git ref not found: {ref}")
        peeled = [sha for sha, name in matches if name.endswith("^{}")]
        revisions = set(peeled or [sha for sha, _ in matches])
        if len(revisions) != 1:
            raise ValueError(f"ambiguous Git ref: {ref}; use a full commit SHA")
        return revisions.pop()

    def doctor(self):
        registry, owned = self.load(self.args.source)
        problems = []
        previous = read_json(self.state) if self.state.exists() else {"skills": {}}
        selected = self.selected(registry)
        discovered = {}
        if self.library.exists():
            for directory in sorted(self.library.iterdir()):
                if directory.is_dir() and (directory / "SKILL.md").exists():
                    metadata = manifest(directory)
                    identity = metadata["name"]
                    if identity in discovered:
                        problems.append(f"duplicate manifest name {identity}: {discovered[identity]} and {directory}")
                    discovered[identity] = directory
        for name, item in sorted(selected.items()):
            try:
                source = item["source"]
                path = owned / source["path"] if source["type"] == "owned" else self.checkout(source, fetch=False)
                if manifest(path)["name"] != name:
                    raise ValueError("manifest name differs from registered name")
                installed = self.library / name
                if not installed.exists() or digest(installed) != previous["skills"].get(name, {}).get("digest"):
                    raise ValueError("missing or modified installed skill; run sync or save your edits")
                if previous["skills"][name]["source"] != source:
                    raise ValueError("installed revision differs from registry; run sync")
                if previous["skills"][name].get("bundleDigest") != digest(path):
                    raise ValueError("authored bundle differs from installed version; run sync")
                for command in item["requires"]["commands"]:
                    if not shutil.which(command):
                        raise ValueError(f"required command missing: {command}")
                print(f"ok: {name} ({','.join(item['agents'])})")
                for server in item["requires"]["mcp"]:
                    print(f"check: {name} requires MCP {server}; verify it in the agent session")
                if set(item["agents"]) != set(AGENTS):
                    print(f"check: {name} is advertised in a shared library; use only with its listed agents")
            except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
                problems.append(f"{name}: {error}")
        for name in sorted(set(previous["skills"]) - set(selected)):
            problems.append(f"{name}: no longer selected; run sync")
        for agent, path in (("codex", self.home / ".agents/skills"),
                            ("claude", self.home / ".claude/skills"),
                            ("omp", self.home / ".omp/agent/skills")):
            if not path.exists() or path.resolve() != self.library.resolve():
                problems.append(f"{agent}: native discovery link missing or points elsewhere: {path}")
            else:
                print(f"ok: {agent} discovery link")
        print("check: OpenCode discovers the shared .agents/skills library")
        if os.environ.get("CODEX_HOME"):
            print("check: CODEX_HOME is set; Codex skills use the user .agents/skills library")
        if shutil.which("nono"):
            result = subprocess.run(["nono", "why", "--self", "--path", str(self.library), "--op", "read"], text=True, capture_output=True)
            if result.returncode == 0 and "DENIED" in result.stdout:
                problems.append(f"nono denies reading {self.library}; restart nono with the needed capability")
            else:
                print("check: sandbox readability must be verified in the agent's launch profile")
        if problems:
            raise ValueError("\n".join(problems))
        print("skills: healthy; discovery links checked, live agent/MCP behavior requires a session check")


def main():
    parser = argparse.ArgumentParser(prog="ax skills", description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("list", "sync", "doctor"):
        child = commands.add_parser(name)
        child.add_argument("--source", action="store_true", help="use the chezmoi source registry and owned bundles")
        if name == "list":
            child.add_argument("--json", action="store_true")
        if name == "sync":
            child.add_argument("--dry-run", action="store_true", help="read-only preview; Git bundles must already be cached")
    for name in ("new", "save", "import", "enable", "disable", "update"):
        child = commands.add_parser(name)
        child.add_argument("--dry-run", action="store_true")
        if name == "save":
            child.add_argument("directory")
            child.add_argument("--replace", action="store_true", help="replace the registered source with this bundle")
        elif name == "import":
            child.add_argument("url")
            child.add_argument("--path", required=True)
            child.add_argument("--ref", default="HEAD")
        else:
            child.add_argument("name")
            if name == "update":
                child.add_argument("--ref", default="HEAD")
    args = parser.parse_args()
    manager = Skills(args)
    try:
        with contextlib.ExitStack() as stack:
            if args.command not in ("list", "doctor") and not args.dry_run:
                manager.state.parent.mkdir(parents=True, exist_ok=True)
                lock = stack.enter_context((manager.state.parent / "skills.lock").open("a"))
                fcntl.flock(lock, fcntl.LOCK_EX)
            if args.command in ("list", "sync", "doctor"):
                getattr(manager, args.command)()
            else:
                manager.mutate()
    except (ValueError, OSError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
        print(f"ax skills: {detail}", file=sys.stderr)
        return 78
    return 0


if __name__ == "__main__":
    sys.exit(main())
