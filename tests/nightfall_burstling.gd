extends SceneTree
## 爆裂体真实生产专项。精度段显式使用5000零件、隔离冷却/站位及100000致死，
## 压缩生命周期只作规则验证；自然成对段保持原90/105/90和原演员属性。
## 不运行玩家档案、不将精度伤害/人工清场冒充自然收益或Windows交付。
const Session := preload("res://scripts/run_session.gd")
const Archive := preload("res://scripts/run_archive.gd")
const Catalog := preload("res://scripts/outpost_catalog.gd")
const Encounter := preload("res://scripts/nightfall_encounters.gd")
const CleanHud := preload("res://scripts/nightfall_clean_hud.gd")
const Burst := preload("res://scripts/nightfall_burstling.gd")
const Transition := preload("res://tests/nightfall_transition_fixture.gd")
const SEED := 20261007
const STEP := .05
const VIEWS := [Vector2i(1920,1200),Vector2i(1920,1080),Vector2i(1440,900)]
const OPEN := Vector3(20,0,30)
const BUILD_POINTS := {"barracks":Vector3(7,5,-8.5),"workshop":Vector3(-7.5,5,-8),
	"laboratory":Vector3(7,5,-3.5),"armory":Vector3(-7,5,-3)}
const OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var burstling_labels: Array[Dictionary] = []
func _draw() -> void:
	burstling_labels.clear()
	super._draw()
func label(value: String, point: Vector2, size_px: int, color: Color = Color(\"e7e1d3\"), latin: bool = false) -> void:
	var actual: Font = display_font if latin else font
	burstling_labels.append({\"text\":value,\"point\":point,\"width\":actual.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x,
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
var profile_path := "user://riftward-burstling-%d.json" % Time.get_ticks_usec()
var original_profile_hashes: Dictionary = {}
var elapsed := 0.0
var births: Array[Dictionary] = []
var wounds: Array[Dictionary] = []
var deaths: Array[Dictionary] = []
var wallets: Array[Dictionary] = []
var casts: Array[Dictionary] = []
var observed: Dictionary = {}
var previous_casts: Dictionary = {}
var moves: Dictionary = {}
var reentry: Dictionary = {}
var evidence: Dictionary = {"seed":SEED,"scope":"precision and original-clock natural routes are separate; native Windows delivery remains unverified",
	"precision":{"parts":5000,"stationed_actors":true,"isolated_cooldowns":100000,"lethal_hurt":100000,"compressed_phase_transitions":true},
	"payments":[],"plans":[],"captures":[],"natural":[],"precision_results":[]}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	render_test = "--render-test" in args
	var index := args.find("--case")
	if index >= 0 and index + 1 < args.size(): selected_case = args[index+1]
	var backend := "headless" if DisplayServer.get_name()=="headless" else ("opengl" if RenderingServer.get_current_rendering_method()=="gl_compatibility" else "metal")
	output_dir = ProjectSettings.globalize_path("res://build/burstling/"+backend).simplify_path()
	index = args.find("--output-dir")
	if index >= 0 and index+1 < args.size():
		var candidate := ProjectSettings.globalize_path(args[index+1]).simplify_path()
		if valid_output(candidate): output_dir = candidate
		else: check(false,"证据只写固定物理build/burstling及后端子目录")
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
	root.child_entered_tree.connect(inject_archive)
	create_timer(360.0,true,false,true).timeout.connect(watchdog)
	call_deferred("run")

func valid_output(candidate: String) -> bool:
	var base := ProjectSettings.globalize_path("res://build/burstling").simplify_path()
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
	if game.has_method("burstling_warning_snapshot"):
		check(game.burstling_warning_snapshot().is_empty(),"真实关闭清理爆裂危险快照")
	if current_scene==game: current_scene=null
	game.queue_free(); game=null
	await frames(4)
	await create_timer(.5,true,false,true).timeout

func clear_hostiles(keep: BattleUnit = null) -> void:
	check(precision,"仅精度段使用明确100000真实致死准备隔离")
	for raw: Variant in game.enemies.duplicate():
		if living(raw) and raw != keep: raw.hurt(100000.0,null)
	game.clear_lobbers(); game.clear_summoners(); game.clear_warders()
	if game.has_method("clear_burstlings"):
		if keep==null: game.clear_burstlings()
	if is_instance_valid(game.siege_boss):
		game.siege_boss.clear(); game.siege_boss.queue_free(); game.siege_boss=null
	game.specializations.reset_effects()
	await frames()

func fresh(is_precision: bool = true, blueprint: String = "") -> bool:
	await close_game()
	precision=is_precision; elapsed=0.0
	births.clear(); wounds.clear(); deaths.clear(); wallets.clear(); casts.clear()
	observed.clear(); previous_casts.clear(); moves.clear()
	var queued := Session.queue_request(self,SEED,"siege")
	check(queued,"真实会话消费固定铁潮四夜种子")
	if not queued: return false
	game=load("res://scenes/nightfall.tscn").instantiate() as Node3D
	root.add_child(game); current_scene=game
	await frames(5)
	game.set_process(false); game.world.set_process(false)
	check(game.archive.path==profile_path and game.phase=="draft","_ready前注入私有档案")
	check(game.run.seed_value==SEED and game.run_mode=="siege","实际会话必须消费原固定seed和真实四夜mode")
	check(game.scrap==90 and game.squads.squads.is_empty(),"原新局90零件和空部队")
	check(game.has_method("burstling_warning_snapshot"),"生产危险快照已接入")
	if not game.has_method("burstling_warning_snapshot"): return false
	await install_observer()
	game.hero.damage_confirmed.connect(record_wound)
	game.hero.defeated.connect(record_death)
	if not blueprint.is_empty():
		check(precision and blueprint=="holdfast_beacon","档案许可夹具仅用于明确精度减伤验证")
		if not precision or blueprint!="holdfast_beacon": return false
		check(game.archive.path==profile_path,"精度许可只允许固定私有档案路径")
		if game.archive.path!=profile_path: return false
		# The real scene disables archive writes on headless _ready. Enable only
		# this explicit private permission fixture, then restore that setting;
		# real selection still checks the opening phase and unlocked catalog.
		var previous_archive_enabled: bool=game.archive.enabled
		game.archive.enabled=true
		var fixture_permission: Dictionary=game.archive.record_victory({"victory":true,"ending_key":"hold","seed":SEED,"mode":"siege","day_number":4})
		game.archive.enabled=previous_archive_enabled
		var permission_ready: bool=bool(fixture_permission.get("ok",false)) and game.archive.has_blueprint(blueprint)
		check(permission_ready,"私有档案精度许可实际解锁坚守蓝图: "+String(fixture_permission.get("reason","")))
		if not permission_ready: return false
		var fixture_selected: bool=game.select_blueprint(blueprint)
		check(fixture_selected and game.selected_blueprint==blueprint and game.opening_night_pending and not game.run_mode_locked,"私有档案精度许可后真实开局选择坚守蓝图")
		if not fixture_selected or game.selected_blueprint!=blueprint: return false
		evidence["fixture_permission_scope"]="private archive permission fixture for blast mitigation only; not natural victory or player archive proof"
	await press(KEY_1)
	check(game.phase=="night" and game.phase_time==105.0,"真实开局输入启动原105秒首夜")
	if precision:
		await clear_hostiles()
		game.scrap=5000; game.phase_time=10000.0; game.wave_index=game.WAVES_PER_NIGHT
		game.pulse_timer=100000.0; game.hero.attack_timer=100000.0; game.gate_trap_charges=0
		for pad: Dictionary in game.world.tower_pads: pad.cooldown=100000.0
		stand_hero(Vector3(-11,5,-10))
	var hero_token: int=game.hero.get_instance_id()
	observed[hero_token]=true
	moves[hero_token]={"origin":vec(game.hero.position),"last":game.hero.position,"distance":0.0,"steps":0,"maximum_step":0.0}
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
		"phase":String(game.phase),"night":int(game.day_number),"hp":victim.hp,"alive":victim.alive,"parts":int(game.scrap)})

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
				"wave":int(member.get_meta("wave_reward_id",-1))})
			member.defeated.connect(record_death)
			member.damage_confirmed.connect(record_wound)
			if member.kind != "monster": moves[token]={"origin":vec(member.position),"last":member.position,"distance":0.0,"steps":0,"maximum_step":0.0}
		if moves.has(token):
			var row: Dictionary=moves[token]
			var moved:=planar(row.last,member.position)
			row.distance+=moved; row.maximum_step=maxf(row.maximum_step,moved)
			if moved>.00001: row.steps+=1
			row.last=member.position; row["final"]=vec(member.position); row["alive"]=member.alive; row["hp"]=member.hp
	for raw: Variant in game.get("burstlings"):
		if not is_instance_valid(raw): continue
		var state: Dictionary=raw.snapshot()
		var token:=int(state.get("source_token",-1))
		var signature: String="%s:%s:%s" % [String(state.phase),int(state.impacts),int(state.cancelled)]
		if previous_casts.get(token,"")==signature: continue
		previous_casts[token]=signature
		casts.append({"token":token,"at":elapsed,"phase":String(state.phase),"remaining":float(state.remaining),
			"position":vec(state.position),"impacts":int(state.impacts),"cancelled":int(state.cancelled),
			"reason":String(state.cancel_reason),"targets_hit":int(state.targets_hit),"night":int(game.day_number)})

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
	check(game.construction.active and game.construction.kind==kind,"实际Y和建设页选择 "+kind)
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

