extends "res://tests/nightfall_haul_routes.gd"
## Artificial phase setup only; natural clearance and victory use real combat.
## Real construction input, paid receipts, stable identities and production lifetimes.
## Precision stages use5000 parts/extended clocks/direct hero positioning.
## Economy separately keeps the original90-part opening and original actors/clocks.

const LAB := Vector3(7,5,-3.5)
const ARMORY := Vector3(7,5,2.5)
const MEDICAL := Vector3(-7.5,5,2.5)
const FREE_TOWER := Vector3(7.5,5,3.5)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args(); render_test = "--render-test" in args
	output_dir = "res://build/demolition"
	var index := args.find("--output-dir")
	if index >= 0 and index+1 < args.size():
		var candidate := ProjectSettings.globalize_path(args[index+1]).simplify_path()
		var allowed := ProjectSettings.globalize_path("res://build").simplify_path()
		if candidate.begins_with(allowed+"/"): output_dir = candidate
		else: check(false,"Demolition evidence must remain below the project build directory")
	root.size = VIEWPORTS[0]; root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT; root.content_scale_size = VIEWPORTS[0]
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true); root.position = Vector2i(10000,10000); root.hide()
	evidence = {"seed":SEED,"scope":"precision5000/extended clocks/direct hero and enemy positions; economy original90 opening/original clocks; captures use controlled lighting; not human campaign balance","completed":[],"captures":[],"hud":[],"accounts":[],"identity":[],"recovery":[],"economy":[]}
	create_timer(300.0,true,false,true).timeout.connect(watchdog)
	call_deferred("run")

func state() -> Dictionary:
	var result := super.state(); var towers: Array[Dictionary] = []; var plots: Array[Dictionary] = []
	for index in game.world.tower_pads.size():
		var pad: Dictionary = game.world.tower_pads[index]
		var row: Dictionary = pad.duplicate(); row.erase("node"); row.erase("turret"); row.erase("label"); row.erase("damage_ring")
		towers.append(row)
	for plot: Dictionary in game.districts.plots:
		var row: Dictionary = plot.duplicate()
		for property: String in ["node","model","lamp","label"]: row.erase(property)
		plots.append(row)
	result.towers = towers; result.plots = plots
	result.active = game.construction.active; result.sell = game.construction.get("sell_mode")
	result.captured = game.districts._captured_scrap; result.recovery_nights = game.districts._begun_nights.duplicate()
	return result

func step(delta: float = STEP) -> void:
	game.simulate(delta); elapsed += delta
	ledger("Actual demolition-related production step")

func quote(point: Vector3) -> Dictionary:
	return game.demolition_at(point)

func begin_sell(point: Vector3) -> Dictionary:
	await close_drawer()
	if not game.construction.active: await press(KEY_Y)
	if not game.construction.sell_mode: await press(KEY_DELETE)
	await aim_at(point)
	var result: Dictionary = game.construction.snapshot()
	check(game.construction.active and game.construction.sell_mode,"Actual construction-only Delete activates demolition")
	return result

func finish_sell() -> void:
	if game.construction.active: await press(KEY_ESCAPE)
	check(not game.construction.active and not game.construction.sell_mode,"Actual Escape leaves demolition and construction")

func sell_gui(point: Vector3, use_f: bool = false) -> Dictionary:
	var preview := await begin_sell(point)
	check(bool(preview.valid),"Actual live demolition preview permits "+String(preview.get("title","building"))+": "+String(preview.get("reason","")))
	var balance: int = game.scrap
	if use_f: await press(KEY_F)
	else: await mouse(game.camera.unproject_position(point),true)
	check(game.scrap == balance+int(preview.refund)+int(preview.get("queue_refund",0)),"True demolition confirmation pays the quoted investment refund and independent prepaid queue refund exactly once")
	var once: int = game.scrap; await press(KEY_F)
	check(game.scrap == once and not bool(quote(point).valid),"Repeated actual F at a retired identity cannot pay again")
	await finish_sell()
	return preview

func tower_at(point: Vector3, include_removed: bool = false) -> int:
	for index in game.world.tower_pads.size():
		var pad: Dictionary = game.world.tower_pads[index]
		if planar(pad.position,point)<.01 and (include_removed or not bool(pad.get("removed",false))): return index
	return -1

func place_tower(point: Vector3) -> int:
	await close_drawer(); await select_building("tower"); await aim_at(point)
	var preview: Dictionary = game.construction.snapshot(); var balance: int = game.scrap
	check(bool(preview.valid),"Actual free-tower preview is valid: "+String(preview.reason))
	await mouse(game.camera.unproject_position(point),true); var index := tower_at(preview.point)
	check(index >= 0 and game.scrap == balance-int(preview.cost),"Actual tower input creates one paid snapped tower")
	await press(KEY_ESCAPE)
	return index

