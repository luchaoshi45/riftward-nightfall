extends Node3D
## One existing cache earns a finite encounter, never a second reward wallet.
const GUARD_COUNT := 2
const LEASH := 8.0
const MIN_ROUTE := 30.0
const MAX_ROUTE := 90.0
const RETURN_POINT := Vector3(0, 5, 4.6)
const HOME_RADIUS := 2.4
const HEIGHT_LIMIT := .9

var game: Node3D
var discoveries: Node3D
var _binding: Dictionary = {}
var _units: Dictionary = {}
var _navigation := AStarGrid2D.new()
var _navigation_signature := 0
var _day_open := false
var _deployment_day := -1

func setup(owner_game: Node3D, owner_discoveries: Node3D) -> void:
	clear()
	game = owner_game
	discoveries = owner_discoveries

func _living(value: Variant) -> bool:
	return is_instance_valid(value) and value is BattleUnit and not value.is_queued_for_deletion() \
		and value.is_inside_tree() and value.alive and value.hp > 0.0

func _context() -> bool:
	return is_instance_valid(game) and is_instance_valid(discoveries) \
		and not game.is_queued_for_deletion() and not discoveries.is_queued_for_deletion()

func _active() -> bool:
	return _context() and String(game.get("phase")) == "day" and float(game.get("phase_time")) > 0.0 \
		and not bool(game.get("quitting")) and not bool(game.get("restart_pending")) \
		and _living(game.get("hero")) and float(game.get("beacon_hp")) > 0.0

func _distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))

func _inside(point: Vector3) -> bool:
	return not _binding.is_empty() and point.is_finite() and _distance(_binding.anchor, point) <= LEASH + .000001

func _binding_current() -> bool:
	if not _context() or _binding.is_empty(): return false
	var index := int(_binding.index)
	var items: Array = discoveries.get("items")
	if index < 0 or index >= items.size(): return false
	var item: Dictionary = items[index]
	var node: Variant = (_binding.node as WeakRef).get_ref()
	return is_same(item, _binding.source) and int(item.get("serial", -1)) == int(_binding.serial) \
		and String(item.get("kind", "")) == "supply_cache" and String(item.get("state", "")) in ["ready", "channel"] \
		and is_instance_valid(node) and node is Node3D and not node.is_queued_for_deletion() \
		and node.is_inside_tree() and item.get("node") == node and item.get("position") == _binding.anchor

func _real_guard(creature: Variant, row: Dictionary) -> bool:
	return _living(creature) and not row.is_empty() and (row.unit as WeakRef).get_ref() == creature \
		and not bool(row.killed) and not bool(row.lost) and _context() \
		and creature.get_parent() == game and creature in game.get("enemies")

func owns(creature: Variant) -> bool:
	if not is_instance_valid(creature) or not creature is BattleUnit: return false
	var row: Dictionary = _units.get(creature.get_instance_id(), {})
	return not row.is_empty() and (row.unit as WeakRef).get_ref() == creature

func _real_friendly(unit: Variant) -> bool:
	if not _living(unit) or not _context(): return false
	if absf(unit.position.y - float(game.call("outpost_height", unit.position))) > HEIGHT_LIMIT: return false
	if unit == game.get("hero"): return unit.get_parent() == game
	var roster: Variant = game.get("squads")
	if not is_instance_valid(roster) or unit.get_parent() != roster: return false
	for squad: Dictionary in roster.get("squads"):
		if unit in squad.members: return true
	return false

func _eligible_item(item: Dictionary) -> bool:
	var node: Variant = item.get("node")
	return String(item.get("kind", "")) == "supply_cache" and String(item.get("state", "")) == "ready" \
		and is_instance_valid(node) and node is Node3D and node.is_inside_tree() and not node.is_queued_for_deletion() \
		and bool(game.call("outpost_walkable", item.get("position", Vector3.INF)))

