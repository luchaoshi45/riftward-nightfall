extends Node3D
## Short-range cone fire for flamethrower squads.
## BattleUnit.tick owns the windup/cooldown clock; this module only owns the
## live cone target set and its once-only damage commit.

const MIN_RANGE := 2.5
const MAX_RANGE := 6.5
const HALF_ANGLE_DEGREES := 32.0
const WINDUP := 0.55
const COOLDOWN := 3.2
const MAX_TARGETS := 4
const HEIGHT_LIMIT := 0.9
const WARNING_SEGMENTS := 10

var game: Node3D
var roster: Node3D
var _units: Dictionary = {}
var _epoch := 0
var _bursts := 0
var _hits := 0
var _cancellations := 0

func setup(controller: Node3D, squad_roster: Node3D) -> void:
	clear()
	game = controller
	roster = squad_roster

func register(source: BattleUnit) -> void:
	if not is_instance_valid(source): return
	_units[source.get_instance_id()] = {"unit": weakref(source), "cast": {}}

func real_enemy(value: Variant) -> bool:
	return _living(value) and value.kind == "monster" and value.team == 2 \
		and is_instance_valid(game) and value in game.get("enemies")

func real_source(source: Variant) -> bool:
	if not _living(source) or not is_instance_valid(roster): return false
	var state: Dictionary = _units.get(source.get_instance_id(), {})
	if state.is_empty() or (state.unit as WeakRef).get_ref() != source: return false
	for squad: Dictionary in roster.get("squads"):
		if String(squad.kind) != "flamer" or int(squad.id) != int(state.squad_id): continue
		var slot := int(state.slot)
		return slot >= 0 and slot < squad.members.size() and squad.members[slot] == source
	return false

func register_with_roster(source: BattleUnit, squad_id: int, slot: int) -> void:
	register(source)
	var state: Dictionary = _units.get(source.get_instance_id(), {})
	if not state.is_empty():
		state.squad_id = squad_id
		state.slot = slot

func _living(value: Variant) -> bool:
	return is_instance_valid(value) and value is BattleUnit and not value.is_queued_for_deletion() \
		and value.alive and value.hp > 0.0

func _active() -> bool:
	return is_instance_valid(game) and String(game.get("phase")) in ["day", "night"]

func distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z))

func _ground_height(point: Vector3) -> float:
	if is_instance_valid(game) and game.has_method("outpost_height"):
		return float(game.call("outpost_height", point))
	return point.y

func _grounded(first: Vector3, second: Vector3) -> bool:
	if not first.is_finite() or not second.is_finite(): return false
	var first_height := _ground_height(first)
	var second_height := _ground_height(second)
	var first_offset := first.y - first_height
	var second_offset := second.y - second_height
	return is_finite(first_height) and is_finite(second_height) \
		and absf(first_offset) <= HEIGHT_LIMIT + .000001 \
		and absf(second_offset) <= HEIGHT_LIMIT + .000001 \
		and absf(first_offset - second_offset) <= HEIGHT_LIMIT + .000001

func _line(from: Vector3, to: Vector3) -> bool:
	return not game.has_method("can_attack_line") or bool(game.call("can_attack_line", from, to))

func _in_cone(origin: Vector3, direction: Vector3, target: Vector3) -> bool:
	var axis := Vector2(direction.x, direction.z)
	var offset := Vector2(target.x - origin.x, target.z - origin.z)
	if axis.length_squared() <= .000001 or offset.length_squared() <= .000001: return false
	var dot := clampf(axis.normalized().dot(offset.normalized()), -1.0, 1.0)
	return acos(dot) <= deg_to_rad(HALF_ANGLE_DEGREES) + .000001

func legal_target(source: BattleUnit, target: Variant) -> bool:
	if not real_source(source) or not real_enemy(target): return false
	var separation := distance(source.position, target.position)
	return separation >= MIN_RANGE and separation <= MAX_RANGE \
		and _grounded(source.position, target.position) and _line(source.position, target.position)

