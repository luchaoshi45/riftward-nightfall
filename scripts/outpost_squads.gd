extends Node3D
## RTS编组、独立兵营训练队列、地形寻路与付费工程/医护支援。
## 主控制器每帧advance，并在enemy.tick后调用intercept_enemy。

const UnitScript = preload("res://scripts/unit.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
const Catalog := preload("res://scripts/outpost_catalog.gd")
const ArtilleryScript := preload("res://scripts/outpost_artillery.gd")
const HunterScript := preload("res://scripts/outpost_hunters.gd")
const EscortScript := preload("res://scripts/outpost_escort.gd")
const MEMBERS_PER_SQUAD := 3
const HIRE_COST := {"shield": 70, "ranged": 80, "engineer": 65, "ballista": 110, "hauler": 70, "medic": 90, "artillery": 150, "hunter": 110}
const TRAIN_TIME := {"shield": 6.0, "ranged": 8.0, "engineer": 7.0, "ballista": 10.0, "hauler": 8.0, "medic": 9.0, "artillery": 12.0, "hunter": 10.0}
const TITLES := {"shield": "盾卫", "ranged": "弩手", "engineer": "工程员", "ballista": "重弩组", "hauler": "采运工队", "medic": "医护队", "artillery": "迫击炮队", "hunter": "猎手队"}
const REPLACE_COST := {"shield": 22, "ranged": 26, "engineer": 20, "ballista": 32, "hauler": 22, "medic": 26, "artillery": 36, "hunter": 32}
const MEDIC_RANGE := 4.8
const MEDIC_HEIGHT_LIMIT := 1.0
const MEDIC_MIN_MISSING := 12.0
const MEDIC_WINDUP := .65
const MEDIC_COOLDOWN := 4.0
const MEDIC_HEAL := 36.0
const MEDIC_COST := 2
const HOLD := "hold"
const RECALL := "recall"
const MOVE := "move"
const AMOVE := "attack_move"
const ESCORT := "escort"
const ATTACK := "attack"
const GUARD := "guard"
const HAUL := "haul"

var game: Node3D
var ranged_enabled := false
var health_multiplier := 1.0
var squads: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var _intercepts: Dictionary = {}
var training_queues: Dictionary = {}
var selected_ids: Array[int] = []
var _has_logistics := false
var _has_hero := false
var _has_construction_blocks := false
var _has_rally := false
var _medic_states: Dictionary = {}
var artillery: Node3D
var hunters: Node3D
var escort: RefCounted
var _epoch := 0

func setup(controller: Node3D, allow_ranged: bool = false) -> void:
	clear()
	game = controller
	if not is_instance_valid(artillery):
		artillery = ArtilleryScript.new()
		artillery.name = "OutpostArtillery"
		add_child(artillery)
	artillery.setup(game)
	if not is_instance_valid(hunters):
		hunters = HunterScript.new()
		hunters.name = "OutpostHunters"
		add_child(hunters)
	hunters.setup(game, self)
	if not is_instance_valid(escort): escort = EscortScript.new()
	escort.setup(game, self)
	for property: Dictionary in game.get_property_list():
		if String(property.name) == "logistics": _has_logistics = true
		if String(property.name) == "hero": _has_hero = true
		if String(property.name) == "construction_blocks": _has_construction_blocks = true
		if String(property.name) == "rally": _has_rally = true
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
	return float(Catalog.troop(kind).get("hp", 110.0))

func _active() -> bool:
	return is_instance_valid(game) and str(game.get("phase")) in ["day", "night"]

func _result(ok: bool, reason: String, cost: int = 0, squad_id: int = -1) -> Dictionary:
	return {"ok": ok, "reason": reason, "cost": cost, "squad_id": squad_id,
		"scrap": int(game.get("scrap")) if is_instance_valid(game) else 0}

func _kind_allowed(kind: String) -> bool:
	return bool(training_eligibility(kind).available)

func training_eligibility(kind: String) -> Dictionary:
	# Read the live prerequisite state instead of trusting a previous HUD snapshot.
	if kind not in Catalog.TROOP_IDS:
		return {"available": false, "reason": "未知兵种", "missing": []}
	if kind == "ranged" and not ranged_enabled:
		return {"available": false, "reason": "弩手尚未开放", "missing": []}
	var requirements: Array = Catalog.troop(kind).get("requires", [])
	var districts: Node = game.get("districts") as Node if is_instance_valid(game) else null
	if is_instance_valid(districts) and districts.has_method("training_eligibility"):
		return districts.call("training_eligibility", kind)
	# Existing isolated fixtures can train basic troops without a city module.
	# Advanced troops still require explicit live technology in every entry path.
	var missing: Array[String] = []
	for required in requirements:
		if not is_instance_valid(districts) or not districts.has_method("has_live") or not bool(districts.call("has_live", String(required))):
			missing.append(String(required))
	if not missing.is_empty():
		var titles: Array[String] = []
		for required: String in missing: titles.append(String(Catalog.building(required).get("title", required)))
		return {"available": false, "reason": "需要存活%s" % "、".join(titles), "missing": missing}
	return {"available": true, "reason": "", "missing": []}

func hire(kind: String) -> Dictionary:
	# 即时工厂只供明确的低层行为用例；生产输入使用enqueue。
	if not _active(): return _result(false, "暂停或选卡时不能招募")
	var eligibility := training_eligibility(kind)
	if not bool(eligibility.available): return _result(false, String(eligibility.reason))
	var troop: Dictionary = Catalog.troop(kind)
	var cost := int(troop.cost)
	if int(game.get("scrap")) < cost: return _result(false, "零件不足")
	game.set("scrap", int(game.get("scrap")) - cost)
	var id := _create_squad(kind, Vector3(0, 5, 3.9))
	if id < 0: return _result(false, "编组生成期间场景已重置", cost)
	return _result(true, "%s编组抵达" % String(troop.title), cost, id)

func _owns_squad(squad: Dictionary, generation: int) -> bool:
	if generation != _epoch or not _active(): return false
	var id := int(squad.get("id", -1))
	return id >= 0 and id < squads.size() and is_same(squads[id], squad)

func _owns_member(soldier: BattleUnit, generation: int) -> bool:
	if generation != _epoch or not _active() or not _living(soldier): return false
	for squad: Dictionary in squads:
		if soldier in squad.members: return true
	return false

func _create_squad(kind: String, origin: Vector3) -> int:
	var generation := _epoch
	if not _active(): return -1
	var id := squads.size()
	var members: Array[BattleUnit] = []
	var initial_order := HAUL if kind == "hauler" else (RECALL if str(game.get("phase")) == "day" else HOLD)
	var squad := {"id": id, "kind": kind, "order": initial_order, "members": members,
		"destination": origin, "origin": origin, "attack_target": null, "formation_index": 0,
		"rally_pending": false, "rally_stations": [], "attack_move_stations": []}
	if kind == "medic":
		squad.merge({"therapy_enabled": false, "treatments": 0, "healed_hp": 0.0, "spent": 0})
	squads.append(squad)
	for slot in MEMBERS_PER_SQUAD:
		if not _owns_squad(squad, generation): return -1
		var soldier := _spawn_member(squad, slot)
		if not _owns_squad(squad, generation):
			_retire_member(soldier)
			return -1
		members.append(soldier)
	return id

func _barracks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(game): return result
	var districts: Node = game.get("districts") as Node
	if not is_instance_valid(districts): return result
	if districts.has_method("active_barracks"):
		for row: Dictionary in districts.call("active_barracks"): result.append(row)
	return result

func _barracks_row(id: int) -> Dictionary:
	for row in _barracks():
		if int(row.index) == id: return row
	return {}

func enqueue(kind: String, barracks_id: int = -1) -> Dictionary:
	if not _active(): return _result(false, "暂停或选卡时不能训练")
	var eligibility := training_eligibility(kind)
	if not bool(eligibility.available): return _result(false, String(eligibility.reason))
	var active_barracks := _barracks()
	if active_barracks.is_empty(): return _result(false, "先建造兵营才能生产部队")
	var chosen := barracks_id
	if chosen < 0:
		var shortest := INF
		for row in active_barracks:
			var duration := 0.0
			for item: Dictionary in training_queues.get(int(row.index), []): duration += float(item.remaining)
			if duration < shortest: shortest = duration; chosen = int(row.index)
	if _barracks_row(chosen).is_empty(): return _result(false, "该兵营无法训练")
	var troop: Dictionary = Catalog.troop(kind)
	var cost := int(troop.cost)
	if int(game.get("scrap")) < cost: return _result(false, "零件不足")
	game.set("scrap", int(game.get("scrap")) - cost)
	if not training_queues.has(chosen): training_queues[chosen] = []
	training_queues[chosen].append({"kind": kind, "title": String(troop.title), "remaining": float(troop.time), "total": float(troop.time), "cost": cost})
	var result := _result(true, "%s已加入兵营训练队列" % String(troop.title), cost)
	result.barracks_id = chosen
	return result

func cancel_training(barracks_id: int, queue_index: int = 0) -> Dictionary:
	if not _active(): return _result(false, "暂停或选卡时不能取消训练")
	var queue: Array = training_queues.get(barracks_id, [])
	if queue_index < 0 or queue_index >= queue.size(): return _result(false, "没有这项训练")
	var refund := int(queue[queue_index].cost)
	queue.remove_at(queue_index)
	game.set("scrap", int(game.get("scrap")) + refund)
	var result := _result(true, "训练已取消，零件已退还", -refund)
	result.refund = refund
	return result

func refresh_barracks() -> void:
	if _active(): _advance_training(0.0)

func _advance_training(delta: float) -> void:
	var generation := _epoch
	var duration_multiplier := 1.0
	var districts: Node = game.get("districts") as Node if is_instance_valid(game) else null
	if is_instance_valid(districts) and districts.has_method("training_duration_multiplier"):
		duration_multiplier = clampf(float(districts.call("training_duration_multiplier")), 0.8, 1.0)
	for id: int in training_queues.keys():
		if generation != _epoch or not _active() or not training_queues.has(id): return
		var queue: Array = training_queues[id]
		var row := _barracks_row(id)
		if row.is_empty():
			var refund := 0
			for item: Dictionary in queue: refund += int(item.cost)
			game.set("scrap", int(game.get("scrap")) + refund)
			training_queues.erase(id)
			continue
		# Queue remaining is stored in base training seconds. Reading the live
		# duration multiplier on every advance makes a build, upgrade, demolition
		# or same-site rebuild take effect on the next simulation frame without
		# changing the already-paid order or refund ledger.
		var budget := delta / duration_multiplier
		while not queue.is_empty() and budget > 0.0 and generation == _epoch and _active():
			var item: Dictionary = queue[0]
			var consumed := minf(budget, float(item.remaining))
			item.remaining = maxf(0.0, float(item.remaining) - consumed)
			budget -= consumed
			if float(item.remaining) > .00001: break
			queue.remove_at(0)
			var squad_id := _create_squad(str(item.kind), _resolve_destination(row.position + Vector3(0, 0, 3.0)))
			if generation != _epoch or not _active() or squad_id < 0: return
			_apply_training_rally(squad_id, id)
			if generation != _epoch or not _active(): return

func rally_spawn_points(barracks_position: Vector3) -> Array[Vector3]:
	# Match both production's exit resolution and _spawn_member's actual offsets.
	var points: Array[Vector3] = []
	var origin := _resolve_destination(barracks_position + Vector3(0, 0, 3.0))
	for slot in MEMBERS_PER_SQUAD:
		points.append(_resolve_destination(origin + Vector3((slot - 1) * 1.2, 0, 0)))
	return points

func rally_station_points(point: Vector3) -> Array[Vector3]:
	# These exact stations are validated at commit, never moved to an adjacent
	# walkable cell when a later building blocks the original destination.
	var points: Array[Vector3] = []
	if not point.is_finite(): return points
	for slot in MEMBERS_PER_SQUAD:
		var station := point + Vector3((slot - 1) * 1.25, 0, 0)
		station.y = _ground_height(station)
		points.append(station)
	return points

func _rally() -> RefCounted:
	if not _has_rally or not is_instance_valid(game): return null
	var value: Variant = game.get("rally")
	return value as RefCounted if is_instance_valid(value) and value is RefCounted else null

func _apply_training_rally(squad_id: int, barracks_id: int) -> void:
	var generation := _epoch
	if squad_id < 0 or squad_id >= squads.size(): return
	var squad: Dictionary = squads[squad_id]
	if not _owns_squad(squad, generation): return
	var rally := _rally()
	if not is_instance_valid(rally) or not rally.has_method("destination_for"): return
	var destination: Dictionary = rally.call("destination_for", barracks_id)
	if not _owns_squad(squad, generation): return
	if not bool(destination.get("enabled", false)): return
	var point: Variant = destination.get("point")
	if not point is Vector3 or not (point as Vector3).is_finite(): return
	var stations := rally_station_points(point)
	if stations.size() != MEMBERS_PER_SQUAD or not _owns_squad(squad, generation): return
	# Only this newly completed squad changes order. Haulers deliberately stop
	# automatic logistics here, and the medic's default disabled switch is kept.
	_set_squad_order(squad, MOVE)
	if not _owns_squad(squad, generation): return
	squad.destination = point
	squad.formation_index = 0
	squad.rally_stations = stations
	squad.rally_pending = true

func _spawn_member(squad: Dictionary, slot: int) -> BattleUnit:
	var generation := _epoch
	if not _owns_squad(squad, generation): return null
	var soldier := UnitScript.new() as BattleUnit
	add_child(soldier)
	# SceneTree node_added/child_entered_tree are synchronous. The fresh unit
	# is not yet in squad.members, so clear cannot retire it on our behalf.
	if not _owns_squad(squad, generation):
		_retire_member(soldier)
		return null
	soldier.setup("minion", 0)
	if not _owns_squad(squad, generation):
		_retire_member(soldier)
		return null
	soldier.name = "Outpost_%s_%d_%d" % [squad.kind, squad.id, slot]
	soldier.set_meta("outpost_squad", true)
	soldier.set_meta("squad_kind", squad.kind)
	soldier.set_meta("amove_engaged", false)
	soldier.title = String(Catalog.troop(String(squad.kind)).title)
	soldier.max_hp = _base_max_hp(squad.kind) * health_multiplier
	soldier.hp = soldier.max_hp
	soldier.armor = 25.0 if squad.kind == "shield" else 0.0
	soldier.damage = float({"shield": 10.0, "ranged": 16.0, "engineer": 5.0, "ballista": 46.0, "hauler": 0.0, "medic": 0.0, "artillery": 32.0, "hunter": 12.0}[squad.kind])
	soldier.attack_range = float({"shield": 2.7, "ranged": 8.6, "engineer": 2.3, "ballista": 12.8, "hauler": 1.5, "medic": 0.0, "artillery": 16.0, "hunter": 2.3}[squad.kind])
	soldier.attack_interval = 1.4 if squad.kind == "hunter" else (4.8 if squad.kind == "artillery" else (3.2 if squad.kind == "ballista" else (1.45 if squad.kind == "shield" else 1.65)))
	soldier.speed = 5.4 if squad.kind == "hunter" else (2.4 if squad.kind == "artillery" else (3.06 if squad.kind == "ballista" else 3.6))
	soldier.windup_duration = .22 if squad.kind == "hunter" else (1.0 if squad.kind == "artillery" else (.55 if squad.kind == "ballista" else (.18 if squad.kind == "shield" else .26)))
	soldier.visual.scale *= .85
	soldier.selection.visible = int(squad.id) in selected_ids
	soldier.position = _resolve_destination(squad.origin + Vector3((slot - 1) * 1.2, 0, 0))
	soldier.set_meta("support_timer", 1.0)
	if squad.kind == "medic":
		_medic_states[soldier.get_instance_id()] = {"unit": weakref(soldier), "casting": false,
			"remaining": 0.0, "cooldown": 0.0, "target": null, "cancel_reason": "",
			"treatments": 0, "healed_hp": 0.0, "spent": 0}
	if squad.kind == "artillery": artillery.register(soldier)
	if squad.kind == "hunter": hunters.register(soldier, int(squad.id), slot)
	_style_member(soldier, str(squad.kind))
	if not _owns_squad(squad, generation):
		_retire_member(soldier)
		return null
	soldier.defeated.connect(_on_member_defeated)
	return soldier

func _station(squad: Dictionary, slot: int, order: String) -> Vector3:
	if order == ESCORT and is_instance_valid(escort): return escort.station(squad, slot)
	var march_stations: Array = squad.get("attack_move_stations", [])
	if order == AMOVE and march_stations.size() == MEMBERS_PER_SQUAD:
		return march_stations[slot]
	var rally_stations: Array = squad.get("rally_stations", [])
	if order in [MOVE, GUARD] and rally_stations.size() == MEMBERS_PER_SQUAD:
		return rally_stations[slot]
	if order == HAUL and String(squad.kind) == "hauler":
		var logistics := _logistics()
		var member: BattleUnit = squad.members[slot]
		if is_instance_valid(logistics) and _living(member):
			var point: Vector3 = logistics.call("destination_for", int(squad.id), member.get_instance_id())
			return point if point.is_finite() else member.position
		return member.position if _living(member) else squad.destination
	if order in [MOVE, AMOVE, ATTACK, GUARD]:
		var index := int(squad.get("formation_index", 0))
		var offset := Vector3((slot - 1) * 1.25 + float([0, -1, 1][index % 3]) * 3.7, 0, float(int(index / 3)) * 2.2)
		return _resolve_destination((squad.destination as Vector3) + offset)
	var x := (float(slot) - 1.0) * 1.6
	var id := int(squad.id)
	var z := 3.9 + float(id % 5) * .9
	if order == HOLD:
		z = ((13.4 - float(id % 4) * 2.3) if squad.kind == "shield" else (5.0 + float(id % 5) * .85)) + Layout.EXPANSION_OFFSET
		if id >= 4: x += float(int(id / 4) % 3 - 1) * 2.8
	return _resolve_destination(Vector3(x, 0, z))

func _resolve_destination(point: Vector3) -> Vector3:
	var goal := point
	if not goal.is_finite(): return Vector3(0, 5, 3.9)
	if game.has_method("hero_safe_destination"): goal = game.call("hero_safe_destination", goal)
	if game.has_method("outpost_walkable") and not bool(game.call("outpost_walkable", goal)):
		if game.has_method("nearest_navigation_cell"):
			var cell: Vector2i = game.call("nearest_navigation_cell", goal, false)
			if cell.x != 999: goal = Vector3(cell.x, 0, cell.y)
	goal.y = _ground_height(goal)
	return goal

func _style_member(soldier: BattleUnit, kind: String) -> void:
	# 复用原创卫兵骨架；不同兵种有独立胸徽和工具轮廓。
	var marker := MeshInstance3D.new()
	var badge := BoxMesh.new()
	badge.size = Vector3(.24, .26, .055)
	marker.mesh = badge
	marker.material_override = BattleVisuals.material(Color({"shield": "72c5d2", "ranged": "e7bb69", "engineer": "88d18b", "ballista": "d99867", "hauler": "adc89b", "medic": "b7e0d7", "artillery": "73bcb8", "hunter": "d8a087"}[kind]), .15)
	soldier.visual.add_child(marker)
	marker.position = Vector3(0, 1.15, -.26)
	if kind == "shield": return
	for part in soldier.visual.find_children("*", "MeshInstance3D", true, false):
		var label := str(part.name).to_lower()
		if "shield" in label or "polearm" in label or "spear" in label: part.visible = false
	var right_arm := soldier.visual.find_child("ArmR", true, false) as Node3D
	if not is_instance_valid(right_arm): right_arm = soldier.visual
	if kind == "ballista":
		_style_heavy_crossbow(right_arm)
		return
	if kind == "artillery":
		_style_artillery(right_arm)
		return
	if kind == "hauler":
		var harness := BattleVisuals.box(soldier.visual, Vector3(0, 1.03, .28), Vector3(.50, .57, .20), BattleVisuals.material(Color("7d7762")))
		harness.name = "HaulHarness"
		var cargo := BattleVisuals.box(soldier.visual, Vector3(0, 1.13, .47), Vector3(.58, .58, .42), BattleVisuals.material(Color("bd955f")))
		cargo.name = "HaulCargo"
		cargo.visible = false
		soldier.set_meta("haul_cargo", 0)
		return
	if kind == "medic":
		_style_medic(right_arm, soldier.visual)
		return
	if kind == "hunter":
		_style_hunter(right_arm, soldier.visual)
		return
	var tool := MeshInstance3D.new()
	var tool_mesh := BoxMesh.new()
	tool_mesh.size = Vector3(.7, .1, .16) if kind == "ranged" else Vector3(.18, .58, .12)
	tool.mesh = tool_mesh
	tool.material_override = BattleVisuals.material(Color("96734b") if kind == "ranged" else Color("bdc9b4"), 0.0)
	right_arm.add_child(tool)
	tool.position = Vector3(0, -.4, -.15)
	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(.13, .1, .75) if kind == "ranged" else Vector3(.4, .15, .16)
	head.mesh = head_mesh; head.material_override = tool.material_override
	tool.add_child(head)
	head.position.y = .2 if kind == "engineer" else 0.0

func _style_hunter(right_arm: Node3D, visual: Node3D) -> void:
	# Native short blades on the existing original guard rig: gameplay prototype.
	var left_arm := visual.find_child("ArmL", true, false) as Node3D
	if not is_instance_valid(left_arm): left_arm = visual
	var iron := BattleVisuals.material(Color("b8c0bb"), 0.0)
	var leather := BattleVisuals.material(Color("715344"), 0.0)
	for arm: Node3D in [right_arm, left_arm]:
		var blade := BattleVisuals.box(arm, Vector3(0, -.55, -.19), Vector3(.075, .54, .11), iron)
		blade.name = "HunterShortBlade"
		var grip := BattleVisuals.box(arm, Vector3(0, -.23, -.19), Vector3(.10, .13, .13), leather)
		grip.name = "HunterBladeGrip"

func _style_artillery(arm: Node3D) -> void:
	# Original guard rig and a native mortar tube, a gameplay prototype.
	var tool := Node3D.new()
	tool.name = "ArtilleryNativeMortar"
	arm.add_child(tool)
	tool.position = Vector3(0,-.44,-.18)
	var iron := BattleVisuals.material(Color("77908e"),0.0)
	var base := BattleVisuals.box(tool,Vector3(0,-.11,.08),Vector3(.38,.11,.43),iron)
	base.name = "ArtilleryBasePlate"
	var tube := MeshInstance3D.new()
	tube.name = "ArtilleryMortarTube"
	var mesh := CylinderMesh.new()
	mesh.top_radius = .105
	mesh.bottom_radius = .13
	mesh.height = .86
	mesh.radial_segments = 10
	tube.mesh = mesh
	tube.material_override = iron
	tool.add_child(tube)
	tube.position = Vector3(0,.26,-.12)
	tube.rotation.x = -.60

func _style_medic(arm: Node3D, visual: Node3D) -> void:
	# The original guard rig carries a native satchel, without a weapon.
	var ivory := BattleVisuals.material(Color("d8e4de"), 0.0)
	var teal := BattleVisuals.material(Color("6ca99e"), 0.0)
	var case_node := BattleVisuals.box(arm, Vector3(0, -.43, -.14), Vector3(.38, .31, .19), ivory)
	case_node.name = "MedicSatchel"
	var stripe := BattleVisuals.box(case_node, Vector3(0, 0, -.10), Vector3(.065, .25, .015), teal)
	stripe.name = "MedicSatchelStripe"
	var handle := BattleVisuals.box(case_node, Vector3(0, .19, 0), Vector3(.19, .065, .08), teal)
	handle.name = "MedicSatchelHandle"
	var armband := BattleVisuals.box(visual, Vector3(.32, 1.1, -.055), Vector3(.18, .16, .27), ivory)
	armband.name = "MedicArmband"

func _style_heavy_crossbow(arm: Node3D) -> void:
	# Native tool geometry on the original guard; no new imported character asset.
	var tool := Node3D.new()
	tool.name = "HeavyCrossbow"
	arm.add_child(tool)
	tool.position = Vector3(0, -.38, -.17)
	var wood := BattleVisuals.material(Color("735440"), 0.0)
	var iron := BattleVisuals.material(Color("9fadb2"), 0.0)
	for piece in [
		["Stock", Vector3(.22, .16, 1.12), Vector3(0, 0, -.15), wood],
		["Bow", Vector3(1.04, .13, .15), Vector3(0, 0, -.53), iron],
		["Rail", Vector3(.10, .06, .86), Vector3(0, .105, -.18), iron],
		["Grip", Vector3(.15, .31, .19), Vector3(0, -.17, .10), wood],
		["Sight", Vector3(.08, .18, .09), Vector3(0, .20, .18), iron]]:
		var node := MeshInstance3D.new()
		node.name = piece[0]
		var mesh := BoxMesh.new()
		mesh.size = piece[1]
		node.mesh = mesh; node.material_override = piece[3]
		tool.add_child(node); node.position = piece[2]

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

func _squad_alive(squad: Dictionary) -> bool:
	for soldier: BattleUnit in squad.members:
		if _living(soldier): return true
	return false

func _refresh_selection() -> void:
	for squad in squads:
		if not _squad_alive(squad): selected_ids.erase(int(squad.id))
		for soldier: BattleUnit in squad.members:
			if _living(soldier): soldier.selection.visible = int(squad.id) in selected_ids

func selected_count() -> int:
	_refresh_selection()
	return selected_ids.size()

func cancel_selection() -> void:
	selected_ids.clear()
	_refresh_selection()

func select_all() -> int:
	if not _active(): return selected_count()
	selected_ids.clear()
	for squad in squads:
		if _squad_alive(squad): selected_ids.append(int(squad.id))
	_refresh_selection()
	return selected_ids.size()

func select_ids(ids: Array[int], add: bool = false) -> Array[int]:
	if not _active() or game.is_queued_for_deletion(): return selected_ids.duplicate()
	var candidates: Array[int] = []
	if add: candidates.assign(selected_ids)
	candidates.append_array(ids)
	var next_ids: Array[int] = []
	for id: int in candidates:
		if id < 0 or id >= squads.size() or id in next_ids: continue
		var squad: Dictionary = squads[id]
		if int(squad.get("id", -1)) == id and _squad_alive(squad): next_ids.append(id)
	selected_ids.assign(next_ids)
	_refresh_selection()
	return selected_ids.duplicate()

func select_at(point: Vector3, add: bool = false) -> int:
	if not _active(): return selected_count()
	var chosen := -1
	var nearest := 1.9
	for squad in squads:
		for soldier: BattleUnit in squad.members:
			if not _living(soldier): continue
			var distance := _ground_distance(soldier.position, point)
			if distance < nearest: nearest = distance; chosen = int(squad.id)
	if not add: selected_ids.clear()
	if chosen >= 0 and chosen not in selected_ids: selected_ids.append(chosen)
	_refresh_selection()
	return chosen

func select_rect(camera: Camera3D, rect: Rect2, add: bool = false) -> int:
	if not _active() or not is_instance_valid(camera): return selected_count()
	if not add: selected_ids.clear()
	var area := rect.abs()
	for squad in squads:
		for soldier: BattleUnit in squad.members:
			if not _living(soldier) or camera.is_position_behind(soldier.global_position): continue
			if area.has_point(camera.unproject_position(soldier.global_position)):
				if int(squad.id) not in selected_ids: selected_ids.append(int(squad.id))
				break
	_refresh_selection()
	return selected_ids.size()

func _command(order: String, point: Vector3, target: BattleUnit = null, exclude_haulers: bool = false) -> Dictionary:
	if not _active(): return _result(false, "暂停或选卡时不能指挥")
	if selected_count() == 0: return _result(false, "请先选择部队")
	if not point.is_finite(): return _result(false, "请选择可通行位置")
	var index := 0
	for squad in squads:
		if int(squad.id) not in selected_ids: continue
		if exclude_haulers and String(squad.kind) == "hauler": continue
		_set_squad_order(squad, order)
		squad.destination = _resolve_destination(point)
		squad.formation_index = index
		squad.attack_target = weakref(target) if is_instance_valid(target) else null
		if String(squad.kind) == "hunter" and order == ATTACK: squad.hunter_attack_anchor = point
		if order == AMOVE:
			var stations: Array[Vector3] = []
			for slot in MEMBERS_PER_SQUAD: stations.append(_station(squad, slot, AMOVE))
			squad.attack_move_stations = stations
		index += 1
	if index == 0: return _result(false, "没有已选护卫部队")
	return _result(true, {MOVE: "部队前往指定位置", AMOVE: "部队沿路迎击，到点驻守", ATTACK: "部队攻击指定敌人", GUARD: "部队守卫指定位置"}[order])

func command_move(point: Vector3) -> Dictionary: return _command(MOVE, point)

func command_attack_move(point: Vector3) -> Dictionary: return _command(AMOVE, point)

func command_move_non_haulers(point: Vector3) -> Dictionary: return _command(MOVE, point, null, true)

func command_escort(target_member: Variant) -> Dictionary:
	if not _active(): return _result(false, "暂停或选卡时不能护航")
	if not _living(target_member) or not target_member is BattleUnit or target_member.hp <= 0.0 \
		or target_member.kind != "minion" or target_member.team != 0:
		return _result(false, "请选择真实存活工队")
	# Scene membership and the original roster slot authorize the convoy.
	# Metadata, an enemy, or a same-numbered member from an old run cannot.
	for squad: Dictionary in squads:
		if String(squad.kind) != "hauler" or target_member not in squad.members: continue
		if not is_instance_valid(escort): return _result(false, "护航系统尚未初始化")
		var result: Dictionary = escort.command_selected(squad)
		result.merge(_result(bool(result.ok), String(result.reason)))
		return result
	return _result(false, "请选择真实存活工队")

func escort_snapshot() -> Dictionary:
	return escort.snapshot() if is_instance_valid(escort) else {"count": 0, "squads": []}

func command_guard(point: Vector3) -> Dictionary: return _command(GUARD, point)

func command_attack(enemy: Variant) -> Dictionary:
	if not _enemy(enemy): return _result(false, "请选择存活敌人")
	for squad in squads:
		if String(squad.kind) == "hunter" and int(squad.id) in selected_ids and not hunters.real_enemy(enemy):
			return _result(false, "请选择真实存活敌人")
	return _command(ATTACK, enemy.position, enemy as BattleUnit)

func set_order(order: String, squad_id: int = -1) -> Dictionary:
	if not _active(): return _result(false, "暂停或选卡时不能指挥")
	if order not in [HOLD, RECALL]: return _result(false, "未知小队命令")
	if squad_id < -1 or squad_id >= squads.size(): return _result(false, "没有这支小队")
	for squad in squads:
		if squad_id >= 0 and int(squad.id) != squad_id: continue
		_set_squad_order(squad, order)
	return _result(true, "小队驻守南门" if order == HOLD else "小队撤回灯塔", 0, squad_id)

func _set_squad_order(squad: Dictionary, order: String) -> void:
	if is_instance_valid(escort): escort.on_order(squad)
	# A manual command owns the squad immediately; arriving later must never
	# replace that command with the old barracks destination.
	squad.rally_pending = false
	squad.rally_stations = []
	squad.attack_move_stations = []
	if String(squad.kind) == "hauler" and order != HAUL:
		var logistics := _logistics()
		if is_instance_valid(logistics): logistics.call("on_manual_order", int(squad.id))
	squad.order = order
	for soldier: BattleUnit in squad.members:
		if not _living(soldier): continue
		soldier.set_meta("amove_engaged", false)
		if String(squad.kind) == "medic": _cancel_medic(soldier, "order_changed")
		if String(squad.kind) == "artillery" and is_instance_valid(artillery): artillery.cancel(soldier)
		if String(squad.kind) == "hunter" and is_instance_valid(hunters): hunters.on_order(soldier)
		soldier.target = null
		soldier.attack_queued = false
		soldier.attack_windup = 0.0
		soldier.path.clear(); soldier.path_timer = 0.0
	squad.attack_target = null

func _logistics() -> Node:
	# Existing isolated fixtures do not declare the controller's logistics property.
	if not _has_logistics or not is_instance_valid(game): return null
	var value: Variant = game.get("logistics")
	return value as Node if is_instance_valid(value) and value is Node else null

func set_haul_order(squad_id: int) -> bool:
	if not _active() or squad_id < 0 or squad_id >= squads.size(): return false
	var squad: Dictionary = squads[squad_id]
	if String(squad.kind) != "hauler" or not _squad_alive(squad): return false
	_set_squad_order(squad, HAUL)
	return true

func set_medic_enabled(squad_id: int, enabled: bool) -> Dictionary:
	if not _active(): return _result(false, "暂停或选卡时不能切换治疗")
	if squad_id < 0 or squad_id >= squads.size(): return _result(false, "没有这支医护队")
	var squad: Dictionary = squads[squad_id]
	if int(squad.id) != squad_id or String(squad.kind) != "medic" or not _squad_alive(squad):
		return _result(false, "请选择存活医护队")
	if squad_id not in selected_ids: return _result(false, "请先选择这支医护队")
	if bool(squad.get("therapy_enabled", false)) != enabled:
		squad.therapy_enabled = enabled
		for soldier: BattleUnit in squad.members:
			if _living(soldier): _cancel_medic(soldier, "therapy_disabled" if not enabled else "")
	var result := _result(true, "医护治疗已开启，每次实际治疗付2零件" if enabled else "医护治疗已关闭", 0, squad_id)
	result.therapy_enabled = enabled
	return result

func _cancel_medic(soldier: BattleUnit, reason: String) -> void:
	if not is_instance_valid(soldier): return
	var state: Dictionary = _medic_states.get(soldier.get_instance_id(), {})
	if state.is_empty(): return
	state.casting = false
	state.remaining = 0.0
	state.target = null
	state.cancel_reason = reason
	soldier.set_meta("medic_casting", false)

func _cancel_medic_casts(reason: String) -> void:
	for squad: Dictionary in squads:
		if String(squad.kind) != "medic": continue
		for soldier: BattleUnit in squad.members:
			if _living(soldier): _cancel_medic(soldier, reason)

func _is_real_medic_target(target: Variant) -> bool:
	if not _living(target): return false
	# Isolated legacy controllers may have no hero property. A similarly
	# tagged node outside the controller's actual roster is never an ally.
	if _has_hero and target == game.get("hero"): return true
	for squad: Dictionary in squads:
		if target in squad.members: return true
	return false

func _medic_target_valid(soldier: BattleUnit, target: Variant) -> bool:
	if not _is_real_medic_target(target): return false
	var patient := target as BattleUnit
	if not patient.position.is_finite() or not soldier.position.is_finite(): return false
	if not is_finite(patient.hp) or not is_finite(patient.max_hp) or patient.hp <= 0.0 or patient.max_hp <= 0.0: return false
	if patient.max_hp - patient.hp < MEDIC_MIN_MISSING: return false
	if _ground_distance(soldier.position, patient.position) > MEDIC_RANGE: return false
	if absf(soldier.position.y - patient.position.y) > MEDIC_HEIGHT_LIMIT: return false
	var source_height := _ground_height(soldier.position)
	var target_height := _ground_height(patient.position)
	if not is_finite(source_height) or not is_finite(target_height) or absf(source_height - target_height) > MEDIC_HEIGHT_LIMIT: return false
	return _medic_line(soldier.position, patient.position)

func _medic_line(from: Vector3, to: Vector3) -> bool:
	if not _attack_line(from, to): return false
	if not _has_construction_blocks: return true
	# Medical treatment reaches a real person, never a building surface.
	# Apply the live building rectangles without adding a unit-body radius
	# or reusing path reachability, which could reject a visible ramp target.
	var blocks: Variant = game.get("construction_blocks")
	if not blocks is Array: return false
	var origin := Vector2(from.x, from.z)
	var direction := Vector2(to.x - from.x, to.z - from.z)
	for block_value: Variant in blocks:
		if not block_value is Rect2: continue
		var block: Rect2 = block_value
		if game.has_method("segment_crosses_wall"):
			if bool(game.call("segment_crosses_wall", origin, direction, block)): return false
		elif _medic_segment_crosses_block(origin, direction, block): return false
	return true

func _medic_segment_crosses_block(origin: Vector2, direction: Vector2, block: Rect2) -> bool:
	# Exact open-interior segment/slab check for isolated controllers that
	# expose building rectangles but do not have the production helper.
	var enter := 0.0
	var leave := 1.0
	for axis in 2:
		var low: float = block.position[axis]
		var high: float = block.end[axis]
		if absf(direction[axis]) < .000001:
			if origin[axis] <= low or origin[axis] >= high: return false
		else:
			var first: float = (low - origin[axis]) / direction[axis]
			var last: float = (high - origin[axis]) / direction[axis]
			enter = maxf(enter, minf(first, last))
			leave = minf(leave, maxf(first, last))
			if enter >= leave or leave <= 0.0 or enter >= 1.0: return false
	return leave > 0.0 and enter < 1.0

func _pick_medic_target(soldier: BattleUnit) -> BattleUnit:
	var candidates: Array[BattleUnit] = []
	if _has_hero:
		var hero_value: Variant = game.get("hero")
		if _living(hero_value): candidates.append(hero_value as BattleUnit)
	for squad: Dictionary in squads:
		for member: BattleUnit in squad.members:
			if _living(member) and member not in candidates: candidates.append(member)
	var chosen: BattleUnit
	var best_ratio := INF
	var best_distance := INF
	for candidate: BattleUnit in candidates:
		if not _medic_target_valid(soldier, candidate): continue
		var ratio := candidate.hp / candidate.max_hp
		var distance := _ground_distance(soldier.position, candidate.position)
		if ratio < best_ratio or (ratio == best_ratio and distance < best_distance):
			chosen = candidate; best_ratio = ratio; best_distance = distance
	return chosen

func _advance_medic(squad: Dictionary, soldier: BattleUnit, delta: float, station: Vector3) -> void:
	var state: Dictionary = _medic_states.get(soldier.get_instance_id(), {})
	if state.is_empty(): return
	# Cooldown belongs to the actual member, not its order, enable switch,
	# repair support_timer or day/night mode. Every active frame advances it.
	state.cooldown = maxf(0.0, float(state.cooldown) - delta)
	soldier.attack_queued = false; soldier.attack_windup = 0.0; soldier.target = null
	if soldier.moving or _ground_distance(soldier.position, station) > .16:
		_cancel_medic(soldier, "moving")
		return
	if not bool(squad.get("therapy_enabled", false)):
		_cancel_medic(soldier, "therapy_disabled")
		return
	if int(game.get("scrap")) < MEDIC_COST:
		_cancel_medic(soldier, "insufficient_parts")
		return
	if float(state.cooldown) > 0.0: return
	if bool(state.casting):
		var target_ref: Variant = state.target
		var target: BattleUnit = target_ref.get_ref() as BattleUnit if target_ref is WeakRef else null
		if not _medic_target_valid(soldier, target):
			_cancel_medic(soldier, "target_invalid")
			return
		state.remaining = maxf(0.0, float(state.remaining) - delta)
		soldier.face(target.position, delta)
		if float(state.remaining) > 0.0: return
		# Recheck the original patient and current wallet at the committing
		# frame. Three simultaneous medics cannot spend the same last parts.
		if not _medic_target_valid(soldier, target) or int(game.get("scrap")) < MEDIC_COST:
			_cancel_medic(soldier, "target_invalid" if not _medic_target_valid(soldier, target) else "insufficient_parts")
			return
		var before := target.hp
		target.hp = minf(target.max_hp, target.hp + MEDIC_HEAL)
		var restored := target.hp - before
		if restored <= 0.0:
			_cancel_medic(soldier, "target_invalid")
			return
		game.set("scrap", int(game.get("scrap")) - MEDIC_COST)
		state.treatments = int(state.treatments) + 1
		state.healed_hp = float(state.healed_hp) + restored
		state.spent = int(state.spent) + MEDIC_COST
		squad.treatments = int(squad.treatments) + 1
		squad.healed_hp = float(squad.healed_hp) + restored
		squad.spent = int(squad.spent) + MEDIC_COST
		_cancel_medic(soldier, "")
		state.cooldown = MEDIC_COOLDOWN
		soldier.attack_pose = .65
		# Distinct attachment heights retain a visible short self-treatment
		# pulse as well as the usual ally beam. Both use the frozen shot clock.
		_beam(soldier.position + Vector3.UP * .9, target.position + Vector3.UP * 1.25, Color("95cdb9"), .022, .24, .12)
		return
	var target := _pick_medic_target(soldier)
	if not is_instance_valid(target): return
	state.casting = true
	state.remaining = MEDIC_WINDUP
	state.target = weakref(target)
	state.cancel_reason = ""
	soldier.set_meta("medic_casting", true)
	soldier.face(target.position, delta)

func medic_snapshot() -> Dictionary:
	# Presentation never creates treatment state, selects targets, reserves
	# money, changes enabled flags or advances a simulation clock.
	var rows: Array[Dictionary] = []
	var total_alive := 0
	var enabled_count := 0
	var treatments := 0
	var healed_hp := 0.0
	var spent := 0
	for squad: Dictionary in squads:
		if String(squad.kind) != "medic": continue
		var members: Array[Dictionary] = []
		var casting := 0
		var cooldown := 0.0
		for slot in MEMBERS_PER_SQUAD:
			var soldier: BattleUnit = squad.members[slot]
			if not _living(soldier): continue
			var state: Dictionary = _medic_states.get(soldier.get_instance_id(), {})
			var target_ref: Variant = state.get("target")
			var target: BattleUnit = target_ref.get_ref() as BattleUnit if target_ref is WeakRef else null
			if not _living(target): target = null
			var is_casting := bool(state.get("casting", false))
			var remaining := float(state.get("remaining", 0.0))
			var member_cooldown := float(state.get("cooldown", 0.0))
			if is_casting: casting += 1
			cooldown = maxf(cooldown, member_cooldown)
			members.append({"slot": slot, "token": soldier.get_instance_id(), "source": soldier,
				"phase": "windup" if is_casting else ("cooldown" if member_cooldown > 0.0 else "idle"),
				"casting": is_casting, "remaining": remaining, "total": MEDIC_WINDUP, "cooldown": member_cooldown,
				"target": target, "target_token": target.get_instance_id() if is_instance_valid(target) else -1,
				"cancel_reason": String(state.get("cancel_reason", "")), "treatments": int(state.get("treatments", 0)),
				"healed_hp": float(state.get("healed_hp", 0.0)), "spent": int(state.get("spent", 0))})
		var alive := members.size()
		total_alive += alive
		if bool(squad.get("therapy_enabled", false)) and alive > 0: enabled_count += 1
		treatments += int(squad.get("treatments", 0))
		healed_hp += float(squad.get("healed_hp", 0.0))
		spent += int(squad.get("spent", 0))
		rows.append({"id": squad.id, "title": "医护队", "selected": int(squad.id) in selected_ids,
			"alive": alive, "therapy_enabled": bool(squad.get("therapy_enabled", false)),
			"treatments": int(squad.get("treatments", 0)), "healed_hp": float(squad.get("healed_hp", 0.0)),
			"spent": int(squad.get("spent", 0)), "casting": casting, "cooldown": cooldown, "members": members})
	return {"count": rows.size(), "alive": total_alive, "enabled_count": enabled_count,
		"treatments": treatments, "healed_hp": healed_hp, "spent": spent, "squads": rows}

func on_day() -> void:
	_epoch += 1
	_cancel_intercepts()
	_cancel_medic_casts("phase_changed")
	if is_instance_valid(artillery): artillery.clear_pending()
	if is_instance_valid(hunters): hunters.clear_pending()
	if is_instance_valid(escort): escort.on_phase_changed()
	_clear_attack_move_encounters()
	for squad in squads:
		if String(squad.kind) == "hauler": continue
		if squad.order in [HOLD, RECALL]: _set_squad_order(squad, RECALL)

func on_night() -> void:
	_epoch += 1
	_cancel_intercepts()
	_cancel_medic_casts("phase_changed")
	if is_instance_valid(artillery): artillery.clear_pending()
	if is_instance_valid(hunters): hunters.clear_pending()
	if is_instance_valid(escort): escort.on_phase_changed()
	_clear_attack_move_encounters()
	for squad in squads:
		if String(squad.kind) == "hauler": continue
		if squad.order in [HOLD, RECALL]: _set_squad_order(squad, HOLD)

func _clear_attack_move_encounters() -> void:
	for squad: Dictionary in squads:
		if squad.order not in [AMOVE, ESCORT]: continue
		for soldier: BattleUnit in squad.members:
			if not _living(soldier): continue
			soldier.set_meta("amove_engaged", false)
			soldier.target = null; soldier.attack_queued = false; soldier.attack_windup = 0.0
			soldier.path.clear(); soldier.path_timer = 0.0

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
	var generation := _epoch
	var elapsed := maxf(0.0, delta)
	for key in _intercepts.keys():
		var enemy := (_intercepts[key].enemy as WeakRef).get_ref() as BattleUnit
		if not _enemy(enemy): _intercepts.erase(key)
	if elapsed <= 0.0: return
	_advance_training(elapsed)
	if generation != _epoch or not _active(): return
	_advance_shots(elapsed)
	if is_instance_valid(artillery): artillery.advance(elapsed)
	if generation != _epoch or not _active(): return
	_refresh_selection()
	for squad in squads:
		if generation != _epoch or not _active(): return
		if squad.order == ESCORT and is_instance_valid(escort): escort.prepare_squad(squad, elapsed)
		if not _owns_squad(squad, generation): return
		var recovering_hunter := false
		if String(squad.kind) == "hunter": recovering_hunter = bool(hunters.prepare_squad(squad))
		var designated: BattleUnit
		if squad.order == ATTACK and String(squad.kind) not in ["medic", "hunter"]:
			var target_ref: Variant = squad.get("attack_target")
			if target_ref is WeakRef: designated = target_ref.get_ref() as BattleUnit
			if _enemy(designated): squad.destination = designated.position
			else:
				_set_squad_order(squad, GUARD)
				squad.destination = _squad_position(squad)
		for slot in MEMBERS_PER_SQUAD:
			if generation != _epoch or not _active(): return
			var soldier: BattleUnit = squad.members[slot]
			if not _living(soldier): continue
			soldier.tick(elapsed)
			if String(squad.kind) == "hunter":
				hunters.advance_member(squad, soldier, slot, elapsed, recovering_hunter)
				if generation != _epoch or not _active(): return
				if _living(soldier): _animate_member(soldier)
				continue
			if String(squad.kind) == "artillery":
				_advance_artillery_member(squad,soldier,elapsed,designated,slot)
				if not _owns_squad(squad, generation): return
				if _living(soldier): _animate_member(soldier)
				continue
			if String(squad.kind) == "medic":
				# Attack commands retain their issued destination for medics.
				# They neither chase an enemy nor leave station to follow a wound.
				var medic_station := _station(squad, slot, String(squad.order))
				_move_member(soldier, medic_station, elapsed)
				_advance_medic(squad, soldier, elapsed, medic_station)
				_animate_member(soldier)
				continue
			if squad.order in [AMOVE, ESCORT]:
				_advance_attack_move_member(squad, soldier, slot, elapsed)
				if not _owns_squad(squad, generation): return
				if _living(soldier): _animate_member(soldier)
				continue
			if squad.order == ATTACK and _enemy(designated) and _in_range(soldier, designated):
				soldier.moving = false
				_attack(soldier, elapsed, designated)
			else:
				var station := _station(squad, slot, str(squad.order))
				if squad.order == ATTACK and _enemy(designated): station = _resolve_destination(designated.position)
				_move_member(soldier, station, elapsed)
				if not soldier.moving and squad.order != RECALL:
					if str(squad.kind) == "engineer": _repair_nearby(soldier, elapsed)
					_attack(soldier, elapsed)
			_animate_member(soldier)
		if generation != _epoch or not _active(): return
		_finish_training_rally(squad)
		if not _owns_squad(squad, generation): return
		_finish_attack_move(squad)

func _advance_attack_move_member(squad: Dictionary, soldier: BattleUnit, slot: int, delta: float) -> void:
	var generation := _epoch
	var target: BattleUnit
	if String(squad.kind) != "hauler":
		if soldier.attack_queued and _enemy(soldier.target) and soldier.target in game.get("enemies") and _in_range(soldier, soldier.target):
			target = soldier.target
		else:
			soldier.attack_queued = false; soldier.attack_windup = 0.0; soldier.target = null
			target = _pick_enemy(soldier, true)
	if is_instance_valid(target):
		soldier.moving = false; soldier.path.clear()
		soldier.set_meta("amove_engaged", true)
		if String(squad.kind) == "engineer": _repair_nearby(soldier, delta)
		if not _owns_member(soldier, generation): return
		_attack(soldier, delta, target)
		return
	soldier.set_meta("amove_engaged", false)
	_move_member(soldier, _station(squad, slot, String(squad.order)), delta)
	if not soldier.moving and String(squad.kind) == "engineer": _repair_nearby(soldier, delta)

func _finish_attack_move(squad: Dictionary) -> void:
	var generation := _epoch
	if not _owns_squad(squad, generation) or squad.order != AMOVE: return
	var stations: Array = squad.get("attack_move_stations", [])
	if stations.size() != MEMBERS_PER_SQUAD: return
	var alive := 0
	for slot in MEMBERS_PER_SQUAD:
		var soldier: BattleUnit = squad.members[slot]
		if not _living(soldier): continue
		alive += 1
		if _ground_distance(soldier.position, stations[slot]) > .16 + .000001: return
	if alive == 0: return
	_set_squad_order(squad, GUARD)
	if _owns_squad(squad, generation): squad.rally_stations = stations

func _finish_training_rally(squad: Dictionary) -> void:
	var generation := _epoch
	if not _owns_squad(squad, generation): return
	if not bool(squad.get("rally_pending", false)) or String(squad.order) != MOVE: return
	var stations: Array = squad.get("rally_stations", [])
	if stations.size() != MEMBERS_PER_SQUAD: return
	var alive := 0
	for slot in MEMBERS_PER_SQUAD:
		var soldier: BattleUnit = squad.members[slot]
		if not _living(soldier): continue
		alive += 1
		if _ground_distance(soldier.position, stations[slot]) > .16 + .000001: return
	if alive == 0: return
	_set_squad_order(squad, GUARD)
	if not _owns_squad(squad, generation): return
	# Retain the validated fixed stations while guarding. Future manual orders
	# clear them, but later construction cannot silently shift a rally anchor.
	squad.rally_stations = stations

func _stop_artillery(soldier: BattleUnit) -> void:
	soldier.moving = false
	soldier.path.clear()
	soldier.target = null
	soldier.attack_queued = false
	soldier.attack_windup = 0.0

func _advance_artillery_member(squad: Dictionary, soldier: BattleUnit, delta: float, designated: BattleUnit, slot: int) -> void:
	if artillery.casting(soldier):
		artillery.advance_unit(soldier,delta)
		return
	if squad.order in [AMOVE, ESCORT]:
		var march_focus: Variant = game.get("focus_target")
		var march_preferred: BattleUnit = march_focus as BattleUnit if artillery.real_enemy(march_focus) and float(game.get("focus_time")) > 0.0 else null
		var march_target: BattleUnit = artillery.pick_target(soldier, march_preferred)
		if is_instance_valid(march_target):
			_stop_artillery(soldier)
			artillery.begin(soldier, march_target)
		else:
			_move_member(soldier, _station(squad, slot, String(squad.order)), delta)
		return
	var preferred: BattleUnit = designated if artillery.real_enemy(designated) else null
	if preferred == null and squad.order not in [MOVE,RECALL]:
		var focus: Variant = game.get("focus_target")
		if artillery.real_enemy(focus) and float(game.get("focus_time")) > 0.0: preferred = focus as BattleUnit
	if preferred != null:
		var separation: float = artillery.distance(soldier.position,preferred.position)
		# An explicit too-close enemy retains the firing position. Never chase
		# into melee or let a station correction mask this player decision.
		if separation < ArtilleryScript.MIN_RANGE or not artillery.ground_compatible(soldier.position,preferred.position):
			_stop_artillery(soldier)
			return
		if artillery.legal_target(soldier,preferred):
			_stop_artillery(soldier)
			artillery.begin(soldier,preferred)
			return
		var approach := _artillery_approach(soldier,preferred)
		_move_member(soldier,approach,delta)
		if artillery.legal_target(soldier,preferred): _stop_artillery(soldier)
		return
	var station := _station(squad,slot,String(squad.order))
	_move_member(soldier,station,delta)
	if soldier.moving or squad.order == RECALL: return
	var target: BattleUnit = artillery.pick_target(soldier)
	if is_instance_valid(target): artillery.begin(soldier,target)

func _artillery_approach(soldier: BattleUnit, target: BattleUnit) -> Vector3:
	var direction := Vector2(soldier.position.x-target.position.x,soldier.position.z-target.position.z).normalized()
	if direction.length_squared() < .001: direction = Vector2.UP
	var best := INF
	var chosen := soldier.position
	# Choose a walkable firing cell, not the enemy's footprint. The existing
	# cached gate-aware route moves the actual soldier toward this position.
	for radius in [15.2,12.0,8.0]:
		for step in 12:
			var radial := direction.rotated(TAU*float(step)/12.0)
			var candidate := _resolve_destination(target.position+Vector3(radial.x,0,radial.y)*float(radius))
			var separation: float = artillery.distance(candidate,target.position)
			if separation < ArtilleryScript.MIN_RANGE or separation > ArtilleryScript.MAX_RANGE: continue
			if not _attack_line(candidate,target.position): continue
			if game.has_method("outpost_walkable") and not bool(game.call("outpost_walkable",candidate)): continue
			var score := _ground_distance(soldier.position,candidate)
			if score < best:
				best = score
				chosen = candidate
	return chosen

func artillery_snapshot() -> Dictionary:
	return artillery.snapshot() if is_instance_valid(artillery) else {"launched":0,"impacts":0,"hits":0,
		"pending":0,"casting":0,"flight":0,"shots":[],"units":[]}

func hunter_snapshot() -> Dictionary:
	return hunters.snapshot() if is_instance_valid(hunters) else {"hits": 0, "cancellations": 0,
		"chasing": 0, "casting": 0, "alive": 0, "count": 0, "units": [], "squads": []}

func _squad_position(squad: Dictionary) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for soldier: BattleUnit in squad.members:
		if _living(soldier): total += soldier.position; count += 1
	return total / float(count) if count > 0 else squad.destination

func _move_member(soldier: BattleUnit, destination: Vector3, delta: float) -> void:
	var distance := _ground_distance(soldier.position, destination)
	soldier.moving = distance > .16
	if not soldier.moving: return
	var waypoint := destination
	if game.has_method("day_hunter_waypoint"):
		waypoint = game.call("day_hunter_waypoint", soldier, destination)
	var direction := waypoint - soldier.position
	direction.y = 0
	var previous := soldier.position
	if direction.length() > .02:
		var next := previous + direction.normalized() * minf(direction.length(), soldier.speed * delta)
		next.y = _ground_height(next)
		if _traversable(previous, next): soldier.position = next
		else: soldier.path.clear(); soldier.path_timer = 0.0
	soldier.moving = _ground_distance(previous, soldier.position) > .00001 or distance > .16
	soldier.face(waypoint, delta)
	soldier.attack_queued = false; soldier.target = null

func _attack_line(from: Vector3, to: Vector3) -> bool:
	return bool(game.call("can_attack_line", from, to)) if game.has_method("can_attack_line") else _traversable(from, to)

func _repair_nearby(soldier: BattleUnit, delta: float) -> void:
	var timer := float(soldier.get_meta("support_timer", 1.0)) - delta
	soldier.set_meta("support_timer", maxf(0.0, timer))
	if timer > 0.0: return
	var districts: Node = game.get("districts") as Node
	var cost := int(districts.call("repair_cost", 2)) if is_instance_valid(districts) else 2
	if int(game.get("scrap")) < cost: return
	var candidate: Dictionary = {}
	var candidate_district_index := -1
	var best := 4.2
	var world: Node = game.get("world") as Node
	if is_instance_valid(world):
		for pad: Dictionary in world.get("tower_pads"):
			if int(pad.level) <= 0 or float(pad.hp) <= 0.0 or float(pad.hp) >= float(pad.max_hp): continue
			var distance := _ground_distance(soldier.position, pad.position)
			if distance <= best and _attack_line(soldier.position, pad.position): best = distance; candidate = pad
	if is_instance_valid(districts):
		for plot: Dictionary in districts.get("plots"):
			if int(plot.level) <= 0 or float(plot.get("hp", 0.0)) <= 0.0 or float(plot.get("hp", 0.0)) >= float(plot.get("max_hp", 0.0)): continue
			var distance := _ground_distance(soldier.position, plot.position)
			if distance <= best and _attack_line(soldier.position, plot.position):
				best = distance; candidate = plot; candidate_district_index = int(plot.get("index", -1))
	if candidate.is_empty(): return
	var restored := minf(20.0, float(candidate.max_hp) - float(candidate.hp))
	if restored <= 0.0: return
	game.set("scrap", int(game.get("scrap")) - cost)
	candidate.hp = minf(float(candidate.max_hp), float(candidate.hp) + restored)
	if candidate_district_index >= 0 and districts.has_method("_refresh_label"):
		districts.call("_refresh_label", candidate_district_index)
	if is_instance_valid(candidate.get("damage_ring")): candidate.damage_ring.visible = float(candidate.hp) < float(candidate.max_hp) * .6
	soldier.set_meta("support_timer", 1.0)
	soldier.attack_pose = 1.0
	_beam(soldier.position + Vector3.UP, candidate.position + Vector3.UP, Color("88d18b"))

func _attack(soldier: BattleUnit, delta: float, designated: BattleUnit = null) -> void:
	if String(soldier.get_meta("squad_kind", "")) in ["hauler", "medic", "artillery"]:
		soldier.attack_queued = false; soldier.target = null; soldier.attack_windup = 0.0
		return
	if soldier.attack_queued:
		if not _enemy(soldier.target) or not _in_range(soldier, soldier.target):
			soldier.attack_queued = false; soldier.target = null
			return
		soldier.face(soldier.target.position, delta)
		if soldier.attack_windup > 0.0: return
		var victim := soldier.target
		var impact := victim.position + Vector3.UP
		var generation := _epoch
		soldier.attack_queued = false; soldier.attack_timer = soldier.attack_interval
		soldier.attack_pose = 1.0
		victim.hurt(soldier.damage, soldier) # Never source hero or mark a player attack.
		if not _owns_member(soldier, generation): return
		if str(soldier.get_meta("squad_kind")) == "ballista":
			_beam(soldier.position + Vector3.UP, impact, Color("efb774"), .065, .24, .95)
		elif str(soldier.get_meta("squad_kind")) == "ranged": _beam(soldier.position + Vector3.UP, impact)
		return
	if soldier.attack_timer > 0.0: return
	var target := designated if _enemy(designated) and _in_range(soldier, designated) else _pick_enemy(soldier)
	if not is_instance_valid(target): return
	soldier.target = target
	soldier.attack_queued = true
	soldier.attack_windup = soldier.windup_duration
	soldier.face(target.position, delta)

func _pick_enemy(soldier: BattleUnit, real_only: bool = false) -> BattleUnit:
	var focus: Variant = game.get("focus_target")
	if _enemy(focus) and (not real_only or focus in game.get("enemies")) and float(game.get("focus_time")) > 0.0 and _in_range(soldier, focus as BattleUnit): return focus as BattleUnit
	var selected: BattleUnit
	var score := -INF
	for candidate: Variant in game.get("enemies"):
		# The production list is pruned next simulation frame, after queue_free.
		if not _enemy(candidate): continue
		var enemy := candidate as BattleUnit
		if not _in_range(soldier, enemy): continue
		var candidate_score := -_ground_distance(soldier.position, enemy.position)
		if str(soldier.get_meta("squad_kind")) in ["ranged", "ballista"]:
			var threat := str(enemy.get_meta("threat", ""))
			var priority := int({"breaker": 4, "sapper": 3, "lobber": 3, "light_eater": 2, "shellguard": 4}.get(threat, 0))
			# A finite source can still add real units; ranged fire can prevent
			# those births. Once spent it follows ordinary melee/interception.
			if threat == "summoner" and bool(enemy.get_meta("summoner_active", false)): priority = 5
			if threat == "warder" and bool(enemy.get_meta("warder_active", false)): priority = 5
			candidate_score += float(priority) * 10.0
		if candidate_score > score: selected = enemy; score = candidate_score
	return selected

func _in_range(soldier: BattleUnit, enemy: BattleUnit) -> bool:
	return _ground_distance(soldier.position, enemy.position) <= soldier.attack_range and _attack_line(soldier.position, enemy.position)

func blocker_for(enemy: Variant) -> BattleUnit:
	if not _active() or str(game.get("phase")) != "night" or not _enemy(enemy): return null
	if str(enemy.get_meta("threat", "")) in ["sapper", "light_eater", "lobber"]: return null
	var closest: BattleUnit
	var distance := 3.2
	for squad in squads:
		if squad.kind != "shield" or squad.order not in [HOLD, GUARD, AMOVE, ESCORT]: continue
		for soldier: BattleUnit in squad.members:
			if not _living(soldier) or soldier.moving: continue
			if squad.order in [AMOVE, ESCORT] and not bool(soldier.get_meta("amove_engaged", false)): continue
			var separation := _ground_distance(soldier.position, enemy.position)
			if separation < distance and _traversable(enemy.position, soldier.position):
				closest = soldier; distance = separation
	return closest

func intercept_enemy(enemy: Variant, delta: float) -> bool:
	if not _enemy(enemy): return false
	var key: int = enemy.get_instance_id()
	if not _active(): return _intercepts.has(key) # An accidental paused call must not mutate combat.
	if str(game.get("phase")) != "night" or str(enemy.get_meta("threat", "")) in ["sapper", "light_eater", "lobber"]:
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
		if squad.kind == "shield" and squad.order in [HOLD, GUARD] and soldier in squad.members: return true
		if squad.kind == "shield" and squad.order in [AMOVE, ESCORT] and soldier in squad.members:
			return not soldier.moving and bool(soldier.get_meta("amove_engaged", false))
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
	if is_instance_valid(escort): escort.on_member_defeated(unit)
	if String(unit.get_meta("squad_kind","")) == "artillery" and is_instance_valid(artillery): artillery.unregister(unit)
	if String(unit.get_meta("squad_kind","")) == "hunter" and is_instance_valid(hunters): hunters.unregister(unit)
	var logistics := _logistics()
	if is_instance_valid(logistics): logistics.call("on_member_defeated", unit.get_instance_id())
	# A real casualty invalidates all pending treatments of that exact member
	# immediately. It cannot be paid for or resurrected by a later commit.
	for state: Dictionary in _medic_states.values():
		var target_ref: Variant = state.get("target")
		if target_ref is WeakRef and target_ref.get_ref() == unit:
			var medic: BattleUnit = (state.unit as WeakRef).get_ref() as BattleUnit
			if is_instance_valid(medic): _cancel_medic(medic, "target_invalid")
	_medic_states.erase(unit.get_instance_id())
	# Keep empty slots, without dangling typed references after queue_free.
	for squad in squads:
		for slot in MEMBERS_PER_SQUAD:
			if squad.members[slot] == unit: squad.members[slot] = null
	_refresh_selection()
	unit.visible = false
	unit.queue_free()

func _retire_member(unit: BattleUnit) -> void:
	if is_instance_valid(unit) and not unit.is_queued_for_deletion(): unit.queue_free()

func _animate_member(soldier: BattleUnit) -> void:
	for label in ["LegL", "LegR"]:
		var limb := soldier.visual.find_child(label, true, false) as Node3D
		if limb: limb.rotation.x = sin(soldier.age * 8.0 + (PI if label == "LegR" else 0.0)) * (.32 if soldier.moving else .0)
	var arm := soldier.visual.find_child("ArmR", true, false) as Node3D
	if arm:
		arm.rotation.x = -soldier.attack_pose * .7 - (.25 if bool(soldier.get_meta("medic_casting", false)) else (.2 if soldier.attack_queued else 0.0))

func _beam(from: Vector3, to: Vector3, tint: Color = Color("efcf86"), width: float = .035, lifetime: float = .18, emission: float = 1.2) -> void:
	var offset := to - from
	if not from.is_finite() or not to.is_finite() or offset.length_squared() <= .000001: return
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = width; mesh.bottom_radius = width
	mesh.radial_segments = 6; mesh.height = maxf(.01, from.distance_to(to))
	node.mesh = mesh
	node.material_override = BattleVisuals.material(tint, emission)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.position = (from + to) * .5
	var direction := offset.normalized()
	if absf(direction.dot(Vector3.UP)) < .999: node.quaternion = Quaternion(Vector3.UP, direction)
	shots.append({"node": node, "time": lifetime, "duration": lifetime})

func _advance_shots(delta: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		shots[i].time = maxf(0.0, float(shots[i].time) - delta)
		var node := shots[i].node as MeshInstance3D
		if not is_instance_valid(node): shots.remove_at(i); continue
		if float(shots[i].time) <= 0.0:
			node.queue_free(); shots.remove_at(i)
		else:
			var width_scale := maxf(.01, float(shots[i].time) / float(shots[i].get("duration", .18)))
			node.scale = Vector3(width_scale, 1, width_scale)

func snapshot() -> Dictionary:
	_refresh_selection()
	var rows: Array[Dictionary] = []
	var total_alive := 0
	for squad in squads:
		var count := 0
		var hp := 0.0
		for soldier: BattleUnit in squad.members:
			if _living(soldier): count += 1; hp += soldier.hp
		total_alive += count
		rows.append({"id": squad.id, "kind": squad.kind, "title": String(Catalog.troop(String(squad.kind)).title), "order": squad.order,
			"order_label": "护航工队" if squad.order == ESCORT else String({HOLD: "驻守南门", RECALL: "撤回灯塔", MOVE: "移动", AMOVE: "攻击推进", ATTACK: "攻击", GUARD: "原地驻守", HAUL: "采运"}.get(squad.order, "待命")),
			"alive": count, "capacity": MEMBERS_PER_SQUAD, "hp": hp, "refill_cost": refill_cost(squad.id),
			"position": _squad_position(squad), "selected": int(squad.id) in selected_ids})
	var queues: Array[Dictionary] = []
	var duration_multiplier := 1.0
	var districts: Node = game.get("districts") as Node if is_instance_valid(game) else null
	if is_instance_valid(districts) and districts.has_method("training_duration_multiplier"):
		duration_multiplier = clampf(float(districts.call("training_duration_multiplier")), 0.8, 1.0)
	for barracks in _barracks():
		var queue: Array[Dictionary] = []
		for item: Dictionary in training_queues.get(int(barracks.index), []):
			var copy := item.duplicate()
			copy["eta"] = maxf(0.0, float(item.remaining) * duration_multiplier)
			queue.append(copy)
		queues.append({"index": barracks.index, "position": barracks.position, "level": barracks.level, "queue": queue})
	return {"count": squads.size(), "max_squads": -1, "alive": total_alive,
		"capacity": squads.size() * MEMBERS_PER_SQUAD, "refill_cost": refill_cost(),
		"ranged_enabled": ranged_enabled, "training_duration_multiplier": duration_multiplier,
		"squads": rows, "selected": selected_ids.size(),
		"selected_ids": selected_ids.duplicate(), "queues": queues, "trainings": queues}

func clear() -> void:
	_epoch += 1
	_cancel_intercepts()
	_cancel_medic_casts("clear")
	if is_instance_valid(artillery): artillery.clear()
	if is_instance_valid(hunters): hunters.clear()
	if is_instance_valid(escort): escort.clear()
	for squad in squads:
		for soldier: BattleUnit in squad.members: _retire_member(soldier)
	squads.clear()
	selected_ids.clear()
	training_queues.clear()
	for shot in shots:
		var node := shot.node as Node
		if is_instance_valid(node): node.queue_free()
	shots.clear()
	_has_logistics = false
	_has_hero = false
	_has_construction_blocks = false
	_has_rally = false
	_medic_states.clear()

func _exit_tree() -> void:
	_epoch += 1
	_cancel_intercepts()
	_cancel_medic_casts("clear")
	if is_instance_valid(artillery): artillery.clear()
	if is_instance_valid(hunters): hunters.clear()
	if is_instance_valid(escort): escort.clear()
	_medic_states.clear()
