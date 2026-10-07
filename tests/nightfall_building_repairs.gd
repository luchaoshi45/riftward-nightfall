extends "res://tests/nightfall_attack_move.gd"
## Artificial phase setup only; natural clearance and victory use real combat.
## Independent repair acceptance. Precision uses5000 parts, extended phases,
## direct stations and real artificial building damage/casualties. Economy
## preserves90/105/90, native enemies/actors/stats, and actual world input.
## Captures use controlled lighting; neither route establishes human balance.

const Grid := preload("res://scripts/construction_grid.gd")
const REPAIR_RECT := Rect2(746,748,112,26)
const SELL_RECT := Rect2(870,748,119,26)
const TOOL_RECT := Rect2(435,642,570,140)
const RECYCLER_POINT := Vector3(0,5,-8.5)
const ROOT_OBSERVER := """extends 'res://scripts/nightfall.gd'
var observed_building_damage: Array[Dictionary] = []
func damage_tower(index: int, amount: float) -> void:
\tvar pad: Dictionary=world.tower_pads[index]
\tvar before: float=float(pad.hp)
\tsuper.damage_tower(index,amount)
\tobserved_building_damage.append({'type':'tower','index':index,'amount':amount,'loss':before-float(pad.hp),'before':before,'after':float(pad.hp),'phase':phase,'day':day_number,'time':phase_time})
"""
const REPAIR_HUD_OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var drawn_rects: Array[Rect2] = []
var drawn_labels: Array[Dictionary] = []
var toolbar_scope := false
func _draw() -> void:
\tdrawn_rects.clear(); drawn_labels.clear(); super._draw()
func draw_construction() -> void:
\ttoolbar_scope=true; super.draw_construction(); toolbar_scope=false
func box(rect: Rect2, fill: Color = Color(.022,.035,.045,.88), outline: Color = Color('435455')) -> void:
\tdrawn_rects.append(rect); super.box(rect,fill,outline)
func label(value: String, point: Vector2, size_px: int, color: Color = Color('e7e1d3'), latin: bool = false) -> void:
\tvar actual: Font = display_font if latin else font
\tdrawn_labels.append({'text':value,'point':point,'size':size_px,'width':actual.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x,'ascent':actual.get_ascent(size_px),'descent':actual.get_descent(size_px),'toolbar':toolbar_scope})
\tsuper.label(value,point,size_px,color,latin)
"""

var stage_returned := false
var engineer_returned := false
var warning_returned := false
var repair_natural_paid := false

func _initialize() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	render_test="--render-test" in args; output_dir="res://build/building-repairs"
	var requested := ""
	for arg: String in args:
		if arg.begins_with("--capture-dir="):requested=arg.trim_prefix("--capture-dir=")
	for flag: String in ["--capture-dir","--output-dir"]:
		var index: int=args.find(flag)
		if requested.is_empty() and index>=0 and index+1<args.size():requested=args[index+1]
	if not requested.is_empty():
		var candidate: String=ProjectSettings.globalize_path(requested).simplify_path()
		var allowed: String=ProjectSettings.globalize_path("res://build").simplify_path()
		if candidate.begins_with(allowed+"/"):output_dir=candidate
		else:check(false,"Repair evidence must remain below the project build directory")
	root.size=VIEWPORTS[0]; root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT; root.content_scale_size=VIEWPORTS[0]
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true); root.position=Vector2i(10000,10000); root.hide()
	evidence={"seed":SEED,"scope":"precision5000/extended clocks/direct stations/artificial real building damage and100000 casualties; economy native90/105/90, no funding/actor placement/enemy modification/time extension; controlled capture lighting; no human or full campaign balance claim","completed":[],"captures":[],"capture_receipt":[],"encounters":[],"input":[],"accounts":[],"timing":[],"cooperation":[],"identity":[],"lifecycle":[],"hud":[],"economy":[]}
	create_timer(900.0,true,false,true).timeout.connect(watchdog); call_deferred("run")

func watchdog() -> void:
	if finished:return
	check(false,"Building repair acceptance stalled in "+active_stage)
	await finalize(); finished=true; quit(1)

func fresh(is_precision: bool=true) -> void:
	await close_game(); precision=is_precision; repair_natural_paid=false
	check(RunSession.queue_request(self,SEED,"siege"),"Actual repair run accepts the fixed siege seed")
	var observer := GDScript.new(); observer.source_code=ROOT_OBSERVER
	check(observer.reload()==OK,"Read-only root observer records genuine damage without changing production behavior")
	var packed: PackedScene=load("res://scenes/nightfall.tscn").duplicate()
	var bundled: Dictionary=packed.get("_bundled").duplicate(true); var replaced := 0
	for index in bundled.variants.size():
		var value: Variant=bundled.variants[index]
		if value is Script and value.resource_path=="res://scripts/nightfall.gd":bundled.variants[index]=observer; replaced+=1
	check(replaced==1,"Observer replaces the one fixed root script before constructing eager controllers")
	packed.set("_bundled",bundled); game=packed.instantiate(); game.scene_file_path="res://scenes/nightfall.tscn"; root.add_child(game); current_scene=game
	for _frame in 5:await process_frame
	game.set_process(false); game.world.set_process(false)
	var hud_script := GDScript.new(); hud_script.source_code=REPAIR_HUD_OBSERVER
	check(hud_script.reload()==OK,"Read-only HUD observer forwards real drawing and input")
	var original: Control=game.hud; var layer: Node=original.get_parent(); layer.remove_child(original); original.queue_free()
	var observed: Control=hud_script.new(); observed.game=game; game.hud=observed; layer.add_child(observed); observed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await press(KEY_1)
	check(game.phase=="night" and game.phase_time==105.0 and game.scrap==90 and game.tower_count()==2 and game.run.seed_value==SEED,"Actual opening preserves90 parts/two gifts/105-second night and seed")
	elapsed=0.0; hurt_events.clear(); death_events.clear(); gate_tokens.clear()
	if precision:
		game.scrap=5000; game.phase_time=10000.0; game.wave_index=game.WAVES_PER_NIGHT
		clear_enemies(); suspend_defense(); stand(HOME)

func state() -> Dictionary:
	var result: Dictionary=super.state(); var towers: Array[Dictionary]=[]; var plots: Array[Dictionary]=[]
	for index in game.world.tower_pads.size():
		var pad: Dictionary=game.world.tower_pads[index]
		towers.append({"index":index,"position":pad.position,"level":pad.level,"hp":pad.hp,"max_hp":pad.max_hp,"removed":pad.get("removed",false),"model":plain(pad.get("turret")),"investment":pad.get("paid_investment",0),"mode":pad.get("mode","")})
	for plot: Dictionary in game.districts.plots:
		plots.append({"index":plot.index,"id":plot.id,"position":plot.position,"kind":plot.kind,"level":plot.level,"hp":plot.hp,"max_hp":plot.max_hp,"removed":plot.get("removed",false),"model":plain(plot.get("model")),"investment":plot.get("paid_investment",0),"pending":plot.pending,"recovery":plot.recovery_elapsed,"recovered":plot.recovered})
	result.towers=towers; result.plots=plots; result.repairs=plain(game.repairs.snapshot())
	return result

func close_game() -> void:
	if not is_instance_valid(game):return
	var service: RefCounted=game.repairs
	await game.prepare_shutdown()
	check((service.snapshot().targets as Array).is_empty(),"Actual shutdown immediately clears all live and waiting repairs")
	await super.close_game()

func repair_row(target_type: String,index: int) -> Dictionary:
	for row: Dictionary in game.repairs.snapshot().targets:
		if String(row.target_type)==target_type and int(row.target_index)==index:return row
	return {}

func aim_repair(point: Vector3) -> void:
	camera_at(point); await mouse(game.camera.unproject_position(point)); game.flush_pending_aim(); game._process(0)

func begin_repair(point: Vector3) -> Dictionary:
	await close_drawer()
	if not game.construction.active:await press(KEY_Y)
	if not game.construction.repair_mode:await press(KEY_H)
	await aim_repair(point)
	check(game.construction.active and game.construction.repair_mode and not game.construction.sell_mode,"Actual Y then H explicitly enters the exclusive repair tool")
	return game.construction.snapshot()

func repair_gui(point: Vector3,use_f: bool=false) -> void:
	var preview: Dictionary=await begin_repair(point); var before: int=game.scrap; var hp: float=float(preview.get("hp",-1))
	check(bool(preview.valid),"Actual repair preview accepts the genuine live damaged building: "+String(preview.reason))
	if use_f:await press(KEY_F)
	else:await mouse(game.camera.unproject_position(point),MOUSE_BUTTON_LEFT)
	var quote: Dictionary=game.repairs.quote_at(point)
	check(bool(quote.repairing) and game.scrap==before and float(quote.hp)==hp,"Actual repair toggle records intent without immediate payment or healing")
	await press(KEY_ESCAPE)
	check(not game.construction.active and not game.construction.repair_mode and bool(game.repairs.quote_at(point).repairing),"Actual Escape exits the tool while retaining the repair intent")

func district_at(kind: String) -> int:
	for plot: Dictionary in game.districts.plots:
		if String(plot.kind)==kind and int(plot.level)>0 and not bool(plot.get("removed",false)):return int(plot.index)
	return -1

func all_buildings() -> Array[Dictionary]:
	var result: Array[Dictionary]=[{"type":"tower","index":0,"kind":"tower","point":game.world.tower_pads[0].position}]
	for row: Dictionary in [{"kind":"barracks","point":BARRACKS},{"kind":"workshop","point":WORKSHOP},{"kind":"recycler","point":RECYCLER_POINT},{"kind":"laboratory","point":LAB},{"kind":"depot","point":DEPOT},{"kind":"infirmary","point":INFIRMARY},{"kind":"armory","point":ARMORY}]:
		var index: int=await build_gui(String(row.kind),row.point)
		if index<0:return []
		result.append({"type":"district","index":index,"kind":row.kind,"point":game.districts.plots[index].position})
	return result

func building(row: Dictionary) -> Dictionary:
	return game.world.tower_pads[int(row.index)] if String(row.type)=="tower" else game.districts.plots[int(row.index)]

func damage(row: Dictionary,amount: float) -> void:
	if String(row.type)=="tower":game.damage_tower(int(row.index),amount)
	else:check(bool(game.districts.damage(int(row.index),amount).ok),"Actual district damage accepts the precision amount")

func toggle(row: Dictionary) -> void:
	check(game.repairs.toggle_at(row.point),"Service accepts genuine damaged "+String(row.kind)+" identity")

func physical_input() -> void:
	await fresh(); var pad: Dictionary=game.world.tower_pads[0]; game.damage_tower(0,160)
	stand(game.building_approach_position(HOME,pad.position,"tower")); var before: int=game.scrap
	await press(KEY_H)
	check(game.scrap==before-20 and float(pad.hp)==float(pad.max_hp)-60 and game.repairs.snapshot().targets.is_empty(),"Outside Y the original nearby H still pays20 and restores100 without starting remote repair")
	stand(HOME); await repair_gui(pad.position,true)
	var intent: Dictionary=game.repairs.snapshot(); var goal: Vector3=game.move_goal
	for code: int in [KEY_ESCAPE,KEY_Y]:
		await begin_repair(pad.position); await press(code)
		check(not game.construction.active and game.repairs.snapshot()==intent and game.move_goal==goal,"Actual tool exit preserves the same intent and hero order")
	await begin_repair(pad.position); await mouse(game.camera.unproject_position(pad.position),MOUSE_BUTTON_RIGHT)
	check(not game.construction.active and game.repairs.snapshot()==intent and game.move_goal==goal,"Actual right cancellation swallows the world command and keeps all repairs")
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport
		await begin_repair(pad.position); var old: Dictionary=state()
		await click_ui(REPAIR_RECT)
		check(game.construction.active and not game.construction.repair_mode and not game.construction.sell_mode and state()==old,"Visible H button owns its click and returns to placement without toggling a world building")
		await click_ui(REPAIR_RECT)
		check(game.construction.repair_mode and state()==old,"Visible H button enters repair without charging or passing through")
		await click_ui(SELL_RECT)
		check(game.construction.sell_mode and not game.construction.repair_mode,"Actual Del button makes sell and repair mutually exclusive")
		await press(KEY_H)
		check(game.construction.repair_mode and not game.construction.sell_mode,"Actual H leaves sell before entering repair")
		await press(KEY_1)
		check(game.construction.active and not game.construction.repair_mode and not game.construction.sell_mode,"Actual numeric type selection returns to construction")
		await press(KEY_H); await press(KEY_PAGEDOWN)
		check(game.construction.active and not game.construction.repair_mode,"Actual page key leaves repair and selects ordinary construction")
		await press(KEY_H); await click_ui(game.hud.construction_page_rect(-1))
		check(game.construction.active and not game.construction.repair_mode,"Actual visible page button also leaves repair")
		await press(KEY_ESCAPE); clear_transients(); await redraw(); camera_at(HOME)
		var screen: Vector2=REPAIR_RECT.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900)
		goal=game.move_goal; await mouse(screen,MOUSE_BUTTON_RIGHT)
		check(not game.construction.active and game.move_goal!=goal and not game.hero_path.is_empty(),"The hidden H button area passes actual right-click to world navigation")
		stand(HOME); goal=game.move_goal
	root.size=VIEWPORTS[0]; root.content_scale_size=VIEWPORTS[0]
	await begin_repair(pad.position); await press(KEY_F3)
	check(game.construction.active and game.construction.repair_mode and game.hud.detail_tab.is_empty() and game.repairs.snapshot()==intent,"Original construction priority consumes F3 while keeping the exclusive repair tool and intent")
	await press(KEY_F); check(not bool(game.repairs.quote_at(pad.position).repairing),"Actual F on an active live target stops only that repair")
	await mouse(game.camera.unproject_position(pad.position),MOUSE_BUTTON_LEFT)
	check(bool(game.repairs.quote_at(pad.position).repairing) and not game.selection_dragging,"Actual left toggle consumes selection input and starts the same genuine target")
	await press(KEY_ESCAPE)
	var barracks: int=await build_gui("barracks",BARRACKS)
	await open_army(); await click_ui(game.hud.RALLY_SELECTOR_RECT); await click_ui(game.hud.RALLY_SET_RECT)
	check(game.rally.active,"Actual existing army controls begin exclusive rally selection")
	before=game.scrap; intent=game.repairs.snapshot(); await press(KEY_H); await press(KEY_F)
	check(game.rally.active and game.scrap==before and game.repairs.snapshot()==intent and not game.construction.active,"Rally selection owns H/F without nearby repairs/upgrades or new tool activation")
	await press(KEY_ESCAPE); check(not game.rally.active and barracks>=0,"Actual Esc cancels only the exclusive rally selector")
	evidence.input.append({"viewports":VIEWPORTS,"repair_rect":REPAIR_RECT,"sell_rect":SELL_RECT,"tool_rect":TOOL_RECT,"original_h_cost":20}); stage_returned=true

func real_accounts() -> void:
	await fresh(); var rows: Array[Dictionary]=await all_buildings(); if rows.size()!=8:return
	var investments: Array[int]=[]; var models: Array[int]=[]; var starting_hp: Array[float]=[]
	for row: Dictionary in rows:
		var target: Dictionary=building(row); damage(row,30.0); investments.append(int(target.get("paid_investment",0))); models.append(int(plain(target.get("turret") if row.type=="tower" else target.get("model")))); starting_hp.append(float(target.hp))
		var preview: Dictionary=game.repairs.quote_at(row.point)
		check(bool(preview.valid) and String(preview.target_type)==row.type and int(preview.target_index)==int(row.index) and int(preview.cost)==5,"Live "+String(row.kind)+" quote exposes the sole real identity/HP and current5 price")
		for cell: Vector2i in Grid.placement(row.point,String(row.kind)).cells:
			var middle: Vector2=Grid.cell_rect(cell).get_center(); var picked: Dictionary=game.repairs.quote_at(Vector3(middle.x,5,middle.y))
			check(bool(picked.valid) and int(picked.target_index)==int(row.index) and String(picked.target_type)==row.type,"Every occupied building cell resolves the same repair identity")
		toggle(row)
	var before: int=game.scrap; var snapshot: Dictionary=state()
	for _read in 20:
		for row: Dictionary in rows:game.repairs.quote_at(row.point)
		game.repairs.snapshot()
	check(state()==snapshot,"Quotes and ordered snapshot are pure reads of HP/wallet/models/clocks/RNG/queues")
	step(.99); check(game.scrap==before,"All eight genuine targets cannot spend before one second")
	for index in rows.size():check(float(building(rows[index]).hp)==starting_hp[index],"All eight HP values stay unchanged before the real deadline")
	step(.011); check(game.scrap==before-40,"Eight buildings share the sole wallet and pay eight full5 chunks")
	for index in rows.size():check(float(building(rows[index]).hp)==starting_hp[index]+25.0,"Every genuine target receives exactly25 HP on its first paid second")
	step(1.0); check(game.scrap==before-80 and game.repairs.snapshot().targets.is_empty(),"Final5HP deficits each pay full5 and automatically stop")
	for index in rows.size():
		var row: Dictionary=rows[index]; var target: Dictionary=building(row)
		check(float(target.hp)==float(target.max_hp) and int(target.get("paid_investment",0))==investments[index],"Repair fills "+String(row.kind)+" without increasing paid investment")
		check(int(plain(target.get("turret") if row.type=="tower" else target.get("model")))==models[index],"Repair preserves "+String(row.kind)+" real model identity")
		var sale: Dictionary=game.demolition_at(row.point)
		check(int(sale.refund)==investments[index]/2,"Actual demolition quote excludes both repair payments from half-investment refund")
	before=game.scrap; step(3.0); check(game.scrap==before,"Full or auto-stopped structures never charge extra")
	var tower: Dictionary=rows[0]; damage(tower,100); toggle(tower); step(.5)
	var workshop: int=district_at("workshop"); before=game.scrap
	check(bool(game.districts.upgrade(workshop).ok) and game.scrap==before-80,"Real workshop upgrade pays80 and refills its original model")
	check(game.districts.repair_cost(5)==4,"Actual second workshop level rounds the5 chunk to4")
	before=game.scrap; step(.501); check(game.scrap==before-4,"A repair deadline re-reads the now-live upgraded workshop discount")
	game.districts.damage(workshop,100000.0); check(game.districts.repair_cost(5)==5,"Genuine workshop destruction immediately removes its discount")
	before=game.scrap; step(1.0); check(game.scrap==before-5,"Subsequent repair chunk re-reads the destroyed-workshop price")
	evidence.accounts.append({"kinds":Catalog.BUILDING_IDS,"first_chunk":40,"partial_final_chunk":40,"investment":investments,"workshop_prices":[5,4,5]}); stage_returned=true

func rotation_result(long_delta: bool) -> Dictionary:
	await fresh(); var left: Dictionary=game.world.tower_pads[0]; var right_pad: Dictionary=game.world.tower_pads[1]
	game.damage_tower(0,150); game.damage_tower(1,150); game.scrap=15
	check(game.repairs.toggle_at(left.position) and game.repairs.toggle_at(right_pad.position),"Ordered fixture genuinely enables both damaged towers")
	if long_delta:game.repairs.tick(3.0)
	else:
		for _second in 3:game.repairs.tick(1.0)
	return {"left":left.hp,"right":right_pad.hp,"parts":game.scrap,"targets":game.repairs.snapshot().targets}

func true_timing() -> void:
	var long_result: Dictionary=await rotation_result(true); var short_result: Dictionary=await rotation_result(false)
	check(long_result==short_result,"tick3 and three tick1 calls are equivalent with ordered same-time payments and insufficient money")
	check(float(long_result.left)==180.0 and float(long_result.right)==155.0 and int(long_result.parts)==0,"Three available chunks go left/right/left instead of first-building monopoly")
	await fresh(); var left: Dictionary=game.world.tower_pads[0]; var right_pad: Dictionary=game.world.tower_pads[1]
	game.damage_tower(0,100); game.damage_tower(1,100); game.scrap=5
	check(game.repairs.toggle_at(right_pad.position) and game.repairs.toggle_at(left.position),"Reverse activation records a different stable order")
	game.repairs.tick(1.0)
	check(float(right_pad.hp)==205.0 and float(left.hp)==180.0 and game.scrap==0,"Exact one-price balance serves the first activated genuine target only")
	check(repair_row("tower",0).status=="waiting" and is_zero_approx(float(repair_row("tower",0).elapsed)),"Insufficient second target retains intent and resets elapsed immediately")
	game.repairs.tick(12.0); game.scrap=5
	game.repairs.tick(.99); check(game.scrap==5 and float(left.hp)==180.0,"Returning money cannot pay an overdue backlog before a fresh complete second")
	game.repairs.tick(.011); check(game.scrap==0 and float(right_pad.hp)==230.0 and float(left.hp)==180.0,"Returning funds retain activation order and pay exactly one current chunk")
	game.repairs.stop("tower",1); game.scrap=4; game.repairs.tick(7.0)
	check(game.scrap==4 and float(left.hp)==180.0 and not repair_row("tower",0).is_empty(),"Four parts cannot partly pay or heal the five-part repair and do retain intent")
	game.scrap=5; game.repairs.tick(.99); check(game.scrap==5,"Waiting target restarts from zero after prolonged insufficient funding")
	game.repairs.tick(.011); check(game.scrap==0 and float(left.hp)==205.0,"Full new second earns one25HP payment with no backlog")
	game.scrap=100; game.repairs.tick(.5); check(game.repairs.toggle_at(left.position),"Actual second toggle stops one target")
	check(repair_row("tower",0).is_empty(),"Stopped target is removed synchronously")
	check(game.repairs.toggle_at(left.position),"Actual third toggle enables a fresh repair interval")
	var before: int=game.scrap; game.repairs.tick(.501)
	check(game.scrap==before and float(left.hp)==205.0,"Stop/re-enable cannot inherit the former half-second")
	game.repairs.tick(.5); check(game.scrap==before-5 and float(left.hp)==230.0,"Fresh toggled interval pays only after its new complete second")
	var unchanged: Dictionary=state()
	for delta: float in [-1.0,NAN,INF,0.0]:game.repairs.tick(delta)
	check(state()==unchanged,"Nonpositive or nonfinite service delta cannot corrupt timers, wallet, HP or identity")
	game.repairs.stop_type("tower"); check(game.repairs.snapshot().targets.is_empty(),"Type-scoped stop removes every actual tower order")
	evidence.timing.append({"long_delta":long_result,"split_delta":short_result,"original_order":[0,1],"reverse_order":[1,0],"waiting_restarts":true}); stage_returned=true

func engineer_finish() -> void:
	engineer_returned=false
	await fresh(); await build_gui("barracks",BARRACKS); var group: Dictionary=await train("engineer"); if group.is_empty():return
	for slot in [0,2]:
		var casualty: BattleUnit=group.members[slot]; casualty.hurt(100000.0,null)
	await process_frame
	check(group.members[0]==null and group.members[2]==null,"Engineer isolation uses two genuine lethal casualties and actual roster cleanup")
	var member: BattleUnit=group.members[1]; var pad: Dictionary=game.world.tower_pads[0]
	var station: Vector3=game.building_approach_position(HOME,pad.position,"tower")
	check(station.is_finite() and game.outpost_walkable(station) and planar(station,pad.position)<=4.2,"Remaining genuine engineer starts on exposed walkable repair ground")
	member.position=station; member.path.clear(); member.moving=false; await select_group(group)
	check(bool(game.squads.command_guard(station).ok),"Original guard command keeps the living paid engineer stationary")
	member.set_meta("support_timer",1.0); game.damage_tower(0,20.0); check(game.repairs.toggle_at(pad.position),"Concurrent remote repair enables the same twenty-HP-deficit tower")
	var before: int=game.scrap; step(.99)
	check(float(pad.hp)==float(pad.max_hp)-20.0 and game.scrap==before,"Both genuine engineer and remote repair wait their full second")
	step(.011)
	check(float(pad.hp)==float(pad.max_hp) and game.scrap==before-2 and game.repairs.snapshot().targets.is_empty(),"Earlier original engineer settlement pays2, fills20, and prevents a zero-deficit remote5 charge")
	before=game.scrap; step(1.0); check(game.scrap==before,"Full-health engineer and stopped remote intent cannot double-charge next second")
	evidence.cooperation.append({"kind":"engineer","trained_cost":65,"final_restore":20,"paid":2,"remote_paid":0}); engineer_returned=true

func original_cooperation() -> void:
	await fresh(); var pad: Dictionary=game.world.tower_pads[0]; game.damage_tower(0,50)
	check(game.repairs.toggle_at(pad.position),"Concurrent original-H fixture enables genuine remote intent")
	game.repairs.tick(.99); stand(game.building_approach_position(HOME,pad.position,"tower")); var before: int=game.scrap
	await press(KEY_H)
	check(float(pad.hp)==float(pad.max_hp) and game.scrap==before-20 and game.repairs.snapshot().targets.is_empty(),"Original real H finishing a fifty-HP deficit removes remote intent immediately")
	game.repairs.tick(2.0); check(game.scrap==before-20,"An already H-filled building incurs no later remote charge")
	stand(HOME); game.damage_tower(0,.25); check(game.repairs.toggle_at(pad.position),"Fractional quarter-HP deficit is a genuine damaged target")
	before=game.scrap; step(1.0)
	check(float(pad.hp)==float(pad.max_hp) and game.scrap==before-5 and game.repairs.snapshot().targets.is_empty(),"Quarter-HP final chunk pays the whole current5 exactly once and stops")
	await engineer_finish(); check(engineer_returned,"Engineer concurrency substage reaches its full completion marker")
	stage_returned=true

func true_identity() -> void:
	for target_type: String in ["tower","district"]:
		await fresh(); var index := 0
		if target_type=="district":index=await build_gui("barracks",BARRACKS)
		var target: Dictionary=game.world.tower_pads[index] if target_type=="tower" else game.districts.plots[index]
		var row: Dictionary={"type":target_type,"index":index,"kind":"tower" if target_type=="tower" else "barracks","point":target.position}
		damage(row,100); toggle(row); game.repairs.tick(.99)
		var original_model: Variant=target.get("turret") if target_type=="tower" else target.get("model"); var model_token: int=int(plain(original_model))
		damage(row,100000.0)
		check(repair_row(target_type,index).is_empty() and not bool(game.repairs.quote_at(row.point).valid),"True destruction synchronously stops the old "+target_type+" and rejects its ruin")
		await process_frame; check(not is_instance_id_valid(model_token),"Actual destruction releases the bound old "+target_type+" model")
		var before: int=game.scrap
		if target_type=="tower":check(game.build_or_upgrade_tower(index),"Original true foundation API rebuilds the destroyed tower")
		else:check(await build_gui("barracks",row.point)==index,"True district ruin rebuild keeps its stable index")
		check(game.scrap==before-60 and int(plain(target.get("turret") if target_type=="tower" else target.get("model")))!=model_token,"Same-number rebuild pays60 for a genuinely new model generation")
		damage(row,70); before=game.scrap; game.repairs.tick(1.0)
		check(game.scrap==before and float(target.hp)==float(target.max_hp)-70.0 and repair_row(target_type,index).is_empty(),"Rebuilt same-number "+target_type+" never inherits old elapsed or intent")
		toggle(row); game.repairs.tick(.99); var rebuilt_model: int=int(plain(target.get("turret") if target_type=="tower" else target.get("model")))
		if target_type=="tower":check(game.build_or_upgrade_tower(index),"Actual tower upgrade succeeds")
		else:check(bool(game.districts.upgrade(index).ok),"Actual district upgrade succeeds")
		check(float(target.hp)==float(target.max_hp) and int(plain(target.get("turret") if target_type=="tower" else target.get("model")))==rebuilt_model and repair_row(target_type,index).is_empty(),"Original upgrade refills and stops immediately while preserving its model")
		damage(row,50); toggle(row); var investment: int=int(target.get("paid_investment",0)); before=game.scrap
		var sale: bool=game.sell_structure_at(row.point)
		check(sale and bool(target.get("removed",false)) and game.scrap==before+investment/2 and repair_row(target_type,index).is_empty(),"Genuine sale retires identity before the half-investment refund and synchronous repair removal")
		before=game.scrap; game.repairs.tick(3.0)
		check(game.scrap==before and not bool(game.repairs.quote_at(row.point).valid),"Retired footprint cannot be remotely repaired or charged")
		var next := -1
		if target_type=="tower":
			check(game.build_tower_at(row.point),"Real new free-tower placement rebuilds the cleared sale footprint"); next=game.world.tower_pads.size()-1
		else:next=await build_gui("barracks",row.point)
		check(next>index and game.repairs.snapshot().targets.is_empty(),"Same-address new building appends a stable identity without inherited repair intent")
		evidence.identity.append({"type":target_type,"old_index":index,"next_index":next,"destroyed_model":model_token,"rebuilt_model":rebuilt_model,"sale_refund":investment/2})
	await fresh(); var pad: Dictionary=game.world.tower_pads[0]; game.damage_tower(0,100); check(game.repairs.toggle_at(pad.position),"Dictionary-generation boundary begins genuine intent")
	var original: Dictionary=pad; var replacement: Dictionary=pad.duplicate()
	game.world.tower_pads[0]=replacement; var before: int=game.scrap; game.repairs.tick(1.0)
	check(game.scrap==before and float(replacement.hp)==180.0 and game.repairs.snapshot().targets.is_empty(),"A copied Dictionary with the same index/model cannot inherit original record identity")
	game.world.tower_pads[0]=original; check(game.repairs.snapshot().targets.is_empty(),"Restoring the former real record cannot resurrect its cancelled repair")
	check(game.repairs.toggle_at(original.position),"Real restored record can be explicitly enabled afresh")
	var queued: Node=original.turret; queued.queue_free(); before=game.scrap; game.repairs.tick(2.0)
	check(game.scrap==before and game.repairs.snapshot().targets.is_empty(),"Queued deletion invalidates the original model before any payment")
	await process_frame
	await fresh(); var fake := Node3D.new(); fake.position=Vector3(7,5,3.5); fake.set_meta("building_kind","tower"); fake.set_meta("hp",1.0); fake.set_meta("repairing",true); game.add_child(fake)
	var unchanged: Dictionary=state()
	check(not bool(game.repairs.quote_at(fake.position).valid) and not game.repairs.toggle_at(fake.position),"Fake node metadata cannot create a repairable building or pay from the real wallet")
	for point: Vector3 in [Vector3(INF,0,0),Vector3(NAN,5,0),Vector3(0,5,0),OPEN]:check(not bool(game.repairs.quote_at(point).valid) and not game.repairs.toggle_at(point),"Nonfinite/core/empty-world points cannot enable a fabricated repair")
	check(state()==unchanged,"Rejected fake and invalid targets preserve every authoritative state field")
	fake.queue_free(); game.repairs.clear(); game.repairs.setup(game)
	check(game.repairs.snapshot().targets.is_empty(),"Repeated actual clear/setup starts with no old target generation")
	stage_returned=true

func frozen_lifecycle() -> void:
	await fresh(); var pad: Dictionary=game.world.tower_pads[0]; game.damage_tower(0,200); await repair_gui(pad.position); step(.4)
	await press(KEY_F1)
	check(game.phase=="paused" and game.music_credits_open,"Actual F1 source page pauses a partially elapsed paid repair")
	var before: Dictionary=state(); await press(KEY_H); await press(KEY_Y); await press(KEY_F); game.simulate(5.0); game.repairs.tick(5.0)
	check(state()==before,"Sources/pause freeze real repair elapsed/HP/wallet and reject original keys plus direct service ticking")
	await press(KEY_ESCAPE); check(game.phase=="paused" and not game.music_credits_open and state()==before,"First actual Escape dismisses sources while keeping the frozen pause")
	await press(KEY_ESCAPE); check(game.phase=="night","Second actual Escape resumes the original night")
	var paid_before: int=game.scrap; await press(KEY_V)
	check(game.phase=="draft" and game.scrap<paid_before,"Actual V buys the original real card offer")
	before=state(); await press(KEY_H); await press(KEY_Y); game.simulate(5.0); game.repairs.tick(5.0)
	check(state()==before,"Paid card selection freezes genuine repair intent, elapsed, HP and wallet")
	await press(KEY_1); check(game.phase=="night" and not repair_row("tower",0).is_empty(),"Actual card choice retains the old repair intent")
	var parts: int=game.scrap; step(.599); check(game.scrap==parts,"Resume consumes only the remaining original interval")
	step(.002); check(game.scrap==parts-5,"Unfrozen partial interval pays at exactly its next complete second")
	TransitionFixture.finish_for_fixture(game); check(game.phase=="draft" and not repair_row("tower",0).is_empty(),"Actual dawn preserves repair intent during its real card draft")
	before=state(); game.simulate(3.0); game.repairs.tick(3.0); check(state()==before,"Dawn draft remains frozen")
	await press(KEY_1); check(game.phase=="day" and not repair_row("tower",0).is_empty(),"Actual daylight resumes the same bound building")
	game.start_night(); clear_enemies(); game.phase_time=10000.0; game.wave_index=game.WAVES_PER_NIGHT
	check(not repair_row("tower",0).is_empty(),"Actual day/night transition retains repair intent")
	for mode: String in ["clear","setup","defeat","victory","shutdown"]:
		await fresh(); pad=game.world.tower_pads[0]; game.damage_tower(0,100); check(game.repairs.toggle_at(pad.position),"Lifecycle "+mode+" has a real pending repair"); game.repairs.tick(.99)
		parts=game.scrap
		match mode:
			"clear":game.repairs.clear()
			"setup":game.repairs.setup(game)
			"defeat":game.hero.hurt(100000.0,null)
			"victory":game.day_number=game.max_nights(); TransitionFixture.finish_for_fixture(game)
			"shutdown":await game.prepare_shutdown()
		check(game.repairs.snapshot().targets.is_empty(),"Actual "+mode+" clears orders synchronously")
		game.repairs.tick(5.0); check(game.scrap==parts and float(pad.hp)==180.0,"Old near-due "+mode+" repair cannot charge or heal after lifecycle boundary")
		evidence.lifecycle.append({"mode":mode,"phase":game.phase,"parts":parts,"hp":pad.hp})
	await fresh(); pad=game.world.tower_pads[0]; game.damage_tower(0,100); await repair_gui(pad.position); step(.99)
	var old_root: int=game.get_instance_id(); var old_model: int=int(plain(pad.turret)); game.hero.hurt(100000.0,null); await press(KEY_ENTER)
	for _frame in 240:
		if current_scene!=null and current_scene.get_instance_id()!=old_root:break
		await create_timer(.02,true,false,true).timeout
	check(current_scene!=null and current_scene.get_instance_id()!=old_root,"Actual Enter retry constructs a new scene")
	if current_scene==null or current_scene.get_instance_id()==old_root:return
	game=current_scene as Node3D; game.set_process(false); game.world.set_process(false)
	for _frame in 5:await process_frame
	check(not is_instance_id_valid(old_root) and not is_instance_id_valid(old_model) and game.run.seed_value==SEED and game.scrap==90 and game.phase=="draft" and game.repairs.snapshot().targets.is_empty(),"True same-seed retry releases old root/model and restores90/opening draft without repair inheritance")
	stage_returned=true

func label_rect(row: Dictionary) -> Rect2:
	return Rect2(Vector2(float(row.point.x),float(row.point.y)-float(row.ascent)),Vector2(float(row.width),float(row.ascent)+float(row.descent)))

func measure_repairs_hud(tag: String,tool: bool=false,help: bool=false) -> void:
	var before: Dictionary=state(); var old_size: Vector2i=root.size
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport; await redraw()
		var repair_seen := false; var help_seen := false; var bottom := 0.0; var button_seen := false
		for row: Dictionary in game.hud.drawn_labels:
			var text: String=String(row.text); var glyph: Rect2=label_rect(row)
			check(Rect2(0,0,1440,900).encloses(glyph),"Actual repair glyph bounds fit "+tag+" "+str(viewport)+": "+text)
			for character: String in text:
				var code: int=character.unicode_at(0)
				if code>=0x4e00 and code<=0x9fff:check(game.hud.font.has_char(code),"Real font supplies Chinese repair glyph "+character)
			if tool and bool(row.get("toolbar",false)):
				check(TOOL_RECT.encloses(glyph),"Complete repair toolbar glyph stays within its original570-by140 rectangle")
				if text.contains("维修"):repair_seen=true
				if text.begins_with("H "):button_seen=true; check(REPAIR_RECT.encloses(glyph),"Complete H button glyph stays inside its actual112-by26 hit rectangle")
				if row.point==Vector2(457,766):check(glyph.end.x<=REPAIR_RECT.position.x-8,"Bottom confirmation/exit instruction leaves a real gap before H")
				if row.point==Vector2(457,714):
					for direction in [-1,1]:check(not glyph.intersects(game.hud.construction_page_rect(direction)),"Actual repair status does not intersect either real page button")
			if help and row.point.x==46 and row.point.y>=230:
				bottom=maxf(bottom,glyph.end.y); check(float(row.width)<=496,"Every actual help row stays in the existing496px column")
				if text.contains("维修") and (text.contains("Y") or text.contains("H")):help_seen=true
		check(not tool or (TOOL_RECT in game.hud.drawn_rects and REPAIR_RECT in game.hud.drawn_rects and repair_seen and button_seen),"Actual repair toolbar and H button are drawn once within existing controls")
		check(not help or (help_seen and bottom<=660.0),"Complete repair help stays above the existing footer/close area without adding rows")
		for direction in [-1,1]:check(not REPAIR_RECT.intersects(game.hud.construction_page_rect(direction)),"H hit rectangle does not overlap either real pagination button")
		check(not REPAIR_RECT.intersects(SELL_RECT),"H and Del actual click rectangles remain disjoint")
		evidence.hud.append({"tag":tag,"viewport":viewport,"help_bottom":bottom,"repair_seen":repair_seen,"button_seen":button_seen,"rectangles":game.hud.drawn_rects.duplicate(),"labels":game.hud.drawn_labels.duplicate(true)})
	check(state()==before,"Three viewport drawing/font observation never advances real repair/world state")
	root.size=old_size; root.content_scale_size=old_size; await redraw()

func actual_hud() -> void:
	await fresh(); TransitionFixture.finish_for_fixture(game); await press(KEY_1); clear_enemies(); game.phase_time=90.0; stand(HOME); clear_transients(); await redraw()
	var baseline: Array=game.hud.live_panel_rects().duplicate(); await measure_repairs_hud("default-day"); await capture("repair-default-day")
	var pad: Dictionary=game.world.tower_pads[0]; game.damage_tower(0,80); await begin_repair(pad.position); clear_transients()
	await measure_repairs_hud("repair-toolbar",true); await capture("repair-toolbar")
	await press(KEY_F); await press(KEY_ESCAPE); clear_transients(); await redraw()
	check(game.hud.live_panel_rects()==baseline,"Active remote repair adds local world markers and keeps default permanent input/panel rectangles unchanged")
	var marker := false
	for row: Dictionary in game.hud.drawn_labels:
		if row.text=="维修":marker=true; check(int(row.size)==12,"Actual local repair marker uses the promised compact12px font")
	check(marker,"Actual building-bound marker truthfully shows a live repair")
	game.scrap=4; step(1.0); clear_transients(); await begin_repair(pad.position)
	check(repair_row("tower",0).status=="waiting","Actual insufficient funds produce the true waiting state")
	await measure_repairs_hud("waiting-toolbar",true); await capture("repair-waiting-money")
	await press(KEY_ESCAPE); clear_transients(); await redraw(); marker=false
	for row: Dictionary in game.hud.drawn_labels:if row.text=="待零件":marker=true
	check(marker and game.hud.live_panel_rects()==baseline,"Actual waiting marker is local and adds no persistent input/panel rectangle")
	game.scrap=50; await advance(4.001); clear_transients(); await redraw()
	check(game.repairs.snapshot().targets.is_empty() and float(pad.hp)==float(pad.max_hp) and game.hud.live_panel_rects()==baseline,"Actual paid completion removes repair intent and restores precisely the default permanent rectangles")
	for row: Dictionary in game.hud.drawn_labels:check(row.text not in ["维修","待零件"],"Stopped/full building draws no obsolete repair marker")
	await begin_repair(pad.position); clear_transients(); await measure_repairs_hud("full-stopped-toolbar",true); await capture("repair-full-stopped")
	await press(KEY_ESCAPE); await press(KEY_F3); await click_ui(game.hud.details_tab_rect(4)); clear_transients()
	check(game.hud.detail_tab=="help","Actual F3 opens the existing operation drawer")
	await measure_repairs_hud("repair-help",false,true); await capture("repair-help")
	await close_drawer(); await true_warning_overlap()
	check(warning_returned,"Native danger-circle substage reaches its complete production/drawing evidence marker")
	stage_returned=true

func true_warning_overlap() -> void:
	warning_returned=false
	var group: Dictionary=await ready("shield",true); if group.is_empty():return
	var pad: Dictionary=game.world.tower_pads[0]; var ally: BattleUnit=group.members[1]
	var station: Vector3=pad.position+Vector3(0,0,-4.0); station.y=game.outpost_height(station)
	check(game.outpost_walkable(station),"Danger-circle fixture places the actual paid shield on open courtyard ground four metres behind its tower")
	check(bool(game.squads.command_guard(station).ok),"Actual selected shield receives the original stationary guard command")
	ally.position=station; ally.path.clear(); ally.moving=false
	stand(HOME); game.damage_tower(0,100); check(game.repairs.toggle_at(pad.position),"Danger-circle witness enables a genuine damaged-tower repair")
	var source: BattleUnit=spawn(station+Vector3(0,0,1.4)); source.attack_timer=0.0
	step(.001,false); camera_at(pad.position); clear_transients()
	var warnings: Array[Dictionary]=game.target_warning_snapshot(); var locked: Dictionary={}
	for warning: Dictionary in warnings:
		if warning.source==source and warning.target==ally:locked=warning
	check(source.attack_queued and not locked.is_empty() and float(locked.get("remaining",0))>0.0,"Native enemy simulation commits a genuine positive windup against the living friendly shield")
	if locked.is_empty():return
	var before: Dictionary=state(); var old_size: Vector2i=root.size
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport; await redraw()
		var factor: Vector2=Vector2(1440,900)/game.hud.get_viewport_rect().size
		var marker_anchor: Vector2=game.camera.unproject_position(pad.position+Vector3.UP*2.8)*factor
		var marker_rect:=Rect2(marker_anchor-Vector2(38,24),Vector2(76,24))
		var danger_center: Vector2=game.camera.unproject_position(ally.global_position+Vector3.UP*1.05)*factor
		var progress_value: float=float(locked.progress); var radius: float=16.0+1.5*progress_value; var extent: float=radius+6.5
		var danger_rect:=Rect2(danger_center-Vector2.ONE*extent,Vector2.ONE*extent*2)
		var progress_rect:=Rect2(danger_center+Vector2(-6.5,-radius-10.5),Vector2(13,5))
		check(marker_rect.intersects(danger_rect),"Actual projected friendly danger circle intersects the proposed local repair marker in "+str(viewport))
		check(danger_rect in game.hud.world_warning_rects and progress_rect in game.hud.world_warning_rects,"Actual drawing reserves both native danger ring and progress-bar boundaries")
		var lock_text := false; var repair_text := false
		for label_row: Dictionary in game.hud.drawn_labels:
			if String(label_row.text).begins_with("蓄力 "):
				lock_text=true; check(not label_rect(label_row).intersects(marker_rect),"Native lock text alone would leave the overlapping repair marker apparently free")
			if label_row.text in ["维修","待零件"]:repair_text=true
		check(lock_text and not repair_text and not (marker_rect in game.hud.drawn_rects),"Actual local repair marker yields to the still-visible native danger ring despite nonoverlapping lock text")
		evidence.hud.append({"tag":"native-danger-circle-priority","viewport":viewport,"source":source.get_instance_id(),"target":ally.get_instance_id(),"remaining":locked.remaining,"marker_rect":marker_rect,"danger_rect":danger_rect,"progress_rect":progress_rect,"lock_text":lock_text,"repair_text":repair_text})
	check(state()==before,"Danger-priority drawing never advances the real queued attack, repair or wallet")
	await capture("repair-native-danger-priority")
	root.size=old_size; root.content_scale_size=old_size; await redraw()
	warning_returned=true

func natural_tick() -> void:
	# Initial passive movement lets unchanged real enemies reach a gifted tower.
	# After the first genuine payment, use the already established fixed policy.
	if repair_natural_paid:
		game.aim=game.hero.position+Vector3(0,0,8)
		if game.gate_pressure()>0:game.cast(0)
		if game.hero.hp<game.hero.max_hp*.6:game.cast(1); game.cast(4)
		if game.gate_pressure()>=6:game.cast(3)
	step()

func natural_economy() -> void:
	await fresh(false); await right(Vector3(0,5,-6))
	var chosen := -1; var payments: Array[Dictionary]=[]; var opened := false; var first_damage: Dictionary={}; var opening_models: Array[int]=[]; var return_order: Dictionary={}
	for pad: Dictionary in game.world.tower_pads:opening_models.append(int(plain(pad.turret)))
	var first_night_elapsed := 0.0
	var first_night_cutoff: Dictionary = {}
	# Bound actual residual combat; the production assault deadline is unchanged.
	for frame in ceili(240.0 / STEP):
		if game.phase!="night":break
		if chosen<0:
			for index in game.world.tower_pads.size():
				var pad: Dictionary=game.world.tower_pads[index]
				if int(pad.level)>0 and float(pad.hp)>0 and float(pad.hp)<float(pad.max_hp):chosen=index; break
			if chosen>=0:
				var pad: Dictionary=game.world.tower_pads[chosen]
				check(not game.observed_building_damage.is_empty(),"Natural activation follows a recorded genuine enemy damage_tower callback")
				first_damage=game.observed_building_damage[-1].duplicate(true)
				check(int(plain(pad.turret))==opening_models[chosen],"Natural damaged building is the original gifted model")
				await repair_gui(pad.position,true); opened=true
		var hp := 0.0; var parts: int=game.scrap; var kills: int=game.kills; var damage_count: int=game.observed_building_damage.size(); var timer_before := -1.0
		if chosen>=0:
			hp=float(game.world.tower_pads[chosen].hp)
			var row: Dictionary=repair_row("tower",chosen)
			if not row.is_empty():timer_before=float(row.elapsed)
		natural_tick()
		first_night_elapsed += STEP
		if first_night_cutoff.is_empty() and first_night_elapsed >= game.NIGHT_LENGTH:
			first_night_cutoff = TransitionFixture.deadline_evidence(game, first_night_elapsed)
		if chosen>=0:
			var loss := 0.0
			for event_index in range(damage_count,game.observed_building_damage.size()):
				var event: Dictionary=game.observed_building_damage[event_index]
				if int(event.index)==chosen:loss+=float(event.loss)
			var restored: float=float(game.world.tower_pads[chosen].hp)-hp+loss
			if restored>0.0001:
				check(restored<=25.0001 and timer_before>=.899,"Natural repair restores at most25 only after its original full-second intent")
				if kills==game.kills:check(game.scrap==parts-5,"Natural no-kill settlement pays the original full5 from the sole wallet")
				payments.append({"before":parts,"after":game.scrap,"kills_before":kills,"kills_after":game.kills,"restored":restored,"damage_same_step":loss,"hp_before":hp,"hp_after":game.world.tower_pads[chosen].hp,"time":game.phase_time,"day":game.day_number})
				if not repair_natural_paid:
					repair_natural_paid=true
					var actual_goal: Vector3=await right(Vector3(0,5,10))
					return_order={"goal":actual_goal,"hero_position":game.hero.position,"time":game.phase_time,"path":game.hero_path.duplicate()}
					check(not game.hero_path.is_empty(),"After first genuine repair payment, actual right-click returns the natural hero to the original gate-defense route")
		if frame%100==99:await process_frame
	TransitionFixture.record_natural_receipt(game, evidence, "opening", first_night_elapsed, first_night_cutoff)
	check(opened and chosen>=0 and repair_natural_paid and not payments.is_empty(),"Original90/105 route genuinely receives enemy tower damage and pays at least one remote repair without artificial funding or damage")
	check(game.hero.alive and game.beacon_hp>0 and game.phase=="draft","This original fixed-seed natural repair route reaches genuine first dawn")
	if game.phase!="draft":return
	var dawn_parts: int=game.scrap; var dawn_kills: int=game.kills; await press(KEY_1)
	check(game.phase=="day" and game.phase_time==90.0 and game.scrap==dawn_parts,"True dawn retains the original90-second day and real remaining balance")
	var had_intent: bool=not repair_row("tower",chosen).is_empty(); var day_start_hp: float=float(game.world.tower_pads[chosen].hp); var after := dawn_parts
	for frame in 100:
		if repair_row("tower",chosen).is_empty():break
		var before: int=game.scrap; var hp: float=float(game.world.tower_pads[chosen].hp); var count: int=game.kills
		natural_tick()
		if game.scrap<before and float(game.world.tower_pads[chosen].hp)>hp:
			check(game.scrap==before-5 and game.kills==count,"Natural daylight continuation pays each whole5 without a kill-income ambiguity")
			payments.append({"before":before,"after":game.scrap,"restored":float(game.world.tower_pads[chosen].hp)-hp,"day":game.day_number,"time":game.phase_time})
		after=game.scrap
		if frame%100==99:await process_frame
	evidence.economy.append({"seed":SEED,"opening":90,"night_seconds":105,"day_seconds":90,"target":chosen,"original_model":opening_models[chosen],"first_real_damage":first_damage,"all_real_tower_damage":game.observed_building_damage.duplicate(true),"payments":payments,"actual_return_order":return_order,"dawn_parts":dawn_parts,"dawn_kills":dawn_kills,"dawn_pending":had_intent,"day_start_hp":day_start_hp,"final_parts":after,"final_hp":game.world.tower_pads[chosen].hp,"hero_hp":game.hero.hp,"beacon_hp":game.beacon_hp,"scope":"one unchanged-seed passive-first/actual-right-return/skill-after-payment scripted route; original90/105/90; genuine enemy damage and paid repair only; no injected money, actors, damage, placement, phase extension, enemy deletion/stats changes or human-balance claim"})
	print("REPAIR_NATURAL target=",chosen," payments=",payments.size()," dawn_parts=",dawn_parts," dawn_kills=",dawn_kills," final_parts=",after)
	stage_returned=true

func capture(tag: String) -> void:
	var before: int=evidence.captures.size(); await super.capture(tag)
	for index in range(before,evidence.captures.size()):
		var name: String=String(evidence.captures[index]); var path: String=ProjectSettings.globalize_path(output_dir).path_join(name+".png")
		evidence.capture_receipt.append({"name":name,"path":path,"sha256":FileAccess.get_sha256(path),"stage":active_stage})

func finalize() -> void:
	await close_game(); await create_timer(.5,true,false,true).timeout; evidence.shutdown_audio_drain_seconds=.5
	var folder: String=ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
	var file: FileAccess=FileAccess.open(folder.path_join("nightfall-building-repairs.json"),FileAccess.WRITE)
	check(file!=null,"Independent repair evidence opens below local build")
	var receipt: FileAccess=FileAccess.open(folder.path_join("capture-receipt.json"),FileAccess.WRITE)
	check(receipt!=null,"Repair capture manifest opens below local build")
	evidence.checks=checks; evidence.failures=failures
	if file!=null:file.store_string(JSON.stringify(evidence,"\t")); file.close()
	if receipt!=null:receipt.store_string(JSON.stringify({"captures":evidence.capture_receipt,"completed":evidence.completed,"checks":checks,"failures":failures},"\t")); receipt.close()

func run() -> void:
	var cases: Dictionary={"input":physical_input,"accounts":real_accounts,"timing":true_timing,"cooperation":original_cooperation,"identity":true_identity,"lifecycle":frozen_lifecycle,"hud":actual_hud,"economy":natural_economy}
	var args: PackedStringArray=OS.get_cmdline_user_args(); var selected: Array=cases.keys(); var index: int=args.find("--case")
	if index>=0 and index+1<args.size():selected=[args[index+1]]
	for name: String in selected:
		if not cases.has(name):check(false,"Unknown independent repair stage "+name); break
		active_stage=name; stage_returned=false; print("REPAIR_STAGE_BEGIN ",name)
		await (cases[name] as Callable).call()
		check(stage_returned,"Repair stage "+name+" reaches its explicit full-body completion marker")
		print("REPAIR_STAGE_END ",name," checks=",checks," failures=",failures.size()); evidence.completed.append(name)
		if not failures.is_empty():break
	await finalize(); finished=true; print("REPAIR_RESULT checks=",checks," failures=",failures.size())
	if failures.is_empty():
		if index < 0 and (evidence.completed as Array) == cases.keys():
			print("NIGHTFALL_BUILDING_REPAIRS_OK checks=",checks," failures=0 full_suite=true")
		else:
			print("NIGHTFALL_BUILDING_REPAIRS_CASE_OK checks=",checks," failures=0 full_suite=false stages=",JSON.stringify(evidence.completed))
	else:
		print("NIGHTFALL_BUILDING_REPAIRS_FAILED checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
