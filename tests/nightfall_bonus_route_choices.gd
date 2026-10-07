extends "res://tests/nightfall_attack_move.gd"
## Artificial phase setup only; natural clearance and victory use real combat.
## Independent scene/input acceptance. Precision uses5000 parts, extended
## clocks, directly stationed hero, authoritative relocated discoveries and
## one manual speed change to inspect immutable cached HUD estimates;
## unrelated enemies are removed. Economy preserves original90/105/90,
## seeded sources/actors/stats and actual earned wallet. Lighting is controlled
## only for captures. Neither section establishes human or campaign balance.

const RETURN_RECT := Rect2(46,244,496,32)
const CONFIRM_RECT := Rect2(46,568,496,34)
const CLOSE_RECT := Rect2(428,692,112,30)
const ROUTE_HOME := Vector3(0,5,3.1)
const ROUTE_ROOT_OBSERVER := """extends 'res://scripts/nightfall.gd'
var observed_contract_payments: Array[Dictionary] = []
var observed_exploration_payments: Array[Dictionary] = []
func settle_contract_reward() -> void:
\tvar before: int=scrap
\tvar request: Dictionary=contracts.pending_reward.duplicate(true)
\tsuper.settle_contract_reward()
\tif not request.is_empty():observed_contract_payments.append({'request':request,'before':before,'after':scrap,'delta':scrap-before,'time':phase_time,'phase':phase})
func grant_exploration_reward(title: String, point: Vector3, scrap_gain: int, hp_gain: float=0.0, mana_gain: float=0.0, category: String='') -> void:
\tvar before: int=scrap
\tvar count: int=exploration_count
\tsuper.grant_exploration_reward(title,point,scrap_gain,hp_gain,mana_gain,category)
\tobserved_exploration_payments.append({'title':title,'category':category,'position':point,'base':scrap_gain,'before':before,'after':scrap,'delta':scrap-before,'additional':scrap-before-scrap_gain,'count_before':count,'count_after':exploration_count,'time':phase_time,'phase':phase})
"""
const ROUTE_OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var drawn_rects: Array[Rect2] = []
var drawn_labels: Array[Dictionary] = []
var drawer_labels: Array[Dictionary] = []
var recording_drawer := false
var draw_queries: Array[int] = []
func _draw() -> void:
\tdrawn_rects.clear(); drawn_labels.clear(); drawer_labels.clear(); recording_drawer=false
\tvar before: int=game.contracts.budget_route_queries
\tsuper._draw()
\tdraw_queries.append(game.contracts.budget_route_queries-before)
func box(rect: Rect2, fill: Color=Color(.022,.035,.045,.88), outline: Color=Color('435455')) -> void:
\tdrawn_rects.append(rect)
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

var stage_returned := false
var natural_gate_crossings: Array[Dictionary] = []
var natural_sources: Array[Dictionary] = []
var natural_primary: Array[Dictionary] = []

func _initialize() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	render_test="--render-test" in args; output_dir="res://build/bonus-route-choices"
	var index: int=args.find("--output-dir")
	if index>=0 and index+1<args.size():
		var requested: String=ProjectSettings.globalize_path(args[index+1]).simplify_path()
		var allowed: String=ProjectSettings.globalize_path("res://build").simplify_path()
		if requested.begins_with(allowed+"/"):output_dir=requested
		else:check(false,"Route evidence must remain below the local build directory")
	root.size=VIEWPORTS[0]; root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT; root.content_scale_size=VIEWPORTS[0]
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true); root.position=Vector2i(10000,10000); root.hide()
	evidence={"seed":SEED,"scope":"precision5000/extended phases/direct positions/authoritative relocated discovery nodes/removed unrelated enemies; economy original90/105/90, native actors/source positions/stats, actual earned wallet; controlled capture lighting; no human or campaign balance claim","completed":[],"captures":[],"capture_receipt":[],"options":[],"input":[],"identity":[],"path":[],"ledger":[],"lifecycle":[],"hud":[],"economy":[]}
	create_timer(900.0,true,false,true).timeout.connect(watchdog); call_deferred("run")

func watchdog() -> void:
	if finished:return
	check(false,"Bonus-route acceptance stalled in "+active_stage)
	await finalize(); finished=true; quit(1)

func install_route_observer() -> void:
	var script: GDScript=GDScript.new(); script.source_code=ROUTE_OBSERVER
	check(script.reload()==OK,"Read-only route HUD observer compiles")
	var original: Control=game.hud; var layer: Node=original.get_parent()
	layer.remove_child(original); original.queue_free()
	var observed: Control=script.new(); observed.game=game; game.hud=observed; layer.add_child(observed)
	observed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); observed.set_process(false)
	await redraw()

func fresh(is_precision: bool=true) -> void:
	await close_game(); precision=is_precision
	check(RunSession.queue_request(self,SEED,"siege"),"Actual bonus run accepts the original fixed siege seed")
	var observer: GDScript=GDScript.new(); observer.source_code=ROUTE_ROOT_OBSERVER
	check(observer.reload()==OK,"Read-only root observer forwards genuine contract payments")
	var packed: PackedScene=load("res://scenes/nightfall.tscn").duplicate()
	var bundled: Dictionary=packed.get("_bundled").duplicate(true); var replaced := 0
	for index in bundled.variants.size():
		var value: Variant=bundled.variants[index]
		if value is Script and value.resource_path=="res://scripts/nightfall.gd":bundled.variants[index]=observer; replaced+=1
	check(replaced==1,"Observer replaces the one root script before constructing its eager modules")
	packed.set("_bundled",bundled); game=packed.instantiate(); game.scene_file_path="res://scenes/nightfall.tscn"; root.add_child(game); current_scene=game
	for _frame in 5:await process_frame
	game.set_process(false); game.world.set_process(false); await install_route_observer(); await press(KEY_1)
	check(game.phase=="night" and game.phase_time==105.0 and game.scrap==90 and game.tower_count()==2 and game.run.seed_value==SEED,"Actual opening preserves original90 parts/two gift towers/105 seconds")
	elapsed=0.0; hurt_events.clear(); death_events.clear(); gate_tokens.clear()
	if precision:
		game.scrap=5000; game.phase_time=10000.0; game.wave_index=game.WAVES_PER_NIGHT
		clear_enemies(); suspend_defense(); stand(HOME)
	check(game.contracts.has_method("bonus_route_options") and game.contracts.has_method("select_bonus_route") and game.has_method("select_bonus_route") and game.has_method("choose_bonus_route"),"Actual production root/module expose the route actions")

