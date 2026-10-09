extends SceneTree

## Production input and controller regression for mobile construction vehicles.
## The first 25 seconds are a real opening observation. Later isolated vehicle,
## wallet and damaged-technology fixtures test precision, not natural balance.
const Grid := preload("res://scripts/construction_grid.gd")
const Catalog := preload("res://scripts/outpost_catalog.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
const VehicleScript := preload("res://scripts/outpost_supply_crate.gd")
const Session := preload("res://scripts/run_session.gd")
const STEP := 1.0 / 30.0
var game: Node3D
var checks := 0
var failures: Array[String] = []
var render_test := false
var opening_vehicle_kind := ""

class ObservedNightfall extends "res://scripts/nightfall.gd":
	# Observe the real delivery call, including opening calls made by choose_card.
	# The first wave legitimately consumes spawn RNG before this call, so whole
	# card-selection before/after comparisons cannot isolate vehicle randomness.
	var delivery_observations: Array[Dictionary] = []
	func _spawn_supply_crate() -> bool:
		var record := {"spawn_before": spawn_rng.state, "wallet_before": scrap,
			"plots_before": districts.plots.size(), "towers_before": tower_count(),
			"alive_before": int(squads.snapshot().alive)}
		var delivered: bool = super._spawn_supply_crate()
		record.merge({"delivered": delivered, "spawn_after": spawn_rng.state,
			"wallet_after": scrap, "plots_after": districts.plots.size(),
			"towers_after": tower_count(), "alive_after": int(squads.snapshot().alive)})
		delivery_observations.append(record)
		return delivered

func _initialize() -> void:
	render_test = "--render-test" in OS.get_cmdline_user_args()
	root.size = Vector2i(1920, 1200)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = root.size
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:return
	failures.append(message)
	if failures.size() <= 30:push_error(message)

func ground(point: Vector3) -> Vector3:
	point.y = game.outpost_height(point)
	return point

func planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func stand(point: Vector3) -> void:
	game.hero.position = ground(point)
	game.move_goal = game.hero.position
	game.hero_path.clear()
	game.hero_keyboard_active = false

func camera_at(point: Vector3, size: float = 38.0) -> void:
	game.camera.size = size
	game.camera_follow = point + Vector3(0, 25, 29)
	game.camera.position = game.camera_follow
	game.camera.look_at(point)

func mouse_at(screen: Vector2, button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = screen
	event.global_position = screen
	event.button_index = button
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame

func click_screen(screen: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	await mouse_at(screen, button, true)
	await mouse_at(screen, button, false)

func click_world(point: Vector3, button: int = MOUSE_BUTTON_LEFT) -> void:
	await click_screen(game.camera.unproject_position(ground(point)), button)

func aim_world(point: Vector3) -> void:
	var event := InputEventMouseMotion.new()
	event.position = game.camera.unproject_position(ground(point))
	event.global_position = event.position
	root.push_input(event, true)
	await process_frame
	# Precision cases disable automatic processing. Flush the real queued mouse
	# sample through the same controller entry used before rendering and keys.
	game.flush_pending_aim()
	game.construction.tick(0.0)

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func select_by_mouse(vehicle: Node3D) -> void:
	var screen: Vector2 = game.camera.unproject_position(vehicle.global_position + Vector3.UP * .8)
	check(game.construction_vehicle_under_cursor(screen) == vehicle, "The actual vehicle screen silhouette must resolve to its live world object")
	await click_screen(screen)
	check(is_same(game.selected_construction_vehicle, vehicle) and bool(vehicle.selected), "A real left-click must select the construction vehicle")

func select_by_drag(vehicle: Node3D) -> void:
	var screen: Vector2 = game.camera.unproject_position(vehicle.global_position)
	var begin := screen - Vector2(30, 30)
	var end := screen + Vector2(30, 30)
	await mouse_at(begin, MOUSE_BUTTON_LEFT, true)
	var motion := InputEventMouseMotion.new()
	motion.position = end
	motion.global_position = end
	motion.relative = end - begin
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	await mouse_at(end, MOUSE_BUTTON_LEFT, false)
	check(is_same(game.selected_construction_vehicle, vehicle), "A real drag-selection rectangle must select a vehicle inside it")

func isolate() -> void:
	game.set_process(false)
	game.phase_time = 10000.0
	for enemy: BattleUnit in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()
	game.contracts.status = "idle"
	for item: Dictionary in game.discoveries.items:game.discoveries.begin_cooling(item, 9999.0)
	for cache: Dictionary in game.world.salvage:
		cache.collected = true
		cache.respawn = 9999.0
	for generator: Dictionary in game.expeditions.generators:generator.state = "complete"
	for camp: Dictionary in game.expeditions.camps:camp.state = "delivered"
	for nest: Dictionary in game.world.nests:nest.cleansed = true
	for relay: Dictionary in game.world.relays:relay.activated = true
	for pad: Dictionary in game.world.tower_pads:pad.cooldown = 9999.0

func in_roster(vehicle: Variant) -> bool:
	# Input helpers await frames, so a successfully consumed vehicle may already
	# be freed. Guard it before asking Godot's typed Node3D array about membership.
	return is_instance_valid(vehicle) and game.supply_crates.has(vehicle)

func clear_vehicles() -> void:
	game.clear_supply_crates(true)
	game.construction.cancel()

func fixture_vehicle(kind: String, point: Vector3) -> Node3D:
	# Controlled vehicle assignment avoids relying on a particular reward roll.
	# It does not deploy buildings or add units; production must still charge.
	var vehicle := VehicleScript.new() as Node3D
	vehicle.setup(game.supply_crate_serial, kind, String(Catalog.building(kind).title))
	game.supply_crate_serial += 1
	vehicle.position = ground(point)
	game.add_child(vehicle)
	game.supply_crates.append(vehicle)
	return vehicle

func legal_point(kind: String, center: Vector3 = Vector3.ZERO, extent: int = 19) -> Vector3:
	for z in range(-extent, extent + 1):
		for x in range(-extent, extent + 1):
			var quote: Dictionary = game.construction.validity(ground(center + Vector3(x, 0, z)), -1, kind)
			if bool(quote.valid):return quote.point
	return Vector3.INF

func movement_and_build_pair() -> Array[Vector3]:
	for z in range(-18, 19):
		for x in range(-18, 13):
			var quote: Dictionary = game.construction.validity(ground(Vector3(x, 0, z)), -1, "barracks")
			if not bool(quote.valid):continue
			var goal: Vector3 = quote.point
			var start: Vector3 = ground(goal + Vector3(6, 0, 0))
			if game.outpost_walkable(start) and game.can_traverse(start, goal):return [start, goal]
	return []

func capture(label: String, settle_lighting: bool = true) -> void:
	if not render_test or DisplayServer.get_name() == "headless":return
	if settle_lighting:game.world._process(game.world.LIGHT_TRANSITION_SECONDS)
	game.hud.queue_redraw()
	for _frame in 6:
		await process_frame
		await RenderingServer.frame_post_draw
	var directory := "res://build/construction-vehicles-render"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK, "Create the local vehicle rendering evidence directory")
	var picture: Image = root.get_texture().get_image()
	check(picture.get_size() == root.content_scale_size, "Vehicle screenshots must match their requested viewport")
	var output := directory + "/" + label + ".png"
	check(picture.save_png(output) == OK, "Save actual vehicle frame " + label)
	print("CONSTRUCTION_VEHICLE_FRAME ", ProjectSettings.globalize_path(output))

func capture_three_views(vehicle: Node3D, label: String) -> void:
	var before_size: Vector2i = root.size
	var before_scale: Vector2i = root.content_scale_size
	for size: Vector2i in [Vector2i(1920, 1200), Vector2i(1920, 1080), Vector2i(1440, 900)]:
		root.size = size
		root.content_scale_size = size
		camera_at(vehicle.position)
		await select_by_mouse(vehicle)
		await capture("%s-%dx%d" % [label, size.x, size.y])
	root.size = before_size
	root.content_scale_size = before_scale

func new_game() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	# PackedScene construction already evaluates the base script's two Node
	# initializers. Replacing its script initializes fresh managers; unlike
	# RefCounted fields, the original unparented Nodes need explicit retirement.
	for member_name: String in ["contracts", "districts"]:
		var initial_manager: Node = game.get(member_name) as Node
		var detached: bool = is_instance_valid(initial_manager) and not initial_manager.is_inside_tree() and initial_manager.get_parent() == null
		check(detached, "The observer must retire only the unparented pre-ready " + member_name + " manager before replacing the scene script")
		if detached:initial_manager.free()
	game.set_script(ObservedNightfall)
	root.add_child(game)
	game.archive.enabled = false
	current_scene = game
	await create_timer(.25).timeout
	game.set_process(false)

func close_game() -> void:
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout

func check_delivery_observations(context: String) -> void:
	var records: Array = game.delivery_observations
	check(not records.is_empty(), context + ": the real delivery path must have executed")
	for record: Dictionary in records:
		check(int(record.spawn_before) == int(record.spawn_after), context + ": vehicle delivery must preserve the independent hostile RNG stream")
		check(int(record.wallet_before) == int(record.wallet_after) and int(record.plots_before) == int(record.plots_after) and int(record.towers_before) == int(record.towers_after) and int(record.alive_before) == int(record.alive_after), context + ": delivery itself must not grant resources, buildings or troops")

func courtyard_lighting() -> void:
	var lamps: Array = game.world.courtyard_lamps
	var globes: Array = game.world.courtyard_globes
	check(lamps.size() == 6 and globes.size() == 6, "The enlarged main courtyard must contain six actual wall lights and six visible lamp globes")
	var left := 0
	var right := 0
	for lamp: OmniLight3D in lamps:
		check(is_instance_valid(lamp) and lamp.is_inside_tree() and game.world.is_ancestor_of(lamp), "Every courtyard light must be a live world entity")
		if lamp.global_position.x < 0.0:left += 1
		else:right += 1
		check(lamp.light_color.r > lamp.light_color.g and lamp.light_color.g > lamp.light_color.b and not lamp.shadow_enabled and lamp.omni_range > 0.0, "Courtyard wall lights must use warm light without adding shadow instability")
		var fixture: Node = lamp.get_parent()
		check(fixture != game.world and fixture.find_children("*", "CollisionObject3D", true, false).is_empty(), "The complete wall-lamp fixture must add no unit-blocking collision body")
	check(left == 3 and right == 3, "The authored courtyard lights must cover both side walls with three lights each")
	game.world._process(game.world.LIGHT_TRANSITION_SECONDS)
	for lamp: OmniLight3D in lamps:
		check(is_equal_approx(lamp.light_energy, game.world.COURTYARD_LAMP_NIGHT_ENERGY), "Actual night transition must illuminate each courtyard lamp")

func capture_opening_lighting_comparison() -> void:
	if not render_test or DisplayServer.get_name() == "headless":return
	# This diagnostic frame shares the production camera and original main/gate
	# lights. Disable only the six new lamps and their shared globe emission.
	var was_processing: bool = game.world.is_processing()
	game.world.set_process(false)
	var energies: Array[float] = []
	for lamp: OmniLight3D in game.world.courtyard_lamps:
		energies.append(lamp.light_energy)
		lamp.light_energy = 0.0
	var globe_material: StandardMaterial3D = game.world.courtyard_globe_material
	var emission: float = globe_material.emission_energy_multiplier
	globe_material.emission_energy_multiplier = 0.0
	await capture("real-first-night-zero-seconds-courtyard-lights-off-comparison", false)
	for index in game.world.courtyard_lamps.size():
		game.world.courtyard_lamps[index].light_energy = energies[index]
	globe_material.emission_energy_multiplier = emission
	game.world.set_process(was_processing)
	check(is_equal_approx(globe_material.emission_energy_multiplier, emission), "The comparison capture must restore the production globe emission")
	for index in game.world.courtyard_lamps.size():
		check(is_equal_approx(game.world.courtyard_lamps[index].light_energy, energies[index]), "The comparison capture must restore every production courtyard light")

func real_opening() -> void:
	check(game.phase == "draft" and game.supply_crates.is_empty(), "Before the opening card is chosen, the production draft must contain no construction vehicle")
	var opening_wallet: int = game.scrap
	var opening_plots: int = game.districts.plots.size()
	var opening_towers: int = game.tower_count()
	check(game.phase == "draft" and game.choose_card(0), "The production draft must start a playable first night")
	check(game.supply_crates.size() == 1 and is_equal_approx(game.supply_crate_clock, 0.0), "Completing the opening card must immediately deliver one actual construction vehicle and begin a fresh twenty-five-second timer")
	if game.supply_crates.size() == 1:opening_vehicle_kind = String(game.supply_crates[0].supply_kind)
	check(game.scrap == opening_wallet and game.districts.plots.size() == opening_plots and game.tower_count() == opening_towers and game.squads.snapshot().alive == 0, "The opening vehicle must not charge or grant resources, a free building or an instant troop")
	check_delivery_observations("Immediate opening delivery")
	var supply_state: int = game.supply_rng.state
	check(not game.choose_card(0) and game.supply_crates.size() == 1 and game.supply_rng.state == supply_state, "Repeated card selection outside the opening draft must not deliver another vehicle")
	courtyard_lighting()
	await capture("real-first-night-zero-seconds-default-camera")
	await capture_opening_lighting_comparison()
	var lamp_energy: Array[float] = []
	for lamp: OmniLight3D in game.world.courtyard_lamps:lamp_energy.append(lamp.light_energy)
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "Real Escape input must pause before any opening game time has elapsed")
	game.advance_supply_crates(100.0)
	game.world._process(100.0)
	check(game.supply_crates.size() == 1 and is_equal_approx(game.supply_crate_clock, 0.0) and game.supply_rng.state == supply_state, "Pausing the immediate opening vehicle must freeze the next delivery clock and random stream")
	for index in game.world.courtyard_lamps.size():
		check(is_equal_approx(game.world.courtyard_lamps[index].light_energy, lamp_energy[index]), "Pause must retain steady courtyard lamp energy")
	await press(KEY_ESCAPE)
	check(game.phase == "night", "A second real Escape input must resume the original first night")
	var elapsed: float = 0.0
	while elapsed < 24.9 and game.phase == "night":
		game._process(STEP)
		elapsed += STEP
	check(elapsed < 25.0 and game.supply_crates.size() == 1, "The real first night must retain only its opening vehicle before the twenty-five-second periodic delivery")
	while elapsed < 25.1 and game.phase == "night":
		game._process(STEP)
		elapsed += STEP
	check(elapsed >= 25.1 and game.phase == "night" and game.hero.alive and game.beacon_hp > 0.0, "The original first-night opening must survive through the real vehicle delivery interval")
	check(game.supply_crates.size() == 2, "After twenty-five real game seconds, the opening vehicle and a second timed vehicle must both exist")
	for vehicle: Node3D in game.supply_crates:
		check(String(vehicle.supply_kind) in Catalog.BUILDING_IDS, "Automatic vehicle deliveries must carry only a real building type")
		var distance: float = planar(vehicle.position, game.hero.position)
		check(distance >= 6.0 - .01 and distance <= 12.0 + .01 and game._supply_crate_in_view(vehicle.position), "A naturally delivered vehicle must remain nearby and visible in the default camera")
		check(not bool(vehicle.opened) and not game.construction.active, "Automatic delivery must not consume the vehicle or enter a construction catalogue")
	check_delivery_observations("Opening and first periodic delivery")
	await capture("real-first-night-default-camera")
	print("CONSTRUCTION_VEHICLE_OPENING elapsed=%.3f phase=%s hero_hp=%.3f beacon_hp=%.3f vehicles=%d" % [elapsed, game.phase, game.hero.hp, game.beacon_hp, game.supply_crates.size()])

func blocked_opening_retry() -> void:
	check(Session.queue_request(self, 20261009, "teaching"), "Queue a separate original-seed scene for the blocked opening precision case")
	await new_game()
	var old_blocks: Array[Rect2] = game.construction_blocks.duplicate()
	var everywhere: Array[Rect2] = [Rect2(Vector2(-Layout.MAP_HALF_X - 1.0, -Layout.MAP_HALF_Z - 1.0), Vector2(Layout.MAP_HALF_X * 2.0 + 2.0, Layout.MAP_HALF_Z * 2.0 + 2.0))]
	game.construction_blocks = everywhere
	var balance: int = game.scrap
	check(game.choose_card(0) and game.phase == "night", "Opening selection must still complete while all nearby delivery positions are physically blocked")
	check(game.supply_crates.is_empty() and is_equal_approx(game.supply_crate_clock, 25.0) and is_equal_approx(game.supply_crate_retry, 1.0) and game.scrap == balance, "A blocked opening delivery must stay due with a one-second game-time retry without consuming resources")
	check_delivery_observations("Blocked opening delivery")
	var supply_state: int = game.supply_rng.state
	game.advance_supply_crates(.49)
	game.advance_supply_crates(.49)
	check(game.supply_crates.is_empty() and game.supply_rng.state == supply_state, "The blocked opening cannot search or deliver before the original one-second retry expires")
	var clock: float = game.supply_crate_clock
	var retry: float = game.supply_crate_retry
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "The blocked opening must also accept a real pause input")
	game.advance_supply_crates(100.0)
	check(is_equal_approx(game.supply_crate_clock, clock) and is_equal_approx(game.supply_crate_retry, retry) and game.supply_rng.state == supply_state and game.supply_crates.is_empty(), "Pause must freeze the blocked first-delivery request instead of dropping or repeating it")
	await press(KEY_ESCAPE)
	game.construction_blocks = old_blocks
	game.advance_supply_crates(.01)
	check(game.supply_crates.is_empty() and game.supply_rng.state == supply_state, "Releasing nearby terrain must preserve the remainder of the first delivery retry")
	game.advance_supply_crates(.02)
	check(game.supply_crates.size() == 1 and game.supply_crate_retry == 0.0 and game.supply_crate_clock < 2.0 and game.scrap == balance, "The original opening request must deliver its actual vehicle once legal ground returns without waiting another full interval")
	check_delivery_observations("Released opening delivery")
	game.end_defeat("Blocked opening vehicle precision defeat")
	game.advance_supply_crates(100.0)
	check(game.phase == "ended" and game.supply_crates.is_empty(), "A real failure must retire the opening vehicle and prevent its due request from reappearing")
	await close_game()

