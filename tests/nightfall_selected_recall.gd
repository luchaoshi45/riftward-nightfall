extends "res://tests/nightfall_veterancy.gd"
## Reuse only the frozen real-GUI, private-archive and observation helpers.
## The nine recall stages below are independent of the parent's test stages.
## Precision explicitly prepares money/positions/clocks. Natural uses the original
## 90/105/90, unchanged actors, real weapons, paths, deaths and paid production.
const RECALL_STAGES := ["input","mixed","weapons","issued","route","identity","lifecycle","hud","natural"]
const WEAPON_DISTANCES := {"shield":1.9,"ranged":6.0,"engineer":1.8,"ballista":9.0,"artillery":10.0,"hunter":1.7,"flamer":4.0,"netter":5.0}

func _initialize() -> void:
	profile_path="user://riftward-selected-recall-%d.json" % Time.get_ticks_usec()
	evidence={"seed":SEED,"scope":"nine selected-recall stages; inherited helpers are not inherited coverage; native Windows unverified",
		"precision":{"parts":5000,"stationed_actors":true,"isolated_cooldowns":100000,"artificial_lifecycle":true},
		"payments":[],"captures":[],"natural":[],"precision_results":[],"weapon_results":[]}
	var args:=OS.get_cmdline_user_args()
	render_test="--render-test" in args
	var index:=args.find("--case")
	if index>=0 and index+1<args.size(): selected_case=args[index+1]
	var backend: String="headless" if DisplayServer.get_name()=="headless" else ("opengl" if RenderingServer.get_current_rendering_method()=="gl_compatibility" else "metal")
	output_dir=ProjectSettings.globalize_path("res://build/selected-recall/"+backend).simplify_path()
	index=args.find("--output-dir")
	if index>=0 and index+1<args.size():
		var candidate:=ProjectSettings.globalize_path(args[index+1]).simplify_path()
		if valid_output(candidate): output_dir=candidate
		else: check(false,"证据只写固定物理build/selected-recall目录")
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
	var base:=ProjectSettings.globalize_path("res://build/selected-recall").simplify_path()
	if candidate!=base and not candidate.begins_with(base+"/"): return false
	var cursor:=candidate
	while cursor!=cursor.get_base_dir():
		var parent:=DirAccess.open(cursor.get_base_dir())
		if parent!=null and parent.is_link(cursor.get_file()): return false
		cursor=cursor.get_base_dir()
	return true

func recall_key() -> void:
	var event:=InputEventKey.new()
	event.keycode=KEY_O; event.physical_keycode=KEY_O; event.alt_pressed=true; event.pressed=true
	root.push_input(event,true)
	event.pressed=false; root.push_input(event,true)
	await process_frame

func strategy_mouse(point: Vector3, button: int, add: bool = false, alt: bool = false) -> void:
	var screen: Vector2=game.camera.unproject_position(point)
	await mouse(screen)
	var event:=InputEventMouseButton.new()
	event.position=screen; event.global_position=screen; event.button_index=button
	event.shift_pressed=add; event.alt_pressed=alt
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if button==MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	event.pressed=true; root.push_input(event,true); await process_frame
	event.pressed=false; event.button_mask=0; root.push_input(event,true); await process_frame

func squad_row(id: int) -> Dictionary:
	for row: Dictionary in game.squads.snapshot().squads:
		if int(row.id)==id: return row
	return {}

func team_row(id: int) -> Dictionary:
	for row: Dictionary in game.logistics.snapshot().teams:
		if int(row.id)==id: return row
	return {}

func select_one(squad: Dictionary) -> void:
	var ids: Array[int]=[int(squad.id)]
	check(game.squads.select_ids(ids)==ids,"公开选择原活编组身份")

