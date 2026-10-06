extends SceneTree
## 指挥中继站专项：依赖、格子占用、训练倍率和真实 HUD 第三建筑页。
##
## 本用例只通过 Nightfall 场景的公开生产入口建造和训练；不伪造钱包、
## 部队或建筑对象。精度段使用较大的零件余额和暂停主循环，避免自然
## 波次把生产账本混入本专项结论。
const Catalog := preload("res://scripts/outpost_catalog.gd")
const Grid := preload("res://scripts/construction_grid.gd")
const RunSession := preload("res://scripts/run_session.gd")
const SCENE := "res://scenes/nightfall.tscn"
const SEED := 20261007
const RELAY := "command_relay"
const ARMORY := "armory"
const BARRACKS := "barracks"
const WORKSHOP := "workshop"
const LABORATORY := "laboratory"

var game: Node3D
var checks := 0
var failures: Array[String] = []
var candidate_points: Array[Vector3] = [
	Vector3(-9, 5, -9), Vector3(-3, 5, -9), Vector3(4, 5, -9), Vector3(9, 5, -9),
	Vector3(-9, 5, -3), Vector3(-3, 5, -3), Vector3(4, 5, -3), Vector3(9, 5, -3),
	Vector3(-9, 5, 4), Vector3(-3, 5, 4), Vector3(4, 5, 4), Vector3(9, 5, 4),
	Vector3(-9, 5, 10), Vector3(-3, 5, 10), Vector3(4, 5, 10), Vector3(9, 5, 10)
]

func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1920, 1200)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 40: push_error(message)

func wait_frames(count: int = 2) -> void:
	for _frame in count: await process_frame

func remove_enemies() -> void:
	if not is_instance_valid(game): return
	for enemy: Variant in game.enemies:
		if is_instance_valid(enemy): (enemy as Node).queue_free()
	game.enemies.clear()
	await process_frame

func close_game() -> void:
	if not is_instance_valid(game): return
	# A real ended-screen restart may already have detached the old scene by
	# the time this cleanup path runs. Keep the render harness idempotent and do
	# not call get_tree/create_timer through a detached Node3D.
	if game.is_inside_tree():
		await game.prepare_shutdown()
		if current_scene == game: current_scene = null
		game.queue_free()
	game = null
	await wait_frames(4)

func fresh() -> void:
	await close_game()
	check(RunSession.queue_request(self, SEED, "siege"), "固定种子应能创建真实标准局请求")
	game = load(SCENE).instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	await wait_frames(6)
	game.set_process(false)
	if is_instance_valid(game.world): game.world.set_process(false)
	check(game.phase == "draft", "中继站专项应从真实开局卡片阶段开始")
	check(game.choose_card(0), "真实开局应能选择第一张卡并进入夜晚")
	await remove_enemies()
	game.phase = "day"
	game.paused_from = "day"
	game.phase_time = game.DAY_LENGTH
	game.scrap = 6000
	game.hero.position = Vector3(0, 5, 4)
	game.hero.position.y = game.outpost_height(game.hero.position)
	game.hero.moving = false
	game.move_goal = game.hero.position
	game.hero_path.clear()
	game.aim = game.hero.position
	check(game.districts.plots.is_empty(), "新局不应继承上一局的城区建筑")
	check(game.squads.training_queues.is_empty(), "新局不应继承上一局的训练队列")

func finish() -> void:
	await close_game()
	print("NIGHTFALL_COMMAND_RELAY_", "OK" if failures.is_empty() else "FAILED",
		" checks=", checks, " failures=", failures.size(),
		" dependency grid multiplier queue_identity lifecycle hud")
	quit(0 if failures.is_empty() else 1)

func point_for(candidate: Vector3, kind: String) -> Dictionary:
	var point := candidate
	point.y = game.outpost_height(point)
	return game.construction.validity(point, -1, kind)