func begin_day() -> void:
	if not _active(): return
	var day := int(game.get("day_number"))
	if _day_open and _deployment_day == day: return
	_retire_binding()
	_day_open = true
	_deployment_day = day
	var candidates: Array[Dictionary] = []
	var items: Array = discoveries.get("items")
	for index in items.size():
		var item: Dictionary = items[index]
		if not _eligible_item(item): continue
		var route_distance := float(discoveries.call("route_distance", RETURN_POINT, item.position))
		if not is_finite(route_distance) or route_distance < MIN_ROUTE or route_distance > MAX_ROUTE: continue
		candidates.append({"index": index, "distance": route_distance})
	candidates.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return int(first.index) < int(second.index) if is_equal_approx(float(first.distance), float(second.distance)) else float(first.distance) > float(second.distance))
	for candidate: Dictionary in candidates:
		var index := int(candidate.index)
		var item: Dictionary = items[index]
		_binding = {"index": index, "source": item, "serial": int(item.serial), "node": weakref(item.node),
			"anchor": item.position, "guards": [], "killed": 0, "lost": 0, "day_active": true,
			"route_distance": float(candidate.distance), "marker": null, "label": null}
		_refresh_navigation(true)
		var homes := _guard_homes(item.position)
		if homes.size() != GUARD_COUNT:
			_binding.clear()
			continue
		var rng: RandomNumberGenerator = game.get("spawn_rng")
		var saved_state := rng.state
		var guards: Array[BattleUnit] = []
		for slot in GUARD_COUNT:
			var guard: BattleUnit = game.call("spawn_creature", false)
			if not _living(guard): break
			guards.append(guard)
			guard.position = homes[slot]
			guard.home_point = homes[slot]
			guard.title = "补给守卫"
			guard.set_meta("supply_cache_guard", true)
			guard.set_meta("cache_guard", true)
			guard.set_meta("cache_guard_index", index)
			guard.set_meta("cache_guard_serial", int(item.serial))
			guard.set_meta("cache_guard_slot", slot)
			var row := {"unit": weakref(guard), "home": homes[slot], "killed": false, "lost": false,
				"target": null, "returning": false, "slot": slot}
			_units[guard.get_instance_id()] = row
			(_binding.guards as Array).append(row)
		rng.state = saved_state
		if guards.size() != GUARD_COUNT or not _binding_current() or not _active():
			_retire_binding()
			continue
		_create_marker(item.node)
		discoveries.set("motivation_revision", int(discoveries.get("motivation_revision")) + 1)
		_refresh_marker()
		return

func _guard_homes(anchor: Vector3) -> Array[Vector3]:
	var homes: Array[Vector3] = []
	for radius in [HOME_RADIUS, 3.2, 1.7]:
		for step in 16:
			var angle := TAU * float(step) / 16.0
			var point := anchor + Vector3(cos(angle) * float(radius), 0, sin(angle) * float(radius))
			point.y = float(game.call("outpost_height", point))
			if not bool(game.call("outpost_walkable", point)) or _route(anchor, point).is_empty() or _route(point, anchor).is_empty(): continue
			if not homes.is_empty() and (_distance(homes[0], point) < 3.0 or _route(homes[0], point).is_empty() or _route(point, homes[0]).is_empty()): continue
			homes.append(point)
			if homes.size() == GUARD_COUNT: return homes
	return homes

func _refresh_navigation(force: bool = false) -> void:
	if _binding.is_empty() or not _context(): return
	var signature := hash(game.get("construction_blocks"))
	if not force and signature == _navigation_signature: return
	_navigation_signature = signature
	var anchor: Vector3 = _binding.anchor
	var left := floori(anchor.x - LEASH) - 1
	var top := floori(anchor.z - LEASH) - 1
	_navigation.region = Rect2i(left, top, 20, 20)
	_navigation.cell_size = Vector2.ONE
	_navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_navigation.update()
	for x in range(left, left + 20):
		for z in range(top, top + 20):
			var point := Vector3(x, 0, z)
			if not _inside(point) or not bool(game.call("outpost_walkable", point)):
				_navigation.set_point_solid(Vector2i(x, z))
	for row: Dictionary in _binding.guards:
		var guard: Variant = (row.unit as WeakRef).get_ref()
		if is_instance_valid(guard):
			guard.path.clear()
			guard.path_timer = 0.0

