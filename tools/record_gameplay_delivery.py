"""Record a verified delivery after validating evidence and all proposed edits."""
import argparse
import hashlib
import json
import os
import re
import stat
import tempfile
from dataclasses import dataclass
from pathlib import Path, PureWindowsPath
from typing import Optional


VERSION = re.compile(r'[0-9]+\.[0-9]+\.[0-9]+')
TEST_NAME = re.compile(r'[a-z0-9_]+')
EXECUTABLE = re.compile(r'(?<![\w.-])Riftward_Nightfall_v([0-9]+\.[0-9]+\.[0-9]+)\.exe(?![\w.-])')
ERRORS = re.compile(r'SCRIPT ERROR|ERROR:|WARNING:.*(?:leaked|still in use)', re.I)
RENDERER = re.compile(
    r'(?:(?:Metal|Vulkan) [0-9][^\r\n]* - (?:Forward\+|Mobile)'
    r'|OpenGL API [0-9][^\r\n]* - Compatibility)'
    r' - Using Device(?: #[0-9]+)?: [^\r\n]+')
MARKER = '<!-- VERIFIED_GAMEPLAY_DELIVERIES -->'
BOM = b'\xef\xbb\xbf'


@dataclass(frozen=True)
class FileSnapshot:
    path: Path
    resolved: Path
    signature: tuple
    digest: bytes
    data: Optional[bytes]


def _signature(info):
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_mode)


def _inside(path, boundary):
    resolved = path.resolve(strict=True)
    try:
        resolved.relative_to(boundary)
    except ValueError:
        raise ValueError(f'Path outside the allowed directory: {path.name}')
    return resolved


def _snapshot(path, boundary, keep_bytes=True, target=False):
    if target and path.is_symlink():
        raise ValueError(f'Delivery target must not be a symlink: {path.name}')
    resolved = _inside(path, boundary)
    before = resolved.stat()
    if not stat.S_ISREG(before.st_mode):
        raise ValueError(f'Expected a regular file: {path.name}')
    digest = hashlib.sha256()
    chunks = []
    with resolved.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
            if keep_bytes:
                chunks.append(chunk)
    if (_signature(before) != _signature(resolved.stat())
            or _inside(path, boundary) != resolved
            or (target and path.is_symlink())):
        raise OSError(f'File changed while being read: {path.name}')
    return FileSnapshot(path, resolved, _signature(before), digest.digest(),
                        b''.join(chunks) if keep_bytes else None)


def _unchanged(snapshot, boundary, target=False):
    current = _snapshot(snapshot.path, boundary, keep_bytes=False, target=target)
    if (current.resolved != snapshot.resolved
            or current.signature != snapshot.signature
            or current.digest != snapshot.digest):
        raise OSError(f'File changed during delivery: {snapshot.path.name}')


def _text(snapshot):
    return snapshot.data.decode('utf-8-sig')


def _encoded(text, snapshot):
    return (BOM if snapshot.data.startswith(BOM) else b'') + text.encode('utf-8')


def _one(matches, label):
    if len(matches) != 1:
        raise ValueError(f'Expected one {label}')
    return matches[0]


def _single_line(value, label):
    if not isinstance(value, str) or not value.strip() or any(c in value for c in '\r\n\x00'):
        raise ValueError(f'Expected nonempty single-line {label}')
    if MARKER in value:
        raise ValueError(f'Unexpected delivery marker in {label}')


def _log_text(data):
    # Windows PowerShell 5.1 redirection can produce UTF-16 with a BOM.
    encoding = 'utf-16' if data.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8-sig'
    return data.decode(encoding, errors='replace')


def _windows_receipt(text, version, executable):
    lines = text.splitlines()
    closes = [line for line in lines if line.startswith('Windows startup and close exit:')]
    if closes != ['Windows startup and close exit: 0']:
        raise ValueError('Missing or unsuccessful Windows startup and close receipt')
    marker = _one([line for line in lines if line.startswith('VERIFIED_WINDOWS_BUILD')],
                  'Windows build completion receipt')
    match = re.fullmatch(r'VERIFIED_WINDOWS_BUILD ([0-9]+\.[0-9]+\.[0-9]+) ([^\r\n]+)', marker)
    if not match or match.group(1) != version:
        raise ValueError('Windows build receipt does not match the requested executable')
    artifact = PureWindowsPath(match.group(2))
    if (not artifact.is_absolute() or artifact.name != executable
            or match.group(2).endswith(('\\', '/'))):
        raise ValueError('Windows build receipt does not match the requested executable')