func redraw() -> void:
	game.hud.refresh_contract_budgets(); game.hud.queue_redraw()
	for _frame in 3:await process_frame

func periphery() -> Dictionary:
	var result: Dictionary=super.state()
	result.combat_rng=game.rng.state; result.discovery_rng=game.discoveries.rng.state; result.wildlife_rng=game.wildlife.rng.state
	result.day=game.day_number; result.hp=game.hero.hp; result.mana=game.mana; result.beacon=game.beacon_hp
	result.kills=game.kills; result.exploration_count=game.exploration_count; result.milestones=game.exploration_milestones
	result.exploration={"day":game.exploration.day_discoveries,"run":game.exploration.run_discoveries,"types":game.exploration.day_kinds.duplicate(),"streak":game.exploration.streak,"streak_time":game.exploration.streak_time,"affinity_time":game.exploration.affinity_time}
	result.plan=game.night_plan.duplicate(true); result.dragging=game.selection_dragging
	result.cards=game.run.owned.duplicate(true); result.pending=game.run.pending
	var sources: Array[Dictionary]=[]
	for item: Dictionary in game.discoveries.items:sources.append({"kind":item.kind,"serial":item.serial,"state":item.state,"position":item.position,"progress":item.progress,"remaining":item.remaining,"respawn":item.respawn,"node":plain(item.node)})
	result.sources=sources
	return result

func plain(value: Variant) -> Variant:
	# A released Object must be tested before any `is Object` operation;
	# Godot raises an error even for that type test on a freed instance.
	if typeof(value)==TYPE_OBJECT:return value.get_instance_id() if is_instance_valid(value) else -1
	if typeof(value)==TYPE_DICTIONARY:
		var result: Dictionary={}
		for key: Variant in value:result[key]=plain(value[key])
		return result
	if typeof(value)==TYPE_ARRAY:
		var result: Array=[]
		for item: Variant in value:result.append(plain(item))
		return result
	return value

func state() -> Dictionary:
	var result: Dictionary=periphery()
	result.contract={"status":game.contracts.status,"target":plain(game.contracts.bonus_target),"done":game.contracts.bonus_done,"choice":game.contracts.bonus_choice,"pending":game.contracts.pending_reward.duplicate(true),"primary":game.contracts.done.duplicate()}
	return result

func routes() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]; result.assign(game.contracts.bonus_route_options())
	check(result.size()<=3,"Production exposes at most three bonus routes")
	for row: Dictionary in result:
		for key: String in ["index","serial","kind","position","scrap","distance","selected","available","reason","budget"]:check(row.has(key),"Route exposes "+key)
		var value: Dictionary=row.get("budget",{})
		for key: String in ["available","candidate","outbound_distance","return_distance","action_seconds","total_seconds","spare_seconds","risk"]:check(value.has(key),"Each route has live budget "+key)
	return result

func selected_route() -> Dictionary:
	for row: Dictionary in game.contracts.bonus_route_options():
		if bool(row.selected):return row
	return {}

func route_at(index: int, serial: int=-1) -> Dictionary:
	for row: Dictionary in game.contracts.bonus_route_options():
		if int(row.index)==index and (serial<0 or int(row.serial)==serial):return row
	return {}

func route_slot(index: int, serial: int) -> int:
	for slot in game.hud.bonus_route_budgets.size():
		var row: Dictionary=game.hud.bonus_route_budgets[slot]
		if int(row.index)==index and int(row.serial)==serial:return slot
	return -1

func ready_primary() -> bool:
	await fresh(); TransitionFixture.finish_for_fixture(game); await press(KEY_1); clear_enemies()
	check(game.phase=="day" and game.day_number==2 and game.phase_time==90.0,"Actual dawn card starts original first daylight before precision extension")
	game.scrap=5000; game.phase_time=10000.0
	var found := false
	for seed_value in 200:
		game.contracts.setup(game,seed_value); game.contracts.on_day()
		if game.contracts.kind=="salvage":found=true; break
	check(found,"Precision seed search exposes a real safe two-cache primary")
	if not found:return false
	for target: Dictionary in game.contracts.targets.duplicate():
		stand(target.position); await press(KEY_F)
		check(bool(target.source.collected),"Actual F collects the authoritative primary salvage")
	check(game.contracts.status=="bonus_offer" and game.contracts.pending_reward.is_empty(),"Real field completion opens a bonus decision without a fabricated delivery")
	clear_enemies(); stand(OPEN)
	return game.contracts.status=="bonus_offer"

func pool(specs: Array[Dictionary]) -> Array[Dictionary]:
	for item: Dictionary in game.discoveries.items:game.discoveries.begin_cooling(item,600.0)
	var result: Array[Dictionary]=[]
	for index in specs.size():
		var item: Dictionary=game.discoveries.items[index]; var point: Vector3=specs[index].position
		point.y=game.outpost_height(point); item.position=point; item.node.position=point
		item.kind=String(specs[index].kind); item.state="ready"; item.progress=0.0; item.serial+=1
		game.discoveries.replace_model(item); result.append(item)
	game.discoveries.motivation_revision+=1; game.contracts.clear_budget_cache()
	return result

func choice_pool() -> Array[Dictionary]:
	return pool([{"kind":"memory_crystal","position":Vector3(5,0,33)},{"kind":"supply_cache","position":Vector3(-12,0,44)},{"kind":"ember_bloom","position":Vector3(12,0,38)}])

func open_contract() -> void:
	if game.construction.active:await press(KEY_ESCAPE)
	if game.hud.detail_tab.is_empty():await press(KEY_F3)
	if game.hud.detail_tab!="contract":await click_ui(game.hud.details_tab_rect(0))
	await redraw(); check(game.hud.detail_tab=="contract","Actual F3/tab opens the existing contract drawer")

func assert_rejected(index: int, serial: int, label: String, expected: Dictionary={}) -> void:
	var before: Dictionary=state(); var selected: Dictionary=plain(selected_route())
	check(not game.select_bonus_route(index,serial,expected),label+": root selection rejects")
	check(state()==before and plain(selected_route())==selected,label+": rejected selection preserves exact wallet/RNG/commands/source choice")
	check(not game.choose_bonus_route(1),label+": confirmation rejects")
	check(state()==before and plain(selected_route())==selected,label+": rejected confirmation does not change source or payout")

