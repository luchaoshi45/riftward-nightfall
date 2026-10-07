extends SceneTree
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
## 夜采真实生产专项。精度段使用5000零件、延长阶段和英雄站位，
## 部队由真实GUI付费训练，装载/返程只走生产simulate和原路径。
## 自然段保留原90/105/90与演员/库存/属性，独立记录收入、费用与损失。
const Catalog := preload("res://scripts/outpost_catalog.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
const RunSession := preload("res://scripts/run_session.gd")
const RunArchive := preload("res://scripts/run_archive.gd")
const SEED := 20261006
const STEP := .1
const HOME := Vector3(0, 5, 3.1)
const WORKSHOP := Vector3(-7.5, 5, -8)
const BARRACKS := Vector3(7, 5, -8.5)
const DEPOT := Vector3(-7.5, 5, -3.5)
const LAB := Vector3(7, 5, -3.5)
const INFIRMARY := Vector3(-7.5, 5, 2.5)
const NIGHT_BUTTON := Rect2(46, 662, 296, 26)
const VIEWPORTS := [Vector2i(1920, 1200), Vector2i(1920, 1080), Vector2i(1440, 900)]
const HUD_OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var haul_labels: Array[Dictionary] = []
func _draw() -> void:
	haul_labels.clear()
	super._draw()
func label(value: String, point: Vector2, size_px: int, color: Color = Color(\"e7e1d3\"), latin: bool = false) -> void:
	var actual: Font = display_font if latin else font
	haul_labels.append({\"text\":value,\"point\":point,\"width\":actual.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x,
		\"ascent\":actual.get_ascent(size_px),\"descent\":actual.get_descent(size_px)})
	super.label(value,point,size_px,color,latin)
"""

var game: Node3D
var checks := 0
var failures: Array[String] = []
var stage := "initialize"
var completed: Array[String] = []
var stage_done := false
var finished := false
var precision := true
var transport_wallet_check := true
var render_test := false
var natural_guard_policy := false
var natural_guard_retry := 0.0
var natural_hero_orders: Array[Dictionary] = []
var natural_hero_distance := 0.0
var natural_hero_minimum_range := INF
var natural_hero_guard_steps := 0
var natural_hero_accepted_paths := 0
var natural_hero_guard_origin := Vector3.ZERO
var hero_damage_book: Array[Dictionary] = []
var output_dir := "res://build/night-haul"
var profile_path := "user://riftward-night-haul-%d.json" % Time.get_ticks_usec()
var depot_index := -1
var lab_index := -1
var elapsed := 0.0
var route_out := 0
var route_in := 0
var movement_violations: Array[String] = []
var damage_book: Array[Dictionary] = []
var death_book: Array[Dictionary] = []
var wallet_book: Array[Dictionary] = []
var observed: Dictionary = {}
var evidence: Dictionary = {"seed":SEED,"fixture_parts":5000,"fixture_seconds":10000,
	"scope":"precision and natural economy are separate; source/Mac evidence does not replace native Windows delivery",
	"captures":[],"payments":[],"transport":[],"natural":{}}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	render_test = "--render-test" in args
	var index := args.find("--output-dir")
	if index >= 0 and index + 1 < args.size():
		var candidate := ProjectSettings.globalize_path(args[index + 1]).simplify_path()
		if valid_output(candidate): output_dir = candidate
		else: check(false, "专项证据必须在物理build子目录且路径链无符号链接")
	root.size = VIEWPORTS[0]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = VIEWPORTS[0]
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.position = Vector2i(-10000, -10000)
		root.hide()
	root.child_entered_tree.connect(inject_archive)
	create_timer(300.0, true, false, true).timeout.connect(watchdog)
	call_deferred("run")

func valid_output(candidate: String) -> bool:
	var base := ProjectSettings.globalize_path("res://build").simplify_path()
	if not candidate.begins_with(base + "/"): return false
	var cursor := base
	var pieces := candidate.trim_prefix(base + "/").split("/", false)
	for index in range(-1, pieces.size()):
		if index >= 0: cursor = cursor.path_join(pieces[index])
		var parent := DirAccess.open(cursor.get_base_dir())
		if parent != null and parent.is_link(cursor.get_file()): return false
	return true

func inject_archive(node: Node) -> void:
	if node is Node3D and node.has_method("select_blueprint"):
		node.set("archive", RunArchive.new(profile_path, true))

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(stage + ": " + message)
	if failures.size() <= 30: push_error(stage + ": " + message)

func near(actual: float, expected: float, message: String, tolerance: float = .001) -> void:
	check(is_finite(actual) and absf(actual - expected) < tolerance,
		message + " [actual=%.5f expected=%.5f]" % [actual, expected])

func planar(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x - second.x, first.z - second.z).length()

func frames(count: int = 3) -> void:
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

func mouse(point: Vector2, click: bool = false, button: int = MOUSE_BUTTON_LEFT, alt: bool = false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	if not click: return
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.alt_pressed = alt
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.button_mask = 0
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func click_ui(rect: Rect2) -> void:
	await mouse(rect.get_center() * game.hud.get_viewport_rect().size / Vector2(1440, 900), true)

func camera_at(point: Vector3) -> void:
	game.camera.size = 38.0
	game.camera.position = point + Vector3(0, 25, 29)
	game.camera.look_at(point)
	game.camera_follow = game.camera.position

func aim_at(point: Vector3) -> void:
	camera_at(point)
	await mouse(game.camera.unproject_position(point))
	game.flush_pending_aim()

func redraw() -> void:
	game.hud.queue_redraw()
	await frames()

func close_drawer() -> void:
	if not game.hud.detail_tab.is_empty(): await press(KEY_F3)

func choose(ids: Array[int]) -> void:
	check(game.squads.select_ids(ids) == ids, "公开选择只接受原真实存活生产编组")

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
	game.specializations.reset_effects()
	await process_frame

func close_game() -> void:
	if not is_instance_valid(game): return
	await game.prepare_shutdown()
	check(game.logistics.snapshot().remaining == 0 and game.logistics.snapshot().cargo == 0
		and game.logistics.night_haul_snapshot().active == 0, "真实关闭清空库存、载货与夜采许可")
	if current_scene == game: current_scene = null
	game.queue_free()
	game = null
	await frames(4)
	await create_timer(.5, true, false, true).timeout

func install_observer() -> void:
	var script := GDScript.new()
	script.source_code = HUD_OBSERVER
	check(script.reload() == OK, "只读HUD观察脚本完整转发原绘制")
	var old: Control = game.hud
	var layer := old.get_parent()
	layer.remove_child(old)
	old.queue_free()
	var replacement: Control = script.new()
	replacement.game = game
	game.hud = replacement
	layer.add_child(replacement)
	replacement.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await redraw()

func fresh(is_precision: bool = true) -> bool:
	await close_game()
	precision = is_precision
	transport_wallet_check = true
	natural_guard_policy = false
	natural_guard_retry = 0.0
	natural_hero_orders.clear()
	natural_hero_distance = 0.0
	natural_hero_minimum_range = INF
	natural_hero_guard_steps = 0
	natural_hero_accepted_paths = 0
	natural_hero_guard_origin = Vector3.ZERO
	hero_damage_book.clear()
	elapsed = 0.0
	route_out = 0
	route_in = 0
	movement_violations.clear()
	damage_book.clear()
	death_book.clear()
	wallet_book.clear()
	observed.clear()
	depot_index = -1
	lab_index = -1
	check(RunSession.queue_request(self, SEED, "siege"), "真实会话消费固定围城种子")
	game = load("res://scenes/nightfall.tscn").instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	await frames(5)
	game.set_process(false)
	game.world.set_process(false)
	game.hero.damage_confirmed.connect(record_hero_damage)
	check(game.archive.path == profile_path and game.phase == "draft", "_ready前隔离真实档案，不改玩家进度")
	check(game.scrap == 90 and game.squads.squads.is_empty(), "真实新局保留原90零件与空队列")
	check(game.logistics.has_method("night_haul_selection") and game.logistics.has_method("night_haul_snapshot")
		and game.logistics.has_method("toggle_selected_night_hauling"), "夜采API必须真实接入生产物流")
	if not game.logistics.has_method("night_haul_snapshot"): return false
	await install_observer()
	await press(KEY_1)
	check(game.phase == "night" and game.phase_time == 105.0, "真实开局键保留原105秒首夜")
	if precision:
		await clear_enemies()
		game.scrap = 5000
		game.phase_time = 10000.0
		game.wave_index = game.WAVES_PER_NIGHT
		game.pulse_timer = 100000.0
		game.hero.attack_timer = 100000.0
		for pad: Dictionary in game.world.tower_pads: pad.cooldown = 100000.0
		game.hero.position = HOME
		game.move_goal = HOME
		game.hero_path.clear()
		game.hero_keyboard_active = false
		game.hero.moving = false
	ledger("开局原有限库存")
	return true

func dawn() -> void:
	await close_drawer()
	# Precision alone removes hostile actors to prepare the real lifecycle.
	# A natural route must already have cleared through actual simulation.
	if precision: TransitionFixture.finish_for_fixture(game)
	check(game.phase == "draft" and game.day_start_pending, "精度人工准备或自然实战清场后，生产黎明进入铭刻")
	await press(KEY_1)
	check(game.phase == "day" and game.phase_time == 90.0, "真实铭刻输入进入原90秒白昼")
	if precision: game.phase_time = 10000.0

func select_building(kind: String) -> void:
	await close_drawer()
	if not game.construction.active: await press(KEY_Y)
	var target_page := Catalog.BUILDING_IDS.find(kind) / 3
	for _page in 4:
		var current: int = Catalog.BUILDING_IDS.find(String(game.construction.kind)) / 3
		if current == target_page: break
		await click_ui(game.hud.construction_page_rect(1 if target_page > current else -1))
	await click_ui(game.hud.construction_kind_rect(Catalog.BUILDING_IDS.find(kind) % 3))
	check(game.construction.active and String(game.construction.kind) == kind, "真实Y与建设翻页选中 " + kind)

func build_gui(kind: String, point: Vector3) -> int:
	await select_building(kind)
	await aim_at(point)
	var preview: Dictionary = game.construction.snapshot()
	check(bool(preview.valid) and bool(preview.tech_valid) and bool(preview.space_valid),
		"真实预览应允许 " + kind + ": " + String(preview.reason))
	if not bool(preview.valid):
		await press(KEY_ESCAPE)
		return -1
	var before: int = game.scrap
	await mouse(game.camera.unproject_position(point), true)
	var found := -1
	for index in game.districts.plots.size():
		var plot: Dictionary = game.districts.plots[index]
		if String(plot.kind) == kind and int(plot.level) > 0 and planar(plot.position, preview.point) < .05: found = index
	check(found >= 0 and game.scrap == before - int(Catalog.building(kind).cost), "GUI确认真实创建并只付目录费用 " + kind)
	(evidence.payments as Array).append({"precision":precision,"kind":kind,"before":before,"after":int(game.scrap),
		"cost":before-int(game.scrap),"phase":String(game.phase),"time_left":float(game.phase_time)})
	await press(KEY_ESCAPE)
	return found

func open_army(page: int = 1) -> void:
	if game.construction.active: await press(KEY_ESCAPE)
	if game.hud.detail_tab.is_empty(): await press(KEY_F3)
	if game.hud.detail_tab != "army": await click_ui(game.hud.details_tab_rect(2))
	for _page in 4:
		if game.hud.troop_page == page: break
		await click_ui(game.hud.troop_page_rect(1 if page > game.hud.troop_page else -1))
	check(game.hud.detail_tab == "army" and game.hud.troop_page == page, "真实F3翻页到原部队页")
	await redraw()

func train_gui(kind: String = "hauler") -> Dictionary:
	var index := Catalog.TROOP_IDS.find(kind)
	await open_army(index / 3)
	var before: int = game.scrap
	var old_count: int = game.squads.squads.size()
	await click_ui(game.hud.training_kind_rect(index % 3))
	check(game.scrap == before - int(Catalog.troop(kind).cost) and game.squads.squads.size() == old_count,
		"真实训练按钮只付款不瞬时出兵 " + kind)
	(evidence.payments as Array).append({"precision":precision,"kind":kind,"before":before,"after":int(game.scrap),
		"cost":before-int(game.scrap),"phase":String(game.phase),"time_left":float(game.phase_time)})
	await close_drawer()
	if not await wait_for(func() -> bool: return game.squads.squads.size() > old_count,
		float(Catalog.troop(kind).time) + 2.0, "完整真实训练后交付 " + kind): return {}
	var squad: Dictionary = game.squads.squads[old_count]
	check(String(squad.kind) == kind and squad.members.size() == 3, "训练交付原三员编组 " + kind)
	observe_members()
	return squad

func ready(teams: int = 1, research: bool = true) -> bool:
	if not await fresh(): return false
	await dawn()
	await build_gui("barracks", BARRACKS)
	await build_gui("workshop", WORKSHOP)
	depot_index = await build_gui("depot", DEPOT)
	if research: lab_index = await build_gui("laboratory", LAB)
	for _team in teams:
		var squad := await train_gui()
		if squad.is_empty(): return false
	check(game.squads.squads.size() == teams, "全部工队来自真实付费订单")
	return depot_index >= 0 and (not research or lab_index >= 0)

func right_field(index: int) -> void:
	await close_drawer()
	var point: Vector3 = game.logistics.fields[index].position
	await aim_at(point)
	await mouse(game.camera.unproject_position(point), true, MOUSE_BUTTON_RIGHT)
	for id: int in game.squads.selected_ids:
		if String(game.squads.squads[id].kind) == "hauler":
			check(int(team_row(id).preferred_field) == index, "真实右键指定原非空废料堆")

func team_row(id: int = 0) -> Dictionary:
	for row: Dictionary in game.logistics.snapshot().teams:
		if int(row.id) == id: return row
	return {}

func permit_row(id: int = 0) -> Dictionary:
	for row: Dictionary in game.logistics.night_haul_snapshot().teams:
		if int(row.id) == id: return row
	return {}

func state() -> Dictionary:
	var units: Array[Dictionary] = []
	var orders: Array[Dictionary] = []
	for squad: Dictionary in game.squads.squads:
		orders.append({"id":int(squad.id),"kind":String(squad.kind),"order":String(squad.order),"destination":squad.destination})
		for member: BattleUnit in squad.members:
			if is_instance_valid(member): units.append({"token":member.get_instance_id(),"hp":member.hp,
				"position":member.position,"path":member.path.duplicate(),"timer":member.path_timer,"moving":member.moving})
	return {"stock":game.logistics.snapshot(),"night":game.logistics.night_haul_snapshot(),"wallet":int(game.scrap),
		"units":units,"orders":orders,"phase":String(game.phase),"time":float(game.phase_time),
		"selection":game.squads.selected_ids.duplicate(),"goal":game.move_goal,"hero_path":game.hero_path.duplicate(),
		"rng":game.rng.state,"run_rng":game.run.rng.state,"spawn_rng":game.spawn_rng.state}

func ledger(label: String) -> void:
	var stock: Dictionary = game.logistics.snapshot()
	check(int(stock.remaining) + int(stock.cargo) + int(stock.delivered) + int(stock.lost) == 480,
		label + "：原480库存＝剩余＋载货＋已交＋死亡丢失")
	var cargo := 0
	for field: Dictionary in stock.fields:
		check(int(field.remaining) >= 0 and int(field.remaining) <= 96, label + "：原单堆96不回填不透支")
	for team: Dictionary in stock.teams:
		var total := 0
		for row: Dictionary in team.members:
			check(int(row.cargo) >= 0 and int(row.cargo) <= 8, label + "：原成员容量8不增发")
			total += int(row.cargo)
		check(total == int(team.cargo), label + "：队载货等于活成员账本")
		cargo += total
	check(cargo == int(stock.cargo), label + "：总载货等于真实成员账本")

func transaction_state() -> Dictionary:
	# A rejection may update a diagnostic reason, but cannot alter the actual
	# wallet, paid/used flags, stock, paths, orders, clocks or random streams.
	var result := state()
	for row: Dictionary in result.night.teams: row.erase("reason")
	return result

func observe_members() -> void:
	for squad: Dictionary in game.squads.squads:
		for member: BattleUnit in squad.members:
			if not is_instance_valid(member) or observed.has(member.get_instance_id()): continue
			observed[member.get_instance_id()] = true
			member.damage_confirmed.connect(record_damage)
			member.defeated.connect(record_death)

func record_damage(victim: BattleUnit, attacker: BattleUnit, hp_loss: float, shield_loss: float) -> void:
	damage_book.append({"at":elapsed,"victim":victim.get_instance_id(),"attacker":attacker.get_instance_id() if is_instance_valid(attacker) else -1,
		"hp_loss":hp_loss,"shield_loss":shield_loss,"cargo":int(victim.get_meta("haul_cargo",0)),"phase":String(game.phase)})

func record_hero_damage(victim: BattleUnit, attacker: BattleUnit, hp_loss: float, shield_loss: float) -> void:
	hero_damage_book.append({"at":elapsed,"victim":victim.get_instance_id(),
		"attacker":attacker.get_instance_id() if is_instance_valid(attacker) else -1,
		"hp_loss":hp_loss,"shield_loss":shield_loss,"position":victim.position,"phase":String(game.phase)})

func record_death(victim: BattleUnit, attacker: BattleUnit) -> void:
	death_book.append({"at":elapsed,"token":victim.get_instance_id(),"kind":String(victim.get_meta("squad_kind","")),
		"attacker":attacker.get_instance_id() if is_instance_valid(attacker) else -1,
		"phase":String(game.phase),"lost":int(game.logistics.snapshot().lost)})

func step(delta: float = STEP) -> void:
	var before: Dictionary = game.logistics.snapshot()
	var money: int = game.scrap
	var spent: int = game.logistics.night_haul_snapshot().spent
	var hero_before: Vector3 = game.hero.position
	var following: bool = not precision and natural_guard_policy and game.phase in ["day", "night"]
	if following and natural_hero_guard_steps == 0: natural_hero_guard_origin = hero_before
	var positions: Dictionary = {}
	for squad: Dictionary in game.squads.squads:
		for member: BattleUnit in squad.members:
			if is_instance_valid(member) and member.alive: positions[member.get_instance_id()] = member.position
	if not precision:
		game.aim = game.hero.position + Vector3(0, 0, 8)
		var near_enemy := INF
		var close_enemies := 0
		if natural_guard_policy:
			natural_guard_retry = maxf(0.0, natural_guard_retry - delta)
			var escort_target: BattleUnit = null
			if not game.squads.squads.is_empty():
				for member: BattleUnit in game.squads.squads[0].members:
					if is_instance_valid(member) and member.alive:
						escort_target = member
						break
			if is_instance_valid(escort_target) and natural_guard_retry <= 0.0:
				natural_guard_retry = 1.0
				if planar(game.hero.position, escort_target.position) > 2.2:
					game.plan_hero_path(escort_target.position)
					if not game.hero_path.is_empty(): natural_hero_accepted_paths += 1
					natural_hero_orders.append({"at":elapsed,"origin":game.hero.position,
						"target_token":escort_target.get_instance_id(),"target":escort_target.position,
						"goal":game.move_goal,"path_size":game.hero_path.size(),"phase":String(game.phase)})
			for enemy: BattleUnit in game.enemies:
				if not is_instance_valid(enemy) or not enemy.alive: continue
				var separation: float = game.hero.position.distance_to(enemy.position)
				if separation < near_enemy:
					near_enemy = separation
					game.aim = enemy.position
				if separation < 7.5: close_enemies += 1
		if (near_enemy < 10.5 if natural_guard_policy else game.gate_pressure() > 0): game.cast(0)
		if game.hero.hp < game.hero.max_hp * .6:
			game.cast(1)
			game.cast(4)
		if (close_enemies >= 3 if natural_guard_policy else game.gate_pressure() >= 6): game.cast(3)
	game.simulate(delta)
	elapsed += delta
	if following:
		natural_hero_distance += planar(hero_before, game.hero.position)
		natural_hero_guard_steps += 1
		if not game.squads.squads.is_empty():
			for member: BattleUnit in game.squads.squads[0].members:
				if is_instance_valid(member) and member.alive:
					natural_hero_minimum_range = minf(natural_hero_minimum_range, planar(game.hero.position, member.position))
	var after: Dictionary = game.logistics.snapshot()
	var permit: Dictionary = game.logistics.night_haul_snapshot()
	if precision and transport_wallet_check:
		var expected := money + int(after.delivered) - int(before.delivered) - (int(permit.spent) - spent)
		if game.scrap != expected and "隔离钱包变化" not in movement_violations: movement_violations.append("隔离钱包变化")
	elif money != game.scrap:
		wallet_book.append({"at":elapsed,"phase":String(game.phase),"before":money,"after":int(game.scrap),
			"delivered_delta":int(after.delivered)-int(before.delivered),"permit_delta":int(permit.spent)-spent})
	for squad: Dictionary in game.squads.squads:
		for member: BattleUnit in squad.members:
			if not is_instance_valid(member) or not member.alive or not positions.has(member.get_instance_id()): continue
			var old: Vector3 = positions[member.get_instance_id()]
			var valid: bool = member.position.is_finite() and game.outpost_walkable(member.position)
			valid = valid and absf(member.position.y - game.outpost_height(member.position)) < .001
			valid = valid and game.can_traverse(old, member.position) and planar(old, member.position) <= member.speed * delta + .001
			if not valid and "真实路径/步长" not in movement_violations: movement_violations.append("真实路径/步长")
			if (old.z < Layout.WALL_CENTER and member.position.z >= Layout.WALL_CENTER) or (old.z > Layout.WALL_CENTER and member.position.z <= Layout.WALL_CENTER):
				var ratio := (Layout.WALL_CENTER - old.z) / (member.position.z - old.z)
				if absf(lerpf(old.x, member.position.x, ratio)) >= Layout.GATE_HALF and "南门越界" not in movement_violations: movement_violations.append("南门越界")
				if member.position.z > old.z: route_out += 1
				else: route_in += 1

func advance(seconds: float) -> void:
	for frame in ceili(seconds / STEP):
		step(minf(STEP, seconds - frame * STEP))
		if frame % 100 == 99: await process_frame

func wait_for(predicate: Callable, seconds: float, label: String) -> bool:
	for frame in ceili(seconds / STEP):
		if bool(predicate.call()): return true
		if game.phase not in ["day","night"]: break
		step()
		if frame % 100 == 99: await process_frame
	var success := bool(predicate.call())
	check(success, label + " 超时: " + str(game.logistics.snapshot()))
	return success

func route_check(label: String) -> void:
	check(movement_violations.is_empty(), label + "：真实生产位移/南门/付款必须正确 " + str(movement_violations))
	ledger(label)

func enable_gui() -> void:
	await open_army()
	check(game.hud.night_haul_button_visible(), "二页原选队区域显示夜采按钮")
	await click_ui(NIGHT_BUTTON)
	await redraw()

func sunset() -> void:
	await close_drawer()
	game.start_night()
	check(game.phase == "night", "真实日落入口处理准备计划")
	if precision:
		await clear_enemies()
		game.phase_time = 10000.0
		game.wave_index = game.WAVES_PER_NIGHT
		game.pulse_timer = 100000.0

func eligibility() -> void:
	if not await ready(1, false): return
	choose([0])
	var before := state()
	check(not bool(game.logistics.prepare_selected_night_hauling().ok) and state() == before,
		"未显式指堆不能准备且不修改钱包或库存")
	await right_field(0)
	var balance: int = game.scrap
	await enable_gui()
	check(bool(permit_row().planned) and game.scrap == balance, "缺研究所仍可白昼准备，此刻不扣款")
	before = state()
	check(bool(game.logistics.prepare_selected_night_hauling().ok) and state() == before,
		"同一白昼重复准备完全幂等")
	await sunset()
	check(not bool(permit_row().active) and not bool(permit_row().used) and game.scrap == balance
		and String(permit_row().reason).contains("研究所"), "日落缺活研究所拒绝且不占当夜一次机会")
	lab_index = await build_gui("laboratory", LAB)
	game.scrap = 19
	before = transaction_state()
	check(not bool(game.logistics.toggle_selected_night_hauling().ok) and transaction_state() == before,
		"真实夜间19零件不得先装配或扣费")
	game.scrap = 200
	var depot: Dictionary = game.districts.plots[depot_index]
	game.districts.damage(depot_index, float(depot.hp) + 999.0)
	before = transaction_state()
	check(not bool(game.logistics.toggle_selected_night_hauling().ok) and transaction_state() == before,
		"缺活中转站不得夜间装配或消耗机会")
	depot_index = await build_gui("depot", depot.position)
	choose([0])
	balance = game.scrap
	await enable_gui()
	check(bool(permit_row().active) and bool(permit_row().used) and game.scrap == balance - 20,
		"补齐实际科技后GUI夜间装配只扣20一次")
	var result: Dictionary = game.logistics.prepare_selected_night_hauling()
	check(not bool(result.ok) and game.scrap == balance - 20, "夜间不得调用白昼准备重置账本")
	await close_drawer()
	game.squads.cancel_selection()
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "真实Esc暂停")
	before = state()
	check(not bool(game.logistics.toggle_selected_night_hauling().ok) and state() == before,
		"暂停阶段写入口拒绝且不改变状态")
	await press(KEY_ESCAPE)
	route_check("资格交易")
	stage_done = true

func payments() -> void:
	if not await ready(3): return
	for id in 3:
		choose([id])
		await right_field(id)
	choose([2, 0, 1])
	var balance: int = game.scrap
	await enable_gui()
	check(game.logistics.night_haul_snapshot().planned == 3 and game.scrap == balance,
		"三队逆序选择白昼准备均不扣款")
	game.scrap = 45
	await sunset()
	var paid: Dictionary = game.logistics.night_haul_snapshot()
	check(game.scrap == 5 and int(paid.spent) == 40 and int(paid.night_spent) == 40,
		"日落45余额只支付两个真实20订单")
	check(bool(permit_row(0).active) and bool(permit_row(1).active) and not bool(permit_row(2).active)
		and not bool(permit_row(2).used), "付款按原编组id升序而非选择顺序，无钱队保留资格")
	var repeat_before := state()
	game.logistics.on_night()
	check(state() == repeat_before, "重复真实夜晚通知不得重复扣费或重建许可")
	choose([0, 1, 2])
	var result: Dictionary = game.logistics.toggle_selected_night_hauling()
	check(bool(result.ok) and int(result.spent) == 0 and game.scrap == 5 and bool(permit_row(0).active)
		and bool(permit_row(1).active), "混选保留已装配队，缺钱队不得额外扣款")
	game.scrap = 25
	result = game.logistics.toggle_selected_night_hauling()
	check(bool(result.ok) and int(result.spent) == 20 and game.scrap == 5
		and game.logistics.night_haul_snapshot().active == 3, "同夜补钱只装配未付第三隊一次")
	var laboratory: Dictionary = game.districts.plots[lab_index]
	game.districts.damage(lab_index, float(laboratory.hp) + 999.0)
	advance_read_only()
	check(game.logistics.night_haul_snapshot().active == 3 and game.scrap == 5,
		"真实付款之后研究所毁坏不撤既有三队许可")
	choose([0])
	result = game.logistics.stop_selected_night_hauling()
	check(bool(result.ok) and not bool(permit_row(0).active) and bool(permit_row(0).used) and game.scrap == 5,
		"停止不退款且保留当夜已用账本")
	check(not bool(game.logistics.toggle_selected_night_hauling().ok) and game.scrap == 5,
		"同队同夜停止后不可重启")
	route_check("升序部分付款")
	stage_done = true

func advance_read_only() -> void:
	var before := state()
	for _read in 5:
		game.logistics.night_haul_selection()
		game.logistics.night_haul_snapshot()
		game.logistics.snapshot()
	check(state() == before, "展示读取不消费余额、库存、计时、随机或路径")

func markers(active: bool, id: int = 0) -> void:
	var squad: Dictionary = game.squads.squads[id]
	for member: BattleUnit in squad.members:
		if not is_instance_valid(member) or not member.alive: continue
		var marker := member.visual.find_child("NightHaulPermit", true, false) as Node3D
		check(bool(member.get_meta("night_haul_active", false)) == active, "便携标元数据必须来自原活许可")
		check(is_instance_valid(marker) and marker.visible and not marker.is_queued_for_deletion() if active
			else (not is_instance_valid(marker) or not marker.visible or marker.is_queued_for_deletion()),
			"实际模型便携标随活许可出现/撤销")

func arm_one() -> bool:
	if not await ready(): return false
	choose([0])
	await right_field(0)
	await enable_gui()
	await sunset()
	check(bool(permit_row().active) and game.logistics.night_haul_snapshot().spent == 20,
		"真实白昼准备经真实日落只付一次20")
	markers(true)
	return bool(permit_row().active)

func transport() -> void:
	if not await ready(): return
	choose([0])
	await right_field(0)
	await enable_gui()
	if not await wait_for(func() -> bool: return float(team_row().loading_progress) > 0.0,
		70.0, "真实日采路径抵达并开始半装载"): return
	var loading := team_row()
	var balance: int = game.scrap
	check(int(loading.cargo) == 0 and int(game.logistics.fields[0].remaining) == 96
		and int(game.logistics.fields[0].claimed_by) == 0, "半装载还未转移任何原库存且有真实预约")
	await sunset()
	check(game.scrap == balance - 20 and bool(permit_row().active), "半装载日落实扣20")
	near(float(team_row().loading_progress), float(loading.loading_progress), "成功日落保留真实半装载进度")
	check(int(team_row().field) == int(loading.field) and int(game.logistics.fields[0].claimed_by) == 0,
		"成功付费日落保留原资源预约与目标")
	for index in loading.members.size():
		check(team_row().members[index].destination == loading.members[index].destination,
			"成功日落不抹掉已经在执行的原成员目标")
	var frozen := state()
	game.logistics.on_night()
	check(state() == frozen, "重复夜钩子不重置活队装载/预约/钱/许可")
	if not await wait_for(func() -> bool: return int(team_row().cargo) == 24,
		6.0, "真实原3秒装载转移24货物"): return
	check(int(game.logistics.fields[0].remaining) == 72 and game.scrap == balance - 20,
		"夜间装载只扣有限库存，不预付交货收入")
	await capture("night-loaded")
	var stopped_money: int = game.scrap
	await enable_gui()
	check(not bool(permit_row().active) and bool(permit_row().used) and int(team_row().cargo) == 24
		and game.scrap == stopped_money, "GUI停止保留原24载货、不退款、不撤HAUL返站")
	markers(false)
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().delivered) == 24,
		75.0, "停止后实际南门路径返站卸货"): return
	check(game.scrap == stopped_money + 24 and int(team_row().cargo) == 0,
		"停止后的真实卸货支付且只支付原24")
	await advance(15.0)
	check(int(game.logistics.fields[0].remaining) == 72 and int(game.logistics.snapshot().delivered) == 24,
		"停止队只返站，不再出发或偷换其他堆")
	check(not bool(game.logistics.toggle_selected_night_hauling().ok), "已停队同夜不可重启")
	check(route_out >= 3 and route_in >= 3, "三名真实成员至少各过南门一次往返")
	route_check("停止载货返站")
	(evidence.transport as Array).append({"scenario":"stopped-loaded","stock":game.logistics.snapshot(),
		"out":route_out,"in":route_in,"permit":game.logistics.night_haul_snapshot()})
	if not await arm_one(): return
	if not await wait_for(func() -> bool: return float(team_row().loading_progress) > 0.0,
		70.0, "真实夜采半装载停采夹具"): return
	var remaining: int = game.logistics.snapshot().remaining
	await enable_gui()
	check(float(team_row().loading_progress) == 0.0 and int(team_row().cargo) == 0,
		"停止取消未装完原料，不按进度发货")
	await advance(20.0)
	check(game.logistics.snapshot().remaining == remaining and game.logistics.snapshot().delivered == 0,
		"半装载停采后有限库存保持原值")
	route_check("停止半装载")
	if not await ready(): return
	choose([0])
	await right_field(0)
	await enable_gui()
	if not await wait_for(func() -> bool: return int(team_row().cargo) == 24,
		70.0, "真实日采先带货进入返程"): return
	var cargo_before := team_row()
	await sunset()
	check(int(team_row().cargo) == 24 and int(game.logistics.fields[0].remaining) == 72,
		"已载货返程日落不丢货、不重复装载")
	check(bool(permit_row().active) and int(cargo_before.cargo) == 24, "返程中的显式计划真实装配")
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().delivered) >= 24,
		75.0, "返程跨日落仍实际卸货"): return
	route_check("返程跨日落")
	stage_done = true

func stock_and_stations() -> void:
	if not await arm_one(): return
	if not await wait_for(func() -> bool: return int(team_row().cargo) == 24,
		70.0, "毁站反例先实际取得载货"): return
	var balance: int = game.scrap
	var old: Dictionary = game.districts.plots[depot_index]
	var old_model := (old.model as Node).get_instance_id()
	game.districts.damage(depot_index, float(old.hp) + 999.0)
	await advance(2.0)
	check(String(team_row().state) == "waiting_home" and int(team_row().cargo) == 24
		and game.scrap == balance and bool(permit_row().active), "中转站毁坏保留已付款许可与实际货，不能远程兑现")
	depot_index = await build_gui("depot", old.position)
	check((game.districts.plots[depot_index].model as Node).get_instance_id() != old_model,
		"真实残址付费重建必须是新一代中转站模型")
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().delivered) >= 24,
		75.0, "保留货找到新代活站后真实卸载"): return
	route_check("毁站与重建")
	if not await arm_one(): return
	if not await wait_for(func() -> bool: return int(game.logistics.fields[0].remaining) == 0,
		240.0, "四趟实际装运采尽原96堆"): return
	check(not bool(permit_row().active) and bool(permit_row().used), "原指定堆采尽使许可失效但不抹已用")
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().cargo) == 0,
		75.0, "采尽最后原载货真实返站"): return
	check(game.logistics.snapshot().delivered == 96 and game.logistics.snapshot().remaining == 384,
		"夜采整堆仍严格交付原96，没有新增库存")
	await advance(20.0)
	for index in range(1, 5): check(game.logistics.fields[index].remaining == 96, "采尽只返站，不自动换原其他堆")
	check(not bool(game.logistics.command_selected_field(0).ok)
		and not bool(game.logistics.toggle_selected_night_hauling().ok), "真空堆与已用队拒绝再出发")
	markers(false)
	await capture("night-exhausted")
	route_check("原整堆守恒")
	if not await arm_one(): return
	if not await wait_for(func() -> bool: return int(team_row().cargo) == 24,
		70.0, "死亡反例先真实装24"): return
	var squad: Dictionary = game.squads.squads[0]
	var first: BattleUnit = squad.members[0]
	first.hurt(first.max_hp + 999.0, game.hero)
	check(game.logistics.snapshot().lost == 8 and game.logistics.snapshot().cargo == 16,
		"真实一员死亡只丢原token八货")
	for slot in [1, 2]:
		var member: BattleUnit = squad.members[slot]
		member.hurt(member.max_hp + 999.0, game.hero)
	step()
	check(game.logistics.snapshot().lost == 24 and game.logistics.snapshot().cargo == 0
		and not bool(permit_row().active), "真实全灭丢24、撤夜采，不向库存返还或给钱")
	route_check("真实死亡丢货")
	stage_done = true

func identities() -> void:
	for reason: String in ["route", "manual", "automatic", "squad", "field"]:
		if not await arm_one(): return
		var balance: int = game.scrap
		var original: Dictionary = game.squads.squads[0]
		var old_field: Dictionary = game.logistics.fields[0]
		match reason:
			"route": await right_field(1)
			"manual": check(bool(game.squads.command_move(HOME).ok), "真实公开手动改令")
			"automatic": check(bool(game.logistics.start_selected_hauling().ok), "真实公开恢复自动采运")
			"squad":
				# Deliberate raw identity substitution is a precision counterexample,
				# not an in-game player action. Keep the replacement's route intact.
				game.squads.squads[0] = original.duplicate()
				check(bool(game.logistics.command_selected_field(1).ok), "同id新Dictionary建立自己的真实新路线")
			"field": game.logistics.fields[0] = old_field.duplicate()
		step()
		check(not bool(permit_row().active) and bool(permit_row().used) and game.scrap == balance,
			reason + "取消旧许可而不退款或清当夜已用")
		if reason == "squad":
			check(String(game.squads.squads[0].order) == "haul" and int(team_row().preferred_field) == 1,
				"旧许可取消不能清同id新Dictionary自己的路线")
			game.squads.squads[0] = original
		if reason == "field": game.logistics.fields[0] = old_field
		if reason in ["manual", "automatic"]:
			choose([0])
			await right_field(0)
		check(not bool(game.logistics.toggle_selected_night_hauling().ok) and game.scrap == balance,
			reason + "同夜重新指堆仍不得二次装配或扣费")
		route_check("原身份/意图 " + reason)
	stage_done = true

func lifecycle() -> void:
	if not await arm_one(): return
	if not await wait_for(func() -> bool: return float(team_row().loading_progress) > 0.0,
		70.0, "暂停反例实际已有装载计时"): return
	var before := state()
	game.logistics.on_day()
	check(state() == before, "真实夜中错误day钩子不得清已付许可、资格、路径或装载")
	await close_drawer()
	game.squads.cancel_selection()
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "真实Esc进入暂停")
	before = state()
	game.simulate(1.0)
	game.logistics.advance(1.0)
	game.logistics.on_day()
	advance_read_only()
	await redraw()
	check(state() == before, "暂停冻结原夜采计时/路径/装载/许可与随机")
	await press(KEY_ESCAPE)
	game.run.grant("夜采专项生命周期夹具")
	game.open_draft()
	check(game.phase == "draft", "真实铭刻入口冻结夜采")
	before = state()
	game.simulate(1.0)
	game.logistics.advance(1.0)
	game.logistics.on_day()
	check(not bool(game.logistics.toggle_selected_night_hauling().ok) and state() == before,
		"选卡阶段冻结全部真实业务状态并拒写")
	await press(KEY_1)
	check(game.phase == "night", "真实选卡回原夜间")
	var paid: int = game.logistics.night_haul_snapshot().spent
	game.logistics.on_night_end()
	check(game.logistics.night_haul_snapshot().retired and not bool(permit_row().active)
		and bool(permit_row().used), "夜末退役清活许可但保留当夜已用和付款")
	choose([0])
	before = transaction_state()
	game.logistics.on_night()
	check(not bool(game.logistics.toggle_selected_night_hauling().ok) and transaction_state() == before,
		"真实夜末至黎明间反复night/写请求不能同夜复启")
	await dawn()
	check(not bool(permit_row().used) and not bool(permit_row().active)
		and game.logistics.night_haul_snapshot().spent == paid, "真实白昼清当夜资格并保留本局实际费用")
	choose([0])
	await right_field(0)
	await enable_gui()
	await sunset()
	check(game.logistics.night_haul_snapshot().spent == paid + 20 and bool(permit_row().active),
		"真实新昼夜才可再装配一次20")
	game.end_defeat("夜采专项真实失败清理")
	check(game.phase == "ended" and game.squads.squads.is_empty()
		and game.logistics.night_haul_snapshot().active == 0, "实际失败清原部队及许可")
	var old_id := game.get_instance_id()
	await press(KEY_ENTER)
	for _frame in 200:
		if current_scene != null and current_scene.get_instance_id() != old_id: break
		await create_timer(.02, true, false, true).timeout
	check(current_scene != null and current_scene.get_instance_id() != old_id, "真实Enter重试重载场景")
	if current_scene == null or current_scene.get_instance_id() == old_id: return
	game = current_scene as Node3D
	game.set_process(false)
	game.world.set_process(false)
	await frames(4)
	check(not is_instance_id_valid(old_id) and game.phase == "draft" and game.scrap == 90
		and game.archive.path == profile_path and game.squads.squads.is_empty(), "同种子重试释放旧场景与玩家外档案隔离")
	check(game.logistics.night_haul_snapshot().spent == 0 and game.logistics.night_haul_snapshot().used == 0,
		"真实重试不继承付款、已用或准备许可")
	ledger("重试原库存")
	stage_done = true

func escort_gui(carrier: Dictionary, guard: Dictionary) -> void:
	choose([int(guard.id)])
	await close_drawer()
	var target: BattleUnit = carrier.members[1]
	await aim_at(target.position)
	await mouse(game.camera.unproject_position(target.position), true, MOUSE_BUTTON_RIGHT, true)
	check(String(guard.order) == "escort" and game.squads.escort_snapshot().count > 0,
		"真实Alt右键给付费护卫绑定原活工队")

func combat() -> void:
	if not await ready(): return
	var carrier: Dictionary = game.squads.squads[0]
	var guard := await train_gui("shield")
	if guard.is_empty(): return
	choose([0])
	await right_field(0)
	await enable_gui()
	await escort_gui(carrier, guard)
	await sunset()
	if not await wait_for(func() -> bool: return String(team_row().state) == "loading",
		80.0, "真实工队及护卫抵达原夜采堆"): return
	var target: BattleUnit = carrier.members[1]
	transport_wallet_check = false
	var enemy: BattleUnit = game.spawn_creature(true, "basic")
	# Precision-only enemy placement witnesses original nearest-unit selection;
	# the workers and escort arrived through their untouched production paths.
	enemy.position = target.position + Vector3(0, 0, 1.0)
	enemy.position.y = game.outpost_height(enemy.position)
	enemy.attack_timer = 0.0
	var selected: Dictionary = game.choose_enemy_target(enemy)
	check(String(selected.kind) == "squad", "实际夜敌在近工队/护卫旁选择最近活单位")
	var nearest: BattleUnit = selected.unit
	var distance := INF
	var expected_token := -1
	for squad: Dictionary in game.squads.squads:
		for member: BattleUnit in squad.members:
			if not is_instance_valid(member) or not member.alive: continue
			var separation := planar(enemy.position, member.position)
			if separation < distance:
				distance = separation
				expected_token = member.get_instance_id()
	check(int(selected.token) == expected_token and planar(enemy.position, HOME) > distance,
		"真实选择与最近活单位距离一致且核心更远")
	var hp := nearest.hp
	game.update_creature(enemy, .001)
	check(enemy.attack_queued and game.attack_target_node(enemy) == nearest, "夜敌对原最近单位启动真实前摇")
	enemy.tick(enemy.windup_duration)
	game.update_creature(enemy, .001)
	check(nearest.hp < hp, "原夜敌前摇完成对原最近单位造成实伤")
	var enemy_hp := enemy.hp
	if not await wait_for(func() -> bool: return not enemy.alive or enemy.hp < enemy_hp,
		12.0, "真实护卫迎击近工队夜敌"): return
	check(guard.order == "escort" and game.squads.escort_snapshot().count > 0,
		"真实交战保持付费护卫绑定")
	markers(true)
	await capture("night-escort-combat")
	evidence["precision_combat"] = {"nearest_token":expected_token,"hp_loss":hp-nearest.hp,
		"enemy_hp_before_guard":enemy_hp,"enemy_hp_after":enemy.hp,"damage":damage_book.duplicate(true),
		"scope":"real paid workers/guard and physical routes; one basic night enemy placed for precision target witness"}
	route_check("真实护卫交战")
	stage_done = true

func capture(tag: String) -> void:
	if not render_test or DisplayServer.get_name() == "headless": return
	var before := state()
	var directory := ProjectSettings.globalize_path(output_dir).simplify_path()
	check(valid_output(directory), "实际图形证据仍在无链接build子目录")
	if not valid_output(directory): return
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "实际图形证据目录创建成功")
	for viewport: Vector2i in VIEWPORTS:
		root.size = viewport
		root.content_scale_size = viewport
		game.world.night_mix = 1.0 if game.phase == "night" else 0.0
		game.world.apply_lighting()
		await redraw()
		for _frame in 2: await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		check(picture.get_size() == root.content_scale_size
			and Vector2(picture.get_size()) == game.hud.get_viewport_rect().size,
			"Mac外壳尺寸与内容像素区分，实际截图须与请求/HUD一致")
		var name := "%s-%dx%d.png" % [tag, viewport.x, viewport.y]
		var path := directory.path_join(name)
		check(picture.save_png(path) == OK, "实际夜采截图完整写入build")
		(evidence.captures as Array).append({"name":name,"stage":stage,"sha256":FileAccess.get_sha256(path)})
	root.size = VIEWPORTS[0]
	root.content_scale_size = VIEWPORTS[0]
	await redraw()
	check(state() == before, "截图/读取不推进原路径、付款、许可或库存")

func quiet_hud() -> void:
	game.notice_time = 0.0
	game.reward_toasts.clear()
	game.beacon_alarm_time = 0.0
	game.hero_damage_flash_time = 0.0
	game.combat.clear_transients()
	game.hud.queue_redraw()

func hud() -> void:
	if not await ready(): return
	await build_gui("infirmary", INFIRMARY)
	var medic := await train_gui("medic")
	if medic.is_empty(): return
	game.squads.cancel_selection()
	quiet_hud()
	await redraw()
	var default_areas: Array = game.hud.live_panel_rects().duplicate()
	check(not default_areas.has(game.hud.SQUAD_PANEL_RECT), "新增夜采不恢复常驻大部队面板")
	choose([0, int(medic.id)])
	await right_field(0)
	for viewport: Vector2i in VIEWPORTS:
		root.size = viewport
		root.content_scale_size = viewport
		await open_army()
		check(Vector2i(game.hud.get_viewport_rect().size) == viewport, "真实GUI使用请求内容视口")
		check(game.hud.NIGHT_HAUL_BUTTON_RECT == NIGHT_BUTTON and game.hud.night_haul_button_visible()
			and game.hud.medic_button_visible() and game.hud.haul_button_visible(),
			"三视口混选显示夜采与原恢复自动/医护按钮")
		check(not NIGHT_BUTTON.intersects(game.hud.MEDIC_BUTTON_RECT)
			and not NIGHT_BUTTON.intersects(game.hud.HAUL_BUTTON_RECT), "真实夜采与原两支持命中矩形没有重叠")
		var therapy: bool = medic.therapy_enabled
		var money: int = game.scrap
		await click_ui(NIGHT_BUTTON)
		check(bool(permit_row().planned) and game.scrap == money and bool(medic.therapy_enabled) == therapy,
			"实际夜采按钮只准备原工队，不扣钱或误触混选医护")
		await redraw()
		var found := false
		var glyphs: Dictionary = {}
		var night_glyphs: Array[Rect2] = []
		var medic_glyphs: Array[Rect2] = []
		for row: Dictionary in game.hud.haul_labels:
			var rect := Rect2(Vector2(row.point.x, row.point.y-float(row.ascent)),
				Vector2(float(row.width), float(row.ascent)+float(row.descent)))
			check(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= 1440 and rect.end.y <= 900,
				"实际中文绘制字形在逻辑屏内 " + String(row.text))
			if String(row.text).contains("夜采") and row.point.y >= NIGHT_BUTTON.position.y and row.point.y <= NIGHT_BUTTON.end.y:
				found = true
				night_glyphs.append(rect)
				check(rect.position.x >= 46 and rect.end.x <= 342 and rect.end.y <= NIGHT_BUTTON.end.y,
					"夜采实际字形在原左支持列/按钮底界内")
			if row.point.x >= 356 and row.point.y >= 662 and row.point.y <= 688: medic_glyphs.append(rect)
			check(not String(row.text).contains("医护合计"), "混选时左统计行由夜采替代，不堆叠医护合计")
			for character in String(row.text):
				var code := character.unicode_at(0)
				if code >= 0x4e00 and code <= 0x9fff: glyphs[code] = character
		for code in glyphs: check(game.hud.font.has_char(int(code)), "实际平台字体包含中文 " + String(glyphs[code]))
		for left: Rect2 in night_glyphs:
			for right: Rect2 in medic_glyphs: check(not left.intersects(right), "混选夜采与医护实际字形不相交")
		check(found, "原二页实际绘制夜采中文")
		advance_read_only()
		await click_ui(game.hud.MEDIC_BUTTON_RECT)
		check(bool(medic.therapy_enabled) != therapy and bool(permit_row().planned) and game.scrap == money,
			"真实右医护按钮保留原开关且不触动夜采计划或付款")
		await click_ui(NIGHT_BUTTON)
		check(not bool(permit_row().planned) and game.scrap == money,
			"白昼第二次实际点击取消准备仍无扣费")
		await close_drawer()
		game.squads.cancel_selection()
		quiet_hud()
		await redraw()
		check(game.hud.live_panel_rects() == default_areas, "收起详情和取消选择后原默认HUD面积完整恢复")
		choose([0, int(medic.id)])
	root.size = VIEWPORTS[0]
	root.content_scale_size = VIEWPORTS[0]
	await open_army()
	await capture("mixed-night-haul-medic")
	await close_drawer()
	game.squads.cancel_selection()
	quiet_hud()
	await capture("default-clean")
	stage_done = true

func natural_walk(point: Vector3, limit: float = 50.0) -> bool:
	game.plan_hero_path(point)
	for frame in ceili(limit / STEP):
		if game.hero.position.distance_to(point) < 2.4: return true
		if game.phase not in ["day", "night"] or not game.hero.alive: return false
		step()
		if frame % 100 == 99: await process_frame
	return game.hero.position.distance_to(point) < 2.4

func natural_attempt(protected: bool) -> Dictionary:
	if not await fresh(false): return {}
	var payments_start: int = (evidence.payments as Array).size()
	check(game.scrap == 90 and game.phase_time == 105.0, "自然段不补钱、不延长首夜")
	game.plan_hero_path(Vector3(0, 5, 10))
	var cutoff: Dictionary = {}
	# The planned assault still ends at 105 seconds. Any surviving threat keeps
	# its real attack/HP/reward state until actual combat clears it, bounded here.
	for frame in ceili(240.0 / STEP):
		if game.phase != "night": break
		step()
		if cutoff.is_empty() and elapsed >= 105.0:
			cutoff = TransitionFixture.deadline_evidence(game, elapsed)
		if frame % 100 == 99: await process_frame
	var first_night_elapsed := elapsed
	check(game.phase == "draft" and game.hero.alive and game.beacon_hp > 0.0,
		"原演员/属性/技能策略完成105秒波次及真实残敌清场，240秒内迎来黎明")
	if game.phase != "draft":
		return {"seed":SEED,"opening_parts":90,"first_night_seconds":105,"first_night_elapsed":first_night_elapsed,
			"cutoff":cutoff,"phase":String(game.phase),"parts":int(game.scrap),"status":"first_night_survival_failed"}
	var dawn_money: int = game.scrap
	var first_kills: int = game.kills
	await press(KEY_1)
	check(game.phase == "day" and game.phase_time == 90.0 and game.scrap == dawn_money,
		"自然黎明保留原90秒白昼和真实赚得钱包")
	var gathered: Array[Dictionary] = []
	# The complete research/carrier/guard/permit chain costs 500. Attempt to
	# earn it through actual finite world crates; report any budget/time gap.
	for _source in 8:
		if game.scrap >= 500 or game.phase != "day" or game.phase_time <= 2.0: break
		var index := -1
		var distance := INF
		for candidate in game.world.salvage.size():
			var source: Dictionary = game.world.salvage[candidate]
			if bool(source.collected): continue
			var cost: float = game.contracts.route_distance(game.hero.position, source.position)
			if cost >= 0.0 and cost < distance:
				index = candidate
				distance = cost
		if index < 0: break
		var source: Dictionary = game.world.salvage[index]
		if not await natural_walk(source.position) or game.phase != "day": break
		var before: int = game.scrap
		await press(KEY_F)
		check(bool(source.collected) and game.scrap > before, "自然F确认实际收取原世界补给箱")
		if not bool(source.collected): break
		gathered.append({"index":index,"position":source.position,"gain":game.scrap-before,
			"time_left":float(game.phase_time),"route_distance":distance})
	var budget: int = game.scrap
	var result: Dictionary = {"seed":SEED,"opening_parts":90,"first_night_seconds":105,"day_seconds":90,
		"first_night_elapsed":first_night_elapsed,"clearance_seconds":maxf(0.0,first_night_elapsed-105.0),"cutoff":cutoff,
		"hero_protected_route":protected,
		"first_night_kills":first_kills,"dawn_parts":dawn_money,"actual_crates":gathered,"parts_before_chain":budget,
		"required_chain_parts":500,"prepared":false,"night_paid":false,"status":"budget_or_time_shortfall",
		"scope":"one fixed-seed scripted route with original clocks/actors/stats; no supplemented money, actor placement, enemy deletion or extended phases; not full human balance"}
	if budget >= 500 and game.phase == "day" and await natural_walk(HOME):
		await build_gui("barracks", BARRACKS)
		await build_gui("workshop", WORKSHOP)
		depot_index = await build_gui("depot", DEPOT)
		lab_index = await build_gui("laboratory", LAB)
		var carrier := await train_gui()
		var guard := await train_gui("shield")
		if not carrier.is_empty() and not guard.is_empty() and game.phase in ["day","night"]:
			choose([int(carrier.id)])
			await right_field(0)
			var before: int = game.scrap
			await enable_gui()
			result.prepared = bool(permit_row(int(carrier.id)).planned)
			result.night_paid = bool(permit_row(int(carrier.id)).active)
			check(game.scrap == before if game.phase == "day" else game.scrap == before-20,
				"自然实际GUI遵循白昼不扣/夜间20费用")
			await escort_gui(carrier, guard)
			result.departure_day_time_left = float(game.phase_time)
			result.parts_after_chain = int(game.scrap)
			natural_guard_policy = protected
			var first_night_stock := -1
			var first_night_spent := -1
			var first_night_cargo := -1
			var first_night_remaining := -1
			for frame in 2200:
				if game.phase == "ended" or not game.hero.alive: break
				if game.phase == "draft":
					await press(KEY_1)
					break
				if game.phase == "night" and first_night_stock < 0:
					first_night_stock = int(game.logistics.snapshot().delivered)
					first_night_spent = int(game.logistics.night_haul_snapshot().spent)
					first_night_cargo = int(game.logistics.snapshot().cargo)
					first_night_remaining = int(game.logistics.snapshot().remaining)
					result.sunset = {"parts":int(game.scrap),"stock":game.logistics.snapshot(),
						"permit":game.logistics.night_haul_snapshot(),"escort":game.squads.escort_snapshot()}
					result.night_paid = first_night_spent == 20
				if first_night_stock >= 0:
					var delivered_delta: int = int(game.logistics.snapshot().delivered) - first_night_stock
					var new_stock: int = first_night_remaining - int(game.logistics.snapshot().remaining)
					var enough: bool = (delivered_delta - first_night_cargo >= 24 and new_stock >= 24) if protected else delivered_delta >= 24
					if enough: break
				step()
				if frame % 100 == 99: await process_frame
			result.night_delivery = int(game.logistics.snapshot().delivered)-maxi(0,first_night_stock)
			result.carried_at_sunset = maxi(0, first_night_cargo)
			result.new_night_stock = maxi(0, first_night_remaining - int(game.logistics.snapshot().remaining)) if first_night_remaining >= 0 else 0
			result.new_night_delivered_minimum = maxi(0, int(result.night_delivery) - maxi(0, first_night_cargo))
			result.status = "paid_and_new_night_delivered" if bool(result.night_paid) and int(result.new_night_delivered_minimum) >= 24 else "actual_attempt_with_losses_or_time_gap"
			if game.phase != "ended":
				ledger("自然有限库存")
				markers(bool(permit_row(int(carrier.id)).active), int(carrier.id))
				camera_at(game.logistics.fields[0].position)
				await capture("natural-hero-protected-night" if protected else "natural-risk-night")
	result.final_phase = String(game.phase)
	result.final_parts = int(game.scrap)
	result.time_left = float(game.phase_time)
	result.hero_hp = game.hero.hp
	result.beacon_hp = game.beacon_hp
	result.stock = game.logistics.snapshot()
	result.permit = game.logistics.night_haul_snapshot()
	result.damage = damage_book.duplicate(true)
	result.hero_damage = hero_damage_book.duplicate(true)
	result.deaths = death_book.duplicate(true)
	result.wallet_changes = wallet_book.duplicate(true)
	result.crossings = {"out":route_out,"in":route_in}
	result.hero_orders = natural_hero_orders.duplicate(true)
	result.hero_guard = {"origin":natural_hero_guard_origin,"final_position":game.hero.position,
		"steps":natural_hero_guard_steps,"actual_distance":natural_hero_distance,
		"minimum_live_worker_distance":natural_hero_minimum_range if is_finite(natural_hero_minimum_range) else -1.0,
		"accepted_paths":natural_hero_accepted_paths}
	var payments: Array[Dictionary] = []
	for index in range(payments_start, (evidence.payments as Array).size()):
		var row: Dictionary = evidence.payments[index]
		if not bool(row.precision): payments.append(row)
	result.instant_gui_payments = payments
	check(movement_violations.is_empty(), "自然工队/护卫保持真实路径与速度 " + str(movement_violations))
	print("NIGHT_HAUL_NATURAL ", JSON.stringify(result))
	return result

func natural_economy() -> void:
	var risk := await natural_attempt(false)
	check(not risk.is_empty(), "原自然风险路线实际完成并保留结果")
	var protected := await natural_attempt(true)
	check(not protected.is_empty(), "同种子英雄合法护送自然路线实际完成")
	if risk.is_empty() or protected.is_empty(): return
	evidence.natural = {"risk":risk,"protected":protected}
	check(risk.actual_crates == protected.actual_crates and risk.instant_gui_payments == protected.instant_gui_payments
		and risk.departure_day_time_left == protected.departure_day_time_left and risk.parts_after_chain == protected.parts_after_chain,
		"两真实路线保留相同原种子、五箱资金、真实购买及出发时刻，只改变合法英雄护送策略")
	check(bool(protected.get("night_paid",false)) and int(protected.permit.spent) == 20
		and int(protected.permit.night_spent) == 20, "自然护送路线真实日落只支付20夜采装配")
	check(int(protected.get("new_night_stock",0)) >= 24 and int(protected.get("new_night_delivered_minimum",0)) >= 24
		and String(protected.final_phase) == "night", "自然至少24真实夜中新采并卸货，扣除日落已有货，不把跨日返程写成新夜采")
	var accepted := false
	for order: Dictionary in protected.hero_orders:
		if int(order.path_size) > 0: accepted = true
	check(accepted and int(protected.hero_guard.accepted_paths) > 0,
		"自然英雄护送至少一次真实路径接受，不把被拒绝的空路径发令当到场")
	check(float(protected.hero_guard.actual_distance) > 2.0,
		"自然英雄护送实际生产移动累计超过2米，不改站位、速度、属性或时钟")
	check(float(protected.hero_guard.minimum_live_worker_distance) >= 0.0
		and float(protected.hero_guard.minimum_live_worker_distance) <= 3.0,
		"自然英雄实际移动后接近原活工队三米内，护送证据不只记录发令")
	stage_done = true

func finish(code: int = 0) -> void:
	if finished: return
	finished = true
	await close_game()
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = profile_path + String(suffix)
		if FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "清私有专项档案，不留玩家副作用")
	var directory := ProjectSettings.globalize_path(output_dir).simplify_path()
	check(valid_output(directory), "专项回执限于无链接物理build目录")
	if valid_output(directory):
		check(DirAccess.make_dir_recursive_absolute(directory) == OK, "固定回执目录创建")
		var file := FileAccess.open(directory.path_join("result.json"), FileAccess.WRITE)
		check(file != null, "完整专项结果JSON写入本地build")
		if file != null:
			evidence.checks = checks
			evidence.failures = failures
			evidence.completed = completed
			file.store_string(JSON.stringify(evidence, "\t"))
			file.close()
	print("NIGHTFALL_NIGHT_HAUL_OK checks=%d" % checks if failures.is_empty() and code == 0
		else "NIGHTFALL_NIGHT_HAUL_FAILED checks=%d failures=%d stage=%s" % [checks,failures.size(),stage])
	quit(0 if failures.is_empty() and code == 0 else 1)

func watchdog() -> void:
	if finished: return
	check(false, "300秒墙钟看门狗有界退出，不把挂起当通过")
	await finish(1)

func run() -> void:
	var cases := {"eligibility":eligibility,"payments":payments,"transport":transport,
		"stock":stock_and_stations,"identity":identities,"lifecycle":lifecycle,
		"combat":combat,"hud":hud,"economy":natural_economy}
	for name: String in cases:
		if not failures.is_empty(): break
		stage = name
		stage_done = false
		print("NIGHT_HAUL_STAGE_BEGIN ", name)
		await (cases[name] as Callable).call()
		check(stage_done, "本段完成全部真实断言并显式结束")
		print("NIGHT_HAUL_STAGE_END ", name, " checks=",checks," failures=",failures.size())
		if stage_done: completed.append(name)
	check(completed.size() == cases.size(), "全九段完成才允许整套成功标记")
	await finish()
