from pathlib import Path
p=Path('art_source/showcase/create_knight_study.py');s=p.read_text(encoding='utf-8-sig');s=s.replace("default_value=.13;bump.inputs['Distance'].default_value=.006","default_value=.08;bump.inputs['Distance'].default_value=.002")
s=s.replace('theta=.18+t*1.50','theta=t*1.68')
s=s.replace("curve('Recessed eye socket',pts,.025,black)","curve('Recessed eye socket',pts,.014,black)")
s=s.replace("for x,y,z in pts],.02,steel)","for x,y,z in pts],.011,steel)")
marker='# Quiet exhibition stage, no image backplate.'
s=s.replace(marker,'''# Seat ornamental wires on the evaluated curved armor surface.
from mathutils.bvhtree import BVHTree
bpy.context.view_layer.update()
bvh=BVHTree.FromObject(bpy.data.objects['Anatomically shaped cuirass'],bpy.context.evaluated_depsgraph_get())
for obj in bpy.context.scene.objects:
 if obj.type=='CURVE' and any(obj.name.startswith(tag) for tag in ['Cuirass sculpted chevron','Recessed radiating breast engraving','Hand laid filigree leaf']):
  for spline in obj.data.splines:
   for point in spline.points:
    hit,normal,idx,dist=bvh.ray_cast(Vector((point.co.x,-2,point.co.z)),Vector((0,1,0)))
    if hit is not None:point.co.y=hit.y-.007
''' + marker)
p.write_text(s,encoding='utf-8')
