extends SceneTree
## 坚守信标生产专项。精度段明确使用高余额、固定演员站位和延长阶段，
## 所有伤害仍经真实普通前摇、投蚀飞行落点或末波首领蓄力；不以
## 直接调用减伤辅助方法代替攻击验收。档案写入仅在本专项临时路径。
const Catalog := preload("res://scripts/outpost_catalog.gd")
const Grid := preload("res://scripts/construction_grid.gd")
const RunSession := preload("res://scripts/run_session.gd")
const RunArchive := preload("res://scripts/run_archive.gd")
const SCENE := "res://scenes/nightfall.tscn"
const HOLDFAST := "holdfast_beacon"
const SEED := 20261007
const VIEWPORTS := [Vector2i(1920, 1200), Vector2i(1920, 1080), Vector2i(1440, 900)]
const CANDIDATES := [Vector3(-9, 5, -9), Vector3(-9, 5, -3), Vector3(9, 5, -9),
	Vector3(9, 5, 4), Vector3(-9, 5, 9), Vector3(9, 5, 10), Vector3(-3, 5, -9)]
const ROOT_OBSERVER := """extends 'res://scripts/nightfall.gd'
var holdfast_hit_receipts: Array[float] = []
func record_beacon_hit(amount: float) -> void:
	holdfast_hit_receipts.append(amount)
	super.record_beacon_hit(amount)
"""
const HUD_OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var holdfast_labels: Array[Dictionary] = []
func _draw() -> void:
	holdfast_labels.clear()
	super._draw()