func parameterized_opening_deliveries() -> void:
	for seed_value: int in [20261010, 41]:
		for mode: String in ["teaching", "siege", "echo"]:
			var context := "%s seed %d" % [mode, seed_value]
			check(Session.queue_request(self, seed_value, mode), context + ": queue an independent production opening")
			await new_game()
			var balance: int = game.scrap
			check(game.phase == "draft" and game.supply_crates.is_empty(), context + ": no vehicle may precede the final opening card")
			if seed_value == 41 and mode == "teaching":
				# A queued extra card is an explicit draft precision fixture. It
				# still uses the real grant/choose pipeline and grants no parts.
				game.run.grant("opening-vehicle-draft-precision")
				var initial_supply_state: int = game.supply_rng.state
				check(game.choose_card(0) and game.phase == "draft" and game.supply_crates.is_empty() and game.supply_rng.state == initial_supply_state, "An unfinished opening draft must not deliver a vehicle before its final queued card")
			check(game.choose_card(0) and game.phase == "night" and game.supply_crates.size() == 1, context + ": completing the opening card must immediately create one vehicle")
			check(game.scrap == balance and game.districts.plots.is_empty() and game.squads.snapshot().alive == 0 and is_equal_approx(game.supply_crate_clock, 0.0), context + ": an immediate vehicle cannot bypass economy or training")
			if game.supply_crates.size() == 1:
				var vehicle: Node3D = game.supply_crates[0]
				check(in_roster(vehicle) and vehicle.is_inside_tree() and vehicle.get_parent() == game and not bool(vehicle.opened) and String(vehicle.supply_kind) in Catalog.BUILDING_IDS and game._supply_crate_in_view(vehicle.position), context + ": the delivered vehicle must be a live visible entity with a real building type")
			check_delivery_observations(context)
			var supply_state: int = game.supply_rng.state
			check(not game.choose_card(0) and game.supply_crates.size() == 1 and game.supply_rng.state == supply_state, context + ": duplicate selection must not repeat the opening reward")
			if seed_value == 41 and mode == "teaching":
				game.run.grant("later-vehicle-draft-precision")
				game.open_draft()
				check(game.phase == "draft" and game.choose_card(0) and game.phase == "night" and game.supply_crates.size() == 1 and game.supply_rng.state == supply_state and game.scrap == balance, "Completing a later genuine card offer must not repeat the run's opening vehicle")
			await close_game()

