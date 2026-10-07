extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
## Independent real-scene acceptance for three squad control groups. Fixtures
## use 5000 parts, extended clocks, direct walkable stations, stationary enemy
## targets and genuine lethal casualties. No human or campaign balance claim.

const Catalog := preload("res://scripts/outpost_catalog.gd")
const CleanHud := preload("res://scripts/nightfall_clean_hud.gd")
const RunSession := preload("res://scripts/run_session.gd")
const SEED := 20261006
const STEP := .1
const HOME := Vector3(0,5,4.5)
const BARRACKS := Vector3(7,5,-8.5)
const WORKSHOP := Vector3(-7.5,5,-8.5)
const LAB := Vector3(7,5,-3.5)
const ARMORY := Vector3(-7,5,-3.5)
const DEPOT := Vector3(7,5,2.5)
const INFIRMARY := Vector3(-7.5,5,2.5)
const OPEN := Vector3(0,0,33)
const FAR_END := Vector3(0,0,59)
const SELECTED_RECT := Rect2(24,762,300,54)
const VIEWPORTS := [Vector2i(1920,1200),Vector2i(1920,1080),Vector2i(1440,900)]
const COMPLETE_GROUP_HELP := "编组：Ctrl+1/2/3保存；数字召回，Shift+数字追加。指挥：点选/框选/Shift追加；Tab全选，O驻守。右键指挥/工队采运；Shift+右键攻击推进。Alt+右键活工队：护航往返；右键改令。"
const FULL_HELP_SECTIONS := ["移动：","技能：","建设：","科技：","互动：","塔防：","探索：","部队：","编组：","指挥：","整备：","界面：","声音："]
const OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var drawn_boxes: Array[Rect2] = []
var drawn_labels: Array[Dictionary] = []
func _draw() -> void:
\tdrawn_boxes.clear(); drawn_labels.clear(); super._draw()
func box(rect: Rect2, fill: Color=Color(.022,.035,.045,.88), outline: Color=Color('435455')) -> void:
\tdrawn_boxes.append(rect); super.box(rect,fill,outline)
func label(value: String, point: Vector2, size_px: int, color: Color=Color('e7e1d3'), latin: bool=false) -> void:
\tvar actual: Font=display_font if latin else font
\tdrawn_labels.append({'text':value,'point':point,'size':size_px,'width':actual.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x,'ascent':actual.get_ascent(size_px),'descent':actual.get_descent(size_px)})
\tsuper.label(value,point,size_px,color,latin)
"""

var game: Node3D
var checks := 0
var failures: Array[String] = []
var render_test := false
var output_dir := "res://build/control-groups"
var active_stage := "initialization"
var finished := false
var evidence: Dictionary = {}

func _initialize() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	render_test="--render-test" in args
	var index: int=args.find("--output-dir")
	if index>=0 and index+1<args.size():
		var candidate: String=ProjectSettings.globalize_path(args[index+1]).simplify_path()
		var allowed: String=ProjectSettings.globalize_path("res://build").simplify_path()
		if candidate.begins_with(allowed+"/"):output_dir=candidate
		else:check(false,"Control-group evidence must remain below the local build directory")
	root.size=VIEWPORTS[0]; root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT; root.content_scale_size=VIEWPORTS[0]
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.position=Vector2i(10000,10000); root.hide()
	evidence={"seed":SEED,"scope":"real scene, GUI paid construction/training and keyboard/mouse selection; precision5000/extended clocks/direct walkable stations/stationary enemies/genuine100000-damage casualties; controlled capture lighting; no natural survival or human balance claim","completed":[],"captures":[],"store":[],"recall":[],"priority":[],"invariants":[],"lifecycle":[],"command":[],"hud":[]}
	create_timer(600.0,true,false,true).timeout.connect(watchdog)
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks+=1
	if condition:return
	failures.append(message)
	if failures.size()<=30:push_error(message)

func watchdog() -> void:
	if finished:return
	check(false,"Control-group acceptance stalled in "+active_stage)
	await close_game(); finished=true; quit(1)

func living(value: Variant) -> bool:
	return is_instance_valid(value) and value is BattleUnit and not value.is_queued_for_deletion() and value.alive and value.hp>0.0

func planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))

func plain(value: Variant) -> Variant:
	if value is Object:return value.get_instance_id() if is_instance_valid(value) else -1
	if value is Dictionary:
		var result: Dictionary={}
		for key: Variant in value:result[key]=plain(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item: Variant in value:result.append(plain(item))
		return result
	return value

func group_snapshot() -> Dictionary:
	return game.control_groups.snapshot()

func slot_row(slot: int) -> Dictionary:
	for row: Dictionary in group_snapshot().groups:
		if int(row.slot)==slot:return row
	check(false,"Snapshot contains the requested one-based slot "+str(slot))
	return {"slot":slot,"ids":[],"alive_ids":[],"count":0}

func sorted_ids(value: Array) -> Array:
	var result: Array=value.duplicate(); result.sort(); return result

func selected() -> Array:
	return game.squads.selected_ids.duplicate()

func assert_selected(ids: Array, label: String) -> void:
	check(sorted_ids(selected())==sorted_ids(ids),label+" selects precisely the expected living squad IDs")
	check(selected().size()==sorted_ids(ids).size(),label+" has no duplicate selection IDs")
	for squad: Dictionary in game.squads.squads:
		for member: Variant in squad.members:
			if living(member):check(bool(member.selection.visible)==(int(squad.id) in ids),label+" synchronizes every actual living selection ring")

func medical_state() -> Dictionary:
	var result: Dictionary=game.squads.medic_snapshot().duplicate(true)
	# Selection presentation is allowed to change; treatment state is not.
	for row: Dictionary in result.squads:row.erase("selected")
	return plain(result)

func periphery() -> Dictionary:
	var roster: Array[Dictionary]=[]
	for squad: Dictionary in game.squads.squads:
		var members: Array[Dictionary]=[]
		for member: Variant in squad.members:
			if not living(member):continue
			var unit: BattleUnit=member as BattleUnit
			members.append({"token":unit.get_instance_id(),"position":unit.position,"hp":unit.hp,"alive":unit.alive,"moving":unit.moving,"path":unit.path.duplicate(),"path_goal":unit.path_goal,"path_timer":unit.path_timer,"cooldown":unit.attack_timer,"queued":unit.attack_queued,"windup":unit.attack_windup,"target":unit.target.get_instance_id() if is_instance_valid(unit.target) else -1,"engaged":bool(unit.get_meta("amove_engaged",false)),"medical":bool(unit.get_meta("medic_casting",false))})
		var values: Dictionary=squad.duplicate(); values.erase("members")
		roster.append({"squad":plain(values),"members":members})
	var enemies: Array[Dictionary]=[]
	for member: Variant in game.enemies:
		if living(member):enemies.append({"token":member.get_instance_id(),"position":member.position,"hp":member.hp,"shield":member.shield,"cooldown":member.attack_timer,"queued":member.attack_queued,"windup":member.attack_windup})
	return {"roster":roster,"enemies":enemies,"logistics":plain(game.logistics.snapshot()),"medical":medical_state(),"hunter":plain(game.squads.hunter_snapshot()),"artillery":plain(game.squads.artillery_snapshot()),"queues":plain(game.squads.training_queues),"shots":plain(game.squads.shots),"wallet":game.scrap,"phase":game.phase,"time":game.phase_time,"day":game.day_number,"rng":game.rng.state,"card_rng":game.run.rng.state,"spawn_rng":game.spawn_rng.state,"discovery_rng":game.discoveries.rng.state,"wildlife_rng":game.wildlife.rng.state,"draw":plain(game.salvage_draw_snapshot()),"goal":game.move_goal,"hero_path":game.hero_path.duplicate(),"hero_position":game.hero.position,"hero_hp":game.hero.hp,"hero_shield":game.hero.shield,"hero_windup":game.hero.attack_windup,"hero_queued":game.hero.attack_queued,"hero_attack_delay":game.hero_attack_delay,"hero_attack_step":game.hero_attack_step,"hero_attack_target":game.hero_attack_target.get_instance_id() if is_instance_valid(game.hero_attack_target) else -1,"mana":game.mana,"beacon":game.beacon_hp,"focus":game.focus_target.get_instance_id() if is_instance_valid(game.focus_target) else -1,"focus_time":game.focus_time,"cooldowns":game.cooldowns.duplicate(),"plan":game.night_plan.duplicate(true)}

func complete_state() -> Dictionary:
	return {"periphery":periphery(),"groups":group_snapshot(),"selection":selected(),"dragging":game.selection_dragging}

func event_key(code: int, pressed: bool, ctrl: bool=false, shift: bool=false, echo: bool=false, meta: bool=false) -> void:
	var event := InputEventKey.new()
	event.keycode=code; event.physical_keycode=code; event.pressed=pressed
	event.ctrl_pressed=ctrl; event.shift_pressed=shift; event.meta_pressed=meta; event.echo=echo
	root.push_input(event,true)

func key_now(code: int, ctrl: bool=false, shift: bool=false) -> void:
	event_key(code,true,ctrl,shift); event_key(code,false,ctrl,shift)

func press(code: int, ctrl: bool=false, shift: bool=false) -> void:
	key_now(code,ctrl,shift); await process_frame

func mouse(point: Vector2, button: int=0, shift: bool=false) -> void:
	var motion := InputEventMouseMotion.new(); motion.position=point; motion.global_position=point; motion.shift_pressed=shift
	root.push_input(motion,true); await process_frame
	if button==0:return
	var event := InputEventMouseButton.new(); event.position=point; event.global_position=point; event.button_index=button; event.shift_pressed=shift
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if button==MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	event.pressed=true; root.push_input(event,true); await process_frame
	event.pressed=false; event.button_mask=0; root.push_input(event,true); await process_frame

func left_edge(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new(); event.position=point; event.global_position=point; event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=pressed; event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0; root.push_input(event,true)

func click_ui(rect: Rect2, shift: bool=false) -> void:
	await mouse(rect.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900),MOUSE_BUTTON_LEFT,shift)

func camera_at(point: Vector3) -> void:
	game.camera.size=38.0; game.camera.position=point+Vector3(0,25,29); game.camera.look_at(point); game.camera_follow=game.camera.position

func stand(point: Vector3) -> void:
	point.y=game.outpost_height(point); game.hero.position=point; game.move_goal=point
	game.hero_path.clear(); game.hero_keyboard_active=false; game.hero.moving=false; game.hero.set_locomotion_velocity(Vector3.ZERO)

func redraw() -> void:
	game.rally.tick(0.0); game.hud.queue_redraw()
	for _frame in 3:await process_frame

func close_drawer() -> void:
	if not game.hud.detail_tab.is_empty():await press(KEY_F3)

func open_army(page: int=0) -> void:
	if game.construction.active:await press(KEY_ESCAPE)
	if game.hud.detail_tab.is_empty():await press(KEY_F3)
	if game.hud.detail_tab!="army":await click_ui(game.hud.details_tab_rect(2))
	for _page in 4:
		if game.hud.troop_page==page:break
		await click_ui(game.hud.troop_page_rect(1 if page>game.hud.troop_page else -1))
	await redraw()
	check(game.hud.detail_tab=="army" and game.hud.troop_page==page,"Actual F3 drawer reaches the intended paid training page")

func select_group(squad: Dictionary, add: bool=false) -> void:
	await close_drawer()
	for member: Variant in squad.members:
		if not living(member):continue
		camera_at(member.position); await mouse(game.camera.unproject_position(member.position),MOUSE_BUTTON_LEFT,add)
		check(int(squad.id) in selected(),"Actual paid member click selects its real squad identity")
		return
	check(false,"Mouse selection fixture requires a living actual member")

func clear_enemies() -> void:
	game.clear_lobbers(); game.clear_summoners(); game.clear_warders(); game.clear_focus(); game.cancel_hero_attack()
	for member: Variant in game.enemies:
		if is_instance_valid(member) and not member.is_queued_for_deletion():member.queue_free()
	game.enemies.clear()

func suspend_defense() -> void:
	game.hero.attack_timer=100000.0; game.pulse_timer=100000.0; game.gate_trap_charges=0
	for pad: Dictionary in game.world.tower_pads:pad.cooldown=100000.0

func groups_empty(snapshot: Dictionary) -> bool:
	if snapshot.groups.size()!=3:return false
	for row: Dictionary in snapshot.groups:
		if not row.ids.is_empty() or not row.alive_ids.is_empty() or int(row.count)!=0:return false
	return true

func close_game() -> void:
	if not is_instance_valid(game):return
	var token: int=game.get_instance_id(); var retired: RefCounted=game.control_groups
	await game.prepare_shutdown()
	var parts: int=game.scrap
	check(groups_empty(retired.snapshot()) and not bool(retired.save(1).ok) and not bool(retired.select(1).ok) and game.scrap==parts,"Actual shutdown unbinds old control groups and cannot modify the retired wallet")
	if current_scene==game:current_scene=null
	game.queue_free(); game=null
	for _frame in 4:await process_frame
	check(not is_instance_id_valid(token),"Actual shutdown releases the previous scene root")

func install_observer() -> void:
	var script := GDScript.new(); script.source_code=OBSERVER
	check(script.reload()==OK,"Read-only observer compiles and forwards actual production HUD drawing/input")
	var previous: Control=game.hud; var layer: Node=previous.get_parent(); layer.remove_child(previous); previous.queue_free()
	var observed: Control=script.new(); observed.game=game; game.hud=observed; layer.add_child(observed)
	observed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame

func fresh_day() -> void:
	await close_game()
	check(RunSession.queue_request(self,SEED,"siege"),"Production session accepts the explicit fixed seed")
	game=load("res://scenes/nightfall.tscn").instantiate(); root.add_child(game); current_scene=game
	for _frame in 5:await process_frame
	game.set_process(false); game.world.set_process(false)
	check(game.control_groups!=null,"Production root owns the independent control-group module")
	await install_observer(); await press(KEY_1)
	check(game.phase=="night" and game.phase_time==105.0 and game.scrap==90 and game.tower_count()==2,"Opening card retains original wallet, gifted towers and night clock")
	clear_enemies(); TransitionFixture.finish_for_fixture(game); await press(KEY_1)
	check(game.phase=="day" and game.phase_time==90.0 and game.run.seed_value==SEED,"Actual dawn card reaches the original first daylight")
	clear_enemies(); game.scrap=5000; game.phase_time=10000.0; stand(HOME); suspend_defense()
	check(groups_empty(group_snapshot()),"Actual new run starts with all three control groups empty")

func step(delta: float=STEP) -> void:
	suspend_defense()
	for member: Variant in game.enemies:
		if living(member):member.speed=0.0; member.attack_timer=100000.0
	game.simulate(delta)

func advance(seconds: float) -> void:
	for frame in ceili(seconds/STEP):
		step(minf(STEP,seconds-float(frame)*STEP))
		if frame%100==99:await process_frame

func wait_for(predicate: Callable, seconds: float, label: String) -> bool:
	for frame in ceili(seconds/STEP):
		if bool(predicate.call()):return true
		step()
		if frame%100==99:await process_frame
	var passed: bool=bool(predicate.call()); check(passed,label+" timed out")
	return passed

func build_gui(kind: String, point: Vector3) -> int:
	stand(HOME)
	if not game.construction.active:await press(KEY_Y)
	var target_page: int=Catalog.BUILDING_IDS.find(kind)/3
	for _page in 4:
		var current_page: int=Catalog.BUILDING_IDS.find(String(game.construction.kind))/3
		if current_page==target_page:break
		await click_ui(game.hud.construction_page_rect(1 if target_page>current_page else -1))
	await click_ui(game.hud.construction_kind_rect(Catalog.BUILDING_IDS.find(kind)%3))
	camera_at(point); await mouse(game.camera.unproject_position(point)); game.flush_pending_aim(); game._process(0)
	var preview: Dictionary=game.construction.snapshot(); var parts: int=game.scrap
	check(bool(preview.valid),"Actual paid "+kind+" has a legal placement: "+String(preview.reason))
	await mouse(game.camera.unproject_position(point),MOUSE_BUTTON_LEFT); await press(KEY_ESCAPE)
	var id: int=-1
	for plot: Dictionary in game.districts.plots:
		if plot.kind==kind and int(plot.level)>0 and planar(plot.position,preview.point)<.05:id=int(plot.index)
	check(id>=0 and game.scrap==parts-int(preview.cost),"Actual world click creates one "+kind+" and pays the displayed sole-wallet cost")
	return id

func train(kind: String) -> Dictionary:
	var id: int=game.squads.squads.size(); var parts: int=game.scrap
	await open_army(Catalog.TROOP_IDS.find(kind)/3)
	await click_ui(game.hud.training_kind_rect(Catalog.TROOP_IDS.find(kind)%3)); await close_drawer()
	check(game.scrap==parts-int(Catalog.troop(kind).cost),"Real "+kind+" GUI training escrows its original price")
	await advance(float(Catalog.troop(kind).time)+.001)
	check(game.squads.squads.size()==id+1,"Real paid training completes with one living "+kind+" squad")
	return game.squads.squads[id] if game.squads.squads.size()>id else {}

func place_group(squad: Dictionary, point: Vector3) -> void:
	for slot in squad.members.size():
		var member: Variant=squad.members[slot]
		if not living(member):continue
		var station: Vector3=point+Vector3((slot-1)*1.25,0,0); station.y=game.outpost_height(station)
		check(game.outpost_walkable(station),"Explicit selection station is genuinely walkable")
		member.position=station; member.path.clear(); member.path_timer=0.0; member.moving=false

func ready(kinds: Array=["shield","ranged","engineer"]) -> Array[Dictionary]:
	await fresh_day(); await build_gui("barracks",BARRACKS)
	if "hauler" in kinds or "artillery" in kinds or "hunter" in kinds:await build_gui("workshop",WORKSHOP)
	if "artillery" in kinds:await build_gui("laboratory",LAB); await build_gui("armory",ARMORY)
	if "hauler" in kinds:await build_gui("depot",DEPOT)
	if "medic" in kinds:await build_gui("infirmary",INFIRMARY)
	var result: Array[Dictionary]=[]
	for kind: String in kinds:
		var squad: Dictionary=await train(kind)
		if squad.is_empty():return []
		result.append(squad)
	for index in result.size():place_group(result[index],OPEN+Vector3((index-1)*7,0,0))
	return result

func right(point: Vector3, shift: bool=false) -> Vector3:
	await close_drawer(); camera_at(point)
	var screen: Vector2=game.camera.unproject_position(point); var ground: Vector3=game.ground_point(screen)
	await mouse(screen,MOUSE_BUTTON_RIGHT,shift); return ground

func spawn(point: Vector3) -> BattleUnit:
	var enemy: BattleUnit=game.spawn_creature(true,"basic")
	point.y=game.outpost_height(point); enemy.position=point; enemy.speed=0.0; enemy.attack_timer=100000.0
	return enemy

func unchanged_key(slot: int, ctrl: bool=false, shift: bool=false, label: String="Selection-only key") -> void:
	game.flush_pending_aim()
	var before: Dictionary=periphery(); key_now(KEY_1+slot-1,ctrl,shift)
	check(periphery()==before,label+" preserves real orders, members, transport, therapy, shells, wallet, every recorded RNG and clock")

func capture(tag: String) -> void:
	if not render_test:return
	check(DisplayServer.get_name()!="headless","Capture uses an actual graphical renderer")
	if DisplayServer.get_name()=="headless":return
	var before: Dictionary=complete_state(); var previous_viewport: Vector2i=root.size
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport
		game.world.night_mix=1.0 if game.phase=="night" else 0.0; game.world.apply_lighting(); await redraw()
		for _frame in 2:await RenderingServer.frame_post_draw
		var picture: Image=root.get_texture().get_image(); var folder: String=ProjectSettings.globalize_path(output_dir)
		DirAccess.make_dir_recursive_absolute(folder)
		var name: String="%s-%dx%d" % [tag,viewport.x,viewport.y]
		check(picture.get_size()==viewport and picture.save_png(folder.path_join(name+".png"))==OK,"Actual control-group PNG saves at requested viewport below build")
		(evidence.captures as Array).append(name)
	check(complete_state()==before,"Capture and controlled lighting never change groups, commands or economic state")
	root.size=previous_viewport; root.content_scale_size=previous_viewport; await redraw()

func store_groups() -> void:
	var squads: Array[Dictionary]=await ready(); if squads.size()!=3:return
	await select_group(squads[0]); unchanged_key(1,true,false,"Real Ctrl1 save")
	check(slot_row(1).ids==[0] and slot_row(1).alive_ids==[0] and int(slot_row(1).count)==1,"Real Ctrl1 saves living squad0 in slot1")
	await select_group(squads[1],true); unchanged_key(2,true,false,"Real Ctrl2 save")
	check(sorted_ids(slot_row(2).ids)==[0,1],"Real Ctrl2 permits an overlapping two-squad group")
	await select_group(squads[2]); unchanged_key(3,true,true,"Real CtrlShift3 save")
	check(slot_row(3).ids==[2] and selected()==[2],"Ctrl takes priority over Shift and saves rather than recalls")
	await select_group(squads[1]); unchanged_key(1,true,false,"Overwrite group1")
	check(slot_row(1).ids==[1] and sorted_ids(slot_row(2).ids)==[0,1] and slot_row(3).ids==[2],"Overwrite touches only the chosen slot")
	await press(KEY_ESCAPE); assert_selected([],"Real Escape before empty save")
	unchanged_key(3,true,false,"Empty selection save")
	check(slot_row(3).ids.is_empty() and int(slot_row(3).count)==0,"Saving an empty selection successfully clears just that group")
	await select_group(squads[0]); camera_at(OPEN)
	var screen: Vector2=game.camera.unproject_position(OPEN+Vector3(15,0,0))
	left_edge(screen,true); check(game.selection_dragging,"Actual left press begins an unfinished selection rectangle")
	unchanged_key(3,true,false,"Save during unfinished box selection")
	check(not game.selection_dragging and slot_row(3).ids==[0],"Successful save cancels unfinished box selection without changing current selection")
	left_edge(screen+Vector2(50,50),false); assert_selected([0],"Old left release after successful save")
	var before: Dictionary=complete_state(); var copy: Dictionary=group_snapshot()
	(copy.groups[0].ids as Array).append(999); (copy.groups[0].alive_ids as Array).clear(); copy.groups.clear()
	for _read in 12:group_snapshot(); slot_row(2)
	check(complete_state()==before,"Snapshot returns detached arrays and repeated reads do not alter groups or selection")
	for slot in [-1,0,4,99]:
		var rejected: Dictionary=game.control_groups.save(slot)
		check(not bool(rejected.ok) and complete_state()==before,"Invalid one-based slot "+str(slot)+" cannot overwrite a saved group")
	(evidence.store as Array).append(group_snapshot()); await capture("store-overlap-and-cleared-slot")

func recall_groups() -> void:
	var squads: Array[Dictionary]=await ready(); if squads.size()!=3:return
	await select_group(squads[0]); await select_group(squads[1],true); await press(KEY_1,true)
	await select_group(squads[1]); await select_group(squads[2],true); await press(KEY_2,true)
	await select_group(squads[2]); unchanged_key(1,false,false,"Actual plain1 recall"); assert_selected([0,1],"Plain1 replacement")
	unchanged_key(2,false,true,"Actual Shift2 union"); assert_selected([0,1,2],"Shift2 additive union")
	unchanged_key(2,false,true,"Repeated Shift2 union"); assert_selected([0,1,2],"Repeated additive group remains deduplicated")
	unchanged_key(2,false,false,"Plain2 replacement"); assert_selected([1,2],"Plain2 drops unrelated squad0")
	var before: Dictionary=complete_state(); unchanged_key(3,false,false,"Empty group recall")
	check(complete_state()==before and not game.construction.active,"Empty plain3 preserves selection and never falls through to old construction")
	var rejected: Dictionary=game.control_groups.select(3,true)
	check(not bool(rejected.ok) and String(rejected.reason)=="empty_group" and complete_state()==before,"Empty additive API rejects with the documented reason and retains selection")
	for slot in [-1,0,4,99]:
		rejected=game.control_groups.select(slot)
		check(not bool(rejected.ok) and complete_state()==before,"Invalid recall slot cannot alter actual selection or commands")
	camera_at(OPEN); var screen: Vector2=game.camera.unproject_position(OPEN+Vector3(15,0,0))
	left_edge(screen,true); check(game.selection_dragging,"Recall fixture starts a real unfinished box")
	game.flush_pending_aim(); before=complete_state()
	event_key(KEY_1,false); event_key(KEY_1,true,false,false,true)
	check(complete_state()==before,"Release-only and echo presses neither recall nor cancel unfinished selection")
	unchanged_key(1); check(not game.selection_dragging,"Successful recall cancels unfinished box selection")
	left_edge(screen+Vector2(80,80),false); assert_selected([0,1],"Old left release after successful recall")
	await press(KEY_ESCAPE); camera_at(OPEN)
	var first: Vector2=game.camera.unproject_position((squads[0].members[1] as BattleUnit).position)
	var second: Vector2=game.camera.unproject_position((squads[1].members[1] as BattleUnit).position)
	var rect: Rect2=Rect2(first,second-first).abs().grow(25)
	check(rect.size.length()>8.0,"Actual box fixture exceeds the production click-versus-drag threshold")
	for member: BattleUnit in squads[2].members:check(not rect.has_point(game.camera.unproject_position(member.position)),"Third paid squad lies outside the actual box hit-test rectangle")
	left_edge(rect.position,true); left_edge(rect.end,false); assert_selected([0,1],"Actual box drag selection")
	await press(KEY_3,true); check(sorted_ids(slot_row(3).ids)==[0,1],"Actual box-selected IDs are saved through Ctrl3")
	var newcomer: Dictionary=await train("shield"); if newcomer.is_empty():return
	place_group(newcomer,OPEN+Vector3(21,0,0)); await select_group(newcomer); await press(KEY_1)
	assert_selected([0,1],"Stored group excludes subsequently trained squad3")
	(evidence.recall as Array).append(group_snapshot()); await capture("recall-real-union-rings")

func reject_keys(label: String) -> void:
	game.flush_pending_aim(); var before: Dictionary=complete_state()
	for slot in 3:
		key_now(KEY_1+slot); key_now(KEY_1+slot,true); key_now(KEY_1+slot,false,true); key_now(KEY_1+slot,true,true)
		check(not bool(game.control_groups.save(slot+1).ok) and not bool(game.control_groups.select(slot+1,true).ok),label+" rejects both direct group actions")
	check(complete_state()==before,label+" rejects every group key/modifier without mutating selection, groups or world state")
	(evidence.priority as Array).append({"gate":label,"selection":selected(),"groups":group_snapshot()})

func input_priority() -> void:
	var squads: Array[Dictionary]=await ready(); if squads.size()!=3:return
	await select_group(squads[0]); await press(KEY_1,true); await select_group(squads[2])
	var groups: Dictionary=group_snapshot(); var selection: Array=selected()
	await press(KEY_Y)
	for page in ceili(Catalog.BUILDING_IDS.size()/3.0):
		if page>0:await press(KEY_PAGEDOWN)
		var visible: Array[String]=game.hud.visible_construction_kinds()
		for index in visible.size():
			for modifiers: Array in [[false,false],[true,false],[false,true],[true,true]]:
				await press(KEY_1+index,bool(modifiers[0]),bool(modifiers[1]))
				check(game.construction.active and game.construction.kind==visible[index] and group_snapshot().groups==groups.groups and selected()==selection,"Active Y construction gives current-page building slots priority over all group modifiers")
	reject_keys("Construction direct API")
	await capture("priority-y-current-page"); await press(KEY_ESCAPE)
	await press(KEY_F1); check(game.music_credits_open and game.phase=="paused","Actual F1 opens sources and pauses with current selection retained")
	reject_keys("F1 sources layer"); await capture("priority-sources-paused"); await press(KEY_ESCAPE)
	check(not game.music_credits_open and game.phase=="paused","First Escape removes sources while keeping pause")
	reject_keys("Real paused phase"); await press(KEY_ESCAPE)
	check(game.phase=="day","Second Escape resumes the original daylight")
	await open_army(); await click_ui(game.hud.RALLY_SELECTOR_RECT); await click_ui(game.hud.RALLY_SET_RECT)
	check(game.rally.active and game.hud.detail_tab.is_empty(),"Actual F3 controls begin exclusive rally point setting")
	reject_keys("Real rally point tool"); await capture("priority-rally-setting"); await press(KEY_ESCAPE)
	check(not game.rally.active,"Actual Escape cancels only the rally tool")
	for modifiers: Array in [[false,false],[true,false],[false,true],[true,true]]:
		groups=group_snapshot(); selection=selected(); var parts: int=game.scrap; var cost: int=game.run.memory_cost()
		await press(KEY_V); check(game.phase=="draft" and game.scrap==parts-cost,"Real V buys the freezing card selection from the sole wallet")
		var frozen: Dictionary=complete_state(); game.simulate(3.0)
		check(complete_state()==frozen and not bool(game.control_groups.save(1).ok) and not bool(game.control_groups.select(1).ok),"Actual draft freezes and rejects direct group APIs")
		await press(KEY_1,bool(modifiers[0]),bool(modifiers[1]))
		check(game.phase=="day" and group_snapshot()==groups and selected()==selection,"Card1 takes priority over every Ctrl/Shift combination and preserves saved groups")
	for index in 3:
		await press(KEY_4+index)
		check(game.contracts.selected_offer==index and group_snapshot()==groups,"Existing4/5/6 still select their actual untouched contract offers")
		await press(KEY_7+index)
		check(game.countermeasure_selected==index and group_snapshot()==groups,"Existing7/8/9 still select actual next-night countermeasures")
	game.restart_pending=true; reject_keys("Pending restart"); game.restart_pending=false
	game.quitting=true; reject_keys("Closing guard"); game.quitting=false
	game.hero.alive=false; reject_keys("Dead-hero boundary fixture"); game.hero.alive=true
	var beacon: float=game.beacon_hp; game.beacon_hp=0.0; reject_keys("Lost-beacon boundary fixture"); game.beacon_hp=beacon
	(evidence.priority as Array).append({"construction_pages":ceili(Catalog.BUILDING_IDS.size()/3.0),"card_modifiers":4,"contract":game.contracts.selected_offer,"countermeasure":game.countermeasure_selected})

func active_invariants() -> void:
	var squads: Array[Dictionary]=await ready(["shield","ranged"]); if squads.size()!=2:return
	place_group(squads[0],Vector3(-7,5,3.5))
	var mover: BattleUnit=squads[0].members[1]
	check(not game.can_traverse(mover.position,FAR_END),"Actual wall blocks the direct march so the precision fixture genuinely requires the south-gate navigation route")
	await select_group(squads[0]); await press(KEY_1,true); await right(FAR_END,true); step(.1)
	check(mover.moving and not mover.path.is_empty() and mover.path_timer>0.0,"Real AMOVE has an active path and positive path clock before group testing")
	(evidence.invariants as Array).append({"state":"real-south-gate-path","position":mover.position,"path":mover.path.duplicate(),"path_timer":mover.path_timer})
	await open_army(); var queued_parts: int=game.scrap
	await click_ui(game.hud.training_kind_rect(0)); await close_drawer()
	var queues: Array=game.squads.training_queues.values()
	check(game.scrap==queued_parts-70 and not queues.is_empty() and not queues[0].is_empty() and float(queues[0][0].remaining)>0.0,"Invariant fixture contains a real paid unfinished shield queue with a positive training clock")
	await select_group(squads[1]); await press(KEY_2,true)
	unchanged_key(1); unchanged_key(2,false,true); unchanged_key(3,true); assert_selected([0,1],"Selection-only keys during real travel")
	place_group(squads[0],OPEN); await select_group(squads[0]); var enemy: BattleUnit=spawn(OPEN+Vector3(0,0,2))
	await right(FAR_END,true); step(.001)
	check(mover.attack_queued and mover.attack_windup>0.0,"Real AMOVE encounters a legal enemy and begins native melee preparation")
	unchanged_key(2); unchanged_key(1,true); unchanged_key(3,false,true)
	check(mover.attack_queued and mover.attack_windup>0.0,"Recall/save do not cancel or accelerate a true melee windup")
	(evidence.invariants as Array).append({"state":"real-path-and-melee-windup","enemy":enemy.get_instance_id(),"windup":mover.attack_windup})
	squads=await ready(["hauler","shield"]); if squads.size()!=2:return
	await select_group(squads[0]); await press(KEY_1,true); await select_group(squads[1]); await press(KEY_2,true); await press(KEY_1)
	await right(game.logistics.fields[0].position)
	if not await wait_for(func() -> bool:return int(game.logistics.snapshot().cargo)>0,100,"Real specified hauling route earns actual carried stock"):return
	var transport: Dictionary=game.logistics.snapshot()
	check(int(transport.cargo)>0 and int(transport.remaining)<480,"Transport invariant fixture has real loaded cargo and deducted field stock")
	unchanged_key(2); unchanged_key(1,false,true); unchanged_key(3,true)
	(evidence.invariants as Array).append({"state":"real-loaded-hauler","stock":transport}); await capture("invariants-loaded-hauler")
	squads=await ready(["medic","shield"]); if squads.size()!=2:return
	place_group(squads[0],OPEN); place_group(squads[1],OPEN+Vector3(0,0,3))
	await select_group(squads[0]); await right(OPEN); game.flush_pending_aim(); await press(KEY_O); await advance(12.0)
	await press(KEY_1,true); await select_group(squads[1]); await press(KEY_2,true)
	stand(OPEN+Vector3(0,0,2)); game.hero.hurt(120.0,null)
	await press(KEY_1); await open_army(1); await click_ui(game.hud.MEDIC_BUTTON_RECT); await close_drawer(); step(.001)
	var medical: Dictionary=game.squads.medic_snapshot(); var casting: int=0
	for row: Dictionary in medical.squads:
		casting+=int(row.casting)
		for member: Dictionary in row.members:
			if bool(member.casting):check(int(member.target_token)==game.hero.get_instance_id() and float(member.remaining)>0.0 and float(member.remaining)<=.65,"Actual positive medical windup belongs to the real injured hero and retains its original duration")
	check(casting>0 and bool(squads[0].therapy_enabled),"Actual GUI enables medical therapy and real injured hero starts a positive treatment windup")
	unchanged_key(2); unchanged_key(1,false,true); unchanged_key(3,true)
	(evidence.invariants as Array).append({"state":"real-medical-windup","medical":plain(medical)}); await capture("invariants-medical-windup")
	squads=await ready(["artillery","shield"]); if squads.size()!=2:return
	await select_group(squads[0]); await right(OPEN); game.flush_pending_aim(); await press(KEY_O); await advance(15.0); await press(KEY_1,true)
	await select_group(squads[1]); await press(KEY_2,true); place_group(squads[1],OPEN+Vector3(25,0,0))
	enemy=spawn(OPEN+Vector3(0,0,10))
	var gunner: BattleUnit=squads[0].members[1]
	check(not gunner.moving and game.squads.artillery.legal_target(gunner,enemy),"Stationary real gunner has a legal original5.5-to16m target before shell preparation")
	step(.001); await advance(1.001)
	var artillery: Dictionary=game.squads.artillery_snapshot()
	check(int(artillery.flight)>0 and int(artillery.launched)>0,"Real legal artillery preparation commits an actual independently flying shell")
	unchanged_key(1); unchanged_key(2); unchanged_key(3,true)
	(evidence.invariants as Array).append({"state":"real-shell-flight","artillery":plain(artillery)}); await capture("invariants-committed-shell")

func lifecycle_groups() -> void:
	var squads: Array[Dictionary]=await ready(["shield","ranged"]); if squads.size()!=2:return
	var original: Dictionary=squads[0]; var tokens: Array=[]
	for member: BattleUnit in original.members:tokens.append(member.get_instance_id())
	await select_group(original); await press(KEY_1,true)
	(original.members[0] as BattleUnit).hurt(100000.0,null); await process_frame
	await select_group(squads[1]); await press(KEY_1); assert_selected([0],"Partial casualty retains the stored living squad")
	check(slot_row(1).ids==[0] and int(slot_row(1).count)==1,"One casualty does not remove the stable squad identity")
	for member: Variant in original.members:
		if living(member):member.hurt(100000.0,null)
	for _frame in 3:await process_frame
	await select_group(squads[1]); var before: Dictionary=complete_state(); var result: Dictionary=game.control_groups.select(1)
	check(not bool(result.ok) and String(result.reason)=="empty_group" and complete_state()==before,"All-dead recall retains another current selection and reports empty_group")
	await press(KEY_1); assert_selected([1],"All-dead plain1 preserves unrelated current selection")
	check(slot_row(1).ids==[0] and slot_row(1).alive_ids.is_empty() and int(slot_row(1).count)==0,"All-dead original Dictionary remains stored with zero living squad count")
	for token: int in tokens:check(not is_instance_id_valid(token),"Every actual defeated old member is released")
	var parts: int=game.scrap; var cost: int=game.squads.refill_cost(); await press(KEY_L)
	check(cost>0 and game.scrap==parts-cost and is_same(game.squads.squads[0],original),"Real daylight L pays the exact missing-member cost and retains original squad Dictionary")
	for member: BattleUnit in original.members:check(living(member) and member.get_instance_id() not in tokens,"Real refill creates a genuinely new living model for each old dead slot")
	await press(KEY_1); assert_selected([0],"Real refill restores the saved group membership")
	check(slot_row(1).alive_ids==[0] and int(slot_row(1).count)==1,"The original saved identity becomes selectable again after true refill")
	var groups: Dictionary=group_snapshot(); game.start_night(); clear_enemies(); game.phase_time=10000.0; game.wave_index=game.WAVES_PER_NIGHT
	check(group_snapshot()==groups,"Actual sunset retains the same saved groups")
	TransitionFixture.finish_for_fixture(game); await press(KEY_1); clear_enemies(); game.phase_time=10000.0
	check(group_snapshot()==groups and game.phase=="day","Actual dawn and card choice retain group identity across day/night generation changes")
	(evidence.lifecycle as Array).append({"mode":"casualty-refill-day-night","groups":groups,"cost":cost}); await capture("lifecycle-refilled-real-identity")
	for reset: String in ["clear","setup"]:
		squads=await ready(["shield","ranged"]); if squads.size()!=2:return
		original=squads[0]; await select_group(original); await press(KEY_1,true)
		if reset=="clear":game.squads.clear()
		else:game.squads.setup(game,true)
		for _frame in 3:await process_frame
		var replacement0: Dictionary=await train("shield"); var replacement1: Dictionary=await train("ranged")
		if replacement0.is_empty() or replacement1.is_empty():return
		place_group(replacement0,OPEN-Vector3(7,0,0)); place_group(replacement1,OPEN+Vector3(7,0,0)); await select_group(replacement1)
		check(int(replacement0.id)==int(original.id) and not is_same(replacement0,original),"Actual squads "+reset+" reuses numeric0 with a new Dictionary identity")
		before=complete_state(); result=game.control_groups.select(1)
		check(not bool(result.ok) and complete_state()==before and slot_row(1).alive_ids.is_empty(),"Stored original identity cannot select new same-number squad after "+reset)
		await press(KEY_1); assert_selected([1],"Stale group input retains new unrelated squad after "+reset)
		game.control_groups.setup(game); check(groups_empty(group_snapshot()),"Module setup retires every old group and binds the current run")
		(evidence.lifecycle as Array).append({"mode":"dictionary-identity-"+reset,"new_id":replacement0.id})
	for ending: String in ["defeat","victory"]:
		squads=await ready(["shield"]); if squads.is_empty():return
		await select_group(squads[0]); await press(KEY_1,true)
		var retired: RefCounted=game.control_groups
		if ending=="defeat":game.end_defeat("Explicit control-group lifecycle fixture")
		else:game.day_number=game.max_nights(); TransitionFixture.finish_for_fixture(game)
		check(game.phase=="ended" and groups_empty(group_snapshot()) and not bool(retired.save(1).ok) and not bool(retired.select(1).ok),"Actual "+ending+" clears and unbinds all saved group identities")
		reject_keys("Actual "+ending+" screen")
		(evidence.lifecycle as Array).append({"mode":ending,"groups":group_snapshot()})
	squads=await ready(["shield"]); if squads.is_empty():return
	await select_group(squads[0]); await press(KEY_1,true)
	var old_root: int=game.get_instance_id(); var old_member: int=(squads[0].members[1] as BattleUnit).get_instance_id()
	game.end_defeat("Actual same-seed control-group retry"); await press(KEY_ENTER)
	for _frame in 240:
		if is_instance_valid(current_scene) and current_scene.get_instance_id()!=old_root:break
		await create_timer(.02,true,false,true).timeout
	check(is_instance_valid(current_scene) and current_scene.get_instance_id()!=old_root,"Actual Enter creates a fresh scene root")
	if not is_instance_valid(current_scene) or current_scene.get_instance_id()==old_root:return
	game=current_scene as Node3D; game.set_process(false); game.world.set_process(false)
	for _frame in 5:await process_frame
	await install_observer()
	check(not is_instance_id_valid(old_root) and not is_instance_id_valid(old_member) and game.run.seed_value==SEED and game.phase=="draft" and game.scrap==90 and groups_empty(group_snapshot()),"Same-seed retry releases old root/member and resets wallet/draft/groups")
	await press(KEY_1); clear_enemies(); TransitionFixture.finish_for_fixture(game); await press(KEY_1); clear_enemies(); game.scrap=5000; game.phase_time=10000.0
	await build_gui("barracks",BARRACKS); original=await train("shield")
	if original.is_empty():return
	place_group(original,OPEN); await select_group(original); result=game.control_groups.select(1)
	check(int(original.id)==0 and not bool(result.ok) and String(result.reason)=="empty_group","Retried new squad0 never inherits the previous run's group1")
	(evidence.lifecycle as Array).append({"mode":"real-enter-retry","old_root":old_root,"new_root":game.get_instance_id()})

func command_integration() -> void:
	var squads: Array[Dictionary]=await ready(["shield","ranged"]); if squads.size()!=2:return
	await select_group(squads[0]); await press(KEY_1,true); await select_group(squads[1]); await press(KEY_2,true)
	await press(KEY_1); var destination: Vector3=await right(FAR_END)
	check(squads[0].order=="move" and planar(squads[0].destination,destination)<.02 and squads[1].order!="move","Recall routes real right MOVE only to the recalled squad")
	await press(KEY_2,false,true); destination=await right(FAR_END,true)
	check(squads[0].order=="attack_move" and squads[1].order=="attack_move" and planar(squads[0].destination,destination)<.02 and planar(squads[1].destination,destination)<.02,"Shift recall union receives the original real Shift-right attack-move command")
	game.flush_pending_aim(); await press(KEY_O)
	check(squads[0].order=="guard" and squads[1].order=="guard","Existing O still guards the recalled actual union")
	await press(KEY_TAB); assert_selected([0,1],"Existing Tab selects every living squad")
	check(slot_row(1).ids==[0] and slot_row(2).ids==[1],"Tab/order commands never implicitly overwrite saved groups")
	await press(KEY_ESCAPE); assert_selected([],"First Escape clears recalled selection")
	check(game.phase=="day","Clearing selected troops retains the active day")
	await press(KEY_ESCAPE); check(game.phase=="paused","Following Escape pauses normally")
	await press(KEY_ESCAPE); check(game.phase=="day","Pause resumes normally")
	stand(Vector3(-7,5,6)); var enemy: BattleUnit=spawn(Vector3(-4,5,6)); await press(KEY_1)
	var tower_reachable: bool=false
	for pad: Dictionary in game.world.tower_pads:
		if int(pad.level)>0 and (pad.position as Vector3).distance_to(enemy.position)<14.0:tower_reachable=true
	check(tower_reachable and planar(game.hero.position,enemy.position)<=27.0,"Actual C fixture lies strictly inside an existing living tower's base14m range and the hero's original27m radius")
	camera_at(enemy.position); await mouse(game.camera.unproject_position(enemy.position)); game.flush_pending_aim(); await press(KEY_C)
	check(game.focus_target==enemy and selected()==[0],"Existing legal C focus accepts the actual enemy after recall without replacing group selection")
	(evidence.command as Array).append({"mode":"move-amove-guard-tab-esc-focus","groups":group_snapshot()})
	squads=await ready(["hauler","shield"]); if squads.size()!=2:return
	await select_group(squads[0]); await press(KEY_1,true); await select_group(squads[1]); await press(KEY_2,true)
	await press(KEY_1); await press(KEY_2,false,true); destination=await right(game.logistics.fields[0].position)
	var row: Dictionary=game.logistics.snapshot().teams[0]
	check(int(row.preferred_field)==0 and squads[1].order=="move" and planar(squads[1].destination,destination)<.02,"Recalled mixed group keeps real hauler specified route plus ordinary escort MOVE")
	var before: Dictionary=group_snapshot(); await press(KEY_2); destination=await right(OPEN+Vector3(20,0,10))
	check(int(game.logistics.snapshot().teams[0].preferred_field)==0 and group_snapshot()==before,"Recalling only escort and moving it preserves the unselected hauler's specified field and all saved groups")
	(evidence.command as Array).append({"mode":"mixed-haul-escort","stock":game.logistics.snapshot()}); await capture("command-recalled-hauler-escort")

func clear_transients() -> void:
	game.notice_time=0.0; game.reward_toasts.clear(); game.beacon_alarm_time=0.0; game.hero_damage_flash_time=0.0; game.combat_milestone_time=0.0
	game.combat.clear_transients()

func permanent_hud_except_objective(label: String) -> Dictionary:
	var objective: Rect2=CleanHud.objective_rect(game.hud,game)
	var boxes: Array=game.hud.drawn_boxes.duplicate()
	var regions: Array=game.hud.live_panel_rects().duplicate()
	check(objective.position==CleanHud.OBJECTIVE_RECT.position and objective.size.x>=200.0
		and objective.size.x<=CleanHud.OBJECTIVE_RECT.size.x and objective.size.y>0.0 and objective.size.y<=110.0,
		label+" keeps the actual content-sized objective inside its established footprint")
	check(boxes.count(objective)==1 and regions.count(objective)==1,
		label+" paints and exposes exactly one actual content-sized objective rectangle")
	# Remove only the exact current objective; every other painted/input region
	# remains in its original order and must compare precisely with the baseline.
	boxes.erase(objective); regions.erase(objective)
	return {"boxes":boxes,"regions":regions}

func measure_hud(tag: String, help: bool=false) -> void:
	game.flush_pending_aim(); var before: Dictionary=complete_state(); var previous_viewport: Vector2i=root.size
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport; await redraw()
		var hint_seen: bool=false; var help_seen: bool=false; var bottom: float=0.0
		var close_seen: bool=false; var toggle_seen: bool=false; var help_body: String=""
		var group_hint: String=game.hud.control_group_hint()
		for row: Dictionary in game.hud.drawn_labels:
			var point: Vector2=row.point; var width: float=row.width
			check(point.x>=0.0 and point.x+width<=1440.0 and point.y-float(row.ascent)>=0.0 and point.y+float(row.descent)<=900.0,"Actual complete glyph rectangle fits "+tag+": "+String(row.text))
			for character: String in String(row.text):
				var code: int=character.unicode_at(0)
				if code>=0x4e00 and code<=0x9fff:check(game.hud.font.has_char(code),"Actual font contains complete Chinese glyph "+character)
			if String(row.text)==group_hint:
				hint_seen=true; check(width<=496.0 and int(row.size)==13,"Actual control_group_hint uses complete13px text within the existing496px drawer column")
			if help and point.x==46.0 and point.y>=183.0:
				bottom=maxf(bottom,point.y+float(row.descent))
				help_body+=String(row.text)
				if String(row.text).contains("Ctrl") and String(row.text).contains("编组"):help_seen=true
			if help and String(row.text) in ["F3 收起","返回快捷操作"]:
				var footer: Rect2=game.hud.DETAIL_CLOSE_RECT if String(row.text)=="F3 收起" else game.hud.HELP_TOGGLE_RECT
				var glyph: Rect2=Rect2(point-Vector2(0,float(row.ascent)),Vector2(width,float(row.ascent)+float(row.descent)))
				check(footer in game.hud.drawn_boxes and footer.encloses(glyph),"Actual expanded-help footer paints its complete caption inside the real button: "+String(row.text))
				if String(row.text)=="F3 收起":close_seen=true
				else:toggle_seen=true
		check(game.hud.detail_tab!="army" or hint_seen,"Actual army drawer draws the real control-group snapshot hint")
		if help:
			check(game.hud.detail_tab=="help" and game.hud.help_details_open,"Complete help measurements require the actually expanded help view")
			check(help_seen and help_body.contains(COMPLETE_GROUP_HELP) and bottom<=game.hud.DETAIL_CLOSE_RECT.position.y,
				"Actual expanded help retains the complete group/recall/union/command instructions and every final glyph above the existing close button")
			for heading: String in FULL_HELP_SECTIONS:check(help_body.contains(heading),"Actual complete help retains Chinese section "+heading)
			check(close_seen and toggle_seen,"Actual complete help draws both its real close button and return-to-quick toggle")
		(evidence.hud as Array).append({"tag":tag,"viewport":viewport,"groups":group_hint,"hint_seen":hint_seen,"help_bottom":bottom,"expanded_help":help,"close_seen":close_seen,"toggle_seen":toggle_seen})
	check(complete_state()==before,"Three-viewport actual drawing and real-font measurement preserve groups, orders, wallet, RNG and clocks")
	root.size=previous_viewport; root.content_scale_size=previous_viewport; await redraw()

func actual_hud() -> void:
	var squads: Array[Dictionary]=await ready(); if squads.size()!=3:return
	if not selected().is_empty():await press(KEY_ESCAPE)
	check(game.phase=="day","HUD baseline begins in an active day without an unintended pause")
	clear_transients(); await redraw()
	var baseline: Dictionary=permanent_hud_except_objective("Day baseline")
	await select_group(squads[0]); await press(KEY_1,true); await select_group(squads[1],true); await press(KEY_2,true); await press(KEY_TAB); await press(KEY_3,true)
	await press(KEY_ESCAPE); clear_transients(); await redraw()
	check(permanent_hud_except_objective("Day saved groups")==baseline,"Saved groups alone preserve every other exact default permanent painted/input rectangle")
	await measure_hud("default-saved-groups"); camera_at(HOME); await capture("hud-default-groups-no-new-panel")
	await press(KEY_2); clear_transients(); await redraw()
	check(SELECTED_RECT in game.hud.drawn_boxes,"Recalled troops use the existing selected strip")
	await measure_hud("selected-recalled-groups"); camera_at(OPEN); await capture("hud-recalled-existing-selected-strip")
	await open_army(); await measure_hud("army-live-group-counts"); await capture("hud-army-live-group-counts")
	for row: Dictionary in group_snapshot().groups:check(int(row.count)==row.alive_ids.size(),"Displayed group count is actual live squads rather than member count")
	await click_ui(game.hud.details_tab_rect(4)); await redraw()
	check(game.hud.detail_tab=="help" and not game.hud.help_details_open,"Actual operation-tab click opens the default quick-help view")
	await measure_hud("help-quick-shortcuts")
	game.flush_pending_aim(); var help_before: Dictionary=complete_state()
	await click_ui(game.hud.HELP_TOGGLE_RECT)
	check(game.hud.detail_tab=="help" and game.hud.help_details_open and complete_state()==help_before,
		"Actual help-toggle GUI expands complete instructions without changing groups, orders, wallet or clocks")
	await measure_hud("help-complete-shortcuts",true); await capture("hud-help-complete-shortcuts")
	await click_ui(game.hud.DETAIL_CLOSE_RECT)
	check(game.hud.detail_tab.is_empty() and not game.hud.help_details_open and complete_state()==help_before,
		"Actual help close button retires expanded content and preserves the same real world state")
	for member: BattleUnit in squads[0].members:member.hurt(100000.0,null)
	for _frame in 3:await process_frame
	await open_army(); await measure_hud("army-dead-group-counts"); await capture("hud-army-dead-group-counts")
	check(int(slot_row(1).count)==0 and int(slot_row(2).count)==1 and int(slot_row(3).count)==2,"Actual casualties update each displayed overlapping group's live count")
	await close_drawer(); await press(KEY_L); await open_army(); await measure_hud("army-refilled-group-counts"); await capture("hud-army-refilled-group-counts")
	check(int(slot_row(1).count)==1 and int(slot_row(2).count)==2 and int(slot_row(3).count)==3,"Real paid refill restores all saved live-count displays")
	await press(KEY_F1); await press(KEY_ESCAPE); await measure_hud("army-paused-existing-controls"); await capture("hud-army-paused-existing-controls")
	await close_drawer()
	if game.phase=="paused":await press(KEY_ESCAPE)
	if not selected().is_empty():await press(KEY_ESCAPE)
	check(game.phase=="day" and selected().is_empty(),"Night HUD comparison resumes the actual day and clears only the remaining troop selection")
	game.start_night(); clear_enemies(); game.phase_time=10000.0; game.wave_index=game.WAVES_PER_NIGHT; clear_transients(); await redraw()
	check(permanent_hud_except_objective("Night saved groups")==baseline,"Night saved groups preserve every other exact default permanent painted/input rectangle without adding a panel")
	await measure_hud("night-default-saved-groups"); camera_at(HOME); await capture("hud-night-default-groups-no-new-panel")

func run() -> void:
	var cases: Dictionary={"store":store_groups,"recall":recall_groups,"priority":input_priority,"invariants":active_invariants,"lifecycle":lifecycle_groups,"command":command_integration,"hud":actual_hud}
	var args: PackedStringArray=OS.get_cmdline_user_args(); var selected_cases: Array=cases.keys(); var index: int=args.find("--case")
	if index>=0 and index+1<args.size():selected_cases=[args[index+1]]
	for name: String in selected_cases:
		if not cases.has(name):check(false,"Unknown control-group acceptance stage "+name); break
		active_stage=name; print("CONTROL_GROUP_STAGE_BEGIN ",name)
		await (cases[name] as Callable).call()
		print("CONTROL_GROUP_STAGE_END ",name," checks=",checks," failures=",failures.size())
		(evidence.completed as Array).append(name)
		if not failures.is_empty():break
	await close_game(); await create_timer(.5,true,false,true).timeout
	evidence.shutdown_audio_drain_seconds=.5
	var folder: String=ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
	var file: FileAccess=FileAccess.open(folder.path_join("nightfall-control-groups.json"),FileAccess.WRITE)
	check(file!=null,"Structured seven-stage control-group evidence opens below local build")
	evidence.checks=checks; evidence.failures=failures
	if file!=null:file.store_string(JSON.stringify(evidence,"\t")); file.close()
	finished=true; print("CONTROL_GROUP_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
