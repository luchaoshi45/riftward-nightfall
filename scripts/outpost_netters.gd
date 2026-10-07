extends Node3D
## Single-target net casts on real squad members. BattleUnit.tick owns the
## windup/cooldown; the shared control ledger owns every landed net's lifetime.

const MIN_RANGE := 2.5
const MAX_RANGE := 9.0
const WINDUP := .6
const COOLDOWN := 4.0
const HEIGHT_LIMIT := .9

var game: Node3D
var roster: Node3D
var _units: Dictionary = {}
var _effects: Dictionary = {}
var _epoch := 0
var _throws := 0
var _hits := 0
var _nets := 0
var _cancellations := 0
var _has_roster := false
var _has_controls := false
var _has_quitting := false
var _has_restart_pending := false
var _has_shutting_down := false

func setup(controller: Node3D, squad_roster: Node3D) -> void:
	clear()
	game = controller
	roster = squad_roster
	_has_roster = false
	_has_controls = false
	_has_quitting = false
	_has_restart_pending = false
	_has_shutting_down = false
	if not is_instance_valid(game): return
	for property: Dictionary in game.get_property_list():
		match String(property.name):
			"squads": _has_roster = true
			"specializations": _has_controls = true
			"quitting": _has_quitting = true
			"restart_pending": _has_restart_pending = true
			"shutting_down": _has_shutting_down = true

func _living(value: Variant) -> bool:
	return is_instance_valid(value) and value is BattleUnit and not value.is_queued_for_deletion() \
		and value.alive and value.hp > 0.0

func _owns_roster() -> bool:
	return is_instance_valid(game) and not game.is_queued_for_deletion() \
		and is_instance_valid(roster) and not roster.is_queued_for_deletion() \
		and (not _has_roster or game.get("squads") == roster)

func _active() -> bool:
	if not _owns_roster() or String(game.get("phase")) not in ["day", "night"]: return false
	if _has_quitting and bool(game.get("quitting")): return false
	if _has_restart_pending and bool(game.get("restart_pending")): return false
	if _has_shutting_down and bool(game.get("shutting_down")): return false
	return true

func real_enemy(value: Variant) -> bool:
	return _living(value) and value.kind == "monster" and value.team == 2 \
		and _owns_roster() and value in game.get("enemies")

func register_with_roster(source: BattleUnit, squad_id: int, slot: int) -> void:
	if not is_instance_valid(source) or not _owns_roster(): return
	var rows: Array = roster.get("squads")
	if squad_id < 0 or squad_id >= rows.size() or slot < 0 or slot >= 3: return
	var squad: Dictionary = rows[squad_id]
	if int(squad.get("id", -1)) != squad_id or String(squad.get("kind", "")) != "netter": return
	_units[source.get_instance_id()] = {"unit": weakref(source), "identity": squad,
		"squad_id": squad_id, "slot": slot, "revision": 0, "cast": {}, "cancel_reason": ""}

func real_source(value: Variant) -> bool:
	if not _living(value) or value.kind != "minion" or value.team != 0 or not _owns_roster(): return false
	var state: Dictionary = _units.get(value.get_instance_id(), {})
	if state.is_empty() or not state.get("unit") is WeakRef or state.unit.get_ref() != value: return false
	var rows: Array = roster.get("squads")
	var id := int(state.get("squad_id", -1))
	if id < 0 or id >= rows.size() or not is_same(rows[id], state.identity): return false
	var squad: Dictionary = rows[id]
	var slot := int(state.get("slot", -1))
	return String(squad.get("kind", "")) == "netter" and slot >= 0 \
		and slot < squad.members.size() and squad.members[slot] == value

func distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z))

func _ground_height(point: Vector3) -> float:
	return float(game.call("outpost_height", point)) if game.has_method("outpost_height") else point.y

func ground_compatible(first: Vector3, second: Vector3) -> bool:
	if not first.is_finite() or not second.is_finite() or not is_instance_valid(game): return false
	var first_height := _ground_height(first)
	var second_height := _ground_height(second)
	var first_offset := first.y - first_height
	var second_offset := second.y - second_height
	return is_finite(first_height) and is_finite(second_height) \
		and absf(first_offset) <= HEIGHT_LIMIT + .000001 \
		and absf(second_offset) <= HEIGHT_LIMIT + .000001 \
		and absf(first_offset - second_offset) <= HEIGHT_LIMIT + .000001

