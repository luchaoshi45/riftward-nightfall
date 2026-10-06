class_name NightfallWarder
extends Node3D
## 有限护盾只在完成真实引导后发放；目标自己的 BattleUnit.tick 管理盾寿命。

const RANGE := 4.8
const MISSING_HEALTH := 12.0
const WINDUP_SECONDS := 1.0
const SHIELD_AMOUNT := 32.0
const SHIELD_SECONDS := 4.0
const CAST_INTERVAL := 6.0
const MAX_CASTS := 3
const HEIGHT_LIMIT := .9

var game: Node3D
var host: BattleUnit
var _state := "idle"
var _remaining := 0.0
var _cooldown := 0.0
var _target: WeakRef
var _generation := 0
var _normal_windup := .34
var _cancel_reason := ""
var _cancelled := 0
var _prototype_root: Node3D
var _shell_materials: Array[StandardMaterial3D] = []

func setup(owner_game: Node3D, owner_host: BattleUnit) -> void:
	clear()
	game = owner_game
	host = owner_host
	if get_parent() == null and is_instance_valid(game): game.add_child(self)
	_cancel_reason = ""
	_cancelled = 0
	if not _living(host): return
	_normal_windup = host.windup_duration
	var saved_cooldown := float(host.get_meta("warder_cooldown", 0.0))
	_cooldown = maxf(0.0, saved_cooldown) if is_finite(saved_cooldown) else 0.0
	host.title = "织壳者"
	host.set_meta("threat", "warder")
	host.set_meta("warder_active", _casts() < MAX_CASTS)
	_state = "exhausted" if _casts() >= MAX_CASTS else ("cooldown" if _cooldown > 0.0 else "idle")
	if not host.defeated.is_connected(_on_host_defeated): host.defeated.connect(_on_host_defeated)
	_attach_prototype()
	_update_prototype()

func advance(delta: float) -> bool:
	if not is_instance_valid(game):
		clear()
		return false
	var phase_name := String(game.get("phase"))
	if phase_name in ["paused", "draft"] or not is_finite(delta) or delta <= 0.0:
		return _state in ["windup", "committing"]
	if phase_name != "night":
		clear()
		return false
	if _state == "committing": return true
	var generation := _generation
	var source := host
	var owner := game
	if not _real_enemy(source):
		if _state == "windup": _cancel("source_dead" if not _living(source) else "source_roster")
		if is_instance_valid(source): source.set_meta("warder_active", false)
		return false
	_cooldown = maxf(0.0, _cooldown - delta)
	source.set_meta("warder_cooldown", _cooldown)
	if _casts() >= MAX_CASTS:
		if _state != "exhausted": _exhaust()
		return false
	source.set_meta("warder_active", true)
	var controlled := _controlled()
	if not _same_context(generation, source, owner): return false
	if controlled:
		if _state == "windup": _cancel("source_controlled")
		else: _cancel_reason = "source_controlled"
		_clear_host_attack()
		source.moving = false
		_update_prototype()
		return true
	if _state == "windup":
		var target := _current_target()
		var rejection := _cast_rejection(target)
		if not _same_context(generation, source, owner): return false
		if not rejection.is_empty():
			_cancel(rejection)
			return true
		_remaining = maxf(0.0, _remaining - delta)
		source.moving = false
		source.attack_queued = true
		source.attack_windup = _remaining
		source.face(target.position, delta)
		if _remaining <= 0.0: _commit()
		if _same_context(generation, source, owner): _update_prototype()
		return true
	# Ordinary queued melee remains owned by the root during these states.
	if _cooldown > 0.0:
		_state = "cooldown"
		_update_prototype()
		return false
	_state = "idle"
	var selected := _pick_target()
	if not _same_context(generation, source, owner): return false
	if not is_instance_valid(selected):
		_update_prototype()
		return false
	_begin(selected)
	return true

func revalidate_cast() -> void:
	# Towers apply their slow later in this same frame; this does not advance time.
	if not is_instance_valid(game) or String(game.get("phase")) != "night" or _state != "windup": return
	var generation := _generation
	var source := host
	var owner := game
	var rejection := _cast_rejection(_current_target())
	if not _same_context(generation, source, owner): return
	if _controlled(): rejection = "source_controlled"
	if not _same_context(generation, source, owner): return
	if not rejection.is_empty(): _cancel(rejection)