func options_case() -> void:
	if not await ready_primary():return
	var items: Array[Dictionary]=choice_pool(); var before: Dictionary=periphery(); var rows: Array[Dictionary]=routes()
	check(rows.size()==3 and int(selected_route().index)==0,"Default route remains the genuinely nearest crystal")
	var crystal: Dictionary=route_at(0); var cache: Dictionary=route_at(1)
	check(int(crystal.scrap)==16 and int(cache.scrap)==31 and float(crystal.distance)<float(cache.distance),"Real short crystal16 and longer cache31 preserve original reward tradeoff")
	check(is_zero_approx(float(crystal.budget.action_seconds)) and is_equal_approx(float(cache.budget.action_seconds),3.0),"Only the ready cache includes the real full three-second opening work")
	for _read in 40:
		routes(); game.contracts.return_budget(); game.contracts.bonus_summary()
	check(periphery()==before,"Repeated route/budget reads leave wallet, all five RNG streams, sources, clocks and commands unchanged")
	evidence.options.append({"tag":"short-crystal-long-cache","rows":plain(rows)})
	pool([{"kind":"memory_crystal","position":Vector3(4,0,33)},{"kind":"memory_crystal","position":Vector3(6,0,33)},{"kind":"supply_cache","position":Vector3(12,0,35)},{"kind":"ember_bloom","position":Vector3(-14,0,36)}])
	rows=routes(); var kinds: Array[String]=[]
	for row: Dictionary in rows:kinds.append(String(row.kind))
	check(rows.size()==3 and int(rows[0].index)==0 and kinds.has("supply_cache") and kinds.has("ember_bloom"),"Nearest default is retained while available different categories take priority over a second crystal")
	pool([{"kind":"memory_crystal","position":Vector3(4,0,33)},{"kind":"memory_crystal","position":Vector3(6,0,33)},{"kind":"memory_crystal","position":Vector3(8,0,33)}])
	check(routes().size()==3,"Same-category alternatives remain real choices when no diversity exists")
	pool([{"kind":"waylight","position":Vector3(4,0,33)}]); rows=routes()
	check(rows.size()==1 and bool(rows[0].selected) and int(rows[0].scrap)==16,"Exactly one real candidate remains usable without manufactured choices")
	pool([]); check(routes().is_empty(),"No ready reachable source produces no bonus route")
	var unchanged: Dictionary=state(); check(not game.choose_bonus_route(1) and state()==unchanged,"No-candidate confirmation cannot invent a target or reward")
	check(game.choose_bonus_route(0) and game.contracts.status=="returning","Zero-candidate day still permits actual primary return")
	stage_returned=true

func input_case() -> void:
	if not await ready_primary():return
	var items: Array[Dictionary]=choice_pool(); await open_contract()
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport; await redraw()
		var slot: int=route_slot(1,int(items[1].serial)); check(slot>=0,"Actual cached HUD contains the real far cache")
		if slot<0:return
		var before: Dictionary=periphery(); await click_ui(game.hud.bonus_route_rect(slot))
		check(int(selected_route().index)==1 and game.contracts.status=="bonus_offer" and periphery()==before,"Real left press/release selects the far cache without world drag, payment, clock or order changes at "+str(viewport))
		await redraw(); var chosen: Dictionary=plain(selected_route()); before=periphery()
		await click_ui(game.hud.bonus_route_rect(0),MOUSE_BUTTON_RIGHT)
		await click_ui(CONFIRM_RECT,MOUSE_BUTTON_RIGHT); await click_ui(RETURN_RECT,MOUSE_BUTTON_RIGHT)
		check(periphery()==before and plain(selected_route())==chosen and game.contracts.status=="bonus_offer","Real right presses/releases on every route action are swallowed at "+str(viewport))
	await press(KEY_5)
	check(game.contracts.status=="bonus_active" and int(game.contracts.bonus_target.index)==1 and int(game.contracts.bonus_target.serial)==int(items[1].serial),"Actual5 confirms the selected far source instead of the nearest crystal")
	var locked: Dictionary=state(); await press(KEY_5); await press(KEY_5)
	check(state()==locked,"Repeated5 after confirmation cannot switch source, spend or duplicate payout")
	check(not game.select_bonus_route(0,int(items[0].serial)) and state()==locked,"Confirmed route cannot be changed through the public action")
	await close_drawer(); await press(KEY_P)
	check(not game.hero_path.is_empty() and planar(game.move_goal,items[1].position)<.01,"ActualP plans the original selected far target")
	evidence.input.append({"target":plain(game.contracts.bonus_target),"viewports":VIEWPORTS})
	if not await ready_primary():return
	choice_pool(); await open_contract(); var before_return: int=game.scrap
	await click_ui(RETURN_RECT)
	check(game.contracts.status=="returning" and game.contracts.bonus_choice=="return" and game.scrap==before_return,"Actual return button preserves primary-only choice without immediate payout")
	stage_returned=true

func identity_case() -> void:
	if not await ready_primary():return
	var items: Array[Dictionary]=choice_pool(); var serial: int=int(items[1].serial)
	check(game.select_bonus_route(1,serial),"Public selection accepts authoritative far cache")
	stand(items[0].position); var rows: Array[Dictionary]=routes()
	check(int(selected_route().index)==1 and bool(selected_route().available) and not route_at(1,serial).is_empty(),"Moving closer to the crystal and reordering keeps the explicitly selected cache")
	for label: String in ["serial","kind","state","channel","active","distance","replacement"]:
		if not await ready_primary():return
		items=choice_pool(); serial=int(items[1].serial); check(game.select_bonus_route(1,serial),"Select original source before "+label)
		await open_contract(); var slot: int=route_slot(1,serial); var old_card: Dictionary=game.hud.bonus_route_budgets[slot].duplicate(false)
		match label:
			"serial":items[1].serial+=1
			"kind":items[1].kind="waylight"
			"state":items[1].state="cooling"
			"channel":items[1].state="channel"
			"active":items[1].state="active"
			"distance":
				items[1].position=Vector3(90,0,80); items[1].position.y=game.outpost_height(items[1].position); items[1].node.position=items[1].position
			"replacement":game.discoveries.items[1]=items[1].duplicate(false)
		game.discoveries.motivation_revision+=1; game.contracts.clear_budget_cache(); rows=routes()
		var chosen: Dictionary=selected_route()
		check(not chosen.is_empty() and int(chosen.index)==1 and int(chosen.serial)==serial and String(chosen.kind)=="supply_cache" and not bool(chosen.available),label+": selected old identity remains visibly unavailable without adopting the replacement")
		var before_gui: Dictionary=state(); await click_ui(game.hud.bonus_route_rect(slot))
		check(state()==before_gui and not bool(selected_route().available),label+": actual stale cached GUI card rejects without replacing the chosen source")
		assert_rejected(1,serial,label,old_card)
		evidence.identity.append({"reason":label,"old_serial":serial,"rows":plain(rows)})
	if not await ready_primary():return
	items=choice_pool(); serial=int(items[1].serial); check(game.select_bonus_route(1,serial),"Select source before actual node release")
	var token: int=items[1].node.get_instance_id(); items[1].node.queue_free(); await process_frame
	check(not is_instance_id_valid(token),"Actual selected discovery node is released")
	var invalid: Dictionary=selected_route()
	check(not invalid.is_empty() and not bool(invalid.available),"Released source remains selected and unavailable")
	assert_rejected(1,serial,"released node")
	stage_returned=true

