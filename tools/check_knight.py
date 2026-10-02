import bpy
from mathutils import Vector
bpy.ops.wm.open_mainfile(filepath=r'C:/Users/Administrator/Documents/ChatGPT/3d game/art_source/hero_showcase_blue.blend')
for o in bpy.context.scene.objects:
 if o.type=='MESH':
  print(o.name,tuple(round(x,3) for x in o.dimensions))
