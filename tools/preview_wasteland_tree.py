from pathlib import Path
import bpy
from mathutils import Vector
ROOT = Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT / "art_source/outpost/dead_tree_v2.blend"))
(ROOT / "build").mkdir(exist_ok=True)
bpy.context.scene.render.engine='CYCLES'
bpy.context.scene.cycles.device='CPU'
bpy.context.scene.cycles.samples=24
bpy.context.scene.render.resolution_x=640
bpy.context.scene.render.resolution_y=800
bpy.context.scene.render.resolution_percentage=100
bpy.context.scene.world.use_nodes=True
bpy.context.scene.world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.045,.045,.045,1)
bpy.context.scene.world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.3
bpy.ops.object.camera_add(location=(5,-8,5.6))
camera=bpy.context.object
camera.rotation_euler=(Vector((0,0,1.46))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO'
camera.data.ortho_scale=4.0
bpy.context.scene.camera=camera
for location,power,size in [((3,-4,6),520,4),((-4,-1,3),260,4),((2,4,5),500,3)]:
    bpy.ops.object.light_add(type='AREA',location=location)
    light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size
    light.rotation_euler=(Vector((0,0,1.5))-light.location).to_track_quat('-Z','Y').to_euler()
grey=bpy.data.materials.new('Grey shape QA only');grey.use_nodes=True
bsdf=grey.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(.36,.36,.36,1);bsdf.inputs['Roughness'].default_value=.9
bpy.context.view_layer.material_override=grey
bpy.context.scene.render.filepath=str(ROOT / 'build/tree-blender-gray.png')
bpy.ops.render.render(write_still=True)
bpy.context.view_layer.material_override=None
bpy.context.scene.render.filepath=str(ROOT / 'build/tree-blender-material.png')
bpy.ops.render.render(write_still=True)
