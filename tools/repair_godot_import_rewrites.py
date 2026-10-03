"""Restore only a proven legacy importer rewrite; retain other work and its index."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEFAULTS = (
    b"mesh_library/use_node_names_as_mesh_names=false\n",
    b"array_mesh/deduplicate_surfaces=true\n",
    b"gltf/texture_map_mode=0\n",
)


def git(root, *args):
    return subprocess.check_output(["git", *args], cwd=root)


def paths(root, *args):
    return [value.decode("utf-8") for value in git(root, args[0], "-z", *args[1:]).split(b"\0") if value]


def editor_sessions(root):
    module = ROOT / "tools/godot_editor_session.ps1"
    quote = lambda value: "'" + str(value).replace("'", "''") + "'"
    command = ("$ErrorActionPreference='Stop'; . " + quote(module)
               + "; $sessions=@(Get-NightfallEditorSessions -WorkspacePath " + quote(root)
               + "); ConvertTo-Json -InputObject $sessions -Depth 4 -Compress")
    # Encoding is explicitly set for the JSON channel, including Chinese paths.
    command = "[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); " + command
    output = subprocess.check_output(
        ["powershell.exe", "-NoLogo", "-NoProfile", "-Command", command], cwd=root)
    return json.loads(output.decode("utf-8-sig").strip() or "[]")


def audit(root):
    root = root.resolve()
    head = git(root, "rev-parse", "HEAD").decode("ascii").strip()
    staged = set(paths(root, "diff", "--cached", "--name-only", "--", "assets/models/*.glb.import"))
    modified = paths(root, "diff", "--name-only", "HEAD", "--", "assets/models/*.glb.import")
    candidates, preserved = [], []
    for relative in modified:
        target = (root / relative).resolve()
        target.relative_to((root / "assets/models").resolve())
        if relative in staged:
            preserved.append({"path": relative, "reason": "staged changes"})
            continue
        if not target.is_file():
            preserved.append({"path": relative, "reason": "missing file"})
            continue
        before = target.read_bytes()
        wanted = git(root, "show", "HEAD:" + relative)
        normalized = wanted.replace(b"\r\n", b"\n")
        if any(normalized.count(option) != 1 for option in DEFAULTS):
            preserved.append({"path": relative, "reason": "baseline has different options"})
            continue
        automatic = normalized
        for option in DEFAULTS:
            automatic = automatic.replace(option, b"")
        if before.replace(b"\r\n", b"\n") != automatic:
            preserved.append({"path": relative, "reason": "other edits"})
            continue
        candidates.append({"path": relative, "target": target, "before": before, "wanted": wanted})
    return head, candidates, preserved


def repair(root, apply=False, session_reader=editor_sessions, before_write=None):
    root = root.resolve()
    head, candidates, preserved = audit(root)
    sessions = session_reader(root)
    report = {"head": head, "automatic_rewrites": len(candidates), "preserved": preserved,
              "active_editors": sessions, "restored": 0, "backup": None}
    if not apply or not candidates:
        return report
    # Even a matching editor must finish saving/importing before a restore.
    if sessions:
        raise RuntimeError("Save and close editors for this project first. No files were restored.")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    backup = root / "build" / ("godot-import-repair-" + stamp + ".zip")
    backup.parent.mkdir(parents=True, exist_ok=True)
    manifest = {"head": head, "files": [
        {"path": entry["path"], "before_sha256": hashlib.sha256(entry["before"]).hexdigest(),
         "restored_sha256": hashlib.sha256(entry["wanted"]).hexdigest()}
        for entry in candidates]}
    with zipfile.ZipFile(backup, "x", zipfile.ZIP_DEFLATED) as archive:
        for entry in candidates:
            archive.writestr(entry["path"], entry["before"])
        archive.writestr("manifest.json", json.dumps(manifest, indent=2))
    with zipfile.ZipFile(backup) as archive:
        for entry in candidates:
            if archive.read(entry["path"]) != entry["before"]:
                raise RuntimeError("Backup verification failed; source files are unchanged.")
    if before_write:
        before_write()
    if git(root, "rev-parse", "HEAD").decode("ascii").strip() != head:
        raise RuntimeError("Repository changed during repair; source files are unchanged.")
    if session_reader(root):
        raise RuntimeError("An editor opened during repair; source files are unchanged.")
    staged_now = set(paths(root, "diff", "--cached", "--name-only", "--", "assets/models/*.glb.import"))
    for entry in candidates:
        if entry["path"] in staged_now or entry["target"].read_bytes() != entry["before"]:
            raise RuntimeError("Concurrent edit preserved: " + entry["path"])
    for entry in candidates:
        if entry["target"].read_bytes() != entry["before"]:
            raise RuntimeError("Concurrent edit preserved: " + entry["path"])
        entry["target"].write_bytes(entry["wanted"])
        report["restored"] += 1
    report["backup"] = str(backup)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Back up and restore proven rewrites after editors close")
    args = parser.parse_args()
    try:
        report = repair(ROOT, apply=args.apply)
    except (RuntimeError, OSError, subprocess.CalledProcessError, ValueError) as error:
        print("IMPORT_REPAIR_BLOCKED:", error)
        return 2
    print(json.dumps(report, ensure_ascii=False, indent=2))
    print("IMPORT_REPAIR_OK" if args.apply else "IMPORT_REPAIR_AUDIT_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