func walk_route(point: Vector3, natural: bool=false, max_seconds: float=80.0) -> bool:
	await close_drawer(); await press(KEY_P)
	check(not game.hero_path.is_empty() or planar(game.hero.position,point)<.2,"ActualP produces a route to the active bonus/home target")
	var traveled := 0.0; var crossings := 0; var stopped := 0
	while planar(game.hero.position,point)>.2 and traveled<max_seconds and game.phase=="day" and game.hero.alive:
		var before: Vector3=game.hero.position; var speed: float=game.hero.speed
		if natural:natural_tick()
		else:game.simulate(STEP)
		traveled+=STEP
		check(game.can_traverse(before,game.hero.position) and game.outpost_walkable(game.hero.position) and absf(game.hero.position.y-game.outpost_height(game.hero.position))<.001 and planar(before,game.hero.position)<=maxf(speed,game.hero.speed)*STEP+.002,"RealP movement stays grounded, speed-bounded and does not cross a wall")
		if (before.z<Layout.WALL_CENTER and game.hero.position.z>=Layout.WALL_CENTER) or (before.z>Layout.WALL_CENTER and game.hero.position.z<=Layout.WALL_CENTER):
			var ratio: float=(Layout.WALL_CENTER-before.z)/(game.hero.position.z-before.z)
			var crossing_x: float=lerpf(before.x,game.hero.position.x,ratio)
			if absf(crossing_x)<=Layout.FORT_OUTER:check(absf(crossing_x)<Layout.GATE_HALF,"RealP traverses the authored wall only through the true south gate"); crossings+=1
		stopped=stopped+1 if before.distance_squared_to(game.hero.position)<.000001 else 0
		if stopped>30:break
		if int(traveled*10)%100==0:await process_frame
	evidence.path.append({"natural":natural,"point":point,"elapsed":traveled,"crossings":crossings,"arrived":planar(game.hero.position,point)<=.2,"phase":game.phase})
	return planar(game.hero.position,point)<=.2

func path_case() -> void:
	if not await ready_primary():return
	stand(Vector3(Layout.FORT_TERRAIN_EDGE+.9,0,-6))
	var items: Array[Dictionary]=pool([{"kind":"memory_crystal","position":Vector3(Layout.FORT_TERRAIN_EDGE+1.4,0,-4)},{"kind":"supply_cache","position":Vector3(Layout.FORT_TERRAIN_EDGE+1.4,0,-6)}])
	var geometry: Array[Dictionary]=[]
	for item: Dictionary in items:geometry.append({"position":item.position,"walkable":game.outpost_walkable(item.position),"outbound":game.contracts.route_distance(game.hero.position,item.position),"homeward":game.contracts.route_distance(item.position,ROUTE_HOME),"straight_homeward":planar(item.position,ROUTE_HOME)})
	var rows: Array[Dictionary]=routes(); var cache: Dictionary=route_at(1)
	evidence.path.append({"tag":"authoritative-wall-budget","hero":game.hero.position,"geometry":geometry,"rows":plain(rows)})
	check(not cache.is_empty(),"The actual same-side exterior cache is walkable and within58 true route metres: "+str(geometry))
	if cache.is_empty():return
	check(float(cache.budget.return_distance)>planar(items[1].position,ROUTE_HOME)*1.5,"Real exterior return budget accounts for the fortress walls and south ramp")
	check(game.select_bonus_route(1,int(items[1].serial)) and game.choose_bonus_route(1),"Same-side exterior route with long south-gate return can be explicitly accepted")
	check(await walk_route(items[1].position),"Accepted actual exterior source is reached by production movement")
	if not await ready_primary():return
	stand(HOME); items=pool([{"kind":"memory_crystal","position":BARRACKS},{"kind":"supply_cache","position":Vector3(-18,0,33)}])
	check(game.select_bonus_route(0,int(items[0].serial)),"Pre-build real source is selectable on free castle cells")
	var barracks: int=await build_gui("barracks",BARRACKS)
	check(barracks>=0 and not game.outpost_walkable(items[0].position),"Real paid barracks construction blocks the selected source and refreshes navigation")
	var chosen: Dictionary=selected_route(); check(not chosen.is_empty() and not bool(chosen.available),"Dynamic building obstruction retains selected source as unavailable")
	assert_rejected(0,int(items[0].serial),"dynamic source obstruction")
	check(game.sell_structure_at(game.districts.plots[barracks].position),"Actual sale retires the obstructing paid building")
	chosen=selected_route(); check(bool(chosen.available) and int(chosen.index)==0,"Navigation reopening restores the same real source instead of changing route")
	check(game.choose_bonus_route(1),"The original reopened source can be confirmed")
	stage_returned=true

