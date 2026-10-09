class_name ConstructionGrid
extends RefCounted
## Shared one-metre building cells, independent of rendering and game state.
const CELL_SIZE := 1.0
const Layout := preload("res://scripts/outpost_layout.gd")
const ORIGIN := Vector2(-Layout.FORT_INNER, -Layout.FORT_INNER)
const CASTLE_CELLS := Rect2i(0, 0, int(Layout.FORT_INNER * 2.0 / CELL_SIZE), int(Layout.FORT_INNER * 2.0 / CELL_SIZE))
const MAX_GRID_INDEX := 1073741820
const MAX_RASTER_CELLS := 65536
const Catalog := preload("res://scripts/outpost_catalog.gd")
const CORE_SIZE := Vector2i(6, 6)

static func sizes(kind: String) -> Vector2i:
	if kind == "core": return CORE_SIZE
	return Catalog.building(kind).get("size", Vector2i.ZERO)

static func build_regions() -> Array[Rect2i]:
	var regions: Array[Rect2i] = [CASTLE_CELLS]
	for castle: Dictionary in Layout.SATELLITE_CASTLES:
		var center: Vector3=castle.position
		var half: float=float(castle.half_extent)
		var corner := (Vector2(center.x-half,center.z-half)-ORIGIN)/CELL_SIZE
		var span := int(half*2.0/CELL_SIZE)
		regions.append(Rect2i(Vector2i(roundi(corner.x),roundi(corner.y)),Vector2i(span,span)))
	return regions

static func region_at(point: Vector3) -> Rect2i:
	if not point.is_finite():return Rect2i()
	var flat := (Vector2(point.x,point.z)-ORIGIN)/CELL_SIZE
	if not _indexable(flat):return Rect2i()
	var cell := Vector2i(floori(flat.x),floori(flat.y))
	for region: Rect2i in build_regions():
		if region.has_point(cell):return region
	return Rect2i()

static func buildable_cell(cell: Vector2i) -> bool:
	for region: Rect2i in build_regions():
		if region.has_point(cell):return true
	return false

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
	for region: Rect2i in build_regions():
		if region.encloses(occupied):
			result.inside = true
			break
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
