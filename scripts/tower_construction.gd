extends Node3D
## Read-only placement checks and a reused castle-tower preview. The controller
## owns confirmation, tower lifetime, economy and the actual construction.
const Layout := preload("res://scripts/outpost_layout.gd")
const TOWER_SCENE: PackedScene = preload("res://assets/models/auto_turret.glb")
const EDGE_MARGIN := 1.4
const CORE_CLEARANCE := 4.0
const DISTRICT_CLEARANCE := 3.0
const TOWER_CLEARANCE := 3.0
const PASSAGE_HALF_WIDTH := 2.0
const PASSAGE_START := 3.5
const BOUNDARY_EPSILON := 0.00001
const VALID_COLOR := Color(0.35, 0.9, 0.58, 0.32)
const INVALID_COLOR := Color(0.95, 0.3, 0.28, 0.32)

var game: Node3D
var active := false
var ghost: Node3D
var ring: MeshInstance3D
var ghost_material: StandardMaterial3D
var ring_material: StandardMaterial3D
var _preview_state := -1

func setup(owner_game: Node3D) -> void:
	clear()
	game = owner_game
	if get_parent() == null:
		game.add_child(self)

func begin() -> bool:
	if not is_instance_valid(game) or game.phase not in ["day", "night"]:
		return false
	active = true
	_ensure_preview()
	tick(0.0)
	return true

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
	game = null

func tick(_delta: float) -> void:
	if not active or not is_instance_valid(game) or game.phase not in ["day", "night"]:
		if is_instance_valid(ghost): ghost.visible = false
		return
	_ensure_preview()
	var placement: Dictionary = validity(game.aim)
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
	var placement: Dictionary = validity(point)
	placement["active"] = active
	return placement

func validity(point: Vector3, ignore_pad_index: int = -1) -> Dictionary:
	var result := {"valid": false, "space_valid": false, "reason": "", "cost": 0, "point": point}
	if not is_instance_valid(game):
		result.reason = "建设系统尚未初始化"
		return result
	result.cost = game.districts.tower_cost(int(game.TOWER_COSTS[0]))
	if not point.is_finite():
		result.reason = "放置位置无效"
		return result
	if game.phase not in ["day", "night"]:
		result.reason = "暂停时不能建造" if game.phase == "paused" else "当前不能建造防御塔"
		return result
	if not Layout.contains_castle(point):
		result.reason = "防御塔只能建在城内"
		return result
	# Vector3 components use float32, so an authored 11.6m edge can arrive as
	# 11.60000038. Accept only this rounding tolerance at the wall margin.
	if not Layout.contains_castle(point, EDGE_MARGIN - BOUNDARY_EPSILON):
		result.reason = "距离城墙至少1.4米"
		return result
	var height: float = game.outpost_height(point)
	if not is_finite(height) or absf(height - Layout.FORT_HEIGHT) > 0.05:
		result.reason = "需要城内平坦地面"
		return result
	result.point = Vector3(point.x, height, point.z)
	var flat := Vector2(point.x, point.z)
	if flat.length() < CORE_CLEARANCE:
		result.reason = "距离灯塔核心至少4米"
		return result
	if absf(point.x) < PASSAGE_HALF_WIDTH and point.z > PASSAGE_START:
		result.reason = "保留核心至南门通道"
		return result
	for plot: Dictionary in game.districts.plots:
		var district_point: Vector3 = plot.position
		if flat.distance_to(Vector2(district_point.x, district_point.z)) < DISTRICT_CLEARANCE:
			result.reason = "距离城区地块至少3米"
			return result
	for index in game.world.tower_pads.size():
		if index == ignore_pad_index: continue
		var pad: Dictionary = game.world.tower_pads[index]
		# Optional authored empty pads do not consume the castle's usable area.
		# A freely built tower keeps its foundation for paid F reconstruction.
		var occupied := int(pad.get("level", 0)) > 0 or bool(pad.get("free_built", false))
		if not occupied: continue
		var tower_point: Vector3 = pad.position
		if flat.distance_to(Vector2(tower_point.x, tower_point.z)) < TOWER_CLEARANCE:
			result.reason = "距离防御塔或残基至少3米"
			return result
	# Advice may show the cost deficit for a usable foundation, while a tower
	# blocked by geometry or a neighbouring free-built tower is never suggested.
	result.space_valid = true
	if int(game.scrap) < int(result.cost):
		result.reason = "零件不足 · 需要%d" % int(result.cost)
		return result
	result.valid = true
	result.reason = "可建造防御塔"
	return result

func confirm() -> bool:
	if not active or not is_instance_valid(game): return false
	# The current cursor and economy may change after tick. The controller also
	# revalidates this point before spending, so cached green previews cannot pay.
	var placement: Dictionary = validity(game.aim)
	if not bool(placement.valid): return false
	if not game.build_tower_at(placement.point): return false
	cancel()
	return true

func _ensure_preview() -> void:
	if is_instance_valid(ghost): return
	ghost = Node3D.new()
	ghost.name = "TowerPlacementPreview"
	add_child(ghost)
	ghost_material = StandardMaterial3D.new()
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	ghost_material.albedo_color = INVALID_COLOR
	var model: Node3D = TOWER_SCENE.instantiate()
	ghost.add_child(model)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = ghost_material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring_material = StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color(INVALID_COLOR, 0.95)
	ring_material.emission_enabled = true
	ring_material.emission = INVALID_COLOR
	ring_material.emission_energy_multiplier = 0.35
	ring = MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = EDGE_MARGIN - 0.06
	mesh.outer_radius = EDGE_MARGIN + 0.06
	mesh.rings = 48
	mesh.ring_segments = 6
	ring.mesh = mesh
	ring.material_override = ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.1
	ghost.add_child(ring)
	ghost.visible = false
	_preview_state = -1
