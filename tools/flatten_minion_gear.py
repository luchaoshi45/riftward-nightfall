from pathlib import Path
p=Path('art_source/refined_models.py');s=p.read_text(encoding='utf-8-sig');start=s.index('def minion(team,armor,glow):');end=s.index("    export('minion_'+team)",start);part=s[start:end]
part=part.replace("shoulder.location.y=0;follow_hand(shoulder,pivot_arm)","shoulder.location.y=0")
part=part.replace("point=cone('Tempered spear point',(.31,-.04,2.02),.115,.008,.42,iron,8);follow_hand(point,arm_r)","cone('Tempered spear point',(.31,-.04,2.02),.115,.008,.42,iron,8)")
part=part.replace("fuller=rod('Spear luminous fuller',(.31,-.132,1.87),(.31,-.132,2.12),.009,glow);follow_hand(fuller,arm_r)","rod('Spear luminous fuller',(.31,-.132,1.87),(.31,-.132,2.12),.009,glow)")
part=part.replace("barb=rod('Spear side barb',(.31,-.04,1.96),(.31+side*.12,-.04,1.86),.018,iron);follow_hand(barb,arm_r)","rod('Spear side barb',(.31,-.04,1.96),(.31+side*.12,-.04,1.86),.018,iron)")
part=part.replace("shield.location.y=-.115;follow_hand(shield,arm_l)","shield.location.y=-.115")
part=part.replace("rib=rod('Shield raised ribs',(-.43+j*.085,-.16,.99),(-.36+j*.085,-.16,1.29),.012,trim);follow_hand(rib,arm_l)","rod('Shield raised ribs',(-.43+j*.085,-.16,.99),(-.36+j*.085,-.16,1.29),.012,trim)")
part=part.replace("boss=ico('Shield radiant boss',(-.325,-.18,1.17),(.065,.035,.075),glow);follow_hand(boss,arm_l)","ico('Shield radiant boss',(-.325,-.18,1.17),(.065,.035,.075),glow)")
part=part.replace(',arm_r)',')').replace(',arm_l)',')')
s=s[:start]+part+s[end:];p.write_text(s,encoding='utf-8')
