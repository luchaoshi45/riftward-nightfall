extends "res://tests/nightfall_haul_routes.gd"
## Real production scene, paid queues, model generations and physical rally paths.
## Precision only: 5000 parts, extended clocks, direct hero positioning and lethal
## boundary damage. No assertion represents human economic or campaign balance.

const SECOND_BARRACKS := Vector3(-7,5,-8.5)
const RALLY_A := Vector3(7,5,3.5)
const RALLY_B := Vector3(-7,5,3.5)
const OUTSIDE := Vector3(9,0,33)
const MEDICAL := Vector3(-7.5,5,2.5)
const LAB := Vector3(7,5,-3.5)
const ARMORY := Vector3(7,5,2.5)
const SUPPORT_POINT := Vector3(0,5,10.5)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args(); render_test = "--render-test" in args
	output_dir = "res://build/rally-points"
	var index := args.find("--output-dir")
	if index >= 0 and index+1 < args.size():
		var candidate := ProjectSettings.globalize_path(args[index+1]).simplify_path()
		var allowed := ProjectSettings.globalize_path("res://build").simplify_path()
		if candidate.begins_with(allowed+"/"): output_dir = candidate
		else: check(false,"Rally evidence must remain below the project build directory")
	root.size = VIEWPORTS[0]; root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT; root.content_scale_size = VIEWPORTS[0]
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.position = Vector2i(10000,10000); root.hide()
	evidence = {"seed":SEED,"scope":"precision5000/extended clocks/direct hero positioning; lethal100000 damage is an explicit lifecycle boundary; controlled capture lighting; no natural economic or human balance claim","completed":[],"captures":[],"hud":[],"routes":[],"identity":[]}
	create_timer(300.0,true,false,true).timeout.connect(watchdog)
	call_deferred("run")

func watchdog() -> void:
	if finished: return
	check(false,"Rally acceptance stalled in "+active_stage)
	await close_game(); finished = true; quit(1)

func state() -> Dictionary:
	var result := super.state(); var configured: Array[Dictionary] = []
	for row: Dictionary in game.districts.active_barracks():
		configured.append({"id":int(row.index),"destination":game.rally.destination_for(int(row.index))})
	result.rally = game.rally.snapshot(); result.rally_active = game.rally.active; result.configured = configured
	var pending: Array = []
	for squad: Dictionary in game.squads.squads:
		pending.append([int(squad.id),bool(squad.get("rally_pending",false)),squad.get("rally_stations",[]).duplicate()])
	result.pending = pending
	return result

func close_game() -> void:
	if not is_instance_valid(game): return
	var rally: RefCounted = game.rally
	var logistics_token: int = game.logistics.get_instance_id()
	await game.prepare_shutdown()
	check(not bool(rally.get("active")) and int(rally.call("selection_id")) == -1,
		"Real shutdown clears captured rally mode and selected production identity")
	check(game.squads.squads.is_empty() and game.logistics.snapshot().remaining == 0,
		"Real shutdown clears rally actors and independent finite sources")
	if current_scene == game: current_scene = null
	game.queue_free(); game = null
	for _frame in 4: await process_frame
	check(not is_instance_id_valid(logistics_token),"Real shutdown releases the transport controller")

func redraw() -> void:
	# The fixture suspends _process, so invoke its actual presentation-only
	# marker tick without advancing simulate or changing the controlled camera.
	if is_instance_valid(game) and game.rally: game.rally.tick(0.0)
	await super.redraw()

func step(delta: float = STEP) -> void:
	var positions: Dictionary = {}
	for squad: Dictionary in game.squads.squads:
		for member: BattleUnit in squad.members:
			if is_instance_valid(member) and member.alive: positions[member.get_instance_id()] = member.position
	game.simulate(delta); elapsed += delta
	var valid := true
	for squad: Dictionary in game.squads.squads:
		for member: BattleUnit in squad.members:
			if not is_instance_valid(member) or not member.alive or not positions.has(member.get_instance_id()): continue
			var previous: Vector3 = positions[member.get_instance_id()]
			valid = valid and member.position.is_finite() and game.outpost_walkable(member.position)
			valid = valid and absf(member.position.y-game.outpost_height(member.position)) < .001
			valid = valid and game.can_traverse(previous,member.position) and planar(previous,member.position) <= member.speed*delta+.001
			if (previous.z < Layout.WALL_CENTER and member.position.z >= Layout.WALL_CENTER) or (previous.z > Layout.WALL_CENTER and member.position.z <= Layout.WALL_CENTER):
				var ratio := (Layout.WALL_CENTER-previous.z)/(member.position.z-previous.z)
				valid = valid and absf(lerpf(previous.x,member.position.x,ratio)) < Layout.GATE_HALF
				if member.position.z > previous.z: route_out += 1
				else: route_in += 1
	check(valid,"All actual rally members take bounded walkable ground steps through the unique south gate")
	var stock: Dictionary = game.logistics.snapshot()
	check(int(stock.remaining)+int(stock.cargo)+int(stock.delivered)+int(stock.lost)==480,"Rally simulation preserves all480 finite transport parts")

