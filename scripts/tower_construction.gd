extends Node3D
## Shared construction selection. The controller owns payment and building lifetime.
const Layout := preload("res://scripts/outpost_layout.gd")
const Grid := preload("res://scripts/construction_grid.gd")
const GridPreview := preload("res://scripts/construction_grid_preview.gd")
const TOWER_SCENE: PackedScene = preload("res://assets/models/auto_turret.glb")
const PAD_SCENE: PackedScene = preload("res://assets/models/tower_pad.glb")
const CORE_SCENE: PackedScene = preload("res://assets/models/watch_beacon.glb")
const BARRACKS_SCENE: PackedScene = preload("res://assets/models/survivor_camp.glb")
const WORKSHOP_SCENE: PackedScene = preload("res://assets/models/day_generator.glb")
const TITLES := {"tower": "防御塔", "barracks": "兵营", "workshop": "工坊"}
const BOUNDARY_EPSILON := 0.00001
const NAVIGATION_MARGIN := 0.05
const UNIT_BODY_RADIUS := 0.25
const VALID_COLOR := Color(0.35, 0.9, 0.58, 0.32)
const INVALID_COLOR := Color(0.95, 0.3, 0.28, 0.32)
const BUDGET_COLOR := Color(0.95, 0.68, 0.28, 0.32)

var game: Node3D
var active := false
var kind := "tower"
var ghost: Node3D
var grid_preview: Node3D
var ring: MeshInstance3D
var ghost_material: StandardMaterial3D
var ring_material: StandardMaterial3D
var _preview_state := -1
var _preview_kind := ""
var _footprints: Dictionary = {}
var _has_hero := false
var _has_squads := false
var _has_enemies := false
var _has_expeditions := false

func setup(owner_game: Node3D) -> void:
	clear()
	game = owner_game
	if get_parent() == null: game.add_child(self)
	for property: Dictionary in game.get_property_list():
		if String(property.name) == "hero": _has_hero = true
		if String(property.name) == "squads": _has_squads = true
		if String(property.name) == "enemies": _has_enemies = true
		if String(property.name) == "expeditions": _has_expeditions = true

func begin(structure_kind: String = "tower") -> bool:
	if not is_instance_valid(game) or game.phase not in ["day", "night"] or not TITLES.has(structure_kind): return false
	kind = structure_kind
	active = true
	_ensure_preview()
	tick(0.0)
	return true

func select_kind(structure_kind: String) -> bool:
	return begin(structure_kind)

func cancel() -> void:
	active = false
	if is_instance_valid(ghost): ghost.visible = false
	if is_instance_valid(grid_preview): grid_preview.hide()

func clear() -> void:
	cancel()
	if is_instance_valid(ghost): ghost.queue_free()
	if is_instance_valid(grid_preview): grid_preview.queue_free()
	ghost = null
	grid_preview = null
	ring = null
	ghost_material = null
	ring_material = null
	_preview_state = -1
	_preview_kind = ""
	_has_hero = false
	_has_squads = false
	_has_enemies = false
	_has_expeditions = false
	game = null

func tick(_delta: float) -> void:
	if not active or not is_instance_valid(game) or game.phase not in ["day", "night"]:
		if is_instance_valid(ghost): ghost.visible = false
		if is_instance_valid(grid_preview): grid_preview.hide()
		return
	_ensure_preview()
	var placement := validity(game.aim, -1, kind)
	var point: Vector3 = placement.point
	if not point.is_finite() or (placement.cells as Array).is_empty():
		ghost.visible = false
		grid_preview.hide()
		return
	ghost.position = point
	ghost.visible = true
	grid_preview.show_placement(placement)
	var state := 1 if bool(placement.valid) else (2 if bool(placement.space_valid) else 0)
	if state != _preview_state:
		_preview_state = state
		var tint: Color = VALID_COLOR if state == 1 else (BUDGET_COLOR if state == 2 else INVALID_COLOR)
		ghost_material.albedo_color = tint
		tint.a = 0.95
		ring_material.albedo_color = tint
		ring_material.emission = tint