func build_at_candidate(kind: String, preferred: Vector3 = Vector3.INF) -> int:
	var points: Array[Vector3] = []
	if preferred.is_finite(): points.append(preferred)
	for point: Vector3 in candidate_points:
		if not points.has(point): points.append(point)
	for raw: Vector3 in points:
		var placement: Dictionary = point_for(raw, kind)
		if not bool(placement.get("valid", false)): continue
		var before: int = game.districts.plots.size()
		var balance: int = int(game.scrap)
		if not game.build_structure_at(placement.point, kind): continue
		var found_index := -1
		for index in game.districts.plots.size():
			var candidate: Dictionary = game.districts.plots[index]
			if String(candidate.get("kind", "")) == kind and int(candidate.get("level", 0)) > 0 \
				and (candidate.get("position", Vector3.INF) as Vector3).distance_to(placement.point) < .01:
				found_index = index
				break
		check(found_index >= 0 and (game.districts.plots.size() == before + 1 or found_index < before),
			"真实%s建造应新增或复用一个稳定城区条目" % kind)
		check(int(game.scrap) == balance - int(Catalog.building(kind).cost), "真实%s建造应只扣一次目录费用" % kind)
		return found_index
	check(false, "当前地图应能找到%s的合法网格位置" % kind)
	return -1

func build_prerequisites() -> Dictionary:
	var result := {}
	result.workshop = build_at_candidate(WORKSHOP)
	result.barracks = build_at_candidate(BARRACKS)
	result.laboratory = build_at_candidate(LABORATORY)
	result.armory = build_at_candidate(ARMORY)
	return result

func queue_probe(kind: String = "shield", barracks_index: int = -1) -> Dictionary:
	var before := int(game.scrap)
	var result: Dictionary = game.squads.enqueue(kind, barracks_index)
	check(bool(result.get("ok", false)), "真实%s应能加入兵营训练队列" % kind)
	if not bool(result.get("ok", false)): return {}
	var selected_index := int(result.get("barracks_id", barracks_index))
	var queue: Array = game.squads.training_queues.get(selected_index, [])
	check(not queue.is_empty(), "付费训练应留下原始队列条目")
	if queue.is_empty(): return {}
	var queue_index := queue.size() - 1
	var item: Dictionary = queue[queue_index].duplicate(true)
	check(String(item.get("kind", "")) == kind, "队列条目应保留真实兵种身份")
	var visible: Dictionary = queue_row(selected_index)
	var cancel: Dictionary = game.squads.cancel_training(selected_index, queue_index)
	check(bool(cancel.get("ok", false)) and int(game.scrap) == before,
		"倍率探针取消订单应完整退回原付款，不改变共享钱包")
	return {"barracks": selected_index, "queue_index": queue_index, "item": item, "visible": visible}

func duration_multiplier() -> float:
	if is_instance_valid(game.districts) and game.districts.has_method("training_duration_multiplier"):
		return float(game.districts.call("training_duration_multiplier"))
	var snapshot: Dictionary = game.squads.snapshot()
	return float(snapshot.get("training_duration_multiplier", 1.0))

func queue_row(barracks_index: int) -> Dictionary:
	for row: Dictionary in game.squads.snapshot().get("queues", []):
		if int(row.get("index", -1)) != barracks_index: continue
		var queue: Array = row.get("queue", [])
		if not queue.is_empty(): return queue[0]
	return {}

func runtime_delta_probe(kind: String, barracks_index: int, multiplier: float, label: String) -> void:
	var result: Dictionary = game.squads.enqueue(kind, barracks_index)
	check(bool(result.get("ok", false)), label + "应能加入真实队列")
	if not bool(result.get("ok", false)): return
	var before: Dictionary = queue_row(barracks_index)
	var before_remaining := float(before.get("remaining", -1.0))
	game.squads.advance(1.0)
	var after: Dictionary = queue_row(barracks_index)
	var after_remaining := float(after.get("remaining", -1.0))
	check(before_remaining >= 0.0 and after_remaining >= 0.0
		and is_equal_approx(before_remaining - after_remaining, 1.0 / multiplier),
		label + "实际一秒应按实时倍率消耗基础训练秒数")
	var id := int(result.get("barracks_id", barracks_index))
	var queue: Array = game.squads.training_queues.get(id, [])
	check(bool(game.squads.cancel_training(id, queue.size() - 1).get("ok", false)), label + "探针订单应能原价取消")

