extends RefCounted
## Run-local paid maintenance. Orders retain the real roster dictionary and
## this generation's scene identity; neither indices nor old ruins are tokens.
const Grid := preload("res://scripts/construction_grid.gd")
const Catalog := preload("res://scripts/outpost_catalog.gd")
const INTERVAL := 1.0
const BASE_COST := 5
const RESTORE := 25.0

var game: Node3D
var _world: Node3D
var _districts: Node3D
var _construction: Node3D
var _orders: Array[Dictionary] = []
var _epoch := 0
var _next_order := 0

func setup(owner_game: Node3D) -> void:
	clear()
	if not _valid_node(owner_game): return
	game = owner_game
	_world = game.get("world") as Node3D
	_districts = game.get("districts") as Node3D
	_construction = game.get("construction") as Node3D

func clear() -> void:
	_epoch += 1
	_orders.clear()
	game = null
	_world = null
	_districts = null
	_construction = null

func quote_at(point: Vector3) -> Dictionary:
	var result := Grid.placement(point, "tower")
	result.merge({"valid": false, "space_valid": false, "tech_valid": true, "missing": [],
		"cost": 0, "kind": "tower", "title": "维修", "hp": 0.0, "max_hp": 0.0,
		"repairing": false, "target_type": "", "target_index": -1, "cell_states": [],
		"reason": "请指向受损建筑 · 灯塔仍用F修复"}, true)
	if not _context_valid() or not point.is_finite(): return result
	result.cost = _cost()
	if _mode() != 1:
		result.reason = "暂停或选卡时不能切换维修"
		return result
	for target_type: String in ["tower", "district"]:
		var roster := _roster(target_type)
		for index in roster.size():
			var target := _target(target_type, index)
			if target.is_empty(): continue
			var kind := _kind(target_type, target)
			var center: Vector3 = target.position
			if not _contains(point, center, kind): continue
			result.merge(Grid.placement(center, kind), true)
			var repairing := not _order_for(target_type, index, target).is_empty()
			var hp := float(target.hp)
			var max_hp := float(target.max_hp)
			var title := String(Catalog.building(kind).get("title", "建筑"))
			var damaged := hp < max_hp
			var cost := int(result.cost)
			var reason := "每秒%d零件 · 最多25耐久 · 末次仍整价" % cost
			if not damaged and not repairing: reason = "建筑耐久已满"
			elif int(game.scrap) < cost: reason = "待零件 · 每秒%d零件/最多25耐久 · 末次整价" % cost
			result.merge({"valid": damaged or repairing, "space_valid": true, "kind": kind,
				"title": title, "hp": hp, "max_hp": max_hp, "repairing": repairing,
				"target_type": target_type, "target_index": index, "reason": reason}, true)
			return result
	return result

func toggle_at(point: Vector3) -> bool:
	# Resolve the current world again; a preview is never payment or identity
	# authority. Enabling an unaffordable order does not consume any resource.
	var quote := quote_at(point)
	if not bool(quote.valid): return false
	var target_type := String(quote.target_type)
	var index := int(quote.target_index)
	var target := _target(target_type, index)
	if target.is_empty(): return false
	var previous := _order_for(target_type, index, target)
	if not previous.is_empty():
		_remove_order(previous)
		return true
	if float(target.hp) >= float(target.max_hp): return false
	# Discard stale bindings at this index before starting a new generation.
	stop(target_type, index)
	var node: Node3D = target.node as Node3D
	var model: Node3D = target.get("turret" if target_type == "tower" else "model") as Node3D
	_next_order += 1
	_orders.append({"target_type": target_type, "target_index": index,
		"identity": target, "node": weakref(node), "model": weakref(model),
		"node_token": int(node.get_instance_id()), "model_token": int(model.get_instance_id()),
		"order": _next_order, "elapsed": 0.0})
	return true

func stop(target_type: String, index: int) -> void:
	for row in range(_orders.size() - 1, -1, -1):
		var order: Dictionary = _orders[row]
		if String(order.target_type) == target_type and int(order.target_index) == index:
			_orders.remove_at(row)

func stop_type(target_type: String) -> void:
	for row in range(_orders.size() - 1, -1, -1):
		if String(_orders[row].target_type) == target_type: _orders.remove_at(row)

func snapshot() -> Dictionary:
	var targets: Array[Dictionary] = []
	if not _context_valid() or _mode() < 0: return {"targets": targets}
	for order: Dictionary in _orders:
		var target := _bound_target(order)
		if target.is_empty() or float(target.hp) >= float(target.max_hp): continue
		var cost := _cost()
		var waiting := int(game.scrap) < cost
		targets.append({"point": target.position,
			"title": String(Catalog.building(_kind(String(order.target_type), target)).get("title", "建筑")),
			"status": "waiting" if waiting else "repairing", "target_type": String(order.target_type),
			"target_index": int(order.target_index), "elapsed": 0.0 if waiting else float(order.elapsed), "cost": cost})
	return {"targets": targets}