func snapshot() -> Dictionary:
	var point: Vector3 = game.aim if is_instance_valid(game) else Vector3.ZERO
	var placement := validity(point, -1, kind)
	placement.active = active
	return placement

func validity(point: Vector3, ignore_pad_index: int = -1, structure_kind: String = "tower", ignore_plot_index: int = -1) -> Dictionary:
	var result := Grid.placement(point, structure_kind)
	result.merge({"valid": false, "space_valid": false, "reason": "", "cost": 0,
		"kind": structure_kind, "title": String(TITLES.get(structure_kind, "建筑")), "cell_states": []})
	if not is_instance_valid(game):
		result.reason = "建设系统尚未初始化"
		return result
	if not TITLES.has(structure_kind):
		result.reason = "未知建筑"
		return result
	result.cost = game.districts.tower_cost(int(game.TOWER_COSTS[0])) if structure_kind == "tower" else int(game.districts.BUILD_COST)
	if not point.is_finite() or (result.cells as Array).is_empty():
		result.reason = "放置位置无效"
		return result
	if game.phase not in ["day", "night"]:
		result.reason = "暂停或选卡时不能建造"
		return result
	point = result.point
	var height: float = game.outpost_height(point)
	result.point = Vector3(point.x, height, point.z)
	var occupied := occupied_cells(ignore_pad_index, ignore_plot_index)
	var units := _living_units()
	var cell_states: Array[Dictionary] = []
	var rejection := ""
	for cell: Vector2i in result.cells:
		var reason := ""
		var rect := Grid.cell_rect(cell)
		var center := rect.get_center()
		if not Grid.CASTLE_CELLS.has_point(cell): reason = "占地格超出城内或覆盖城墙"
		elif not is_finite(height) or absf(height - Layout.FORT_HEIGHT) > .05: reason = "需要城内平坦地面"
		elif occupied.has(cell): reason = String(occupied[cell])
		else:
			for unit: Node3D in units:
				var position := unit.position
				if absf(position.y - height) > 1.0: continue
				if _overlaps(center, Vector2.ONE * (Grid.CELL_SIZE * .5 + NAVIGATION_MARGIN), false, Vector2(position.x, position.z), Vector2.ONE * UNIT_BODY_RADIUS, true):
					reason = "占地格有正在这里的单位"
					break
		cell_states.append({"cell": cell, "space_valid": reason.is_empty(), "reason": reason})
		if rejection.is_empty() and not reason.is_empty(): rejection = reason
	result.cell_states = cell_states
	if not rejection.is_empty():
		result.reason = rejection
		return result
	result.space_valid = true
	if int(game.scrap) < int(result.cost):
		result.reason = "零件不足 · 需要%d" % int(result.cost)
		return result
	result.valid = true
	result.reason = "可建造%s · %d×%d格" % [String(result.title), Grid.sizes(structure_kind).x, Grid.sizes(structure_kind).y]
	return result

func occupied_cells(ignore_pad_index: int = -1, ignore_plot_index: int = -1) -> Dictionary:
	var occupied: Dictionary = {}
	_reserve_cells(occupied, Vector3.ZERO, "core", "占地格覆盖灯塔核心底座")
	if not is_instance_valid(game): return occupied
	for index in game.districts.plots.size():
		if index == ignore_plot_index: continue
		var plot: Dictionary = game.districts.plots[index]
		if int(plot.get("level", 0)) <= 0 or float(plot.get("hp", 0.0)) <= 0.0: continue
		_reserve_cells(occupied, plot.position, String(plot.kind), "占地格已有建筑")
	for index in game.world.tower_pads.size():
		if index == ignore_pad_index: continue
		var pad: Dictionary = game.world.tower_pads[index]
		if int(pad.get("level", 0)) <= 0 and not bool(pad.get("free_built", false)): continue
		_reserve_cells(occupied, pad.position, "tower", "占地格有防御塔或残基")
	return occupied

