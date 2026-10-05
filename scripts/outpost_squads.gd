extends Node3D
## Small defensive squads, using the existing minion placeholder asset.
## Controller hooks: advance once per simulation frame; after enemy.tick call
## intercept_enemy before normal targeting. on_day/on_night never resurrect.
## setup(controller, false) enables shields only; true also enables ranged.

const UnitScript = preload("res://scripts/unit.gd")
const MAX_SQUADS := 2
const MEMBERS_PER_SQUAD := 3
const HIRE_COST := {"shield": 70, "ranged": 80}
const REPLACE_COST := {"shield": 22, "ranged": 26}
const HOLD := "hold"
const RECALL := "recall"

var game: Node3D
var ranged_enabled := false
var health_multiplier := 1.0
var squads: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var _intercepts: Dictionary = {}

func setup(controller: Node3D, allow_ranged: bool = false) -> void:
	clear()
	game = controller
	ranged_enabled = allow_ranged
	health_multiplier = 1.0

func set_health_multiplier(value: float) -> void:
	var next := clampf(value, 0.5, 3.0)
	if is_equal_approx(next, health_multiplier): return
	for squad in squads:
		for soldier: BattleUnit in squad.members:
			if not _living(soldier): continue
			var ratio := clampf(soldier.hp / maxf(1.0, soldier.max_hp), 0.0, 1.0)
			soldier.max_hp = _base_max_hp(str(squad.kind)) * next
			soldier.hp = soldier.max_hp * ratio
	health_multiplier = next

func _base_max_hp(kind: String) -> float:
	return 200.0 if kind == "shield" else 110.0

func _active() -> bool:
	return is_instance_valid(game) and str(game.get("phase")) in ["day", "night"]

func _result(ok: bool, reason: String, cost: int = 0, squad_id: int = -1) -> Dictionary:
	return {"ok": ok, "reason": reason, "cost": cost, "squad_id": squad_id,
		"scrap": int(game.get("scrap")) if is_instance_valid(game) else 0}

func hire(kind: String) -> Dictionary:
	if not _active(): return _result(false, "暂停或选卡时不能招募")
	if not HIRE_COST.has(kind): return _result(false, "未知兵种")
	if kind == "ranged" and not ranged_enabled: return _result(false, "弩手尚未开放")
	if squads.size() >= MAX_SQUADS: return _result(false, "最多两支小队；伤亡请在白昼补员")
	var cost := int(HIRE_COST[kind])
	if int(game.get("scrap")) < cost: return _result(false, "零件不足")
	var id := squads.size()
	var members: Array[BattleUnit] = []
	var initial_order := RECALL if str(game.get("phase")) == "day" else HOLD
	var squad := {"id": id, "kind": kind, "order": initial_order, "members": members}
	game.set("scrap", int(game.get("scrap")) - cost)
	squads.append(squad)
	for slot in MEMBERS_PER_SQUAD: members.append(_spawn_member(squad, slot))
	return _result(true, "盾卫小队抵达" if kind == "shield" else "弩手小队抵达", cost, id)

func _spawn_member(squad: Dictionary, slot: int) -> BattleUnit:
	var soldier := UnitScript.new() as BattleUnit
	add_child(soldier)
	soldier.setup("minion", 0)
	soldier.name = "Outpost_%s_%d_%d" % [squad.kind, squad.id, slot]
	soldier.set_meta("outpost_squad", true)
	soldier.set_meta("squad_kind", squad.kind)
	soldier.title = "盾卫" if squad.kind == "shield" else "弩手"
	soldier.max_hp = _base_max_hp(squad.kind) * health_multiplier
	soldier.hp = soldier.max_hp
	soldier.armor = 25.0 if squad.kind == "shield" else 0.0
	soldier.damage = 10.0 if squad.kind == "shield" else 16.0
	soldier.attack_range = 2.7 if squad.kind == "shield" else 8.6
	soldier.attack_interval = 1.45 if squad.kind == "shield" else 1.65
	soldier.speed = 3.6
	soldier.windup_duration = .18 if squad.kind == "shield" else .26
	soldier.visual.scale *= .85
	soldier.selection.visible = true
	soldier.position = _station(squad, slot, RECALL)
	soldier.defeated.connect(_on_member_defeated)
	return soldier

