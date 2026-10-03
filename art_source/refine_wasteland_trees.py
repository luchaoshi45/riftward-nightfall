"""Original fire-scarred tree: shaped source, baked PBR, staged GLB only.

Blender 4.5 background entry point. Does not replace assets/models/dead_tree.glb.
Primary limbs and buttress roots stay editable in the source collection. A voxel
union makes organic crotches before a bounded export mesh is unwrapped and baked.
"""
import json
import math
import os
import struct

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "art_source", "outpost", "dead_tree_v2.blend")
STAGED = os.path.join(ROOT, "art_source", "staging", "dead_tree_v2.glb")
TAU = math.tau

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for data in list(bpy.data.materials):
    if data.users == 0:
        bpy.data.materials.remove(data)

shapes = bpy.data.collections.new("Editable organic trunk limbs and roots")
bpy.context.scene.collection.children.link(shapes)
export = bpy.data.collections.new("Baked realtime tree - two material meshes")
bpy.context.scene.collection.children.link(export)


def mesh(name, vertices, faces, collection=shapes):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    for polygon in data.polygons:
        polygon.use_smooth = True
    return obj


def interpolate(points, count):
    """Catmull-Rom centreline, including smoothly varying radii."""
    values = []
    points = [Vector(p) for p in points]
    for j in range(len(points) - 1):
        a, b, c, d = points[max(0, j - 1)], points[j], points[j + 1], points[min(len(points) - 1, j + 2)]
        for step in range(count):
            t = step / count
            values.append((2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t ** 3) * .5)
    values.append(points[-1])
    return values


def limb(name, points, sides=14, samples=6, phase=0, fluting=.075):
    ring = interpolate(points, samples)
    vertices, faces = [], []
    for j, sample in enumerate(ring):
        centre = Vector(sample[:3])
        tangent = Vector(ring[min(len(ring) - 1, j + 1)][:3]) - Vector(ring[max(0, j - 1)][:3])
        tangent.normalize()
        right = tangent.cross(Vector((0, 1, 0)))
        if right.length < .2:
            right = tangent.cross(Vector((1, 0, 0)))
        right.normalize()
        across = right.cross(tangent).normalized()
        twist = j * .014 + phase
        for k in range(sides):
            a = TAU * k / sides + twist
            radius = max(.010, sample[3]) * (1 + fluting * math.sin(5 * a + j * .085) + fluting * .55 * math.sin(3 * a - j * .045))
            point = centre + (right * math.cos(a) + across * math.sin(a)) * radius
            vertices.append(tuple(point))
        if j:
            for k in range(sides):
                a = (j - 1) * sides + k
                b = (j - 1) * sides + (k + 1) % sides
                faces.append((a, b, j * sides + (k + 1) % sides, j * sides + k))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple((len(ring) - 1) * sides + k for k in range(sides)))
    obj = mesh(name, vertices, faces)
    obj["purpose"] = "Editable tapered organic sweep; fused in realtime copy"
    return obj


# Quiet, bowed central mass; lean reverses in the upper crown instead of forming
# a straight cylinder. Several thick roots carry its weight, at soil level.
limb("Bowed scarred main trunk", [(0, 0, -.04, .37), (-.12, .02, .31, .31),
     (-.17, .025, .85, .23), (.005, -.025, 1.42, .20), (.14, .03, 2.02, .145),
     (.015, .12, 2.61, .106), (.19, .13, 3.05, .063)], sides=24, samples=8, fluting=.185)
for i in range(6):
    angle = i * TAU / 6 + .17
    length = [.93, .76, .98, .82, .69, .87][i]
    limb("Buttress root %02d" % i,
         [(-.09, .01, .44, .16), (.20 * math.cos(angle), .20 * math.sin(angle), .20, .14),
          (.56 * math.cos(angle), .54 * math.sin(angle), .085, .072),
          (length * math.cos(angle + .13), length * math.sin(angle + .13), .025, .021)],
         samples=5, sides=12, phase=angle)

limb("Left reaching arm", [(-.11, .01, 1.04, .20), (-.44, -.03, 1.34, .16),
     (-.83, -.10, 1.63, .115), (-1.18, -.23, 2.03, .075), (-1.43, -.27, 2.43, .040)], phase=.6)
limb("Left broken upper fork", [(-.75, -.08, 1.61, .105), (-.70, .09, 1.95, .079),
     (-.83, .17, 2.30, .053), (-.76, .21, 2.60, .032)], sides=12, samples=5, phase=1.1)
