extends Node3D
## Finite melee pursuit. BattleUnit.tick alone advances preparation and cooldown.
const LEASH := 8.0
const HEIGHT_LIMIT := .9
const BONUS := 18.0
const STUCK_LIMIT := 1.0

var game: Node3D
var roster: Node3D
var _units: Dictionary = {}
var _epoch := 0
var _hits := 0
var _cancellations := 0

func setup(controller: Node3D, squad_roster: Node3D) -> void:
	clear()
	game = controller
	roster = squad_roster

func register(source: BattleUnit, squad_id: int, slot: int) -> void:
	_units[source.get_instance_id()] = {"unit": weakref(source), "squad_id": squad_id,
		"slot": slot, "phase": "idle", "anchor": source.position, "target": null,
		"stuck": 0.0, "blocked": {}, "hits": 0, "cancel_reason": "", "encounter": false}

func _living(value: Variant) -> bool:
	return is_instance_valid(value) and value is BattleUnit and not value.is_queued_for_deletion() and value.alive and value.hp > 0.0

func real_enemy(value: Variant) -> bool:
	return _living(value) and value.kind == "monster" and value.team == 2 and is_instance_valid(game) and value in game.get("enemies")

func real_source(source: Variant) -> bool:
	if not _living(source) or not is_instance_valid(roster): return false
	var state: Dictionary = _units.get(source.get_instance_id(), {})
	if state.is_empty() or (state.unit as WeakRef).get_ref() != source: return false
	for squad: Dictionary in roster.get("squads"):
		if String(squad.kind) != "hunter" or int(squad.id) != int(state.squad_id): continue
		var slot := int(state.slot)
		return slot >= 0 and slot < squad.members.size() and squad.members[slot] == source
	return false

func distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))

func _active() -> bool:
	return is_instance_valid(game) and String(game.get("phase")) in ["day", "night"]

func _grounded(first: Vector3, second: Vector3) -> bool:
	if not first.is_finite() or not second.is_finite(): return false
	var first_offset := first.y - float(roster.call("_ground_height", first))
	var second_offset := second.y - float(roster.call("_ground_height", second))
	return is_finite(first_offset) and is_finite(second_offset) and absf(first_offset) <= HEIGHT_LIMIT + .000001 \
		and absf(second_offset) <= HEIGHT_LIMIT + .000001 and absf(first_offset - second_offset) <= HEIGHT_LIMIT + .000001

func _reachable(source: BattleUnit, point: Vector3) -> bool:
	if not point.is_finite(): return false
	if game.has_method("outpost_walkable") and not bool(game.call("outpost_walkable", point)): return false
	if bool(roster.call("_traversable", source.position, point)): return true
	if game.has_method("enemy_target_reachable"):
		return bool(game.call("enemy_target_reachable", source.position, {"kind": "squad", "position": point}))
	return false

func legal_target(source: BattleUnit, target: Variant, anchor: Vector3) -> bool:
	return real_source(source) and real_enemy(target) and distance(anchor, target.position) <= LEASH + .000001 \
		and _grounded(source.position, target.position) and _reachable(source, target.position)

func _contact(source: BattleUnit, target: Variant) -> bool:
	return real_enemy(target) and distance(source.position, target.position) <= source.attack_range + .000001 \
		and _grounded(source.position, target.position) and bool(roster.call("_attack_line", source.position, target.position)) \
		and bool(roster.call("_traversable", source.position, target.position))

func bonus_target(target: Variant) -> bool:
	if not real_enemy(target): return false
	var role := String(target.get_meta("threat", ""))
	return role in ["runner", "light_eater", "lobber", "burstling"] or (role == "summoner" and bool(target.get_meta("summoner_active", false))) \
		or (role == "warder" and bool(target.get_meta("warder_active", false)))

func _priority(target: BattleUnit) -> int:
	var role := String(target.get_meta("threat", ""))
	# Idle burstlings remain specialist victims; a committed ground blast is
	# the most urgent target inside the same fixed, reachable pursuit area.
	if role == "burstling": return -1 if bool(target.get_meta("burstling_winding", false)) else 0
	if role == "summoner" and bool(target.get_meta("summoner_active", false)): return 0
	if role == "warder" and bool(target.get_meta("warder_active", false)): return 1
	return int({"lobber": 2, "light_eater": 3, "runner": 4, "breaker": 6, "sapper": 6, "shellguard": 6}.get(role, 5))

func _block_signature() -> int:
	return hash(game.get("construction_blocks")) if bool(roster.get("_has_construction_blocks")) else 0

