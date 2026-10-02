from pathlib import Path
p=Path('art_source/refined_models.py');s=p.read_text(encoding='utf-8-sig');marker='def hero(team,armor,glow):';helper='''def optimize_meshes():
    # Retain articulated pivots and cloth, merge static surfaces by material.
    groups={}
    for obj in list(bpy.context.scene.objects):
        if obj.type!='MESH' or obj.name=='Tailored pleated cape':continue
        bpy.context.view_layer.objects.active=obj
        for mod in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        key=(obj.parent,obj.data.materials[0] if obj.data.materials else None)
        groups.setdefault(key,[]).append(obj)
    for (parent,mat),objects in groups.items():
        if len(objects)<2:continue
        bpy.ops.object.select_all(action='DESELECT')
        for obj in objects:obj.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        bpy.ops.object.join()
        objects[0].name='Forged '+(mat.name if mat else 'mesh')

''';s=s.replace(marker,helper+marker);s=s.replace("    export('hero_'+team)","    optimize_meshes()\n    export('hero_'+team)").replace("    export('tower_'+team)","    optimize_meshes()\n    export('tower_'+team)");p.write_text(s,encoding='utf-8')
p=Path('export_presets.cfg');s=p.read_text(encoding='utf-8-sig').replace('v0.3.1','v0.3.2').replace('0.3.1.0','0.3.2.0');p.write_text(s,encoding='utf-8')
p=Path('启动游戏.cmd');s=p.read_text().replace('if exist "build\\Riftward_v0.3.1.exe" (','if exist "build\\Riftward_v0.3.2.exe" (\n    start "" "build\\Riftward_v0.3.2.exe"\n) else if exist "build\\Riftward_v0.3.1.exe" (');p.write_text(s,encoding='ascii')
