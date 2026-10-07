extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
## Independent production-scene acceptance. Precision sections use 5000 parts,
## extended clocks, direct hero placement and removed unrelated enemies. They
## never fabricate a positive exploration counter. Economy keeps the original
## 90/105/90 clocks, wallet, actors and combat stats, and walks the real route.
## Captures use controlled lighting; neither section proves human balance.

const RunSession := preload("res://scripts/run_session.gd")
const DrawScript := preload("res://scripts/salvage_draw.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
const SEED := 20261006
const STEP := .1
const HOME := Vector3(0,5,4.5)
const VIEWPORTS := [Vector2i(1920,1200),Vector2i(1920,1080),Vector2i(1440,900)]
const DRAWER := Rect2(24,112,540,622)
const NAV := Rect2(46,692,190,30)
const DRAW_BUTTON := Rect2(46,418,496,38)
const CLOSE := Rect2(428,692,112,30)
const OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var drawn_boxes: Array[Rect2] = []
var drawn_labels: Array[Dictionary] = []
var drawer_labels: Array[Dictionary] = []
var recording_drawer := false
func _draw() -> void:
\tdrawn_boxes.clear(); drawn_labels.clear(); drawer_labels.clear(); recording_drawer=false
\tsuper._draw()
func box(rect: Rect2, fill: Color=Color(.022,.035,.045,.88), outline: Color=Color('435455')) -> void:
\tdrawn_boxes.append(rect)
\tif rect==Rect2(24,112,540,622):recording_drawer=true
\tif rect==Rect2(428,692,112,30):recording_drawer=false
\tsuper.box(rect,fill,outline)
func label(value: String, point: Vector2, size_px: int, color: Color=Color('e7e1d3'), latin: bool=false) -> void:
\tvar actual: Font=display_font if latin else font
\tvar row: Dictionary={'text':value,'point':point,'size':size_px,'width':actual.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x,'ascent':actual.get_ascent(size_px),'descent':actual.get_descent(size_px)}
\tdrawn_labels.append(row)
\tif recording_drawer:drawer_labels.append(row)
\tsuper.label(value,point,size_px,color,latin)
"""

var game: Node3D
var checks := 0
var failures: Array[String] = []
var render_test := false
var output_dir := "res://build/salvage-draw"
var active_stage := "initialization"
var finished := false
var evidence: Dictionary = {}
var elapsed := 0.0
var natural_gate_crossings: Array[Dictionary] = []

func _initialize() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	render_test="--render-test" in args
	var index: int=args.find("--output-dir")
	if index>=0 and index+1<args.size():
		var candidate: String=ProjectSettings.globalize_path(args[index+1]).simplify_path()
		var allowed: String=ProjectSettings.globalize_path("res://build").simplify_path()
		if candidate.begins_with(allowed+"/"):output_dir=candidate
		else:check(false,"Salvage-draw evidence must remain below the local build directory")
	root.size=VIEWPORTS[0]; root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT; root.content_scale_size=VIEWPORTS[0]
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.position=Vector2i(10000,10000); root.hide()
	evidence={"seed":SEED,"scope":"precision5000/extended clocks/direct hero placement/removal of unrelated enemies; real F sources, no positive exploration-counter assignment; economy original90 wallet/105 night/90 day/native actors and real walking; controlled capture lighting; no human or campaign balance claim","completed":[],"captures":[],"unlock":[],"input":[],"ledger":[],"boundary":[],"lifecycle":[],"hud":[],"economy":[]}
	create_timer(600.0,true,false,true).timeout.connect(watchdog)
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks+=1
	if condition:return
	failures.append(message)
	if failures.size()<=30:push_error(message)

func watchdog() -> void:
	if finished:return
	check(false,"Salvage-draw acceptance stalled in "+active_stage)
	await close_game(); finished=true; quit(1)

func planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))

func draw_snapshot() -> Dictionary:
	return game.salvage_draw_snapshot()

func periphery() -> Dictionary:
	return {"phase":game.phase,"day":game.day_number,"time":game.phase_time,
		"combat_rng":game.rng.state,"card_rng":game.run.rng.state,"spawn_rng":game.spawn_rng.state,
		"discovery_rng":game.discoveries.rng.state,"wildlife_rng":game.wildlife.rng.state,
		"plan":game.night_plan.duplicate(true),"cards":game.run.owned.duplicate(true),"offer":game.run.offer.duplicate(true),
		"pending":game.run.pending,"memory_level":game.run.memory_level,"kills":game.kills,
		"count":game.exploration_count,"milestones":game.exploration_milestones,
		"run_discoveries":game.exploration.run_discoveries,"day_discoveries":game.exploration.day_discoveries,
		"route_day":game.exploration.route_day,"route":game.exploration.route_order.duplicate(),
		"streak":game.exploration.streak,"streak_time":game.exploration.streak_time,
		"speed_time":game.exploration.speed_time,"affinity_time":game.exploration.affinity_time,
		"goal":game.move_goal,"path":game.hero_path.duplicate(),"hero_position":game.hero.position,
		"hero_hp":game.hero.hp,"hero_alive":game.hero.alive,"mana":game.mana,"beacon_hp":game.beacon_hp,
		"selection":game.squads.selected_ids.duplicate(),"dragging":game.selection_dragging,
		"queues":game.squads.training_queues.duplicate(true),"quitting":game.quitting,"restart_pending":game.restart_pending}

func state() -> Dictionary:
	return {"parts":game.scrap,"draw":draw_snapshot(),"periphery":periphery()}

func press(code: int) -> void:
	var event: InputEventKey=InputEventKey.new()
	event.keycode=code; event.physical_keycode=code; event.pressed=true
	root.push_input(event,true); event.pressed=false; root.push_input(event,true)
	await process_frame

func mouse(point: Vector2, button: int=MOUSE_BUTTON_LEFT) -> void:
	var motion: InputEventMouseMotion=InputEventMouseMotion.new()
	motion.position=point; motion.global_position=point
	root.push_input(motion,true); await process_frame
	var event: InputEventMouseButton=InputEventMouseButton.new()
	event.position=point; event.global_position=point; event.button_index=button
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if button==MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	event.pressed=true; root.push_input(event,true); await process_frame
	event.pressed=false; event.button_mask=0; root.push_input(event,true); await process_frame

func click_ui(rect: Rect2, button: int=MOUSE_BUTTON_LEFT) -> void:
	await mouse(rect.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900),button)

func release_ui(rect: Rect2) -> void:
	var event: InputEventMouseButton=InputEventMouseButton.new()
	event.position=rect.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900)
	event.global_position=event.position; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=false
	root.push_input(event,true); await process_frame

func redraw() -> void:
	game.hud.queue_redraw()
	for _frame in 3:await process_frame

func install_observer() -> void:
	var script: GDScript=GDScript.new(); script.source_code=OBSERVER
	check(script.reload()==OK,"Read-only recorder compiles and forwards the real HUD/input")
	var original: Control=game.hud; var layer: Node=original.get_parent()
	layer.remove_child(original); original.queue_free()
	var observed: Control=script.new(); observed.game=game; game.hud=observed; layer.add_child(observed)
	observed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await redraw()

func camera_at(point: Vector3) -> void:
	game.camera.size=38.0; game.camera.position=point+Vector3(0,25,29)
	game.camera.look_at(point); game.camera_follow=game.camera.position

func stand(point: Vector3) -> void:
	point.y=game.outpost_height(point); game.hero.position=point; game.move_goal=point
	game.hero_path.clear(); game.hero_keyboard_active=false; game.hero.moving=false
	game.hero.set_locomotion_velocity(Vector3.ZERO)

func close_drawer() -> void:
	if not game.hud.detail_tab.is_empty():await press(KEY_F3)

func open_exploration(subpage: bool=false) -> void:
	if game.hud.detail_tab.is_empty():await press(KEY_F3)
	if game.hud.detail_tab!="exploration":await click_ui(game.hud.details_tab_rect(1))
	if bool(game.hud.salvage_draw_open)!=subpage:await click_ui(NAV)
	await redraw()
	check(game.hud.detail_tab=="exploration" and bool(game.hud.salvage_draw_open)==subpage,"Actual F3/tab/footer selects the intended exploration page")

func right(point: Vector3) -> Vector3:
	await close_drawer(); camera_at(point)
	var screen: Vector2=game.camera.unproject_position(point)
	var ground: Vector3=game.ground_point(screen)
	await mouse(screen,MOUSE_BUTTON_RIGHT)
	check(ground.is_finite(),"Real right-click has a finite sampled ground target")
	return ground

func clear_enemies() -> void:
	game.clear_lobbers(); game.clear_summoners(); game.clear_warders(); game.clear_focus(); game.cancel_hero_attack()
	for value: Variant in game.enemies:
		if is_instance_valid(value) and not value.is_queued_for_deletion():value.queue_free()
	game.enemies.clear()

func close_game() -> void:
	if not is_instance_valid(game):return
	var token: int=game.get_instance_id()
	var retired: RefCounted=game.salvage_draw
	await game.prepare_shutdown()
	var before: int=game.scrap
	check(not bool(retired.snapshot().available) and not bool(retired.draw().ok) and game.scrap==before,"Actual shutdown retires the old draw without paying its wallet")
	if current_scene==game:current_scene=null
	game.queue_free(); game=null
	for _frame in 4:await process_frame
	check(not is_instance_id_valid(token),"Actual shutdown releases the retired scene root")

func fresh(seed_value: int=SEED) -> void:
	await close_game()
	check(RunSession.queue_request(self,seed_value,"siege"),"Production session accepts the explicit siege seed")
	game=load("res://scenes/nightfall.tscn").instantiate(); root.add_child(game); current_scene=game
	for _frame in 5:await process_frame
	game.set_process(false); game.world.set_process(false)
	check(game.has_method("salvage_draw_snapshot") and game.has_method("draw_salvage_supply"),"Production root exposes the pure snapshot and draw action")
	await install_observer(); await press(KEY_1)
	check(game.phase=="night" and game.day_number==1 and game.phase_time==105.0 and game.scrap==90 and game.tower_count()==2 and game.run.seed_value==seed_value,"Actual opening retains original wallet/towers/105-second night and seed")
	elapsed=0.0

func precision_day() -> void:
	await fresh(); clear_enemies(); TransitionFixture.finish_for_fixture(game); await press(KEY_1)
	check(game.phase=="day" and game.day_number==2 and game.phase_time==90.0,"Real night completion and dawn card begin the actual first daylight")
	clear_enemies(); game.scrap=5000; game.phase_time=10000.0; stand(HOME)
	check(game.exploration.day_discoveries==0 and int(draw_snapshot().used)==0,"Isolated new daylight starts without fabricated exploration or purchases")

func ready_original_cache() -> int:
	# Removing unrelated precision actors does not earn the daily guarded box.
	# Select another original source satisfying the production opening gate;
	# leave the guarded source, its generation and its defeat ledger untouched.
	for index in game.discoveries.items.size():
		var item: Dictionary=game.discoveries.items[index]
		var node: Variant=item.get("node")
		if String(item.kind)!="supply_cache" or String(item.state)!="ready":continue
		if not is_instance_valid(node) or not node is Node3D or node.is_queued_for_deletion() or not node.is_inside_tree():continue
		if item.position!=node.position or not game.outpost_walkable(item.position):continue
		if game.discoveries.cache_guards.can_open(index):return index
	return -1

func collect_original(index: int) -> void:
	check(index>=0 and index<game.discoveries.items.size(),"Collection requires an existing original discovery index")
	if index<0 or index>=game.discoveries.items.size():return
	var item: Dictionary=game.discoveries.items[index]
	var original: Vector3=item.position; var original_node: Vector3=item.node.position
	var original_serial: int=item.serial
	check(item.state=="ready" and original==original_node,"The original seeded source is ready at its unchanged true position")
	if String(item.kind)=="supply_cache":
		check(game.discoveries.cache_guards.can_open(index),"The original real cache satisfies the actual guard prerequisite before F")
		if not game.discoveries.cache_guards.can_open(index):return
	stand(original)
	check(game.discoveries.nearest_item()==index and not game.discoveries.interaction_prompt().is_empty(),"Production nearest source and prompt select the original discovery")
	check(game.contracts.active_target_interaction().is_empty() and game.expeditions.interaction_prompt().is_empty(),"No higher-priority contract/expedition shadows this real F source")
	var before_count: int=game.exploration_count; var before_day: int=game.exploration.day_discoveries
	await press(KEY_F)
	if String(item.kind)=="supply_cache":
		check(item.state=="channel" and game.exploration_count==before_count,"Real cache F starts work without a discovery reward")
		game.simulate(3.001)
	check(item.state in ["cooling","active"] and game.exploration_count==before_count+1 and game.exploration.day_discoveries==before_day+1,"Only the completed real F discovery increments both genuine exploration ledgers")
	check(item.position==original and item.node.position==original_node and int(item.serial)==original_serial,"Real collection never relocates or replaces the seeded source generation")
	if item.state=="cooling":check(float(item.respawn)>=45.0 and float(item.respawn)<=65.0,"Real source keeps the original random45–65-second renewal")
	var collected: int=game.exploration_count; var parts: int=game.scrap
	await press(KEY_F)
	check(game.exploration_count==collected and game.scrap==parts,"Repeated actual F cannot repeat a consumed discovery reward")

func eligible() -> void:
	await precision_day(); await collect_original(0); stand(HOME)
	check(bool(draw_snapshot().available),"A real daylight discovery and actual high home position unlock purchasing")

func reject(label: String, expected_reason: String="") -> void:
	var before: Dictionary=state(); var view: Dictionary=draw_snapshot()
	check(not bool(view.available),label+": current eligibility is false")
	if not expected_reason.is_empty():check(String(view.reason)==expected_reason,label+": published rejection reason matches")
	var result: Dictionary=game.draw_salvage_supply()
	check(not bool(result.ok) and state()==before,label+": rejection preserves wallet, quota, all RNG, last receipt and game state")
	(evidence.boundary as Array).append({"label":label,"reason":view.reason,"before":before.draw,"parts":before.parts})

func oracle(seed_value: int, day_id: int=2) -> RandomNumberGenerator:
	var random: RandomNumberGenerator=RandomNumberGenerator.new()
	random.seed=RunSession.stream_seed(seed_value ^ 0x5a17c9 ^ (day_id*104729),"salvage_draw")
	return random

func expected_payout(roll: int) -> int:
	if roll>=90:return 120
	if roll>=60:return 40
	return 10

func check_receipt(result: Dictionary, wallet_before: int, roll: int, draw_number: int, module: RefCounted) -> void:
	var payout: int=expected_payout(roll)
	check(bool(result.ok) and int(result.roll)==roll and int(result.payout)==payout,"Committed receipt matches the independent real-seed roll and payout")
	check(int(result.cost)==30 and int(result.net)==payout-30 and int(result.wallet_before)==wallet_before and int(result.wallet_after)==wallet_before-30+payout,"Receipt records the actual30 cost, payout/net and both wallet values")
	check(game.scrap==wallet_before-30+payout and int(result.draw_number)==draw_number and int(module.snapshot().used)==draw_number,"Exactly one existing wallet assignment and one quota increment settle the draw")
	check(module.snapshot().last==result,"Published last receipt is exactly the committed transaction")

func capture(tag: String) -> void:
	if not render_test:return
	check(DisplayServer.get_name()!="headless","Capture requires a real renderer")
	if DisplayServer.get_name()=="headless":return
	var before: Dictionary=state(); var previous: Vector2i=root.size
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport
		game.world.night_mix=1.0 if game.phase=="night" else 0.0; game.world.apply_lighting(); await redraw()
		for _frame in 2:await RenderingServer.frame_post_draw
		var picture: Image=root.get_texture().get_image()
		check(picture.get_size()==viewport,"Real PNG matches its requested viewport")
		var folder: String=ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
		var name: String="%s-%dx%d" % [tag,viewport.x,viewport.y]
		check(not name in evidence.captures,"Capture names are unique within the actual run")
		check(picture.save_png(folder.path_join(name+".png"))==OK,"Real draw PNG saves beneath local build")
		(evidence.captures as Array).append(name)
	check(state()==before,"Captures never purchase, consume RNG, move actors or advance the real phase clock")
	root.size=previous; root.content_scale_size=previous; await redraw()

func unlock_sources() -> void:
	await precision_day()
	check(game.exploration_count==0 and not bool(draw_snapshot().available),"Fresh first daylight cannot unlock from a fabricated positive counter")
	reject("home without any real exploration","exploration_required")
	await open_exploration(true); await capture("unlock-locked"); await close_drawer()
	var legacy_guard: Dictionary=game.discoveries.cache_guards.snapshot(2)
	var cache_index: int=ready_original_cache()
	check(cache_index>=0,"Three-second unlock fixture finds an original ready box satisfying the actual guard prerequisite")
	if cache_index<0:return
	var cache: Dictionary=game.discoveries.items[cache_index]; var original: Vector3=cache.position
	var original_node: Node3D=cache.node; var original_serial: int=cache.serial
	var open_guard: Dictionary=game.discoveries.cache_guards.snapshot(cache_index)
	check(not bool(open_guard.blocked) and original_node.position==original,"Channel unlock uses the real open source at its unchanged seeded position")
	stand(original); await press(KEY_F)
	check(cache.state=="channel" and game.exploration_count==0 and game.exploration.day_discoveries==0,"Starting the original three-second cache is not a discovery")
	await open_exploration(true); await capture("unlock-real-cache-channel"); await close_drawer()
	stand(HOME); reject("incomplete cache cannot unlock","exploration_required")
	game.simulate(.001); check(cache.state=="ready" and float(cache.progress)==0.0,"Leaving the true cache cancels its unfinished work")
	await collect_original(cache_index); stand(HOME)
	check(cache.node==original_node and int(cache.serial)==original_serial and cache.position==original,"Cancelled and completed channel keep the same original cache identity")
	check(bool(draw_snapshot().available) and int(draw_snapshot().remaining)==2,"Actual cache completion unlocks two purchases at home")
	await open_exploration(true); await capture("unlock-real-day-home")
	(evidence.unlock as Array).append({"kind":"supply_cache","index":cache_index,"serial":original_serial,"position":original,
		"guard_prerequisite":open_guard,"former_fixed_index":2,"former_guard_state":legacy_guard,
		"count":game.exploration_count,"day_discoveries":game.exploration.day_discoveries,"snapshot":draw_snapshot()})
	await fresh(); clear_enemies(); await collect_original(0); stand(HOME)
	reject("night exploration cannot purchase","not_day")
	var old_count: int=game.exploration_count
	TransitionFixture.finish_for_fixture(game); await press(KEY_1); clear_enemies(); game.scrap=5000; game.phase_time=10000.0; stand(HOME)
	check(game.exploration_count==old_count and game.exploration.day_discoveries==0,"A real dawn retains run exploration but clears this daylight's exploration")
	reject("previous-night exploration cannot unlock today","exploration_required")
	await collect_original(1); stand(HOME)
	check(bool(draw_snapshot().available),"An actual new daylight F unlocks despite the retained night history")

func actual_input() -> void:
	await eligible(); await open_exploration(false)
	var before: Dictionary=state(); await click_ui(NAV)
	check(bool(game.hud.salvage_draw_open) and state()==before,"Actual footer navigation enters the draw page without payment or world commands")
	for button: int in [MOUSE_BUTTON_RIGHT]:
		before=state(); await click_ui(DRAW_BUTTON,button)
		check(state()==before,"Actual draw-page right click consumes the drawer without buying or issuing a world command")
	before=state(); await release_ui(DRAW_BUTTON)
	check(state()==before,"A real unpaired left release never purchases or leaks into world input")
	var random: RandomNumberGenerator=oracle(SEED)
	for number in [1,2]:
		var roll: int=random.randi_range(0,99); var wallet_before: int=game.scrap; var unrelated: Dictionary=periphery()
		await click_ui(DRAW_BUTTON)
		var result: Dictionary=draw_snapshot().last
		check_receipt(result,wallet_before,roll,number,game.salvage_draw)
		check(int(draw_snapshot().rng_state)==random.state and periphery()==unrelated,"A genuine left press consumes one isolated draw and preserves gameplay")
		(evidence.input as Array).append(result)
		if number==1:await capture("input-first-result")
	before=state(); await click_ui(DRAW_BUTTON)
	check(state()==before and String(draw_snapshot().reason)=="daily_limit","The third actual GUI press rejects atomically at the real daily cap")
	await capture("input-daily-cap")
	await click_ui(NAV); check(not bool(game.hud.salvage_draw_open),"Actual footer returns to the unchanged exploration main page")
	before=state(); await click_ui(DRAW_BUTTON,MOUSE_BUTTON_RIGHT)
	check(state()==before,"Hidden draw coordinates on the main drawer cannot purchase or command the world")
	await open_exploration(true); await click_ui(game.hud.details_tab_rect(2))
	check(not bool(game.hud.salvage_draw_open),"Changing the real tab clears the draw subpage")
	await open_exploration(true); await click_ui(CLOSE)
	check(game.hud.detail_tab.is_empty() and not bool(game.hud.salvage_draw_open),"The original close button clears the subpage and closes details")
	await open_exploration(true); await click_ui(game.hud.MAP_BUTTON_RECT)
	check(not bool(game.hud.salvage_draw_open),"The real map toggle clears the draw subpage")
	if game.hud.map_expanded:await click_ui(game.hud.MAP_BUTTON_RECT)

func exact_ledger() -> void:
	await eligible()
	var seeds: Dictionary={}
	for candidate in range(1,20001):
		var probe: RandomNumberGenerator=oracle(candidate)
		var roll: int=probe.randi_range(0,99)
		if not seeds.has(roll):seeds[roll]=candidate
		if seeds.size()==100:break
	check(seeds.size()==100,"Independent seeded RNG finds witnesses for every one of the100 real outcome buckets")
	if seeds.size()!=100:return
	var weights: Dictionary={10:0,40:0,120:0}; var total_payout := 0
	for bucket in range(100):
		var seed_value: int=int(seeds[bucket]); var probe: RefCounted=DrawScript.new()
		probe.setup(game,seed_value); probe.begin_day(); game.scrap=5000
		var random: RandomNumberGenerator=oracle(seed_value)
		check(int(probe.snapshot().rng_state)==random.state,"Day2 module begins at its independently derived daily seed")
		var unrelated: Dictionary=periphery(); var root_before: Dictionary=draw_snapshot()
		var roll: int=random.randi_range(0,99); var result: Dictionary=probe.draw()
		check(roll==bucket,"Seed witness exercises the intended exact outcome bucket")
		check_receipt(result,5000,roll,1,probe)
		check(int(probe.snapshot().rng_state)==random.state and periphery()==unrelated and draw_snapshot()==root_before,"A bucket draw advances exactly its local RNG while all five existing streams and the live root draw remain unchanged")
		weights[int(result.payout)]=int(weights[int(result.payout)])+1; total_payout+=int(result.payout)
		(evidence.ledger as Array).append({"bucket":bucket,"seed":seed_value,"result":result,"rng_state":probe.snapshot().rng_state})
		var copy: Dictionary=probe.snapshot(); copy.last.payout=-900; copy.results[0].payout=-900
		check(int(probe.snapshot().last.payout)==expected_payout(bucket) and int(probe.snapshot().results[0].payout)==10,"Mutating returned nested snapshots cannot alter production receipts or probability tables")
		probe.clear()
	check(weights=={10:60,40:30,120:10} and total_payout==3000,"All100 exact buckets prove60/30/10 percent and theoretical mean payout30; this is not a sampled-frequency claim")
	var stream_a: RefCounted=DrawScript.new(); stream_a.setup(game,SEED); stream_a.begin_day(); game.scrap=5000
	var isolated: Dictionary=stream_a.draw(); var isolated_state: int=int(stream_a.snapshot().rng_state)
	# Deliberate precision-only interleaving: these are real pre-existing RNGs,
	# not natural combat/card outcomes or evidence of a changed campaign.
	for _draw in 17:
		game.rng.randf(); game.run.rng.randf(); game.spawn_rng.randf(); game.discoveries.rng.randf(); game.wildlife.rng.randf()
	var stream_b: RefCounted=DrawScript.new(); stream_b.setup(game,SEED); stream_b.begin_day(); game.scrap=5000
	var interleaved: Dictionary=stream_b.draw()
	check(int(interleaved.roll)==int(isolated.roll) and int(interleaved.payout)==int(isolated.payout) and int(stream_b.snapshot().rng_state)==isolated_state,"Interleaving all five original streams cannot change the independent same-seed/day draw sequence")
	stream_a.clear(); stream_b.clear()
	for bucket in [0,60,90]:
		game.salvage_draw.setup(game,int(seeds[bucket])); game.salvage_draw.begin_day(); game.scrap=5000
		var unrelated: Dictionary=periphery(); var result: Dictionary=game.draw_salvage_supply()
		check_receipt(result,5000,bucket,1,game.salvage_draw)
		check(periphery()==unrelated,"Root notification/result presentation never grants exploration, changes cards or gameplay")
		await open_exploration(true); await capture("ledger-payout-%d" % int(result.payout))
	game.salvage_draw.setup(game,SEED); game.salvage_draw.begin_day(); game.scrap=5000
	var random: RandomNumberGenerator=oracle(SEED)
	for number in [1,2]:
		var roll: int=random.randi_range(0,99); var wallet_before: int=game.scrap
		check_receipt(game.draw_salvage_supply(),wallet_before,roll,number,game.salvage_draw)
		var before: Dictionary=state(); game.salvage_draw.begin_day()
		check(state()==before,"Repeating begin_day for the same day cannot reseed, replay or replenish quota")
	reject("settled third purchase","daily_limit")
	var source_state: Dictionary=state()
	for _read in 50:
		game.salvage_draw_snapshot(); game.salvage_draw.snapshot()
	check(state()==source_state,"Repeated pure snapshots cannot consume randomness, replenish limits or alter wallets")
	(evidence.ledger as Array).append({"weights":weights,"mean_payout":float(total_payout)/100.0,"mean_net":float(total_payout)/100.0-30.0})

func boundary_conditions() -> void:
	await eligible(); await open_exploration(true)
	game.scrap=29; reject("wallet29","insufficient_scrap"); await capture("boundary-wallet29")
	game.scrap=0; reject("wallet0","insufficient_scrap"); game.scrap=5000
	for x: float in [5.99,6.0]:
		game.hero.position=Vector3(x,5,0); game.move_goal=game.hero.position; game.hero_path.clear()
		check(bool(draw_snapshot().available),"Real horizontal home radius includes %.2fm on the high court" % x)
		(evidence.boundary as Array).append({"home_x":x,"snapshot":draw_snapshot()})
	await capture("boundary-inclusive6")
	game.hero.position=Vector3(6.01,5,0); game.move_goal=game.hero.position
	reject("home6.01","return_home"); await capture("boundary-outside6")
	for y: float in [4.8,0.0]:
		game.hero.position=Vector3(0,y,3); game.move_goal=game.hero.position
		reject("home height%.1f" % y,"return_home")
	for point: Vector3 in [Vector3(INF,5,0),Vector3(NAN,5,0)]:
		game.hero.position=point
		var before: Dictionary=draw_snapshot(); var parts: int=game.scrap
		var result: Dictionary=game.draw_salvage_supply()
		check(not bool(result.ok) and String(before.reason)=="return_home" and draw_snapshot()==before and game.scrap==parts,"Nonfinite actor position rejects without touching draw state or wallet")
	stand(HOME)
	for clock: float in [0.0,-.001,INF,NAN]:
		game.phase_time=clock
		var before: Dictionary=draw_snapshot(); var parts: int=game.scrap
		var result: Dictionary=game.draw_salvage_supply()
		check(not bool(result.ok) and String(before.reason)=="not_day" and draw_snapshot()==before and game.scrap==parts,"Nonpositive/nonfinite daylight clocks reject without RNG, quota or wallet changes")
	game.phase_time=10000.0
	game.day_number=1; reject("opening day cannot purchase","day_unavailable"); game.day_number=2
	game.day_number=3; reject("uninitialized later day","day_unavailable"); game.day_number=2
	game.exploration.route_day=3; reject("exploration belongs to a different day","exploration_required"); game.exploration.route_day=2
	game.hero.hp=0.0; reject("dead health","hero_unavailable"); game.hero.hp=game.hero.max_hp
	game.hero.alive=false; reject("dead actor flag","hero_unavailable"); game.hero.alive=true
	game.beacon_hp=0.0; reject("destroyed beacon","beacon_unavailable"); game.beacon_hp=game.BEACON_MAX
	game.quitting=true; reject("close pending","closed"); game.quitting=false
	game.restart_pending=true; reject("retry pending","closed"); game.restart_pending=false
	game.scrap=30
	var random: RandomNumberGenerator=oracle(SEED); var roll: int=random.randi_range(0,99)
	check_receipt(game.draw_salvage_supply(),30,roll,1,game.salvage_draw)
	check(game.scrap==expected_payout(roll),"Exactly30 existing parts can buy one draw without a second wallet")

func lifecycle_boundaries() -> void:
	await eligible(); await open_exploration(true)
	var first: Dictionary=game.draw_salvage_supply(); var remembered: Dictionary=draw_snapshot()
	await close_drawer(); await press(KEY_ESCAPE)
	check(game.phase=="paused","Real Esc enters pause after the drawer is closed")
	var before: Dictionary=state(); game.simulate(30.0)
	check(state()==before,"Actual pause freezes the original phase clock, wallet, draw and all random streams")
	reject("real pause","not_day"); await open_exploration(true)
	before=state(); await click_ui(DRAW_BUTTON); check(state()==before,"Actual paused GUI cannot purchase or leak a world command")
	await capture("lifecycle-paused"); await close_drawer(); await press(KEY_F1)
	check(game.music_credits_open,"Real F1 opens sources over pause")
	before=state(); await click_ui(DRAW_BUTTON); check(state()==before,"Actual source overlay prevents underlying draw purchases")
	await press(KEY_ESCAPE); check(game.phase=="paused" and not game.music_credits_open,"First actual Esc closes sources and retains pause")
	await press(KEY_ESCAPE); check(game.phase=="day","Second actual Esc resumes the daylight")
	await press(KEY_V); check(game.phase=="draft","Real paid V opens the production reinforcement draft")
	before=state(); game.simulate(30.0); reject("real card draft","not_day")
	check(state()==before,"Actual card selection freezes clocks, quota, receipt and RNG after its legitimate card cost")
	await press(KEY_1); check(game.phase=="day" and int(draw_snapshot().used)==1,"Finishing the actual card returns to the same one-used daylight")
	check(draw_snapshot().last==first,"Pause/sources/card selection retain the last committed draw receipt")
	game.start_night(); clear_enemies()
	check(game.phase=="night" and int(draw_snapshot().used)==1 and int(draw_snapshot().rng_state)==int(remembered.rng_state) and int(draw_snapshot().remaining)==0,"Actual dusk preserves earned result/RNG/quota and closes all remaining daylight purchases")
	var dusk: Dictionary=draw_snapshot(); game.phase="day"; game.salvage_draw.begin_day()
	check(String(draw_snapshot().reason)=="day_unavailable" and int(draw_snapshot().used)==int(dusk.used) and int(draw_snapshot().rng_state)==int(dusk.rng_state) and int(draw_snapshot().remaining)==0,"Explicit same-day reopen fixture cannot undo the dusk latch or replenish quota")
	game.phase="night"
	reject("actual dusk","not_day"); await open_exploration(true); await capture("lifecycle-night")
	await close_drawer(); TransitionFixture.finish_for_fixture(game); await press(KEY_1); clear_enemies(); stand(HOME)
	check(game.phase=="day" and game.day_number==3 and game.exploration.day_discoveries==0 and int(draw_snapshot().used)==0,"Real next dawn resets quota but requires a new genuine daylight discovery")
	var next_random: RandomNumberGenerator=oracle(SEED,3)
	check(int(draw_snapshot().rng_state)==next_random.state,"A real later daylight gets its independent seed without depending on yesterday's draw count")
	reject("next day starts locked","exploration_required"); await open_exploration(true); await capture("lifecycle-next-day-locked")
	await close_drawer(); game.phase_time=10000.0; game.scrap=5000; await collect_original(1); stand(HOME)
	check(bool(draw_snapshot().available),"Real next-day F restores purchasing independently of the prior day's exploration")
	var later: Dictionary=game.draw_salvage_supply()
	check(bool(later.ok) and int(later.day_id)==3 and int(later.draw_number)==1,"The later day's first real transaction uses the new quota")
	(evidence.lifecycle as Array).append({"first":first,"later":later,"next_day":draw_snapshot()})
	var retired: RefCounted=game.salvage_draw; var old_root: int=game.get_instance_id()
	game.hero.hurt(100000.0,null)
	check(game.phase=="ended" and not game.hero.alive,"Explicit lethal fixture follows actual hero death and defeat cleanup")
	var ended_parts: int=game.scrap; var ended: Dictionary=retired.snapshot()
	check(not bool(retired.draw().ok) and game.scrap==ended_parts and retired.snapshot()==ended,"Actual defeat retires the draw without refunding or repaying earned transactions")
	await press(KEY_ENTER)
	for _frame in 240:
		if current_scene!=null and current_scene.get_instance_id()!=old_root:break
		await create_timer(.02,true,false,true).timeout
	check(current_scene!=null and current_scene.get_instance_id()!=old_root,"Actual Enter reloads a new root for the same-seed retry")
	if current_scene==null or current_scene.get_instance_id()==old_root:return
	game=current_scene as Node3D; game.set_process(false); game.world.set_process(false)
	for _frame in 5:await process_frame
	check(not is_instance_id_valid(old_root) and game.run.seed_value==SEED and game.phase=="draft" and game.scrap==90 and game.exploration_count==0 and int(draw_snapshot().used)==0 and draw_snapshot().last.is_empty(),"Same-seed actual retry frees the old scene and starts with original90 parts, no exploration or receipt")
	before=state(); check(not bool(retired.draw().ok) and state()==before,"An externally retained old RefCounted draw cannot write the new run's wallet")
	await install_observer(); await press(KEY_1); clear_enemies(); TransitionFixture.finish_for_fixture(game); await press(KEY_1); clear_enemies()
	game.scrap=5000; game.phase_time=10000.0; await collect_original(0); stand(HOME)
	var replay: Dictionary=game.draw_salvage_supply()
	check(int(replay.roll)==int(first.roll) and int(replay.payout)==int(first.payout),"A genuine same-seed retry reproduces the first day's first roll after a new real exploration")
	game.day_number=game.max_nights(); TransitionFixture.finish_for_fixture(game)
	check(game.phase=="ended" and game.victory,"Explicit last-night boundary invokes actual production victory cleanup")
	reject("actual victory","closed")
	game.salvage_draw.clear(); var cleared: Dictionary=draw_snapshot(); game.salvage_draw.clear()
	check(draw_snapshot()==cleared and int(cleared.used)==0 and int(cleared.remaining)==0 and cleared.last.is_empty() and not bool(cleared.available),"Repeated clear is idempotent and retires all local receipt/quota state")

func clear_transients() -> void:
	game.notice_time=0.0; game.beacon_alarm_time=0.0; game.hero_damage_flash_time=0.0; game.combat_milestone_time=0.0
	game.combat.clear_transients()

func measure_hud(tag: String) -> void:
	var before: Dictionary=state(); var previous: Vector2i=root.size
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport; await redraw()
		var bottom := 0.0; var nav_seen := false; var draw_seen := false
		for row: Dictionary in game.hud.drawn_labels:
			check(row.point.x>=0 and row.point.x+float(row.width)<=1440 and row.point.y-float(row.ascent)>=0 and row.point.y+float(row.descent)<=900,"Actual glyph rectangles remain inside the logical viewport in "+tag+": "+String(row.text))
			if NAV.has_point(row.point):nav_seen=true; check(row.point.x+float(row.width)<=NAV.end.x,"Actual footer navigation text fits its190px rectangle")
			if DRAW_BUTTON.has_point(row.point):draw_seen=true; check(row.point.x+float(row.width)<=DRAW_BUTTON.end.x,"Actual draw-button text fits its496px rectangle")
			for character: String in String(row.text):
				var code: int=character.unicode_at(0)
				if code>=0x4e00 and code<=0x9fff:check(game.hud.font.has_char(code),"Actual system font includes Chinese glyph "+character)
		for row: Dictionary in game.hud.drawer_labels:
			if row.point.x==46 and row.point.y>=175 and row.point.y<692:
				bottom=maxf(bottom,float(row.point.y)+float(row.descent))
				check(float(row.width)<=496.0 and row.point.y+float(row.descent)<=692,"Complete exploration/draw content fits496px and stays above the original close/footer row")
		check(nav_seen and NAV in game.hud.drawn_boxes and CLOSE in game.hud.drawn_boxes,"Actual exploration page retains separate navigation and the original close button")
		check(not bool(game.hud.salvage_draw_open) or draw_seen,"Actual draw subpage has its real confirmation button text")
		(evidence.hud as Array).append({"tag":tag,"viewport":viewport,"content_bottom":bottom,"nav":nav_seen,"draw":draw_seen,"subpage":game.hud.salvage_draw_open})
	check(state()==before,"Repeated three-viewport layout observation is pure for wallet, eligibility, RNG, clocks and actors")
	root.size=previous; root.content_scale_size=previous; await redraw()

func actual_hud() -> void:
	await precision_day()
	var cache_index: int=ready_original_cache()
	check(cache_index>=0,"Four-reward HUD fixture requires a real original box satisfying the actual guard prerequisite")
	if cache_index<0:return
	for index: int in [0,1,cache_index,3]:await collect_original(index)
	stand(HOME); check(game.reward_toasts.size()==4,"Four actual production reward records occupy the original exploration history")
	await open_exploration(false); await measure_hud("four-real-rewards"); await capture("hud-four-real-rewards")
	var rewards: Array=game.reward_toasts.duplicate(true); var before: Dictionary=state()
	await click_ui(NAV); await measure_hud("draw-subpage"); await capture("hud-draw-subpage")
	check(game.reward_toasts==rewards and state()==before,"Real subpage navigation preserves every existing exploration reward record")
	await click_ui(NAV); check(game.reward_toasts==rewards,"Returning from draw details retains the four real exploration rewards")
	await close_drawer(); clear_transients(); await redraw()
	var original_boxes: Array=game.hud.drawn_boxes.duplicate(); var original_rects: Array=game.hud.visible_hud_rects()
	await open_exploration(true); await click_ui(DRAW_BUTTON); await close_drawer(); clear_transients(); await redraw()
	check(game.hud.drawn_boxes==original_boxes and game.hud.visible_hud_rects()==original_rects,"A settled draw adds no default permanent HUD rectangle after the drawer closes")
	await open_exploration(true); await measure_hud("result"); await capture("hud-result")
	await click_ui(DRAW_BUTTON); await measure_hud("daily-cap"); await capture("hud-daily-cap")

func natural_tick() -> void:
	game.aim=game.hero.position+Vector3(0,0,8)
	if game.gate_pressure()>0:game.cast(0)
	if game.hero.hp<game.hero.max_hp*.6:game.cast(1); game.cast(4)
	if game.gate_pressure()>=6:game.cast(3)
	var before: Vector3=game.hero.position; var speed: float=game.hero.speed
	game.simulate(STEP); elapsed+=STEP
	var after: Vector3=game.hero.position
	check(after.is_finite() and game.outpost_walkable(after) and absf(after.y-game.outpost_height(after))<.001 and game.can_traverse(before,after) and planar(before,after)<=speed*STEP+.001,"Every native natural hero step is finite, grounded, traversable and speed-bounded")
	if (before.z<Layout.WALL_CENTER and after.z>=Layout.WALL_CENTER) or (before.z>Layout.WALL_CENTER and after.z<=Layout.WALL_CENTER):
		var ratio: float=(Layout.WALL_CENTER-before.z)/(after.z-before.z)
		var crossing_x: float=lerpf(before.x,after.x,ratio)
		if absf(crossing_x)<=Layout.FORT_OUTER:
			check(absf(crossing_x)<Layout.GATE_HALF,"Every crossing of the actual south wall passes through its true gate")
		if absf(crossing_x)<Layout.GATE_HALF:
			natural_gate_crossings.append({"day_second":90.0-game.phase_time,"x":crossing_x,"from":before,"to":after})

func walk_to(point: Vector3, limit: int=850) -> bool:
	var sampled: Vector3=await right(point)
	check(planar(sampled,point)<.05 and planar(game.move_goal,sampled)<.05,"Actual natural right click commits the unmodified source/home target")
	for frame in limit:
		if game.phase!="day" or not game.hero.alive:return false
		if planar(game.hero.position,point)<.2:return true
		natural_tick()
		if frame%50==49:await process_frame
	return false

func natural_economy() -> void:
	await fresh(); await right(Vector3(0,5,10))
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
	check(game.phase=="draft" and game.hero.alive and game.beacon_hp>0,"Unmodified original skill policy reaches genuine dawn from the funded first night")
	if game.phase!="draft":return
	var dawn_parts: int=game.scrap; var deaths: int=game.kills; await press(KEY_1)
	check(game.phase=="day" and game.phase_time==90.0 and game.scrap==dawn_parts and game.exploration_count==0,"Real dawn retains original90-second daylight, actually earned parts and no fabricated exploration")
	var source: Dictionary=game.discoveries.items[0]; var original: Vector3=source.position
	check(source.kind=="ember_bloom" and source.state=="ready" and source.node.position==original and game.outpost_walkable(original),"Natural route uses the original seeded ready first flower without relocating any actor or resource")
	natural_gate_crossings.clear()
	var reached: bool=await walk_to(original)
	check(reached and game.discoveries.nearest_item()==0 and game.interaction_prompt().contains("余烬花"),"Natural real navigation reaches the original source and its production F prompt before sunset")
	if not reached:return
	var before_collection: int=game.scrap; var collection_clock: float=game.phase_time
	await press(KEY_F)
	var collection_gain: int=game.scrap-before_collection
	check(source.state=="cooling" and game.exploration_count==1 and game.exploration.day_discoveries==1 and game.exploration.run_discoveries==1 and game.phase_time==collection_clock,"Natural genuine F consumes the unmodified source and produces the real unlock without advancing its native clock")
	check(source.position==original and source.node.position==original,"Natural source remains at its original seeded location")
	var collected_at: float=90.0-game.phase_time
	reject("natural discovery still requires returning home","return_home")
	reached=await walk_to(HOME)
	check(reached and game.hero.position.y>4.8 and planar(game.hero.position,Vector3.ZERO)<=6.0 and bool(draw_snapshot().available),"Native hero truly returns through the south gate to the high beacon court within the original90 seconds")
	if not reached:return
	var returned_at: float=90.0-game.phase_time; var returning_income: int=game.scrap-before_collection-collection_gain
	check(natural_gate_crossings.size()>=2,"The unmodified natural collection and return contain actual outward and inward south-gate crossings")
	await open_exploration(true); await capture("natural-original-day-home")
	var before_draws: int=game.scrap; var clock: float=game.phase_time; var receipts: Array[Dictionary]=[]
	var random: RandomNumberGenerator=oracle(SEED)
	for number in [1,2]:
		var roll: int=random.randi_range(0,99); var wallet_before: int=game.scrap; var unrelated: Dictionary=periphery()
		await click_ui(DRAW_BUTTON); var result: Dictionary=draw_snapshot().last
		check_receipt(result,wallet_before,roll,number,game.salvage_draw)
		check(periphery()==unrelated and game.phase_time==clock,"Natural GUI settlement spends only the earned wallet and consumes no phase time or gameplay RNG")
		receipts.append(result)
	var total_payout := 0
	for receipt: Dictionary in receipts:total_payout+=int(receipt.payout)
	check(game.scrap==before_draws-60+total_payout,"The natural two-draw wallet delta is precisely both real payments and committed payouts")
	var capped: Dictionary=state(); await click_ui(DRAW_BUTTON)
	check(state()==capped,"Natural third GUI click retains the exact already-earned results and daily cap")
	await capture("natural-two-draws")
	(evidence.economy as Array).append({"seed":SEED,"opening":90,"night_seconds":105,"day_seconds":90,"first_night_deaths":deaths,"dawn_parts":dawn_parts,"source_position":original,"collection_day_second":collected_at,"collection_gain":collection_gain,"return_day_second":returned_at,"remaining_seconds_at_draw":clock,"route_other_income":returning_income,"parts_before_draws":before_draws,"parts_after_draws":game.scrap,"payments":60,"payouts":total_payout,"receipts":receipts,"gate_crossings":natural_gate_crossings.duplicate(true),"hero_hp":game.hero.hp,"beacon_hp":game.beacon_hp,"scope":"one fixed-seed original skill policy; no added money, clock changes, source/hero placement, enemy removal or stat changes; only first-night and original-day real collection/return/two-purchase proof"})
	print("SALVAGE_NATURAL dawn_parts=",dawn_parts," deaths=",deaths," collected=",collected_at," returned=",returned_at," remaining=",clock," before=",before_draws," after=",game.scrap," paid60 payout=",total_payout)

func run() -> void:
	var cases: Dictionary={"unlock":unlock_sources,"input":actual_input,"ledger":exact_ledger,"boundary":boundary_conditions,"lifecycle":lifecycle_boundaries,"hud":actual_hud,"economy":natural_economy}
	var args: PackedStringArray=OS.get_cmdline_user_args(); var selected: Array=cases.keys(); var index: int=args.find("--case")
	if index>=0 and index+1<args.size():selected=[args[index+1]]
	for name: String in selected:
		if not cases.has(name):check(false,"Unknown salvage-draw stage "+name); break
		active_stage=name; print("SALVAGE_STAGE_BEGIN ",name)
		await (cases[name] as Callable).call()
		print("SALVAGE_STAGE_END ",name," checks=",checks," failures=",failures.size())
		(evidence.completed as Array).append(name)
		if not failures.is_empty():break
	await close_game()
	await create_timer(.5,true,false,true).timeout
	evidence.shutdown_audio_drain_seconds=.5
	var folder: String=ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
	var file: FileAccess=FileAccess.open(folder.path_join("nightfall-salvage-draw.json"),FileAccess.WRITE)
	check(file!=null,"Structured salvage evidence opens under the local build directory")
	evidence.checks=checks; evidence.failures=failures
	if file!=null:file.store_string(JSON.stringify(evidence,"\t")); file.close()
	finished=true; print("SALVAGE_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
