extends SceneTree
## Production technology, five-building placement, four-troop pagination and
## limited wreck recovery. Advanced-content fixtures explicitly seed 5000 parts;
## these assertions test transactions and combat, not first-night affordability.
const Catalog := preload("res://scripts/outpost_catalog.gd")
const Grid := preload("res://scripts/construction_grid.gd")
const RunSession := preload("res://scripts/run_session.gd")
const SCENE := "res://scenes/nightfall.tscn"
const SEED := 20261006
const HOME := Vector3(0, 5, 3.1)
const WORKSHOP := Vector3(-7.5, 5, -8)
const BARRACKS := Vector3(7, 5, -8.5)
const RECYCLER := Vector3(-7.5, 5, -3.5)
const LABORATORY := Vector3(7, 5, -3.5)
const SECOND_RECYCLER := Vector3(-7.5, 5, 2.5)
const RECORDING_HUD := """extends 'res://scripts/nightfall_hud.gd'
var drawn_rects: Array[Rect2] = []
var drawn_labels: Array[String] = []
func _draw() -> void:
	drawn_rects.clear()
	drawn_labels.clear()
	super._draw()
func box(rect: Rect2, fill: Color = Color(.022,.035,.045,.88), outline: Color = Color("435455")) -> void:
	drawn_rects.append(rect)
	super.box(rect,fill,outline)
func label(value: String, point: Vector2, size_px: int, color: Color = Color("e7e1d3"), latin: bool = false) -> void:
	drawn_labels.append(value)
	super.label(value,point,size_px,color,latin)
"""
var game: Node3D
var checks := 0
var failures: Array[String] = []
var completed: Array[String] = []
var render_test := false
var output_dir := "res://build/outpost-tech"
var evidence: Dictionary = {"fixture_parts": 5000, "seed": SEED, "captures": []}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	render_test = "--render-test" in args
	var output_index := args.find("--output-dir")
	if output_index >= 0 and output_index + 1 < args.size():
		var candidate := ProjectSettings.globalize_path(args[output_index + 1]).simplify_path()
		var build_root := ProjectSettings.globalize_path("res://build").simplify_path()
		if candidate.begins_with(build_root + "/"): output_dir = candidate
	root.size = Vector2i(1920, 1200)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1920, 1200)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 30: push_error(message)

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func mouse(pixel: Vector2, click: bool = false, button: int = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pixel
	motion.global_position = pixel
	root.push_input(motion, true)
	await process_frame
	if not click: return
	var event := InputEventMouseButton.new()
	event.position = pixel
	event.global_position = pixel
	event.button_index = button
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.button_mask = 0
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func click_ui(rect: Rect2, button: int = MOUSE_BUTTON_LEFT) -> void:
	await mouse(rect.get_center() * game.hud.get_viewport_rect().size / Vector2(1440, 900), true, button)

func redraw() -> void:
	game.hud.queue_redraw()
	for _frame in 3: await process_frame

func stand(point: Vector3) -> void:
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.move_goal = point
	game.hero_path.clear()
	game.hero_keyboard_active = false
	game.hero.moving = false
	game.hero.set_locomotion_velocity(Vector3.ZERO)

func camera_at(point: Vector3) -> void:
	game.camera.size = 38.0
	game.camera.position = point + Vector3(0, 25, 29)
	game.camera.look_at(point)
	game.camera_follow = game.camera.position

func aim_at(point: Vector3) -> void:
	camera_at(point)
	await mouse(game.camera.unproject_position(point))
	game._process(0.0)

func remove_enemies() -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()

func close_game() -> void:
	if not is_instance_valid(game): return
	await game.prepare_shutdown()
	if current_scene == game: current_scene = null
	game.queue_free()
	game = null
	for _frame in 4: await process_frame

func fresh(keep_wave: bool = false) -> void:
	await close_game()
	check(RunSession.queue_request(self, SEED, "siege"), "The technology scene must accept its fixed real run seed")
	game = load(SCENE).instantiate()
	root.add_child(game)
	current_scene = game
	for _frame in 5: await process_frame
	game.set_process(false)
	game.world.set_process(false)
	# Fixed local observation only: inherit and forward every production draw
	# and input method, retaining the real GUI event dispatch path.
	var recorder := GDScript.new()
	recorder.source_code = RECORDING_HUD
	check(recorder.reload() == OK, "The fixed observer must compile as a subclass of the actual production HUD")
	var old_hud: Control = game.hud
	var layer: Node = old_hud.get_parent()
	layer.remove_child(old_hud)
	old_hud.queue_free()
	var observed: Control = recorder.new()
	observed.game = game
	game.hud = observed
	layer.add_child(observed)
	observed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await press(KEY_1)
	check(game.phase == "night" and game.run_mode == "siege" and game.run.seed_value == SEED,
		"The actual opening key must create a standard production night")
	# This explicit advanced-content bankroll is separate from the unmodified
	# production-wallet test in nightfall_single_resource_economy.gd.
	game.scrap = 5000
	if not keep_wave: remove_enemies()
	for pad: Dictionary in game.world.tower_pads: pad.cooldown = 9999.0
	stand(HOME)
	check(game.hud.detail_tab.is_empty() and not game.hud.map_expanded,
		"Adding content must preserve the default closed tactical drawer")

func read_state() -> Dictionary:
	var levels: Array = []
	for plot: Dictionary in game.districts.plots: levels.append([plot.kind, plot.level, plot.hp, plot.pending])
	return {"parts": int(game.scrap), "rng": game.run.rng.state, "spawn_rng": game.spawn_rng.state,
		"levels": levels, "queues": game.squads.training_queues.duplicate(true),
		"blocks": game.construction_blocks.duplicate(), "path": game.hero_path.duplicate(),
		"goal": game.move_goal, "phase": String(game.phase), "time": float(game.phase_time),
		"selection": game.squads.selected_ids.duplicate(), "dragging": bool(game.selection_dragging)}

func clean_build_navigation(label: String) -> void:
	stand(HOME)
	game.notice_time = 0.0
	game.hero_damage_flash_time = 0.0
	game.combat_milestone_time = 0.0
	game.reward_toasts.clear()
	game.squads.cancel_selection()
	await redraw()
	var button: Rect2 = game.hud.BUILD_BUTTON_RECT
	var context: Rect2 = game.hud.context_prompt_rect()
	var original_phase: String = game.phase
	check(button == Rect2(272, 824, 64, 36) and game.hud.live_panel_rects().has(button),
		label + ": the compact build button must have the real reserved bottom hitbox")
	check(game.hud.drawn_rects.has(button) and game.hud.drawn_labels.has("Y 建造"),
		label + ": the actual production draw must render its small discoverable build control")
	check(game.interaction_prompt().is_empty() and not game.hud.drawn_rects.has(context)
		and not game.hud.live_panel_rects().has(context),
		label + ": idle gameplay must neither draw nor reserve a fallback construction instruction bar")
	var covered := 0.0
	for rect: Rect2 in game.hud.live_panel_rects():
		covered += rect.get_area()
		check(not rect.intersects(Rect2(340, 130, 760, 500)),
			label + ": each permanent panel must leave the central battlefield clear")
	check(covered / (1440.0 * 900.0) < .25,
		label + ": permanent UI accounting with the new build button must remain below one quarter of the screen")
	var before := read_state()
	await click_ui(button, MOUSE_BUTTON_RIGHT)
	check(read_state() == before and not game.construction.active,
		label + ": right-clicking the visible build button must not command the hero, select units or begin placement")
	await click_ui(button)
	check(game.construction.active and game.phase == original_phase and game.scrap == int(before.parts)
		and game.move_goal == before.goal and game.hero_path == before.path and not game.selection_dragging,
		label + ": one real build-button click must enter placement without spending or passing through to the world")
	before = read_state()
	await click_ui(button, MOUSE_BUTTON_RIGHT)
	check(game.construction.active and read_state() == before,
		label + ": right-click on the visible build button must also not cancel placement behind the UI")
	await click_ui(button)
	check(not game.construction.active and game.phase == original_phase and game.scrap == int(before.parts),
		label + ": another real build-button click must exit placement without a payment")
	await press(KEY_ESCAPE)
	check(game.phase == "paused", label + ": the build-button pause case must enter actual pause")
	await redraw()
	check(game.hud.drawn_rects.has(button) and game.hud.drawn_labels.has("Y 建造"),
		label + ": the paused HUD must retain the visible build affordance")
	before = read_state()
	await click_ui(button)
	await click_ui(button, MOUSE_BUTTON_RIGHT)
	check(game.phase == "paused" and not game.construction.active and read_state() == before,
		label + ": paused build-button clicks must consume input without starting construction or sending commands")
	await press(KEY_ESCAPE)
	check(game.phase == original_phase and not game.construction.active,
		label + ": resume must preserve the original active phase and closed build context")

func live_count() -> int:
	var total := 0
	for plot: Dictionary in game.districts.plots:
		if int(plot.level) > 0 and float(plot.hp) > 0.0: total += 1
	return total

func plot_at(kind: String, point: Vector3) -> int:
	for plot: Dictionary in game.districts.plots:
		if String(plot.kind) == kind and int(plot.level) > 0 and (plot.position as Vector3).distance_to(point) < .01:
			return int(plot.index)
	return -1

func snapshot(index: int) -> Dictionary:
	for row: Dictionary in game.districts.snapshots():
		if int(row.index) == index: return row
	return {}

func select_building(kind: String, key_slot: bool = false) -> void:
	if not game.construction.active: await press(KEY_Y)
	var desired := Catalog.BUILDING_IDS.find(kind) / 3
	var current := Catalog.BUILDING_IDS.find(String(game.construction.kind)) / 3
	if desired != current:
		var direction := 1 if desired > current else -1
		await click_ui(game.hud.construction_page_rect(direction))
	var slot := Catalog.BUILDING_IDS.find(kind) % 3
	if key_slot: await press(KEY_1 + slot)
	else: await click_ui(game.hud.construction_kind_rect(slot))
	check(game.construction.active and String(game.construction.kind) == kind,
		"Visible current-page input must select " + kind)

func assert_footprint(index: int, kind: String, point: Vector3) -> void:
	if index < 0: return
	var row := snapshot(index)
	var size: Vector2i = Catalog.building(kind).size
	var placement: Dictionary = game.construction.validity(point, -1, kind)
	check(int(row.level) == 1 and is_equal_approx(float(row.hp), float(Catalog.building(kind).hp)),
		"The real " + kind + " must own its catalog durability")
	check((placement.cells as Array).size() == size.x * size.y and not bool(placement.space_valid),
		"The real " + kind + " must reserve its full distinct cell footprint")
	check(not game.outpost_walkable(point), "The real " + kind + " center must block production navigation")
	for cell: Vector2i in placement.cells:
		var center := Grid.cell_rect(cell).get_center()
		check(not game.outpost_walkable(Vector3(center.x, 5, center.y)),
			"Every occupied " + kind + " cell must block the actual walkable world")
	check(is_instance_valid(game.districts.plots[index].model), "The actual " + kind + " must retain its visible model")

func build_gui(kind: String, point: Vector3, key_slot: bool = false) -> int:
	stand(HOME)
	await select_building(kind, key_slot)
	await aim_at(point)
	var placement: Dictionary = game.construction.snapshot()
	check(bool(placement.valid) and bool(placement.tech_valid) and bool(placement.space_valid),
		"The actual affordable preview must permit " + kind + ": " + String(placement.reason))
	var count := live_count()
	var balance: int = game.scrap
	await mouse(game.camera.unproject_position(point), true)
	var index := plot_at(kind, placement.point)
	check(index >= 0 and live_count() == count + 1 and game.scrap == balance - int(placement.cost),
		"A real world click must create " + kind + " and charge its displayed fee exactly once")
	var paid: int = game.scrap
	await press(KEY_F)
	await mouse(game.camera.unproject_position(point), true)
	check(game.scrap == paid and live_count() == count + 1,
		"Repeated occupied-cell input must not duplicate or recharge " + kind)
	await press(KEY_ESCAPE)
	check(not game.construction.active and game.phase == "night", "Esc must leave build context and resume the live battlefield")
	if kind != "tower": assert_footprint(index, kind, placement.point)
	return index

func destroy(index: int, name: String) -> void:
	if index < 0: return
	var point: Vector3 = game.districts.plots[index].position
	var balance: int = game.scrap
	var result: Dictionary = game.districts.damage(index, 100000.0)
	check(bool(result.ok) and bool(result.destroyed) and int(game.districts.plots[index].level) == 0,
		"Actual lethal damage must destroy " + name)
	check(game.outpost_walkable(point), "Destroyed " + name + " must immediately release its navigation center")
	for cell: Vector2i in Grid.placement(point, name).cells:
		var center := Grid.cell_rect(cell).get_center()
		check(game.outpost_walkable(Vector3(center.x, 5, center.y)),
			"Destroyed " + name + " must release every original building cell")
	if name != "barracks": check(game.scrap == balance, "Building destruction must not invent a parts refund")
	await process_frame

func capture(name: String, night: bool = false) -> void:
	if not render_test: return
	check(DisplayServer.get_name() != "headless", "Technology evidence needs an actual graphical backend")
	if DisplayServer.get_name() == "headless": return
	game.world.night_mix = 1.0 if night else 0.0
	game.world.set_night(night)
	game.world.apply_lighting()
	game.hud.queue_redraw()
	for _frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	check(picture.get_size() == Vector2i(1920, 1200), "Technology evidence must use the actual 1920x1200 content viewport")
	var folder := ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(folder)
	check(picture.save_png(folder.path_join(name + ".png")) == OK, "Technology screenshot must be saved beneath local build")
	evidence.captures.append(name)

func catalog_and_technology() -> void:
	await fresh()
	await clean_build_navigation("Idle night")
	check(Catalog.BUILDING_IDS.size() == 5 and Catalog.TROOP_IDS.size() == 4,
		"The playable catalog must contain five buildings and four troops")
	var copy := Catalog.building("laboratory")
	copy.cost = -1
	(copy.requires as Array).clear()
	check(int(Catalog.building("laboratory").cost) == 120 and Catalog.building("laboratory").requires == ["barracks", "workshop"],
		"A caller's catalog copy must not alter the authoritative price or prerequisites")
	var troop := Catalog.troop("ballista")
	troop.time = 0.0
	check(float(Catalog.troop("ballista").time) == 10.0, "Troop definitions must return independent copies")
	check(not bool(game.districts.build_eligibility("unknown").available)
		and not bool(game.squads.training_eligibility("unknown").available),
		"Unknown technology IDs must fail explicitly")
	var before := read_state()
	for _read in 12:
		var recovery: Dictionary = game.districts.build_eligibility("recycler")
		var science: Dictionary = game.districts.build_eligibility("laboratory")
		var heavy: Dictionary = game.squads.training_eligibility("ballista")
		check(not bool(recovery.available) and recovery.missing == ["workshop"], "Recovery must name its missing live workshop")
		check(not bool(science.available) and science.missing == ["barracks", "workshop"], "Research must name both missing live buildings")
		check(not bool(heavy.available) and heavy.missing == ["laboratory"], "Heavy troops must name their live research prerequisite")
		game.districts.snapshots()
		game.construction.validity(RECYCLER, -1, "recycler")
		game.squads.snapshot()
	check(read_state() == before, "Eligibility and display reads must preserve wallet, randomness, navigation and queues")
	await press(KEY_Y)
	await press(KEY_PAGEDOWN)
	check(game.hud.visible_construction_kinds() == ["recycler", "laboratory"] and game.construction.kind == "recycler",
		"Real PgDn must select the first building on the second three-slot page")
	await press(KEY_2)
	check(game.construction.kind == "laboratory", "Second-page key 2 must select research")
	await press(KEY_3)
	await click_ui(game.hud.construction_kind_rect(2))
	check(game.construction.kind == "laboratory" and game.scrap == 5000,
		"The empty third construction slot must not select or buy a hidden old building")
	await press(KEY_1)
	await aim_at(RECYCLER)
	var locked: Dictionary = game.construction.snapshot()
	check(not bool(locked.valid) and not bool(locked.tech_valid) and bool(locked.space_valid)
		and locked.missing == ["workshop"] and int(locked.cost) == 90,
		"Tech-locked recovery must retain its true free footprint and ninety-part cost")
	for cell: Dictionary in locked.cell_states:
		check(bool(cell.space_valid), "A missing technology prerequisite must not paint free building cells as occupied")
	check(game.construction.grid_preview.tech_limited and not game.construction.grid_preview.budget_limited,
		"The production preview must distinguish the technology boundary from insufficient money")
	check(game.construction.ghost_material.albedo_color.is_equal_approx(game.construction.TECH_COLOR),
		"A free tech-locked ghost must use the production technology tint")
	var balance: int = game.scrap
	await capture("recycler-tech-locked", true)
	await press(KEY_F)
	await mouse(game.camera.unproject_position(RECYCLER), true)
	check(game.scrap == balance and live_count() == 0 and game.construction.active,
		"Locked real keyboard and world-click transactions must not spend or build")
	await click_ui(game.hud.construction_page_rect(-1))
	check(game.hud.visible_construction_kinds() == ["tower", "barracks", "workshop"] and game.construction.kind == "tower",
		"The actual previous-page button must restore the three original buildings")
	await press(KEY_ESCAPE)
	var workshop := await build_gui("workshop", WORKSHOP)
	check(bool(game.districts.build_eligibility("recycler").available)
		and game.districts.build_eligibility("laboratory").missing == ["barracks"],
		"A real live workshop must unlock recovery and leave research's missing barracks explicit")
	var recycler := await build_gui("recycler", RECYCLER, true)
	var barracks := await build_gui("barracks", BARRACKS)
	check(bool(game.districts.build_eligibility("laboratory").available), "Both real live prerequisites must unlock research")
	await select_building("laboratory", true)
	await aim_at(LABORATORY)
	check(bool(game.construction.snapshot().valid), "Research must first have a genuinely valid production preview")
	await destroy(workshop, "workshop")
	balance = game.scrap
	await press(KEY_F)
	check(game.scrap == balance and plot_at("laboratory", LABORATORY) == -1,
		"Confirming a formerly valid preview after same-frame prerequisite loss must not spend or build research")
	var stale: Dictionary = game.construction.snapshot()
	check(bool(stale.space_valid) and not bool(stale.tech_valid) and stale.missing == ["workshop"],
		"A stale research preview must immediately expose its missing live workshop")
	await capture("laboratory-prerequisite-lost", false)
	await press(KEY_ESCAPE)
	var rebuilt := await build_gui("workshop", WORKSHOP, true)
	check(rebuilt == workshop, "Paid same-site workshop rebuilding must reuse the real destroyed plot identity")
	var laboratory := await build_gui("laboratory", LABORATORY, true)
	check(bool(game.squads.training_eligibility("ballista").available), "A real live laboratory must unlock heavy-crossbow troops")
	await destroy(rebuilt, "workshop")
	check(int(game.districts.plots[laboratory].level) == 1 and int(game.districts.plots[recycler].level) == 1
		and bool(game.squads.training_eligibility("ballista").available),
		"Earlier advanced buildings and direct laboratory troop unlock must survive loss of their own workshop prerequisite")
	check(not bool(game.districts.build_eligibility("laboratory").available)
		and not bool(game.districts.build_eligibility("recycler").available),
		"Workshop loss must reject new dependent buildings while existing structures survive")
	await build_gui("workshop", WORKSHOP)
	stand(Vector3(10.5, 5, -8.5))
	game.plan_hero_path(Vector3(3.8, 5, -8.5))
	check(not game.hero_path.is_empty(), "Real hero navigation must find a route around the newly built research/barracks line")
	for point: Vector3 in game.hero_path:
		check(game.outpost_walkable(point), "The actual planned hero route must avoid every live building footprint")
	stand(HOME)
	camera_at(Vector3(0, 5, -3))
	await capture("five-building-city-day", false)
	await capture("five-building-city-night", true)
	evidence.buildings = {"workshop": workshop, "recycler": recycler, "barracks": barracks, "laboratory": laboratory}
	completed.append("technology")

func open_army() -> void:
	if game.construction.active: await press(KEY_ESCAPE)
	if game.hud.detail_tab.is_empty(): await press(KEY_F3)
	if game.hud.detail_tab != "army": await click_ui(game.hud.details_tab_rect(2))
	await redraw()
	check(game.hud.detail_tab == "army" and not game.hud.map_expanded,
		"The actual army tab must open only inside the single tactical drawer")

func train_heavy_gui() -> void:
	await open_army()
	if game.hud.troop_page == 0: await click_ui(game.hud.troop_page_rect(1))
	var balance: int = game.scrap
	var before: Dictionary = game.squads.training_queues.duplicate(true)
	await click_ui(game.hud.training_kind_rect(0))
	check(game.scrap == balance - 110 and game.squads.training_queues != before,
		"The actual advanced-page button must charge 110 parts and queue one heavy squad")
	await redraw()

func assert_heavy(group: Dictionary) -> void:
	check(String(group.kind) == "ballista" and group.members.size() == 3,
		"Ten seconds of paid production must create one real three-person heavy squad")
	for member: BattleUnit in group.members:
		check(is_instance_valid(member) and member.alive, "Every produced heavy-crossbow member must be alive")
		if not is_instance_valid(member): continue
		check(is_equal_approx(member.max_hp, 150.0 * game.districts.squad_health_multiplier())
			and is_equal_approx(member.hp, member.max_hp), "Actual heavy HP must use its catalog base and the live barracks multiplier")
		check(is_equal_approx(member.attack_range, 12.8) and is_equal_approx(member.damage, 46.0)
			and is_equal_approx(member.attack_interval, 3.2) and is_equal_approx(member.windup_duration, .55)
			and is_equal_approx(member.speed, 3.06), "Actual heavy combat timing, damage, range and slower speed must match its declared rules")
		check(is_instance_valid(member.visual.find_child("HeavyCrossbow", true, false)),
			"The real produced heavy troop must have its distinct crossbow silhouette")

func troop_pages_and_paid_queue() -> void:
	var barracks: int = evidence.buildings.barracks
	var laboratory: int = evidence.buildings.laboratory
	await open_army()
	check(game.hud.visible_training_kinds() == ["shield", "ranged", "engineer"], "Army page one must retain three original troop slots")
	var balance: int = game.scrap
	await press(KEY_PAGEDOWN)
	check(game.hud.visible_training_kinds() == ["ballista"] and game.hud.training_page == 0 and game.scrap == balance,
		"Actual army PgDn must switch only the troop page without spending or moving the refund page")
	await click_ui(game.hud.training_kind_rect(1))
	await click_ui(game.hud.training_kind_rect(2))
	check(game.scrap == balance and game.squads.training_queues.is_empty(),
		"Empty advanced troop slots must consume drawer input without training hidden ranged or engineers")
	await train_heavy_gui()
	var queue: Array = game.squads.training_queues.get(barracks, [])
	check(queue.size() == 1 and String(queue[0].kind) == "ballista" and float(queue[0].remaining) == 10.0,
		"The real heavy order must target a live barracks with the declared ten-second queue")
	var frozen := read_state()
	await press(KEY_ESCAPE)
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "Closing the drawer then Esc must pause active play")
	game.squads.advance(11.0)
	game.districts.tick(11.0)
	check(game.squads.training_queues == frozen.queues and game.scrap == int(frozen.parts)
		and game.squads.squads.is_empty(), "Paused production must freeze the paid heavy queue and shared wallet")
	await press(KEY_ESCAPE)
	game.run.grant("科技回归 · 免费选卡冻结夹具")
	await press(KEY_V)
	check(game.phase == "draft", "A real free pending choice must open the production draft")
	game.squads.advance(11.0)
	game.districts.tick(11.0)
	check(game.squads.training_queues == frozen.queues and game.scrap == int(frozen.parts)
		and game.squads.squads.is_empty(), "Draft production must freeze existing heavy training without spending")
	await press(KEY_1)
	await destroy(laboratory, "laboratory")
	check(not bool(game.squads.training_eligibility("ballista").available), "Destroyed research must immediately lock new heavy orders")
	await open_army()
	balance = game.scrap
	await click_ui(game.hud.training_kind_rect(0))
	check(game.scrap == balance and game.squads.training_queues.get(barracks, []).size() == 1,
		"The visible locked advanced button must not charge after research destruction")
	check(not bool(game.squads.enqueue("ballista").ok) and not bool(game.squads.hire("ballista").ok)
		and game.scrap == balance, "Every heavy creation entry point must reject a missing live laboratory")
	await capture("heavy-locked-paid-queue", true)
	game.squads.advance(9.99)
	check(game.squads.squads.is_empty(), "A paid order must not finish before ten actual training seconds")
	game.squads.advance(.02)
	check(game.squads.squads.size() == 1 and game.squads.training_queues.get(barracks, []).is_empty()
		and game.scrap == balance, "Previously paid heavy training must finish after technology loss without a second fee")
	if not game.squads.squads.is_empty(): assert_heavy(game.squads.squads[0])
	await press(KEY_ESCAPE)
	var rebuilt := await build_gui("laboratory", LABORATORY)
	check(rebuilt == laboratory and bool(game.squads.training_eligibility("ballista").available),
		"Research paid rebuilding must restore the same identity and new heavy order eligibility")
	completed.append("training")