func _station(squad: Dictionary, slot: int, order: String) -> Vector3:
	var x := (float(slot) - 1.0) * 1.6
	var z := 3.9 + float(squad.id) * .9
	if order == HOLD:
		z = (13.4 - float(squad.id) * 2.3) if squad.kind == "shield" else (5.0 + float(squad.id) * .85)
	var point := Vector3(x, 0, z)
	point.y = _ground_height(point)
	return point

func _ground_height(point: Vector3) -> float:
	var world: Node = game.get("world") as Node
	if is_instance_valid(world) and world.has_method("hero_walk_height"):
		return float(world.call("hero_walk_height", point))
	if game.has_method("outpost_height"): return float(game.call("outpost_height", point))
	if is_instance_valid(world) and world.has_method("terrain_height"):
		return float(world.call("terrain_height", point))
	return point.y

func _traversable(from: Vector3, to: Vector3) -> bool:
	return not game.has_method("can_traverse") or bool(game.call("can_traverse", from, to))

func _ground_distance(a: Vector3, b: Vector3) -> float:
	# Combat spacing follows the walkable plane. Raised terrain can put two
	# units more than a metre apart vertically while they are still adjacent on
	# the ramp; Vector3 distance would make guards fail to intercept at the gate.
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func set_order(order: String, squad_id: int = -1) -> Dictionary:
	if not _active(): return _result(false, "暂停或选卡时不能指挥")
	if order not in [HOLD, RECALL]: return _result(false, "未知小队命令")
	if squad_id < -1 or squad_id >= squads.size(): return _result(false, "没有这支小队")
	for squad in squads:
		if squad_id >= 0 and int(squad.id) != squad_id: continue
		_set_squad_order(squad, order)
	return _result(true, "小队驻守南门" if order == HOLD else "小队撤回灯塔", 0, squad_id)

func _set_squad_order(squad: Dictionary, order: String) -> void:
	squad.order = order
	for soldier: BattleUnit in squad.members:
		if not _living(soldier): continue
		soldier.target = null
		soldier.attack_queued = false
		soldier.attack_windup = 0.0

func on_day() -> void:
	_cancel_intercepts()
	for squad in squads: _set_squad_order(squad, RECALL)

func on_night() -> void:
	_cancel_intercepts()
	for squad in squads: _set_squad_order(squad, HOLD)

func refill(squad_id: int = -1) -> Dictionary:
	if not _active() or str(game.get("phase")) != "day": return _result(false, "只能在白昼付费补员休整")
	if squad_id < -1 or squad_id >= squads.size(): return _result(false, "没有这支小队")
	var cost := refill_cost(squad_id)
	if cost <= 0: return _result(false, "小队无需补员休整")
	if int(game.get("scrap")) < cost: return _result(false, "零件不足")
	game.set("scrap", int(game.get("scrap")) - cost)
	for squad in squads:
		if squad_id >= 0 and int(squad.id) != squad_id: continue
		for slot in MEMBERS_PER_SQUAD:
			var soldier: BattleUnit = squad.members[slot]
			if _living(soldier): soldier.hp = soldier.max_hp
			else:
				_retire_member(soldier)
				squad.members[slot] = _spawn_member(squad, slot)
	return _result(true, "小队补员休整完成", cost, squad_id)

func refill_cost(squad_id: int = -1) -> int:
	if squad_id < -1 or squad_id >= squads.size(): return 0
	var cost := 0
	for squad in squads:
		if squad_id >= 0 and int(squad.id) != squad_id: continue
		for soldier: BattleUnit in squad.members:
			if not _living(soldier): cost += int(REPLACE_COST[squad.kind])
			elif soldier.hp < soldier.max_hp:
				cost += ceili((soldier.max_hp - soldier.hp) / soldier.max_hp * 10.0)
	return cost