func module_for(host: BattleUnit) -> Node3D:
	for raw: Variant in game.get("burstlings"):
		if is_instance_valid(raw) and raw.get("host")==host: return raw as Node3D
	check(false,"真实出生须登记对应爆裂控制器")
	return null

func spawn_burst(point: Vector3) -> BattleUnit:
	check(precision,"直接出生/站位仅用于精度隔离，不用于自然证据")
	var host: BattleUnit=game.spawn_creature(true,"burstling")
	point.y=game.outpost_height(point)
	host.position=point; host.attack_timer=0.0
	observe()
	return host

func arm(host: BattleUnit) -> Node3D:
	var module:=module_for(host)
	if module==null: return null
	module.advance(.001)
	var state: Dictionary=module.snapshot()
	check(String(state.phase)=="windup" and bool(host.get_meta("burstling_winding",false)),"近合法目标真实进入完整蓄爆")
	near(float(state.remaining),1.4,"启动帧不偷耗1.4秒蓄爆")
	return module

func damage_sum(token: int, source_token: int = -1) -> float:
	var amount:=0.0
	for row: Dictionary in wounds:
		if int(row.token)==token and (source_token<0 or int(row.source)==source_token): amount+=float(row.hp_loss)+float(row.shield_loss)
	return amount

func plan_and_ledger() -> void:
	var generator:=Encounter.new()
	for mode: String in ["teaching","standard","siege","echo"]:
		for night in range(1,5):
			for nest in range(4):
				for seed in [SEED,20261006,29045]:
					var plan: Array[Dictionary]=generator.make_plan(mode,night,seed,nest)
					check(plan==generator.make_plan(mode,night,seed,nest),"保存计划同参数完整确定 "+mode)
					for index in 5:
						var row: Dictionary=plan[index]
						var expected:=1 if mode!="teaching" and ((night==2 and index==1) or (night>=3 and index in [1,3])) else 0
						check(row.roles.count("burstling")==expected,"仅指定夜波替换一个普通随从")
						var base_count:=8+night*3 if index==0 else 8+night*2+index*2
						var count: int=maxi(4,base_count-mini(nest*2,6))
						check(int(row.role_count)==row.roles.size() and row.roles.size()==count,"人数和封巢减少仍匹配原公式")
						check(int(row.count)==row.roles.size()+(1 if bool(row.boss_entry) else 0),"首领人数仍真实另计")
						check(int(row.get("burstling_count",-1))==expected,"真实预告数量匹配角色列表")
						for role: String in row.roles: check(role in Encounter.KNOWN_ROLES,"计划只含已知实际角色")
	# Teaching and standard share the same theme RNG; replacing only the new
	# role back to basic must restore exact original deterministic shuffle order.
	for night in range(1,5):
		for seed in [SEED,20261006,29045]:
			for nest in range(4):
				var original: Array[Dictionary]=generator.make_plan("teaching",night,seed,nest)
				var changed: Array[Dictionary]=generator.make_plan("standard",night,seed,nest)
				for index in 5:
					var restored: Array=changed[index].roles.duplicate()
					for slot in restored.size():
						if restored[slot]=="burstling": restored[slot]="basic"
					check(restored==original[index].roles,"原专职与shuffle随机流逐位保留")
	(evidence.plans as Array).append({"modes":4,"nights":4,"nest_counts":4,"seeds":[SEED,20261006,29045],"exact_restored_roles":true})
	if not await fresh(): return
	# Explicit compressed lifecycle still registers and kills all original waves.
	game.wave_index=1
	for _wave in 4: game.spawn_night_wave()
	await clear_hostiles()
	game.phase_time=.01; step(.02)
	check(game.phase=="draft","首夜精度真实死亡后到实际截止进入黎明")
	await press(KEY_1)
	game.phase_time=.01; step(.02)
	check(game.phase=="night" and game.day_number==2,"真实日落进入第二夜")
	game.pulse_timer=100000.0; game.hero.attack_timer=100000.0
	for pad: Dictionary in game.world.tower_pads: pad.cooldown=100000.0
	game.spawn_night_wave()
	var wave_id: int=game.active_wave_reward_id
	var row: Dictionary=game.wave_rewards.snapshot(wave_id)
	check(row.has("budget") and row.has("count"),"实际四夜模式必须有真实登记的波次账本")
	if not row.has("budget") or not row.has("count"): return
	check(int(row.budget)==24 and int(row.count)==game.night_plan[1].roles.size(),"真实第二波保留24预算及完整计划人数")
	var host: BattleUnit
	for raw: Variant in game.enemies:
		if living(raw) and String(raw.get_meta("threat",""))=="burstling": host=raw
	check(host!=null,"真实第二夜第二波实际出生爆裂体")
	if host==null: return
	near(host.max_hp,(155.0+2.0*28.0)*.72,"生产第二夜爆裂生命缩放")
	near(host.armor,0.0,"生产爆裂无甲")
	near(host.speed,3.4,"生产爆裂移速3.4")
	near(host.damage,42.0,"生产爆裂固定42伤")
	await clear_hostiles(host)
	stand_hero(OPEN)
	host.position=OPEN+Vector3(1.0,0,0); host.position.y=game.outpost_height(host.position)
	var controller:=arm(host)
	if controller==null: return
	# These are all remaining genuine production waves, followed by genuine
	# deaths. Only the clock is compressed; the live fuse survives the deadline.
	for _wave in 3: game.spawn_night_wave()
	await clear_hostiles(host)
	check(game.wave_index==5,"第二夜五个原计划波均已真实出生")
	game.phase_time=.01; step(.02)
	check(game.phase=="night" and game.night_clearance_active,"截止保留真实蓄爆源进入清场")
	check(living(host) and String(controller.snapshot().phase)=="windup","截止不消除仍活源及未完成真实前摇")
	game.finish_night()
	check(game.phase=="night" and game.night_clearance_snapshot().remaining==1,"真实提前黎明入口拒绝未死亡爆裂源")
	var before: int=game.scrap
	controller.advance(1.401)
	check(not host.alive and int(controller.snapshot().impacts)==1,"自耗走真实死亡且一次爆炸")
	row=game.wave_rewards.snapshot(wave_id)
	check(bool(row.cleared) and int(row.paid)==24,"原波全真死亡后准确结清24一次")
	var after: int=game.scrap
	game._on_creature_defeated(host,null)
	check(game.scrap==after and int(game.wave_rewards.snapshot(wave_id).paid)==24,"重复死亡回调不得重复支付原预算")
	check(game.kill_chain==0,"自爆与精度null致死不冒充英雄普攻连斩")
	(evidence.precision_results as Array).append({"kind":"real-wave","id":wave_id,"ledger":row,"self_consumption_wallet_delta":after-before})
	step(.02)
	check(game.phase=="draft" and game.burstling_warning_snapshot().is_empty(),"真实源死亡后生产清场循环才进入黎明并退役危险环")
	await press(KEY_1)
	check(game.phase=="day" and game.phase_time==90.0,"真实清场后仍完整90秒白昼")
	stage_finished=true

