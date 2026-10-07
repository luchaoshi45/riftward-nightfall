class_name NightfallBurstling
extends Node3D
## 近程固定圆心蓄爆。false 仅允许根控制器继续原寻路，不允许普通攻击。

const Construction = preload("res://scripts/tower_construction.gd")
const ARM_RANGE: float = 1.8
const WINDUP_SECONDS: float = 1.4
const BLAST_RADIUS: float = 2.4
const HEIGHT_TOLERANCE: float = 0.75
const RESET_SECONDS: float = 1.0
const WARNING_SEGMENTS: int = 48

var game: Node3D
var host: BattleUnit
var _state: String = "idle"
var _remaining: float = 0.0
var _cooldown: float = 0.0
var _point: Vector3 = Vector3.ZERO
var _source_position: Vector3 = Vector3.ZERO
var _source_token: int = -1
var _target: Dictionary = {}
var _damage: float = 0.0
var _generation: int = 0
var _detonated: bool = false
var _cancel_reason: String = ""
var _cancelled: int = 0
var _impacts: int = 0
var _targets_hit: int = 0
var _normal_windup: float = 0.34
var _warning_root: Node3D
var _ring: MeshInstance3D
var _progress_ring: MeshInstance3D
var _progress_radius: float = -1.0
var _prototype_root: Node3D

func setup(owner_game: Node3D, owner_host: BattleUnit) -> void:
	clear()
	game = owner_game
	host = owner_host
	_source_token = host.get_instance_id() if is_instance_valid(host) else -1
	var generation := _generation
	if get_parent() == null and is_instance_valid(game): game.add_child(self)
	if generation != _generation or not _living(host): return
	_normal_windup = host.windup_duration
	_state = "idle"
	_cancel_reason = ""
	_cancelled = 0
	_impacts = 0
	_targets_hit = 0
	_detonated = false
	host.title = "爆裂体"
	host.set_meta("threat", "burstling")
	host.set_meta("burstling_controller_token", get_instance_id())
	host.set_meta("burstling_winding", false)
	host.attack_range = ARM_RANGE
	host.windup_duration = WINDUP_SECONDS
	if not host.defeated.is_connected(_on_host_defeated): host.defeated.connect(_on_host_defeated)
	_attach_prototype()

func advance(delta: float) -> bool:
	if not _owner_available():
		clear()
		return false
	var phase_name := String(game.get("phase"))
	if _ending() or phase_name not in ["night", "paused", "draft"]:
		clear()
		return false
	if phase_name in ["paused", "draft"] or not is_finite(delta) or delta <= 0.0:
		return _state in ["windup", "committing", "detonated"]
	# Commit before hurt(): a synchronous callback cannot spend this source again.
	if _state == "committing": return true
	if _detonated: return true
	_cooldown = maxf(0.0, _cooldown - delta)
	var generation := _generation
	var rejection := _source_rejection()
	if generation != _generation or not _active(): return false
	if not rejection.is_empty():
		if _state == "windup":
			_cancel(rejection)
			return true
		_cancel_reason = rejection
		_state = "cooldown" if _cooldown > 0.0 else "idle"
		_clear_host_attack()
		return false
	if _state == "windup":
		_remaining = maxf(0.0, _remaining - delta)
		host.moving = false
		host.attack_queued = true
		host.attack_windup = _remaining
		host.face(_target.get("position", _point), delta)
		_update_warning()
		if _remaining <= 0.0: _detonate()
		return true
	_clear_host_attack()
	if _cooldown > 0.0:
		_state = "cooldown"
		return false
	_state = "idle"
	var selected := _pick_target()
	if generation != _generation or not _active() or selected.is_empty(): return false
	_begin(selected)
	return _state == "windup"

func revalidate_cast() -> void:
	# Real tower/net control lands later in the same frame. No clock advances here.
	if not _active() or _state != "windup": return
	var generation := _generation
	var rejection := _source_rejection()
	if generation == _generation and _active() and not rejection.is_empty(): _cancel(rejection)

