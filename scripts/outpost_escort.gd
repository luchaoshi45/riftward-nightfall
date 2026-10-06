extends RefCounted
## Real convoy bindings. Only destinations change; movement and combat stay
## owned by the existing squad/member clocks and gate-aware route cache.
const REFRESH_TIME := .5
const REFRESH_DISTANCE := .8
const MEMBERS := 3

var game: Node3D
var roster: Node3D
var _bindings: Dictionary = {}
var _has_navigation := false
var _has_blocks := false
var _has_roster_property := false
var _has_quitting := false
var _has_restart_pending := false

func setup(controller: Node3D, squad_roster: Node3D) -> void:
	clear()
	game = controller
	roster = squad_roster
	if not is_instance_valid(game): return
	for property: Dictionary in game.get_property_list():
		if String(property.name) == "hero_navigation": _has_navigation = true
		if String(property.name) == "construction_blocks": _has_blocks = true
		if String(property.name) == "squads": _has_roster_property = true
		if String(property.name) == "quitting": _has_quitting = true
		if String(property.name) == "restart_pending": _has_restart_pending = true

func _living(value: Variant) -> bool:
	return is_instance_valid(value) and value is BattleUnit and not value.is_queued_for_deletion() \
		and value.alive and value.hp > 0.0 and value.kind == "minion" and value.team == 0

func _owned(squad: Dictionary) -> bool:
	if not is_instance_valid(roster) or roster.is_queued_for_deletion(): return false
	if not is_instance_valid(game) or game.is_queued_for_deletion(): return false
	if _has_roster_property and game.get("squads") != roster: return false
	var rows: Array = roster.get("squads")
	var id := int(squad.get("id", -1))
	return id >= 0 and id < rows.size() and is_same(rows[id], squad)

func _alive(squad: Dictionary) -> bool:
	if not _owned(squad): return false
	for member: Variant in squad.get("members", []):
		if _living(member): return true
	return false

func _active() -> bool:
	if not is_instance_valid(game) or game.is_queued_for_deletion() or String(game.get("phase")) not in ["day", "night"]: return false
	if _has_quitting and bool(game.get("quitting")): return false
	if _has_restart_pending and bool(game.get("restart_pending")): return false
	return is_instance_valid(roster) and not roster.is_queued_for_deletion() and (not _has_roster_property or game.get("squads") == roster)

func _reference_slot(squad: Dictionary, previous: int = -1) -> int:
	var members: Array = squad.get("members", [])
	if previous >= 0 and previous < members.size() and _living(members[previous]): return previous
	if previous < 0 and members.size() > 1 and _living(members[1]): return 1
	for slot in members.size():
		if _living(members[slot]): return slot
	return -1

func _navigation_token() -> int:
	if not _has_navigation or not is_instance_valid(game): return -1
	var navigation: Variant = game.get("hero_navigation")
	return int(navigation.get_instance_id()) if is_instance_valid(navigation) else -1

func _block_signature() -> int:
	return hash(game.get("construction_blocks")) if _has_blocks and is_instance_valid(game) else 0

func _distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))

func _walkable(point: Vector3) -> bool:
	return point.is_finite() and (not game.has_method("outpost_walkable") or bool(game.call("outpost_walkable", point)))

func _grounded(point: Vector3) -> Vector3:
	return Vector3(point.x, float(roster.call("_ground_height", point)), point.z)

func _route_reaches(origin: Vector3, destination: Vector3, binding: Dictionary) -> bool:
	binding.route_checks = int(binding.route_checks) + 1
	if not origin.is_finite() or not _walkable(destination): return false
	if bool(roster.call("_traversable", origin, destination)): return true
	if not _has_navigation or not game.has_method("nearest_navigation_cell"): return false
	var navigation: Variant = game.get("hero_navigation")
	if not navigation is AStarGrid2D: return false
	var start: Vector2i = game.call("nearest_navigation_cell", origin, true)
	var finish: Vector2i = game.call("nearest_navigation_cell", destination, false)
	if start.x == 999 or finish.x == 999: return false
	binding.path_queries = int(binding.path_queries) + 1
	var path: PackedVector2Array = navigation.get_point_path(start, finish)
	if path.is_empty(): return false
	# Validate the same continuous smoothing used by build_day_hunter_route.
	# A neighbouring grid cell alone does not prove the final offset reachable.
	var cursor := origin
	var index := 0
	while index < path.size():
		var furthest := index
		for candidate in range(index, path.size()):
			var point := Vector3(path[candidate].x, 0, path[candidate].y)
			if bool(roster.call("_traversable", cursor, point)): furthest = candidate
			else: break
		var waypoint := Vector3(path[furthest].x, 0, path[furthest].y)
		if not bool(roster.call("_traversable", cursor, waypoint)): return false
		cursor = waypoint
		index = furthest + 1
	return bool(roster.call("_traversable", cursor, destination))