func _route_cell(point: Vector3) -> Vector2i:
	var selected := Vector2i(999, 999)
	var nearest := INF
	var origin := Vector2i(roundi(point.x), roundi(point.z))
	for x in range(origin.x - 2, origin.x + 3):
		for z in range(origin.y - 2, origin.y + 3):
			var cell := Vector2i(x, z)
			if not _navigation.is_in_boundsv(cell) or _navigation.is_point_solid(cell): continue
			var candidate := Vector3(x, 0, z)
			candidate.y = float(game.call("outpost_height", candidate))
			var separation := _distance(point, candidate)
			if separation < nearest and bool(game.call("can_traverse", point, candidate)):
				selected = cell
				nearest = separation
	return selected

func _route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var route := PackedVector3Array()
	if not _context() or not _inside(to) or not bool(game.call("outpost_walkable", to)): return route
	if bool(game.call("can_traverse", from, to)):
		route.append(to)
		return route
	var start := _route_cell(from)
	var finish := _route_cell(to)
	if start.x == 999 or finish.x == 999: return route
	var grid_route := _navigation.get_point_path(start, finish)
	if grid_route.is_empty(): return route
	var previous := from
	var points := PackedVector3Array()
	for cell: Vector2 in grid_route:
		var point := Vector3(cell.x, 0, cell.y)
		point.y = float(game.call("outpost_height", point))
		if not _inside(point) or not bool(game.call("can_traverse", previous, point)): return PackedVector3Array()
		points.append(point)
		previous = point
	if not bool(game.call("can_traverse", previous, to)): return PackedVector3Array()
	if points.is_empty() or points[points.size() - 1].distance_to(to) > .05: points.append(to)
	# The closest grid centre can sit behind a unit between cells. Smoothing
	# visible consecutive points avoids repeatedly routing backwards to it.
	var cursor := from
	var index := 0
	while index < points.size():
		var furthest := index
		for next_index in range(index, points.size()):
			if bool(game.call("can_traverse", cursor, points[next_index])): furthest = next_index
			else: break
		var waypoint := points[furthest]
		if not bool(game.call("can_traverse", cursor, waypoint)): return PackedVector3Array()
		if cursor.distance_to(waypoint) > .05: route.append(waypoint)
		cursor = waypoint
		index = furthest + 1
	if route.is_empty(): route.append(to)
	return route

func target_for(creature: BattleUnit) -> Dictionary:
	if not _active() or not _day_open or not _binding_current() or not owns(creature) or not _inside(creature.position): return {}
	var row: Dictionary = _units[creature.get_instance_id()]
	if not _real_guard(creature, row) or bool(row.returning): return {}
	var candidates: Array[BattleUnit] = []
	var hero: Variant = game.get("hero")
	if _real_friendly(hero): candidates.append(hero)
	var roster: Variant = game.get("squads")
	if is_instance_valid(roster):
		for squad: Dictionary in roster.get("squads"):
			for member: BattleUnit in squad.members:
				if _real_friendly(member): candidates.append(member)
	var selected: BattleUnit
	var nearest := INF
	for candidate: BattleUnit in candidates:
		if not _inside(candidate.position): continue
		var separation := _distance(creature.position, candidate.position)
		if separation >= nearest or _route(creature.position, candidate.position).is_empty(): continue
		selected = candidate
		nearest = separation
	if not is_instance_valid(selected): return {}
	return {"kind": "hero" if selected == hero else "squad", "index": -1,
		"token": selected.get_instance_id(), "unit": selected, "position": selected.position}

func _cancel(creature: BattleUnit) -> void:
	creature.attack_queued = false
	creature.attack_windup = 0.0
	creature.target = null
	creature.path.clear()
	creature.path_timer = 0.0