func ready(two: bool = false) -> void:
	await fresh()
	barracks_index = await build_gui("barracks",BARRACKS)
	if two: await build_gui("barracks",SECOND_BARRACKS)
	await dawn()
	check(game.rally is RefCounted and game.rally.selection_id()==-1 and not game.rally.active,
		"Real new production scene starts in automatic camp selection without a rally tool")

func select_camp(id: int) -> void:
	await open_army(false)
	for _choice in game.districts.active_barracks().size()+2:
		if game.rally.selection_id()==id: break
		await click_ui(game.hud.RALLY_SELECTOR_RECT)
	check(game.rally.selection_id()==id,"Actual existing army selector chooses camp "+str(id))

func open_army(second: bool = true) -> void:
	# The inherited transport helper assumes only one page turn; specialized
	# troops now use page3, so return with the actual bounded pagination input.
	if game.construction.active: await press(KEY_ESCAPE)
	if game.hud.detail_tab.is_empty(): await press(KEY_F3)
	if game.hud.detail_tab!="army": await click_ui(game.hud.details_tab_rect(2))
	var target:=1 if second else 0
	for _page in 3:
		if game.hud.troop_page==target: break
		await click_ui(game.hud.troop_page_rect(1 if target>game.hud.troop_page else -1))
	await redraw()
	check(game.hud.detail_tab=="army" and game.hud.troop_page==target,"Actual bounded army pagination opens the intended page from any of the three pages")

func begin_gui(id: int) -> void:
	await select_camp(id); await click_ui(game.hud.RALLY_SET_RECT)
	check(game.rally.active and game.hud.detail_tab.is_empty() and not game.construction.active,
		"Actual set-rally button closes the drawer and captures the selected live camp")

func setting_gui(id: int, point: Vector3) -> Vector3:
	await begin_gui(id); await aim_at(point)
	var physical: Vector3 = game.ground_point(game.camera.unproject_position(point))
	await mouse(game.camera.unproject_position(point),true)
	var result: Dictionary = game.rally.destination_for(id)
	check(not game.rally.active and bool(result.enabled) and planar(result.point,physical)<.02,
		"Actual left ground click commits the physical point to this camp")
	return result.point if bool(result.enabled) else point

func queue_gui(kind: String) -> void:
	await open_army(false)
	var target_page: int = Catalog.TROOP_IDS.find(kind)/3
	for _page in 3:
		if game.hud.troop_page==target_page: break
		await click_ui(game.hud.troop_page_rect(1 if target_page>game.hud.troop_page else -1))
	var before: int = game.scrap
	await click_ui(game.hud.training_kind_rect(Catalog.TROOP_IDS.find(kind)%3))
	check(game.scrap==before-int(Catalog.troop(kind).cost),"Real "+kind+" GUI order pays the sole parts balance exactly once")
	await close_drawer()

func squad_row(id: int) -> Dictionary:
	return game.squads.squads[id] if id >= 0 and id < game.squads.squads.size() else {}

func stationed(id: int) -> bool:
	var squad := squad_row(id)
	if squad.is_empty() or String(squad.order)!="guard" or bool(squad.get("rally_pending",false)): return false
	var living := 0
	for slot in squad.members.size():
		var member: BattleUnit = squad.members[slot]
		if not is_instance_valid(member) or not member.alive: continue
		living += 1
		var expected: Vector3 = squad.destination+Vector3((slot-1)*1.25,0,0)
		if planar(member.position,expected)>.24 or member.moving: return false
	return living>0

func only_squad(id: int) -> void:
	await close_drawer()
	var squad := squad_row(id)
	for member: BattleUnit in squad.members:
		if is_instance_valid(member) and member.alive:
			camera_at(member.position); await mouse(game.camera.unproject_position(member.position),true); break
	check(game.squads.selected_ids==[id],"Actual member click selects precisely the intended rally squad")