func paid_build_no_teleport(kind: String,point: Vector3) -> int:
	await select_building(kind); await aim_at(point)
	var preview: Dictionary = game.construction.snapshot(); var before: int = game.scrap
	check(bool(preview.valid),"Original-wallet construction preview is genuinely valid")
	await mouse(game.camera.unproject_position(point),true); await press(KEY_ESCAPE)
	var index := plot_at(kind,preview.point)
	check(index >= 0 and game.scrap == before-int(Catalog.building(kind).cost),"Original-wallet GUI pays the real building cost")
	return index

func released_cells(point: Vector3,kind: String) -> void:
	for cell: Vector2i in Grid.placement(point,kind).cells:
		var center := Grid.cell_rect(cell).get_center(); var world := Vector3(center.x,5,center.y)
		check(not game.construction.occupied_cells().has(cell) and game.outpost_walkable(world),"Retiring the real structure releases every occupied cell and its navigation")

func selection_input_and_full_footprint() -> void:
	await fresh(); var index := await build_gui("barracks",BARRACKS)
	var point: Vector3 = game.districts.plots[index].position
	var before := state(); await press(KEY_DELETE)
	check(state() == before,"Delete outside Y construction cannot enable demolition or change any world transaction")
	await press(KEY_BACKSPACE)
	check(state()==before,"Actual Mac physical Delete outside Y cannot enable demolition")
	await select_building("tower"); await aim_at(FREE_TOWER); await capture("ordinary-existing-construction-toolbar"); await finish_sell()
	var preview := await begin_sell(point)
	check(bool(preview.valid) and int(preview.investment)==60 and int(preview.refund)==30 and int(preview.queue_refund)==0,"Real paid barracks quote is exactly60 invested/30 refunded")
	check(preview.cells.size()==12 and preview.size==Vector2i(4,3),"Actual demolition highlights the complete4-by3 footprint")
	before = state()
	for cell: Vector2i in Grid.placement(point,"barracks").cells:
		var middle := Grid.cell_rect(cell).get_center(); var at := Vector3(middle.x,5,middle.y)
		var picked := quote(at)
		check(bool(picked.valid) and int(picked.target_index)==index and String(picked.target_type)=="district","Every real occupied cell picks the same full building identity")
	for _read in 30: quote(point); game.construction.snapshot(); game.districts.demolition_quote(index)
	check(state() == before,"Demolition quotes and previews are pure reads with no receipt/queue/RNG effects")
	check(not bool(quote(Vector3.INF).valid),"Non-finite points cannot be sold")
	for cell: Vector2i in Grid.placement(Vector3(0,5,0),"core").cells:
		var core_cell := Grid.cell_rect(cell).get_center()
		check(not bool(quote(Vector3(core_cell.x,5,core_cell.y)).valid),"Every real-height occupied core cell remains protected")
	var balance: int = game.scrap; await aim_at(Vector3(0,5,0)); await press(KEY_F)
	check(game.scrap==balance and game.beacon_hp==game.BEACON_MAX,"Real F in core demolition preview cannot retire or refund the core")
	await aim_at(point); await capture("full-barracks-demolition-preview")
	await mouse(game.camera.unproject_position(point),true,MOUSE_BUTTON_RIGHT)
	check(not game.construction.active and not game.construction.sell_mode and game.scrap==balance,"Actual right-click cancels the demolition tool without selling")
	await begin_sell(point); await press(KEY_Y)
	check(not game.construction.active and not game.construction.sell_mode,"Actual Y also exits demolition")
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport
		await begin_sell(point); await click_ui(game.hud.DEMOLITION_BUTTON_RECT)
		check(game.construction.active and not game.construction.sell_mode,"Actual existing-toolbar button toggles back to placement in every viewport")
		await click_ui(game.hud.DEMOLITION_BUTTON_RECT)
		check(game.construction.active and game.construction.sell_mode,"Actual existing-toolbar button explicitly enables demolition in every viewport")
		await press(KEY_BACKSPACE)
		check(game.construction.active and not game.construction.sell_mode,"Actual Mac physical Delete returns to building in every viewport")
		await press(KEY_BACKSPACE)
		check(game.construction.active and game.construction.sell_mode,"Actual Mac physical Delete explicitly re-enters demolition")
		await click_ui(game.hud.construction_kind_rect(0))
		check(game.construction.active and not game.construction.sell_mode,"Actual type choice returns to ordinary construction without retaining the destructive tool")
		await press(KEY_DELETE); await click_ui(game.hud.construction_page_rect(1))
		check(game.construction.active and not game.construction.sell_mode,"Actual page change also leaves demolition")
		await press(KEY_DELETE); await finish_sell()
		await press(KEY_Y)
		check(game.construction.active and not game.construction.sell_mode,"A new actual Y session starts ordinary placement after previous demolition")
		await finish_sell()
		# The ordinary Y notification can genuinely cover this former toolbar
		# location; expire it through the real controller before testing blank UI.
		game._process(4.0)
		check(game.notice_time<=0,"Actual transient construction notice expires before blank-region input")
		camera_at(HOME)
		var screen: Vector2=game.hud.DEMOLITION_BUTTON_RECT.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900)
		var old_goal: Vector3=game.move_goal
		await mouse(screen,true,MOUSE_BUTTON_RIGHT)
		check(game.move_goal!=old_goal and not game.hero_path.is_empty() and not game.construction.active,"After exiting the old toolbar area passes real right-click through to world navigation")
		stand(HOME)
	root.size=VIEWPORTS[0];root.content_scale_size=VIEWPORTS[0]
	await sell_gui(point,true)
	check(bool(game.districts.plots[index].removed),"True F creates a stable retired barracks tombstone")
	released_cells(point,"barracks")

