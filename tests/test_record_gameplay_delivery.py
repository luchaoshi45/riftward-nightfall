"""Isolated registration acceptance; fixture logs are not native Windows proof.

Every CLI and API call targets a TemporaryDirectory repository. The production
script is copied there before use; no real counter, launcher, or document is
ever passed to the registration function. Faults exercise actual filesystem
commit boundaries, not copies of the implementation's transformation rules.
"""
from __future__ import annotations

import codecs
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import uuid


SOURCE = Path(__file__).resolve().parents[1] / "tools" / "record_gameplay_delivery.py"
TARGETS = ("optimization-progress.json", "启动游戏.cmd", "README.md", "AGENTS.md")
OLD_LAUNCH_VERSION = "0.8.25"
PREVIOUS = "0.8.37"
VERSION = "0.8.38"
LABEL = f"Riftward_Nightfall_v{VERSION}"
RENDER = "fixture_render"
NAME = "隔离登记测试"
VERIFICATION = "合成临时证据；不代表Windows原生验收"
RENDER_HEADER = "Metal 4.0 - Forward+ - Using Device #0: Apple - Apple M5 (Apple9)"
NATIVE_FIXTURE_PATH = rf"C:\Synthetic acceptance fixture\build\{LABEL}.exe"
MARKER = "<!-- VERIFIED_GAMEPLAY_DELIVERIES -->"
README_HISTORY = "历史回执：0.8.25与0.8.37曾使用build/Riftward_Nightfall_v0.8.25.exe，逐字保留。"
AGENTS_HISTORY = "历史：本机0.8.25和源码0.8.37；| 47 | 0.8.37 | 旧验收 | 保留 |"
AGENTS_WINDOWS_HISTORY = "- 完整游戏验证/Windows版本：当前源码0.8.37、47/100，Windows成品仍为0.8.25；本轮未生成新Windows交付，不计入100次目标。"
CURRENT_BASELINE = "- 最新已验证源码版：0.8.37，完成47/100；Windows成品基线仍为0.8.25，具体新功能和验收见本轮交付表。"
CURRENT_PROJECT = "- 远端初始导入为0.8.17，本机最新已验证源码版为0.8.37，完成47/100；原介绍保留0.8.25与0.8.37。Windows成品基线仍为0.8.25；后续版本、已验证进度以 `optimization-progress.json` 为准。"