func actual_hud(tag: String) -> void:
	var before := state(); var previous_viewport: Vector2i=root.size
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport; await redraw()
		var glyphs_fit: bool = not game.hud.drawn_labels.is_empty(); var chinese_available := true
		var selector_present := false; var rally_rows: Array[Dictionary] = []
		for row: Dictionary in game.hud.drawn_labels:
			glyphs_fit = glyphs_fit and row.point.x>=0 and row.point.x+float(row.width)<=1440 and row.point.y-float(row.ascent)>=0 and row.point.y+float(row.descent)<=900
			for character: String in String(row.text):
				var code := character.unicode_at(0)
				if code>=0x4e00 and code<=0x9fff: chinese_available = chinese_available and game.hud.font.has_char(code)
			if String(row.text).contains("集结") or (row.point.y>=422 and row.point.y<=449): rally_rows.append(row.duplicate())
			if row.point.y>=422 and row.point.y<=449 and row.point.x>=46 and row.point.x<234:
				selector_present = true; glyphs_fit = glyphs_fit and row.point.x+float(row.width)<=234
		check(glyphs_fit and chinese_available,"Actual rally HUD glyph bounds and Chinese font are complete in "+tag+" "+str(viewport))
		if game.hud.detail_tab=="army":
			check(selector_present,"Actual selected camp/automatic caption remains in the existing188-pixel column")
			check(not game.hud.RALLY_SELECTOR_RECT.intersects(game.hud.RALLY_SET_RECT) and not game.hud.RALLY_SET_RECT.intersects(game.hud.RALLY_RESET_RECT),"Actual three rally buttons have independent hitboxes")
		if game.rally.active:
			check(game.hud.drawn_rects.has(game.hud.RALLY_PROMPT_RECT),"Actual mode draws the existing bottom rally tool rectangle")
			check(not game.hud.RALLY_PROMPT_RECT.intersects(Rect2(435,773,570,24)),"Actual rally tool leaves the hero-hit warning region separate")
		(evidence.hud as Array).append({"tag":tag,"viewport":viewport,"rally_labels":rally_rows})
	check(state()==before,"Actual three-viewport HUD measurement does not spend, walk, alter queues or advance randomness")
	root.size=previous_viewport; root.content_scale_size=previous_viewport; await redraw()

func capture(label: String) -> void:
	if not render_test: return
	check(DisplayServer.get_name()!="headless","Rally captures require a real graphical renderer")
	if DisplayServer.get_name()=="headless": return
	var before := state(); var previous_viewport: Vector2i=root.size
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport
		game.world.night_mix=1.0 if game.phase=="night" else 0.0; game.world.apply_lighting(); await redraw()
		for _frame in 2: await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		check(image.get_size()==viewport and Vector2i(game.hud.get_viewport_rect().size)==viewport,"Rally capture matches the actual render viewport")
		var folder := ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
		var name := "%s-%dx%d" % [label,viewport.x,viewport.y]
		check(image.save_png(folder.path_join(name+".png"))==OK,"Real rally capture saves beneath local build")
		(evidence.captures as Array).append(name)
	check(state()==before,"Rally captures cannot advance actual wallet, production, movement or RNG")
	root.size=previous_viewport; root.content_scale_size=previous_viewport; await redraw()