func real_paid_accounts() -> void:
	await fresh()
	var gift: Dictionary = game.world.tower_pads[0]
	check(int(quote(gift.position).investment)==0 and int(quote(gift.position).refund)==0,"Original gifted tower has no paid build investment")
	await sell_gui(gift.position)
	await build_gui("workshop",WORKSHOP)
	var gift_index := 1; var pad: Dictionary = game.world.tower_pads[gift_index]
	stand(game.building_approach_position(HOME,pad.position,"tower")); camera_at(pad.position)
	var before: int = game.scrap; await press(KEY_F)
	check(int(pad.level)==2 and game.scrap==before-45,"True F applies the live workshop discount to gifted-tower upgrade")
	before=game.scrap; await press(KEY_J)
	check(game.scrap==before-45 and game.specializations.branch(pad)=="piercing","True J records the actual paid45 specialization")
	var expected := 90; check(int(quote(pad.position).investment)==expected and int(quote(pad.position).refund)==45,"Gifted tower refunds only its actual discounted upgrade plus specialization payments")
	game.damage_tower(gift_index,110); before=game.scrap; await press(KEY_H)
	check(game.scrap==before-18 and int(quote(pad.position).investment)==expected,"True discounted H repair pays18 without adding it to capital investment")
	game.damage_tower(gift_index,float(pad.hp)-1.0)
	check(int(quote(pad.position).refund)==45,"A genuinely one-HP tower retains the same capital refund independent of durability")
	stand(HOME); await sell_gui(pad.position)
	var created := await place_tower(FREE_TOWER)
	if created < 0: return
	pad=game.world.tower_pads[created]
	check(int(quote(pad.position).investment)==54 and int(quote(pad.position).refund)==27,"Free placement records actual discounted54 build payment")
	stand(game.building_approach_position(HOME,pad.position,"tower")); before=game.scrap; await press(KEY_F)
	check(game.scrap==before-45 and int(pad.level)==2,"Actual newly built tower upgrades for discounted45")
	before=game.scrap; await press(KEY_K)
	check(game.scrap==before-45,"Actual new tower specialization pays its independent45")
	before=game.scrap; await press(KEY_F)
	check(game.scrap==before-68 and int(pad.level)==3,"Actual third-level upgrade rounds discounted67.5 up to68")
	check(int(quote(pad.position).investment)==212 and int(quote(pad.position).refund)==106,"Actual receipt includes54+45+45+68 and refunds106")
	stand(HOME); await sell_gui(pad.position)
	await build_gui("barracks",BARRACKS); var plot_index := plot_at("barracks",BARRACKS)
	# A diagonal navigation approach may be farther than the2.6-metre F radius.
	# Use an actual walkable exposed face inside that unchanged interaction radius.
	stand(BARRACKS+Vector3(0,0,2.0)); before=game.scrap
	check(game.outpost_walkable(game.hero.position) and game.districts.nearest()==plot_index and game.nearest_tower_pad()<0,"District upgrade input genuinely selects the paid barracks from a walkable exposed face")
	await press(KEY_F)
	check(game.scrap==before-80 and game.districts.plots[plot_index].level==2,"Actual district upgrade pays its original80")
	game.districts.damage(plot_index,float(game.districts.plots[plot_index].hp)-1.0)
	check(int(quote(BARRACKS).investment)==140 and int(quote(BARRACKS).refund)==70,"Actual damaged upgraded district refunds half its paid140")
	stand(HOME); await begin_sell(BARRACKS); await capture("paid-investment-independent-of-one-hp"); await finish_sell(); await sell_gui(BARRACKS)
	(evidence.accounts as Array).append({"gift_paid":90,"gift_refund":45,"gift_repair_excluded":18,"free_paid":212,"free_refund":106,"district_paid":140,"district_refund":70})

