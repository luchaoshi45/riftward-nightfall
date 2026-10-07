extends Node3D
## Finite physical salvage: members carry goods, reachable live depots pay once.
const NightHaulScript = preload("res://scripts/outpost_night_haul.gd")
const HAUL := "haul"
const DEPOT := "depot"
const FIELD_STOCK := 96
const MEMBER_CAPACITY := 8
const LOAD_SECONDS := 3.0
const UNLOAD_SECONDS := 1.0
const FIELD_RADIUS := 1.3
const ARRIVAL_RADIUS := .23
const PLANNING_INTERVAL := .5
const FIELD_SEEDS := [Vector3(-20, 0, 29), Vector3(20, 0, 29), Vector3(-33, 0, 43), Vector3(33, 0, 43), Vector3(0, 0, 59)]
const STATE_TITLES := {"idle": "准备采运", "outbound": "前往废料堆", "loading": "装载中", "returning": "载货返站",
	"unloading": "卸货中", "manual": "手动指挥", "night_wait": "夜间待命", "waiting_home": "等待可达中转站",
	"waiting_field": "等待可达废料堆", "exhausted": "废料已采尽", "defeated": "工队已阵亡"}

var game: Node3D
var fields: Array[Dictionary] = []
var delivered := 0
var lost := 0
var raided := 0
var _teams: Dictionary = {}
var _cargo: Dictionary = {}
var _members: Dictionary = {}
var _member_teams: Dictionary = {}
var _properties: Dictionary = {}
var _elapsed := 0.0
var _navigation_token := -1
var _route_cache: Dictionary = {}
var night_haul := NightHaulScript.new()

func setup(controller: Node3D) -> void:
	clear()
	game = controller
	if get_parent() == null: game.add_child(self)
	for property: Dictionary in game.get_property_list(): _properties[String(property.name)] = true
	night_haul.setup(self)
	var used: Array[Vector3] = []
	for index in FIELD_SEEDS.size():
		var point := _field_site(FIELD_SEEDS[index], used)
		if not point.is_finite():
			push_error("Finite salvage field %d has no reachable position" % index)
			continue
		used.append(point)
		fields.append(_create_field(index, point))

func clear() -> void:
	night_haul.clear()
	for token in _cargo.keys(): _show_cargo(int(token), 0)
	for field: Dictionary in fields:
		if is_instance_valid(field.get("node")): (field.node as Node).queue_free()
	fields.clear()
	_teams.clear(); _cargo.clear(); _members.clear(); _member_teams.clear(); _properties.clear()
	_route_cache.clear()
	delivered = 0; lost = 0; raided = 0; _elapsed = 0.0; _navigation_token = -1
	game = null

func _property(name: String) -> Variant:
	return game.get(name) if is_instance_valid(game) and _properties.has(name) else null

func _active() -> bool:
	if not is_instance_valid(game) or game.is_queued_for_deletion() or String(_property("phase")) not in ["day", "night"]: return false
	for flag: String in ["quitting", "restart_pending", "shutting_down"]:
		if bool(_property(flag)): return false
	return true

func _living(unit: Variant) -> bool:
	return is_instance_valid(unit) and unit is BattleUnit and not unit.is_queued_for_deletion() and unit.alive

func _unit(token: int) -> BattleUnit:
	var reference: Variant = _members.get(token)
	if reference is WeakRef:
		var value: Variant = reference.get_ref()
		if _living(value): return value as BattleUnit
	return null

func _squads() -> Node:
	var value: Variant = _property("squads")
	return value as Node if is_instance_valid(value) and value is Node else null

func _sync_teams() -> void:
	var squads := _squads()
	if not is_instance_valid(squads): return
	var live_tokens: Dictionary = {}
	for squad: Dictionary in squads.get("squads"):
		if String(squad.kind) != "hauler": continue
		var id := int(squad.id)
		if not _teams.has(id):
			_teams[id] = {"id": id, "state": "idle", "reason": "", "field": -1, "preferred_field": -1, "home": -1,
				"loading": 0.0, "automatic": String(squad.order) == HAUL, "retry": 0.0,
				"destinations": {}, "homes": {}, "unloading": {}, "tokens": [], "positions": {},
				"stalled": 0.0, "blocked_fields": {}}
		var team: Dictionary = _teams[id]
		team.automatic = String(squad.order) == HAUL
		var tokens: Array[int] = []
		for member: Variant in squad.members:
			if not _living(member): continue
			var token: int = member.get_instance_id()
			tokens.append(token); live_tokens[token] = true
			_members[token] = weakref(member); _member_teams[token] = id
		team.tokens = tokens
	for token in _cargo.keys():
		if not live_tokens.has(token): on_member_defeated(int(token))
	for token in _members.keys():
		if not live_tokens.has(token):
			_members.erase(token); _member_teams.erase(token)