func deliver(kind: String, dusk: bool=false) -> void:
	if not await ready_primary():return
	var items: Array[Dictionary]=pool([{"kind":"memory_crystal","position":Vector3(5,0,33)},{"kind":kind,"position":Vector3(-12,0,44)}])
	var primary: int=int(game.contracts.selected_reward.scrap); var extra: int=int(game.contracts.BONUS_PAYOUTS[kind].scrap)
	check(game.select_bonus_route(1,int(items[1].serial)) and game.choose_bonus_route(1),"Actual selected "+kind+" confirms the original source")
	check(await walk_route(items[1].position),"RealP reaches selected "+kind)
	var balance: int=game.scrap; var count: int=game.exploration_count; var previous_source_rng: int=game.discoveries.rng.state
	await press(KEY_F)
	if kind=="supply_cache":
		check(items[1].state=="channel" and game.scrap==balance and game.exploration_count==count,"ActualF starts cache work without paying ordinary or contract rewards")
		game.simulate(2.99)
		check(items[1].state=="channel" and game.scrap==balance and game.exploration_count==count and not game.contracts.bonus_done,"Full original three seconds are required before cache completion")
		game.simulate(.011)
	check(game.contracts.status=="returning" and game.contracts.bonus_done and game.exploration_count==count+1,"Only real selected discovery completion changes P guidance to home")
	var field_income: int=game.scrap-balance
	check(field_income>=(46 if kind=="supply_cache" else 12) and game.discoveries.rng.state!=previous_source_rng,"Ordinary real source income and renewal RNG occur at field completion")
	var direct_before: Dictionary=state()
	check(not game.discoveries.interact_index(1) and state()==direct_before,"A direct repeated interaction with the exact consumed source cannot duplicate its field reward")
	var prompt: String=game.interaction_prompt(); var before_repeat: int=game.scrap; var observed_start: int=game.observed_exploration_payments.size()
	await press(KEY_F)
	var selected_receipts := 0
	for payment: Dictionary in game.observed_exploration_payments:
		if String(payment.category)==kind and planar(payment.position,items[1].position)<.001:selected_receipts+=1
	check(selected_receipts==1 and items[1].state=="cooling" and game.contracts.bonus_done,"Actual repeatedF may execute another legal nearby action but cannot recollect the same selected discovery")
	evidence.ledger.append({"tag":"repeated-F-other-action","kind":kind,"prompt":prompt,"before":before_repeat,"after":game.scrap,"selected_receipts":selected_receipts,"new_receipts":plain(game.observed_exploration_payments.slice(observed_start)),"state":plain(state())})
	var before_home: int=game.scrap
	if dusk:
		game.phase_time=.01; game.simulate(.02)
		check(game.phase=="night" and game.contracts.status=="completed" and game.scrap==before_home+primary,"Actual dusk pays completed primary guarantee once and abandons the additional return award")
	else:
		check(await walk_route(ROUTE_HOME),"RealP returns through south ramp to actual raised-ground home")
		var payments: Array=game.observed_contract_payments
		check(game.contracts.status=="completed" and game.contracts.pending_reward.is_empty() and payments.size()==1 and int(payments[0].delta)==primary+10+extra,"True early home return settles primary, original ten-part early reward and only the selected extra once")
		check(int(payments[0].after)-int(payments[0].before)==int(payments[0].request.scrap),"The actual wallet change at settlement exactly equals the authoritative selected contract request")
	var paid: int=game.scrap
	for _repeat in 20:game.update_day_contracts(.0); game.settle_contract_reward()
	check(game.scrap==paid,"Repeated real ledger polling never duplicates an already earned delivery")
	evidence.ledger.append({"kind":kind,"dusk":dusk,"primary":primary,"extra":extra,"field_income":field_income,"field_wallet":before_home,"final_wallet":paid,"payments":game.observed_contract_payments.duplicate(true),"target":plain(game.contracts.bonus_target)})

func ledger_case() -> void:
	await deliver("memory_crystal"); await deliver("supply_cache"); await deliver("supply_cache",true)
	stage_returned=true

func lifecycle_case() -> void:
	if not await ready_primary():return
	var items: Array[Dictionary]=choice_pool(); check(game.select_bonus_route(1,int(items[1].serial)),"Original selection starts lifecycle checks")
	await close_drawer(); await press(KEY_ESCAPE)
	check(game.phase=="paused" and game.paused_from=="day","ActualEscape pauses the live daylight")
	var frozen: Dictionary=state(); var before: Dictionary=plain(selected_route())
	game.simulate(2.0); await open_contract(); await click_ui(CONFIRM_RECT); await click_ui(RETURN_RECT); await click_ui(game.hud.bonus_route_rect(0)); await press(KEY_5); await press(KEY_4)
	check(state()==frozen and plain(selected_route())==before,"Actual paused keys/buttons and simulation preserve clock, selected source, wallet/RNG/commands")
	assert_rejected(1,int(items[1].serial),"paused")
	check(not game.contracts.choose_bonus(0) and state()==frozen,"Direct module4 is also guarded during pause")
	await close_drawer(); await press(KEY_ESCAPE); check(game.phase=="day","ActualEscape resumes original daylight")
	for label: String in ["draft","night","ended","zero-time","hero-dead","core-dead","quitting","restart"]:
		var old_phase: String=game.phase; var old_time: float=game.phase_time; var old_alive: bool=game.hero.alive; var old_hp: float=game.beacon_hp
		if label in ["draft","night","ended"]:game.phase=label
		elif label=="zero-time":game.phase_time=0.0
		elif label=="hero-dead":game.hero.alive=false
		elif label=="core-dead":game.beacon_hp=0.0
		elif label=="quitting":game.quitting=true
		elif label=="restart":game.restart_pending=true
		var rejected: Dictionary=state(); assert_rejected(1,int(items[1].serial),label)
		check(not game.choose_bonus_route(0) and not game.contracts.choose_bonus(0) and state()==rejected,label+": both direct and root primary-return actions reject without settlement")
		game.phase=old_phase; game.phase_time=old_time; game.hero.alive=old_alive; game.beacon_hp=old_hp; game.quitting=false; game.restart_pending=false
	game.contracts.setup(game,SEED)
	check(game.contracts.bonus_target.is_empty() and game.contracts.bonus_route_options().is_empty(),"Actual module setup retires selected and confirmed sources")
	game.contracts.on_day(); check(game.contracts.status=="active","Fresh setup generates a new legitimate main contract")
	if not await ready_primary():return
	items=choice_pool(); check(game.select_bonus_route(1,int(items[1].serial)) and game.choose_bonus_route(1),"Real retry fixture confirms a live source")
	var old_root: int=game.get_instance_id(); game.end_defeat("Explicit retry boundary"); await press(KEY_ENTER)
	for _frame in 240:
		if current_scene!=null and current_scene.get_instance_id()!=old_root:break
		await create_timer(.02,true,false,true).timeout
	check(current_scene!=null and current_scene.get_instance_id()!=old_root,"ActualEnter creates a fresh same-seed root")
	if current_scene==null or current_scene.get_instance_id()==old_root:return
	game=current_scene as Node3D; game.set_process(false); game.world.set_process(false)
	for _frame in 5:await process_frame
	check(not is_instance_id_valid(old_root) and game.run.seed_value==SEED and game.phase=="draft" and game.scrap==90 and game.contracts.bonus_target.is_empty() and game.contracts.bonus_route_options().is_empty(),"Actual retry releases old actors and selected route identity without changing original opening")
	evidence.lifecycle.append({"retry_seed":game.run.seed_value,"parts":game.scrap,"phase":game.phase})
	stage_returned=true

