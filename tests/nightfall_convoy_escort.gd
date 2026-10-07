extends "res://tests/nightfall_attack_move.gd"
## Artificial phase setup only; natural clearance and victory use real combat.
## Independent production convoy acceptance. Shared helpers supply real GUI
## purchases, navigation, native combat, font observation and scene cleanup.
## Precision uses5000/extended clocks/direct stations/stationary or spawned
## enemies/100000 true hurt. Economy preserves90/105/90 and native actors.

var crossings: Dictionary = {}
var watched_damage: Dictionary = {}
var income_book: Array[Dictionary] = []
var convoy_time := 0.0
var stage_returned := false
var medical_returned := false
var route_performance: Dictionary = {}
var natural_monitor := false
var natural_wallet_changes: Array[Dictionary] = []
const CONVOY_ROOT_OBSERVER := """extends 'res://scripts/nightfall.gd'
var convoy_movement_route_calls := 0
var convoy_movement_route_max_usec := 0
func build_day_hunter_route(creature: BattleUnit, destination: Vector3) -> void:
\tconvoy_movement_route_calls+=1
\tvar started: int=Time.get_ticks_usec()
\tsuper.build_day_hunter_route(creature,destination)
\tconvoy_movement_route_max_usec=maxi(convoy_movement_route_max_usec,Time.get_ticks_usec()-started)
"""

func _initialize() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	render_test="--render-test" in args; output_dir="res://build/convoy-escort"
	var index: int=args.find("--output-dir")
	if index>=0 and index+1<args.size():
		var candidate: String=ProjectSettings.globalize_path(args[index+1]).simplify_path()
		var allowed: String=ProjectSettings.globalize_path("res://build").simplify_path()
		if candidate.begins_with(allowed+"/"):output_dir=candidate
		else:check(false,"Convoy evidence must remain below the local build directory")
	root.size=VIEWPORTS[0]; root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT; root.content_scale_size=VIEWPORTS[0]
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.position=Vector2i(10000,10000); root.hide()
	evidence={"seed":SEED,"scope":"precision5000/extended clocks/direct actor stations/stationary enemies and100000 true casualties; native moving enemies explicitly restored in combat; economy original90/105/90 and unchanged actors/seed with each genuine income and purchase recorded; controlled capture lighting; no human or complete campaign balance claim","completed":[],"captures":[],"capture_receipt":[],"input":[],"cycle":[],"combat":[],"encounters":[],"specialists":[],"path":[],"paths":[],"lifecycle":[],"hud":[],"economy":[]}
	create_timer(900.0,true,false,true).timeout.connect(watchdog)
	call_deferred("run")

func watchdog() -> void:
	if finished:return
	check(false,"Convoy acceptance stalled in "+active_stage)
	await finalize(); finished=true; quit(1)

func escort_state() -> Dictionary:
	return game.squads.escort_snapshot()

func escort_row(id: int) -> Dictionary:
	for row: Dictionary in escort_state().squads:
		if int(row.squad_id)==id:return row
	return {}

func state() -> Dictionary:
	var result: Dictionary=super.state()
	result.escort=plain(escort_state())
	return result

func close_game() -> void:
	if not is_instance_valid(game):return
	var manager: Node=game.squads
	await game.prepare_shutdown()
	check(int(manager.escort_snapshot().count)==0,"Actual shutdown clears and unbinds all convoy targets")
	await super.close_game()

func fresh(is_precision: bool=true) -> void:
	await close_game(); precision=is_precision; natural_monitor=false; natural_wallet_changes.clear()
	check(RunSession.queue_request(self,SEED,"siege"),"Actual new convoy run accepts the fixed siege seed")
	var observer := GDScript.new(); observer.source_code=CONVOY_ROOT_OBSERVER
	check(observer.reload()==OK,"Fixed convoy root observer forwards actual movement route building without changing behavior")
	var packed: PackedScene=load("res://scenes/nightfall.tscn").duplicate()
	var bundled: Dictionary=packed.get("_bundled").duplicate(true); var replaced := 0
	for index in bundled.variants.size():
		var value: Variant=bundled.variants[index]
		if value is Script and value.resource_path=="res://scripts/nightfall.gd":bundled.variants[index]=observer; replaced+=1
	check(replaced==1,"Observer replaces only the one fixed root script before constructing production controllers")
	packed.set("_bundled",bundled); game=packed.instantiate(); game.scene_file_path="res://scenes/nightfall.tscn"; root.add_child(game); current_scene=game
	for _frame in 5:await process_frame
	game.set_process(false); game.world.set_process(false)
	var hud_script := GDScript.new(); hud_script.source_code=OBSERVER; check(hud_script.reload()==OK,"Fixed convoy HUD observer forwards real input and font drawing")
	var original: Control=game.hud; var layer: Node=original.get_parent(); layer.remove_child(original); original.queue_free()
	var observed: Control=hud_script.new(); observed.game=game; game.hud=observed; layer.add_child(observed); observed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await press(KEY_1)
	check(game.phase=="night" and game.phase_time==105.0 and game.scrap==90 and game.tower_count()==2 and game.run.seed_value==SEED,"Actual convoy opening preserves original ninety parts, gifted towers, seed and105-second night")
	elapsed=0.0; hurt_events.clear(); death_events.clear(); gate_tokens.clear()
	route_performance={"steps":0,"max_step_usec":0,"max_module_queries_per_step":0,"max_movement_route_calls_per_step":0,"module_queries":0,"module_route_checks":0,"movement_route_calls":0}
	if precision:
		game.scrap=5000; game.phase_time=10000.0; game.wave_index=game.WAVES_PER_NIGHT
		clear_enemies(); suspend_defense(); stand(HOME)

func module_totals() -> Dictionary:
	var result: Dictionary={"queries":0,"checks":0}
	for row: Dictionary in escort_state().squads:
		result.queries+=int(row.path_queries); result.checks+=int(row.route_checks)
		check(int(row.route_checks)<=6*int(row.station_updates) and int(row.path_queries)<=int(row.route_checks),"Each actual module station refresh performs at most six route checks and no more AStar calls than checks")
	return result

func step(delta: float=STEP, freeze_enemy: bool=true) -> void:
	if natural_monitor:
		for actor: Variant in game.enemies+[game.hero]:
			if living(actor) and not watched_damage.has(actor.get_instance_id()):
				watched_damage[actor.get_instance_id()]=true; actor.damage_confirmed.connect(record_hurt); actor.defeated.connect(record_death)
	var wallet_before: int=game.scrap; var killed_before: int=game.kills; var delivered_before: int=int(game.logistics.snapshot().delivered)
	var positions: Dictionary={}
	for squad: Dictionary in game.squads.squads:
		for member: Variant in squad.members:
			if living(member):positions[member.get_instance_id()]=member.position
	var module_before: Dictionary=module_totals(); var route_before: int=int(game.get("convoy_movement_route_calls")); var started: int=Time.get_ticks_usec()
	super.step(delta,freeze_enemy); convoy_time+=delta
	if natural_monitor and game.scrap!=wallet_before:
		natural_wallet_changes.append({"at":convoy_time,"before":wallet_before,"after":game.scrap,"delta":game.scrap-wallet_before,"kills_before":killed_before,"kills_after":game.kills,"delivered_before":delivered_before,"delivered_after":int(game.logistics.snapshot().delivered)})
	var duration: int=Time.get_ticks_usec()-started; var module_after: Dictionary=module_totals()
	var queries: int=maxi(0,int(module_after.queries)-int(module_before.queries)); var routes: int=maxi(0,int(game.get("convoy_movement_route_calls"))-route_before)
	route_performance.steps+=1; route_performance.max_step_usec=maxi(int(route_performance.max_step_usec),duration)
	route_performance.max_module_queries_per_step=maxi(int(route_performance.max_module_queries_per_step),queries)
	route_performance.max_movement_route_calls_per_step=maxi(int(route_performance.max_movement_route_calls_per_step),routes)
	route_performance.module_queries+=queries; route_performance.module_route_checks+=maxi(0,int(module_after.checks)-int(module_before.checks)); route_performance.movement_route_calls+=routes
	for squad: Dictionary in game.squads.squads:
		for member: Variant in squad.members:
			if not living(member) or not positions.has(member.get_instance_id()):continue
			var previous: Vector3=positions[member.get_instance_id()]
			if (previous.z<Layout.WALL_CENTER and member.position.z>=Layout.WALL_CENTER) or (previous.z>Layout.WALL_CENTER and member.position.z<=Layout.WALL_CENTER):
				var fraction: float=(Layout.WALL_CENTER-previous.z)/(member.position.z-previous.z)
				check(absf(lerpf(previous.x,member.position.x,fraction))<Layout.GATE_HALF,"Both directions of every escort/carrier crossing use the genuine south gate")
				var token: int=member.get_instance_id()
				if not crossings.has(token):crossings[token]={"out":0,"in":0,"kind":squad.kind,"squad_id":squad.id}
				var direction: String="out" if member.position.z>previous.z else "in"
				crossings[token][direction]=int(crossings[token][direction])+1
				if not crossings[token].has("first_"+direction):crossings[token]["first_"+direction]=convoy_time
				crossings[token]["last_"+direction]=convoy_time