func pick_target(source: BattleUnit, preferred: BattleUnit = null) -> BattleUnit:
	if not real_source(source): return null
	if legal_target(source, preferred): return preferred
	var chosen: BattleUnit
	var best := INF
	for value: Variant in game.get("enemies"):
		if not legal_target(source, value): continue
		var separation := distance(source.position, value.position)
		if separation < best:
			best = separation
			chosen = value as BattleUnit
	return chosen

func casting(source: BattleUnit) -> bool:
	if not is_instance_valid(source): return false
	var cast_value: Variant = _units.get(source.get_instance_id(), {}).get("cast", {})
	return cast_value is Dictionary and not (cast_value as Dictionary).is_empty()

func begin(source: BattleUnit, target: BattleUnit) -> bool:
	if not _active() or not real_source(source) or not legal_target(source, target): return false
	if source.attack_timer > 0.0 or source.moving or casting(source): return false
	var state: Dictionary = _units.get(source.get_instance_id(), {})
	if state.is_empty(): return false
	var direction := target.position - source.position
	direction.y = 0.0
	if direction.length_squared() <= .000001: return false
	direction = direction.normalized()
	var cast := {"phase": "windup", "remaining": WINDUP, "total": WINDUP,
		"source_token": source.get_instance_id(), "target_token": target.get_instance_id(),
		"source_ref": weakref(source), "target_ref": weakref(target),
		"source_position": source.position, "direction": direction, "damage": 0.0,
		"visual": null}
	state.cast = cast
	source.target = target
	source.attack_queued = true
	source.attack_windup = WINDUP
	source.face(target.position, .05)
	_create_warning(cast)
	_update_visual(cast)
	return true

func advance_unit(source: BattleUnit, delta: float) -> void:
	if not _active() or not is_finite(delta) or delta <= 0.0 or not is_instance_valid(source): return
	var state: Dictionary = _units.get(source.get_instance_id(), {})
	var cast: Dictionary = state.get("cast", {})
	if cast.is_empty(): return
	var target := (cast.target_ref as WeakRef).get_ref() as BattleUnit
	if not real_source(source) or source.moving or distance(source.position, cast.source_position) > .01 \
		or not legal_target(source, target):
		cancel(source, "target_invalid")
		return
	cast.remaining = source.attack_windup
	source.face(cast.source_position + cast.direction, delta)
	_update_visual(cast)
	if source.attack_windup > 0.0: return
	state.cast = {}
	source.target = null
	source.attack_queued = false
	source.attack_windup = 0.0
	source.attack_timer = COOLDOWN
	source.attack_pose = 1.0
	cast.phase = "impact"
	cast.damage = maxf(0.0, source.damage)
	_bursts += 1
	_emit_burst(cast, source)
	_free_visual(cast)

func cancel(source: BattleUnit, _reason: String = "order_changed") -> void:
	if not is_instance_valid(source): return
	var state: Dictionary = _units.get(source.get_instance_id(), {})
	var cast: Dictionary = state.get("cast", {})
	if not cast.is_empty():
		_cancellations += 1
		_free_visual(cast)
		state.cast = {}
	source.target = null
	source.attack_queued = false
	source.attack_windup = 0.0

func unregister(source: BattleUnit) -> void:
	if not is_instance_valid(source): return
	cancel(source, "source_dead")
	_units.erase(source.get_instance_id())

func clear_pending() -> void:
	_epoch += 1
	for state: Dictionary in _units.values():
		var source := (state.unit as WeakRef).get_ref() as BattleUnit
		if is_instance_valid(source): cancel(source, "phase_changed")

func clear() -> void:
	clear_pending()
	_units.clear()
	_bursts = 0
	_hits = 0
	_cancellations = 0

func advance(_delta: float) -> void:
	# The owning squad advances each member and calls advance_unit immediately;
	# this hook exists for symmetry with artillery and future visual cleanup.
	pass

