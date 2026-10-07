extends SceneTree
## 投网队真实生产专项。精度段显式使用5000零件、延长阶段、演员站位，
## 不把模块数值当作炮击收益；固定落点成对案例实际移动疾行体并核对实伤。
## 最后一段保留自然105秒首夜/90秒白昼、原钱包/演员/属性，不保证脚本整局胜利。
const Catalog := preload("res://scripts/outpost_catalog.gd")
const RunSession := preload("res://scripts/run_session.gd")
const RunArchive := preload("res://scripts/run_archive.gd")
const BossScript := preload("res://scripts/nightfall_siege_boss.gd")
const SCENE := "res://scenes/nightfall.tscn"
const SEED := 20261007
const STEP := .05
const VIEWPORTS := [Vector2i(1920, 1200), Vector2i(1920, 1080), Vector2i(1440, 900)]
const CANDIDATES := [Vector3(-9, 5, -9), Vector3(-9, 5, -3), Vector3(9, 5, -9),
	Vector3(9, 5, 4), Vector3(-9, 5, 9), Vector3(9, 5, 10), Vector3(-3, 5, -9)]
const OPEN := Vector3(20, 0, 30)
const HUD_OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var netter_labels: Array[Dictionary] = []
func _draw() -> void:
	netter_labels.clear()
	super._draw()