limb("Left low snapped spur", [(-.43, -.02, 1.35, .085), (-.70, -.34, 1.50, .056),
     (-.92, -.50, 1.66, .047)], sides=12, samples=5, phase=.4)
limb("Right upright arm", [(.07, .005, 1.63, .161), (.48, .05, 1.80, .137),
     (.86, .15, 1.94, .097), (1.18, .24, 2.30, .065), (1.41, .21, 2.73, .036)], phase=1.7)
limb("Right lateral split", [(.68, .11, 1.88, .086), (.89, -.18, 2.17, .060),
     (1.06, -.35, 2.48, .032)], sides=12, samples=5, phase=1.2)
limb("Back swept crown arm", [(.12, .04, 2.00, .129), (.23, .32, 2.27, .10),
     (.43, .71, 2.42, .068), (.39, 1.05, 2.80, .040)], samples=5, phase=2.0)
limb("Back crown fork", [(.39, .63, 2.40, .064), (.08, .86, 2.62, .047),
     (-.08, 1.04, 2.90, .026)], sides=12, samples=5, phase=2.4)
limb("Front hanging scar limb", [(0, -.01, 1.47, .13), (.10, -.30, 1.61, .102),
     (.35, -.58, 1.63, .067), (.53, -.85, 1.80, .042)], sides=12, samples=5, phase=2.8)
limb("Fire stripped left high twig", [(-1.14, -.23, 2.00, .060), (-1.27, -.51, 2.22, .035),
     (-1.16, -.67, 2.43, .021)], sides=10, samples=4, phase=1.4)
limb("Upper snapped side tine", [(.03, .11, 2.59, .077), (.34, -.09, 2.80, .044),
     (.52, -.22, 2.91, .026)], sides=10, samples=4, phase=3.0)
limb("Lower downward broken twig", [(-.67, -.06, 1.51, .070), (-.96, .10, 1.44, .046),
     (-1.17, .16, 1.49, .032)], sides=10, samples=4, phase=.9)