func tick(delta: float) -> void:
	var mode := _mode()
	if mode < 0:
		clear()
		return
	if mode == 0 or not is_finite(delta) or delta <= 0.0: return
	var epoch := _epoch
	var rows: Array[Dictionary] = _orders.duplicate()
	var blocked: Dictionary = {}
	var remaining := delta
	# Visit events by their actual due time. Equal-time events preserve enabling
	# order, so a long tick has the same wallet competition as shorter ticks.
	while true:
		if epoch != _epoch: return
		mode = _mode()
		if mode < 0:
			clear()
			return
		if mode == 0: return
		var eligible: Array[Dictionary] = []
		var next_due := INTERVAL
		for order: Dictionary in rows:
			if not _present(order): continue
			var target := _bound_target(order)
			if target.is_empty() or float(target.hp) >= float(target.max_hp):
				_remove_order(order)
				continue
			if blocked.has(int(order.order)) or int(game.scrap) < _cost():
				order.elapsed = 0.0
				blocked[int(order.order)] = true
				continue
			var elapsed := float(order.elapsed)
			if not is_finite(elapsed) or elapsed < 0.0: elapsed = 0.0
			order.elapsed = minf(INTERVAL, elapsed)
			eligible.append(order)
			next_due = minf(next_due, INTERVAL - float(order.elapsed))
		if eligible.is_empty() or remaining <= 0.0: return
		var step := minf(remaining, next_due)
		for order: Dictionary in eligible:
			var needed := INTERVAL - float(order.elapsed)
			order.elapsed = INTERVAL if step >= needed else float(order.elapsed) + step
		remaining = maxf(0.0, remaining - step)
		if step < next_due: return
		for order: Dictionary in eligible:
			if epoch != _epoch: return
			mode = _mode()
			if mode < 0:
				clear()
				return
			if mode == 0: return
			if not _present(order): continue
			var target := _bound_target(order)
			if target.is_empty() or float(target.hp) >= float(target.max_hp):
				_remove_order(order)
				continue
			# Every receipt reads the latest workshop price, wallet and HP. A
			# shortage clears all elapsed credit; no debt survives this tick.
			var cost := _cost()
			if int(game.scrap) < cost:
				order.elapsed = 0.0
				blocked[int(order.order)] = true
				continue
			if float(order.elapsed) < INTERVAL: continue
			game.scrap -= cost
			target.hp = minf(float(target.max_hp), float(target.hp) + RESTORE)
			order.elapsed = 0.0
			if float(target.hp) >= float(target.max_hp): _remove_order(order)
			_refresh_target(String(order.target_type), int(order.target_index), target)
			if epoch != _epoch: return

func _refresh_target(target_type: String, index: int, target: Dictionary) -> void:
	if target_type == "district":
		_districts.call("_refresh_label", index)
	else:
		var ring: Variant = target.get("damage_ring")
		if _valid_node(ring): ring.visible = float(target.hp) < float(target.max_hp) * .6

func _present(order: Dictionary) -> bool:
	for current: Dictionary in _orders:
		if is_same(current, order): return true
	return false

func _remove_order(order: Dictionary) -> void:
	for row in range(_orders.size() - 1, -1, -1):
		if is_same(_orders[row], order):
			_orders.remove_at(row)
			return

func _order_for(target_type: String, index: int, target: Dictionary) -> Dictionary:
	for order: Dictionary in _orders:
		if String(order.target_type) != target_type or int(order.target_index) != index: continue
		if is_same(order.identity, target) and not _bound_target(order).is_empty(): return order
	return {}

func _bound_target(order: Dictionary) -> Dictionary:
	var target_type := String(order.target_type)
	var target := _target(target_type, int(order.target_index))
	if target.is_empty() or not is_same(target, order.identity): return {}
	var node: Node3D = target.node as Node3D
	var model: Node3D = target.get("turret" if target_type == "tower" else "model") as Node3D
	if int(node.get_instance_id()) != int(order.node_token) or int(model.get_instance_id()) != int(order.model_token): return {}
	if (order.node as WeakRef).get_ref() != node or (order.model as WeakRef).get_ref() != model: return {}
	return target

func _target(target_type: String, index: int) -> Dictionary:
	var roster := _roster(target_type)
	if index < 0 or index >= roster.size() or not roster[index] is Dictionary: return {}
	var target: Dictionary = roster[index]
	if bool(target.get("removed", false)) or int(target.get("level", 0)) <= 0: return {}
	var hp := float(target.get("hp", 0.0))
	var max_hp := float(target.get("max_hp", 0.0))
	if not is_finite(hp) or not is_finite(max_hp) or hp <= 0.0 or max_hp <= 0.0: return {}
	var point: Variant = target.get("position")
	if not point is Vector3 or not point.is_finite(): return {}
	var kind := _kind(target_type, target)
	if Catalog.building(kind).is_empty() or (target_type == "district" and kind == "tower"): return {}
	if not _valid_node(target.get("node")) or not _valid_node(target.get("turret" if target_type == "tower" else "model")): return {}
	return target

func _roster(target_type: String) -> Array:
	if not _context_valid(): return []
	var rows: Variant = _world.get("tower_pads") if target_type == "tower" else _districts.get("plots") if target_type == "district" else null
	return rows if rows is Array else []

func _kind(target_type: String, target: Dictionary) -> String:
	return "tower" if target_type == "tower" else String(target.get("kind", ""))

func _contains(point: Vector3, center: Vector3, kind: String) -> bool:
	var half: Vector2 = _construction.call("footprint", kind)
	return absf(point.y - center.y) <= 1.0 and Rect2(Vector2(center.x, center.z) - half, half * 2.0).has_point(Vector2(point.x, point.z))

func _cost() -> int:
	return maxi(0, int(_districts.call("repair_cost", BASE_COST)))

func _context_valid() -> bool:
	return _valid_node(game) and _valid_node(_world) and _valid_node(_districts) and _valid_node(_construction) \
		and game.get("world") == _world and game.get("districts") == _districts and game.get("construction") == _construction

func _mode() -> int:
	if not _context_valid() or bool(game.get("quitting")) or bool(game.get("restart_pending")): return -1
	var phase := String(game.get("phase"))
	if phase in ["day", "night"]: return 1
	return 0 if phase in ["paused", "draft"] else -1

func _valid_node(value: Variant) -> bool:
	return is_instance_valid(value) and value is Node3D and not value.is_queued_for_deletion()