func retired_indices_and_fresh_receipts() -> void:
	await fresh(); var index := await place_tower(FREE_TOWER)
	if index < 0: return
	var point: Vector3 = game.world.tower_pads[index].position; var original: Dictionary = game.world.tower_pads[index]
	var body_token: int = (original.turret as Node).get_instance_id()
	game.damage_tower(index,100000.0); await process_frame
	check(not is_instance_id_valid(body_token) and int(quote(point).investment)==0 and int(quote(point).refund)==0,"Actual destruction retires the old tower capital and model")
	var before: int = game.scrap
	check(game.build_or_upgrade_tower(index) and game.scrap==before-60,"Real destroyed foundation rebuild pays a fresh60")
	check(int(quote(point).investment)==60 and int(quote(point).refund)==30,"Rebuilding records only the new generation's payment")
	game.damage_tower(index,100000.0); await process_frame
	var receipt := await sell_gui(point)
	check(int(receipt.refund)==0 and bool(original.removed),"Actual dead foundation clears for zero refund and keeps its stable index")
	before=game.scrap
	check(not game.build_or_upgrade_tower(index) and game.scrap==before,"A retired tower index cannot be resurrected by the old F build API")
	released_cells(point,"tower")
	var next := await place_tower(point)
	check(next>index and int(game.world.tower_pads[next].paid_investment)==60 and bool(game.world.tower_pads[index].removed),"Same-location new tower appends a new identity without overwriting its tombstone")
	await fresh(); var old := await build_gui("barracks",BARRACKS)
	point=game.districts.plots[old].position; var plot: Dictionary=game.districts.plots[old]
	body_token=(plot.model as Node).get_instance_id(); game.districts.damage(old,100000.0); await process_frame
	check(not is_instance_id_valid(body_token) and int(quote(point).investment)==0,"Real destroyed district clears prior capital")
	var reused := await build_gui("barracks",point)
	check(reused==old and int(quote(point).investment)==60,"Undemolished district wreck rebuild keeps stable index with a fresh paid account")
	game.districts.damage(old,100000.0); await process_frame; receipt=await sell_gui(point)
	check(int(receipt.refund)==0 and bool(plot.removed),"Real district wreck clearance is a zero-refund retirement")
	var again := await build_gui("barracks",point)
	check(again>old and bool(game.districts.plots[old].removed),"After deliberate retirement same-site district appends instead of reusing the tombstone")
	for row: Dictionary in game.districts.snapshots(): check(int(row.index)!=old,"Retired district is absent from actual HUD/minimap snapshots without renumbering live indices")
	before=game.scrap
	check(not bool(game.districts.demolish(old).ok) and not bool(game.districts.choose(old,"barracks").ok) and game.scrap==before,"Repeated retired-index demolition and old rebuild cannot pay or revive")
	await begin_sell(point); var stale: Dictionary=game.construction.snapshot()
	game.districts.damage(again,100000.0); before=game.scrap; await press(KEY_F)
	check(int(stale.refund)==30 and game.scrap==before and bool(game.districts.plots[again].removed),"Actual F recomputes a stale live preview after destruction instead of trusting the old30 quote")
	await finish_sell(); await capture("retired-stable-indices-freed-location")