func snapshot() -> Dictionary:
	var source: BattleUnit = host if is_instance_valid(host) else null
	return {"phase": _state, "source": source, "source_token": _source_token,
		"source_title": "爆裂体", "position": _point, "radius": BLAST_RADIUS,
		"remaining": _remaining if _state == "windup" else 0.0, "total": WINDUP_SECONDS,
		"progress": 1.0 if _detonated else (1.0 - clampf(_remaining / WINDUP_SECONDS, 0.0, 1.0) if _state == "windup" else 0.0),
		"cooldown": _cooldown, "target_kind": String(_target.get("kind", "")),
		"target_token": int(_target.get("token", -1)), "target_index": int(_target.get("index", -1)),
		"cancel_reason": _cancel_reason, "cancelled": _cancelled, "impacts": _impacts,
		"damage": _damage, "detonated": _detonated, "targets_hit": _targets_hit}

func clear() -> void:
	_generation += 1
	_clear_host_attack()
	if is_instance_valid(host):
		if host.defeated.is_connected(_on_host_defeated): host.defeated.disconnect(_on_host_defeated)
		if int(host.get_meta("burstling_controller_token", -1)) == get_instance_id():
			host.remove_meta("burstling_controller_token")
			host.windup_duration = _normal_windup
	_clear_warning()
	if is_instance_valid(_prototype_root):
		_prototype_root.visible = false
		_prototype_root.queue_free()
	_prototype_root = null
	host = null
	_source_token = -1
	_target = {}
	_state = "idle"
	_remaining = 0.0
	_cooldown = 0.0
	_damage = 0.0
	_detonated = false
	_point = Vector3.ZERO

func _exit_tree() -> void:
	clear()

func _living(value: Variant) -> bool:
	return is_instance_valid(value) and value is BattleUnit and not value.is_queued_for_deletion() \
		and value.alive and value.hp > 0.0

func _owner_available() -> bool:
	return is_instance_valid(game) and not game.is_queued_for_deletion() \
		and not is_queued_for_deletion() and get_parent() == game

func _ending() -> bool:
	return bool(game.get("quitting")) or bool(game.get("restart_pending")) or bool(game.get("shutting_down"))

func _active() -> bool:
	return _owner_available() and String(game.get("phase")) == "night" and not _ending()

func _owns_source() -> bool:
	if not _living(host) or not _owner_available(): return false
	var controllers: Variant = game.get("burstlings")
	var enemies: Variant = game.get("enemies")
	return controllers is Array and self in controllers and enemies is Array and host in enemies \
		and host.get_instance_id() == _source_token and host.get_parent() == game \
		and host.kind == "monster" and host.team == 2 and String(host.get_meta("threat", "")) == "burstling" \
		and int(host.get_meta("burstling_controller_token", -1)) == get_instance_id()

func _ground_height(point: Vector3) -> float:
	return float(game.call("outpost_height", point)) if is_instance_valid(game) else NAN

func _grounded(point: Vector3) -> bool:
	if not point.is_finite(): return false
	var ground := _ground_height(point)
	return is_finite(ground) and absf(point.y - ground) <= HEIGHT_TOLERANCE

func _distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))

func _controlled() -> bool:
	if not _living(host) or not _owner_available(): return false
	var controls: Variant = game.get("specializations")
	return is_instance_valid(controls) and float(controls.call("movement_multiplier", host)) < 0.9999

func _source_rejection() -> String:
	if not _living(host): return "source_dead"
	if not _owns_source(): return "source_roster"
	if not _grounded(host.position): return "source_height"
	if not bool(game.call("outpost_walkable", host.position)): return "source_blocked"
	if _state == "windup" and host.position.distance_to(_source_position) > 0.05: return "source_moved"
	if _controlled(): return "source_controlled"
	return ""