func wait_actual(predicate: Callable, seconds: float, label: String, freeze_enemy: bool=true) -> bool:
	for frame in ceili(seconds/STEP):
		if bool(predicate.call()):return true
		step(STEP,freeze_enemy)
		if frame%100==99:await process_frame
	var passed: bool=bool(predicate.call()); check(passed,label+" timed out")
	return passed

func alt_mouse(point: Vector2, shift: bool=false) -> void:
	var motion := InputEventMouseMotion.new(); motion.position=point; motion.global_position=point; motion.alt_pressed=true; motion.shift_pressed=shift
	root.push_input(motion,true); await process_frame
	var event := InputEventMouseButton.new(); event.position=point; event.global_position=point; event.button_index=MOUSE_BUTTON_RIGHT; event.alt_pressed=true; event.shift_pressed=shift
	event.pressed=true; event.button_mask=MOUSE_BUTTON_MASK_RIGHT; root.push_input(event,true); await process_frame
	event.pressed=false; event.button_mask=0; root.push_input(event,true); await process_frame

func alt_member(member: BattleUnit, shift: bool=false) -> void:
	await close_drawer(); camera_at(member.position)
	await alt_mouse(game.camera.unproject_position(member.position+Vector3.UP*.7),shift)

func carrier_row(id: int) -> Dictionary:
	for row: Dictionary in game.logistics.snapshot().teams:
		if int(row.id)==id:return row
	return {}

func target_invariants(target: Dictionary) -> Dictionary:
	var row: Dictionary={}
	for item: Dictionary in super.state().orders:
		if int(item.id)==int(target.id):row=item
	return {"order":row,"stock":plain(game.logistics.snapshot()),"parts":game.scrap,"rng":game.rng.state,"spawn_rng":game.spawn_rng.state,"card_rng":game.run.rng.state,"clock":game.phase_time,"hero_goal":game.move_goal,"hero_path":game.hero_path.duplicate()}

func convoy(kinds: Array=["shield"], single: bool=false) -> Array[Dictionary]:
	await fresh(); crossings.clear(); watched_damage.clear(); convoy_time=0.0
	await build_gui("barracks",BARRACKS); await build_gui("workshop",WORKSHOP); await build_gui("depot",DEPOT)
	if "ballista" in kinds or "artillery" in kinds:await build_gui("laboratory",LAB)
	if "artillery" in kinds:await build_gui("armory",ARMORY)
	if "medic" in kinds:await build_gui("infirmary",INFIRMARY)
	var result: Array[Dictionary]=[]; var carrier: Dictionary=await train("hauler")
	if carrier.is_empty():return []
	result.append(carrier)
	for kind: String in kinds:
		var guard: Dictionary=await train(kind)
		if guard.is_empty():return []
		if single:
			for slot: int in [0,2]:
				if living(guard.members[slot]):guard.members[slot].hurt(100000.0,null)
			await process_frame
		result.append(guard)
	TransitionFixture.finish_for_fixture(game); await press(KEY_1); clear_enemies(); game.phase_time=10000.0; suspend_defense(); stand(HOME)
	await select_group(carrier); game.squads.command_guard(OPEN); place_group(carrier,OPEN)
	for index in range(1,result.size()):place_group(result[index],OPEN+Vector3(0,0,-5-float(index)*3))
	check(int(escort_state().count)==0,"A real new paid roster has no inherited convoy binding")
	return result

func bind_convoy(groups: Array[Dictionary], mixed: bool=false, shift: bool=false) -> void:
	await select_group(groups[1])
	for index in range(2,groups.size()):await select_group(groups[index],true)
	if mixed:await select_group(groups[0],true)
	var target: BattleUnit=groups[0].members[1]
	var before: Dictionary=target_invariants(groups[0]); await alt_member(target,shift)
	check(target_invariants(groups[0])==before,"Actual Alt target pickup preserves every carrier path, reservation, load/unload clock, true cargo, sole wallet and RNG")
	for index in range(1,groups.size()):
		check(groups[index].order=="escort" and not escort_row(int(groups[index].id)).is_empty() and int(escort_row(int(groups[index].id)).target_squad_id)==int(groups[0].id),"Actual Alt-right binds precisely the selected paid non-carrier squad")

func physical_input() -> void:
	var groups: Array[Dictionary]=await convoy(["shield","ranged"]); if groups.size()!=3:return
	await select_group(groups[0]); await right(game.logistics.fields[0].position); step(.1)
	check(groups[0].order=="haul" and int(carrier_row(int(groups[0].id)).preferred_field)==0,"Ordinary real right first designates the finite source")
	await bind_convoy(groups,true,true)
	var before: Dictionary=state(); await alt_member(groups[0].members[1],true)
	check(state()==before,"Alt+Shift remains convoy and repeating the same real target is a complete no-op")
	await alt_mouse(game.camera.unproject_position(OPEN+Vector3(15,0,0)))
	check(state()==before,"Actual Alt miss consumes input without moving hero or any selected squad")
	var enemy: BattleUnit=spawn(OPEN+Vector3(0,0,12)); before=state(); camera_at(enemy.position)
	await alt_mouse(game.camera.unproject_position(enemy.position+Vector3.UP*.7))
	check(state()==before,"Actual Alt enemy hit rejects rather than falling into attack or hero movement")
	var rogue: BattleUnit=UnitScript.new(); game.squads.add_child(rogue); rogue.setup("minion",0); rogue.set_meta("squad_kind","hauler"); rogue.position=OPEN+Vector3(8,0,0)
	before=state(); var rejection: Dictionary=game.squads.command_escort(rogue)
	check(not bool(rejection.ok) and state()==before,"Forged hauler metadata outside the authoritative paid roster cannot be escorted")
	rogue.queue_free(); await process_frame
	await select_group(groups[0]); before=state(); await alt_member(groups[0].members[1])
	check(state()==before,"Carrier-only selection rejects Alt and cannot change any carrier")
	game.squads.cancel_selection(); before=state(); await alt_member(groups[0].members[1])
	check(state()==before,"No selected non-carrier consumes Alt without hero path fallback")
	await select_group(groups[1]); await open_army(); before=state()
	await alt_mouse(game.hud.SQUAD_PANEL_RECT.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900))
	check(state()==before,"Visible F3 drawer consumes Alt-right before the world picker")
	await close_drawer(); await press(KEY_Y); before=plain(escort_state()); await alt_member(groups[0].members[1])
	check(plain(escort_state())==before,"Active construction right cancellation has priority over convoy")
	if game.construction.active:await press(KEY_ESCAPE)
	await open_army(); await click_ui(game.hud.RALLY_SELECTOR_RECT); await click_ui(game.hud.RALLY_SET_RECT)
	check(game.rally.active,"Actual original F3 controls enter independent rally selection")
	before=state(); await alt_member(groups[0].members[1])
	check(not game.rally.active and state()==before,"Actual rally-selection Alt-right cancels its picker before convoy or hero orders")
	await bind_convoy(groups); camera_at(OPEN); await capture("input-real-mixed-convoy")
	(evidence.input as Array).append({"snapshot":escort_state(),"target":target_invariants(groups[0])})
	stage_returned=true