func reset_shooter(group: Dictionary, enemy: BattleUnit, point: Vector3) -> BattleUnit:
	game.squads.cancel_selection()
	game.squads.select_at(group.members[1].position)
	game.squads.command_guard(point)
	for slot in 3:
		var soldier: BattleUnit = group.members[slot]
		soldier.position = point + Vector3((slot - 1) * 1.25, 0, 0)
		soldier.path.clear()
		soldier.attack_queued = false
		soldier.target = null
		# Isolate one real shooter; other members remain alive and stationary.
		soldier.attack_timer = 9999.0 if slot != 1 else 0.0
		soldier.attack_windup = 0.0
	enemy.position = point + Vector3(8, 0, 0)
	return group.members[1]

func heavy_actual_combat() -> void:
	if game.squads.squads.is_empty(): return
	remove_enemies()
	var group: Dictionary = game.squads.squads[0]
	var target: BattleUnit = game.spawn_creature(true, "basic")
	target.max_hp = 10000.0
	target.hp = target.max_hp
	target.armor = 0.0
	target.speed = 0.0
	var origin := Vector3(-4, 5, -11)
	var shooter := reset_shooter(group, target, origin)
	check(game.can_attack_line(shooter.position, target.position), "The combat fixture must use a truly unobstructed city firing line")
	var hp := target.hp
	var kills: int = game.kills
	var parts: int = game.scrap
	game.squads.advance(.001)
	check(shooter.attack_queued and is_equal_approx(shooter.attack_windup, .55) and target.hp == hp,
		"Real heavy advance must begin a visible .55-second windup without immediate damage")
	camera_at(Vector3(0, 5, -9))
	await capture("heavy-real-windup", true)
	game.squads.advance(.54)
	check(shooter.attack_queued and target.hp == hp, "Heavy damage must wait for the actual complete windup")
	game.squads.advance(.011)
	check(not shooter.attack_queued and is_equal_approx(target.hp, hp - 46.0)
		and is_equal_approx(shooter.attack_timer, 3.2) and not game.squads.shots.is_empty(),
		"The actual completed windup must submit exactly one forty-six-damage hit and its bolt effect")
	await capture("heavy-real-strike", true)
	game.squads.advance(3.19)
	check(not shooter.attack_queued and is_equal_approx(target.hp, hp - 46.0),
		"A heavy shooter must not attack again before its full 3.2-second cooldown")
	game.squads.advance(.02)
	check(shooter.attack_queued and is_equal_approx(target.hp, hp - 46.0),
		"The next legal heavy attack must start a new windup rather than an instant second hit")
	game.squads.advance(.55)
	check(is_equal_approx(target.hp, hp - 92.0) and game.kills == kills and game.scrap == parts,
		"Two actual heavy impacts must deal ninety-two damage without hero kill/parts attribution")
	shooter = reset_shooter(group, target, origin)
	hp = target.hp
	game.squads.advance(.001)
	check(shooter.attack_queued, "The distance-cancel test must first begin a real windup")
	target.position = origin + Vector3(18, 0, 0)
	game.squads.advance(.56)
	check(not shooter.attack_queued and target.hp == hp,
		"A target leaving the real 12.8-metre range before impact must cancel queued heavy damage")
	shooter = reset_shooter(group, target, origin)
	game.squads.advance(.001)
	check(shooter.attack_queued, "The dead-target test must first begin a real windup")
	var victim_id := target.get_instance_id()
	target.hurt(100000.0, game.hero)
	kills = game.kills
	parts = game.scrap
	game.squads.advance(.56)
	check(not shooter.attack_queued and game.kills == kills and game.scrap == parts,
		"An actually defeated pending target must not cause duplicate impact, death or reward")
	await process_frame
	check(not is_instance_id_valid(victim_id), "The production defeated creature must actually release its old instance")
	remove_enemies()
	game.squads.cancel_selection()
	shooter.hurt(shooter.max_hp * .5, null)
	var ratio := shooter.hp / shooter.max_hp
	var barracks: int = evidence.buildings.barracks
	var balance: int = game.scrap
	var upgraded: Dictionary = game.districts.upgrade(barracks)
	check(bool(upgraded.ok) and game.scrap == balance - 80 and is_equal_approx(shooter.max_hp, 150.0 * game.districts.squad_health_multiplier())
		and is_equal_approx(shooter.hp / shooter.max_hp, ratio),
		"Real barracks upgrading must apply heavy catalog HP while retaining each living troop's damaged proportion")
	var lost: BattleUnit = group.members[0]
	lost.hurt(100000.0, null)
	await process_frame
	game.finish_night()
	check(game.phase == "draft", "The actual dawn must open its free production choice before daytime restocking")
	await press(KEY_1)
	check(game.phase == "day", "Actual dawn choice must resume day for paid troop recovery")
	remove_enemies()
	var fee: int = game.squads.refill_cost(0)
	balance = game.scrap
	await press(KEY_L)
	check(fee == 37 and game.scrap == balance - fee and game.squads.refill_cost(0) == 0,
		"Real daytime L must charge one missing heavy member's 32 parts plus the damaged survivor's five")
	assert_heavy(group)
	balance = game.scrap
	await press(KEY_L)
	check(game.scrap == balance, "Repeated L on a restored real heavy squad must never charge again")
	game.start_night()
	remove_enemies()
	for pad: Dictionary in game.world.tower_pads: pad.cooldown = 9999.0
	completed.append("combat")