func _reserve_cells(occupied: Dictionary, point: Vector3, structure_kind: String, reason: String) -> void:
	# Live construction stores snapped centers. Conservatively rasterize any
	# legacy/test off-grid structure at its actual position instead of moving it.
	var half := footprint(structure_kind)
	for cell: Vector2i in Grid.cells_for_rect(Rect2(Vector2(point.x, point.z) - half, half * 2.0)):
		if not occupied.has(cell): occupied[cell] = reason

func footprint(structure_kind: String) -> Vector2:
	return Vector2(Grid.sizes(structure_kind)) * Grid.CELL_SIZE * .5

func model_footprint(structure_kind: String) -> Vector2:
	if _footprints.has(structure_kind): return _footprints[structure_kind]
	if structure_kind == "tower":
		var pad := PAD_SCENE.instantiate() as Node3D
		var tower := TOWER_SCENE.instantiate() as Node3D
		var pad_size := _named_footprint(pad, "Reinforced tower socket")
		var tower_size := _named_footprint(tower, "Defense tower footing") * 1.24
		var radius := maxf(maxf(pad_size.x, pad_size.y), maxf(tower_size.x, tower_size.y))
		_footprints[structure_kind] = Vector2.ONE * radius
		pad.free()
		tower.free()
	elif structure_kind == "core":
		var core := CORE_SCENE.instantiate() as Node3D
		var half := _named_footprint(core, "Generator footing")
		_footprints[structure_kind] = Vector2.ONE * maxf(half.x, half.y)
		core.free()
	elif is_instance_valid(game) and structure_kind in ["barracks", "workshop"]:
		_footprints[structure_kind] = game.districts.footprint(structure_kind)
	else: return Vector2.ZERO
	return _footprints[structure_kind]

func navigation_blocks() -> Array[Rect2]:
	var blocks: Array[Rect2] = []
	if not is_instance_valid(game): return blocks
	var core := footprint("core")
	blocks.append(Rect2(-core, core * 2.0).grow(NAVIGATION_MARGIN))
	for pad: Dictionary in game.world.tower_pads:
		# A destroyed footing still reserves its construction identity, but its
		# low plate is traversable. Destroying a defense must reopen the route.
		if int(pad.get("level", 0)) <= 0 or float(pad.get("hp", 0.0)) <= 0.0: continue
		var point: Vector3 = pad.position
		var half := footprint("tower")
		blocks.append(Rect2(Vector2(point.x, point.z) - half, half * 2.0).grow(NAVIGATION_MARGIN))
	for plot: Dictionary in game.districts.plots:
		if int(plot.get("level", 0)) <= 0 or float(plot.get("hp", 0.0)) <= 0.0: continue
		var point: Vector3 = plot.position
		var half := footprint(String(plot.kind))
		blocks.append(Rect2(Vector2(point.x, point.z) - half, half * 2.0).grow(NAVIGATION_MARGIN))
	return blocks

func confirm() -> bool:
	if not active or not is_instance_valid(game): return false
	var placement := validity(game.aim, -1, kind)
	if not bool(placement.valid): return false
	if not game.build_structure_at(placement.point, kind): return false
	tick(0.0)
	return true

func _overlaps(a: Vector2, a_half: Vector2, a_circle: bool, b: Vector2, b_half: Vector2, b_circle: bool) -> bool:
	if a_circle and b_circle: return a.distance_to(b) < a_half.x + b_half.x - BOUNDARY_EPSILON
	if a_circle:
		var nearest := Vector2(clampf(a.x, b.x - b_half.x, b.x + b_half.x), clampf(a.y, b.y - b_half.y, b.y + b_half.y))
		return a.distance_to(nearest) < a_half.x - BOUNDARY_EPSILON
	if b_circle: return _overlaps(b, b_half, true, a, a_half, false)
	return absf(a.x - b.x) < a_half.x + b_half.x - BOUNDARY_EPSILON and absf(a.y - b.y) < a_half.y + b_half.y - BOUNDARY_EPSILON