func repeated_cycle() -> void:
	var groups: Array[Dictionary]=await convoy(["shield","ranged"]); if groups.size()!=3:return
	place_group(groups[0],HOME); place_group(groups[1],HOME+Vector3(0,0,2)); place_group(groups[2],HOME+Vector3(0,0,4))
	await select_group(groups[0]); await right(game.logistics.fields[0].position); await bind_convoy(groups)
	crossings.clear(); var parts: int=game.scrap
	if not await wait_actual(func() -> bool:return carrier_row(int(groups[0].id)).state=="loading",70,"First true south-gate arrival at finite heap"):return
	var first: Dictionary=carrier_row(int(groups[0].id)); await advance(.99)
	var before: Dictionary=state(); await alt_member(groups[0].members[1]); check(state()==before,"Repeated convoy target during positive real loading does not restart the source clock")
	check(float(carrier_row(int(groups[0].id)).loading_progress)>=float(first.loading_progress)+.98/3.0,"Loading keeps advancing under convoy without remote cargo")
	await capture("cycle-first-real-loading")
	if not await wait_actual(func() -> bool:return int(game.logistics.snapshot().delivered)>=48,170,"Two true finite loads and per-member return deliveries"):return
	check(game.scrap==parts+int(game.logistics.snapshot().delivered),"Isolated convoy movement pays exactly actual carrier delivery and never produces another balance")
	var second: Dictionary=carrier_row(int(groups[0].id))
	check(int(second.preferred_field)==0 and groups[0].order=="haul","Two escorted round trips preserve the original designated heap and automatic haul intent")
	for guard: Dictionary in groups:
		for member: Variant in guard.members:
			if not living(member):continue
			var row: Dictionary=crossings.get(member.get_instance_id(),{})
			check(int(row.get("out",0))>=2 and int(row.get("in",0))>=2,"Each actual carrier and both escort kinds traverse both directions of the south gate for two trips")
	(evidence.cycle as Array).append({"stock":game.logistics.snapshot(),"crossings":crossings.duplicate(true),"escort":escort_state(),"parts_before":parts,"parts_after":game.scrap,"route_performance":route_performance.duplicate(true),"movement_route_max_usec":game.get("convoy_movement_route_max_usec")})
	camera_at(DEPOT); await capture("cycle-two-real-returns")
	await select_group(groups[0]); var loaded: bool=await wait_actual(func() -> bool:return int(game.logistics.snapshot().cargo)==24,90,"Third real cargo before manual carrier command")
	if not loaded:return
	var stock: Dictionary=game.logistics.snapshot(); await right(OPEN+Vector3(8,0,0)); await advance(2)
	check(groups[0].order=="move" and int(game.logistics.snapshot().cargo)==int(stock.cargo) and int(escort_state().count)==2,"A manual carrier move retains its true cargo and all escorts follow the same actual target identity")
	camera_at(OPEN); await capture("cycle-manual-target-with-cargo")
	groups=await convoy(["shield"],true); if groups.size()!=2:return
	await stationary_guard(groups)
	await select_group(groups[0])
	var reference_member: BattleUnit=groups[0].members[1]
	precision_shift_carrier(groups[0],.9); step(.001)
	var sampled: Dictionary=escort_row(int(groups[1].id)); var updates: int=int(sampled.station_updates)
	check(float(sampled.refresh_remaining)>.499,"Exact cadence fixture begins immediately after a real reference-displacement refresh with a positive half-second timer")
	precision_shift_carrier(groups[0],.79); step(.499)
	check(is_equal_approx(planar(sampled.reference,reference_member.position),.79),"Cadence precision target truly remains at its new paid guard point0.79m from the sampled reference")
	check(int(escort_row(int(groups[1].id)).station_updates)==updates,"Actual convoy does not refresh before the native half-second cadence")
	step(.0011); check(int(escort_row(int(groups[1].id)).station_updates)==updates,"An expired native cadence does not refresh for a true reference displacement below0.8m")
	precision_shift_carrier(groups[0],.02); step(.001)
	check(is_equal_approx(planar(sampled.reference,reference_member.position),.81),"Expired cadence precision target is truly0.81m from the old sampled reference")
	check(int(escort_row(int(groups[1].id)).station_updates)==updates+1,"After expiry the actual reference displacement beyond0.8m produces exactly one squad station refresh")
	precision_shift_carrier(groups[0],.9); step(.499)
	check(is_equal_approx(planar(escort_row(int(groups[1].id)).reference,reference_member.position),.9),"New-cadence precision target stays at its actual0.9m shifted guard point during the full0.499s window")
	check(int(escort_row(int(groups[1].id)).station_updates)==updates+1,"A second significant reference displacement still waits for the new half-second cadence")
	step(.0011); check(int(escort_row(int(groups[1].id)).station_updates)==updates+2,"The next actual cadence expiry performs one refresh without per-frame path rebuilding")
	(evidence.cycle as Array).append({"case":"native-cadence-and-displacement","initial":sampled,"final":escort_state(),"route_performance":route_performance.duplicate(true)})
	stage_returned=true

func precision_shift_carrier(carrier: Dictionary, distance: float) -> void:
	var point: Vector3=carrier.members[1].position+Vector3(distance,0,0)
	check(precision and bool(game.squads.command_guard(point).ok),"Cadence boundary uses an explicit paid-roster guard point and precision-only direct placement")
	place_group(carrier,point)

func observe_members() -> void:
	for squad: Dictionary in game.squads.squads:
		for member: Variant in squad.members:
			if living(member) and not watched_damage.has(member.get_instance_id()):
				watched_damage[member.get_instance_id()]=true
				member.damage_confirmed.connect(record_hurt); member.defeated.connect(record_death)