func actor_state(squad: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for slot in squad.members.size():
		var raw: Variant=squad.members[slot]
		if not living(raw): continue
		var member: BattleUnit=raw
		result.append({"slot":slot,"token":member.get_instance_id(),"hp":member.hp,"max_hp":member.max_hp,
			"damage":member.damage,"speed":member.speed,"armor":member.armor,"cooldown":member.attack_timer,
			"position":vec(member.position),"path":member.path.duplicate(),"path_timer":member.path_timer,
			"growth":member_state(member).duplicate(true)})
	return result

func wait_until(predicate: Callable, seconds: float, message: String) -> bool:
	for frame in ceili(seconds/STEP):
		if bool(predicate.call()): check(true,message); return true
		if game.phase not in ["day","night"]: break
		step()
		if frame%100==99: await process_frame
	var reached:=bool(predicate.call())
	check(reached,message)
	return reached

func at_recall_stations(squad: Dictionary) -> bool:
	for slot in squad.members.size():
		var raw: Variant=squad.members[slot]
		if not living(raw): return false
		var expected: Vector3=game.squads._station(squad,slot,"recall")
		if planar(raw.position,expected)>.18: return false
	return true

func recall_input() -> void:
	if not await fresh(): return
	if await build_gui("barracks")<0: return
	var chosen: Dictionary=await train_gui("ranged")
	var unchosen: Dictionary=await train_gui("shield")
	if chosen.is_empty() or unchosen.is_empty(): return
	station(chosen,[OPEN,OPEN+Vector3(2,0,0),OPEN+Vector3(-2,0,0)])
	station(unchosen,[OPEN+Vector3(6,0,0),OPEN+Vector3(8,0,0),OPEN+Vector3(10,0,0)])
	quiet_hud(); camera_at(OPEN)
	await strategy_mouse(chosen.members[0].position,MOUSE_BUTTON_LEFT)
	check(game.squads.selected_ids==[int(chosen.id)],"真实战场左键点选原弩手队")
	var before:=actor_state(chosen)
	var money: int=game.scrap
	await recall_key()
	check(chosen.order=="recall" and bool(chosen.get("manual_recall",false)),"真实Alt+O撤回所选并记录显式状态")
	check(unchosen.order=="guard" and not bool(unchosen.get("manual_recall",false)),"未选盾卫原命令不变")
	check(bool(squad_row(int(chosen.id)).get("manual_recall",false)),"只读snapshot披露原编组显式撤回")
	check(game.scrap==money,"撤回命令不扣钱或奖励")
	var after:=actor_state(chosen)
	for index in before.size():
		for key: String in ["hp","max_hp","damage","speed","armor","cooldown","position","growth"]:
			check(before[index][key]==after[index][key],"下令不瞬移/恢复/改属性或经验: "+key)
	step(.1)
	var running:=actor_state(chosen)
	check(running.any(func(row: Dictionary)->bool:return not (row.path as PackedVector3Array).is_empty()),"原导航实际建立撤回路径")
	await recall_key(); await recall_key()
	check(actor_state(chosen)==running,"重复Alt+O幂等保原路径、时钟、生命和经验")
	var point:=OPEN+Vector3(0,0,-2)
	await mouse(game.camera.unproject_position(point)); game.flush_pending_aim()
	await press(KEY_O)
	check(chosen.order=="guard" and not bool(chosen.get("manual_recall",false)),"普通O仍为光标驻守并接管显式撤回")
	await recall_key()
	await strategy_mouse(point,MOUSE_BUTTON_RIGHT)
	check(chosen.order=="move" and not bool(chosen.get("manual_recall",false)),"真实右键移动接管显式撤回")
	await recall_key()
	await strategy_mouse(point,MOUSE_BUTTON_RIGHT,true)
	check(chosen.order=="attack_move" and not bool(chosen.get("manual_recall",false)),"真实Shift右键推进接管显式撤回")
	game.squads.cancel_selection()
	var commands: Array[String]=[String(chosen.order),String(unchosen.order)]
	await recall_key()
	check([String(chosen.order),String(unchosen.order)]==commands and not game.recall_selected_squads(),"无选择Alt+O拒绝，不能替换普通O全軍语义")
	await press(KEY_O)
	check(chosen.order=="hold" and unchosen.order=="hold","普通O无选择仍切换全军驻守")
	await press(KEY_O)
	check(chosen.order=="recall" and unchosen.order=="recall" and not bool(chosen.get("manual_recall",false)),"原全军O撤回不是跨夜显式撤回")
	(evidence.precision_results as Array).append({"stage":"input","selected":int(chosen.id),"unselected":int(unchosen.id),"before":before,"after_command":after,"repeat_preserved":running})
	stage_finished=true

func mixed() -> void:
	if not await fresh(): return
	for kind: String in ["barracks","workshop","depot","laboratory","infirmary"]:
		if await build_gui(kind)<0: return
	var hauler: Dictionary=await train_gui("hauler")
	var shield: Dictionary=await train_gui("shield")
	var medic: Dictionary=await train_gui("medic")
	if hauler.is_empty() or shield.is_empty() or medic.is_empty() or not await day_fixture(): return
	select_one(hauler)
	check(bool(game.logistics.command_selected_field(0).ok),"原公开指定真实废料堆")
	check(bool(game.logistics.prepare_selected_night_hauling().ok),"原白昼显式准备夜采")
	var before_sunset: int=game.scrap
	game.phase_time=.01; step(.02)
	check(game.phase=="night" and game.scrap==before_sunset-20 and int(game.logistics.night_haul_snapshot().active)==1,"真实日落入口一次支付原20装配费")
	await clear_hostiles(); game.wave_index=game.WAVES_PER_NIGHT; game.phase_time=10000.0; game.pulse_timer=100000.0
	if not await wait_until(func()->bool:return int(team_row(int(hauler.id)).cargo)>0,90.0,"真实路径及装载取得原有限货物"): return
	select_one(medic)
	check(bool(game.squads.set_medic_enabled(int(medic.id),true).ok),"原医护公开显式开疗")
	select_one(shield)
	check(bool(game.squads.command_escort(hauler.members[0]).ok),"真实盾卫公开绑定活工队往返护航")
	var ids: Array[int]=[int(hauler.id),int(shield.id),int(medic.id)]
	check(game.squads.select_ids(ids)==ids,"公开混选工队、护卫、医护")
	var stock: Dictionary=game.logistics.snapshot().duplicate(true)
	var permits: Dictionary=game.logistics.night_haul_snapshot().duplicate(true)
	var raw_team: Dictionary=game.logistics.get("_teams")[int(hauler.id)].duplicate(true)
	var raw_cargo: Dictionary=game.logistics.get("_cargo").duplicate(true)
	var hauler_state:=actor_state(hauler)
	var money: int=game.scrap
	await recall_key()
	check(hauler.order=="haul" and not bool(hauler.get("manual_recall",false)),"混选Alt+O在下令入口前排除工队")
	check(stock==game.logistics.snapshot() and permits==game.logistics.night_haul_snapshot(),"有限库存、货物、指定堆、预约和已付许可逐项不变")
	check(raw_team==game.logistics.get("_teams")[int(hauler.id)] and raw_cargo==game.logistics.get("_cargo"),"装卸计时、返站绑定和原货账逐项不变")
	check(hauler_state==actor_state(hauler) and game.scrap==money,"工队原路径冷却及唯一钱包保持")
	check(shield.order=="recall" and medic.order=="recall" and bool(shield.get("manual_recall",false)) and bool(medic.get("manual_recall",false)),"混选仅两支非工队显式撤回")
	check(int(game.squads.escort_snapshot().count)==0,"撤回护卫解除原护航绑定")
	check(bool(medic.get("therapy_enabled",false)),"撤回不暗中关闭已付治疗开关")
	select_one(hauler)
	var before:=actor_state(hauler)
	await recall_key()
	check(actor_state(hauler)==before and game.logistics.snapshot()==stock and not game.recall_selected_squads(),"全工队选中拒绝且不改变任何采运状态")
	if not await wait_until(func()->bool:return int(game.logistics.snapshot().delivered)>int(stock.delivered),100.0,"未被撤回工队原货真实返站交付"): return
	(evidence.precision_results as Array).append({"stage":"mixed","stock_before":stock,"permits_before":permits,"stock_after_delivery":game.logistics.snapshot(),"medical_switch_preserved":bool(medic.therapy_enabled)})
	stage_finished=true

func weapons() -> void:
	if not await fresh(): return
	for kind: String in ["barracks","workshop","laboratory","armory"]:
		if await build_gui(kind)<0: return
	for kind: String in COMBAT_KINDS:
		await clear_hostiles()
		var squad: Dictionary=await train_gui(kind)
		if squad.is_empty(): return
		freeze_troop_attacks()
		station(squad,[OPEN,OPEN+Vector3(0,0,-24),OPEN+Vector3(0,0,-28)])
		var enemy: BattleUnit=spawn_precision_enemy("basic",OPEN+Vector3(0,0,float(WEAPON_DISTANCES[kind])))
		var source: BattleUnit=squad.members[0]
		select_one(squad)
		check(bool(game.squads.command_attack(enemy).ok),"真实公开指定目标启动 "+kind)
		source.attack_timer=0.0; weapon_step(.001)
		check(source.attack_queued and source.attack_windup>0.0,"真实生产武器已进入原前摇 "+kind)
		var windup: float=source.attack_windup
		weapon_step(windup*.4)
		var hp: float=enemy.hp
		var state:=actor_state(squad)
		await recall_key()
		check(squad.order=="recall" and bool(squad.get("manual_recall",false)),"前摇中真实Alt+O接管 "+kind)
		check(not source.attack_queued and source.attack_windup==0.0 and source.target==null,"撤回取消未发真实前摇 "+kind)
		var after:=actor_state(squad)
		for index in state.size():
			for key: String in ["hp","max_hp","speed","damage","armor","growth","cooldown"]:
				check(state[index][key]==after[index][key],"前摇取消保持原员状态 "+kind+":"+key)
		weapon_step(windup+1.0)
		near(enemy.hp,hp,"撤回后原未发武器不补打一击 "+kind)
		check(not source.attack_queued,"撤回中不能重新开启前摇 "+kind)
		(evidence.weapon_results as Array).append({"kind":kind,"source":source.get_instance_id(),"target":enemy.get_instance_id(),"windup":windup,"hp_before":hp,"hp_after":enemy.hp,"source_before":state,"source_after_command":after})
	stage_finished=true

func issued() -> void:
	if not await fresh(): return
	for kind: String in ["barracks","workshop","laboratory","armory"]:
		if await build_gui(kind)<0: return
	var artillery: Dictionary=await train_gui("artillery")
	if artillery.is_empty(): return
	station(artillery,[OPEN,OPEN+Vector3(0,0,-24),OPEN+Vector3(0,0,-28)])
	var source: BattleUnit=artillery.members[0]
	var target: BattleUnit=spawn_precision_enemy("basic",OPEN+Vector3(0,0,10))
	select_one(artillery)
	check(bool(game.squads.command_attack(target).ok),"公开炮击原目标")
	source.attack_timer=0.0; weapon_step(.001); weapon_step(1.001)
	var shot: Dictionary=game.squads.artillery_snapshot().duplicate(true)
	check(int(shot.flight)==1 and int(shot.launched)==1,"完整一秒准备实际发出一枚原炮弹")
	var hp: float=target.hp
	var wounds_before:=wounds.size()
	await recall_key()
	check(int(game.squads.artillery_snapshot().flight)==1 and game.squads.artillery_snapshot().shots==shot.shots,"撤回保原已发炮弹、固定落点和飞行时钟")
	weapon_step(.799)
	near(target.hp,hp,"命令后未到原0.8秒飞行不能提前落地")
	weapon_step(.002)
	var real:=0.0
	for index in range(wounds_before,wounds.size()):
		var row: Dictionary=wounds[index]
		if int(row.token)==target.get_instance_id() and int(row.source)==source.get_instance_id(): real+=float(row.hp_loss)
	check(real>0.0 and int(game.squads.artillery_snapshot().impacts)==1,"撤回后的原炮弹真实落地并确认来源伤害")
	check(artillery.order=="recall" and not source.attack_queued,"已发炮弹完成不重新接管原撤回")
	if not await wait_until(func()->bool:return at_recall_stations(artillery),80.0,"原炮手实际寻路到内城站位"): return
	await clear_hostiles()
	var near_home: BattleUnit=spawn_precision_enemy("basic",source.position+Vector3(0,0,6))
	var untouched: float=near_home.hp
	source.attack_timer=0.0; weapon_step(2.0)
	near(near_home.hp,untouched,"到内城仍是显式停火，不能重新自动炮击")
	(evidence.precision_results as Array).append({"stage":"issued","shot_before":shot,"actual_damage":real,"shot_after":game.squads.artillery_snapshot(),"arrived":at_recall_stations(artillery)})
	stage_finished=true

func route() -> void:
	if not await fresh(): return
	if await build_gui("barracks")<0: return
	var squad: Dictionary=await train_gui("shield")
	if squad.is_empty(): return
	select_one(squad)
	var outside:=Vector3(0,0,Layout.RAMP_END+8.0)
	check(bool(game.squads.command_move(outside).ok),"原公开移动到南门外，无直接摆位")
	if not await wait_until(func()->bool:return squad.members.all(func(raw: Variant)->bool:return living(raw) and raw.position.z>Layout.RAMP_END+6.0),100.0,"三原员真实经过南门坡道抵达城外"): return
	var departure:=actor_state(squad)
	await recall_key()
	var crossed: Dictionary={}
	var travelled:=0.0
	for frame in 2000:
		if at_recall_stations(squad): break
		var before: Array[Vector3]=[]
		for raw: Variant in squad.members: before.append(raw.position)
		step()
		for slot in squad.members.size():
			var member: BattleUnit=squad.members[slot]
			var distance:=planar(before[slot],member.position)
			travelled+=distance
			check(distance<=member.speed*STEP+.001,"真实撤回逐步保持原速度上限")
			if distance>.00001: check(game.can_traverse(before[slot],member.position),"真实撤回每步不穿城墙/建筑/坡道边")
			if member.position.z<Layout.RAMP_TOP and before[slot].z>=Layout.RAMP_TOP: crossed[member.get_instance_id()]=true
		if frame%100==99: await process_frame
	check(at_recall_stations(squad) and crossed.size()==3 and travelled>60.0,"三员沿原导航真实跨南门并到内城，不以接受命令冒充到达")
	for row: Dictionary in actor_state(squad):
		var prior: Dictionary=departure[int(row.slot)]
		for key: String in ["hp","max_hp","speed","armor","damage","growth"]: check(row[key]==prior[key],"真实往返不赠恢复或成长: "+key)
	var member: BattleUnit=squad.members[0]
	var enemy: BattleUnit=spawn_precision_enemy("basic",member.position+Vector3(0,0,1.0))
	enemy.attack_timer=0.0
	check(game.squads.blocker_for(enemy)==null,"撤回盾卫不再拦截敌人")
	var selected: Dictionary=game.choose_enemy_target(enemy)
	check(String(selected.get("kind",""))=="squad","原敌方目标选择仍可锁定撤回活单位")
	if selected.get("unit") is BattleUnit: member=selected.unit
	var token:=member.get_instance_id()
	var loss:=hp_damage(token)
	step(.001)
	check(enemy.attack_queued and String(enemy.get_meta("attack_target_kind",""))=="squad","真实敌人对撤回单位启动原承伤前摇")
	near(hp_damage(token),loss,"敌前摇开始不能提前实伤")
	await advance(.5)
	check(hp_damage(token)>loss,"撤回单位承受原敌方实际生命损失，不赠无敌")
	(evidence.precision_results as Array).append({"stage":"route","departure":departure,"arrival":actor_state(squad),"crossed_gate":crossed.size(),"total_real_distance":travelled,"enemy":enemy.get_instance_id(),"victim":token,"actual_damage":hp_damage(token)-loss})
	stage_finished=true

func identity() -> void:
	if not await fresh(): return
	if await build_gui("barracks")<0: return
	var original: Dictionary=await train_gui("ranged")
	if original.is_empty(): return
	select_one(original); await recall_key()
	var old_token: int=original.members[0].get_instance_id()
	var old_id:=int(original.id)
	check(bool(original.get("manual_recall",false)),"原真实编组已标显式撤回")
	# Explicit module-reset identity counterexample, not a natural retirement.
	game.squads.setup(game,true); await frames()
	check(game.squads.squads.is_empty() and game.squads.selected_ids.is_empty(),"人工生命周期清理销毁原演员和选择")
	var replacement: Dictionary=await train_gui("ranged")
	if replacement.is_empty(): return
	check(int(replacement.id)==old_id and replacement.members[0].get_instance_id()!=old_token and not is_same(original,replacement),"真实重新付款训练的同号队为新身份")
	check(not bool(replacement.get("manual_recall",false)) and not bool(squad_row(old_id).get("manual_recall",false)),"新同号队不继承旧字典显式标记")
	game.squads.on_night()
	check(replacement.order=="hold" and not bool(replacement.get("manual_recall",false)),"新身份仍走原未标记日落驻守")
	select_one(replacement); await recall_key()
	for raw: Variant in replacement.members.duplicate():
		if living(raw): raw.hurt(100000.0,game.hero)
	check(int(squad_row(old_id).alive)==0,"精度真实死亡链使原新队无活员")
	check(not bool(game.squads.command_recall().ok),"全死所选不能当作撤回成功")
	var ids: Array[int]=[999]
	game.squads.selected_ids=ids
	var dead_order: String=replacement.order
	check(not bool(game.squads.command_recall().ok) and replacement.order==dead_order,"失效选择ID被拒绝且不改任何原编组")
	game.squads.cancel_selection()
	(evidence.precision_results as Array).append({"stage":"identity","same_numeric_id":old_id,"old_member":old_token,"actual_retraining":true,"old_dictionary_not_owned":not is_same(original,replacement)})
	stage_finished=true

func lifecycle() -> void:
	if not await fresh(): return
	if await build_gui("barracks")<0: return
	var manual: Dictionary=await train_gui("ranged")
	var automatic: Dictionary=await train_gui("shield")
	if manual.is_empty() or automatic.is_empty(): return
	select_one(manual); await recall_key()
	game.squads.set_order("recall",int(automatic.id))
	var before:=actor_state(manual)
	await press(KEY_ESCAPE) # Selection is dismissed first, as in the real UI.
	await press(KEY_ESCAPE)
	check(game.phase=="paused","真实Esc取消选择后暂停")
	var ids: Array[int]=[int(manual.id)]
	game.squads.select_ids(ids)
	await recall_key()
	check(not game.recall_selected_squads() and not bool(game.squads.command_recall().ok),"暂停拒绝真实按键及两个公开入口")
	game.simulate(10.0); game.squads.advance(10.0)
	check(actor_state(manual)==before and bool(manual.get("manual_recall",false)),"暂停冻结原路径/生命/冷却/成长与显式状态")
	game.squads.cancel_selection(); await press(KEY_ESCAPE)
	game.run.grant("精度待选卡冻结验证"); game.open_draft()
	check(game.phase=="draft","真实局内选卡入口")
	game.squads.select_ids(ids); await recall_key()
	check(not game.recall_selected_squads() and not bool(game.squads.command_recall().ok),"选卡拒绝真实按键及两个公开入口")
	game.simulate(10.0); game.squads.advance(10.0)
	check(actor_state(manual)==before and bool(manual.get("manual_recall",false)),"选卡保原撤回且完整冻结")
	await press(KEY_1)
	check(game.phase=="night","真实选卡恢复原夜")
	var enemy: BattleUnit=spawn_precision_enemy("basic",OPEN+Vector3(0,0,13))
	game.phase_time=.01; game.wave_index=game.WAVES_PER_NIGHT; step(.02)
	check(game.phase=="night" and game.night_clearance_active and living(enemy),"精度截止入口保残敌进入真实清场")
	check(manual.order=="recall" and bool(manual.get("manual_recall",false)),"真实清场不会自动把显式撤回送回前线")
	game.finish_night(); check(game.phase=="night","残敌存活拒绝提前黎明")
	enemy.hurt(100000.0,game.hero); step(.05)
	check(game.phase=="draft","残敌真实死亡后进入黎明卡")
	await press(KEY_1)
	check(game.phase=="day" and game.phase_time==90.0,"真实黎明入口完整原90秒")
	check(manual.order=="recall" and bool(manual.get("manual_recall",false)) and automatic.order=="recall","真实白昼保手动撤回及原自动休整")
	await clear_hostiles(); game.phase_time=.01; step(.02)
	check(game.phase=="night" and game.day_number==2,"精度真日落入口开启第二夜")
	check(manual.order=="recall" and bool(manual.get("manual_recall",false)),"真实下一夜仍保显式撤回")
	check(automatic.order=="hold" and not bool(automatic.get("manual_recall",false)),"未标记自动队仍按原规则日落驻守")
	var scene:=game.get_instance_id()
	game.end_defeat("精度真实败局清理显式撤回")
	check(game.phase=="ended" and game.squads.squads.is_empty() and not game.recall_selected_squads(),"真实结束清原编组并拒绝撤军")
	await press(KEY_ENTER)
	for _frame in 200:
		if current_scene!=null and current_scene.get_instance_id()!=scene: break
		await create_timer(.02,true,false,true).timeout
	check(current_scene!=null and current_scene.get_instance_id()!=scene,"真实Enter重试换新场景")
	if current_scene==null or current_scene.get_instance_id()==scene: return
	game=current_scene as Node3D; game.set_process(false); game.world.set_process(false)
	check(game.phase=="draft" and game.archive.path==profile_path and game.scrap==90 and game.squads.squads.is_empty(),"真实重试私有档案、原90开局且无旧撤回状态")
	stage_finished=true

func hud() -> void:
	if not await fresh(): return
	if await build_gui("barracks")<0: return
	var squad: Dictionary=await train_gui("ranged")
	if squad.is_empty(): return
	station(squad,[OPEN,OPEN+Vector3(2,0,0),OPEN+Vector3(-2,0,0)])
	quiet_hud(); camera_at(OPEN); await frames()
	var baseline:=stable_rects()
	for viewport: Vector2i in VIEWS:
		root.size=viewport; root.content_scale_size=viewport
		quiet_hud(); select_one(squad); await frames()
		var selected_rects:=stable_rects()
		await recall_key(); game.notice_time=0.0; game.hud.queue_redraw(); await frames()
		check(stable_rects()==selected_rects,"显式撤回只复用原选队短条，不增加常驻矩形")
		var actual:=drawn_text()
		check(actual.contains("撤回1队") and actual.contains("Alt+O"),"真实选队短条绘制撤回状态与快捷键")
		await capture("selected-recall-short-strip",OPEN)
		await press(KEY_F3); await click_ui(game.hud.details_tab_rect(4)); await frames()
		actual=drawn_text()
		check(game.hud.detail_tab=="help" and actual.contains("Alt+O"),"真实F3操作速查包含所选撤回说明")
		await capture("help-recall-shortcuts",OPEN)
		await click_ui(game.hud.HELP_TOGGLE_RECT); await frames()
		check(game.hud.help_details_open and drawn_text().contains("Alt+O"),"真实完整帮助保撤回说明")
		for row: Dictionary in game.hud.get("veterancy_labels"):
			var point: Vector2=row.point
			check(point.x>=0.0 and point.x+float(row.width)<=1441.0 and point.y+float(row.descent)<=901.0,"实际所看中文字形留在逻辑视口")
		await capture("help-recall-full",OPEN)
		await press(KEY_F3); game.squads.cancel_selection(); game.hud.queue_redraw(); await frames()
		check(stable_rects()==baseline and not drawn_text().contains("撤回1队"),"收起F3并取消选队恢复原清爽默认区域")
		await capture("default-after-recall-dismissed",OPEN)
	root.size=VIEWS[0]; root.content_scale_size=VIEWS[0]
	stage_finished=true

func natural_attempt(withdraw: bool) -> Dictionary:
	if not await fresh(false): return {}
	var payments_start: int=(evidence.payments as Array).size()
	var result: Dictionary={"policy":"injured-original-veterans-selected-recall" if withdraw else "injured-original-veterans-continue-guard",
		"seed":SEED,"original_parts":90,"original_night":105,"original_day":90,"supplemented_parts":false,
		"direct_actor_placement":false,"direct_enemy_damage":false,"changed_actor_attributes":false,"extended_deadline":false}
	game.plan_hero_path(Vector3(0,5,10))
	var seconds:=0.0
	for frame in 2600:
		if game.phase!="night": break
		natural_policy(); seconds+=.1
		if frame%100==99: await process_frame
	result.first_night={"seconds":seconds,"phase":String(game.phase),"parts":int(game.scrap),"kills":int(game.kills)}
	check(game.phase=="draft" and game.hero.alive and game.beacon_hp>0.0,"自然原技能与原时钟真实度过首夜")
	if game.phase!="draft": result.status="opening_failed"; return result
	await press(KEY_1)
	check(game.phase=="day" and game.phase_time==90.0,"自然首黎明原完整白昼")
	var dawn: int=game.scrap
	if dawn<210: result.status="actual_budget_shortfall"; return result
	if await build_gui("barracks")<0: result.status="actual_construction_failed"; return result
	var shield: Dictionary=await train_gui("shield")
	var ranged: Dictionary=await train_gui("ranged")
	if shield.is_empty() or ranged.is_empty(): result.status="actual_training_failed"; return result
	check(game.scrap==dawn-210,"自然GUI真实兵营60/盾卫70/弩手80且没有补钱")
	result.departure={"parts":int(game.scrap),"day_time":float(game.phase_time),"dawn_parts":dawn,"payments":[60,70,80]}
	var ids: Array[int]=[int(shield.id),int(ranged.id)]
	game.squads.select_ids(ids)
	check(bool(game.squads.command_guard(Vector3(0,5,8.5)).ok),"自然公开驻守到原前方真实位置")
	game.plan_hero_path(Vector3(0,5,10))
	for frame in 1000:
		if game.phase!="day": break
		natural_policy()
		if frame%100==99: await process_frame
	check(game.phase=="night" and game.day_number==2,"自然原90秒白昼真实进入第二夜")
	if game.phase!="night": result.status="second_night_not_reached"; return result
	game.plan_hero_path(Vector3(0,5,12)); seconds=0.0
	for frame in 2600:
		if game.phase!="night": break
		natural_policy(); seconds+=.1
		if frame%100==99: await process_frame
	result.second_night={"seconds":seconds,"phase":String(game.phase),"parts":int(game.scrap),"hero_hp":game.hero.hp,"beacon_hp":game.beacon_hp}
	if game.phase!="draft": result.status="promotion_route_not_reached"; return result
	var veterans:=actor_state(ranged)
	var original_tokens: Array[int]=[]
	for row: Dictionary in veterans:
		original_tokens.append(int(row.token))
	check(veterans.size()==3 and veterans.all(func(row: Dictionary)->bool:return int(row.growth.get("rank",0))>=1),"自然原前方策略三原弩手经真实死敌贡献晋级")
	result.third_day_veterans=veterans
	await press(KEY_1)
	check(game.phase=="day" and game.phase_time==90.0,"自然第二黎明仍完整原90秒白昼")
	result.third_day_parts=int(game.scrap)
	game.plan_hero_path(Vector3(0,5,10))
	for frame in 1000:
		if game.phase!="day": break
		natural_policy()
		if frame%100==99: await process_frame
	check(game.phase=="night" and game.day_number==3,"原第三日落真正产生城防取舍")
	if game.phase!="night": result.status="third_night_not_reached"; return result
	game.plan_hero_path(Vector3(0,5,4))
	var triggering: Dictionary={}
	var baseline_damage:=0.0
	for token: int in original_tokens: baseline_damage+=hp_damage(token)
	var recalled_distances: Dictionary={}
	var cutoff: Dictionary={}
	seconds=0.0
	for frame in 2600:
		if game.phase!="night": break
		natural_policy(); seconds+=.1
		var damage:=0.0
		for token: int in original_tokens: damage+=hp_damage(token)
		if triggering.is_empty() and damage>baseline_damage:
			triggering={"seconds":seconds,"at":elapsed,"night":int(game.day_number),"parts":int(game.scrap),"time_left":float(game.phase_time),
				"actual_hp_loss":damage-baseline_damage,"members":actor_state(ranged),"hero_hp":game.hero.hp,"beacon_hp":game.beacon_hp}
			select_one(ranged)
			for token: int in original_tokens:
				var row: Dictionary=moves.get(token,{})
				recalled_distances[token]=float(row.get("distance",0.0))
			if withdraw: await recall_key()
			triggering["real_alt_o_issued"]=withdraw
			triggering["accepted_manual_recall"]=bool(ranged.get("manual_recall",false))
			triggering["after_command"]=actor_state(ranged)
			if withdraw:
				check(ranged.order=="recall" and bool(ranged.get("manual_recall",false)),"自然真受伤后实际Alt+O接受原活队")
				var before_command: Array[Dictionary]=triggering.members
				var after_command: Array[Dictionary]=triggering.after_command
				check(before_command.size()==after_command.size(),"自然命令保持原存活演员数")
				for index in mini(before_command.size(),after_command.size()):
					for key: String in ["token","hp","max_hp","speed","damage","armor","cooldown","position","growth"]:
						check(before_command[index][key]==after_command[index][key],"自然撤回命令保持原员而不回血/晋级/改属性/瞬移: "+key)
		if cutoff.is_empty() and seconds>=105.0: cutoff=Transition.deadline_evidence(game,seconds)
		if frame%100==99: await process_frame
	result.status="real_third_dawn" if game.phase=="draft" else ("real_defeat" if game.phase=="ended" else "bounded_real_clearance_unfinished")
	result.third_night={"seconds":seconds,"phase":String(game.phase),"parts":int(game.scrap),"hero_hp":game.hero.hp,"beacon_hp":game.beacon_hp,
		"cutoff":cutoff,"clearance":game.night_clearance_snapshot()}
	result.trigger=triggering
	var end_members: Array[Dictionary]=[]
	if game.phase!="ended": end_members=actor_state(ranged)
	var survivors:=0
	var actual_deaths: Array[Dictionary]=[]
	var movement: Array[Dictionary]=[]
	for token: int in original_tokens:
		for death: Dictionary in deaths:
			if int(death.token)==token: actual_deaths.append(death)
		for member: Dictionary in end_members:
			if int(member.token)==token: survivors+=1
		var row: Dictionary=moves.get(token,{}).duplicate(true)
		row.erase("last"); row["token"]=token
		row["after_trigger_distance"]=float(row.get("distance",0.0))-float(recalled_distances.get(token,row.get("distance",0.0)))
		movement.append(row)
	result.original_tokens=original_tokens; result.original_member_deaths=actual_deaths; result.original_survivors=survivors
	result.original_end_members=end_members; result.actual_original_movement=movement
	var returned_veterans: Array[int]=[]
	if withdraw and not triggering.is_empty() and game.phase!="ended":
		for member: Dictionary in end_members:
			var token:=int(member.token)
			var distance:=0.0
			for row: Dictionary in movement:
				if int(row.token)==token: distance=float(row.after_trigger_distance)
			var destination: Vector3=game.squads._station(ranged,int(member.slot),"recall")
			var actual_position:=Vector3(float(member.position[0]),float(member.position[1]),float(member.position[2]))
			if token in original_tokens and int(member.growth.get("rank",0))>=1 and distance>.5 and planar(actual_position,destination)<=.18:
				returned_veterans.append(token)
	result.original_returned_live_veterans=returned_veterans
	result.true_injury_trigger_proven=not triggering.is_empty()
	result.natural_recall_path_proven=withdraw and not triggering.is_empty() and movement.any(func(row: Dictionary)->bool:return float(row.after_trigger_distance)>.5)
	result.natural_veteran_survival_proven=not returned_veterans.is_empty()
	result.natural_all_original_veterans_saved_proven=returned_veterans.size()==3 and survivors==3 and actual_deaths.is_empty()
	result.births=births.duplicate(true); result.damage=wounds.duplicate(true); result.deaths=deaths.duplicate(true)
	result.member_growth=growth.duplicate(true); result.wallet_changes=wallets.duplicate(true); result.growth_receipts=natural_receipts()
	var payments: Array[Dictionary]=[]
	for index in range(payments_start,(evidence.payments as Array).size()): payments.append(evidence.payments[index])
	result.gui_payments=payments
	await capture_all("natural-recall" if withdraw else "natural-continue-guard",Vector3(0,5,7))
	print("SELECTED_RECALL_NATURAL ",JSON.stringify(result))
	return result

func natural() -> void:
	var continuing: Dictionary=await natural_attempt(false)
	var withdrawing: Dictionary=await natural_attempt(true)
	(evidence.natural as Array).append(continuing); (evidence.natural as Array).append(withdrawing)
	check(not continuing.is_empty() and not withdrawing.is_empty(),"两条自然原规则尝试保留真实结果")
	if not continuing.has("departure") or not withdrawing.has("departure"): return
	check(continuing.first_night==withdrawing.first_night and continuing.departure==withdrawing.departure,"两路原首夜/自然付款/出发时刻完全相同")
	if not continuing.has("gui_payments") or not withdrawing.has("gui_payments"): return
	check(continuing.gui_payments==withdrawing.gui_payments,"两路真实GUI支付严格相同")
	check(continuing.second_night==withdrawing.second_night and int(continuing.third_day_parts)==int(withdrawing.third_day_parts),"分支前原第二夜与第三白昼钱包完全相同")
	if not continuing.trigger.is_empty() and not withdrawing.trigger.is_empty():
		for key: String in ["seconds","at","night","parts","time_left","actual_hp_loss","hero_hp","beacon_hp"]:
			near(float(continuing.trigger[key]),float(withdrawing.trigger[key]),"首次真实受伤前成对分支保持同一轨迹: "+key)
		check(not bool(continuing.trigger.accepted_manual_recall) and bool(withdrawing.trigger.accepted_manual_recall),"成对分支只在真受伤后的公开撤军策略不同")
	evidence["natural_comparison"]={"continuing_status":continuing.status,"withdrawing_status":withdrawing.status,
		"continuing_survivors":int(continuing.get("original_survivors",0)),"withdrawing_survivors":int(withdrawing.get("original_survivors",0)),
		"recall_path_proven":bool(withdrawing.get("natural_recall_path_proven",false)),"veteran_survival_proven":bool(withdrawing.get("natural_veteran_survival_proven",false)),
		"all_original_veterans_saved_proven":bool(withdrawing.get("natural_all_original_veterans_saved_proven",false)),
		"scope":"one fixed seed and legal original clocks; failed safety, balance, victory or native Windows claims remain unproven; aggregate wallet difference is not recall profit"}
	stage_finished=true

func finish(code: int = 0) -> void:
	if finished: return
	finished=true; await close_game()
	for path: String in original_profile_hashes.keys():
		var now:=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
		check(now==String(original_profile_hashes[path]),"玩家原档案/备份及两配置保持原哈希")
	for suffix: String in ["",".tmp",".bak"]:
		var path: String=profile_path+suffix
		if FileAccess.file_exists(path): check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path))==OK,"只清理私有撤回测试档案")
	if selected_case.is_empty(): check(completed==RECALL_STAGES,"完整自身成功标记要求九段全部实际执行到末尾")
	evidence["partial_case"]=selected_case; evidence["full_suite"]=selected_case.is_empty()
	if valid_output(output_dir):
		check(DirAccess.make_dir_recursive_absolute(output_dir)==OK,"固定撤回证据目录可写")
		var file:=FileAccess.open(output_dir.path_join("result.json"),FileAccess.WRITE)
		check(file!=null,"完整撤回JSON可创建")
		evidence["checks"]=checks; evidence["failures"]=failures; evidence["completed"]=completed
		if file!=null: file.store_string(JSON.stringify(evidence,"\t")); file.close()
	var passed:=failures.is_empty() and code==0
	if passed and selected_case.is_empty(): print("NIGHTFALL_SELECTED_RECALL_OK checks=%d" % checks)
	elif passed: print("NIGHTFALL_SELECTED_RECALL_CASE_OK case=%s checks=%d full_suite=false" % [selected_case,checks])
	else: print("NIGHTFALL_SELECTED_RECALL_FAILED checks=%d failures=%d stage=%s" % [checks,failures.size(),stage])
	quit(0 if passed else 1)

func run() -> void:
	if not selected_case.is_empty() and selected_case not in RECALL_STAGES:
		check(false,"--case只接受自身明确九段之一"); await finish(1); return
	for name: String in RECALL_STAGES:
		if not selected_case.is_empty() and name!=selected_case: continue
		stage=name; stage_finished=false; print("SELECTED_RECALL_STAGE ",name)
		match name:
			"input": await recall_input()
			"mixed": await mixed()
			"weapons": await weapons()
			"issued": await issued()
			"route": await route()
			"identity": await identity()
			"lifecycle": await lifecycle()
			"hud": await hud()
			"natural": await natural()
		check(stage_finished,"自身阶段须到实际末尾，未执行父段不算覆盖")
		if stage_finished: completed.append(name)
		print("SELECTED_RECALL_STAGE_DONE ",name," checks=",checks," failures=",failures.size())
	await finish()
