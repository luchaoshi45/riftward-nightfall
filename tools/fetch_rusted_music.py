"""Fetch an author's explicitly free music pack using its normal itch download flow."""
import html
import json
import re
import sys
from pathlib import Path
import requests

slug = sys.argv[1]
label = sys.argv[2]
base = 'https://rustedstudio.itch.io/' + slug
session = requests.Session()
session.headers['User-Agent'] = 'Mozilla/5.0'
response = session.get(base, timeout=30)
response.raise_for_status()
page = response.text
if not re.search(r'"actual_price"\s*:\s*0', page):
    raise RuntimeError('This pack is not explicitly free; do not proceed')
csrf = html.unescape(re.search(r'name="csrf_token"\s+value="([^"]+)"', page).group(1))
response = session.post(base + '/download_url', data={'csrf_token': csrf}, timeout=30)
response.raise_for_status()
download_page_url = response.json()['url']
response = session.get(download_page_url, timeout=30)
response.raise_for_status()
download_page = response.text
Path('build/music-' + label + '-download-page.html').write_text(download_page, encoding='utf-8')
upload_ids = re.findall(r'data-upload_id="(\d+)"', download_page)
print(json.dumps({'pack': label, 'upload_ids': upload_ids}, ensure_ascii=False))
if len(upload_ids) != 1:
    raise RuntimeError('Expected one archive: inspect the official download page')
csrf = html.unescape(re.search(r'name="csrf_token"\s+value="([^"]+)"', download_page).group(1))
response = session.post(base + '/file/' + upload_ids[0], data={'csrf_token': csrf}, params={'source':'download','as_props':'1'}, timeout=30)
response.raise_for_status()
result = response.json()
if 'url' not in result:
    raise RuntimeError('The official download did not yield a file: ' + str(result.get('errors', [])))
out = Path('build/music-downloads')
out.mkdir(exist_ok=True)
target = out / (label + '.rar')
with session.get(result['url'], stream=True, timeout=60) as audio:
    audio.raise_for_status()
    with target.open('wb') as stream:
        for chunk in audio.iter_content(1024 * 1024):
            stream.write(chunk)
print(json.dumps({'pack': label, 'archive': str(target), 'bytes': target.stat().st_size}))