func _target_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var seen: Dictionary = {}
	var hero_value: Variant = game.get("hero")
	if _living(hero_value) and hero_value.kind == "hero" and hero_value.team == 0 and hero_value.get_parent() == game:
		rows.append({"kind": "hero", "index": -1, "token": hero_value.get_instance_id(), "unit": hero_value})
		seen[hero_value.get_instance_id()] = true
	var roster_value: Variant = game.get("squads")
	if is_instance_valid(roster_value) and roster_value is Node3D and not roster_value.is_queued_for_deletion():
		var roster := roster_value as Node3D
		var groups: Array = roster.get("squads")
		for group_index in groups.size():
			var group_value: Variant = groups[group_index]
			if not group_value is Dictionary: continue
			var group: Dictionary = group_value
			var members: Array = group.get("members", [])
			for slot in members.size():
				var member_value: Variant = members[slot]
				if not _living(member_value) or member_value.kind != "minion" or member_value.team != 0 \
					or member_value.get_parent() != roster or seen.has(member_value.get_instance_id()): continue
				seen[member_value.get_instance_id()] = true
				rows.append({"kind": "squad", "index": -1, "token": member_value.get_instance_id(),
					"unit": member_value, "roster": roster, "group": group, "group_index": group_index, "slot": slot})
	var world_value: Variant = game.get("world")
	if is_instance_valid(world_value) and world_value is Node3D and not world_value.is_queued_for_deletion():
		var world := world_value as Node3D
		var pads: Array = world.get("tower_pads")
		for index in pads.size():
			var pad_value: Variant = pads[index]
			if not pad_value is Dictionary: continue
			var pad: Dictionary = pad_value
			var model: Variant = pad.get("turret")
			if int(pad.get("level", 0)) <= 0 or float(pad.get("hp", 0.0)) <= 0.0 or not _model_live(model, world): continue
			rows.append({"kind": "tower", "index": index, "token": model.get_instance_id(), "model": model,
				"owner": world, "row": pad, "structure_kind": "tower", "center": pad.position})
		var beacon_value: Variant = world.get("beacon")
		if float(game.get("beacon_hp")) > 0.0 and _model_live(beacon_value, world):
			rows.append({"kind": "beacon", "index": -1, "token": beacon_value.get_instance_id(),
				"model": beacon_value, "owner": world, "structure_kind": "core", "center": beacon_value.position})
		var barricade_value: Variant = game.get("gate_barricade")
		if float(game.get("gate_barricade_hp")) > 0.0 and _model_live(barricade_value, world):
			rows.append({"kind": "barricade", "index": -1, "token": barricade_value.get_instance_id(),
				"model": barricade_value, "owner": world, "structure_kind": "barricade", "center": barricade_value.position})
	var districts_value: Variant = game.get("districts")
	if is_instance_valid(districts_value) and districts_value is Node3D and not districts_value.is_queued_for_deletion():
		var districts := districts_value as Node3D
		var plots: Array = districts.get("plots")
		for index in plots.size():
			var plot_value: Variant = plots[index]
			if not plot_value is Dictionary: continue
			var plot: Dictionary = plot_value
			var model: Variant = plot.get("model")
			if int(plot.get("level", 0)) <= 0 or float(plot.get("hp", 0.0)) <= 0.0 or not _model_live(model, districts): continue
			rows.append({"kind": "district", "index": index, "token": model.get_instance_id(), "model": model,
				"owner": districts, "row": plot, "structure_kind": String(plot.kind), "center": plot.position})
	return rows

func _model_live(value: Variant, owner: Node3D) -> bool:
	return is_instance_valid(value) and value is Node3D and not value.is_queued_for_deletion() \
		and is_instance_valid(owner) and owner.is_ancestor_of(value)