func advance(creature: BattleUnit, delta: float) -> void:
	if not owns(creature) or delta <= 0.0: return
	if not _context() or not _binding_current():
		_retire_binding()
		return
	if not _active() or not _day_open: return
	_refresh_guard_states()
	var row: Dictionary = _units.get(creature.get_instance_id(), {})
	if not _real_guard(creature, row): return
	_refresh_navigation()
	var old_target: Variant = (row.target as WeakRef).get_ref() if row.target is WeakRef else null
	if row.target != null and (not _real_friendly(old_target) or not _inside(old_target.position) or _route(creature.position, old_target.position).is_empty()):
		_cancel(creature)
		row.target = null
		row.returning = true
	if not _inside(creature.position):
		_cancel(creature)
		row.target = null
		row.returning = true
	if bool(row.returning):
		_return_home(creature, row, delta)
		return
	var selected := target_for(creature)
	if selected.is_empty():
		_cancel(creature)
		row.target = null
		_return_home(creature, row, delta)
		return
	var target: BattleUnit = selected.unit
	if old_target != target:
		_cancel(creature)
		row.target = weakref(target)
	var route := _route(creature.position, target.position)
	if route.is_empty():
		_cancel(creature)
		row.target = null
		row.returning = true
		_return_home(creature, row, delta)
		return
	# Install the bounded route before the production decision; its normal
	# cooldown, windup, attack warnings and hurt callbacks remain authoritative.
	creature.path = route
	creature.path_goal = target.position
	creature.path_timer = .45
	var previous := creature.position
	game.call("update_creature", creature, delta)
	# A real hit may synchronously finish the match and clear this module.
	if not owns(creature) or not _binding_current() or not _living(creature): return
	_limit_step(creature, previous)

func _return_home(creature: BattleUnit, row: Dictionary, delta: float) -> void:
	var home: Vector3 = row.home
	creature.moving = false
	if _distance(creature.position, home) <= .16:
		row.returning = false
		return
	row.returning = true
	var route := _route(creature.position, home)
	if route.is_empty(): return
	var target: Vector3 = route[0]
	var direction := target - creature.position
	direction.y = 0.0
	if direction.length() <= .05: return
	var previous := creature.position
	var specializations: Variant = game.get("specializations")
	var multiplier := float(specializations.call("movement_multiplier", creature)) if is_instance_valid(specializations) else 1.0
	var next := previous + direction.normalized() * minf(direction.length(), creature.speed * multiplier * delta)
	if bool(game.call("can_traverse", previous, next)):
		next.y = float(game.call("outpost_height", next))
		creature.position = next
		_limit_step(creature, previous)
	creature.face(target, delta)
	creature.moving = creature.position.distance_squared_to(previous) > .000001

func _limit_step(creature: BattleUnit, previous: Vector3) -> void:
	var anchor: Vector3 = _binding.anchor
	var allowed := maxf(LEASH, _distance(previous, anchor))
	if _distance(creature.position, anchor) <= allowed + .000001: return
	var proposed := creature.position
	var lower := 0.0
	var upper := 1.0
	for iteration in 24:
		var middle := (lower + upper) * .5
		if _distance(previous.lerp(proposed, middle), anchor) <= allowed: lower = middle
		else: upper = middle
	var limited := previous.lerp(proposed, lower)
	limited.y = float(game.call("outpost_height", limited))
	creature.position = limited if bool(game.call("can_traverse", previous, limited)) else previous
	_cancel(creature)
	var row: Dictionary = _units.get(creature.get_instance_id(), {})
	if not row.is_empty():
		row.target = null
		row.returning = true

func on_defeated(creature: BattleUnit) -> bool:
	if not is_instance_valid(creature): return false
	if not bool(creature.get_meta("supply_cache_guard", false)): return true
	var row: Dictionary = _units.get(creature.get_instance_id(), {})
	if row.is_empty() or (row.unit as WeakRef).get_ref() != creature or not _binding_current() \
		or not _day_open or not _active() or bool(row.killed) or bool(row.lost) \
		or creature.alive or creature.hp > 0.0 or creature.is_queued_for_deletion() \
		or creature.get_parent() != game or creature not in game.get("enemies"): return false
	row.killed = true
	row.target = null
	_binding.killed = int(_binding.killed) + 1
	discoveries.set("motivation_revision", int(discoveries.get("motivation_revision")) + 1)
	_refresh_marker()
	return true

func _refresh_guard_states() -> void:
	if _binding.is_empty(): return
	for row: Dictionary in _binding.guards:
		if bool(row.killed) or bool(row.lost): continue
		var guard: Variant = (row.unit as WeakRef).get_ref()
		if not _real_guard(guard, row):
			row.lost = true
			_binding.lost = int(_binding.lost) + 1
			_retire_unit(row)

