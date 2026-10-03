"""Original ash-outpost iron lamp: editable source + self-contained glTF PBR.

Run with Blender 4.5 in background. This script only creates the v2 source and a
staged GLB under build; the release owner promotes that file after coordination.
The old watch_beacon asset and the playable scene are never modified here.
"""
import math
import os
import random
from collections import defaultdict

import bpy
import numpy as np
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "art_source", "outpost", "watch_beacon_v2.blend")
STAGED_GLB = os.path.join(ROOT, "build", "watch-beacon-v2-staged.glb")
TAU = math.tau

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for old in list(bpy.data.materials):
    if old.users == 0:
        bpy.data.materials.remove(old)

source_collection = bpy.data.collections.new("Editable Watch Beacon V2")
bpy.context.scene.collection.children.link(source_collection)


def to_source(obj):
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    source_collection.objects.link(obj)
    return obj


def image(name, values, non_color=False):
    size = values.shape[0]
    texture = bpy.data.images.new(name, width=size, height=size, alpha=False)
    texture.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    pixels = np.ones((size, size, 4), dtype=np.float32)
    if values.ndim == 2:
        pixels[:, :, :3] = values[:, :, None]
    else:
        pixels[:, :, :3] = values[:, :, :3]
    texture.pixels.foreach_set(pixels.ravel())
    texture.pack()
    return texture


def noise(size, cells, seed):
    rng = np.random.default_rng(seed)
    tile = rng.random((cells, cells)).astype(np.float32)
    axis = np.arange(size, dtype=np.float32) * cells / size
    low = np.floor(axis).astype(np.int32)
    f = axis - low
    f = f * f * (3.0 - 2.0 * f)
    hi = (low + 1) % cells
    rows = tile[low[:, None], low[None, :]] * (1 - f[None, :])
    rows += tile[low[:, None], hi[None, :]] * f[None, :]
    top = tile[hi[:, None], low[None, :]] * (1 - f[None, :])
    top += tile[hi[:, None], hi[None, :]] * f[None, :]
    return rows * (1 - f[:, None]) + top * f[:, None]


def pbr_material(name, color, metallic, roughness, textured=None, emission=0, alpha=1):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*color, alpha)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, alpha)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Alpha"].default_value = alpha
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*color, 1)
        bsdf.inputs["Emission Strength"].default_value = emission
    if alpha < 1:
        material.surface_render_method = "DITHERED"
        material.use_backface_culling = False
    if textured:
        size = 1024
        broad = noise(size, 9, 584)
        middle = noise(size, 37, 171)
        grain = noise(size, 183, 442)
        if textured == "iron":
            base = np.array([0.175, 0.196, 0.203], dtype=np.float32)
            variation = 0.87 + broad * 0.20 + (grain - 0.5) * 0.055
            rust = np.clip((broad - 0.64) * 2.0, 0, 0.25) * np.clip((middle - 0.4) * 2.0, 0, 1)
            colors = base[None, None, :] * variation[:, :, None]
            colors = colors * (1 - rust[:, :, None]) + np.array([0.26, 0.153, 0.078]) * rust[:, :, None]
            rough = np.clip(roughness + (broad - 0.5) * 0.13 + rust * 0.27, 0.48, 0.85)
            height = (middle - 0.5) * 0.0018 + (grain - 0.5) * 0.00048
        else:
            base = np.array([0.335, 0.343, 0.329], dtype=np.float32)
            colors = base[None, None, :] * (0.88 + broad * 0.20 + (grain - 0.5) * 0.13)[:, :, None]
            colors += ((middle - 0.5) * 0.013)[:, :, None] * np.array([1.0, 0.90, 0.70])
            rough = np.clip(roughness + (middle - 0.5) * 0.06, 0.87, 0.99)
            height = (middle - 0.5) * 0.0020 + (grain - 0.5) * 0.0010
        dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * size * 0.5
        dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * size * 0.5
        normal = np.stack((-dx, -dy, np.ones_like(dx)), axis=2)
        normal /= np.linalg.norm(normal, axis=2)[:, :, None]
        normal = normal * 0.5 + 0.5
        maps = [("Base", image(name + " Base", np.clip(colors, 0, 1)), "Base Color"),
                ("Roughness", image(name + " Roughness", rough, True), "Roughness")]
        for label, bitmap, socket in maps:
            node = nodes.new("ShaderNodeTexImage")
            node.name = label + " - packed original texture"
            node.image = bitmap
            links.new(node.outputs["Color"], bsdf.inputs[socket])
        normal_bitmap = image(name + " Normal", normal, True)
        normal_image = nodes.new("ShaderNodeTexImage")
        normal_image.image = normal_bitmap
        normal_node = nodes.new("ShaderNodeNormalMap")
        normal_node.inputs["Strength"].default_value = 0.70
        links.new(normal_image.outputs["Color"], normal_node.inputs["Color"])
        links.new(normal_node.outputs["Normal"], bsdf.inputs["Normal"])
    return material


