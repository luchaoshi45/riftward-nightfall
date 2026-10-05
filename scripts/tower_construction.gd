extends Node3D
## Shared construction selection. The controller owns payment and building lifetime.
const Layout := preload("res://scripts/outpost_layout.gd")
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

var game: Node3D
var active := false
var kind := "tower"
var ghost: Node3D
var ring: MeshInstance3D
var ghost_material: StandardMaterial3D
var ring_material: StandardMaterial3D
var _preview_state := -1
var _preview_kind := ""
var _footprints: Dictionary = {}
var _has_hero := false
var _has_squads := false

func setup(owner_game: Node3D) -> void:
	clear()
	game = owner_game
	if get_parent() == null: game.add_child(self)
	for property: Dictionary in game.get_property_list():
		if String(property.name) == "hero": _has_hero = true
		if String(property.name) == "squads": _has_squads = true

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

func clear() -> void:
	cancel()
	if is_instance_valid(ghost): ghost.queue_free()
	ghost = null
	ring = null
	ghost_material = null
	ring_material = null
	_preview_state = -1
	_preview_kind = ""
	_has_hero = false
	_has_squads = false
	game = null

func tick(_delta: float) -> void:
	if not active or not is_instance_valid(game) or game.phase not in ["day", "night"]:
		if is_instance_valid(ghost): ghost.visible = false
		return
	_ensure_preview()
	var placement := validity(game.aim, -1, kind)
	var point: Vector3 = placement.point
	if not point.is_finite():
		ghost.visible = false
		return
	ghost.position = point
	ghost.visible = true
	var state := 1 if bool(placement.valid) else 0
	if state != _preview_state:
		_preview_state = state
		var tint: Color = VALID_COLOR if state == 1 else INVALID_COLOR
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
	var result := {"valid": false, "space_valid": false, "reason": "", "cost": 0, "point": point,
		"kind": structure_kind, "title": String(TITLES.get(structure_kind, "建筑"))}
	if not is_instance_valid(game):
		result.reason = "建设系统尚未初始化"
		return result
	if not TITLES.has(structure_kind):
		result.reason = "未知建筑"
		return result
	result.cost = game.districts.tower_cost(int(game.TOWER_COSTS[0])) if structure_kind == "tower" else int(game.districts.BUILD_COST)
	if not point.is_finite():
		result.reason = "放置位置无效"
		return result
	if game.phase not in ["day", "night"]:
		result.reason = "暂停或选卡时不能建造"
		return result
	if not Layout.contains_castle(point):
		result.reason = "建筑只能建在城内"
		return result
	var half := footprint(structure_kind)
	if absf(point.x) + half.x > Layout.FORT_INNER + BOUNDARY_EPSILON or absf(point.z) + half.y > Layout.FORT_INNER + BOUNDARY_EPSILON:
		result.reason = "建筑底座不能覆盖城墙"
		return result
	var height: float = game.outpost_height(point)
	if not is_finite(height) or absf(height - Layout.FORT_HEIGHT) > 0.05:
		result.reason = "需要城内平坦地面"
		return result
	result.point = Vector3(point.x, height, point.z)
	var flat := Vector2(point.x, point.z)
	if _overlaps(flat, half, structure_kind == "tower", Vector2.ZERO, footprint("core"), true):
		result.reason = "不能覆盖灯塔核心底座"
		return result
	for index in game.districts.plots.size():
		if index == ignore_plot_index: continue
		var plot: Dictionary = game.districts.plots[index]
		if int(plot.get("level", 0)) <= 0 or float(plot.get("hp", 0.0)) <= 0.0: continue
		var district_point: Vector3 = plot.position
		if _overlaps(flat, half, structure_kind == "tower", Vector2(district_point.x, district_point.z), footprint(String(plot.kind)), false):
			result.reason = "不能覆盖已有建筑"
			return result
	for index in game.world.tower_pads.size():
		if index == ignore_pad_index: continue
		var pad: Dictionary = game.world.tower_pads[index]
		if int(pad.get("level", 0)) <= 0 and not bool(pad.get("free_built", false)): continue
		var tower_point: Vector3 = pad.position
		if _overlaps(flat, half, structure_kind == "tower", Vector2(tower_point.x, tower_point.z), footprint("tower"), true):
			result.reason = "不能覆盖防御塔或残基"
			return result
	for unit: Node3D in _living_units():
		var position := unit.position
		if absf(position.y - height) > 1.0: continue
		# Navigation uses a small expanded AABB, including a tower's circular
		# corners. Never allow its new movement block to trap an existing unit.
		if _overlaps(flat, half + Vector2.ONE * NAVIGATION_MARGIN, false, Vector2(position.x, position.z), Vector2.ONE * UNIT_BODY_RADIUS, true):
			result.reason = "不能覆盖正在这里的单位"
			return result
	result.space_valid = true
	if int(game.scrap) < int(result.cost):
		result.reason = "零件不足 · 需要%d" % int(result.cost)
		return result
	result.valid = true
	result.reason = "可建造%s" % String(result.title)
	return result

func footprint(structure_kind: String) -> Vector2:
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
		var hero := game.get("hero") as Node3D
		if is_instance_valid(hero) and _unit_alive(hero): units.append(hero)
	if _has_squads:
		var squads: Node = game.get("squads") as Node
		if is_instance_valid(squads):
			for squad: Dictionary in squads.get("squads"):
				for member: Node3D in squad.members:
					if is_instance_valid(member) and _unit_alive(member): units.append(member)
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
