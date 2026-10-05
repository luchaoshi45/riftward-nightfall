class_name ContractRouteBudget
extends RefCounted
## Presentation-only estimates. Reads authoritative sources without starting
## actions, spending rewards, changing orders, or claiming a combat duration.

static func evaluate(contract: Node, offer_index: int = -1) -> Dictionary:
	var result := _empty_budget()
	if not is_instance_valid(contract):return result
	var game: Node = contract.get("game")
	if not is_instance_valid(game) or String(contract.get("status")) != "active":return result
	if not _day_phase(game):return result
	var hero_value: Variant = game.get("hero")
	if not is_instance_valid(hero_value):return result
	var hero: Node3D = hero_value as Node3D
	if not is_instance_valid(hero) or not bool(hero.get("alive")):return result
	var selected_index: int = int(contract.get("selected_offer"))
	var index: int = selected_index if offer_index < 0 else offer_index
	var offers: Array = contract.get("offers")
	if index < 0 or index >= offers.size():return result
	var offer: Dictionary = offers[index]
	var selected: bool = index == selected_index
	var kind: String = String(contract.get("kind")) if selected else String(offer.get("kind", ""))
	var targets: Array = contract.get("targets") if selected else offer.get("targets", [])
	var done: Dictionary = contract.get("done") if selected else {}
	var remaining: Array[Dictionary] = []
	for target: Dictionary in targets:
		if selected and done.has(int(target.get("index", -1))):continue
		var source: Dictionary = target.get("source", {})
		if not _finished(kind, source):remaining.append(target)
	result.active = true
	result.remaining_targets = remaining.size()
	result.escort = kind == "escort" and not remaining.is_empty()
	result.risk = "unreachable"
	var home: Vector3 = contract.RETURN_HOME
	var clock: float = maxf(0.0, float(game.get("phase_time")))
	var reward: Dictionary = contract.get("selected_reward") if selected else offer
	var risk_seconds: float = float(reward.get("risk_seconds", 0.0))
	if risk_seconds <= 0.0:risk_seconds = float(offer.get("risk_seconds", 0.0))
	result.deadline_seconds = clock - maxf(0.0, risk_seconds) if not remaining.is_empty() else clock
	if not _walkable(game, hero.position) or not _walkable(game, home):return result
	if kind not in ["salvage", "generator", "escort", "nest"]:return result
	var hero_speed: float = maxf(1.0, float(hero.get("speed")))
	if result.escort:
		# Production escort offers contain one scout. Never silently omit a
		# second live target if a future offer changes that invariant.
		if remaining.size() != 1:return result
		return _escort_budget(contract, game, hero, remaining[0], home, hero_speed, clock, result)
	var cursor: Vector3 = hero.position
	var outbound: float = 0.0
	var work: float = 0.0
	var next_goal: Vector3 = home
	var first_leg: bool = true
	for target: Dictionary in remaining:
		var source: Dictionary = target.get("source", {})
		var point: Vector3 = source.get("position", target.get("position", Vector3.INF))
		if not _walkable(game, point):return _unreachable(result)
		var expeditions: Node = game.get("expeditions")
		# An active generator charges anywhere inside its real 3D circle.
		# Walking to its centre is not a prerequisite for remaining work.
		var holding_here: bool = first_leg and kind == "generator" and String(source.get("state", "")) == "active" and is_instance_valid(expeditions) and hero.position.distance_to(point) <= float(expeditions.HOLD_RADIUS)
		var leg: float = 0.0 if holding_here else _distance(contract, game, cursor, point)
		if not is_finite(leg):return _unreachable(result)
		if first_leg:next_goal = point;first_leg = false
		outbound += leg
		if not holding_here:cursor = point
		if kind == "generator":
			if not is_instance_valid(expeditions):return _unreachable(result)
			var hold: float = float(expeditions.HOLD_SECONDS)
			var state: String = String(source.get("state", ""))
			if state not in ["ready", "active"]:return _unreachable(result)
			work += hold if state == "ready" else maxf(0.0, hold - float(source.get("progress", 0.0)))
			var guards: int = 3 if state == "ready" else _alive_guards(source.get("guards", []))
			result.guard_count += guards
			result.combat_required = bool(result.combat_required) or guards > 0
		elif kind == "nest" and bool(game.nest_guarded(point)):
			result.combat_required = true
			result.guard_count = -1
	var returning: float = _distance(contract, game, cursor, home)
	if remaining.is_empty() and bool(contract.returned_home()):returning = 0.0
	if not is_finite(returning):return _unreachable(result)
	result.available = true
	result.next_goal = next_goal
	result.outbound_distance = outbound
	result.return_distance = returning
	result.work_seconds = work
	result.target_seconds = outbound / hero_speed + work
	result.total_seconds = float(result.target_seconds) + returning / hero_speed
	return _finish_timing(result, clock, float(contract.EARLY_RETURN_SECONDS))