func lifecycle_and_tech() -> Dictionary:
	var definition: Dictionary = Catalog.building(RELAY)
	check(Catalog.BUILDING_IDS.has(RELAY), "建筑目录应包含指挥中继站")
	check(String(definition.get("title", "")) == "指挥中继站", "中继站目录必须保留中文标题")
	var size: Vector2i = definition.get("size", Vector2i.ZERO)
	check(size.x > 0 and size.y > 0, "中继站必须声明有效网格尺寸")
	var missing: Dictionary = game.districts.build_eligibility(RELAY)
	check(not bool(missing.get("available", true)) and (missing.get("missing", []) as Array).has(ARMORY),
		"军械厂尚未存活时，中继站必须明确报告军械厂依赖")
	var blocked_balance := int(game.scrap)
	var blocked_point := point_for(Vector3(9, 5, 10), RELAY)
	check(not bool(blocked_point.get("tech_valid", true)), "中继站预览应在缺少军械厂时标红科技条件")
	check(not game.build_structure_at(blocked_point.point, RELAY) and int(game.scrap) == blocked_balance,
		"依赖未满足时真实建造不能扣款或追加建筑")
	var grid := Grid.placement(Vector3(-9, 5, 10), RELAY)
	check(grid.inside and (grid.cells as Array).size() == size.x * size.y and grid.rect.size == Vector2(size),
		"中继站应按目录尺寸占据连续且完整的网格格子")
	var prerequisites := build_prerequisites()
	check(prerequisites.armory >= 0 and game.districts.has_live(ARMORY), "存活军械厂应成为中继站唯一新增前置链的终点")
	var relay_index := build_at_candidate(RELAY, Vector3(9, 5, 10))
	check(relay_index >= 0, "军械厂存活后应允许真实建造指挥中继站")
	if relay_index < 0: return {"relay": -1, "prerequisites": prerequisites}
	var plot: Dictionary = game.districts.plots[relay_index]
	grid = Grid.placement(plot.position, RELAY)
	check(String(plot.kind) == RELAY and int(plot.level) == 1 and is_instance_valid(plot.model),
		"已建中继站应具有真实模型、一级和稳定plot身份")
	var occupied: Dictionary = game.construction.occupied_cells()
	for cell: Vector2i in grid.cells:
		check(occupied.has(cell), "中继站每一格都应进入建设系统占用表")
	var overlap: Dictionary = game.construction.validity(plot.position, -1, RELAY)
	check(not bool(overlap.get("valid", false)) and not bool(overlap.get("space_valid", true)),
		"同一中继站的网格占格必须拒绝重叠建造")
	return {"relay": relay_index, "prerequisites": prerequisites}