func advance(delta: float) -> void:
	if not _active() or not is_finite(delta) or delta <= 0.0: return
	_elapsed += delta
	_sync_teams()
	night_haul.advance()
	var navigation: Variant = _property("hero_navigation")
	var token: int = navigation.get_instance_id() if is_instance_valid(navigation) else -1
	if token != _navigation_token:
		_navigation_token = token; _route_cache.clear()
		for team: Dictionary in _teams.values(): team.retry = 0.0; team.homes.clear()
	for team: Dictionary in _teams.values():
		if not _active(): return
		team.retry = maxf(0.0, float(team.retry) - delta)
		if (team.tokens as Array).is_empty():
			_release_field(team); team.destinations.clear(); team.homes.clear()
			_set_state(team, "defeated", "补员后可重新开始采运")
			continue
		if not bool(team.automatic):
			_release_field(team); team.destinations.clear(); team.unloading.clear()
			team.preferred_field = -1
			_set_state(team, "manual", "载货保留 · 点击恢复采运")
			continue
		_clear_empty_preference(team)
		if _team_cargo(int(team.id)) > 0:
			_release_field(team)
			_advance_return(team, delta, true)
		elif String(_property("phase")) == "night":
			if night_haul.can_haul(int(team.id)):
				_advance_field(team, delta)
			else:
				_release_field(team)
				_advance_return(team, delta, false)
		else:
			_advance_field(team, delta)
	_refresh_route_markers()

func _field_live(index: int) -> bool:
	if index < 0 or index >= fields.size(): return false
	var node: Variant = fields[index].get("node")
	return is_instance_valid(node) and node is Node3D and not node.is_queued_for_deletion() and node.get_parent() == self and (fields[index].position as Vector3).is_finite()

func field_at_point(point: Vector3) -> int:
	# Picking also finds empty heaps so the command can explain their depletion.
	# Reading the map must never claim stock, refresh routes or advance a clock.
	if not point.is_finite() or absf(point.y - _height(point)) > .75: return -1
	var found := -1
	var nearest := FIELD_RADIUS
	for index in fields.size():
		if not _field_live(index): continue
		var distance := _distance(point, fields[index].position)
		if distance <= nearest:
			found = index; nearest = distance
	return found

func selected_hauler_count() -> int:
	var squads := _squads()
	if not is_instance_valid(squads): return 0
	var count := 0
	for squad: Dictionary in squads.get("squads"):
		if String(squad.kind) != "hauler" or int(squad.id) not in squads.get("selected_ids"): continue
		for member: Variant in squad.members:
			if _living(member):
				count += 1
				break
	return count

func haul_raider_targets() -> Array[Dictionary]:
	# The raider may only lock a real living carrier that currently owns
	# physical cargo. A selected or automatic order alone is never enough.
	_sync_teams()
	var result: Array[Dictionary] = []
	for team: Dictionary in _teams.values():
		var team_id := int(team.id)
		for token: int in team.tokens:
			var member := _unit(token)
			var cargo_row: Dictionary = _cargo.get(token, {})
			if not _living(member) or cargo_row.is_empty() or int(cargo_row.get("amount", 0)) <= 0:
				continue
			result.append({"kind": "squad", "index": -1, "token": token,
				"squad_id": team_id, "unit": member, "position": member.position,
				"haul_cargo": int(cargo_row.amount)})
	return result

func haul_raider_target(origin: Vector3) -> Dictionary:
	var candidates := haul_raider_targets()
	if candidates.is_empty():
		return {}
	var selected: Dictionary = {}
	var best := INF
	for candidate: Dictionary in candidates:
		var point: Vector3 = candidate.position
		var distance := _distance(origin, point)
		if distance < best:
			best = distance
			selected = candidate
	return selected