static func _escort_budget(contract: Node, game: Node, hero: Node3D,
		target: Dictionary, home: Vector3, hero_speed: float, clock: float,
		result: Dictionary) -> Dictionary:
	var source: Dictionary = target.get("source", {})
	var scout_value: Variant = source.get("npc")
	if not is_instance_valid(scout_value):return _unreachable(result)
	var scout: Node3D = scout_value as Node3D
	var expeditions: Node = game.get("expeditions")
	if not is_instance_valid(scout) or not bool(scout.get("alive")):return _unreachable(result)
	if not is_instance_valid(expeditions) or not _walkable(game, scout.position):return _unreachable(result)
	var state: String = String(source.get("state", ""))
	if state not in ["waiting", "escort"]:return _unreachable(result)
	var cursor: Vector3 = hero.position
	var outbound: float = 0.0
	var next_goal: Vector3 = home
	if state == "waiting":
		cursor = source.get("position", target.get("position", Vector3.INF))
		outbound = _distance(contract, game, hero.position, cursor)
		next_goal = cursor
	var returning: float = _distance(contract, game, cursor, home)
	var scout_return: float = _distance(contract, game, scout.position, home)
	if state == "escort" and bool(contract.returned_home()):returning = 0.0
	if bool(contract.in_home_area(scout.position)):scout_return = 0.0
	if not is_finite(outbound) or not is_finite(returning) or not is_finite(scout_return):return _unreachable(result)
	var follow_speed: float = maxf(1.0, float(expeditions.FOLLOW_SPEED))
	result.available = true
	result.next_goal = next_goal
	result.outbound_distance = outbound
	result.return_distance = returning
	result.work_seconds = 0.0
	result.follow_speed = follow_speed
	# Reaching camp does not complete a rescue. The slower of the hero's and
	# scout's real remaining home routes estimates delivery, including when the
	# hero is already home. Escort ambushers are not a delivery prerequisite.
	result.target_seconds = outbound / hero_speed + maxf(returning / hero_speed, scout_return / follow_speed)
	result.total_seconds = result.target_seconds
	return _finish_timing(result, clock, float(contract.EARLY_RETURN_SECONDS))

static func _finish_timing(result: Dictionary, clock: float, early_seconds: float) -> Dictionary:
	result.deadline_spare_seconds = float(result.deadline_seconds) - float(result.target_seconds)
	result.spare_seconds = clock - float(result.total_seconds)
	var least_spare: float = minf(float(result.deadline_spare_seconds), float(result.spare_seconds))
	result.risk = "late" if least_spare < 0.0 else ("tight" if least_spare < early_seconds else "ready")
	return result

static func _day_phase(game: Node) -> bool:
	var phase: String = String(game.get("phase"))
	if phase == "day":return true
	if phase == "paused":return String(game.get("paused_from")) == "day"
	if phase == "draft":return String(game.get("return_phase")) == "day"
	return false