func movement_and_payment() -> void:
	clear_vehicles()
	game.scrap = 600 # Explicit precision fixture, never a natural economy claim.
	stand(Vector3(0, 0, 8))
	var route: Array[Vector3] = movement_and_build_pair()
	check(route.size() == 2, "The vehicle must have a genuinely legal six-metre approach to a buildable barracks footprint")
	if route.size() != 2:return
	var vehicle: Node3D = fixture_vehicle("barracks", route[0])
	camera_at((route[0] + route[1]) * .5)
	await select_by_mouse(vehicle)
	await select_by_drag(vehicle)
	var original_hero: Vector3 = game.hero.position
	var original_wallet: int = game.scrap
	await click_world(route[1], MOUSE_BUTTON_RIGHT)
	check(not vehicle.path_points.is_empty(), "A real right-click must give the selected vehicle an actual navigation path")
	check(game.hero_path.is_empty() and game.hero.position == original_hero, "The selected vehicle movement command must leave the hero at its own position")
	var before_move: Vector3 = vehicle.position
	for _step in 300:
		game.advance_supply_crates(STEP)
		if planar(vehicle.position, route[1]) < .15:break
	check(planar(vehicle.position, before_move) > 5.5 and planar(vehicle.position, route[1]) < .3, "The vehicle must actually navigate to the commanded build location")
	check(game.scrap == original_wallet and not bool(vehicle.opened), "Moving a vehicle cannot charge construction or consume it")
	var plot_count: int = game.districts.plots.size()
	var expected: Vector3 = Grid.placement(vehicle.position, "barracks").point
	await capture_three_views(vehicle, "selected-mobile-barracks")
	await press(KEY_D)
	check(game.districts.plots.size() == plot_count + 1, "Real D input must deploy the vehicle into a new barracks")
	check(game.scrap == original_wallet - int(Catalog.building("barracks").cost), "Only successful deployment may charge the original barracks cost exactly once")
	check(not in_roster(vehicle) and not is_instance_valid(game.selected_construction_vehicle) and not game.construction.active, "A successful deployment must consume the vehicle and clear its selection and preview")
	var last: Dictionary = game.districts.plots.back()
	check(planar(last.position, expected) < .01 and String(last.kind) == "barracks", "Deployment must use the vehicle's snapped current footprint")
	var paid_wallet: int = game.scrap
	await press(KEY_D)
	check(game.scrap == paid_wallet and game.districts.plots.size() == plot_count + 1, "Repeated D input cannot charge or deploy an already consumed vehicle")