func _line(from: Vector3, to: Vector3) -> bool:
	return bool(game.call("can_attack_line", from, to)) if game.has_method("can_attack_line") \
		else bool(roster.call("_attack_line", from, to))

func legal_target(source: BattleUnit, target: Variant) -> bool:
	if not real_source(source) or not real_enemy(target): return false
	var separation := distance(source.position, target.position)
	return separation >= MIN_RANGE and separation <= MAX_RANGE \
		and ground_compatible(source.position, target.position) and _line(source.position, target.position)

func _controls() -> Variant:
	var control: Variant = game.get("specializations") if _has_controls and _owns_roster() else null
	return control if is_instance_valid(control) and control.has_method("apply_net") \
		and control.has_method("net_remaining") else null

func net_remaining(enemy: Variant) -> float:
	if not real_enemy(enemy): return 0.0
	var control: Variant = _controls()
	if not is_instance_valid(control): return 0.0
	var remaining := float(control.call("net_remaining", enemy))
	return maxf(0.0, remaining) if is_finite(remaining) else 0.0

func _reserved(target: BattleUnit, source: BattleUnit) -> bool:
	for state: Dictionary in _units.values():
		var other := (state.unit as WeakRef).get_ref() as BattleUnit
		if other == source or not real_source(other): continue
		var cast: Dictionary = state.get("cast", {})
		if cast.is_empty() or not cast.get("target_ref") is WeakRef: continue
		if (cast.target_ref as WeakRef).get_ref() == target and _cast_current(other, target, cast): return true
	return false

func pick_target(source: BattleUnit, preferred: BattleUnit = null) -> BattleUnit:
	if not real_source(source): return null
	# Explicit player focus wins even when that enemy already carries a net.
	if legal_target(source, preferred): return preferred
	var chosen: BattleUnit
	var best_controlled := 2
	var best := INF
	for value: Variant in game.get("enemies"):
		if not legal_target(source, value): continue
		var target := value as BattleUnit
		# Reserve a real in-progress cast as well as a landed net, so three
		# members deciding in one frame spread control across legal enemies.
		var controlled := 1 if net_remaining(target) > 0.0 or _reserved(target, source) else 0
		var separation := distance(source.position, target.position)
		if controlled < best_controlled or (controlled == best_controlled and \
			(separation < best or (is_equal_approx(separation, best) and \
			(is_instance_valid(chosen) and target.get_instance_id() < chosen.get_instance_id())))):
			best_controlled = controlled
			best = separation
			chosen = target
	return chosen

func casting(source: BattleUnit) -> bool:
	if not is_instance_valid(source): return false
	return not (_units.get(source.get_instance_id(), {}).get("cast", {}) as Dictionary).is_empty()

func begin(source: BattleUnit, target: BattleUnit) -> bool:
	if not _active() or not legal_target(source, target) or not is_instance_valid(_controls()): return false
	if source.attack_timer > 0.0 or source.moving or casting(source): return false
	var state: Dictionary = _units[source.get_instance_id()]
	var cast := {"phase": "windup", "epoch": _epoch, "remaining": WINDUP, "total": WINDUP,
		"source_ref": weakref(source), "target_ref": weakref(target),
		"source_token": source.get_instance_id(), "target_token": target.get_instance_id(),
		"source_position": source.position, "order": String(state.identity.order),
		"revision": int(state.revision), "visual": null}
	state.cast = cast
	state.cancel_reason = ""
	source.target = target
	source.attack_queued = true
	source.attack_windup = WINDUP
	source.face(target.position, .05)
	_create_warning(cast, target)
	if not _cast_current(source, target, cast) or not is_same(state.get("cast", {}), cast):
		_free_visual(cast)
		return false
	_update_warning(cast, target)
	return true

func _cast_current(source: BattleUnit, target: BattleUnit, cast: Dictionary) -> bool:
	if int(cast.get("epoch", -1)) != _epoch or not _active() or not legal_target(source, target): return false
	var state: Dictionary = _units.get(source.get_instance_id(), {})
	return not state.is_empty() and String(state.identity.order) == String(cast.order) \
		and int(state.revision) == int(cast.revision) and not source.moving \
		and source.position.distance_to(cast.source_position) <= .01