func _blocked(state: Dictionary, target: BattleUnit) -> bool:
	var row: Dictionary = (state.blocked as Dictionary).get(target.get_instance_id(), {})
	# A fleeing victim must return to its original encounter area before it
	# can lure this march again. Moving farther cannot refresh the old leash.
	if row.has("leash_anchor"):
		return distance(row.leash_anchor, target.position) > LEASH + .000001
	return not row.is_empty() and distance(row.point, target.position) <= .8 and int(row.signature) == _block_signature()

func pick_target(source: BattleUnit, anchor: Vector3) -> BattleUnit:
	if not real_source(source): return null
	var state: Dictionary = _units[source.get_instance_id()]
	var focus: Variant = game.get("focus_target")
	if float(game.get("focus_time")) > 0.0 and legal_target(source, focus, anchor) and not _blocked(state, focus): return focus as BattleUnit
	var selected: BattleUnit
	var priority := 999
	var nearest := INF
	for value: Variant in game.get("enemies"):
		if not legal_target(source, value, anchor): continue
		var enemy := value as BattleUnit
		if _blocked(state, enemy): continue
		var rank := _priority(enemy)
		var separation := distance(source.position, enemy.position)
		if rank < priority or (rank == priority and separation < nearest):
			selected = enemy; priority = rank; nearest = separation
	return selected

func cancel(source: BattleUnit, reason: String = "order_changed") -> void:
	if not is_instance_valid(source): return
	var state: Dictionary = _units.get(source.get_instance_id(), {})
	if state.is_empty(): return
	if source.attack_queued: _cancellations += 1
	state.phase = "idle"; state.target = null; state.stuck = 0.0
	state.encounter = false
	state.cancel_reason = reason
	source.target = null; source.attack_queued = false; source.attack_windup = 0.0
	source.path.clear(); source.path_timer = 0.0
	# An order never refunds elapsed attack cooldown or advances the unit clock.
	_epoch += 1

func on_order(source: BattleUnit) -> void:
	cancel(source)
	var state: Dictionary = _units.get(source.get_instance_id(), {})
	if not state.is_empty(): state.blocked = {}

func unregister(source: BattleUnit) -> void:
	if not is_instance_valid(source): return
	cancel(source, "source_dead")
	_units.erase(source.get_instance_id())

func prepare_squad(squad: Dictionary) -> bool:
	# A manual attack owns the original command point; target motion cannot drag it.
	if String(squad.order) != "attack": return false
	var target: Variant = (squad.attack_target as WeakRef).get_ref() if squad.attack_target is WeakRef else null
	var anchor: Vector3 = squad.get("hunter_attack_anchor", squad.destination)
	if real_enemy(target) and distance(anchor, target.position) <= LEASH + .000001: return false
	roster.call("_set_squad_order", squad, "guard")
	squad.destination = roster.call("_resolve_destination", anchor)
	return true # Return this frame; do not substitute another victim immediately.

func _return(source: BattleUnit, state: Dictionary, anchor: Vector3, delta: float) -> void:
	source.target = null
	var before := source.position
	roster.call("_move_member", source, anchor, delta)
	if distance(source.position, anchor) <= .16:
		state.phase = "idle"; source.moving = false
	elif distance(before, source.position) <= .000001:
		state.phase = "blocked"; source.moving = false
	else: state.phase = "returning"

