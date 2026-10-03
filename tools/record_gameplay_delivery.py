"""Record one playable delivery only after source rendering and packaged checks."""
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--version', required=True)
parser.add_argument('--name', required=True)
parser.add_argument('--verification', required=True)
parser.add_argument('--render-test', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
progress_path = root / 'optimization-progress.json'
progress = json.loads(progress_path.read_text(encoding='utf-8-sig'))
previous = progress['latest_version']
expected = '.'.join(previous.split('.')[:2] + [str(int(previous.split('.')[-1]) + 1)])
if args.version != expected or not 0 <= progress['completed'] < progress['target']:
    raise SystemExit('Unexpected release sequence')
label = f'Riftward_Nightfall_v{args.version}'
build = root / 'build'
if not (build / f'{label}.exe').is_file():
    raise SystemExit('Missing Windows executable')
logs = [build / f'export-{label}.log', build / f'startup-{label}.out.log',
        build / f'startup-{label}.err.log', build / f'{args.render_test}-render.out.log',
        build / f'{args.render_test}-render.err.log']
pack_logs = list(build.glob(f'*-packaged-{label}.log'))
if not pack_logs:
    raise SystemExit('Missing packaged checks')
for path in logs + pack_logs:
    text = path.read_text(encoding='utf-8-sig', errors='replace')
    if re.search(r'SCRIPT ERROR|ERROR:|WARNING:.*(?:leaked|still in use)', text):
        raise SystemExit(f'Errors in {path.name}')
    if (path in pack_logs or path.name.endswith('render.out.log')) and '_OK' not in text:
        raise SystemExit(f'Missing completion marker: {path.name}')
progress.update(completed=progress['completed'] + 1, latest_version=args.version,
                latest_improvement=args.name, verification=args.verification)
progress_path.write_text(json.dumps(progress, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
launcher = root / '启动游戏.cmd'
launcher.write_text(launcher.read_text(encoding='utf-8-sig').replace(previous, args.version), encoding='utf-8')
readme = root / 'README.md'
text = readme.read_text(encoding='utf-8').replace(previous, args.version)
text = re.sub(r'最新已验证Windows版本为[^\n]+',
              f'最新已验证Windows版本为{args.version}，完成{progress["completed"]}/100，以 [optimization-progress.json](optimization-progress.json) 为准。{args.name}。', text)
readme.write_text(text, encoding='utf-8')
agents = root / 'AGENTS.md'
text = agents.read_text(encoding='utf-8')
row = f'| {progress["completed"]} | {args.version} | {args.name} | 已验收：{args.verification} |\n'
marker = '<!-- VERIFIED_GAMEPLAY_DELIVERIES -->'
if marker not in text:
    text = text.replace('## 主机A当前工作', '## 本轮已验收的玩法交付\n\n| 计数 | 版本 | 改进 | 验证 |\n| --- | --- | --- | --- |\n' + marker + '\n\n## 主机A当前工作')
text = text.replace(marker, row + marker)
text = re.sub(r'本机最新已验证可玩版为[^；\n]+', f'本机最新已验证可玩版为{args.version}，完成{progress["completed"]}/100', text)
text = re.sub(r'- 最新已验证可玩版：[^\n]+', f'- 最新已验证可玩版：{args.version}，完成{progress["completed"]}/100，具体新功能和验收见本轮交付表。', text)
text = re.sub(r'- 完整游戏验证/Windows版本：[^\n]+', f'- 完整游戏验证/Windows版本：{args.version}（Godot4.7.2），本地build/{label}.exe，启动入口已更新；成品未上传GitHub Release。', text)
text = re.sub(r'- 完成计数：[^\n]+', f'- 完成计数：{progress["completed"]}/100，本轮已交付{progress["completed"]-29}/10；以optimization-progress.json为准。', text)
agents.write_text(text, encoding='utf-8')
print(f'RECORDED_DELIVERY {args.version} {progress["completed"]}/100')