func snapshot() -> Dictionary:
	var source: BattleUnit = host if is_instance_valid(host) else null
	var target := _current_target()
	return {"phase": _state, "remaining": _remaining, "total": WINDUP_SECONDS,
		"progress": 1.0 - clampf(_remaining / WINDUP_SECONDS, 0.0, 1.0) if _state in ["windup", "committing"] else 0.0,
		"cooldown": _cooldown, "casts": _casts(), "max_casts": MAX_CASTS,
		"source": source, "target": target,
		"source_token": source.get_instance_id() if is_instance_valid(source) else -1,
		"target_token": target.get_instance_id() if is_instance_valid(target) else -1,
		"source_title": "织壳者", "position": source.position if is_instance_valid(source) else Vector3.ZERO,
		"cancel_reason": _cancel_reason, "cancelled": _cancelled,
		"range": RANGE, "shield_amount": SHIELD_AMOUNT, "shield_seconds": SHIELD_SECONDS}

func clear() -> void:
	_generation += 1
	if _state in ["windup", "committing"]: _clear_host_attack()
	if is_instance_valid(host):
		host.set_meta("warder_active", false)
		host.windup_duration = _normal_windup
		if host.defeated.is_connected(_on_host_defeated): host.defeated.disconnect(_on_host_defeated)
	if is_instance_valid(_prototype_root): _prototype_root.queue_free()
	_prototype_root = null
	_shell_materials.clear()
	_target = null
	host = null
	_state = "idle"
	_remaining = 0.0
	_cooldown = 0.0

func _exit_tree() -> void:
	clear()

func _living(value: Variant) -> bool:
	return is_instance_valid(value) and value is BattleUnit and not value.is_queued_for_deletion() and value.alive and value.hp > 0.0

func _real_enemy(value: Variant) -> bool:
	return _living(value) and value.kind == "monster" and value.team == 2 and is_instance_valid(game) and value in game.get("enemies")

func _same_context(generation: int, source: BattleUnit, owner: Node3D) -> bool:
	return generation == _generation and is_instance_valid(owner) and game == owner and is_instance_valid(source) and host == source \
		and String(owner.get("phase")) == "night" and _real_enemy(source)

func _casts() -> int:
	return maxi(0, int(host.get_meta("warder_casts", 0))) if is_instance_valid(host) else 0

func _controlled() -> bool:
	if not _living(host) or not is_instance_valid(game): return false
	var specializations: Variant = game.get("specializations")
	return specializations != null and float(specializations.movement_multiplier(host)) < .9999

func _current_target() -> BattleUnit:
	if _target == null: return null
	var value: Variant = _target.get_ref()
	return value as BattleUnit if is_instance_valid(value) and value is BattleUnit else null

func _distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))

func _cast_rejection(target: Variant) -> String:
	if not _real_enemy(host): return "source_dead" if not _living(host) else "source_roster"
	if _casts() >= MAX_CASTS: return "source_exhausted"
	var recipient_rejection := _recipient_rejection(target)
	if not recipient_rejection.is_empty(): return recipient_rejection
	if not host.position.is_finite() or not target.position.is_finite(): return "target_position"
	if _distance(host.position, target.position) > RANGE + .000001: return "target_range"
	var generation := _generation
	var source := host
	var owner := game
	var first := source.position
	var second: Vector3 = target.position
	var first_ground := float(owner.call("outpost_height", first))
	if not _same_context(generation, source, owner): return "context_changed"
	var second_ground := float(owner.call("outpost_height", second))
	if not _same_context(generation, source, owner): return "context_changed"
	var first_offset := first.y - first_ground
	var second_offset := second.y - second_ground
	if not is_finite(first_offset) or not is_finite(second_offset) or absf(first_offset) > HEIGHT_LIMIT + .000001 or absf(second_offset) > HEIGHT_LIMIT + .000001 or absf(first_offset - second_offset) > HEIGHT_LIMIT + .000001: return "target_height"
	var line_clear := bool(owner.call("can_attack_line", first, second))
	if not _same_context(generation, source, owner): return "context_changed"
	if not line_clear: return "line_blocked"
	var traversable := bool(owner.call("can_traverse", first, second))
	if not _same_context(generation, source, owner): return "context_changed"
	if not traversable: return "path_blocked"
	# A synchronous world callback can retire or move the recipient without
	# rebuilding this controller. Never commit the earlier identity/position.
	if not _living(target): return "target_dead"
	if source.position != first or target.position != second: return "target_moved"
	return _recipient_rejection(target)

func _recipient_rejection(target: Variant) -> String:
	if not _real_enemy(target): return "target_dead" if not _living(target) else "target_roster"
	if target == host or String(target.get_meta("threat", "")) == "warder" or bool(target.get_meta("siege_boss", false)): return "target_excluded"
	if not is_finite(target.hp) or not is_finite(target.max_hp) or target.max_hp <= 0.0 or target.max_hp - target.hp < MISSING_HEALTH: return "target_health"
	if not is_finite(target.shield) or target.shield > 0.0: return "target_shielded"
	return ""