func production_and_priority() -> void:
	if not await fresh(): return
	for kind: String in ["barracks","workshop","laboratory","armory"]:
		check(await build_gui(kind)>=0,"真实GUI科技建设 "+kind)
	for kind: String in ["shield","ranged","hunter","netter","artillery"]:
		var squad:=await train_gui(kind)
		if squad.is_empty(): return
		station(squad,[OPEN+Vector3(0,0,kind.length()),OPEN+Vector3(0,0,kind.length()+3),OPEN+Vector3(0,0,kind.length()+6)])
	var ranged: Dictionary=game.squads.squads[1]
	var hunter: Dictionary=game.squads.squads[2]
	station(ranged,[OPEN,OPEN+Vector3(0,0,8),OPEN+Vector3(0,0,12)])
	station(hunter,[OPEN+Vector3(0,0,-4),OPEN+Vector3(0,0,-8),OPEN+Vector3(0,0,-12)])
	var host:=spawn_burst(OPEN+Vector3(4,0,0))
	var ordinary: BattleUnit=game.spawn_creature(true,"basic")
	ordinary.position=OPEN+Vector3(2,0,0); ordinary.position.y=game.outpost_height(ordinary.position)
	var source: BattleUnit=ranged.members[0]
	check(game.squads._pick_enemy(source,true)==host,"原合法射程内弩手主动优先爆裂体")
	check(game.squads.hunters.bonus_target(host),"猎手保留专职敌加伤资格")
	var token:=host.get_instance_id()
	var hp:=host.hp
	var ids: Array[int]=[int(ranged.id)]
	check(game.squads.select_ids(ids)==ids,"公开选择真实弩手")
	check(bool(game.squads.command_attack(host).ok),"公开指定爆裂体攻击")
	source.attack_timer=0.0
	game.squads.advance(.001)
	check(source.attack_queued and source.target==host,"真实远程命令先完整前摇")
	near(host.hp,hp,"前摇开始不提前造成伤害")
	game.squads.advance(.259)
	near(host.hp,hp,"真实弩手0.26秒前摇未到不命中")
	game.squads.advance(.002)
	near(hp-host.hp,16.0,"弩手完整前摇一次真实16伤")
	check(damage_sum(token,source.get_instance_id())>=16.0,"真实伤害信号见证合法源")
	# An actual ranged release at the end of a live fuse kills the low-HP
	# precision target; no direct hurt is used to claim ranged interception.
	stand_hero(OPEN+Vector3(5,0,0))
	host.position=OPEN+Vector3(4,0,0); host.hp=8.0
	var controller:=arm(host)
	if controller==null: return
	source.attack_timer=0.0
	game.squads.advance(.001); game.squads.advance(.261)
	controller.advance(.3)
	check(not host.alive and int(controller.snapshot().impacts)==0,"真实远程实伤击杀蓄爆源后不爆炸")
	await clear_hostiles()
	station(ranged,[OPEN+Vector3(0,0,9),OPEN+Vector3(0,0,12),OPEN+Vector3(0,0,15)])
	station(hunter,[OPEN,OPEN+Vector3(0,0,-9),OPEN+Vector3(0,0,-12)])
	host=spawn_burst(OPEN+Vector3(1,0,0))
	var hunter_source: BattleUnit=hunter.members[0]
	var hunter_ids: Array[int]=[int(hunter.id)]
	check(game.squads.select_ids(hunter_ids)==hunter_ids and bool(game.squads.command_attack(host).ok),"真实猎手公开指定爆裂体")
	hunter_source.attack_timer=0.0
	hp=host.hp; token=host.get_instance_id()
	game.squads.advance(.001)
	check(hunter_source.attack_queued and hunter_source.target==host,"真实猎手先完整前摇")
	near(host.hp,hp,"猎手前摇开始零提前伤害")
	var hunter_windup: float=hunter_source.attack_windup
	game.squads.advance(hunter_windup-.001)
	near(host.hp,hp,"猎手完整前摇结束前零伤")
	game.squads.advance(.002)
	near(hp-host.hp,30.0,"猎手12基础加18专职真实30伤")
	near(damage_sum(token,hunter_source.get_instance_id()),30.0,"猎手30伤只有真实hurt信号证明")
	stage_finished=true

func burst_and_targets() -> void:
	if not await fresh(): return
	await build_gui("barracks")
	var shield:=await train_gui("shield")
	if shield.is_empty(): return
	station(shield,[OPEN+Vector3(1,0,0),OPEN+Vector3(-1,0,0),OPEN+Vector3(0,0,2.401)])
	stand_hero(OPEN+Vector3(0,0,1.4))
	game.hero.shield=10.0; game.hero.shield_time=10.0
	var hero_hp: float=game.hero.hp
	var first: BattleUnit=shield.members[0]
	var second: BattleUnit=shield.members[1]
	var outside: BattleUnit=shield.members[2]
	var hp1:=first.hp; var hp2:=second.hp; var hp3:=outside.hp
	var host:=spawn_burst(OPEN)
	var controller:=arm(host)
	if controller==null: return
	var cast: Dictionary=controller.snapshot()
	check(String(cast.target_kind)=="squad" and int(cast.target_token)==first.get_instance_id(),"最近合法部队先于更远英雄")
	controller.advance(1.399)
	near(first.hp,hp1,"完整1.4秒前零伤害")
	near(game.hero.hp,hero_hp,"蓄爆前英雄零实伤")
	controller.advance(.002)
	near(hp1-first.hp,42.0*100.0/(100.0+first.armor),"爆炸走盾卫真实护甲")
	near(hp2-second.hp,42.0*100.0/(100.0+second.armor),"同圈另一真实成员也仅受一击")
	near(hp3-outside.hp,0.0,"2.401米圈外真实成员不受伤")
	near(game.hero.shield,0.0,"爆炸先扣原英雄护盾")
	near(hero_hp-game.hero.hp,42.0*100.0/(100.0+game.hero.armor)-10.0,"先护甲后扣盾，余伤走真实英雄生命入口",.1)
	check(int(controller.snapshot().impacts)==1 and not host.alive,"一次扩散后真实自耗")
	var result_hp:=first.hp
	controller.advance(5.0)
	near(first.hp,result_hp,"后续advance不得重复伤害")
	await capture_all("actual-group-impact",OPEN)
	await clear_hostiles()
	station(shield,[OPEN+Vector3(8,0,0),OPEN+Vector3(9,0,0),OPEN+Vector3(10,0,0)])
	stand_hero(OPEN+Vector3(1,0,0))
	host=spawn_burst(OPEN); controller=arm(host)
	if controller==null: return
	check(String(controller.snapshot().target_kind)=="hero","最近合法英雄成为蓄爆目标")
	var center: Vector3=controller.snapshot().position
	var source_token:=host.get_instance_id()
	var damage_before:=damage_sum(game.hero.get_instance_id(),source_token)
	game.plan_hero_path(OPEN+Vector3(8,0,0))
	var start: Vector3=game.hero.position
	await advance(1.41)
	check(planar(start,game.hero.position)>2.4,"公开英雄路径实际离开原固定危险圈")
	check(planar(center,game.hero.position)>2.4,"实际撤出启动时保存的固定危险圈")
	near(damage_sum(game.hero.get_instance_id(),source_token)-damage_before,0.0,"真实移出后对应源零实伤")
	check(deaths.any(func(row: Dictionary) -> bool: return int(row.token)==source_token and int(row.source)==source_token),"诱空后真实自耗回调，不访问已退休控制器")
	(evidence.precision_results as Array).append({"kind":"public-lure","source":source_token,"fixed_center":vec(center),"start":vec(start),"final":vec(game.hero.position),"source_damage":damage_sum(game.hero.get_instance_id(),source_token)-damage_before})
	await capture_all("empty-lure-impact",OPEN)
	stage_finished=true