def _completion_line(text, marker, filename, allow_details=False):
    matches = [line for line in text.splitlines() if line.startswith(marker)]
    if allow_details:
        valid = (len(matches) == 1 and re.fullmatch(
            re.escape(marker) + r'(?:[ \t]+\S[^\r\n]*)?', matches[0]))
    else:
        valid = matches == [marker]
    if not valid:
        raise ValueError(f'Missing or duplicate completion marker: {filename}')


def _readme_update(text, old_file, new_file, version, completed, target, name):
    edits = []
    summary = _one(list(re.finditer(r'^最新已验证Windows版本为([^\r\n]+)', text, re.M)),
                   'current Windows summary')
    old_version = EXECUTABLE.fullmatch(old_file).group(1)
    if not summary.group(1).startswith(old_version + '，'):
        raise ValueError('Windows summary disagrees with the launcher')
    edits.append((summary.start(), summary.end(),
                  f'最新已验证Windows版本为{version}，完成{completed}/{target}，'
                  f'以 [optimization-progress.json](optimization-progress.json) 为准。{name}。'))
    launcher = _one(list(re.finditer(
        r'(`启动游戏\.cmd` 已指向)([0-9]+\.[0-9]+\.[0-9]+)', text)), 'launcher usage')
    if launcher.group(2) != old_version:
        raise ValueError('README launcher usage disagrees with the launcher')
    edits.append((launcher.start(2), launcher.end(2), version))
    usage = _one(list(re.finditer(r'^本机有成品时[^\r\n]*', text, re.M)),
                 'current executable usage')
    usage_file = _one(list(EXECUTABLE.finditer(usage.group())), 'usage executable')
    if usage_file.group() != old_file:
        raise ValueError('README executable usage disagrees with the launcher')
    edits.append((usage.start() + usage_file.start(), usage.start() + usage_file.end(), new_file))
    exports = list(re.finditer(
        r'''^godot[^\r\n]*--export-release[ \t]+(['"])Windows Desktop\1[^\r\n]*''', text, re.M))
    if exports:
        export = _one(exports, 'current Windows export command')
        export_file = _one(list(EXECUTABLE.finditer(export.group())), 'export executable')
        if export_file.group() != old_file:
            raise ValueError('README export command disagrees with the launcher')
        edits.append((export.start() + export_file.start(), export.start() + export_file.end(), new_file))
    for start, end, replacement in sorted(edits, reverse=True):
        text = text[:start] + replacement + text[end:]
    return text


def _agents_current_edits(text, title, line_pattern, source_label,
                          previous, previous_count, old_version, target,
                          version, completed):
    headings = list(re.finditer(r'^## ' + re.escape(title) + r'[ \t]*\r?$', text, re.M))
    if not headings:
        return []
    heading = _one(headings, f'{title} section')
    next_heading = re.search(r'^##[ \t]', text[heading.end():], re.M)
    end = heading.end() + next_heading.start() if next_heading else len(text)
    body = text[heading.end():end]
    line = _one(list(re.finditer(line_pattern, body, re.M)), f'{title} current version field')
    source = _one(list(re.finditer(
        re.escape(source_label) + r'(?P<version>[0-9]+\.[0-9]+\.[0-9]+)，'
        r'完成(?P<count>[0-9]+)/(?P<target>[0-9]+)', line.group())), f'{title} source progress')
    windows = _one(list(re.finditer(
        r'Windows成品基线仍为(?P<version>[0-9]+\.[0-9]+\.[0-9]+)', line.group())),
        f'{title} Windows baseline')
    if (source.group('version') != previous or int(source.group('count')) != previous_count
            or int(source.group('target')) != target or windows.group('version') != old_version):
        raise ValueError(f'{title} current versions disagree with the recorded progress or launcher')
    offset = heading.end() + line.start()
    return [
        (offset + source.start('version'), offset + source.end('version'), version),
        (offset + source.start('count'), offset + source.end('count'), str(completed)),
        (offset + windows.start('version'), offset + windows.end('version'), version),
    ]