func command_selected_field(index: int) -> Dictionary:
	if not _active(): return {"ok": false, "count": 0, "reason": "暂停或选卡时不能指定采运"}
	if not _field_live(index): return {"ok": false, "count": 0, "reason": "请选择真实废料堆"}
	if int(fields[index].remaining) <= 0: return {"ok": false, "count": 0, "reason": "废料堆已采尽 · 请选择其他资源线"}
	if selected_hauler_count() <= 0: return {"ok": false, "count": 0, "reason": "请先选择存活采运工队"}
	var squads := _squads()
	_sync_teams()
	var commanded := 0
	for id: int in squads.get("selected_ids"):
		if not _teams.has(id) or (_teams[id].tokens as Array).is_empty(): continue
		var team: Dictionary = _teams[id]
		# A repeated order is genuinely inert, including an unload already in progress.
		if bool(team.automatic) and int(team.preferred_field) == index:
			commanded += 1
			continue
		night_haul.cancel(id, "资源线已改变 · 夜采取消")
		var has_goods := _team_cargo(id) > 0
		# An automatic loaded carrier retains its current depot route and unload timer.
		# Other changes clear unit paths through the existing squad order API.
		if (not bool(team.automatic) or not has_goods) and not bool(squads.call("set_haul_order", id)): continue
		_release_field(team)
		team.preferred_field = index; team.automatic = true; team.retry = 0.0
		if not has_goods:
			team.destinations.clear(); team.homes.clear(); team.unloading.clear(); team.home = -1
			_set_state(team, "idle" if String(_property("phase")) == "day" else "night_wait", "指定堆%d · 夜间不采料" % (index + 1) if String(_property("phase")) == "night" else "")
		elif String(team.state) != "unloading":
			_set_state(team, "returning", "先卸已有载货，再前往指定堆%d" % (index + 1))
		commanded += 1
	_refresh_route_markers()
	return {"ok": commanded > 0, "count": commanded,
		"reason": "%d队指定废料堆%d · %s" % [commanded, index + 1, "夜间先返站，天亮续线" if String(_property("phase")) == "night" else "载货先卸，白昼循环采运"] if commanded > 0 else "请先选择存活采运工队"}

func _clear_empty_preference(team: Dictionary) -> void:
	var index := int(team.preferred_field)
	if index >= 0 and _team_cargo(int(team.id)) <= 0 and (not _field_live(index) or int(fields[index].remaining) <= 0):
		team.preferred_field = -1

func start_selected_hauling() -> Dictionary:
	if not _active(): return {"ok": false, "reason": "暂停或选卡时不能恢复采运", "count": 0}
	var squads := _squads()
	if not is_instance_valid(squads): return {"ok": false, "reason": "部队尚未初始化", "count": 0}
	_sync_teams()
	var started := 0
	for id: int in squads.get("selected_ids"):
		if not _teams.has(id) or (_teams[id].tokens as Array).is_empty(): continue
		night_haul.cancel(id, "恢复自动采运 · 夜采取消")
		if not bool(squads.call("set_haul_order", id)): continue
		var team: Dictionary = _teams[id]
		_release_field(team); team.automatic = true; team.retry = 0.0
		team.preferred_field = -1
		team.homes.clear(); team.unloading.clear(); team.destinations.clear()
		_set_state(team, "returning" if _team_cargo(id) > 0 else "idle", "")
		started += 1
	_refresh_route_markers()
	return {"ok": started > 0, "count": started,
		"reason": ("%d队恢复采运" % started if String(_property("phase")) == "day" else "%d队返站 · 夜间不采料" % started) if started > 0 else "请先选择存活采运工队"}

func on_manual_order(squad_id: int) -> void:
	night_haul.cancel(squad_id, "手动指挥已取消夜采")
	if not _teams.has(squad_id): return
	var team: Dictionary = _teams[squad_id]
	_release_field(team); team.automatic = false
	team.preferred_field = -1
	team.destinations.clear(); team.homes.clear(); team.unloading.clear()
	team.home = -1
	_set_state(team, "manual", "载货保留 · 点击恢复采运")
	_refresh_route_markers()

func on_member_defeated(member_token: int) -> void:
	night_haul.on_member_defeated(member_token)
	var row: Dictionary = _cargo.get(member_token, {})
	var team_id := int(row.get("squad_id", _member_teams.get(member_token, -1)))
	if not row.is_empty():
		lost += int(row.amount)
		_cargo.erase(member_token)
		_show_cargo(member_token, 0)
	if _teams.has(team_id):
		var team: Dictionary = _teams[team_id]
		_release_field(team)
		team.destinations.erase(member_token); team.homes.erase(member_token); team.unloading.erase(member_token)
		team.retry = 0.0
	_refresh_route_markers()

