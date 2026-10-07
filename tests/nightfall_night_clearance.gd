extends SceneTree
## 每夜真实清场专项。精度段明确压缩时钟、用5000零件、站位与冷却隔离，
## 全部敌方演员通过生产hurt/defeated清除；这些夹具不是自然经济证明。
## 自然段保留原90零件、105秒计划窗口、90秒白昼、原演员/属性与合法技能路径。
const Session := preload("res://scripts/run_session.gd")
const Archive := preload("res://scripts/run_archive.gd")
const Catalog := preload("res://scripts/outpost_catalog.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
const SEED := 20261006
const STEP := .1
const VIEWPORTS := [Vector2i(1920,1200),Vector2i(1920,1080),Vector2i(1440,900)]
const HOME := Vector3(0,5,3.1)
const HERO_POINT := Vector3(-4,5,-10)
const SOURCE_POINT := Vector3(-10,5,-10)
const BUILD_POINTS := {
	"barracks":Vector3(7,5,-8.5),"workshop":Vector3(-7.5,5,-8),
	"depot":Vector3(-7.5,5,-3.5),"laboratory":Vector3(7,5,-3.5)}
const OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var clearance_labels: Array[Dictionary] = []
var clearance_boxes: Array[Rect2] = []
func _draw() -> void:
	clearance_labels.clear()
	clearance_boxes.clear()
	super._draw()
func label(value: String, point: Vector2, size_px: int, color: Color = Color(\"e7e1d3\"), latin: bool = false) -> void:
	var actual: Font = display_font if latin else font
	clearance_labels.append({\"text\":value,\"point\":point,\"width\":actual.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x,
		\"ascent\":actual.get_ascent(size_px),\"descent\":actual.get_descent(size_px),\"latin\":latin})
	super.label(value,point,size_px,color,latin)
func box(rect: Rect2, fill: Color = Color(.022,.035,.045,.88), outline: Color = Color(\"435455\")) -> void:
	clearance_boxes.append(rect)
	super.box(rect,fill,outline)
"""

var game: Node3D
var checks := 0
var failures: Array[String] = []
var stage := "initialize"
var stage_done := false
var completed: Array[String] = []
var finished := false
var precision := true
var render_test := false
var segment := ""
var output_dir := ""
var profile_path := "user://riftward-night-clearance-%d.json" % Time.get_ticks_usec()
var elapsed := 0.0
var births: Array[Dictionary] = []
var deaths: Array[Dictionary] = []
var damage: Array[Dictionary] = []
var wallets: Array[Dictionary] = []
var observed: Dictionary = {}
var evidence: Dictionary = {
	"scope":"precision fixtures and original-clock natural routes are separate; source/Mac evidence is not native Windows delivery",
	"precision":{"parts":5000,"lethal_hurt":100000,"compressed_deadlines":true,"actor_stations":true,"unrelated_attack_cooldowns":100000},
	"captures":[],"ordinary":[],"guards":[],"flight":[],"ledger":[],"specialists":[],"transport":{},"natural":[]}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	render_test = "--render-test" in args
	var index := args.find("--segment")
	if index >= 0 and index + 1 < args.size(): segment = args[index + 1]
	var backend := "headless" if DisplayServer.get_name() == "headless" else ("opengl" if RenderingServer.get_current_rendering_method() == "gl_compatibility" else "metal")
	output_dir = ProjectSettings.globalize_path("res://build/night-clearance/" + backend).simplify_path()
	index = args.find("--output-dir")
	if index >= 0 and index + 1 < args.size():
		var candidate := ProjectSettings.globalize_path(args[index + 1]).simplify_path()
		if valid_output(candidate): output_dir = candidate
		else: check(false,"证据目录只接受物理build/night-clearance及固定后端子目录")
	check(valid_output(output_dir),"默认证据路径链必须无符号链接")
	root.size = VIEWPORTS[0]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = VIEWPORTS[0]
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.position = Vector2i(-10000,-10000)
		root.hide()
	root.child_entered_tree.connect(inject_archive)
	create_timer(300.0,true,false,true).timeout.connect(watchdog)
	call_deferred("run")

func valid_output(candidate: String) -> bool:
	var base := ProjectSettings.globalize_path("res://build/night-clearance").simplify_path()
	if candidate not in [base,base.path_join("headless"),base.path_join("metal"),base.path_join("opengl")]: return false
	var cursor := candidate
	while cursor != cursor.get_base_dir():
		var parent := DirAccess.open(cursor.get_base_dir())
		if parent != null and parent.is_link(cursor.get_file()): return false
		cursor = cursor.get_base_dir()
	return true

func inject_archive(node: Node) -> void:
	if node is Node3D and node.has_method("select_blueprint"):
		node.set("archive",Archive.new(profile_path,true))

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(stage + ": " + message)
	if failures.size() <= 35: push_error(stage + ": " + message)

func near(actual: float, expected: float, message: String, tolerance: float = .001) -> void:
	check(is_finite(actual) and absf(actual-expected) < tolerance,message + " actual=%.6f expected=%.6f" % [actual,expected])

func frames(count: int = 3) -> void:
	for _frame in count: await process_frame

func living(unit: Variant) -> bool:
	return is_instance_valid(unit) and unit is BattleUnit and not unit.is_queued_for_deletion() and unit.alive

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event,true)
	event.pressed = false
	root.push_input(event,true)
	await process_frame

func mouse(point: Vector2, button: int = MOUSE_BUTTON_RIGHT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion,true)
	await process_frame
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.button_mask = MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	root.push_input(event,true)
	await process_frame
	event.pressed = false
	event.button_mask = 0
	root.push_input(event,true)
	await process_frame

func click_ui(rect: Rect2) -> void:
	await mouse(rect.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900),MOUSE_BUTTON_LEFT)

func camera_at(point: Vector3) -> void:
	game.camera.size = 38.0
	game.camera.position = point + Vector3(0,25,29)
	game.camera.look_at(point)
	game.camera_follow = game.camera.position

func stand(point: Vector3) -> void:
	check(precision,"仅精度夹具允许直接站位")
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.move_goal = point
	game.hero_path.clear()
	game.hero_keyboard_active = false
	game.hero.moving = false

func record_death(victim: BattleUnit, source: BattleUnit) -> void:
	deaths.append({"token":victim.get_instance_id(),"wave":int(victim.get_meta("wave_reward_id",-1)),
		"role":String(victim.get_meta("threat","")),"at":elapsed,"phase":String(game.phase),
		"time":float(game.phase_time),"clearance":game.night_clearance_snapshot(),"hp":victim.hp,"alive":victim.alive,
		"source":source.get_instance_id() if is_instance_valid(source) else -1,"parts_after_root_callback":int(game.scrap)})

func record_damage(victim: BattleUnit, source: BattleUnit, hp_loss: float, shield_loss: float) -> void:
	damage.append({"victim":victim.get_instance_id(),"hero":victim == game.hero,"at":elapsed,
		"source":source.get_instance_id() if is_instance_valid(source) else -1,
		"hp_loss":hp_loss,"shield_loss":shield_loss,"position":victim.position,"phase":String(game.phase),
		"time":float(game.phase_time),"clearing":bool(game.night_clearance_active)})

func observe() -> void:
	if not is_instance_valid(game): return
	for raw: Variant in game.enemies:
		if not living(raw): continue
		var unit: BattleUnit = raw
		if observed.has(unit.get_instance_id()): continue
		observed[unit.get_instance_id()] = true
		births.append({"token":unit.get_instance_id(),"wave":int(unit.get_meta("wave_reward_id",-1)),
			"role":String(unit.get_meta("threat","")),"at":elapsed,"night":int(game.day_number),"position":unit.position,
			"max_hp":unit.max_hp,"hp":unit.hp,"damage":unit.damage,"armor":unit.armor,"speed":unit.speed,
			"summoned":bool(unit.get_meta("summoned_reinforcement",false)),
			"fixture_extra":bool(unit.get_meta("clearance_fixture_extra",false))})
		unit.defeated.connect(record_death)
		unit.damage_confirmed.connect(record_damage)

func step(delta: float = STEP) -> void:
	observe()
	var before: int = game.scrap
	var before_phase: String = game.phase
	var before_day: int = game.day_number
	game.simulate(delta)
	if before_phase in ["night","day"]: elapsed += delta
	if before != game.scrap:
		wallets.append({"at":elapsed,"before":before,"after":int(game.scrap),"phase_before":before_phase,
			"phase_after":String(game.phase),"night":before_day,"clearance":game.night_clearance_snapshot()})
	if game.phase == "night": observe()

func advance(seconds: float) -> void:
	for frame in ceili(seconds/STEP):
		step(minf(STEP,seconds-frame*STEP))
		if frame % 100 == 99: await process_frame

func signature() -> Dictionary:
	var units: Array[Dictionary] = []
	for raw: Variant in game.enemies:
		if not is_instance_valid(raw) or not raw is BattleUnit: continue
		var unit: BattleUnit = raw
		units.append({"token":unit.get_instance_id(),"alive":unit.alive,"hp":unit.hp,"shield":unit.shield,
			"position":unit.position,"windup":unit.attack_windup,"queued":unit.attack_queued,"cooldown":unit.attack_timer})
	return {"phase":String(game.phase),"day":int(game.day_number),"parts":int(game.scrap),"kills":int(game.kills),
		"time":float(game.phase_time),"waves":int(game.wave_index),"clearance":game.night_clearance_snapshot(),
		"hero_hp":game.hero.hp,"hero_alive":game.hero.alive,"hero_position":game.hero.position,"beacon":float(game.beacon_hp),
		"enemies":units,"queues":game.squads.training_queues.duplicate(true),"stock":game.logistics.snapshot(),
		"permit":game.logistics.night_haul_snapshot(),"spawn_rng":game.spawn_rng.state}

func close_game() -> void:
	if not is_instance_valid(game): return
	await game.prepare_shutdown()
	check(not game.night_clearance_active and not game.final_clearance_active and game.night_clearance_elapsed == 0.0,
		"真实关闭重置每夜与末夜清场状态")
	check(game.logistics.snapshot().remaining == 0 and game.logistics.night_haul_snapshot().active == 0,
		"真实关闭清理有限物流库存与夜采许可")
	if current_scene == game: current_scene = null
	game.queue_free()
	game = null
	await frames(4)
	await create_timer(.5,true,false,true).timeout

func install_observer() -> void:
	var script := GDScript.new()
	script.source_code = OBSERVER
	check(script.reload() == OK,"只读HUD观察器完整继承并转发绘制")
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

func fresh(is_precision: bool = true, seed_value: int = SEED) -> bool:
	await close_game()
	precision = is_precision
	elapsed = 0.0
	births.clear(); deaths.clear(); damage.clear(); wallets.clear(); observed.clear()
	check(Session.queue_request(self,seed_value,"siege"),"真实会话使用所选围城种子")
	game = load("res://scenes/nightfall.tscn").instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	await frames(5)
	game.set_process(false)
	game.world.set_process(false)
	check(game.has_method("night_clearance_snapshot") and game.has_method("begin_night_clearance"),"真实清场生产接口存在")
	if not game.has_method("night_clearance_snapshot") or not game.has_method("begin_night_clearance"): return false
	check(game.archive.path == profile_path and game.phase == "draft","_ready之前隔离玩家档案")
	check(game.scrap == 90 and game.run.seed_value == seed_value and not game.night_clearance_active,"原开局钱包、种子与清场初态")
	game.hero.damage_confirmed.connect(record_damage)
	await install_observer()
	await press(KEY_1)
	check(game.phase == "night" and game.phase_time == 105.0 and game.wave_index == 1,"真实开局键启动原105秒首夜与第一波")
	observe()
	if precision:
		game.scrap = 5000
		suspend_defense()
	return true

func suspend_defense() -> void:
	check(precision,"自然段不得抑制原防御行为")
	game.hero.attack_timer = 100000.0
	game.pulse_timer = 100000.0
	for pad: Dictionary in game.world.tower_pads: pad.cooldown = 100000.0

func issue_all_waves() -> void:
	check(precision,"精度夹具才压缩计划波次的生成时刻")
	for _wave in 5:
		if game.wave_index >= game.WAVES_PER_NIGHT: break
		game.spawn_night_wave()
		observe()
	check(game.wave_index == game.WAVES_PER_NIGHT,"五份真实保存波全部实际出生")

func kill_all(keep: BattleUnit = null) -> void:
	check(precision,"自然证据禁止夹具致死与删怪")
	observe()
	for raw: Variant in game.enemies.duplicate():
		if not living(raw): continue
		var unit: BattleUnit = raw
		if unit != keep: unit.hurt(100000.0,game.hero)

func next_precision_night() -> void:
	issue_all_waves()
	kill_all()
	game.phase_time = .01
	step(.02)
	check(game.phase == "draft" and not game.night_clearance_active,"精度全真死亡后通过实际截止入口进入黎明")
	await press(KEY_1)
	check(game.phase == "day" and game.phase_time == 90.0,"实际黎明铭刻恢复原90秒白昼")
	game.phase_time = .01
	step(.02)
	check(game.phase == "night" and game.phase_time == 105.0 and not game.night_clearance_active,"实际日落重置清场和原下一夜时钟")
	suspend_defense()
	observe()

func precision_night(night: int = 1) -> bool:
	if not await fresh(): return false
	for _night in range(1,night): await next_precision_night()
	check(game.day_number == night and game.phase == "night","精度阶段推进到目标真实夜次")
	return game.phase == "night"

func residual(role: String = "basic", point: Vector3 = Vector3(100,0,-100)) -> BattleUnit:
	issue_all_waves()
	var wave_id: int = game.active_wave_reward_id
	var before: Dictionary = game.wave_rewards.snapshot(wave_id)
	check(not bool(before.cleared) and int(before.kills) < int(before.count),"额外精度残敌登记前原末波仍有真实活敌，不能重开已清账本")
	# This is an additional precision actor, not an original planned survivor.
	# Register while the original wave is live, then genuinely kill the others.
	var unit: BattleUnit = game.spawn_creature(true,role)
	unit.set_meta("clearance_fixture_extra",true)
	unit.position = point
	unit.position.y = game.outpost_height(point)
	check(game.register_active_wave_enemy(unit),"额外精度残敌真实登记到尚未清空的原末波预算")
	var registered: Dictionary = game.wave_rewards.snapshot(wave_id)
	check(int(registered.count) == int(before.count)+1 and int(registered.budget) == int(before.budget)
		and int(registered.paid) == int(before.paid) and not bool(registered.cleared),"额外夹具只增加真实演员计数，不重开或增加原波预算")
	observe()
	kill_all(unit)
	var residual_wave: Dictionary = game.wave_rewards.snapshot(wave_id)
	check(living(unit) and int(residual_wave.kills) == int(residual_wave.count)-1 and not bool(residual_wave.cleared),
		"原计划敌人真实死亡后额外精度演员仍保留同一未清末波")
	return unit

func enter_clearance() -> void:
	check(precision,"自然证据不能压缩截止时钟")
	game.phase_time = .01
	step(.02)
	check(game.phase == "night" and game.night_clearance_active and game.phase_time == 0.0,"105秒窗口截止进入真实清场且时钟保持零")

func guard_reject(label: String) -> void:
	var before := signature()
	game.finish_night()
	check(signature() == before,"finish_night门禁无侧效应：" + label)
	(evidence.guards as Array).append(label)

func guards() -> void:
	if not await precision_night(): return
	guard_reject("原105秒窗口仍有时间")
	game.begin_night_clearance()
	check(not game.night_clearance_active,"正时间不能提前开启清场")
	game.phase_time = 0.0
	game.begin_night_clearance()
	check(not game.night_clearance_active,"未发齐五波不能开启清场")
	guard_reject("时钟零但五波未发齐")
	var keep: BattleUnit = residual()
	game.begin_night_clearance()
	check(game.night_clearance_active and not game.final_clearance_active,"普通夜与末夜清场子态区分")
	var state: Dictionary = game.night_clearance_snapshot()
	game.begin_night_clearance()
	check(game.night_clearance_snapshot() == state,"重复清场入口幂等且不清演员/重置elapsed")
	guard_reject("普通清场仍有真实活残敌")
	keep.hurt(100000.0,game.hero)
	for property: String in ["quitting","restart_pending","shutting_down"]:
		game.set(property,true)
		guard_reject(property)
		game.set(property,false)
	for phase_value: String in ["paused","draft","day"]:
		game.phase = phase_value
		guard_reject("非战斗阶段" + phase_value)
	game.phase = "night"
	game.phase_time = .1
	guard_reject("清场态仍不能使用正时钟完成")
	game.phase_time = 0.0
	game.wave_index = 4
	guard_reject("清场态仍检查真实五波完成")
	game.wave_index = 5
	game.hero.alive = false
	guard_reject("英雄已死亡")
	game.hero.alive = true
	var hp: float = game.hero.hp
	game.hero.hp = 0.0
	guard_reject("英雄生命为零")
	game.hero.hp = hp
	var beacon: float = game.beacon_hp
	game.beacon_hp = 0.0
	guard_reject("灯塔生命为零")
	game.beacon_hp = beacon
	game.finish_night()
	check(game.phase == "draft" and game.day_number == 2,"全部真实门禁成立后仅一次黎明")
	var after := signature()
	game.finish_night()
	check(signature() == after,"黎明阶段重复结束调用不得增天数或再次付款")
	stage_done = true

func ordinary() -> void:
	for night in [1,2]:
		if not await precision_night(night): return
		var keep: BattleUnit = residual("basic",Vector3(-5.2,5,-10))
		stand(HERO_POINT)
		keep.attack_timer = 0.0
		game.phase_time = .08
		step(.01)
		check(keep.attack_queued and keep.attack_windup > .1,"普通夜截止前启动真实近战前摇")
		var token: int = keep.get_instance_id()
		var hp: float = keep.hp
		var windup: float = keep.attack_windup
		var target: String = keep.get_meta("attack_target_kind","")
		var spawn_state: int = game.spawn_rng.state
		var plan: Array = game.night_plan.duplicate(true)
		step(.1)
		check(game.phase == "night" and game.night_clearance_active and not game.final_clearance_active,"第%d普通夜残敌不能被计时删掉" % night)
		check(living(keep) and keep.get_instance_id() == token and keep.hp == hp and keep.attack_queued,
			"跨界保留原实例、原生命与真实前摇")
		check(keep.attack_windup < windup and keep.get_meta("attack_target_kind","") == target,"前摇与锁定目标跨界继续")
		var before_hits: int = damage.size()
		step(.3)
		var real_hit := false
		for index in range(before_hits,damage.size()):
			var row: Dictionary = damage[index]
			if bool(row.hero) and int(row.source) == token and float(row.hp_loss) > 0.0 and bool(row.clearing): real_hit = true
		check(real_hit,"跨105秒前摇在清场期间造成真实英雄生命损失")
		near(game.phase_time,0.0,"普通清场时钟不变负数")
		near(game.night_clearance_elapsed,.3,"只有实际清场战斗步推进elapsed")
		var money: int = game.scrap
		var ledgers: Array[Dictionary] = []
		for wave in 5: ledgers.append(game.wave_rewards.snapshot((night-1)*5+wave))
		await advance(.2)
		check(game.spawn_rng.state == spawn_state and game.night_plan == plan and game.wave_index == 5,
			"清场期间不重刷计划或消耗出生随机流")
		check(game.scrap == money,"残敌只继续攻击，不产生重复波次奖励")
		for wave in 5: check(game.wave_rewards.snapshot((night-1)*5+wave) == ledgers[wave],"未死残敌不能推进波次账本")
		(evidence.ordinary as Array).append({"night":night,"residual":token,"before_hp":hp,"snapshot":game.night_clearance_snapshot(),"damage":damage.duplicate(true)})
		await capture("ordinary-night-%d" % night)
		keep.hurt(100000.0,game.hero)
		step(.02)
		check(game.phase == "draft" and game.day_number == night+1 and not game.night_clearance_active,"真实最后死亡后才推进普通黎明")
		await press(KEY_1)
		check(game.phase == "day" and game.phase_time == 90.0,"加时不能吞掉下一白昼90秒")
	stage_done = true

func empty_deadline() -> void:
	if not await precision_night(): return
	issue_all_waves(); kill_all()
	game.phase_time = .25
	step(.1)
	check(game.phase == "night" and not game.night_clearance_active,"全部已杀但105秒窗口未尽，不能提前天亮")
	game.finish_night()
	check(game.phase == "night","空场也必须等待真实窗口结束")
	step(.16)
	check(game.phase == "draft" and game.day_number == 2 and not game.night_clearance_active,"截止无残敌可在同帧真实黎明")
	await press(KEY_1)
	check(game.phase_time == 90.0,"无残敌黎明同样保留完整白昼")
	stage_done = true

func flight() -> void:
	if not await precision_night(): return
	var source: BattleUnit = residual("lobber",SOURCE_POINT)
	stand(HERO_POINT)
	var controller: Node3D = null
	for raw: Variant in game.lobbers:
		if not is_instance_valid(raw) or not raw is Node3D: continue
		var candidate: Node3D = raw
		if candidate.get("host") == source: controller = candidate
	check(controller != null,"精度投蚀源使用真实生产控制器")
	if controller == null: return
	step(.01)
	check(String(controller.snapshot().phase) == "windup","真实投蚀前摇锁定可达英雄")
	await advance(1.16)
	check(String(controller.snapshot().phase) == "flight","完整真实前摇产生唯一飞弹")
	var controller_id: int = controller.get_instance_id()
	var source_id: int = source.get_instance_id()
	var hits: int = damage.size()
	source.hurt(100000.0,game.hero)
	await frames()
	game.phase_time = .01
	step(.02)
	var state: Dictionary = game.night_clearance_snapshot()
	check(game.phase == "night" and bool(state.active) and int(state.remaining) == 0 and int(state.projectiles) == 1,
		"宿主真实死亡后唯一在途飞弹仍阻止普通黎明")
	guard_reject("唯一在途投蚀飞弹")
	await press(KEY_ESCAPE)
	var paused: Dictionary = controller.snapshot()
	# The real source.hurt above also records enemy damage; freeze comparison
	# uses the actual pause baseline while the impact audit retains all rows.
	var paused_hits: int = damage.size()
	var paused_hp: float = game.hero.hp
	var paused_shield: float = game.hero.shield
	var clock: float = game.night_clearance_elapsed
	step(2.0)
	check(game.phase == "paused" and controller.snapshot() == paused and damage.size() == paused_hits
		and game.hero.hp == paused_hp and game.hero.shield == paused_shield,"真实暂停冻结孤立飞弹和伤害")
	near(game.night_clearance_elapsed,clock,"真实暂停不累计清场elapsed")
	await capture("orphan-flight-paused")
	await press(KEY_ESCAPE)
	step(float(controller.snapshot().stage_remaining)+.001)
	var impacts := 0
	for index in range(hits,damage.size()):
		var row: Dictionary = damage[index]
		if bool(row.hero) and float(row.hp_loss) > 0.0: impacts += 1
	check(impacts == 1 and game.phase == "draft" and game.day_number == 2,"真实最后飞弹落地只伤害一次后才黎明")
	await frames()
	check(not is_instance_id_valid(controller_id) and not is_instance_id_valid(source_id),"黎明释放原投蚀控制器与宿主")
	(evidence.flight as Array).append({"source":source_id,"controller":controller_id,"before_impact":state,"impacts":impacts})
	stage_done = true

func freeze() -> void:
	if not await precision_night(2): return
	var keep: BattleUnit = residual()
	enter_clearance()
	await advance(.5)
	await press(KEY_ESCAPE)
	check(game.phase == "paused","真实Esc暂停普通清场")
	var state := signature()
	step(5.0)
	check(signature() == state,"暂停冻结残敌、前摇、队列、库存、钱包与清场时间")
	guard_reject("暂停清场")
	await capture("ordinary-paused")
	await press(KEY_ESCAPE)
	check(game.phase == "night" and game.night_clearance_active,"真实Esc回原普通清场")
	var parts: int = game.scrap
	var cost: int = game.run.memory_cost()
	await press(KEY_V)
	check(game.phase == "draft" and game.return_phase == "night" and game.scrap == parts-cost,"真实V付费打开清场铭刻")
	state = signature()
	step(5.0)
	check(signature() == state,"付费铭刻同样冻结原清场演员与物流")
	guard_reject("铭刻清场")
	await press(KEY_1)
	check(game.phase == "night" and game.night_clearance_active and game.scrap == parts-cost,"真实选卡返回同一清场且不再扣费")
	var clock: float = game.night_clearance_elapsed
	step(.1)
	near(game.night_clearance_elapsed,clock+.1,"选卡返回后战斗继续推进清场elapsed")
	keep.hurt(100000.0,game.hero)
	step(.01)
	check(game.phase == "draft" and game.day_number == 3,"恢复后真实最后死亡正常黎明")
	stage_done = true

func ledger() -> void:
	if not await precision_night(): return
	await next_precision_night()
	issue_all_waves(); kill_all()
	game.phase_time = .01
	step(.02)
	await press(KEY_1)
	check(game.phase == "day" and game.day_number == 3,"独立押注夹具通过真实清场到下一白昼")
	check(game.select_wave_wager_target(4),"真实白昼选择最后波押注")
	var placement: Dictionary = game.place_wave_wager(0)
	check(bool(placement.get("ok",false)),"真实风险选择被生产押注接受")
	var before_lock: int = game.scrap
	game.phase_time = .01
	step(.02)
	suspend_defense()
	var ticket: Dictionary = game.wave_wager_snapshot()
	check(String(ticket.state) == "locked" and game.scrap == before_lock-int(ticket.stake),"真实日落仅扣一次所选stake")
	issue_all_waves()
	var target_id: int = int(ticket.target_reward_id)
	var keep: BattleUnit = null
	for raw: Variant in game.enemies:
		if not living(raw): continue
		var unit: BattleUnit = raw
		if int(unit.get_meta("wave_reward_id",-1)) == target_id: keep = unit; break
	check(keep != null,"保存所选波原真实演员作为清场残敌")
	if keep == null: return
	kill_all(keep)
	keep.position = Vector3(100,0,-100)
	var balance: int = game.scrap
	enter_clearance()
	check(String(game.wave_wager_snapshot().state) == "locked" and game.scrap == balance,"105秒截止不提前丢失或支付整夜押注")
	var ledger_before: Dictionary = game.wave_rewards.snapshot(target_id)
	keep.hurt(100000.0,game.hero)
	var ledger_after: Dictionary = game.wave_rewards.snapshot(target_id)
	var won: Dictionary = game.wave_wager_snapshot()
	check(bool(ledger_after.cleared) and int(ledger_after.paid) == 24 and String(won.state) == "won","清场真杀完成原24预算与押注")
	check(game.scrap == balance+24-int(ledger_before.paid)+int(won.reward),"真实最后死亡只支付剩余24预算份额和原押注派彩")
	var settled: int = game.scrap
	keep.hurt(100000.0,game.hero)
	check(game.scrap == settled,"重复死亡不能重复派彩")
	step(.02)
	check(game.phase == "draft" and game.scrap == settled,"黎明清理不重复奖励或退款")
	(evidence.ledger as Array).append({"ticket":ticket,"before":ledger_before,"after":ledger_after,"settled":won,"parts":settled})
	# 独立第二夜甲壳悬赏必须在105秒截止，不能把清场加时当延长悬赏。
	if not await precision_night(): return
	issue_all_waves(); kill_all(); game.phase_time = .01; step(.02); await press(KEY_1)
	check(game.select_bounty(),"真实第二夜白昼接受甲壳悬赏")
	game.phase_time = .01; step(.02); suspend_defense(); issue_all_waves()
	keep = null
	for raw: Variant in game.enemies:
		if not living(raw): continue
		var unit: BattleUnit = raw
		if int(unit.get_meta("wave_reward_id",-1)) == 7: keep = unit; break
	check(keep != null,"甲壳目标波保持原真实残敌")
	if keep == null: return
	kill_all(keep); keep.position = Vector3(100,0,-100)
	enter_clearance()
	check(String(game.bounty_snapshot().state) == "expired","甲壳悬赏在105秒严格到期")
	balance = game.scrap
	ledger_before = game.wave_rewards.snapshot(7)
	keep.hurt(100000.0,game.hero)
	check(game.scrap == balance+24-int(ledger_before.paid) and String(game.bounty_snapshot().state) == "expired",
		"清场真杀仅结原波预算，不支付已到期48悬赏")
	stage_done = true

func specialists() -> void:
	if not await precision_night(2): return
	var source: BattleUnit = residual("summoner",Vector3(0,0,Layout.RAMP_END+8.0))
	stand(Vector3(100,0,-100))
	var token: int = source.get_instance_id()
	var controller: Node3D = null
	for raw: Variant in game.summoners:
		if not is_instance_valid(raw) or not raw is Node3D: continue
		var candidate: Node3D = raw
		if candidate.get("host") == source: controller = candidate
	check(controller != null,"真实召援源与生产控制器连接")
	if controller == null: return
	var plan: Array = game.night_plan.duplicate(true)
	enter_clearance()
	check(String(controller.snapshot().phase) == "windup","截止保留已开始的真实2.4秒召援前摇")
	for frame in 190:
		if int(source.get_meta("summoner_spawned",0)) == 2: break
		step()
		if frame % 100 == 99: await process_frame
	check(living(source) and int(source.get_meta("summoner_spawned",0)) == 2 and game.night_clearance_active,
		"105秒后有限召援实际继续，原宿主只产生终生两名增援")
	var summoned: Array[int] = []
	for row: Dictionary in births:
		if bool(row.summoned) and float(row.at) >= 0.0: summoned.append(int(row.token))
	check(summoned.size() == 2,"清场期间记录两个真正出生的应召演员")
	var spawn_state: int = game.spawn_rng.state
	await advance(1.0)
	check(source.get_meta("summoner_spawned",0) == 2 and game.spawn_rng.state == spawn_state and game.night_plan == plan and game.wave_index == 5,
		"终生预算耗尽不再生人，也不重刷计划波次")
	var parts: int = game.scrap
	for raw: Variant in game.enemies.duplicate():
		if not living(raw): continue
		var unit: BattleUnit = raw
		if bool(unit.get_meta("summoned_reinforcement",false)): unit.hurt(100000.0,game.hero)
	check(game.scrap == parts,"应召演员真实死亡沿原规则没有额外零件奖励")
	check(game.night_clearance_snapshot().remaining == 1,"应召死亡后原活源仍阻止黎明")
	(evidence.specialists as Array).append({"kind":"summoner","source":token,"summoned":summoned,"state":controller.snapshot()})
	source.hurt(100000.0,game.hero); step(.02)
	check(game.phase == "draft" and game.day_number == 3,"有限增援与原宿主均真死后普通黎明")
	if not await precision_night(4): return
	issue_all_waves()
	var boss: BattleUnit = null
	for raw: Variant in game.enemies:
		if not living(raw): continue
		var unit: BattleUnit = raw
		if bool(unit.get_meta("siege_boss",false)): boss = unit; break
	check(boss != null,"真实第四夜第五波原首领实际出生")
	if boss == null: return
	kill_all(boss)
	boss.position = Vector3(8,5,0)
	stand(Vector3(10,5,0))
	var old_count: int = game.wave_rewards.snapshot(19).count
	enter_clearance()
	check(game.final_clearance_active and game.boss_snapshot().adds == 0,"末夜截止保留活首领与未使用增援预算")
	# 用原18甲和实际hurt跨越两条原生命阈值，不直接改首领生命。
	boss.hurt(1100.0,game.hero); step(.02)
	check(game.boss_snapshot().adds == 3 and game.wave_rewards.snapshot(19).count == old_count+3,
		"末夜加时原2/3生命阈值实际产生第一批3人并登记同波")
	boss.hurt(1100.0,game.hero); step(.02)
	check(game.boss_snapshot().adds == 6 and game.boss_snapshot().reinforcement_batches == 2
		and game.wave_rewards.snapshot(19).count == old_count+6,"末夜加时原1/3阈值产生第二批3人，终生封顶6")
	(evidence.specialists as Array).append({"kind":"boss","state":game.boss_snapshot(),"ledger":game.wave_rewards.snapshot(19)})
	boss.hurt(100000.0,game.hero); step(.02)
	check(game.phase == "night" and game.final_clearance_active and game.night_clearance_snapshot().remaining == 6,
		"加时首领已死但六名真实增援仍阻止胜利")
	guard_reject("末夜首领死后的真实增援")
	kill_all(); step(.02)
	check(game.phase == "ended" and game.victory,"首领和全部实际增援真死后末夜结算")
	# 独立精度末夜：提前真杀首领时仍处于原105秒窗口，不能冒称已进入清场。
	if not await precision_night(4): return
	issue_all_waves()
	var early_boss: BattleUnit = null
	var early_keep: BattleUnit = null
	for raw: Variant in game.enemies:
		if not living(raw): continue
		var unit: BattleUnit = raw
		if bool(unit.get_meta("siege_boss",false)): early_boss = unit
		elif early_keep == null and String(unit.get_meta("threat","")) == "stalker": early_keep = unit
	check(early_boss != null and early_keep != null,"提前击破夹具保留原计划的真实首领与普通残敌")
	if early_boss == null or early_keep == null: return
	for raw: Variant in game.enemies.duplicate():
		if not living(raw): continue
		var unit: BattleUnit = raw
		if unit != early_boss and unit != early_keep: unit.hurt(100000.0,game.hero)
	early_keep.position = Vector3(100,0,-100)
	early_keep.attack_timer = 100000.0
	var early_boss_token: int = early_boss.get_instance_id()
	check(game.phase_time == 105.0 and not game.night_clearance_active,"提前真杀发生在原105秒窗口内")
	early_boss.hurt(100000.0,game.hero)
	step(.02)
	var early_state: Dictionary = game.night_clearance_snapshot()
	check(game.phase == "night" and game.phase_time > 0.0 and not bool(early_state.active)
		and not game.final_clearance_active and String(game.boss_snapshot().phase) == "dead"
		and int(early_state.remaining) == 1,"首领实际提前致死仍保留正时钟与原残敌，不提前清场或胜利")
	var early_death: Dictionary = {}
	for row: Dictionary in deaths:
		if int(row.token) == early_boss_token: early_death = row
	check(not early_death.is_empty() and float(early_death.get("time",0)) > 0.0
		and not bool(early_death.get("alive",true)) and float(early_death.get("hp",1)) <= 0.0,
		"提前击破来自正计时下真实hurt死亡回调")
	quiet_hud(); camera_at(HOME); await redraw()
	var early_labels: Array[String] = []
	var premature_clearance := false
	for row: Dictionary in game.hud.clearance_labels:
		var text: String = row.text
		early_labels.append(text)
		premature_clearance = premature_clearance or text.contains("清场中") or text.begins_with("清场 +")
	check("末夜首领 · 已击破" in early_labels and "01:45" in early_labels
		and "首领威胁已解除 · 守住剩余波次" in early_labels and not premature_clearance,
		"真实HUD提前击破显示已击破与原正倒计时，尚未显示截止清场字串")
	enter_clearance()
	check(living(early_keep) and game.final_clearance_active and game.night_clearance_snapshot().remaining == 1,
		"实际截止才对同一原残敌进入末夜清场")
	quiet_hud(); await redraw()
	var deadline_labels: Array[String] = []
	var saw_deadline_clock := false
	var saw_deadline_population := false
	for row: Dictionary in game.hud.clearance_labels:
		var text: String = row.text
		deadline_labels.append(text)
		saw_deadline_clock = saw_deadline_clock or text.begins_with("清场 +")
		saw_deadline_population = saw_deadline_population or (text.begins_with("清场中")
			and text.contains("残敌1") and text.contains("飞弹0"))
	check("末夜首领 · 已击破" in deadline_labels and saw_deadline_clock and saw_deadline_population
		and "首领威胁已解除 · 守住剩余波次" not in deadline_labels,
		"真实HUD截止后才显示清场加时及残敌/飞弹，与首领提前击破区别")
	(evidence.specialists as Array).append({"kind":"early-boss-hud","boss_token":early_boss_token,
		"residual_token":early_keep.get_instance_id(),"death":early_death,"early":early_state,
		"early_labels":early_labels,"deadline":game.night_clearance_snapshot(),"deadline_labels":deadline_labels})
	early_keep.hurt(100000.0,game.hero); step(.02)
	check(game.phase == "ended" and game.victory,"提前死首领仍须实际截止且原残敌真死才胜利")
	stage_done = true

func transport() -> void:
	if not await precision_night(): return
	issue_all_waves(); kill_all(); game.phase_time = .01; step(.02); await press(KEY_1)
	game.phase_time = 10000.0
	stand(HOME)
	var payments: Array[Dictionary] = []
	for kind: String in BUILD_POINTS:
		var parts: int = game.scrap
		check(game.build_structure_at(BUILD_POINTS[kind],kind),"隔离精度用生产网格真建设" + kind)
		check(game.scrap == parts-int(Catalog.building(kind).cost),"实际建筑只付目录原价")
		payments.append({"kind":kind,"paid":parts-game.scrap})
	var before: int = game.scrap
	var order: Dictionary = game.squads.enqueue("hauler")
	check(bool(order.get("ok",false)) and game.scrap == before-70,"真实工队订单付款70，非即时招募")
	await advance(8.1)
	check(game.squads.squads.size() == 1,"完整原8秒生产交付工队")
	if game.squads.squads.is_empty(): return
	var carrier: Dictionary = game.squads.squads[0]
	var carrier_ids: Array[int] = [int(carrier.id)]
	check(game.squads.select_ids(carrier_ids) == carrier_ids,"真实选择原工队")
	check(bool(game.logistics.command_selected_field(0).ok),"生产命令指定真实有限废料堆")
	before = game.scrap
	var planned: Dictionary = game.logistics.prepare_selected_night_hauling()
	check(bool(planned.get("ok",false)) and game.scrap == before,"白昼夜采准备不扣费")
	game.start_night(); suspend_defense(); observe()
	check(game.scrap == before-20 and game.logistics.night_haul_snapshot().active == 1,"真实日落只付20夜采装配")
	var keep: BattleUnit = residual()
	keep.attack_timer = 100000.0
	before = game.scrap
	order = game.squads.enqueue("shield")
	check(bool(order.get("ok",false)) and game.scrap == before-70,"清场前真实付费队列保留原生产订单")
	var stock_before: Dictionary = game.logistics.snapshot()
	enter_clearance()
	var spent: int = game.logistics.night_haul_snapshot().spent
	var delivered := false
	for frame in 1000:
		var stock: Dictionary = game.logistics.snapshot()
		check(int(stock.remaining)+int(stock.cargo)+int(stock.delivered)+int(stock.lost) == 480,"清场夜采原480有限库存守恒")
		check(game.logistics.night_haul_snapshot().spent == spent and game.logistics.night_haul_snapshot().active == 1,
			"同一清场继续原付费许可且不重复收费")
		if int(stock.delivered) >= int(stock_before.delivered)+16 and game.squads.squads.size() == 2: delivered = true; break
		step()
		if frame % 100 == 99: await process_frame
	check(delivered,"有界清场真实路径新采并卸货且完成原付费队列")
	check(game.phase == "night" and game.night_clearance_active,"物流到账不能冒充真实最后残敌死亡")
	var stock_final: Dictionary = game.logistics.snapshot()
	check(int(stock_final.remaining) < int(stock_before.remaining) and int(stock_final.delivered) > int(stock_before.delivered),
		"清场证明真新采并真实返站，非远端直接加钱")
	evidence.transport = {"fixture":true,"payments":payments,"carrier":carrier.id,"before":stock_before,
		"after":stock_final,"permit":game.logistics.night_haul_snapshot(),"clearance":game.night_clearance_snapshot(),
		"scope":"5000-part compressed-deadline precision fixture; real production prices/training/routes/finite stock; not natural profitability"}
	await capture("paid-night-haul-clearance")
	keep.hurt(100000.0,game.hero); step(.02)
	check(game.phase == "draft" and game.logistics.night_haul_snapshot().active == 0 and game.logistics.night_haul_snapshot().retired,
		"真实黎明才注销夜采，付费账本不返还")
	await press(KEY_1)
	check(game.phase_time == 90.0 and game.logistics.night_haul_snapshot().spent == spent,"真实白昼不继承清场时间或重扣装配")
	stage_done = true

func lifecycle() -> void:
	if not await precision_night(): return
	residual(); enter_clearance(); await advance(.2)
	game.hero.hurt(100000.0,null)
	check(game.phase == "ended" and not game.victory and not game.night_clearance_active and game.night_clearance_elapsed == 0.0,
		"真实致命伤失败立即清理清场状态")
	guard_reject("失败后禁止改成胜利或黎明")
	var old_id: int = game.get_instance_id()
	await press(KEY_ENTER)
	for frame in 150:
		if is_instance_valid(current_scene) and current_scene.get_instance_id() != old_id: break
		await create_timer(.01,true,false,true).timeout
	check(is_instance_valid(current_scene) and current_scene.get_instance_id() != old_id,"真实Enter重试替换整个旧局")
	if not is_instance_valid(current_scene) or current_scene.get_instance_id() == old_id: return
	game = current_scene as Node3D
	game.set_process(false); game.world.set_process(false)
	check(not is_instance_id_valid(old_id) and game.run.seed_value == SEED and game.scrap == 90 and game.phase == "draft",
		"真实重试保留原种子与90开局且释放旧场景")
	check(not game.night_clearance_active and not game.final_clearance_active and game.night_clearance_elapsed == 0.0,
		"新局不继承普通/末夜清场或加时")
	if not await precision_night(4): return
	var keep: BattleUnit = residual()
	enter_clearance()
	check(game.night_clearance_active and game.final_clearance_active,"第四夜末夜是同一清场的final子态")
	guard_reject("末夜活残敌同样阻止胜利")
	keep.hurt(100000.0,game.hero); step(.02)
	check(game.phase == "ended" and game.victory and not game.night_clearance_active,"末夜真实最后死亡后胜利并清理清场")
	guard_reject("胜利后重复结算")
	stage_done = true

func redraw() -> void:
	game.hud.queue_redraw()
	await frames()

func quiet_hud() -> void:
	game.notice_time = 0.0
	game.reward_toasts.clear()
	game.beacon_alarm_time = 0.0
	game.hero_damage_flash_time = 0.0
	game.combat.clear_transients()
	game.squads.cancel_selection()

func capture(tag: String) -> void:
	if not render_test: return
	check(DisplayServer.get_name() != "headless","实际截图须由真实图形backend产生")
	if DisplayServer.get_name() == "headless": return
	check(valid_output(output_dir),"写截图前复查固定物理证据目录")
	if not valid_output(output_dir): return
	check(DirAccess.make_dir_recursive_absolute(output_dir) == OK,"实际证据目录可创建")
	var before := signature()
	for viewport: Vector2i in VIEWPORTS:
		root.size = viewport; root.content_scale_size = viewport
		await redraw()
		for _frame in 2: await RenderingServer.frame_post_draw
		var picture: Image = root.get_texture().get_image()
		check(picture.get_size() == viewport and Vector2(picture.get_size()) == game.hud.get_viewport_rect().size,
			"真实内容像素匹配三视口，区别Mac窗口外壳")
		var name := "%s-%dx%d.png" % [tag,viewport.x,viewport.y]
		var path := output_dir.path_join(name)
		check(picture.save_png(path) == OK,"保存实际清场截图")
		(evidence.captures as Array).append({"name":name,"stage":stage,"sha256":FileAccess.get_sha256(path)})
	root.size = VIEWPORTS[0]; root.content_scale_size = VIEWPORTS[0]
	await redraw()
	check(signature() == before,"三视口截图不能推进战斗、时钟、付款与库存")

func hud() -> void:
	if not await precision_night(2): return
	residual(); enter_clearance(); await advance(1.2)
	quiet_hud(); camera_at(HOME)
	await redraw()
	var default_areas: Array = game.hud.live_panel_rects().duplicate()
	var before := signature()
	for viewport: Vector2i in VIEWPORTS:
		root.size = viewport; root.content_scale_size = viewport
		await redraw()
		var saw_time := false
		var saw_population := false
		for row: Dictionary in game.hud.clearance_labels:
			var point: Vector2 = row.point
			check(point.x >= 0 and point.y-float(row.ascent) >= 0 and point.x+float(row.width) <= 1440 and point.y+float(row.descent) <= 900,
				"清场中文实际字形完整落在1440×900逻辑视口：" + String(row.text))
			for character: String in String(row.text):
				var code: int = character.unicode_at(0)
				if code >= 0x4e00 and code <= 0x9fff: check(game.hud.font.has_char(code),"清场实际中文字体包含" + character)
			if String(row.text).begins_with("清场 +"): saw_time = true
			if String(row.text).contains("残敌1") and String(row.text).contains("飞弹0"): saw_population = true
		check(saw_time and saw_population,"三视口阶段栏实际显示清场加时与真实敌/弹数量")
		var area := 0.0
		for rect: Rect2 in game.hud.live_panel_rects(): area += rect.get_area()
		check(area/(1440.0*900.0) <= .17,"清场不重新加入大面积常驻面板")
		await press(KEY_F3)
		await click_ui(game.hud.details_tab_rect(3))
		check(game.hud.detail_tab == "defense","实际F3防线详情仍按需展开")
		await press(KEY_F3)
		quiet_hud(); await redraw()
		check(game.hud.detail_tab.is_empty() and game.hud.live_panel_rects() == default_areas,"收起详情完整恢复默认清场面积")
	check(signature() == before,"界面三视口导航不改变真实清场/残敌/钱包")
	root.size = VIEWPORTS[0]; root.content_scale_size = VIEWPORTS[0]
	await capture("default-ordinary-clearance")
	stage_done = true

func natural_policy() -> void:
	# 与既有自然物流相同的原技能策略；不改属性/出生/钱/时钟。
	game.aim = game.hero.position + Vector3(0,0,8)
	if game.gate_pressure() > 0: game.cast(0)
	if game.hero.hp < game.hero.max_hp*.6: game.cast(1); game.cast(4)
	if game.gate_pressure() >= 6: game.cast(3)
	step()

func natural_route(seed_value: int) -> Dictionary:
	if not await fresh(false,seed_value): return {}
	camera_at(Vector3(0,5,10))
	await mouse(game.camera.unproject_position(Vector3(0,5,10)))
	var start: Dictionary = {"parts":game.scrap,"hero_hp":game.hero.hp,"hero_max_hp":game.hero.max_hp,
		"hero_damage":game.hero.damage,"hero_speed":game.hero.speed,"beacon":game.beacon_hp,"time":game.phase_time,
		"sources":game.logistics.snapshot()}
	var cutoff: Dictionary = {}
	var cutoff_tokens: Array[int] = []
	var completed_naturally := false
	for frame in 2400:
		if game.phase != "night": break
		natural_policy()
		var direct_dawn: bool = game.phase == "draft" and game.day_number == 2 and elapsed >= 105.0-.0001
		if cutoff.is_empty() and (game.phase_time <= 0.0 or direct_dawn):
			var cutoff_state: Dictionary = game.night_clearance_snapshot()
			if game.phase in ["night","ended"]:
				for raw: Variant in game.enemies:
					if not living(raw): continue
					var unit: BattleUnit = raw
					cutoff_tokens.append(unit.get_instance_id())
			elif direct_dawn:
				# finish_night已把时钟改90并生成白昼守卫；它们不属于刚结束的夜。
				cutoff_state = {"active":false,"final":false,"remaining":0,"projectiles":0,"elapsed":0.0}
			cutoff = {"reached":true,"direct_dawn":direct_dawn,"at":elapsed,"tokens":cutoff_tokens.duplicate(),"phase":String(game.phase),
				"parts":int(game.scrap),"hero_hp":game.hero.hp,"beacon":float(game.beacon_hp),
				"state":cutoff_state}
		if game.phase == "night" and game.night_clearance_active:
			check(game.phase_time == 0.0 and game.wave_index == 5,"自然加时保持零时钟与原五波，不改时间延长计划")
		if frame % 100 == 99: await process_frame
	if cutoff.is_empty(): cutoff = {"reached":false,"terminated_at":elapsed,"phase":String(game.phase),"parts":int(game.scrap)}
	if game.phase == "draft" and game.day_number == 2: completed_naturally = true
	check(completed_naturally or game.phase == "ended","自然策略有界240秒内真实黎明或真实失败，禁止超时删怪")
	if seed_value == SEED: check(completed_naturally,"原20261006种子原技能策略必须通过真实首夜清场")
	var dead_tokens: Dictionary = {}
	for row: Dictionary in deaths:
		check(not dead_tokens.has(int(row.token)),"自然演员真实死亡只记录一次")
		dead_tokens[int(row.token)] = true
		check(not bool(row.alive) and float(row.hp) <= 0.0,"自然清场账本来自实际致死回调")
	if completed_naturally:
		for token: int in cutoff_tokens: check(dead_tokens.has(token),"105秒自然残敌必须有同实例真实死亡回执")
		check(births.size() == deaths.size(),"真实黎明前全部原夜晚出生演员均已真杀，不能依赖阶段清理删怪")
	var result: Dictionary = {"seed":seed_value,"mode":"siege","start":start,"spawn_window_seconds":105,"day_seconds":90,
		"cutoff":cutoff,"actual_dawn_or_defeat_seconds":elapsed,"clearance_seconds":maxf(0.0,elapsed-105.0),
		"births":births.duplicate(true),"deaths":deaths.duplicate(true),"damage":damage.duplicate(true),
		"wallet_changes":wallets.duplicate(true),"final_parts":int(game.scrap),"hero_hp":game.hero.hp,"beacon":float(game.beacon_hp),
		"phase":String(game.phase),"completed":completed_naturally,
		"scope":"bounded fixed-seed genuine skill/path policy; original90 wallet/105 spawning window/90 next day/native actors and stats; no enemy deletion/lethal fixture/clock or stat edits/funding; wallet includes real ordinary and chain income; not human balance"}
	var terminal_cutoff: Dictionary = cutoff.get("state",{})
	result["natural_extra_combat_proven"] = completed_naturally and (int(terminal_cutoff.get("remaining",0)) > 0 or int(terminal_cutoff.get("projectiles",0)) > 0)
	if not bool(result.natural_extra_combat_proven):
		result["extra_combat_scope"] = "This natural route does not prove combat after the deadline; isolated precision stages prove residual attacks and committed projectiles."
	if completed_naturally:
		var parts: int = game.scrap
		await press(KEY_1)
		check(game.phase == "day" and game.phase_time == 90.0 and game.scrap == parts,"自然真实清场后原完整白昼与赚得钱包")
		result.day_entry = {"parts":game.scrap,"time":game.phase_time,"clearance":game.night_clearance_snapshot()}
	camera_at(HOME)
	await capture("natural-seed-%d" % seed_value)
	print("NIGHT_CLEARANCE_NATURAL ",JSON.stringify(result))
	return result

func natural() -> void:
	var proven := false
	for seed_value in [SEED,20261007]:
		var result: Dictionary = await natural_route(seed_value)
		check(not result.is_empty(),"独立原种子自然路线保留真实结果")
		(evidence.natural as Array).append(result)
		proven = proven or bool(result.get("natural_extra_combat_proven",false))
	evidence["natural_extra_combat_proven"] = proven
	if not proven:
		evidence["natural_extra_combat_scope"] = "Neither original-clock natural route proves surviving threats at the deadline; precision residual, projectile and reinforcement stages provide the separate extra-combat proof."
	stage_done = true

func finish(code: int = 0) -> void:
	if finished: return
	finished = true
	await close_game()
	for suffix in ["",".tmp",".bak"]:
		var path: String = profile_path+String(suffix)
		if FileAccess.file_exists(path): check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK,"仅清私有专项档案")
	if valid_output(output_dir):
		check(DirAccess.make_dir_recursive_absolute(output_dir) == OK,"结果目录可创建")
		var file := FileAccess.open(output_dir.path_join("result.json"),FileAccess.WRITE)
		check(file != null,"结构化清场回执可写入固定物理目录")
		if file != null:
			evidence["checks"] = checks; evidence["failures"] = failures; evidence["completed"] = completed
			evidence["segment"] = segment; evidence["render"] = render_test
			file.store_string(JSON.stringify(evidence,"\t")); file.close()
	else: check(false,"结果路径复核失败，拒绝写入")
	var passed := failures.is_empty() and code == 0
	if passed and segment.is_empty(): print("NIGHTFALL_NIGHT_CLEARANCE_OK checks=%d failures=0" % checks)
	elif passed: print("NIGHTFALL_NIGHT_CLEARANCE_SEGMENT_OK segment=%s checks=%d" % [segment,checks])
	else: print("NIGHTFALL_NIGHT_CLEARANCE_FAILED stage=%s checks=%d failures=%d" % [stage,checks,failures.size()])
	quit(0 if passed else 1)

func watchdog() -> void:
	if finished: return
	check(false,"300秒墙钟看门狗退出，挂起不得当通过")
	await finish(1)

func run() -> void:
	var cases := {"guards":guards,"ordinary":ordinary,"empty":empty_deadline,"flight":flight,"freeze":freeze,
		"ledger":ledger,"specialists":specialists,"transport":transport,"lifecycle":lifecycle,"hud":hud,"natural":natural}
	if not segment.is_empty() and not cases.has(segment):
		check(false,"未知清场专项段")
		await finish(1)
		return
	for name: String in cases:
		if not segment.is_empty() and name != segment: continue
		if not failures.is_empty(): break
		stage = name; stage_done = false
		print("NIGHT_CLEARANCE_STAGE_BEGIN ",name)
		await (cases[name] as Callable).call()
		check(stage_done,"本段完成全部实际断言")
		if stage_done: completed.append(name)
		print("NIGHT_CLEARANCE_STAGE_END ",name," checks=",checks," failures=",failures.size())
	check(completed.size() == (cases.size() if segment.is_empty() else 1),"完整十一段才发整套成功，单段单独成功token")
	await finish()