func camps_queues_and_pure_setting() -> void:
	await ready(true)
	var second := plot_at("barracks",SECOND_BARRACKS)
	check(second>=0 and second!=barracks_index,"Two real paid camps have independent stable identities")
	var before := state()
	for _read in 10: game.rally.snapshot(); game.rally.destination_for(barracks_index); game.rally.selection_id()
	check(state()==before,"Repeated real rally presentation reads do not move, spend, progress queues or consume RNG")
	var a := await setting_gui(barracks_index,RALLY_A); var b := await setting_gui(second,RALLY_B)
	check(planar(a,b)>10 and game.rally.destination_for(barracks_index).point==a,"Each actual camp retains its own distinct point")
	await select_camp(barracks_index); before=state()
	a=await setting_gui(barracks_index,a); a=await setting_gui(barracks_index,a)
	check(game.scrap==before.parts and game.phase_time==before.time and game.run.rng.state==before.rng and game.squads.training_queues==before.queues,"Repeated valid setting cannot spend the wallet, progress real clocks or consume RNG")
	await select_camp(barracks_index); await close_drawer(); var wallet: int = game.scrap
	await press(KEY_U); await press(KEY_I)
	var first_queue: Array = game.squads.training_queues.get(barracks_index,[])
	check(first_queue.size()==2 and String(first_queue[0].kind)=="shield" and String(first_queue[1].kind)=="ranged" and game.scrap==wallet-150,"Actual U/I bind to the chosen camp in paid sequential order")
	await select_camp(second); await close_drawer(); wallet=game.scrap; await press(KEY_N)
	check(game.scrap==wallet-65,"Actual N binds the paid engineer order to the explicitly selected second camp")
	check(game.squads.training_queues.get(second,[]).size()==1,"Actual troop button independently targets the second chosen camp")
	await advance(6.1)
	check(game.squads.squads.size()==1 and String(squad_row(0).kind)=="shield" and squad_row(0).destination==a,"First camp completes its six-second shield while other two orders remain pending")
	check(game.squads.training_queues.get(second,[]).size()==1 and game.squads.training_queues.get(barracks_index,[]).size()==1,"Same camp is sequential and different camps genuinely advance in parallel")
	await advance(1.0)
	check(game.squads.squads.size()==2 and String(squad_row(1).kind)=="engineer" and squad_row(1).destination==b,"Second real camp completes its seven-second engineer at its own point")
	await select_camp(-1); await close_drawer(); await press(KEY_U)
	check(game.squads.training_queues.get(second,[]).size()==1 and String(game.squads.training_queues[second][0].kind)=="shield","Automatic mode still chooses the actually shortest independent queue")
	await open_army(false); await actual_hud("two-camps-training"); await capture("two-camps-training"); await close_drawer()
	await advance(7.0)
	check(game.squads.squads.size()==4,"Both sequential and parallel real paid orders finish exactly once")
	await wait_for(func() -> bool: return stationed(0) and stationed(1) and stationed(2) and stationed(3),60,"All actual new groups physically reach their camp-specific formations")
	check(squad_row(2).destination==b and squad_row(3).destination==a,"Every completed order reads the identity of its own production camp")
	await select_camp(barracks_index); before=state()
	await begin_gui(barracks_index)
	var invalid: Dictionary=game.rally.commit(Vector3.INF)
	check(not bool(invalid.ok) and game.rally.active and game.rally.destination_for(barracks_index).point==a,"Nonfinite commit keeps the live mode and previous valid camp point")
	invalid=game.rally.commit(game.districts.plots[barracks_index].position)
	check(not bool(invalid.ok) and game.rally.active,"Occupied live building cannot be accepted as a rally point")
	invalid=game.rally.commit(a+Vector3(0,.076,0))
	check(not bool(invalid.ok) and game.rally.active,"A non-ground height outside the actual tolerance cannot configure the camp")
	invalid=game.rally.commit(Vector3(Layout.MAP_HALF_X+.001,0,33))
	check(not bool(invalid.ok) and game.rally.active,"Finite points beyond the real map cannot configure a rally")
	invalid=game.rally.commit(Vector3(12.5,5,3.5))
	check(not bool(invalid.ok) and game.rally.active,"A clear center cannot hide one of the three formation stations inside the real side wall")
	game.rally.cancel_setting()
	check(int(game.scrap)==int(before.parts) and game.run.rng.state==before.rng and game.phase_time==before.time and game.squads.training_queues==before.queues,"Rejected/repeated rally setting never charges or advances production clocks or RNG")
	await select_camp(barracks_index); await click_ui(game.hud.RALLY_RESET_RECT)
	check(not bool(game.rally.destination_for(barracks_index).enabled) and bool(game.rally.destination_for(second).enabled),"Actual reset removes only the chosen camp point")
	await close_drawer(); await press(KEY_U); await advance(6.1)
	check(String(squad_row(4).order)=="recall" and not bool(squad_row(4).get("rally_pending",false)),"Unconfigured day production preserves its original automatic recall rule")
	night_fixture(); await press(KEY_U); await advance(6.1)
	check(String(squad_row(5).order)=="hold" and not bool(squad_row(5).get("rally_pending",false)),"Unconfigured night production preserves its original automatic south-gate hold rule")