func cancelled_and_failed_deployment() -> void:
	clear_vehicles()
	game.scrap = 500
	var point: Vector3 = legal_point("tower")
	check(point.is_finite(), "A tower failure fixture needs an otherwise legal building position")
	if not point.is_finite():return
	var vehicle: Node3D = fixture_vehicle("tower", point)
	camera_at(point)
	await select_by_mouse(vehicle)
	game.scrap = 0
	await press(KEY_D)
	check(game.construction.active and game.deployment_vehicle == vehicle and in_roster(vehicle) and game.scrap == 0, "An unaffordable deployment must retain the vehicle and its bound grid preview without charging")
	await capture_three_views(vehicle, "unaffordable-tower-preview")
	await press(KEY_ESCAPE)
	check(not game.construction.active and in_roster(vehicle) and not bool(vehicle.opened) and game.scrap == 0, "Escape must cancel the preview while retaining the unpaid vehicle")
	await press(KEY_D)
	await click_world(point, MOUSE_BUTTON_RIGHT)
	check(not game.construction.active and in_roster(vehicle) and game.scrap == 0, "Right-click must cancel an unsuccessful deployment without losing its vehicle")
	game.scrap = 500
	await press(KEY_D)
	check(not in_roster(vehicle) and game.scrap < 500, "After restoring the budget, the same retained tower vehicle must deploy normally")

	clear_vehicles()
	var core_vehicle: Node3D = fixture_vehicle("barracks", Vector3.ZERO)
	camera_at(Vector3(0, Layout.FORT_HEIGHT, 0))
	await select_by_mouse(core_vehicle)
	var before_wallet: int = game.scrap
	var before_plots: int = game.districts.plots.size()
	await press(KEY_D)
	check(game.construction.active and in_roster(core_vehicle) and game.scrap == before_wallet, "An occupied core footprint must retain a failed deployment and its wallet")
	var remote_point: Vector3 = legal_point("barracks")
	check(remote_point.is_finite(), "The remote-preview counterexample needs a legal distant footprint")
	if remote_point.is_finite():
		check(not game.build_structure_at(remote_point, "barracks"), "A vehicle-bound preview cannot build directly at a different remote footprint")
		await click_world(remote_point)
		check(game.districts.plots.size() == before_plots and game.scrap == before_wallet and in_roster(core_vehicle), "Clicking a remote valid position cannot teleport a failed vehicle deployment")
		var quote: Dictionary = game.construction.snapshot()
		check(planar(quote.point, Grid.placement(core_vehicle.position, "barracks").point) < .01, "The bound preview must remain at the vehicle's current grid footprint")
	await press(KEY_ESCAPE)
	check(not game.construction.active and in_roster(core_vehicle), "Cancelling an occupied position preserves its vehicle")