iron = pbr_material("Beacon V2 ash-worn forged iron", (0.035, 0.043, 0.047), 0.76, 0.63, "iron")
stone = pbr_material("Beacon V2 carved basalt footing", (0.092, 0.096, 0.087), 0.0, 0.95, "stone")
edge_iron = pbr_material("Beacon V2 exposed iron edge", (0.105, 0.119, 0.120), 0.80, 0.49)
bronze = pbr_material("Beacon V2 dark oxidized bronze", (0.145, 0.080, 0.029), 0.67, 0.59)
soot = pbr_material("Beacon V2 blackened service seams", (0.019, 0.025, 0.028), 0.27, 0.84)
glass = pbr_material("Beacon V2 enclosed amber lamp glass", (0.34, 0.245, 0.12), 0.0, 0.19, alpha=0.22)
glass.node_tree.nodes.get("Principled BSDF").inputs["Coat Weight"].default_value = 0.28
core = pbr_material("Beacon V2 protected incandescent core", (0.95, 0.47, 0.085), 0.0, 0.47, emission=2.4)
ceramic = pbr_material("Beacon V2 pale refractory ceramic", (0.36, 0.33, 0.25), 0.0, 0.85)
signal = pbr_material("Beacon V2 small teal status lamps", (0.11, 0.40, 0.40), 0.0, 0.44, emission=0.8)


def mesh(name, vertices, faces, material, smooth=False, uvs=None):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    data.materials.append(material)
    for polygon in data.polygons:
        polygon.use_smooth = smooth
    obj = bpy.data.objects.new(name, data)
    source_collection.objects.link(obj)
    if uvs:
        layer = data.uv_layers.new(name="UVMap")
        for polygon in data.polygons:
            for loop in polygon.loop_indices:
                layer.data[loop].uv = uvs[data.loops[loop].vertex_index]
    return obj