func geometry_and_buildings() -> void:
	if not await fresh(): return
	var index:=await build_gui("barracks")
	if index<0: return
	var plot: Dictionary=game.districts.plots[index]
	stand_hero(OPEN)
	var edge: Vector3=plot.position+Vector3(-3.0,0,0)
	edge.y=game.outpost_height(edge)
	var host:=spawn_burst(edge)
	var controller:=arm(host)
	if controller==null: return
	check(String(controller.snapshot().target_kind)=="district" and int(controller.snapshot().target_index)==index,"合法建筑表面近距可蓄爆")
	check(planar(plot.position,host.position)>2.4,"建筑中心圈外用完整占格表面判定")
	var hp: float=plot.hp
	controller.advance(1.401)
	near(hp-float(plot.hp),42.0,"建筑表面爆炸真实耐久只扣一次")
	await clear_hostiles()
	# The old 1.8m stop measured from a point .35m outside the face left this
	# source 2.1m from the actual surface forever. Start outside arming range;
	# only real movement through the controller may bring it into contact.
	var approach_start: Vector3=plot.position+Vector3(-4.1,0,0)
	host=spawn_burst(approach_start); controller=module_for(host)
	if controller==null: return
	controller.advance(.001)
	check(String(controller.snapshot().phase)=="idle","距兵营真实表面2.1米不得提前蓄爆")
	var start: Vector3=host.position
	for _step in 20:
		step(.05)
		if not living(host) or game.burstling_warning_snapshot().size()>0: break
	check(living(host) and planar(start,host.position)>.05,"原2.1米停止死区必须发生实际寻路位移")
	check(game.burstling_warning_snapshot().size()==1,"真实移动抵达兵营表面后完整开始蓄爆")
	await clear_hostiles()
	var workshop:=await build_gui("workshop")
	if workshop<0: return
	var blocker: Dictionary=game.districts.plots[workshop]
	var blocked_source: Vector3=blocker.position+Vector3(0,0,-1.1)
	var blocked_target: Vector3=blocker.position+Vector3(0,0,1.1)
	stand_hero(blocked_target)
	host=spawn_burst(blocked_source); controller=arm(host)
	if controller==null: return
	check(game.can_attack_line(host.position,game.hero.position),"动态工坊遮挡由真实建设占格承担，不混为静态城墙")
	check(String(controller.snapshot().target_kind)=="district" and int(controller.snapshot().target_index)==workshop,"源合法接触动态工坊表面")
	var blocked_hero_hp: float=game.hero.hp
	var blocker_hp: float=blocker.hp
	controller.advance(1.401)
	near(game.hero.hp,blocked_hero_hp,"真实存活工坊挡住圈内跨楼英雄，不穿占格群伤")
	near(blocker_hp-float(blocker.hp),42.0,"挡线建筑自身真实表面仍只承受42")
	await clear_hostiles()
	stand_hero(blocked_target)
	host=spawn_burst(blocked_source); controller=arm(host)
	if controller==null: return
	check(bool(game.districts.damage(workshop,100000.0).destroyed),"精度真伤毁坏动态遮挡工坊")
	controller.revalidate_cast()
	check(String(controller.snapshot().phase)=="windup","原目标毁坏不取消已经点燃的固定原地爆圈")
	blocked_hero_hp=game.hero.hp
	controller.advance(1.401)
	near(blocked_hero_hp-game.hero.hp,42.0*100.0/(100.0+game.hero.armor),"动态楼真实毁坏后圈内原英雄才实际承伤")
	await clear_hostiles()
	# World walls and local terrain are real; the actor stations are precision.
	var wall_source:=Vector3(-14.0,5,0)
	var wall_target:=Vector3(-12.0,5,0)
	stand_hero(wall_target)
	host=spawn_burst(wall_source); controller=module_for(host)
	check(not game.can_attack_line(host.position,game.hero.position),"实际城墙构成跨墙反例")
	if controller!=null:
		controller.advance(.001)
		check(String(controller.snapshot().phase)!="windup","隔墙近点不能蓄爆")
	await clear_hostiles()
	stand_hero(OPEN+Vector3(1,0,0))
	game.hero.position.y+=.751
	host=spawn_burst(OPEN); controller=module_for(host)
	if controller!=null:
		controller.advance(.001)
		check(String(controller.snapshot().phase)!="windup","离当地地面超过.75目标不得开始")
	stand_hero(OPEN+Vector3(1,0,0))
	if controller!=null:
		controller.advance(.001)
		check(String(controller.snapshot().phase)=="windup","原地面合法目标可完整准备")
		host.position.y+=.751; controller.revalidate_cast()
		check(String(controller.snapshot().phase)=="cooldown" and int(controller.snapshot().impacts)==0,"源真实高度失效取消未完成蓄爆")
	await clear_hostiles()
	# Slope height itself is not a flying offset. Full radius is sampled on
	# real ground; compare host and hero local offsets rather than world Y.
	var slope:=Vector3(0,game.outpost_height(Vector3(0,0,22)),22)
	stand_hero(slope+Vector3(0,0,1.3))
	host=spawn_burst(slope); controller=arm(host)
	if controller!=null:
		var before: float=game.hero.hp
		controller.advance(1.401)
		check(game.hero.hp<before,"真实坡面相同当地高度仍受完整爆圈伤害")
	await capture_all("actual-ramp-impact",slope)
	if not await structure_targets_and_identity(): return
	stage_finished=true

func structure_hp(kind: String, index: int = 0) -> float:
	match kind:
		"beacon": return float(game.beacon_hp)
		"barricade": return float(game.gate_barricade_hp)
		"tower": return float(game.world.tower_pads[index].hp)
		"district": return float(game.districts.plots[index].hp)
	return NAN

func structure_source(kind: String, index: int = 0) -> Vector3:
	match kind:
		"beacon": return Vector3(0,5,4.3)
		"barricade": return (game.gate_barricade.position as Vector3)+Vector3(0,0,.9)
		"tower":
			var tower_center: Vector3=game.world.tower_pads[index].position
			var tower_half: Vector2=game.construction.footprint("tower")
			return tower_center+Vector3(tower_half.x+1.1,0,0)
		"district":
			var plot: Dictionary=game.districts.plots[index]
			var district_half: Vector2=game.construction.footprint(String(plot.kind))
			return (plot.position as Vector3)+Vector3(district_half.x+1.2,0,0)
	return Vector3.INF

func structure_blast(kind: String, multiplier: float) -> bool:
	await clear_hostiles()
	stand_hero(OPEN)
	game.beacon_alarm_time=0.0; game.beacon_alarm_damage=0.0
	var host:=spawn_burst(structure_source(kind))
	var controller:=arm(host)
	if controller==null: return false
	check(String(controller.snapshot().target_kind)==kind,"真实最近建筑表面进入完整蓄爆 "+kind)
	var before:=structure_hp(kind)
	controller.advance(1.399)
	near(structure_hp(kind),before,"建筑完整蓄爆结束前零提前伤害 "+kind)
	controller.advance(.002)
	var expected:=42.0 if kind=="tower" else 42.0*multiplier
	near(before-structure_hp(kind),expected,"真实结构伤害入口与当前坚守倍率 "+kind)
	check(int(controller.snapshot().impacts)==1 and not host.alive,"建筑爆炸真实一次自耗 "+kind)
	if kind=="beacon":
		near(float(game.beacon_alarm_damage),expected,"灯塔警报只记录减伤后的实际损失")
		check(game.beacon_alarm_time>0.0,"真实爆裂灯塔伤害产生原警报")
	(evidence.precision_results as Array).append({"kind":"blast-structure","target":kind,"multiplier":multiplier,"loss":before-structure_hp(kind),"expected":expected})
	if is_equal_approx(multiplier,.82): await capture_all("structure-"+kind+"-level-two",structure_source(kind))
	return true