class RepositoryFixture:
    def __init__(self, base: Path, source_bytes: bytes):
        self.root = base / "repo"
        self.outside = base / "outside"
        self.root.mkdir()
        self.outside.mkdir()
        (self.root / "tools").mkdir()
        self.script = self.root / "tools" / "record_gameplay_delivery.py"
        self.script.write_bytes(source_bytes)
        self.build = self.root / "build"
        self.build.mkdir()
        self.set_progress()
        self.set_launcher()
        self.set_readme()
        self.set_agents()
        self.executable = self.build / f"{LABEL}.exe"
        self.executable.write_bytes(b"MZ synthetic fixture only; not a Windows executable")
        self.logs = [
            self.build / f"export-{LABEL}.log",
            self.build / f"startup-{LABEL}.out.log",
            self.build / f"startup-{LABEL}.err.log",
            self.build / f"{RENDER}-render.out.log",
            self.build / f"{RENDER}-render.err.log",
            self.build / f"nightfall_loop-packaged-{LABEL}.log",
        ]
        for index, path in enumerate(self.logs):
            path.write_bytes(b"" if index in (2, 4) else b"SYNTHETIC_FIXTURE_OK\n")
        self.logs[3].write_text(RENDER_HEADER + f"\nSYNTHETIC_FIXTURE_ONLY\n{RENDER.upper()}_OK\n", encoding="utf-8")
        self.logs[5].write_bytes(b"SYNTHETIC_FIXTURE_ONLY\nNIGHTFALL_LOOP_OK\n")
        self.native_receipt = self.build / f"verified-{LABEL}.log"
        self.set_native_receipt()
        self.logs.append(self.native_receipt)

    def set_native_receipt(self, version=VERSION, executable=NATIVE_FIXTURE_PATH, close_exit=0):
        text = ("SYNTHETIC_FIXTURE_ONLY: this receipt is not Windows execution evidence\n"
                f"Windows startup and close exit: {close_exit}\n"
                f"VERIFIED_WINDOWS_BUILD {version} {executable}\n")
        self.native_receipt.write_text(text, encoding="utf-8")

    def set_progress(self, completed=47, target=100, version=PREVIOUS, bom=False, newline="\n"):
        value = {
            "target": target,
            "completed": completed,
            "latest_version": version,
            "latest_improvement": "旧登记",
            "verification": "旧证据",
            "retained_extension": {"note": "retain this unrelated field"},
        }
        text = json.dumps(value, ensure_ascii=False, indent=2).replace("\n", newline) + newline
        self.write_text("optimization-progress.json", text, bom)

    def set_launcher(self, version=OLD_LAUNCH_VERSION, second=None, bom=False, newline="\r\n"):
        second = version if second is None else second
        lines = [
            "@echo off",
            'cd /d "%~dp0"',
            f'if exist "build\\Riftward_Nightfall_v{version}.exe" (',
            f'    start "" "build\\Riftward_Nightfall_v{second}.exe"',
            ") else (",
            "    echo 保留0.8.25和0.8.37的无关帮助文字.",
            "    pause",
            ")",
        ]
        self.write_text("启动游戏.cmd", newline.join(lines) + newline, bom)

    def set_readme(self, version=OLD_LAUNCH_VERSION, bom=False, newline="\n", export=False):
        lines = [
            "# 临时仓库 · 不是Windows交付",
            "",
            f"最新已验证Windows版本为{version}，完成35/100，以 [optimization-progress.json](optimization-progress.json) 为准。旧介绍。",
            "",
            f"开发及本版成品使用4.7.2。`启动游戏.cmd` 已指向{version}；旧兼容包只作历史记录。",
            f"本机有成品时双击 `启动游戏.cmd` 或 `build/Riftward_Nightfall_v{version}.exe`。",
            "",
            "## 历史回执",
            README_HISTORY,
        ]
        if export:
            lines.insert(6, f"godot --headless --export-release 'Windows Desktop' build/Riftward_Nightfall_v{version}.exe")
        self.write_text("README.md", newline.join(lines) + newline, bom)

    def set_agents(self, bom=False, newline="\n", current=False):
        lines = [
            "# 临时交接",
            "",
            AGENTS_HISTORY,
            "",
            "## 主机A验收历史",
            AGENTS_WINDOWS_HISTORY,
            "",
        ]
        if current:
            lines.extend([
                "## 项目与当前状态",
                CURRENT_PROJECT,
                "",
                "## 当前共同基线",
                CURRENT_BASELINE,
                "保留当前段落中的无关0.8.25和0.8.37。",
                "",
            ])
        lines.extend([
            "## 本轮已验收的玩法交付",
            "| 计数 | 版本 | 改进 | 验证 |",
            "| --- | --- | --- | --- |",
            "| 47 | 0.8.37 | 旧登记 | 原样历史 |",
            MARKER,
            "",
            "## 主机A当前工作",
            "保留这个无关段落与所有历史版本。",
        ])
        self.write_text("AGENTS.md", newline.join(lines) + newline, bom)

    def reset_current_delivery_targets(self):
        self.set_progress()
        self.set_launcher()
        self.set_readme()
        self.set_agents(current=True)

    def write_text(self, name: str, text: str, bom=False):
        (self.root / name).write_bytes((codecs.BOM_UTF8 if bom else b"") + text.encode("utf-8"))

    def snapshot(self):
        return {name: (self.root / name).read_bytes() if (self.root / name).is_file() else None for name in TARGETS}

    def run(self, version=VERSION, render_test=RENDER):
        return subprocess.run(
            [sys.executable, str(self.script), "--version", version, "--name", NAME,
             "--verification", VERIFICATION, "--render-test", render_test],
            cwd=self.outside, capture_output=True, text=True, timeout=20,
        )

    def module(self):
        name = f"isolated_record_delivery_{uuid.uuid4().hex}"
        spec = importlib.util.spec_from_file_location(name, self.script)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module


class RecordDeliveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source_bytes = SOURCE.read_bytes()

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="record-delivery-acceptance-")
        self.addCleanup(self.directory.cleanup)
        self.repo = RepositoryFixture(Path(self.directory.name), self.source_bytes)

    def reject(self, *, version=VERSION, render_test=RENDER):
        before = self.repo.snapshot()
        result = self.repo.run(version=version, render_test=render_test)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("RECORDED_DELIVERY", result.stdout)
        self.assertEqual(self.repo.snapshot(), before, "A rejected registration changed a target's bytes")
        return result

    def success(self, count=48, target=100, render_test=RENDER):
        result = self.repo.run(render_test=render_test)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"RECORDED_DELIVERY {VERSION} {count}/{target}", result.stdout)
        progress = json.loads((self.repo.root / TARGETS[0]).read_text(encoding="utf-8-sig"))
        self.assertEqual((progress["completed"], progress["target"], progress["latest_version"]), (count, target, VERSION))
        self.assertEqual(progress["latest_improvement"], NAME)
        self.assertEqual(progress["verification"], VERIFICATION)
        self.assertEqual(progress["retained_extension"], {"note": "retain this unrelated field"})
        launcher = (self.repo.root / "启动游戏.cmd").read_text(encoding="utf-8-sig")
        self.assertEqual(launcher.count(f"Riftward_Nightfall_v{VERSION}.exe"), 2)
        self.assertIn("echo 保留0.8.25和0.8.37的无关帮助文字.", launcher)
        readme = (self.repo.root / "README.md").read_text(encoding="utf-8-sig")
        self.assertIn(f"最新已验证Windows版本为{VERSION}，完成{count}/{target}", readme)
        self.assertIn(f"`启动游戏.cmd` 已指向{VERSION}", readme)
        self.assertIn(f"本机有成品时双击 `启动游戏.cmd` 或 `build/Riftward_Nightfall_v{VERSION}.exe`。", readme)
        self.assertIn(README_HISTORY, readme)
        agents = (self.repo.root / "AGENTS.md").read_text(encoding="utf-8-sig")
        self.assertEqual(agents.count(MARKER), 1)
        self.assertIn(f"| {count} | {VERSION} | {NAME} |", agents)
        self.assertIn(VERIFICATION, agents)
        self.assertIn(AGENTS_HISTORY, agents)
        self.assertIn(AGENTS_WINDOWS_HISTORY, agents)
        self.assertIn("| 47 | 0.8.37 | 旧登记 | 原样历史 |", agents)
        return progress

    def test_source_counter_and_stale_launcher_are_synchronized(self):
        self.success()

    def test_launcher_already_matches_source_version(self):
        self.repo.set_launcher(PREVIOUS)
        self.repo.set_readme(PREVIOUS)
        self.success()

    def test_utf8_bom_and_crlf_preserved_for_all_targets(self):
        self.repo.set_progress(bom=True, newline="\r\n")
        self.repo.set_launcher(bom=True, newline="\r\n")
        self.repo.set_readme(bom=True, newline="\r\n")
        self.repo.set_agents(bom=True, newline="\r\n")
        self.success()
        for name in TARGETS:
            with self.subTest(name=name):
                content = (self.repo.root / name).read_bytes()
                self.assertTrue(content.startswith(codecs.BOM_UTF8))
                self.assertIn(b"\r\n", content)
                self.assertNotIn(b"\n", content.replace(b"\r\n", b""))

    def test_plain_utf8_and_lf_preserved(self):
        self.repo.set_launcher(newline="\n")
        self.success()
        for name in TARGETS:
            with self.subTest(name=name):
                content = (self.repo.root / name).read_bytes()
                self.assertFalse(content.startswith(codecs.BOM_UTF8))
                self.assertNotIn(b"\r\n", content)

    def test_real_target_is_used_in_output_and_summary(self):
        self.repo.set_progress(completed=59, target=60)
        self.success(count=60, target=60)

    def test_optional_export_command_updates_current_executable_only(self):
        self.repo.set_readme(export=True)
        self.success()
        readme = (self.repo.root / "README.md").read_text()
        self.assertIn(f"godot --headless --export-release 'Windows Desktop' build/{LABEL}.exe", readme)
        self.assertIn(README_HISTORY, readme)

    def test_launcher_references_different_versions(self):
        self.repo.set_launcher(second="0.8.26")
        self.reject()

    def test_launcher_has_no_matching_executable(self):
        self.repo.write_text("启动游戏.cmd", "@echo off\r\necho no product reference\r\n")
        self.reject()

    def test_launcher_has_only_one_executable_reference(self):
        path = self.repo.root / "启动游戏.cmd"
        content = path.read_bytes().replace(b'    start "" "build\\Riftward_Nightfall_v0.8.25.exe"\r\n', b"    echo incomplete launcher\r\n")
        path.write_bytes(content)
        self.reject()

    def test_launcher_has_extra_matching_reference(self):
        path = self.repo.root / "启动游戏.cmd"
        path.write_bytes(path.read_bytes() + b"rem build\\Riftward_Nightfall_v0.8.25.exe\r\n")
        self.reject()

    def test_launcher_commands_must_share_the_complete_build_path(self):
        for changed_command in ("start_only", "both"):
            with self.subTest(changed_command=changed_command):
                self.repo.set_launcher()
                path = self.repo.root / "启动游戏.cmd"
                content = path.read_bytes()
                if changed_command == "start_only":
                    content = content.replace(b'start "" "build\\', b'start "" "archive\\')
                else:
                    content = content.replace(b'"build\\', b'"archive\\')
                path.write_bytes(content)
                self.reject()

    def test_missing_launcher(self):
        (self.repo.root / "启动游戏.cmd").unlink()
        self.reject()

    def test_missing_readme(self):
        (self.repo.root / "README.md").unlink()
        self.reject()

    def test_missing_agents(self):
        (self.repo.root / "AGENTS.md").unlink()
        self.reject()

    def test_missing_progress(self):
        (self.repo.root / "optimization-progress.json").unlink()
        self.reject()

    def test_duplicate_agents_marker(self):
        path = self.repo.root / "AGENTS.md"
        path.write_bytes(path.read_bytes() + MARKER.encode() + b"\n")
        self.reject()

    def test_missing_agents_marker(self):
        path = self.repo.root / "AGENTS.md"
        path.write_bytes(path.read_bytes().replace(MARKER.encode(), b""))
        self.reject()

    def test_current_agents_sections_update_only_authoritative_fields(self):
        self.repo.set_agents(bom=True, newline="\r\n", current=True)
        self.success()
        content = (self.repo.root / "AGENTS.md").read_bytes()
        self.assertTrue(content.startswith(codecs.BOM_UTF8))
        self.assertNotIn(b"\n", content.replace(b"\r\n", b""))
        expected_baseline = "- 最新已验证源码版：0.8.38，完成48/100；Windows成品基线仍为0.8.38，具体新功能和验收见本轮交付表。"
        expected_project = "- 远端初始导入为0.8.17，本机最新已验证源码版为0.8.38，完成48/100；原介绍保留0.8.25与0.8.37。Windows成品基线仍为0.8.38；后续版本、已验证进度以 `optimization-progress.json` 为准。"
        self.assertIn((expected_baseline + "\r\n").encode(), content)
        self.assertIn((expected_project + "\r\n").encode(), content)
        self.assertIn((AGENTS_WINDOWS_HISTORY + "\r\n").encode(), content)
        self.assertIn("保留当前段落中的无关0.8.25和0.8.37。\r\n".encode(), content)

    def test_current_agents_section_requires_authoritative_line(self):
        for line in (CURRENT_BASELINE, CURRENT_PROJECT):
            with self.subTest(line=line):
                self.repo.reset_current_delivery_targets()
                path = self.repo.root / "AGENTS.md"
                path.write_bytes(path.read_bytes().replace(line.encode(), b""))
                self.reject()

    def test_current_agents_authoritative_line_must_be_unique(self):
        for line in (CURRENT_BASELINE, CURRENT_PROJECT):
            with self.subTest(line=line):
                self.repo.reset_current_delivery_targets()
                path = self.repo.root / "AGENTS.md"
                path.write_bytes(path.read_bytes().replace(line.encode(), (line + "\n" + line).encode()))
                self.reject()

    def test_current_agents_fields_cannot_be_missing(self):
        removals = [(PREVIOUS, ""), ("完成47/100", "完成/100"),
                    ("完成47/100", "完成47/"), ("Windows成品基线仍为0.8.25", "Windows成品基线仍为")]
        for line in (CURRENT_BASELINE, CURRENT_PROJECT):
            for old, missing in removals:
                with self.subTest(line=line, field=old, missing=missing):
                    self.repo.reset_current_delivery_targets()
                    path = self.repo.root / "AGENTS.md"
                    changed = line.replace(old, missing, 1)
                    path.write_bytes(path.read_bytes().replace(line.encode(), changed.encode()))
                    self.reject()

    def test_current_agents_fields_must_match_source_and_launcher(self):
        mismatches = [(PREVIOUS, "0.8.36"), ("完成47/100", "完成46/100"),
                      ("完成47/100", "完成47/99"), ("Windows成品基线仍为0.8.25", "Windows成品基线仍为0.8.26")]
        for line in (CURRENT_BASELINE, CURRENT_PROJECT):
            for old, different in mismatches:
                with self.subTest(line=line, field=old, different=different):
                    self.repo.reset_current_delivery_targets()
                    path = self.repo.root / "AGENTS.md"
                    changed = line.replace(old, different, 1)
                    path.write_bytes(path.read_bytes().replace(line.encode(), changed.encode()))
                    self.reject()

    def test_readme_current_version_disagrees_with_launcher(self):
        self.repo.set_readme("0.8.26")
        self.reject()

    def test_duplicate_readme_current_summary(self):
        path = self.repo.root / "README.md"
        path.write_bytes(path.read_bytes() + "最新已验证Windows版本为0.8.25，完成35/100。\n".encode())
        self.reject()

    def test_readme_without_current_usage(self):
        path = self.repo.root / "README.md"
        path.write_text("\n".join(line for line in path.read_text().splitlines() if not line.startswith("本机有成品时")) + "\n")
        self.reject()

    def test_missing_executable(self):
        self.repo.executable.unlink()
        self.reject()

    def test_missing_each_required_log(self):
        for path in self.repo.logs:
            with self.subTest(log=path.name):
                content = path.read_bytes()
                path.unlink()
                self.reject()
                path.write_bytes(content)

    def test_confirmed_error_markers_in_every_evidence_log(self):
        markers = [b"ERROR: synthetic failure\n", b"SCRIPT ERROR: synthetic failure\n",
                   b"WARNING: 3 objects leaked at exit\n", b"WARNING: Resource still in use\n"]
        for path in self.repo.logs:
            original = path.read_bytes()
            for marker in markers:
                with self.subTest(log=path.name, marker=marker):
                    path.write_bytes(original + b"\n" + marker)
                    self.reject()
            path.write_bytes(original)

    def test_render_completion_marker_is_required(self):
        self.repo.logs[3].write_bytes(b"Render started but did not complete\n")
        self.reject()

    def test_packaged_completion_marker_is_required(self):
        self.repo.logs[5].write_bytes(b"Package test started but did not complete\n")
        self.reject()

    def test_empty_startup_logs_without_native_receipt_are_rejected(self):
        self.repo.logs[1].write_bytes(b"")
        self.repo.logs[2].write_bytes(b"")
        self.repo.native_receipt.unlink()
        self.reject()

    def test_native_close_exit_must_be_zero(self):
        for close_exit in (1, -1, 259):
            with self.subTest(close_exit=close_exit):
                self.repo.set_native_receipt(close_exit=close_exit)
                self.reject()

    def test_native_marker_must_match_version_and_executable(self):
        cases = [
            (PREVIOUS, NATIVE_FIXTURE_PATH),
            (VERSION, rf"C:\Synthetic acceptance fixture\build\Riftward_Nightfall_v{PREVIOUS}.exe"),
            (VERSION, r"C:\Synthetic acceptance fixture\build\Other_Product.exe"),
            (VERSION, NATIVE_FIXTURE_PATH + ".backup"),
            (VERSION, f"{LABEL}.exe"),
            (VERSION, rf"build\{LABEL}.exe"),
            (VERSION, f"/Users/synthetic-fixture/build/{LABEL}.exe"),
        ]
        for version, executable in cases:
            with self.subTest(version=version, executable=executable):
                self.repo.set_native_receipt(version=version, executable=executable)
                self.reject()

    def test_native_close_and_completion_lines_must_be_unique(self):
        for duplicate in ("Windows startup and close exit: 0", f"VERIFIED_WINDOWS_BUILD {VERSION} {NATIVE_FIXTURE_PATH}"):
            with self.subTest(duplicate=duplicate):
                self.repo.set_native_receipt()
                content = self.repo.native_receipt.read_bytes()
                self.repo.native_receipt.write_bytes(content + (duplicate + "\n").encode())
                self.reject()

    def test_export_or_arbitrary_ok_does_not_replace_native_receipt(self):
        receipts = [
            "Mac export completed\nSYNTHETIC_FIXTURE_OK\n",
            "SYNTHETIC_FIXTURE_OK\n",
            f"VERIFIED_WINDOWS_BUILD {VERSION} {NATIVE_FIXTURE_PATH}\n",
            "Windows startup and close exit: 0\nSYNTHETIC_FIXTURE_OK\n",
            f"example: Windows startup and close exit: 0\nexample: VERIFIED_WINDOWS_BUILD {VERSION} {NATIVE_FIXTURE_PATH}\n",
        ]
        for receipt in receipts:
            with self.subTest(receipt=receipt):
                self.repo.native_receipt.write_text(receipt, encoding="utf-8")
                self.reject()

    def test_night_loop_packaged_evidence_is_required(self):
        self.repo.logs[5].unlink()
        (self.repo.build / f"arbitrary-packaged-{LABEL}.log").write_bytes(b"ARBITRARY_TEST_OK\n")
        self.reject()

    def test_night_loop_requires_its_own_success_line(self):
        for marker in ("OTHER_TEST_OK", "example: NIGHTFALL_LOOP_OK", "NIGHTFALL_LOOP_OK_extra", "TEXT_NIGHTFALL_LOOP_OK"):
            with self.subTest(marker=marker):
                self.repo.logs[5].write_text("SYNTHETIC_FIXTURE_ONLY\n" + marker + "\n", encoding="utf-8")
                self.reject()

    def test_render_requires_the_selected_scripts_success_line(self):
        for marker in ("OTHER_TEST_OK", f"example: {RENDER.upper()}_OK", f"{RENDER.upper()}_OK_extra", f"{RENDER.upper()}_OK_FALSE", f"TEXT_{RENDER.upper()}_OK"):
            with self.subTest(marker=marker):
                self.repo.logs[3].write_text(RENDER_HEADER + "\nSYNTHETIC_FIXTURE_ONLY\n" + marker + "\n", encoding="utf-8")
                self.reject()

    def test_render_accepts_real_completion_details(self):
        render_test = "nightfall_attack_visual"
        output = self.repo.build / f"{render_test}-render.out.log"
        errors = self.repo.build / f"{render_test}-render.err.log"
        self.repo.logs[3].rename(output)
        self.repo.logs[4].rename(errors)
        self.repo.logs[3], self.repo.logs[4] = output, errors
        completion = ("NIGHTFALL_ATTACK_VISUAL_OK contact=140ms sequence critical kills3 "
                      'fixed_camera F2 movement silent_mix {"synthetic_fixture":true}\n')
        output.write_text(RENDER_HEADER + "\nSYNTHETIC_FIXTURE_ONLY\n" + completion, encoding="utf-8")
        self.success(render_test=render_test)

    def test_render_requires_a_device_header_besides_completion(self):
        headers = [
            "",
            "Godot Engine v4.7.2.stable.official - https://godotengine.org\n",
            "Godot Engine v4.7.2.stable.official - Headless\n",
            "Headless - Using Device: Dummy\n",
        ]
        for header in headers:
            with self.subTest(header=header):
                self.repo.logs[3].write_text(header + f"{RENDER.upper()}_OK\n", encoding="utf-8")
                self.reject()

    def test_powershell_utf16_bom_evidence_is_supported(self):
        for path in self.repo.logs:
            text = path.read_text(encoding="utf-8")
            path.write_bytes(codecs.BOM_UTF16_LE + text.encode("utf-16-le"))
        self.success()

    def test_repeated_version_is_rejected(self):
        self.reject(version=PREVIOUS)

    def test_skip_or_malformed_version_is_rejected(self):
        for version in ("0.8.39", "0.8.-1", "../0.8.38", "0.8.38-extra", "0.8.38/anything"):
            with self.subTest(version=version):
                self.reject(version=version)

    def test_full_target_does_not_record(self):
        self.repo.set_progress(completed=100, target=100)
        self.reject()

    def test_negative_counter_does_not_record(self):
        self.repo.set_progress(completed=-1)
        self.reject()

    def test_traversal_and_absolute_render_stems_are_rejected(self):
        for stem in ("../escape", "../../outside/evidence", str(self.repo.outside / "absolute"), "build/fixture_render", "fixture_render\\other"):
            with self.subTest(stem=stem):
                self.reject(render_test=stem)

    def test_executable_symlink_outside_repository_is_rejected(self):
        outside = self.repo.outside / "product.exe"
        outside.write_bytes(self.repo.executable.read_bytes())
        self.repo.executable.unlink()
        self.repo.executable.symlink_to(outside)
        before = outside.read_bytes()
        self.reject()
        self.assertEqual(outside.read_bytes(), before)

    def test_evidence_symlink_outside_repository_is_rejected(self):
        for path in self.repo.logs:
            with self.subTest(log=path.name):
                content = path.read_bytes()
                outside = self.repo.outside / path.name
                outside.write_bytes(content)
                path.unlink()
                path.symlink_to(outside)
                self.reject()
                self.assertEqual(outside.read_bytes(), content)
                path.unlink()
                path.write_bytes(content)

    def test_build_directory_symlink_outside_repository_is_rejected(self):
        outside_build = self.repo.outside / "build"
        shutil.move(str(self.repo.build), outside_build)
        self.repo.build.symlink_to(outside_build, target_is_directory=True)
        before = {path.name: path.read_bytes() for path in outside_build.iterdir()}
        self.reject()
        self.assertEqual({path.name: path.read_bytes() for path in outside_build.iterdir()}, before)

    def test_evidence_symlink_inside_repo_but_outside_build_is_rejected(self):
        storage = self.repo.root / "unverified-evidence"
        storage.mkdir()
        for path in [self.repo.executable] + self.repo.logs:
            with self.subTest(evidence=path.name):
                content = path.read_bytes()
                stored = storage / path.name
                stored.write_bytes(content)
                path.unlink()
                path.symlink_to(stored)
                self.reject()
                self.assertEqual(stored.read_bytes(), content)
                path.unlink()
                path.write_bytes(content)

    def test_build_directory_symlink_inside_repo_is_rejected(self):
        stored_build = self.repo.root / "unverified-build"
        shutil.move(str(self.repo.build), stored_build)
        self.repo.build.symlink_to(stored_build, target_is_directory=True)
        before = {path.name: path.read_bytes() for path in stored_build.iterdir()}
        self.reject()
        self.assertEqual({path.name: path.read_bytes() for path in stored_build.iterdir()}, before)

    def test_target_symlink_outside_repository_is_rejected(self):
        for name in TARGETS:
            with self.subTest(target=name):
                path = self.repo.root / name
                content = path.read_bytes()
                outside = self.repo.outside / name
                outside.write_bytes(content)
                path.unlink()
                path.symlink_to(outside)
                self.reject()
                self.assertEqual(outside.read_bytes(), content)
                path.unlink()
                path.write_bytes(content)

    def test_import_has_no_argparse_or_registration_side_effect(self):
        before = self.repo.snapshot()
        with mock.patch.object(sys, "argv", ["unrelated-program", "--unknown"]):
            module = self.repo.module()
        self.assertTrue(callable(module.record_delivery))
        self.assertEqual(self.repo.snapshot(), before)

    def test_api_returns_only_the_updated_fixture_progress(self):
        module = self.repo.module()
        result = module.record_delivery(self.repo.root, VERSION, NAME, VERIFICATION, RENDER)
        on_disk = json.loads((self.repo.root / TARGETS[0]).read_text(encoding="utf-8-sig"))
        self.assertEqual(result, on_disk)
        self.assertEqual(result["completed"], 48)

    def test_first_atomic_replace_io_failure_changes_no_target(self):
        module = self.repo.module()
        before = self.repo.snapshot()
        original_replace = os.replace
        injected = []

        def fail_once(source, destination, *args, **kwargs):
            if Path(destination).name in TARGETS and not injected:
                injected.append(Path(destination).name)
                raise OSError("Injected first target replace failure")
            return original_replace(source, destination, *args, **kwargs)

        with mock.patch.object(os, "replace", side_effect=fail_once):
            with self.assertRaises(OSError):
                module.record_delivery(self.repo.root, VERSION, NAME, VERIFICATION, RENDER)
        self.assertTrue(injected, "The fault did not reach a real atomic target replacement")
        self.assertEqual(self.repo.snapshot(), before)

    def test_late_atomic_replace_io_failure_rolls_back_prior_writes(self):
        module = self.repo.module()
        before = self.repo.snapshot()
        original_replace = os.replace
        commits = []
        injected = []

        def fail_third(source, destination, *args, **kwargs):
            if Path(destination).name in TARGETS and not injected:
                commits.append(Path(destination).name)
                if len(commits) == 3:
                    injected.append(Path(destination).name)
                    raise OSError("Injected third target replace failure")
            return original_replace(source, destination, *args, **kwargs)

        with mock.patch.object(os, "replace", side_effect=fail_third):
            with self.assertRaises(OSError):
                module.record_delivery(self.repo.root, VERSION, NAME, VERIFICATION, RENDER)
        self.assertEqual(len(commits), 3, "The fault must follow two actual committed targets")
        self.assertTrue(injected)
        self.assertEqual(self.repo.snapshot(), before, "A late I/O failure left a partial registration")

    def test_concurrent_edit_is_preserved_and_other_targets_roll_back(self):
        module = self.repo.module()
        before = self.repo.snapshot()
        original_replace = os.replace
        injected = []
        external = before["README.md"] + "外部并发编辑：必须保留。\n".encode()

        def external_edit_before_first_commit(source, destination, *args, **kwargs):
            if Path(destination).name in TARGETS and not injected:
                chosen = "README.md" if Path(destination).name != "README.md" else "AGENTS.md"
                content = before[chosen] + "外部并发编辑：必须保留。\n".encode()
                (self.repo.root / chosen).write_bytes(content)
                injected.append((chosen, content))
            return original_replace(source, destination, *args, **kwargs)

        with mock.patch.object(os, "replace", side_effect=external_edit_before_first_commit):
            with self.assertRaises((ValueError, OSError, RuntimeError)):
                module.record_delivery(self.repo.root, VERSION, NAME, VERIFICATION, RENDER)
        self.assertEqual(len(injected), 1)
        chosen, content = injected[0]
        expected = dict(before)
        expected[chosen] = content
        self.assertEqual(self.repo.snapshot(), expected, "Concurrency handling overwrote external work or retained other partial writes")


if __name__ == "__main__":
    unittest.main(verbosity=2)
