"""Generate only the original enlarged castle terrain with Blender 4.5.

The castle dimensions come from scripts/outpost_layout.gd. This script never
imports create_outpost.py or regenerates its other assets. Blender coordinates
are (world x, -world z, world height), so glTF's Y-up conversion preserves the
actual Godot southern entrance at positive Z rather than mirroring the ramp.
"""
from pathlib import Path
import math
import random
import re

import bpy


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "art_source" / "outpost" / "castle_ground.blend"
RUNTIME = ROOT / "assets" / "models" / "castle_ground.glb"
LAYOUT_NAMES = (
    "FORT_HEIGHT", "FORT_INNER", "FORT_OUTER", "WALL_CENTER", "GATE_HALF",
    "RAMP_INNER_HALF", "RAMP_OUTER_HALF", "RAMP_SURFACE_HALF", "RAMP_TOP",
    "RAMP_WALL_START", "RAMP_WALL_END", "RAMP_END", "FORT_TERRAIN_EDGE",
)


def read_layout():
    source = (ROOT / "scripts" / "outpost_layout.gd").read_text(encoding="utf-8")
    dimensions = {}
    for name in LAYOUT_NAMES:
        match = re.search(rf"^const {name} := ([0-9]+(?:\.[0-9]+)?)$", source, re.MULTILINE)
        if match is None:
            raise ValueError(f"Missing numeric shared layout constant: {name}")
        dimensions[name] = float(match.group(1))
    return dimensions


LAYOUT = read_layout()


def height(x, z):
    edge = max(abs(x), abs(z))
    if z > LAYOUT["RAMP_TOP"] and abs(x) < LAYOUT["RAMP_SURFACE_HALF"]:
        rise = (LAYOUT["RAMP_END"] - z) / (LAYOUT["RAMP_END"] - LAYOUT["RAMP_TOP"])
    else:
        rise = (LAYOUT["FORT_TERRAIN_EDGE"] - edge) / (
            LAYOUT["FORT_TERRAIN_EDGE"] - LAYOUT["RAMP_TOP"]
        )
    rise = max(0.0, min(1.0, rise))
    return LAYOUT["FORT_HEIGHT"] * rise * rise * (3.0 - 2.0 * rise)


def material(name, color, metallic=0.0, roughness=0.88):
    result = bpy.data.materials.new(name)
    result.diffuse_color = (*color, 1.0)
    result.use_nodes = True
    principled = result.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (*color, 1.0)
    principled.inputs["Metallic"].default_value = metallic
    principled.inputs["Roughness"].default_value = roughness
    return result