func _pick_target() -> BattleUnit:
	var selected: BattleUnit
	var lowest := INF
	var nearest := INF
	var generation := _generation
	var source := host
	var owner := game
	var candidates: Array = owner.get("enemies").duplicate()
	for candidate: Variant in candidates:
		var rejection := _cast_rejection(candidate)
		if not _same_context(generation, source, owner): return null
		if not rejection.is_empty(): continue
		var enemy := candidate as BattleUnit
		var ratio := enemy.hp / enemy.max_hp
		var distance := _distance(source.position, enemy.position)
		if ratio < lowest or (is_equal_approx(ratio, lowest) and distance < nearest):
			selected = enemy
			lowest = ratio
			nearest = distance
	return selected

func _begin(target: BattleUnit) -> void:
	_target = weakref(target)
	_state = "windup"
	_remaining = WINDUP_SECONDS
	_cancel_reason = ""
	host.moving = false
	host.windup_duration = WINDUP_SECONDS
	host.attack_queued = true
	host.attack_windup = _remaining
	host.set_meta("attack_target_kind", "")
	host.set_meta("attack_target_index", -1)
	host.set_meta("attack_target_token", -1)
	_update_prototype()

func _commit() -> void:
	var generation := _generation
	var source := host
	var owner := game
	var target := _current_target()
	var rejection := _cast_rejection(target)
	if not _same_context(generation, source, owner): return
	if _controlled(): rejection = "source_controlled"
	if not _same_context(generation, source, owner): return
	if rejection.is_empty(): rejection = _recipient_rejection(target)
	if not rejection.is_empty():
		_cancel(rejection)
		return
	_state = "committing"
	_remaining = 0.0
	_clear_host_attack()
	# Commit the lifetime debit before the actual shield; no controller rebuild
	# can replenish it, and another source sees the shield at its own recheck.
	source.set_meta("warder_casts", _casts() + 1)
	_cooldown = CAST_INTERVAL
	source.set_meta("warder_cooldown", _cooldown)
	target.shield = SHIELD_AMOUNT
	target.shield_time = SHIELD_SECONDS
	target.set_meta("warder_shield", true)
	if not _same_context(generation, source, owner): return
	source.attack_pose = 1.0
	_target = null
	_cancel_reason = ""
	if _casts() >= MAX_CASTS: _exhaust()
	else: _state = "cooldown"
	_update_prototype()

func _cancel(reason: String) -> void:
	_state = "cooldown" if _cooldown > 0.0 else "idle"
	_remaining = 0.0
	_target = null
	_cancel_reason = reason
	_cancelled += 1
	_clear_host_attack()
	_update_prototype()

func _exhaust() -> void:
	if _state in ["windup", "committing"]: _clear_host_attack()
	_state = "exhausted"
	_remaining = 0.0
	_target = null
	if is_instance_valid(host): host.set_meta("warder_active", false)
	_update_prototype()

func _clear_host_attack() -> void:
	if not is_instance_valid(host): return
	host.attack_queued = false
	host.attack_windup = 0.0
	host.windup_duration = _normal_windup
	host.set_meta("attack_target_kind", "")
	host.set_meta("attack_target_index", -1)
	host.set_meta("attack_target_token", -1)

func _on_host_defeated(unit: BattleUnit, _source: BattleUnit) -> void:
	if not is_instance_valid(host) or unit != host: return
	if _state == "windup": _cancel("source_dead")
	host.set_meta("warder_active", false)

func _attach_prototype() -> void:
	if not is_instance_valid(host.visual): return
	_prototype_root = Node3D.new()
	_prototype_root.name = "WarderNativeShellCrest"
	host.visual.add_child(_prototype_root)
	for index in MAX_CASTS:
		var shell := MeshInstance3D.new()
		shell.name = "WarderBudgetShell%d" % (index + 1)
		var mesh := PrismMesh.new()
		mesh.size = Vector3(.24, .46, .24)
		shell.mesh = mesh
		var material := BattleVisuals.material(Color("b5c4a6"), .025)
		shell.material_override = material
		_shell_materials.append(material)
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_prototype_root.add_child(shell)
		var side := float(index - 1)
		shell.position = Vector3(side * .28, 1.28 + (.08 if index == 1 else 0.0), .18)
		shell.rotation.z = -side * .22

func _update_prototype() -> void:
	if _shell_materials.is_empty(): return
	var combat: Variant = game.get("combat") if is_instance_valid(game) else null
	var reduced := combat != null and bool(combat.reduced_effects)
	var available := maxi(0, MAX_CASTS - _casts())
	for index in _shell_materials.size():
		var material := _shell_materials[index]
		material.albedo_color = Color("b5c4a6") if index < available else Color("595e54")
		material.emission_energy_multiplier = (0.045 if reduced else .12) if index < available and _state == "windup" else (.025 if index < available else 0.0)