func heavy_refunds_and_pagination() -> void:
	var barracks: int = evidence.buildings.barracks
	await train_heavy_gui()
	await train_heavy_gui()
	await train_heavy_gui()
	await train_heavy_gui()
	check(game.squads.training_queues.get(barracks, []).size() == 4, "Four actual advanced button presses must create four paid orders")
	await click_ui(game.hud.training_page_rect(1))
	await redraw()
	check(game.hud.training_page == 1 and game.hud.troop_page == 1,
		"Actual refund paging must operate independently of the heavy troop page")
	await press(KEY_PAGEUP)
	check(game.hud.troop_page == 0 and game.hud.training_page == 1,
		"Army PgUp must leave the chosen second refund page intact")
	await click_ui(game.hud.troop_page_rect(1))
	await redraw()
	check(game.hud.training_cancel_buttons.size() == 1 and int(game.hud.training_cancel_buttons[0].queue_index) == 3,
		"The visible second refund page must retain the exact fourth order identity")
	await capture("heavy-page-and-refund-page", true)
	var balance: int = game.scrap
	if not game.hud.training_cancel_buttons.is_empty():
		var button: Rect2 = game.hud.training_cancel_buttons[0].rect
		await click_ui(button)
		check(game.scrap == balance + 110 and game.squads.training_queues.get(barracks, []).size() == 3,
			"The actual advanced-order cancel button must refund its paid 110 parts exactly once")
	# Cancel the remaining production orders through their real cancellation
	# authority before the isolated two-order barracks-destruction assertion.
	while not game.squads.training_queues.get(barracks, []).is_empty(): game.squads.cancel_training(barracks, 0)
	await redraw()
	balance = game.scrap
	check(not bool(game.squads.cancel_training(barracks, 0).ok) and game.scrap == balance,
		"An empty advanced queue must reject another refund")
	await train_heavy_gui()
	await train_heavy_gui()
	balance = game.scrap
	await destroy(barracks, "barracks")
	check(game.scrap == balance + 220 and not game.squads.training_queues.has(barracks),
		"Destroyed production barracks must refund both unfinished 110-part heavy orders once")
	game.districts.damage(barracks, 100000.0)
	game.squads.refresh_barracks()
	check(game.scrap == balance + 220 and game.squads.squads.size() == 1,
		"Repeated barracks destruction/refresh must not refund twice or remove an already completed heavy squad")
	balance = game.scrap
	check(not bool(game.squads.enqueue("ballista").ok) and game.scrap == balance,
		"A live laboratory without any live production barracks must not accept a new heavy order")
	await press(KEY_ESCAPE)
	completed.append("refunds")