func advance(delta: float, active: bool = true) -> void:
	if not active or not _active(): return
	var elapsed := maxf(0.0, delta)
	for key in _intercepts.keys():
		var enemy := (_intercepts[key].enemy as WeakRef).get_ref() as BattleUnit
		if not _enemy(enemy): _intercepts.erase(key)
	if elapsed <= 0.0: return
	_advance_shots(elapsed)
	for squad in squads:
		for slot in MEMBERS_PER_SQUAD:
			if not _active(): return # A real kill can open the production card UI.
			var soldier: BattleUnit = squad.members[slot]
			if not _living(soldier): continue
			soldier.tick(elapsed)
			var station := _station(squad, slot, squad.order)
			var direction := station - soldier.position
			direction.y = 0
			soldier.moving = direction.length() > .12
			if soldier.moving:
				var next := soldier.position + direction.normalized() * minf(direction.length(), soldier.speed * elapsed)
				next.y = _ground_height(next)
				if _traversable(soldier.position, next): soldier.position = next
				soldier.face(station, elapsed)
				soldier.attack_queued = false; soldier.target = null
			elif squad.order == HOLD: _attack(soldier, elapsed)
			else: soldier.attack_queued = false; soldier.target = null
			_animate_member(soldier)

func _attack(soldier: BattleUnit, delta: float) -> void:
	if soldier.attack_queued:
		if not _enemy(soldier.target) or not _in_range(soldier, soldier.target):
			soldier.attack_queued = false; soldier.target = null
			return
		soldier.face(soldier.target.position, delta)
		if soldier.attack_windup > 0.0: return
		var victim := soldier.target
		var impact := victim.position + Vector3.UP
		soldier.attack_queued = false; soldier.attack_timer = soldier.attack_interval
		soldier.attack_pose = 1.0
		victim.hurt(soldier.damage, soldier) # Never source hero or mark a player attack.
		if str(soldier.get_meta("squad_kind")) == "ranged": _beam(soldier.position + Vector3.UP, impact)
		return
	if soldier.attack_timer > 0.0: return
	var target := _pick_enemy(soldier)
	if not is_instance_valid(target): return
	soldier.target = target
	soldier.attack_queued = true
	soldier.attack_windup = soldier.windup_duration
	soldier.face(target.position, delta)

func _pick_enemy(soldier: BattleUnit) -> BattleUnit:
	var focus: Variant = game.get("focus_target")
	if _enemy(focus) and float(game.get("focus_time")) > 0.0 and _in_range(soldier, focus as BattleUnit): return focus as BattleUnit
	var selected: BattleUnit
	var score := -INF
	for candidate: Variant in game.get("enemies"):
		# The production list is pruned next simulation frame, after queue_free.
		if not _enemy(candidate): continue
		var enemy := candidate as BattleUnit
		if not _in_range(soldier, enemy): continue
		var candidate_score := -_ground_distance(soldier.position, enemy.position)
		if str(soldier.get_meta("squad_kind")) == "ranged":
			candidate_score += float({"breaker": 4, "sapper": 3, "light_eater": 2}.get(str(enemy.get_meta("threat", "")), 0)) * 10.0
		if candidate_score > score: selected = enemy; score = candidate_score
	return selected

func _in_range(soldier: BattleUnit, enemy: BattleUnit) -> bool:
	return _ground_distance(soldier.position, enemy.position) <= soldier.attack_range and _traversable(soldier.position, enemy.position)

func blocker_for(enemy: Variant) -> BattleUnit:
	if not _active() or str(game.get("phase")) != "night" or not _enemy(enemy): return null
	if str(enemy.get_meta("threat", "")) in ["sapper", "light_eater"]: return null
	var closest: BattleUnit
	var distance := 3.2
	for squad in squads:
		if squad.kind != "shield" or squad.order != HOLD: continue
		for soldier: BattleUnit in squad.members:
			if not _living(soldier) or soldier.moving: continue
			var separation := _ground_distance(soldier.position, enemy.position)
			if separation < distance and _traversable(enemy.position, soldier.position):
				closest = soldier; distance = separation
	return closest