func multiplier_and_queue(relay_index: int, barracks_index: int) -> Dictionary:
	var base := queue_probe("shield", barracks_index)
	var base_total := float(base.get("item", {}).get("total", 0.0))
	check(is_equal_approx(base_total, float(Catalog.troop("shield").time)), "无中继时队列总时长应等于兵种目录基础时间")
	var first := duration_multiplier()
	check(is_equal_approx(first, .9), "一级中继站应将训练倍率即时设为0.9")
	var level_one := queue_probe("shield", barracks_index)
	check(is_equal_approx(float(level_one.get("visible", {}).get("eta", 0.0)), base_total * first),
		"一级中继站的可见训练ETA应使用实时0.9倍率")
	runtime_delta_probe("shield", barracks_index, first, "一级中继站")
	var mid_upgrade: Dictionary = game.squads.enqueue("engineer", barracks_index)
	check(bool(mid_upgrade.get("ok", false)), "升级即时生效段应先加入工程员订单")
	var mid_before: Dictionary = queue_row(barracks_index)
	game.squads.advance(.5)
	var mid_progress: Dictionary = queue_row(barracks_index)
	var first_half_delta := float(mid_before.get("remaining", 0.0)) - float(mid_progress.get("remaining", 0.0))
	var upgrade: Dictionary = game.districts.upgrade(relay_index)
	check(bool(upgrade.get("ok", false)) and int(game.districts.plots[relay_index].level) == 2,
		"真实F升级中继站应进入二级并恢复耐久")
	var second := duration_multiplier()
	check(is_equal_approx(second, .8) and second < first, "二级中继站应即时降至0.8倍率")
	game.squads.advance(.5)
	var mid_after: Dictionary = queue_row(barracks_index)
	var second_half_delta := float(mid_progress.get("remaining", 0.0)) - float(mid_after.get("remaining", 0.0))
	check(is_equal_approx(first_half_delta, .5 / first) and is_equal_approx(second_half_delta, .5 / second),
		"已付款队列在中途升级后下一帧必须分别使用一级和二级倍率")
	var mid_queue: Array = game.squads.training_queues.get(barracks_index, [])
	check(bool(game.squads.cancel_training(barracks_index, mid_queue.size() - 1).get("ok", false)),
		"中途升级订单清理必须只退回一次原价")
	var level_two := queue_probe("shield", barracks_index)
	check(is_equal_approx(float(level_two.get("visible", {}).get("eta", 0.0)), base_total * second),
		"二级中继站的新训练订单应立即使用0.8倍率")
	return {"base": base_total, "first": first, "second": second, "level_one": level_one, "level_two": level_two}

func parallel_barracks_probe(first_barracks: int, multiplier: float) -> void:
	var second_barracks := build_at_candidate(BARRACKS, Vector3(-9, 10, 4))
	check(second_barracks >= 0 and second_barracks != first_barracks, "指挥中继站应支持两座独立兵营并行生产")
	if second_barracks < 0 or second_barracks == first_barracks: return
	var first_order: Dictionary = game.squads.enqueue("shield", first_barracks)
	var second_order: Dictionary = game.squads.enqueue("engineer", second_barracks)
	check(bool(first_order.get("ok", false)) and bool(second_order.get("ok", false)), "两座兵营应各自接受一项真实订单")
	if not bool(first_order.get("ok", false)) or not bool(second_order.get("ok", false)): return
	var first_before := float(queue_row(first_barracks).get("remaining", 0.0))
	var second_before := float(queue_row(second_barracks).get("remaining", 0.0))
	game.squads.advance(1.0)
	var first_after := float(queue_row(first_barracks).get("remaining", 0.0))
	var second_after := float(queue_row(second_barracks).get("remaining", 0.0))
	check(is_equal_approx(first_before - first_after, 1.0 / multiplier)
		and is_equal_approx(second_before - second_after, 1.0 / multiplier),
		"两座兵营的真实队列应同时读取同一个中继站倍率")
	var first_queue: Array = game.squads.training_queues.get(first_barracks, [])
	var second_queue: Array = game.squads.training_queues.get(second_barracks, [])
	game.squads.cancel_training(first_barracks, first_queue.size() - 1)
	game.squads.cancel_training(second_barracks, second_queue.size() - 1)

func queue_destruction_recovery(relay_index: int, barracks_index: int, expected_before: float) -> void:
	var before_scrap := int(game.scrap)
	var order: Dictionary = game.squads.enqueue("shield", barracks_index)
	check(bool(order.get("ok", false)), "实时队列恢复段应能支付一项盾卫训练")
	if not bool(order.get("ok", false)): return
	var initial := queue_row(barracks_index)
	var initial_remaining := float(initial.get("remaining", 0.0))
	game.squads.advance(1.0)
	var progressed := queue_row(barracks_index)
	check(String(progressed.get("kind", "")) == "shield" and float(progressed.get("remaining", 0.0)) < initial_remaining,
		"中继站加速下已付款队列应真实消耗训练时间")
	var destroyed: Dictionary = game.districts.damage(relay_index, 100000.0)
	check(bool(destroyed.get("destroyed", false)) and is_equal_approx(duration_multiplier(), expected_before),
		"中继站被真实摧毁后训练倍率应恢复到剩余科技水平")
	var after_destroy := queue_row(barracks_index)
	check(String(after_destroy.get("kind", "")) == "shield" and int(game.scrap) == before_scrap - int(Catalog.troop("shield").cost),
		"队列中途摧毁中继站不能偷偷退款、丢单或重复扣款")
	game.squads.advance(.5)
	var resumed := queue_row(barracks_index)
	check(String(resumed.get("kind", "")) == "shield" or resumed.is_empty(),
		"中继站损毁后兵营队列仍应继续恢复到完成，而不是卡死")
	while not game.squads.training_queues.get(barracks_index, []).is_empty():
		game.squads.advance(.5)
		if checks > 5000: break
	check(game.squads.training_queues.get(barracks_index, []).is_empty(), "恢复后的训练队列最终应完成并移除")