func _target_current(selected: Dictionary) -> bool:
	var kind := String(selected.get("kind", ""))
	var token := int(selected.get("token", -1))
	if kind in ["hero", "squad"]:
		var unit: Variant = selected.get("unit")
		if not _living(unit) or unit.get_instance_id() != token or unit.team != 0: return false
		if kind == "hero": return game.get("hero") == unit and unit.kind == "hero" and unit.get_parent() == game
		var roster: Variant = selected.get("roster")
		if not is_instance_valid(roster) or roster != game.get("squads") or roster.is_queued_for_deletion() \
			or unit.kind != "minion" or unit.get_parent() != roster: return false
		var groups: Array = roster.get("squads")
		var group_index := int(selected.get("group_index", -1))
		if group_index < 0 or group_index >= groups.size() or not is_same(groups[group_index], selected.get("group")): return false
		var members: Array = groups[group_index].get("members", [])
		var slot := int(selected.get("slot", -1))
		return slot >= 0 and slot < members.size() and members[slot] == unit
	var owner: Variant = selected.get("owner")
	var model: Variant = selected.get("model")
	if not is_instance_valid(owner) or not owner is Node3D or not _model_live(model, owner as Node3D) \
		or model.get_instance_id() != token: return false
	if kind == "district":
		if owner != game.get("districts"): return false
		var plots: Array = owner.get("plots")
		var index := int(selected.get("index", -1))
		if index < 0 or index >= plots.size() or not is_same(plots[index], selected.get("row")): return false
		var plot: Dictionary = plots[index]
		return int(plot.level) > 0 and float(plot.hp) > 0.0 and plot.get("model") == model
	if owner != game.get("world"): return false
	match kind:
		"tower":
			var pads: Array = owner.get("tower_pads")
			var index := int(selected.get("index", -1))
			if index < 0 or index >= pads.size() or not is_same(pads[index], selected.get("row")): return false
			var pad: Dictionary = pads[index]
			return int(pad.level) > 0 and float(pad.hp) > 0.0 and pad.get("turret") == model
		"barricade": return game.get("gate_barricade") == model and float(game.get("gate_barricade_hp")) > 0.0
		"beacon": return owner.get("beacon") == model and float(game.get("beacon_hp")) > 0.0
	return false

func _surface(selected: Dictionary, origin: Vector3) -> Vector3:
	if String(selected.kind) in ["hero", "squad"]:
		var value: Variant = selected.get("unit")
		return value.position if _living(value) else Vector3.INF
	var center: Vector3 = selected.get("center", Vector3.INF)
	if not center.is_finite(): return Vector3.INF
	var rect: Rect2
	if String(selected.kind) == "barricade":
		var model: Variant = selected.get("model")
		if not is_instance_valid(model) or not model is Node3D: return Vector3.INF
		rect = _model_rect(model as Node3D)
	else:
		var construction: Variant = game.get("construction")
		if not is_instance_valid(construction): return Vector3.INF
		var half: Vector2 = construction.call("footprint", String(selected.structure_kind))
		rect = Rect2(Vector2(center.x, center.z) - half, half * 2.0)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0: return Vector3.INF
	return Vector3(clampf(origin.x, rect.position.x, rect.end.x), center.y, clampf(origin.z, rect.position.y, rect.end.y))

func _model_rect(model: Node3D) -> Rect2:
	# The gate prop has no grid entry; its real mesh bounds define its surface.
	var bounds := {"minimum": Vector2(INF, INF), "maximum": Vector2(-INF, -INF)}
	_collect_model_bounds(model, bounds)
	var minimum: Vector2 = bounds.minimum
	var maximum: Vector2 = bounds.maximum
	return Rect2(minimum, maximum - minimum) if minimum.is_finite() and maximum.is_finite() else Rect2()