func real_combat() -> void:
	var groups: Array[Dictionary]=await convoy(["shield"],true); if groups.size()!=2:return
	await bind_convoy(groups); await advance(3)
	game.start_night(); clear_enemies(); game.phase_time=10000.0; game.wave_index=game.WAVES_PER_NIGHT
	var shield: BattleUnit=groups[1].members[1]; var initial: Vector3=shield.position
	var enemy: BattleUnit=spawn(initial+Vector3(0,0,5)); enemy.speed=3.4; enemy.attack_timer=0.0
	var born: Vector3=enemy.position; observe_members(); var hp: float=shield.hp
	if not await wait_actual(func() -> bool:return shield.hp<hp,12,"Native moving nighttime enemy reaches and truly hurts a stationary convoy shield",false):return
	check(planar(born,enemy.position)>.5 and game.squads.blocker_for(enemy)==shield,"A true enemy approaches through normal movement and the stationed25-armor escort shield genuinely intercepts")
	var found := false
	for hit: Dictionary in hurt_events:
		if int(hit.victim)==shield.get_instance_id() and int(hit.source)==enemy.get_instance_id():found=true; check(is_equal_approx(float(hit.hp),enemy.damage/1.25),"Original shield armor receives native enemy damage with real source attribution")
	check(found and int(game.logistics.snapshot().lost)==0,"Real escort interception produces an actual hurt callback without fabricating cargo loss")
	(evidence.combat as Array).append({"case":"moving-night-enemy-true-interception","birth":born,"enemy_position":enemy.position,"shield":shield.position,"hurt":hurt_events.duplicate(true),"stock":game.logistics.snapshot()})
	await capture("combat-native-shield-interception")
	groups=await convoy([]); if groups.size()!=1:return
	await select_group(groups[0]); await right(game.logistics.fields[0].position)
	if not await wait_actual(func() -> bool:return int(game.logistics.snapshot().cargo)==24,90,"Real cargo before unprotected native casualty"):return
	var carrier: BattleUnit=groups[0].members[1]; var held: Vector3=carrier.position
	await right(held); game.squads.command_guard(held); place_group(groups[0],held)
	enemy=spawn(carrier.position+Vector3(0,0,3)); enemy.speed=3.4; enemy.attack_timer=0.0; observe_members(); var token: int=carrier.get_instance_id()
	if not await wait_actual(func() -> bool:return not living(carrier),90,"Actual native attacks defeat the loaded unprotected carrier",false):return
	check(int(game.logistics.snapshot().lost)>=8 and not game.logistics._cargo.has(token),"Native damage death discards only real cargo owned by the defeated member")
	(evidence.combat as Array).append({"case":"unprotected-native-loaded-death","hurt":hurt_events.duplicate(true),"deaths":death_events.duplicate(true),"stock":game.logistics.snapshot()})
	await capture("combat-native-carrier-loss")
	stage_returned=true

func stationary_guard(groups: Array[Dictionary]) -> BattleUnit:
	await bind_convoy(groups)
	var source: BattleUnit=groups[1].members[1]
	await wait_actual(func() -> bool:return not source.moving and planar(source.position,escort_row(int(groups[1].id)).stations[1])<=.17,35,"Actual paid escort settles at a legal per-member station before native combat")
	return source

func specialized_convoy() -> void:
	for kind: String in ["shield","ranged","engineer","ballista"]:
		var groups: Array[Dictionary]=await convoy([kind],true); if groups.size()!=2:return
		var source: BattleUnit=await stationary_guard(groups)
		var enemy: BattleUnit=spawn(source.position+Vector3(0,0,2)); var hp: float=enemy.hp
		step(.001); check(source.attack_queued and is_equal_approx(source.attack_windup,source.windup_duration),"Stationed "+kind+" begins its complete original legal-range preparation")
		var before: Dictionary=state(); await alt_member(groups[0].members[1]); check(state()==before,"Repeating convoy during "+kind+" preparation preserves pending attack and cooldown")
		await advance(source.windup_duration-.001); check(enemy.hp==hp,"Convoy "+kind+" cannot commit before native windup")
		step(.002); check(enemy.hp<hp,"Convoy "+kind+" commits true original damage through hurt")
		var cooldown: float=source.attack_timer; before=state(); await alt_member(groups[0].members[1]); check(state()==before and source.attack_timer==cooldown,"Repeating same target preserves earned "+kind+" cooldown")
		(evidence.specialists as Array).append({"kind":kind,"damage":hurt_events.duplicate(true),"native_damage":source.damage,"native_windup":source.windup_duration,"native_cooldown":source.attack_interval})
	var groups: Array[Dictionary]=await convoy(["hunter"],true); if groups.size()!=2:return
	var source: BattleUnit=await stationary_guard(groups); var start: Vector3=source.position
	var enemy: BattleUnit=spawn(start+Vector3(0,0,6),"runner"); var hp: float=enemy.hp; step(.001)
	check(bool(hunter_row(source).encounter) and hunter_row(source).anchor==start,"First escort hunter encounter freezes the actual source position as its original8m anchor")
	if not await wait_actual(func() -> bool:return source.attack_queued,4,"Actual hunter chase reaches2.3m range"):return
	await advance(.219); check(enemy.hp==hp,"Escort hunter retains native.22 preparation")
	step(.002); check(is_equal_approx(enemy.hp,hp-30.0),"Escort hunter runner hit retains native30 base damage")
	var anchor: Vector3=hunter_row(source).anchor
	groups[0].members[1].position+=Vector3(1,0,0); groups[0].members[1].position.y=game.outpost_height(groups[0].members[1].position)
	step(.6); check(hunter_row(source).anchor==anchor,"Moving real carrier cannot roll an active hunter encounter anchor")
	enemy.position=anchor+Vector3(0,0,8.01); enemy.position.y=game.outpost_height(enemy.position); step(.001)
	check(not bool(hunter_row(source).encounter),"Escaping beyond the unchanged8m escort hunter anchor releases the real encounter")
	await advance(.5); check(enemy.hp==hp-30.0,"Escort hunter does not recapture an escaped victim by rolling the chase anchor")
	await capture("specialist-hunter-fixed-anchor")
	groups=await convoy(["hunter"],true); if groups.size()!=2:return
	await select_group(groups[0]); game.squads.command_guard(Vector3(-8,5,4.2)); place_group(groups[0],Vector3(-8,5,4.2)); place_group(groups[1],Vector3(-8,5,6))
	source=await stationary_guard(groups); start=source.position; enemy=spawn(start+Vector3(0,0,6),"runner"); step(.001)
	check(bool(hunter_row(source).encounter) and hunter_row(source).anchor==start and int(hunter_row(source).target_token)==enemy.get_instance_id(),"Actual courtyard convoy hunter establishes its original reachable six-metre encounter")
	var far_focus: BattleUnit=spawn(start+Vector3(9,0,0)); game.focus_cooldown=0.0; camera_at(far_focus.position); await mouse(game.camera.unproject_position(far_focus.position)); game.flush_pending_aim(); await press(KEY_C)
	check(game.focus_target==far_focus,"Original C legally marks the real globally reachable target beyond this convoy hunter's frozen anchor")
	step(.001); check(int(hunter_row(source).target_token)==enemy.get_instance_id() and hunter_row(source).anchor==start,"Legal distant C cannot roll or replace the convoy hunter's fixed eight-metre encounter")
	for distance: float in [7.99,8.0,8.01]:
		far_focus.position=start+Vector3(distance,0,0); far_focus.position.y=game.outpost_height(far_focus.position)
		check(game.squads.hunters.legal_target(source,far_focus,start)==(distance<=8.0),"Actual convoy hunter preserves the exact native eight-metre candidate boundary at "+str(distance))
	(evidence.specialists as Array).append({"kind":"hunter-legal-far-c","anchor":start,"candidate":enemy.position,"far_focus":far_focus.position,"hunter":plain(hunter_row(source))})
	groups=await convoy(["artillery"],true); if groups.size()!=2:return
	source=await stationary_guard(groups)
	for distance: float in [5.49,5.5,16.0,16.01]:
		clear_enemies(); step(.001); enemy=spawn(source.position+Vector3(0,0,distance)); step(.001)
		check(source.attack_queued==(distance>=5.5 and distance<=16.0),"Escort mortar keeps its original current-position5.5–16 range at "+str(distance))
	clear_enemies(); step(.001); await select_group(groups[0]); game.squads.command_guard(Vector3(-7,5,4.2)); place_group(groups[0],Vector3(-7,5,4.2)); place_group(groups[1],Vector3(-7,5,6))
	source=await stationary_guard(groups); start=source.position; far_focus=spawn(Vector3(10,5,6)); var too_close: BattleUnit=spawn(start+Vector3(0,0,2))
	game.focus_cooldown=0.0; camera_at(far_focus.position); await mouse(game.camera.unproject_position(far_focus.position)); game.flush_pending_aim(); await press(KEY_C)
	check(game.focus_target==far_focus and planar(start,far_focus.position)>16.0,"Actual C accepts the legal courtyard target beyond the escort mortar's current native range")
	await advance(.4)
	check(source.position==start and not source.moving and not source.attack_queued and far_focus.hp==far_focus.max_hp and too_close.hp==too_close.max_hp,"A distant legal C and too-close enemy cannot induce pursuit or a shot from a settled convoy mortar")
	(evidence.specialists as Array).append({"kind":"mortar-legal-far-c","station":start,"far_focus":far_focus.position,"near":too_close.position,"artillery":plain(game.squads.artillery_snapshot())})
	clear_enemies(); step(.001); await select_group(groups[0]); game.squads.command_guard(OPEN); place_group(groups[0],OPEN); place_group(groups[1],OPEN+Vector3(0,0,1.8)); source=await stationary_guard(groups)
	clear_enemies(); step(.001); enemy=spawn(source.position+Vector3(0,0,10)); hp=enemy.hp; step(.001)
	await advance(.999); step(.002)
	check(int(game.squads.artillery_snapshot().flight)==1,"Real escort mortar launches one committed native shell")
	var cooldown: float=source.attack_timer; await select_group(groups[1]); await right(source.position+Vector3(4,0,0))
	check(escort_row(int(groups[1].id)).is_empty() and source.attack_timer==cooldown,"Manual mortar movement unbinds escort while preserving the launched shell and cooldown")
	await advance(.801); check(is_equal_approx(enemy.hp,hp-32.0) and int(game.squads.artillery_snapshot().impacts)==1,"Already fired escort shell survives manual overwrite and impacts exactly once for32")
	await capture("specialist-committed-mortar")
	groups=await convoy(["ranged"],true); if groups.size()!=2:return
	await select_group(groups[0]); game.squads.command_guard(Vector3(10,5,10.2)); place_group(groups[0],Vector3(10,5,10.2)); place_group(groups[1],Vector3(10,5,12))
	source=await stationary_guard(groups); enemy=spawn(Vector3(10,0,17)); hp=enemy.hp
	check(not game.can_attack_line(source.position,enemy.position),"The genuine castle wall blocks the otherwise nearby convoy ranged candidate")
	await advance(.4); check(not source.attack_queued and enemy.hp==hp,"Convoy ordinary ranged cannot attack through the actual wall")
	clear_enemies(); await select_group(groups[0]); game.squads.command_guard(OPEN); place_group(groups[0],OPEN); place_group(groups[1],OPEN+Vector3(0,0,1.8)); source=await stationary_guard(groups)
	enemy=spawn(source.position+Vector3(0,0,2)); game.enemies.erase(enemy); await advance(.4)
	check(not source.attack_queued and enemy.hp==enemy.max_hp,"Convoy scans reject a detached real enemy that is absent from the authoritative hostile roster")
	enemy.queue_free(); await process_frame
	medical_returned=false
	await medical_engineer()
	check(medical_returned,"Medical and engineering native substage reaches its explicit completion marker")
	stage_returned=true