func second_relay_cap_and_identity(relay_index: int, first_relay_position: Vector3, barracks_index: int) -> void:
	var second_index := build_at_candidate(RELAY, Vector3(-9, 10, 10))
	check(second_index >= 0, "军械厂链应允许建造第二座中继站")
	if second_index < 0: return
	var capped := duration_multiplier()
	check(is_equal_approx(capped, .9) or is_equal_approx(capped, .8), "第二座一级中继站应返回有限训练倍率")
	# 当前第一座已升级为二级，第二座一级的总等级仍应封顶为二级效果。
	check(is_equal_approx(capped, .8), "二级中继站加第二座一级站不能突破全城0.8封顶")
	var old_plot: Dictionary = game.districts.plots[second_index]
	var old_id := int(old_plot.id)
	var old_model_id := (old_plot.model as Node).get_instance_id() if is_instance_valid(old_plot.model) else -1
	var old_position: Vector3 = old_plot.position
	var balance: int = int(game.scrap)
	var quote: Dictionary = game.districts.demolition_quote(second_index)
	var sold: Dictionary = game.districts.demolish(second_index)
	check(bool(sold.get("ok", false)) and bool(sold.get("removed", false)) and int(game.scrap) == balance + int(quote.get("refund", 0)),
		"拆售中继站应按本代投入返还零件并终止其活跃身份")
	check(game.districts.active_command_relays().size() == 1, "拆售一座中继站后活跃清单只能保留另一座")
	await process_frame
	var new_index := build_at_candidate(RELAY, old_position)
	check(new_index >= 0, "原网格位置释放后应能付费重建中继站")
	if new_index < 0: return
	var new_plot: Dictionary = game.districts.plots[new_index]
	var new_model_id := (new_plot.model as Node).get_instance_id() if is_instance_valid(new_plot.model) else -1
	check(int(new_plot.id) != old_id and new_model_id != old_model_id,
		"拆售后重建必须创建新的建筑代际身份，旧模型不能被复用")
	check(game.districts.active_command_relays().size() == 2, "重建后两座中继站应重新加入活跃清单")
	# 以实时订单验证重建的中继站能继续提供倍率，但不继承旧队列或付款。
	var probe := queue_probe("shield", barracks_index)
	check(is_equal_approx(duration_multiplier(), .8) and not probe.is_empty(), "新代中继站应重新参与训练倍率且不污染订单钱包")