func advance_unit(source: BattleUnit, delta: float) -> void:
	if not _active() or not is_finite(delta) or delta <= 0.0 or not is_instance_valid(source): return
	var state: Dictionary = _units.get(source.get_instance_id(), {})
	var cast: Dictionary = state.get("cast", {})
	if cast.is_empty(): return
	var target := (cast.target_ref as WeakRef).get_ref() as BattleUnit
	if not _cast_current(source, target, cast) or not source.attack_queued or source.target != target:
		cancel(source, "target_invalid")
		return
	cast.remaining = source.attack_windup
	source.face(target.position, delta)
	_update_warning(cast, target)
	if source.attack_windup > 0.0: return
	# Retire before hurt: synchronous death/damage callbacks cannot submit this
	# cast twice, or attach its control to a replacement unit or a new run.
	state.cast = {}
	source.target = null
	source.attack_queued = false
	source.attack_windup = 0.0
	source.attack_timer = COOLDOWN
	source.attack_pose = 1.0
	_free_visual(cast)
	var generation := _epoch
	var damage := maxf(0.0, source.damage) if is_finite(source.damage) else 0.0
	_throws += 1
	_hits += 1
	target.hurt(damage, source)
	if generation != _epoch or not _cast_current(source, target, cast): return
	var control: Variant = _controls()
	if not is_instance_valid(control): return
	var applied := bool(control.call("apply_net", target))
	if generation != _epoch or not _cast_current(source, target, cast) or not applied: return
	_nets += 1
	_ensure_effect(target)

func cancel(source: BattleUnit, reason: String = "order_changed") -> void:
	if not is_instance_valid(source): return
	var state: Dictionary = _units.get(source.get_instance_id(), {})
	if state.is_empty(): return
	state.revision = int(state.revision) + 1
	var cast: Dictionary = state.get("cast", {})
	if not cast.is_empty():
		_cancellations += 1
		_free_visual(cast)
		state.cast = {}
	state.cancel_reason = reason
	source.target = null
	source.attack_queued = false
	source.attack_windup = 0.0

func unregister(source: BattleUnit) -> void:
	if not is_instance_valid(source): return
	cancel(source, "source_dead")
	_units.erase(source.get_instance_id())
	# A landed net belongs to its real target, and survives its thrower's death.

func clear_pending() -> void:
	_epoch += 1
	for state: Dictionary in _units.values():
		var source := (state.unit as WeakRef).get_ref() as BattleUnit
		if is_instance_valid(source): cancel(source, "phase_changed")
		else: _free_visual(state.get("cast", {}))
	for effect: Dictionary in _effects.values(): _free_visual(effect)
	_effects.clear()

func clear() -> void:
	clear_pending()
	_units.clear()
	_throws = 0
	_hits = 0
	_nets = 0
	_cancellations = 0

func advance(_delta: float) -> void:
	if not _active(): return
	for id in _units.keys():
		var state: Dictionary = _units[id]
		var source := (state.unit as WeakRef).get_ref() as BattleUnit
		if real_source(source): continue
		if is_instance_valid(source): cancel(source, "source_invalid")
		else: _free_visual(state.get("cast", {}))
		_units.erase(id)
	for id in _effects.keys():
		var effect: Dictionary = _effects[id]
		var target := (effect.unit as WeakRef).get_ref() as BattleUnit
		var remaining := net_remaining(target)
		if remaining <= 0.0:
			_free_visual(effect)
			_effects.erase(id)
			continue
		_update_effect(effect, target, remaining)

func _mesh_material(alpha: float) -> StandardMaterial3D:
	var material := BattleVisuals.material(Color("8ecddd", alpha), .12)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func _net_geometry(root: Node3D, warning: bool) -> void:
	var material := _mesh_material(.16 if warning else .58)
	var ring := BattleVisuals.ring(root, Vector3(0, .065, 0), .65, Color("8ecddd"), .028)
	ring.name = "NetRing"
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for angle in [-PI / 4.0, PI / 4.0]:
		var line := BattleVisuals.box(root, Vector3(0, .08, 0), Vector3(1.12, .025, .025), material)
		line.name = "NetCross"
		line.rotation.y = angle
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _create_warning(cast: Dictionary, target: BattleUnit) -> void:
	var root := Node3D.new()
	root.name = "NetterCastWarning"
	cast.visual = root
	target.add_child(root)
	if root.is_queued_for_deletion() or not real_enemy(target): return
	_net_geometry(root, true)