func _collect_model_bounds(node: Node3D, bounds: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var box: AABB = node.mesh.get_aabb()
		var transform_to_game := game.global_transform.affine_inverse() * node.global_transform
		for corner in 8:
			var point: Vector3 = transform_to_game * box.get_endpoint(corner)
			var flat := Vector2(point.x, point.z)
			bounds.minimum = (bounds.minimum as Vector2).min(flat)
			bounds.maximum = (bounds.maximum as Vector2).max(flat)
	for child: Node in node.get_children():
		if child is Node3D: _collect_model_bounds(child as Node3D, bounds)

func _legal_surface(origin: Vector3, selected: Dictionary, radius: float) -> bool:
	if not _target_current(selected): return false
	var point := _surface(selected, origin)
	if not _grounded(origin) or not _grounded(point) or _distance(origin, point) > radius: return false
	var first_offset := origin.y - _ground_height(origin)
	var second_offset := point.y - _ground_height(point)
	if absf(first_offset - second_offset) > HEIGHT_TOLERANCE or not _attack_line(origin, point, selected): return false
	if String(selected.kind) not in ["hero", "squad"]:
		return _attack_line(origin, selected.center, selected)
	return true

func _attack_line(origin: Vector3, destination: Vector3, selected: Dictionary) -> bool:
	if not bool(game.call("can_attack_line", origin, destination)): return false
	var blocks: Variant = game.get("construction_blocks")
	if not blocks is Array: return false
	var own_rect := Rect2()
	if String(selected.kind) in ["tower", "district", "beacon"]:
		var construction: Variant = game.get("construction")
		if not is_instance_valid(construction): return false
		var half: Vector2 = construction.call("footprint", String(selected.structure_kind))
		var center: Vector3 = selected.center
		own_rect = Rect2(Vector2(center.x, center.z) - half, half * 2.0).grow(Construction.NAVIGATION_MARGIN)
	var flat := Vector2(origin.x, origin.z)
	var direction := Vector2(destination.x - origin.x, destination.z - origin.z)
	for value: Variant in blocks:
		if not value is Rect2: continue
		var block: Rect2 = value
		# The recipient's own real footprint permits contact with its surface;
		# another live structure remains an obstruction, including for blast rays.
		if own_rect.size != Vector2.ZERO and block.is_equal_approx(own_rect): continue
		if bool(game.call("segment_crosses_wall", flat, direction, block)): return false
	return true

func _pick_target() -> Dictionary:
	var chosen: Dictionary = {}
	var best := INF
	for selected: Dictionary in _target_rows():
		if not _legal_surface(host.position, selected, ARM_RANGE): continue
		var point := _surface(selected, host.position)
		var separation := _distance(host.position, point)
		if separation < best or (is_equal_approx(separation, best) and int(selected.token) < int(chosen.get("token", 9223372036854775807))):
			best = separation
			chosen = selected
			chosen.position = point
	return chosen

func _begin(selected: Dictionary) -> void:
	var generation := _generation
	_target = selected
	_source_position = host.position
	_point = Vector3(host.position.x, _ground_height(host.position), host.position.z)
	_state = "windup"
	_remaining = WINDUP_SECONDS
	_cancel_reason = ""
	host.moving = false
	host.attack_queued = true
	host.attack_windup = WINDUP_SECONDS
	host.set_meta("burstling_winding", true)
	host.set_meta("attack_target_kind", String(_target.kind))
	host.set_meta("attack_target_index", int(_target.index))
	host.set_meta("attack_target_token", int(_target.token))
	_clear_warning()
	_warning_root = Node3D.new()
	_warning_root.name = "BurstlingFixedGroundWarning"
	_ring = _terrain_ring(BLAST_RADIUS, 0.07, 0.085, Color("d98c59"))
	_ring.name = "BurstlingGroundDangerRadius"
	_progress_radius = BLAST_RADIUS * 0.10
	_progress_ring = _terrain_ring(_progress_radius, 0.035, 0.12, Color("c76c4e"))
	_progress_ring.name = "BurstlingGroundCountdown"
	add_child(_warning_root)
	if generation == _generation and _state == "windup": _update_warning()

func _cancel(reason: String) -> void:
	_state = "cooldown"
	_remaining = 0.0
	_cooldown = RESET_SECONDS
	_cancel_reason = reason
	_cancelled += 1
	_clear_host_attack()
	_clear_warning()
	if _living(host): host.moving = false

func _clear_host_attack() -> void:
	if not is_instance_valid(host) or int(host.get_meta("burstling_controller_token", -1)) != get_instance_id(): return
	host.attack_queued = false
	host.attack_windup = 0.0
	host.attack_target_hero = false
	host.set_meta("burstling_winding", false)
	host.set_meta("attack_target_kind", "")
	host.set_meta("attack_target_index", -1)
	host.set_meta("attack_target_token", -1)

func _on_host_defeated(_unit: BattleUnit, _source: BattleUnit) -> void:
	if _state == "windup": _cancel("source_dead")
	# A committed blast is one event: reflection death cannot discard its other hits.
	if _state != "committing": _clear_warning()

func _commit_active(generation: int, owner_token: int) -> bool:
	if generation != _generation or not _active() or game.get_instance_id() != owner_token \
		or _state != "committing" or not _detonated: return false
	var controllers: Variant = game.get("burstlings")
	if not controllers is Array or not self in controllers: return false
	if not is_instance_valid(host): return true
	if host.get_instance_id() != _source_token: return false
	# Reflection may retire this exact source during an earlier recipient's hurt.
	# A still-living body, however, must retain this original controller ownership.
	return _owns_source() if _living(host) else true

func _abandon_reassigned_commit(generation: int) -> void:
	if generation == _generation and _state == "committing" and _living(host) and not _owns_source():
		# clear() only resets host metadata when our controller token still owns it.
		# It therefore retires the obsolete controller without cancelling a new cast.
		clear()

func _detonate() -> void:
	var generation := _generation
	if _detonated or _state != "windup" or not _active() or not _source_rejection().is_empty(): return
	if generation != _generation or not _active() or _state != "windup" or not _owns_source(): return
	var owner_token := game.get_instance_id()
	_state = "committing"
	_detonated = true
	_remaining = 0.0
	_damage = maxf(0.0, host.damage) if is_finite(host.damage) else 0.0
	var amount := _damage
	_impacts += 1
	_clear_host_attack()
	host.moving = false
	host.attack_pose = 1.0
	# Sample the recipients before the first synchronous hurt callback. A new
	# actor or same-place rebuilt model never becomes part of this old explosion.
	var recipients: Array[Dictionary] = []
	var seen: Dictionary = {}
	for selected: Dictionary in _target_rows():
		var key := int(selected.token)
		if not seen.has(key) and _legal_surface(_point, selected, BLAST_RADIUS):
			seen[key] = true
			recipients.append(selected)
	for selected: Dictionary in recipients:
		if not _commit_active(generation, owner_token):
			_abandon_reassigned_commit(generation)
			return
		if not _target_current(selected): continue
		# A source can be queued/freed by reflection during an earlier target's hurt.
		var source: BattleUnit = host if is_instance_valid(host) else null
		match String(selected.kind):
			"hero", "squad":
				var value: Variant = selected.get("unit")
				if not _living(value): continue
				_targets_hit += 1
				_hurt_unit(value as BattleUnit, amount, source)
			"tower":
				_targets_hit += 1
				game.call("damage_tower", int(selected.index), amount)
			"district":
				_targets_hit += 1
				selected.owner.call("damage", int(selected.index), amount)
			"barricade":
				_targets_hit += 1
				game.call("damage_gate_barricade", amount)
			"beacon":
				_targets_hit += 1
				game.call("apply_beacon_damage", amount, "爆裂体击碎灯塔 · 哨站失守")
	if not _commit_active(generation, owner_token):
		_abandon_reassigned_commit(generation)
		return
	_state = "detonated"
	_remaining = 0.0
	_clear_warning()
	# Self-expenditure goes through BattleUnit.defeated and the original wave
	# ledger. The monster itself is the source, so it cannot mint hero kill-chain.
	if _owns_source():
		var expenditure := (host.hp + maxf(0.0, host.shield) + 1.0) * maxf(1.0, (100.0 + host.armor) / 100.0)
		if is_finite(expenditure): host.hurt(expenditure, host)

func _hurt_unit(fighter: BattleUnit, amount: float, source: BattleUnit) -> void:
	var had_title := fighter.has_meta("delayed_enemy_hit_title")
	var previous: Variant = fighter.get_meta("delayed_enemy_hit_title", "")
	fighter.set_meta("delayed_enemy_hit_title", "爆裂体")
	fighter.hurt(amount, source)
	if not is_instance_valid(fighter): return
	if had_title: fighter.set_meta("delayed_enemy_hit_title", previous)
	else: fighter.remove_meta("delayed_enemy_hit_title")

func _terrain_ring(radius: float, width: float, lift: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mat := BattleVisuals.material(color)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warning_root.add_child(node)
	node.position = _point
	_resample_ring(node, radius, width, lift)
	return node

func _resample_ring(node: MeshInstance3D, radius: float, width: float, lift: float) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for step in WARNING_SEGMENTS:
		var angle := TAU * float(step) / float(WARNING_SEGMENTS)
		var radial := Vector2(cos(angle), sin(angle))
		for edge_radius in [maxf(0.02, radius - width), radius + width]:
			var offset := radial * float(edge_radius)
			var world_point := _point + Vector3(offset.x, 0.0, offset.y)
			vertices.append(Vector3(offset.x, _ground_height(world_point) + lift - _point.y, offset.y))
			normals.append(Vector3.UP)
		var next := ((step + 1) % WARNING_SEGMENTS) * 2
		var current := step * 2
		indices.append_array(PackedInt32Array([current, next, current + 1, current + 1, next, next + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	node.mesh = mesh

func _update_warning() -> void:
	var combat: Variant = game.get("combat") if is_instance_valid(game) else null
	var reduced := is_instance_valid(combat) and bool(combat.get("reduced_effects"))
	if is_instance_valid(_ring):
		(_ring.material_override as StandardMaterial3D).albedo_color = Color("bc825c") if reduced else Color("d98c59")
	if is_instance_valid(_progress_ring):
		var progress := 1.0 - clampf(_remaining / WINDUP_SECONDS, 0.0, 1.0)
		var radius := BLAST_RADIUS * maxf(0.10, progress)
		if not is_equal_approx(_progress_radius, radius):
			_progress_radius = radius
			_resample_ring(_progress_ring, radius, 0.035, 0.12)
		(_progress_ring.material_override as StandardMaterial3D).albedo_color = Color("946c53") if reduced else Color("c76c4e")

func _clear_warning() -> void:
	if is_instance_valid(_warning_root):
		_warning_root.visible = false
		_warning_root.queue_free()
	_warning_root = null
	_ring = null
	_progress_ring = null
	_progress_radius = -1.0

func _attach_prototype() -> void:
	if not is_instance_valid(host) or not is_instance_valid(host.visual): return
	_prototype_root = Node3D.new()
	_prototype_root.name = "BurstlingNativeMatteSacks"
	var flesh := BattleVisuals.material(Color("9d604c"))
	var strap := BattleVisuals.material(Color("504a42"))
	for side in [-1.0, 1.0]:
		var sac := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.34
		sphere.height = 0.68
		sphere.radial_segments = 12
		sphere.rings = 8
		sac.mesh = sphere
		sac.material_override = flesh
		_prototype_root.add_child(sac)
		sac.position = Vector3(side * 0.34, 1.0, 0.12)
		sac.scale = Vector3(0.9, 1.18, 1.22)
		BattleVisuals.box(_prototype_root, Vector3(side * 0.34, 1.0, 0.12), Vector3(0.10, 0.75, 0.11), strap)
	host.visual.add_child(_prototype_root)
