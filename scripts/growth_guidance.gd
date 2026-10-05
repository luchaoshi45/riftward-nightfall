extends RefCounted
## Read-only suggestions from the current run budget. Reading never spends,
## queues cards, selects a tower branch, or requests a navigation path.
const Layout := preload("res://scripts/outpost_layout.gd")

static func snapshot(game: Node3D) -> Dictionary:
	var memory_cost: int = game.run.memory_cost()
	var memory: Dictionary = {
		"pending": int(game.run.pending),
		"cost": memory_cost,
		"balance": int(game.scrap),
		"shortfall": maxi(0, memory_cost - int(game.scrap)),
		"available": game.run.has_available_upgrade(),
	}
	var candidates: Array[Dictionary] = []
	for index in range(game.world.tower_pads.size()):
		var pad: Dictionary = game.world.tower_pads[index]
		var level: int = int(pad.get("level", 0))
		var alive: bool = level > 0 and float(pad.get("hp", 0.0)) > 0.0
		if level == 0:
			var placement: Dictionary = game.construction.validity(pad.position, index)
			if bool(placement.space_valid):
				candidates.append(_candidate(game, pad, index, "build",
					game.districts.tower_cost(game.TOWER_COSTS[0]), "F", 3,
					"增加自动火力，拦截附近敌人"))
		elif alive and level in [1, 2]:
			# Production adds 17 base damage and 1.5 m range per level;
			# its shot interval falls by 0.18 s before branch modifiers.
			# Upgrade also restores durability to the new level's maximum.
			candidates.append(_candidate(game, pad, index, "upgrade",
				game.districts.tower_cost(game.TOWER_COSTS[level]), "F",
				0 if _south_gate(pad) else 1,
				"基础伤害+17 · 射程+1.5米 · 射击更快，修满耐久"))
		if alive and level >= 2 and game.specializations.branch(pad) == "standard":
			# Workshop discounts do not apply to the mutually exclusive
			# branch choice. The suggestion leaves J/K to the player.
			candidates.append(_candidate(game, pad, index, "specialize",
				game.specializations.COST, "J/K", 2,
				"J 重敌破甲 / K 群体牵制，二选一"))
	var place_cost: int = game.districts.tower_cost(game.TOWER_COSTS[0])
	var place_shortfall: int = maxi(0, place_cost - int(game.scrap))
	candidates.append({"index": -1, "label": "城内空地", "action": "place", "target_level": 1,
		"cost": place_cost, "shortfall": place_shortfall, "affordable": place_shortfall == 0,
		"key": "Y", "benefit": "进入放置模式，选择城内空地建塔", "_priority": 4, "_distance": 0.0})
	candidates.sort_custom(_before)
	var selected: Dictionary = candidates[0]
	selected.erase("_priority")
	selected.erase("_distance")
	return {"tower": selected, "memory": memory}

static func _candidate(game: Node3D, pad: Dictionary, index: int,
		action: String, cost: int, key: String, priority: int, benefit: String) -> Dictionary:
	var shortfall: int = maxi(0, cost - int(game.scrap))
	var distance: float = 0.0
	if is_instance_valid(game.hero):
		distance = game.hero.position.distance_squared_to(pad.position)
	return {
		"index": index, "label": _label(pad, index), "action": action,
		"target_level": int(pad.level) + 1 if action == "upgrade" else 1,
		"cost": cost, "shortfall": shortfall, "affordable": shortfall == 0,
		"key": key, "benefit": benefit,
		"_priority": priority, "_distance": distance,
	}

static func _before(a: Dictionary, b: Dictionary) -> bool:
	if bool(a.affordable) != bool(b.affordable):
		return bool(a.affordable)
	if not bool(a.affordable) and int(a.shortfall) != int(b.shortfall):
		return int(a.shortfall) < int(b.shortfall)
	if int(a._priority) != int(b._priority):
		return int(a._priority) < int(b._priority)
	if float(a._distance) != float(b._distance):
		return float(a._distance) < float(b._distance)
	return int(a.index) < int(b.index)

static func _south_gate(pad: Dictionary) -> bool:
	var point: Vector3 = pad.position
	return String(pad.get("zone", "outer")) != "core" \
		and point.z > Layout.FORT_INNER - 4.0 and point.z > absf(point.x)

static func _label(pad: Dictionary, index: int) -> String:
	var point: Vector3 = pad.position
	if String(pad.get("zone", "outer")) == "core":
		var direction: String
		if absf(point.x) > 1.0 and absf(point.z) > 1.0:
			direction = ("东" if point.x >= 0.0 else "西") + ("南" if point.z >= 0.0 else "北")
		elif absf(point.x) >= absf(point.z):
			direction = "东" if point.x >= 0.0 else "西"
		else:
			direction = "南" if point.z >= 0.0 else "北"
		return "核心%s塔" % direction
	if _south_gate(pad):
		return "南门东塔" if point.x >= 0.0 else "南门西塔"
	var quadrant: String = ("东" if point.x >= 0.0 else "西") \
		+ ("南" if point.z >= 0.0 else "北")
	return "%s城内塔%d" % [quadrant, index + 1]