func raid_member(member_token: int, expected_member: Variant, expected_squad_id: int, amount: int) -> Dictionary:
	# A raider must operate on the exact live carrier it originally targeted.
	# Refreshing the roster here prevents a same-slot replacement from inheriting
	# the old target, while all validation happens before touching cargo or stats.
	var result := {"ok": false, "amount": 0, "reason": "", "token": member_token,
		"squad_id": expected_squad_id, "remaining": 0}
	if not _active():
		result.reason = "inactive"
		return result
	if amount <= 0:
		result.reason = "invalid_amount"
		return result
	if expected_squad_id < 0:
		result.reason = "invalid_squad"
		return result
	_sync_teams()
	var member := _unit(member_token)
	if not _living(member):
		result.reason = "member_not_alive"
		return result
	if not is_instance_valid(expected_member) or not is_same(member, expected_member):
		result.reason = "member_identity_mismatch"
		return result
	var current_squad_id := int(_member_teams.get(member_token, -1))
	if current_squad_id != expected_squad_id:
		result.reason = "squad_identity_mismatch"
		return result
	var cargo_row: Dictionary = _cargo.get(member_token, {})
	if cargo_row.is_empty():
		result.reason = "no_cargo"
		return result
	if int(cargo_row.get("squad_id", -1)) != expected_squad_id:
		result.reason = "cargo_identity_mismatch"
		return result
	var available := maxi(0, int(cargo_row.get("amount", 0)))
	var stolen := mini(amount, available)
	if stolen <= 0:
		result.reason = "no_cargo"
		return result

	# Commit the whole transfer as one state change. The wallet is deliberately
	# untouched: raided goods leave the carrier and are tracked separately from
	# goods lost when a carrier is defeated.
	var remaining := available - stolen
	if remaining > 0:
		cargo_row.amount = remaining
		_cargo[member_token] = cargo_row
	else:
		_cargo.erase(member_token)
	raided += stolen
	_show_cargo(member_token, remaining)
	result.ok = true
	result.amount = stolen
	result.remaining = remaining
	return result

func on_night() -> void:
	if not _active() or String(_property("phase")) != "night": return
	var permit_state := night_haul.snapshot()
	# A retired night remains closed even while finish_night still owns the
	# night phase. Replaying the hook must not mutate ordinary return state.
	if bool(permit_state.retired) and int(permit_state.night) == int(permit_state.current_night): return
	_sync_teams()
	night_haul.on_night()
	for team: Dictionary in _teams.values():
		if night_haul.can_haul(int(team.id)): continue
		_release_field(team); team.retry = 0.0
		if bool(team.automatic):
			_set_state(team, "returning" if _team_cargo(int(team.id)) > 0 else "night_wait", "天黑停止采料 · 载货继续返站")
	_refresh_route_markers()

func on_night_end() -> void:
	night_haul.on_night_end()
	_refresh_route_markers()

func on_day() -> void:
	if not _active() or String(_property("phase")) != "day": return
	night_haul.on_day()
	for team: Dictionary in _teams.values():
		_release_field(team); team.retry = 0.0
		if bool(team.automatic): _set_state(team, "returning" if _team_cargo(int(team.id)) > 0 else "idle", "")
	_refresh_route_markers()

func night_haul_snapshot() -> Dictionary:
	return night_haul.snapshot()

func night_haul_selection() -> Dictionary:
	return night_haul.selection()

func prepare_selected_night_hauling() -> Dictionary:
	# Explicit field commands already synchronize their real team. A rejected
	# permit request must not create an otherwise absent logistics state.
	return night_haul.prepare_selected()

func toggle_selected_night_hauling() -> Dictionary:
	return night_haul.toggle_selected()

func stop_selected_night_hauling() -> Dictionary:
	return night_haul.stop_selected()

func _stop_night_hauling(id: int, reason: String) -> void:
	if not _teams.has(id): return
	var team: Dictionary = _teams[id]
	_release_field(team); team.retry = 0.0; team.destinations.clear()
	# This is a permit stop, not a manual squad order. Loaded members retain
	# their paid-for cargo, home bindings and current unload timers.
	if bool(team.automatic):
		_set_state(team, "returning" if _team_cargo(id) > 0 else "night_wait", reason)
	_refresh_route_markers()

func destination_for(squad_id: int, member_token: int) -> Vector3:
	if _teams.has(squad_id):
		var destinations: Dictionary = _teams[squad_id].destinations
		if destinations.has(member_token): return destinations[member_token]
	var member := _unit(member_token)
	return member.position if _living(member) else Vector3.INF

func _set_state(team: Dictionary, state: String, reason: String) -> void:
	team.state = state; team.reason = reason

func _release_field(team: Dictionary) -> void:
	var index := int(team.field)
	if index >= 0 and index < fields.size() and int(fields[index].claimed_by) == int(team.id): fields[index].claimed_by = -1
	team.field = -1; team.loading = 0.0; team.stalled = 0.0; team.positions.clear()

func _team_cargo(id: int) -> int:
	var amount := 0
	for row: Dictionary in _cargo.values():
		if int(row.squad_id) == id: amount += int(row.amount)
	return amount