func medical_engineer() -> void:
	var groups: Array[Dictionary]=await convoy(["medic"],true); if groups.size()!=2:return
	var medic: BattleUnit=await stationary_guard(groups); var carrier: BattleUnit=groups[0].members[1]
	carrier.hurt(100.0,null); var hp: float=carrier.hp; var parts: int=game.scrap
	await advance(5); check(not bool(groups[1].therapy_enabled) and carrier.hp==hp and game.scrap==parts,"Convoy never automatically enables medical therapy or grants free healing")
	await select_group(groups[1]); await open_army(1); await click_ui(game.hud.MEDIC_BUTTON_RECT); await close_drawer()
	step(.001); check(bool(groups[1].therapy_enabled),"Actual F3 keeps the original explicit paid-treatment switch")
	if not await wait_actual(func() -> bool:return int(game.squads.medic_snapshot().treatments)>0,8,"Native stationary escort medical treatment"):return
	check(game.scrap==parts-2*int(game.squads.medic_snapshot().treatments) and carrier.hp>hp,"Convoy medical healing pays exactly2 per actual restoration from the sole wallet")
	(evidence.specialists as Array).append({"kind":"medic","medical":plain(game.squads.medic_snapshot()),"native_speed":medic.speed})
	await capture("specialist-paid-medical")
	groups=await convoy(["engineer"],true); if groups.size()!=2:return
	await select_group(groups[0]); game.squads.command_guard(Vector3(7,5,6)); place_group(groups[0],Vector3(7,5,6))
	var engineer: BattleUnit=await stationary_guard(groups)
	var pad: Dictionary=game.world.tower_pads[0]; game.damage_tower(0,60.0); hp=float(pad.hp); parts=game.scrap
	if not await wait_actual(func() -> bool:return float(pad.hp)>hp,5,"Native escort engineer reaches actual damaged tower maintenance"):return
	check(game.scrap<parts and float(pad.hp)<=float(pad.max_hp),"Escort engineering uses real paid repair without overfilling tower HP")
	(evidence.specialists as Array).append({"kind":"engineer","restored":float(pad.hp)-hp,"spent":parts-game.scrap,"position":engineer.position})
	medical_returned=true

func physical_paths() -> void:
	var groups: Array[Dictionary]=await convoy(["shield","ballista","artillery"]); if groups.size()!=4:return
	await select_group(groups[0]); game.squads.command_guard(OPEN); place_group(groups[0],OPEN)
	for index in range(1,groups.size()):place_group(groups[index],HOME+Vector3((index-2)*2,0,0))
	place_group(groups[1],Vector3(-7,5,3.5))
	await bind_convoy(groups); crossings.clear(); step(.1)
	var moving_guard: BattleUnit=groups[1].members[1]
	check(moving_guard.moving and not moving_guard.path.is_empty() and moving_guard.path_timer>0.0,"Actual escort follows a nonempty wall-constrained south-gate path with a positive native route clock")
	var moving_state: Dictionary=state(); await alt_member(groups[0].members[1])
	check(state()==moving_state,"Repeated convoy target preserves the actual nonempty south-gate path, route clock and preparation")
	(evidence.path as Array).append({"case":"positive-native-route","position":moving_guard.position,"path":moving_guard.path.duplicate(),"path_timer":moving_guard.path_timer})
	for index in game.world.tower_pads.size():
		if int(game.world.tower_pads[index].level)>0:game.damage_tower(index,float(game.world.tower_pads[index].hp))
	for x: float in [-11.0,11.0]:check(game.build_structure_at(Vector3(x,5,7.5),"barracks"),"Actual paid district seals the side of the dynamic barrier")
	var gap := -1
	for x: float in [-7.5,-4.5,-1.5,1.5,4.5,7.5]:
		check(game.build_tower_at(Vector3(x,5,7.5)),"Actual paid tower seals the complete dynamic barrier")
		if x==1.5:gap=game.world.tower_pads.size()-1
	await advance(5); check(int(escort_state().count)==3 and crossings.is_empty(),"Post-command complete building barrier preserves all target identities without crossing or teleporting")
	await capture("path-real-barrier-wait")
	check(gap>=0,"Dynamic path fixture records the real gap building identity")
	if gap<0:return
	var point: Vector3=game.world.tower_pads[gap].position
	await press(KEY_Y); await press(KEY_DELETE); camera_at(point); await mouse(game.camera.unproject_position(point)); game.flush_pending_aim(); game._process(0)
	check(game.construction.sell_mode and bool(game.construction.snapshot().valid),"Actual demolition toolbar has a valid current gap quote")
	await press(KEY_F); await press(KEY_ESCAPE)
	check(bool(game.world.tower_pads[gap].removed),"Actual paid-building demolition releases the true navigation gap")
	var reopened: float=convoy_time
	if not await wait_actual(func() -> bool:
		for index in range(1,groups.size()):
			for member: Variant in groups[index].members:
				if living(member) and member.position.z<Layout.WALL_CENTER:return false
		return true,70,"Retained escorts recover through the real demolition gap"):return
	for index in range(1,groups.size()):
		for member: Variant in groups[index].members:
			if living(member):check(int(crossings.get(member.get_instance_id(),{}).get("out",0))>=1,"Every real slow and ordinary escort walks through the reopened south route")
	check(is_equal_approx(groups[2].members[1].speed,3.06) and is_equal_approx(groups[3].members[1].speed,2.4),"Slow ballista and mortar keep native speeds while following instead of convoy acceleration")
	var actual_lag: Array[Dictionary]=[]
	for index in range(1,groups.size()):
		var last_gate := reopened
		for member: Variant in groups[index].members:
			if living(member):last_gate=maxf(last_gate,float(crossings.get(member.get_instance_id(),{}).get("last_out",reopened)))
		actual_lag.append({"kind":groups[index].kind,"native_speed":groups[index].members[1].speed,"last_member_gate_seconds_after_reopen":last_gate-reopened,"current_reference_distance":planar(groups[index].members[1].position,groups[0].members[1].position)})
	(evidence.path as Array).append({"gap":gap,"crossings":crossings.duplicate(true),"escort":escort_state(),"actual_slow_member_lag":actual_lag,"ballista_speed":groups[2].members[1].speed,"mortar_speed":groups[3].members[1].speed,"route_performance":route_performance.duplicate(true),"movement_route_max_usec":game.get("convoy_movement_route_max_usec")})
	await capture("path-real-demolition-recovery")
	stage_returned=true