func technology_and_identity() -> void:
	clear_vehicles()
	game.scrap = 600
	var workshop_point: Vector3 = legal_point("workshop")
	check(workshop_point.is_finite(), "Technology precision fixture requires a legal workshop point")
	if not workshop_point.is_finite():return
	# Paid low-level building fixture isolates loss of live technology from RNG.
	var before_workshop: int = game.scrap
	check(game.build_structure_at(workshop_point, "workshop"), "The workshop technology fixture must use the real paid building path")
	check(game.scrap == before_workshop - int(Catalog.building("workshop").cost), "The temporary technology fixture must pay its original construction cost")
	var workshop: Dictionary = game.districts.plots.back()
	var point: Vector3 = legal_point("recycler")
	check(point.is_finite(), "An eligible recycler vehicle must have an initially legal footprint")
	if not point.is_finite():return
	var vehicle: Node3D = fixture_vehicle("recycler", point)
	camera_at(point)
	await select_by_mouse(vehicle)
	var damage: Dictionary = game.districts.damage(int(workshop.index), float(workshop.hp) + 1.0)
	check(bool(damage.get("destroyed", false)) and not game.districts.has_live("workshop"), "Real building damage must remove the current workshop prerequisite")
	var balance: int = game.scrap
	await press(KEY_D)
	check(game.construction.active and in_roster(vehicle) and game.scrap == balance, "Losing live technology after vehicle delivery must block deployment without consuming the vehicle or fee")
	check(String(game.notice).contains("工坊"), "A failed deployment must disclose its actual missing technology")
	await press(KEY_ESCAPE)
	game.supply_crates.erase(vehicle)
	check(not game.select_construction_vehicle(vehicle) and not game.deploy_selected_vehicle() and game.scrap == balance, "A stale vehicle removed from the current roster cannot be selected or deployed")
	game.supply_crates.append(vehicle)
	game.select_construction_vehicle(vehicle)
	game.remove_child(vehicle)
	root.add_child(vehicle)
	check(not game.deploy_selected_vehicle() and game.scrap == balance, "A vehicle reparented outside its owning controller cannot deploy")
	root.remove_child(vehicle)
	game.add_child(vehicle)
	vehicle.open()
	check(not game.select_construction_vehicle(vehicle) and not game.deploy_selected_vehicle() and game.scrap == balance, "An opened or consumed vehicle identity cannot deploy again")
	clear_vehicles()

func failed_preview_maintenance_input() -> void:
	clear_vehicles()
	game.scrap = 600
	stand(Vector3(0, 0, 8))
	var tower_point: Vector3 = legal_point("tower")
	check(tower_point.is_finite(), "Vehicle-preview maintenance needs a separate legal paid tower")
	if not tower_point.is_finite():return
	var build_quote: Dictionary = game.construction.validity(tower_point, -1, "tower")
	var build_balance: int = game.scrap
	check(game.build_structure_at(tower_point, "tower") and game.scrap == build_balance - int(build_quote.cost), "The remote maintenance fixture must construct its tower through the real paid path")
	var tower_index := -1
	for index in game.world.tower_pads.size():
		var candidate: Dictionary = game.world.tower_pads[index]
		if int(candidate.level) > 0 and not bool(candidate.get("removed", false)) and planar(candidate.position, tower_point) < .01:
			tower_index = index
			break
	check(tower_index >= 0, "The actual paid tower must have a live maintenance identity")
	if tower_index < 0:return
	var pad: Dictionary = game.world.tower_pads[tower_index]
	game.damage_tower(tower_index, 50.0)
	var damaged_hp: float = pad.hp
	check(damaged_hp > 0.0 and damaged_hp < float(pad.max_hp), "Real tower damage must create a repairable target away from the vehicle")
	var vehicle: Node3D = fixture_vehicle("barracks", Vector3.ZERO)
	camera_at(vehicle.position)
	await select_by_mouse(vehicle)
	var balance: int = game.scrap
	var plot_count: int = game.districts.plots.size()
	await press(KEY_D)
	check(game.construction.active and is_same(game.deployment_vehicle, vehicle) and in_roster(vehicle) and game.scrap == balance, "Core occupancy must leave the vehicle's unsuccessful deployment preview active before maintenance")
	await press(KEY_H)
	check(game.construction.repair_mode and not game.construction.sell_mode, "Real H input must switch the failed vehicle preview to repair mode")
	camera_at(tower_point)
	await aim_world(tower_point)
	var repair_quote: Dictionary = game.construction.snapshot()
	check(bool(repair_quote.valid) and String(repair_quote.get("target_type", "")) == "tower" and int(repair_quote.get("target_index", -1)) == tower_index and planar(repair_quote.point, tower_point) < .01, "The actual repair HUD quote must follow the mouse tower instead of the bound vehicle footprint")
	check(planar(game.aim, tower_point) < .1 and planar(game.aim, vehicle.position) > 8.0, "The real queued mouse sample must resolve away from the vehicle while maintenance is active")
	await capture("failed-vehicle-preview-mouse-tower-repair")
	await press(KEY_F)
	var repair_orders: Array = game.repairs.snapshot().targets
	check(repair_orders.size() == 1 and int(repair_orders[0].target_index) == tower_index and game.scrap == balance, "Real F confirmation must enable the pointed tower's repair order without an immediate fee")
	game.repairs.tick(1.0)
	check(is_equal_approx(float(pad.hp), damaged_hp + 25.0) and game.scrap == balance - int(repair_quote.cost), "The actual one-second repair event must restore the pointed tower and charge its original resource price")
	check(in_roster(vehicle) and not bool(vehicle.opened) and is_same(game.deployment_vehicle, vehicle) and game.districts.plots.size() == plot_count, "A paid repair must keep the failed deployment vehicle and must not construct its barracks")
	await press(KEY_ESCAPE)
	check(not game.construction.active and in_roster(vehicle) and not bool(vehicle.opened), "Leaving the repair tool must preserve the still-undeployed vehicle")

	camera_at(vehicle.position)
	await select_by_mouse(vehicle)
	balance = game.scrap
	await press(KEY_D)
	check(game.construction.active and is_same(game.deployment_vehicle, vehicle) and game.scrap == balance, "The same core-blocked vehicle must enter a second failed preview before demolition")
	await press(KEY_DELETE)
	check(game.construction.sell_mode and not game.construction.repair_mode, "Real Delete input must switch that failed preview to demolition mode")
	camera_at(tower_point)
	await aim_world(tower_point)
	var sell_quote: Dictionary = game.construction.snapshot()
	check(bool(sell_quote.valid) and String(sell_quote.get("target_type", "")) == "tower" and int(sell_quote.get("target_index", -1)) == tower_index and planar(sell_quote.point, tower_point) < .01, "The actual demolition HUD quote must identify the remote paid tower under the mouse")
	check(int(sell_quote.get("refund", 0)) > 0 and int(sell_quote.get("investment", 0)) == int(pad.paid_investment), "The pointed paid tower must retain its real capital and positive demolition refund")
	await capture("failed-vehicle-preview-mouse-tower-demolition")
	# Move the sampled aim back to the vehicle first. The actual left-click must
	# resample its own tower position and cannot rely on the prior HUD quote.
	await aim_world(vehicle.position)
	await click_world(tower_point)
	check(bool(pad.get("removed", false)) and game.scrap == balance + int(sell_quote.get("refund", 0)) + int(sell_quote.get("queue_refund", 0)), "A real tower click must retire that identity and pay its exact quoted refund despite the bound vehicle")
	check(game.repairs.snapshot().targets.is_empty() and in_roster(vehicle) and not bool(vehicle.opened) and game.districts.plots.size() == plot_count, "Demolition must retire the tower repair order while retaining the vehicle and every unrelated building")
	var refunded_balance: int = game.scrap
	await click_world(tower_point)
	check(game.scrap == refunded_balance and in_roster(vehicle), "Repeated real clicks cannot refund an already sold tower or consume the construction vehicle")
	await press(KEY_ESCAPE)
	clear_vehicles()