func kill_for_recovery(enemy: BattleUnit, point: Vector3) -> Dictionary:
	var id := enemy.get_instance_id()
	enemy.position = point
	var before: int = game.scrap
	var kills: int = game.kills
	enemy.hurt(100000.0, game.hero)
	check(not enemy.alive and game.kills == kills + 1, "Recovery must start with one real production night-enemy death")
	var reward: int = game.scrap - before
	var paid: int = game.scrap
	enemy.hurt(100000.0, game.hero)
	check(game.scrap == paid and game.kills == kills + 1 and not bool(game.districts.register_wreck(id, point).accepted),
		"Repeated real lethal input and the same wreck identity must never register a second recovery")
	return {"id": id, "base_reward": reward}

func wreck_recovery() -> void:
	await fresh(true)
	await build_gui("workshop", WORKSHOP)
	var recycler := await build_gui("recycler", RECYCLER)
	var station_point: Vector3 = game.districts.plots[recycler].position
	var initial_ids: Array[int] = []
	var victims: Array = game.enemies.duplicate()
	check(not victims.is_empty(), "Limited recovery must use the actual first-night wave rather than fabricated kill rewards")
	if victims.is_empty(): return
	var first: Dictionary = kill_for_recovery(victims[0], station_point + Vector3(0, 0, 2))
	initial_ids.append(int(first.id))
	var row := snapshot(recycler)
	check(int(row.pending) == 2 and int(row.recovered) == 0 and int(row.recovery_cap_remaining) == 22,
		"A genuine nearby first-night death must queue exactly two parts against the global twenty-four cap")
	var balance: int = game.scrap
	game.districts.tick(3.99)
	row = snapshot(recycler)
	check(game.scrap == balance and int(row.pending) == 2 and float(row.recovery_progress) > .99,
		"A level-one recovery station must not pay before its complete four-second processing interval")
	await capture("recycler-real-pending", true)
	game.districts.tick(.02)
	row = snapshot(recycler)
	check(game.scrap == balance + 2 and int(row.pending) == 0 and int(row.recovered) == 2,
		"Completed real wreck processing must add two parts to the same production wallet")
	var second := await build_gui("recycler", SECOND_RECYCLER)
	check(int(snapshot(second).recovery_cap_remaining) == 22,
		"Building another real recovery station must not multiply or reset the whole-city per-night budget")
	var second_point: Vector3 = game.districts.plots[second].position
	var base_income := int(first.base_reward)
	var deaths := 1
	for value in victims:
		if not is_instance_valid(value): continue
		var enemy := value as BattleUnit
		if not enemy.alive: continue
		var outcome: Dictionary = kill_for_recovery(enemy, station_point + Vector3(0, 0, 2) if deaths % 2 == 0 else second_point + Vector3(0, 0, 2))
		base_income += int(outcome.base_reward)
		initial_ids.append(int(outcome.id))
		deaths += 1
	await process_frame
	game.enemies.clear()
	game.spawn_night_wave()
	victims = game.enemies.duplicate()
	for value in victims:
		if not is_instance_valid(value): continue
		var enemy := value as BattleUnit
		if not enemy.alive: continue
		var outcome: Dictionary = kill_for_recovery(enemy, station_point + Vector3(0, 0, 2) if deaths % 2 == 0 else second_point + Vector3(0, 0, 2))
		base_income += int(outcome.base_reward)
		initial_ids.append(int(outcome.id))
		deaths += 1
	check(deaths > 12 and int(snapshot(recycler).recovery_cap_remaining) == 0
		and int(snapshot(second).recovery_cap_remaining) == 0,
		"More than twelve actual night deaths across two stations must exhaust one shared twenty-four-part capture cap")
	var pending: int = int(snapshot(recycler).pending) + int(snapshot(second).pending)
	check(pending == 22, "After the first paid two parts, both real stations together may retain only twenty-two more")
	balance = game.scrap
	game.districts.tick(100.0)
	check(game.scrap == balance + 22 and int(snapshot(recycler).recovered) + int(snapshot(second).recovered) == 24,
		"Processing every captured real wreck across both stations must yield at most twenty-four additional parts this night")
	balance = game.scrap
	game.districts.begin_night(1)
	check(int(snapshot(recycler).recovery_cap_remaining) == 0
		and not bool(game.districts.register_wreck(9912345, station_point).accepted),
		"Repeating the same-night start must not reset the shared recovery cap")
	game.districts.tick(100.0)
	check(game.scrap == balance, "Exhausted recovery must not create passive income without captured wrecks")
	evidence.recovery = {"actual_deaths": deaths, "actual_wave_base_parts": base_income,
		"processed_parts": 24, "stations": 2, "cap_remaining": 0}
	await process_frame
	game.enemies.clear()
	game.finish_night()
	await press(KEY_1)
	check(game.phase == "day" and game.day_number == 2, "Real first-night completion must reach the second production day")
	var day_enemy: BattleUnit = game.enemies[0]
	day_enemy.position = station_point
	day_enemy.hurt(100000.0, game.hero)
	check(int(snapshot(recycler).pending) == 0 and int(snapshot(recycler).recovery_cap_remaining) == 0,
		"A genuine daylight enemy death must not register another night wreck")
	check(not bool(game.districts.register_wreck(9912346, station_point).accepted), "Direct daytime wreck registration must reject")
	game.start_night()
	check(int(snapshot(recycler).recovery_cap_remaining) == 24,
		"The actual controller start of the next night must restore one whole-city twenty-four-part capture budget")
	for id: int in initial_ids:
		check(not bool(game.districts.register_wreck(id, station_point).accepted), "An actual old death identity must stay consumed across nights")
	var far: BattleUnit = game.enemies[0]
	var far_outcome: Dictionary = kill_for_recovery(far, Vector3(100, 0, 100))
	check(int(snapshot(recycler).recovery_cap_remaining) == 24
		and not bool(game.districts.register_wreck(int(far_outcome.id), station_point).accepted),
		"A real out-of-range death must stay ineligible after moving its previously observed identity nearer")
	var nearest: BattleUnit = game.enemies[1]
	kill_for_recovery(nearest, second_point + Vector3(0, 0, .5))
	check(int(snapshot(second).pending) == 2 and int(snapshot(recycler).pending) == 0,
		"A real death must be assigned once to its nearest live station")
	balance = game.scrap
	game.districts.upgrade(second)
	check(game.scrap == balance - 80 and int(snapshot(second).level) == 2,
		"Actual paid station upgrading must consume its real eighty-part fee")
	balance = game.scrap
	game.districts.tick(2.99)
	check(game.scrap == balance and int(snapshot(second).pending) == 2,
		"A level-two station must still wait the full faster three-second interval")
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "Recovery freeze test must enter actual paused production")
	var stopped := snapshot(second)
	game.districts.tick(10.0)
	check(snapshot(second) == stopped and game.scrap == balance
		and not bool(game.districts.register_wreck(9912347, second_point).accepted),
		"Actual pause must freeze pending processing and reject new wreck registration")
	await press(KEY_ESCAPE)
	game.run.grant("回收回归 · 免费选卡冻结夹具")
	await press(KEY_V)
	game.districts.tick(10.0)
	check(game.phase == "draft" and snapshot(second) == stopped and game.scrap == balance
		and not bool(game.districts.register_wreck(9912348, second_point).accepted),
		"Actual card choice must also freeze pending wreck recovery")
	await press(KEY_1)
	game.districts.tick(.02)
	check(game.scrap == balance + 2 and int(snapshot(second).pending) == 0,
		"Resuming production must finish the existing upgraded station progress once")
	var stock: BattleUnit = game.enemies[2]
	kill_for_recovery(stock, station_point)
	check(int(snapshot(recycler).pending) == 2, "The final destruction case must start with one genuine captured wreck")
	balance = game.scrap
	await destroy(recycler, "recycler")
	check(int(snapshot(recycler).pending) == 0, "Destroyed recovery must discard its own unfinished captured stock")
	game.districts.tick(10.0)
	check(game.scrap == balance, "A destroyed station must not pay its discarded stock through an orphan timer")
	await build_gui("recycler", RECYCLER)
	check(int(snapshot(recycler).pending) == 0 and int(snapshot(recycler).recovered) == 0
		and int(snapshot(recycler).recovery_cap_remaining) == 20,
		"Paid recovery rebuilding must clear local stock while preserving this night's already consumed global cap")
	game.districts.begin_night(3)
	check(game.day_number == 2 and int(snapshot(recycler).recovery_cap_remaining) == 20,
		"Passing a future night number during the actual second night must not reset its spent capture budget")
	game.day_number = 3
	check(not bool(game.districts.register_wreck(9912350, station_point).accepted)
		and int(snapshot(recycler).recovery_cap_remaining) == 20,
		"A manually switched night without the controller's legitimate begin must not register new wrecks")
	game.day_number = 2
	check(not bool(game.districts.register_wreck(-1, station_point).accepted)
		and not bool(game.districts.register_wreck(9912349, Vector3.INF).accepted),
		"Invalid identities and non-finite wreck positions must never consume a capture")
	await open_army()
	await capture("expanded-army-page-one", false)
	await press(KEY_PAGEDOWN)
	await capture("expanded-army-tech-locked", true)
	await press(KEY_ESCAPE)
	var carry: BattleUnit = game.enemies[3]
	kill_for_recovery(carry, station_point)
	check(int(snapshot(recycler).pending) == 2, "Cross-day processing must start with a genuine captured second-night wreck")
	game.finish_night()
	await press(KEY_1)
	check(game.phase == "day" and game.day_number == 3, "Actual dawn must carry already captured wreck stock into the next day")
	check(int(snapshot(recycler).pending) == 2, "Dawn must preserve previously captured stock without generating another death")
	balance = game.scrap
	game.districts.tick(4.01)
	check(game.scrap == balance + 2 and int(snapshot(recycler).pending) == 0,
		"A living station may finish its existing night wreck during active daylight without a fresh capture")
	await clean_build_navigation("Idle daylight")
	completed.append("recovery")

func run() -> void:
	await catalog_and_technology()
	await troop_pages_and_paid_queue()
	await heavy_actual_combat()
	await heavy_refunds_and_pagination()
	await wreck_recovery()
	check(completed == ["technology", "training", "combat", "refunds", "recovery"],
		"Every complete technology stage must finish; a runtime-aborted coroutine cannot be reported as a passing suite")
	await close_game()
	var folder := ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(folder)
	evidence.checks = checks
	evidence.failures = failures
	var file := FileAccess.open(folder.path_join("results.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(evidence, "\t")); file.close()
	print("NIGHTFALL_OUTPOST_TECH_EVIDENCE " + JSON.stringify(evidence))
	print("NIGHTFALL_OUTPOST_TECH_OK checks=%d" % checks if failures.is_empty()
		else "NIGHTFALL_OUTPOST_TECH_FAILED checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