func frozen_lifecycle() -> void:
	var groups: Array[Dictionary]=await convoy(["shield"],true); if groups.size()!=2:return
	var source: BattleUnit=await stationary_guard(groups); var target: BattleUnit=groups[0].members[1]
	var enemy: BattleUnit=spawn(source.position+Vector3(0,0,2)); step(.001); check(source.attack_queued,"Lifecycle begins with genuine native escort preparation")
	await press(KEY_F1); var frozen: Dictionary=state(); var rejection: Dictionary=game.squads.command_escort(target); await alt_member(target); game.simulate(5)
	check(game.phase=="paused" and game.music_credits_open and not bool(rejection.ok) and state()==frozen,"Sources and actual pause freeze and reject escort without consuming pending attacks, stock, clocks or RNG")
	await capture("lifecycle-paused-sources"); await press(KEY_ESCAPE); await press(KEY_ESCAPE)
	await press(KEY_V); frozen=state(); rejection=game.squads.command_escort(target); await alt_member(target); game.simulate(5)
	check(game.phase=="draft" and not bool(rejection.ok) and state()==frozen,"Paid card choice freezes and rejects real convoy API and Alt input")
	await press(KEY_1); var cooldown: float=source.attack_timer; game.start_night(); clear_enemies(); game.phase_time=10000.0; game.wave_index=game.WAVES_PER_NIGHT
	check(int(escort_state().count)==1 and source.attack_timer==cooldown and not source.attack_queued,"Sunset retains the actual binding and native cooldown while clearing the old encounter preparation")
	TransitionFixture.finish_for_fixture(game); await press(KEY_1); clear_enemies(); game.phase_time=10000.0
	check(int(escort_state().count)==1,"Actual next dawn preserves the living convoy identity")
	var reference: Dictionary=escort_row(int(groups[1].id)); check(int(reference.target_member_slot)==1,"Original actual carrier slot1 is the stable reference")
	target.hurt(100000.0,null)
	check(int(escort_row(int(groups[1].id)).target_member_slot)==0,"True reference death synchronously selects the first living slot0")
	await select_group(groups[0]); var parts: int=game.scrap; await press(KEY_L)
	check(living(groups[0].members[1]) and game.scrap<parts and int(escort_row(int(groups[1].id)).target_member_slot)==0,"Actual paid target refill does not replace the still-valid slot0 reference")
	check(living(groups[1].members[0]) and living(groups[1].members[1]) and living(groups[1].members[2]),"Original global L refill also genuinely pays to restore the two precision casualty guard slots")
	var guard_positions: Array[Vector3]=[]
	for member: Variant in groups[1].members:
		guard_positions.append(member.position if living(member) else Vector3.INF)
	var late_refill: Dictionary={"calls":0}
	var final_target: BattleUnit=groups[0].members[2]
	final_target.defeated.connect(refill_after_final_death.bind(groups[0],groups[1],guard_positions,late_refill))
	var casualty_members: Array=groups[0].members.duplicate()
	for member: Variant in casualty_members:
		if living(member):member.hurt(100000.0,null)
	check(int(escort_state().count)==0 and groups[1].order=="guard","Final target death synchronously unbinds escort and commits per-member current-position guard before another simulation")
	for slot in groups[1].members.size():
		if living(groups[1].members[slot]):check(groups[1].members[slot].position==guard_positions[slot],"Target final death cannot move any living escort")
	check(int(late_refill.calls)==1 and bool(late_refill.refill.ok) and int(late_refill.after_parts)<int(late_refill.before_parts),"A later callback in the same true defeated signal pays for fresh real target members after immediate convoy guard commitment")
	check(int(escort_state().count)==0 and groups[1].order=="guard" and living(groups[0].members[1]),"Same-signal paid target refill cannot resurrect the retired convoy binding")
	(evidence.lifecycle as Array).append({"case":"same-defeated-signal-paid-refill","callback":late_refill.duplicate(true),"guard_stations":groups[1].rally_stations.duplicate()})
	await capture("lifecycle-dead-target-guard")
	for order: String in ["move","attack","guard","attack_move"]:
		groups=await convoy(["shield"],true); if groups.size()!=2:return
		source=await stationary_guard(groups)
		clear_enemies(); enemy=spawn(source.position+Vector3(0,0,2)); var native_hp: float=enemy.hp
		if not await wait_actual(func() -> bool:return enemy.hp<native_hp,8,"Manual-order fixture earns native damage and a genuine positive cooldown"):return
		cooldown=source.attack_timer; check(cooldown>0.0,"Actual escort hurt commits its earned native cooldown before manual overwrite")
		match order:
			"move":await right(OPEN+Vector3(5,0,0))
			"attack":await right(enemy.position)
			"guard":game.aim=source.position; await press(KEY_O)
			"attack_move":await right(OPEN+Vector3(0,0,10),true)
		check(groups[1].order==order and int(escort_state().count)==0 and source.attack_timer==cooldown and not source.attack_queued,"Actual manual "+order+" unbinds convoy and cancels preparation while retaining native cooldown")
		clear_enemies()
	var old_target: BattleUnit=groups[0].members[1]; var old_dictionary: Dictionary=groups[0]; var old_token: int=old_target.get_instance_id()
	game.squads.setup(game,true)
	check(int(escort_state().count)==0 and game.squads.squads.is_empty(),"Actual roster setup clears original Dictionary identities")
	var new_target: Dictionary=await train("hauler"); var new_guard: Dictionary=await train("shield")
	if new_target.is_empty() or new_guard.is_empty():return
	check(int(new_target.id)==int(old_dictionary.id) and not is_same(new_target,old_dictionary) and not is_instance_id_valid(old_token),"Real paid retraining reuses the numeric squad ID with a fresh Dictionary and releases the old actor")
	await select_group(new_guard); frozen=state(); rejection=game.squads.command_escort(instance_from_id(old_token))
	check(not bool(rejection.ok) and state()==frozen and int(escort_state().count)==0,"New same-number target cannot inherit or authorize an old released target actor")
	rejection=game.squads.escort.command_selected(old_dictionary)
	check(not bool(rejection.ok) and state()==frozen,"Actual binding module rejects the old target Dictionary despite the matching newly paid numeric ID")
	for mode: String in ["clear","setup","defeat","victory"]:
		groups=await convoy(["shield"]); if groups.size()!=2:return
		await bind_convoy(groups); await advance(4); source=groups[1].members[1]
		enemy=spawn(source.position+Vector3(0,0,1)); var hook: Dictionary={"count":0}; enemy.damage_confirmed.connect(reenter.bind(mode,hook))
		step(.001); hurt_events.clear(); step(.181)
		check(int(hook.count)==1 and hurt_events.size()==1 and game.squads.squads.is_empty() and int(escort_state().count)==0,"Synchronous actual hurt "+mode+" cancels all remaining old-generation escort actions")
		(evidence.lifecycle as Array).append({"mode":mode,"hurt":hurt_events.duplicate(true),"phase":game.phase,"escort":escort_state()})
	groups=await convoy(["shield"]); if groups.size()!=2:return
	await bind_convoy(groups); var old_root: int=game.get_instance_id(); game.end_defeat("Explicit genuine convoy retry boundary")
	await press(KEY_ENTER)
	for _frame in 240:
		if current_scene!=null and current_scene.get_instance_id()!=old_root:break
		await create_timer(.02,true,false,true).timeout
	check(current_scene!=null and current_scene.get_instance_id()!=old_root,"Actual Enter creates a new same-seed root")
	if current_scene==null or current_scene.get_instance_id()==old_root:return
	game=current_scene as Node3D; game.set_process(false); game.world.set_process(false)
	for _frame in 5:await process_frame
	check(not is_instance_id_valid(old_root) and game.run.seed_value==SEED and game.phase=="draft" and game.scrap==90 and game.squads.squads.is_empty() and int(escort_state().count)==0,"True same-seed reload releases old actors, targets and all convoy identities")
	stage_returned=true

