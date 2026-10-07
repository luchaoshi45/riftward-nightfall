extends "res://tests/nightfall_selected_recall.gd"
## Only inherited real-GUI/private-archive/observation helpers are reused.
## The nine stages below are this test's complete coverage. Precision explicitly
## prepares money, positions and clocks; combat still uses the original weapons
## and three expedition guards. Natural never prepares money, actors or clocks.
const CAPTURE_STAGES := ["input","mixed","hold","combat","identity","reentry","lifecycle","hud","natural"]
const CHARGE_SECONDS := 12.0
const CHARGE_RADIUS := 5.0
var callback_receipts: Array[Dictionary] = []

func _initialize() -> void:
	profile_path="user://riftward-generator-capture-%d.json" % Time.get_ticks_usec()
	evidence={"seed":SEED,"scope":"nine generator-capture stages; inherited helper stages are not executed; native Windows unverified",
		"precision":{"parts":5000,"stationed_actors":true,"isolated_cooldowns":100000,"direct_hurt_fixture":true,"artificial_lifecycle":true},
		"payments":[],"captures":[],"natural":[],"precision_results":[],"weapon_results":[]}
	var args:=OS.get_cmdline_user_args()
	render_test="--render-test" in args
	var index:=args.find("--case")
	if index>=0 and index+1<args.size(): selected_case=args[index+1]
	var backend: String="headless" if DisplayServer.get_name()=="headless" else ("opengl" if RenderingServer.get_current_rendering_method()=="gl_compatibility" else "metal")
	output_dir=ProjectSettings.globalize_path("res://build/generator-capture/"+backend).simplify_path()
	index=args.find("--output-dir")
	if index>=0 and index+1<args.size():
		var candidate:=ProjectSettings.globalize_path(args[index+1]).simplify_path()
		if valid_output(candidate): output_dir=candidate
		else: check(false,"证据只写固定物理build/generator-capture目录")
	check(valid_output(output_dir),"固定证据路径及所有父目录无符号链接")
	for suffix: String in ["",".bak",".tmp"]:
		var path: String=Archive.PROFILE_PATH+suffix
		original_profile_hashes[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	for path: String in ["res://project.godot","res://export_presets.cfg"]:
		original_profile_hashes[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	root.size=VIEWS[0]; root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT; root.content_scale_size=VIEWS[0]
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.position=Vector2i(-10000,-10000); root.hide()
	root.child_entered_tree.connect(inject_archive)
	create_timer(480.0,true,false,true).timeout.connect(watchdog)
	call_deferred("run")

func valid_output(candidate: String) -> bool:
	var base:=ProjectSettings.globalize_path("res://build/generator-capture").simplify_path()
	if candidate!=base and not candidate.begins_with(base+"/"): return false
	var cursor:=candidate
	while cursor!=cursor.get_base_dir():
		var parent:=DirAccess.open(cursor.get_base_dir())
		if parent!=null and parent.is_link(cursor.get_file()): return false
		cursor=cursor.get_base_dir()
	return true

func capture_state() -> Dictionary:
	return game.expeditions.capture_snapshot()

func site_row(index: int = 0) -> Dictionary:
	for row: Dictionary in capture_state().sites:
		if int(row.index)==index: return row
	return {}

func capture_team(id: int) -> Dictionary:
	for row: Dictionary in capture_state().squads:
		if int(row.id)==id: return row
	return {}

func site_point(index: int = 0) -> Vector3:
	return game.expeditions.generators[index].position

func hold_fixture(squad: Dictionary, index: int = 0) -> void:
	var point:=site_point(index)
	station(squad,[point+Vector3(-1.25,0,0),point,point+Vector3(1.25,0,0)])
	select_one(squad)
	check(bool(game.squads.command_generator(index).ok),"精度原真实队显式绑定原发电机")

func mute_guards(index: int = 0) -> void:
	check(precision,"守卫冷却隔离仅用于明确精度段")
	for raw: Variant in game.expeditions.generators[index].guards:
		if living(raw): raw.attack_timer=100000.0

func guards_tokens(index: int = 0) -> Array[int]:
	var result: Array[int]=[]
	for raw: Variant in game.expeditions.generators[index].guards:
		if is_instance_valid(raw): result.append(raw.get_instance_id())
	return result

func real_death_rows(tokens: Array[int]) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for row: Dictionary in deaths:
		if int(row.token) in tokens: result.append(row)
	return result

func capture_input() -> void:
	if not await fresh() or not await day_fixture(): return
	if await build_gui("barracks")<0: return
	var chosen: Dictionary=await train_gui("ranged")
	var other: Dictionary=await train_gui("shield")
	if chosen.is_empty() or other.is_empty(): return
	var initial:=capture_state().duplicate(true)
	check(not bool(game.squads.command_generator(0).ok),"没有选择拒绝占领且不代控英雄")
	check(capture_state()==initial,"拒绝无选择不启动站点或改变绑定")
	select_one(chosen)
	check(not bool(game.squads.command_generator(-1).ok) and not bool(game.squads.command_generator(99).ok),"无效站号拒绝")
	var point:=site_point()
	check(game.expeditions.generator_at_point(point)==0,"真实站点中心命中原index")
	check(game.expeditions.generator_at_point(point+Vector3(3.399,0,0))==0 and game.expeditions.generator_at_point(point+Vector3(3.5,0,0))==-1,"有限3.4米命中区不抢附近地面令")
	station(chosen,[OPEN,OPEN+Vector3(2,0,0),OPEN+Vector3(-2,0,0)])
	quiet_hud(); camera_at(OPEN)
	await strategy_mouse(chosen.members[0].position,MOUSE_BUTTON_LEFT)
	check(game.squads.selected_ids==[int(chosen.id)],"真实战场左键选原训练队")
	var actors:=actor_state(chosen)
	var money: int=game.scrap
	camera_at(point)
	await strategy_mouse(point,MOUSE_BUTTON_RIGHT)
	check(chosen.order=="capture" and other.order=="recall","真实右键站点只给选队占领令")
	check(int(capture_state().count)==1 and int(capture_team(int(chosen.id)).site_index)==0,"只读快照绑定原队及原站")
	check(game.expeditions.generators[0].state=="ready" and float(game.expeditions.generators[0].progress)==0.0,"尚未抵达不远程开站或蓄能")
	check(game.scrap==money,"公开占领不收费或赠钱")
	var after:=actor_state(chosen)
	for index in actors.size():
		for field: String in ["token","hp","max_hp","damage","speed","armor","cooldown","position","growth"]:
			check(actors[index][field]==after[index][field],"命令不瞬移/回血/改属性或成长: "+field)
	step(.05)
	var marching:=actor_state(chosen)
	check(marching.any(func(row: Dictionary)->bool:return not (row.path as PackedVector3Array).is_empty()),"原导航实际建立站点行军路径")
	var snapshot:=capture_state().duplicate(true)
	await strategy_mouse(point,MOUSE_BUTTON_RIGHT)
	check(actor_state(chosen)==marching and capture_state()==snapshot,"重复同站真实右键幂等保持路径/冷却/绑定")
	for _read in 30: game.squads.capture_snapshot(); game.expeditions.capture_snapshot()
	check(actor_state(chosen)==marching and capture_state()==snapshot,"快照只读不推进时钟、充能或改演员")
	await strategy_mouse(point+Vector3(0,0,-6),MOUSE_BUTTON_RIGHT)
	check(chosen.order=="move" and int(capture_state().count)==0,"附近普通地面右键改令同步取消原绑定")
	select_one(chosen); check(bool(game.squads.command_generator(1).ok),"可公开改为另一真实站点")
	check(int(capture_team(int(chosen.id)).site_index)==1 and site_row(0).assigned_ids.is_empty(),"换站旧站即时解绑")
	await recall_key()
	check(chosen.order=="recall" and int(capture_state().count)==0,"原Alt+O明确撤回接管占领")
	(evidence.precision_results as Array).append({"stage":"input","chosen":int(chosen.id),"before":actors,"command":after,"marching":marching,"snapshot":snapshot})
	stage_finished=true

func capture_mixed() -> void:
	if not await fresh() or not await day_fixture(): return
	for kind: String in ["barracks","workshop","depot","laboratory"]:
		if await build_gui(kind)<0: return
	var hauler: Dictionary=await train_gui("hauler")
	var ranged: Dictionary=await train_gui("ranged")
	if hauler.is_empty() or ranged.is_empty(): return
	select_one(hauler)
	check(bool(game.logistics.command_selected_field(0).ok),"原公开指定有限废料堆")
	check(bool(game.logistics.prepare_selected_night_hauling().ok),"白昼原公开准备下一夜采运")
	if not await wait_until(func()->bool:return int(team_row(int(hauler.id)).cargo)>0,90.0,"原工队真实装载有限货物"): return
	var stock: Dictionary=game.logistics.snapshot().duplicate(true)
	var permits: Dictionary=game.logistics.night_haul_snapshot().duplicate(true)
	var raw_team: Dictionary=game.logistics.get("_teams")[int(hauler.id)].duplicate(true)
	var raw_cargo: Dictionary=game.logistics.get("_cargo").duplicate(true)
	var hauler_actors:=actor_state(hauler)
	var money: int=game.scrap
	var ids: Array[int]=[int(hauler.id),int(ranged.id)]
	check(game.squads.select_ids(ids)==ids,"公开混选活工队和原弩手")
	check(bool(game.squads.command_generator(0).ok),"混选仅派原非工队夺取站点")
	check(hauler.order=="haul" and ranged.order=="capture" and int(capture_state().count)==1,"工队原令与绑定排除保持")
	check(stock==game.logistics.snapshot() and permits==game.logistics.night_haul_snapshot(),"有限库存/货物/指定线/预约和夜采准备保持")
	check(raw_team==game.logistics.get("_teams")[int(hauler.id)] and raw_cargo==game.logistics.get("_cargo"),"原装卸时钟及逐员货账不变")
	check(actor_state(hauler)==hauler_actors and game.scrap==money,"混选工队原路径/生命/冷却及唯一钱包不变")
	select_one(hauler)
	check(not bool(game.squads.command_generator(1).ok),"纯工队不能冒充占领部队")
	check(stock==game.logistics.snapshot() and permits==game.logistics.night_haul_snapshot() and actor_state(hauler)==hauler_actors,"拒绝纯工队完整保原工作")
	(evidence.precision_results as Array).append({"stage":"mixed","stock":stock,"permits":permits,"cargo":raw_cargo,"hauler":hauler_actors,"capture":capture_state()})
	stage_finished=true

func capture_hold() -> void:
	if not await fresh() or not await day_fixture(): return
	if await build_gui("barracks")<0: return
	var first: Dictionary=await train_gui("ranged")
	var second: Dictionary=await train_gui("shield")
	if first.is_empty() or second.is_empty(): return
	hold_fixture(first); hold_fixture(second)
	stand_hero(site_point())
	var money: int=game.scrap
	var cells: int=game.generator_cells
	step(.05); mute_guards()
	var site: Dictionary=game.expeditions.generators[0]
	var tokens:=guards_tokens()
	check(site.state=="active" and tokens.size()==3,"原成员进入5米圈自动开站并实际生成原三守卫")
	check(site_row().hero_inside and int(site_row().arrived)==6 and int(capture_state().count)==2,"英雄和两原三员队同时在圈内")
	var guards_before: Array[Dictionary]=[]
	for raw: Variant in site.guards:
		if living(raw): guards_before.append({"token":raw.get_instance_id(),"hp":raw.hp,"max_hp":raw.max_hp,"damage":raw.damage,"armor":raw.armor,"speed":raw.speed})
	for _frame in 240:
		var before: float=site.progress
		step()
		near(float(site.progress),minf(CHARGE_SECONDS,before+STEP),"英雄与多队守圈只按一次原delta充能")
	check(site.state=="active" and float(site.progress)==CHARGE_SECONDS and int(site_row().guards_alive)==3,"原12秒封顶但三守卫仍活不能完成")
	check(game.scrap==money and game.generator_cells==cells,"仅守圈不结算100或能源芯")
	stand_hero(Vector3(-11,5,-10))
	select_one(first); check(bool(game.squads.command_move(site_point()+Vector3(0,0,-12)).ok),"一队公开离圈取消其身份")
	check(int(capture_state().count)==1 and not bool(capture_team(int(second.id)).is_empty()),"另一原活队保持独立绑定")
	for raw: Variant in site.guards.duplicate():
		if living(raw): raw.hurt(100000.0,game.hero)
	step()
	var actual_deaths:=real_death_rows(tokens)
	check(actual_deaths.size()==3 and actual_deaths.all(func(row: Dictionary)->bool:return not bool(row.alive) and float(row.hp)==0.0),"精度守卫准备经过原真实hp0死亡回调")
	check(site.state=="complete" and game.scrap==money+115 and game.generator_cells==cells+1,"原三死亡15与一次原100/芯各自结算")
	check(second.order=="guard" and int(capture_state().count)==0,"完成转原地点驻守并解绑，不接另一站")
	var paid: int=game.scrap
	for _repeat in 20: game.expeditions.complete_generator(site); game.expeditions.tick(.05)
	check(game.scrap==paid and game.generator_cells==cells+1 and not bool(game.squads.command_generator(0).ok),"重复完成/ tick/已完成站指令不重复发奖")
	check(int(game.expeditions.generator_at_point(site_point()))==-1,"完成站不吞普通地面右键")
	(evidence.precision_results as Array).append({"stage":"hold","guards_before":guards_before,"guard_deaths":actual_deaths,"parts_before":money,"parts_after":paid,"cells_before":cells,"cells_after":int(game.generator_cells)})
	stage_finished=true

func capture_combat() -> void:
	if not await fresh() or not await day_fixture(): return
	if await build_gui("barracks")<0: return
	var shield: Dictionary=await train_gui("shield")
	var ranged: Dictionary=await train_gui("ranged")
	if shield.is_empty() or ranged.is_empty(): return
	var initial_shield:=actor_state(shield)
	var initial_ranged:=actor_state(ranged)
	for squad: Dictionary in [shield,ranged]:
		for raw: Variant in squad.members:
			if living(raw): raw.attack_timer=0.0
	var ids: Array[int]=[int(shield.id),int(ranged.id)]
	check(game.squads.select_ids(ids)==ids,"公开选择真实训练两队出城")
	camera_at(site_point()); await strategy_mouse(site_point(),MOUSE_BUTTON_RIGHT)
	check(shield.order=="capture" and ranged.order=="capture","真实右键发电机接受两队")
	var money: int=game.scrap
	var cells: int=game.generator_cells
	var crossed: Dictionary={}
	var tokens: Array[int]=[]
	var guard_births: Array[Dictionary]=[]
	var steps:=0
	var first_charge:=0.0
	var first_activation:=-1.0
	var guard_target_proven:=false
	var hero_origin: Vector3=game.hero.position
	for frame in 2400:
		if game.phase!="day" or game.expeditions.generators[0].state=="complete": break
		var positions: Dictionary={}
		for squad: Dictionary in [shield,ranged]:
			for raw: Variant in squad.members:
				if living(raw): positions[raw.get_instance_id()]={"position":raw.position,"speed":raw.speed}
		var before: float=game.expeditions.generators[0].progress
		step(); steps+=1
		for squad: Dictionary in [shield,ranged]:
			for raw: Variant in squad.members:
				if not living(raw) or not positions.has(raw.get_instance_id()): continue
				var previous: Dictionary=positions[raw.get_instance_id()]
				var moved:=planar(previous.position,raw.position)
				check(moved<=float(previous.speed)*STEP+.001,"真实行军每步保持原移速")
				if moved>.00001: check(game.can_traverse(previous.position,raw.position),"真实行军每步不穿城墙/建筑/坡道")
				if (previous.position as Vector3).z<Layout.RAMP_TOP and raw.position.z>=Layout.RAMP_TOP: crossed[raw.get_instance_id()]=true
		var site: Dictionary=game.expeditions.generators[0]
		check(float(site.progress)-before<=STEP+.001,"实战多队原delta充能不叠加")
		if site.state=="active" and first_activation<0.0:
			first_activation=elapsed; first_charge=float(site.progress); tokens=guards_tokens()
			for token: int in tokens:
				for birth: Dictionary in births:
					if int(birth.token)==token: guard_births.append(birth)
		for raw: Variant in site.guards:
			if not living(raw): continue
			var target: Dictionary=game.choose_enemy_target(raw)
			if String(target.get("kind",""))=="squad" and is_instance_valid(target.get("unit")):
				var unit: BattleUnit=target.unit
				check(unit in shield.members or unit in ranged.members,"站点守卫只追真实原占领成员")
				guard_target_proven=true
		if frame%100==99: await process_frame
	var complete: bool=game.expeditions.generators[0].state=="complete"
	check(complete,"真实生产武器/三守卫战斗与原12秒达到完整占领")
	check(crossed.size()==6,"六原训练成员实际经南门向外通过")
	check(tokens.size()==3 and guard_births.size()==3,"真实开站只生成三名原守卫")
	check(guard_target_proven,"原守卫实际锁定占领单位，英雄可留城")
	near(planar(game.hero.position,hero_origin),0.0,"真实占领段英雄始终留在原城内位置")
	var actual_deaths:=real_death_rows(tokens)
	check(actual_deaths.size()==3 and actual_deaths.all(func(row: Dictionary)->bool:return float(row.hp)==0.0 and not bool(row.alive)),"三原守卫均实际hp0死亡，未删除演员代清场")
	var troop_damage:=0.0
	var troop_tokens: Array[int]=[]
	for member: Dictionary in initial_shield+initial_ranged: troop_tokens.append(int(member.token))
	for row: Dictionary in wounds:
		if int(row.token) in tokens and int(row.source) in troop_tokens: troop_damage+=float(row.hp_loss)
	check(troop_damage>0.0,"实际原武器确认造成守卫生命损失")
	check(game.scrap==money+115 and game.generator_cells==cells+1,"完整实战只支付原15死亡与原100/一芯奖励")
	check(first_activation>=0.0 and elapsed-first_activation+first_charge>=CHARGE_SECONDS-.001,"实际完成经过原12秒驻圈时间")
	(evidence.weapon_results as Array).append({"stage":"combat","precision":true,"clock_extended_fixture":true,"initial_shield":initial_shield,"initial_ranged":initial_ranged,
		"guard_births":guard_births,"guard_deaths":actual_deaths,"guard_hp_damage_by_original_troops":troop_damage,"crossed_gate":crossed.size(),"steps":steps,
		"activation_at":first_activation,"completed_at":elapsed,"original_guard_target_proven":guard_target_proven,"complete":complete,"parts_before":money,"parts_after":int(game.scrap),"snapshot":capture_state()})
	stage_finished=true

func capture_identity() -> void:
	if not await fresh() or not await day_fixture(): return
	if await build_gui("barracks")<0: return
	var original: Dictionary=await train_gui("ranged")
	var donor: Dictionary=await train_gui("ranged")
	if original.is_empty() or donor.is_empty(): return
	hold_fixture(original); step(.05); mute_guards()
	var site: Dictionary=game.expeditions.generators[0]
	var charge: float=site.progress
	var old_members: Array=original.members.duplicate()
	var donor_members: Array=donor.members.duplicate()
	original.members=donor_members; donor.members=old_members
	check(int(capture_state().count)==0 and int(site_row().holders)==0,"原同Dictionary/同号队换全部槽演员不继承旧占领身份")
	game.expeditions.tick(.25)
	near(float(site.progress),charge,"换原槽身份不能继续旧守圈")
	original.members=old_members; donor.members=donor_members
	select_one(original); check(bool(game.squads.command_generator(0).ok),"显式新令可重新登记当前原成员")
	var clone: Dictionary=original.duplicate(true)
	var index: int=game.squads.squads.find(original)
	game.squads.squads[index]=clone
	check(int(clone.id)==int(original.id) and not is_same(clone,original) and int(capture_state().count)==0,"同数字ID新Dictionary不继承旧绑定")
	game.expeditions.tick(.25); near(float(site.progress),charge,"同号新字典不能持旧圈")
	game.squads.squads[index]=original
	select_one(original); check(bool(game.squads.command_generator(0).ok),"还原正式原字典需再次显式下令")
	var new_site: Dictionary=site.duplicate(true)
	game.expeditions.generators[0]=new_site
	check(int(capture_state().count)==0,"同index新站Dictionary拒绝旧绑定")
	game.expeditions.tick(.25); near(float(new_site.progress),charge,"旧站令不能推进同号新站")
	var wallet: int=game.scrap
	game.expeditions.complete_generator(site)
	check(game.scrap==wallet and game.generator_cells==0,"不属于当前数组的旧站不能发奖")
	game.expeditions.generators[0]=site
	select_one(original); check(bool(game.squads.command_generator(0).ok),"原站恢复后显式重令")
	var old_id:=int(original.id)
	var old_token: int=old_members[0].get_instance_id()
	game.squads.setup(game,true); await frames()
	check(int(capture_state().count)==0,"原roster重新setup代际使旧绑定退役")
	var replacement: Dictionary=await train_gui("ranged")
	if replacement.is_empty(): return
	check(int(replacement.id)==old_id and replacement.members[0].get_instance_id()!=old_token,"同号新队经过再次GUI付款与完整训练")
	check(replacement.order!="capture" and int(capture_state().count)==0,"真实新同号Actor不继承任务")
	(evidence.precision_results as Array).append({"stage":"identity","same_numeric_id":old_id,"original_member_token":old_token,"retrained_token":replacement.members[0].get_instance_id(),"same_dictionary_slots_rejected":true,"new_dictionary_rejected":true,"new_site_rejected":true})
	stage_finished=true

func refill_during_death(_victim: BattleUnit, _source: BattleUnit, squad_id: int) -> void:
	var wallet: int=game.scrap
	var receipt: Dictionary=game.squads.refill(squad_id)
	callback_receipts.append({"kind":"paid-refill-during-real-death","ok":bool(receipt.ok),"before":wallet,"after":int(game.scrap),"capture":capture_state().duplicate(true)})

func capture_reentry() -> void:
	if not await fresh() or not await day_fixture(): return
	if await build_gui("barracks")<0: return
	var squad: Dictionary=await train_gui("ranged")
	if squad.is_empty(): return
	hold_fixture(squad); step(.05); mute_guards()
	var tokens: Array[int]=capture_team(int(squad.id)).member_tokens
	var charge: float=game.expeditions.generators[0].progress
	callback_receipts.clear()
	for slot in 3:
		var old: BattleUnit=squad.members[slot]
		old.defeated.connect(refill_during_death.bind(int(squad.id)))
		old.hurt(100000.0,game.hero)
		check(living(squad.members[slot]) and squad.members[slot].get_instance_id()!=tokens[slot],"原死亡回调同步付费产生同槽新Actor")
	check(callback_receipts.size()==3 and callback_receipts.all(func(row: Dictionary)->bool:return bool(row.ok) and int(row.before)-int(row.after)==26),"三次同步补员各真实支付原26")
	check(int(capture_state().count)==0 and int(site_row().holders)==0,"原三员真死后同期新槽不继承持圈")
	game.expeditions.tick(.25)
	near(float(game.expeditions.generators[0].progress),charge,"真死亡中同步替换全部槽不继续旧充能")
	select_one(squad); check(bool(game.squads.command_generator(0).ok),"玩家重新显式下令可登记三真实付费新人")
	var newer: Array[int]=capture_team(int(squad.id)).member_tokens
	check(newer.size()==3 and newer.all(func(token: int)->bool:return token not in tokens),"新令成员身份全是付费新演员")
	var old_roster: Node3D=game.squads
	var replacement: Node3D=load("res://scripts/outpost_squads.gd").new()
	game.add_child(replacement); replacement.setup(game,true); game.squads=replacement
	var actor_before:=actor_state(squad)
	check(int(game.expeditions.capture_snapshot().count)==0 and int(old_roster.capture_snapshot().count)==0,"同controller换正式roster立即拒绝旧归属")
	old_roster.advance(.25); game.expeditions.tick(.25)
	check(actor_state(squad)==actor_before,"旧roster不接管新正式roster期间仍推进旧演员")
	near(float(game.expeditions.generators[0].progress),charge,"旧roster不能继续持圈")
	old_roster.clear(); await frames()
	var retrained: Dictionary=await train_gui("ranged")
	if retrained.is_empty(): return
	check(int(retrained.id)==int(squad.id) and int(capture_state().count)==0 and retrained.order!="capture","换正式roster的新同号队须独立付费且不继承")
	(evidence.precision_results as Array).append({"stage":"reentry","old_tokens":tokens,"new_tokens":newer,"synchronous_paid_refills":callback_receipts.duplicate(true),"replacement_roster":replacement.get_instance_id()})
	stage_finished=true

func capture_lifecycle() -> void:
	if not await fresh() or not await day_fixture(): return
	if await build_gui("barracks")<0: return
	var squad: Dictionary=await train_gui("ranged")
	if squad.is_empty(): return
	hold_fixture(squad); step(.05); mute_guards()
	var actors:=actor_state(squad)
	var site: Dictionary=game.expeditions.generators[0]
	var charge: float=site.progress
	var old_guards: Array=site.guards.duplicate()
	await press(KEY_ESCAPE); await press(KEY_ESCAPE)
	check(game.phase=="paused","真实Esc取消选择后暂停")
	select_one(squad)
	check(not bool(game.squads.command_generator(1).ok),"暂停拒绝公开占领新令")
	game.simulate(10.0); game.squads.advance(10.0)
	check(actor_state(squad)==actors and site.state=="active","暂停原行军/武器/生命与站态完全冻结")
	near(float(site.progress),charge,"暂停不消耗原驻圈时长")
	game.squads.cancel_selection(); await press(KEY_ESCAPE)
	check(game.phase=="day" and int(capture_state().count)==1,"真实恢复后仍绑定原队原站")
	game.run.grant("精度发电机选卡冻结验证"); game.open_draft()
	check(game.phase=="draft","真实局内待选卡入口")
	select_one(squad)
	check(not bool(game.squads.command_generator(1).ok),"选卡拒绝公开占领新令")
	game.simulate(10.0); game.squads.advance(10.0)
	check(actor_state(squad)==actors and site.state=="active","选卡保原队而完整冻结")
	near(float(site.progress),charge,"选卡不偷加充能")
	await press(KEY_1)
	check(game.phase=="day" and int(capture_state().count)==1,"真实选卡回原白昼继续旧绑定")
	game.phase_time=.01; step(.02)
	check(game.phase=="night" and squad.order=="hold" and int(capture_state().count)==0,"真实日落退役占领并走原驻守")
	check(site.state=="ready" and float(site.progress)==0.0 and not site.ring.visible,"未完成站按原日落归零而次日可重试")
	check(not bool(game.squads.command_generator(0).ok) and game.expeditions.generator_at_point(site_point())==-1,"夜间指令及站点命中均拒绝")
	for raw: Variant in old_guards:
		if is_instance_valid(raw): check(not game.expeditions.is_generator_guard(raw),"日落原守卫身份已退役")
	if not await day_fixture(): return
	select_one(squad); check(bool(game.squads.command_generator(0).ok),"次日原活队需新显式命令")
	var scene:=game.get_instance_id()
	game.end_defeat("精度占领败局清理")
	check(game.phase=="ended" and game.squads.squads.is_empty() and int(capture_state().count)==0,"真实失败清理原队及占领身份")
	check(not bool(game.squads.command_generator(0).ok),"结束后拒绝公开占领")
	await press(KEY_ENTER)
	for _frame in 200:
		if current_scene!=null and current_scene.get_instance_id()!=scene: break
		await create_timer(.02,true,false,true).timeout
	check(current_scene!=null and current_scene.get_instance_id()!=scene,"真实Enter重试换新场景")
	if current_scene==null or current_scene.get_instance_id()==scene: return
	game=current_scene as Node3D; game.set_process(false); game.world.set_process(false)
	check(game.phase=="draft" and game.archive.path==profile_path and game.scrap==90 and game.squads.squads.is_empty() and int(capture_state().count)==0,"重试原90开局、私有档案和新站无旧任务")
	if not await fresh() or not await day_fixture(): return
	if await build_gui("barracks")<0: return
	var victor: Dictionary=await train_gui("ranged")
	if victor.is_empty(): return
	hold_fixture(victor); step(.05); mute_guards()
	game.day_number=game.max_nights()
	check(Transition.finish_for_fixture(game),"明确人工末夜生命周期通过原清场交接入口")
	check(game.phase=="ended" and game.victory and game.squads.squads.is_empty() and int(capture_state().count)==0,"真实胜利入口清理占领，不当自然获胜证据")
	if not await fresh() or not await day_fixture(): return
	if await build_gui("barracks")<0: return
	var closing: Dictionary=await train_gui("ranged")
	if closing.is_empty(): return
	hold_fixture(closing); step(.05)
	var expedition: Node3D=game.expeditions
	await game.prepare_shutdown()
	check(int(expedition.capture_snapshot().count)==0 and game.shutting_down,"真实关闭入口先退役占领绑定")
	await close_game()
	check(not is_instance_valid(expedition),"关闭后原远征模块随实际场景释放")
	(evidence.precision_results as Array).append({"stage":"lifecycle","paused_charge":charge,"actual_sunset_reset":true,"defeat_and_enter_retry":true,"artificial_final_victory_cleanup":true,"real_close_cleanup":true})
	stage_finished=true

func drawn_bounds(label: String, detail: bool) -> void:
	for row: Dictionary in game.hud.get("veterancy_labels"):
		var point: Vector2=row.point
		var text: String=row.text
		check(point.x>=0.0 and point.x+float(row.width)<=1441.0 and point.y+float(row.descent)<=901.0,label+"实际字体留在逻辑视口")
		for character: String in text:
			var code:=character.unicode_at(0)
			if code>=0x4e00 and code<=0x9fff: check(game.hud.font.has_char(code),label+"中文字体存在实际字形: "+character)
		if not detail or point.x<CleanHud.TEXT_X or point.x>CleanHud.TEXT_X+CleanHud.TEXT_WIDTH or point.y<165.0: continue
		if text in ["收起详情","查看详细说明","返回快捷操作"]: continue
		if point.y>CleanHud.DRAWER_CLOSE_RECT.position.y: continue
		check(float(row.width)<=CleanHud.TEXT_WIDTH+.001,label+"真实正文单行不越原抽屉宽度")
		check(point.y+float(row.descent)<CleanHud.DRAWER_CLOSE_RECT.position.y-5.0,label+"真实正文与原关闭/展开按钮保留间隙")

func capture_hud() -> void:
	if not await fresh() or not await day_fixture(): return
	if await build_gui("barracks")<0: return
	var squad: Dictionary=await train_gui("ranged")
	if squad.is_empty(): return
	quiet_hud(); camera_at(site_point()); await frames()
	var baseline:=stable_rects()
	select_one(squad); check(bool(game.squads.command_generator(0).ok),"真实可玩占领命令用于HUD")
	var selected_rects:=stable_rects()
	for viewport: Vector2i in VIEWS:
		root.size=viewport; root.content_scale_size=viewport
		game.notice_time=0.0; game.hud.queue_redraw(); await frames()
		check(stable_rects()==selected_rects,"占领仅复用原选队短条，不增常驻面板")
		check(drawn_text().contains("夺取1队") and drawn_text().contains("右键改令") and drawn_text().contains("Alt+O"),"实际所选短条明确占领状态与撤令入口")
		drawn_bounds("所选短条",false)
		await capture("selected-generator-short-strip",site_point())
		await press(KEY_F3); await click_ui(game.hud.details_tab_rect(1)); await frames()
		var actual:=drawn_text()
		for phrase: String in ["地图争夺","白昼选队右键发电机","1号","2号","3号","部队行军中","守圈12秒","多队不加速","日落中断"]:
			check(actual.contains(phrase),"实际探索页完整披露原站及规则: "+phrase)
		drawn_bounds("探索页",true)
		var before:=capture_state().duplicate(true)
		var actors:=actor_state(squad)
		var money: int=game.scrap
		await mouse(CleanHud.DRAWER_RECT.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900),MOUSE_BUTTON_RIGHT)
		check(capture_state()==before and actor_state(squad)==actors and game.scrap==money,"F3探索正文真实右键不穿透为移动/占领或经济操作")
		await capture("f3-generator-stations-marching",site_point())
		await click_ui(game.hud.details_tab_rect(4)); await frames()
		check(drawn_text().contains("白昼选队右键发电机") and drawn_text().contains("Alt+右键工队护航"),"真实速查新增发电机同时保留护航")
		drawn_bounds("速查帮助",true)
		await capture("help-generator-shortcuts",site_point())
		await click_ui(game.hud.HELP_TOGGLE_RECT); await frames()
		check(game.hud.help_details_open and drawn_text().contains("守圈12秒并清守") and drawn_text().contains("日落中断"),"完整帮助披露真实守圈和守卫条件")
		drawn_bounds("完整帮助",true)
		await capture("help-generator-full",site_point())
		await press(KEY_F3); game.squads.cancel_selection(); game.hud.queue_redraw(); await frames()
		check(stable_rects()==baseline and not drawn_text().contains("夺取1队"),"收起详情和选队恢复原清爽默认矩形")
		await capture("default-generator-order-dismissed",site_point())
		select_one(squad)
	root.size=VIEWS[0]; root.content_scale_size=VIEWS[0]
	# An explicit production-reward fixture activates the longest existing buffs
	# and four actual toasts. It is never used in the natural economic route.
	check(precision,"拥挤探索收益仅为明确HUD精度夹具")
	var point:=Vector3(45,0,45)
	game.exploration.set_waylight_count(2)
	game.hero.hp-=120.0; game.mana-=100.0
	game.exploration.arm_contract_affinity(["ember_bloom"])
	game.grant_exploration_reward("余烬花",point,34,18,24,"ember_bloom")
	game.grant_exploration_reward("余烬晶簇",point,47,15,22,"memory_crystal")
	game.grant_exploration_reward("补给箱",point,78,25,32,"supply_cache")
	game.grant_exploration_reward("灯碑",point,56,22,30,"waylight")
	game.exploration.arm_contract_affinity(game.exploration.ROUTE_KINDS)
	check(game.exploration.affinity_active() and game.exploration.network_active() and game.exploration.speed_bonus_value()>0.0 and game.reward_toasts.size()==4,"真实生产奖励入口形成共鸣/灯网/加速和四条收益状态")
	await press(KEY_F3); await click_ui(game.hud.details_tab_rect(1))
	for viewport: Vector2i in VIEWS:
		root.size=viewport; root.content_scale_size=viewport; game.hud.queue_redraw(); await frames()
		var actual:=drawn_text()
		for phrase: String in ["共鸣","加速","灯网","最近收益","地图争夺","1号","2号","3号"]:
			check(actual.contains(phrase),"拥挤真实探索页仍绘制所需信息: "+phrase)
		drawn_bounds("四收益+全buff探索页",true)
		await capture("f3-generator-crowded-exploration",site_point())
	root.size=VIEWS[0]; root.content_scale_size=VIEWS[0]
	await press(KEY_F3)
	hold_fixture(squad); step(.05); mute_guards(); game.notice_time=0.0
	await press(KEY_F3); await click_ui(game.hud.details_tab_rect(1))
	await capture_all("f3-generator-active-three-real-guards",site_point())
	(evidence.precision_results as Array).append({"stage":"hud","original_default_rects":baseline,"selected_rects":selected_rects,"crowded_production_reward_fixture":true,"active_station":site_row()})
	stage_finished=true

func capture_natural() -> void:
	if not await fresh(false): return
	var payments_start: int=(evidence.payments as Array).size()
	var result: Dictionary={"policy":"original-shield-and-crossbow-capture-hero-stays-fort","seed":SEED,"original_parts":90,"original_night":105,"original_day":90,
		"supplemented_parts":false,"direct_actor_placement":false,"direct_enemy_damage":false,"changed_actor_attributes":false,"extended_deadline":false,
		"natural_capture_proven":false,"natural_all_original_members_survived":false,"natural_hero_stayed_in_fort":false}
	game.plan_hero_path(Vector3(0,5,10))
	var seconds:=0.0
	var cutoff: Dictionary={}
	for frame in 2600:
		if game.phase!="night": break
		natural_policy(); seconds+=.1
		if cutoff.is_empty() and seconds>=105.0: cutoff=Transition.deadline_evidence(game,seconds)
		if frame%100==99: await process_frame
	result.first_night={"seconds":seconds,"phase":String(game.phase),"parts":int(game.scrap),"kills":int(game.kills),"cutoff":cutoff}
	check(game.phase=="draft" and game.hero.alive and game.beacon_hp>0.0,"原技能与原105秒时钟真实度过首夜才训练出征")
	if game.phase!="draft":
		result.status="opening_failed"; (evidence.natural as Array).append(result); stage_finished=true; return
	await press(KEY_1)
	check(game.phase=="day" and game.phase_time==90.0,"真实首黎明保原完整90秒白昼")
	var dawn: int=game.scrap
	check(dawn==269,"固定原首夜自然策略实际收入269，没有补钱包")
	if dawn<210:
		result.status="actual_budget_shortfall"; (evidence.natural as Array).append(result); stage_finished=true; return
	var barracks:=await build_gui("barracks")
	var shield: Dictionary=await train_gui("shield")
	var ranged: Dictionary=await train_gui("ranged")
	check(barracks>=0 and not shield.is_empty() and not ranged.is_empty(),"自然GUI建营与真实完整付费训练两队")
	if shield.is_empty() or ranged.is_empty():
		result.status="actual_training_failed"; (evidence.natural as Array).append(result); stage_finished=true; return
	check(game.scrap==dawn-210 and game.scrap==59,"真实60+70+80三笔唯一钱包支出后原59")
	result.departure={"parts":int(game.scrap),"day_time":float(game.phase_time),"dawn_parts":dawn,"payments":[60,70,80],"shield":actor_state(shield),"ranged":actor_state(ranged),"hero_position":vec(game.hero.position)}
	var ids: Array[int]=[int(shield.id),int(ranged.id)]
	check(game.squads.select_ids(ids)==ids,"自然公开选择实际训练原两队")
	camera_at(site_point()); await strategy_mouse(site_point(),MOUSE_BUTTON_RIGHT)
	var accepted: bool=shield.order=="capture" and ranged.order=="capture" and int(capture_state().count)==2
	check(accepted,"自然实际右键发电机，未摆部队")
	result.command={"accepted":accepted,"site_index":0,"point":vec(site_point()),"after_command_shield":actor_state(shield),"after_command_ranged":actor_state(ranged),"at":elapsed}
	game.squads.cancel_selection()
	# The hero may remain in the fort and issue a legal original hero path. No
	# hero attack/skill is used to kill the station's guards during this daylight.
	game.plan_hero_path(Vector3(0,5,4))
	var member_tokens: Array[int]=[]
	for squad: Dictionary in [shield,ranged]:
		for raw: Variant in squad.members:
			if living(raw): member_tokens.append(raw.get_instance_id())
	var crossed: Dictionary={}
	var original_guards: Array[int]=[]
	var guard_births: Array[Dictionary]=[]
	var activation: Dictionary={}
	var completion: Dictionary={}
	var charge_history: Array[Dictionary]=[]
	var previous_state:="ready"
	var maximum_charge_step:=0.0
	var hero_left_fort:=false
	var guards_hero_hp_damage:=0.0
	for frame in 1000:
		if game.phase!="day": break
		var positions: Dictionary={}
		for squad: Dictionary in [shield,ranged]:
			for raw: Variant in squad.members:
				if living(raw): positions[raw.get_instance_id()]={"point":raw.position,"speed":raw.speed}
		var progress: float=game.expeditions.generators[0].progress
		step(.1)
		for squad: Dictionary in [shield,ranged]:
			for raw: Variant in squad.members:
				if not living(raw) or not positions.has(raw.get_instance_id()): continue
				var before: Dictionary=positions[raw.get_instance_id()]
				var moved:=planar(before.point,raw.position)
				check(moved<=float(before.speed)*.1+.001,"自然原成员每步不加速")
				if moved>.00001: check(game.can_traverse(before.point,raw.position),"自然原成员每步真实可达不穿墙")
				if (before.point as Vector3).z<Layout.RAMP_TOP and raw.position.z>=Layout.RAMP_TOP: crossed[raw.get_instance_id()]=true
		if game.phase=="day":
			var station: Dictionary=game.expeditions.generators[0]
			var gained: float=float(station.progress)-progress
			maximum_charge_step=maxf(maximum_charge_step,gained)
			check(gained<=.1+.001,"自然多队守圈最多一倍原delta")
			var row:=site_row().duplicate(true)
			if String(station.state)!=previous_state or frame%10==0:
				row["at"]=elapsed; row["day_time"]=float(game.phase_time); charge_history.append(row)
			previous_state=String(station.state)
			if station.state=="active" and activation.is_empty():
				original_guards=guards_tokens()
				activation={"at":elapsed,"day_time":float(game.phase_time),"parts":int(game.scrap),"snapshot":row}
				for token: int in original_guards:
					for born: Dictionary in births:
						if int(born.token)==token: guard_births.append(born)
			if station.state=="complete" and completion.is_empty():
				completion={"at":elapsed,"day_time":float(game.phase_time),"parts":int(game.scrap),"generator_cells":int(game.generator_cells),"snapshot":row}
		if game.hero.position.y<=4.8: hero_left_fort=true
		if not completion.is_empty(): break
		if frame%100==99: await process_frame
	var actual_deaths:=real_death_rows(original_guards)
	var troop_damage:=0.0
	for wound: Dictionary in wounds:
		if int(wound.token) not in original_guards: continue
		if int(wound.source) in member_tokens: troop_damage+=float(wound.hp_loss)
		if int(wound.source)==game.hero.get_instance_id(): guards_hero_hp_damage+=float(wound.hp_loss)
	var survivors: Array[Dictionary]=[]
	for squad: Dictionary in [shield,ranged]: survivors.append_array(actor_state(squad))
	var original_survivors:=0
	for member: Dictionary in survivors:
		if int(member.token) in member_tokens: original_survivors+=1
	result.status="real_daytime_capture" if not completion.is_empty() else ("real_defeat" if game.phase=="ended" else "original_sunset_without_capture")
	result.activation=activation; result.completion=completion; result.guard_births=guard_births; result.original_guard_tokens=original_guards; result.original_guard_deaths=actual_deaths
	result.actual_original_troop_guard_hp_damage=troop_damage; result.hero_guard_hp_damage=guards_hero_hp_damage
	result.original_member_tokens=member_tokens; result.original_survivors=original_survivors; result.end_members=survivors
	result.crossed_gate=crossed.size(); result.maximum_charge_delta=maximum_charge_step; result.charge_history=charge_history
	result.natural_hero_stayed_in_fort=not hero_left_fort
	result.natural_capture_proven=not completion.is_empty() and original_guards.size()==3 and actual_deaths.size()==3 and troop_damage>0.0 and guards_hero_hp_damage==0.0 and game.generator_cells==1
	result.natural_all_original_members_survived=original_survivors==6
	result.end={"phase":String(game.phase),"day_time":float(game.phase_time),"parts":int(game.scrap),"hero_hp":game.hero.hp,"beacon_hp":game.beacon_hp,"snapshot":capture_state()}
	result.births=births.duplicate(true); result.damage=wounds.duplicate(true); result.deaths=deaths.duplicate(true); result.wallet_changes=wallets.duplicate(true); result.member_growth=growth.duplicate(true)
	var movement: Array[Dictionary]=[]
	for token: int in member_tokens:
		var row: Dictionary=moves.get(token,{}).duplicate(true)
		row.erase("last"); row["token"]=token; movement.append(row)
	result.original_member_movement=movement
	var payments: Array[Dictionary]=[]
	for index in range(payments_start,(evidence.payments as Array).size()): payments.append(evidence.payments[index])
	result.gui_payments=payments
	check(guards_hero_hp_damage==0.0 and not hero_left_fort,"自然英雄留城且没有代部队清站守卫")
	if bool(result.natural_capture_proven):
		check(crossed.size()==6 and actual_deaths.all(func(row: Dictionary)->bool:return float(row.hp)==0.0 and not bool(row.alive)),"自然成功只由原门路线和三真实hp0守卫死亡证明")
		check(float(completion.day_time)>0.0,"自然成功发生在原90秒白昼截止前")
		check(game.scrap>=59+115,"自然实际钱包确实含原站100与三守卫15，其他真实收入独立记账")
	(evidence.natural as Array).append(result)
	await capture_all("natural-generator-capture" if bool(result.natural_capture_proven) else "natural-generator-unfinished",site_point())
	print("GENERATOR_CAPTURE_NATURAL ",JSON.stringify(result))
	stage_finished=true

func finish(code: int = 0) -> void:
	if finished: return
	finished=true; await close_game()
	for path: String in original_profile_hashes.keys():
		var now:=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
		check(now==String(original_profile_hashes[path]),"玩家原档案/备份及两配置保持原哈希")
	for suffix: String in ["",".tmp",".bak"]:
		var path: String=profile_path+suffix
		if FileAccess.file_exists(path): check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path))==OK,"只清理私有发电机专项档案")
	if selected_case.is_empty(): check(completed==CAPTURE_STAGES,"完整成功只由九自身阶段实际末尾证明")
	evidence["partial_case"]=selected_case; evidence["full_suite"]=selected_case.is_empty(); evidence["shutdown_audio_drain_seconds"]=.5
	if valid_output(output_dir):
		check(DirAccess.make_dir_recursive_absolute(output_dir)==OK,"固定专项证据目录可写")
		var file:=FileAccess.open(output_dir.path_join("result.json"),FileAccess.WRITE)
		check(file!=null,"完整专项JSON可创建")
		evidence["checks"]=checks; evidence["failures"]=failures; evidence["completed"]=completed
		if file!=null: file.store_string(JSON.stringify(evidence,"\t")); file.close()
	var passed:=failures.is_empty() and code==0
	if passed and selected_case.is_empty(): print("NIGHTFALL_GENERATOR_CAPTURE_OK checks=%d failures=0" % checks)
	elif passed: print("NIGHTFALL_GENERATOR_CAPTURE_CASE_OK case=%s checks=%d failures=0 full_suite=false" % [selected_case,checks])
	else: print("NIGHTFALL_GENERATOR_CAPTURE_FAILED checks=%d failures=%d stage=%s" % [checks,failures.size(),stage])
	quit(0 if passed else 1)

func run() -> void:
	if not selected_case.is_empty() and selected_case not in CAPTURE_STAGES:
		check(false,"--case只接受自身明确九段之一"); await finish(1); return
	for name: String in CAPTURE_STAGES:
		if not selected_case.is_empty() and name!=selected_case: continue
		stage=name; stage_finished=false
		var failure_count:=failures.size()
		print("GENERATOR_CAPTURE_STAGE ",name)
		match name:
			"input": await capture_input()
			"mixed": await capture_mixed()
			"hold": await capture_hold()
			"combat": await capture_combat()
			"identity": await capture_identity()
			"reentry": await capture_reentry()
			"lifecycle": await capture_lifecycle()
			"hud": await capture_hud()
			"natural": await capture_natural()
		check(stage_finished,"自身阶段须到实际末尾，未执行父段不算覆盖")
		if stage_finished: completed.append(name)
		if stage_finished and failures.size()==failure_count: print("GENERATOR_CAPTURE_CASE_OK case=%s checks=%d" % [name,checks])
		else: print("GENERATOR_CAPTURE_CASE_FAILED case=%s checks=%d failures=%d" % [name,checks,failures.size()-failure_count])
	await finish()