func _advance_field(team: Dictionary, delta: float) -> void:
	if not _active() or not is_finite(delta) or delta <= 0.0: return
	# Permission is checked at the actual field path as well as its caller.
	# Losing an original field/roster identity cannot fall back to a new heap.
	if String(_property("phase")) == "night" and not night_haul.can_haul(int(team.id)):
		_release_field(team)
		_advance_return(team, delta, _team_cargo(int(team.id)) > 0)
		return
	if _depots().is_empty():
		_release_field(team); team.destinations.clear(); team.home = -1; team.homes.clear()
		_set_state(team, "waiting_home", "需要存活中转站")
		return
	var field_index := int(team.field)
	if field_index < 0:
		if float(team.retry) > 0.0: return
		field_index = _choose_field(team)
		team.retry = PLANNING_INTERVAL
		if field_index < 0:
			team.destinations.clear()
			if int(team.preferred_field) >= 0:
				_set_state(team, "waiting_field", String(team.reason))
			else:
				_set_state(team, "exhausted" if _remaining() <= 0 else "waiting_field", "本局废料已采尽" if _remaining() <= 0 else "无空闲可达废料堆")
			return
		team.field = field_index; fields[field_index].claimed_by = int(team.id)
		team.homes.clear(); team.unloading.clear(); team.home = -1
		team.positions.clear(); team.stalled = 0.0
	var field: Dictionary = fields[field_index]
	if not _field_live(field_index) or int(field.remaining) <= 0 or int(field.claimed_by) != int(team.id):
		_release_field(team); team.destinations.clear(); team.retry = 0.0
		return
	var all_arrived := true
	var destinations: Dictionary = {}
	var movement := 0.0
	for slot in (team.tokens as Array).size():
		var member_token := int(team.tokens[slot])
		var member := _unit(member_token)
		if not _living(member): all_arrived = false; continue
		var point := _field_destination(field.position, slot)
		destinations[member_token] = point
		if float(team.retry) <= 0.0 and _route_cost(member.position, point) < 0.0:
			(team.blocked_fields as Dictionary)[field_index] = _elapsed + 3.0
			_release_field(team); team.destinations.clear(); team.retry = 1.0
			_set_state(team, "waiting_field", "路径被建筑阻断 · 预约已释放")
			return
		if (team.positions as Dictionary).has(member_token): movement += _distance(member.position, team.positions[member_token])
		team.positions[member_token] = member.position
		if not _at_field(member, field.position) or _distance(member.position, point) > ARRIVAL_RADIUS: all_arrived = false
	team.destinations = destinations
	if float(team.retry) <= 0.0: team.retry = PLANNING_INTERVAL
	if not all_arrived:
		team.loading = 0.0
		team.stalled = float(team.stalled) + delta if movement < .001 else 0.0
		if float(team.stalled) >= 3.0:
			(team.blocked_fields as Dictionary)[field_index] = _elapsed + 3.0
			_release_field(team); team.destinations.clear(); team.retry = 1.0
			_set_state(team, "waiting_field", "移动受阻 · 预约已释放")
		else: _set_state(team, "outbound", "")
		return
	team.stalled = 0.0
	_set_state(team, "loading", "")
	team.loading = float(team.loading) + delta
	if float(team.loading) < LOAD_SECONDS: return
	if String(_property("phase")) == "night" and not night_haul.can_haul(int(team.id)):
		_release_field(team); team.destinations.clear()
		return
	# Atomic finite source transfer. Only members really standing at this heap
	# acquire goods; a dead or remotely located member never receives capacity.
	var remaining := int(field.remaining)
	for member_token: int in team.tokens:
		var member := _unit(member_token)
		if not _living(member) or not _at_field(member, field.position) or remaining <= 0: continue
		var amount := mini(MEMBER_CAPACITY, remaining)
		_cargo[member_token] = {"squad_id": int(team.id), "amount": amount}
		remaining -= amount
		_show_cargo(member_token, amount)
	field.remaining = remaining
	_refresh_field(field)
	_release_field(team); team.destinations.clear(); team.retry = 0.0
	if remaining <= 0: night_haul.cancel(int(team.id), "指定废料堆已采尽 · 载货返站")
	_set_state(team, "returning", "")

func _choose_field(team: Dictionary) -> int:
	var member := _unit(int(team.tokens[0]))
	if not _living(member): return -1
	var preferred := int(team.preferred_field)
	if preferred >= 0:
		team.reason = "等待指定堆%d可达 · 保持资源线" % (preferred + 1)
		if not _field_live(preferred): return -1
		var field: Dictionary = fields[preferred]
		if int(field.remaining) <= 0: return -1
		if int(field.claimed_by) >= 0 and int(field.claimed_by) != int(team.id):
			team.reason = "指定堆%d被其他工队预约 · 保持资源线" % (preferred + 1)
			return -1
		if float((team.blocked_fields as Dictionary).get(preferred, 0.0)) > _elapsed: return -1
		for slot in (team.tokens as Array).size():
			var carrier := _unit(int(team.tokens[slot]))
			if not _living(carrier) or _route_cost(carrier.position, _field_destination(field.position, slot)) < 0.0: return -1
		return preferred
	var candidates: Array[int] = []
	for index in fields.size():
		var field: Dictionary = fields[index]
		if not _field_live(index) or int(field.remaining) <= 0 or int(field.claimed_by) >= 0: continue
		if float((team.blocked_fields as Dictionary).get(index, 0.0)) > _elapsed: continue
		candidates.append(index)
	candidates.sort_custom(func(left: int, right: int) -> bool: return _distance(member.position, fields[left].position) < _distance(member.position, fields[right].position))
	for index in candidates:
		var reachable := true
		for slot in (team.tokens as Array).size():
			var carrier := _unit(int(team.tokens[slot]))
			if not _living(carrier) or _route_cost(carrier.position, _field_destination(fields[index].position, slot)) < 0.0:
				reachable = false; break
		if reachable: return index
	return -1

