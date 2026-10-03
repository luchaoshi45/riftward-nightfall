"""Protect intentional import edits and staged work during a legacy rewrite repair."""
import importlib.util
from pathlib import Path
import shutil
import os
import stat
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("repair", ROOT / "tools/repair_godot_import_rewrites.py")
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)
BASELINE = b"[params]\nnodes/root_scale=1.0\n" + b"".join(repair.DEFAULTS)


class ImportRepairTests(unittest.TestCase):
    def setUp(self):
        self.build = (ROOT / "build").resolve()
        self.build.mkdir(exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix="import-repair-fixture-", dir=self.build)).resolve()
        self.root.relative_to(self.build)
        self.git("init", "-q")
        self.git("config", "user.name", "Import repair fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "core.autocrlf", "false")
        (self.root / "assets/models").mkdir(parents=True)
        self.model = self.root / "assets/models/model.glb.import"
        self.model.write_bytes(BASELINE)
        self.git("add", "assets/models/model.glb.import")
        self.git("commit", "-qm", "fixture baseline")
        self.automatic = BASELINE
        for option in repair.DEFAULTS:
            self.automatic = self.automatic.replace(option, b"")

    def tearDown(self):
        # Delete only this newly created fixture, never a computed repository root.
        self.root.resolve().relative_to(self.build)
        if not self.root.name.startswith("import-repair-fixture-"):
            raise RuntimeError("Unexpected cleanup target")
        def writable_retry(function, path, _):
            Path(path).resolve().relative_to(self.root)
            os.chmod(path, stat.S_IWRITE)
            function(path)
        shutil.rmtree(self.root, onerror=writable_retry)

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, stderr=subprocess.STDOUT)

    def run_repair(self, **kwargs):
        kwargs.setdefault("session_reader", lambda _: [])
        return repair.repair(self.root, **kwargs)

    def test_exact_rewrite_backup_restore_and_idempotence(self):
        self.model.write_bytes(self.automatic.replace(b"\n", b"\r\n"))
        before = self.model.read_bytes()
        preview = self.run_repair()
        self.assertEqual(preview["automatic_rewrites"], 1)
        self.assertEqual(self.model.read_bytes(), before)
        result = self.run_repair(apply=True)
        self.assertEqual(result["restored"], 1)
        with zipfile.ZipFile(result["backup"]) as backup:
            self.assertEqual(backup.read("assets/models/model.glb.import"), before)
        self.assertEqual(self.model.read_bytes(), BASELINE)
        self.assertEqual(self.git("status", "--porcelain"), b"?? build/\n")
        self.assertEqual(self.run_repair(apply=True)["restored"], 0)

    def test_manual_settings_and_staged_rewrites_are_preserved(self):
        manual = self.automatic.replace(b"root_scale=1.0", b"root_scale=2.0")
        self.model.write_bytes(manual)
        self.assertEqual(self.run_repair(apply=True)["restored"], 0)
        self.assertEqual(self.model.read_bytes(), manual)
        self.model.write_bytes(self.automatic)
        self.git("add", "assets/models/model.glb.import")
        index_before = self.git("diff", "--cached")
        self.assertEqual(self.run_repair(apply=True)["restored"], 0)
        self.assertEqual(self.model.read_bytes(), self.automatic)
        self.assertEqual(self.git("diff", "--cached"), index_before)

    def test_active_editor_blocks_without_restoring(self):
        self.model.write_bytes(self.automatic)
        with self.assertRaisesRegex(RuntimeError, "close editors"):
            self.run_repair(apply=True, session_reader=lambda _: [{"ProcessId": 123}])
        self.assertEqual(self.model.read_bytes(), self.automatic)
        self.assertFalse((self.root / "build").exists())

    def test_new_manual_edit_and_new_editor_during_backup_are_preserved(self):
        self.model.write_bytes(self.automatic)
        manual = self.automatic + b"nodes/root_name=HumanEdit\n"
        with self.assertRaisesRegex(RuntimeError, "Concurrent edit"):
            self.run_repair(apply=True, before_write=lambda: self.model.write_bytes(manual))
        self.assertEqual(self.model.read_bytes(), manual)
        self.model.write_bytes(self.automatic)
        queries = iter([[], [{"ProcessId": 124}]])
        with self.assertRaisesRegex(RuntimeError, "editor opened"):
            self.run_repair(apply=True, session_reader=lambda _: next(queries))
        self.assertEqual(self.model.read_bytes(), self.automatic)


if __name__ == "__main__":
    unittest.main()
