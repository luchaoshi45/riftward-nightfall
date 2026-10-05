#!/usr/bin/env python3
"""Read the production GLB and guard against courtyard/ramp depth competition.

No Blender/Godot installation or third-party package is required. Shared edges
are allowed; only complete triangles duplicated across materials are rejected.
This checks actual transformed vertex data, never a joined mesh's AABB.
Ramp coping/terrain intersections are checked over every overlapping projected
triangle: the height difference is linear, so its extrema lie at clip vertices.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import itertools
import json
import math
from pathlib import Path
import re
import struct
import sys


ROOT = Path(__file__).resolve().parents[1]
IDENTITY = (1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1.)
FORMATS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
RAMP_NAMES = ("RAMP_INNER_HALF", "RAMP_OUTER_HALF", "RAMP_WALL_START", "RAMP_WALL_END")


def ramp_dimensions():
    source = (ROOT / "scripts/outpost_layout.gd").read_text(encoding="utf-8")
    dimensions = {}
    for name in RAMP_NAMES:
        match = re.search(rf"^const {name} := ([0-9]+(?:\.[0-9]+)?)$", source, re.MULTILINE)
        if match is None:
            raise ValueError(f"Missing numeric shared layout constant: {name}")
        dimensions[name] = float(match.group(1))
    return dimensions


def projected_bounds(triangle):
    return (min(point[0] for point in triangle), min(point[2] for point in triangle),
            max(point[0] for point in triangle), max(point[2] for point in triangle))


def bounds_overlap(first, second, tolerance=0.):
    return (first[0] <= second[2] + tolerance and second[0] <= first[2] + tolerance
            and first[1] <= second[3] + tolerance and second[1] <= first[3] + tolerance)


def polygon_area(points):
    if len(points) < 3:
        return 0.
    return sum(first[0] * second[1] - first[1] * second[0]
               for first, second in zip(points, points[1:] + points[:1])) * .5


def triangle_overlap(first, second):
    """Return their convex XZ overlap, including new edge-intersection vertices."""
    polygon = [(point[0], point[2]) for point in first]
    clip = [(point[0], point[2]) for point in second]
    if polygon_area(clip) < 0.:
        clip.reverse()
    for edge_start, edge_end in zip(clip, clip[1:] + clip[:1]):
        if not polygon:
            break
        edge_x = edge_end[0] - edge_start[0]
        edge_z = edge_end[1] - edge_start[1]

        def distance(point):
            return edge_x * (point[1] - edge_start[1]) - edge_z * (point[0] - edge_start[0])

        output = []
        previous = polygon[-1]
        previous_distance = distance(previous)
        for current in polygon:
            current_distance = distance(current)
            previous_inside = previous_distance >= -1e-12
            current_inside = current_distance >= -1e-12
            if current_inside != previous_inside:
                weight = previous_distance / (previous_distance - current_distance)
                weight = max(0., min(1., weight))
                output.append(tuple(previous[axis] + weight * (current[axis] - previous[axis])
                                    for axis in range(2)))
            if current_inside:
                output.append(current)
            previous, previous_distance = current, current_distance
        polygon = output
    compact = []
    for point in polygon:
        if not compact or max(abs(point[axis] - compact[-1][axis]) for axis in range(2)) > 1e-10:
            compact.append(point)
    if len(compact) > 1 and max(abs(compact[0][axis] - compact[-1][axis]) for axis in range(2)) <= 1e-10:
        compact.pop()
    return compact


def triangle_height(triangle, point):
    a, b, c = triangle
    dx1, dz1 = b[0] - a[0], b[2] - a[2]
    dx2, dz2 = c[0] - a[0], c[2] - a[2]
    determinant = dx1 * dz2 - dx2 * dz1
    if abs(determinant) < 1e-14:
        raise ValueError("Ramp depth inspection encountered a vertical/degenerate triangle")
    px, pz = point[0] - a[0], point[1] - a[2]
    u = (px * dz2 - pz * dx2) / determinant
    v = (dx1 * pz - dz1 * px) / determinant
    return a[1] + u * (b[1] - a[1]) + v * (c[1] - a[1])


def is_ramp_coping(triangle, material_name, dimensions, tolerance):
    if material_name != "Weathered concrete":
        return False
    inner, outer = dimensions["RAMP_INNER_HALF"], dimensions["RAMP_OUTER_HALF"]
    start, end = dimensions["RAMP_WALL_START"], dimensions["RAMP_WALL_END"]
    # Each authored cap spans both exact strip edges. Material and footprint
    # together exclude nearby retaining-wall bevels and evacuation-road slabs.
    xs = [abs(point[0]) for point in triangle]
    if not (abs(min(xs) - inner) <= tolerance and abs(max(xs) - outer) <= tolerance):
        return False
    if not all(min(abs(x - inner), abs(x - outer)) <= tolerance for x in xs):
        return False
    if not (all(point[0] > 0. for point in triangle) or all(point[0] < 0. for point in triangle)):
        return False
    if not all(start - tolerance <= point[2] <= end + tolerance for point in triangle):
        return False
    a, b, c = triangle
    normal_y = ((b[2] - a[2]) * (c[0] - a[0])
                - (b[0] - a[0]) * (c[2] - a[2]))
    return normal_y > tolerance * tolerance


def inspect_ramp_coping(coping, terrain, dimensions, tolerance):
    errors = []
    areas = {"left": 0., "right": 0.}
    covered_faces = 0
    overlaps = 0
    minimum, maximum = math.inf, -math.inf
    witness = None
    terrain_bounds = [(triangle, projected_bounds(triangle)) for triangle in terrain]
    for crown in coping:
        footprint = [(point[0], point[2]) for point in crown]
        area = abs(polygon_area(footprint))
        side = "left" if crown[0][0] < 0. else "right"
        areas[side] += area
        overlap_area = 0.
        bounds = projected_bounds(crown)
        for ground, ground_bounds in terrain_bounds:
            if not bounds_overlap(bounds, ground_bounds, tolerance):
                continue
            polygon = triangle_overlap(crown, ground)
            clipped_area = abs(polygon_area(polygon))
            if clipped_area <= tolerance * tolerance:
                continue
            overlaps += 1
            overlap_area += clipped_area
            for point in polygon:
                coping_height = triangle_height(crown, point)
                ground_height = triangle_height(ground, point)
                gap = coping_height - ground_height
                if gap < minimum:
                    minimum = gap
                    witness = {"xz_m": list(point), "coping_height_m": coping_height,
                               "terrain_height_m": ground_height}
                maximum = max(maximum, gap)
        if abs(overlap_area - area) <= max(area * 1e-5, tolerance * tolerance * 10):
            covered_faces += 1
        else:
            errors.append("A ramp coping triangle is not completely covered by production terrain")
    expected_area = ((dimensions["RAMP_OUTER_HALF"] - dimensions["RAMP_INNER_HALF"])
                     * (dimensions["RAMP_WALL_END"] - dimensions["RAMP_WALL_START"]))
    if not coping or any(abs(area - expected_area) > expected_area * 1e-5 for area in areas.values()):
        errors.append("Both complete southern ramp coping strips must be present")
    if not math.isfinite(minimum) or minimum <= .003:
        errors.append("Every ramp coping/terrain overlap needs more than 3 mm depth clearance")
    return {"ramp_coping_top_triangles": len(coping),
            "ramp_coping_covered_triangles": covered_faces,
            "ramp_coping_overlap_regions": overlaps,
            "ramp_coping_projected_area_m2": areas,
            "ramp_coping_min_clearance_m": minimum if math.isfinite(minimum) else None,
            "ramp_coping_max_clearance_m": maximum if math.isfinite(maximum) else None,
            "ramp_coping_min_clearance_witness": witness}, list(dict.fromkeys(errors))


def multiply(a, b):
    return tuple(sum(a[k * 4 + row] * b[column * 4 + k] for k in range(4))
                 for column in range(4) for row in range(4))


def transform(matrix, point):
    return tuple(sum(matrix[k * 4 + axis] * point[k] for k in range(3))
                 + matrix[12 + axis] for axis in range(3))


def node_matrix(node):
    if "matrix" in node:
        return tuple(node["matrix"])
    x, y, z, w = node.get("rotation", (0., 0., 0., 1.))
    sx, sy, sz = node.get("scale", (1., 1., 1.))
    tx, ty, tz = node.get("translation", (0., 0., 0.))
    return ((1 - 2 * (y * y + z * z)) * sx, 2 * (x * y + z * w) * sx,
            2 * (x * z - y * w) * sx, 0.,
            2 * (x * y - z * w) * sy, (1 - 2 * (x * x + z * z)) * sy,
            2 * (y * z + x * w) * sy, 0.,
            2 * (x * z + y * w) * sz, 2 * (y * z - x * w) * sz,
            (1 - 2 * (x * x + y * y)) * sz, 0., tx, ty, tz, 1.)


class Glb:
    def __init__(self, path):
        if path.stat().st_size > 128 * 1024 * 1024:
            raise ValueError("GLB exceeds the 128 MiB inspection limit")
        raw = path.read_bytes()
        if len(raw) < 20:
            raise ValueError("GLB header is missing")
        magic, version, length = struct.unpack_from("<4sII", raw)
        if magic != b"glTF" or version != 2 or length != len(raw):
            raise ValueError("Expected a complete glTF 2.0 binary asset")
        chunks = {}
        cursor = 12
        while cursor < len(raw):
            chunk_length, kind = struct.unpack_from("<II", raw, cursor)
            cursor += 8
            if cursor + chunk_length > len(raw):
                raise ValueError("GLB chunk exceeds the file length")
            chunks[kind] = raw[cursor:cursor + chunk_length]
            cursor += chunk_length
        self.data = json.loads(chunks[0x4E4F534A])
        self.binary = chunks[0x004E4942]
        if any("uri" in buffer for buffer in self.data.get("buffers", [])):
            raise ValueError("External buffers are not supported by this local GLB guard")

    def accessor(self, index):
        accessor = self.data["accessors"][index]
        if "sparse" in accessor:
            raise ValueError("Sparse accessors require an explicit inspection update")
        view = self.data["bufferViews"][accessor["bufferView"]]
        if view.get("buffer", 0) != 0:
            raise ValueError("Only the GLB's embedded buffer is supported")
        pattern = "<" + FORMATS[accessor["componentType"]] * WIDTHS[accessor["type"]]
        size = struct.calcsize(pattern)
        stride = view.get("byteStride", size)
        offset = accessor.get("byteOffset", 0)
        count = accessor["count"]
        end = offset + max(0, count - 1) * stride + (size if count else 0)
        start = view.get("byteOffset", 0)
        if stride < size or offset < 0 or count < 0 or end > view["byteLength"]:
            raise ValueError("Accessor exceeds its declared buffer view")
        if start < 0 or start + view["byteLength"] > len(self.binary):
            raise ValueError("Buffer view exceeds the embedded buffer")
        return [struct.unpack_from(pattern, self.binary, start + offset + i * stride)
                for i in range(count)]

    def triangles(self):
        data = self.data
        scene = data["scenes"][data.get("scene", 0)]
        stack = [(index, IDENTITY, ()) for index in scene["nodes"]]
        while stack:
            index, parent, ancestors = stack.pop()
            if index in ancestors:
                raise ValueError("Node hierarchy contains a cycle")
            node = data["nodes"][index]
            matrix = multiply(parent, node_matrix(node))
            for child in node.get("children", []):
                stack.append((child, matrix, ancestors + (index,)))
            if "mesh" not in node:
                continue
            for primitive in data["meshes"][node["mesh"]]["primitives"]:
                if primitive.get("mode", 4) != 4:
                    raise ValueError("Only triangle-list primitives are supported")
                points = [transform(matrix, point)
                          for point in self.accessor(primitive["attributes"]["POSITION"])]
                indices = ([entry[0] for entry in self.accessor(primitive["indices"])]
                           if "indices" in primitive else list(range(len(points))))
                if len(indices) % 3 or any(i < 0 or i >= len(points) for i in indices):
                    raise ValueError("Primitive contains invalid triangle indices")
                for offset in range(0, len(indices), 3):
                    yield (node.get("name", ""), primitive.get("material", -1),
                           tuple(points[indices[offset + i]] for i in range(3)))


class VertexIds:
    """Match all three coordinates within tolerance, including bin boundaries."""
    def __init__(self, tolerance):
        self.tolerance = tolerance
        self.buckets = defaultdict(list)
        self.points = []

    def identify(self, point):
        if not all(math.isfinite(c) for c in point):
            raise ValueError("GLB contains non-finite vertex coordinates")
        cell = tuple(math.floor(c / self.tolerance) for c in point)
        for delta in itertools.product((-1, 0, 1), repeat=3):
            neighbor = tuple(cell[k] + delta[k] for k in range(3))
            for index in self.buckets.get(neighbor, ()):
                if max(abs(point[k] - self.points[index][k]) for k in range(3)) <= self.tolerance:
                    return index
        index = len(self.points)
        self.points.append(point)
        self.buckets[cell].append(index)
        return index


def inspect(path, tolerance=2e-6):
    glb = Glb(path)
    ramp = ramp_dimensions()
    vertices = VertexIds(tolerance)
    faces = defaultdict(set)
    yard_tops = []
    terrain_tops = []
    ramp_coping = []
    ramp_terrain = []
    ramp_regions = [(side * ramp["RAMP_OUTER_HALF"], ramp["RAMP_WALL_START"],
                     side * ramp["RAMP_INNER_HALF"], ramp["RAMP_WALL_END"])
                    if side < 0 else
                    (ramp["RAMP_INNER_HALF"], ramp["RAMP_WALL_START"],
                     ramp["RAMP_OUTER_HALF"], ramp["RAMP_WALL_END"])
                    for side in (-1, 1)]
    material_names = glb.data.get("materials", [])
    triangle_count = 0
    # Current authored yard: 21 rows/columns, 1.18 m stride, 1.05 m slabs.
    yard_half = 10 * 1.18 + 1.05 / 2 + tolerance
    for name, material, triangle in glb.triangles():
        triangle_count += 1
        key = tuple(sorted(vertices.identify(point) for point in triangle))
        if len(set(key)) == 3:
            faces[key].add(material)
        if name.startswith("Sculpted enlarged castle wasteland"):
            terrain_tops.extend(point[1] for point in triangle)
            if any(bounds_overlap(projected_bounds(triangle), region, tolerance)
                   for region in ramp_regions):
                ramp_terrain.append(triangle)
            continue
        material_name = material_names[material].get("name") if material >= 0 else None
        if is_ramp_coping(triangle, material_name, ramp, tolerance):
            ramp_coping.append(triangle)
        if material_name not in (
                "Weathered concrete", "Concrete fracture"):
            continue
        if not all(abs(point[0]) <= yard_half and abs(point[2]) <= yard_half for point in triangle):
            continue
        height = [point[1] for point in triangle]
        if max(height) - min(height) > tolerance:
            continue
        a, b, c = triangle
        normal_y = ((b[2] - a[2]) * (c[0] - a[0])
                    - (b[0] - a[0]) * (c[2] - a[2]))
        if normal_y > tolerance * tolerance:
            yard_tops.extend(height)
    duplicates = [key for key, materials in faces.items() if len(materials) > 1]
    errors = []
    if not terrain_tops:
        errors.append("Production terrain was not found")
    terrain_top = max(terrain_tops) if terrain_tops else None
    if terrain_top is not None and abs(terrain_top - 5.) > tolerance:
        errors.append("Production terrain top must remain 5 metres")
    top_triangles = len(yard_tops) // 3
    if top_triangles != 372 * 2:
        errors.append("Expected every top triangle of the 372 courtyard slabs")
    clearance = ([min(yard_tops) - terrain_top, max(yard_tops) - terrain_top]
                 if yard_tops and terrain_top is not None else None)
    if clearance is None or clearance[0] <= .003 or clearance[1] >= .02:
        errors.append("Each courtyard top needs a 3–20 mm gap above the terrain")
    if duplicates:
        errors.append("Different materials contain duplicate complete triangles")
    ramp_result, ramp_errors = inspect_ramp_coping(ramp_coping, ramp_terrain, ramp, tolerance)
    errors.extend(ramp_errors)
    result = {"ok": not errors, "asset": path.name, "tolerance_m": tolerance,
              "triangles": triangle_count, "terrain_top_m": terrain_top,
              "courtyard_top_triangles": top_triangles,
              "courtyard_slabs": top_triangles // 2,
              "courtyard_clearance_m": clearance,
              "cross_material_duplicate_triangles": len(duplicates), "errors": errors}
    result.update(ramp_result)
    if duplicates:
        result["duplicate_bounds_m"] = [
            [min(vertices.points[i][axis] for key in duplicates for i in key),
             max(vertices.points[i][axis] for key in duplicates for i in key)] for axis in range(3)]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", type=Path, default=ROOT / "assets/models/castle_ground.glb")
    args = parser.parse_args()
    try:
        result = inspect(args.glb)
    except (OSError, ValueError, KeyError, IndexError, TypeError, struct.error) as error:
        result = {"ok": False, "asset": args.glb.name, "errors": [str(error)]}
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