func physical_gate_redirect_and_override() -> void:
	await ready()
	var outside := await setting_gui(barracks_index,OUTSIDE)
	await select_camp(barracks_index); await queue_gui("shield"); await advance(6.1)
	check(String(squad_row(0).order)=="move" and bool(squad_row(0).get("rally_pending",false)),"Real new squad begins an explicit pending physical move instead of spawning at its point")
	for member: BattleUnit in squad_row(0).members: check(planar(member.position,outside)>15,"Actual new member is born by its camp and never teleports outside")
	if not await wait_for(func() -> bool: return route_out>0,60,"Actual new troop reaches the south gate"): return
	camera_at(Layout.gate_point()); await capture("real-south-gate-rally-move")
	var destination: Vector3=squad_row(0).destination
	var next := await setting_gui(barracks_index,RALLY_A)
	check(squad_row(0).destination==destination and bool(squad_row(0).get("rally_pending",false)),"Changing the camp point during travel never retasks an already produced group")
	if not await wait_for(func() -> bool: return stationed(0),80,"All three actual members arrive at their exact outside formation"): return
	check(route_out==3,"All three real members cross the unique south gate once")
	camera_at(outside); await capture("all-three-outside-rally")
	await queue_gui("ranged"); await advance(4.0)
	var changed := await setting_gui(barracks_index,RALLY_B); await advance(4.1)
	check(squad_row(1).destination==changed and squad_row(0).destination==outside,"Training-in-progress reads the current camp point at completion while old troops remain outside")
	await only_squad(1); await aim_at(next); await mouse(game.camera.unproject_position(next),true,MOUSE_BUTTON_RIGHT)
	check(String(squad_row(1).order)=="move" and not bool(squad_row(1).get("rally_pending",false)) and planar(squad_row(1).destination,next)<.02,"Actual manual right-click clears the automatic pending move and takes ownership")
	await press(KEY_O)
	check(String(squad_row(1).order)=="guard" and not bool(squad_row(1).get("rally_pending",false)),"Actual O guard also clears pending without reapplying a camp point")
	await advance(12)
	check(planar(squad_row(1).destination,next)<.02 and squad_row(0).destination==outside,"Subsequent ticks never reissue a camp rally over real manual orders")
	(evidence.routes as Array).append({"out_crossings":route_out,"in_crossings":route_in,"outside":outside,"old_group_destination":squad_row(0).destination,"manual_group_destination":squad_row(1).destination})

func blockage_death_and_refill() -> void:
	await ready()
	var point := await setting_gui(barracks_index,RALLY_A)
	await select_camp(barracks_index); await queue_gui("shield"); await advance(6.1)
	check(game.build_structure_at(RALLY_A,"barracks"),"A real later paid building occupies the not-yet-reached rally formation")
	var blocker := plot_at("barracks",RALLY_A)
	await advance(8.0)
	check(squad_row(0).destination==point and bool(squad_row(0).get("rally_pending",false)) and String(squad_row(0).order)=="move","A later occupied exact point retains its intended formation and waits instead of silently substituting nearby ground")
	for member: BattleUnit in squad_row(0).members: check(not Grid.placement(RALLY_A,"barracks").rect.has_point(Vector2(member.position.x,member.position.z)),"Waiting actual member never occupies the later building")
	camera_at(RALLY_A); await capture("actual-blocked-rally-formation")
	var wallet: int=game.scrap
	game.districts.damage(blocker,100000.0); await process_frame
	check(game.scrap==wallet and not game.outpost_walkable(BARRACKS),"Lethal blocker boundary damage releases no money and leaves the production camp alive")
	var victim: BattleUnit=squad_row(0).members[0]; var victim_token:=victim.get_instance_id()
	victim.hurt(100000.0,game.hero)
	check(not victim.alive,"Real hurt callback kills the one boundary victim during a pending move")
	if not await wait_for(func() -> bool: return stationed(0),60,"Surviving members resume the original exact point after real blocker destruction"): return
	check(squad_row(0).destination==point and not bool(squad_row(0).get("rally_pending",false)),"Dead members do not prevent the actual surviving formation from completing")
	wallet=game.scrap; await press(KEY_L)
	check(game.scrap==wallet-22 and (squad_row(0).members[0] as BattleUnit).get_instance_id()!=victim_token,"True daylight L pays the existing22-part shield replacement cost and creates a new member identity")
	if not await wait_for(func() -> bool: return stationed(0),60,"The paid replacement physically joins its existing fixed formation"): return
	check(squad_row(0).destination==point,"Paid replacement respects its group's real manual formation, without rereading a changed camp point")
	ledger("After blocked rally and paid replacement")

