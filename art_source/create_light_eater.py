"""Original Blender source for the lamp-eating night moth.

Run from the project root with Blender's --background --python option.  The
saved .blend remains editable; the GLB is the game-scale, animated-node asset.
"""

import bpy
import math
import os
from mathutils import Vector


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "art_source", "outpost", "night_light_eater.blend")
GAME = os.path.join(ROOT, "assets", "models", "night_light_eater.glb")


def material(name, rgb, roughness=0.8, metallic=0.0, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1.0)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*rgb, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    if emission:
        shader.inputs["Emission Color"].default_value = (*rgb, 1.0)
        shader.inputs["Emission Strength"].default_value = emission
    return mat


body = material("Moth charcoal velvet", (0.052, 0.072, 0.080), .92)
wing = material("Moth ink teal membrane", (0.075, 0.16, 0.17), .83)
wing_edge = material("Moth powdered wing ridge", (0.23, 0.35, 0.33), .83)
bone = material("Moth pale ivory cartilage", (0.24, 0.29, 0.27), .75)
metal = material("Moth salvaged brass shell", (0.18, 0.14, 0.095), .57, .34)
glow = material("Stolen lantern light", (0.34, 0.76, 0.72), .28, .06, 2.0)
dim_glow = material("Wing dust constellation", (0.13, 0.51, 0.53), .52, 0, 1.65)


def bevel(obj, width):
    bevel_modifier = obj.modifiers.new("Soft physical edge", "BEVEL")
    bevel_modifier.width = width
    bevel_modifier.segments = 2
    obj.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    return obj


def sphere(name, point, size, mat, subdivisions=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1, location=point)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for face in obj.data.polygons:
        face.use_smooth = True
    return obj


def rod(name, a, b, radius, mat, sides=9):
    a, b = Vector(a), Vector(b)
    vector = b - a
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=radius,
                                    radius2=radius * .76, depth=vector.length,
                                    location=(a + b) * .5)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = vector.to_track_quat("Z", "Y").to_euler()
    obj.data.materials.append(mat)
    return obj


def sheet(name, points, mat):
    # One clean fan: the material exports two-sided for banked flight.
    triangles = [(0, 1, 7), (1, 2, 7), (2, 3, 7), (3, 4, 7),
                 (4, 5, 7), (5, 6, 7), (6, 0, 7)]
    data = bpy.data.meshes.new(name)
    data.from_pydata(points, [], triangles)
    data.update()
    data.materials.append(mat)
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return obj


def pivot(name, point):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = point
    obj.empty_display_size = .12
    return obj


def attach(obj, parent):
    bpy.context.view_layer.update()
    matrix = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = matrix


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

# A narrow body and broad sculpted wings create a silhouette unlike any
# ground-based night creature.  The light core is held inside exposed ribs.
sphere("Long velvet thorax", (0, -.13, 1.05), (.30, .59, .31), body, 3)
sphere("Segmented tapered abdomen", (0, .48, .96), (.25, .53, .25), body, 2)
sphere("Angular head", (0, -.75, 1.14), (.26, .31, .23), metal, 2)
sphere("Stolen amber heart", (0, -.15, 1.30), (.17, .26, .21), glow, 2)
for side in (-1, 1):
    rod("Heart containment arch", (side * .25, -.37, 1.09),
        (side * .15, .07, 1.44), .043, bone)
    rod("Breastplate edging", (side * .19, -.64, 1.31),
        (side * .25, -.25, 1.30), .037, metal)
    sphere("Four cold compound eyes", (side * .17, -.94, 1.19),
           (.075, .042, .055), glow, 2)
    rod("Forward hooked antenna", (side * .11, -.98, 1.28),
        (side * .35, -1.42, 1.50), .025, bone)
    sphere("Antenna light detector", (side * .36, -1.43, 1.51),
           (.035, .04, .045), dim_glow, 1)
    for leg in range(3):
        y = -.43 + leg * .35
        hip = (side * .21, y, .97)
        knee = (side * (.41 + leg * .035), y + .09, .61)
        tip = (side * (.52 + leg * .05), y + .21, .28)
        rod("Jointed grasping leg", hip, knee, .032, bone)
        rod("Hooked lower tarsus", knee, tip, .020, body, 8)

for band in range(4):
    y = .19 + band * .22
    sphere("Abdominal ventral scale", (0, y, 1.16 - band * .045),
           (.21 - band * .02, .075, .07), metal, 1)

for side, label in ((-1, "Left"), (1, "Right")):
    joint = pivot("MothWing" + label, (side * .23, -.14, 1.19))
    p = [(side * .24, -.22, 1.20),
         (side * .61, -.75, 1.20),
         (side * 1.10, -.84, 1.17),
         (side * 1.76, -.41, 1.15),
         (side * 1.57, .30, 1.11),
         (side * 1.10, .58, 1.10),
         (side * .42, .34, 1.17),
         (side * .95, -.08, 1.18)]
    attach(sheet("Swept nightwing membrane " + label, p, wing), joint)
    # Curved outer edge, exposed flight-veins and two light-catching windows.
    for a, b in ((0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6)):
        radius = .043 if a in (0, 1, 2) else .025
        attach(rod("Scalloped leading ridge " + label, p[a], p[b],
                   radius, wing_edge, 8), joint)
    for target in (p[2], p[3], p[4], p[5]):
        attach(rod("Radial wing vein " + label, p[0], target,
                   .018, bone, 7), joint)
    for index, (x, y) in enumerate(((1.20, -.37), (1.39, .08), (.93, .29))):
        attach(sphere("Glowing ocellus %d %s" % (index, label),
                      (side * x, y, 1.205), (.09, .11, .013),
                      glow if index == 0 else dim_glow, 1), joint)
    # Rear streamers separate the wing tips when the wings close.
    for root_x, root_y in ((1.35, .29), (.85, .43)):
        tip = (side * (root_x + .24), root_y + .50, .88)
        attach(rod("Hanging wing streamer " + label,
                   (side * root_x, root_y, 1.12), tip,
                   .026, bone, 7), joint)

# Preserve each wing's parent node when merging.  The Godot animation script
# rotates these empties rather than deforming the GLB's material groups.
groups = {}
for obj in tuple(bpy.context.scene.objects):
    if obj.type == "MESH":
        key = (obj.parent.name if obj.parent else "",
               tuple(mat.name for mat in obj.data.materials))
        groups.setdefault(key, []).append(obj)
for objects in groups.values():
    if len(objects) < 2:
        continue
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()

os.makedirs(os.path.dirname(SOURCE), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=SOURCE)
bpy.ops.export_scene.gltf(filepath=GAME, export_format="GLB", export_yup=True)
print("LIGHT_EATER_READY", sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type == "MESH"))
