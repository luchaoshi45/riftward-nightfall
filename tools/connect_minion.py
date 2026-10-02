from pathlib import Path
p=Path('art_source/create_assets.py');s=p.read_text(encoding='utf-8-sig');s=s.replace('hero = refined_models.hero\ntower = refined_models.tower','hero = refined_models.hero\ntower = refined_models.tower\nminion = refined_models.minion');p.write_text(s,encoding='utf-8')