func measure_routes(tag: String) -> void:
	var before: Dictionary=state(); var viewport_before: Vector2i=root.size
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport; await redraw()
		var row_counts: Array[int]=[0,0,0]; var bottom := 0.0
		for row: Dictionary in game.hud.drawn_labels:
			check(row.point.x>=0 and row.point.x+float(row.width)<=1440 and row.point.y-float(row.ascent)>=0 and row.point.y+float(row.descent)<=900,"Actual complete glyph bounds fit viewport in "+tag+": "+String(row.text))
			for character: String in String(row.text):
				var code: int=character.unicode_at(0)
				if code>=0x4e00 and code<=0x9fff:check(game.hud.font.has_char(code),"Actual Chinese font includes "+character)
		for row: Dictionary in game.hud.drawer_labels:
			if row.point.x>=46 and row.point.x<542 and row.point.y<692:
				bottom=maxf(bottom,float(row.point.y)+float(row.descent)); check(row.point.x+float(row.width)<=542 and row.point.y+float(row.descent)<=692,"Full actual contract text fits496px and stays above the original footer")
			for slot in mini(3,game.hud.bonus_route_budgets.size()):
				var rect: Rect2=game.hud.bonus_route_rect(slot)
				if rect.has_point(row.point):
					row_counts[slot]+=1
					check(row.point.y-float(row.ascent)>=rect.position.y and row.point.y+float(row.descent)<=rect.end.y and row.point.x+float(row.width)<=rect.end.x,"Every complete route-card line fits its actual82px control")
		if game.contracts.status=="bonus_offer":
			check(RETURN_RECT in game.hud.drawn_rects and CONFIRM_RECT in game.hud.drawn_rects,"Actual decision page contains separated primary-return and selected-confirm controls")
			for slot in game.hud.bonus_route_budgets.size():
				var row: Dictionary=game.hud.bonus_route_budgets[slot]
				check(row_counts[slot]==(4 if bool(row.budget.available) else 3),"Actual route card draws its complete reward/base-income and valid timing or invalid-source explanation")
		check(CLOSE_RECT in game.hud.drawn_rects and bottom<692,"Route details leave the original close/footer clear")
		for delta: int in game.hud.draw_queries:check(delta==0,"Real draw reads cached budgets without A* queries")
		evidence.hud.append({"tag":tag,"viewport":viewport,"rows":row_counts,"bottom":bottom,"routes":plain(game.hud.bonus_route_budgets)})
	check(state()==before,"Three-viewport drawing never moves, changes sources/orders, spends or advances RNG/clocks")
	root.size=viewport_before; root.content_scale_size=viewport_before; await redraw()

func hud_case() -> void:
	if not await ready_primary():return
	var items: Array[Dictionary]=choice_pool(); await open_contract()
	await measure_routes("three-default"); await capture("three-default")
	var cached: Array=game.hud.bonus_route_budgets.duplicate(false); var previous_speed: float=game.hero.speed
	game.hero.speed=previous_speed+2.4; game.hud.queue_redraw()
	for _frame in 3:await process_frame
	for cached_slot in cached.size():
		var value: Dictionary=cached[cached_slot].budget; var speed: float=maxf(1.0,float(value.speed))
		var expected: String="去程%.0f米/%.0f秒 · 回程%.0f米/%.0f秒 · 行动%.0f秒" % [float(value.outbound_distance),ceilf(float(value.outbound_distance)/speed),float(value.return_distance),ceilf(float(value.return_distance)/speed),ceilf(float(value.action_seconds))]
		var found := false
		for row: Dictionary in game.hud.drawn_labels:
			if row.point==game.hud.bonus_route_rect(cached_slot).position+Vector2(12,58):found=String(row.text)==expected
		check(found,"Unrefreshed cached budget draws its own original speed consistently instead of mixing live speed")
	await redraw()
	for row: Dictionary in game.hud.bonus_route_budgets:check(is_equal_approx(float(row.budget.speed),game.hero.speed),"Explicit production cache refresh reads the live speed for the complete new estimate")
	game.hero.speed=previous_speed; await redraw()
	var slot: int=route_slot(1,int(items[1].serial)); await click_ui(game.hud.bonus_route_rect(slot)); await redraw()
	await measure_routes("far-cache-selected"); await capture("far-cache-selected")
	game.phase_time=8.0; await redraw(); await measure_routes("late-budget"); await capture("late-budget")
	game.phase_time=10000.0; items[1].serial+=1; game.discoveries.motivation_revision+=1; await redraw()
	await measure_routes("selected-stale"); await capture("selected-stale")
	if not await ready_primary():return
	pool([]); await open_contract(); await measure_routes("no-candidates"); await capture("no-candidates")
	if not await ready_primary():return
	pool([{"kind":"memory_crystal","position":Vector3(5,0,33)}]); await open_contract(); await measure_routes("single-candidate"); await capture("single-candidate")
	await close_drawer(); await press(KEY_ESCAPE); await open_contract(); await measure_routes("paused-view-only")
	await close_drawer(); await press(KEY_ESCAPE); check(game.phase=="day","Actual paused route observation resumes without changing controls")
	await close_drawer(); clear_transients(); await redraw(); var base: Array=game.hud.visible_hud_rects().duplicate(); var boxes: Array=game.hud.drawn_rects.duplicate()
	await open_contract(); await close_drawer(); clear_transients(); await redraw()
	check(game.hud.visible_hud_rects()==base and game.hud.drawn_rects==boxes,"Closed route drawer adds no default permanent HUD area")
	stage_returned=true

func natural_tick() -> void:
	game.aim=game.hero.position+Vector3(0,0,8)
	if game.gate_pressure()>0:game.cast(0)
	if game.hero.hp<game.hero.max_hp*.6:game.cast(1); game.cast(4)
	if game.gate_pressure()>=6:game.cast(3)
	var before: Vector3=game.hero.position; var speed: float=game.hero.speed
	game.simulate(STEP); elapsed+=STEP
	check(game.hero.position.is_finite() and game.outpost_walkable(game.hero.position) and absf(game.hero.position.y-game.outpost_height(game.hero.position))<.001 and game.can_traverse(before,game.hero.position) and planar(before,game.hero.position)<=maxf(speed,game.hero.speed)*STEP+.002,"Natural actual hero steps remain finite, grounded and speed-bounded")
	if (before.z<Layout.WALL_CENTER and game.hero.position.z>=Layout.WALL_CENTER) or (before.z>Layout.WALL_CENTER and game.hero.position.z<=Layout.WALL_CENTER):
		var ratio: float=(Layout.WALL_CENTER-before.z)/(game.hero.position.z-before.z); var x: float=lerpf(before.x,game.hero.position.x,ratio)
		if absf(x)<=Layout.FORT_OUTER:check(absf(x)<Layout.GATE_HALF,"Native natural wall crossing uses the real south gate")
		if absf(x)<Layout.GATE_HALF:natural_gate_crossings.append({"day_second":90.0-game.phase_time,"x":x,"from":before,"to":game.hero.position})