def material(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Metallic"].default_value = 0
    bsdf.inputs["Roughness"].default_value = .92
    return mat, bsdf


bark, bsdf = material("Original charred longitudinal bark - baked PBR")
bark.use_backface_culling = True
nodes, links = bark.node_tree.nodes, bark.node_tree.links
coord = nodes.new("ShaderNodeTexCoord")
scale = nodes.new("ShaderNodeVectorMath")
scale.operation = "MULTIPLY"
scale.inputs[1].default_value = (8.8, 8.8, .29)
links.new(coord.outputs["Object"], scale.inputs[0])
grooves = nodes.new("ShaderNodeTexNoise")
grooves.inputs["Scale"].default_value = 3.9
grooves.inputs["Detail"].default_value = 2.0
grooves.inputs["Roughness"].default_value = .68
links.new(scale.outputs["Vector"], grooves.inputs["Vector"])
color = nodes.new("ShaderNodeValToRGB")
color.color_ramp.elements[0].position = .20
color.color_ramp.elements[0].color = (.020, .017, .015, 1)
color.color_ramp.elements[1].position = .81
color.color_ramp.elements[1].color = (.095, .089, .074, 1)
mid = color.color_ramp.elements.new(.56)
mid.color = (.048, .047, .040, 1)
links.new(grooves.outputs["Fac"], color.inputs["Fac"])
links.new(color.outputs["Color"], bsdf.inputs["Base Color"])
rough = nodes.new("ShaderNodeMapRange")
rough.inputs["To Min"].default_value = .84
rough.inputs["To Max"].default_value = .99
links.new(grooves.outputs["Fac"], rough.inputs["Value"])
links.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
bump = nodes.new("ShaderNodeBump")
bump.inputs["Strength"].default_value = .40
bump.inputs["Distance"].default_value = .017
links.new(grooves.outputs["Fac"], bump.inputs["Height"])
links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
bark.diffuse_color = (.054, .051, .043, 1)

# Editable source does not use the game bake as an excuse for smooth rods.
for obj in shapes.objects:
    obj.data.materials.append(bark)

bpy.context.view_layer.update()
copies = []
for source in list(shapes.objects):
    copy = source.copy()
    copy.data = source.data.copy()
    export.objects.link(copy)
    copies.append(copy)
bpy.ops.object.select_all(action="DESELECT")
for obj in copies:
    obj.select_set(True)
bpy.context.view_layer.objects.active = copies[0]
bpy.ops.object.join()
body = bpy.context.object
body.name = "AshTree_ContinuousTrunkRootsAndCrown"
body.data.materials.clear()
body.data.materials.append(bark)
source_bark = bark.copy()
source_bark.name = "Editable directional bark study - never exported"
for editable in shapes.objects:
    editable.data.materials.clear()
    editable.data.materials.append(source_bark)

# Crotches blend as wood, with no cylindrical socket seams. Retained source
# sweeps let an artist change proportions before repeating this small bake.
remesh = body.modifiers.new("Fused organic limb crotches", "REMESH")
remesh.mode = "VOXEL"
remesh.voxel_size = .022
remesh.use_smooth_shade = True
bpy.ops.object.modifier_apply(modifier=remesh.name)
smooth = body.modifiers.new("Quiet broad transitions", "SMOOTH")
smooth.factor = .40
smooth.iterations = 1
bpy.ops.object.modifier_apply(modifier=smooth.name)
triangles = sum(len(p.vertices) - 2 for p in body.data.polygons)
decimate = body.modifiers.new("Realtime silhouette budget", "DECIMATE")
decimate.ratio = min(1, 6100 / max(1, triangles))
bpy.ops.object.modifier_apply(modifier=decimate.name)
for polygon in body.data.polygons:
    polygon.use_smooth = True

# Actual broken wood is a visible material section with jagged geometry, rather
# than brighter stripes over an unbroken cylinder. Faces sit at limb ends.
wood, wood_bsdf = material("Original fire-exposed splinter wood")
wood_bsdf.inputs["Base Color"].default_value = (.145, .107, .065, 1)
wood_bsdf.inputs["Roughness"].default_value = .94
wood.diffuse_color = (.145, .107, .065, 1)
cap_vertices, cap_faces = [], []
for index, (centre, previous, radius) in enumerate([
    ((.19, .13, 3.045), (.015, .12, 2.61), .055),
    ((-.92, -.50, 1.66), (-.70, -.34, 1.50), .042),
    ((-1.43, -.27, 2.43), (-1.18, -.23, 2.03), .034),
    ((1.41, .21, 2.73), (1.18, .24, 2.30), .030),
    ((.39, 1.05, 2.80), (.43, .71, 2.42), .033),
]):
    centre = Vector(centre)
    direction = (centre - Vector(previous)).normalized()
    right = direction.cross(Vector((0, 1, 0))).normalized()
    across = right.cross(direction).normalized()
    origin = len(cap_vertices)
    cap_vertices.append(tuple(centre + direction * .016))
    for k in range(9):
        a = k * TAU / 9
        reach = radius * (1 + .11 * math.sin(k * 2.61 + index))
        cap_vertices.append(tuple(centre + (right * math.cos(a) + across * math.sin(a)) * reach + direction * (.015 + .026 * max(0, math.sin(k * 3.13 + index)))))
    for k in range(9):
        cap_faces.append((origin, origin + 1 + k, origin + 1 + (k + 1) % 9))
    # One rough triangular splinter carries the break profile at a readable size.
    tip = len(cap_vertices)
    a = (index * 1.71) % TAU
    base = centre + (right * math.cos(a) + across * math.sin(a)) * radius * .75
    cap_vertices.extend([tuple(base + across * .014), tuple(base - across * .015), tuple(base + direction * .085)])
    cap_faces.append((tip, tip + 1, tip + 2))
caps = mesh("AshTree_BrokenEndGrainSplinters", cap_vertices, cap_faces, export)
caps.data.materials.append(wood)
for polygon in caps.data.polygons:
    polygon.use_smooth = False

# A few trunk scars use shallow missing bark edges. Their dark interior reads
# from shape/shadow and costs no extra material or meshes after joining.
scar_parts = []
bpy.context.view_layer.update()
surface_bvh = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
for z, a, width, length in [(1.02, -1.61, .037, .31), (1.70, -1.86, .028, .22), (.53, -.62, .04, .25)]:
    centre = Vector((-.07, -.025, z))
    tangent = Vector((-math.sin(a), math.cos(a), 0))
    outward = Vector((math.cos(a), math.sin(a), 0))
    c, surface_normal, face_index, distance = surface_bvh.ray_cast(centre + outward * .7, -outward, 1.4)
    if c is None:
        continue
    c -= outward * .002
    vertices = [tuple(c - tangent * width - Vector((0, 0, length * .5))),
                tuple(c + tangent * width - Vector((0, 0, length * .42))),
                tuple(c + tangent * width * .6 + Vector((0, 0, length * .48))),
                tuple(c - tangent * width * .5 + Vector((0, 0, length * .56))),
                tuple(c + outward * .022)]
    part = mesh("Raised peeling scar edge", vertices, [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], export)
    part.data.materials.append(bark)
    scar_parts.append(part)
if scar_parts:
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    for part in scar_parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()

group = body.vertex_groups.new(name="WindWeight_RootFixed_CrownFlexible")
for vertex in body.data.vertices:
    weight = max(0, min(1, (vertex.co.z - .40) / 2.65)) ** 1.65
    group.add([vertex.index], weight, "REPLACE")
body["wind_mask_note"] = "Editable Blender vertex group only; no wind shader connected in this iteration"


def unwrap(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.12, island_margin=.018)
    bpy.ops.object.mode_set(mode="OBJECT")


unwrap(body)
unwrap(caps)
bpy.context.scene.render.engine = "CYCLES"
bpy.context.scene.cycles.device = "CPU"
bpy.context.scene.cycles.samples = 8
bpy.context.scene.render.bake.margin = 6
bpy.context.scene.render.bake.use_pass_direct = False
bpy.context.scene.render.bake.use_pass_indirect = False
bpy.context.scene.render.bake.use_pass_color = True


def bake(kind, non_color=False):
    texture = bpy.data.images.new("AshTree_Baked_%s_512" % kind, width=512, height=512, alpha=False)
    texture.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    target = nodes.new("ShaderNodeTexImage")
    target.image = texture
    for node in nodes:
        node.select = False
    target.select = True
    nodes.active = target
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.bake(type=kind)
    texture.pack()
    nodes.remove(target)
    return texture


base = bake("DIFFUSE")
rough_map = bake("ROUGHNESS", True)
normal_map = bake("NORMAL", True)
for node in list(nodes):
    if node.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL"):
        nodes.remove(node)
for label, texture, socket in [("Baked base color", base, "Base Color"), ("Baked roughness", rough_map, "Roughness")]:
    tex = nodes.new("ShaderNodeTexImage")
    tex.label = label
    tex.image = texture
    links.new(tex.outputs["Color"], bsdf.inputs[socket])
normal_tex = nodes.new("ShaderNodeTexImage")
normal_tex.image = normal_map
normal = nodes.new("ShaderNodeNormalMap")
normal.inputs["Strength"].default_value = .7
links.new(normal_tex.outputs["Color"], normal.inputs["Color"])
links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])

