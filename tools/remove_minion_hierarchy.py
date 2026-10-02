from pathlib import Path
p=Path('art_source/refined_models.py');s=p.read_text(encoding='utf-8-sig');a=s.index('def minion(team,armor,glow):');b=s.index("    export('minion_'+team)",a);part=s[a:b];part=part.replace('    follow_hand(shaft);shaft.rotation_euler.y=-.12','    shaft.rotation_euler.y=-.12');s=s[:a]+part+s[b:];p.write_text(s,encoding='utf-8')