func refill_after_final_death(_victim: BattleUnit, _source: BattleUnit, target: Dictionary, guard: Dictionary, stations: Array[Vector3], hook: Dictionary) -> void:
	hook.calls=int(hook.calls)+1
	check(int(escort_state().count)==0 and guard.order=="guard" and guard.rally_stations==stations,"Later real defeated callback observes every current-position guard already committed before any paid refill")
	hook.before_parts=game.scrap; hook.guard_order=guard.order; hook.guard_stations=guard.rally_stations.duplicate()
	hook.refill=game.squads.refill(int(target.id)); hook.after_parts=game.scrap
	var tokens: Array[int]=[]
	for member: Variant in target.members:
		if living(member):tokens.append(member.get_instance_id())
	hook.new_members=tokens

func measure_convoy_hud(tag: String, help: bool=false) -> void:
	var before: Dictionary=state(); var previous_viewport: Vector2i=root.size
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport; await redraw()
		var escort_seen := false; var help_bottom := 0.0
		for row: Dictionary in game.hud.drawn_labels:
			check(row.point.x>=0 and row.point.x+float(row.width)<=1440 and row.point.y-float(row.ascent)>=0 and row.point.y+float(row.descent)<=900,"Every actual convoy glyph rectangle fits the logical viewport")
			for character: String in String(row.text):
				var code: int=character.unicode_at(0)
				if code>=0x4e00 and code<=0x9fff:check(game.hud.font.has_char(code),"Actual font contains convoy Chinese glyph "+character)
			if String(row.text).contains("Alt+") and String(row.text).contains("护航"):
				escort_seen=true; check(float(row.width)<=496,"Actual complete Alt convoy instruction fits the original F3 column")
			if row.point in [Vector2(38,783),Vector2(38,808)]:check(float(row.width)<=272,"Actual convoy selection title/hint fits the existing272px short strip")
			if help and row.point.x==46 and row.point.y>=230:help_bottom=maxf(help_bottom,float(row.point.y)+float(row.descent))
		check(game.hud.detail_tab not in ["army","help"] or escort_seen,"Actual army/help drawer contains the complete Alt convoy instruction")
		check(not help or help_bottom<=660.01,"Actual final help glyph preserves the existing660px bound and32px close-button gap")
		(evidence.hud as Array).append({"tag":tag,"viewport":viewport,"escort_instruction":escort_seen,"help_bottom":help_bottom})
	check(state()==before,"Three-viewport actual HUD reads cannot change convoy state, movement, cargo, clocks or wallet")
	root.size=previous_viewport; root.content_scale_size=previous_viewport; await redraw()

func actual_hud() -> void:
	var groups: Array[Dictionary]=await convoy(["shield"]); if groups.size()!=2:return
	await select_group(groups[1]); clear_transients(); await redraw(); var ordinary: Array=game.hud.drawn_rects.duplicate()
	await bind_convoy(groups); clear_transients(); await redraw()
	check(game.hud.drawn_rects==ordinary and SELECTED_RECT in game.hud.drawn_rects,"Actual convoy selection uses exactly the existing strip without adding any permanent rectangle")
	await measure_convoy_hud("selected-convoy"); camera_at(OPEN); await capture("hud-selected-convoy")
	var before: Dictionary=state(); await alt_mouse(SELECTED_RECT.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900))
	check(state()==before,"Actual visible short strip consumes Alt mouse without reissuing world orders")
	await open_army(); await measure_convoy_hud("army-convoy"); await capture("hud-army-convoy")
	await click_ui(game.hud.details_tab_rect(4)); await measure_convoy_hud("help-convoy",true); await capture("hud-help-convoy")
	await close_drawer(); game.squads.cancel_selection(); clear_transients(); await redraw()
	check(not (SELECTED_RECT in game.hud.drawn_rects),"Unselected default world does not retain any convoy rectangle")
	await capture("hud-default-clean-day")
	stage_returned=true

func natural_walk(point: Vector3, seconds: float=35.0) -> bool:
	await right(point)
	for frame in ceili(seconds/STEP):
		if game.hero.position.distance_to(point)<2.1:return true
		if game.phase!="day":break
		natural_tick()
		if frame%100==99:await process_frame
	check(false,"Original unextended natural hero route reaches the genuine exploration source before sunset")
	return false

