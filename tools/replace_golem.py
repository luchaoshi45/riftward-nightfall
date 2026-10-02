from pathlib import Path
p=Path('art_source/create_assets.py');s=p.read_text(encoding='utf-8-sig');a=s.index("ico('Torso',(0,0,1.28)");b=s.index("export('golem')",a)+len("export('golem')");s=s[:a]+'refined_models.golem()'+s[b:];p.write_text(s,encoding='utf-8')