func model_generation_and_refund() -> void:
	await ready(true)
	var second:=plot_at("barracks",SECOND_BARRACKS)
	await setting_gui(barracks_index,RALLY_A); await setting_gui(second,RALLY_B)
	await select_camp(barracks_index); await queue_gui("shield"); await queue_gui("ranged")
	await select_camp(second); await queue_gui("engineer")
	await begin_gui(barracks_index)
	var old_token: int=(game.districts.plots[barracks_index].model as Node).get_instance_id()
	var wallet: int=game.scrap; game.districts.damage(barracks_index,100000.0); await process_frame
	check(game.scrap==wallet+150 and game.squads.training_queues.get(barracks_index,[]).is_empty(),"Real production camp destruction refunds its two unfinished receipts exactly once")
	check(game.build_structure_at(BARRACKS,"barracks"),"Real same-site wreck rebuild creates a fresh paid camp generation")
	check((game.districts.plots[barracks_index].model as Node).get_instance_id()!=old_token and not is_instance_id_valid(old_token),"Same stable district index owns a genuinely new live model token")
	var rejected: Dictionary=game.rally.commit(RALLY_B)
	check(not bool(rejected.ok) and not game.rally.active and game.rally.selection_id()==-1 and not bool(game.rally.destination_for(barracks_index).enabled),"The old captured model token cannot configure a freshly rebuilt camp or retain its prior rally point")
	check(bool(game.rally.destination_for(second).enabled) and game.squads.training_queues.get(second,[]).size()==1,"Other camp points and paid queues survive the first camp's destruction")
	wallet=game.scrap; game.squads.refresh_barracks()
	check(game.scrap==wallet,"Repeated real dead-camp refresh cannot refund a consumed receipt twice")
	await setting_gui(barracks_index,RALLY_A); await select_camp(barracks_index); await queue_gui("shield")
	await close_drawer(); await select_building("barracks"); await press(KEY_DELETE); await aim_at(BARRACKS)
	var sale: Dictionary=game.construction.snapshot(); wallet=game.scrap
	check(bool(sale.valid) and int(sale.refund)==30 and int(sale.queue_refund)==70,"Actual live rebuilt-camp sale quotes its new investment and separate unfinished training receipt")
	await mouse(game.camera.unproject_position(BARRACKS),true); await press(KEY_F)
	check(game.scrap==wallet+100 and bool(game.districts.plots[barracks_index].removed),"Actual sale pays both receipts once and retires the stable identity")
	await press(KEY_ESCAPE); step(.01)
	check(not bool(game.rally.destination_for(barracks_index).enabled) and game.rally.selection_id()==-1,"Retired camp removes its point and explicit production selection")
	var next:=await build_gui("barracks",BARRACKS)
	check(next>barracks_index and not bool(game.rally.destination_for(next).enabled),"Same-site camp built after sale appends a fresh identity without inheriting retired rally intent")
	(evidence.identity as Array).append({"retired":barracks_index,"new":next,"old_model_token":old_token,"queue_refund":150,"sale":sale.refund,"sale_queue":sale.queue_refund})

func support_freeze_and_lifetimes() -> void:
	await ready(); await build_gui("workshop",WORKSHOP); depot_index=await build_gui("depot",DEPOT)
	await build_gui("infirmary",MEDICAL)
	await build_gui("laboratory",LAB); await build_gui("armory",ARMORY)
	var point:=await setting_gui(barracks_index,SUPPORT_POINT)
	await select_camp(barracks_index); await queue_gui("hauler"); await queue_gui("medic"); await advance(17.1)
	if not await wait_for(func() -> bool: return stationed(0) and stationed(1),60,"Actual paid support groups reach the camp rally formation"): return
	await advance(15)
	check(game.logistics.snapshot().remaining==480 and game.logistics.snapshot().cargo==0 and game.logistics.snapshot().delivered==0 and not bool(team_row(0).automatic),"Explicitly rallied new haulers stay in manual guard and cannot secretly begin automatic collection")
	check(not bool(squad_row(1).therapy_enabled) and int(squad_row(1).treatments)==0,"Explicitly rallied new medics remain in their original default-off therapy mode")
	for kind: String in ["ballista","hunter","artillery"]: await queue_gui(kind)
	await advance(32.1)
	check(game.squads.squads.size()==5 and String(squad_row(2).kind)=="ballista" and String(squad_row(3).kind)=="hunter" and String(squad_row(4).kind)=="artillery","Real tech-gated paid queues also create the three specialized troop movement branches")
	if not await wait_for(func() -> bool: return stationed(2) and stationed(3) and stationed(4),100,"Slow heavy fire and finite-chase troops physically finish their exact rally formations"): return
	check(squad_row(2).destination==point and squad_row(3).destination==point and squad_row(4).destination==point,"Specialized heavy bow, hunter and mortar movement preserves the configured camp anchor")
	await only_squad(0); await open_army(); await actual_hud("rallied-support-off"); await capture("rallied-support-off"); await close_drawer()
	await select_camp(barracks_index); await queue_gui("shield"); await advance(1.0)
	await begin_gui(barracks_index); await press(KEY_F1); await press(KEY_ESCAPE)
	check(game.phase=="paused","Actual pause preserves a live rally tool and pending production")
	var before:=state(); game.simulate(5); game.squads.advance(5)
	var rejected: Dictionary=game.rally.commit(RALLY_B)
	check(not bool(rejected.ok) and state()==before,"Pause freezes actual queues, positions, wallet, clock and captured rally state")
	await press(KEY_ESCAPE)
	if game.phase=="paused": await press(KEY_ESCAPE)
	game.rally.cancel_setting(); await close_drawer()
	var wallet: int=game.scrap; var cost: int=game.run.memory_cost(); await press(KEY_V)
	check(game.phase=="draft" and game.scrap==wallet-cost,"Actual V pays the sole wallet for the real freezing card choice")
	before=state(); game.simulate(5); game.squads.advance(5)
	check(state()==before,"Actual paid choice freezes rally travel, training and all recorded economic state")
	await press(KEY_1); check(game.phase=="day" and game.rally.destination_for(barracks_index).point==point,"Real choice resumes daylight with the existing camp point")
	night_fixture(); await advance(6)
	check(squad_row(0).destination==point and String(squad_row(0).order)=="guard","Day/night transition preserves the existing rallied support order")
	await begin_gui(barracks_index)
	var old_root:=game.get_instance_id(); var old_model: int=(game.districts.plots[barracks_index].model as Node).get_instance_id()
	game.end_defeat("集结点生命周期验收")
	check(not game.rally.active and game.rally.selection_id()==-1 and game.squads.squads.is_empty(),"Actual defeat clears pending mode, selected camp and every old rally actor")
	await press(KEY_ENTER)
	for _frame in 240:
		await create_timer(.02,true,false,true).timeout
		if is_instance_valid(current_scene) and current_scene.get_instance_id()!=old_root:
			game=current_scene as Node3D; game.set_process(false); game.world.set_process(false); break
	check(is_instance_valid(game) and game.get_instance_id()!=old_root and not is_instance_id_valid(old_root) and not is_instance_id_valid(old_model),"Actual same-seed Enter releases the prior game and production model generations")
	if not is_instance_valid(game) or game.get_instance_id()==old_root: return
	await observer()
	check(game.run.seed_value==SEED and game.phase=="draft" and game.rally.selection_id()==-1 and not game.rally.active and game.districts.plots.is_empty(),"Retry keeps the real seed and contains no inherited camp selection, points or tool")
	await ready(); await setting_gui(barracks_index,RALLY_A); await begin_gui(barracks_index)
	game.day_number=game.max_nights(); game.finish_night()
	check(game.victory and game.phase=="ended" and not game.rally.active and game.rally.selection_id()==-1,"Actual victory also clears an active camp selection tool")