def mesh(name, vertices, faces, mat, smooth=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata([(x, -z, h) for x, z, h in vertices], [],
                     [tuple(reversed(face)) for face in faces])
    data.update()
    data.materials.append(mat)
    for face in data.polygons:
        face.use_smooth = smooth
    node = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(node)
    return node


def box(name, point, size, mat, bevel=0.0, yaw=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(point[0], -point[1], point[2]))
    node = bpy.context.object
    node.name = name
    node.scale = size
    node.rotation_euler.z = -yaw
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    node.data.materials.append(mat)
    if bevel > 0.0:
        modifier = node.modifiers.new("Weathered edges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        node.modifiers.new("Weighted stone normals", "WEIGHTED_NORMAL")
    return node


def terrain(soil):
    # Preserve the whole wasteland bounds rather than scaling the world. Extra
    # half-metre rows resolve the enlarged smoothstep slopes; exact breakpoint
    # rows keep the authored ramp flanks and wall transitions in agreement.
    xs = set(float(i) for i in range(-126, 127))
    zs = set(float(i) for i in range(-110, 111))
    xs.update(i * 0.5 for i in range(-34, 35))
    zs.update(i * 0.5 for i in range(-34, 54))
    # The outer embankment rises five metres over only 2.5 metres. Quarter
    # metre rows keep triangle interpolation within two centimetres there.
    for side in [-1, 1]:
        for step in range(13):
            boundary = side * (13.0 + step * 0.25)
            xs.add(boundary)
            zs.add(boundary)
    for name in ["FORT_INNER", "FORT_OUTER", "WALL_CENTER", "FORT_TERRAIN_EDGE", "RAMP_TOP"]:
        xs.update([LAYOUT[name], -LAYOUT[name]])
        zs.update([LAYOUT[name], -LAYOUT[name]])
    for name in ["RAMP_INNER_HALF", "RAMP_OUTER_HALF", "RAMP_SURFACE_HALF"]:
        boundary = LAYOUT[name] + (0.001 if name == "RAMP_SURFACE_HALF" else 0.0)
        xs.update([boundary, -boundary])
    # The height rule has a steep exposed flank outside its 3.2 m surface.
    # A narrow explicit strip prevents a full one-metre triangle from pulling
    # the visible edge away from the actual playable ramp.
    xs.update([LAYOUT["RAMP_SURFACE_HALF"] - 0.001, -LAYOUT["RAMP_SURFACE_HALF"] + 0.001])
    for name in ["RAMP_WALL_START", "RAMP_WALL_END", "RAMP_END"]:
        zs.add(LAYOUT[name])
    xs, zs = sorted(xs), sorted(zs)
    vertices = [(x, z, height(x, z)) for z in zs for x in xs]
    faces = []
    width = len(xs)
    for row in range(len(zs) - 1):
        for column in range(width - 1):
            first = row * width + column
            faces.extend([(first, first + 1, first + width + 1), (first, first + width + 1, first + width)])
    node = mesh("Sculpted enlarged castle wasteland", vertices, faces, soil, True)
    node["height_source"] = "scripts/outpost_layout.gd terrain_height"


def stone_walls(stone, coping):
    inner = LAYOUT["FORT_INNER"]
    outer = LAYOUT["FORT_OUTER"]
    center = LAYOUT["WALL_CENTER"]
    thickness = outer - inner
    top = LAYOUT["FORT_HEIGHT"]

    def segment(start, end, axis, side):
        length = end - start
        sections = math.ceil(length / 2.1)
        stride = length / sections
        for index in range(sections):
            along = start + (index + 0.5) * stride
            location = (side * center, along, top * 0.5) if axis == "x" else (along, side * center, top * 0.5)
            size = (thickness, stride + 0.018, top) if axis == "x" else (stride + 0.018, thickness, top)
            box("Castle retaining wall", location, size, stone, 0.045)
            lip = (location[0], location[1], top + 0.04)
            lip_size = (thickness, stride + 0.018, 0.16) if axis == "x" else (stride + 0.018, thickness, 0.16)
            box("Castle stone parapet coping", lip, lip_size, coping, 0.018)

    for side in [-1, 1]:
        segment(-outer, outer, "x", side)
    segment(-outer, outer, "z", -1)
    segment(-outer, -LAYOUT["GATE_HALF"], "z", 1)
    segment(LAYOUT["GATE_HALF"], outer, "z", 1)
    # Ramp side faces use the same start/end and exact collision width. Their
    # sloping top vertices follow the shared terrain function at both ends.
    sections = 22
    start, end = LAYOUT["RAMP_WALL_START"], LAYOUT["RAMP_WALL_END"]
    for index in range(sections):
        near = start + (end - start) * index / sections
        far = start + (end - start) * (index + 1) / sections
        for side in [-1, 1]:
            x0 = min(side * LAYOUT["RAMP_INNER_HALF"], side * LAYOUT["RAMP_OUTER_HALF"])
            x1 = max(side * LAYOUT["RAMP_INNER_HALF"], side * LAYOUT["RAMP_OUTER_HALF"])
            hn, hf = height(0.0, near), height(0.0, far)
            vertices = [(x0, near, 0), (x1, near, 0), (x1, far, 0), (x0, far, 0),
                        (x0, near, hn), (x1, near, hn), (x1, far, hf), (x0, far, hf)]
            faces = [(0, 3, 2, 1), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7), (4, 5, 6, 7)]
            mesh("Castle causeway stone flank", vertices, faces, stone)
            crown = [(x0, near, hn), (x1, near, hn), (x1, far, hf), (x0, far, hf)]
            mesh("Castle causeway worn coping", crown, [(0, 1, 2, 3)], coping)


def courtyard(concrete, fracture, rng):
    # Four times the usable floor area, with small fitted slabs around the
    # beacon and long restrained aisle fragments across the expanded yard.
    # Slabs finish on the gameplay floor instead of adding walkable height.
    for row in range(-10, 11):
        for column in range(-10, 11):
            if rng.random() < 0.16:
                continue
            x, z = column * 1.18, row * 1.18
            size = (1.05, 1.05, 0.08)
            box("Fractured castle courtyard", (x, z, LAYOUT["FORT_HEIGHT"] - 0.04), size,
                concrete if rng.random() < 0.7 else fracture, 0.012)
    for arm in range(4):
        direction = arm * math.pi / 2.0
        for distance in range(15, 108):
            for side in [-1, 0, 1]:
                if rng.random() < 0.16:
                    continue
                x = math.cos(direction) * distance * 0.92 - math.sin(direction) * side * 1.07
                z = math.sin(direction) * distance * 0.92 + math.cos(direction) * side * 1.07
                box("Broken evacuation road", (x, z, height(x, z) - 0.045), (0.74, 0.82, 0.075),
                    fracture if rng.random() < 0.57 else concrete, 0.008, rng.uniform(-0.16, 0.16))


def outskirts_debris(fracture, rust, rng):
    for index in range(400):
        angle = rng.random() * math.tau
        radius = rng.uniform(30.0, 105.0)
        x, z = radius * math.cos(angle), radius * math.sin(angle)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1.0, location=(x, -z, -0.07))
        node = bpy.context.object
        node.name = "Half buried outer slag"
        node.scale = (0.12 + rng.random() * 0.24, 0.10 + rng.random() * 0.24, 0.09 + rng.random() * 0.17)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        node.data.materials.append(fracture if index % 3 else rust)


