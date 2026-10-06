extends Node3D
## Player-positioned buildings with stable identities and paid rebuilding.
const BUILD_COST := 60
const UPGRADE_COST := 80
const MAX_LEVEL := 2
const Layout := preload("res://scripts/outpost_layout.gd")
const Catalog := preload("res://scripts/outpost_catalog.gd")
const INTERACTION_RADIUS := 2.6
const BARRACKS := "barracks"
const WORKSHOP := "workshop"
const RECYCLER := "recycler"
const LABORATORY := "laboratory"
const DEPOT := "depot"
const INFIRMARY := "infirmary"
const ARMORY := "armory"
const BARRACKS_SCENE: PackedScene = preload("res://assets/models/survivor_camp.glb")
const WORKSHOP_SCENE: PackedScene = preload("res://assets/models/day_generator.glb")
const BASE_HEALTH := {BARRACKS: 600.0, WORKSHOP: 450.0, RECYCLER: 500.0, LABORATORY: 550.0, DEPOT: 500.0, INFIRMARY: 480.0, ARMORY: 600.0}
const RECOVERY_RADIUS := 12.0
const RECOVERY_NIGHT_CAP := 24
const WRECK_SCRAP := 2

var game: Node3D
var plots: Array[Dictionary] = []
var _footprints: Dictionary = {}
var _wreck_ids: Dictionary = {}
var _begun_nights: Dictionary = {}
var _recovery_day := -1
var _captured_scrap := 0

func setup(owner_game: Node3D) -> void:
	clear()
	game = owner_game
	if get_parent() == null: game.add_child(self)

func clear() -> void:
	for plot: Dictionary in plots:
		if is_instance_valid(plot.node): (plot.node as Node3D).queue_free()
	plots.clear()
	_wreck_ids.clear()
	_begun_nights.clear()
	_recovery_day = -1
	_captured_scrap = 0
	game = null

func has_live(kind: String) -> bool:
	for plot: Dictionary in plots:
		if String(plot.kind) == kind and _living(plot): return true
	return false

func build_eligibility(kind: String) -> Dictionary:
	return _technology_eligibility(Catalog.building(kind), "未知建筑")

func training_eligibility(kind: String) -> Dictionary:
	return _technology_eligibility(Catalog.troop(kind), "未知兵种")

func _technology_eligibility(definition: Dictionary, unknown_reason: String) -> Dictionary:
	var missing: Array[String] = []
	var titles: Array[String] = []
	if definition.is_empty(): return {"available": false, "reason": unknown_reason, "missing": missing}
	for prerequisite: String in definition.requires:
		if has_live(prerequisite): continue
		missing.append(prerequisite)
		titles.append(String(Catalog.building(prerequisite).get("title", prerequisite)))
	return {"available": missing.is_empty(), "reason": "" if missing.is_empty() else "需要存活%s" % "、".join(titles), "missing": missing}

func begin_night(day: int) -> void:
	if not _active() or String(game.phase) != "night" or day < 1 or day != _current_night_day() or _begun_nights.has(day): return
	_begun_nights[day] = true
	_recovery_day = day
	_captured_scrap = 0

func register_wreck(id: int, point: Vector3) -> Dictionary:
	if not _active() or String(game.phase) != "night" or _recovery_day < 1 or _recovery_day != _current_night_day():
		return {"accepted": false, "reason": "只回收夜袭的真实残骸"}
	if id < 0 or not point.is_finite() or _wreck_ids.has(id): return {"accepted": false, "reason": "无效或重复残骸"}
	# Remember every observed death, including out-of-range/capped deaths: it
	# cannot become a second wreck after another station or night is created.
	_wreck_ids[id] = true
	if _captured_scrap + WRECK_SCRAP > RECOVERY_NIGHT_CAP: return {"accepted": false, "reason": "本夜回收额度已满"}
	var nearest_index := -1
	var nearest_distance := RECOVERY_RADIUS
	for index in plots.size():
		var plot: Dictionary = plots[index]
		if String(plot.kind) != RECYCLER or not _living(plot): continue
		var distance: float = point.distance_to(plot.position)
		if distance <= nearest_distance:
			nearest_index = index
			nearest_distance = distance
	if nearest_index < 0: return {"accepted": false, "reason": "附近没有存活回收站"}
	var selected: Dictionary = plots[nearest_index]
	selected.pending = int(selected.pending) + WRECK_SCRAP
	_captured_scrap += WRECK_SCRAP
	_refresh_label(nearest_index)
	return {"accepted": true, "index": nearest_index, "pending": int(selected.pending), "amount": WRECK_SCRAP,
		"recovery_cap_remaining": RECOVERY_NIGHT_CAP - _captured_scrap}

