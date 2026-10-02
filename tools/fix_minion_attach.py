from pathlib import Path
p=Path('art_source/refined_models.py');s=p.read_text(encoding='utf-8-sig');start=s.index('def minion(team,armor,glow):');end=s.index("    export('minion_'+team)",start)+len("    export('minion_'+team)");part=s[start:end]
part=part.replace("    # Compact, forward leaning silhouette with a visible cloth tail.","    def follow_hand(obj,parent):\n        bpy.context.view_layer.update()\n        world=obj.matrix_world.copy()\n        obj.parent=parent\n        obj.matrix_world=world\n        return obj\n    # Compact, forward leaning silhouette with a visible cloth tail.")
part=part.replace("shoulder.location.y=0;shoulder.parent=pivot_arm", "shoulder.location.y=0;follow_hand(shoulder,pivot_arm)")
part=part.replace("(.31,-.025,1.33),.034,.027,1.25,darkleather,12,arm_r)\n    shaft.rotation_euler.y=-.12", "(.31,-.025,1.33),.034,.027,1.25,darkleather,12)\n    follow_hand(shaft,arm_r);shaft.rotation_euler.y=-.12")
part=part.replace("cone('Tempered spear point',(.31,-.04,2.02),.115,.008,.42,iron,8,arm_r)", "point=cone('Tempered spear point',(.31,-.04,2.02),.115,.008,.42,iron,8);follow_hand(point,arm_r)")
part=part.replace("rod('Spear luminous fuller',(.31,-.132,1.87),(.31,-.132,2.12),.009,glow,arm_r)", "fuller=rod('Spear luminous fuller',(.31,-.132,1.87),(.31,-.132,2.12),.009,glow);follow_hand(fuller,arm_r)")
part=part.replace("rod('Spear side barb',(.31,-.04,1.96),(.31+side*.12,-.04,1.86),.018,iron,arm_r)", "barb=rod('Spear side barb',(.31,-.04,1.96),(.31+side*.12,-.04,1.86),.018,iron);follow_hand(barb,arm_r)")
part=part.replace("shield.location.y=-.115", "shield.location.y=-.115;follow_hand(shield,arm_l)")
part=part.replace("rod('Shield raised ribs',(-.43+j*.085,-.16,.99),(-.36+j*.085,-.16,1.29),.012,trim,arm_l)", "rib=rod('Shield raised ribs',(-.43+j*.085,-.16,.99),(-.36+j*.085,-.16,1.29),.012,trim);follow_hand(rib,arm_l)")
part=part.replace("ico('Shield radiant boss',(-.325,-.18,1.17),(.065,.035,.075),glow,arm_l)", "boss=ico('Shield radiant boss',(-.325,-.18,1.17),(.065,.035,.075),glow);follow_hand(boss,arm_l)")
part=part.replace("    optimize_meshes()\n    export('minion_'+team)", "    export('minion_'+team)")
s=s[:start]+part+s[end:];p.write_text(s,encoding='utf-8')