func intercept_enemy(enemy: Variant, delta: float) -> bool:
	if not _enemy(enemy): return false
	var key: int = enemy.get_instance_id()
	if not _active(): return _intercepts.has(key) # An accidental paused call must not mutate combat.
	if str(game.get("phase")) != "night" or str(enemy.get_meta("threat", "")) in ["sapper", "light_eater"]:
		_cancel_enemy_intercept(enemy)
		return false
	var blocker: BattleUnit
	if _intercepts.has(key):
		blocker = (_intercepts[key].target as WeakRef).get_ref() as BattleUnit
		if not _living(blocker) or not _is_holding(blocker) or _ground_distance(blocker.position, enemy.position) > 3.5:
			blocker = null
	if not is_instance_valid(blocker): blocker = blocker_for(enemy)
	if not is_instance_valid(blocker):
		_cancel_enemy_intercept(enemy)
		return false
	if not _intercepts.has(key) or (_intercepts[key].target as WeakRef).get_ref() != blocker:
		_cancel_enemy_intercept(enemy)
		_intercepts[key] = {"enemy": weakref(enemy), "target": weakref(blocker)}
		enemy.attack_queued = false; enemy.attack_windup = 0.0
	# Intercepts bypass nightfall's normal target selector. Keep the live
	# blocker in the same metadata channel so target-side warnings follow the
	# unit that will actually receive this attack.
	enemy.set_meta("attack_target_kind", "squad")
	enemy.set_meta("attack_target_index", -1)
	enemy.set_meta("attack_target_token", blocker.get_instance_id())
	var distance: float = _ground_distance(enemy.position, blocker.position)
	enemy.face(blocker.position, delta)
	if distance > enemy.attack_range:
		enemy.attack_queued = false; enemy.attack_windup = 0.0
		var direction: Vector3 = blocker.position - enemy.position
		direction.y = 0
		# Intercepted enemies use the same live tower slow as the normal
		# movement path. Do not write the modified value back to speed: a
		# short control effect must expire without changing enemy data.
		var movement_multiplier := 1.0
		var specialization: Variant = game.get("specializations")
		if specialization != null:
			movement_multiplier = float(specialization.movement_multiplier(enemy))
		var next: Vector3 = enemy.position + direction.normalized() * minf(direction.length(), enemy.speed * movement_multiplier * maxf(0.0, delta))
		next.y = _ground_height(next)
		enemy.moving = _traversable(enemy.position, next)
		if enemy.moving: enemy.position = next
	elif enemy.attack_queued and enemy.attack_windup <= 0.0:
		enemy.moving = false; enemy.attack_queued = false
		enemy.attack_timer = enemy.attack_interval; enemy.attack_pose = 1.0
		blocker.hurt(enemy.damage, enemy)
	elif not enemy.attack_queued and enemy.attack_timer <= 0.0:
		enemy.moving = false; enemy.attack_queued = true
		enemy.windup_duration = .22 if str(enemy.get_meta("threat", "")) == "runner" else (.55 if str(enemy.get_meta("threat", "")) == "breaker" else .34)
		enemy.attack_windup = enemy.windup_duration
	return true

func _is_holding(soldier: BattleUnit) -> bool:
	for squad in squads:
		if squad.kind == "shield" and squad.order == HOLD and soldier in squad.members: return true
	return false

func _cancel_enemy_intercept(enemy: BattleUnit) -> void:
	var key := enemy.get_instance_id()
	if not _intercepts.has(key): return
	_intercepts.erase(key)
	enemy.attack_queued = false; enemy.attack_windup = 0.0
	enemy.set_meta("attack_target_kind", "")
	enemy.set_meta("attack_target_index", -1)
	enemy.set_meta("attack_target_token", -1)

func _cancel_intercepts() -> void:
	for value: Dictionary in _intercepts.values():
		var enemy := (value.enemy as WeakRef).get_ref() as BattleUnit
		if is_instance_valid(enemy): enemy.attack_queued = false; enemy.attack_windup = 0.0
	_intercepts.clear()