func walk_natural_primary(point: Vector3) -> bool:
	await close_drawer(); await press(KEY_P)
	for frame in 900:
		if game.phase!="day" or not game.hero.alive:return false
		if planar(game.hero.position,point)<.2:return true
		natural_tick()
		if frame%100==99:await process_frame
	return false

func natural_route(longer: bool) -> void:
	await fresh(false); await right(Vector3(0,5,10)); natural_gate_crossings.clear()
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
	check(game.phase=="draft" and game.hero.alive and game.beacon_hp>0,"Original90/105 skill policy reaches genuine first dawn")
	if game.phase!="draft":return
	var dawn_parts: int=game.scrap; var kills: int=game.kills; await press(KEY_1)
	check(game.phase=="day" and game.phase_time==90.0 and game.scrap==dawn_parts,"Actual first dawn retains90 seconds and earned wallet")
	natural_sources.clear(); natural_primary.clear()
	for item: Dictionary in game.discoveries.items:natural_sources.append({"index":natural_sources.size(),"position":item.position,"kind":item.kind,"serial":item.serial,"node":item.node.get_instance_id()})
	var chosen := -1
	for index in game.contracts.offers.size():
		if String(game.contracts.offers[index].kind)=="salvage":chosen=index; break
	if chosen<0:
		evidence.economy.append({"longer":longer,"seed":SEED,"dawn_parts":dawn_parts,"kills":kills,"completed_primary":false,"reason":"Original seeded day has no offered salvage route; no target, seed or clock was changed","offers":plain(game.contracts.offers)})
		check(false,"Original seed must expose a real salvage primary for this bounded natural route; report actual offers instead of fabricating completion")
		return
	await press(KEY_4+chosen)
	for target: Dictionary in game.contracts.targets.duplicate():
		var original: Vector3=target.source.position; natural_primary.append({"index":target.index,"position":original,"collected":target.source.collected})
		check(await walk_natural_primary(original),"Native90-second realP reaches the original primary salvage source")
		if game.phase!="day" or not game.hero.alive:return
		await press(KEY_F); check(bool(target.source.collected) and target.source.position==original,"Natural realF completes unchanged authoritative primary source")
	check(game.contracts.status=="bonus_offer","Natural real primary field work reaches the route-choice decision")
	if game.contracts.status!="bonus_offer":return
	var primary_completed_at: float=90.0-game.phase_time
	var approach: Array[Dictionary]=[]; var rows: Array[Dictionary]=routes(); var has_tradeoff := false
	# Both branches perform the identical legitimate approach to home before
	# deciding. Ready sources remain in their seeded positions; no fourth
	# candidate is injected into the three-card production shortlist.
	await close_drawer(); await press(KEY_P)
	check(not game.hero_path.is_empty(),"Natural preliminary P begins a real homeward route while bonus choice remains open")
	approach.append({"action":"P toward actual home","time":game.phase_time,"position":game.hero.position,"goal":game.move_goal})
	for frame in 150:
		rows=routes(); var cache_route: Dictionary={}; var short_route: Dictionary={}
		for row: Dictionary in rows:
			if String(row.kind)=="supply_cache" and bool(row.available):cache_route=row
		if not cache_route.is_empty():
			for row: Dictionary in rows:
				if int(row.scrap)<int(cache_route.scrap) and float(row.distance)<float(cache_route.distance) and bool(row.available):short_route=row; break
		has_tradeoff=not short_route.is_empty()
		if has_tradeoff or game.phase!="day" or not game.hero.alive:break
		natural_tick()
		if frame%50==49:await process_frame
	var stop: Vector3=game.hero.position; var stopped_at: float=game.phase_time; var sampled: Vector3=await right(stop)
	check(planar(sampled,stop)<.05 and planar(game.move_goal,sampled)<.05,"Natural real right click at the current traversable position stops the shared homeward approach without relocating the hero")
	approach.append({"action":"actual right click current position","time":stopped_at,"position":stop,"sampled":sampled,"goal":game.move_goal})
	rows=routes(); check(rows.size()>=2,"Native completed primary exposes at least two real bonus routes")
	if rows.size()<2:return
	var route: Dictionary=rows[0]
	var cache_route: Dictionary={}
	for row: Dictionary in rows:
		if String(row.kind)=="supply_cache" and bool(row.available):cache_route=row
	if has_tradeoff and not cache_route.is_empty():
		if longer:route=cache_route
		else:
			for row: Dictionary in rows:
				if int(row.scrap)<int(cache_route.scrap) and float(row.distance)<float(cache_route.distance) and bool(row.available):route=row; break
	elif longer:
		for row: Dictionary in rows:
			if float(row.distance)>float(route.distance) and int(row.scrap)>=int(route.scrap):route=row
		if int(route.index)==int(rows[0].index):route=rows[1]
	var original_source: Dictionary=game.discoveries.items[int(route.index)]; var original_position: Vector3=original_source.position
	var decision_at: float=90.0-game.phase_time; var before_choice: Dictionary=periphery()
	await open_contract(); var slot: int=route_slot(int(route.index),int(route.serial)); check(slot>=0,"Natural cached drawer contains the actual chosen candidate")
	if slot<0:return
	await click_ui(game.hud.bonus_route_rect(slot)); await redraw()
	var selected_before_capture: Dictionary=plain(selected_route())
	await capture("natural-longer" if longer else "natural-nearest")
	check(periphery()==before_choice and plain(selected_route())==selected_before_capture,"Natural decision screenshot preserves original84-second clock, exact selected source, earned wallet/RNG and world commands")
	await press(KEY_5)
	check(game.contracts.status=="bonus_active" and int(game.contracts.bonus_target.index)==int(route.index) and periphery()==before_choice,"Natural actualGUI/5 binds the chosen source without payment, RNG or clock changes")
	var primary_reward: int=int(game.contracts.selected_reward.scrap); var before_field: int=game.scrap
	var exploration_start: int=game.observed_exploration_payments.size()
	var reached: bool=await walk_route(original_position,true)
	if reached:
		check(original_source.position==original_position and original_source.node.position==original_position and int(original_source.serial)==int(route.serial),"Natural chosen source retains its original generation and world/model position")
		await press(KEY_F)
		while game.phase=="day" and original_source.state=="channel":natural_tick()
	var completed_field: bool=game.contracts.bonus_done; var after_field: int=game.scrap; var returned := false
	var discoveries: Array[Dictionary]=[]; var field_income := 0
	for index in range(exploration_start,game.observed_exploration_payments.size()):
		var payment: Dictionary=game.observed_exploration_payments[index]; discoveries.append(payment); field_income+=int(payment.delta)
	if completed_field:
		check(discoveries.size()==1 and int(discoveries[0].base)==(46 if String(route.kind)=="supply_cache" else 0 if String(route.kind)=="waylight" else 12) and int(discoveries[0].count_after)==int(discoveries[0].count_before)+1,"Natural real discovery observer records the selected source's unchanged base income and one genuine completion")
	if game.phase=="day" and completed_field:returned=await walk_route(ROUTE_HOME,true)
	while game.phase=="day" and game.contracts.status!="completed":natural_tick()
	var payments: Array=game.observed_contract_payments.duplicate(true); var contract_income := 0
	for payment: Dictionary in payments:contract_income+=int(payment.delta)
	check(payments.size()==1,"Natural route settles exactly one authoritative contract payment")
	if returned:
		var payment: Dictionary=payments[0]
		check(contract_income==primary_reward+int(route.scrap)+(10 if float(payment.time)>=game.contracts.EARLY_RETURN_SECONDS else 0),"Natural real return receives exactly selected contract rewards separately from field/combat income")
	else:check(game.contracts.status=="completed" and contract_income==primary_reward,"Native dusk retains only completed primary when the attempted bonus cannot return in time")
	evidence.economy.append({"longer":longer,"seed":SEED,"opening":90,"night_seconds":105,"day_seconds":90,"kills":kills,"dawn_parts":dawn_parts,"primary":natural_primary.duplicate(true),"original_sources":natural_sources.duplicate(true),"primary_completed_day_second":primary_completed_at,"shared_approach_actions":approach,"higher_reward_longer_cache_comparison":has_tradeoff,"decision_day_second":decision_at,"options":plain(rows),"selected":plain(route),"reached_source":reached,"completed_field":completed_field,"returned_home":returned,"before_field":before_field,"after_field":after_field,"field_income":field_income,"field_payments":discoveries,"other_outbound_income":after_field-before_field-field_income,"contract_income":contract_income,"contract_payments":payments,"other_return_income":game.scrap-after_field-contract_income,"primary_reward":primary_reward,"final_parts":game.scrap,"remaining":game.phase_time,"phase":game.phase,"hero_hp":game.hero.hp,"beacon_hp":game.beacon_hp,"gate_crossings":natural_gate_crossings.duplicate(true),"scope":"fixed original seed90/105/90; genuine primary/P/F/GUI route only; no funding, source/actor placement, enemy deletion/stats/clock changes; not human or campaign balance"})
	print("BONUS_ROUTE_NATURAL longer=",longer," decision=",decision_at," selected=",route.kind," distance=",route.distance," extra=",route.scrap," returned=",returned," parts=",game.scrap," phase=",game.phase)