# Save both editable sweeps and completed realtime copy. Authoring sweeps are
# hidden in the saved scene and are never included in selection-only glTF.
for obj in shapes.objects:
    obj.hide_render = True
    obj.hide_set(True)
bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"
bpy.context.scene.world.color = (.035, .035, .035)
bpy.context.view_layer.update()
os.makedirs(os.path.dirname(SOURCE), exist_ok=True)
os.makedirs(os.path.dirname(STAGED), exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=SOURCE)
bpy.ops.object.select_all(action="DESELECT")
for obj in export.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.export_scene.gltf(filepath=STAGED, export_format="GLB", use_selection=True,
                          export_yup=True, export_apply=True, export_texcoords=True,
                          export_normals=True, export_materials="EXPORT", export_image_format="AUTO")


def glb_stats(path):
    with open(path, "rb") as stream:
        blob = stream.read()
    length, chunk_type = struct.unpack_from("II", blob, 12)
    content = json.loads(blob[20:20 + length])
    vertices = sum(content["accessors"][p["attributes"]["POSITION"]]["count"] for m in content["meshes"] for p in m["primitives"])
    triangles = sum(content["accessors"][p["indices"]]["count"] // 3 for m in content["meshes"] for p in m["primitives"])
    primitives = sum(len(m["primitives"]) for m in content["meshes"])
    bounds = []
    for m in content["meshes"]:
        for p in m["primitives"]:
            acc = content["accessors"][p["attributes"]["POSITION"]]
            bounds.append((acc.get("min"), acc.get("max")))
    return {"vertices": vertices, "triangles": triangles, "meshes": len(content["meshes"]),
            "material_draws": primitives, "textures": len(content.get("images", [])), "bytes": len(blob), "bounds": bounds}


old = glb_stats(os.path.join(ROOT, "assets", "models", "dead_tree.glb"))
new = glb_stats(STAGED)
assert new["triangles"] < 10000 and new["meshes"] <= 3 and new["material_draws"] <= 3
assert new["textures"] >= 3
print("WASTELAND_TREE_V2_STAGED", json.dumps({"old": old, "new": new}, ensure_ascii=False))
