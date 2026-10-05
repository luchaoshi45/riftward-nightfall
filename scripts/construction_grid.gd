class_name ConstructionGrid
extends RefCounted
## Shared one-metre building cells, independent of rendering and game state.
const CELL_SIZE := 1.0
const ORIGIN := Vector2(-13.0, -13.0)
const CASTLE_CELLS := Rect2i(0, 0, 26, 26)
const MAX_GRID_INDEX := 1073741820
const MAX_RASTER_CELLS := 65536
const BUILDING_SIZES := {
	"tower": Vector2i(3, 3),
	"barracks": Vector2i(4, 3),
	"workshop": Vector2i(3, 2),
	"core": Vector2i(6, 6),
}

static func sizes(kind: String) -> Vector2i:
	return BUILDING_SIZES.get(kind, Vector2i.ZERO)

static func placement(point: Vector3, kind: String) -> Dictionary:
	var cells: Array[Vector2i] = []
	var size := sizes(kind)
	var result := {"point": point if point.is_finite() else Vector3.ZERO, "anchor": Vector2i.ZERO,
		"size": Vector2i.ZERO, "cells": cells, "rect": Rect2(), "inside": false}
	if not point.is_finite() or size == Vector2i.ZERO: return result
	var anchor_float := (Vector2(point.x, point.z) - ORIGIN) / CELL_SIZE - Vector2(size) * 0.5
	if not _indexable(anchor_float): return result
	var anchor := Vector2i(roundi(anchor_float.x), roundi(anchor_float.y))
	var occupied := Rect2i(anchor, size)
	var corner := ORIGIN + Vector2(anchor) * CELL_SIZE
	var dimensions := Vector2(size) * CELL_SIZE
	var center := corner + dimensions * 0.5
	for z in range(anchor.y, anchor.y + size.y):
		for x in range(anchor.x, anchor.x + size.x): cells.append(Vector2i(x, z))
	result.point = Vector3(center.x, point.y, center.y)
	result.anchor = anchor
	result.size = size
	result.rect = Rect2(corner, dimensions)
	result.inside = CASTLE_CELLS.encloses(occupied)
	return result

static func cells_for_rect(rect: Rect2) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x <= 0.0 or rect.size.y <= 0.0: return cells
	var first_float := (rect.position - ORIGIN) / CELL_SIZE
	var end_float := (rect.end - ORIGIN) / CELL_SIZE
	if not _indexable(first_float) or not _indexable(end_float): return cells
	# Half-open bounds: an edge exactly on a grid line does not claim the cell
	# beyond it. A positive sliver still belongs to every cell it intersects.
	var first := Vector2i(floori(first_float.x), floori(first_float.y))
	var end := Vector2i(ceili(end_float.x), ceili(end_float.y))
	var width: int = int(end.x) - int(first.x)
	var height: int = int(end.y) - int(first.y)
	if width <= 0 or height <= 0 or width > MAX_RASTER_CELLS or height > MAX_RASTER_CELLS or width * height > MAX_RASTER_CELLS: return cells
	for z in range(first.y, end.y):
		for x in range(first.x, end.x): cells.append(Vector2i(x, z))
	return cells

static func cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(ORIGIN + Vector2(cell) * CELL_SIZE, Vector2.ONE * CELL_SIZE)

static func _indexable(point: Vector2) -> bool:
	return point.is_finite() and absf(point.x) <= MAX_GRID_INDEX and absf(point.y) <= MAX_GRID_INDEX