func _living_units() -> Array[Node3D]:
	var units: Array[Node3D] = []
	if _has_hero:
		var hero: Variant = game.get("hero")
		if is_instance_valid(hero) and hero is Node3D and _unit_alive(hero): units.append(hero)
	if _has_squads:
		var squads: Node = game.get("squads") as Node
		if is_instance_valid(squads):
			for squad: Dictionary in squads.get("squads"):
				for member in squad.members:
					if is_instance_valid(member) and member is Node3D and _unit_alive(member): units.append(member)
	if _has_enemies:
		for enemy in game.get("enemies"):
			if is_instance_valid(enemy) and enemy is Node3D and _unit_alive(enemy): units.append(enemy)
	if _has_expeditions:
		var expeditions: Node = game.get("expeditions") as Node
		if is_instance_valid(expeditions):
			for camp: Dictionary in expeditions.get("camps"):
				var scout: Variant = camp.get("npc")
				if is_instance_valid(scout) and scout is Node3D and _unit_alive(scout): units.append(scout)
	return units

func _unit_alive(unit: Node3D) -> bool:
	if unit is BattleUnit: return (unit as BattleUnit).hp > 0.0
	for property: Dictionary in unit.get_property_list():
		if String(property.name) == "hp": return float(unit.get("hp")) > 0.0
	return true

func _named_footprint(model: Node3D, part_name: String) -> Vector2:
	var mesh := model.find_child(part_name, true, false) as MeshInstance3D
	if not is_instance_valid(mesh): return Vector2.ZERO
	var transform := mesh.transform
	var parent := mesh.get_parent()
	while parent != model and parent is Node3D:
		transform = (parent as Node3D).transform * transform
		parent = parent.get_parent()
	var bounds: AABB = transform * mesh.get_aabb()
	return Vector2(maxf(absf(bounds.position.x), absf(bounds.end.x)), maxf(absf(bounds.position.z), absf(bounds.end.z)))

func _ensure_preview() -> void:
	if not is_instance_valid(grid_preview):
		grid_preview = GridPreview.new()
		add_child(grid_preview)
		grid_preview.setup()
		grid_preview.hide()
	if not is_instance_valid(ghost):
		ghost = Node3D.new()
		ghost.name = "ConstructionPreview"
		add_child(ghost)
		ghost_material = StandardMaterial3D.new()
		ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ghost_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		ghost_material.albedo_color = INVALID_COLOR
		ring_material = StandardMaterial3D.new()
		ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_material.albedo_color = Color(INVALID_COLOR, 0.95)
		ring_material.emission_enabled = true
		ring_material.emission = INVALID_COLOR
		ring_material.emission_energy_multiplier = 0.35
		ring = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.rings = 48
		torus.ring_segments = 6
		ring.mesh = torus
		ring.material_override = ring_material
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position.y = 0.1
		ghost.add_child(ring)
		ring.visible = false
		ghost.visible = false
	if _preview_kind == kind: return
	for child: Node in ghost.get_children():
		if child != ring: child.free()
	var scene: PackedScene = TOWER_SCENE if kind == "tower" else (BARRACKS_SCENE if kind == "barracks" else WORKSHOP_SCENE)
	var model := scene.instantiate() as Node3D
	ghost.add_child(model)
	if kind != "tower": game.districts.prepare_model(model)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = ghost_material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var radius := maxf(footprint(kind).x, footprint(kind).y)
	(ring.mesh as TorusMesh).inner_radius = maxf(0.01, radius - 0.04)
	(ring.mesh as TorusMesh).outer_radius = radius + 0.04
	_preview_kind = kind
	_preview_state = -1