func recipient_reentry(_victim: BattleUnit, _source: BattleUnit, _hp_loss: float, _shield_loss: float, action: String, index: int) -> void:
	check(precision,"收件人身份重入仅作明确精度反例")
	reentry={"action":action,"index":index,"ok":false}
	match action:
		"district-rebuild":
			var plot: Dictionary=game.districts.plots[index]
			var point: Vector3=plot.position
			var old_model: int=plot.model.get_instance_id()
			var cost: int=Catalog.building(String(plot.kind)).cost
			var before: int=game.scrap
			check(bool(game.districts.damage(index,100000.0).destroyed),"回调精度真伤毁楼")
			var rebuilt: bool=game.build_structure_at(point,String(plot.kind))
			reentry.merge({"ok":rebuilt and game.scrap==before-cost,"old_model":old_model,"new_model":int(game.districts.plots[index].model.get_instance_id()) if rebuilt else -1,"cost":before-int(game.scrap)},true)
		"district-dictionary":
			var original_plot: Dictionary=game.districts.plots[index]
			var clone_plot: Dictionary=original_plot.duplicate(true)
			game.districts.plots[index]=clone_plot
			reentry["ok"]=not is_same(original_plot,game.districts.plots[index])
		"tower-rebuild":
			var pad: Dictionary=game.world.tower_pads[index]
			var old_turret: int=pad.turret.get_instance_id()
			var tower_cost: int=game.districts.tower_cost(game.TOWER_COSTS[0])
			var prior_money: int=game.scrap
			game.damage_tower(index,100000.0)
			var new_tower: bool=game.build_or_upgrade_tower(index)
			reentry.merge({"ok":new_tower and game.scrap==prior_money-tower_cost,"old_model":old_turret,"new_model":int(game.world.tower_pads[index].turret.get_instance_id()) if new_tower else -1,"cost":prior_money-int(game.scrap)},true)
		"tower-dictionary":
			var original_pad: Dictionary=game.world.tower_pads[index]
			var clone_pad: Dictionary=original_pad.duplicate(true)
			game.world.tower_pads[index]=clone_pad
			reentry["ok"]=not is_same(original_pad,game.world.tower_pads[index])
		"beacon-parent", "barricade-parent":
			var model: Node3D=game.world.beacon if action=="beacon-parent" else game.gate_barricade
			model.reparent(game,true)
			reentry["ok"]=model.get_parent()==game and not game.world.is_ancestor_of(model)

func recipient_identity_case(kind: String, action: String) -> bool:
	await clear_hostiles()
	var origin:=structure_source(kind)
	stand_hero(origin+Vector3(0,0,-1) if kind in ["tower","district"] else origin+Vector3(1,0,0))
	var host:=spawn_burst(origin)
	var controller:=arm(host)
	if controller==null: return false
	reentry.clear()
	var before:=structure_hp(kind)
	var callback:=recipient_reentry.bind(action,0)
	game.hero.damage_confirmed.connect(callback,CONNECT_ONE_SHOT)
	controller.advance(1.401)
	if game.hero.damage_confirmed.is_connected(callback): game.hero.damage_confirmed.disconnect(callback)
	check(bool(reentry.get("ok",false)),"第一个真实hurt回调实际执行受控身份更换 "+action)
	if action.ends_with("rebuild"):
		check(int(reentry.get("old_model",-1))!=int(reentry.get("new_model",-1)),"同址真实付款重建形成新模型身份 "+action)
		var full_hp: float=game.world.tower_pads[0].max_hp if kind=="tower" else game.districts.plots[0].max_hp
		near(structure_hp(kind),full_hp,"本次旧采样不得纳入回调中新建模型 "+action)
	else:
		near(structure_hp(kind),before,"原Dictionary或parent身份失效后不得伤害替换收件人 "+action)
	if action.ends_with("parent"):
		var displaced: Node3D=game.world.beacon if kind=="beacon" else game.gate_barricade
		displaced.reparent(game.world,true)
	check(int(controller.snapshot().impacts)==1 and not host.alive,"收件人失效只跳过该对象，原源一次真实自耗")
	(evidence.precision_results as Array).append(reentry.duplicate(true))
	return true

func structure_targets_and_identity() -> bool:
	if not await fresh(true,"holdfast_beacon"): return false
	stand_hero(Vector3(0,5,13.4))
	var before: int=game.scrap
	check(game.build_gate_barricade() and game.scrap==before-int(game.BARRICADE_COST),"真实部署路障并支付原费用")
	if game.gate_barricade_hp<=0.0: return false
	stand_hero(OPEN)
	for kind: String in ["beacon","barricade","tower"]:
		if not await structure_blast(kind,1.0): return false
	if await build_gui("workshop")<0: return false
	var holdfast:=await build_gui("holdfast_beacon",Vector3(-9,5,-3))
	if holdfast<0: return false
	for level in [1,2]:
		if level==2: check(bool(game.districts.upgrade(holdfast).ok),"真实支付坚守信标二级升级")
		var multiplier:=.9 if level==1 else .82
		near(float(game.districts.holdfast_damage_multiplier()),multiplier,"当前存活真实坚守等级倍率")
		for kind: String in ["beacon","barricade","tower"]:
			if not await structure_blast(kind,multiplier): return false
	check(bool(game.districts.damage(holdfast,100000.0).destroyed),"精度真伤摧毁信标即时移除减伤")
	near(float(game.districts.holdfast_damage_multiplier()),1.0,"毁坏后真实倍率恢复原伤害")
	for kind: String in ["beacon","barricade","tower"]:
		if not await structure_blast(kind,1.0): return false
	for spec: Array in [["district","district-rebuild"],["district","district-dictionary"],["tower","tower-rebuild"],["tower","tower-dictionary"],["beacon","beacon-parent"],["barricade","barricade-parent"]]:
		if not await recipient_identity_case(String(spec[0]),String(spec[1])): return false
	return true

func controls_and_artillery() -> void:
	if not await fresh(): return
	for kind: String in ["barracks","workshop","laboratory","armory"]: await build_gui(kind)
	var netter:=await train_gui("netter")
	var artillery:=await train_gui("artillery")
	if netter.is_empty() or artillery.is_empty(): return
	station(netter,[OPEN+Vector3(-5,0,0),OPEN+Vector3(-5,0,9),OPEN+Vector3(-5,0,12)])
	station(artillery,[OPEN+Vector3(-8,0,0),OPEN+Vector3(-8,0,10),OPEN+Vector3(-8,0,14)])
	stand_hero(OPEN+Vector3(1,0,0))
	var host:=spawn_burst(OPEN)
	var controller:=arm(host)
	if controller==null: return
	var ids: Array[int]=[int(netter.id)]
	check(game.squads.select_ids(ids)==ids and bool(game.squads.command_attack(host).ok),"真实投网队公开攻击爆裂体")
	var source: BattleUnit=netter.members[0]
	source.attack_timer=0.0
	game.squads.advance(.001)
	check(game.squads.netters.casting(source),"真实投网命令启动0.6秒前摇")
	game.squads.advance(.599)
	near(game.specializations.net_remaining(host),0.0,"投网完整前摇前不产生控制")
	game.squads.advance(.002)
	check(game.specializations.net_remaining(host)>0.0,"真实投网实伤后产生控制")
	controller.revalidate_cast()
	check(String(controller.snapshot().phase)=="cooldown" and int(controller.snapshot().impacts)==0,"真实网控立即取消尚未爆炸的源")
	near(float(controller.snapshot().cooldown),1.0,"取消留下完整一秒重新准备间隔")
	var before: float=game.hero.hp
	controller.advance(.999)
	near(game.hero.hp,before,"取消后不能冒出旧爆炸")
	controller.advance(.002)
	check(String(controller.snapshot().phase)!="windup","一秒到但真实网仍在时不重开")
	await capture_all("actual-net-cancel",OPEN)
	game.specializations.advance(2.01,true)
	controller.advance(.001)
	check(String(controller.snapshot().phase)=="windup","网自然到期后重新完整1.4秒准备")
	near(float(controller.snapshot().remaining),1.4,"取消不会恢复旧剩余前摇")
	# A real tower control shot independently cancels the new preparation.
	var pad: Dictionary=game.world.tower_pads[0]
	var saved:=pad.duplicate(true)
	pad.level=2; pad.specialization="control"
	game.specializations.resolve_shot(pad,host,game.enemies,1.0,null)
	controller.revalidate_cast()
	check(int(controller.snapshot().cancelled)>=2 and int(controller.snapshot().impacts)==0,"真实牵制塔与网投均取消未完成蓄爆")
	for key: Variant in saved.keys(): pad[key]=saved[key]
	await clear_hostiles()
	stand_hero(OPEN+Vector3(1,0,0))
	host=spawn_burst(OPEN)
	controller=module_for(host)
	ids=[int(artillery.id)]
	check(game.squads.select_ids(ids)==ids and bool(game.squads.command_attack(host).ok),"真实炮队公开指定爆裂体")
	var gunner: BattleUnit=artillery.members[0]
	gunner.attack_timer=0.0
	game.squads.advance(.001)
	check(gunner.attack_queued,"真实炮队完整准备而非直接制造炮弹")
	game.squads.advance(1.001)
	var hp: float=host.hp
	game.squads.advance(.799)
	near(host.hp,hp,"真实固定落点弹完整0.8秒飞行前不得提前命中")
	game.squads.advance(.002)
	near(hp-host.hp,32.0,"真实炮弹落地一次32伤")
	var after: float=host.hp
	game.squads.advance(.3)
	near(host.hp,after,"已落炮弹不重复造成伤害")
	(evidence.precision_results as Array).append({"kind":"actual-net-and-artillery","net_source":source.get_instance_id(),"gunner":gunner.get_instance_id(),"artillery_damage":hp-after})
	stage_finished=true

