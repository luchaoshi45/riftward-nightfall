"""Prepare licensed Rusted Music Studio tracks for low-level adaptive game music."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

OUT = Path('assets/audio/music')
WORK = Path('build/music-prepared')
OUT.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)
TRACKS = [
    ('day_exploration', Path('build/music-downloads/piano/Wet Sand.mp3'), 240/35*2, 240/35*28, 240/35),
    ('night_watch', Path('build/music-downloads/apocalypse/Apocalypse Z/03 - Perish Lane ( level, mood, menu ).ogg'), 0, 186, 6),
    ('siege_combat', Path('build/music-downloads/war/Orchestral Fantasy - WAR/WAR - Mastered Tracks/Dark Sorcery Siege - Custom - 4 4 - C minor - 141BPM-Open-Low.mp3'), 240 / 141 * 10, 240 / 141 * 128, 240 / 141),
]
# A 4/4 bar is 240/BPM seconds (the piano uses a slow 35 BPM pulse).

def run(args):
    result = subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'info', '-y', *args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr[-1800:])
    return result.stderr

def probe(path):
    result = subprocess.run(['ffprobe','-v','error','-show_entries','format=duration:stream=codec_name,sample_rate,channels','-of','json',str(path)],capture_output=True,text=True,check=True)
    return json.loads(result.stdout)

report = []
for key, source, start, length, overlap in TRACKS:
    if len(sys.argv)>1 and key not in sys.argv[1:]:continue
    prepared = WORK / (key + '.wav')
    if overlap:
        # Move the loop seam into a bar-aligned overlap: the final sample
        # approaches the same source point as the first sample of the body.
        duration = length + overlap
        graph = (
            f'[0:a]atrim=start={start}:duration={duration},asetpts=PTS-STARTPTS,asplit=3[a][b][c];'
            f'[a]atrim=start={overlap}:end={length},asetpts=PTS-STARTPTS[body];'
            f'[b]atrim=start={length}:end={duration},asetpts=PTS-STARTPTS[tail];'
            f'[c]atrim=start=0:end={overlap},asetpts=PTS-STARTPTS[head];'
            f'[tail][head]acrossfade=d={overlap}:c1=tri:c2=tri[seam];'
            '[body][seam]concat=n=2:v=0:a=1[out]'
        )
        run(['-i',str(source),'-filter_complex',graph,'-map','[out]','-ar','44100','-ac','2','-c:a','pcm_f32le',str(prepared)])
    else:
        # This author's OGG is already a native loop; retain its whole phrase.
        run(['-i',str(source),'-ar','44100','-ac','2','-c:a','pcm_f32le',str(prepared)])
    stats_text = run(['-i',str(prepared),'-af','loudnorm=I=-18:TP=-2:LRA=11:print_format=json','-f','null','-'])
    stats = json.JSONDecoder().raw_decode(stats_text[stats_text.rfind('{'):])[0]
    normalization = (
        'loudnorm=I=-18:TP=-2:LRA=11:linear=true:'
        f'measured_I={stats["input_i"]}:measured_TP={stats["input_tp"]}:'
        f'measured_LRA={stats["input_lra"]}:measured_thresh={stats["input_thresh"]}:'
        f'offset={stats["target_offset"]}'
    )
    destination = OUT / (key + '.ogg')
    duration = float(probe(prepared)['format']['duration'])
    # A tiny edge window also removes codec-block/DC jumps in noisy drones.
    normalization += f',afade=t=in:st=0:d=0.008,afade=t=out:st={duration-.008}:d=0.008'
    run(['-i',str(prepared),'-af',normalization,'-ar','44100','-ac','2','-c:a','libvorbis','-q:a','5','-metadata','artist=Rusted Music Studio - Fabien C.','-metadata','license=https://creativecommons.org/licenses/by/4.0/',str(destination)])
    verification_text = run(['-i',str(destination),'-af','loudnorm=I=-18:TP=-2:LRA=11:print_format=json','-f','null','-'])
    verified = json.JSONDecoder().raw_decode(verification_text[verification_text.rfind('{'):])[0]
    item = {'track':key,'source':source.name,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'duration':float(probe(destination)['format']['duration']),'integrated_lufs':float(verified['input_i']),'true_peak_db':float(verified['input_tp']),'bytes':destination.stat().st_size}
    assert -19.5 < item['integrated_lufs'] < -16.5, item
    assert item['true_peak_db'] < -.5, item
    report.append(item)
    print(json.dumps(item,ensure_ascii=False),flush=True)
(WORK / 'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