func tick(delta: float) -> void:
	if not _active() or not is_finite(delta) or delta <= 0.0: return
	for index in plots.size():
		var plot: Dictionary = plots[index]
		if String(plot.kind) != RECYCLER or not _living(plot): continue
		if int(plot.pending) < WRECK_SCRAP:
			plot.recovery_elapsed = 0.0
			continue
		plot.recovery_elapsed = float(plot.recovery_elapsed) + delta
		var interval := _recovery_interval(plot)
		var paid := false
		while int(plot.pending) >= WRECK_SCRAP and float(plot.recovery_elapsed) >= interval:
			plot.recovery_elapsed = float(plot.recovery_elapsed) - interval
			plot.pending = int(plot.pending) - WRECK_SCRAP
			plot.recovered = int(plot.recovered) + WRECK_SCRAP
			game.scrap += WRECK_SCRAP
			paid = true
		if int(plot.pending) < WRECK_SCRAP: plot.recovery_elapsed = 0.0
		if paid: _refresh_label(index)

func _recovery_interval(plot: Dictionary) -> float:
	return 3.0 if int(plot.level) >= 2 else 4.0

func _current_night_day() -> int:
	if not is_instance_valid(game): return -1
	for property: Dictionary in game.get_property_list():
		if String(property.name) == "day_number": return int(game.get("day_number"))
	return -1

func nearest() -> int:
	if not _active() or not is_instance_valid(game.hero): return -1
	var selected := -1
	var distance := INTERACTION_RADIUS
	for index in plots.size():
		if bool(plots[index].get("removed", false)): continue
		var candidate: float = game.hero.position.distance_to(plots[index].position)
		if candidate <= distance:
			selected = index
			distance = candidate
	return selected

func build_at(point: Vector3, kind: String) -> Dictionary:
	if not _active(): return _failure("暂停或选卡时不能建造")
	var definition := Catalog.building(kind)
	if definition.is_empty() or kind == "tower": return _failure("请选择城区建筑")
	var technology := build_eligibility(kind)
	if not bool(technology.available): return _failure(String(technology.reason))
	var construction: Node3D = game.get("construction") as Node3D
	if not is_instance_valid(construction): return _failure("建设系统尚未初始化")
	var placement: Dictionary = construction.validity(point, -1, kind)
	if not bool(placement.valid): return _failure(String(placement.reason))
	# Final payment authority checks current technology and balance again.
	technology = build_eligibility(kind)
	if not bool(technology.available): return _failure(String(technology.reason))
	var cost := int(definition.cost)
	if int(game.scrap) < cost: return _failure("零件不足 · 需要%d" % cost)
	var index := -1
	for candidate in plots.size():
		if not bool(plots[candidate].get("removed", false)) and int(plots[candidate].level) == 0 and (plots[candidate].position as Vector3).distance_to(placement.point) <= 0.01:
			index = candidate
			break
	if index < 0:
		index = plots.size()
		plots.append(_new_plot(index, placement.point))
	var plot: Dictionary = plots[index]
	game.scrap -= cost
	# Only this generation's actual payment is refundable after a rebuild.
	plot.paid_investment = cost
	plot.kind = kind
	plot.level = 1
	plot.max_hp = float(definition.hp)
	plot.hp = plot.max_hp
	plot.pending = 0
	plot.recovery_elapsed = 0.0
	plot.recovered = 0
	_build_model(plot)
	_refresh_label(index)
	_changed()
	return _success(index, cost)

func choose(index: int, kind: String) -> Dictionary:
	var allowed := _can_change(index)
	if not allowed.ok: return allowed
	if int(plots[index].level) > 0: return _failure("已建建筑不能更换方向")
	return build_at(plots[index].position, kind)