func queues_and_technology() -> void:
	await fresh(); var index := await build_gui("barracks",BARRACKS)
	await press(KEY_U); await advance(6.1)
	check(game.squads.squads.size()==1,"Actual paid completed barracks training produces a real retained squad")
	var tokens: Array[int]=[]
	for member: BattleUnit in game.squads.squads[0].members: tokens.append(member.get_instance_id())
	await press(KEY_U); await press(KEY_I)
	check(game.squads.training_queues[index].size()==2,"Two actual prepaid production orders remain incomplete")
	await advance(1.0); var preview := await begin_sell(BARRACKS)
	check(int(preview.refund)==30 and int(preview.queue_refund)==150,"Demolition separates capital30 from full unused queue150")
	await capture("barracks-real-queue-refund-preview"); await finish_sell(); var before: int=game.scrap
	await sell_gui(BARRACKS)
	check(game.scrap==before+180 and game.squads.training_queues.get(index,[]).is_empty(),"Real barracks sale returns the independent full150 queue prepayment plus30 capital once")
	for token: int in tokens: check(is_instance_id_valid(token) and (instance_from_id(token) as BattleUnit).alive,"Already produced soldiers survive the demolished barracks")
	before=game.scrap; await advance(10.0)
	check(game.scrap==before and game.squads.squads.size()==1,"Canceled prepaid orders cannot later spawn or refund a second time")
	await fresh(); await build_gui("barracks",BARRACKS); await build_gui("workshop",WORKSHOP)
	await build_gui("laboratory",LAB); await build_gui("depot",DEPOT); await build_gui("armory",ARMORY)
	check(bool(game.squads.training_eligibility("ballista").available) and bool(game.squads.training_eligibility("artillery").available),"Real live technologies initially authorize advanced production")
	await sell_gui(LAB)
	before=game.scrap; var rejected: Dictionary=game.squads.enqueue("ballista")
	check(not bool(rejected.ok) and game.scrap==before and not bool(game.districts.build_eligibility("armory").available),"Sold laboratory prevents new real heavy-crossbow production and required construction")
	await sell_gui(ARMORY); before=game.scrap; rejected=game.squads.enqueue("artillery")
	check(not bool(rejected.ok) and game.scrap==before,"Sold armory prevents new artillery orders without charging")
	await sell_gui(DEPOT); before=game.scrap; rejected=game.squads.enqueue("hauler")
	check(not bool(rejected.ok) and game.scrap==before,"Sold depot prevents new hauler training")
	await sell_gui(WORKSHOP)
	check(not bool(game.districts.build_eligibility("recycler").available) and not bool(game.districts.build_eligibility("depot").available),"Sold workshop invalidates the actual dependent building prerequisites")
	await fresh()
	var first := await build_gui("barracks",BARRACKS)
	var middle := await build_gui("barracks",WORKSHOP)
	var last := await build_gui("barracks",LAB)
	for item: Dictionary in [{"index":first,"kind":"ranged"},{"index":middle,"kind":"shield"},{"index":last,"kind":"shield"}]:
		check(bool(game.squads.enqueue(String(item.kind),int(item.index)).ok),"Actual stable-index barracks receives its own paid order")
	step(.25)
	var first_queue: Array=game.squads.training_queues[first].duplicate(true)
	var last_queue: Array=game.squads.training_queues[last].duplicate(true)
	var first_token: int=(game.districts.plots[first].model as Node).get_instance_id()
	var last_token: int=(game.districts.plots[last].model as Node).get_instance_id()
	await sell_gui(WORKSHOP)
	check(game.districts.plots.size()==3 and game.districts.plots[middle].removed and (game.districts.plots[first].model as Node).get_instance_id()==first_token and (game.districts.plots[last].model as Node).get_instance_id()==last_token,"Actual middle-slot retirement leaves both other building indices and models stable")
	check(game.squads.training_queues[first]==first_queue and game.squads.training_queues[last]==last_queue,"Middle-slot sale preserves other paid orders and their actual remaining time")
	var indices: Array[int]=[]
	for row: Dictionary in game.districts.snapshots():indices.append(int(row.index))
	check(indices==[first,last],"Actual filtered snapshots keep their original live indices")
	await capture("actual-middle-barracks-retired-live-indices")
	await advance(8.0)
	check(game.squads.squads.size()==2 and game.squads.training_queues[first].is_empty() and game.squads.training_queues[last].is_empty(),"Other stable-index barracks genuinely finish both retained orders")

func actual_wreck_recovery_cap() -> void:
	await fresh(); await build_gui("workshop",WORKSHOP)
	var index := await build_gui("recycler",DEPOT); var point: Vector3=game.districts.plots[index].position
	var source_tokens: Array[int]=[]
	for _death in 12:
		var source: BattleUnit=game.spawn_creature(false); source.position=point+Vector3(0,0,5); source_tokens.append(source.get_instance_id()); source.hurt(100000.0,game.hero)
	await process_frame
	check(int(game.districts.plots[index].pending)==24 and game.districts._captured_scrap==24,"Twelve actual enemy defeat callbacks capture exactly the unchanged24 nightly quota")
	var balance: int=game.scrap; var preview := await begin_sell(point)
	check(int(preview.refund)==45 and int(preview.investment)==90,"Unprocessed24 material never enters the capital refund")
	check(int(preview.pending_loss)==24 and String(preview.reason).contains("24"),"Actual recycler quote discloses the real material that retirement discards")
	await capture("recycler-real-unprocessed24-preview"); await finish_sell(); await sell_gui(point)
	check(game.scrap==balance+45 and int(game.districts.plots[index].pending)==0,"Actual recycler retirement discards unprocessed material instead of redeeming it")
	var rebuilt := await build_gui("recycler",point)
	check(rebuilt>index and game.districts._captured_scrap==24,"Same-night new recycler identity cannot restore the already spent nightly quota")
	var source: BattleUnit=game.spawn_creature(false); source.position=point+Vector3(0,0,5); source.hurt(100000.0,game.hero); await process_frame
	check(game.districts.plots[rebuilt].pending==0,"Actual new death after same-night rebuild is rejected by the existing shared cap")
	game.districts.begin_night(game.day_number)
	check(game.districts._captured_scrap==24,"Repeated real begin_night cannot refresh the same-night quota")
	game.day_number+=1; game.start_night(); clear_enemies(); game.phase_time=10000;game.wave_index=game.WAVES_PER_NIGHT; game.spawn_timer=100000
	source=game.spawn_creature(false); source.position=point+Vector3(0,0,5); source.hurt(100000.0,game.hero); await process_frame
	check(game.districts.plots[rebuilt].pending==2 and game.districts._captured_scrap==2,"Actual next-night transition restores only its original quota")
	(evidence.recovery as Array).append({"actual_first_night_deaths":12,"captured":24,"sale_refund":45,"discarded_pending":24,"same_night_new_pending":0,"next_night_pending":2,"scope":"real defeat callbacks with precision direct lethal hurt,not natural combat difficulty"})

