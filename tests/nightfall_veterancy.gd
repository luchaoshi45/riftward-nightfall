extends SceneTree
## 逐员老兵真实生产专项。精度段显式使用5000零件、隔离站位/冷却及直接hurt，
## 用于边界与生命周期验证；真实武器段仍经过GUI生产、完整前摇和原hurt/death链。
## 自然成对段保持原90/105/90、原演员属性与真实GUI收入支出，不摆人或直接伤敌。
const Session := preload("res://scripts/run_session.gd")
const Archive := preload("res://scripts/run_archive.gd")
const Catalog := preload("res://scripts/outpost_catalog.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
const Encounter := preload("res://scripts/nightfall_encounters.gd")
const CleanHud := preload("res://scripts/nightfall_clean_hud.gd")
const Transition := preload("res://tests/nightfall_transition_fixture.gd")
const SEED := 20261007
const COMBAT_KINDS := ["shield","ranged","engineer","ballista","artillery","hunter","flamer","netter"]
const BASE_DAMAGE := {"shield":10.0,"ranged":16.0,"engineer":5.0,"ballista":46.0,"artillery":32.0,"hunter":12.0,"flamer":22.0,"netter":10.0}
const STEP := .05
const VIEWS := [Vector2i(1920,1200),Vector2i(1920,1080),Vector2i(1440,900)]
const OPEN := Vector3(20,0,30)
const BUILD_POINTS := {"barracks":Vector3(7,5,-8.5),"workshop":Vector3(-7.5,5,-8),
	"laboratory":Vector3(7,5,-3.5),"armory":Vector3(-7,5,-3),
	"depot":Vector3(9,5,4.5),"infirmary":Vector3(-9,5,4.5)}
const OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var veterancy_labels: Array[Dictionary] = []
func _draw() -> void:
	veterancy_labels.clear()
	super._draw()
func label(value: String, point: Vector2, size_px: int, color: Color = Color(\"e7e1d3\"), latin: bool = false) -> void:
	var actual: Font = display_font if latin else font
	veterancy_labels.append({\"text\":value,\"point\":point,\"width\":actual.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x,
		\"ascent\":actual.get_ascent(size_px),\"descent\":actual.get_descent(size_px)})
	super.label(value,point,size_px,color,latin)
"""

var game: Node3D
var checks := 0
var failures: Array[String] = []
var completed: Array[String] = []
var stage := "initialize"
var stage_finished := false
var precision := true
var render_test := false
var selected_case := ""
var finished := false
var output_dir := ""
var profile_path := "user://riftward-veterancy-%d.json" % Time.get_ticks_usec()
var original_profile_hashes: Dictionary = {}
var elapsed := 0.0
var births: Array[Dictionary] = []
var wounds: Array[Dictionary] = []
var deaths: Array[Dictionary] = []
var wallets: Array[Dictionary] = []
var observed: Dictionary = {}
var growth_signatures: Dictionary = {}
var growth: Array[Dictionary] = []
var moves: Dictionary = {}
var reentry: Dictionary = {}
var evidence: Dictionary = {"seed":SEED,"scope":"precision, production weapons and original-clock natural routes are separate; native Windows unverified",
	"precision":{"parts":5000,"stationed_actors":true,"isolated_cooldowns":100000,"direct_hurt_fixture":true,"artificial_lifecycle":true},
	"payments":[],"captures":[],"natural":[],"precision_results":[],"weapon_results":[]}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	render_test = "--render-test" in args
	var index := args.find("--case")
	if index >= 0 and index + 1 < args.size(): selected_case = args[index+1]
	var backend := "headless" if DisplayServer.get_name()=="headless" else ("opengl" if RenderingServer.get_current_rendering_method()=="gl_compatibility" else "metal")
	output_dir = ProjectSettings.globalize_path("res://build/veterancy/"+backend).simplify_path()
	index = args.find("--output-dir")
	if index >= 0 and index+1 < args.size():
		var candidate := ProjectSettings.globalize_path(args[index+1]).simplify_path()
		if valid_output(candidate): output_dir = candidate
		else: check(false,"证据只写固定物理build/veterancy及后端子目录")
	check(valid_output(output_dir),"默认证据路径无符号链接")
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = Archive.PROFILE_PATH + suffix
		original_profile_hashes[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	root.size = VIEWS[0]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = VIEWS[0]
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.position = Vector2i(-10000,-10000)
		root.hide()
	for local_path: String in ["res://project.godot","res://export_presets.cfg"]:
		original_profile_hashes[local_path]=FileAccess.get_sha256(local_path) if FileAccess.file_exists(local_path) else "absent"
	root.child_entered_tree.connect(inject_archive)
	create_timer(480.0,true,false,true).timeout.connect(watchdog)
	call_deferred("run")

func valid_output(candidate: String) -> bool:
	var base := ProjectSettings.globalize_path("res://build/veterancy").simplify_path()
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
	failures.append(stage+": "+message)
	if failures.size() <= 40: push_error(stage+": "+message)

func near(actual: float, expected: float, message: String, tolerance: float = .001) -> void:
	check(is_finite(actual) and absf(actual-expected) <= tolerance,message+" actual=%.6f expected=%.6f" % [actual,expected])

func vec(point: Vector3) -> Array[float]:
	return [point.x,point.y,point.z]

func planar(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x-second.x,first.z-second.z).length()

func living(value: Variant) -> bool:
	return is_instance_valid(value) and value is BattleUnit and not value.is_queued_for_deletion() and value.alive and value.hp>0.0

func frames(count: int = 3) -> void:
	for _frame in count: await process_frame

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode=code; event.physical_keycode=code; event.pressed=true
	root.push_input(event,true)
	event.pressed=false
	root.push_input(event,true)
	await process_frame

func mouse(point: Vector2, button: int = 0) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position=point; motion.global_position=point
	root.push_input(motion,true)
	await process_frame
	if button == 0: return
	var event := InputEventMouseButton.new()
	event.position=point; event.global_position=point; event.button_index=button
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if button==MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	event.pressed=true
	root.push_input(event,true)
	await process_frame
	event.pressed=false; event.button_mask=0
	root.push_input(event,true)
	await process_frame

func click_ui(rect: Rect2) -> void:
	await mouse(rect.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900),MOUSE_BUTTON_LEFT)

func camera_at(point: Vector3) -> void:
	game.camera.size=38.0
	game.camera.position=point+Vector3(0,25,29)
	game.camera.look_at(point)
	game.camera_follow=game.camera.position

func close_drawer() -> void:
	if not game.hud.detail_tab.is_empty(): await press(KEY_F3)
	if game.construction.active: await press(KEY_ESCAPE)

func install_observer() -> void:
	var script := GDScript.new()
	script.source_code=OBSERVER
	check(script.reload()==OK,"固定只读HUD观察器解析")
	var old: Control=game.hud
	var layer := old.get_parent()
	layer.remove_child(old); old.queue_free()
	var replacement: Control=script.new()
	replacement.game=game; game.hud=replacement
	layer.add_child(replacement)
	replacement.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames()

func close_game() -> void:
	if not is_instance_valid(game): return
	await game.prepare_shutdown()
	if current_scene==game: current_scene=null
	game.queue_free(); game=null
	await frames(4)
	await create_timer(.5,true,false,true).timeout

func clear_hostiles(keep: BattleUnit = null) -> void:
	check(precision,"仅精度段使用明确100000真实致死准备隔离")
	for raw: Variant in game.enemies.duplicate():
		if living(raw) and raw != keep: raw.hurt(100000.0,null)
	game.clear_lobbers(); game.clear_summoners(); game.clear_warders()
	if keep==null: game.clear_burstlings()
	if is_instance_valid(game.siege_boss):
		game.siege_boss.clear(); game.siege_boss.queue_free(); game.siege_boss=null
	game.specializations.reset_effects()
	await frames()

func fresh(is_precision: bool = true) -> bool:
	await close_game()
	precision=is_precision; elapsed=0.0
	births.clear(); wounds.clear(); deaths.clear(); wallets.clear(); growth.clear()
	observed.clear(); growth_signatures.clear(); moves.clear(); reentry.clear()
	var queued: bool=Session.queue_request(self,SEED,"siege")
	check(queued,"真实会话接受原种子与四夜铁潮")
	if not queued: return false
	game=load("res://scenes/nightfall.tscn").instantiate() as Node3D
	root.add_child(game); current_scene=game
	await frames(5)
	game.set_process(false); game.world.set_process(false)
	check(game.archive.path==profile_path and game.phase=="draft","_ready前注入固定私有档案")
	check(game.run.seed_value==SEED and game.run_mode=="siege","实际会话消费固定种子与真实模式")
	check(game.scrap==90 and game.squads.squads.is_empty(),"原开局90零件且没有部队")
	check(is_instance_valid(game.squads.veterancy),"真实部队模块已装配逐员老兵")
	if not is_instance_valid(game.squads.veterancy): return false
	await install_observer()
	await press(KEY_1)
	check(game.phase=="night" and game.phase_time==105.0,"真实选卡开启原105秒首夜")
	if precision:
		await clear_hostiles()
		game.scrap=5000; game.phase_time=10000.0; game.wave_index=game.WAVES_PER_NIGHT
		game.pulse_timer=100000.0; game.hero.attack_timer=100000.0; game.gate_trap_charges=0
		for pad: Dictionary in game.world.tower_pads: pad.cooldown=100000.0
		stand_hero(Vector3(-11,5,-10))
	observe()
	return true

func stand_hero(point: Vector3) -> void:
	check(precision,"自然段禁止直接摆英雄")
	point.y=game.outpost_height(point)
	game.hero.position=point; game.move_goal=point; game.hero_path.clear()
	game.hero.moving=false; game.hero_keyboard_active=false
	game.hero.set_locomotion_velocity(Vector3.ZERO)

func record_wound(victim: BattleUnit, source: BattleUnit, hp_loss: float, shield_loss: float) -> void:
	wounds.append({"token":victim.get_instance_id(),"source":source.get_instance_id() if is_instance_valid(source) else -1,
		"hero":victim==game.hero,"hp_loss":hp_loss,"shield_loss":shield_loss,"position":vec(victim.position),
		"at":elapsed,"phase":String(game.phase),"night":int(game.day_number)})

func record_death(victim: BattleUnit, source: BattleUnit) -> void:
	deaths.append({"token":victim.get_instance_id(),"source":source.get_instance_id() if is_instance_valid(source) else -1,
		"role":String(victim.get_meta("threat",victim.get_meta("squad_kind",""))),"at":elapsed,
		"phase":String(game.phase),"night":int(game.day_number),"hp":victim.hp,"alive":victim.alive,"parts":int(game.scrap),"eligible_members":eligible_member_tokens()})

func observe() -> void:
	if not is_instance_valid(game): return
	var actors: Array=[]
	actors.append(game.hero)
	actors.append_array(game.enemies)
	for squad: Dictionary in game.squads.squads: actors.append_array(squad.members)
	for raw: Variant in actors:
		if not living(raw): continue
		var member: BattleUnit=raw
		var token:=member.get_instance_id()
		if not observed.has(token):
			observed[token]=true
			births.append({"token":token,"kind":member.kind,"role":String(member.get_meta("threat",member.get_meta("squad_kind",""))),
				"night":int(game.day_number),"at":elapsed,"position":vec(member.position),"hp":member.hp,
				"max_hp":member.max_hp,"armor":member.armor,"damage":member.damage,"speed":member.speed,
				"wave":int(member.get_meta("wave_reward_id",-1)),"reinforcement":bool(member.get_meta("summoned_reinforcement",false))})
			member.defeated.connect(record_death)
			member.damage_confirmed.connect(record_wound)
			if member.kind != "monster": moves[token]={"origin":vec(member.position),"last":member.position,"distance":0.0,"steps":0,"maximum_step":0.0}
		if moves.has(token):
			var row: Dictionary=moves[token]
			var moved:=planar(row.last,member.position)
			row.distance+=moved; row.maximum_step=maxf(row.maximum_step,moved)
			if moved>.00001: row.steps+=1
			row.last=member.position; row["final"]=vec(member.position); row["alive"]=member.alive; row["hp"]=member.hp
	for squad: Dictionary in game.squads.squads:
		for value: Variant in squad.members:
			if not living(value): continue
			var row: Dictionary=game.squads.veterancy.member_snapshot(value)
			if row.is_empty(): continue
			var token: int=int(row.source_token)
			var signature: String="%.6f:%d" % [float(row.xp),int(row.rank)]
			if growth_signatures.get(token,"")==signature: continue
			growth_signatures[token]=signature
			var copy: Dictionary=row.duplicate(true)
			copy["at"]=elapsed; copy["night"]=int(game.day_number); copy["phase"]=String(game.phase)
			growth.append(copy)

func eligible_member_tokens() -> Array[int]:
	var result: Array[int]=[]
	if not is_instance_valid(game) or not is_instance_valid(game.squads): return result
	for squad: Dictionary in game.squads.squads:
		for value: Variant in squad.members:
			if living(value) and not game.squads.veterancy.member_snapshot(value).is_empty(): result.append(value.get_instance_id())
	return result

func step(delta: float = STEP) -> void:
	observe()
	var before: int=game.scrap
	var prior_phase: String=game.phase
	game.simulate(delta)
	if prior_phase in ["day","night"]: elapsed+=delta
	if before!=game.scrap: wallets.append({"at":elapsed,"before":before,"after":int(game.scrap),"phase":String(game.phase)})
	observe()

func advance(seconds: float) -> void:
	for frame in ceili(seconds/STEP):
		step(minf(STEP,seconds-frame*STEP))
		if frame%100==99: await process_frame

func build_gui(kind: String, preferred: Vector3 = Vector3.INF) -> int:
	await close_drawer()
	await press(KEY_Y)
	var target_page: int=Catalog.BUILDING_IDS.find(kind)/3
	for _page in 5:
		var current: int=Catalog.BUILDING_IDS.find(String(game.construction.kind))/3
		if current==target_page: break
		await click_ui(game.hud.construction_page_rect(1 if target_page>current else -1))
	await click_ui(game.hud.construction_kind_rect(Catalog.BUILDING_IDS.find(kind)%3))
	check(game.construction.active and game.construction.kind==kind,"真实Y及自由格子建设选择 "+kind)
	var point: Vector3=preferred if preferred.is_finite() else BUILD_POINTS[kind]
	camera_at(point)
	await mouse(game.camera.unproject_position(point))
	game.flush_pending_aim()
	var preview: Dictionary=game.construction.snapshot()
	check(bool(preview.valid),"真实格子预览允许 "+kind+": "+String(preview.reason))
	var before: int=game.scrap
	if bool(preview.valid): await mouse(game.camera.unproject_position(point),MOUSE_BUTTON_LEFT)
	var found:=-1
	for index in game.districts.plots.size():
		var plot: Dictionary=game.districts.plots[index]
		if plot.kind==kind and int(plot.level)>0 and planar(plot.position,preview.point)<.05: found=index
	check(found>=0 and game.scrap==before-int(Catalog.building(kind).cost),"GUI创建并只支付真实费用 "+kind)
	(evidence.payments as Array).append({"precision":precision,"kind":kind,"before":before,"after":int(game.scrap),"at":elapsed,"time":float(game.phase_time)})
	await press(KEY_ESCAPE)
	return found

func train_gui(kind: String) -> Dictionary:
	await close_drawer()
	await press(KEY_F3)
	await click_ui(game.hud.details_tab_rect(2))
	var index: int=Catalog.TROOP_IDS.find(kind)
	var page: int=index/3
	for _page in 4:
		if game.hud.troop_page==page: break
		await click_ui(game.hud.troop_page_rect(1 if page>game.hud.troop_page else -1))
	var before: int=game.scrap
	var old_size: int=game.squads.squads.size()
	await click_ui(game.hud.training_kind_rect(index%3))
	check(game.scrap==before-int(Catalog.troop(kind).cost) and game.squads.squads.size()==old_size,"GUI真实付款且不瞬时交付 "+kind)
	(evidence.payments as Array).append({"precision":precision,"kind":kind,"before":before,"after":int(game.scrap),"at":elapsed,"time":float(game.phase_time)})
	await close_drawer()
	var time: float=Catalog.troop(kind).time
	await advance(time-.05)
	check(game.squads.squads.size()==old_size,"完整训练时长前不交付 "+kind)
	await advance(.10)
	check(game.squads.squads.size()==old_size+1,"真实完整训练后只交付一队 "+kind)
	if game.squads.squads.size()!=old_size+1: return {}
	var squad: Dictionary=game.squads.squads[old_size]
	check(squad.kind==kind and squad.members.size()==3,"三员原身份真实生产 "+kind)
	if precision:
		for raw: Variant in squad.members:
			if living(raw): raw.attack_timer=100000.0
	observe()
	return squad

func station(squad: Dictionary, points: Array) -> void:
	check(precision,"自然段禁止摆部队")
	game.squads._set_squad_order(squad,"guard")
	squad.destination=points[0]; squad.rally_stations=points.duplicate()
	for slot in squad.members.size():
		var raw: Variant=squad.members[slot]
		if not living(raw): continue
		var soldier: BattleUnit=raw
		var point: Vector3=points[slot]
		point.y=game.outpost_height(point)
		soldier.position=point; soldier.path.clear(); soldier.moving=false; soldier.attack_timer=100000.0

func member_state(source: Variant) -> Dictionary:
	return game.squads.veterancy.member_snapshot(source)

func member_xp(source: Variant) -> float:
	var state: Dictionary=member_state(source)
	check(not state.is_empty(),"真实活逐员身份有老兵快照")
	return float(state.get("xp",-1.0))

func weapon_step(delta: float) -> void:
	observe()
	game.squads.advance(delta)
	elapsed+=delta
	observe()

func freeze_troop_attacks() -> void:
	for squad: Dictionary in game.squads.squads:
		for value: Variant in squad.members:
			if living(value): value.attack_timer=100000.0

func spawn_precision_enemy(role: String = "basic", point: Vector3 = OPEN+Vector3(0,0,6)) -> BattleUnit:
	check(precision,"精度工厂站位不能混入自然证据")
	var enemy: BattleUnit=game.spawn_creature(true,role)
	point.y=game.outpost_height(point)
	enemy.position=point; enemy.attack_timer=100000.0
	observe()
	return enemy

func fixture_earn(source: BattleUnit, target_xp: float) -> bool:
	check(precision,"直接hurt贡献准备仅用于明确精度夹具")
	if not precision or not living(source): return false
	for _iteration in 12:
		var state: Dictionary=member_state(source)
		if state.is_empty(): return false
		var missing: float=clampf(target_xp,0.0,900.0)-float(state.xp)
		if missing<=.00001: return true
		var enemy: BattleUnit=spawn_precision_enemy("basic",OPEN+Vector3(0,0,13))
		var amount: float=minf(missing,enemy.hp)
		enemy.hurt(amount,source)
		if living(enemy): enemy.hurt(100000.0,game.hero)
		observe()
		if absf(member_xp(source)-float(state.xp)-amount)>.001:
			near(member_xp(source),float(state.xp)+amount,"精度贡献只经真实死亡回调结算一次")
			return false
		await frames()
	near(member_xp(source),clampf(target_xp,0.0,900.0),"有界精度准备实际达到目标经验")
	return absf(member_xp(source)-clampf(target_xp,0.0,900.0))<=.001

func hp_damage(token: int, source_token: int = -1) -> float:
	var result:=0.0
	for row: Dictionary in wounds:
		if int(row.token)==token and (source_token<0 or int(row.source)==source_token): result+=float(row.hp_loss)
	return result

func day_fixture() -> bool:
	check(precision,"人工阶段准备不能作为自然黎明或经济证明")
	if game.phase=="day": return true
	check(Transition.finish_for_fixture(game),"人工生命周期准备通过原交接入口")
	if game.phase!="draft": return false
	await press(KEY_1)
	check(game.phase=="day" and game.phase_time==90.0,"真实选黎明卡进入完整原90秒白昼")
	game.phase_time=10000.0
	game.pulse_timer=100000.0; game.hero.attack_timer=100000.0
	await clear_hostiles()
	return game.phase=="day"

func one_hit(squad: Dictionary, role: String = "basic", existing: BattleUnit = null) -> Dictionary:
	await close_drawer()
	freeze_troop_attacks()
	station(squad,[OPEN,OPEN+Vector3(0,0,-24),OPEN+Vector3(0,0,-28)])
	var kind: String=String(squad.kind)
	var distance: float=float({"shield":1.9,"ranged":6.0,"engineer":1.8,"ballista":9.0,"artillery":10.0,"hunter":1.7,"flamer":4.0,"netter":5.0}[kind])
	var enemy: BattleUnit=existing if living(existing) else spawn_precision_enemy(role,OPEN+Vector3(0,0,distance))
	var source: BattleUnit=squad.members[0]
	var ids: Array[int]=[int(squad.id)]
	check(game.squads.select_ids(ids)==ids and bool(game.squads.command_attack(enemy).ok),"公开指定真实敌人启动原武器 "+kind)
	source.attack_timer=0.0
	var before: float=enemy.hp
	var before_events: int=wounds.size()
	weapon_step(.001)
	check(source.attack_queued and source.attack_windup>0.0,"实际生产前摇已开始 "+kind)
	var windup: float=source.windup_duration
	near(source.attack_windup,windup,"启动帧不偷扣完整准备 "+kind)
	weapon_step(windup-.001)
	near(enemy.hp,before,"完整武器前摇结束前不能提前实伤 "+kind)
	weapon_step(.002)
	if kind=="artillery":
		near(enemy.hp,before,"炮手准备结束只发弹，不提前落地")
		weapon_step(.799)
		near(enemy.hp,before,"完整0.8秒飞行前不得产生炮伤")
		weapon_step(.002)
	var actual:=0.0
	for index in range(before_events,wounds.size()):
		var row: Dictionary=wounds[index]
		if int(row.token)==enemy.get_instance_id() and int(row.source)==source.get_instance_id(): actual+=float(row.hp_loss)+float(row.shield_loss)
	check(actual>0.0,"真实武器必须产生对应Actor来源的确认伤害 "+kind)
	var receipt: Dictionary={"kind":kind,"source":source.get_instance_id(),"target":enemy.get_instance_id(),
		"actual":actual,"hp_damage":before-enemy.hp,"windup":windup,"damage":source.damage,"rank":int(member_state(source).get("rank",-1))}
	(evidence.weapon_results as Array).append(receipt)
	return {"source":source,"enemy":enemy,"receipt":receipt}

func weapon_kill(squad: Dictionary, enemy: BattleUnit) -> bool:
	var source: BattleUnit=squad.members[0]
	var token:=enemy.get_instance_id()
	freeze_troop_attacks(); source.attack_timer=0.0
	for frame in 2000:
		if not living(enemy): break
		weapon_step(.05)
		if not living(enemy): break
		if frame%100==99: await process_frame
	var actual:=deaths.any(func(row: Dictionary) -> bool: return int(row.token)==token and float(row.hp)==0.0 and not bool(row.alive))
	check(actual,"真实生产武器经过完整前摇与冷却击杀目标")
	return actual

func production() -> void:
	if not await fresh(): return
	if await build_gui("barracks")<0: return
	var ranged: Dictionary=await train_gui("ranged")
	var shield: Dictionary=await train_gui("shield")
	if ranged.is_empty() or shield.is_empty(): return
	for squad: Dictionary in [ranged,shield]:
		for value: Variant in squad.members:
			var state: Dictionary=member_state(value)
			check(not state.is_empty() and int(state.rank)==0 and float(state.xp)==0.0 and String(state.rank_label)=="新兵","真实完整训练交付三名零经验新兵")
	var fired: Dictionary=await one_hit(ranged)
	var source: BattleUnit=fired.source
	var enemy: BattleUnit=fired.enemy
	var original: float=enemy.max_hp
	near(member_xp(source),0.0,"活敌已受真伤但没有真实死亡时不提前升级")
	if not await weapon_kill(ranged,enemy): return
	near(member_xp(source),original,"原完整真实生命由本员武器击杀后只结一次贡献")
	game.squads.veterancy.on_enemy_defeated(enemy)
	near(member_xp(source),original,"重复真实死亡入口不重复派经验")
	await clear_hostiles()
	if await build_gui("workshop")<0 or await build_gui("depot")<0 or await build_gui("infirmary")<0: return
	for kind: String in ["hauler","medic"]:
		var support: Dictionary=await train_gui(kind)
		if support.is_empty(): return
		for value: Variant in support.members:
			check(member_state(value).is_empty(),"零攻击支援成员不伪造杀敌成长 "+kind)
	stage_finished=true

func contribution() -> void:
	if not await fresh(): return
	if await build_gui("barracks")<0: return
	var first: Dictionary=await train_gui("ranged")
	var second: Dictionary=await train_gui("ranged")
	if first.is_empty() or second.is_empty(): return
	var first_hit: Dictionary=await one_hit(first)
	var enemy: BattleUnit=first_hit.enemy
	var a: BattleUnit=first_hit.source
	var b: BattleUnit=second.members[0]
	await one_hit(second,"basic",enemy)
	near(member_xp(a),0.0,"第一参与者未等真实死亡不会拿经验")
	near(member_xp(b),0.0,"第二参与者未等真实死亡不会拿经验")
	var original: float=enemy.max_hp
	if not await weapon_kill(second,enemy): return
	near(member_xp(a),16.0,"非尾刀成员按此前真实HP贡献获经验")
	near(member_xp(b),original-16.0,"尾刀者只获得自己真实剩余HP贡献，不抢整敌经验")
	near(member_xp(a)+member_xp(b),original,"真实多人武器总经验等于原敌HP，无溢伤")
	await clear_hostiles()
	var before: float=member_xp(a)
	enemy=spawn_precision_enemy()
	enemy.armor=60.0; enemy.shield=10.0; enemy.shield_time=100.0
	await one_hit(first,"basic",enemy)
	near(enemy.hp,enemy.max_hp,"60甲后的10实伤先被真实盾完整吸收")
	near(member_xp(a),before,"盾吸收不计HP贡献")
	await one_hit(first,"basic",enemy)
	near(member_xp(a),before,"真实HP损耗仍等待真死")
	enemy.hurt(100000.0,game.hero)
	near(member_xp(a),before+10.0,"护甲与护盾后的实际10HP才结算，英雄尾刀不抢贡献")
	await clear_hostiles()
	before=member_xp(a)
	enemy=spawn_precision_enemy()
	enemy.damage_confirmed.emit(enemy,a,50.0,0.0)
	game.squads.veterancy.on_enemy_defeated(enemy)
	near(member_xp(a),before,"未真实扣HP的伪信号与活敌假死回调不记经验")
	enemy.hurt(100000.0,game.hero)
	near(member_xp(a),before,"伪损伤不能在随后真死时兑现")
	await clear_hostiles()
	before=member_xp(a)
	enemy=spawn_precision_enemy()
	var budget: float=enemy.hp
	enemy.hurt(80.0,a)
	enemy.hp=enemy.max_hp # Explicit healing fixture; never a natural route.
	enemy.hurt(80.0,a)
	enemy.hp=enemy.max_hp
	enemy.hurt(100000.0,a)
	near(member_xp(a),minf(900.0,before+budget),"同一原敌治疗后重复伤害仍封原登记HP预算")
	await clear_hostiles()
	before=member_xp(b)
	var stranger:=BattleUnit.new()
	game.squads.add_child(stranger); stranger.setup("minion",0)
	stranger.set_meta("outpost_squad",true); stranger.set_meta("squad_kind","ranged")
	enemy=spawn_precision_enemy()
	enemy.hurt(40.0,stranger)
	enemy.hurt(100000.0,game.hero)
	near(member_xp(b),before,"陌生友军Actor和复制metadata不取得真实成员经验")
	check(member_state(stranger).is_empty(),"陌生友军没有公开逐员成长状态")
	stranger.queue_free()
	await clear_hostiles()
	var summoner: BattleUnit=spawn_precision_enemy("summoner",Vector3(0,0,Layout.RAMP_END+5.0))
	var module: Node3D=null
	for value: Variant in game.summoners:
		if is_instance_valid(value) and value.get("host")==summoner: module=value
	check(module!=null,"真实召潮源有对应生产控制器")
	if module==null: return
	module.advance(.001); module.advance(2.401)
	var reinforcement: BattleUnit=null
	for value: Variant in game.enemies:
		if living(value) and bool(value.get_meta("summoned_reinforcement",false)): reinforcement=value
	check(reinforcement!=null,"完整真实召潮引导产生有限援军")
	if reinforcement==null: return
	before=member_xp(b)
	reinforcement.hurt(100000.0,b)
	near(member_xp(b),before,"真实召援死亡不扩张老兵经验预算")
	stage_finished=true

func promotion() -> void:
	if not await fresh(): return
	if await build_gui("barracks")<0: return
	var squad: Dictionary=await train_gui("ranged")
	if squad.is_empty(): return
	var source: BattleUnit=squad.members[0]
	station(squad,[OPEN,OPEN+Vector3(0,0,-24),OPEN+Vector3(0,0,-28)])
	source.hurt(17.0,game.hero)
	var hp: float=source.hp
	var base_max: float=source.max_hp
	var speed: float=source.speed
	var range_value: float=source.attack_range
	var interval: float=source.attack_interval
	var windup: float=source.windup_duration
	source.attack_timer=3.7
	if not await fixture_earn(source,299.0): return
	check(int(member_state(source).rank)==0,"299点仍为新兵")
	if not await fixture_earn(source,300.0): return
	check(int(member_state(source).rank)==1 and String(member_state(source).rank_label)=="老兵","300点真实死亡贡献晋级老兵")
	near(source.damage,17.6,"老兵基础攻击总倍率1.10")
	near(source.max_hp,base_max*1.1,"老兵容量叠真实原兵营倍率")
	near(source.hp,hp,"晋级容量不提供任何免费恢复")
	near(source.attack_timer,3.7,"晋级不刷新原实际冷却")
	if not await fixture_earn(source,899.0): return
	check(int(member_state(source).rank)==1,"899点仍为老兵")
	if not await fixture_earn(source,900.0): return
	check(int(member_state(source).rank)==2 and String(member_state(source).rank_label)=="精锐","900点晋级精锐")
	near(source.damage,19.2,"精锐倍率1.20不是两档相乘")
	near(source.max_hp,base_max*1.2,"精锐容量总倍率1.20")
	near(source.hp,hp,"第二次晋级仍保原绝对生命")
	near(source.speed,speed,"老兵不改变移动速度")
	near(source.attack_range,range_value,"老兵不改变射程")
	near(source.attack_interval,interval,"老兵不改变攻击间隔")
	near(source.windup_duration,windup,"老兵不改变前摇")
	var extra: BattleUnit=spawn_precision_enemy()
	extra.hurt(100000.0,source)
	near(member_xp(source),900.0,"满级经验严格封顶900")
	near(source.damage,19.2,"重复死亡不叠乘攻击")
	var first_state: Dictionary=game.squads.veterancy.snapshot()
	var wallet: int=game.scrap
	for _read in 40: game.squads.veterancy.snapshot(); member_state(source); game.squads.snapshot()
	check(first_state==game.squads.veterancy.snapshot() and game.scrap==wallet,"HUD纯读不清理/结算/付款/改变成长状态")
	stage_finished=true

func weapons() -> void:
	if not await fresh(): return
	for kind: String in ["barracks","workshop","laboratory","armory"]:
		if await build_gui(kind)<0: return
	for kind: String in COMBAT_KINDS:
		var squad: Dictionary=await train_gui(kind)
		if squad.is_empty(): return
		var source: BattleUnit=squad.members[0]
		if not await fixture_earn(source,900.0): return
		var role: String="lobber" if kind=="hunter" else "basic"
		var actual: Dictionary=await one_hit(squad,role)
		var expected: float=float(BASE_DAMAGE[kind])*1.2+(18.0 if kind=="hunter" else 0.0)
		near(float(actual.receipt.actual),expected,"八兵种真实前摇后使用晋级基础攻击 "+kind)
		near(source.max_hp,float(Catalog.troop(kind).hp)*game.squads.health_multiplier*1.2,"八兵种实际容量保兵营与精锐叠加 "+kind)
		if kind=="netter":
			check(game.specializations.net_remaining(actual.enemy)>0.0,"晋级投网仍产生原真实控制")
			near(float(game.specializations.net_remaining(actual.enemy)),2.0,"晋级不放大原两秒网寿命")
		await clear_hostiles()
	if not await stamped_attacks(): return
	stage_finished=true

func stamped_attacks() -> bool:
	if not await fresh(): return false
	for kind: String in ["barracks","workshop","laboratory","armory"]:
		if await build_gui(kind)<0: return false
	var cannon: Dictionary=await train_gui("artillery")
	var flamer: Dictionary=await train_gui("flamer")
	if cannon.is_empty() or flamer.is_empty(): return false
	var source: BattleUnit=cannon.members[0]
	if not await fixture_earn(source,299.0): return false
	station(cannon,[OPEN,OPEN+Vector3(0,0,-24),OPEN+Vector3(0,0,-28)])
	var enemy: BattleUnit=spawn_precision_enemy("basic",OPEN+Vector3(0,0,10))
	var ids: Array[int]=[int(cannon.id)]
	game.squads.select_ids(ids); check(bool(game.squads.command_attack(enemy).ok),"原炮手公开攻击开始完整准备")
	source.attack_timer=0.0
	weapon_step(.001); weapon_step(1.001)
	var before: float=enemy.hp
	check(not game.squads.artillery.snapshot().shots.is_empty(),"真实准备完成后有已发炮弹盖章")
	if not await fixture_earn(source,300.0): return false
	near(source.damage,35.2,"原炮弹飞行中真实晋级改变后续基础攻击")
	weapon_step(.801)
	near(before-enemy.hp,32.0,"已盖章原炮弹落地仍为32伤")
	await clear_hostiles()
	freeze_troop_attacks()
	source=flamer.members[0]
	if not await fixture_earn(source,299.0): return false
	station(flamer,[OPEN,OPEN+Vector3(0,0,-24),OPEN+Vector3(0,0,-28)])
	var first: BattleUnit=spawn_precision_enemy("basic",OPEN+Vector3(0,0,3.8))
	var next: BattleUnit=spawn_precision_enemy("basic",OPEN+Vector3(0,0,4.5))
	first.hurt(first.hp-1.0,game.hero) # Explicit precision HP preparation.
	ids=[int(flamer.id)]
	game.squads.select_ids(ids); check(bool(game.squads.command_attack(first).ok),"原喷火公开命令形成两名真实圈内目标")
	source.attack_timer=0.0; before=next.hp
	weapon_step(.001); weapon_step(.551)
	check(not first.alive and int(member_state(source).rank)==1,"首个真实火焰受害者死亡贡献1点触发晋级")
	near(before-next.hp,22.0,"同次喷火已盖章伤害不因首个受害者晋级改变后续目标")
	near(source.damage,24.2,"晋级仅改变下一次喷火的基础伤害")
	return true

func health() -> void:
	if not await fresh(): return
	var barracks:=await build_gui("barracks")
	if barracks<0: return
	var squad: Dictionary=await train_gui("ranged")
	if squad.is_empty(): return
	var source: BattleUnit=squad.members[0]
	var base: float=Catalog.troop("ranged").hp
	near(source.max_hp,base*1.2,"一级真实兵营原容量倍率1.2")
	source.hurt(20.0,game.hero)
	var hp: float=source.hp
	if not await fixture_earn(source,900.0): return
	near(source.hp,hp,"准备精锐不免费治疗受伤员")
	near(source.max_hp,base*1.2*1.2,"精锐容量与一级兵营相乘")
	var ratio: float=source.hp/source.max_hp
	var wallet: int=game.scrap
	check(bool(game.districts.upgrade(barracks).ok) and game.scrap==wallet-80,"真实兵营升级付款80")
	game.squads.set_health_multiplier(game.districts.squad_health_multiplier())
	near(source.max_hp,base*1.4*1.2,"二级兵营容量保精锐倍率")
	near(source.hp/source.max_hp,ratio,"建筑倍率沿原比例更新生命，区别于晋级绝对生命规则")
	near(member_xp(source),900.0,"真实兵营升级不重置经验")
	var rebuild_point: Vector3=game.districts.plots[barracks].position
	check(bool(game.districts.damage(barracks,100000.0).destroyed),"精度真实伤害毁坏原兵营")
	game.squads.set_health_multiplier(game.districts.squad_health_multiplier())
	near(source.max_hp,base*1.2,"兵营全毁只撤建筑倍率，不撤精锐倍率")
	near(source.hp/source.max_hp,ratio,"毁坏仍沿原比例生命规则")
	near(member_xp(source),900.0,"建筑毁坏不删除幸存原员经验")
	if await build_gui("barracks",rebuild_point)<0: return
	game.squads.set_health_multiplier(game.districts.squad_health_multiplier())
	near(source.max_hp,base*1.2*1.2,"同址真实付费新兵营恢复建筑倍率")
	if not await day_fixture(): return
	var fee: int=game.squads.refill_cost()
	wallet=game.scrap
	check(fee>0,"容量晋级仍需真实付费恢复")
	await press(KEY_L)
	check(game.scrap==wallet-fee,"真实L休整只付原伤势费用")
	near(source.hp,source.max_hp,"付费休整恢复真实精锐容量")
	near(member_xp(source),900.0,"付费治疗原员保精锐经验")
	var token:=source.get_instance_id()
	source.hurt(100000.0,game.hero)
	check(squad.members[0]==null and member_state(source).is_empty(),"真死亡立即清原槽及原员成长身份")
	wallet=game.scrap; fee=game.squads.refill_cost()
	check(fee==26,"真实弩手死亡补员原26零件")
	await press(KEY_L)
	var replacement: Variant=squad.members[0]
	check(living(replacement) and replacement.get_instance_id()!=token and game.scrap==wallet-26,"L实际付款并交付同槽新Actor")
	if not living(replacement): return
	near(member_xp(replacement),0.0,"同槽新弩手不继承旧900经验")
	near(replacement.damage,16.0,"补员基础攻击重新从新兵开始")
	near(replacement.max_hp,base*1.2,"补员保真实兵营倍率但不继承旧精锐容量")
	(evidence.precision_results as Array).append({"kind":"barracks-health-paid-refill","old_token":token,
		"new_token":replacement.get_instance_id(),"new_xp":member_xp(replacement),"paid":26})
	stage_finished=true

func nested_damage(victim: BattleUnit, _source: BattleUnit, other: BattleUnit, amount: float, marker: String) -> void:
	var key: String="%d:%s" % [victim.get_instance_id(),marker]
	if reentry.has(key): return
	reentry[key]=true
	victim.hurt(amount,other)

func kill_refill_reentry(_victim: BattleUnit, _source: BattleUnit, member: BattleUnit, squad_id: int) -> void:
	var token:=member.get_instance_id()
	member.hurt(100000.0,game.hero)
	var before: int=game.scrap
	var receipt: Dictionary=game.squads.refill(squad_id)
	reentry["real_refill"]={"old_token":token,"paid":before-game.scrap,"ok":bool(receipt.ok),
		"new_token":game.squads.squads[squad_id].members[0].get_instance_id()}

func end_reentry(_victim: BattleUnit, _source: BattleUnit, _hp_loss: float, _shield_loss: float) -> void:
	game.end_defeat("精度确认伤害中同步真结束")

func identity() -> void:
	if not await fresh(): return
	if await build_gui("barracks")<0: return
	var first: Dictionary=await train_gui("ranged")
	var second: Dictionary=await train_gui("ranged")
	if first.is_empty() or second.is_empty(): return
	var a: BattleUnit=first.members[0]
	var b: BattleUnit=second.members[0]
	var enemy: BattleUnit=spawn_precision_enemy()
	enemy.hurt(12.0,a)
	var original: Dictionary=game.squads.squads[int(first.id)]
	game.squads.squads[int(first.id)]=original.duplicate(false)
	check(member_state(a).is_empty(),"同id同成员但新Dictionary不能冒充原编组")
	enemy.hurt(100000.0,game.hero)
	game.squads.squads[int(first.id)]=original
	near(member_xp(a),0.0,"身份失效时拒绝旧贡献，恢复原编组不得补兑现")
	await clear_hostiles()
	enemy=spawn_precision_enemy()
	enemy.hurt(10.0,a)
	game.enemies.erase(enemy)
	game.squads.veterancy.observe_enemies()
	game.enemies.append(enemy)
	enemy.hurt(100000.0,a)
	near(member_xp(a),0.0,"同原敌移出名单后重新插回仍不兑现退休贡献")
	await clear_hostiles()
	# Controlled synchronous damaged reentry after the real factory registration.
	# No claim is made about arbitrary earlier damage_confirmed listener order.
	enemy=spawn_precision_enemy()
	var original_hp: float=enemy.hp
	var callback:=nested_damage.bind(b,0.0,"zero")
	enemy.damaged.connect(callback)
	enemy.hurt(100000.0,a)
	near(member_xp(a),original_hp,"damaged内另一真员零伤嵌套不挡原A真实致死确认与贡献")
	near(member_xp(b),0.0,"嵌套0伤B无damage_confirmed，不领取A经验")
	await clear_hostiles()
	enemy=spawn_precision_enemy()
	var before_a: float=member_xp(a)
	callback=nested_damage.bind(b,10.0,"actual")
	enemy.damaged.connect(callback)
	enemy.hurt(20.0,a)
	enemy.hurt(100000.0,game.hero)
	near(member_xp(a),before_a+20.0,"真实嵌套伤害按A外层自身20生命损耗结算")
	near(member_xp(b),10.0,"真实嵌套伤害按B内层自身10生命损耗结算")
	if not await day_fixture(): return
	enemy=spawn_precision_enemy()
	enemy.hurt(12.0,a)
	callback=kill_refill_reentry.bind(a,int(first.id))
	enemy.damaged.connect(callback,CONNECT_ONE_SHOT)
	enemy.hurt(100000.0,a)
	check(reentry.has("real_refill") and bool(reentry.real_refill.ok) and int(reentry.real_refill.paid)==26,"敌damaged内真死原参与员并真实付费补同槽")
	var successor: Variant=first.members[0]
	check(living(successor) and successor.get_instance_id()==int(reentry.real_refill.new_token),"同步补员仍是新Actor原槽身份")
	if not living(successor): return
	near(member_xp(successor),0.0,"旧贡献和外层致死源不转给同步补员")
	(evidence.precision_results as Array).append(reentry.real_refill.duplicate(true))
	await clear_hostiles()
	enemy=spawn_precision_enemy()
	enemy.damage_confirmed.connect(end_reentry,CONNECT_ONE_SHOT)
	enemy.hurt(100000.0,successor)
	check(game.phase=="ended" and game.squads.squads.is_empty() and int(game.squads.veterancy.snapshot().alive)==0,"真结束同步清原局来源及尚未死亡结算，不感染随后场景")
	if not await dead_shell_identity(): return
	stage_finished=true

func dead_shell_identity() -> bool:
	if not await fresh(): return false
	for kind: String in ["barracks","workshop","laboratory","armory"]:
		if await build_gui(kind)<0: return false
	var squad: Dictionary=await train_gui("artillery")
	if squad.is_empty() or not await day_fixture(): return false
	freeze_troop_attacks()
	station(squad,[OPEN,OPEN+Vector3(0,0,-24),OPEN+Vector3(0,0,-28)])
	var source: BattleUnit=squad.members[0]
	var source_token:=source.get_instance_id()
	var enemy: BattleUnit=spawn_precision_enemy("basic",OPEN+Vector3(0,0,10))
	var enemy_token:=enemy.get_instance_id()
	enemy.hurt(enemy.hp-16.0,game.hero)
	var ids: Array[int]=[int(squad.id)]
	game.squads.select_ids(ids); check(bool(game.squads.command_attack(enemy).ok),"真实白昼炮手公开命令准备炮弹")
	source.attack_timer=0.0
	weapon_step(.001); weapon_step(1.001)
	check(not game.squads.artillery.snapshot().shots.is_empty(),"完整准备后有原盖章炮弹")
	source.hurt(100000.0,game.hero)
	check(squad.members[0]==null,"原发弹炮手真死亡释放槽位")
	var before: int=game.scrap
	await press(KEY_L)
	var successor: Variant=squad.members[0]
	check(living(successor) and successor.get_instance_id()!=source_token and game.scrap==before-36,"炮弹飞行中L真付款36创建同槽新炮手")
	if not living(successor): return false
	weapon_step(.801)
	check(deaths.any(func(row: Dictionary) -> bool: return int(row.token)==enemy_token and float(row.hp)==0.0),"已发原炮弹完整飞行后真实击杀16生命目标")
	near(member_xp(successor),0.0,"死亡源旧炮弹不把生命贡献转移给同槽新员")
	(evidence.precision_results as Array).append({"kind":"dead-artillery-source","old":source_token,
		"new":successor.get_instance_id(),"target":enemy_token,"paid":36,"new_xp":member_xp(successor)})
	return true

func lifecycle() -> void:
	if not await fresh(): return
	if await build_gui("barracks")<0: return
	var squad: Dictionary=await train_gui("ranged")
	if squad.is_empty(): return
	var source: BattleUnit=squad.members[0]
	if not await fixture_earn(source,300.0): return
	station(squad,[OPEN,OPEN+Vector3(0,0,-24),OPEN+Vector3(0,0,-28)])
	var enemy: BattleUnit=spawn_precision_enemy("basic",OPEN+Vector3(0,0,13))
	enemy.hurt(40.0,source)
	observe()
	var before: Dictionary=game.squads.veterancy.snapshot()
	var hp: float=enemy.hp
	await press(KEY_ESCAPE)
	check(game.phase=="paused","真实Esc暂停老兵局")
	game.simulate(10.0); game.squads.advance(10.0)
	check(before==game.squads.veterancy.snapshot(),"暂停冻结经验和待结算贡献")
	near(enemy.hp,hp,"暂停保真实活敌生命")
	await capture_all("paused-original-veteran",OPEN)
	await press(KEY_ESCAPE)
	game.run.grant("精度待选卡冻结验证"); game.open_draft()
	check(game.phase=="draft","真实生产待选卡入口")
	game.simulate(10.0); game.squads.advance(10.0)
	check(before==game.squads.veterancy.snapshot(),"选卡冻结经验和待结算来源")
	await press(KEY_1)
	check(game.phase=="night","真实选卡恢复原夜")
	near(member_xp(source),300.0,"选卡不清已有老兵经验")
	game.phase_time=.01; game.wave_index=game.WAVES_PER_NIGHT
	step(.02)
	check(game.phase=="night" and game.night_clearance_active and living(enemy),"精度原截止入口进入真实清场，保原活敌")
	near(member_xp(source),300.0,"清场开始不提前结贡献或清成长")
	game.finish_night()
	check(game.phase=="night","存在真实残敌时拒绝提前黎明")
	await capture_all("clearance-pending-contribution",OPEN)
	enemy.hurt(100000.0,game.hero)
	near(member_xp(source),340.0,"跨截止原贡献只在真实死亡后结40一次")
	step(.05)
	check(game.phase=="draft","真实清完残敌后进入黎明卡")
	await press(KEY_1)
	check(game.phase=="day" and game.phase_time==90.0,"原真实黎明完整90秒白昼")
	near(member_xp(source),340.0,"真实日夜钩子不清幸存者成长")
	await clear_hostiles()
	game.phase_time=.01
	step(.02)
	check(game.phase=="night" and game.day_number==2,"精度推进真实日落入口")
	near(member_xp(source),340.0,"下一真实夜晚仍保原Actor成长")
	var old_scene:=game.get_instance_id()
	game.end_defeat("精度真实败局清局与重试")
	check(game.phase=="ended" and int(game.squads.veterancy.snapshot().alive)==0 and float(game.squads.veterancy.snapshot().xp_total)==0.0,"结束清局内经验，不写成免费新局继承")
	await press(KEY_ENTER)
	for _frame in 200:
		if current_scene!=null and current_scene.get_instance_id()!=old_scene: break
		await create_timer(.02,true,false,true).timeout
	check(current_scene!=null and current_scene.get_instance_id()!=old_scene,"真实Enter重试换场景")
	if current_scene==null or current_scene.get_instance_id()==old_scene: return
	game=current_scene as Node3D
	game.set_process(false); game.world.set_process(false)
	check(game.archive.path==profile_path and game.phase=="draft" and game.scrap==90,"真实重试仍注入私有档案，保原90开局")
	check(game.squads.squads.is_empty() and int(game.squads.veterancy.snapshot().alive)==0 and float(game.squads.veterancy.snapshot().xp_total)==0.0,"真实新场景没有旧同id槽位或经验污染")
	stage_finished=true

func quiet_hud() -> void:
	game.notice_time=0.0; game.reward_toasts.clear(); game.beacon_alarm_time=0.0
	game.hero_damage_flash_time=0.0; game.combat_milestone_time=0.0
	game.kill_chain=0; game.kill_chain_time=0.0
	game.combat.clear_transients()
	game.squads.cancel_selection(); game.hud.dismiss_details()
	game.hud.queue_redraw()

func capture(tag: String, focus: Vector3) -> void:
	if not render_test or DisplayServer.get_name()=="headless": return
	camera_at(focus)
	for _frame in 3:
		await process_frame; await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	var pixels:=root.content_scale_size
	check(image.get_size()==pixels and Vector2(pixels)==game.hud.get_viewport_rect().size,"真实PNG与HUD均为请求内容像素")
	check(valid_output(output_dir),"每次写证据前核对物理固定路径")
	check(DirAccess.make_dir_recursive_absolute(output_dir)==OK,"固定本地证据目录")
	var path:=output_dir.path_join("%s-%dx%d.png" % [tag,pixels.x,pixels.y])
	check(image.save_png(path)==OK,"真实渲染写完整PNG")
	(evidence.captures as Array).append({"path":path,"sha256":FileAccess.get_sha256(path),"width":pixels.x,"height":pixels.y,"stage":stage})

func capture_all(tag: String, focus: Vector3) -> void:
	for viewport: Vector2i in VIEWS:
		root.size=viewport; root.content_scale_size=viewport
		game.hud.queue_redraw(); await frames()
		await capture(tag,focus)
	root.size=VIEWS[0]; root.content_scale_size=VIEWS[0]

func stable_rects() -> Array[Rect2]:
	var result: Array[Rect2]=game.hud.live_panel_rects().duplicate()
	result.erase(CleanHud.objective_rect(game.hud,game))
	return result

func drawn_text() -> String:
	var result:=""
	for row: Dictionary in game.hud.get("veterancy_labels"): result+=String(row.text)+"\n"
	return result

func hud() -> void:
	if not await fresh(): return
	if await build_gui("barracks")<0: return
	var first: Dictionary=await train_gui("ranged")
	var second: Dictionary=await train_gui("shield")
	if first.is_empty() or second.is_empty(): return
	station(first,[OPEN,OPEN+Vector3(2.0,0,0),OPEN+Vector3(-2.0,0,0)])
	station(second,[OPEN+Vector3(4,0,0),OPEN+Vector3(6,0,0),OPEN+Vector3(8,0,0)])
	quiet_hud(); camera_at(OPEN); await frames()
	var original:=stable_rects()
	check(not drawn_text().contains("老兵") and not drawn_text().contains("精锐"),"未选新兵默认画面没有成长文字堆叠")
	if not await fixture_earn(first.members[0],300.0): return
	if not await fixture_earn(first.members[1],900.0): return
	if not await fixture_earn(second.members[0],300.0): return
	if not await fixture_earn(second.members[1],300.0): return
	quiet_hud(); await frames()
	check(stable_rects()==original,"实际成长后未选默认常驻矩形逐项不变，目标动态矩形单独排除")
	check(not drawn_text().contains("老兵") and not drawn_text().contains("精锐"),"未选晋级员仍不绘制世界成长标签")
	await capture_all("default-clean-unselected-growth",OPEN)
	var ids: Array[int]=[int(first.id)]
	for viewport: Vector2i in VIEWS:
		root.size=viewport; root.content_scale_size=viewport
		quiet_hud(); game.squads.select_ids(ids); camera_at(OPEN); await frames()
		var world_labels: Array[Dictionary]=[]
		for row: Dictionary in game.hud.get("veterancy_labels"):
			if String(row.text) in ["老兵","精锐"]: world_labels.append(row)
		check(world_labels.size()==2,"单选只绘两名实际晋级员，第三新兵无标签")
		for row: Dictionary in world_labels:
			var footprint:=Rect2((row.point as Vector2)-Vector2(3,float(row.ascent)),Vector2(float(row.width)+6,float(row.ascent)+float(row.descent)))
			check(footprint.position.x>=0 and footprint.end.x<=1440 and footprint.position.y>=0 and footprint.end.y<=900,"世界成长中文实际字形留在请求视口")
		await capture("selected-world-two-ranks",OPEN)
		await press(KEY_F3); await click_ui(game.hud.details_tab_rect(2))
		check(game.hud.detail_tab=="army" and game.hud.troop_page==0,"真实F3部队首页成长入口")
		await frames()
		var actual:=drawn_text()
		for phrase: String in ["300老兵 / 900精锐","晋级不回血","补员为新兵","1老兵300/900","2精锐900","3新兵0/300","无需尾刀"]:
			check(actual.contains(phrase),"实际中文说明与逐员进度完整绘制: "+phrase)
		for row: Dictionary in game.hud.get("veterancy_labels"):
			var point: Vector2=row.point
			if point.x==46.0 and point.y>=553.0 and point.y<=681.0:
				check(float(row.width)<=496.0 and point.y+float(row.descent)<CleanHud.DRAWER_RECT.end.y,"新增成长行实际字形在原抽屉及关闭按钮边界内")
		await capture("f3-squad-member-growth",OPEN)
		var mixed: Array[int]=[int(first.id),int(second.id)]
		game.squads.select_ids(mixed); game.hud.queue_redraw(); await frames()
		check(drawn_text().contains("队%d：" % (int(first.id)+1)) and not drawn_text().contains("队%d：" % (int(second.id)+1)),"混选只披露首个实际选中队，不混三员来源")
		await capture("f3-mixed-selection-growth",OPEN)
		await click_ui(game.hud.troop_page_rect(1)); await frames()
		check(game.hud.troop_page==1 and not drawn_text().contains("成长：真击杀"),"真实翻页保原兵种详情且成长说明仅放首页")
		await click_ui(game.hud.troop_page_rect(-1)); await press(KEY_F3)
		game.squads.cancel_selection(); game.hud.queue_redraw(); await frames()
		check(stable_rects()==original,"关闭F3取消选择后默认矩形精确恢复")
		game.squads.select_ids(mixed); game.hud.queue_redraw(); await frames()
		var ranked_count:=0
		for row: Dictionary in game.hud.get("veterancy_labels"):
			if String(row.text) in ["老兵","精锐"]: ranked_count+=1
		check(ranked_count<=game.hud.MAX_RENDERED_WORLD_LABELS and ranked_count==3,"四名选中晋级员沿原世界标签三条上限")
		await capture("selected-growth-label-cap",OPEN)
		await press(KEY_Y); await frames()
		check(game.construction.active,"真实建设隐藏成长标签验证")
		for row: Dictionary in game.hud.get("veterancy_labels"):
			check(String(row.text) not in ["老兵","精锐"],"建设预览不堆世界成长标签")
		await capture("construction-hides-growth",OPEN)
		await press(KEY_ESCAPE); quiet_hud(); await frames()
		check(stable_rects()==original,"收建设再清选择后默认区域恢复")
	root.size=VIEWS[0]; root.content_scale_size=VIEWS[0]
	# A real missing slot has no invented progress row; no removal fixture is used.
	first.members[2].hurt(100000.0,game.hero)
	game.squads.select_ids(ids)
	await press(KEY_F3); await click_ui(game.hud.details_tab_rect(2)); await frames()
	check(not drawn_text().contains("3新兵0/300") and drawn_text().contains("1老兵300/900"),"真死亡空槽不借其他员身份绘成长")
	await capture_all("f3-real-casualty-slot",OPEN)
	await press(KEY_F3); quiet_hud()
	if not await day_fixture(): return
	quiet_hud(); await capture_all("default-clean-day-growth",Vector3(0,5,8))
	stage_finished=true

func natural_policy() -> void:
	game.aim=game.hero.position+Vector3(0,0,8)
	if game.gate_pressure()>0: game.cast(0)
	if game.hero.hp<game.hero.max_hp*.6: game.cast(1); game.cast(4)
	if game.gate_pressure()>=6: game.cast(3)
	step(.1)

func natural_receipts() -> Dictionary:
	var credits: Dictionary={}
	var rows: Array[Dictionary]=[]
	var summons:=0
	for death: Dictionary in deaths:
		var token:=int(death.token)
		var birth: Dictionary={}
		for born: Dictionary in births:
			if int(born.token)==token: birth=born; break
		if birth.is_empty() or String(birth.kind)!="monster": continue
		check(float(death.hp)==0.0 and not bool(death.alive),"自然来源仅采用真实hp0死亡回执")
		if bool(birth.reinforcement): summons+=1; continue
		var budget: float=minf(float(birth.hp),float(birth.max_hp))
		var used:=0.0
		var contributions: Dictionary={}
		for wound: Dictionary in wounds:
			if int(wound.token)!=token: continue
			var share: float=minf(float(wound.hp_loss),maxf(0.0,budget-used))
			used+=share
			if int(wound.source) not in death.eligible_members or share<=0.0: continue
			var source:=int(wound.source)
			contributions[source]=float(contributions.get(source,0.0))+share
			credits[source]=float(credits.get(source,0.0))+share
		rows.append({"enemy":token,"budget":budget,"used":used,"contributions":contributions,
			"real_death_at":death.at,"eligible_at_real_death":death.eligible_members})
	var promoted:=false
	var gained:=false
	for actual: Dictionary in growth:
		var experience:=float(actual.xp)
		var token:=int(actual.source_token)
		check(experience>=0.0 and experience<=900.0,"自然逐员经验保持原900上限")
		check(experience<=minf(900.0,float(credits.get(token,0.0)))+.001,"自然实际成长有真实死敌生命贡献支持，无盾/溢伤/召援")
		if experience>0.0: gained=true
		if int(actual.rank)>=1 and experience>=300.0: promoted=true
	var current: Dictionary=game.squads.veterancy.snapshot()
	for member: Dictionary in current.members:
		near(float(member.xp),minf(900.0,float(credits.get(int(member.source_token),0.0))),"自然末存活原员实际经验匹配真实生命贡献账本")
	return {"real_death_contributions":rows,"eligible_hp_by_member":credits,"excluded_summoned_deaths":summons,
		"current_members":current.members,"natural_growth_proven":gained,"natural_promotion_proven":promoted,
		"scope":"true death and still-live original-member receipts; 300/900 is never prepared by fixtures in natural routes"}

func natural_attempt(protected: bool) -> Dictionary:
	if not await fresh(false): return {}
	var payments_start: int=(evidence.payments as Array).size()
	var result: Dictionary={"policy":"front-hero-protection" if protected else "rear-hero-exposure","seed":SEED,
		"original_parts":90,"original_night":105,"original_day":90,"supplemented_parts":false,
		"direct_actor_placement":false,"direct_enemy_damage":false,"changed_actor_attributes":false,"extended_deadline":false}
	game.plan_hero_path(Vector3(0,5,10))
	var first_seconds:=0.0
	var cutoff: Dictionary={}
	for frame in 2600:
		if game.phase!="night": break
		natural_policy(); first_seconds+=.1
		if cutoff.is_empty() and first_seconds>=105.0: cutoff=Transition.deadline_evidence(game,first_seconds)
		if frame%100==99: await process_frame
	result.first_night={"seconds":first_seconds,"phase":String(game.phase),"parts":int(game.scrap),"kills":int(game.kills),"cutoff":cutoff}
	check(game.phase=="draft" and game.hero.alive and game.beacon_hp>0.0,"原技能策略真实度过首夜才开始自然生产")
	if game.phase!="draft": result.status="opening_failed"; return result
	await press(KEY_1)
	check(game.phase=="day" and game.phase_time==90.0,"自然实际黎明保原完整90秒白昼")
	var dawn: int=game.scrap
	if dawn<210:
		result.status="actual_budget_shortfall"; result.dawn_parts=dawn
		return result
	var barracks:=await build_gui("barracks")
	var shield: Dictionary=await train_gui("shield")
	var ranged: Dictionary=await train_gui("ranged")
	check(barracks>=0 and not shield.is_empty() and not ranged.is_empty(),"自然GUI60/70/80真实生产两队，无补款")
	if shield.is_empty() or ranged.is_empty(): result.status="actual_training_failed"; return result
	check(game.scrap==dawn-210,"自然唯一钱包只支付兵营盾卫弩手三笔210")
	result.departure={"parts":int(game.scrap),"day_time":float(game.phase_time),"dawn_parts":dawn,"payments":[60,70,80]}
	var ids: Array[int]=[int(shield.id),int(ranged.id)]
	check(game.squads.select_ids(ids)==ids,"自然公开选择原真实训练小队")
	var destination:=Vector3(0,5,8.5)
	var order: Dictionary=game.squads.command_guard(destination)
	check(bool(order.ok),"自然公开移动驻守，不能直接摆部队")
	game.plan_hero_path(Vector3(0,5,10))
	for frame in 1000:
		if game.phase!="day": break
		natural_policy()
		if frame%100==99: await process_frame
	check(game.phase=="night" and game.day_number==2,"真实90秒白昼自然进入原第二夜")
	if game.phase!="night": result.status="second_night_not_reached"; return result
	var hero_destination:=Vector3(0,5,12) if protected else Vector3(0,5,4)
	game.plan_hero_path(hero_destination)
	result.public_orders=[{"kind":"guard","squads":ids,"point":vec(destination),"accepted":bool(order.ok)},
		{"kind":"hero_path","point":vec(hero_destination),"accepted_path_points":game.hero_path.size(),"at":elapsed}]
	var second_seconds:=0.0
	var second_cutoff: Dictionary={}
	for frame in 2600:
		if game.phase!="night": break
		natural_policy(); second_seconds+=.1
		if second_cutoff.is_empty() and second_seconds>=105.0: second_cutoff=Transition.deadline_evidence(game,second_seconds)
		if frame%100==99: await process_frame
	result.status="real_second_dawn" if game.phase=="draft" else ("real_defeat" if game.phase=="ended" else "bounded_real_clearance_unfinished")
	result.second_night={"seconds":second_seconds,"phase":String(game.phase),"parts":int(game.scrap),"time_left":float(game.phase_time),
		"hero_hp":game.hero.hp,"beacon_hp":game.beacon_hp,"cutoff":second_cutoff,"clearance":game.night_clearance_snapshot()}
	result.births=births.duplicate(true); result.damage=wounds.duplicate(true); result.deaths=deaths.duplicate(true)
	result.member_growth=growth.duplicate(true); result.wallet_changes=wallets.duplicate(true)
	var movement: Array[Dictionary]=[]
	for token: Variant in moves.keys():
		var row: Dictionary=moves[token].duplicate(true)
		row.erase("last"); row["token"]=token
		movement.append(row)
	result.actual_member_movement=movement
	var payments: Array[Dictionary]=[]
	for index in range(payments_start,(evidence.payments as Array).size()): payments.append(evidence.payments[index])
	result.gui_payments=payments
	result.growth_receipts=natural_receipts()
	result.natural_growth_proven=bool(result.growth_receipts.natural_growth_proven)
	result.natural_promotion_proven=bool(result.growth_receipts.natural_promotion_proven)
	await capture_all("natural-protected" if protected else "natural-exposed",Vector3(0,5,9))
	print("VETERANCY_NATURAL ",JSON.stringify(result))
	return result

func economy() -> void:
	var exposed: Dictionary=await natural_attempt(false)
	var protected: Dictionary=await natural_attempt(true)
	(evidence.natural as Array).append(exposed); (evidence.natural as Array).append(protected)
	check(not exposed.is_empty() and not protected.is_empty(),"两条自然原规则尝试保留实际结果")
	if not exposed.has("departure") or not protected.has("departure"): return
	check(exposed.first_night==protected.first_night and exposed.departure==protected.departure,"成对策略种子/原首夜/出发付款及时刻完全相同")
	if not exposed.has("gui_payments") or not protected.has("gui_payments"): return
	check(exposed.gui_payments==protected.gui_payments,"成对自然路线GUI三笔支付严格相同")
	check(exposed.births.any(func(row: Dictionary) -> bool: return int(row.night)==2 and String(row.kind)=="monster")
		and protected.births.any(func(row: Dictionary) -> bool: return int(row.night)==2 and String(row.kind)=="monster"),"两路真正观察原第二夜敌方出生，不以命令代替实战")
	evidence["natural_comparison"]={"exposed_status":exposed.status,"protected_status":protected.status,
		"exposed_growth_proven":exposed.natural_growth_proven,"protected_growth_proven":protected.natural_growth_proven,
		"exposed_promotion_proven":exposed.natural_promotion_proven,"protected_promotion_proven":protected.natural_promotion_proven,
		"scope":"fixed-seed legal original-clock routes; actual outcomes need not be victory or promotion, and do not prove player balance or native Windows delivery"}
	stage_finished=true

func finish(code: int = 0) -> void:
	if finished: return
	finished=true
	await close_game()
	for path: String in original_profile_hashes.keys():
		var now:=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
		check(now==String(original_profile_hashes[path]),"玩家原档案/备份及两配置保持原哈希")
	for suffix in ["", ".tmp", ".bak"]:
		var path: String=profile_path+suffix
		if FileAccess.file_exists(path): check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path))==OK,"只清理私有测试档案")
	if selected_case.is_empty(): check(completed==["production","contribution","promotion","weapons","health","identity","lifecycle","hud","economy"],"完整成功标记要求九段全部实际到末尾")
	evidence["partial_case"]=selected_case; evidence["full_suite"]=selected_case.is_empty()
	if valid_output(output_dir):
		check(DirAccess.make_dir_recursive_absolute(output_dir)==OK,"固定build证据目录可写")
		var file:=FileAccess.open(output_dir.path_join("result.json"),FileAccess.WRITE)
		check(file!=null,"证据JSON创建成功")
		evidence["checks"]=checks; evidence["failures"]=failures; evidence["completed"]=completed
		if file!=null: file.store_string(JSON.stringify(evidence,"\t")); file.close()
	var passed:=failures.is_empty() and code==0
	if passed and selected_case.is_empty(): print("NIGHTFALL_VETERANCY_OK checks=%d" % checks)
	elif passed: print("NIGHTFALL_VETERANCY_CASE_OK case=%s checks=%d full_suite=false" % [selected_case,checks])
	else: print("NIGHTFALL_VETERANCY_FAILED checks=%d failures=%d stage=%s" % [checks,failures.size(),stage])
	quit(0 if passed else 1)

func watchdog() -> void:
	if finished: return
	check(false,"480秒真实看门狗有界退出")
	await finish(1)

func run() -> void:
	var stages: Array[String]=["production","contribution","promotion","weapons","health","identity","lifecycle","hud","economy"]
	if not selected_case.is_empty() and selected_case not in stages:
		check(false,"--case只接受明确专项阶段"); await finish(1); return
	for name: String in stages:
		if not selected_case.is_empty() and name!=selected_case: continue
		stage=name; stage_finished=false
		print("VETERANCY_STAGE ",stage)
		match name:
			"production": await production()
			"contribution": await contribution()
			"promotion": await promotion()
			"weapons": await weapons()
			"health": await health()
			"identity": await identity()
			"lifecycle": await lifecycle()
			"hud": await hud()
			"economy": await economy()
		check(stage_finished,"阶段须真实执行末尾，提前返回或异常不假计完整")
		if stage_finished: completed.append(name)
		print("VETERANCY_STAGE_DONE ",stage," checks=",checks," failures=",failures.size())
	await finish()