func upgrade(index: int) -> Dictionary:
	var allowed := _can_change(index)
	if not allowed.ok: return allowed
	var plot: Dictionary = plots[index]
	if not _living(plot): return _failure("请先重建建筑")
	if int(plot.level) >= MAX_LEVEL: return _failure("建筑已达到二级")
	if int(game.scrap) < UPGRADE_COST: return _failure("升级需要 80 零件")
	game.scrap -= UPGRADE_COST
	plot.paid_investment = maxi(0, int(plot.get("paid_investment", 0))) + UPGRADE_COST
	plot.level = int(plot.level) + 1
	plot.max_hp = float(Catalog.building(String(plot.kind)).hp) + 180.0
	plot.hp = plot.max_hp
	(plot.lamp as OmniLight3D).light_energy = 0.72
	_refresh_label(index)
	_changed()
	return _success(index, UPGRADE_COST)

func damage(index: int, amount: float) -> Dictionary:
	var allowed := _can_change(index)
	if not allowed.ok: return allowed
	if not is_finite(amount) or amount <= 0.0: return _failure("无效伤害")
	var plot: Dictionary = plots[index]
	if not _living(plot): return _failure("建筑已经损毁")
	var dealt := minf(float(plot.hp), amount)
	plot.hp = maxf(0.0, float(plot.hp) - amount)
	var destroyed := float(plot.hp) <= 0.0
	if destroyed:
		plot.paid_investment = 0
		plot.level = 0
		plot.pending = 0
		plot.recovery_elapsed = 0.0
		if is_instance_valid(plot.model): (plot.model as Node3D).queue_free()
		plot.model = null
		(plot.lamp as OmniLight3D).light_energy = 0.0
		_changed()
	_refresh_label(index)
	return {"ok": true, "index": index, "damage": dealt, "hp": float(plot.hp), "destroyed": destroyed, "kind": String(plot.kind)}

func demolition_quote(index: int) -> Dictionary:
	var result := {"ok": false, "reason": "", "index": index, "kind": "", "refund": 0,
		"investment": 0, "live": false, "queue_refund": 0}
	var allowed := _can_change(index)
	if not allowed.ok:
		result.reason = String(allowed.reason)
		return result
	var plot: Dictionary = plots[index]
	var live := _living(plot)
	var investment := maxi(0, int(plot.get("paid_investment", 0))) if live else 0
	result.merge({"ok": true, "kind": String(plot.kind), "investment": investment,
		"live": live, "refund": floori(float(investment) * .5), "queue_refund": _queued_refund(index)}, true)
	return result

func demolish(index: int) -> Dictionary:
	# Requote at commit; previews never consume investment or training receipts.
	var quote := demolition_quote(index)
	if not bool(quote.ok): return quote
	var plot: Dictionary = plots[index]
	var anchor: Variant = plot.get("node")
	var refund := int(quote.refund)
	var queue_refund := int(quote.queue_refund)
	# End the identity before paying or invoking callbacks. Even a zero-refund
	# ruin is consumed once, and its stable index is never reused after removal.
	plot.removed = true
	plot.paid_investment = 0
	plot.level = 0
	plot.hp = 0.0
	plot.max_hp = 0.0
	plot.pending = 0
	plot.recovery_elapsed = 0.0
	plot.recovered = 0
	for reference: String in ["model", "node", "ring", "label", "lamp"]: plot[reference] = null
	if is_instance_valid(anchor): (anchor as Node).queue_free()
	game.scrap += refund
	# The existing barracks refresh refunds each unfinished training receipt,
	# separately from this building's investment, and consumes its queue once.
	_changed()
	return {"ok": true, "reason": "", "index": index, "kind": String(quote.kind), "refund": refund,
		"queue_refund": queue_refund, "investment": int(quote.investment), "live": bool(quote.live),
		"removed": true, "scrap": int(game.scrap)}

func _queued_refund(index: int) -> int:
	if String(plots[index].kind) != BARRACKS: return 0
	for property: Dictionary in game.get_property_list():
		if String(property.name) != "squads": continue
		var squads: Node = game.get("squads") as Node
		if not is_instance_valid(squads): return 0
		for squad_property: Dictionary in squads.get_property_list():
			if String(squad_property.name) != "training_queues": continue
			var queues: Dictionary = squads.get("training_queues")
			var refund := 0
			for item: Dictionary in queues.get(index, []): refund += maxi(0, int(item.cost))
			return refund
		return 0
	return 0