func reaction(_victim: BattleUnit, source: BattleUnit, _hp_loss: float, _shield_loss: float, action: String, controller: Node3D) -> void:
	if not is_instance_valid(controller): return
	if action=="reflect" and living(source): source.hurt(100000.0,null)
	elif action=="clear": controller.clear()
	elif action=="swap" and living(source):
		var successor:=Burst.new()
		game.burstlings.append(successor)
		successor.setup(game,source)
		reentry={"action":"same-host-controller","old":controller.get_instance_id(),"new":successor.get_instance_id(),"host":source.get_instance_id()}
	elif action=="end" and game.phase!="ended": game.end_defeat("精度同步败局")

func lifecycle_and_reentry() -> void:
	if not await fresh(): return
	await build_gui("barracks")
	var shield:=await train_gui("shield")
	if shield.is_empty(): return
	station(shield,[OPEN+Vector3(1,0,0),OPEN+Vector3(-1,0,0),OPEN+Vector3(0,0,1.5)])
	stand_hero(OPEN+Vector3(0,0,1.0))
	var host:=spawn_burst(OPEN)
	var controller:=arm(host)
	if controller==null: return
	var hp: float=game.hero.hp
	var before: Dictionary=controller.snapshot()
	await press(KEY_ESCAPE)
	check(game.phase=="paused","真实Esc暂停")
	game.simulate(10.0); controller.advance(10.0)
	near(float(controller.snapshot().remaining),float(before.remaining),"暂停冻结真实蓄爆")
	near(game.hero.hp,hp,"暂停无实伤")
	await capture_all("actual-paused-windup",OPEN)
	await press(KEY_ESCAPE)
	game.run.grant("精度免费待选卡")
	game.open_draft()
	check(game.phase=="draft","生产待选卡入口真实冻结")
	game.simulate(10.0); controller.advance(10.0)
	near(float(controller.snapshot().remaining),float(before.remaining),"draft冻结真实蓄爆")
	await press(KEY_1)
	check(game.phase=="night","真实选卡回原夜")
	# Core loop must not route a shield-adjacent fuse into its .34s single hit.
	step(.35)
	near(game.hero.hp,hp,"0.35秒普通拦截前摇不得偷发爆裂伤害")
	check(controller.snapshot().phase=="windup" and host.attack_queued,"盾卫附近仍保留独立蓄爆")
	var remaining: float=controller.snapshot().remaining
	controller.advance(remaining+.001)
	check(int(controller.snapshot().impacts)==1 and not host.alive,"普通盾卫链不吞掉真实一次爆炸")
	for action: String in ["reflect","clear","swap","end"]:
		if game.phase=="ended":
			if not await fresh(): return
			await build_gui("barracks"); shield=await train_gui("shield")
		station(shield,[OPEN+Vector3(1,0,0),OPEN+Vector3(-1,0,0),OPEN+Vector3(0,0,1.5)])
		stand_hero(OPEN+Vector3(0,0,1.0))
		host=spawn_burst(OPEN); controller=arm(host)
		if controller==null: return
		var second: BattleUnit=shield.members[0]
		var before_hp:=second.hp
		var callback:=reaction.bind(action,controller)
		game.hero.damage_confirmed.connect(callback,CONNECT_ONE_SHOT)
		controller.advance(1.401)
		if action=="reflect":
			check(second.hp<before_hp and int(controller.snapshot().impacts)==1,"伤害同步反杀源不取消已经提交的同次扩散")
		else:
			if is_instance_valid(second) and not second.is_queued_for_deletion():
				near(second.hp,before_hp,"同步clear或结束停止随后受害者扩散")
			else:
				check(action=="end" and game.squads.squads.is_empty(),"真实败局退役后不访问旧部队")
			if action=="swap":
				check(living(host) and not reentry.is_empty() and int(host.get_meta("burstling_controller_token",-1))==int(reentry.get("new",-2)),"同活源新控制器接管后旧事件停止，不能自耗或擦新归属")
				(evidence.precision_results as Array).append(reentry.duplicate(true))
			check(game.phase=="ended" if action=="end" else String(controller.snapshot().phase)=="idle","同步生命周期回调真实完成")
		await clear_hostiles()
	if not await fresh(): return
	stand_hero(OPEN+Vector3(1,0,0))
	host=spawn_burst(OPEN); controller=arm(host)
	if controller==null: return
	game.enemies.erase(host)
	controller.revalidate_cast()
	check(int(controller.snapshot().impacts)==0 and String(controller.snapshot().phase)=="cooldown","移出原生产roster的同点活对象不能提交旧爆炸")
	game.enemies.append(host)
	controller.clear()
	controller.advance(10.0)
	near(int(controller.snapshot().impacts),0.0,"clear后旧身份不继续提交")
	var retry_id:=game.get_instance_id()
	game.end_defeat("精度真实结束后重试")
	check(game.phase=="ended","公开同种子重试前必须真实结束")
	await press(KEY_ENTER)
	for _frame in 200:
		if current_scene!=null and current_scene.get_instance_id()!=retry_id: break
		await create_timer(.02,true,false,true).timeout
	check(current_scene!=null and current_scene.get_instance_id()!=retry_id,"真实场景重试而非夹具重建")
	if current_scene==null or current_scene.get_instance_id()==retry_id: return
	game=current_scene as Node3D
	game.set_process(false); game.world.set_process(false)
	check(game.phase=="draft" and game.scrap==90 and game.squads.squads.is_empty() and game.burstling_warning_snapshot().is_empty(),"重试重置本局经济/兵员/危险源")
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