func label(value: String, point: Vector2, size_px: int, color: Color = Color(\"e7e1d3\"), latin: bool = false) -> void:
	var selected_font: Font = display_font if latin else font
	netter_labels.append({\"text\": value, \"point\": point, \"size\": size_px,
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
var capture_tag := "headless"
var profile_path := "user://riftward-netter-test-%d.json" % Time.get_ticks_usec()
var evidence: Dictionary = {"seed": SEED, "fixture_parts": 5000, "captures": [],
	"artillery": [], "natural": {}, "scope": "source/Mac only; Windows delivery remains separate"}

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
	# Also covers true reload_current_scene before the root's _ready can write.
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
	if failures.size() <= 30: push_error(stage + ": " + message)

func near(actual: float, expected: float, message: String, tolerance: float = .001) -> void:
	check(is_finite(actual) and absf(actual - expected) < tolerance,
		message + " [actual=%.6f expected=%.6f]" % [actual, expected])

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

func click(rect: Rect2) -> void:
	var point: Vector2 = rect.get_center() * game.hud.get_viewport_rect().size / Vector2(1440, 900)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	event.button_mask = 0
	root.push_input(event, true)
	await process_frame

func close_game() -> void:
	if not is_instance_valid(game): return
	await game.prepare_shutdown()
	if current_scene == game: current_scene = null
	game.queue_free()
	game = null
	await frames(4)

func cleanup_profile() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path: String = profile_path + suffix
		if FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK,
				"临时档案及备份须清理，不影响玩家档案")

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

func stand_hero(point: Vector3) -> void:
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.hero.moving = false
	game.hero.set_locomotion_velocity(Vector3.ZERO)
	game.move_goal = point
	game.hero_path.clear()
	game.hero_keyboard_active = false
	game.aim = point

func isolate() -> void:
	game.phase = "night"
	game.phase_time = 1000.0
	game.wave_index = game.WAVES_PER_NIGHT
	game.pulse_timer = 9999.0
	game.hero.attack_timer = 9999.0
	game.gate_trap_charges = 0
	for pad: Dictionary in game.world.tower_pads: pad.cooldown = 9999.0

func fresh(precision: bool = true) -> bool:
	await close_game()
	check(RunSession.queue_request(self, SEED, "siege"), "固定种子应由真实会话入口消费")
	game = load(SCENE).instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	await frames(4)
	game.set_process(false)
	game.world.set_process(false)
	check(game.phase == "draft" and game.archive.path == profile_path,
		"真实开局选卡及_ready前临时档案隔离应生效")
	check(game.squads.squads.is_empty() and game.squads.training_queues.is_empty(),
		"新局没有上局部队、训练或投网注册")
	await press(KEY_1)
	check(game.phase == "night" and game.run.seed_value == SEED, "真实1键选卡应启动第一夜")
	if precision:
		await clear_enemies()
		isolate()
		game.scrap = 5000
		stand_hero(Vector3(-11, 5, 10))
	return is_instance_valid(game.squads.get("netters"))

func build(kind: String) -> int:
	for raw: Vector3 in CANDIDATES:
		var point := raw
		point.y = game.outpost_height(point)
		var placement: Dictionary = game.construction.validity(point, -1, kind)
		if not bool(placement.get("valid", false)): continue
		var before: int = game.scrap
		if not game.build_structure_at(placement.point, kind): continue
		near(float(before - game.scrap), float(Catalog.building(kind).cost), kind + "真实建设只扣一次目录费用")
		for index in game.districts.plots.size():
			var plot: Dictionary = game.districts.plots[index]
			if String(plot.kind) == kind and int(plot.level) > 0 and not bool(plot.removed) \
				and (plot.position as Vector3).distance_to(placement.point) < .01: return index
	check(false, "当前地图应有可付费的%s合法格子" % kind)
	return -1

func technology(armory: bool = false) -> Dictionary:
	var buildings := {}
	for kind: String in ["workshop", "barracks", "laboratory"]:
		buildings[kind] = build(kind)
	if armory: buildings.armory = build("armory")
	return buildings

func troop_count(kind: String) -> int:
	var result := 0
	for squad: Dictionary in game.squads.squads:
		if String(squad.kind) == kind: result += 1
	return result

func train(kind: String = "netter") -> Dictionary:
	var old_size: int = game.squads.squads.size()
	var before: int = game.scrap
	var definition := Catalog.troop(kind)
	check(game.train_troop(kind), "真实控制器必须接受付费 " + kind + " 队列")
	near(float(before - game.scrap), float(definition.cost), "训练一次只扣目录零件 " + kind)
	game.squads.advance(float(definition.time) - .01)
	check(game.squads.squads.size() == old_size, "完整训练时长之前不得提前交付 " + kind)
	game.squads.advance(.011)
	check(game.squads.squads.size() == old_size + 1, "足够真实训练秒数后只交付一队 " + kind)
	if game.squads.squads.size() != old_size + 1: return {}
	var squad: Dictionary = game.squads.squads[old_size]
	check(String(squad.kind) == kind and squad.members.size() == 3, "训练结果必须是目录兵种的三名真实成员")
	for member: BattleUnit in squad.members:
		check(is_instance_valid(member) and member.alive and member.team == 0,
			"生产成员应实际存活并隶属于玩家")
		member.attack_timer = 9999.0
	return squad

func ready_squad(armory: bool = false) -> Dictionary:
	if not await fresh():
		check(false, "投网生产模块应接入真实squads")
		return {}
	technology(armory)
	return train()

func enemy(role: String, point: Vector3) -> BattleUnit:
	var target: BattleUnit = game.spawn_creature(true, role)
	point.y = game.outpost_height(point)
	target.position = point
	target.attack_timer = 9999.0
	return target

func place_source(squad: Dictionary, point: Vector3 = OPEN) -> BattleUnit:
	game.squads._set_squad_order(squad, "guard")
	squad.destination = point
	squad.rally_stations = [point, point + Vector3(0, 0, 2), point + Vector3(0, 0, 4)]
	for slot in 3:
		var member: BattleUnit = squad.members[slot]
		if not is_instance_valid(member) or not member.alive: continue
		member.position = squad.rally_stations[slot]
		member.position.y = game.outpost_height(member.position)
		member.moving = false
		member.path.clear()
		member.attack_timer = 0.0 if slot == 0 else 9999.0
	return squad.members[0] as BattleUnit

func attack_order(squad: Dictionary, target: BattleUnit) -> void:
	var ids: Array[int] = [int(squad.id)]
	check(game.squads.select_ids(ids) == ids, "公开选队入口须选中真实生产小队")
	var result: Dictionary = game.squads.command_attack(target)
	check(bool(result.ok) and String(squad.order) == "attack"
		and squad.attack_target is WeakRef and squad.attack_target.get_ref() == target,
		"公开指定攻击入口须保存原真实敌人身份")

func advance_roster(seconds: float, controls: bool = false) -> void:
	var remaining := seconds
	while remaining > .000001:
		var delta := minf(STEP, remaining)
		if controls: game.specializations.advance(delta, game.phase in ["day", "night"])
		game.squads.advance(delta)
		remaining -= delta

func throw_at(squad: Dictionary, target: BattleUnit) -> BattleUnit:
	var source: BattleUnit = squad.members[0]
	source.attack_timer = 0.0
	attack_order(squad, target)
	game.squads.advance(.001)
	check(game.squads.netters.casting(source) and source.attack_queued,
		"真实部队攻击命令必须先启动投网前摇")
	advance_roster(.601)
	return source

func production() -> void:
	if not await fresh():
		check(false, "生产尚未接入投网模块")
		return
	var definition := Catalog.troop("netter")
	check(Catalog.TROOP_IDS.size() == 10 and Catalog.TROOP_IDS[9] == "netter", "投网队是第十兵种并保留原九兵种顺序")
	check(String(definition.title) == "投网队" and int(definition.cost) == 100
		and definition.requires == ["laboratory"], "投网队100零件且唯一直接前置为活研究所")
	near(float(definition.time), 9.0, "目录训练九秒")
	near(float(definition.hp), 100.0, "目录基础生命100")
	var before: int = game.scrap
	var eligibility: Dictionary = game.squads.training_eligibility("netter")
	check(not eligibility.available and String(eligibility.reason).contains("研究所"), "缺研究所必须明示科技锁")
	check(not game.train_troop("netter") and game.scrap == before
		and game.squads.training_queues.is_empty(), "科技拒绝不扣钱、不留订单")
	var buildings := technology()
	check(game.squads.training_eligibility("netter").available, "真实工坊/兵营/研究所建设后解锁")
	game.scrap = 99
	check(not game.train_troop("netter") and game.scrap == 99
		and game.squads.training_queues.is_empty(), "99零件不能先付款或留队列")
	game.scrap = before - 240
	var squad := train()
	if squad.is_empty(): return
	for member: BattleUnit in squad.members:
		near(member.max_hp, 100.0 * game.districts.squad_health_multiplier(),
			"真实成员100基础HP乘原存活兵营生命加成")
		near(member.damage, 10.0, "真实成员10基础伤害")
		near(member.armor, 0.0, "真实成员没有额外护甲")
		near(member.speed, 3.6, "真实成员3.6移动速度")
		near(member.attack_interval, 4.0, "真实成员4秒攻击冷却")
		near(member.windup_duration, .6, "真实成员0.6秒前摇")
		check(member.visual.find_child("NetterLauncher", true, false) != null
			and member.visual.find_child("NetterCoil", true, false) != null,
			"三成员均使用实际投网器具轮廓")
	check(int(game.squads.netter_snapshot().alive) == 3, "真实投网注册数量与三名存活成员一致")
	game.phase = "day"
	var first: BattleUnit = squad.members[0]
	var old_token := first.get_instance_id()
	first.hurt(first.max_hp + 999.0, game.hero)
	check(not first.alive and int(game.squads.netter_snapshot().alive) == 2, "死亡当帧注销原投网成员")
	near(float(game.squads.refill_cost(int(squad.id))), 28.0, "缺一员真实补员报价28")
	before = game.scrap
	check(bool(game.squads.refill(int(squad.id)).ok), "白昼真实补员入口应恢复原队")
	check(game.scrap == before - 28 and squad.members[0].get_instance_id() != old_token
		and int(game.squads.netter_snapshot().alive) == 3, "补员扣28且使用新的真实成员身份")
	near(float(game.squads.refill_cost(int(squad.id))), 0.0, "补员完成不再重复报价")
	var laboratory: Dictionary = game.districts.plots[int(buildings.laboratory)]
	game.districts.damage(int(buildings.laboratory), float(laboratory.hp) + 999.0)
	before = game.scrap
	check(not game.train_troop("netter") and game.scrap == before, "研究所真实损毁后禁止新队且不扣费")
	check(int(game.squads.netter_snapshot().alive) == 3, "损毁前置不撤销已交付三名部队")

func combat_and_geometry() -> void:
	var squad := await ready_squad()
	if squad.is_empty(): return
	var source := place_source(squad)
	var target := enemy("basic", OPEN + Vector3(5, 0, 0))
	check(game.squads.netters.real_source(source) and game.squads.netters.real_enemy(target), "实际roster与敌人列表身份必须认可")
	check(game.squads.netters.legal_target(source, target), "同地面五米真目标可以投网")
	var hp := target.hp
	attack_order(squad, target)
	game.squads.advance(.001)
	check(game.squads.netters.casting(source), "实际指定攻击触发投网前摇")
	near(target.hp, hp, "开始前摇不得提前伤害")
	advance_roster(.589)
	near(target.hp, hp, "完整0.6秒前不得命中")
	advance_roster(.012)
	near(hp - target.hp, 10.0 * 100.0 / (100.0 + target.armor), "完成前摇走BattleUnit真实护甲伤害")
	near(float(game.specializations.net_remaining(target)), 2.0, "实际命中附加独立两秒网")
	near(float(game.specializations.movement_multiplier(target)), .55, "普通怪真实速度倍率55%")
	near(source.attack_timer, 4.0, "命中帧留下完整四秒冷却")
	check(not game.squads.netters.casting(source) and not source.attack_queued,
		"一次命中提交后原前摇不再留队")
	var after_hp := target.hp
	advance_roster(.3)
	near(target.hp, after_hp, "冷却内不重复伤害或重复投网")
	check(int(game.squads.netter_snapshot().throws) == 1 and int(game.squads.netter_snapshot().hits) == 1
		and int(game.squads.netter_snapshot().nets) == 1, "真实投掷/实伤/成功控制各记一次")
	game.squads.netters.cancel(source, "fixture_geometry")
	for separation in [2.499, 2.5, 9.0, 9.001]:
		target.position = OPEN + Vector3(float(separation), 0, 0)
		var legal: bool = game.squads.netters.legal_target(source, target)
		check(legal == (float(separation) >= 2.5 and float(separation) <= 9.0),
			"2.5–9米含边界的真实投网射程 %.3f" % separation)
	source.position = Vector3(11.5, 5, 8)
	target.position = Vector3(15, game.outpost_height(Vector3(15, 0, 8)), 8)
	check(not game.can_attack_line(source.position, target.position), "实际城墙是几何阻挡见证")
	check(not game.squads.netters.legal_target(source, target), "墙另一侧不能投网")
	source.position = OPEN
	target.position = OPEN + Vector3(4, .901, 0)
	check(not game.squads.netters.legal_target(source, target), "离地高度超限不得投网")
	target.position = Vector3.INF
	check(not game.squads.netters.legal_target(source, target), "非有限目标不得进入前摇")
	target.position = OPEN + Vector3(4, 0, 0)
	game.enemies.erase(target)
	check(not game.squads.netters.legal_target(source, target), "移出真实敌人账本的同对象不得控制")
	game.enemies.append(target)
	check(not game.squads.netters.legal_target(source, game.hero), "实际玩家英雄不能当敌人投网")
	await targeting_priority()

func targeting_priority() -> void:
	# Precision-only formations and target positions let all three real paid
	# members decide in the same production frame; no direct begin() calls.
	for mode: String in ["automatic", "explicit", "focus"]:
		var squad := await ready_squad()
		if squad.is_empty(): return
		var anchor := OPEN if mode != "focus" else Vector3(-7, 5, 5)
		place_source(squad, anchor)
		var targets: Array[BattleUnit] = []
		for slot in 3:
			var point := anchor + Vector3(5 if mode != "focus" else 4, 0, slot * 2)
			targets.append(enemy("basic", point))
		for member: BattleUnit in squad.members:
			member.attack_timer = 0.0
			for victim: BattleUnit in targets:
				check(game.squads.netters.legal_target(member, victim),
					mode + "三成员前摇预约夹具必须全员全目标真实合法")
		var ids: Array[int] = [int(squad.id)]
		check(game.squads.select_ids(ids) == ids, mode + "公开选队保持真实小队")
		if mode == "explicit":
			check(bool(game.squads.command_attack(targets[2]).ok), "显式攻击使用公开真目标命令")
		else:
			check(bool(game.squads.command_attack_move(anchor + Vector3(8, 0, 0)).ok),
				mode + "公开推进命令进入真实迎击")
		if mode == "focus":
			stand_hero(Vector3(-11, 5, 10))
			game.aim = targets[2].position
			await press(KEY_C)
			check(game.focus_target == targets[2] and game.focus_time > 0.0,
				"真实C输入须经过原英雄/活塔射程建立远端集火")
		game.squads.advance(.001)
		var snapshot: Dictionary = game.squads.netter_snapshot()
		check(int(snapshot.casting) == 3, mode + "同一真实生产帧应启动三成员完整前摇")
		var committed: Array[int] = []
		for row: Dictionary in snapshot.units:
			check(String(row.phase) == "windup" and is_equal_approx(float(row.remaining), .6),
				mode + "目标选择不能绕过真实0.6秒前摇")
			if int(row.target_token) not in committed: committed.append(int(row.target_token))
		check(committed.size() == (3 if mode == "automatic" else 1),
			"自动三敌须按正在前摇预约分散；显式与C允许三员同敌 " + mode)
		if mode != "automatic":
			check(committed == [targets[2].get_instance_id()], mode + "真实指定目标优先于较近未控制敌")
		advance_roster(.601)
		check(int(game.squads.netter_snapshot().hits) == 3,
			mode + "三名真实成员各提交一次实际伤害")
		for victim: BattleUnit in targets:
			check((game.specializations.net_remaining(victim) > 0.0)
				== (mode == "automatic" or victim == targets[2]),
				mode + "实际落网集合须与原前摇预约一致")
		evidence["targeting_" + mode] = {"committed_target_count": committed.size(),
			"real_hits": int(game.squads.netter_snapshot().hits), "scope": "precision formation; public commands and actual C input"}

func cancellations() -> void:
	var squad := await ready_squad()
	if squad.is_empty(): return
	for reason: String in ["move", "amove", "source_moved", "target_range", "target_dead", "wall"]:
		await clear_enemies()
		var source := place_source(squad)
		var target := enemy("basic", OPEN + Vector3(5, 0, 0))
		var hp := target.hp
		attack_order(squad, target)
		game.squads.advance(.001)
		check(game.squads.netters.casting(source), reason + "反例必须先存在真实前摇")
		advance_roster(.2)
		match reason:
			"move": check(bool(game.squads.command_move(OPEN + Vector3(12, 0, 0)).ok), "公开移动改令应接受真实已选队")
			"amove": check(bool(game.squads.command_attack_move(OPEN + Vector3(12, 0, 0)).ok), "公开推进改令应接受真实已选队")
			"source_moved": source.position += Vector3(.2, 0, 0)
			"target_range": target.position += Vector3(10, 0, 0)
			"target_dead": target.hurt(target.max_hp + 999.0, game.hero)
			"wall":
				source.position = Vector3(11.5, 5, 8)
				target.position = Vector3(15, game.outpost_height(Vector3(15, 0, 8)), 8)
		# Tick only the actual source+module here, so cancellation cannot quietly
		# reacquire a different target through a subsequent squad frame.
		source.tick(.401)
		game.squads.netters.advance_unit(source, .401)
		check(not game.squads.netters.casting(source) and not source.attack_queued,
			reason + "取消不得保留未命中的原前摇")
		near(source.attack_timer, 0.0, reason + "失败前摇不虚构冷却")
		near(float(game.specializations.net_remaining(target)), 0.0, reason + "取消不留控制")
		if target.alive: near(target.hp, hp, reason + "取消不得提交伤害")
	await clear_enemies()
	var source := place_source(squad)
	var target := enemy("basic", OPEN + Vector3(5, 0, 0))
	attack_order(squad, target)
	game.squads.advance(.001)
	source.hurt(source.max_hp + 999.0, target)
	check(not source.alive and not game.squads.netters.casting(source), "源真实死亡当帧取消未命中前摇")
	near(float(game.specializations.net_remaining(target)), 0.0, "死亡未发网不影响目标")
	check(int(game.squads.netter_snapshot().alive) == 2, "死亡不留模块孤儿")
	game.phase = "day"
	check(bool(game.squads.refill(int(squad.id)).ok), "反伤测试使用实际付费补员")
	game.phase = "night"
	source = place_source(squad)
	target.damage_confirmed.connect(func(victim: BattleUnit, attacker: BattleUnit, _hp: float, _shield: float) -> void:
		if is_instance_valid(attacker) and attacker.alive: attacker.hurt(attacker.max_hp + 999.0, victim), CONNECT_ONE_SHOT)
	var before := target.hp
	throw_at(squad, target)
	near(before - target.hp, 10.0, "同步反伤夹具仍先完成真实一次目标伤害")
	check(not source.alive and not game.squads.netters.casting(source), "真实伤害确认回调杀源不继续旧代前摇")
	near(float(game.specializations.net_remaining(target)), 0.0, "hurt回调杀源时不得随后新挂网")
	await synchronous_invalidations()

func invalidate_during_hurt(victim: BattleUnit, attacker: BattleUnit, _hp: float, _shield: float,
		reason: String, squad: Dictionary, original_source: BattleUnit) -> void:
	check(attacker == original_source and victim.alive, reason + "受控反例必须由真实源对仍活目标的hurt确认触发")
	victim.set_meta("netter_sync_fixture", reason)
	match reason:
		"order": check(bool(game.squads.command_move(OPEN + Vector3(12, 0, 0)).ok), "hurt同步公开改令须接受实际已选队")
		"slot": squad.members[0] = squad.members[1]
		"dictionary": game.squads.squads[int(squad.id)] = squad.duplicate()
		"epoch": game.squads.netters.clear()

func synchronous_invalidations() -> void:
	# Controlled re-entrancy counterexamples deliberately mutate a real roster
	# slot/Dictionary or clear the module during damage_confirmed. These are
	# lifecycle identity proofs, not naturally reachable UI actions or balance.
	for reason: String in ["order", "slot", "dictionary", "epoch"]:
		var squad := await ready_squad()
		if squad.is_empty(): return
		var source := place_source(squad)
		var victim := enemy("basic", OPEN + Vector3(5, 0, 0))
		victim.damage_confirmed.connect(invalidate_during_hurt.bind(reason, squad, source), CONNECT_ONE_SHOT)
		var before := victim.hp
		throw_at(squad, victim)
		check(String(victim.get_meta("netter_sync_fixture", "")) == reason,
			reason + "反例须实际经过hurt同步回调")
		near(before - victim.hp, 10.0, reason + "同步失效之前仍保留一次真实原伤害")
		near(float(game.specializations.net_remaining(victim)), 0.0,
			reason + "hurt同步改令/换槽/换Dictionary/清epoch后不得随后新挂网")
		check(not game.squads.netters.casting(source) and not source.attack_queued,
			reason + "旧源前摇已经提交，不留二次伤害或控制入口")
		check(victim.find_child("NetterLandedNet", true, false) == null,
			reason + "受控失效不留下未记账成功网视觉")
		# Restore deliberately replaced raw identities before ordinary cleanup;
		# otherwise the test itself would hide the displaced actor from cleanup.
		if reason == "slot": squad.members[0] = source
		if reason == "dictionary": game.squads.squads[int(squad.id)] = squad
	evidence["synchronous_identity_scope"] = "controlled actual hurt-signal re-entrancy: source death, public order, raw slot/Dictionary replacement, clear epoch; not normal UI or natural balance"

func controls_and_motion() -> void:
	var squad := await ready_squad()
	if squad.is_empty(): return
	var source := place_source(squad)
	var runner := enemy("runner", OPEN + Vector3(5, 0, 0))
	stand_hero(OPEN + Vector3(20, 0, 0))
	throw_at(squad, runner)
	var base_speed := runner.speed
	var origin := runner.position
	runner.tick(.2)
	game.update_creature(runner, .2)
	var slow_distance := runner.position.distance_to(origin)
	near(slow_distance, base_speed * .55 * .2, "疾行体真实update_creature位移减慢45%", .01)
	near(runner.speed, base_speed, "控制不得回写基础速度")
	game.squads._set_squad_order(squad, "move")
	near(float(game.specializations.net_remaining(runner)), 2.0, "源改令不撤已经成功落网")
	source.hurt(source.max_hp + 999.0, runner)
	near(float(game.specializations.movement_multiplier(runner)), .55, "源死亡不撤已经成功落网")
	game.specializations.advance(1.99)
	check(game.specializations.net_remaining(runner) > 0.0, "两秒前控制仍存活")
	game.specializations.advance(.011)
	near(float(game.specializations.net_remaining(runner)), 0.0, "两秒到期自动移除")
	near(float(game.specializations.movement_multiplier(runner)), 1.0, "到期恢复原速度倍率")
	origin = runner.position
	runner.tick(.2)
	game.update_creature(runner, .2)
	near(runner.position.distance_to(origin), base_speed * .2, "原疾行体真实移动恢复全速", .01)
	for role: String in ["breaker", "sapper", "shellguard"]:
		var heavy := enemy(role, OPEN + Vector3(6, 0, 5))
		check(game.specializations.apply_net(heavy), "共享控制接受真实重敌 " + role)
		near(float(game.specializations.movement_multiplier(heavy)), .8, role + "只减慢20%")
		near(float(game.specializations.net_remaining(heavy)), 2.0, role + "独立两秒时限")
	# Use the actual tower damage/control route. Different clocks must not
	# add strength or inherit one another's remaining duration.
	var pad: Dictionary = game.world.tower_pads[0]
	stand_hero(pad.position + Vector3(2, 0, 0))
	var tower_wallet: int = game.scrap
	var upgrade_cost: int = game.districts.tower_cost(50)
	check(game.build_or_upgrade_tower(0) and int(pad.level) == 2,
		"牵制时限反例先真实付费升级存活二级塔")
	check(game.choose_tower_specialization("control") and game.scrap == tower_wallet - upgrade_cost - 45,
		"原牵制科技通过真实工坊折后塔升级/45改装付款解锁")
	game.specializations.reset_effects()
	var hp := runner.hp
	game.specializations.resolve_shot(pad, runner, [runner], 1.0, game.hero)
	check(runner.hp < hp, "真实牵制塔提交实际伤害作为塔减速见证")
	near(float(game.specializations.movement_multiplier(runner)), .7, "原塔减速保持30%")
	game.specializations.advance(.5)
	check(game.specializations.apply_net(runner), "后发真实投网控制可共存")
	near(float(game.specializations.movement_multiplier(runner)), .55, "塔与网只取最强45%而非75%")
	game.specializations.advance(.701)
	near(float(game.specializations.movement_multiplier(runner)), .55, "塔先到期不抹掉独立网")
	near(float(game.specializations.net_remaining(runner)), 1.299, "网不借用塔的1.2秒钟")
	game.specializations.reset_effects()
	check(game.specializations.apply_net(runner), "第二组时限反例先挂网")
	game.specializations.advance(1.5)
	game.specializations.resolve_shot(pad, runner, [runner], 1.0, game.hero)
	game.specializations.advance(.501)
	near(float(game.specializations.net_remaining(runner)), 0.0, "先发网独立到期")
	near(float(game.specializations.movement_multiplier(runner)), .7, "后发塔尚余寿命继续减慢30%")
	game.specializations.advance(.701)
	near(float(game.specializations.movement_multiplier(runner)), 1.0, "两种控制均独立到期后恢复")
	check(game.specializations.apply_net(runner), "死亡清理反例挂真实网")
	runner.hurt(runner.max_hp + 999.0, game.hero)
	near(float(game.specializations.net_remaining(runner)), 0.0, "真实死亡当帧移除目标控制")

func specialists() -> void:
	var squad := await ready_squad()
	if squad.is_empty(): return
	for role: String in ["lobber", "summoner", "warder"]:
		await clear_enemies()
		place_source(squad, Vector3(5, 0, 35))
		stand_hero(Vector3(0, 0, 30))
		var host := enemy(role, Vector3(5, 0, 30))
		var controller: Node3D
		if role == "lobber": controller = game.lobbers.back()
		elif role == "summoner": controller = game.summoners.back()
		else:
			controller = game.warders.back()
			var recipient := enemy("basic", Vector3(6, 0, 30))
			recipient.hurt(40.0, game.hero)
		controller.advance(.001)
		check(String(controller.snapshot().phase) == "windup", role + "必须先进入真实专职引导")
		var hp := host.hp
		throw_at(squad, host)
		check(host.hp < hp and game.specializations.net_remaining(host) > 0.0, role + "真实部队投掷完成伤害及控制")
		controller.advance(.001)
		check(String(controller.snapshot().phase) != "windup"
			and String(controller.snapshot().cancel_reason) == "source_controlled", role + "专职引导被实际网打断")
		if role == "lobber": check(int(controller.snapshot().launched) == 0 and int(controller.snapshot().impacts) == 0,
			"投蚀未发弹的前摇不会留下固定落点伤害")
		elif role == "summoner": check(int(controller.snapshot().spawned) == 0,
			"召潮未完成引导不得冒充真实出生或消费有限名额")
		else: check(int(controller.snapshot().casts) == 0,
			"织壳未完成引导不得提交护盾或消费名额")
	await clear_enemies()
	var source := place_source(squad, Vector3(4, 5, 7))
	stand_hero(Vector3(0, 5, 8))
	var boss := enemy("breaker", Vector3(0, 5, 7))
	game.siege_boss = BossScript.new()
	game.siege_boss.setup(game, boss)
	game.siege_boss.advance(8.001)
	check(String(game.siege_boss.snapshot().phase) == "windup", "真实首领先启动局部拍击蓄力")
	var hp := boss.hp
	throw_at(squad, boss)
	game.siege_boss.advance(.001)
	var actual_loss := hp - boss.hp
	near(actual_loss, 10.0 * 100.0 / 118.0, "投网10伤仍走首领18护甲")
	near(float(game.specializations.movement_multiplier(boss)), .8, "首领移动控制取重敌20%")
	check(String(game.siege_boss.snapshot().phase) == "windup", "小额投网不能绕过首领220实际HP打断门槛")
	near(float(game.siege_boss.snapshot().interrupt_damage), actual_loss, "首领累计真实HP损失，不使用投网状态冒充220")
	boss.hurt((220.0 - actual_loss) * 1.18 - .02, source)
	game.siege_boss.advance(.001)
	check(String(game.siege_boss.snapshot().phase) == "windup", "真实损失220之前首领继续蓄力")
	boss.hurt(.04, source)
	game.siege_boss.advance(.001)
	check(String(game.siege_boss.snapshot().phase) == "exposed", "真实累计达到220才进入首领破绽")

func fixed_landing_comparison() -> void:
	for use_net in [false, true]:
		var squad := await ready_squad(true)
		if squad.is_empty(): return
		var cannon_squad := train("artillery")
		if cannon_squad.is_empty(): return
		var netter := place_source(squad, OPEN + Vector3(0, 0, 2))
		var cannon := place_source(cannon_squad, OPEN)
		var runner := enemy("runner", OPEN + Vector3(8, 0, 0))
		var aim_actor := enemy("basic", OPEN + Vector3(7, 0, 0))
		stand_hero(OPEN + Vector3(-10, 0, -5))
		if use_net:
			throw_at(squad, runner)
			check(game.specializations.net_remaining(runner) > 0.0, "炮击成对网组必须先真投掷命中疾行体")
		else:
			check(game.specializations.net_remaining(runner) == 0.0, "炮击对照组不得预挂控制")
		# Restore the same fixed netter formation in both scenes after the
		# optional targeted throw. Otherwise the throw's destination would move
		# one formation nearer and change the runner's chosen target as well.
		netter = place_source(squad, OPEN + Vector3(0, 0, 2))
		netter.attack_timer = 9999.0
		for member: BattleUnit in squad.members: member.attack_timer = 9999.0
		cannon.attack_timer = 0.0
		attack_order(cannon_squad, aim_actor)
		game.squads.advance(.001)
		check(game.squads.artillery.casting(cannon), "两组均用真实指定目标启动完整炮兵前摇")
		var fixed_point := aim_actor.position
		advance_roster(1.001, true)
		var launched: Dictionary = game.squads.artillery_snapshot()
		check(int(launched.launched) == 1 and int(launched.flight) == 1, "一秒真实准备后只能发射一枚固定落点弹")
		if int(launched.flight) == 0: continue
		near((launched.shots[0].point as Vector3).distance_to(fixed_point), 0.0,
			"发射不改变最初真实目标采样的落点")
		var before := runner.hp
		var origin := runner.position
		var flight_seconds := 0.0
		for _frame in 20:
			if int(game.squads.artillery_snapshot().impacts) > 0: break
			game.specializations.advance(STEP)
			game.squads.advance(STEP)
			if int(game.squads.artillery_snapshot().impacts) > 0: break
			runner.tick(STEP)
			game.update_creature(runner, STEP)
			flight_seconds += STEP
		var result: Dictionary = game.squads.artillery_snapshot()
		check(int(result.impacts) == 1, "真实飞行到期应提交且仅提交一次落点爆炸")
		var distance := runner.position.distance_to(fixed_point)
		var hp_loss := before - runner.hp
		check(hp_loss > 0.0 if use_net else is_zero_approx(hp_loss),
			"有网疾行体留在真实炮圈受到实伤；无网对照跑出固定炮圈")
		check(distance <= 2.2 if use_net else distance > 2.2,
			"实际疾行位移与2.2米固定半径应解释两组命中差异")
		near(hp_loss, 32.0 * 100.0 / (100.0 + runner.armor) if use_net else 0.0,
			"仅网组承担原32点炮兵实际伤害，不混入预先10伤")
		check(runner.position != origin and runner.speed == 5.4, "成对场景必须实际移动且保留原疾行速度")
		evidence.artillery.append({"net": use_net, "fixed_point": fixed_point, "origin": origin,
			"final": runner.position, "distance": distance, "runner_hp_loss_from_shell": hp_loss,
			"flight_motion_seconds": flight_seconds, "impacts": int(result.impacts),
			"scope": "precision actors hold during aim windup, then actual runner updates throughout launched flight"})
		await capture("artillery-net" if use_net else "artillery-free", Vector3(25, 0, 30))
	check(evidence.artillery.size() == 2, "炮击收益必须留下同种子成对真实实伤回执")

func lifecycle() -> void:
	var squad := await ready_squad()
	if squad.is_empty(): return
	var source := place_source(squad)
	var target := enemy("basic", OPEN + Vector3(5, 0, 0))
	throw_at(squad, target)
	source.attack_timer = 0.0
	attack_order(squad, target)
	game.squads.advance(.001)
	var pending := source.attack_windup
	var remaining := float(game.specializations.net_remaining(target))
	var hp := target.hp
	await press(KEY_ESCAPE)
	check(game.phase == "night" and game.squads.selected_count() == 0,
		"真实Esc先取消公开指定攻击留下的部队选择")
	near(source.attack_windup, pending, "取消选择不取消已经提交的部队攻击命令")
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "真实Esc进入暂停")
	game.simulate(1.0)
	game.squads.advance(1.0)
	near(source.attack_windup, pending, "暂停冻结真实成员前摇")
	near(float(game.specializations.net_remaining(target)), remaining, "暂停冻结目标网寿命")
	near(target.hp, hp, "暂停不提交待发网伤害")
	await press(KEY_ESCAPE)
	check(game.phase == "night", "真实Esc恢复原阶段")
	game.run.grant("投网专项生命周期夹具")
	game.open_draft()
	check(game.phase == "draft", "真实待选铭刻入口可冻结战场")
	game.simulate(1.0)
	game.squads.advance(1.0)
	near(source.attack_windup, pending, "选卡冻结待发网")
	near(float(game.specializations.net_remaining(target)), remaining, "选卡冻结独立网计时")
	check(game.choose_card(0) and game.phase == "night", "真实选卡恢复原夜间")
	game.finish_night()
	check(not game.squads.netters.casting(source), "真实黎明取消旧前摇")
	near(float(game.specializations.net_remaining(target)), 0.0, "真实黎明清理旧网，不跨白昼继承")
	if game.phase == "draft": game.choose_card(0)
	check(game.phase == "day", "真实黎明铭刻后进入白昼")
	game.start_night()
	check(game.phase == "night", "真实日落入口进入下一夜")
	near(float(game.specializations.net_remaining(target)), 0.0, "日落不复活上夜目标控制")
	game.end_defeat("投网专项真实失败清理")
	check(game.phase == "ended" and game.squads.squads.is_empty(), "失败清理真实小队注册")
	near(float(game.specializations.net_remaining(target)), 0.0, "失败清理公共网状态")
	var old_root := game.get_instance_id()
	await press(KEY_ENTER)
	for _frame in 200:
		if current_scene != null and current_scene.get_instance_id() != old_root: break
		await create_timer(.02, true, false, true).timeout
	check(current_scene != null and current_scene.get_instance_id() != old_root,
		"真实Enter重试必须重载场景")
	if current_scene == null or current_scene.get_instance_id() == old_root: return
	game = current_scene as Node3D
	game.set_process(false)
	game.world.set_process(false)
	await frames(3)
	check(not is_instance_id_valid(old_root) and game.phase == "draft" and game.run.seed_value == SEED,
		"同种子真实重试释放旧root且重新进入开局选卡")
	check(game.scrap == 90 and game.squads.squads.is_empty() and game.squads.training_queues.is_empty()
		and int(game.squads.netter_snapshot().alive) == 0 and game.archive.path == profile_path,
		"实际重试不继承钱、投网成员、队列或玩家档案路径")
	game.end_defeat("投网专项新种子入口夹具")
	game.request_run_restart(false)
	var retry_root := game.get_instance_id()
	for _frame in 200:
		if current_scene != null and current_scene.get_instance_id() != retry_root: break
		await create_timer(.02, true, false, true).timeout
	check(current_scene != null and current_scene.get_instance_id() != retry_root, "真实新种子新局必须重新加载")
	if current_scene == null or current_scene.get_instance_id() == retry_root: return
	game = current_scene as Node3D
	game.set_process(false)
	game.world.set_process(false)
	check(game.run.seed_value != SEED and game.squads.squads.is_empty() and game.scrap == 90,
		"实际新局使用新种子且部队和经济重置")
	await press(KEY_1)
	await clear_enemies()
	isolate()
	var controlled := enemy("basic", OPEN)
	check(game.specializations.apply_net(controlled), "关闭前必须存在真实控制用于清理见证")
	await game.prepare_shutdown()
	check(game.shutting_down and game.squads.squads.is_empty(), "真实关闭设置生命周期标记且清理roster")
	near(float(game.specializations.net_remaining(controlled)), 0.0, "关闭不能保留公共网计时")

func install_hud_observer() -> void:
	var observer := GDScript.new()
	observer.source_code = HUD_OBSERVER
	check(observer.reload() == OK, "固定只读HUD观察脚本应能编译")
	var old: Control = game.hud
	var layer := old.get_parent()
	layer.remove_child(old)
	old.queue_free()
	var replacement: Control = observer.new()
	replacement.game = game
	game.hud = replacement
	layer.add_child(replacement)
	replacement.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames()

func capture(tag: String, focus: Vector3 = Vector3.ZERO) -> void:
	if not render_test or DisplayServer.get_name() == "headless": return
	if focus != Vector3.ZERO:
		game.camera.position = focus + Vector3(0, 25, 29)
		game.camera.look_at(focus)
		game.camera_follow = game.camera.position
	for _frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	# The maximized Retina window can have a different outer size while the
	# viewport texture and HUD both render at the requested content pixels.
	var content_pixels := root.content_scale_size
	check(image.get_size() == content_pixels
		and Vector2(image.get_size()) == game.hud.get_viewport_rect().size,
		"真实截图与HUD必须共同采用请求内容像素视口")
	var directory := "res://build/netters-" + capture_tag
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK,
		"证据仅写固定本地build目录")
	var basename := "%s-%dx%d.png" % [tag, content_pixels.x, content_pixels.y]
	check(image.save_png(directory.path_join(basename)) == OK, "实际渲染证据应写出完整PNG")
	evidence.captures.append(basename)

func hud_and_input() -> void:
	var squad := await ready_squad()
	if squad.is_empty(): return
	await install_hud_observer()
	game.squads.cancel_selection()
	game.notice_time = 0.0
	game.reward_toasts.clear()
	game.beacon_alarm_time = 0.0
	game.combat.clear_transients()
	check(game.hud.detail_tab == "", "默认HUD保持抽屉收起")
	var rects_before: Array = game.hud.live_panel_rects().duplicate()
	check(not rects_before.has(game.hud.SQUAD_PANEL_RECT), "新增兵种不增加常驻大部队面板")
	await press(KEY_F3)
	await click(game.hud.details_tab_rect(2))
	check(game.hud.detail_tab == "army", "真实F3及部队页点击应进入原抽屉")
	for _page in 3: await click(game.hud.troop_page_rect(1))
	check(game.hud.troop_page == 3 and game.hud.visible_training_kinds() == ["netter"],
		"真实翻页第三次进入第四页，独立展示投网队")
	for viewport: Vector2i in VIEWPORTS:
		root.size = viewport
		root.content_scale_size = viewport
		game.hud.queue_redraw()
		await frames(4)
		check(Vector2i(game.hud.get_viewport_rect().size) == viewport, "三视口均由真实GUI采用请求像素尺寸")
		var title_seen := false
		var dependency_seen := false
		var mechanic_seen := false
		for row: Dictionary in game.hud.netter_labels:
			if String(row.text).contains("投网队"): title_seen = true
			if String(row.text).contains("研究所"): dependency_seen = true
			if String(row.text).contains("45%") or String(row.text).contains("20%"): mechanic_seen = true
			if row.point.x >= 44 and row.point.x <= 542 and row.point.y >= 178 and row.point.y <= 690:
				check(float(row.point.x) + float(row.width) <= 550.0
					and float(row.point.y) + float(row.descent) <= 692.0,
					"第四页实际中文字形须在原抽屉列宽/关闭按钮上界内: " + String(row.text))
		check(title_seen and dependency_seen and mechanic_seen, "第四页实际绘制中文兵种、研究所依赖与真实减速说明")
		for character in "投网队研究所零件秒":
			check(game.hud.font.has_char(character.unicode_at(0)), "实际平台字体含中文字符 " + character)
		var before: int = game.scrap
		var before_count := troop_count("netter")
		await click(game.hud.training_kind_rect(0))
		check(game.scrap == before - 100 and troop_count("netter") == before_count,
			"第四页真实训练按钮只付100且不瞬时出兵")
		var queues: Array = game.squads.snapshot().queues
		var found := false
		for queue: Dictionary in queues:
			if queue.queue.is_empty(): continue
			var order: Dictionary = queue.queue.back()
			if String(order.kind) != "netter": continue
			found = true
			near(float(order.remaining), 9.0, "真实GUI创建完整九秒订单")
			check(game.cancel_troop_training(int(queue.index), queue.queue.size() - 1), "实际取消训练退回原订单")
			break
		check(found and game.scrap == before, "真实GUI训练与取消共用同一零件账本")
		await capture("army-fourth-page")
		await click(game.hud.DETAIL_CLOSE_RECT)
		# Actual training and cancellation notify the player. Compare permanent
		# areas only after removing this fixture's notices as before the baseline.
		game.notice_time = 0.0
		game.reward_toasts.clear()
		game.hud.queue_redraw()
		await frames()
		check(game.hud.detail_tab == "" and game.hud.live_panel_rects() == rects_before,
			"收起第四页回到原默认面积")
		await capture("default-clean")
		await press(KEY_F3)
		await click(game.hud.details_tab_rect(2))
	root.size = VIEWPORTS[0]
	root.content_scale_size = VIEWPORTS[0]
	game.hud.dismiss_details()
	var source := place_source(squad)
	var target := enemy("basic", OPEN + Vector3(5, 0, 0))
	attack_order(squad, target)
	game.squads.advance(.001)
	check(game.squads.netters.casting(source), "图形证据中的准备须来自真实部队命令")
	await capture("netter-windup", OPEN + Vector3(3, 0, 0))
	advance_roster(.601)
	check(game.specializations.net_remaining(target) > 0.0, "图形证据中的落网须来自真实一次命中")
	await capture("netter-landed", OPEN + Vector3(3, 0, 0))

func natural_tick() -> void:
	game.aim = game.hero.position + Vector3(0, 0, 8)
	if game.gate_pressure() > 0: game.cast(0)
	if game.hero.hp < game.hero.max_hp * .6:
		game.cast(1)
		game.cast(4)
	if game.gate_pressure() >= 6: game.cast(3)
	game.simulate(.1)

func natural_economy() -> void:
	if not await fresh(false): return
	check(game.scrap == 90 and game.phase_time == 105.0, "自然段原90零件与105秒首夜保持")
	game.plan_hero_path(Vector3(0, 5, 10))
	for frame in 1100:
		if game.phase != "night": break
		natural_tick()
		if frame % 100 == 99: await process_frame
	check(game.phase == "draft" and game.hero.alive and game.beacon_hp > 0.0,
		"原始技能策略实际度过首夜，没有补钱、摆位、删怪、改属性或延时")
	if game.phase != "draft": return
	var dawn_parts: int = game.scrap
	var first_kills: int = game.kills
	await press(KEY_1)
	check(game.phase == "day" and game.phase_time == 90.0 and game.scrap == dawn_parts,
		"自然黎明保留原90秒白昼与真实赚得的钱包")
	# Before paying the chain, earn the remaining budget from actual reachable
	# salvage. Movement uses the real hero path and F input at the source.
	var collected: Array[Dictionary] = []
	var attempts := 0
	while game.phase == "day" and game.phase_time > 20.0 and game.scrap < 340 and attempts < 8:
		attempts += 1
		var chosen := -1
		var distance := INF
		for index in game.world.salvage.size():
			var item: Dictionary = game.world.salvage[index]
			if bool(item.collected): continue
			var separation: float = game.hero.position.distance_to(item.position)
			if separation < distance:
				chosen = index
				distance = separation
		if chosen < 0: break
		var item: Dictionary = game.world.salvage[chosen]
		var before: int = game.scrap
		game.plan_hero_path(item.position)
		for frame in 280:
			if game.phase != "day" or game.phase_time <= 15.0 or game.hero.position.distance_to(item.position) < 2.4: break
			natural_tick()
			if frame % 100 == 99: await process_frame
		await press(KEY_F)
		if bool(item.collected):
			collected.append({"index": chosen, "gain": game.scrap - before, "time_left": game.phase_time})
		else: break
	var before_buildings: int = game.scrap
	var buildings := technology()
	var after_buildings: int = game.scrap
	check(before_buildings - after_buildings == 240 and buildings.size() == 3,
		"自然科技链只支付工坊60/兵营60/研究所120，唯一钱包不增新资源")
	var success: bool = game.train_troop("netter")
	if before_buildings >= 340:
		check(success and game.scrap == after_buildings - 100, "自然探索赚得足够预算才支付100投网队")
		var before_train_time := float(game.phase_time)
		for frame in 100:
			if game.phase != "day" or troop_count("netter") > 0: break
			natural_tick()
		check(troop_count("netter") == 1 and before_train_time - game.phase_time >= 8.999,
			"原自然白昼中实际耗九秒交付三员投网队")
	else:
		check(not success and game.scrap == after_buildings, "自然收入不足时真实训练拒绝，不补钱掩盖经济缺口")
	evidence.natural = {"seed": SEED, "opening_parts": 90, "first_night_seconds": 105,
		"day_seconds": 90, "first_night_kills": first_kills, "dawn_parts": dawn_parts,
		"actual_salvage": collected, "parts_before_chain": before_buildings,
		"chain_payments": [60, 60, 120], "after_chain": after_buildings,
		"netter_order_accepted": success, "delivered": troop_count("netter"),
		"final_parts": game.scrap, "time_left": game.phase_time, "hero_hp": game.hero.hp,
		"beacon_hp": game.beacon_hp,
		"scope": "one natural fixed-seed first-night/day policy; no supplemented money, actor placement, enemy/stat changes or clock extension; insufficient budget is reported"}
	print("NETTER_NATURAL ", JSON.stringify(evidence.natural))
	await capture("natural-day", Vector3(0, 5, 10))

func finish(exit_code: int) -> void:
	if finished: return
	finished = true
	await close_game()
	# Dummy audio retires playback references on its mixing thread after all
	# players/nodes are gone; give it the same bounded grace as alarm tests.
	await create_timer(.5, true, false, true).timeout
	cleanup_profile()
	evidence["checks"] = checks
	evidence["failures"] = failures
	evidence["completed"] = completed
	var directory := "res://build/netters-" + capture_tag
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory.path_join("result.json"), FileAccess.WRITE)
	if file == null: check(false, "专项回执须能写入固定build路径")
	else:
		file.store_string(JSON.stringify(evidence, "\t"))
		file.close()
	print("NIGHTFALL_NETTERS_OK checks=%d" % checks if failures.is_empty() and exit_code == 0
		else "NIGHTFALL_NETTERS_FAILED checks=%d failures=%d stage=%s" % [checks, failures.size(), stage])
	quit(0 if failures.is_empty() and exit_code == 0 else 1)

func watchdog() -> void:
	if finished: return
	check(false, "180秒看门狗有界退出，不能把挂起进程当通过")
	await finish(1)

func run() -> void:
	var cases := {"production": production, "combat": combat_and_geometry, "cancellation": cancellations,
		"control": controls_and_motion, "specialists": specialists, "artillery": fixed_landing_comparison,
		"lifecycle": lifecycle, "hud": hud_and_input, "economy": natural_economy}
	for label: String in cases:
		stage = label
		print("NETTER_STAGE_BEGIN ", stage)
		await (cases[label] as Callable).call()
		completed.append(stage)
		print("NETTER_STAGE_END ", stage, " checks=", checks, " failures=", failures.size())
	await finish(0)