func active_barracks() -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	for plot: Dictionary in plots:
		if _living(plot) and String(plot.kind) == BARRACKS:
			active.append({"index": int(plot.index), "id": int(plot.id), "position": plot.position, "level": int(plot.level)})
	return active

func active_depots() -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	for plot: Dictionary in plots:
		if not _living(plot) or String(plot.kind) != DEPOT: continue
		if not is_instance_valid(plot.node) or not is_instance_valid(plot.model): continue
		# Rebuilding reuses the plot id but creates a new model identity. Cargo
		# orders can check this token without retaining freed scene objects.
		active.append({"index": int(plot.index), "id": int(plot.id), "position": plot.position, "level": int(plot.level),
			"token": int(plot.model.get_instance_id()), "node": weakref(plot.node), "model": weakref(plot.model)})
	return active

func guard_regen(point: Vector3) -> float:
	if not is_instance_valid(game) or not point.is_finite() or not Layout.contains_castle(point): return 0.0
	if not game.outpost_walkable(point) or absf(point.y - float(game.outpost_height(point))) > 0.75: return 0.0
	return float(_levels(BARRACKS)) * 3.0

func squad_health_multiplier() -> float:
	return minf(3.0, 1.0 + float(_levels(BARRACKS)) * 0.2)

func tower_cost(base: int) -> int:
	var discount := minf(0.2, float(_levels(WORKSHOP)) * 0.1)
	return maxi(0, ceili(float(base) * (1.0 - discount)))

func repair_cost(base: int) -> int:
	return tower_cost(base)

func snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in plots.size():
		var plot: Dictionary = plots[index]
		if bool(plot.get("removed", false)): continue
		var level := int(plot.level)
		var kind := String(plot.kind)
		var definition := Catalog.building(kind)
		var title := String(definition.get("title", "建筑"))
		var benefit := ""
		match kind:
			BARRACKS: benefit = "据点恢复 +%d/秒 · 部队生命 +%d%%" % [level * 3, level * 20]
			WORKSHOP: benefit = "塔建设与维修减费 · 全城最高20%%"
			RECYCLER: benefit = "12米内夜袭残骸 · %.0f秒加工2零件 · 全城每夜24上限" % _recovery_interval(plot)
			LABORATORY: benefit = "存活时解锁重弩组 · 前置兵营与工坊"
			DEPOT: benefit = "工队真实返站才入账 · 有限废料 · 二级卸货更快"
			INFIRMARY: benefit = "存活时解锁医护队 · 治疗须在部队页开启并付费"
			ARMORY: benefit = "存活时解锁迫击炮队 · 前置研究所与工坊"
		if not _living(plot):
			title += "残址"
			benefit = "重新选址到这里可付费重建"
		result.append({"index": index, "id": int(plot.id), "position": plot.position, "kind": kind, "level": level,
			"title": title, "benefit": benefit, "hp": float(plot.hp), "max_hp": float(plot.max_hp),
			"cost": int(definition.get("cost", BUILD_COST)) if level == 0 else UPGRADE_COST, "can_choose": _active() and level == 0,
			"pending": int(plot.pending), "recovered": int(plot.recovered),
			"recovery_progress": clampf(float(plot.recovery_elapsed) / _recovery_interval(plot), 0.0, 1.0),
			"recovery_cap_remaining": RECOVERY_NIGHT_CAP - _captured_scrap,
			"can_upgrade": _active() and _living(plot) and level < MAX_LEVEL})
	return result

func prompt() -> String:
	var index := nearest()
	if index < 0: return ""
	var plot: Dictionary = plots[index]
	var title := String(Catalog.building(String(plot.kind)).get("title", "建筑"))
	if not _living(plot): return "%s残址 · 进入建设模式付费重建" % title
	if int(plot.level) < MAX_LEVEL: return "%s一级 · F 升级二级 · 80 零件" % title
	return "%s二级 · 建设完成" % title

func footprint(kind: String) -> Vector2:
	if kind not in [BARRACKS, WORKSHOP, RECYCLER, LABORATORY, DEPOT, INFIRMARY, ARMORY]: return Vector2.ZERO
	if not _footprints.has(kind):
		var model := create_model(kind)
		var bounds := model_bounds(model)
		_footprints[kind] = Vector2(bounds.size.x, bounds.size.z) * Vector2(model.scale.x, model.scale.z) * 0.5
		model.free()
	return _footprints[kind]