func _refresh(squad: Dictionary, binding: Dictionary, reference: BattleUnit) -> void:
	var stations: Array[Vector3] = []
	var index := int(squad.get("formation_index", 0))
	var waiting := false
	for slot in MEMBERS:
		var point := reference.position + Vector3((slot - 1) * 1.25 + float([0, -1, 1][index % 3]) * 3.7, 0, 1.8 + float(int(index / 3)) * 2.2)
		point = _grounded(point)
		var member: Variant = squad.members[slot]
		# Formation offsets must remain connected to the actual convoy member.
		# At narrow gates or building corners fall back to its real walkable point.
		if not _walkable(point) or not bool(roster.call("_traversable", reference.position, point)):
			point = reference.position
			binding.fallbacks = int(binding.fallbacks) + 1
		if _living(member) and not _route_reaches(member.position, point, binding):
			if point != reference.position and _route_reaches(member.position, reference.position, binding):
				point = reference.position
				binding.fallbacks = int(binding.fallbacks) + 1
			else:
				# Keep the binding while a real closure prevents passage. Navigation
				# replacement retries immediately; no alternate convoy is substituted.
				point = member.position
				waiting = true
		stations.append(point)
		# Existing movement owns this member's path. A reference update never
		# cancels a windup, resets cooldown or rebuilds that path here.
	binding.stations = stations
	binding.reference = reference.position
	binding.navigation_token = _navigation_token()
	binding.block_signature = _block_signature()
	binding.refresh_remaining = REFRESH_TIME
	binding.station_updates = int(binding.station_updates) + 1
	binding.phase = "waiting" if waiting else "following"

func command_selected(target_squad: Dictionary) -> Dictionary:
	if not _active(): return {"ok": false, "reason": "暂停或选卡时不能护航", "count": 0}
	if not _owned(target_squad) or String(target_squad.get("kind", "")) != "hauler" or not _alive(target_squad):
		return {"ok": false, "reason": "请选择真实存活工队", "count": 0}
	var count := 0
	var unchanged := 0
	var formation := 0
	var generation := int(roster.get("_epoch"))
	for squad: Dictionary in roster.get("squads"):
		if int(squad.id) not in roster.get("selected_ids") or String(squad.kind) == "hauler" or not _alive(squad): continue
		var old: Dictionary = _bindings.get(int(squad.id), {})
		if String(squad.order) == "escort" and not old.is_empty() and is_same(old.identity, squad) and is_same(old.target_identity, target_squad):
			count += 1; unchanged += 1; formation += 1
			continue
		roster.call("_set_squad_order", squad, "escort")
		if int(roster.get("_epoch")) != generation or not _active() or not _owned(squad) or not _alive(target_squad):
			return {"ok": false, "reason": "场景已变化，请重新选择工队", "count": count}
		squad.formation_index = formation
		squad.destination = target_squad.members[_reference_slot(target_squad)].position
		var binding := {"identity": squad, "target_identity": target_squad,
			"target_squad_id": int(target_squad.id), "target_member_slot": _reference_slot(target_squad),
			"reference": Vector3.INF, "stations": [], "refresh_remaining": 0.0,
			"navigation_token": -1, "block_signature": 0, "phase": "following",
			"station_updates": 0, "route_checks": 0, "path_queries": 0, "fallbacks": 0}
		_bindings[int(squad.id)] = binding
		_refresh(squad, binding, target_squad.members[int(binding.target_member_slot)])
		count += 1; formation += 1
	if count == 0: return {"ok": false, "reason": "请先选择活护卫部队", "count": 0}
	return {"ok": true, "reason": "护卫沿路跟随工队往返" if unchanged < count else "已在护航该工队，原进度保留",
		"count": count, "unchanged": unchanged, "target_squad_id": int(target_squad.id)}

func _binding(squad: Dictionary) -> Dictionary:
	var binding: Dictionary = _bindings.get(int(squad.get("id", -1)), {})
	if binding.is_empty() or not _owned(squad) or not is_same(binding.identity, squad): return {}
	return binding