func retired_preview_and_vehicle_clearance() -> void:
	clear_vehicles()
	game.scrap = 600
	var vehicle: Node3D = fixture_vehicle("barracks", Vector3.ZERO)
	camera_at(Vector3(0, Layout.FORT_HEIGHT, 0))
	await select_by_mouse(vehicle)
	await press(KEY_D)
	check(game.construction.active and int(game.deployment_vehicle_id) == vehicle.get_instance_id(), "A failed deployment must bind the preview to the original vehicle identity")
	var distant_point: Vector3 = legal_point("barracks")
	check(distant_point.is_finite(), "A retired-vehicle preview fixture needs an otherwise legal distant point")
	var balance: int = game.scrap
	var plots_before: int = game.districts.plots.size()
	var bound_id: int = vehicle.get_instance_id()
	vehicle.queue_free()
	await process_frame
	check(not is_instance_valid(vehicle) and int(game.deployment_vehicle_id) == bound_id, "The vehicle must actually be freed while its stale preview identity is still present")
	if distant_point.is_finite():
		check(not game.build_structure_at(distant_point, "barracks"), "A freed deployment vehicle cannot fall back to a remotely placeable ordinary permit")
	game.aim = distant_point
	check(not game.construction.confirm() and game.scrap == balance and game.districts.plots.size() == plots_before, "Confirming a stale bound preview must reject construction without consuming a fee")
	game.advance_supply_crates(.01)
	check(not game.construction.active and int(game.deployment_vehicle_id) == 0 and game.pending_build_permit_kind.is_empty() and not is_instance_valid(game.selected_construction_vehicle), "The next controller advance must retire the stale preview, identity and selection")

	clear_vehicles()
	var point: Vector3 = legal_point("barracks")
	check(point.is_finite(), "The full-body vehicle collision fixture needs an initially legal building footprint")
	if not point.is_finite():return
	var footprint: Dictionary = Grid.placement(point, "barracks")
	var bounds: Rect2 = footprint.rect
	var neighbor_point := Vector3(bounds.end.x + .7, point.y, bounds.get_center().y)
	var primary: Node3D = fixture_vehicle("barracks", point)
	var neighbor: Node3D = fixture_vehicle("tower", neighbor_point)
	check(not bounds.has_point(Vector2(neighbor.position.x, neighbor.position.z)) and neighbor.position.x - bounds.end.x > .25 and neighbor.position.x - bounds.end.x < float(neighbor.BODY_CLEARANCE), "The neighboring vehicle fixture must overlap by its full body while its center remains outside the legacy quarter-metre radius")
	camera_at(point)
	await select_by_mouse(primary)
	balance = game.scrap
	plots_before = game.districts.plots.size()
	await press(KEY_D)
	var quote: Dictionary = game.construction.snapshot()
	check(not bool(quote.space_valid) and game.construction.active and in_roster(primary) and in_roster(neighbor), "Another construction vehicle's complete body must block a neighboring building footprint")
	check(game.scrap == balance and game.districts.plots.size() == plots_before, "A full-body vehicle collision must not charge resources or create a building")
	await capture("adjacent-vehicle-full-body-rejection")
	await press(KEY_ESCAPE)
	game.supply_crates.erase(neighbor)
	neighbor.queue_free()
	await process_frame
	check(game.deploy_selected_vehicle() and game.scrap == balance - int(Catalog.building("barracks").cost), "Once the conflicting vehicle is removed, the original retained vehicle may deploy with one real fee")
	clear_vehicles()

func expanded_enemy_spawn_positions() -> void:
	# Twenty original factory births check expansion geometry. Actors are
	# retired directly after inspection; no kills or free rewards are awarded.
	var phase_before: String = game.phase
	var random_state_before: int = game.spawn_rng.state
	var wallet_before: int = game.scrap
	var kills_before: int = game.kills
	for night: bool in [false, true]:
		game.phase = "night" if night else "day"
		for seed_value: int in [1, 7, 17, 41, 113, 999, 20261009, 214748364, 987654, 8061]:
			game.spawn_rng.seed = seed_value
			var creature: BattleUnit = game.spawn_creature(night, "basic", false)
			var point: Vector3 = creature.position
			var context: String = "%s seed %d" % ["night" if night else "day", seed_value]
			check(point.is_finite() and game.outpost_walkable(point) and absf(point.x) < Layout.MAP_HALF_X and absf(point.z) < Layout.MAP_HALF_Z, context + ": a real enemy factory birth must stand on legal map ground")
			check(not Layout.contains_castle(point) and not Layout.satellite_contains(point), context + ": an enemy birth cannot appear inside the expanded main or satellite castles")
			var clear_of_geometry: bool = true
			for blocks: Array in [game.WALK_BLOCKS, game.TERRAIN_BLOCKS, game.construction_blocks]:
				for block: Rect2 in blocks:
					if block.grow(.45).has_point(Vector2(point.x, point.z)):clear_of_geometry = false
			check(clear_of_geometry, context + ": an enemy birth must clear the wall, mountain, water and building boundaries")
			if night:check(point.z >= Layout.RAMP_END + 8.5, context + ": night attackers must begin beyond the enlarged south ramp")
			game.enemies.erase(creature)
			creature.queue_free()
	var resolve_state: int = game.spawn_rng.state
	var wall_point := Vector3(-Layout.WALL_CENTER, 0, 0)
	var resolved: Vector3 = game._resolve_enemy_spawn_point(wall_point)
	check(game.outpost_walkable(resolved) and not Layout.contains_castle(resolved), "A position in an expanded wall must resolve to genuine outside ground")
	check(game.spawn_rng.state == resolve_state, "Deterministic outward position repair cannot consume additional hostile RNG values")
	game.phase = phase_before
	game.spawn_rng.state = random_state_before
	check(game.scrap == wallet_before and game.kills == kills_before, "The inspected spawn actors must retire without awarding free kills or resources")
	await process_frame