def group_meshes():
    groups = {}
    for node in bpy.context.scene.objects:
        if node.type != "MESH" or node.name.startswith("Sculpted"):
            continue
        groups.setdefault(tuple(mat.name for mat in node.data.materials), []).append(node)
    for nodes in groups.values():
        if len(nodes) < 2:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for node in nodes:
            node.select_set(True)
        bpy.context.view_layer.objects.active = nodes[0]
        bpy.ops.object.join()


def main():
    if bpy.app.version[:2] != (4, 5):
        raise RuntimeError("Use Blender 4.5 to preserve the agreed editable source version")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)
    soil = material("Ash compacted earth", (0.075, 0.072, 0.061))
    concrete = material("Weathered concrete", (0.13, 0.14, 0.13))
    fracture = material("Concrete fracture", (0.060, 0.075, 0.074))
    rust = material("Old iron rust", (0.17, 0.082, 0.046), 0.42, 0.82)
    rng = random.Random(274)
    terrain(soil)
    courtyard(concrete, fracture, rng)
    stone_walls(fracture, concrete)
    outskirts_debris(fracture, rust, rng)
    group_meshes()
    bpy.context.scene["original_asset"] = "Riftward Nightfall enlarged castle terrain"
    bpy.context.scene["layout_dimensions"] = repr(LAYOUT)
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
    bpy.ops.export_scene.gltf(filepath=str(RUNTIME), export_format="GLB", export_yup=True)
    polygons = sum(len(node.data.polygons) for node in bpy.context.scene.objects if node.type == "MESH")
    print("CASTLE_GROUND_READY", polygons, "source", SOURCE.name, "runtime", RUNTIME.name)


if __name__ == "__main__":
    main()