func hud() -> void:
	if not await fresh(): return
	stand_hero(OPEN+Vector3(1,0,0))
	camera_at(OPEN)
	quiet_hud(); await frames()
	var original: Array=game.hud.live_panel_rects().duplicate()
	original.erase(CleanHud.objective_rect(game.hud,game))
	await capture_all("default-clean",Vector3(0,5,8))
	camera_at(OPEN)
	var host:=spawn_burst(OPEN)
	var controller:=arm(host)
	if controller==null: return
	quiet_hud(); await frames()
	var current: Array=game.hud.live_panel_rects().duplicate()
	current.erase(CleanHud.objective_rect(game.hud,game))
	check(current==original,"扣除真实动态目标矩形后全部常驻命中区域逐一保持")
	var warnings: Array=game.burstling_warning_snapshot()
	check(warnings.size()==1 and String(warnings[0].phase)=="windup","源旁报警仅真实蓄爆")
	await capture_all("actual-windup",OPEN)
	# Use the actual saved next plan in the existing F3 defense drawer.
	game.night_plan=Encounter.new().make_plan("standard",2,SEED,0)
	game.day_number=2
	await press(KEY_F3); await click_ui(game.hud.details_tab_rect(3))
	check(game.hud.detail_tab=="defense","真实F3防线点击仍使用原抽屉")
	for viewport: Vector2i in VIEWS:
		root.size=viewport; root.content_scale_size=viewport; game.hud.queue_redraw(); await frames(4)
		var title:=false; var mechanic:=false
		for row: Dictionary in game.hud.burstling_labels:
			var value:=String(row.text)
			if value.contains("爆裂"): title=true
			if value.contains("1.4") or value.contains("2.4"): mechanic=true
			if row.point.x>=44 and row.point.x<=542 and row.point.y>=178 and row.point.y<=690:
				check(float(row.point.x)+float(row.width)<=550.0 and float(row.point.y)+float(row.descent)<=692.0,"实际防线中文字形在原抽屉边界: "+value)
		check(title and mechanic,"实际F3绘制爆裂体和真实秒数/半径说明")
		for character in "爆裂体蓄爆零件击杀投网": check(game.hud.font.has_char(character.unicode_at(0)),"实际字体支持中文 "+character)
		await capture("defense-details",OPEN)
	await press(KEY_F3); quiet_hud(); await frames()
	controller.clear()
	check(game.burstling_warning_snapshot().is_empty(),"清理后原危险环与HUD快照同时退休")
	# Later nights combine all finite supports in the same two-line rail. Use
	# the actual saved siege plans and existing day/night drawer branches;
	# these are explicit UI fixtures, never natural spawn/economy evidence.
	for night in [3,4]:
		game.day_number=night
		game.night_plan=Encounter.new().make_plan("siege",night,SEED,0)
		var planned_bursts:=0
		for entry: Dictionary in game.night_plan: planned_bursts+=int(entry.get("burstling_count",0))
		check(planned_bursts==2,"第三/四夜真实保存计划各两只爆裂体")
		for phase_name: String in ["day","night"]:
			game.phase=phase_name
			game.world.set_night(phase_name=="night")
			await press(KEY_F3); await click_ui(game.hud.details_tab_rect(3))
			check(game.hud.detail_tab=="defense","第三/四夜真实F3防线入口仍可点击")
			for viewport: Vector2i in VIEWS:
				root.size=viewport; root.content_scale_size=viewport
				game.hud.queue_redraw(); await frames(4)
				var rendered:=""
				var advice_rendered:=""
				var advice_rows: Array[Dictionary]=[]
				for row: Dictionary in game.hud.burstling_labels:
					var value:=String(row.text)
					if row.point.x>=44 and row.point.x<=542 and row.point.y>=178 and row.point.y<=690:
						rendered+=value+"\n"
						check(float(row.point.x)+float(row.width)<=550.0 and float(row.point.y)+float(row.descent)<=692.0,"最长夜3/4组合中文字形在原抽屉边界: "+value)
						if is_equal_approx(float(row.point.y),286.0) or is_equal_approx(float(row.point.y),308.0):
							advice_rows.append(row)
							advice_rendered+=value+"\n"
				if phase_name=="night":
					check(advice_rows.size()==2,"最长夜3/4完整威胁提示实际仅绘制286/308两行")
					for row: Dictionary in advice_rows:
						check(float(row.width)<=CleanHud.TEXT_WIDTH,"最长威胁提示完整字形落在原文本轨道宽度内")
					for phrase: String in ["爆裂1.4秒/2.4米","撤离","击杀","牵制/投网打断","召潮2.4秒/2援","织壳1秒/32盾4秒/最多3次","甲壳60甲/J破甲/C集火"]:
						check(advice_rendered.contains(phrase),"第三/四夜两行实际完整同时披露有限支援与反制: "+phrase)
				else:
					check(rendered.contains("爆裂%d只" % planned_bursts) and rendered.contains("1.4秒/2.4米"),"真实白昼预告披露后续两只、完整蓄爆时间与半径")
				await capture("defense-night%d-%s" % [night,phase_name],OPEN)
			await press(KEY_F3); quiet_hud(); await frames()
	root.size=VIEWS[0]; root.content_scale_size=VIEWS[0]
	stage_finished=true

func natural_policy() -> void:
	game.aim=game.hero.position+Vector3(0,0,8)
	if game.gate_pressure()>0: game.cast(0)
	if game.hero.hp<game.hero.max_hp*.6: game.cast(1); game.cast(4)
	if game.gate_pressure()>=6: game.cast(3)
	step(.1)

func natural_order_exists(orders: Array[Dictionary], token: int, kind: String) -> bool:
	return orders.any(func(row: Dictionary) -> bool: return int(row.token)==token and String(row.kind)==kind)

func natural_counter_receipts(orders: Array[Dictionary], members: Array[int], sources: Dictionary) -> Dictionary:
	var interceptions: Array[Dictionary]=[]
	var responses: Array[Dictionary]=[]
	for order: Dictionary in orders:
		if not bool(order.accepted): continue
		var token:=int(order.token)
		var after:=float(order.run_at)
		if String(order.kind)=="public-ranged-focus":
			var actual_hits:=0.0
			for row: Dictionary in wounds:
				if int(row.token)==token and int(row.source) in members and float(row.at)>=after:
					actual_hits+=float(row.hp_loss)+float(row.shield_loss)
			for row: Dictionary in deaths:
				if int(row.token)==token and int(row.source) in members and float(row.at)>=after and actual_hits>0.0:
					interceptions.append({"source":token,"order_at":after,"death_at":row.at,"killer":row.source,"actual_ranged_damage":actual_hits})
		elif String(order.kind)=="public-shield-retreat":
			var response:=order.duplicate(true)
			var actual: Array[Dictionary]=[]
			for start: Dictionary in order.members:
				var member_token:=int(start.token)
				var move: Dictionary=moves.get(member_token,{})
				if move.is_empty(): continue
				var final_raw: Array=move.get("final",move.origin)
				var final_point:=Vector3(float(final_raw[0]),float(final_raw[1]),float(final_raw[2]))
				var center_raw: Array=order.center
				var center:=Vector3(float(center_raw[0]),float(center_raw[1]),float(center_raw[2]))
				actual.append({"token":member_token,"start":start.point,"final":final_raw,
					"distance_after_order":maxf(0.0,float(move.distance)-float(start.distance)),
					"actual_steps_after_order":maxi(0,int(move.steps)-int(start.steps)),"final_separation":planar(final_point,center)})
			response["actual_movement"]=actual
			responses.append(response)
	var burst_damage:=0.0
	for row: Dictionary in wounds:
		if sources.has(int(row.source)) and int(row.token)!=int(row.source): burst_damage+=float(row.hp_loss)+float(row.shield_loss)
	return {"public_ranged_interceptions":interceptions,"retreat_responses":responses,"actual_burst_damage_to_friends":burst_damage,
		"natural_counter_proven":not interceptions.is_empty(),"scope":"counter true requires accepted public focus, actual ranged hurt and matching ranged-source death; retreat records alone do not prove a successful dodge"}