func main_gate_to_satellite_route() -> void:
	clear_vehicles()
	game.scrap = 600 # Route precision fixture; movement and deployment stay real.
	stand(Vector3(0, 0, 8))
	var south_castle: Dictionary = Layout.SATELLITE_CASTLES[2]
	var destination_quote: Dictionary = game.construction.validity(ground(south_castle.position), -1, "barracks")
	var destination: Vector3 = destination_quote.point
	var source: Vector3 = ground(Vector3(0, 0, Layout.RAMP_TOP - 2.0))
	check(bool(destination_quote.valid), "The south-castle route must end at a currently legal snapped barracks footprint")
	var vehicle: Node3D = fixture_vehicle("barracks", source)
	camera_at(source)
	await select_by_mouse(vehicle)
	# A camera pan fixture lets a real world click target the distant castle;
	# it never teleports the vehicle or creates navigation points itself.
	camera_at(destination)
	await click_world(destination, MOUSE_BUTTON_RIGHT)
	check(not vehicle.path_points.is_empty(), "A distant satellite order must create a real navigation route through the main gate and the satellite opening")
	var reached_outer_ground: bool = false
	var entered_satellite: bool = false
	var moving_elapsed: float = 0.0
	for _step in 3600:
		game.advance_supply_crates(STEP)
		moving_elapsed += STEP
		if vehicle.position.z > Layout.RAMP_END and vehicle.position.y < .2:reached_outer_ground = true
		if Layout.satellite_contains(vehicle.position, -2.0):entered_satellite = true
		if vehicle.path_points.is_empty() and planar(vehicle.position, destination) < .02:break
	check(reached_outer_ground, "The vehicle must actually leave the main castle via its height-transition ramp")
	check(entered_satellite and planar(vehicle.position, source) > 80.0 and vehicle.path_points.is_empty() and planar(vehicle.position, destination) < .02, "The original vehicle must finish its real route at the legal satellite destination rather than deploy from a remote fixture")
	var expected_footprint: Vector3 = Grid.placement(vehicle.position, "barracks").point
	var balance: int = game.scrap
	await press(KEY_D)
	check(not in_roster(vehicle) and game.scrap == balance - int(Catalog.building("barracks").cost), "Only after arriving may the driven satellite vehicle deploy and pay its fee")
	var built: Dictionary = game.districts.plots.back()
	check(planar(built.position, expected_footprint) < .01 and planar(built.position, destination) < .01, "The driven vehicle must deploy at its own snapped destination footprint")
	print("CONSTRUCTION_VEHICLE_ROUTE elapsed=%.3f outer_ground=%s entered_satellite=%s" % [moving_elapsed, reached_outer_ground, entered_satellite])
	await capture("driven-south-satellite-deployed")

func map_and_satellite_deployment() -> void:
	check(Grid.CASTLE_CELLS.size == Vector2i(44, 44), "The expanded main castle must expose a forty-four by forty-four build grid")
	check(Layout.MAP_HALF_X >= 190.0 and Layout.MAP_HALF_Z >= 160.0, "The expanded world must contain at least the requested wider play envelope")
	check(Layout.SATELLITE_CASTLES.size() == 3 and Grid.build_regions().size() == 4, "Three real satellite castle areas must join the main grid's build regions")
	clear_vehicles()
	game.scrap = 1000
	for castle: Dictionary in Layout.SATELLITE_CASTLES:
		var center: Vector3 = castle.position
		var point: Vector3 = legal_point("barracks", center, 10)
		check(point.is_finite(), "%s must contain an actual legal flat building footprint" % String(castle.name))
		if not point.is_finite():continue
		check(absf(point.y) < .05 and bool(Grid.placement(point, "barracks").inside), "Satellite deployment must use its flat terrain and existing building occupancy grid")
		var vehicle: Node3D = fixture_vehicle("barracks", point)
		camera_at(point)
		await select_by_mouse(vehicle)
		var before: int = game.scrap
		await press(KEY_D)
		check(not in_roster(vehicle) and game.scrap == before - int(Catalog.building("barracks").cost), "A satellite barracks vehicle must deploy and charge the same real building fee")
		var built: Dictionary = game.districts.plots.back()
		check(planar(built.position, point) < .01, "Satellite deployment cannot be moved back into the main castle")
		await capture("satellite-%s-deployed" % String(castle.name))
	var wilderness: Vector3 = ground(Vector3(45, 0, 50))
	check(not bool(game.construction.validity(wilderness, -1, "barracks").space_valid), "Open wilderness outside all castles cannot bypass the existing legal build-region restrictions")