def _agents_update(text, version, completed, name, verification,
                   previous, previous_count, old_version, target):
    if text.count(MARKER) != 1:
        raise ValueError('Expected one verified deliveries marker')
    marker = _one(list(re.finditer(r'^' + re.escape(MARKER) + r'(?=\r?$)', text, re.M)),
                  'verified deliveries marker line')
    rows = list(re.finditer(r'^\|[ \t]*([0-9]+)[ \t]*\|[ \t]*([0-9]+\.[0-9]+\.[0-9]+)[ \t]*\|',
                            text, re.M))
    if any(row.group(2) == version or int(row.group(1)) == completed for row in rows):
        raise ValueError('Delivery version or count already recorded')
    newline = '\r\n' if '\r\n' in text else '\n'
    def cell(value):
        return value.replace('\\', '\\\\').replace('|', '\\|')
    row = f'| {completed} | {version} | {cell(name)} | 已验收：{cell(verification)} |{newline}'
    edits = [(marker.start(), marker.start(), row)]
    for title, line_pattern, source_label in (
        ('当前共同基线', r'^- 最新已验证源码版：[^\r\n]*', '最新已验证源码版：'),
        ('项目与当前状态', r'^- 远端初始导入为[^\r\n]*', '本机最新已验证源码版为'),
    ):
        edits.extend(_agents_current_edits(text, title, line_pattern, source_label,
                                          previous, previous_count, old_version, target,
                                          version, completed))
    for start, end, replacement in sorted(edits, reverse=True):
        text = text[:start] + replacement + text[end:]
    return text


def _stage(snapshot, data):
    descriptor, filename = tempfile.mkstemp(prefix=f'.{snapshot.path.name}.delivery-',
                                           suffix='.tmp', dir=snapshot.path.parent)
    temporary = Path(filename)
    try:
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.chmod(stat.S_IMODE(snapshot.signature[-1]))
    except BaseException:
        temporary.unlink()
        raise
    return temporary


def _commit(snapshots, updates, evidence, root, build):
    """Replace each file atomically; ordinary failures get best-effort rollback.

    These replacements are not a crash-proof transaction across four files.
    """
    temporary = []
    replacements = {}
    backups = {}
    committed = []
    expected = {snapshot.path: snapshot for snapshot in snapshots}
    try:
        for snapshot in snapshots:
            replacements[snapshot.path] = _stage(snapshot, updates[snapshot.path])
            temporary.append(replacements[snapshot.path])
            backups[snapshot.path] = _stage(snapshot, snapshot.data)
            temporary.append(backups[snapshot.path])
        for snapshot in snapshots:
            for current in expected.values():
                _unchanged(current, root, target=True)
            for proof in evidence:
                _unchanged(proof, build)
            os.replace(replacements[snapshot.path], snapshot.path)
            committed.append(snapshot)
            current = _snapshot(snapshot.path, root, target=True)
            if current.data != updates[snapshot.path]:
                raise OSError(f'Unexpected contents after replacement: {snapshot.path.name}')
            expected[snapshot.path] = current
        for current in expected.values():
            _unchanged(current, root, target=True)
        for proof in evidence:
            _unchanged(proof, build)
    except BaseException as error:
        rollback_errors = []
        for snapshot in reversed(committed):
            try:
                current = _snapshot(snapshot.path, root, target=True)
                if current.data != updates[snapshot.path]:
                    raise OSError('Concurrent content retained')
                os.replace(backups[snapshot.path], snapshot.path)
            except (OSError, ValueError) as rollback_error:
                rollback_errors.append(f'{snapshot.path.name}: {rollback_error}')
        if rollback_errors:
            raise OSError(f'{error}; rollback incomplete: {"; ".join(rollback_errors)}') from error
        raise
    finally:
        for path in temporary:
            try:
                path.unlink()
            except FileNotFoundError:
                pass