func intercept_target_for(enemy: BattleUnit) -> BattleUnit:
	# The normal enemy target metadata is bypassed while a shield intercept is
	# active. Expose the live blocker so the HUD can draw the same warning on
	# the unit that will actually receive the hit.
	if not is_instance_valid(enemy): return null
	var value: Variant = _intercepts.get(enemy.get_instance_id())
	if not value is Dictionary: return null
	var blocker := (value.target as WeakRef).get_ref() as BattleUnit
	return blocker if _living(blocker) and _is_holding(blocker) else null

func _enemy(unit: Variant) -> bool:
	return _living(unit) and unit.kind == "monster" and unit.team == 2

func _living(unit: Variant) -> bool:
	return is_instance_valid(unit) and unit is BattleUnit and not unit.is_queued_for_deletion() and unit.alive

func _on_member_defeated(unit: BattleUnit, _source: BattleUnit) -> void:
	# Keep empty slots, without dangling typed references after queue_free.
	for squad in squads:
		for slot in MEMBERS_PER_SQUAD:
			if squad.members[slot] == unit: squad.members[slot] = null
	unit.visible = false
	unit.queue_free()

func _retire_member(unit: BattleUnit) -> void:
	if is_instance_valid(unit) and not unit.is_queued_for_deletion(): unit.queue_free()

func _animate_member(soldier: BattleUnit) -> void:
	for label in ["LegL", "LegR"]:
		var limb := soldier.visual.find_child(label, true, false) as Node3D
		if limb: limb.rotation.x = sin(soldier.age * 8.0 + (PI if label == "LegR" else 0.0)) * (.32 if soldier.moving else .0)
	var arm := soldier.visual.find_child("ArmR", true, false) as Node3D
	if arm: arm.rotation.x = -soldier.attack_pose * .7 - (.2 if soldier.attack_queued else 0.0)

func _beam(from: Vector3, to: Vector3) -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = .035; mesh.bottom_radius = .035
	mesh.radial_segments = 6; mesh.height = maxf(.01, from.distance_to(to))
	node.mesh = mesh
	node.material_override = BattleVisuals.material(Color("efcf86"), 1.2)
	add_child(node)
	node.position = (from + to) * .5
	var direction := (to - from).normalized()
	if absf(direction.dot(Vector3.UP)) < .999: node.quaternion = Quaternion(Vector3.UP, direction)
	shots.append({"node": node, "time": .18})

func _advance_shots(delta: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		shots[i].time = maxf(0.0, float(shots[i].time) - delta)
		var node := shots[i].node as MeshInstance3D
		if not is_instance_valid(node): shots.remove_at(i); continue
		if float(shots[i].time) <= 0.0:
			node.queue_free(); shots.remove_at(i)
		else: node.scale = Vector3(maxf(.01, float(shots[i].time) / .18), 1, maxf(.01, float(shots[i].time) / .18))

func snapshot() -> Dictionary:
	var rows: Array[Dictionary] = []
	var total_alive := 0
	for squad in squads:
		var count := 0
		var hp := 0.0
		for soldier: BattleUnit in squad.members:
			if _living(soldier): count += 1; hp += soldier.hp
		total_alive += count
		rows.append({"id": squad.id, "kind": squad.kind, "order": squad.order,
			"alive": count, "capacity": MEMBERS_PER_SQUAD, "hp": hp, "refill_cost": refill_cost(squad.id)})
	return {"count": squads.size(), "max_squads": MAX_SQUADS, "alive": total_alive,
		"capacity": MAX_SQUADS * MEMBERS_PER_SQUAD, "refill_cost": refill_cost(),
		"ranged_enabled": ranged_enabled, "squads": rows}

func clear() -> void:
	_cancel_intercepts()
	for squad in squads:
		for soldier: BattleUnit in squad.members: _retire_member(soldier)
	squads.clear()
	for shot in shots:
		var node := shot.node as Node
		if is_instance_valid(node): node.queue_free()
	shots.clear()

func _exit_tree() -> void:
	_cancel_intercepts()