func _field_destination(point: Vector3, slot: int) -> Vector3:
	var destination := point + Vector3((slot - 1) * .55, 0, 0)
	if not _walkable(destination): destination = point
	destination.y = _height(destination)
	return destination

func _at_field(member: BattleUnit, point: Vector3) -> bool:
	return _distance(member.position, point) <= FIELD_RADIUS and absf(member.position.y - _height(member.position)) <= .75 and _walkable(member.position) and _line(member.position, point)

func _advance_return(team: Dictionary, delta: float, has_goods: bool) -> void:
	var waiting := false
	var unloading := false
	var destinations: Dictionary = {}
	team.home = -1
	for member_token: int in team.tokens:
		var member := _unit(member_token)
		if not _living(member): continue
		var home: Dictionary = (team.homes as Dictionary).get(member_token, {})
		if not _home_valid(home) or (float(team.retry) <= 0.0 and _route_cost(member.position, home.get("position", Vector3.INF)) < 0.0):
			home = _choose_home(member)
			team.homes[member_token] = home
			team.unloading[member_token] = 0.0
		if home.is_empty():
			destinations[member_token] = member.position
			team.unloading[member_token] = 0.0
			if _cargo.has(member_token) or not has_goods: waiting = true
			continue
		team.home = int(home.index)
		var destination: Vector3 = home.position
		destinations[member_token] = destination
		if not _cargo.has(member_token): continue
		if not _at_home(member, home):
			team.unloading[member_token] = 0.0
			continue
		unloading = true
		var elapsed := float((team.unloading as Dictionary).get(member_token, 0.0)) + delta
		team.unloading[member_token] = elapsed
		var plot := _home_plot(home)
		var interval := .5 if int(plot.get("level", 0)) >= 2 else UNLOAD_SECONDS
		if elapsed < interval: continue
		# Each carrier, not the squad centroid, must really reach the current
		# live station and remain there. Erase before paying so reentry is inert.
		var amount := int(_cargo[member_token].amount)
		_cargo.erase(member_token); team.unloading.erase(member_token)
		delivered += amount
		game.set("scrap", int(_property("scrap")) + amount)
		_show_cargo(member_token, 0)
	team.destinations = destinations
	_clear_empty_preference(team)
	if float(team.retry) <= 0.0: team.retry = PLANNING_INTERVAL
	if waiting: _set_state(team, "waiting_home", "保留载货 · 等待可达存活中转站" if has_goods else "等待可达存活中转站 · 夜间不采料")
	elif has_goods: _set_state(team, "unloading" if unloading else "returning", "")
	else: _set_state(team, "night_wait", "夜間不出发 · 返回中转站待命")

func _depots() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var districts: Variant = _property("districts")
	if not is_instance_valid(districts): return rows
	for plot: Dictionary in districts.get("plots"):
		if String(plot.get("kind", "")) != DEPOT or int(plot.get("level", 0)) <= 0 or float(plot.get("hp", 0.0)) <= 0.0: continue
		var model: Variant = plot.get("model")
		if not is_instance_valid(model) or model.is_queued_for_deletion(): continue
		rows.append(plot)
	return rows

func _home_plot(home: Dictionary) -> Dictionary:
	if home.is_empty(): return {}
	for plot: Dictionary in _depots():
		if int(plot.index) == int(home.index) and (plot.model as Node).get_instance_id() == int(home.token): return plot
	return {}

func _home_valid(home: Dictionary) -> bool:
	if home.is_empty(): return false
	var point: Vector3 = home.get("position", Vector3.INF)
	return point.is_finite() and _walkable(point) and not _home_plot(home).is_empty()

func _choose_home(member: BattleUnit) -> Dictionary:
	if not game.has_method("building_approach_position"): return {}
	var selected: Dictionary = {}
	var best := INF
	for plot: Dictionary in _depots():
		var point: Vector3 = game.call("building_approach_position", member.position, plot.position, DEPOT)
		if not point.is_finite() or not _walkable(point): continue
		var cost := _route_cost(member.position, point)
		if cost < 0.0 or cost >= best: continue
		best = cost
		selected = {"index": int(plot.index), "token": (plot.model as Node).get_instance_id(), "position": point}
	return selected