func advance_member(squad: Dictionary, source: BattleUnit, slot: int, delta: float, recovering: bool = false) -> void:
	if not _active() or not real_source(source): return
	var state: Dictionary = _units[source.get_instance_id()]
	var order := String(squad.order)
	var march := order in ["attack_move", "escort"]
	var station: Vector3 = roster.call("_station", squad, slot, order)
	var anchor: Vector3 = squad.get("hunter_attack_anchor", squad.destination) if order == "attack" else station
	if march:
		if not bool(state.encounter):
			var encountered: BattleUnit = pick_target(source, source.position)
			if not real_enemy(encountered):
				state.anchor = source.position
				_return(source, state, station, delta)
				if source.moving: state.phase = "command_move"
				return
			state.encounter = true
			state.anchor = source.position
			state.target = weakref(encountered)
		anchor = state.anchor
	else:
		state.anchor = anchor
	if order in ["move", "recall"]:
		if source.attack_queued or state.target != null: cancel(source, "moving")
		state.anchor = station
		_return(source, state, station, delta)
		if source.moving: state.phase = "command_move"
		return
	if recovering:
		_return(source, state, station, delta)
		return
	var target: Variant = (state.target as WeakRef).get_ref() if state.target is WeakRef else null
	if march:
		if not legal_target(source, target, anchor):
			if real_enemy(target) and distance(anchor, target.position) > LEASH + .000001:
				(state.blocked as Dictionary)[target.get_instance_id()] = {"leash_anchor": anchor}
			cancel(source, "target_invalid")
			_return(source, state, station, delta)
			if source.moving: state.phase = "command_move"
			return
		elif not source.attack_queued:
			# Reuse the normal focus and threat priorities inside this encounter's
			# fixed leash. A new victim never moves the encounter anchor.
			target = pick_target(source, anchor)
	elif order == "attack":
		target = (squad.attack_target as WeakRef).get_ref() if squad.attack_target is WeakRef else null
		if not legal_target(source, target, anchor) or (real_enemy(target) and _blocked(state, target)):
			cancel(source, "target_unreachable")
			_return(source, state, station, delta)
			return
	elif target != null and not legal_target(source, target, anchor):
		cancel(source, "target_invalid")
		_return(source, state, station, delta)
		return
	elif target == null:
		target = pick_target(source, anchor)
	elif not source.attack_queued and not march:
		target = pick_target(source, anchor)
	if not real_enemy(target):
		_return(source, state, station, delta)
		return
	state.target = weakref(target)
	if source.attack_queued and (source.target != target or not _contact(source, target)):
		if march:
			# Losing contact cancels only this preparation, keeping the finite
			# encounter anchor while walking back into actual melee reach.
			_cancellations += 1
			source.target = null; source.attack_queued = false; source.attack_windup = 0.0
			source.path.clear(); source.path_timer = 0.0
			state.cancel_reason = "contact_lost"
		else:
			cancel(source, "contact_lost")
			_return(source, state, station, delta)
			return
	if source.attack_queued:
		source.moving = false; source.face(target.position, delta)
		state.phase = "windup"
		if source.attack_windup > 0.0: return
		var generation := _epoch
		var amount: float = source.damage + (BONUS if bonus_target(target) else 0.0)
		source.attack_queued = false; source.target = null
		source.attack_timer = source.attack_interval; source.attack_pose = 1.0
		state.phase = "idle"
		# The synchronous hurt callback may clear/setup the entire game or roster.
		target.hurt(amount, source)
		if generation != _epoch or not _active() or not real_source(source): return
		_hits += 1; state.hits = int(state.hits) + 1
		return
	if not _contact(source, target):
		var before := source.position
		roster.call("_move_member", source, target.position, delta)
		source.target = target
		state.phase = "chasing"
		state.stuck = float(state.stuck) + delta if distance(before, source.position) <= .000001 else 0.0
		if float(state.stuck) >= STUCK_LIMIT:
			(state.blocked as Dictionary)[target.get_instance_id()] = {"point": target.position, "signature": _block_signature()}
			cancel(source, "path_blocked")
			_return(source, state, station, delta)
		return
	source.moving = false; source.path.clear(); state.stuck = 0.0
	if source.attack_timer > 0.0:
		state.phase = "cooldown"
		return
	source.target = target; source.attack_queued = true; source.attack_windup = source.windup_duration
	source.face(target.position, delta); state.phase = "windup"

func clear_pending() -> void:
	_epoch += 1
	for state: Dictionary in _units.values():
		var source := (state.unit as WeakRef).get_ref() as BattleUnit
		if is_instance_valid(source): on_order(source)

func clear() -> void:
	clear_pending()
	_units.clear(); _hits = 0; _cancellations = 0

func snapshot() -> Dictionary:
	var units: Array[Dictionary] = []
	var rows: Array[Dictionary] = []
	var chasing := 0
	var casting := 0
	for state: Dictionary in _units.values():
		var source := (state.unit as WeakRef).get_ref() as BattleUnit
		if not real_source(source): continue
		var target: Variant = (state.target as WeakRef).get_ref() if state.target is WeakRef else null
		var row := {"unit": source, "source_token": source.get_instance_id(), "squad_id": state.squad_id, "slot": state.slot,
			"phase": String(state.phase), "anchor": state.anchor, "encounter": bool(state.get("encounter", false)), "target_token": target.get_instance_id() if real_enemy(target) else -1,
			"remaining": source.attack_windup if source.attack_queued else 0.0, "cooldown": source.attack_timer,
			"hits": int(state.hits), "cancel_reason": String(state.cancel_reason)}
		units.append(row)
		if String(state.phase) == "chasing": chasing += 1
		if source.attack_queued: casting += 1
	if is_instance_valid(roster):
		for squad: Dictionary in roster.get("squads"):
			if String(squad.kind) != "hunter": continue
			var members: Array[Dictionary] = []
			for row: Dictionary in units:
				if int(row.squad_id) == int(squad.id): members.append(row.duplicate())
			rows.append({"id": squad.id, "order": squad.order, "alive": members.size(), "members": members})
	return {"hits": _hits, "cancellations": _cancellations, "chasing": chasing, "casting": casting,
		"alive": units.size(), "count": rows.size(), "units": units, "squads": rows}

func _exit_tree() -> void:
	clear()
