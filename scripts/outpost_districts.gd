extends Node3D
## Player-positioned buildings with stable identities and paid rebuilding.
const BUILD_COST := 60
const UPGRADE_COST := 80
const MAX_LEVEL := 2
const Layout := preload("res://scripts/outpost_layout.gd")
const INTERACTION_RADIUS := 2.6
const BARRACKS := "barracks"
const WORKSHOP := "workshop"
const BARRACKS_SCENE: PackedScene = preload("res://assets/models/survivor_camp.glb")
const WORKSHOP_SCENE: PackedScene = preload("res://assets/models/day_generator.glb")
const BASE_HEALTH := {BARRACKS: 600.0, WORKSHOP: 450.0}

var game: Node3D
var plots: Array[Dictionary] = []
var _footprints: Dictionary = {}

func setup(owner_game: Node3D) -> void:
	clear()
	game = owner_game
	if get_parent() == null: game.add_child(self)

func clear() -> void:
	for plot: Dictionary in plots:
		if is_instance_valid(plot.node): (plot.node as Node3D).queue_free()
	plots.clear()

func nearest() -> int:
	if not _active() or not is_instance_valid(game.hero): return -1
	var selected := -1
	var distance := INTERACTION_RADIUS
	for index in plots.size():
		var candidate: float = game.hero.position.distance_to(plots[index].position)
		if candidate <= distance:
			selected = index
			distance = candidate
	return selected

func build_at(point: Vector3, kind: String) -> Dictionary:
	if not _active(): return _failure("暂停或选卡时不能建造")
	if kind not in [BARRACKS, WORKSHOP]: return _failure("请选择兵营或工坊")
	var construction: Node3D = game.get("construction") as Node3D
	if not is_instance_valid(construction): return _failure("建设系统尚未初始化")
	var placement: Dictionary = construction.validity(point, -1, kind)
	if not bool(placement.valid): return _failure(String(placement.reason))
	var index := -1
	for candidate in plots.size():
		if int(plots[candidate].level) == 0 and (plots[candidate].position as Vector3).distance_to(placement.point) <= 0.01:
			index = candidate
			break
	if index < 0:
		index = plots.size()
		plots.append(_new_plot(index, placement.point))
	var plot: Dictionary = plots[index]
	game.scrap -= BUILD_COST
	plot.kind = kind
	plot.level = 1
	plot.max_hp = float(BASE_HEALTH[kind])
	plot.hp = plot.max_hp
	_build_model(plot)
	_refresh_label(index)
	_changed()
	return _success(index, BUILD_COST)

func choose(index: int, kind: String) -> Dictionary:
	if index < 0 or index >= plots.size(): return _failure("无效建筑")
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
	plot.level = int(plot.level) + 1
	plot.max_hp = float(BASE_HEALTH[String(plot.kind)]) + 180.0
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
		plot.level = 0
		if is_instance_valid(plot.model): (plot.model as Node3D).queue_free()
		plot.model = null
		(plot.lamp as OmniLight3D).light_energy = 0.0
		_changed()
	_refresh_label(index)
	return {"ok": true, "index": index, "damage": dealt, "hp": float(plot.hp), "destroyed": destroyed, "kind": String(plot.kind)}

func active_barracks() -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	for plot: Dictionary in plots:
		if _living(plot) and String(plot.kind) == BARRACKS:
			active.append({"index": int(plot.index), "id": int(plot.id), "position": plot.position, "level": int(plot.level)})
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
		var level := int(plot.level)
		var kind := String(plot.kind)
		var title := "兵营" if kind == BARRACKS else "工坊"
		var benefit := "据点恢复 +%d/秒 · 部队生命 +%d%%" % [level * 3, level * 20] if kind == BARRACKS else "塔建设与维修减费 · 全城最高20%%"
		if not _living(plot):
			title += "残址"
			benefit = "重新选址到这里可付费重建"
		result.append({"index": index, "id": int(plot.id), "position": plot.position, "kind": kind, "level": level,
			"title": title, "benefit": benefit, "hp": float(plot.hp), "max_hp": float(plot.max_hp),
			"cost": BUILD_COST if level == 0 else UPGRADE_COST, "can_choose": _active() and level == 0,
			"can_upgrade": _active() and _living(plot) and level < MAX_LEVEL})
	return result

func prompt() -> String:
	var index := nearest()
	if index < 0: return ""
	var plot: Dictionary = plots[index]
	var title := "兵营" if String(plot.kind) == BARRACKS else "工坊"
	if not _living(plot): return "%s残址 · 进入建设模式付费重建" % title
	if int(plot.level) < MAX_LEVEL: return "%s一级 · F 升级二级 · 80 零件" % title
	return "%s二级 · 建设完成" % title

func footprint(kind: String) -> Vector2:
	if kind not in [BARRACKS, WORKSHOP]: return Vector2.ZERO
	if not _footprints.has(kind):
		var scene: PackedScene = BARRACKS_SCENE if kind == BARRACKS else WORKSHOP_SCENE
		var model := scene.instantiate() as Node3D
		var bounds := model_bounds(model)
		_footprints[kind] = Vector2(bounds.size.x, bounds.size.z) * model_scale(bounds) * 0.5
		model.free()
	return _footprints[kind]

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
		"model": null, "ring": ring, "label": label, "lamp": lamp, "hp": 0.0, "max_hp": 0.0}

func _build_model(plot: Dictionary) -> void:
	if is_instance_valid(plot.model): (plot.model as Node3D).queue_free()
	var scene: PackedScene = BARRACKS_SCENE if String(plot.kind) == BARRACKS else WORKSHOP_SCENE
	var model := scene.instantiate() as Node3D
	(plot.node as Node3D).add_child(model)
	model.name = "DistrictBuilding"
	prepare_model(model)
	plot.model = model
	(plot.lamp as OmniLight3D).light_energy = 0.55

func _refresh_label(index: int) -> void:
	var plot: Dictionary = plots[index]
	var title := "兵营" if String(plot.kind) == BARRACKS else "工坊"
	(plot.label as Label3D).text = "%s · %d级 · %d/%d" % [title, int(plot.level), ceili(float(plot.hp)), ceili(float(plot.max_hp))] if _living(plot) else title + "残址"
	(plot.ring as MeshInstance3D).material_override = BattleVisuals.material(Color("e0b36d") if _living(plot) else Color("805b51"), 0.25)

func _levels(kind: String) -> int:
	var total := 0
	for plot: Dictionary in plots:
		if _living(plot) and String(plot.kind) == kind: total += int(plot.level)
	return total

func _living(plot: Dictionary) -> bool:
	return int(plot.get("level", 0)) > 0 and float(plot.get("hp", 0.0)) > 0.0

func _active() -> bool:
	return is_instance_valid(game) and String(game.phase) in ["day", "night"]

func _can_change(index: int) -> Dictionary:
	if not is_instance_valid(game): return _failure("建设系统尚未初始化")
	if not _active(): return _failure("暂停或选卡时不能建设")
	if index < 0 or index >= plots.size(): return _failure("无效建筑")
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
