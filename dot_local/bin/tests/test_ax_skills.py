"""Exercise the public ax skills CLI in isolated homes and Git repositories."""

import json
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
AX = ROOT / "dot_local/bin/executable_ax"


class SkillCommands(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.config = self.home / ".config"
        self.source = self.root / "source"
        self.owned = self.source / "skills/owned"
        self.library = self.config / "agents/skills"
        self.registry = {"version": 1, "skills": {}, "machine": {"preset": "t3", "ai": True}, "ownedRoot": str(self.owned)}
        self.env = {**os.environ, "HOME": str(self.home), "XDG_CONFIG_HOME": str(self.config),
                    "XDG_CACHE_HOME": str(self.home / ".cache"), "XDG_STATE_HOME": str(self.home / ".local/state"),
                    "AX_SKILLS_SOURCE_ROOT": str(self.source), "MISE_CACHE_DIR": str(self.root / "mise-cache"),
                    "MISE_STATE_DIR": str(self.root / "mise-state"), "MISE_DATA_DIR": str(self.root / "mise-data"),
                    "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}
        self.env.pop("AX_SKILLS_REGISTRY_PATH", None)
        self.env.pop("CODEX_HOME", None)
        self.env.pop("NONO_SESSION_ID", None)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        (bin_dir / "python3").symlink_to(Path(os.sys.executable).resolve())
        self.env["PATH"] = str(bin_dir) + os.pathsep + self.env["PATH"]
        self.skill("example")
        self.persist()

    def skill(self, name, description="Example workflow."):
        directory = self.owned / name
        directory.mkdir(parents=True)
        (directory / "SKILL.md").write_text(f"---\nname: {name}\ndescription: {description}\n---\n\nDo useful work.\n")
        self.registry["skills"][name] = {"source": {"type": "owned", "path": name}, "enabled": True,
            "agents": ["claude", "codex", "omp", "opencode"], "presets": ["*"], "requires": {"commands": [], "mcp": []}}
        return directory

    def persist(self):
        path = self.source / ".chezmoidata/ai-skills.yaml"
        path.parent.mkdir(parents=True, exist_ok=True)
        data = {k: v for k, v in self.registry.items() if k not in ("machine", "ownedRoot")}
        path.write_text(json.dumps({"aiSkills": data}))
        path = self.config / "ax/skills.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(self.registry))

    def cli(self, *args, ok=True):
        result = subprocess.run(["bash", str(AX), "skills", *args], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0 if ok else 78, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def source_registry(self):
        return json.loads((self.source / ".chezmoidata/ai-skills.yaml").read_text())["aiSkills"]

    def links(self):
        for path in (self.home / ".agents/skills", self.home / ".claude/skills", self.home / ".omp/agent/skills"):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.symlink_to(self.library, target_is_directory=True)

    def test_sync_idempotent_preserves_unmanaged_and_dry_run(self):
        self.assertIn("install: example", self.cli("sync", "--dry-run"))
        self.assertFalse(self.library.exists())
        self.cli("sync")
        self.skill("what-skill")
        self.persist()
        personal = self.library / "personal"
        personal.mkdir()
        (personal / "notes.txt").write_text("keep me")
        self.cli("sync")
        self.assertIn("example", (self.library / "what-skill/references/catalog.md").read_text())
        self.assertNotIn("install:", self.cli("sync"))
        self.assertEqual((personal / "notes.txt").read_text(), "keep me")
        self.links()
        self.assertIn("healthy", self.cli("doctor"))

    def test_preflight_preserves_all_bundles_on_collision(self):
        self.cli("sync")
        self.skill("another")
        self.persist()
        original = self.library / "example/SKILL.md"
        original.write_text(original.read_text() + "User edit\n")
        self.assertIn("edited or unmanaged", self.cli("sync", ok=False))
        self.assertFalse((self.library / "another").exists())
        self.assertIn("User edit", original.read_text())

    def test_sync_rejects_duplicate_manifest_before_installing(self):
        shutil.copytree(self.owned / "example", self.library / "personal-copy")
        self.assertIn("duplicate manifest name", self.cli("sync", ok=False))
        self.assertFalse((self.library / "example").exists())
        self.assertTrue((self.library / "personal-copy/SKILL.md").exists())

    def test_save_rolls_back_source_when_registry_write_fails(self):
        self.cli("sync")
        installed = self.library / "example/SKILL.md"
        original = (self.owned / "example/SKILL.md").read_text()
        installed.write_text(original + "Preserved user edit\n")
        registry_path = self.source / ".chezmoidata/ai-skills.yaml"
        before_registry = registry_path.read_text()
        # Compile directly to avoid writing Python cache files into the source tree.
        manager_path = ROOT / "dot_local/lib/ax/skills.py"
        manager_module = types.ModuleType("ax_skills")
        exec(compile(manager_path.read_text(), str(manager_path), "exec"), manager_module.__dict__)
        args = argparse.Namespace(command="save", directory=str(installed.parent), replace=True, dry_run=False)
        with patch.dict(os.environ, self.env), patch.object(manager_module, "write_json", side_effect=OSError("disk full")):
            with self.assertRaisesRegex(OSError, "disk full"):
                manager_module.Skills(args).mutate()
        self.assertEqual((self.owned / "example/SKILL.md").read_text(), original)
        self.assertEqual(registry_path.read_text(), before_registry)
        self.assertIn("Preserved user edit", installed.read_text())

    def render_sync_hook(self):
        shutil.copytree(ROOT / ".chezmoitemplates", self.source / ".chezmoitemplates", dirs_exist_ok=True)
        shutil.copy2(ROOT / ".chezmoidata/machine.yaml", self.source / ".chezmoidata/machine.yaml")
        manager = self.source / "dot_local/lib/ax/skills.py"
        manager.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "dot_local/lib/ax/skills.py", manager)
        result = subprocess.run(["chezmoi", "--source", str(self.source), "--config",
                                 str(ROOT / "examples/configs/linux-t3-arm64.json"), "execute-template"],
                                input=(ROOT / "run_onchange_after_sync-ai-skills.sh.tmpl").read_text(),
                                env=self.env, text=True, capture_output=True, check=True)
        return result.stdout

    def test_sync_hook_changes_for_payload_rename(self):
        asset = self.owned / "example/old.txt"
        asset.write_text("literal asset")
        before = self.render_sync_hook()
        asset.rename(asset.with_name("new.txt"))
        self.assertNotEqual(self.render_sync_hook(), before)

    def test_sync_hook_changes_for_executable_mode(self):
        asset = self.owned / "example/tool.sh"
        asset.write_text("#!/bin/sh\nexit 0\n")
        asset.chmod(0o644)
        before = self.render_sync_hook()
        asset.chmod(0o755)
        self.assertNotEqual(self.render_sync_hook(), before)

    def test_save_replace_preserves_edit_then_syncs(self):
        self.cli("sync")
        installed = self.library / "example/SKILL.md"
        installed.write_text(installed.read_text() + "User edit\n")
        self.cli("save", str(installed.parent), "--replace")
        self.assertIn("User edit", (self.owned / "example/SKILL.md").read_text())
        self.cli("sync", "--source")
        self.assertIn("User edit", installed.read_text())

    def test_save_what_skill_description_then_regenerates_catalog(self):
        self.skill("what-skill")
        self.persist()
        self.cli("sync")
        installed = self.library / "what-skill/SKILL.md"
        installed.write_text(installed.read_text().replace("Example workflow.", "Choose useful workflows."))
        self.cli("save", str(installed.parent), "--replace")
        self.cli("sync", "--source")
        self.assertIn("Choose useful workflows.", (installed.parent / "references/catalog.md").read_text())

    def test_save_does_not_silently_discard_edited_generated_catalog(self):
        self.skill("what-skill")
        self.persist()
        self.cli("sync")
        installed = self.library / "what-skill"
        catalog = installed / "references/catalog.md"
        catalog.write_text(catalog.read_text() + "Personal annotations\n")
        self.cli("save", str(installed), "--replace")
        self.cli("sync", "--source", ok=False)
        self.assertIn("Personal annotations", catalog.read_text())

    def test_disable_preserves_modified_skill_until_saved(self):
        self.cli("sync")
        path = self.library / "example/SKILL.md"
        path.write_text(path.read_text() + "edit\n")
        self.cli("disable", "example")
        self.cli("sync", "--source", ok=False)
        self.assertTrue(path.exists())

    def test_new_enable_disable_and_presets(self):
        self.cli("new", "another", "--dry-run")
        self.assertFalse((self.owned / "another").exists())
        self.cli("new", "another")
        self.cli("sync", "--source")
        self.assertTrue((self.library / "another/SKILL.md").exists())
        self.cli("disable", "another")
        self.cli("sync", "--source")
        self.assertFalse((self.library / "another").exists())
        self.cli("enable", "another")
        self.cli("sync", "--source")
        self.assertTrue((self.library / "another").exists())
        self.registry["skills"]["example"]["presets"] = ["workstation"]
        self.persist()
        self.cli("sync")
        self.assertFalse((self.library / "example").exists())

    def test_doctor_detects_changed_authored_bundle(self):
        self.cli("sync")
        self.links()
        path = self.owned / "example/SKILL.md"
        path.write_text(path.read_text() + "updated\n")
        self.assertIn("authored bundle differs", self.cli("doctor", ok=False))

    def test_missing_dependency_and_discovery_link(self):
        self.registry["skills"]["example"]["requires"]["commands"] = ["ax-command-that-does-not-exist"]
        self.persist()
        self.cli("sync")
        output = self.cli("doctor", ok=False)
        self.assertIn("required command missing", output)
        self.assertIn("native discovery link missing", output)

    def test_rejects_traversal_duplicate_and_symlinks(self):
        self.cli("new", "../escape", ok=False)
        self.cli("new", "example", ok=False)
        link = self.owned / "example/external"
        link.symlink_to(self.root)
        self.assertIn("symlinks", self.cli("sync", ok=False))
        link.unlink()
        self.registry["skills"]["example"]["source"]["path"] = "../escape"
        self.persist()
        self.assertIn("unsafe skill path", self.cli("sync", ok=False))

    def test_adopts_exact_legacy_bundle_but_preserves_changed_bundle(self):
        shutil.copytree(self.owned / "example", self.library / "example")
        self.cli("sync")
        self.assertTrue((self.home / ".local/state/ax/skills.json").exists())

    def test_floating_git_revision_rejected_before_fetch(self):
        self.registry["skills"]["example"]["source"] = {"type": "git", "url": "https://skills.invalid/repo", "path": "skills/example", "revision": "main"}
        self.persist()
        self.assertIn("full commit SHA", self.cli("sync", ok=False))

    def test_save_preserves_payload_names_and_modes(self):
        scripts = self.owned / "example/scripts"
        scripts.mkdir()
        (scripts / "run_eval.py").write_text("print('payload')\n")
        self.persist()
        self.cli("sync", "--source")
        self.assertTrue((self.library / "example/scripts/run_eval.py").exists())
        script = self.library / "example/scripts/run_eval.py"
        script.chmod(0o755)
        asset = self.library / "example/template.tmpl"
        asset.write_text("{{ keep this literal }}\n")
        self.cli("save", str(asset.parent), "--replace")
        self.assertTrue((self.owned / "example/template.tmpl").exists())
        self.assertTrue((self.owned / "example/scripts/run_eval.py").exists())
        self.cli("sync", "--source")
        self.assertTrue(script.stat().st_mode & 0o111)
        self.assertEqual(asset.read_text(), "{{ keep this literal }}\n")

    def test_refuses_symlinked_library(self):
        other = self.root / "other"
        other.mkdir()
        self.library.parent.mkdir(parents=True)
        self.library.symlink_to(other, target_is_directory=True)
        self.assertIn("symlinked library", self.cli("sync", ok=False))
        self.assertEqual(list(other.iterdir()), [])

    def test_migrates_known_legacy_name_and_preserves_unknown_edits(self):
        self.library.mkdir(parents=True)
        legacy = self.library / "old-example"
        shutil.copytree(self.owned / "example", legacy)
        self.registry["skills"]["example"]["legacyNames"] = ["old-example"]
        self.persist()
        self.cli("sync")
        self.assertFalse(legacy.exists())
        self.assertTrue((self.library / "example").exists())
        shutil.copytree(self.owned / "example", legacy)
        (legacy / "SKILL.md").write_text((legacy / "SKILL.md").read_text() + "changed\n")
        self.assertIn("edited legacy skill", self.cli("sync", ok=False))
        self.assertTrue(legacy.exists())

    def test_doctor_detects_duplicate_manifest_names(self):
        self.cli("sync")
        self.links()
        shutil.copytree(self.library / "example", self.library / "another-directory")
        self.assertIn("duplicate manifest name", self.cli("doctor", ok=False))

    def test_repository_deployment_and_full_owned_library(self):
        arguments = ["chezmoi", "--source", str(ROOT), "--destination", str(self.home),
                     "--config", str(ROOT / "examples/configs/linux-t3-arm64.json"),
                     "--cache", str(self.root / "chezmoi-cache"),
                     "--persistent-state", str(self.root / "chezmoistate.boltdb")]
        targets = [str(self.home / path) for path in
                   (".local/bin/ax", ".local/lib/ax", ".config/ax/skills.json", ".agents/skills", ".claude/skills", ".omp/agent/skills")]
        before = (self.config / "ax/skills.json").read_text()
        subprocess.run([*arguments, "apply", "--exclude=scripts", "--dry-run", *targets],
                       env=self.env, capture_output=True, text=True, check=True)
        self.assertEqual((self.config / "ax/skills.json").read_text(), before)
        for target in targets:
            Path(target).parent.mkdir(parents=True, exist_ok=True)
        applied = subprocess.run([*arguments, "apply", "--exclude=scripts", *targets], env=self.env, capture_output=True, text=True)
        self.assertEqual(applied.returncode, 0, applied.stdout + applied.stderr)
        registry_path = self.config / "ax/skills.json"
        registry = json.loads(registry_path.read_text())
        self.assertEqual(registry["ownedRoot"], str(ROOT / "skills/owned"))
        for item in registry["skills"].values():
            if item["source"]["type"] == "git":
                item["enabled"] = False  # Remote downloads have separate offline Git tests.
        registry_path.write_text(json.dumps(registry))
        deployed = subprocess.run([str(self.home / ".local/bin/ax"), "skills", "sync"],
                                  env=self.env, capture_output=True, text=True)
        self.assertEqual(deployed.returncode, 0, deployed.stdout + deployed.stderr)
        self.assertTrue((self.library / "skill-creator/scripts/run_eval.py").exists())
        self.assertTrue((self.library / "diagnosing-bugs/SKILL.md").exists())
        self.assertIn("healthy", self.cli("doctor"))
        managed = subprocess.run([*arguments, "managed", "--refresh-externals=never"], env=self.env,
                                 capture_output=True, text=True, check=True).stdout.splitlines()
        self.assertFalse(any(path.startswith("skills/") for path in managed))

    def test_migration_from_actual_pre_manager_deployment(self):
        if subprocess.run(["git", "-C", str(ROOT), "cat-file", "-e", "17dede9^{commit}"],
                          capture_output=True).returncode:
            self.skipTest("fetch pre-manager commit 17dede9 to exercise historical migration")
        legacy_source = self.root / "legacy-source"
        legacy_source.mkdir()
        # The historical source includes literal_ names and an empty __init__.py;
        # use chezmoi itself rather than assuming the deployed tree matches Git.
        archive = subprocess.run(["git", "-C", str(ROOT), "archive", "17dede9", "dot_config/agents/skills"],
                                 capture_output=True, check=True).stdout
        subprocess.run(["tar", "-xf", "-", "-C", str(legacy_source)], input=archive, check=True)
        subprocess.run(["chezmoi", "--source", str(legacy_source), "--destination", str(self.home),
                        "--config", str(ROOT / "examples/configs/linux-t3-arm64.json"),
                        "--cache", str(self.root / "legacy-cache"),
                        "--persistent-state", str(self.root / "legacy-state.boltdb"), "apply"],
                       env=self.env, capture_output=True, text=True, check=True)
        self.assertFalse((self.library / "skill-creator/scripts/__init__.py").exists())
        self.registry = json.loads((ROOT / ".chezmoidata/ai-skills.yaml").read_text())["aiSkills"]
        self.registry.update(machine={"preset": "t3", "ai": True}, ownedRoot=str(ROOT / "skills/owned"))
        for item in self.registry["skills"].values():
            if item["source"]["type"] == "git":
                item["enabled"] = False
        self.persist()
        self.cli("sync")
        self.assertTrue((self.library / "skill-creator/scripts/__init__.py").exists())
        self.assertTrue((self.library / "diagnosing-bugs/SKILL.md").exists())
        self.assertFalse((self.library / "diagnose").exists())

    def fixture_remote(self):
        repo = self.root / "upstream"
        repo.mkdir()
        def git(*args):
            return subprocess.run([shutil.which("git"), "-C", str(repo), *args], env=self.env, check=True, capture_output=True, text=True).stdout.strip()
        git("init", "--quiet")
        path = repo / "skills/remote"
        path.mkdir(parents=True)
        (path / "SKILL.md").write_text("---\nname: remote\ndescription: Remote workflow.\n---\n\nVersion one.\n")
        git("add", ".")
        git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false", "commit", "-m", "one")
        first = git("rev-parse", "HEAD")
        bin_dir = self.root / "bin"
        bin_dir.mkdir(exist_ok=True)
        # Redirect a test HTTPS URL to a real local Git repository, keeping real
        # fetch/archive/revision behavior while the suite remains fully offline.
        wrapper = bin_dir / "git"
        wrapper.write_text("#!/usr/bin/env python3\nimport os,sys\nargs=[os.environ['AX_TEST_REMOTE'] if a == 'https://skills.invalid/repo' else a for a in sys.argv[1:]]\nos.execv(os.environ['AX_TEST_GIT'], [os.environ['AX_TEST_GIT'], *args])\n")
        wrapper.chmod(0o755)
        self.env["AX_TEST_REMOTE"] = str(repo)
        self.env["AX_TEST_GIT"] = shutil.which("git")
        self.env["PATH"] = str(bin_dir) + os.pathsep + self.env["PATH"]
        return path, first, git

    def test_import_pinning_cache_update_and_tamper_detection(self):
        path, first, git = self.fixture_remote()
        self.cli("import", "https://skills.invalid/repo", "--path", "skills/remote")
        self.assertEqual(self.source_registry()["skills"]["remote"]["source"]["revision"], first)
        self.cli("sync", "--source")
        (path / "SKILL.md").write_text((path / "SKILL.md").read_text() + "Version two.\n")
        git("add", ".")
        git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false", "commit", "-m", "two")
        self.cli("sync", "--source")
        self.assertNotIn("Version two", (self.library / "remote/SKILL.md").read_text())
        self.cli("update", "remote")
        self.cli("sync", "--source")
        self.assertIn("Version two", (self.library / "remote/SKILL.md").read_text())
        for cached in (self.home / ".cache/ax/skills").glob("*/skill/SKILL.md"):
            cached.write_text(cached.read_text() + "tampered\n")
        self.assertIn("cache was modified", self.cli("sync", "--source", ok=False))

    def test_git_archive_symlink_rejected(self):
        path, _, git = self.fixture_remote()
        (path / "outside").symlink_to("../../outside")
        git("add", ".")
        git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false", "commit", "-m", "symlink")
        self.assertIn("unsupported archive entry", self.cli("import", "https://skills.invalid/repo", "--path", "skills/remote", ok=False))
        self.assertNotIn("remote", self.source_registry()["skills"])


if __name__ == "__main__":
    unittest.main()