def record_delivery(root, version, name, verification, render_test):
    """Validate and record one delivery, returning the updated progress mapping."""
    if not isinstance(version, str) or not VERSION.fullmatch(version):
        raise ValueError('Expected a numeric three-part version')
    if not isinstance(render_test, str) or not TEST_NAME.fullmatch(render_test):
        raise ValueError('Unexpected render test filename')
    _single_line(name, 'name')
    _single_line(verification, 'verification')
    root = Path(root).resolve(strict=True)
    if not root.is_dir():
        raise ValueError('Expected a repository directory')
    snapshots = [_snapshot(root / filename, root, target=True) for filename in
                 ('启动游戏.cmd', 'README.md', 'AGENTS.md', 'optimization-progress.json')]
    launcher, readme, agents, progress_file = snapshots
    progress = json.loads(_text(progress_file))
    if not isinstance(progress, dict):
        raise ValueError('Expected a progress object')
    previous = progress.get('latest_version')
    completed, target = progress.get('completed'), progress.get('target')
    if (not isinstance(previous, str) or not VERSION.fullmatch(previous)
            or type(completed) is not int or type(target) is not int
            or not 0 <= completed < target):
        raise ValueError('Invalid release progress')
    major, minor, patch = previous.split('.')
    if version != f'{major}.{minor}.{int(patch) + 1}':
        raise ValueError('Unexpected release sequence')
    label = f'Riftward_Nightfall_v{version}'
    new_file = f'{label}.exe'
    launcher_text = _text(launcher)
    references = list(EXECUTABLE.finditer(launcher_text))
    if len(references) != 2 or references[0].group() != references[1].group():
        raise ValueError('Expected two consistent launcher executable references')
    old_file = references[0].group()
    exists = _one(list(re.finditer(
        r'^[ \t]*if[ \t]+exist[ \t]+"([^"\r\n]+)"[ \t]*\([ \t]*\r?$',
        launcher_text, re.M | re.I)), 'launcher if exist statement')
    starts = _one(list(re.finditer(
        r'^[ \t]*start[ \t]+""[ \t]+"([^"\r\n]+)"[ \t]*\r?$',
        launcher_text, re.M | re.I)), 'launcher start statement')
    expected_path = 'build\\' + old_file
    if any(reference.group(1).replace('/', '\\') != expected_path for reference in (exists, starts)):
        raise ValueError('Launcher statements must reference the same verified build executable')
    if tuple(map(int, references[0].group(1).split('.'))) > tuple(map(int, previous.split('.'))):
        raise ValueError('Launcher version is ahead of recorded progress')
    updated_progress = dict(progress, completed=completed + 1, latest_version=version,
                            latest_improvement=name, verification=verification)
    updated_readme = _readme_update(_text(readme), old_file, new_file, version,
                                    completed + 1, target, name)
    updated_agents = _agents_update(_text(agents), version, completed + 1, name, verification,
                                    previous, completed, references[0].group(1), target)
    newline = '\r\n' if b'\r\n' in progress_file.data else '\n'
    updated_json = (json.dumps(updated_progress, ensure_ascii=False, indent=2) + '\n').replace('\n', newline)
    updates = {
        launcher.path: _encoded(EXECUTABLE.sub(lambda match: new_file, launcher_text), launcher),
        readme.path: _encoded(updated_readme, readme),
        agents.path: _encoded(updated_agents, agents),
        progress_file.path: _encoded(updated_json, progress_file),
    }
    if (root / 'build').is_symlink():
        raise ValueError('Build directory must not be a symlink')
    build = _inside(root / 'build', root)
    if not build.is_dir():
        raise ValueError('Missing build directory')
    executable = _snapshot(root / 'build' / new_file, build, keep_bytes=False)
    if executable.signature[2] == 0:
        raise ValueError('Empty Windows executable')
    log_paths = [root / 'build' / filename for filename in (
        f'export-{label}.log', f'startup-{label}.out.log', f'startup-{label}.err.log',
        f'{render_test}-render.out.log', f'{render_test}-render.err.log',
        f'verified-{label}.log')]
    render_log = root / 'build' / f'{render_test}-render.out.log'
    native_log = root / 'build' / f'verified-{label}.log'
    loop_log = root / 'build' / f'nightfall_loop-packaged-{label}.log'
    packaged = sorted((root / 'build').glob(f'*-packaged-{label}.log'))
    if loop_log not in packaged:
        raise ValueError('Missing packaged nightfall_loop check')
    evidence = [executable]
    for path in log_paths + packaged:
        proof = _snapshot(path, build)
        text = _log_text(proof.data)
        if ERRORS.search(text):
            raise ValueError(f'Errors in {path.name}')
        if path == loop_log:
            _completion_line(text, 'NIGHTFALL_LOOP_OK', path.name)
        elif path == render_log:
            _completion_line(text, render_test.upper() + '_OK', path.name, allow_details=True)
        elif path in packaged and '_OK' not in text:
            raise ValueError(f'Missing completion marker: {path.name}')
        if path == render_log and not any(RENDERER.fullmatch(line) for line in text.splitlines()):
            raise ValueError('Missing non-headless rendering backend receipt')
        if path == native_log:
            _windows_receipt(text, version, new_file)
        evidence.append(proof)
    _commit(snapshots, updates, evidence, root, build)
    return updated_progress


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--name', required=True)
    parser.add_argument('--verification', required=True)
    parser.add_argument('--render-test', required=True)
    args = parser.parse_args()
    try:
        progress = record_delivery(Path(__file__).resolve().parents[1], args.version,
                                   args.name, args.verification, args.render_test)
    except (OSError, ValueError) as error:
        raise SystemExit(str(error))
    print(f'RECORDED_DELIVERY {args.version} {progress["completed"]}/{progress["target"]}')


if __name__ == '__main__':
    main()