func _update_warning(cast: Dictionary, target: BattleUnit) -> void:
	var root := cast.get("visual") as Node3D
	if not is_instance_valid(root) or not real_enemy(target): return
	root.position = Vector3.ZERO
	var ring := root.get_node_or_null("NetRing") as MeshInstance3D
	if is_instance_valid(ring):
		var material := ring.material_override as StandardMaterial3D
		material.albedo_color.a = .12 + .18 * (1.0 - clampf(float(cast.remaining) / WINDUP, 0.0, 1.0))

func _ensure_effect(target: BattleUnit) -> void:
	if not _active() or not real_enemy(target) or net_remaining(target) <= 0.0: return
	var id := target.get_instance_id()
	var effect: Dictionary = _effects.get(id, {})
	if not effect.is_empty() and (effect.unit as WeakRef).get_ref() == target:
		_update_effect(effect, target, net_remaining(target))
		return
	var root := Node3D.new()
	root.name = "NetterLandedNet"
	effect = {"unit": weakref(target), "visual": root}
	_effects[id] = effect
	# Parent to the real target: enemy movement occurs later than squad
	# advancement, so copying positions here would leave the net one frame behind.
	target.add_child(root)
	if root.is_queued_for_deletion() or not _active() or not real_enemy(target) \
		or not is_same(_effects.get(id, {}), effect):
		_free_visual(effect)
		return
	_net_geometry(root, false)
	_update_effect(effect, target, net_remaining(target))

func _update_effect(effect: Dictionary, target: BattleUnit, remaining: float) -> void:
	var root := effect.get("visual") as Node3D
	if not is_instance_valid(root) or not real_enemy(target): return
	root.position = Vector3.ZERO
	var ring := root.get_node_or_null("NetRing") as MeshInstance3D
	if is_instance_valid(ring):
		var material := ring.material_override as StandardMaterial3D
		# The ledger is the only clock: visual fade never expires control early.
		material.albedo_color.a = .58 * clampf(remaining / .35, 0.0, 1.0)

func _free_visual(value: Dictionary) -> void:
	if value.is_empty(): return
	# A target owns its warning/net children and may already have freed them.
	# Validate the raw Variant before casting a potentially retired object.
	var visual: Variant = value.get("visual")
	if is_instance_valid(visual) and visual is Node3D:
		var root := visual as Node3D
		root.visible = false
		root.queue_free()
	value.visual = null

func snapshot() -> Dictionary:
	var rows: Array[Dictionary] = []
	var casts := 0
	for state: Dictionary in _units.values():
		var source := (state.unit as WeakRef).get_ref() as BattleUnit
		if not real_source(source): continue
		var cast: Dictionary = state.get("cast", {})
		if not cast.is_empty(): casts += 1
		var target := (cast.target_ref as WeakRef).get_ref() as BattleUnit if cast.get("target_ref") is WeakRef else null
		rows.append({"unit": source, "source_token": source.get_instance_id(),
			"squad_id": int(state.squad_id), "slot": int(state.slot),
			"phase": "windup" if not cast.is_empty() else ("cooldown" if source.attack_timer > 0.0 else "idle"),
			"remaining": source.attack_windup if not cast.is_empty() else 0.0,
			"total": WINDUP, "cooldown": source.attack_timer,
			"target": target if real_enemy(target) else null,
			"target_token": target.get_instance_id() if real_enemy(target) else -1,
			"cancel_reason": String(state.get("cancel_reason", ""))})
	var effects: Array[Dictionary] = []
	for effect: Dictionary in _effects.values():
		var target := (effect.unit as WeakRef).get_ref() as BattleUnit
		var remaining := net_remaining(target)
		if remaining <= 0.0: continue
		effects.append({"target": target, "target_token": target.get_instance_id(), "remaining": remaining})
	return {"alive": rows.size(), "casting": casts, "throws": _throws, "hits": _hits,
		"nets": _nets, "cancellations": _cancellations, "units": rows, "effects": effects}

func _exit_tree() -> void:
	clear()