func physical_ui_modes_and_release() -> void:
	await ready(true)
	await queue_gui("shield"); await advance(6.1)
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport; await redraw()
		await press(KEY_TAB)
		check(game.squads.selected_ids==[0],"Actual Tab provides a nonempty squad selection before temporary camp setting")
		await select_camp(barracks_index)
		var selected: Array=game.squads.selected_ids.duplicate()
		await click_ui(game.hud.RALLY_SET_RECT); await aim_at(RALLY_A)
		var before:=state()
		for key: int in [KEY_F,KEY_U,KEY_I,KEY_N,KEY_O,KEY_TAB,KEY_V]:
			await press(key)
			check(state()==before and game.phase!="draft" and game.scrap==int(before.parts),"Live rally mode consumes actual key "+str(key)+" without training, ordering or paying for a card")
		await click_ui(game.hud.MEMORY_BUTTON_RECT)
		check(state()==before and game.phase!="draft" and game.scrap==int(before.parts),"Actual memory GUI click is consumed by live rally mode without purchasing a card")
		check(state()==before and game.squads.selected_ids==selected,"Mode consumes real interaction, production and squad keys without stealing existing selection")
		if viewport==VIEWPORTS[0]:
			await actual_hud("live-setting"); await capture("live-setting")
		await mouse(game.camera.unproject_position(RALLY_A),true,MOUSE_BUTTON_RIGHT)
		check(not game.rally.active and not bool(game.rally.destination_for(barracks_index).enabled) and game.move_goal==before.goal and game.squads.selected_ids==selected,"Actual right-click cancels live setting without moving actors or writing a point")
		await begin_gui(barracks_index); await press(KEY_ESCAPE)
		check(not game.rally.active and game.move_goal==before.goal,"Actual Escape cancels only the temporary setting mode")
		await begin_gui(barracks_index); await click_ui(game.hud.RALLY_CANCEL_RECT)
		check(not game.rally.active and game.move_goal==before.goal,"Actual bottom cancel button consumes its click without world movement")
		await begin_gui(barracks_index); await press(KEY_F3)
		check(not game.rally.active and not game.hud.detail_tab.is_empty(),"Explicit F3 reopening cancels temporary setting and returns the real detail drawer")
		await close_drawer(); await begin_gui(barracks_index); await press(KEY_Y)
		check(not game.rally.active and game.construction.active,"Explicit Y construction switch cancels setting and opens the existing construction tool")
		await press(KEY_ESCAPE)
		await begin_gui(barracks_index); await click_ui(game.hud.BUILD_BUTTON_RECT)
		check(not game.rally.active and game.construction.active,"Actual Y GUI button cancels setting and opens the existing construction tool")
		await press(KEY_ESCAPE)
		await setting_gui(barracks_index,RALLY_A)
		var configured: Dictionary=game.rally.destination_for(barracks_index).duplicate(true)
		await begin_gui(barracks_index); await aim_at(BARRACKS)
		var occupied: Vector3=game.ground_point(game.camera.unproject_position(BARRACKS))
		check(not game.outpost_walkable(occupied),"Real mouse ray for the invalid rally case lands inside the actual occupied camp")
		before=state()
		await mouse(game.camera.unproject_position(BARRACKS),true); await redraw()
		check(game.rally.active and state()==before and game.rally.destination_for(barracks_index)==configured,"Actual occupied-camp left click preserves live setting, the prior point and every recorded economic/order state")
		var feedback: String=game.hud.rally_feedback; var tool_feedback:=0
		for row: Dictionary in game.hud.drawn_labels:
			if String(row.text)==feedback:
				tool_feedback+=1
				check(row.point.x>=453 and row.point.x+float(row.width)<=849 and row.point.y==747,"Actual invalid-point feedback stays within the third rally tool row")
		check(not feedback.is_empty() and tool_feedback==1 and game.hud.drawn_rects.has(game.hud.RALLY_PROMPT_RECT),"Actual failure text remains visibly drawn once in the live tool while the ordinary notice is hidden")
		if viewport==VIEWPORTS[0]: await actual_hud("occupied-camp-feedback")
		await press(KEY_ESCAPE)
		await open_army(false)
		if viewport==VIEWPORTS[0]: await actual_hud("configured")
		await close_drawer()
		if game.squads.selected_count()>0: await press(KEY_ESCAPE)
		stand(OUTSIDE); camera_at(OUTSIDE); await advance(4); await redraw()
		check(not game.hud.drawn_rects.has(game.hud.RALLY_PROMPT_RECT),"Cancelled/committed rally mode stops drawing its old world-input rectangle")
		var old_goal: Vector3=game.move_goal
		await click_ui(game.hud.RALLY_PROMPT_RECT,MOUSE_BUTTON_RIGHT)
		check(game.move_goal!=old_goal and not game.rally.active,"Real right-click in the released old tool region reaches normal world hero movement")
		await select_camp(barracks_index); await click_ui(game.hud.RALLY_RESET_RECT); await close_drawer()
	root.size=VIEWPORTS[0]; root.content_scale_size=VIEWPORTS[0]
	await select_camp(barracks_index); await setting_gui(barracks_index,RALLY_B)
	await open_army(false); await capture("configured-existing-army-page")
	await press(KEY_F1); await press(KEY_ESCAPE); await actual_hud("paused-army"); await capture("paused-existing-army-page")
	var before:=state(); await click_ui(game.hud.RALLY_SET_RECT); await click_ui(game.hud.RALLY_RESET_RECT)
	check(state()==before,"Paused real army rally controls cannot reset points or activate setting")