func _retire_unit(row: Dictionary) -> void:
	var guard: Variant = (row.unit as WeakRef).get_ref()
	if not is_instance_valid(guard): return
	_cancel(guard)
	guard.set_meta("cache_guard_retired", true)
	# The root walks enemies by index. Retirement must not shrink that roster
	# in the middle of advance(); its ordinary dead-entry sweep owns removal.
	guard.alive = false
	guard.moving = false
	guard.visible = false
	guard.queue_free()
	_units.erase(guard.get_instance_id())

func _retire_binding() -> void:
	if not _binding.is_empty():
		for row: Dictionary in _binding.guards: _retire_unit(row)
		for field in ["marker", "label"]:
			var node: Variant = _binding.get(field)
			if is_instance_valid(node): node.queue_free()
	_binding.clear()
	_units.clear()

func on_night() -> void:
	_day_open = false
	if not _binding_current():
		_retire_binding()
		return
	_binding.day_active = false
	for row: Dictionary in _binding.guards:
		if not bool(row.killed) and not bool(row.lost):
			row.lost = true
			_binding.lost = int(_binding.lost) + 1
		_retire_unit(row)
	# An unearned cache stays locked for this exact source generation. Clearing
	# actors at sunset cannot masquerade as two defeated guards.
	_refresh_marker()

func clear() -> void:
	_retire_binding()
	_day_open = false
	_deployment_day = -1

func tick() -> void:
	if not _context(): return
	if not _binding_current():
		_retire_binding()
		return
	_refresh_guard_states()
	_refresh_marker()

func can_open(index: int) -> bool:
	if not _binding.is_empty() and not _binding_current(): _retire_binding()
	var state := snapshot(index)
	return not bool(state.blocked)

func snapshot(index: int) -> Dictionary:
	var state := {"index": index, "serial": -1, "guarded": false, "blocked": false, "remaining": 0,
		"killed": 0, "lost": 0, "cleared": false, "anchor": Vector3.INF, "day_active": false, "route_distance": INF}
	if _context():
		var items: Array = discoveries.get("items")
		if index >= 0 and index < items.size(): state.serial = int(items[index].get("serial", -1))
	if not _binding_current() or index != int(_binding.index): return state
	state.serial = int(_binding.serial)
	state.guarded = true
	state.killed = int(_binding.killed)
	state.lost = int(_binding.lost)
	state.remaining = GUARD_COUNT - int(_binding.killed)
	state.cleared = int(_binding.killed) == GUARD_COUNT
	state.blocked = not bool(state.cleared)
	state.anchor = _binding.anchor
	state.day_active = bool(_binding.day_active)
	state.route_distance = float(_binding.route_distance)
	return state

func _create_marker(parent: Node3D) -> void:
	_binding.marker = BattleVisuals.ring(parent, Vector3.UP * .15, 1.65, Color("e17b68"), .045)
	var label := Label3D.new()
	parent.add_child(label)
	label.position = Vector3(0, 3.5, 0)
	label.font_size = 24
	label.pixel_size = .008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 5
	label.modulate = Color("ffab91")
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Hiragino Sans GB", "Heiti SC", "Microsoft YaHei", "Noto Sans CJK SC"])
	font.allow_system_fallback = true
	label.font = font
	_binding.label = label

func _refresh_marker() -> void:
	if not _binding_current(): return
	var state := snapshot(int(_binding.index))
	var hero: Variant = game.get("hero")
	var nearby := _living(hero) and _distance(hero.position, _binding.anchor) < 22.0
	var visible := nearby and bool(state.blocked)
	var marker: Variant = _binding.marker
	var label: Variant = _binding.label
	if is_instance_valid(marker): marker.visible = visible
	if is_instance_valid(label):
		label.visible = visible
		label.text = "守卫 %d/2 · 清后3秒\n46零件" % int(state.remaining) if bool(state.day_active) else "日落未清 · 次日再试\n封锁 %d/2" % int(state.remaining)