static func _walkable(game: Node, point: Vector3) -> bool:
	return point.is_finite() and bool(game.outpost_walkable(point))

static func _distance(contract: Node, game: Node, from: Vector3, to: Vector3) -> float:
	if not _walkable(game, from) or not _walkable(game, to):return INF
	return float(contract.route_distance(from, to))

static func _finished(kind: String, source: Dictionary) -> bool:
	match kind:
		"salvage":return bool(source.get("collected", false))
		"generator":return String(source.get("state", "")) == "complete"
		"escort":return String(source.get("state", "")) == "delivered"
		"nest":return bool(source.get("cleansed", false))
	return false

static func _alive_guards(guards: Array) -> int:
	var count: int = 0
	for guard in guards:
		# Completed enemies may remain in the site's list after queue_free.
		# Validate before a typed assignment or any property access.
		if is_instance_valid(guard) and guard is Node and bool(guard.get("alive")):count += 1
	return count

static func _empty_budget() -> Dictionary:
	return {"active": false, "available": false, "next_goal": Vector3.INF,
		"outbound_distance": INF, "return_distance": INF, "work_seconds": 0.0,
		"target_seconds": INF, "total_seconds": INF, "deadline_seconds": 0.0,
		"deadline_spare_seconds": -INF, "spare_seconds": -INF, "risk": "inactive",
		"combat_required": false, "guard_count": 0, "escort": false, "remaining_targets": 0,
		"follow_speed": 0.0}

static func _unreachable(result: Dictionary) -> Dictionary:
	result.available = false
	result.next_goal = Vector3.INF
	result.outbound_distance = INF
	result.return_distance = INF
	result.target_seconds = INF
	result.total_seconds = INF
	result.deadline_spare_seconds = -INF
	result.spare_seconds = -INF
	result.risk = "unreachable"
	return result

static func travel_text(budget: Dictionary) -> String:
	if not bool(budget.get("active", false)):return ""
	if not bool(budget.get("available", false)):return "目标或返家路线不可达"
	# The centre-to-centre routes estimate travel; actual interaction and home
	# checks accept a radius, so this is not a strict minimum-duration promise.
	return "预计往返%d秒 · 导航行程%.0f米" % [maxi(0, ceili(float(budget.total_seconds))),
		float(budget.outbound_distance) + float(budget.return_distance)]

static func timing_text(budget: Dictionary) -> String:
	if not bool(budget.get("active", false)):return ""
	if not bool(budget.get("available", false)):return "无法估算主委托行程"
	var target_spare: int = floori(float(budget.deadline_spare_seconds))
	var home_spare: int = floori(float(budget.spare_seconds))
	if int(budget.remaining_targets) == 0:
		return "日落前难返家 · 主委托保底保留" if home_spare < 0 else "主目标已完成 · 返家整备余%d秒" % home_spare
	if target_spare < 0:return "目标截止有风险 · 预计返家余%d秒" % home_spare
	if home_spare < 0:return "目标截止余%d秒 · 日落前难返家" % target_spare
	return "目标截止余%d秒 · 返家整备余%d秒%s" % [target_spare, home_spare,
		" · 时间紧" if String(budget.risk) == "tight" else ""]

static func condition_text(budget: Dictionary) -> String:
	if not bool(budget.get("active", false)):return ""
	if not bool(budget.get("available", false)):return "估时不含战斗 · 请先恢复通路"
	if bool(budget.escort):return "估时不含战斗 · 哨兵%.1f米/秒" % float(budget.get("follow_speed", 0.0))
	var guards: int = int(budget.guard_count)
	var work: float = float(budget.work_seconds)
	var conditions: Array[String] = ["估时不含战斗"]
	if work > 0.0:conditions.append("守圈剩%.1f秒" % work)
	if bool(budget.combat_required):conditions.append("需清巢边守卫" if guards < 0 else "需清%d名守卫" % guards)
	return " · ".join(conditions)
