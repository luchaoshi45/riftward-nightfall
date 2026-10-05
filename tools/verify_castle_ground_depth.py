#!/usr/bin/env python3
"""Read the production GLB and guard against courtyard depth competition.

No Blender/Godot installation or third-party package is required. Shared edges
are allowed; only complete triangles duplicated across materials are rejected.
This checks actual transformed vertex data, never a joined mesh's AABB.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import itertools
import json
import math
from pathlib import Path
import struct
import sys


ROOT = Path(__file__).resolve().parents[1]
IDENTITY = (1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1., 0., 0., 0., 0., 1.)
FORMATS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


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
    vertices = VertexIds(tolerance)
    faces = defaultdict(set)
    yard_tops = []
    terrain_tops = []
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
            continue
        if material < 0 or material_names[material].get("name") not in (
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
    result = {"ok": not errors, "asset": path.name, "tolerance_m": tolerance,
              "triangles": triangle_count, "terrain_top_m": terrain_top,
              "courtyard_top_triangles": top_triangles,
              "courtyard_slabs": top_triangles // 2,
              "courtyard_clearance_m": clearance,
              "cross_material_duplicate_triangles": len(duplicates), "errors": errors}
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
