extends Node3D
## 两处局内建设地块；建筑收益不跨局，塔与英雄接入由主控制器负责。

const BUILD_COST: int = 60
const UPGRADE_COST: int = 80
const MAX_LEVEL: int = 2
const INTERACTION_RADIUS: float = 2.6
const BARRACKS: String = "barracks"
const WORKSHOP: String = "workshop"
const PLOT_POINTS: Array[Vector3] = [Vector3(-5.4, 5.0, -4.0), Vector3(5.4, 5.0, -4.0)]
const BARRACKS_SCENE: PackedScene = preload("res://assets/models/survivor_camp.glb")
const WORKSHOP_SCENE: PackedScene = preload("res://assets/models/day_generator.glb")

var game: Node3D
var plots: Array[Dictionary] = []

func setup(owner_game: Node3D) -> void:
	clear()
	game = owner_game
	if get_parent() == null:
		game.add_child(self)
	for index in range(PLOT_POINTS.size()):
		var point: Vector3 = PLOT_POINTS[index]
		point.y = float(game.outpost_height(point))
		if not game.outpost_walkable(point):
			push_error("城区地块位于不可通行区域: %s" % point)
			continue
		var anchor: Node3D = Node3D.new()
		anchor.name = "DistrictPlot%d" % index
		add_child(anchor)
		anchor.position = point
		var ring: MeshInstance3D = BattleVisuals.ring(anchor, Vector3(0, 0.08, 0), 1.3, Color("927e55"), 0.035)
		var label: Label3D = Label3D.new()
		anchor.add_child(label)
		label.position = Vector3(0, 2.35, 0)
		label.font_size = 30
		label.pixel_size = 0.0055
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 5
		label.modulate = Color("dbbd84")
		var lamp: OmniLight3D = OmniLight3D.new()
		anchor.add_child(lamp)
		lamp.position = Vector3(0, 1.75, 0)
		lamp.light_color = Color("e7b779")
		lamp.omni_range = 3.3
		lamp.light_energy = 0.0
		lamp.shadow_enabled = false
		var plot: Dictionary = {"position": point, "kind": "", "level": 0, "node": anchor, "model": null, "ring": ring, "label": label, "lamp": lamp}
		plots.append(plot)
		_refresh_label(index)

func clear() -> void:
	for plot in plots:
		var node: Node3D = plot.node
		if is_instance_valid(node):
			node.queue_free()
	plots.clear()

func nearest() -> int:
	if not is_instance_valid(game) or game.phase != "day" or not is_instance_valid(game.hero):
		return -1
	var selected: int = -1
	var distance: float = INTERACTION_RADIUS
	for index in range(plots.size()):
		var candidate: float = game.hero.position.distance_to(plots[index].position)
		if candidate <= distance:
			selected = index
			distance = candidate
	return selected

func choose(index: int, kind: String) -> Dictionary:
	var allowed: Dictionary = _can_change(index)
	if not allowed.ok:
		return allowed
	if kind not in [BARRACKS, WORKSHOP]:
		return _failure("请选择兵营或工坊")
	var plot: Dictionary = plots[index]
	if int(plot.level) > 0:
		return _failure("已建城区不能更换方向")
	if int(game.scrap) < BUILD_COST:
		return _failure("建造需要 60 零件")
	game.scrap -= BUILD_COST
	plot.kind = kind
	plot.level = 1
	_build_model(plot)
	_refresh_label(index)
	return {"ok": true, "reason": "", "cost": BUILD_COST, "scrap": int(game.scrap), "index": index, "kind": kind, "level": 1}

func upgrade(index: int) -> Dictionary:
	var allowed: Dictionary = _can_change(index)
	if not allowed.ok:
		return allowed
	var plot: Dictionary = plots[index]
	if int(plot.level) == 0:
		return _failure("先选择城区方向")
	if int(plot.level) >= MAX_LEVEL:
		return _failure("城区已达到二级")
	if int(game.scrap) < UPGRADE_COST:
		return _failure("升级需要 80 零件")
	game.scrap -= UPGRADE_COST
	plot.level = int(plot.level) + 1
	(plot.lamp as OmniLight3D).light_energy = 0.72
	_refresh_label(index)
	return {"ok": true, "reason": "", "cost": UPGRADE_COST, "scrap": int(game.scrap), "index": index, "kind": String(plot.kind), "level": int(plot.level)}

func guard_regen(point: Vector3) -> float:
	if not is_instance_valid(game) or absf(point.x) > 6.4 or absf(point.z) > 6.4:
		return 0.0
	if not game.outpost_walkable(point) or absf(point.y - float(game.outpost_height(point))) > 0.75:
		return 0.0
	return float(_levels(BARRACKS)) * 3.0