func create_model(kind: String) -> Node3D:
	if kind not in [BARRACKS, WORKSHOP, RECYCLER, LABORATORY, DEPOT, INFIRMARY, ARMORY]: return null
	var scene: PackedScene = BARRACKS_SCENE if kind in [BARRACKS, LABORATORY, INFIRMARY] else WORKSHOP_SCENE
	var base := scene.instantiate() as Node3D
	prepare_model(base)
	if kind in [BARRACKS, WORKSHOP]: return base
	# New types share the editable original assets, with purpose-specific native
	# geometry. The same factory is used by real buildings and construction.
	var model := Node3D.new()
	model.name = "RecyclerPrototype" if kind == RECYCLER else "LaboratoryPrototype" if kind == LABORATORY else "DepotPrototype" if kind == DEPOT else "ArmoryPrototype" if kind == ARMORY else "InfirmaryPrototype"
	model.set_meta("building_kind", kind)
	model.add_child(base)
	var steel := BattleVisuals.material(Color("384e54"))
	var copper := BattleVisuals.material(Color("b58653"))
	var glass := BattleVisuals.material(Color("7299b1"))
	if kind == RECYCLER:
		for side in [-1.0, 1.0]:
			var bin := BattleVisuals.box(model, Vector3(side * 0.92, 0.48, 0.8), Vector3(0.58, 0.85, 0.7), steel)
			bin.name = "SalvageHopper"
			for item in 3:
				var debris := BattleVisuals.box(model, Vector3(side * 0.92, 0.94 + item * 0.075, 0.8), Vector3(0.38, 0.07, 0.42), copper)
				debris.rotation.y = float(item) * 0.65
		var press := BattleVisuals.box(model, Vector3(0, 1.52, 0.85), Vector3(1.0, 0.32, 0.38), copper)
		press.name = "RecoveryPress"
	elif kind == LABORATORY:
		var bench := BattleVisuals.box(model, Vector3(1.42, 0.64, 0.3), Vector3(0.55, 0.65, 0.95), steel)
		bench.name = "ResearchBench"
		var apparatus := BattleVisuals.box(model, Vector3(1.42, 1.19, 0.3), Vector3(0.32, 0.5, 0.5), glass)
		apparatus.name = "ResearchApparatus"
		var mast := BattleVisuals.box(model, Vector3(-1.5, 1.03, 0.7), Vector3(0.09, 2.02, 0.09), copper)
		mast.name = "ResearchAntenna"
		BattleVisuals.box(model, Vector3(-1.5, 1.95, 0.7), Vector3(0.6, 0.07, 0.07), copper)
	elif kind == DEPOT:
		# The original workshop and this real cargo dock stay within the 3x3
		# building cells. Construction previews use this same measured geometry.
		var dock := BattleVisuals.box(model, Vector3(0, 0.16, 1.13), Vector3(2.58, 0.26, 0.5), steel)
		dock.name = "CargoDock"
		for side in [-1.0, 1.0]:
			var crate := BattleVisuals.box(model, Vector3(side * 0.72, 0.50, 1.12), Vector3(0.50, 0.42, 0.44), copper)
			crate.name = "CargoCrate"
			BattleVisuals.box(model, Vector3(side * 0.72, 0.72, 1.12), Vector3(0.54, 0.055, 0.48), steel)
		var mast := BattleVisuals.box(model, Vector3(1.18, 0.95, -1.13), Vector3(0.07, 1.5, 0.07), steel)
		mast.name = "CargoMarker"
		var cargo_sign := BattleVisuals.box(model, Vector3(1.05, 1.61, -1.13), Vector3(0.44, 0.34, 0.07), copper)
		cargo_sign.name = "CargoSign"
		BattleVisuals.box(model, Vector3(1.05, 1.61, -1.175), Vector3(0.24, 0.05, 0.03), steel)
	elif kind == ARMORY:
		# Shared workshop plus real tube-rack geometry, all within the 4x3 cells.
		# This building only unlocks artillery; there is no passive income or ammo wallet.
		var rack := BattleVisuals.box(model, Vector3(1.60, 0.33, 0.30), Vector3(0.60, 0.60, 1.15), steel)
		rack.name = "ArmoryTubeRack"
		for front in [-1.0, 1.0]:
			var mount := Node3D.new()
			mount.name = "ArmoryMortarTube"
			model.add_child(mount)
			mount.position = Vector3(1.60, 0.60, 0.30 + front * 0.31)
			mount.rotation.x = 0.33
			var barrel := MeshInstance3D.new()
			var tube := CylinderMesh.new()
			tube.top_radius = 0.13
			tube.bottom_radius = 0.16
			tube.height = 0.98
			tube.radial_segments = 16
			tube.rings = 2
			barrel.mesh = tube
			barrel.material_override = steel
			mount.add_child(barrel)
			barrel.position.y = 0.55
			var muzzle := MeshInstance3D.new()
			var rim := TorusMesh.new()
			rim.inner_radius = 0.105
			rim.outer_radius = 0.16
			rim.rings = 16
			rim.ring_segments = 6
			muzzle.mesh = rim
			muzzle.material_override = copper
			mount.add_child(muzzle)
			muzzle.position.y = 1.06
		var store := BattleVisuals.box(model, Vector3(-1.60, 0.40, 0.30), Vector3(0.58, 0.70, 0.94), copper)
		store.name = "ArmorySupplyCase"
		BattleVisuals.box(model, Vector3(-1.60, 0.78, 0.30), Vector3(0.60, 0.06, 0.96), steel)
	else:
		# This station only unlocks paid medical squads. Supply cases and a cyan
		# marker identify the shared camp prototype without adding passive healing.
		var medicine := BattleVisuals.material(Color("d4dfd9"))
		var medical_mark := BattleVisuals.material(Color("77d4ce"), 0.12)
		for side in [-1.0, 1.0]:
			var case := BattleVisuals.box(model, Vector3(side * 0.80, 0.42, 1.07), Vector3(0.48, 0.42, 0.48), medicine)
			case.name = "MedicalSupplyCase"
			BattleVisuals.box(model, Vector3(side * 0.80, 0.66, 1.07), Vector3(0.50, 0.06, 0.50), steel)
			BattleVisuals.box(model, Vector3(side * 0.80, 0.697, 1.07), Vector3(0.23, 0.014, 0.055), medical_mark)
			for end in [-1.0, 1.0]:
				BattleVisuals.box(model, Vector3(side * 0.80, 0.697, 1.07 + end * 0.07125), Vector3(0.055, 0.014, 0.0875), medical_mark)
		var mast := BattleVisuals.box(model, Vector3(1.14, 0.92, -1.12), Vector3(0.06, 1.58, 0.06), steel)
		mast.name = "MedicalMarkerMast"
		var sign := BattleVisuals.box(model, Vector3(0.98, 1.68, -1.12), Vector3(0.48, 0.50, 0.08), steel)
		sign.name = "CyanMedicalMarker"
		for face in [-1.0, 1.0]:
			BattleVisuals.box(model, Vector3(0.98, 1.68, -1.12 + face * 0.053), Vector3(0.30, 0.075, 0.024), medical_mark)
			for end in [-1.0, 1.0]:
				BattleVisuals.box(model, Vector3(0.98, 1.68 + end * 0.09375, -1.12 + face * 0.053), Vector3(0.075, 0.1125, 0.024), medical_mark)
	return model