func _at_home(member: BattleUnit, home: Dictionary) -> bool:
	var plot := _home_plot(home)
	if plot.is_empty(): return false
	var point: Vector3 = home.position
	return _distance(member.position, point) <= ARRIVAL_RADIUS and absf(member.position.y - _height(point)) <= .75 and _walkable(member.position) and _traversable(member.position, point) and _line(member.position, plot.position)

func _show_cargo(token: int, amount: int) -> void:
	var reference: Variant = _members.get(token)
	var value: Variant = reference.get_ref() if reference is WeakRef else null
	if not is_instance_valid(value) or not value is BattleUnit: return
	value.set_meta("haul_cargo", amount)
	var model := (value as BattleUnit).visual.find_child("HaulCargo", true, false) as Node3D
	if is_instance_valid(model): model.visible = amount > 0

func _remaining() -> int:
	var amount := 0
	for field: Dictionary in fields: amount += int(field.remaining)
	return amount

func snapshot() -> Dictionary:
	# Presentation never plans routes, claims stock, advances clocks or pays.
	var field_rows: Array[Dictionary] = []
	for field: Dictionary in fields:
		field_rows.append({"id": int(field.id), "position": field.position, "title": "废料堆", "stock": FIELD_STOCK,
			"remaining": int(field.remaining), "claimed_by": int(field.claimed_by)})
	var rows: Array[Dictionary] = []
	var total_cargo := 0
	for row: Dictionary in _cargo.values(): total_cargo += int(row.amount)
	for team: Dictionary in _teams.values():
		var members: Array[Dictionary] = []
		var unload_progress := 0.0
		for token: int in team.tokens:
			var member := _unit(token)
			var home: Dictionary = (team.homes as Dictionary).get(token, {})
			var plot := _home_plot(home)
			var seconds := .5 if int(plot.get("level", 0)) >= 2 else UNLOAD_SECONDS
			var progress := clampf(float((team.unloading as Dictionary).get(token, 0.0)) / seconds, 0.0, 1.0)
			unload_progress = maxf(unload_progress, progress)
			members.append({"token": token, "cargo": int((_cargo.get(token, {}) as Dictionary).get("amount", 0)),
				"alive": _living(member), "position": member.position if _living(member) else Vector3.INF,
				"destination": (team.destinations as Dictionary).get(token, Vector3.INF), "unloading_progress": progress})
		rows.append({"id": int(team.id), "state": String(team.state), "state_title": STATE_TITLES.get(String(team.state), "采运"),
			"reason": String(team.reason), "field": int(team.field), "preferred_field": int(team.preferred_field), "home": int(team.home), "automatic": bool(team.automatic),
			"cargo": _team_cargo(int(team.id)), "loading_progress": clampf(float(team.loading) / LOAD_SECONDS, 0.0, 1.0),
			"unloading_progress": unload_progress, "members": members})
	return {"remaining": _remaining(), "cargo": total_cargo, "delivered": delivered, "lost": lost, "raided": raided,
		"fields": field_rows, "teams": rows}

func _distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x, from.z).distance_to(Vector2(to.x, to.z))

func _height(point: Vector3) -> float:
	if game.has_method("outpost_height"): return float(game.call("outpost_height", point))
	return point.y

func _walkable(point: Vector3) -> bool:
	return point.is_finite() and (not game.has_method("outpost_walkable") or bool(game.call("outpost_walkable", point)))

func _traversable(from: Vector3, to: Vector3) -> bool:
	return game.has_method("can_traverse") and bool(game.call("can_traverse", from, to))

func _line(from: Vector3, to: Vector3) -> bool:
	return bool(game.call("can_attack_line", from, to)) if game.has_method("can_attack_line") else _traversable(from, to)

func _route_cost(from: Vector3, to: Vector3) -> float:
	if not from.is_finite() or not to.is_finite() or not _walkable(to): return -1.0
	if _traversable(from, to): return _distance(from, to)
	var navigation: Variant = _property("hero_navigation")
	if not navigation is AStarGrid2D or not game.has_method("nearest_navigation_cell"): return -1.0
	var start: Vector2i = game.call("nearest_navigation_cell", from, true)
	var finish: Vector2i = game.call("nearest_navigation_cell", to, true)
	if start.x == 999 or finish.x == 999: return -1.0
	var key := "%s" % Vector4i(start.x, start.y, finish.x, finish.y)
	if _route_cache.has(key): return float(_route_cache[key])
	var path: PackedVector2Array = navigation.get_point_path(start, finish)
	var cost := -1.0
	if not path.is_empty():
		cost = 0.0
		for index in range(1, path.size()): cost += path[index - 1].distance_to(path[index])
	if _route_cache.size() >= 2048: _route_cache.clear()
	_route_cache[key] = cost
	return cost