func natural_economy() -> void:
	for protected: bool in [false,true]:
		await fresh(false); crossings.clear(); watched_damage.clear(); income_book.clear(); convoy_time=0.0
		await right(Vector3(0,5,10))
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
		check(game.phase=="draft" and game.hero.alive and game.beacon_hp>0,"Original natural first night reaches dawn under the unchanged fixed skill policy")
		if game.phase!="draft":return
		var first_deaths: int=game.kills; var dawn_parts: int=game.scrap; await press(KEY_1)
		check(game.phase_time==90.0 and game.scrap==dawn_parts,"Actual natural dawn preserves original90-second day and genuinely earned parts")
		for _source in 8:
			if game.scrap>=360:break
			var nearest: Dictionary={}; var best := INF
			for source: Dictionary in game.world.salvage:
				if bool(source.collected):continue
				var distance: float=game.contracts.route_distance(game.hero.position,source.position)
				if distance<best:nearest=source; best=distance
			check(not nearest.is_empty(),"Natural convoy funding uses an actual available world crate")
			if nearest.is_empty() or not await natural_walk(nearest.position):return
			check(game.nearest_salvage()==game.world.salvage.find(nearest),"Natural F input has the selected genuine crate within the original three-dimensional interaction range")
			var parts: int=game.scrap; var counter: int=game.exploration_count; await press(KEY_F)
			check(bool(nearest.collected) and game.scrap>parts,"Actual natural F grants the genuine crate income without fixture funding")
			if not bool(nearest.collected) or game.scrap<=parts:return
			income_book.append({"kind":"real-world-salvage","position":nearest.position,"gain":game.scrap-parts,"before":parts,"after":game.scrap,"exploration_before":counter,"exploration_after":game.exploration_count,"day":game.day_number,"day_second":90.0-game.phase_time})
		check(game.scrap>=360,"Genuine additional exploration funds all360 parts of the unchanged convoy setup")
		if game.scrap<360:return
		if not await natural_walk(HOME):return
		var payments: Array[Dictionary]=[]
		for row: Dictionary in [{"kind":"barracks","position":BARRACKS},{"kind":"workshop","position":WORKSHOP},{"kind":"depot","position":DEPOT}]:
			var parts: int=game.scrap; await build_gui(String(row.kind),row.position)
			payments.append({"kind":row.kind,"cost":parts-game.scrap,"day":game.day_number,"day_second":90.0-game.phase_time})
		var parts: int=game.scrap; var carrier: Dictionary=await train("hauler"); payments.append({"kind":"hauler","cost":parts-game.scrap,"day":game.day_number,"day_second":90.0-game.phase_time})
		parts=game.scrap; var shield: Dictionary=await train("shield"); payments.append({"kind":"shield","cost":parts-game.scrap,"day":game.day_number,"day_second":90.0-game.phase_time})
		if carrier.is_empty() or shield.is_empty():return
		observe_members(); await select_group(carrier); await right(game.logistics.fields[0].position)
		if protected:await select_group(shield); await alt_member(carrier.members[1])
		natural_monitor=true; var departure_kills: int=game.kills
		var sent_at: float=90.0-game.phase_time; var after_payments: int=game.scrap; var first_delivery := -1.0; var sunset: Dictionary={}; var stages: Array[Dictionary]=[]
		for frame in 4300:
			if int(game.logistics.snapshot().delivered)>=48 or game.phase=="ended":break
			if game.phase=="draft":await press(KEY_1); stages.append({"phase":"actual-dawn-card","day":game.day_number,"parts":game.scrap,"time":game.phase_time})
			if game.phase=="day" and game.phase_time<=STEP and sunset.is_empty():sunset={"day":game.day_number,"parts":game.scrap,"stock":game.logistics.snapshot(),"escort":escort_state()}
			natural_tick()
			if first_delivery<0 and int(game.logistics.snapshot().delivered)>0:first_delivery=convoy_time
			if frame%100==99:await process_frame
		var stock: Dictionary=game.logistics.snapshot()
		check(int(stock.delivered)>=48,"Original natural phases produce at least two real finite deliveries without extending daylight or adding money")
		var carrier_out := 0; var carrier_in := 0
		for row: Dictionary in crossings.values():
			if int(row.squad_id)==int(carrier.id):carrier_out+=int(row.out); carrier_in+=int(row.in)
		check(carrier_out>=6 and carrier_in>=6,"Natural two-trip proof records all three actual carriers passing both directions of the genuine south gate twice")
		var total_payment := 0
		for row: Dictionary in payments:total_payment+=int(row.cost)
		check(total_payment==360,"Natural convoy funding records exactly original60+60+100+70+70 prices")
		(evidence.economy as Array).append({"protected":protected,"seed":SEED,"opening":90,"night_seconds":105,"day_seconds":90,"first_night_deaths":first_deaths,"dawn_parts":dawn_parts,"genuine_extra_income":income_book.duplicate(true),"payments":payments,"total_payments":total_payment,"after_payments":after_payments,"sent_at_day_second":sent_at,"first_delivery_simulated_second":first_delivery,"two_deliveries_actual_day_second":90.0-game.phase_time,"sunset":sunset,"subsequent_actual_phases":stages,"final_stock":stock,"final_parts":game.scrap,"departure_kills":departure_kills,"final_kills":game.kills,"wallet_changes_after_departure":natural_wallet_changes.duplicate(true),"crossings":crossings.duplicate(true),"damage":hurt_events.duplicate(true),"deaths":death_events.duplicate(true),"hero_hp":game.hero.hp,"beacon_hp":game.beacon_hp,"phase":game.phase,"day":game.day_number,"escort":escort_state(),"route_performance":route_performance.duplicate(true),"movement_route_max_usec":game.get("convoy_movement_route_max_usec"),"scope":"fixed-seed scripted route only; no fixture funding, actor/source placement, time extension, enemy removal/stat changes or full-human-balance claim; actual member damage and cargo loss are recorded independently of outgoing combat and non-logistics income"})
		camera_at(DEPOT); await capture("natural-two-trips-"+("escort" if protected else "baseline"))
	if (evidence.economy as Array).size()==2:
		var baseline: Dictionary=evidence.economy[0]; var protected: Dictionary=evidence.economy[1]
		check(baseline.dawn_parts==protected.dawn_parts and baseline.genuine_extra_income==protected.genuine_extra_income and baseline.payments==protected.payments and baseline.sent_at_day_second==protected.sent_at_day_second,"Natural same-seed paired routes have identical genuine funding, purchases and departure time")
	stage_returned=true

func capture(tag: String) -> void:
	var before: int=(evidence.captures as Array).size()
	await super.capture(tag)
	for index in range(before,(evidence.captures as Array).size()):
		var name: String=String(evidence.captures[index]); var path: String=ProjectSettings.globalize_path(output_dir).path_join(name+".png")
		(evidence.capture_receipt as Array).append({"name":name,"path":path,"sha256":FileAccess.get_sha256(path),"stage":active_stage})

func finalize() -> void:
	await close_game(); await create_timer(.5,true,false,true).timeout
	evidence.shutdown_audio_drain_seconds=.5
	var folder: String=ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
	var file: FileAccess=FileAccess.open(folder.path_join("nightfall-convoy-escort.json"),FileAccess.WRITE)
	check(file!=null,"Structured independent eight-stage convoy evidence opens below local build")
	var receipt: FileAccess=FileAccess.open(folder.path_join("capture-receipt.json"),FileAccess.WRITE)
	check(receipt!=null,"Capture manifest receipt opens below local build")
	evidence.checks=checks; evidence.failures=failures
	if file!=null:file.store_string(JSON.stringify(evidence,"\t")); file.close()
	if receipt!=null:receipt.store_string(JSON.stringify({"captures":evidence.capture_receipt,"completed":evidence.completed,"checks":checks,"failures":failures},"\t")); receipt.close()

func run() -> void:
	var cases: Dictionary={"input":physical_input,"cycle":repeated_cycle,"combat":real_combat,"specialists":specialized_convoy,"path":physical_paths,"lifecycle":frozen_lifecycle,"hud":actual_hud,"economy":natural_economy}
	var args: PackedStringArray=OS.get_cmdline_user_args(); var selected: Array=cases.keys(); var index: int=args.find("--case")
	if index>=0 and index+1<args.size():selected=[args[index+1]]
	for name: String in selected:
		if not cases.has(name):check(false,"Unknown independent convoy stage "+name); break
		active_stage=name; stage_returned=false; print("CONVOY_STAGE_BEGIN ",name)
		await (cases[name] as Callable).call()
		check(stage_returned,"Convoy stage "+name+" reaches its explicit full-body completion marker")
		print("CONVOY_STAGE_END ",name," checks=",checks," failures=",failures.size())
		(evidence.completed as Array).append(name)
		if not failures.is_empty():break
	await finalize(); finished=true
	print("CONVOY_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