func squad_health_multiplier() -> float:
	return 1.0 + float(_levels(BARRACKS)) * 0.2

func tower_cost(base: int) -> int:
	var discount: float = minf(0.2, float(_levels(WORKSHOP)) * 0.1)
	return maxi(0, ceili(float(base) * (1.0 - discount)))

func repair_cost(base: int) -> int:
	return tower_cost(base)

func snapshots() -> Array[Dictionary]:
	var snapshots_list: Array[Dictionary] = []
	for index in range(plots.size()):
		var plot: Dictionary = plots[index]
		var level: int = int(plot.level)
		var kind: String = String(plot.kind)
		var title: String = "空闲地块" if level == 0 else ("兵营" if kind == BARRACKS else "工坊")
		var benefit: String = "选择兵营恢复驻守，或工坊节省建设" if level == 0 else ("据点恢复 +%d/秒 · 小队生命 +%d%%" % [level * 3, level * 20] if kind == BARRACKS else "塔建造与维修费用 -%d%%" % (level * 10))
		var allowed: Dictionary = _can_change(index)
		snapshots_list.append({"index": index, "position": plot.position, "kind": kind, "level": level, "title": title, "benefit": benefit, "cost": BUILD_COST if level == 0 else UPGRADE_COST, "can_choose": allowed.ok and level == 0, "can_upgrade": allowed.ok and level > 0 and level < MAX_LEVEL})
	return snapshots_list

func prompt() -> String:
	var index: int = nearest()
	if index < 0:
		return ""
	var plot: Dictionary = plots[index]
	if int(plot.level) == 0:
		return "城区地块 · 选择兵营 / 工坊 · 60 零件"
	var title: String = "兵营" if plot.kind == BARRACKS else "工坊"
	if int(plot.level) < MAX_LEVEL:
		return "%s一级 · 升级二级消耗 80 零件" % title
	return "%s二级 · 城区建设完成" % title

func _levels(kind: String) -> int:
	var total: int = 0
	for plot in plots:
		if plot.kind == kind:
			total += int(plot.level)
	return total

func _can_change(index: int) -> Dictionary:
	if not is_instance_valid(game):
		return _failure("城区尚未初始化")
	if game.phase != "day":
		return _failure("请在白昼建设城区")
	if index < 0 or index >= plots.size():
		return _failure("无效地块")
	if not is_instance_valid(game.hero) or game.hero.position.distance_to(plots[index].position) > INTERACTION_RADIUS:
		return _failure("靠近城区地块才能建设")
	return {"ok": true, "reason": "", "cost": 0, "scrap": int(game.scrap)}

func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "cost": 0, "scrap": int(game.scrap) if is_instance_valid(game) else 0}

func _refresh_label(index: int) -> void:
	var plot: Dictionary = plots[index]
	var label: Label3D = plot.label
	if int(plot.level) == 0:
		label.text = "城区地块 %d" % (index + 1)
	else:
		label.text = "%s · %d级" % ["兵营" if plot.kind == BARRACKS else "工坊", int(plot.level)]
		(plot.ring as MeshInstance3D).material_override = BattleVisuals.material(Color("e0b36d"), 0.25)

func _build_model(plot: Dictionary) -> void:
	var scene: PackedScene = BARRACKS_SCENE if plot.kind == BARRACKS else WORKSHOP_SCENE
	var model: Node3D = scene.instantiate() as Node3D
	(plot.node as Node3D).add_child(model)
	model.name = "DistrictBuilding"
	var bounds: AABB = model_bounds(model)
	var footprint: float = maxf(bounds.size.x, bounds.size.z)
	var scale_factor: float = minf(1.0, minf(2.7 / maxf(footprint, 0.01), 2.15 / maxf(bounds.size.y, 0.01)))
	model.scale *= scale_factor
	model.position = Vector3(-(bounds.position.x + bounds.size.x * 0.5) * scale_factor, -bounds.position.y * scale_factor, -(bounds.position.z + bounds.size.z * 0.5) * scale_factor)
	plot.model = model
	(plot.lamp as OmniLight3D).light_energy = 0.55

func model_bounds(model: Node3D) -> AABB:
	var combined: AABB = AABB()
	var found: bool = false
	var inverse: Transform3D = model.global_transform.affine_inverse()
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh.mesh == null:
			continue
		var bounds: AABB = (inverse * mesh.global_transform) * mesh.get_aabb()
		combined = combined.merge(bounds) if found else bounds
		found = true
	return combined
