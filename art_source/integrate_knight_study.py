"""Convert the editable portrait sculpture into an articulated game character."""
import bpy,os,math
from mathutils import Matrix,Vector
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT,'art_source','hero_blue.blend'))
# Preserve working limbs and weapon pivots from the full-body character.
def limb(obj):
 p=obj
 while p:
  if p.name in ['ArmL','ArmR','LegL','LegR']:return True
  p=p.parent
 return False
for obj in list(bpy.context.scene.objects):
 if not limb(obj):bpy.data.objects.remove(obj,do_unlink=True)
original=set(bpy.data.objects)
with bpy.data.libraries.load(os.path.join(ROOT,'art_source','showcase','knight_study.blend'),link=False) as (src,dst):
 dst.objects=[n for n in src.objects if not any(n.startswith(x) for x in ['Museum plinth','Plinth','Studio','Portrait camera','Warm large','Cool edge','Frontal softbox','Brass contour'])]
for obj in dst.objects:
 if obj is not None:bpy.context.collection.objects.link(obj)
bpy.context.view_layer.update()
new=[o for o in dst.objects if o is not None]
transform=Matrix.Translation((0,0,.80))@Matrix.Scale(.65,4)
for obj in new:
 obj.matrix_world=transform@obj.matrix_world
 if obj.type=='CURVE':obj.data.bevel_resolution=1;obj.data.resolution_u=5
 for mod in obj.modifiers:
  if mod.type=='SUBSURF':mod.levels=1;mod.render_levels=1
# Convert modeled ornaments to exportable mesh; attach shoulder shells to arms.
for obj in new:
 if obj.type not in ['MESH','CURVE']:continue
 bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
 bpy.ops.object.convert(target='MESH')
 if any(k in obj.name for k in ['shoulder','Shoulder']):
  center=sum((obj.matrix_world@Vector(c) for c in obj.bound_box),Vector())/8
  matrix=obj.matrix_world.copy();obj.parent=bpy.data.objects['ArmL' if center.x<0 else 'ArmR'];obj.matrix_world=matrix
 if obj.name=='Woven asymmetric mantle':obj.name='Tailored pleated cape'
# glTF receives explicit PBR channels; Blender procedural node trees are not exported.
for mat in bpy.data.materials:
 if not mat.use_nodes:continue
 old=mat.node_tree.nodes.get('Principled BSDF')
 if old is None:continue
 color=tuple(old.inputs['Base Color'].default_value);metal=float(old.inputs['Metallic'].default_value);rough=float(old.inputs['Roughness'].default_value)
 emission=tuple(old.inputs['Emission Color'].default_value);strength=float(old.inputs['Emission Strength'].default_value)
 mat.node_tree.nodes.clear();p=mat.node_tree.nodes.new('ShaderNodeBsdfPrincipled');out=mat.node_tree.nodes.new('ShaderNodeOutputMaterial');mat.node_tree.links.new(p.outputs[0],out.inputs['Surface'])
 p.inputs['Base Color'].default_value=(.065,.105,.135,1) if 'Forged silver' in mat.name else color;p.inputs['Metallic'].default_value=min(metal,.65);p.inputs['Roughness'].default_value=max(rough,.38)
 p.inputs['Emission Color'].default_value=emission;p.inputs['Emission Strength'].default_value=strength
# Merge static meshes per material and parent while retaining the animated cloak.
groups={}
for obj in list(bpy.context.scene.objects):
 if obj.type!='MESH' or obj.name=='Tailored pleated cape':continue
 groups.setdefault((obj.parent,tuple(obj.data.materials)),[]).append(obj)
for (parent,mats),objects in groups.items():
 if len(objects)<2:continue
 bpy.ops.object.select_all(action='DESELECT')
 for obj in objects:obj.select_set(True)
 bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join()
 objects[0].name='Knight '+(parent.name if parent else 'body')+' '+(mats[0].name if mats else 'surface')
for team in ['blue','red']:
 if team=='red':
  for mat in bpy.data.materials:
   if not mat.use_nodes:continue
   p=mat.node_tree.nodes.get('Principled BSDF')
   if p is None:continue
   if 'midnight steel' in mat.name or 'Forged silver' in mat.name:p.inputs['Base Color'].default_value=(.16,.045,.055,1)
   if 'woven mantle' in mat.name:p.inputs['Base Color'].default_value=(.10,.012,.025,1)
   if 'aether' in mat.name:
    p.inputs['Base Color'].default_value=(.36,.025,.04,1);p.inputs['Emission Color'].default_value=(.7,.035,.06,1)
 bpy.ops.object.select_all(action='SELECT')
 bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'art_source','hero_showcase_'+team+'.blend'))
 bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT,'assets','models','hero_showcase_'+team+'.glb'),export_format='GLB',export_yup=True)
print('SHOWCASE_GAME_CHARACTER_READY')