func natural_attempt(active: bool) -> Dictionary:
	if not await fresh(false): return {}
	var payments_start: int=(evidence.payments as Array).size()
	var result: Dictionary={"policy":"public-move-focus" if active else "dense-hold","seed":SEED,
		"original_parts":90,"original_night":105,"original_day":90,"supplemented_parts":false,
		"direct_actor_placement":false,"direct_enemy_damage":false,"extended_deadline":false}
	game.plan_hero_path(Vector3(0,5,10))
	var first_seconds:=0.0
	var cutoff: Dictionary={}
	for frame in 2400:
		if game.phase!="night": break
		natural_policy(); first_seconds+=.1
		if cutoff.is_empty() and first_seconds>=105.0: cutoff=Transition.deadline_evidence(game,first_seconds)
		if frame%100==99: await process_frame
	result.first_night={"seconds":first_seconds,"phase":String(game.phase),"parts":int(game.scrap),"kills":int(game.kills),"cutoff":cutoff}
	check(game.phase=="draft" and game.hero.alive and game.beacon_hp>0.0,"原技能策略真实度过首夜")
	if game.phase!="draft": result.status="opening_failed"; return result
	await press(KEY_1)
	check(game.phase=="day" and game.phase_time==90.0,"自然真实黎明原90秒白昼")
	var dawn: int=game.scrap
	if dawn<210:
		result.status="actual_budget_shortfall"; result.dawn_parts=dawn
		return result
	var barracks:=await build_gui("barracks")
	var shield:=await train_gui("shield")
	var ranged:=await train_gui("ranged")
	check(barracks>=0 and not shield.is_empty() and not ranged.is_empty(),"自然GUI60/70/80预算实际交付盾卫和弩手")
	if shield.is_empty() or ranged.is_empty(): result.status="actual_training_failed"; return result
	var ranged_tokens: Array[int]=[]
	for raw: Variant in ranged.members:
		if living(raw): ranged_tokens.append(raw.get_instance_id())
	check(game.scrap==dawn-210,"自然唯一钱包只支付三笔210，无补款")
	result.departure={"parts":int(game.scrap),"day_time":float(game.phase_time),"dawn_parts":dawn,"payments":[60,70,80]}
	var ids: Array[int]=[int(shield.id),int(ranged.id)]
	check(game.squads.select_ids(ids)==ids,"自然公开选择两真实生产小队")
	var destination:=Vector3(0,5,8.5)
	check(bool(game.squads.command_move(destination).ok),"自然公开移动形成密集守门站位")
	game.plan_hero_path(Vector3(0,5,10))
	for frame in 1000:
		if game.phase!="day": break
		natural_policy()
		if frame%100==99: await process_frame
	check(game.phase=="night" and game.day_number==2,"真实90秒白昼后进入原第二夜")
	var second_seconds:=0.0
	var active_orders: Array[Dictionary]=[]
	var seen_sources: Dictionary={}
	for frame in 800:
		if game.phase!="night": break
		for raw: Variant in game.enemies:
			if living(raw) and String(raw.get_meta("threat",""))=="burstling": seen_sources[raw.get_instance_id()]=true
		if active:
			for raw: Variant in game.get("burstlings"):
				if not is_instance_valid(raw): continue
				var state: Dictionary=raw.snapshot()
				var target: Variant=state.source
				if living(target) and not natural_order_exists(active_orders,target.get_instance_id(),"public-ranged-focus"):
					var ranged_ids: Array[int]=[int(ranged.id)]
					game.squads.select_ids(ranged_ids)
					var command: Dictionary=game.squads.command_attack(target)
					active_orders.append({"token":target.get_instance_id(),"at":second_seconds,"run_at":elapsed,"kind":"public-ranged-focus","accepted":bool(command.ok)})
				if String(state.phase)=="windup" and living(target) and not natural_order_exists(active_orders,target.get_instance_id(),"public-shield-retreat"):
					var shield_ids: Array[int]=[int(shield.id)]
					game.squads.select_ids(shield_ids)
					var retreat: Vector3=(state.position as Vector3)+Vector3(-5,0,-2)
					retreat.y=game.outpost_height(retreat)
					var response: Dictionary=game.squads.command_move(retreat)
					var start_members: Array[Dictionary]=[]
					for raw_member: Variant in shield.members:
						if not living(raw_member): continue
						var member_token: int=raw_member.get_instance_id()
						var move: Dictionary=moves.get(member_token,{})
						start_members.append({"token":member_token,"point":vec(raw_member.position),"distance":float(move.get("distance",0.0)),"steps":int(move.get("steps",0))})
					active_orders.append({"token":target.get_instance_id(),"at":second_seconds,"run_at":elapsed,"kind":"public-shield-retreat","accepted":bool(response.ok),
						"center":vec(state.position),"radius":float(state.radius),"remaining":float(state.remaining),"members":start_members,"hero_start":vec(game.hero.position)})
					game.plan_hero_path(Vector3(3.5,5,7))
		natural_policy(); second_seconds+=.1
		if frame%100==99: await process_frame
		if second_seconds>=45.0 and seen_sources.size()>0: break
	result.status="observed_real_second_wave" if seen_sources.size()>0 else "actual_burstling_not_reached"
	result.second_night={"seconds":second_seconds,"phase":String(game.phase),"parts":int(game.scrap),"time_left":float(game.phase_time),
		"hero_hp":game.hero.hp,"beacon_hp":game.beacon_hp,"born_burstlings":seen_sources.keys(),"orders":active_orders}
	result.births=births.duplicate(true); result.damage=wounds.duplicate(true); result.deaths=deaths.duplicate(true)
	result.casts=casts.duplicate(true); result.wallet_changes=wallets.duplicate(true)
	var movement: Array[Dictionary]=[]
	for token: Variant in moves.keys():
		var row: Dictionary=moves[token].duplicate(true)
		row.erase("last"); row["token"]=token
		movement.append(row)
	result.actual_member_movement=movement
	var payments: Array[Dictionary]=[]
	for index in range(payments_start,(evidence.payments as Array).size()): payments.append(evidence.payments[index])
	result.gui_payments=payments
	result.natural_burst_observed=seen_sources.size()>0
	result.natural_windup_observed=casts.any(func(row: Dictionary) -> bool: return int(row.night)==2 and String(row.phase)=="windup")
	result.counter_receipts=natural_counter_receipts(active_orders,ranged_tokens,seen_sources)
	result.natural_counter_proven=bool(result.counter_receipts.natural_counter_proven)
	await capture_all("natural-active" if active else "natural-dense",Vector3(0,5,9))
	print("BURSTLING_NATURAL ",JSON.stringify(result))
	return result

func economy() -> void:
	var dense:=await natural_attempt(false)
	var active:=await natural_attempt(true)
	(evidence.natural as Array).append(dense); (evidence.natural as Array).append(active)
	check(not dense.is_empty() and not active.is_empty(),"两条原规则自然尝试都保留真实结果")
	if not dense.has("departure") or not active.has("departure"): return
	check(dense.departure==active.departure,"成对策略相同种子/原首夜/付款和出发时刻")
	check(dense.gui_payments==active.gui_payments,"成对自然路线真实GUI支付严格相同")
	check(dense.second_night.born_burstlings.size()>0 and active.second_night.born_burstlings.size()>0,"两自然路线实际到达原第二夜爆裂体出生")
	# Actual outcomes are evidence, never assert an invented victory or require
	# active play to win before seeing both production trajectories.
	evidence["natural_comparison"]={"dense_status":dense.status,"active_status":active.status,
		"dense_counter_proven":dense.natural_counter_proven,"active_counter_proven":active.natural_counter_proven,
		"dense_actual_burst_damage":dense.counter_receipts.actual_burst_damage_to_friends,"active_actual_burst_damage":active.counter_receipts.actual_burst_damage_to_friends,
		"scope":"one fixed seed, legal public policy; neither fixture nor native Windows proof"}
	stage_finished=true

func finish(code: int = 0) -> void:
	if finished: return
	finished=true
	await close_game()
	for path: String in original_profile_hashes.keys():
		var now:=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
		check(now==String(original_profile_hashes[path]),"玩家原档案和备份保持原哈希")
	for suffix in ["", ".tmp", ".bak"]:
		var path: String=profile_path+suffix
		if FileAccess.file_exists(path): check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path))==OK,"只清理私有测试档案")
	evidence["checks"]=checks; evidence["failures"]=failures; evidence["completed"]=completed
	evidence["partial_case"]=selected_case; evidence["full_suite"]=selected_case.is_empty()
	if valid_output(output_dir):
		check(DirAccess.make_dir_recursive_absolute(output_dir)==OK,"固定build证据目录可写")
		var file:=FileAccess.open(output_dir.path_join("result.json"),FileAccess.WRITE)
		check(file!=null,"证据JSON创建成功")
		if file!=null: file.store_string(JSON.stringify(evidence,"\t")); file.close()
	var passed:=failures.is_empty() and code==0
	if passed and selected_case.is_empty(): print("NIGHTFALL_BURSTLING_OK checks=%d" % checks)
	elif passed: print("NIGHTFALL_BURSTLING_CASE_OK case=%s checks=%d full_suite=false" % [selected_case,checks])
	else: print("NIGHTFALL_BURSTLING_FAILED checks=%d failures=%d stage=%s" % [checks,failures.size(),stage])
	quit(0 if passed else 1)

func watchdog() -> void:
	if finished: return
	check(false,"360秒真实看门狗有界退出")
	await finish(1)

func run() -> void:
	var stages: Array[String]=["plan","production","burst","geometry","controls","lifecycle","hud","economy"]
	if not selected_case.is_empty() and selected_case not in stages:
		check(false,"--case只接受明确专项阶段"); await finish(1); return
	for name: String in stages:
		if not selected_case.is_empty() and name!=selected_case: continue
		stage=name
		stage_finished=false
		print("BURSTLING_STAGE ",stage)
		match name:
			"plan": await plan_and_ledger()
			"production": await production_and_priority()
			"burst": await burst_and_targets()
			"geometry": await geometry_and_buildings()
			"controls": await controls_and_artillery()
			"lifecycle": await lifecycle_and_reentry()
			"hud": await hud()
			"economy": await economy()
		check(stage_finished,"阶段必须实际执行至末尾；脚本异常或提前返回不得假计完整")
		if stage_finished: completed.append(name)
		print("BURSTLING_STAGE_DONE ",stage," checks=",checks," failures=",failures.size())
	await finish()