func _guard(squad: Dictionary, binding: Dictionary) -> void:
	var stations: Array[Vector3] = []
	for slot in MEMBERS:
		var member: Variant = squad.members[slot]
		stations.append(member.position if _living(member) else (binding.stations[slot] if (binding.stations as Array).size() == MEMBERS else squad.destination))
	# Unbind before order cancellation, so a synchronous refill cannot inherit
	# the old convoy. Each living soldier guards its actual individual position.
	_bindings.erase(int(squad.id))
	if not _owned(squad): return
	roster.call("_set_squad_order", squad, "guard")
	if not _owned(squad): return
	squad.rally_stations = stations
	squad.destination = stations[1]

func prepare_squad(squad: Dictionary, delta: float) -> void:
	if not _active() or String(squad.order) != "escort": return
	var binding := _binding(squad)
	if binding.is_empty(): return
	var target_squad: Dictionary = binding.target_identity
	if not _owned(target_squad) or not _alive(target_squad) or not _alive(squad):
		_guard(squad, binding)
		return
	var old_slot := int(binding.target_member_slot)
	var slot := _reference_slot(target_squad, old_slot)
	var reference: BattleUnit = target_squad.members[slot]
	binding.target_member_slot = slot
	binding.refresh_remaining = maxf(0.0, float(binding.refresh_remaining) - maxf(0.0, delta))
	var navigation_changed := int(binding.navigation_token) != _navigation_token() or int(binding.block_signature) != _block_signature()
	if slot != old_slot or navigation_changed or (float(binding.refresh_remaining) <= 0.0 and _distance(binding.reference, reference.position) > REFRESH_DISTANCE):
		_refresh(squad, binding, reference)

func station(squad: Dictionary, slot: int) -> Vector3:
	var binding := _binding(squad)
	var stations: Array = binding.get("stations", [])
	if slot >= 0 and slot < stations.size(): return stations[slot]
	var member: Variant = squad.members[slot] if slot >= 0 and slot < squad.members.size() else null
	return member.position if _living(member) else squad.destination

func on_order(squad: Dictionary) -> void:
	var binding := _binding(squad)
	if not binding.is_empty(): _bindings.erase(int(squad.id))

func on_member_defeated(_member: BattleUnit) -> void:
	# This runs inside the real defeated signal, before any later refill callback.
	for id: int in _bindings.keys():
		var binding: Dictionary = _bindings[id]
		var squad: Dictionary = binding.identity
		var target_squad: Dictionary = binding.target_identity
		if not _owned(squad):
			_bindings.erase(id)
			continue
		if not _alive(squad) or not _owned(target_squad) or not _alive(target_squad):
			_guard(squad, binding)
			continue
		var old_slot := int(binding.target_member_slot)
		var next_slot := _reference_slot(target_squad, old_slot)
		if next_slot != old_slot:
			binding.target_member_slot = next_slot
			_refresh(squad, binding, target_squad.members[next_slot])

func on_phase_changed() -> void:
	# The binding survives day/night; only sampled geometry waits for the next
	# active frame. Member pending attacks are cleared by the roster itself.
	for binding: Dictionary in _bindings.values():
		binding.navigation_token = -2
		binding.refresh_remaining = 0.0

func snapshot() -> Dictionary:
	var rows: Array[Dictionary] = []
	for id: int in _bindings:
		var binding: Dictionary = _bindings[id]
		var squad: Dictionary = binding.identity
		var target_squad: Dictionary = binding.target_identity
		if not _owned(squad) or not _owned(target_squad) or not _alive(squad) or not _alive(target_squad) or String(squad.order) != "escort": continue
		rows.append({"squad_id": id, "target_squad_id": int(binding.target_squad_id),
			"target_member_slot": int(binding.target_member_slot), "binding": true,
			"phase": String(binding.phase), "reference": binding.reference,
			"stations": (binding.stations as Array).duplicate(), "refresh_remaining": float(binding.refresh_remaining),
			"station_updates": int(binding.station_updates), "route_checks": int(binding.route_checks),
			"path_queries": int(binding.path_queries), "fallbacks": int(binding.fallbacks),
			"navigation_token": int(binding.navigation_token)})
	return {"count": rows.size(), "squads": rows}

func clear() -> void:
	for id: int in _bindings.keys():
		var binding: Dictionary = _bindings.get(id, {})
		if not binding.is_empty() and _owned(binding.identity): _guard(binding.identity, binding)
	_bindings.clear()
	game = null
	roster = null
	_has_navigation = false
	_has_blocks = false
	_has_roster_property = false
	_has_quitting = false
	_has_restart_pending = false