func _emit_burst(cast: Dictionary, source: BattleUnit) -> void:
	var generation := _epoch
	var victims: Array[BattleUnit] = []
	for value: Variant in game.get("enemies"):
		if not real_enemy(value): continue
		var enemy := value as BattleUnit
		if distance(source.position, enemy.position) < MIN_RANGE \
			or distance(source.position, enemy.position) > MAX_RANGE \
			or not _grounded(source.position, enemy.position) \
			or not _in_cone(source.position, cast.direction, enemy.position) \
			or not _line(source.position, enemy.position): continue
		victims.append(enemy)
	# Pick nearest victims explicitly so the four-target cap is deterministic
	# even when the controller's enemy list contains dynamic reinforcements.
	while not victims.is_empty() and victims.size() > MAX_TARGETS:
		var farthest := 0
		var farthest_distance := distance(source.position, victims[0].position)
		for index in range(1, victims.size()):
			var candidate_distance := distance(source.position, victims[index].position)
			if candidate_distance > farthest_distance:
				farthest = index
				farthest_distance = candidate_distance
		victims.remove_at(farthest)
	for victim: BattleUnit in victims:
		if generation != _epoch or not _active() or not real_enemy(victim): return
		victim.hurt(float(cast.damage), source)
		_hits += 1
	BattleVisuals.burst(self, source.position + Vector3.UP * .12, 1.0, Color("f09a54"), .18)

func _create_warning(cast: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "FlamethrowerConeWarning"
	add_child(root)
	cast.visual = root
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "FlamethrowerCone"
	mesh_node.mesh = _cone_mesh(MAX_RANGE, deg_to_rad(HALF_ANGLE_DEGREES))
	var tint := Color("ee9b50", .34)
	var material := BattleVisuals.material(tint, .22)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_node.material_override = material
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh_node)

func _cone_mesh(radius: float, half_angle: float) -> ArrayMesh:
	var vertices := PackedVector3Array([Vector3.ZERO])
	var normals := PackedVector3Array([Vector3.UP])
	var indices := PackedInt32Array()
	for index in range(WARNING_SEGMENTS + 1):
		var angle := -half_angle + (half_angle * 2.0) * float(index) / float(WARNING_SEGMENTS)
		vertices.append(Vector3(sin(angle) * radius, .035, cos(angle) * radius))
		normals.append(Vector3.UP)
	for index in range(WARNING_SEGMENTS):
		indices.append_array(PackedInt32Array([0, index + 1, index + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _update_visual(cast: Dictionary) -> void:
	var root := cast.get("visual") as Node3D
	var source := (cast.source_ref as WeakRef).get_ref() as BattleUnit
	if not is_instance_valid(root) or not is_instance_valid(source): return
	root.position = source.position
	root.rotation.y = atan2(cast.direction.x, cast.direction.z)
	var cone := root.get_node_or_null("FlamethrowerCone") as MeshInstance3D
	if not is_instance_valid(cone): return
	var material := cone.material_override as StandardMaterial3D
	if is_instance_valid(material):
		material.albedo_color.a = .14 + .22 * clampf(float(cast.remaining) / WINDUP, 0.0, 1.0)

func _free_visual(cast: Dictionary) -> void:
	var root := cast.get("visual") as Node3D
	if is_instance_valid(root): root.queue_free()

func snapshot() -> Dictionary:
	var rows: Array[Dictionary] = []
	var casting_count := 0
	for state: Dictionary in _units.values():
		var source := (state.unit as WeakRef).get_ref() as BattleUnit
		if not real_source(source): continue
		var cast: Dictionary = state.get("cast", {})
		if not cast.is_empty(): casting_count += 1
		var target := (cast.target_ref as WeakRef).get_ref() as BattleUnit if cast.get("target_ref") is WeakRef else null
		rows.append({"unit": source, "source_token": source.get_instance_id(),
			"phase": "windup" if not cast.is_empty() else "idle",
			"remaining": source.attack_windup if not cast.is_empty() else 0.0,
			"total": WINDUP, "target": target if real_enemy(target) else null,
			"target_token": target.get_instance_id() if real_enemy(target) else -1})
	return {"bursts": _bursts, "hits": _hits, "cancellations": _cancellations,
		"casting": casting_count,
		"alive": rows.size(), "units": rows}

func _exit_tree() -> void:
	clear()