func lifecycle_freeze_and_retry() -> void:
	var before_scrap := int(game.scrap)
	game.phase = "paused"
	var blocked_queue: Dictionary = game.squads.enqueue("shield")
	check(not bool(blocked_queue.get("ok", false)) and int(game.scrap) == before_scrap, "暂停时不能创建或支付新训练队列")
	var blocked_build: Dictionary = game.districts.build_at(Vector3(9, 10, 4), RELAY)
	check(not bool(blocked_build.get("ok", false)) and int(game.scrap) == before_scrap, "暂停时不能建造中继站")
	game.phase = "draft"
	var draft_queue: Dictionary = game.squads.enqueue("shield")
	check(not bool(draft_queue.get("ok", false)) and int(game.scrap) == before_scrap, "选卡阶段不能创建或支付新训练队列")
	var draft_build: Dictionary = game.districts.build_at(Vector3(9, 10, 4), RELAY)
	check(not bool(draft_build.get("ok", false)) and int(game.scrap) == before_scrap, "选卡阶段不能建造中继站")
	game.phase = "night"
	var live_multiplier := duration_multiplier()
	check(live_multiplier <= .8, "昼夜切换不应清除存活中继站的训练倍率")
	var old_id := game.get_instance_id()
	game.request_run_restart(true)
	await wait_frames(2)
	check(game.get_instance_id() == old_id and not game.restart_pending, "未结束局面调用重试必须保持当前场景")
	var previous: Node3D = game
	game.phase = "ended"
	game.victory = false
	game.ending_key = "defeat"
	game.request_run_restart(true)
	var elapsed := 0.0
	while current_scene == previous and elapsed < 5.0:
		await create_timer(.05).timeout
		elapsed += .05
	check(current_scene != previous, "结束画面触发重试应在有限时间内替换真实场景")
	if current_scene != previous and current_scene is Node3D:
		game = current_scene as Node3D
		await wait_frames(5)
		game.set_process(false)
		if is_instance_valid(game.world): game.world.set_process(false)
		check(game.phase == "draft" and game.districts.active_command_relays().is_empty()
			and game.squads.training_queues.is_empty() and is_equal_approx(duration_multiplier(), 1.0),
			"真实重试应清空旧中继站、倍率和所有建筑生产身份")
	else:
		await close_game()
		await fresh()

func hud_third_page() -> void:
	check(Catalog.BUILDING_IDS.find(RELAY) / 3 >= 2, "新增中继站应进入中文建筑第三页")
	game.phase = "day"
	check(game.construction.begin(RELAY), "真实建设入口应能打开中继站预览")
	game.hud._process(0.0)
	var kinds: Array[String] = game.hud.visible_construction_kinds()
	check(game.hud.construction_page == 2 and kinds.has(RELAY), "HUD第三页应显示指挥中继站而非隐藏到旧页")
	var relay_slot := Catalog.BUILDING_IDS.find(RELAY) % 3
	check(game.hud.construction_kind_rect(relay_slot) == Rect2(457 + relay_slot * 175, 658, 166, 31),
		"HUD第三页中继站按钮必须保留真实中文建筑页命中区")
	check(String(Catalog.building(RELAY).title).contains("指挥") and String(Catalog.building(RELAY).title).contains("中继站"),
		"HUD第三页建筑名称必须使用可读中文")
	game.hud.queue_redraw()
	await wait_frames(2)
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("res://build")
		var image := root.get_texture().get_image()
		check(image.save_png("res://build/command-relay-hud-page3.png") == OK, "HUD第三建筑页应能实际渲染截图")
	game.construction.cancel()

func run() -> void:
	await fresh()
	var tech := await lifecycle_and_tech()
	if int(tech.get("relay", -1)) < 0:
		await finish()
		return
	var relay_index := int(tech.relay)
	var prerequisites: Dictionary = tech.prerequisites
	var barracks_index := int(prerequisites.barracks)
	check(barracks_index >= 0, "训练倍率专项需要一座真实兵营")
	var relay_position: Vector3 = game.districts.plots[relay_index].position
	var multiplier := multiplier_and_queue(relay_index, barracks_index)
	parallel_barracks_probe(barracks_index, float(multiplier.second))
	queue_destruction_recovery(relay_index, barracks_index, 1.0)
	# The destruction segment intentionally removes the first relay. Rebuild a
	# fresh generation and upgrade it before exercising the two-live-relay cap.
	relay_index = build_at_candidate(RELAY, relay_position)
	check(relay_index >= 0, "队列中途损毁后的中继站应能在原位置重建")
	if relay_index >= 0:
		var rebuilt_upgrade: Dictionary = game.districts.upgrade(relay_index)
		check(bool(rebuilt_upgrade.get("ok", false)), "重建后的中继站应能重新升级到二级")
	await second_relay_cap_and_identity(relay_index, relay_position, barracks_index)
	await lifecycle_freeze_and_retry()
	await hud_third_page()
	await finish()