func economy_case() -> void:
	await natural_route(false); await natural_route(true)
	stage_returned=true

func capture(tag: String) -> void:
	var first: int=evidence.captures.size(); var selected: Dictionary=plain(selected_route()); await super.capture(tag)
	check(plain(selected_route())==selected,"Actual capture preserves the precise selected discovery identity")
	for index in range(first,evidence.captures.size()):
		var path: String=ProjectSettings.globalize_path(output_dir).path_join(String(evidence.captures[index])+".png"); var texture: Image=Image.load_from_file(path)
		check(texture!=null,"Capture loads its actual PNG before recording the receipt")
		if texture!=null:evidence.capture_receipt.append({"tag":tag,"path":path,"width":texture.get_width(),"height":texture.get_height(),"sha256":FileAccess.get_sha256(path)})

func finalize() -> void:
	await close_game(); await create_timer(.5,true,false,true).timeout; evidence.shutdown_audio_drain_seconds=.5
	check(not is_instance_valid(game) and current_scene==null,"Final bonus-route scene cleanup completes before the suite result")
	var folder: String=ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
	var file: FileAccess=FileAccess.open(folder.path_join("nightfall-bonus-route-choices.json"),FileAccess.WRITE)
	check(file!=null,"Route evidence opens below the local build directory")
	var receipt: FileAccess=FileAccess.open(folder.path_join("capture-receipt.json"),FileAccess.WRITE)
	check(receipt!=null,"Route capture manifest opens below local build")
	evidence.checks=checks; evidence.failures=failures
	if file!=null:file.store_string(JSON.stringify(evidence,"\t")); file.close()
	if receipt!=null:receipt.store_string(JSON.stringify({"captures":evidence.capture_receipt,"completed":evidence.completed,"checks":checks,"failures":failures},"\t")); receipt.close()

func run() -> void:
	var cases: Dictionary={"options":options_case,"input":input_case,"identity":identity_case,"path":path_case,"ledger":ledger_case,"lifecycle":lifecycle_case,"hud":hud_case,"economy":economy_case}
	var args: PackedStringArray=OS.get_cmdline_user_args(); var selected: Array=cases.keys(); var index: int=args.find("--case")
	if index>=0:
		if index+1<args.size():selected=[args[index+1]]
		else:check(false,"Missing bonus-route case after --case"); selected=[]
	for name: String in selected:
		if not cases.has(name):check(false,"Unknown bonus-route case "+name); break
		active_stage=name; stage_returned=false; print("BONUS_ROUTE_STAGE_BEGIN ",name)
		await (cases[name] as Callable).call()
		check(stage_returned,"Route stage "+name+" reaches its explicit full-body completion marker")
		print("BONUS_ROUTE_STAGE_END ",name," checks=",checks," failures=",failures.size()); evidence.completed.append(name)
		if not failures.is_empty():break
	if index<0:check((evidence.completed as Array)==cases.keys(),"The complete bonus-route suite finishes every expected stage")
	await finalize(); finished=true; print("BONUS_ROUTE_RESULT checks=",checks," failures=",failures.size())
	if index<0 and (evidence.completed as Array)==cases.keys() and failures.is_empty():print("NIGHTFALL_BONUS_ROUTE_CHOICES_OK checks=",checks)
	quit(0 if failures.is_empty() else 1)