func cargo_after_retiring_station() -> void:
	await route_ready(); await press(KEY_ESCAPE)
	var precision_clock: float=game.phase_time;game.phase_time=game.DAY_LENGTH;game._process(4.0)
	check(game.phase=="day" and game.notice_time<=0 and game.beacon_alarm_time<=0 and game.hero_damage_flash_time<=0 and game.squads.selected_count()==0 and game.hud.detail_tab.is_empty() and not game.construction.active and game.target_warning_snapshot().is_empty(),"Actual default daylight frame has no drawer, notice, selection, construction or attack alert")
	await capture("default-day-no-drawer")
	game.phase_time=precision_clock;await press(KEY_TAB);await right_field(0)
	if not await wait_for(func()->bool:return game.logistics.snapshot().cargo==24,160,"Real cargo before station retirement"): return
	if not await wait_for(func()->bool:return not (game.logistics._teams[0].homes as Dictionary).is_empty(),5,"Actual returning members hold a live station identity"): return
	var model_token: int=(game.districts.plots[depot_index].model as Node).get_instance_id()
	for home: Dictionary in game.logistics._teams[0].homes.values(): check(int(home.token)==model_token,"Returning cargo refers to the actual sold station model token")
	await sell_gui(DEPOT); await process_frame
	check(not is_instance_id_valid(model_token),"Actual station sale releases the old receiving model identity")
	var balance: int=game.scrap; await advance(8.0)
	check(game.logistics.snapshot().cargo==24 and game.logistics.snapshot().delivered==0 and game.scrap==balance and String(team_row().state)=="waiting_home","Stationless real carriers preserve their goods and never redeem them remotely")
	await capture("real-cargo-waits-after-station-sale")
	var new_index := await build_gui("depot",DEPOT)
	check(new_index>depot_index and (game.districts.plots[new_index].model as Node).get_instance_id()!=model_token,"Same-site new receiver has a new stable plot and model identity")
	if not await wait_for(func()->bool:return game.logistics.snapshot().delivered==24,160,"Actual carriers reach the new receiving station"): return
	check(game.logistics.snapshot().cargo==0 and int(team_row().preferred_field)==0,"Existing physical goods settle only after arrival at the new station")
	await capture("actual-new-station-physical-delivery")
	await route_ready(); await right_field(0)
	if not await wait_for(func()->bool:return float(team_row().unloading_progress)>.1,160,"Real first-level individual unload clock before retirement"):return
	step(maxf(0.0,.99-float(team_row().unloading_progress)))
	var monitored := -1
	for row: Dictionary in team_row().members:
		if int(row.cargo)>0 and float(row.unloading_progress)>=.98:monitored=int(row.token);break
	check(monitored>=0,"Actual carrier still owns goods at approximately0.99 seconds of the old unload")
	if monitored<0:return
	model_token=(game.districts.plots[depot_index].model as Node).get_instance_id()
	await begin_sell(DEPOT);await capture("actual-old-station-unload099-sale-preview");await finish_sell();await sell_gui(DEPOT)
	new_index=await build_gui("depot",DEPOT)
	check(new_index>depot_index and not is_instance_id_valid(model_token),"Actual same-site replacement invalidates the old receiver before any next simulation tick")
	var delivered_before: int=game.logistics.snapshot().delivered
	step(.02)
	check(int((instance_from_id(monitored) as BattleUnit).get_meta("haul_cargo",-1))==8 and game.logistics.snapshot().delivered==delivered_before,"New receiver cannot redeem the old0.99-second unload at1.01 seconds")
	var new_home: Dictionary=game.logistics._teams[0].homes[monitored]
	check(int(new_home.index)==new_index and int(new_home.token)==(game.districts.plots[new_index].model as Node).get_instance_id() and float(game.logistics._teams[0].unloading[monitored])<=.020001,"Actual replaced receiver gets its own model identity and restarts the individual unload clock")
	if not await wait_for(func()->bool:return int((instance_from_id(monitored) as BattleUnit).get_meta("haul_cargo",-1))==0,10,"Actual retained cargo completes a fresh live receiver unload"):return
	check(game.logistics.snapshot().delivered>=delivered_before+8,"Only the carrier's completed new unload redeems its real eight goods")

