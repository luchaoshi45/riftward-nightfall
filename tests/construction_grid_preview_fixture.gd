extends SceneTree
## Standalone overlay lifetime, spatial feedback and real slope geometry.
const Grid := preload("res://scripts/construction_grid.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
const Preview := preload("res://scripts/construction_grid_preview.gd")
var preview: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 20: push_error(message)

func placement(point: Vector3, kind: String, blocked_index: int = -1, can_pay: bool = true) -> Dictionary:
	var result: Dictionary = Grid.placement(point, kind)
	result.space_valid = blocked_index < 0 and bool(result.inside)
	result.valid = bool(result.space_valid) and can_pay
	var states: Array[Dictionary] = []
	for index in result.cells.size():
		states.append({"cell": result.cells[index], "space_valid": index != blocked_index and bool(result.inside), "reason": ""})
	result.cell_states = states
	return result

func material_checks() -> void:
	for node: MeshInstance3D in [preview.grid_node, preview.footprint_node, preview.border_node]:
		var material := node.material_override as StandardMaterial3D
		check(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Construction overlays never cast shadows")
		check(not material.emission_enabled, "Overlay colors cannot bloom or change nearby lighting")
		check(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "Moving dynamic lights cannot flicker the grid")
		check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and material.vertex_color_use_as_albedo,
			"Per-cell soft colors must be consumed by the real material")
		check(not material.no_depth_test, "Buildings must still occlude ground overlays")

func geometry_checks(node: MeshInstance3D, lift: float) -> void:
	var arrays: Array = node.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	check(vertices.size() > 0 and vertices.size() == colors.size(), "All visible vertices must carry a cell color")
	for vertex in vertices:
		check(vertex.is_finite() and absf(vertex.y - Layout.terrain_height(vertex) - lift) < 0.00001,
			"Each overlay vertex follows authored terrain without sharing its depth")

func has_color(colors: PackedColorArray, expected: Color) -> bool:
	# ArrayMesh stores vertex colors in normalized 8-bit channels.
	for color in colors:
		if absf(color.r - expected.r) < 0.005 and absf(color.g - expected.g) < 0.005 and absf(color.b - expected.b) < 0.005 and absf(color.a - expected.a) < 0.005: return true
	return false

func run() -> void:
	preview = Preview.new()
	root.add_child(preview)
	preview.setup()
	check(not preview.visible, "Construction mode starts with the overlay hidden")
	check(preview.get_child_count() == 3, "One cached city grid, fill and edge node cover every preview")
	var city_vertices: PackedVector3Array = preview.grid_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(city_vertices.size() == 54 * 6, "All 27 horizontal and 27 vertical castle lines must be drawn once")
	geometry_checks(preview.grid_node, Preview.GRID_LIFT)
	material_checks()
	var good := placement(Vector3(7.5, 5, -7.5), "tower")
	preview.show_placement(good)
	check(preview.visible and preview.current_cells.size() == 9 and not preview.budget_limited,
		"A valid tower shows its nine free cells immediately")
	geometry_checks(preview.footprint_node, Preview.FILL_LIFT)
	geometry_checks(preview.border_node, Preview.EDGE_LIFT)
	var grid_mesh_id: int = preview.grid_node.mesh.get_instance_id()
	var fill_mesh_id: int = preview.footprint_node.mesh.get_instance_id()
	var edge_mesh_id: int = preview.border_node.mesh.get_instance_id()
	var material_id: int = preview.footprint_node.material_override.get_instance_id()
	var fills: int = preview.fill_rebuilds
	var borders: int = preview.border_rebuilds
	for _frame in 120: preview.show_placement(placement(Vector3(7.61, 5, -7.47), "tower"))
	check(preview.fill_rebuilds == fills and preview.border_rebuilds == borders,
		"Continuous cursor movement inside a snapped cell must reuse existing geometry")
	check(preview.grid_node.mesh.get_instance_id() == grid_mesh_id and preview.footprint_node.mesh.get_instance_id() == fill_mesh_id and
		preview.border_node.mesh.get_instance_id() == edge_mesh_id and preview.footprint_node.material_override.get_instance_id() == material_id,
		"Preview nodes, meshes and materials retain their identities over repeated updates")
	preview.show_placement(placement(Vector3(7.5, 5, -7.5), "tower", -1, false))
	check(preview.budget_limited and preview.current_states.count(false) == 0,
		"Insufficient funds must keep all spatially free cells green")
	check(preview.fill_rebuilds == fills and preview.border_rebuilds == borders + 1,
		"A budget-only change updates the amber outline without rebuilding cell fill")
	var edge_colors: PackedColorArray = preview.border_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(has_color(edge_colors, Preview.BUDGET_EDGE) and not has_color(edge_colors, Preview.BLOCKED_EDGE),
		"Budget failure has an amber boundary and no false red collision")
	preview.show_placement(placement(Vector3(7.5, 5, -7.5), "tower", 4))
	check(preview.current_states.count(false) == 1 and not preview.budget_limited,
		"A single occupied cell does not turn its free neighbours into blockers")
	var fill_colors: PackedColorArray = preview.footprint_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(has_color(fill_colors, Preview.FREE_FILL) and has_color(fill_colors, Preview.BLOCKED_FILL), "Mixed occupancy is shown with both red and green cells")
	preview.show_placement(placement(Vector3(14.5, 2, 0.5), "workshop"))
	check(not preview.current_states.is_empty() and preview.current_states.count(true) == 0, "Castle-exterior preview remains visibly blocked")
	geometry_checks(preview.footprint_node, Preview.FILL_LIFT)
	geometry_checks(preview.border_node, Preview.EDGE_LIFT)
	var slope_vertices: PackedVector3Array = preview.footprint_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var min_height := INF
	var max_height := -INF
	for vertex in slope_vertices:
		min_height = minf(min_height, vertex.y)
		max_height = maxf(max_height, vertex.y)
	check(max_height - min_height > 3.0, "Exterior cells drape over the actual five-metre embankment")
	for kind in ["barracks", "workshop", "tower"]:
		preview.show_placement(placement(Vector3(-7, 5, -7), kind))
		check(preview.current_cells.size() == Grid.sizes(kind).x * Grid.sizes(kind).y, "Changing construction type updates its true occupied cells")
		check(preview.get_child_count() == 3, "Type changes do not leave retired preview nodes")
	preview.hide()
	check(not preview.visible, "Cancellation or pause can immediately hide all preview layers")
	preview.show_placement(good)
	check(preview.visible, "The same cached nodes can resume construction")
	preview.show_placement({"point": Vector3.INF, "cells": good.cells})
	check(not preview.visible, "An invalid cursor never displays stale placement feedback")
	preview.queue_free()
	await process_frame
	print("CONSTRUCTION_GRID_PREVIEW_FIXTURE_", "OK" if failures.is_empty() else "FAILED", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