func _field_site(seed: Vector3, used: Array[Vector3]) -> Vector3:
	var origin := Vector3(0, 5, 3.9)
	var hero: Variant = _property("hero")
	if is_instance_valid(hero): origin = hero.position
	for ring in 9:
		for side in (1 if ring == 0 else 8):
			var angle := TAU * float(side) / 8.0
			var point := seed + Vector3(cos(angle), 0, sin(angle)) * float(ring) * 1.5
			point.y = _height(point)
			if not _walkable(point) or _route_cost(origin, point) < 0.0 or _overlapping_sources(point, used): continue
			return point
	return Vector3.INF

func _overlapping_sources(point: Vector3, used: Array[Vector3]) -> bool:
	for old: Vector3 in used:
		if _distance(point, old) < 4.0: return true
	for property in ["world", "expeditions", "discoveries"]:
		var module: Variant = _property(property)
		if not is_instance_valid(module): continue
		var collections: Array = ["salvage", "relays", "nests"] if property == "world" else (["generators", "camps"] if property == "expeditions" else ["items"])
		var available: Dictionary = {}
		for definition: Dictionary in module.get_property_list(): available[String(definition.name)] = true
		for collection: String in collections:
			if not available.has(collection): continue
			for source: Dictionary in module.get(collection):
				var old: Vector3 = source.get("position", Vector3.INF)
				if old.is_finite() and _distance(point, old) < 3.5: return true
	return false

func _create_field(id: int, point: Vector3) -> Dictionary:
	var anchor := Node3D.new()
	anchor.name = "FiniteSalvage%d" % id
	add_child(anchor); anchor.position = point
	var steel := BattleVisuals.material(Color("687872"))
	var copper := BattleVisuals.material(Color("a38762"))
	var heap := Node3D.new(); anchor.add_child(heap); heap.name = "FiniteHeap"
	for piece in 8:
		var position := Vector3(float(piece % 3 - 1) * .46, .20 + float(piece / 3) * .18, float(piece % 2) * .48 - .24)
		var chunk := BattleVisuals.box(heap, position, Vector3(.56, .24, .43), steel if piece % 2 == 0 else copper)
		chunk.rotation.y = float(piece) * .63
	var ring := BattleVisuals.ring(anchor, Vector3(0, .07, 0), 1.04, Color("8ba57a"), .025)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var route_ring := BattleVisuals.ring(anchor, Vector3(0, .09, 0), 1.30, Color("b9d49e"), .04)
	route_ring.name = "SelectedHaulRoute"
	route_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; route_ring.visible = false
	var label := Label3D.new(); anchor.add_child(label)
	label.position = Vector3(0, 1.34, 0); label.font_size = 24; label.pixel_size = .006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED; label.outline_size = 4; label.modulate = Color("b8cba8")
	var field := {"id": id, "index": fields.size(), "node": anchor, "label": label, "heap": heap, "route_ring": route_ring, "position": point, "remaining": FIELD_STOCK, "stock": FIELD_STOCK, "claimed_by": -1}
	_refresh_field(field)
	return field

func _refresh_field(field: Dictionary) -> void:
	_refresh_field_marker(field)
	if is_instance_valid(field.heap):
		var pieces := ceili(float(field.remaining) / FIELD_STOCK * 8.0)
		for index in (field.heap as Node).get_child_count():
			(field.heap as Node).get_child(index).visible = index < pieces

func _refresh_field_marker(field: Dictionary) -> void:
	var selected := _selected_route_field(int(field.index))
	if is_instance_valid(field.label): (field.label as Label3D).text = "指定堆%d · 剩余%d" % [int(field.index) + 1, int(field.remaining)] if selected else "废料 · %d" % int(field.remaining)
	if is_instance_valid(field.get("route_ring")): (field.route_ring as Node3D).visible = selected

func _selected_route_field(index: int) -> bool:
	var squads := _squads()
	if not is_instance_valid(squads): return false
	for squad: Dictionary in squads.get("squads"):
		var id := int(squad.id)
		if String(squad.kind) != "hauler" or id not in squads.get("selected_ids") or not _teams.has(id): continue
		if not bool(_teams[id].automatic) or int(_teams[id].preferred_field) != index: continue
		for member: Variant in squad.members:
			if _living(member): return true
	return false

func _refresh_route_markers() -> void:
	for field: Dictionary in fields: _refresh_field_marker(field)

func _exit_tree() -> void:
	clear()