func real_enemy_lock_release() -> void:
	for kind: String in ["tower","workshop"]:
		await fresh(); var index := -1
		if kind=="tower": index=await place_tower(Vector3(7.5,5,3.5))
		else: index=await build_gui(kind,Vector3(7.5,5,3.5))
		if index<0:return
		var point: Vector3=game.world.tower_pads[index].position if kind=="tower" else game.districts.plots[index].position
		var enemy: BattleUnit=game.spawn_creature(false); enemy.position=point+Vector3(2.2,0,0); enemy.position.y=game.outpost_height(enemy.position); enemy.attack_timer=0
		var expected_type := "tower" if kind=="tower" else "district"
		if not await wait_for(func()->bool:return enemy.attack_queued,10,"Actual enemy approaches the real "+kind+" and starts its genuine melee preparation"): return
		check(String(enemy.get_meta("attack_target_kind",""))==expected_type and int(enemy.get_meta("attack_target_index",-1))==index and enemy.attack_windup>0,"Real enemy windup locks the building about to be retired")
		await begin_sell(point); await capture("enemy-real-"+kind+"-windup-before-sale"); await finish_sell(); await sell_gui(point)
		check(not enemy.attack_queued and enemy.attack_windup==0 and game.attack_target_node(enemy)==null,"Actual demolition cancels the old target windup and releases its attack lock")
		var replacement := await place_tower(point) if kind=="tower" else await build_gui(kind,point)
		if replacement<0:return
		check(replacement>index,"Same-site building replacement owns a new identity before the next actual tick")
		for pad: Dictionary in game.world.tower_pads:pad.cooldown=100000.0
		var new_building: Dictionary=game.world.tower_pads[replacement] if kind=="tower" else game.districts.plots[replacement]
		var hp: float=new_building.hp;var paid: int=game.scrap
		step(.01)
		check(new_building.hp==hp and enemy.attack_queued and int(enemy.get_meta("attack_target_index",-1))==replacement and is_equal_approx(enemy.attack_windup,.34),"Same-site new building requires the actual complete new0.34-second windup")
		step(.33);check(new_building.hp==hp,"New building cannot inherit elapsed preparation from the sold identity")
		step(.02);check(is_equal_approx(float(new_building.hp),hp-enemy.damage),"Actual completed new windup normally damages the replacement once")
		check(game.scrap==paid,"A canceled stale building attack cannot produce demolition money or another payment")
		clear_enemies()
		if kind=="tower":check(game.world.tower_pads[index].removed,"Enemy cannot damage or resurrect a retired tower index")
		else:check(game.districts.plots[index].removed,"Enemy cannot damage or resurrect a retired district index")
	await fresh();var index:=await build_gui("workshop",FREE_TOWER);var point: Vector3=game.districts.plots[index].position
	var caster: BattleUnit=game.spawn_creature(true,"lobber");caster.position=point+Vector3(4,0,0);caster.position.y=game.outpost_height(caster.position)
	var controller: Node3D=game.lobbers.back()
	if not await wait_for(func()->bool:return String(controller.snapshot().phase)=="windup",5,"Actual thrower prepares on the live building to retire"):return
	check(String(controller.snapshot().target_kind)=="district" and int(controller.snapshot().target_index)==index,"Actual lobber locks the old district model")
	var token: int=(game.districts.plots[index].model as Node).get_instance_id()
	await sell_gui(point);var replacement:=await build_gui("workshop",point);var hp: float=game.districts.plots[replacement].hp
	step(.02)
	check(replacement>index and not is_instance_id_valid(token) and String(controller.snapshot().cancel_reason)=="target_dead" and int(controller.snapshot().launched)==0 and game.districts.plots[replacement].hp==hp,"Actual thrower's old model token cancels its incomplete cast across same-site retirement and replacement")

func freeze_and_run_lifetimes() -> void:
	await fresh(); var index := await build_gui("barracks",BARRACKS); await begin_sell(BARRACKS)
	await press(KEY_F1); await press(KEY_ESCAPE)
	check(game.phase=="paused","Actual F1 pauses the active demolition preview")
	var before := state(); await press(KEY_F); game.construction.confirm(); game.sell_structure_at(BARRACKS); game.construction.toggle_sell(); game.simulate(5)
	check(state()==before and not game.districts.plots[index].removed,"Paused true input and production entry points cannot sell or toggle demolition")
	await capture("paused-live-demolition-preview")
	await press(KEY_ESCAPE)
	# Escape follows the existing construction exit first; resume the real pause
	# explicitly if the tool was still active, without changing production rules.
	if game.phase=="paused":await press(KEY_ESCAPE)
	if not game.construction.active:await begin_sell(BARRACKS)
	var balance: int=game.scrap; var cost: int=game.run.memory_cost(); await press(KEY_V)
	check(game.phase=="draft" and game.scrap==balance-cost,"Actual V pays for a legal card offer during the demolition tool")
	before=state(); game.construction.confirm(); game.sell_structure_at(BARRACKS); game.simulate(5)
	check(state()==before and not game.districts.plots[index].removed,"Paid choice freezes the old preview and all sale transactions")
	await press(KEY_1); check(game.phase=="night","Actual card selection returns to its original night")
	await begin_sell(BARRACKS); var old_root:=game.get_instance_id(); var old_model: int=(game.districts.plots[index].model as Node).get_instance_id()
	game.end_defeat("拆卖生命周期验收"); check(not game.sell_structure_at(BARRACKS),"Actual defeat disallows the previously valid sale")
	await press(KEY_ENTER)
	for _frame in 240:
		await create_timer(.02,true,false,true).timeout
		if is_instance_valid(current_scene) and current_scene.get_instance_id()!=old_root:
			game=current_scene as Node3D;game.set_process(false);game.world.set_process(false);break
	check(is_instance_valid(game) and game.get_instance_id()!=old_root and not is_instance_id_valid(old_root) and not is_instance_id_valid(old_model),"True same-seed Enter releases the prior building, preview and game identities")
	if not is_instance_valid(game) or game.get_instance_id()==old_root:return
	await observer()
	check(game.run.seed_value==SEED and game.phase=="draft" and not game.construction.sell_mode and game.districts.plots.is_empty(),"Actual retry keeps seed while removing demolition mode, prior receipts and tombstones")
	await fresh(); await build_gui("barracks",BARRACKS); await begin_sell(BARRACKS); game.day_number=game.max_nights();TransitionFixture.finish_for_fixture(game)
	check(game.victory and game.phase=="ended" and not game.sell_structure_at(BARRACKS),"Actual victory makes an existing demolition preview inert")

