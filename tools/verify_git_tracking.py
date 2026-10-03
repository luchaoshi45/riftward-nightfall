"""Read-only check for source files and resource inputs omitted from Git."""
from collections import Counter
import json
from pathlib import Path
import re
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE_FOLDERS = {"art_source", "assets", "scenes", "scripts", "tests", "tools", "coordination"}
GENERATED_FOLDERS = {".godot", ".tools", "build", "release", "tmp", "output", "devlog", "handoff"}
REQUIRED = {"AGENTS.md", "project.godot", "export_presets.cfg", "optimization-progress.json",
            "启动游戏.cmd", "LICENSES.md", "ASSETS.md", ".gitignore", ".gitattributes"}


def git_paths(*args):
    output = subprocess.check_output(["git", *args, "-z"], cwd=ROOT)
    return {value for value in output.decode("utf-8").split("\0") if value}


def resource_input(path, owner, tracked, problems):
    path = path.replace("\\", "/")
    if "%" in path or "*" in path or not Path(path).suffix:
        return  # A dynamic prefix or template, rather than a complete input.
    if path.split("/")[0] in GENERATED_FOLDERS:
        return  # Screenshots and test output are intentionally not source inputs.
    if path not in tracked:
        problems.append(f"未追踪资源: {owner} -> {path}")


def main():
    tracked = git_paths("ls-files")
    problems = [f"必要文件未追踪: {path}" for path in sorted(REQUIRED - tracked)]
    problems.extend(f"已追踪文件在本地缺失: {path}" for path in sorted(tracked)
                    if not (ROOT / path).is_file())
    problems.extend(f"新文件尚未加入Git，先核对用途: {path}"
                    for path in sorted(git_paths("ls-files", "--others", "--exclude-standard")))
    ignored = git_paths("ls-files", "--others", "--ignored", "--exclude-standard")
    for path in sorted(ignored):
        if path.split("/")[0] not in SOURCE_FOLDERS:
            continue
        if "/__pycache__/" in path or path.endswith((".blend1", ".blend2", ".pyc", ".log", ".pid", ".tmp")):
            continue
        problems.append(f"源码目录内文件被忽略，需核对规则: {path}")

    checked_resources = 0
    for relative in sorted(tracked):
        path = ROOT / relative
        if not path.is_file():
            continue
        if path.suffix in {".gd", ".tscn", ".tres", ".godot", ".gdshader"}:
            content = path.read_text(encoding="utf-8-sig")
            for value in re.findall(r"res://[^\"'\r\n]+", content):
                resource_input(value[6:], relative, tracked, problems)
                checked_resources += 1
        elif path.suffix == ".glb":
            data = path.read_bytes()
            if len(data) < 20 or data[:4] != b"glTF":
                problems.append(f"GLB未下载完整或头部无效: {relative}，检查Git LFS")
                continue
            length, kind = struct.unpack_from("<II", data, 12)
            if kind != 0x4E4F534A or 20 + length > len(data):
                problems.append(f"GLB JSON块无效: {relative}")
                continue
            document = json.loads(data[20:20 + length])
            for item in document.get("images", []) + document.get("buffers", []):
                uri = item.get("uri", "")
                if not uri or uri.startswith("data:"):
                    continue
                resolved = (path.parent / uri).resolve()
                if not resolved.is_relative_to(ROOT):
                    problems.append(f"GLB引用仓库外输入: {relative} -> {uri}")
                else:
                    resource_input(resolved.relative_to(ROOT).as_posix(), relative, tracked, problems)

    print(json.dumps({"tracked_files": len(tracked),
                      "source_counts": dict(sorted(Counter(path.split("/")[0] for path in tracked
                                                           if path.split("/")[0] in SOURCE_FOLDERS).items())),
                      "resource_references_checked": checked_resources, "problems": problems},
                     ensure_ascii=False, indent=2))
    if problems:
        return 1
    print("GIT_TRACKING_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