func lifecycle_and_no_pickup() -> void:
	clear_vehicles()
	game.scrap = 0
	var vehicle: Node3D = fixture_vehicle("barracks", Vector3(10, 0, 10))
	stand(vehicle.position)
	var wallet: int = game.scrap
	game.advance_supply_crates(.1)
	game._try_open_supply_crates()
	check(in_roster(vehicle) and not bool(vehicle.opened) and not game.construction.active and game.pending_build_permit_kind.is_empty() and game.scrap == wallet, "Actual hero contact must not consume a construction vehicle, award a licence or open a preview")
	stand(Vector3(0, 0, 8))
	camera_at(vehicle.position)
	await select_by_mouse(vehicle)
	await click_world(vehicle.position + Vector3(5, 0, 0), MOUSE_BUTTON_RIGHT)
	var position_before: Vector3 = vehicle.position
	var path_before: Array[Vector3] = vehicle.path_points.duplicate()
	var pulse_before: float = vehicle.pulse_time
	var clock_before: float = game.supply_crate_clock
	game.phase = "paused"
	game.advance_supply_crates(10.0)
	await press(KEY_D)
	check(vehicle.position == position_before and vehicle.path_points == path_before and is_equal_approx(vehicle.pulse_time, pulse_before) and is_equal_approx(game.supply_crate_clock, clock_before), "Pause must freeze the selected vehicle's movement, visual pulse and delivery clock")
	check(in_roster(vehicle) and game.scrap == wallet and not game.construction.active, "Paused D input cannot deploy or consume a vehicle")
	game.phase = "day"
	await press(KEY_D)
	check(game.construction.active and in_roster(vehicle), "A failed live deployment must expose a preview before transition checks")
	game.start_night()
	check(game.phase == "night" and game.supply_crates.size() == 1 and in_roster(vehicle) and not game.construction.active and not bool(vehicle.opened) and game.supply_crate_clock == 0.0, "Day-to-night transition must retain exactly the actual vehicle without another opening delivery while cancelling its deployment preview")
	game.begin_day()
	check(game.phase == "day" and game.supply_crates.size() == 1 and in_roster(vehicle) and not bool(vehicle.opened) and game.supply_crate_clock == 0.0, "Night-to-day transition must retain exactly the same undeployed vehicle without another opening delivery")
	game.end_defeat("Construction vehicle regression defeat")
	check(game.phase == "ended" and not game.victory and game.supply_crates.is_empty() and not is_instance_valid(game.selected_construction_vehicle) and not is_instance_valid(game.deployment_vehicle), "The real failure path must clear vehicles, selection and bound deployment")
	game.advance_supply_crates(100.0)
	check(game.supply_crates.is_empty(), "An ended run cannot spawn more vehicles")

func actual_retry_and_victory() -> void:
	var old_id: int = game.get_instance_id()
	var old_seed: int = game.run.seed_value
	await press(KEY_ENTER)
	for _frame in 300:
		if is_instance_valid(current_scene) and current_scene.get_instance_id() != old_id:break
		await create_timer(.01).timeout
	check(is_instance_valid(current_scene) and current_scene.get_instance_id() != old_id, "Real Enter input must reload a fresh controller for a same-seed retry")
	if not is_instance_valid(current_scene) or current_scene.get_instance_id() == old_id:return
	game = current_scene as Node3D
	game.archive.enabled = false
	game.set_process(false)
	check(game.phase == "draft" and game.run.seed_value == old_seed and game.supply_crates.is_empty() and not is_instance_valid(game.selected_construction_vehicle) and not is_instance_valid(game.deployment_vehicle), "A real retry must preserve the seed while recreating an empty vehicle roster")
	var retry_wallet: int = game.scrap
	await press(KEY_1)
	check(game.phase == "night" and game.supply_crates.size() == 1 and is_equal_approx(game.supply_crate_clock, 0.0) and game.scrap == retry_wallet, "The real same-seed reload must deliver a new opening vehicle immediately after real card-key selection")
	if game.supply_crates.size() == 1:
		var retry_vehicle: Node3D = game.supply_crates[0]
		check(in_roster(retry_vehicle) and retry_vehicle.get_parent() == game and not bool(retry_vehicle.opened) and String(retry_vehicle.supply_kind) == opening_vehicle_kind, "A same-seed retry must create a fresh live opening vehicle with the original deterministic building reward")
	check(not game.choose_card(0) and game.supply_crates.size() == 1, "A repeated choice after the real retry cannot repeat its immediate delivery")
	isolate()
	fixture_vehicle("tower", Vector3(10, 0, 10))
	game.phase = "night"
	game.phase_time = 0.0
	game.wave_index = game.WAVES_PER_NIGHT
	game.day_number = game.max_nights()
	game.night_clearance_active = true
	game.final_clearance_active = true
	game.finish_night()
	check(game.phase == "ended" and game.victory and game.supply_crates.is_empty() and not is_instance_valid(game.selected_construction_vehicle) and not is_instance_valid(game.deployment_vehicle), "A separate real final-clearance victory must clear the remaining vehicle roster")

func run() -> void:
	check(Session.queue_request(self, 20261009, "teaching"), "Create a fixed original opening seed for the vehicle observation")
	await new_game()
	await real_opening()
	var opening_vehicle_count: int = game.supply_crates.size()
	game.begin_day()
	check(game.supply_crates.size() == opening_vehicle_count and is_equal_approx(game.supply_crate_clock, 0.0), "An ordinary dawn must preserve both actual vehicles without another opening reward")
	game.world._process(game.world.LIGHT_TRANSITION_SECONDS)
	for lamp: OmniLight3D in game.world.courtyard_lamps:
		check(is_equal_approx(lamp.light_energy, game.world.COURTYARD_LAMP_DAY_ENERGY), "Actual dawn must fade the courtyard lamps to their authored daylight energy")
	isolate()
	var y_balance: int = game.scrap
	await press(KEY_Y)
	check(not game.construction.active and game.scrap == y_balance, "Y without a selected vehicle cannot open a building catalogue")
	clear_vehicles()
	var periodic_wallet: int = game.scrap
	var periodic_hostile_state: int = game.spawn_rng.state
	game.advance_supply_crates(25.0 * 8.0)
	check(game.supply_crates.size() <= 3 and game.supply_crates.size() > 0, "Repeated delivery intervals must keep at most three real vehicles")
	game.advance_supply_crates(25.0 * 8.0)
	check(game.supply_crates.size() <= 3 and game.scrap == periodic_wallet and game.spawn_rng.state == periodic_hostile_state, "Further periodic deliveries must retain the three-vehicle cap, original wallet and independent enemy random stream")
	for vehicle: Node3D in game.supply_crates:
		check(String(vehicle.supply_kind) in Catalog.BUILDING_IDS and not bool(vehicle.opened), "All queued world deliveries must remain undeployed building vehicles")
	await movement_and_payment()
	await cancelled_and_failed_deployment()
	await technology_and_identity()
	await failed_preview_maintenance_input()
	await retired_preview_and_vehicle_clearance()
	await main_gate_to_satellite_route()
	await map_and_satellite_deployment()
	await expanded_enemy_spawn_positions()
	await lifecycle_and_no_pickup()
	await actual_retry_and_victory()
	await close_game()
	await blocked_opening_retry()
	await parameterized_opening_deliveries()
	if failures.is_empty():
		print("NIGHTFALL_CONSTRUCTION_VEHICLES_OK checks=%d failures=0" % checks)
	else:
		push_error("NIGHTFALL_CONSTRUCTION_VEHICLES_FAILED checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