func prepare_model(model: Node3D) -> void:
	var bounds := model_bounds(model)
	var factor := model_scale(bounds)
	model.scale *= factor
	model.position = Vector3(-(bounds.position.x + bounds.size.x * 0.5) * factor, -bounds.position.y * factor,
		-(bounds.position.z + bounds.size.z * 0.5) * factor)

func model_scale(bounds: AABB) -> float:
	return minf(1.0, minf(2.7 / maxf(maxf(bounds.size.x, bounds.size.z), 0.01), 2.15 / maxf(bounds.size.y, 0.01)))

func model_bounds(model: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	for child: Node in model.get_children(): _collect_bounds(child, Transform3D.IDENTITY, boxes)
	var combined := AABB()
	for index in boxes.size(): combined = boxes[index] if index == 0 else combined.merge(boxes[index])
	return combined

func _collect_bounds(node: Node, parent_transform: Transform3D, boxes: Array[AABB]) -> void:
	var transform := parent_transform
	if node is Node3D: transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		boxes.append(transform * (node as MeshInstance3D).get_aabb())
	for child: Node in node.get_children(): _collect_bounds(child, transform, boxes)

func _new_plot(index: int, point: Vector3) -> Dictionary:
	var anchor := Node3D.new()
	anchor.name = "DistrictBuilding%d" % index
	add_child(anchor)
	anchor.position = point
	var ring := BattleVisuals.ring(anchor, Vector3(0, 0.08, 0), 1.3, Color("927e55"), 0.035)
	var label := Label3D.new()
	anchor.add_child(label)
	label.position = Vector3(0, 2.35, 0)
	label.font_size = 30
	label.pixel_size = 0.0055
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 5
	label.modulate = Color("dbbd84")
	var lamp := OmniLight3D.new()
	anchor.add_child(lamp)
	lamp.position = Vector3(0, 1.75, 0)
	lamp.light_color = Color("e7b779")
	lamp.omni_range = 3.3
	lamp.light_energy = 0.0
	lamp.shadow_enabled = false
	return {"index": index, "id": index, "position": point, "kind": "", "level": 0, "node": anchor,
		"removed": false, "paid_investment": 0,
		"model": null, "ring": ring, "label": label, "lamp": lamp, "hp": 0.0, "max_hp": 0.0,
		"pending": 0, "recovery_elapsed": 0.0, "recovered": 0}

func _build_model(plot: Dictionary) -> void:
	if is_instance_valid(plot.model): (plot.model as Node3D).queue_free()
	var model := create_model(String(plot.kind))
	(plot.node as Node3D).add_child(model)
	model.name = "DistrictBuilding"
	plot.model = model
	(plot.lamp as OmniLight3D).light_energy = 0.55

func _refresh_label(index: int) -> void:
	var plot: Dictionary = plots[index]
	if bool(plot.get("removed", false)): return
	var title := String(Catalog.building(String(plot.kind)).get("title", "建筑"))
	(plot.label as Label3D).text = "%s · %d级 · %d/%d" % [title, int(plot.level), ceili(float(plot.hp)), ceili(float(plot.max_hp))] if _living(plot) else title + "残址"
	if String(plot.kind) == RECYCLER and _living(plot) and int(plot.pending) > 0:
		(plot.label as Label3D).text += "\n待处理 %d 零件" % int(plot.pending)
	(plot.ring as MeshInstance3D).material_override = BattleVisuals.material(Color("e0b36d") if _living(plot) else Color("805b51"), 0.25)

func _levels(kind: String) -> int:
	var total := 0
	for plot: Dictionary in plots:
		if _living(plot) and String(plot.kind) == kind: total += int(plot.level)
	return total

func _living(plot: Dictionary) -> bool:
	return not bool(plot.get("removed", false)) and int(plot.get("level", 0)) > 0 and float(plot.get("hp", 0.0)) > 0.0

func _active() -> bool:
	return is_instance_valid(game) and String(game.phase) in ["day", "night"]

func _can_change(index: int) -> Dictionary:
	if not is_instance_valid(game): return _failure("建设系统尚未初始化")
	if not _active(): return _failure("暂停或选卡时不能建设")
	if index < 0 or index >= plots.size(): return _failure("无效建筑")
	if bool(plots[index].get("removed", false)): return _failure("建筑已拆除")
	return {"ok": true, "reason": ""}

func _changed() -> void:
	if game.has_method("refresh_construction_navigation"): game.call("refresh_construction_navigation")
	for property: Dictionary in game.get_property_list():
		if String(property.name) != "squads": continue
		var squads: Node = game.get("squads") as Node
		if is_instance_valid(squads) and squads.has_method("set_health_multiplier"):
			squads.call("set_health_multiplier", squad_health_multiplier())
		if is_instance_valid(squads) and squads.has_method("refresh_barracks"):
			squads.call("refresh_barracks")
		break

func _success(index: int, cost: int) -> Dictionary:
	var plot: Dictionary = plots[index]
	return {"ok": true, "reason": "", "index": index, "id": int(plot.id), "cost": cost,
		"scrap": int(game.scrap), "kind": String(plot.kind), "level": int(plot.level), "hp": float(plot.hp)}

func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "cost": 0, "scrap": int(game.scrap) if is_instance_valid(game) else 0}