func run() -> void:
	var cases := {"queues":camps_queues_and_pure_setting,"paths":physical_gate_redirect_and_override,"barrier":blockage_death_and_refill,"identity":model_generation_and_refund,"freeze":support_freeze_and_lifetimes,"hud":physical_ui_modes_and_release}
	var args:=OS.get_cmdline_user_args(); var selected: Array=cases.keys(); var index:=args.find("--case")
	if index>=0 and index+1<args.size(): selected=[args[index+1]]
	for name: String in selected:
		if not cases.has(name): check(false,"Unknown rally stage "+name); break
		active_stage=name; print("RALLY_STAGE_BEGIN ",name)
		await (cases[name] as Callable).call()
		print("RALLY_STAGE_END ",name," checks=",checks," failures=",failures.size())
		(evidence.completed as Array).append(name)
		if not failures.is_empty(): break
	await close_game(); evidence.checks=checks; evidence.failures=failures
	var folder:=ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
	var file:=FileAccess.open(folder.path_join("rally-points.json"),FileAccess.WRITE)
	check(file!=null,"Rally evidence opens beneath local build")
	evidence.checks=checks; evidence.failures=failures
	if file!=null: file.store_string(JSON.stringify(evidence,"\t")); file.close()
	finished=true; print("RALLY_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