def bevel(obj, width=0.025, segments=3):
    modifier = obj.modifiers.new("Small forged or worn arris", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    obj.modifiers.new("Weighted surface normals", "WEIGHTED_NORMAL")
    return obj


def lathe(name, profile, material, sides=64, smooth=True):
    vertices, uv = [], []
    radius = max(r for z, r in profile)
    for z, r in profile:
        for i in range(sides + 1):
            angle = TAU * i / sides
            vertices.append((r * math.cos(angle), r * math.sin(angle), z))
            uv.append((angle * radius * 0.65, z * 0.65))
    ring = sides + 1
    faces = [(j * ring + i, j * ring + i + 1, (j + 1) * ring + i + 1, (j + 1) * ring + i)
             for j in range(len(profile) - 1) for i in range(sides)]
    faces.extend([tuple(reversed(range(ring))), tuple((len(profile) - 1) * ring + i for i in range(ring))])
    return mesh(name, vertices, faces, material, smooth, uv)


def torus(name, major, minor, z, material, rotation=None, location=None):
    bpy.ops.mesh.primitive_torus_add(major_segments=64, minor_segments=10,
                                   location=location or (0, 0, z), major_radius=major, minor_radius=minor)
    obj = to_source(bpy.context.object)
    obj.name = name
    if rotation:
        obj.rotation_euler = rotation
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def box(name, location, dimensions, material, width=0.02, rotation=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = to_source(bpy.context.object)
    obj.name = name
    obj.scale = dimensions
    if rotation:
        obj.rotation_euler = rotation
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    return bevel(obj, width)


def curve(name, points, radius, material):
    data = bpy.data.curves.new(name, "CURVE")
    data.dimensions = "3D"
    data.resolution_u = 12
    data.bevel_depth = radius
    data.bevel_resolution = 3
    data.use_fill_caps = True
    spline = data.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, position in zip(spline.bezier_points, points):
        point.co = position
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    data.materials.append(material)
    obj = bpy.data.objects.new(name, data)
    source_collection.objects.link(obj)
    return obj


def radial(angle, radius, z):
    return (radius * math.cos(angle), radius * math.sin(angle), z)


def stone_sector(index):
    rng = random.Random(116 + index)
    begin = index * TAU / 8 + 0.009
    end = (index + 1) * TAU / 8 - 0.009
    profile = [(0.025, 2.47), (0.075, 2.53), (0.22, 2.51), (0.32, 2.38)]
    vertices = []
    steps = 8
    for z, radius in profile:
        for i in range(steps + 1):
            angle = begin + (end - begin) * i / steps
            wear = 0.014 * math.sin(angle * 11.3) + rng.uniform(-0.012, 0.012)
            vertices.append(radial(angle, radius + wear, z + rng.uniform(-0.006, 0.006)))
    for z, radius in profile:
        for i in range(steps + 1):
            angle = begin + (end - begin) * i / steps
            vertices.append(radial(angle, 0.06, z))
    ring = steps + 1
    inner = len(profile) * ring
    faces = []
    for layer in range(len(profile) - 1):
        for i in range(steps):
            a = layer * ring + i
            faces.append((a, a + 1, a + ring + 1, a + ring))
    for i in range(steps):
        faces.append((i, inner + i, inner + i + 1, i + 1))
        a = (len(profile) - 1) * ring + i
        faces.append((a, a + 1, inner + a + 1, inner + a))
    faces.append(tuple([i * ring for i in range(len(profile))] +
                       [inner + i * ring for i in reversed(range(len(profile)))]))
    faces.append(tuple([i * ring + steps for i in reversed(range(len(profile)))] +
                       [inner + i * ring + steps for i in range(len(profile))]))
    return bevel(mesh("Individual cut footing stone %02d" % index, vertices, faces, stone), 0.022, 2)


# A low, stable foundation leads the silhouette; separate stones retain editable
# seams and a restrained, slightly irregular perimeter rather than stacked discs.
for sector in range(8):
    stone_sector(sector)
lathe("Raised basalt collar", [(0.29, 1.87), (0.35, 1.90), (0.43, 1.83), (0.45, 1.58)], stone)
lathe("Continuous tapered generator housing", [(0.43, 1.13), (0.49, 1.18), (0.62, 1.13),
      (0.99, 0.95), (1.20, 0.79), (1.35, 0.77)], iron)
lathe("Worn generator top rim", [(1.25, 0.81), (1.28, 0.89), (1.37, 0.89), (1.40, 0.76)], edge_iron)
lathe("Lamp socket neck", [(1.34, 0.55), (1.44, 0.53), (1.66, 0.42), (1.82, 0.50)], iron)
lathe("Refractory lamp support", [(1.72, 0.47), (1.80, 0.55), (1.87, 0.54), (1.91, 0.43)], ceramic)

# Six legible bent load-bearing members meet the foundation and cap. Their dark
# inner members support the glass without turning the object into a wire cage.
for i in range(6):
    angle = i * TAU / 6 + math.pi / 6
    box("Bolted strut footing %d" % i, radial(angle, 1.41, 0.50), (0.35, 0.28, 0.13),
        iron, 0.025, (0, 0, angle))
    points = [radial(angle, 1.42, 0.53), radial(angle, 1.25, 1.12),
              radial(angle, 0.98, 1.77), radial(angle, 0.83, 2.36),
              radial(angle, 0.75, 3.18), radial(angle, 0.48, 3.40)]
    curve("Continuous forged bearing arch %d" % i, points, 0.070, iron)
    curve("Inner leaded glass mullion %d" % i,
          [radial(angle, 0.48, 1.90), radial(angle, 0.64, 2.14),
           radial(angle, 0.69, 2.67), radial(angle, 0.61, 3.17)], 0.027, bronze)
    box("Anchor bolt %d" % i, radial(angle, 1.42, 0.60), (0.085, 0.085, 0.045),
        edge_iron, 0.008, (0, 0, angle))

# The broad smooth closed lens encloses a much smaller incandescent element.
# No faceted orange jewel is left outside the cage.
lathe("Closed curved protective glass", [(1.91, 0.02), (1.94, 0.43), (2.10, 0.59),
      (2.40, 0.66), (2.74, 0.66), (3.05, 0.59), (3.18, 0.44), (3.20, 0.02)], glass, 80)
lathe("Protected rounded incandescent chamber", [(2.03, 0.03), (2.09, 0.22), (2.28, 0.31),
      (2.73, 0.30), (2.97, 0.22), (3.02, 0.03)], core, 64)
torus("Lower sealing bead", 0.46, 0.038, 1.96, bronze)
torus("Upper sealing bead", 0.45, 0.035, 3.18, bronze)
for z in [2.14, 2.39, 2.68, 2.88]:
    torus("Internal dark resistance loop %.2f" % z, 0.315 if z < 2.8 else 0.26, 0.015, z, soot)

# Compact umbrella profile has no broad plate hiding the light from the game's
# fixed elevated southern viewpoint. A stepped vent stack completes the outline.
lathe("Forged rain hood continuous profile", [(3.17, 0.44), (3.20, 0.75), (3.24, 0.78),
      (3.28, 0.75), (3.37, 0.58), (3.46, 0.40), (3.50, 0.20)], iron, 64)
lathe("Vent hood crown", [(3.45, 0.18), (3.50, 0.23), (3.58, 0.23),
      (3.63, 0.16), (3.68, 0.045)], edge_iron, 48)
for i in range(6):
    angle = TAU * i / 6
    curve("Radial rain hood seam %d" % i,
          [radial(angle, 0.22, 3.505), radial(angle, 0.41, 3.47),
           radial(angle, 0.60, 3.39), radial(angle, 0.75, 3.285)], 0.012, soot)

# Service hardware has a purpose and sits under the visual focal point. A single
# front shield, pull handle and two dim status lenses read as a repairable machine.
box("Front recessed service hatch", (0, -0.927, 0.88), (0.60, 0.055, 0.53), soot, 0.050)
box("Chamfered inspection hatch plate", (0, -0.966, 0.88), (0.53, 0.045, 0.46), iron, 0.038)
curve("Forged service door pull", [(-0.16, -1.014, 0.78), (-0.16, -1.06, 0.89),
      (0.16, -1.06, 0.89), (0.16, -1.014, 0.78)], 0.020, edge_iron)
for x in [-0.18, 0.18]:
    box("Small service status window", (x, -1.004, 1.05), (0.075, 0.018, 0.055), signal, 0.011)
for i in range(4):
    angle = i * math.pi / 2
    curve("Curved anchored grounding conduit %d" % i,
          [radial(angle, 1.00, 0.71), radial(angle, 1.45, 0.39),
           radial(angle + 0.11, 2.00, 0.35), radial(angle + 0.12, 2.20, 0.30)], 0.038, soot)
    box("Ground cable clamp %d" % i, radial(angle + 0.11, 2.01, 0.36),
        (0.12, 0.21, 0.035), iron, 0.008, (0, 0, angle))

# One restrained ward inscription, broad enough to see at a closer gameplay zoom.
for side in [-1, 1]:
    curve("Front ward chevron %d" % side,
          [(0, -1.02, 0.64), (side * 0.15, -1.02, 0.71), (side * 0.20, -1.02, 0.73)],
          0.011, bronze)


def ensure_uv(obj):
    if obj.type != "MESH" or obj.data.uv_layers:
        return
    layer = obj.data.uv_layers.new(name="UVMap")
    matrix = obj.matrix_world
    for polygon in obj.data.polygons:
        dominant = max(range(3), key=lambda axis: abs(polygon.normal[axis]))
        axes = [(1, 2), (0, 2), (0, 1)][dominant]
        for loop in polygon.loop_indices:
            vertex = matrix @ obj.data.vertices[obj.data.loops[loop].vertex_index].co
            layer.data[loop].uv = (vertex[axes[0]] * 0.65, vertex[axes[1]] * 0.65)


for obj in source_collection.objects:
    ensure_uv(obj)
bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"
bpy.context.scene.world.color = (0.035, 0.035, 0.035)
bpy.context.view_layer.update()
os.makedirs(os.path.dirname(SOURCE), exist_ok=True)
os.makedirs(os.path.dirname(STAGED_GLB), exist_ok=True)
# Retain the live Bézier bearing arches and all individually editable source parts.
bpy.ops.wm.save_as_mainfile(filepath=SOURCE)

export_collection = bpy.data.collections.new("Temporary glTF export meshes")
bpy.context.scene.collection.children.link(export_collection)
copies = []
for source in list(source_collection.objects):
    obj = source.copy()
    obj.data = source.data.copy()
    export_collection.objects.link(obj)
    copies.append(obj)
bpy.ops.object.select_all(action="DESELECT")
for obj in copies:
    obj.select_set(True)
bpy.context.view_layer.objects.active = copies[0]
bpy.ops.object.convert(target="MESH")
copies = list(export_collection.objects)
for obj in copies:
    ensure_uv(obj)
groups = defaultdict(list)
for obj in copies:
    groups[tuple(material.name for material in obj.data.materials)].append(obj)
for objects in groups.values():
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
bpy.ops.object.select_all(action="DESELECT")
for obj in export_collection.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = next(iter(export_collection.objects))
bpy.ops.export_scene.gltf(filepath=STAGED_GLB, export_format="GLB", use_selection=True,
                          export_yup=True, export_apply=True, export_texcoords=True,
                          export_normals=True, export_materials="EXPORT", export_image_format="AUTO")
polygons = sum(len(obj.data.polygons) for obj in export_collection.objects)
print("WATCH_BEACON_V2_STAGED", STAGED_GLB, "source_parts", len(source_collection.objects),
      "export_meshes", len(export_collection.objects), "polygons", polygons)