func label(value: String, point: Vector2, size_px: int, color: Color = Color(\"e7e1d3\"), latin: bool = false) -> void:
	var selected_font: Font = display_font if latin else font
	holdfast_labels.append({\"text\": value, \"point\": point, \"size\": size_px,
		\"width\": selected_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x,
		\"ascent\": selected_font.get_ascent(size_px), \"descent\": selected_font.get_descent(size_px)})
	super.label(value, point, size_px, color, latin)
"""

var game: Node3D
var checks := 0
var failures: Array[String] = []
var completed: Array[String] = []
var stage := "initialize"
var finished := false
var render_test := false
var capture_tag := "default"
var profile_path := "user://riftward-holdfast-test-%d.json" % Time.get_ticks_usec()
var evidence: Dictionary = {"seed": SEED, "fixture_parts": 6000, "captures": [], "damage": []}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	render_test = "--render-test" in args
	var tag_index := args.find("--capture-tag")
	if tag_index >= 0 and tag_index + 1 < args.size() and args[tag_index + 1] in ["metal", "opengl"]:
		capture_tag = args[tag_index + 1]
	root.size = VIEWPORTS[0]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = VIEWPORTS[0]
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_position(Vector2i(-10000, -10000))
		root.hide()
	# This fires before _ready on an actual reload, keeping graphical retry
	# fixtures away from the player's persistent archive as well.
	root.child_entered_tree.connect(inject_archive)
	create_timer(180.0, true, false, true).timeout.connect(watchdog)
	call_deferred("run")

func inject_archive(node: Node) -> void:
	if node is Node3D and node.has_method("select_blueprint"):
		node.set("archive", RunArchive.new(profile_path, true))

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(stage + ": " + message)
	if failures.size() <= 35: push_error(stage + ": " + message)

func near(actual: float, expected: float, message: String) -> void:
	check(is_finite(actual) and absf(actual - expected) < .001,
		message + " [actual=%.5f expected=%.5f]" % [actual, expected])

func wait_frames(count: int = 3) -> void:
	for _frame in count: await process_frame

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func click(rect: Rect2) -> void:
	var pixel: Vector2 = rect.get_center() * game.hud.get_viewport_rect().size / Vector2(1440, 900)
	var event := InputEventMouseButton.new()
	event.position = pixel
	event.global_position = pixel
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.button_mask = 0
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func cleanup_profile() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var candidate: String = profile_path + suffix
		if FileAccess.file_exists(candidate):
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate)) == OK,
				"临时档案与备用文件应完全移除")

func close_game() -> void:
	if not is_instance_valid(game): return
	if game.is_inside_tree():
		await game.prepare_shutdown()
		if current_scene == game: current_scene = null
		game.queue_free()
	game = null
	await wait_frames(4)

func clear_enemies() -> void:
	game.clear_lobbers()
	game.clear_summoners()
	game.clear_warders()
	if is_instance_valid(game.siege_boss):
		game.siege_boss.clear()
		game.siege_boss.queue_free()
		game.siege_boss = null
	for enemy: BattleUnit in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	await process_frame

func stand(point: Vector3) -> void:
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.hero.moving = false
	game.hero.set_locomotion_velocity(Vector3.ZERO)
	game.move_goal = point
	game.hero_path.clear()
	game.hero_keyboard_active = false
	game.aim = point

func isolate_night() -> void:
	game.phase = "night"
	game.phase_time = 1000.0
	game.wave_index = game.WAVES_PER_NIGHT
	game.pulse_timer = 9999.0
	game.gate_trap_charges = 0
	game.hero.attack_timer = 9999.0
	for pad: Dictionary in game.world.tower_pads: pad.cooldown = 9999.0
	for squad: Dictionary in game.squads.squads:
		for member: BattleUnit in squad.members:
			if is_instance_valid(member): member.attack_timer = 9999.0

func fresh() -> bool:
	await close_game()
	check(RunSession.queue_request(self, SEED, "siege"), "真实场景应接受固定种子与铁潮模式")
	var observer := GDScript.new()
	observer.source_code = ROOT_OBSERVER
	if observer.reload() != OK:
		check(false, "只读伤害观察脚本应能编译")
		return false
	var packed: PackedScene = load(SCENE).duplicate()
	var bundled: Dictionary = packed.get("_bundled").duplicate(true)
	var replacements := 0
	for index in bundled.variants.size():
		var value: Variant = bundled.variants[index]
		if value is Script and value.resource_path == "res://scripts/nightfall.gd":
			bundled.variants[index] = observer
			replacements += 1
	check(replacements == 1, "只在实例化前替换真实根脚本，避免 eager 模块重复生成")
	if replacements != 1: return false
	packed.set("_bundled", bundled)
	game = packed.instantiate() as Node3D
	game.scene_file_path = SCENE
	root.add_child(game)
	current_scene = game
	await wait_frames(5)
	game.set_process(false)
	game.world.set_process(false)
	game.archive.enabled = true
	check(game.archive.path == profile_path and game.phase == "draft" and game.opening_night_pending,
		"开局必须使用本专项临时档案与真实铭刻阶段")
	check(game.districts.plots.is_empty() and game.squads.squads.is_empty()
		and game.squads.training_queues.is_empty() and game.selected_blueprint == "",
		"新局不得继承上局建筑、部队、订单或蓝图选择")
	return true

func open_night(blueprint: String) -> void:
	check(game.select_blueprint(blueprint), "真实开局应能选择当前解锁的蓝图许可")
	await press(KEY_1)
	check(game.phase == "night" and game.run_mode_locked and not game.opening_night_pending,
		"真实 1 键铭刻后应进入夜晚并锁定蓝图")
	check(not game.select_blueprint("") and not game.select_blueprint("signal_beacon"),
		"运行中不能切换蓝图或补选另一个结局许可")
	await clear_enemies()
	isolate_night()
	game.scrap = 6000
	stand(Vector3(-11, 5, 10))

func build(kind: String, preferred: Vector3 = Vector3.INF) -> int:
	var points: Array[Vector3] = []
	if preferred.is_finite(): points.append(preferred)
	for raw: Vector3 in CANDIDATES:
		if not points.has(raw): points.append(raw)
	for raw: Vector3 in points:
		var point := raw
		point.y = game.outpost_height(point)
		var placement: Dictionary = game.construction.validity(point, -1, kind)
		if not bool(placement.get("valid", false)): continue
		var before := int(game.scrap)
		if not game.build_structure_at(placement.point, kind): continue
		near(float(before - game.scrap), float(Catalog.building(kind).cost), kind + "真实建造必须只扣一次目录费用")
		for index in game.districts.plots.size():
			var plot: Dictionary = game.districts.plots[index]
			if String(plot.kind) == kind and int(plot.level) > 0 and not bool(plot.removed) \
				and (plot.position as Vector3).distance_to(placement.point) < .01: return index
	check(false, "真实地图应能找到并支付%s合法占格" % kind)
	return -1

func rejection(point: Vector3, expected_text: String) -> void:
	var before := int(game.scrap)
	var before_count: int = game.districts.plots.size()
	var eligibility: Dictionary = game.districts.build_eligibility(HOLDFAST)
	check(not bool(eligibility.available) and String(eligibility.reason).contains(expected_text),
		"真实科技拒绝应明确说明 " + expected_text)
	var placement: Dictionary = game.construction.validity(point, -1, HOLDFAST)
	check(not bool(placement.tech_valid), "真实格子预览应报告蓝图/前置科技无效")
	check(not game.build_structure_at(point, HOLDFAST) and int(game.scrap) == before
		and game.districts.plots.size() == before_count, "拒绝实际建造不能扣款或生成建筑条目")

func archive_and_loadout() -> void:
	stage = "archive"
	check(not game.archive.has_blueprint(HOLDFAST) and not game.select_blueprint(HOLDFAST),
		"空档案必须拒绝坚守蓝图选择")
	check(game.available_blueprints().size() == 1, "锁定档案只显示无蓝图")
	await open_night("")
	var workshop := build("workshop")
	check(workshop >= 0, "档案拒绝探针仍使用真实付费工坊")
	# Adversarial caller-state check: an invalid selected ID must not bypass
	# the independent persisted permission at the final building authority.
	game.selected_blueprint = HOLDFAST
	rejection(Vector3(-9, 5, -3), "档案尚未解锁")
	game.selected_blueprint = ""
	game.day_number = game.max_nights()
	game.start_night()
	await clear_enemies()
	game.wave_index = 4
	game.spawn_night_wave()
	check(bool(game.night_plan[4].boss_entry) and is_instance_valid(game.siege_boss),
		"坚守结局解锁必须经过真实末夜末波首领生产入口")
	game.begin_final_clearance()
	for enemy: BattleUnit in game.enemies.duplicate():
		if is_instance_valid(enemy) and enemy.alive: enemy.hurt(100000.0, game.hero)
	game.simulate(.02)
	check(game.phase == "ended" and game.victory and game.ending_key == "hold",
		"真实末夜清场与未清巢穴必须结算坚守胜利")
	check(game.archive.has_blueprint(HOLDFAST) and bool(game.archive_result.get("ok", false))
		and FileAccess.file_exists(profile_path), "真实胜利结算应向临时档案写入坚守蓝图")
	var history_size: int = game.archive.snapshot().run_history.size()
	game.finish_night()
	check(game.archive.snapshot().run_history.size() == history_size,
		"重复结算不能重复记录胜利或解锁")
	var persisted := RunArchive.new(profile_path, true)
	check(persisted.has_blueprint(HOLDFAST) and persisted.completed_objectives().has("victory_hold"),
		"重读临时档案应保留真实坚守目标与许可")
	completed.append(stage)
	stage = "unselected"
	if not await fresh(): return
	await open_night("")
	check(build("workshop") >= 0, "未选择许可的场景应仍能付费建立工坊")
	rejection(Vector3(-9, 5, -3), "开局选择")
	completed.append(stage)

func beacon_receipt(before: float, expected: float, label: String) -> void:
	near(before - float(game.beacon_hp), expected, label + "灯塔实际生命损失")
	var receipts: Array = game.holdfast_hit_receipts
	check(receipts.size() == 1, label + "record_beacon_hit必须只接受一次真实伤害")
	if receipts.size() == 1: near(float(receipts[0]), expected, label + "警报记录必须是减伤后实际损失")
	near(float(game.beacon_alarm_damage), expected, label + "可见灯塔警报不能记录原始伤害")
	check(game.beacon_alarm_time > 0.0, label + "真实灯塔伤害应触发警报")
	evidence.damage.append({"label": label, "loss": before - float(game.beacon_hp), "expected": expected,
		"receipts": receipts.duplicate(), "alarm": float(game.beacon_alarm_damage)})

func reset_receipt() -> void:
	game.holdfast_hit_receipts.clear()
	game.beacon_alarm_time = 0.0
	game.beacon_alarm_damage = 0.0

func melee_core(multiplier: float, label: String) -> void:
	await clear_enemies()
	isolate_night()
	stand(Vector3(-11, 5, 10))
	reset_receipt()
	var enemy: BattleUnit = game.spawn_creature(true, "basic")
	enemy.position = Vector3(0, 5, 3.6)
	check(String(game.choose_enemy_target(enemy).kind) == "beacon", label + "真实最近目标应为灯塔")
	var before := float(game.beacon_hp)
	game.simulate(.001)
	check(enemy.attack_queued and enemy.get_meta("attack_target_kind", "") == "beacon"
		and enemy.attack_windup > 0.0, label + "普通敌人必须先进入真实前摇")
	near(float(game.beacon_hp), before, label + "前摇开始不能提前扣灯塔生命")
	var remaining := float(enemy.attack_windup)
	game.simulate(maxf(0.0, remaining - .01))
	near(float(game.beacon_hp), before, label + "完整前摇结束前不能伤害灯塔")
	game.simulate(.011)
	beacon_receipt(before, minf(before, float(enemy.damage) * multiplier), label)
	await clear_enemies()

func melee_gate(multiplier: float, label: String) -> void:
	await clear_enemies()
	isolate_night()
	if game.gate_barricade_hp <= 0.0:
		stand(Vector3(0, 5, 13.4))
		var before_money := int(game.scrap)
		check(game.build_gate_barricade() and int(game.scrap) == before_money - int(game.BARRICADE_COST),
			label + "必须真实部署并支付南门路障")
	stand(Vector3(-11, 5, 10))
	var enemy: BattleUnit = game.spawn_creature(true, "breaker")
	var point: Vector3 = game.gate_barricade.position + Vector3(0, 0, .9)
	point.y = game.outpost_height(point)
	enemy.position = point
	check(String(game.choose_enemy_target(enemy).kind) == "barricade", label + "真实破城体应选择南门路障")
	var before := float(game.gate_barricade_hp)
	game.simulate(.001)
	check(enemy.attack_queued and enemy.get_meta("attack_target_kind", "") == "barricade",
		label + "路障承伤必须来自真实破城体前摇")
	near(float(game.gate_barricade_hp), before, label + "路障前摇不能提前扣耐久")
	game.simulate(maxf(0.0, float(enemy.attack_windup) - .01))
	near(float(game.gate_barricade_hp), before, label + "完整路障前摇结束前不得结算")
	game.simulate(.011)
	near(before - float(game.gate_barricade_hp), float(enemy.damage) * multiplier, label + "实际路障损失应使用当前减伤")
	await clear_enemies()

func lobber_core(multiplier: float, label: String, pause_probe: bool = false) -> void:
	await clear_enemies()
	isolate_night()
	stand(Vector3(-11, 5, 10))
	reset_receipt()
	var enemy: BattleUnit = game.spawn_creature(true, "lobber")
	enemy.position = Vector3(0, 5, 5)
	var controller: Node3D
	for candidate: Node3D in game.lobbers:
		if candidate.host == enemy: controller = candidate
	check(is_instance_valid(controller), label + "真实投蚀生产必须创建攻击控制器")
	if not is_instance_valid(controller): return
	var before := float(game.beacon_hp)
	game.simulate(.001)
	var state: Dictionary = controller.snapshot()
	check(String(state.phase) == "windup" and String(state.target_kind) == "beacon",
		label + "投蚀必须真实锁定灯塔并显示地面落点")
	if String(state.phase) != "windup": return
	game.simulate(float(state.stage_remaining) + .001)
	state = controller.snapshot()
	check(String(state.phase) == "flight" and int(state.launched) == 1, label + "完整前摇应发射一枚真实投蚀弹")
	near(float(game.beacon_hp), before, label + "发射仍不能提前造成落点伤害")
	if pause_probe:
		var remaining := float(state.stage_remaining)
		await press(KEY_ESCAPE)
		check(game.phase == "paused", "真实 Esc 输入应暂停投蚀飞行")
		game.simulate(1.0)
		controller.advance(1.0)
		near(float(controller.snapshot().stage_remaining), remaining, "暂停必须冻结真实投蚀弹")
		near(float(game.beacon_hp), before, "暂停不能结算灯塔伤害")
		await press(KEY_ESCAPE)
		check(game.phase == "night", "真实 Esc 输入应恢复原夜晚")
	game.simulate(float(controller.snapshot().stage_remaining) - .01)
	near(float(game.beacon_hp), before, label + "投蚀弹到达前不得扣灯塔生命")
	game.simulate(.011)
	check(String(controller.snapshot().phase) == "impact" and int(controller.snapshot().impacts) == 1,
		label + "真实固定落点必须只结算一次命中")
	beacon_receipt(before, float(enemy.damage) * multiplier, label)
	var settled := float(game.beacon_hp)
	game.simulate(.05)
	near(float(game.beacon_hp), settled, label + "持续落点画面不能重复支付伤害")
	await clear_enemies()

func boss_core(multiplier: float, label: String) -> void:
	await clear_enemies()
	game.day_number = 4
	game.prepare_next_night_plan(false)
	game.wave_index = 4
	game.spawn_night_wave()
	var boss: BattleUnit
	for enemy: BattleUnit in game.enemies:
		if enemy.get_meta("siege_boss", false): boss = enemy
	check(is_instance_valid(boss) and is_instance_valid(game.siege_boss), label + "真实末波应生产唯一首领")
	if not is_instance_valid(boss): return
	for enemy: BattleUnit in game.enemies.duplicate():
		if enemy != boss: enemy.queue_free()
	game.enemies.clear()
	game.enemies.append(boss)
	await process_frame
	isolate_night()
	reset_receipt()
	boss.position = Vector3(0, 5, 5.8)
	stand(Vector3(0, 5, 3.1))
	check(game.can_traverse(boss.position, game.hero.position), label + "首领应能真实触及灯塔边缘英雄")
	var before := float(game.beacon_hp)
	game.simulate(8.001)
	var state: Dictionary = game.boss_snapshot()
	check(String(state.phase) == "windup" and (state.position as Vector3).distance_to(Vector3(0, 5, 3.1)) < .001,
		label + "首领必须真实锁定灯塔边缘位置蓄力")
	near(float(game.beacon_hp), before, label + "首领蓄力不得提前伤害灯塔")
	stand(Vector3(-11, 5, 10))
	game.simulate(float(state.windup) - .01)
	near(float(game.beacon_hp), before, label + "完整拍击蓄力结束前不能扣核心生命")
	game.simulate(.011)
	check(String(game.boss_snapshot().phase) == "approach", label + "真实拍击结束应返回接近状态")
	beacon_receipt(before, 70.0 * multiplier, label)
	await clear_enemies()

func lobber_gate(multiplier: float, label: String) -> void:
	await clear_enemies()
	isolate_night()
	stand(Vector3(-11, 5, 10))
	reset_receipt()
	var enemy: BattleUnit = game.spawn_creature(true, "lobber")
	var point: Vector3 = game.gate_barricade.position + Vector3(1.8, 0, .3)
	point.y = game.outpost_height(point)
	enemy.position = point
	var controller: Node3D
	for candidate: Node3D in game.lobbers:
		if candidate.host == enemy: controller = candidate
	check(is_instance_valid(controller), label + "路障投蚀应来自真实生产攻击器")
	if not is_instance_valid(controller): return
	var before := float(game.gate_barricade_hp)
	var core_before := float(game.beacon_hp)
	game.simulate(.001)
	var state: Dictionary = controller.snapshot()
	check(String(state.phase) == "windup" and String(state.target_kind) == "barricade",
		label + "投蚀应在真实坡道选择最近活路障并锁落点")
	if String(state.phase) != "windup": return
	game.simulate(float(state.stage_remaining) + .001)
	check(String(controller.snapshot().phase) == "flight", label + "路障投蚀必须经过完整前摇发射")
	near(float(game.gate_barricade_hp), before, label + "发射阶段不得提前扣路障耐久")
	game.simulate(float(controller.snapshot().stage_remaining) - .01)
	near(float(game.gate_barricade_hp), before, label + "完整飞行结束前不能伤害路障")
	game.simulate(.011)
	check(String(controller.snapshot().phase) == "impact" and int(controller.snapshot().impacts) == 1,
		label + "实际路障落点应只结算一次")
	near(before - float(game.gate_barricade_hp), float(enemy.damage) * multiplier,
		label + "真实投蚀路障耐久损失必须使用当前减伤")
	near(float(game.beacon_hp), core_before, label + "南门落点不能波及远端灯塔")
	check(game.holdfast_hit_receipts.is_empty(), label + "南门落点不能伪造灯塔警报记录")
	await clear_enemies()

func install_hud_observer() -> void:
	var script := GDScript.new()
	script.source_code = HUD_OBSERVER
	check(script.reload() == OK, "中文 HUD 只读观察脚本应编译")
	var old: Control = game.hud
	var layer := old.get_parent()
	layer.remove_child(old)
	old.queue_free()
	var replacement: Control = script.new()
	replacement.game = game
	game.hud = replacement
	layer.add_child(replacement)
	replacement.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await wait_frames()

func hud_page(label: String) -> void:
	game.phase = "day"
	game.phase_time = game.DAY_LENGTH
	check(game.construction.begin(HOLDFAST), "真实建设入口应打开坚守信标网格预览")
	game.aim = Vector3(9, 5, 4)
	game.construction.tick(0.0)
	game.hud._process(0.0)
	var slot := Catalog.BUILDING_IDS.find(HOLDFAST) % 3
	check(game.hud.construction_page == 3 and game.hud.visible_construction_kinds().has(HOLDFAST),
		"中文坚守信标必须出现在真实建设第四页")
	for viewport: Vector2i in VIEWPORTS:
		root.size = viewport
		root.content_scale_size = viewport
		game.hud.queue_redraw()
		await wait_frames(4)
		check(Vector2i(game.hud.get_viewport_rect().size) == viewport, "中文建设页必须采用请求视口尺寸")
		for character in "坚守信标工坊零件":
			check(game.hud.font.has_char(character.unicode_at(0)), "实际系统字体必须具有中文字符 " + character)
		var title_drawn := false
		for row: Dictionary in game.hud.holdfast_labels:
			if String(row.text).contains("坚守信标"):
				title_drawn = true
				check(float(row.point.x) >= 435.0 and float(row.point.x) + float(row.width) <= 1005.0
					and float(row.point.y) - float(row.ascent) >= 642.0
					and float(row.point.y) + float(row.descent) <= 782.0,
					"实际坚守中文标签必须落在建设栏边界内")
		check(title_drawn, "第四建设页必须实际绘制中文坚守名称")
		var before_money := int(game.scrap)
		await click(game.hud.construction_kind_rect(slot))
		check(game.construction.kind == HOLDFAST and int(game.scrap) == before_money,
			"实际第四页按钮应只选择坚守许可，不透传为建造付款")
		if render_test and DisplayServer.get_name() != "headless":
			for _frame in 3:
				await process_frame
				await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			check(image.get_size() == viewport, "实际截图必须具有指定像素尺寸")
			var directory := "res://build/holdfast-" + capture_tag
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
			var basename := "%s-%dx%d.png" % [label, viewport.x, viewport.y]
			check(image.save_png(directory.path_join(basename)) == OK, "真实坚守证据应写入本地 build")
			evidence.captures.append(basename)
	game.construction.cancel()
	root.size = VIEWPORTS[0]
	root.content_scale_size = VIEWPORTS[0]
	isolate_night()

func building_and_damage() -> bool:
	stage = "building"
	if not await fresh(): return false
	check(game.archive.has_blueprint(HOLDFAST) and game.select_blueprint(HOLDFAST), "真实重开后应能选择已解锁坚守许可")
	await open_night(HOLDFAST)
	rejection(Vector3(-9, 5, -3), "存活工坊")
	var definition: Dictionary = Catalog.building(HOLDFAST)
	check(Catalog.BUILDING_IDS.has(HOLDFAST) and definition.title == "坚守信标"
		and int(definition.cost) == 110 and definition.size == Vector2i(3, 2)
		and float(definition.hp) == 520.0, "目录必须真实登记110零件、3×2、520耐久与中文名称")
	var workshop := build("workshop")
	var holdfast := build(HOLDFAST, Vector3(-9, 5, -3))
	check(workshop >= 0 and holdfast >= 0, "存活工坊后应能真实付费建造坚守信标")
	if workshop < 0 or holdfast < 0: return false
	var plot: Dictionary = game.districts.plots[holdfast]
	var position: Vector3 = plot.position
	var placement := Grid.placement(position, HOLDFAST)
	check(placement.size == Vector2i(3, 2) and placement.cells.size() == 6 and placement.inside,
		"坚守信标必须占据城内连续六格")
	for cell: Vector2i in placement.cells:
		check(game.construction.occupied_cells().has(cell), "真实建设占用表应包含信标每一格")
	var before_money := int(game.scrap)
	check(not game.build_structure_at(position, HOLDFAST) and int(game.scrap) == before_money,
		"实际同格重叠不能再次扣款或复制信标")
	check(is_instance_valid(plot.model) and (plot.label as Label3D).text.contains("坚守信标"),
		"真实信标必须具有模型和中文建筑标签")
	var bounds: AABB = (plot.model as Node3D).transform * game.districts.model_bounds(plot.model)
	check(bounds.position.x >= -1.5 - .001 and bounds.end.x <= 1.5 + .001
		and bounds.position.z >= -1.0 - .001 and bounds.end.z <= 1.0 + .001,
		"实际信标模型必须完整落在3×2占格内")
	await install_hud_observer()
	await hud_page("level-one")
	completed.append(stage)
	stage = "level-one"
	near(float(game.districts.holdfast_damage_multiplier()), .9, "一级存活信标应提供10%减伤")
	await melee_core(.9, "一级普通攻击")
	await melee_gate(.9, "一级南门路障")
	await lobber_gate(.9, "一级南门投蚀落点")
	await lobber_core(.9, "一级投蚀落点", true)
	await boss_core(.9, "一级首领拍击")
	completed.append(stage)
	stage = "level-two"
	before_money = int(game.scrap)
	var upgrade: Dictionary = game.districts.upgrade(holdfast)
	check(bool(upgrade.ok) and int(game.scrap) == before_money - 80
		and int(plot.level) == 2 and float(plot.hp) == 700.0, "真实二级升级必须扣80零件并恢复700耐久")
	near(float(game.districts.holdfast_damage_multiplier()), .82, "二级存活信标应提供18%减伤")
	check(not bool(game.districts.upgrade(holdfast).ok), "信标达到二级后应拒绝再次升级")
	await melee_core(.82, "二级普通攻击")
	await melee_gate(.82, "二级南门路障")
	await lobber_gate(.82, "二级南门投蚀落点")
	await lobber_core(.82, "二级投蚀落点")
	await boss_core(.82, "二级首领拍击")
	await hud_page("level-two")
	completed.append(stage)
	stage = "identity"
	check(bool(game.districts.damage(workshop, 100000.0).destroyed), "真实工坊损毁应解除后续建造前置")
	near(float(game.districts.holdfast_damage_multiplier()), .82, "工坊损毁不能移除已建存活信标效果")
	rejection(Vector3(9, 5, 4), "存活工坊")
	await melee_core(.82, "工坊失效后的存活信标")
	check(build("workshop", game.districts.plots[workshop].position) >= 0, "工坊应能同址付费重建")
	var original_model_id: int = plot.model.get_instance_id()
	var destroyed: Dictionary = game.districts.damage(holdfast, 100000.0)
	check(bool(destroyed.destroyed) and game.districts.live_level(HOLDFAST) == 0,
		"真实损毁必须立即移除存活信标")
	near(float(game.districts.holdfast_damage_multiplier()), 1.0, "损毁后不能保留减伤")
	await melee_core(1.0, "信标损毁后的普通攻击")
	await melee_gate(1.0, "信标损毁后的南门路障")
	await lobber_gate(1.0, "信标损毁后的南门投蚀落点")
	await hud_page("destroyed")
	var rebuilt := build(HOLDFAST, position)
	check(rebuilt == holdfast and game.districts.plots[rebuilt].model.get_instance_id() != original_model_id,
		"残址重建应保留plot索引并创建新的真实模型代际")
	near(float(game.districts.holdfast_damage_multiplier()), .9, "付费重建一级后应恢复10%减伤")
	await melee_core(.9, "残址重建后的普通攻击")
	var quote: Dictionary = game.demolition_at(position)
	before_money = int(game.scrap)
	check(bool(quote.valid) and int(quote.refund) == 55 and game.sell_structure_at(position)
		and int(game.scrap) == before_money + 55, "真实拆卖一级信标必须按本代付款返还55零件")
	check(not game.sell_structure_at(position) and int(game.scrap) == before_money + 55,
		"相同位置重复拆卖不能再次退款")
	near(float(game.districts.holdfast_damage_multiplier()), 1.0, "拆卖后不能保留减伤")
	await melee_core(1.0, "拆卖后的普通攻击")
	var new_index := build(HOLDFAST, position)
	check(new_index >= 0 and new_index != holdfast, "拆卖后同址建造必须产生新plot身份")
	var second_index := build(HOLDFAST, Vector3(9, 5, 4))
	check(second_index >= 0 and second_index != new_index, "红警式自由建造应允许第二座存活信标")
	near(float(game.districts.holdfast_damage_multiplier()), .82, "两座一级信标总效果应封顶18%")
	await melee_core(.82, "双一级封顶普通攻击")
	check(bool(game.districts.upgrade(second_index).ok), "第二座信标应允许独立付费升级")
	near(float(game.districts.holdfast_damage_multiplier()), .82, "二级加一级不能突破18%封顶")
	await melee_gate(.82, "多座封顶南门路障")
	check(game.sell_structure_at(game.districts.plots[second_index].position), "第二座真实二级信标应能拆卖")
	near(float(game.districts.holdfast_damage_multiplier()), .9, "拆卖二级后剩余一级应即时恢复10%档")
	await hud_page("rebuilt")
	completed.append(stage)
	return true

func troops_and_lifecycle() -> void:
	stage = "lifecycle"
	var barracks := build("barracks", Vector3(9, 5, -9))
	check(barracks >= 0, "真实兵营必须为训练生命周期提供生产入口")
	if barracks < 0: return
	var before := int(game.scrap)
	var order: Dictionary = game.squads.enqueue("ranged", barracks)
	check(bool(order.ok) and int(game.scrap) == before - 80, "真实弩手订单必须仍按80零件付款")
	game.squads.advance(7.99)
	check(game.squads.squads.is_empty(), "坚守信标不能加速8秒弩手训练")
	game.squads.advance(.02)
	check(game.squads.squads.size() == 1 and game.squads.squads[0].members.size() == 3,
		"完整真实训练应生成三名正常弩手")
	near(float(game.districts.squad_health_multiplier()), 1.2,
		"坚守信标不得叠加生命倍率，一座兵营仍只提供原有1.2倍")
	for member: BattleUnit in game.squads.squads[0].members:
		near(float(member.max_hp), 132.0, "信标不能更改一座兵营训练所得的原132生命弩手")
	game.squads.select_all()
	check(bool(game.squads.command_move(Vector3(9, 5, 9)).ok), "真实部队应能通过生产命令移至远端庭院")
	for _step in 160: game.squads.advance(.1)
	var row: Dictionary = game.squads.squads[0]
	var member: BattleUnit = row.members[0]
	check(member.position.distance_to(Vector3(7.75, 5, 9)) < 1.0,
		"真实弩手应完成庭院移动并远离灯塔受击精度区")
	# Enemy damage to a real paid troop keeps the unit armour path; holdfast
	# protects the two named structures, rather than becoming global armour.
	await clear_enemies()
	isolate_night()
	stand(Vector3(-11, 5, 10))
	var enemy: BattleUnit = game.spawn_creature(true, "basic")
	enemy.position = member.position + Vector3(0, 0, 1.2)
	var selected: Dictionary = game.choose_enemy_target(enemy)
	check(String(selected.kind) == "squad" and int(selected.token) == member.get_instance_id(),
		"真实敌人应选择训练所得最近弩手")
	var member_before := float(member.hp)
	game.simulate(.001)
	check(enemy.attack_queued, "真实敌人攻击付费部队必须进入前摇")
	game.simulate(float(enemy.attack_windup) + .001)
	near(member_before - float(member.hp), float(enemy.damage), "信标不能减免真实弩手承伤")
	await clear_enemies()
	var multiplier := float(game.districts.holdfast_damage_multiplier())
	var balance := int(game.scrap)
	await press(KEY_ESCAPE)
	check(game.phase == "night" and game.squads.selected_count() == 0,
		"已选部队时第一次真实Esc必须先清选择，保持原输入优先级")
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "真实 Esc 应进入暂停阶段")
	check(not game.build_structure_at(Vector3(-3, 5, -9), HOLDFAST)
		and not bool(game.squads.enqueue("ranged", barracks).ok) and int(game.scrap) == balance,
		"暂停应阻止信标建造与部队付款")
	near(float(game.districts.holdfast_damage_multiplier()), multiplier, "暂停不能改变存活建筑的可恢复效果")
	await press(KEY_ESCAPE)
	game.run.grant("坚守信标专项的非开局生命周期探针")
	game.open_draft()
	check(game.phase == "draft" and not game.select_blueprint(""), "非开局选卡不能改变信标许可")
	check(not game.build_structure_at(Vector3(-3, 5, -9), HOLDFAST) and int(game.scrap) == balance,
		"非开局铭刻应冻结建造付款")
	check(game.choose_card(0) and game.phase == "night", "非开局铭刻完成应回到原夜晚")
	near(float(game.districts.holdfast_damage_multiplier()), multiplier, "选卡前后信标效果不能丢失")
	game.day_number = 1
	game.finish_night()
	check(game.phase == "draft" and game.day_start_pending, "真实黎明应进入新白昼铭刻")
	check(game.choose_card(0) and game.phase == "day", "真实白昼卡片应进入整备")
	near(float(game.districts.holdfast_damage_multiplier()), multiplier, "昼夜切换不能丢失仍存活的信标")
	game.start_night()
	await clear_enemies()
	isolate_night()
	near(float(game.districts.holdfast_damage_multiplier()), multiplier, "真实日落后信标必须继续生效")
	game.request_run_restart(true)
	await wait_frames(2)
	check(not game.restart_pending, "未结束阶段不得重试或丢弃信标")
	var original_id := game.get_instance_id()
	game.beacon_hp = 5.0
	await melee_core(multiplier, "最后5点生命的真实普通攻击")
	check(game.phase == "ended" and not game.victory and game.beacon_hp == 0.0,
		"真实致命攻击必须按剩余5生命截断伤害并进入失败结算")
	near(float(game.districts.holdfast_damage_multiplier()), 1.0, "真实结束阶段必须清除有效减伤")
	game.request_run_restart(true)
	var elapsed := 0.0
	while is_instance_valid(game) and current_scene == game and elapsed < 6.0:
		await create_timer(.05, true, false, true).timeout
		elapsed += .05
	check(is_instance_valid(current_scene) and current_scene.get_instance_id() != original_id,
		"真实同种子重试必须在有限时间内替换场景")
	if is_instance_valid(current_scene) and current_scene is Node3D:
		game = current_scene as Node3D
		await wait_frames(4)
		game.set_process(false)
		game.world.set_process(false)
		check(game.phase == "draft" and game.run.seed_value == SEED and game.selected_blueprint == ""
			and game.districts.plots.is_empty() and game.squads.squads.is_empty()
			and game.squads.training_queues.is_empty(), "真实重试必须清空所有run-local信标和部队，仅保留种子及档案许可")
		check(game.archive.path == profile_path and game.archive.has_blueprint(HOLDFAST),
			"重试仍使用隔离档案并保留永久蓝图")
		near(float(game.districts.holdfast_damage_multiplier()), 1.0, "重试后的开局不能继承减伤")
	else:
		game = null
	if await fresh():
		check(game.districts.plots.is_empty() and game.selected_blueprint == "", "独立新局同样不能继承上局信标")
		near(float(game.districts.holdfast_damage_multiplier()), 1.0, "独立新局必须恢复基础承伤")
	completed.append(stage)

func watchdog() -> void:
	if finished: return
	check(false, "专项超过180秒有限执行期限")
	await finalize()

func finalize() -> void:
	if finished: return
	finished = true
	stage = "cleanup"
	await close_game()
	RunSession.clear_request(self)
	cleanup_profile()
	if render_test:
		check(DisplayServer.get_name() != "headless", "渲染模式必须使用实际图形后端")
	var output := "res://build/holdfast-" + capture_tag
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	check(file != null, "专项证据JSON必须可写入本地build")
	evidence["checks"] = checks
	evidence["failures"] = failures
	evidence["completed"] = completed
	evidence["renderer"] = DisplayServer.get_name()
	if file != null:
		file.store_string(JSON.stringify(evidence, "\t"))
		file.close()
	print("NIGHTFALL_HOLDFAST_BLUEPRINT_%s checks=%d failures=%d stages=%s" %
		["OK" if failures.is_empty() else "FAILED", checks, failures.size(), ",".join(completed)])
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	cleanup_profile()
	if await fresh():
		await archive_and_loadout()
		if await building_and_damage(): await troops_and_lifecycle()
	await finalize()
