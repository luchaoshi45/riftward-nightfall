extends Node3D
## Stable, reusable world-space overlays. Placement authority remains in construction.
const Grid := preload("res://scripts/construction_grid.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
const GRID_LIFT := 0.055
const FILL_LIFT := 0.070
const EDGE_LIFT := 0.086
const GRID_WIDTH := 0.022
const EDGE_WIDTH := 0.038
const GRID_COLOR := Color(0.40, 0.64, 0.70, 0.24)
const FREE_FILL := Color(0.20, 0.76, 0.43, 0.24)
const BLOCKED_FILL := Color(0.90, 0.20, 0.14, 0.34)
const FREE_EDGE := Color(0.36, 0.91, 0.56, 0.76)
const BLOCKED_EDGE := Color(0.98, 0.32, 0.22, 0.90)
const BUDGET_EDGE := Color(0.98, 0.70, 0.22, 0.90)
const TECH_EDGE := Color(0.63, 0.60, 0.98, 0.90)
const TERRAIN_STEP := 0.25

var grid_node: MeshInstance3D
var footprint_node: MeshInstance3D
var border_node: MeshInstance3D
var fill_rebuilds := 0
var border_rebuilds := 0
var budget_limited := false
var tech_limited := false
var current_cells: Array[Vector2i] = []
var current_states: Array[bool] = []
var _space_signature := ""
var _border_signature := ""
var _grid_region: Rect2i = Rect2i()

func setup() -> void:
	_ensure_nodes()
	hide()

func show_placement(placement: Dictionary) -> void:
	_ensure_nodes()
	var cells: Array = placement.get("cells", [])
	var point: Vector3 = placement.get("point", Vector3.INF)
	if cells.is_empty() or not point.is_finite():
		hide()
		return
	var region := Grid.region_at(point)
	if not region.has_area():region=Grid.CASTLE_CELLS
	_update_grid(region)
	var states: Dictionary = {}
	for state: Dictionary in placement.get("cell_states", []):
		if state.get("cell") is Vector2i:
			states[state.cell] = bool(state.get("space_valid", false))
	current_cells.clear()
	current_states.clear()
	var signature := ""
	for cell: Vector2i in cells:
		var free := bool(states.get(cell, placement.get("space_valid", false)))
		current_cells.append(cell)
		current_states.append(free)
		signature += "%d,%d,%d;" % [cell.x, cell.y, int(free)]
	tech_limited = bool(placement.get("space_valid", false)) and not bool(placement.get("tech_valid", true))
	budget_limited = bool(placement.get("space_valid", false)) and not tech_limited and not bool(placement.get("valid", false))
	if signature != _space_signature:
		_space_signature = signature
		_update_fill()
	var edge_signature := signature + str(budget_limited) + str(tech_limited)
	if edge_signature != _border_signature:
		_border_signature = edge_signature
		_update_border()
	show()

func _ensure_nodes() -> void:
	if is_instance_valid(grid_node): return
	grid_node = _mesh_node("CastleConstructionGrid", -2)
	footprint_node = _mesh_node("ConstructionCellFill", -1)
	border_node = _mesh_node("ConstructionCellEdges", 0)
	_update_grid(Grid.CASTLE_CELLS)

func _update_grid(region: Rect2i) -> void:
	if region==_grid_region:return
	_grid_region=region
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var corner: Vector2 = Grid.ORIGIN + Vector2(region.position) * Grid.CELL_SIZE
	var end: Vector2 = corner + Vector2(region.size) * Grid.CELL_SIZE
	# Cache the active castle's one-metre lines. Moving a deployment vehicle
	# to another castle changes this background; footprints stay authoritative.
	for x in range(region.size.x + 1):
		var coordinate := corner.x + float(x) * Grid.CELL_SIZE
		_append_strip(vertices, colors, Vector2(coordinate, corner.y), Vector2(coordinate, end.y), GRID_WIDTH, GRID_LIFT, GRID_COLOR, false)
	for z in range(region.size.y + 1):
		var coordinate := corner.y + float(z) * Grid.CELL_SIZE
		_append_strip(vertices, colors, Vector2(corner.x, coordinate), Vector2(end.x, coordinate), GRID_WIDTH, GRID_LIFT, GRID_COLOR, false)
	_write_mesh(grid_node.mesh as ArrayMesh, vertices, colors)

func _mesh_node(node_name: String, priority: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = ArrayMesh.new()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color.WHITE
	material.render_priority = priority
	node.material_override = material
	add_child(node)
	return node

func _update_fill() -> void:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	for index in current_cells.size():
		var rect: Rect2 = Grid.cell_rect(current_cells[index]).grow(-0.045)
		var color := FREE_FILL if current_states[index] else BLOCKED_FILL
		var divisions := 1 if Grid.buildable_cell(current_cells[index]) else 4
		for z in divisions:
			for x in divisions:
				var start := rect.position + Vector2(x, z) * rect.size / float(divisions)
				var end := start + rect.size / float(divisions)
				_append_quad(vertices, colors, [start, Vector2(end.x, start.y), end, Vector2(start.x, end.y)], FILL_LIFT, color)
	_write_mesh(footprint_node.mesh as ArrayMesh, vertices, colors)
	fill_rebuilds += 1

func _update_border() -> void:
	var edges: Dictionary = {}
	for index in current_cells.size():
		var cell := current_cells[index]
		var free := current_states[index]
		# Shared boundaries are drawn once. A blocked neighbour wins their color.
		for key in [Vector3i(cell.x, cell.y, 0), Vector3i(cell.x, cell.y + 1, 0),
			Vector3i(cell.x, cell.y, 1), Vector3i(cell.x + 1, cell.y, 1)]:
			if not edges.has(key): edges[key] = {"free": free, "count": 1}
			else:
				edges[key].free = bool(edges[key].free) and free
				edges[key].count = int(edges[key].count) + 1
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	for key: Vector3i in edges:
		var edge: Dictionary = edges[key]
		var start := Grid.ORIGIN + Vector2(key.x, key.y) * Grid.CELL_SIZE
		var direction := Vector2.RIGHT if key.z == 0 else Vector2.DOWN
		var color := FREE_EDGE if bool(edge.free) else BLOCKED_EDGE
		if bool(edge.free) and int(edge.count) == 1:
			if tech_limited: color = TECH_EDGE
			elif budget_limited: color = BUDGET_EDGE
		_append_strip(vertices, colors, start, start + direction * Grid.CELL_SIZE, EDGE_WIDTH, EDGE_LIFT, color, true)
	_write_mesh(border_node.mesh as ArrayMesh, vertices, colors)
	border_rebuilds += 1

func _append_strip(vertices: PackedVector3Array, colors: PackedColorArray, start: Vector2, end: Vector2,
	width: float, lift: float, color: Color, sample_terrain: bool) -> void:
	var direction := end - start
	var side := Vector2(-direction.y, direction.x).normalized() * width * 0.5
	var divisions := maxi(1, ceili(direction.length() / TERRAIN_STEP)) if sample_terrain else 1
	for index in divisions:
		var a := start.lerp(end, float(index) / float(divisions))
		var b := start.lerp(end, float(index + 1) / float(divisions))
		_append_quad(vertices, colors, [a - side, b - side, b + side, a + side], lift, color)

func _append_quad(vertices: PackedVector3Array, colors: PackedColorArray, corners: Array[Vector2],
	lift: float, color: Color) -> void:
	for index in [0, 1, 2, 0, 2, 3]:
		var corner := corners[index]
		var point := Vector3(corner.x, 0.0, corner.y)
		point.y = Layout.terrain_height(point) + lift
		vertices.append(point)
		colors.append(color)

func _write_mesh(mesh: ArrayMesh, vertices: PackedVector3Array, colors: PackedColorArray) -> void:
	mesh.clear_surfaces()
	if vertices.is_empty(): return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