func untouched_opening_wallet() -> void:
	await natural_scene()
	var opening_time: float=game.phase_time; var point: Vector3=game.hero.position
	check(game.scrap==90 and opening_time==105 and game.tower_count()==2,"The economic example keeps the original90 opening,105-second night and gifted two towers")
	var index := await paid_build_no_teleport("barracks",BARRACKS)
	check(game.scrap==30 and game.hero.position==point,"Actual original-wallet building pays60 without fixture money or hero teleportation")
	await sell_gui(game.districts.plots[index].position,true)
	check(game.scrap==60 and game.phase_time==opening_time and game.hero.position==point,"Actual original-wallet sale returns30 with untouched original clock and hero position")
	(evidence.economy as Array).append({"opening":90,"build":60,"refund":30,"final":game.scrap,"phase":game.phase,"original_phase_time":opening_time,"scope":"original opening wallet and true construction GUI;no whole-night simulation or human difficulty claim"})
	await capture("original90-build60-sell30-wallet60")

func actual_demolition_hud() -> void:
	await fresh(); var index := await build_gui("barracks",BARRACKS); await begin_sell(BARRACKS)
	await validate_hud("live-demolition-toolbar")
	await redraw(); var text := ""
	for row: Dictionary in game.hud.drawn_labels:text+=String(row.text)+"\n"
	check(text.contains("拆卖") and text.contains("30"),"Actual existing Y toolbar exposes demolition and its real refund")
	await capture("existing-toolbar-real-refund30")
	await finish_sell(); await press(KEY_F3); await click_ui(game.hud.details_tab_rect(4)); await validate_hud("demolition-help",true)
	await capture("existing-f3-demolition-help")
	await close_drawer(); game.districts.damage(index,100000); await begin_sell(BARRACKS)
	check(int(game.construction.snapshot().refund)==0,"Actual dead-building toolbar presents its zero-refund clearance")
	await validate_hud("zero-refund-wreck-clearance"); await capture("actual-wreck-clearance-zero-refund")
	await finish_sell()

func run() -> void:
	var cases := {"input":selection_input_and_full_footprint,"accounts":real_paid_accounts,"identity":retired_indices_and_fresh_receipts,"queue_tech":queues_and_technology,"recycler":actual_wreck_recovery_cap,"logistics":cargo_after_retiring_station,"enemy":real_enemy_lock_release,"freeze":freeze_and_run_lifetimes,"economy":untouched_opening_wallet,"hud":actual_demolition_hud}
	var args := OS.get_cmdline_user_args(); var selected: Array=cases.keys();var index:=args.find("--case")
	if index>=0 and index+1<args.size():selected=[args[index+1]]
	for name: String in selected:
		if not cases.has(name):check(false,"Unknown demolition stage "+name);break
		active_stage=name;print("DEMOLITION_STAGE_BEGIN ",name)
		await (cases[name] as Callable).call();print("DEMOLITION_STAGE_END ",name," checks=",checks," failures=",failures.size())
		(evidence.completed as Array).append(name)
		if not failures.is_empty():break
	await close_game()
	var folder := ProjectSettings.globalize_path(output_dir);DirAccess.make_dir_recursive_absolute(folder)
	var file:=FileAccess.open(folder.path_join("demolition.json"),FileAccess.WRITE);check(file!=null,"Demolition evidence opens only under build")
	evidence.checks=checks;evidence.failures=failures
	if file!=null:file.store_string(JSON.stringify(evidence,"\t"));file.close()
	finished=true;print("DEMOLITION_RESULT checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
