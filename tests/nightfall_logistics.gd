extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
## Real finite transport production. Explicit 5000 parts/10000 seconds isolate
## transactions and paths; these fixtures do not claim economic balance.
const Catalog := preload("res://scripts/outpost_catalog.gd")
const Grid := preload("res://scripts/construction_grid.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
const RunSession := preload("res://scripts/run_session.gd")
const SEED := 20261006
const STEP := .1
const HOME := Vector3(0, 5, 3.1)
const WORKSHOP := Vector3(-7.5, 5, -8)
const BARRACKS := Vector3(7, 5, -8.5)
const DEPOT := Vector3(-7.5, 5, -3.5)
const VIEWPORTS := [Vector2i(1920, 1200), Vector2i(1920, 1080), Vector2i(1440, 900)]
const OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var drawn_rects: Array[Rect2] = []
var drawn_labels: Array[Dictionary] = []
func _draw() -> void:
\tdrawn_rects.clear(); drawn_labels.clear()
\tsuper._draw()
func box(rect: Rect2, fill: Color = Color(.022,.035,.045,.88), outline: Color = Color('435455')) -> void:
\tdrawn_rects.append(rect)
\tsuper.box(rect,fill,outline)
func label(value: String, point: Vector2, size_px: int, color: Color = Color('e7e1d3'), latin: bool = false) -> void:
\tdrawn_labels.append({'text':value,'point':point,'width':font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x})
\tsuper.label(value,point,size_px,color,latin)
"""
var game: Node3D
var failures: Array[String] = []
var checks := 0
var render_test := false
var output_dir := "res://build/transport-economy"
var depot_index := -1
var barracks_index := -1
var route_out := 0
var route_in := 0
var elapsed := 0.0
var hurt_events: Array[Dictionary] = []
var evidence: Dictionary = {"fixture_parts": 5000, "fixture_phase_seconds": 10000,
	"seed": SEED, "captures": [], "completed": [], "transport_economy": {}}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	render_test = "--render-test" in args
	var index := args.find("--output-dir")
	if index >= 0 and index + 1 < args.size():
		var candidate := ProjectSettings.globalize_path(args[index + 1]).simplify_path()
		var allowed := ProjectSettings.globalize_path("res://build").simplify_path()
		if candidate.begins_with(allowed + "/"): output_dir = candidate
	root.size = VIEWPORTS[0]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = VIEWPORTS[0]
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 30: push_error(message)

func planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = true
	root.push_input(event, true)
	event.pressed = false; root.push_input(event, true)
	await process_frame

func mouse(point: Vector2, click: bool = false, button: int = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point; motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	if not click: return
	var event := InputEventMouseButton.new()
	event.position = point; event.global_position = point; event.button_index = button
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	event.pressed = true; root.push_input(event, true)
	await process_frame
	event.button_mask = 0; event.pressed = false; root.push_input(event, true)
	await process_frame

func click_ui(rect: Rect2, button: int = MOUSE_BUTTON_LEFT) -> void:
	await mouse(rect.get_center() * game.hud.get_viewport_rect().size / Vector2(1440, 900), true, button)

func redraw() -> void:
	game.hud.queue_redraw()
	for _frame in 3: await process_frame

func stand(point: Vector3) -> void:
	point.y = game.outpost_height(point)
	game.hero.position = point; game.move_goal = point
	game.hero_path.clear(); game.hero_keyboard_active = false; game.hero.moving = false
	game.hero.set_locomotion_velocity(Vector3.ZERO)

func camera_at(point: Vector3) -> void:
	game.camera.size = 38.0
	game.camera.position = point + Vector3(0, 25, 29)
	game.camera.look_at(point); game.camera_follow = game.camera.position

func aim_at(point: Vector3) -> void:
	camera_at(point)
	await mouse(game.camera.unproject_position(point))
	game._process(0.0)

func clear_enemies() -> void:
	for enemy: BattleUnit in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()

func close_game() -> void:
	if not is_instance_valid(game): return
	var token: int = game.logistics.get_instance_id()
	await game.prepare_shutdown()
	check(game.logistics.snapshot().remaining == 0 and game.logistics.snapshot().cargo == 0,
		"Actual prepare_shutdown must clear finite heaps and every member cargo")
	if current_scene == game: current_scene = null
	game.queue_free(); game = null
	for _frame in 4: await process_frame
	check(not is_instance_id_valid(token), "Shutdown must release the real transport controller")

func fresh(keep_wave: bool = false) -> void:
	await close_game()
	check(RunSession.queue_request(self, SEED, "siege"), "Production transport must accept its real fixed standard seed")
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game); current_scene = game
	for _frame in 5: await process_frame
	game.set_process(false); game.world.set_process(false)
	var script := GDScript.new(); script.source_code = OBSERVER
	check(script.reload() == OK, "The fixed observer must compile and forward the actual production HUD")
	var original: Control = game.hud
	var layer: Node = original.get_parent()
	layer.remove_child(original); original.queue_free()
	var observed: Control = script.new()
	observed.game = game; game.hud = observed; layer.add_child(observed)
	observed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await press(KEY_1)
	check(game.phase == "night" and game.run.seed_value == SEED, "Real opening key must begin standard production night")
	if not keep_wave:
		clear_enemies(); game.phase_time = 10000.0; game.wave_index = game.WAVES_PER_NIGHT
	game.scrap = 5000
	game.hero.attack_timer = 100000.0; game.pulse_timer = 100000.0; game.spawn_timer = 100000.0
	for pad: Dictionary in game.world.tower_pads: pad.cooldown = 100000.0
	stand(HOME); elapsed = 0.0; depot_index = -1; barracks_index = -1
	var stock: Dictionary = game.logistics.snapshot()
	check(stock.remaining == 480 and stock.cargo == 0 and stock.delivered == 0 and stock.lost == 0 and stock.fields.size() == 5,
		"A new real scene must begin with five finite 96-part heaps and no inherited goods")
	for field: Dictionary in stock.fields:
		check(field.remaining == 96 and field.stock == 96 and not Layout.contains_castle(field.position)
			and game.outpost_walkable(field.position) and is_equal_approx(field.position.y, game.outpost_height(field.position)),
			"Each finite source must begin on genuine reachable outside terrain")

func state() -> Dictionary:
	var positions: Dictionary = {}
	for group: Dictionary in game.squads.squads:
		for member: BattleUnit in group.members:
			if is_instance_valid(member) and member.alive: positions[member.get_instance_id()] = member.position
	return {"stock": game.logistics.snapshot(), "parts": int(game.scrap), "positions": positions,
		"rng": game.run.rng.state, "spawn_rng": game.spawn_rng.state, "goal": game.move_goal,
		"path": game.hero_path.duplicate(), "selection": game.squads.selected_ids.duplicate(),
		"phase": String(game.phase), "time": float(game.phase_time), "queues": game.squads.training_queues.duplicate(true)}

func ledger(label: String) -> void:
	var stock: Dictionary = game.logistics.snapshot()
	check(int(stock.remaining) + int(stock.cargo) + int(stock.delivered) + int(stock.lost) == 480,
		label + ": remaining + member cargo + delivered + lost must conserve exactly 480")
	var total := 0
	var claims: Dictionary = {}
	for field: Dictionary in stock.fields:
		check(int(field.remaining) >= 0 and int(field.remaining) <= 96, label + ": no heap may go negative or refill")
		if int(field.claimed_by) >= 0:
			check(not claims.has(field.claimed_by), label + ": a team may not reserve multiple heaps")
			claims[field.claimed_by] = field.id
	for team: Dictionary in stock.teams:
		var team_total := 0
		for row: Dictionary in team.members:
			check(int(row.cargo) >= 0 and int(row.cargo) <= 8, label + ": a live token owns at most eight goods")
			team_total += int(row.cargo)
			var member := instance_from_id(int(row.token)) as BattleUnit
			if is_instance_valid(member):
				var pack := member.visual.find_child("HaulCargo", true, false) as Node3D
				check(int(member.get_meta("haul_cargo", 0)) == int(row.cargo) and is_instance_valid(pack)
					and pack.visible == (int(row.cargo) > 0), label + ": actual metadata/backpack must agree with token cargo")
		check(team_total == int(team.cargo), label + ": team cargo must equal its living token goods")
		total += team_total
	check(total == int(stock.cargo), label + ": all member goods must equal the authoritative in-transit total")

func step(delta: float = STEP) -> void:
	var before := state()
	game.simulate(delta); elapsed += delta
	var after: Dictionary = game.logistics.snapshot()
	check(int(game.scrap) == int(before.parts) + int(after.delivered) - int(before.stock.delivered),
		"Isolated production simulation pays only newly physically delivered cargo")
	for group: Dictionary in game.squads.squads:
		for member: BattleUnit in group.members:
			if not is_instance_valid(member) or not member.alive or not before.positions.has(member.get_instance_id()): continue
			var previous: Vector3 = before.positions[member.get_instance_id()]
			check(member.position.is_finite() and game.outpost_walkable(member.position)
				and absf(member.position.y - game.outpost_height(member.position)) < .001,
				"Actual carriers remain on finite walkable real terrain")
			check(game.can_traverse(previous, member.position) and planar(previous, member.position) <= member.speed * delta + .001,
				"A real carrier step cannot cross geometry or teleport")
			if (previous.z < Layout.WALL_CENTER and member.position.z >= Layout.WALL_CENTER) or (previous.z > Layout.WALL_CENTER and member.position.z <= Layout.WALL_CENTER):
				var ratio := (Layout.WALL_CENTER - previous.z) / (member.position.z - previous.z)
				var x := lerpf(previous.x, member.position.x, ratio)
				check(absf(x) < Layout.GATE_HALF, "Every actual wall crossing must pass through the unique south gate")
				if member.position.z > previous.z: route_out += 1
				else: route_in += 1
	ledger("Production step")

func advance(seconds: float) -> void:
	for frame in ceili(seconds / STEP):
		step(minf(STEP, seconds - float(frame) * STEP))
		if frame % 100 == 99: await process_frame

func team_row(id: int = 0) -> Dictionary:
	for row: Dictionary in game.logistics.snapshot().teams:
		if int(row.id) == id: return row
	return {}

func wait_for(predicate: Callable, seconds: float, label: String) -> bool:
	for frame in ceili(seconds / STEP):
		if bool(predicate.call()): return true
		step()
		if frame % 100 == 99: await process_frame
	check(bool(predicate.call()), label + " timed out; " + str(game.logistics.snapshot()))
	return bool(predicate.call())

func plot_at(kind: String, point: Vector3) -> int:
	for plot: Dictionary in game.districts.plots:
		if String(plot.kind) == kind and int(plot.level) > 0 and planar(plot.position, point) < .05: return int(plot.index)
	return -1

func select_building(kind: String) -> void:
	if not game.construction.active: await press(KEY_Y)
	var page := Catalog.BUILDING_IDS.find(kind) / 3
	var current: int = Catalog.BUILDING_IDS.find(String(game.construction.kind)) / 3
	if page != current: await click_ui(game.hud.construction_page_rect(1 if page > current else -1))
	await click_ui(game.hud.construction_kind_rect(Catalog.BUILDING_IDS.find(kind) % 3))
	check(game.construction.active and String(game.construction.kind) == kind, "Actual building pagination selects " + kind)

func build_gui(kind: String, point: Vector3) -> int:
	stand(HOME)
	await select_building(kind); await aim_at(point)
	var preview: Dictionary = game.construction.snapshot()
	check(bool(preview.valid) and bool(preview.tech_valid) and bool(preview.space_valid), "Actual live preview permits " + kind + ": " + String(preview.reason))
	var balance: int = game.scrap
	await mouse(game.camera.unproject_position(point), true)
	var id := plot_at(kind, preview.point)
	check(id >= 0 and int(game.scrap) == balance - int(Catalog.building(kind).cost), "Actual confirmation creates one paid " + kind)
	var paid: int = game.scrap
	await press(KEY_F)
	check(int(game.scrap) == paid, "Repeated occupied confirmation must not charge twice")
	await press(KEY_ESCAPE)
	if id >= 0 and kind == "depot":
		check(float(game.districts.plots[id].hp) == 500.0 and Grid.placement(preview.point, kind).cells.size() == 9
			and not game.outpost_walkable(preview.point), "Actual depot owns nine blocked cells and 500 HP")
		for cell: Vector2i in Grid.placement(preview.point, kind).cells:
			var center := Grid.cell_rect(cell).get_center()
			check(not game.outpost_walkable(Vector3(center.x, 5, center.y)), "Each occupied depot cell blocks actual navigation")
	return id

func open_army(second: bool = true) -> void:
	if game.construction.active: await press(KEY_ESCAPE)
	if game.hud.detail_tab.is_empty(): await press(KEY_F3)
	if game.hud.detail_tab != "army": await click_ui(game.hud.details_tab_rect(2))
	if (game.hud.troop_page > 0) != second: await click_ui(game.hud.troop_page_rect(1 if second else -1))
	await redraw()
	check(game.hud.detail_tab == "army" and (game.hud.troop_page > 0) == second, "Actual F3 army pagination exposes the intended troop page")

func close_drawer() -> void:
	if not game.hud.detail_tab.is_empty(): await press(KEY_F3)

func train_gui() -> void:
	await open_army()
	check(game.hud.visible_training_kinds() == ["ballista", "hauler", "medic"], "Actual second army page retains heavy troops and haulers alongside the new medical entry")
	var balance: int = game.scrap
	await click_ui(game.hud.training_kind_rect(1))
	check(game.scrap == balance - 70, "Actual hauler button charges exactly 70 parts")
	await redraw()

func dawn() -> void:
	await close_drawer()
	TransitionFixture.finish_for_fixture(game)
	check(game.phase == "draft" and game.day_start_pending, "Actual surviving-night transition opens its dawn choice")
	await press(KEY_1)
	check(game.phase == "day", "Actual dawn input begins production daylight")
	clear_enemies(); game.phase_time = 10000.0; game.spawn_timer = 100000.0
	game.hero.attack_timer = 100000.0; game.pulse_timer = 100000.0
	for pad: Dictionary in game.world.tower_pads: pad.cooldown = 100000.0

func night_fixture() -> void:
	game.start_night(); clear_enemies(); game.phase_time = 10000.0; game.wave_index = game.WAVES_PER_NIGHT
	game.pulse_timer = 100000.0; game.spawn_timer = 100000.0

func capture(label: String) -> void:
	if not render_test: return
	check(DisplayServer.get_name() != "headless", "Transport evidence requires an actual graphical renderer")
	if DisplayServer.get_name() == "headless": return
	var before := state()
	for viewport: Vector2i in VIEWPORTS:
		root.size = viewport; root.content_scale_size = viewport
		game.world.night_mix = 1.0 if game.phase == "night" else 0.0
		game.world.apply_lighting(); game.hud.queue_redraw()
		for _frame in 5:
			await process_frame
			await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		check(image.get_size() == viewport and Vector2i(game.hud.get_viewport_rect().size) == viewport,
			"Actual PNG and HUD content match " + str(viewport))
		for row: Dictionary in game.hud.drawn_labels:
			if String(row.text).contains("采运") or String(row.text).contains("废料") or String(row.text).contains("在途") or String(row.text).contains("中转站"):
				check(row.point.x >= 0 and row.point.x + float(row.width) <= 1440 and row.point.y <= 900,
					"New actual Chinese transport labels remain inside every scaled viewport")
				if row.point.x >= 46 and row.point.x <= 532 and row.point.y >= 580 and row.point.y <= 660:
					check(row.point.x + float(row.width) <= 532,
						"Actual new army transport labels must fit inside the drawer and resume hitbox")
		var folder := ProjectSettings.globalize_path(output_dir)
		DirAccess.make_dir_recursive_absolute(folder)
		var name := "%s-%dx%d" % [label, viewport.x, viewport.y]
		check(image.save_png(folder.path_join(name + ".png")) == OK, "Actual images save only below local build")
		(evidence.captures as Array).append(name)
	check(state() == before, "Three viewport captures cannot spend parts, reserve stock or advance transport")
	root.size = VIEWPORTS[0]; root.content_scale_size = VIEWPORTS[0]
	for _frame in 3: await process_frame

func frozen_transport(stage: String) -> void:
	await close_drawer()
	if game.squads.selected_count() > 0: await press(KEY_ESCAPE)
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "Actual Escape pauses during " + stage)
	var before := state()
	game.simulate(5.0); game.logistics.advance(5.0); game.squads.advance(5.0)
	check(state() == before, "Pause freezes positions, cargo, stock, queues, clocks and wallet during " + stage)
	await press(KEY_ESCAPE)
	game.run.grant("采运验证 · 免费选卡冻结夹具")
	await press(KEY_V)
	check(game.phase == "draft", "Actual V opens its real pending choice during " + stage)
	before = state()
	game.simulate(5.0); game.logistics.advance(5.0); game.squads.advance(5.0)
	check(state() == before, "Actual choice freezes physical transport during " + stage)
	await press(KEY_1)
	check(game.phase == "day", "Actual choice completion resumes the original daylight transport")

func catalog_queue_and_first_trip() -> void:
	await fresh()
	check(Catalog.BUILDING_IDS.slice(0, 6) == ["tower", "barracks", "workshop", "recycler", "laboratory", "depot"]
		and Catalog.TROOP_IDS.slice(0, 5) == ["shield", "ranged", "engineer", "ballista", "hauler"],
		"Finite transport retains its sixth-building/fifth-troop position in the original catalog prefix")
	check(Catalog.building("depot").requires == ["workshop"] and Catalog.troop("hauler").requires == ["depot"], "Depot/hauler depend on distinct live prerequisites")
	await select_building("depot"); await aim_at(DEPOT)
	var preview: Dictionary = game.construction.snapshot()
	check(bool(preview.space_valid) and not bool(preview.tech_valid) and not bool(preview.valid), "Missing workshop rejects an otherwise clear depot preview")
	var balance: int = game.scrap
	await press(KEY_F)
	check(game.scrap == balance and plot_at("depot", DEPOT) < 0, "Actual missing-tech confirmation cannot build or spend")
	await press(KEY_ESCAPE); await open_army()
	await click_ui(game.hud.training_kind_rect(1))
	check(game.scrap == balance and game.squads.training_queues.is_empty(), "Actual missing-depot hauler button cannot charge or train")
	await close_drawer()
	await build_gui("workshop", WORKSHOP)
	barracks_index = await build_gui("barracks", BARRACKS)
	depot_index = await build_gui("depot", DEPOT)
	await capture("sixth-building-depot")
	await train_gui()
	var orders: Array = game.squads.training_queues.get(barracks_index, [])
	check(orders.size() == 1 and String(orders[0].kind) == "hauler" and float(orders[0].remaining) == 8.0, "Actual order uses the paid eight-second barracks queue")
	await capture("hauler-training-page")
	var cancel: Dictionary = game.hud.training_cancel_buttons[0]
	balance = game.scrap
	await click_ui(cancel.rect)
	check(game.scrap == balance + 70 and game.squads.training_queues.get(barracks_index, []).is_empty(), "Actual cancellation refunds the sole order once")
	balance = game.scrap
	await click_ui(cancel.rect)
	check(not bool(game.squads.cancel_training(barracks_index, 0).ok) and game.scrap == balance, "Repeated empty-order cancellation cannot repeat its refund")
	await train_gui()
	check(bool(game.districts.damage(depot_index, 100000.0).destroyed), "Actual damage destroys the live training prerequisite")
	balance = game.scrap
	await click_ui(game.hud.training_kind_rect(1))
	check(game.scrap == balance and game.squads.training_queues[barracks_index].size() == 1, "Destroyed depot rejects new orders while preserving a paid order")
	check(bool(game.districts.damage(barracks_index, 100000.0).destroyed), "Actual barracks destruction removes the queue source")
	check(game.scrap == balance + 70 and game.squads.training_queues.is_empty(), "Destroyed barracks refunds the unfinished order once")
	game.squads.refresh_barracks()
	check(game.scrap == balance + 70, "Repeated barracks refresh cannot repeat the refund")
	await close_drawer()
	barracks_index = await build_gui("barracks", BARRACKS)
	depot_index = await build_gui("depot", DEPOT)
	await train_gui(); await close_drawer()
	await advance(7.99)
	check(game.squads.squads.is_empty(), "Actual 7.99 seconds cannot complete an eight-second order")
	step(.02)
	check(game.squads.squads.size() == 1 and game.squads.squads[0].members.size() == 3, "Actual paid queue creates three real living haulers")
	for member: BattleUnit in game.squads.squads[0].members:
		check(member.alive and is_equal_approx(member.max_hp, 120.0 * game.districts.squad_health_multiplier())
			and member.damage == 0.0, "Actual hauler uses its 120-HP base with the existing live barracks health bonus and cannot attack")
	await dawn()
	var before := state()
	for _read in 12: game.logistics.snapshot()
	check(state() == before, "Presentation reads cannot claim, pay, route or consume randomness")
	camera_at(HOME); await capture("default-clean-transport-city")
	if not await wait_for(func() -> bool: return String(team_row().get("state", "")) == "outbound" and game.squads.squads[0].members[0].position.z > 20, 60, "Real first south-gate departure"): return
	camera_at(game.squads.squads[0].members[1].position); await capture("actual-carriers-outside-gate")
	if not await wait_for(func() -> bool: return float(team_row().get("loading_progress", 0)) > .05, 100, "Actual arrival/loading"): return
	check(game.logistics.snapshot().remaining == 480 and game.logistics.snapshot().cargo == 0, "Beginning loading cannot remove stock or pay early")
	camera_at(game.squads.squads[0].members[1].position); await capture("actual-loading-at-finite-source")
	await frozen_transport("loading")
	for member: Dictionary in team_row().members:
		check(planar(member.position, member.destination) <= .23,
			"Every actual loaded member must first reach its own heap approach before the shared three-second timer")
	var remaining_load := 3.0 * (1.0 - float(team_row().loading_progress))
	step(maxf(.001, remaining_load - .01))
	check(game.logistics.snapshot().remaining == 480 and game.logistics.snapshot().cargo == 0,
		"Actual loading cannot transfer even one good before three complete seconds")
	step(.02)
	check(game.logistics.snapshot().cargo == 24, "Actual completed three-second loading transfers each carrier's eight goods once")
	check(game.logistics.snapshot().remaining == 456 and game.logistics.snapshot().delivered == 0, "First load physically transfers 24 finite goods without paying")
	await capture("loaded-backpacks-returning")
	# An explicit zero-speed member isolates the per-token arrival rule without
	# teleporting anybody or changing cargo/source inventory. The other two
	# physically return; their squad centroid cannot redeem this outside member.
	var waiting_member: BattleUnit = game.squads.squads[0].members[0]
	var normal_speed := waiting_member.speed
	var outside_position := waiting_member.position
	waiting_member.speed = 0.0
	if not await wait_for(func() -> bool: return float(team_row().get("unloading_progress", 0)) > 0, 120, "Real station-edge return"): return
	await frozen_transport("unloading")
	var unloading_member: Dictionary = {}
	for member: Dictionary in team_row().members:
		if float(member.unloading_progress) > 0 and int(member.cargo) > 0: unloading_member = member; break
	check(not unloading_member.is_empty(), "First-level station exposes an individual genuine unloading clock")
	if not unloading_member.is_empty():
		var token: int = unloading_member.token
		var remaining_unload := 1.0 - float(unloading_member.unloading_progress)
		step(maxf(.001, remaining_unload - .01))
		var owner := instance_from_id(token) as BattleUnit
		check(int(owner.get_meta("haul_cargo", 0)) == 8, "Actual level-one station cannot settle before the full one-second interval")
		step(.02)
		check(int(owner.get_meta("haul_cargo", 0)) == 0, "Actual level-one station settles an arrived member once after one second")
	camera_at(DEPOT); await capture("actual-depot-unloading")
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().delivered) == 16, 20, "Two individual genuinely arrived member deliveries"): return
	check(waiting_member.position == outside_position and int(waiting_member.get_meta("haul_cargo", 0)) == 8
		and game.logistics.snapshot().cargo == 8, "A squad with two paid arrivals cannot remotely redeem its outside third carrier")
	waiting_member.speed = normal_speed
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().delivered) == 24, 20, "First genuine delivery"): return
	check(route_out >= 3 and route_in >= 3 and game.logistics.snapshot().cargo == 0, "Every carrier crosses the unique gate both ways before first delivery")
	(evidence.completed as Array).append("live_technology_actual_gui_queue_refund_once_real_first_trip_pause_choice")

func record_hurt(member: BattleUnit, source: BattleUnit, hp_loss: float, _shield_loss: float) -> void:
	hurt_events.append({"token": member.get_instance_id(), "source": source.get_instance_id() if is_instance_valid(source) else -1, "damage": hp_loss})

func resume_gui() -> void:
	await open_army(); await redraw()
	check(game.hud.haul_button_visible() and game.hud.drawn_rects.has(game.hud.HAUL_BUTTON_RECT), "Selected-hauler army second page draws the actual resume control")
	var before := state()
	await click_ui(game.hud.HAUL_BUTTON_RECT, MOUSE_BUTTON_RIGHT)
	check(state() == before, "Right-click resume UI cannot issue a world order or begin transport")
	await close_drawer()
	# F1 is the real pause route that preserves a selection. Close its credits
	# with Escape while remaining paused, then inspect the same visible button.
	await press(KEY_F1)
	check(game.phase == "paused" and game.music_credits_open, "Actual F1 pauses while preserving the live carrier selection")
	await press(KEY_ESCAPE)
	await open_army()
	check(game.hud.haul_button_visible() and game.hud.drawn_rects.has(game.hud.HAUL_BUTTON_RECT)
		and game.squads.selected_count() == 1, "Actual selected carrier retains a visible disabled resume control during pause")
	await capture("paused-visible-resume-control")
	before = state()
	await click_ui(game.hud.HAUL_BUTTON_RECT)
	check(state() == before, "Paused resume clicks cannot execute a transport transaction")
	await close_drawer(); await press(KEY_ESCAPE)
	check(game.phase == "day", "Actual Escape resumes original daylight")
	await press(KEY_TAB); await open_army(false); await redraw()
	check(not game.hud.haul_button_visible() and not game.hud.drawn_rects.has(game.hud.HAUL_BUTTON_RECT), "First troop page cannot draw the advanced resume control")
	before = state()
	await click_ui(game.hud.HAUL_BUTTON_RECT)
	check(state() == before, "Clicking a hidden resume control inside the first-page drawer is inert")
	await open_army(); await capture("selected-hauler-resume-control")
	await click_ui(game.hud.HAUL_BUTTON_RECT)
	check(String(game.squads.squads[0].order) == "haul" and bool(team_row().automatic), "Actual visible resume click restores the production haul order")
	await close_drawer()

func manual_orders_and_real_loss() -> void:
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().cargo) == 24, 160, "Second loaded trip"): return
	await press(KEY_TAB)
	check(game.squads.selected_count() == 1, "Actual Tab selects the cargo group")
	var group: Dictionary = game.squads.squads[0]
	var middle: BattleUnit = group.members[1]
	await aim_at(middle.position + Vector3(0, 0, 3))
	await mouse(game.camera.unproject_position(game.aim), true, MOUSE_BUTTON_RIGHT)
	check(String(group.order) == "move" and String(team_row().state) == "manual" and int(team_row().cargo) == 24,
		"Actual selected right-click movement stops automatic hauling and retains live goods")
	await aim_at(middle.position); await press(KEY_O)
	check(String(group.order) == "guard" and not bool(team_row().automatic) and int(team_row().cargo) == 24, "Actual O guard retains cargo and stops hauling")
	await advance(2.0)
	var carrier: BattleUnit = group.members[0]
	var enemy: BattleUnit = game.spawn_creature(false)
	enemy.position = carrier.position + Vector3(0, 0, 10); enemy.position.y = game.outpost_height(enemy.position)
	check(game.choose_enemy_target(enemy).is_empty(), "Ordinary daylight enemy cannot activate on outside carriers beyond eight metres")
	var idle := enemy.position
	enemy.attack_queued = true; enemy.attack_windup = .1
	game.update_creature(enemy, .2)
	check(enemy.position == idle and not enemy.attack_queued, "Out-of-alert enemy cancels stale attacks and remains idle")
	enemy.set_meta("day_hunter", true)
	check(String(game.choose_enemy_target(enemy).get("kind", "")) == "hero", "Original contract hunters still follow the hero")
	enemy.remove_meta("day_hunter")
	enemy.position = carrier.position + Vector3(0, 0, 4); enemy.position.y = game.outpost_height(enemy.position)
	var approach_start := enemy.position
	check(enemy.damage == 13.0 and enemy.speed == 2.3, "Escort casualty uses a genuine unbuffed ordinary enemy")
	var target: Dictionary = game.choose_enemy_target(enemy)
	check(String(target.get("kind", "")) == "squad" and int(target.get("token", -1)) == carrier.get_instance_id(), "Nearby daytime enemy selects a reachable outside carrier")
	await aim_at(enemy.position)
	await mouse(game.camera.unproject_position(enemy.position), true, MOUSE_BUTTON_RIGHT)
	check(String(group.order) == "attack" and not bool(team_row().automatic) and int(team_row().cargo) == 24, "Actual designated attack interrupts hauling without deleting goods")
	await aim_at(middle.position); await press(KEY_O)
	await advance(1.0)
	carrier = game.choose_enemy_target(enemy).get("unit") as BattleUnit
	if not is_instance_valid(carrier):
		check(false, "Guard formation must leave a real nearby attackable carrier"); return
	var token := carrier.get_instance_id()
	var hp := carrier.hp
	carrier.damage_confirmed.connect(record_hurt)
	hurt_events.clear(); enemy.attack_timer = 0.0; enemy.attack_queued = false
	if not await wait_for(func() -> bool: return enemy.attack_queued, 8, "Ordinary daytime enemy physically approaches before its attack"): return
	check(planar(approach_start, enemy.position) > .2 and game.can_traverse(approach_start, enemy.position)
		and planar(enemy.position, carrier.position) <= enemy.attack_range + .001,
		"An actual ordinary daytime attacker must walk along real ground into melee range before preparing its strike")
	check(enemy.attack_queued and enemy.attack_windup > 0 and carrier.hp == hp and hurt_events.is_empty(), "Real enemy starts preparation before hurting cargo")
	step(.20)
	check(carrier.hp == hp and hurt_events.is_empty(), "Incomplete preparation cannot apply instant cargo damage")
	if not await wait_for(func() -> bool: return not is_instance_id_valid(token) or group.members.count(null) > 0, 25, "Genuine ordinary strikes kill a loaded carrier"): return
	var losses: Dictionary = game.logistics.snapshot()
	check(losses.lost == 8 and losses.cargo == 16 and losses.remaining == 432 and not hurt_events.is_empty(), "Genuine hurt/death loses only that token's eight goods without stock refill or remote payment")
	for event: Dictionary in hurt_events:
		check(event.source == enemy.get_instance_id() and event.damage > 0 and event.damage <= 13.001, "Every loss event originates in the genuine ordinary enemy")
	clear_enemies(); await process_frame
	var balance: int = game.scrap
	await press(KEY_L)
	check(game.scrap == balance - 22 and group.members.count(null) == 0, "Actual daylight L charges 22 for the single missing carrier")
	step(.001)
	check(game.logistics.snapshot().lost == 8 and game.logistics.snapshot().cargo == 16, "New empty replacement token cannot recover the dead carrier's goods")
	await resume_gui()
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().delivered) == 40, 160, "Surviving actual sixteen-part delivery"): return
	check(game.logistics.snapshot().lost == 8, "Survivor delivery never repays lost goods")
	(evidence.completed as Array).append("real_mouse_move_attack_guard_resume_day_enemy_windup_hurt_token_loss_paid_refill")

func sunset_and_station_identity() -> void:
	if not await wait_for(func() -> bool: return float(team_row().get("loading_progress", 0)) > .1, 160, "Incomplete third load"): return
	var before: Dictionary = game.logistics.snapshot()
	night_fixture(); await advance(8.0)
	check(game.logistics.snapshot().remaining == before.remaining and game.logistics.snapshot().cargo == 0 and game.logistics.snapshot().delivered == before.delivered,
		"Actual sunset cancels incomplete loading and all new source transfers")
	await dawn()
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().cargo) == 24, 160, "Actual post-dawn load"): return
	night_fixture()
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().delivered) == 64, 160, "Real loaded sunset return and payout"): return
	before = game.logistics.snapshot(); await advance(12.0)
	check(game.logistics.snapshot().remaining == before.remaining and game.logistics.snapshot().cargo == 0 and String(team_row().state) == "night_wait",
		"After genuine nighttime delivery carriers wait without collecting")
	await capture("night-delivery-then-wait")
	await dawn()
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().cargo) == 24, 180, "Next actual cargo load"): return
	var old_token: int = game.districts.plots[depot_index].model.get_instance_id()
	check(bool(game.districts.damage(depot_index, 100000.0).destroyed), "Actual lethal damage invalidates the only station")
	await advance(3.0)
	check(game.logistics.snapshot().cargo == 24 and game.logistics.snapshot().delivered == 64 and String(team_row().state) == "waiting_home", "Destroyed station leaves intact waiting cargo with no remote payout")
	camera_at(game.squads.squads[0].members[1].position)
	await press(KEY_TAB); await open_army(); await capture("destroyed-station-cargo-waiting")
	await close_drawer()
	if game.squads.selected_count() > 0: await press(KEY_ESCAPE)
	var recycler := await build_gui("recycler", DEPOT)
	check(recycler == depot_index and String(game.districts.plots[recycler].kind) == "recycler", "Same-site replacement genuinely reuses the plot with another kind")
	await advance(4.0)
	check(game.logistics.snapshot().cargo == 24 and game.logistics.snapshot().delivered == 64, "Same-site recycler cannot redeem goods by stale depot index/location")
	check(bool(game.districts.damage(recycler, 100000.0).destroyed), "Actual replacement remains destructible")
	depot_index = await build_gui("depot", DEPOT)
	check(game.districts.plots[depot_index].model.get_instance_id() != old_token, "Actual rebuilt receiving station has a fresh token")
	var balance: int = game.scrap
	check(bool(game.districts.upgrade(depot_index).ok) and game.scrap == balance - 80, "Actual depot upgrade uses the paid level-two authority")
	if not await wait_for(func() -> bool: return float(team_row().get("unloading_progress", 0)) > 0, 180, "Real upgraded station approach"): return
	var monitored: Dictionary = {}
	for member: Dictionary in team_row().members:
		if float(member.unloading_progress) > 0 and int(member.cargo) > 0: monitored = member; break
	check(not monitored.is_empty(), "Upgraded unloading exposes an actual individual token timer")
	if not monitored.is_empty():
		var token: int = monitored.token
		var remaining := .5 * (1.0 - float(monitored.unloading_progress))
		step(maxf(.001, remaining - .01))
		var owner := instance_from_id(token) as BattleUnit
		check(is_instance_valid(owner) and int(owner.get_meta("haul_cargo", 0)) == 8, "Upgraded station cannot settle before the real half-second interval")
		step(.02)
		check(int(owner.get_meta("haul_cargo", 0)) == 0, "Upgraded station settles that real carrier once at half a second")
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().delivered) == 88, 20, "All real rebuilt-station payouts"): return
	(evidence.completed as Array).append("sunset_cancel_loaded_return_night_wait_destroyed_station_same_site_kind_token_rebuild_upgraded_unload")

func sealed_station_route() -> void:
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().cargo) == 24, 180, "Real cargo for sealed path"): return
	stand(HOME)
	for index in game.world.tower_pads.size(): game.damage_tower(index, float(game.world.tower_pads[index].hp))
	for x: float in [-11.0, 11.0]:
		check(game.build_structure_at(Vector3(x, 5, 7.5), "barracks"), "Real end barracks occupy both row ends")
	var gap := -1
	for x: float in [-7.5, -4.5, -1.5, 1.5, 4.5, 7.5]:
		var count: int = game.world.tower_pads.size()
		check(game.build_tower_at(Vector3(x, 5, 7.5)), "Real paid adjacent towers seal the remaining 26-cell row")
		if x == 1.5: gap = count
	var member: BattleUnit = game.squads.squads[0].members[1]
	check(not game.building_approach_position(member.position, DEPOT, "depot").is_finite(), "The real full-width row seals every reachable station edge")
	var before: Dictionary = game.logistics.snapshot()
	await advance(5.0)
	check(game.logistics.snapshot().cargo == 24 and game.logistics.snapshot().delivered == before.delivered and String(team_row().state) == "waiting_home",
		"Physically sealed receiving station cannot issue remote wallet payments")
	camera_at(Vector3(0, 5, 7.5)); await capture("real-building-row-seals-station")
	if gap < 0: return
	game.damage_tower(gap, float(game.world.tower_pads[gap].hp))
	check(game.outpost_walkable(Vector3(1.5, 5, 7.5)), "Actual demolition releases the real gap")
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().delivered) == int(before.delivered) + 24, 180, "Real reopened-route delivery"): return
	for index in game.world.tower_pads.size():
		if int(game.world.tower_pads[index].level) > 0: game.damage_tower(index, float(game.world.tower_pads[index].hp))
	for plot: Dictionary in game.districts.plots:
		if String(plot.kind) == "barracks" and absf(plot.position.z - 7.5) < .01 and int(plot.level) > 0: game.districts.damage(int(plot.index), 100000.0)
	(evidence.completed as Array).append("real_dense_row_no_remote_settlement_demolition_recovers_path")

func multiple_teams_and_exhaustion() -> void:
	await train_gui(); await train_gui(); await close_drawer()
	await advance(16.01)
	check(game.squads.squads.size() == 3, "Two genuine sequential paid orders produce additional real carrier groups")
	var inside: BattleUnit = game.squads.squads[2].members[1]
	var enemy: BattleUnit = game.spawn_creature(false)
	enemy.position = inside.position + Vector3(.5, 0, 0); enemy.position.y = game.outpost_height(enemy.position)
	check(Layout.contains_castle(inside.position) and game.choose_enemy_target(enemy).is_empty(), "Ordinary daylight enemy cannot activate on living carriers inside the city")
	clear_enemies()
	var original_sources: Array = []
	for source: Dictionary in game.world.salvage: original_sources.append([source.position, source.collected, source.respawn])
	var initial_delivered: int = game.logistics.snapshot().delivered
	var initial_parts: int = game.scrap
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().remaining) == 0 and int(game.logistics.snapshot().cargo) == 0, 1400, "Real three-team exhaustion of unchanged 480 goods"): return
	var final: Dictionary = game.logistics.snapshot()
	check(final.delivered == 472 and final.lost == 8 and game.scrap == initial_parts + 472 - initial_delivered,
		"After one genuine carrier loss, transport pays exactly 472 delivered parts")
	await advance(8.0)
	for row: Dictionary in game.logistics.snapshot().teams:
		check(String(row.state) == "exhausted" and int(row.cargo) == 0, "Each carrier reports exhausted after all five finite sources are gone")
	var sources: Array = []
	for source: Dictionary in game.world.salvage: sources.append([source.position, source.collected, source.respawn])
	check(sources == original_sources, "Carrier harvesting leaves the independent hero salvage untouched")
	camera_at(game.logistics.fields[0].position)
	await press(KEY_TAB); await open_army(); await capture("five-finite-heaps-exhausted")
	await close_drawer()
	if game.squads.selected_count() > 0: await press(KEY_ESCAPE)
	var wallet: int = game.scrap
	night_fixture(); await advance(10.0)
	# This is the third daylight transition; keep the standard fourth-night
	# victory outside this transport endurance fixture by using begin_day.
	game.begin_day(); clear_enemies(); game.phase_time = 10000.0; game.spawn_timer = 100000.0
	await advance(10.0)
	check(game.logistics.snapshot().remaining == 0 and game.logistics.snapshot().delivered == 472 and game.logistics.snapshot().lost == 8 and game.scrap == wallet,
		"Production day/night transitions cannot refresh finite sources or pay by timer")
	(evidence.transport_economy as Dictionary).merge({"final": final, "gate_out_crossings": route_out,
		"gate_in_crossings": route_in, "simulated_seconds": elapsed, "real_hurt_events": hurt_events}, true)
	(evidence.completed as Array).append("three_real_teams_reservations_finite_480_exhaustion_no_refresh_independent_hero_sources")

func original_wave_ledger() -> void:
	await fresh(true)
	var baseline: int = game.scrap
	var deaths := 0
	for wave in 5:
		var entry: Dictionary = game.wave_rewards.snapshot(wave)
		check(game.wave_index == wave + 1 and int(entry.budget) == 24 and bool(entry.sealed), "Transport preserves each real original standard wave's 24-part ledger")
		var balance: int = game.scrap
		var victims: Array = game.enemies.duplicate()
		for creature: BattleUnit in victims:
			if not is_instance_valid(creature) or not creature.alive: continue
			creature.hurt(100000.0, game.hero); deaths += 1
			var paid: int = game.scrap
			check(game.wave_rewards.defeat(creature) == 0 and game.scrap == paid, "Repeated original death claims cannot create extra battle or carrier rewards")
		entry = game.wave_rewards.snapshot(wave)
		check(bool(entry.cleared) and int(entry.paid) == 24 and game.scrap == balance + 24, "Real original enemy deaths clear and pay exactly 24 parts")
		await process_frame
		game.enemies.clear()
		if wave < 4: game.spawn_night_wave()
	check(deaths == 71 and game.scrap == baseline + 120 and game.logistics.snapshot().remaining == 480 and game.logistics.snapshot().cargo == 0 and game.logistics.snapshot().delivered == 0,
		"All five original waves still pay exactly 120 independently of untouched carrier inventory")
	(evidence.completed as Array).append("original_five_real_wave_deaths_exact_24_120")

func run() -> void:
	await catalog_queue_and_first_trip()
	if failures.is_empty(): await manual_orders_and_real_loss()
	if failures.is_empty(): await sunset_and_station_identity()
	if failures.is_empty(): await sealed_station_route()
	if failures.is_empty(): await multiple_teams_and_exhaustion()
	if failures.is_empty(): await original_wave_ledger()
	await close_game()
	# Wait for the actual audio server to retire playback handles after freeing
	# the final scene; successful assertions alone do not prove clean teardown.
	await create_timer(.5, true, false, true).timeout
	evidence.checks = checks; evidence.failures = failures
	var folder := ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("transport-economy.json"), FileAccess.WRITE)
	check(file != null, "Transport evidence JSON must open beneath local build")
	if file: file.store_string(JSON.stringify(evidence, "\t")); file.close()
	print("NIGHTFALL_LOGISTICS_", "OK" if failures.is_empty() else "FAILED", " checks=", checks,
		" transport_economy actual_gui finite_token_cargo real_gate_paths windup_hurt_loss station_identity no_remote_payout")
	quit(0 if failures.is_empty() else 1)
