extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
## Real scene/input/training/damage/navigation. Precision: 5000 parts, extended
## clocks, direct positions, stationary enemies and genuine lethal casualties.
## Economy keeps native wallet, clocks, stats and hero position. Captures use
## controlled lighting. Neither fixture represents human or campaign balance.

const Catalog := preload("res://scripts/outpost_catalog.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
const RunSession := preload("res://scripts/run_session.gd")
const UnitScript := preload("res://scripts/unit.gd")
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
const VIEWPORTS := [Vector2i(1920,1200),Vector2i(1920,1080),Vector2i(1440,900)]
const SELECTED_RECT := Rect2(24,762,300,54)
const OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var drawn_rects: Array[Rect2] = []
var drawn_labels: Array[Dictionary] = []
func _draw() -> void:
\tdrawn_rects.clear(); drawn_labels.clear(); super._draw()
func box(rect: Rect2, fill: Color = Color(.022,.035,.045,.88), outline: Color = Color('435455')) -> void:
\tdrawn_rects.append(rect); super.box(rect,fill,outline)
func label(value: String, point: Vector2, size_px: int, color: Color = Color('e7e1d3'), latin: bool = false) -> void:
\tvar actual: Font = display_font if latin else font
\tdrawn_labels.append({'text':value,'point':point,'size':size_px,'width':actual.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x,'ascent':actual.get_ascent(size_px),'descent':actual.get_descent(size_px)})
\tsuper.label(value,point,size_px,color,latin)
"""

var game: Node3D
var checks := 0
var failures: Array[String] = []
var render_test := false
var output_dir := "res://build/attack-move"
var active_stage := "initialization"
var finished := false
var precision := true
var elapsed := 0.0
var hurt_events: Array[Dictionary] = []
var death_events: Array[Dictionary] = []
var gate_tokens: Dictionary = {}
var evidence: Dictionary = {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args(); render_test="--render-test" in args
	var index := args.find("--output-dir")
	if index>=0 and index+1<args.size():
		var candidate := ProjectSettings.globalize_path(args[index+1]).simplify_path()
		var allowed := ProjectSettings.globalize_path("res://build").simplify_path()
		if candidate.begins_with(allowed+"/"):output_dir=candidate
		else:check(false,"Attack-move evidence must remain below the local build directory")
	root.size=VIEWPORTS[0]; root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT; root.content_scale_size=VIEWPORTS[0]
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.position=Vector2i(10000,10000); root.hide()
	evidence={"seed":SEED,"scope":"precision5000/extended clocks/direct positions/stationary enemies/lethal100000 casualties; economy original90 wallet/105 night/90 day/native stats; controlled capture lighting; no human or campaign balance claim","completed":[],"captures":[],"encounters":[],"specialists":[],"paths":[],"lifecycle":[],"hud":[],"economy":[]}
	create_timer(600.0,true,false,true).timeout.connect(watchdog)
	call_deferred("run")

func watchdog() -> void:
	if finished:return
	check(false,"Attack-move acceptance stalled in "+active_stage)
	await close_game(); finished=true; quit(1)

func check(condition: bool, message: String) -> void:
	checks+=1
	if condition:return
	failures.append(message)
	if failures.size()<=30:push_error(message)

func planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))

func living(value: Variant) -> bool:
	return is_instance_valid(value) and value is BattleUnit and not value.is_queued_for_deletion() and value.alive and value.hp>0

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

func state() -> Dictionary:
	var orders: Array[Dictionary]=[]; var enemies: Array[Dictionary]=[]
	for group: Dictionary in game.squads.squads:
		var members: Array[Dictionary]=[]
		for value: Variant in group.members:
			if not living(value):continue
			var unit: BattleUnit=value as BattleUnit
			members.append({"token":unit.get_instance_id(),"position":unit.position,"hp":unit.hp,"moving":unit.moving,"path":unit.path.duplicate(),"path_goal":unit.path_goal,"path_timer":unit.path_timer,"cooldown":unit.attack_timer,"queued":unit.attack_queued,"windup":unit.attack_windup,"target":unit.target.get_instance_id() if is_instance_valid(unit.target) else -1,"engaged":bool(unit.get_meta("amove_engaged",false))})
		orders.append({"id":group.id,"kind":group.kind,"order":group.order,"destination":group.destination,"stations":group.get("attack_move_stations",[]).duplicate(),"rally":group.get("rally_stations",[]).duplicate(),"members":members})
	for value: Variant in game.enemies:
		if not living(value):continue
		var unit: BattleUnit=value as BattleUnit
		enemies.append({"token":unit.get_instance_id(),"position":unit.position,"hp":unit.hp,"queued":unit.attack_queued,"windup":unit.attack_windup,"cooldown":unit.attack_timer})
	return {"orders":orders,"enemies":enemies,"stock":plain(game.logistics.snapshot()),"hunter":plain(game.squads.hunter_snapshot()),"artillery":plain(game.squads.artillery_snapshot()),"medical":plain(game.squads.medic_snapshot()),"parts":game.scrap,"phase":game.phase,"time":game.phase_time,"rng":game.run.rng.state,"spawn_rng":game.spawn_rng.state,"goal":game.move_goal,"hero_position":game.hero.position,"hero_path":game.hero_path.duplicate(),"selection":game.squads.selected_ids.duplicate(),"queues":game.squads.training_queues.duplicate(true)}

func press(code: int) -> void:
	var event := InputEventKey.new(); event.keycode=code; event.physical_keycode=code; event.pressed=true
	root.push_input(event,true); event.pressed=false; root.push_input(event,true); await process_frame

func mouse(point: Vector2, button: int = 0, shift: bool = false) -> void:
	var motion := InputEventMouseMotion.new(); motion.position=point; motion.global_position=point; motion.shift_pressed=shift
	root.push_input(motion,true); await process_frame
	if button==0:return
	var event := InputEventMouseButton.new(); event.position=point; event.global_position=point; event.button_index=button; event.shift_pressed=shift
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if button==MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	event.pressed=true; root.push_input(event,true); await process_frame
	event.pressed=false; event.button_mask=0; root.push_input(event,true); await process_frame

func click_ui(rect: Rect2, button: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	await mouse(rect.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900),button,shift)

func camera_at(point: Vector3) -> void:
	game.camera.size=38.0; game.camera.position=point+Vector3(0,25,29); game.camera.look_at(point); game.camera_follow=game.camera.position

func stand(point: Vector3) -> void:
	point.y=game.outpost_height(point); game.hero.position=point; game.move_goal=point
	game.hero_path.clear(); game.hero_keyboard_active=false; game.hero.moving=false; game.hero.set_locomotion_velocity(Vector3.ZERO)

func redraw() -> void:
	game.rally.tick(0.0); game.hud.queue_redraw()
	for _frame in 3:await process_frame

func right(point: Vector3, shift: bool = false) -> Vector3:
	await close_drawer(); camera_at(point)
	var screen: Vector2=game.camera.unproject_position(point)
	var ground: Vector3=game.ground_point(screen)
	await mouse(screen,MOUSE_BUTTON_RIGHT,shift)
	return ground

func close_drawer() -> void:
	if not game.hud.detail_tab.is_empty():await press(KEY_F3)

func open_army(page: int = 0) -> void:
	if game.construction.active:await press(KEY_ESCAPE)
	if game.hud.detail_tab.is_empty():await press(KEY_F3)
	if game.hud.detail_tab!="army":await click_ui(game.hud.details_tab_rect(2))
	for _page in 4:
		if game.hud.troop_page==page:break
		await click_ui(game.hud.troop_page_rect(1 if page>game.hud.troop_page else -1))
	await redraw()
	check(game.hud.detail_tab=="army" and game.hud.troop_page==page,"Actual F3 and bounded pagination select the intended army page")

func select_group(group: Dictionary, add: bool = false) -> void:
	await close_drawer()
	for value: Variant in group.members:
		if not living(value):continue
		var unit: BattleUnit=value as BattleUnit
		camera_at(unit.position); await mouse(game.camera.unproject_position(unit.position),MOUSE_BUTTON_LEFT,add); break
	check(int(group.id) in game.squads.selected_ids,"Actual member click selects the genuine paid squad")

func clear_enemies() -> void:
	game.clear_lobbers(); game.clear_summoners(); game.clear_warders(); game.clear_focus(); game.cancel_hero_attack()
	for value: Variant in game.enemies:
		if is_instance_valid(value) and not value.is_queued_for_deletion():value.queue_free()
	game.enemies.clear()

func suspend_defense() -> void:
	game.hero.attack_timer=100000.0; game.pulse_timer=100000.0; game.gate_trap_charges=0
	for pad: Dictionary in game.world.tower_pads:pad.cooldown=100000.0

func close_game() -> void:
	if not is_instance_valid(game):return
	var token := game.get_instance_id()
	await game.prepare_shutdown()
	check(game.squads.squads.is_empty() and game.logistics.snapshot().teams.is_empty() and game.squads.hunter_snapshot().units.is_empty(),"Actual shutdown clears every squad, attack-move encounter and carrier intent")
	if current_scene==game:current_scene=null
	game.queue_free(); game=null
	for _frame in 4:await process_frame
	check(not is_instance_id_valid(token),"Actual shutdown releases the old scene root")

func fresh(is_precision: bool = true) -> void:
	await close_game(); precision=is_precision
	check(RunSession.queue_request(self,SEED,"siege"),"Actual new run accepts the fixed siege seed")
	game=load("res://scenes/nightfall.tscn").instantiate(); root.add_child(game); current_scene=game
	for _frame in 5:await process_frame
	game.set_process(false); game.world.set_process(false)
	var script := GDScript.new(); script.source_code=OBSERVER
	check(script.reload()==OK,"Read-only observer compiles and forwards production HUD drawing/input")
	var original: Control=game.hud; var layer: Node=original.get_parent(); layer.remove_child(original); original.queue_free()
	var observed: Control=script.new(); observed.game=game; game.hud=observed; layer.add_child(observed)
	observed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await press(KEY_1)
	check(game.phase=="night" and game.phase_time==105.0 and game.scrap==90 and game.tower_count()==2 and game.run.seed_value==SEED,"Actual opening preserves ninety parts, two gifted towers and the original105-second night")
	elapsed=0; hurt_events.clear(); death_events.clear(); gate_tokens.clear()
	if precision:
		game.scrap=5000; game.phase_time=10000.0; game.wave_index=game.WAVES_PER_NIGHT
		clear_enemies(); suspend_defense(); stand(HOME)

func step(delta: float = STEP, freeze_enemy: bool = true) -> void:
	var positions: Dictionary={}
	for group: Dictionary in game.squads.squads:
		for value: Variant in group.members:
			if living(value):positions[value.get_instance_id()]=value.position
	if precision:
		suspend_defense()
		if freeze_enemy:
			for value: Variant in game.enemies:
				if living(value):value.speed=0.0; value.attack_timer=100000.0
	game.simulate(delta); elapsed+=delta
	var valid := true
	for group: Dictionary in game.squads.squads:
		for value: Variant in group.members:
			if not living(value) or not positions.has(value.get_instance_id()):continue
			var unit: BattleUnit=value as BattleUnit; var previous: Vector3=positions[unit.get_instance_id()]
			valid=valid and unit.position.is_finite() and game.outpost_walkable(unit.position) and absf(unit.position.y-game.outpost_height(unit.position))<.001
			valid=valid and game.can_traverse(previous,unit.position) and planar(previous,unit.position)<=unit.speed*delta+.001
			if previous.z<Layout.WALL_CENTER and unit.position.z>=Layout.WALL_CENTER:
				var ratio := (Layout.WALL_CENTER-previous.z)/(unit.position.z-previous.z)
				valid=valid and absf(lerpf(previous.x,unit.position.x,ratio))<Layout.GATE_HALF
				gate_tokens[unit.get_instance_id()]=true
	check(valid,"Every actual member step is bounded, grounded and walkable through the real south gate")
	var stock: Dictionary=game.logistics.snapshot()
	if game.phase=="ended":
		check(int(stock.remaining)==0 and int(stock.cargo)==0 and int(stock.delivered)==0 and int(stock.lost)==0 and stock.fields.is_empty() and stock.teams.is_empty(),"Actual victory/defeat clears every finite field, carrier and ledger instead of retaining a retired run's480 parts")
	else:
		check(int(stock.remaining)+int(stock.cargo)+int(stock.delivered)+int(stock.lost)==480 and stock.fields.size()==5,"Every live-run real step conserves all480 parts across the original five finite fields")

func advance(seconds: float, freeze_enemy: bool = true) -> void:
	for frame in ceili(seconds/STEP):
		step(minf(STEP,seconds-float(frame)*STEP),freeze_enemy)
		if frame%100==99:await process_frame

func wait_for(predicate: Callable, seconds: float, label: String) -> bool:
	for frame in ceili(seconds/STEP):
		if bool(predicate.call()):return true
		step()
		if frame%100==99:await process_frame
	var passed: bool=bool(predicate.call())
	check(passed,label+" timed out; "+str(state().orders))
	return passed

func select_building(kind: String) -> void:
	if not game.construction.active:await press(KEY_Y)
	var target_page: int=Catalog.BUILDING_IDS.find(kind)/3
	for _page in 4:
		var current_page: int=Catalog.BUILDING_IDS.find(String(game.construction.kind))/3
		if current_page==target_page:break
		await click_ui(game.hud.construction_page_rect(1 if target_page>current_page else -1))
	await click_ui(game.hud.construction_kind_rect(Catalog.BUILDING_IDS.find(kind)%3))
	check(game.construction.active and game.construction.kind==kind,"Actual Y toolbar selects "+kind)

func build_gui(kind: String, point: Vector3) -> int:
	if precision:stand(HOME)
	await select_building(kind); camera_at(point); await mouse(game.camera.unproject_position(point)); game.flush_pending_aim(); game._process(0)
	var preview: Dictionary=game.construction.snapshot(); var balance: int=game.scrap
	check(bool(preview.valid),"Actual paid "+kind+" preview is valid: "+String(preview.reason))
	await mouse(game.camera.unproject_position(point),MOUSE_BUTTON_LEFT); await press(KEY_ESCAPE)
	var id := -1
	for plot: Dictionary in game.districts.plots:
		if plot.kind==kind and int(plot.level)>0 and planar(plot.position,preview.point)<.05:id=int(plot.index)
	check(id>=0 and game.scrap==balance-int(Catalog.building(kind).cost),"Actual world confirmation creates exactly one paid "+kind)
	return id

func train(kind: String) -> Dictionary:
	var id: int=game.squads.squads.size(); var before: int=game.scrap
	await open_army(Catalog.TROOP_IDS.find(kind)/3)
	await click_ui(game.hud.training_kind_rect(Catalog.TROOP_IDS.find(kind)%3)); await close_drawer()
	check(game.scrap==before-int(Catalog.troop(kind).cost),"Actual "+kind+" training escrows its original cost once")
	await advance(float(Catalog.troop(kind).time)+.001)
	check(game.squads.squads.size()==id+1,"Actual independent training queue creates the paid "+kind+" squad")
	return game.squads.squads[id] if game.squads.squads.size()>id else {}

func ready(kind: String, single: bool = false) -> Dictionary:
	await fresh(); await build_gui("barracks",BARRACKS)
	if kind in ["hunter","ballista","artillery","hauler"]:await build_gui("workshop",WORKSHOP)
	if kind in ["ballista","artillery"]:await build_gui("laboratory",LAB)
	if kind=="artillery":await build_gui("armory",ARMORY)
	if kind=="hauler":await build_gui("depot",DEPOT)
	if kind=="medic":await build_gui("infirmary",INFIRMARY)
	var group := await train(kind)
	if group.is_empty():return {}
	if single:
		for slot in [0,2]:
			var unit: BattleUnit=group.members[slot]
			unit.hurt(100000.0,null)
		await process_frame
		check(group.members[0]==null and group.members[2]==null,"Single-attacker fixture uses real100000-damage casualties and production cleanup")
	place_group(group,OPEN); await select_group(group)
	return group

func place_group(group: Dictionary, point: Vector3) -> void:
	for slot in group.members.size():
		var value: Variant=group.members[slot]
		if not living(value):continue
		var unit: BattleUnit=value as BattleUnit
		var station := point+Vector3((slot-1)*1.25,0,0); station.y=game.outpost_height(station)
		check(game.outpost_walkable(station),"Explicit precision station lies on real walkable ground")
		unit.position=station; unit.path.clear(); unit.path_timer=0; unit.moving=false

func spawn(point: Vector3, role: String = "basic") -> BattleUnit:
	var enemy: BattleUnit=game.spawn_creature(true,role)
	point.y=game.outpost_height(point); enemy.position=point
	(evidence.encounters as Array).append({"birth":enemy.get_instance_id(),"role":role,"hp":enemy.max_hp,"armor":enemy.armor,"speed":enemy.speed,"damage":enemy.damage})
	enemy.speed=0; enemy.attack_timer=100000.0
	enemy.damage_confirmed.connect(record_hurt); enemy.defeated.connect(record_death)
	return enemy

func record_hurt(victim: BattleUnit, source: BattleUnit, hp_loss: float, shield_loss: float) -> void:
	hurt_events.append({"victim":victim.get_instance_id(),"source":source.get_instance_id() if is_instance_valid(source) else -1,"hp":hp_loss,"shield":shield_loss,"at":elapsed})

func record_death(victim: BattleUnit, source: BattleUnit) -> void:
	death_events.append({"victim":victim.get_instance_id(),"source":source.get_instance_id() if is_instance_valid(source) else -1,"at":elapsed})

func guarded(group: Dictionary) -> bool:
	return not group.is_empty() and group.order=="guard" and not bool(group.get("rally_pending",false))

func capture(tag: String) -> void:
	if not render_test:return
	check(DisplayServer.get_name()!="headless","Capture requires an actual graphical renderer")
	if DisplayServer.get_name()=="headless":return
	var before := state(); var previous_viewport: Vector2i=root.size
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport
		game.world.night_mix=1.0 if game.phase=="night" else 0.0; game.world.apply_lighting(); await redraw()
		for _frame in 2:await RenderingServer.frame_post_draw
		var image: Image=root.get_texture().get_image()
		check(image.get_size()==viewport,"Actual capture matches the requested viewport")
		var folder := ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
		var name := "%s-%dx%d" % [tag,viewport.x,viewport.y]
		check(image.save_png(folder.path_join(name+".png"))==OK,"Actual attack-move PNG saves below local build")
		(evidence.captures as Array).append(name)
	check(state()==before,"Capture and controlled lighting preserve actual orders, clocks, damage and wallets")
	root.size=previous_viewport; root.content_scale_size=previous_viewport; await redraw()

func physical_input() -> void:
	var group := await ready("shield"); if group.is_empty():return
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport
		var physical := await right(FAR_END)
		check(group.order=="move" and planar(group.destination,physical)<.02,"Ordinary actual right ground remains MOVE in "+str(viewport))
		physical=await right(FAR_END,true)
		check(group.order=="attack_move" and planar(group.destination,physical)<.02 and group.attack_move_stations.size()==3,"Actual Shift-right issues fixed three-station AMOVE in "+str(viewport))
		var enemy := spawn(OPEN+Vector3(3,0,5))
		physical=await right(enemy.position,true)
		check(group.order=="attack_move" and group.attack_target==null and planar(group.destination,physical)<.02,"Shift-right on a real enemy wins before ordinary enemy picking")
		await right(enemy.position)
		check(group.order=="attack" and (group.attack_target as WeakRef).get_ref()==enemy,"Ordinary right enemy retains explicit ATTACK")
		clear_enemies(); await process_frame
	root.size=VIEWPORTS[0]; root.content_scale_size=VIEWPORTS[0]
	var before := state(); var rejected: Dictionary=game.squads.command_attack_move(Vector3(INF,0,0))
	check(not bool(rejected.ok) and state()==before,"Nonfinite AMOVE API is rejected without side effects")
	for flag: String in ["quitting","restart_pending"]:
		game.set(flag,true); before=state(); await right(FAR_END,true)
		check(state()==before,"Directly forwarded actual Shift-right respects the "+flag+" shutdown guard")
		game.set(flag,false)
	await press(KEY_Y); before=state(); await right(FAR_END,true)
	check(not game.construction.active and state().orders==before.orders and game.move_goal==before.goal,"Construction owns Shift-right cancellation without issuing a squad or hero order")
	await open_army(); await click_ui(game.hud.RALLY_SELECTOR_RECT); await click_ui(game.hud.RALLY_SET_RECT)
	check(game.rally.active,"Actual existing army controls enter rally-setting mode")
	before=state(); await right(FAR_END,true)
	check(not game.rally.active and state().orders==before.orders and game.move_goal==before.goal,"Rally-setting owns Shift-right cancellation without replacing orders")
	game.squads.cancel_selection(); before=state(); var physical := await right(OPEN,true)
	check(state().orders==before.orders and planar(game.move_goal,physical)<.35,"Unselected Shift-right preserves ordinary hero path input")
	await select_group(group)
	place_group(group,OPEN+Vector3(-5,0,0))
	var second := await train("shield"); if second.is_empty():return
	place_group(second,OPEN+Vector3(5,0,0)); await select_group(group); await select_group(second,true)
	check(game.squads.selected_count()==2,"Actual Shift-left preserves additive squad selection")
	await right(FAR_END,true); camera_at(OPEN); await capture("input-two-squads")

func ordinary_encounters() -> void:
	for kind: String in ["shield","ranged","engineer","ballista"]:
		var group := await ready(kind,true); if group.is_empty():return
		var source: BattleUnit=group.members[1]; var enemy := spawn(OPEN+Vector3(0,0,2))
		var native_hp: float=enemy.hp; var start: Vector3=source.position
		await right(FAR_END); await advance(.3)
		check(enemy.hp==native_hp and source.position.z>start.z and not source.attack_queued,"Original "+kind+" MOVE marches past a currently legal enemy without attacking")
		await right(FAR_END,true); var endpoint: Vector3=group.destination; var stations: Array=group.attack_move_stations.duplicate()
		step(.001); var stopped: Vector3=source.position
		check(source.attack_queued and is_equal_approx(source.attack_windup,source.windup_duration) and not source.moving and bool(source.get_meta("amove_engaged",false)),"AMOVE "+kind+" stops and starts the full original native windup")
		await advance(source.windup_duration-.001)
		check(enemy.hp==native_hp and source.position==stopped and source.attack_queued,"AMOVE "+kind+" cannot hurt before its complete native windup")
		step(.002)
		check(is_equal_approx(enemy.hp,native_hp-source.damage) and is_equal_approx(source.attack_timer,source.attack_interval) and hurt_events.size()==1 and int(hurt_events[0].source)==source.get_instance_id(),"AMOVE "+kind+" commits native damage with true minion attribution and full cooldown")
		check(group.destination==endpoint and group.attack_move_stations==stations,"First actual hit cannot move immutable march endpoints")
		if kind=="shield":camera_at(stopped); await capture("ordinary-native-windup-and-hit")
		if not await wait_for(func() -> bool:return not living(enemy),90,"First actual "+kind+" enemy death"):return
		check(death_events.size()==1 and int(death_events[0].source)==source.get_instance_id(),"First actual "+kind+" defeat comes through its original hurt/death callback")
		var cooldown: float=source.attack_timer; var second := spawn(source.position+Vector3(0,0,2)); var second_hp: float=second.hp
		step(.001)
		check(second.hp==second_hp and source.attack_timer>0 and source.attack_timer<cooldown and group.destination==endpoint,"Second encounter preserves the already earned native cooldown and fixed destination")
		if not await wait_for(func() -> bool:return not living(second),90,"Second actual "+kind+" enemy death"):return
		check(death_events.size()==2 and group.destination==endpoint and group.attack_move_stations==stations,"Second real defeat needs no reissued order or destination rewrite")
		if not await wait_for(func() -> bool:return guarded(group),50,"Same "+kind+" endpoint after two actual kills"):return
		check(planar(source.position,stations[1])<=.17 and game.attack_chain==0,"Living "+kind+" reaches the saved station and GUARD without hero attack-chain credit")
		(evidence.encounters as Array).append({"kind":kind,"endpoint":endpoint,"stations":stations,"damage":hurt_events.duplicate(true),"deaths":death_events.duplicate(true),"arrival":source.position,"parts":game.scrap})
	var group := await ready("shield",true); if group.is_empty():return
	var source: BattleUnit=group.members[1]; var enemy := spawn(source.position+Vector3(0,0,1.4)); enemy.attack_timer=0
	var intercepted: Array[Dictionary]=[]
	source.damage_confirmed.connect(func(victim: BattleUnit, attacker: BattleUnit, hp_loss: float, shield_loss: float) -> void:
		intercepted.append({"victim":victim.get_instance_id(),"source":attacker.get_instance_id() if is_instance_valid(attacker) else -1,"hp":hp_loss,"shield":shield_loss}))
	await right(FAR_END,true); step(.001,false)
	# Squads advance before enemy.tick/intercept in the same actual simulation.
	# This first step engages the shield and creates a complete .34 preparation.
	check(game.squads.blocker_for(enemy)==source and game.squads.intercept_target_for(enemy)==source and enemy.attack_queued and is_equal_approx(enemy.attack_windup,.34),"A stopped AMOVE shield genuinely intercepts with the complete original enemy preparation")
	var hp: float=source.hp; var hero_hp: float=game.hero.hp; var beacon_hp: float=game.beacon_hp
	step(.001,false)
	check(enemy.attack_queued and is_equal_approx(enemy.attack_windup,.339) and source.hp==hp,"The next actual enemy tick consumes exactly .001 of the same interception preparation")
	await advance(.338,false)
	check(source.hp==hp and intercepted.is_empty() and enemy.attack_queued,"Actual intercepted enemy cannot hurt before its complete .34-second preparation")
	step(.002,false)
	check(is_equal_approx(source.hp,hp-enemy.damage/1.25) and intercepted.size()==1 and int(intercepted[0].victim)==source.get_instance_id() and int(intercepted[0].source)==enemy.get_instance_id() and is_equal_approx(float(intercepted[0].hp),enemy.damage/1.25) and float(intercepted[0].shield)==0.0 and game.hero.hp==hero_hp and game.beacon_hp==beacon_hp,"Actual intercepted native enemy damage hits the engaged25-armor shield once with true source attribution and preserves hero/core")
	(evidence.encounters as Array).append({"kind":"native-interception","first_windup":.34,"next_windup":.339,"enemy_damage":enemy.damage,"shield_armor":source.armor,"received":intercepted.duplicate(true)})

func hunter_row(source: BattleUnit) -> Dictionary:
	for row: Dictionary in game.squads.hunter_snapshot().units:
		if int(row.source_token)==source.get_instance_id():return row
	return {}

func specialized_encounters() -> void:
	var group := await ready("hunter",true); if group.is_empty():return
	var source: BattleUnit=group.members[1]; var start: Vector3=source.position
	var target := spawn(start+Vector3(0,0,6),"runner"); var native_hp: float=target.hp
	await right(FAR_END,true); var endpoint: Vector3=group.destination; step(.001)
	check(bool(hunter_row(source).encounter) and hunter_row(source).anchor==start and source.moving,"Hunter first AMOVE contact freezes the actual encounter position and uses real chase navigation")
	if not await wait_for(func() -> bool:return source.attack_queued,3,"Hunter reaches actual melee range"):return
	check(hunter_row(source).anchor==start and is_equal_approx(source.attack_windup,.22),"Hunter chase retains its anchor and starts the complete original .22-second windup")
	await advance(.219); check(target.hp==native_hp,"Hunter cannot hurt before native .22-second preparation")
	step(.002); check(is_equal_approx(target.hp,native_hp-30.0),"Real AMOVE hunter retains its original runner bonus30 damage")
	target.position=start+Vector3(0,0,8.01); target.position.y=game.outpost_height(target.position); step(.001)
	check(not bool(hunter_row(source).encounter) and group.destination==endpoint and source.moving,"True target escape beyond the original8m anchor releases the encounter and resumes the same destination")
	await advance(.5)
	check(source.position.z>start.z+2 and not bool(hunter_row(source).encounter) and target.hp==native_hp-30.0,"Walking closer cannot recapture the escaped victim by rolling its original anchor")
	clear_enemies(); place_group(group,Vector3(-7,5,6)); await right(Vector3(-7,5,11),true)
	start=source.position; var runner := spawn(start+Vector3(3,0,1),"runner"); var focused := spawn(start+Vector3(3,0,0))
	step(.001); check(int(hunter_row(source).target_token)==runner.get_instance_id(),"Original real threat priority selects runner before unfocused ordinary target")
	game.aim=focused.position; await press(KEY_C)
	check(game.focus_target==focused and game.focus_time>0,"Actual C accepts a legal real target through original tower and hero range")
	step(.001); check(int(hunter_row(source).target_token)==focused.get_instance_id() and hunter_row(source).anchor==start,"Legal C reselects inside the same frozen hunter encounter anchor")
	if not await wait_for(func() -> bool:return source.attack_queued,3,"Focused hunter reaches native melee"):return
	var queued: float=source.attack_windup; game.clear_focus(); step(.01)
	check(source.target==focused and source.attack_windup<queued and hunter_row(source).anchor==start,"Existing hunter preparation keeps its committed victim and advances instead of resetting for new priority")
	await capture("hunter-frozen-anchor")
	# The previous (-7,12) target lies inside the opening left tower's actual
	# 3x3 footprint plus .05 navigation margin. Keep the six-metre witness
	# wholly in the courtyard by shifting only this fixture one metre west.
	clear_enemies(); place_group(group,Vector3(-8,5,6)); await right(Vector3(-8,5,11),true)
	start=source.position; target=spawn(start+Vector3(0,0,6),"runner")
	check(not game.outpost_walkable(Vector3(-7,5,12)),"Original (-7,12) fixture is genuinely blocked by the unchanged gifted tower navigation margin")
	check(game.outpost_walkable(target.position) and game.squads.hunters.legal_target(source,target,start),"Outside-C fixture begins with a walkable, reachable real runner inside the original8m hunter leash")
	step(.001)
	check(bool(hunter_row(source).encounter) and int(hunter_row(source).target_token)==target.get_instance_id() and hunter_row(source).anchor==start,"Outside-C fixture first establishes the genuine six-metre encounter and frozen actual source anchor")
	var beyond := spawn(start+Vector3(9,0,0)); game.focus_cooldown=0; game.aim=beyond.position; await press(KEY_C)
	check(game.focus_target==beyond,"Original root C can legally target an enemy beyond this hunter's encounter anchor")
	var before_outside_c: Dictionary=plain(hunter_row(source))
	step(.001); check(int(hunter_row(source).target_token)==target.get_instance_id() and hunter_row(source).anchor==start,"Hunter rejects globally legal C outside its original8m encounter leash")
	(evidence.specialists as Array).append({"kind":"hunter-outside-c","source":start,"runner":target.position,"beyond":beyond.position,"before":before_outside_c,"after":plain(hunter_row(source))})
	for distance: float in [7.99,8.0,8.01]:
		beyond.position=start+Vector3(distance,0,0); beyond.position.y=game.outpost_height(beyond.position)
		check(game.squads.hunters.legal_target(source,beyond,start)==(distance<=8.0),"Real hunter legal-target boundary uses the original8m anchor at "+str(distance))
	var rogue: BattleUnit=UnitScript.new(); game.squads.add_child(rogue); rogue.setup("minion",0); rogue.set_meta("squad_kind","hunter")
	group.members[1]=rogue
	check(not game.squads.hunters.real_source(source) and not game.squads.hunters.real_source(rogue),"Metadata and forged roster membership cannot replace the registered real hunter source")
	group.members[1]=source; rogue.queue_free(); await process_frame
	(evidence.specialists as Array).append({"kind":"hunter","anchor":start,"endpoint":endpoint,"damage":hurt_events.duplicate(true)})
	group=await ready("artillery",true); if group.is_empty():return
	source=group.members[1]
	for distance: float in [5.49,5.5,16.0,16.01]:
		clear_enemies(); place_group(group,OPEN); target=spawn(OPEN+Vector3(0,0,distance)); await right(FAR_END,true); step(.001)
		check(source.attack_queued==(distance>=5.5 and distance<=16.0),"Artillery AMOVE uses only legal native5.5–16m current-location targets at "+str(distance))
		if not source.attack_queued:check(source.moving,"Illegal near/far artillery target cannot stall AMOVE")
	clear_enemies(); place_group(group,Vector3(-7,5,6)); target=spawn(Vector3(10,5,6)); var near := spawn(Vector3(-7,5,8))
	game.focus_cooldown=0; game.aim=target.position; await press(KEY_C)
	check(game.focus_target==target,"Actual C marks the genuine globally reachable17m far artillery target")
	await right(Vector3(-7,5,11),true); start=source.position; await advance(.4)
	check(source.moving and planar(start,source.position)>.5 and not source.attack_queued and target.hp==target.max_hp and near.hp==near.max_hp,"Too-close enemy and distant C cannot drag or stall an artillery march")
	clear_enemies(); place_group(group,OPEN); target=spawn(OPEN+Vector3(0,0,10)); native_hp=target.hp
	await right(FAR_END,true); step(.001); check(source.attack_windup==1.0,"Artillery starts its full original one-second preparation")
	await advance(.999); check(int(game.squads.artillery_snapshot().launched)==0 and target.hp==native_hp,"Artillery cannot launch or hurt before its native one-second preparation")
	step(.002); var launched: Dictionary=game.squads.artillery_snapshot()
	check(int(launched.launched)==1 and int(launched.flight)==1 and is_equal_approx(source.attack_timer,4.8),"Actual artillery launch retains .8-second committed flight and4.8-second cooldown")
	var cooldown: float=source.attack_timer; await right(OPEN+Vector3(5,0,0)); check(source.attack_timer==cooldown,"Manual MOVE preserves a launched artillery cooldown")
	await advance(.799); check(target.hp==native_hp,"Committed shell cannot hurt before its native .8-second flight")
	step(.002); check(is_equal_approx(target.hp,native_hp-32.0) and int(game.squads.artillery_snapshot().impacts)==1,"Manual overwrite preserves exactly one committed real32-damage shell")
	await capture("artillery-committed-flight")
	await advance(5); check(int(game.squads.artillery_snapshot().launched)==1,"Manual march cannot create extra shells from the old encounter")
	clear_enemies(); place_group(group,OPEN); target=spawn(OPEN+Vector3(0,0,10)); await right(FAR_END,true); endpoint=group.destination
	if not await wait_for(func() -> bool:return not living(target),50,"Native artillery encounter kills its actual enemy"):return
	if not await wait_for(func() -> bool:return guarded(group),50,"Artillery resumes its original endpoint after real death"):return
	check(group.destination==endpoint,"Actual artillery defeat resumes immutable march destination")
	await support_encounter()

func support_encounter() -> void:
	var carriers := await ready("hauler"); if carriers.is_empty():return
	await build_gui("infirmary",INFIRMARY); TransitionFixture.finish_for_fixture(game); await press(KEY_1); clear_enemies(); game.phase_time=10000.0; suspend_defense()
	var medics := await train("medic"); if medics.is_empty():return
	await select_group(carriers); var heap: Vector3=game.logistics.fields[0].position
	await right(heap); check(carriers.order=="haul","Ordinary real right heap retains designated HAUL")
	if not await wait_for(func() -> bool:return game.logistics.snapshot().cargo==24,160,"Real haul route loads24 through original three-second loading"):return
	var stock: Dictionary=game.logistics.snapshot(); var before_parts: int=game.scrap
	place_group(medics,heap+Vector3(5,0,0)); await select_group(carriers); await select_group(medics,true)
	var destination: Vector3=game.logistics.fields[4].position; await right(destination,true)
	check(carriers.order=="attack_move" and medics.order=="attack_move" and game.logistics.snapshot().cargo==24,"Mixed support Shift-right on another real heap chooses AMOVE and retains genuine cargo")
	var team: Dictionary=game.logistics.snapshot().teams[0]
	check(not bool(team.automatic) and int(team.preferred_field)==-1 and not bool(medics.therapy_enabled),"Manual AMOVE clears automatic/preferred hauling while preserving medic's default disabled therapy")
	for field: Dictionary in game.logistics.snapshot().fields:check(int(field.claimed_by)!=int(carriers.id),"Manual AMOVE releases the carrier's real heap reservation")
	var enemy := spawn(destination+Vector3(0,0,2)); var hp: float=enemy.hp
	if not await wait_for(func() -> bool:return guarded(carriers) and guarded(medics),160,"Mixed support arrival at ordinary formation endpoints"):return
	check(game.logistics.snapshot().remaining==stock.remaining and game.logistics.snapshot().cargo==24 and game.logistics.snapshot().delivered==stock.delivered and game.scrap==before_parts,"Manual carrier AMOVE neither loads nor delivers remotely and preserves all actual cargo")
	check(enemy.hp==hp and int(game.squads.medic_snapshot().treatments)==0,"Haulers and default-off medics never attack or automatically enable therapy during AMOVE")
	camera_at(destination); await open_army(1); await capture("mixed-support-cargo24")
	(evidence.specialists as Array).append({"kind":"support","before":stock,"after":game.logistics.snapshot(),"medical":plain(game.squads.medic_snapshot())})

func physical_paths() -> void:
	var group := await ready("shield"); if group.is_empty():return
	place_group(group,HOME); gate_tokens.clear(); await right(OPEN,true); var endpoint: Vector3=group.destination
	if not await wait_for(func() -> bool:return guarded(group),50,"Three real members traverse the south gate"):return
	check(gate_tokens.size()==3 and group.destination==endpoint,"Every real trained member crosses the unique south gate and reaches the fixed destination")
	(evidence.paths as Array).append({"route":"birth-side-to-outside","tokens":gate_tokens.keys(),"endpoint":endpoint})
	group=await ready("ranged",true); if group.is_empty():return
	place_group(group,Vector3(8,5,12)); var source: BattleUnit=group.members[1]; var enemy := spawn(Vector3(8,0,17)); var hp: float=enemy.hp
	check(not game.can_attack_line(source.position,enemy.position),"Actual castle wall blocks the otherwise nearby enemy line")
	await right(Vector3(-8,5,12),true); await advance(.4)
	check(source.moving and not source.attack_queued and enemy.hp==hp,"AMOVE never fires through the genuine wall and retains movement")
	clear_enemies(); place_group(group,OPEN); enemy=spawn(OPEN+Vector3(0,0,2)); game.enemies.erase(enemy)
	await right(FAR_END,true); await advance(.2)
	check(source.moving and not source.attack_queued and enemy.hp==enemy.max_hp,"Detached real enemy cannot be reacquired by an AMOVE scan")
	enemy.queue_free(); await process_frame
	group=await ready("shield"); if group.is_empty():return
	place_group(group,HOME); await right(OPEN,true); endpoint=group.destination; var stations: Array=group.attack_move_stations.duplicate()
	for index in game.world.tower_pads.size():
		var pad: Dictionary=game.world.tower_pads[index]
		if int(pad.level)>0:game.damage_tower(index,float(pad.hp))
	for x: float in [-11.0,11.0]:check(game.build_structure_at(Vector3(x,5,7.5),"barracks"),"Actual paid end building seals the dynamic row")
	var gap := -1
	for x: float in [-7.5,-4.5,-1.5,1.5,4.5,7.5]:
		check(game.build_tower_at(Vector3(x,5,7.5)),"Actual paid tower seals the dynamic row at "+str(x))
		if x==1.5:gap=game.world.tower_pads.size()-1
	gate_tokens.clear(); await advance(5)
	check(group.order=="attack_move" and group.destination==endpoint and group.attack_move_stations==stations and gate_tokens.is_empty(),"New complete building row preserves blocked AMOVE intent without replacing endpoint or teleporting")
	camera_at(HOME); await capture("path-real-row-blocked")
	check(gap>=0,"Real row records the exact live gap tower")
	if gap<0:return
	game.damage_tower(gap,float(game.world.tower_pads[gap].hp))
	if not await wait_for(func() -> bool:return guarded(group),60,"Retained AMOVE recovers after actual tower destruction"):return
	check(gate_tokens.size()==3 and group.destination==endpoint,"Actual destruction reopens navigation and all original members continue without a new command")
	camera_at(OPEN); await capture("path-real-gap-recovered")
	(evidence.paths as Array).append({"route":"dynamic-row","gap":gap,"tokens":gate_tokens.keys(),"endpoint":endpoint})

func reenter(victim: BattleUnit, _source: BattleUnit, _hp: float, _shield: float, mode: String, hook: Dictionary) -> void:
	if int(hook.count)>0:return
	hook.count=1; hook.victim=victim.get_instance_id()
	match mode:
		"clear":game.squads.clear()
		"setup":game.squads.setup(game)
		"defeat":game.end_defeat("Explicit synchronous lifecycle boundary")
		"victory":game.day_number=game.max_nights(); TransitionFixture.finish_for_fixture(game)

func frozen_lifecycle() -> void:
	var group := await ready("shield",true); if group.is_empty():return
	var source: BattleUnit=group.members[1]; var enemy := spawn(OPEN+Vector3(0,0,2)); await right(FAR_END,true); step(.001)
	await press(KEY_F1); check(game.phase=="paused" and game.music_credits_open,"Actual F1 opens sources above pause during a native AMOVE windup")
	var before := state(); var rejected: Dictionary=game.squads.command_attack_move(OPEN)
	await right(OPEN,true); game.simulate(5)
	check(not bool(rejected.ok) and state()==before,"Pause freezes actual movement, enemy damage, pending windup, queues, clocks and rejects AMOVE API/input")
	await capture("lifecycle-paused-sources")
	await press(KEY_ESCAPE)
	check(not game.music_credits_open and game.phase=="paused" and state()==before,"First actual Esc dismisses sources while preserving the frozen pause and pending AMOVE")
	await capture("lifecycle-paused")
	await press(KEY_ESCAPE)
	check(game.phase=="night" and state().orders==before.orders,"Second actual Esc resumes the original night with its untouched pending order")
	before=state(); await press(KEY_V); check(game.phase=="draft","Actual paid V card selection opens the production draft")
	var frozen := state(); rejected=game.squads.command_attack_move(OPEN); await right(OPEN,true); game.simulate(5)
	check(not bool(rejected.ok) and state()==frozen,"Paid draft freezes and rejects attack-move through real APIs/input")
	await press(KEY_1); check(game.phase=="night" and state().orders==before.orders,"Actual card selection retains the pending original AMOVE order")
	var hp: float=enemy.hp; await right(FAR_END)
	check(not source.attack_queued and source.attack_windup==0,"Manual MOVE cancels a pending encounter preparation")
	await advance(.4); check(enemy.hp==hp,"Canceled native windup cannot commit later damage")
	await right(FAR_END,true); step(.001); await advance(source.windup_duration+.001)
	var cooldown: float=source.attack_timer; check(cooldown>0 and enemy.hp<hp,"Lifecycle fixture earns a genuine positive cooldown from actual damage")
	await right(OPEN+Vector3(5,0,0)); check(source.attack_timer==cooldown,"Manual MOVE cannot reset earned cooldown")
	game.squads.command_guard(OPEN); check(source.attack_timer==cooldown,"Manual GUARD cannot reset earned cooldown")
	await right(FAR_END,true); check(source.attack_timer==cooldown,"Replacement AMOVE cannot reset earned cooldown")
	var endpoint: Vector3=group.destination; var stations: Array=group.attack_move_stations.duplicate()
	TransitionFixture.finish_for_fixture(game); await press(KEY_1); clear_enemies(); game.phase_time=10000.0
	check(game.phase=="day" and group.order=="attack_move" and group.destination==endpoint and group.attack_move_stations==stations and source.attack_timer==cooldown and not source.attack_queued,"Actual dawn preserves manual endpoint and CD while clearing stale encounter preparation")
	var old_token := source.get_instance_id(); source.hurt(100000.0,null); await process_frame
	var balance: int=game.scrap; await press(KEY_L)
	var replacement: BattleUnit=group.members[1]
	check(living(replacement) and replacement.get_instance_id()!=old_token and game.scrap<balance and group.destination==endpoint and group.attack_move_stations==stations,"Real daylight L pays for a new token that inherits the current fixed AMOVE destination")
	game.start_night(); clear_enemies(); game.phase_time=10000.0; game.wave_index=game.WAVES_PER_NIGHT
	check(group.order=="attack_move" and group.destination==endpoint,"Actual sunset preserves manual march intent")
	place_group(group,OPEN); enemy=spawn(OPEN+Vector3(0,0,2)); step(.001); var parts: int=game.scrap
	enemy.queue_free(); game.enemies.erase(enemy); await process_frame; step(.1)
	check(replacement.moving and not replacement.attack_queued and game.scrap==parts,"Queued deletion invalidates encounter without inventing death or reward")
	for mode: String in ["clear","setup","defeat","victory"]:
		group=await ready("shield"); if group.is_empty():return
		enemy=spawn(OPEN+Vector3(0,0,1)); var hook: Dictionary={"count":0}; enemy.damage_confirmed.connect(reenter.bind(mode,hook))
		await right(FAR_END,true); step(.001); hurt_events.clear(); step(.181)
		check(int(hook.count)==1 and hurt_events.size()==1,"Synchronous true hurt callback "+mode+" stops every remaining old-generation member attack")
		check(game.squads.squads.is_empty(),"Synchronous "+mode+" clears the actual old roster")
		(evidence.lifecycle as Array).append({"mode":mode,"hits":hurt_events.duplicate(true),"phase":game.phase,"stock":game.logistics.snapshot()})
	group=await ready("shield"); if group.is_empty():return
	await right(FAR_END,true); var old_root := game.get_instance_id(); game.end_defeat("Explicit actual retry boundary")
	await press(KEY_ENTER)
	for _frame in 240:
		if current_scene!=null and current_scene.get_instance_id()!=old_root:break
		await create_timer(.02,true,false,true).timeout
	check(current_scene!=null and current_scene.get_instance_id()!=old_root,"Actual Enter produces a new scene instead of continuing the retired root")
	if current_scene==null or current_scene.get_instance_id()==old_root:return
	game=current_scene as Node3D; game.set_process(false); game.world.set_process(false)
	for _frame in 5:await process_frame
	check(not is_instance_id_valid(old_root) and game.run.seed_value==SEED and game.phase=="draft" and game.scrap==90 and game.squads.squads.is_empty(),"Same-seed actual retry releases old actors and resets wallet/draft without AMOVE inheritance")

func clear_transients() -> void:
	game.notice_time=0; game.reward_toasts.clear(); game.beacon_alarm_time=0; game.hero_damage_flash_time=0; game.combat_milestone_time=0
	game.combat.clear_transients()

func measure_hud(tag: String, help: bool = false) -> void:
	var before := state(); var previous_viewport: Vector2i=root.size
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport; await redraw()
		var hint_seen := false; var army_seen := false; var help_bottom := 0.0
		for row: Dictionary in game.hud.drawn_labels:
			check(row.point.x>=0 and row.point.x+float(row.width)<=1440 and row.point.y-float(row.ascent)>=0 and row.point.y+float(row.descent)<=900,"Actual glyph rectangle fits viewport in "+tag+": "+String(row.text))
			for character: String in String(row.text):
				var code := character.unicode_at(0)
				if code>=0x4e00 and code<=0x9fff:check(game.hud.font.has_char(code),"Actual font contains Chinese glyph "+character)
			if row.point==Vector2(38,808):
				hint_seen=true
				check(int(row.size)==13 and float(row.width)<=272 and String(row.text) in ["右键指挥 · Shift+右键推进","工队右键采运 · Shift+右键推进","选点中 · 原部队命令保留"],"Complete actual13px selected hint fits the original272px budget")
			if row.point==Vector2(38,783):check(int(row.size)==14 and float(row.width)<=272,"Actual selected title fits the original272px budget at14px")
			if row.point==Vector2(46,494):check(int(row.size)==13 and float(row.width)<=496 and row.text==game.hud.control_group_hint(),"Complete actual shortcut-group row fits its original496px column")
			if row.point==Vector2(46,522):
				army_seen=true; check(int(row.size)==14 and float(row.width)<=496 and row.text=="Shift+右键攻击推进 · Alt+右键工队护航","Complete actual attack-move and escort instructions fit496px at14px")
			if help and row.point.x==46 and row.point.y>=230:help_bottom=maxf(help_bottom,float(row.point.y)+float(row.descent))
		check(game.squads.selected_count()==0 or hint_seen,"Actual selected strip retains the complete command hint")
		check(game.hud.detail_tab!="army" or army_seen,"Actual existing army drawer displays the complete new instruction")
		check(not help or help_bottom<=692,"Actual final help glyph remains above the existing close button")
		(evidence.hud as Array).append({"tag":tag,"viewport":viewport,"hint":hint_seen,"army":army_seen,"help_bottom":help_bottom})
	check(state()==before,"Actual three-viewport HUD reads never reissue orders, move, spend or advance RNG/clocks")
	root.size=previous_viewport; root.content_scale_size=previous_viewport; await redraw()

func actual_hud() -> void:
	var group := await ready("shield"); if group.is_empty():return
	clear_transients(); await right(FAR_END); clear_transients(); await redraw()
	var original: Array=game.hud.drawn_rects.duplicate(); await right(FAR_END,true); clear_transients(); await redraw()
	check(game.hud.drawn_rects==original and SELECTED_RECT in game.hud.drawn_rects,"AMOVE uses precisely the original selected rectangle without new permanent HUD area")
	var title_seen := false
	for row: Dictionary in game.hud.drawn_labels:
		if row.point==Vector2(38,783):title_seen=row.text=="已选1队 · 推进1队"
	check(title_seen,"Actual selected title truthfully reports one selected attacking march")
	await measure_hud("selected-march"); camera_at(OPEN); await capture("hud-selected-march")
	var before := state(); await click_ui(SELECTED_RECT,MOUSE_BUTTON_RIGHT,true)
	check(state()==before,"Visible original selected strip swallows actual Shift-right without world commands")
	await open_army(); await measure_hud("army"); await capture("hud-army")
	await click_ui(game.hud.details_tab_rect(4)); await redraw()
	check(game.hud.detail_tab=="help","Actual tab opens the existing help drawer")
	await measure_hud("help",true); await capture("hud-help")
	await close_drawer(); var point: Vector3=OPEN+Vector3(6,0,0); await right(point,true)
	check(planar(group.destination,game.ground_point(game.camera.unproject_position(point)))<.02,"Dismissed drawer releases real world Shift-right input")
	group=await ready("hunter",true); if group.is_empty():return
	await right(FAR_END,true); await open_army(2); await measure_hud("hunter-third-page"); await capture("hud-hunter-page")
	var footer := false
	for row: Dictionary in game.hud.drawn_labels:
		if String(row.text).contains("普通移动/召回不追敌"):footer=true; check(float(row.width)<=496,"Actual hunter ordinary/AMOVE distinction fits its existing footer")
	check(footer,"Actual hunter page retains the complete ordinary movement/AMOVE distinction")

func natural_tick() -> void:
	game.aim=game.hero.position+Vector3(0,0,8)
	if game.gate_pressure()>0:game.cast(0)
	if game.hero.hp<game.hero.max_hp*.6:game.cast(1); game.cast(4)
	if game.gate_pressure()>=6:game.cast(3)
	step()

func natural_economy() -> void:
	await fresh(false); await right(Vector3(0,5,10))
	var first_night_elapsed := 0.0
	var first_night_cutoff: Dictionary = {}
	# Bound actual residual combat; the production assault deadline is unchanged.
	for frame in ceili(240.0 / STEP):
		if game.phase!="night":break
		natural_tick()
		first_night_elapsed += STEP
		if first_night_cutoff.is_empty() and first_night_elapsed >= game.NIGHT_LENGTH:
			first_night_cutoff = TransitionFixture.deadline_evidence(game, first_night_elapsed)
		if frame%100==99:await process_frame
	TransitionFixture.record_natural_receipt(game, evidence, "opening", first_night_elapsed, first_night_cutoff)
	check(game.phase=="draft" and game.hero.alive and game.beacon_hp>0,"Unmodified first night reaches genuine dawn under the fixed original skill policy")
	if game.phase!="draft":return
	var deaths: int=game.kills; var dawn_parts: int=game.scrap; await press(KEY_1)
	check(game.phase=="day" and game.phase_time==90.0 and game.scrap==dawn_parts,"Actual dawn keeps original90-second daylight and genuinely earned wallet")
	await build_gui("barracks",BARRACKS)
	var group := await train("shield"); if group.is_empty():return
	var after_payments: int=game.scrap
	check(after_payments==dawn_parts-60-70,"Natural barracks and shield queue pay130 from the sole earned balance")
	await select_group(group); gate_tokens.clear(); await right(OPEN,true)
	var endpoint: Vector3=group.destination; var sent_at: float=90.0-game.phase_time; var arrival := -1.0
	while game.phase=="day":
		if arrival<0 and guarded(group):arrival=90.0-game.phase_time
		natural_tick()
		if int(elapsed*10)%100==0:await process_frame
	check(game.phase=="night" and game.day_number==2 and game.phase_time==105.0,"Natural original90-second day reaches the original105-second second night")
	check(arrival>=sent_at and gate_tokens.size()==3 and group.destination==endpoint,"Natural paid squad physically reaches the true AMOVE endpoint through all three native gate crossings")
	(evidence.economy as Array).append({"seed":SEED,"opening":90,"night_seconds":105,"day_seconds":90,"first_night_deaths":deaths,"dawn_parts":dawn_parts,"payments":[{"kind":"barracks","cost":60},{"kind":"shield","cost":70}],"after_payments":after_payments,"sent_at_day_second":sent_at,"arrived_at_day_second":arrival,"endpoint":endpoint,"gate_tokens":gate_tokens.keys(),"sunset_parts":game.scrap,"hero_hp":game.hero.hp,"beacon_hp":game.beacon_hp,"scope":"one fixed-seed original skill policy; no added money, actor placement, enemy-stat or phase-clock changes; only first-night and daylight route proof"})
	print("AMOVE_NATURAL dawn_parts=",dawn_parts," deaths=",deaths," after130=",after_payments," sent=",sent_at," arrived=",arrival," sunset_parts=",game.scrap)
	camera_at(OPEN); await capture("natural-unextended-day-arrival")

func run() -> void:
	var cases: Dictionary={"input":physical_input,"encounter":ordinary_encounters,"specialists":specialized_encounters,"path":physical_paths,"lifecycle":frozen_lifecycle,"hud":actual_hud,"economy":natural_economy}
	var args := OS.get_cmdline_user_args(); var selected: Array=cases.keys(); var index := args.find("--case")
	if index>=0 and index+1<args.size():selected=[args[index+1]]
	for name: String in selected:
		if not cases.has(name):check(false,"Unknown attack-move stage "+name); break
		active_stage=name; print("AMOVE_STAGE_BEGIN ",name)
		await (cases[name] as Callable).call()
		print("AMOVE_STAGE_END ",name," checks=",checks," failures=",failures.size())
		(evidence.completed as Array).append(name)
		if not failures.is_empty():break
	await close_game()
	# Four headless presentation frames can elapse faster than the background
	# Ogg decoder/audio mixer retires its stopped playback handles. Keep the
	# real production shutdown checks, then give final thread teardown actual
	# wall time, as the existing clean-HUD acceptance cleanup does.
	await create_timer(.5,true,false,true).timeout
	evidence.shutdown_audio_drain_seconds=.5
	var folder := ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("nightfall-attack-move.json"),FileAccess.WRITE)
	check(file!=null,"Structured attack-move evidence opens below local build")
	evidence.checks=checks; evidence.failures=failures
	if file!=null:file.store_string(JSON.stringify(evidence,"\t")); file.close()
	finished=true; print("AMOVE_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
