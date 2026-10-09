extends SceneTree

## Controller precision regression using isolated, fixed-position fixtures.
## Movement, paid placement and completed training call their production paths;
## these cases do not claim a natural economy or full-run balance result.
const Grid := preload("res://scripts/construction_grid.gd")
const Catalog := preload("res://scripts/outpost_catalog.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
const CrateScript := preload("res://scripts/outpost_supply_crate.gd")
const STEP := 1.0 / 30.0
var game: Node3D
var checks := 0
var failures: Array[String] = []
var render_test := false

func _initialize() -> void:
	render_test = "--render-test" in OS.get_cmdline_user_args()
	root.size = Vector2i(1920, 1200)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1920, 1200)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:return
	failures.append(message)
	if failures.size() <= 25:push_error(message)

func ground(point: Vector3) -> Vector3:
	point.y = game.outpost_height(point)
	return point

func stand(point: Vector3) -> void:
	game.hero.position = ground(point)
	game.move_goal = game.hero.position
	game.hero_path.clear()
	game.hero_keyboard_active = false

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	game._unhandled_input(event)

func isolate() -> void:
	game.set_process(false)
	game.phase_time = 10000.0
	for enemy: BattleUnit in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()
	game.contracts.status = "idle"
	for item: Dictionary in game.discoveries.items:
		game.discoveries.begin_cooling(item, 9999.0)
	for cache: Dictionary in game.world.salvage:
		cache.collected = true
		cache.respawn = 9999.0
	for generator: Dictionary in game.expeditions.generators:generator.state = "complete"
	for camp: Dictionary in game.expeditions.camps:camp.state = "delivered"
	for nest: Dictionary in game.world.nests:nest.cleansed = true
	for relay: Dictionary in game.world.relays:relay.activated = true
	for pad: Dictionary in game.world.tower_pads:pad.cooldown = 9999.0

func reset_supply() -> void:
	game.clear_supply_crates(true)
	game.construction.cancel()
	# Retire accepted random pickup orders using the real cancellation/refund path.
	for id: int in game.squads.training_queues.keys():
		while not game.squads.training_queues[id].is_empty():
			if not bool(game.squads.cancel_training(id).ok):break

func fixture_crate(point: Vector3) -> Node3D:
	var crate := CrateScript.new() as Node3D
	crate.setup(game.supply_crate_serial)
	game.supply_crate_serial += 1
	crate.position = ground(point)
	game.add_child(crate)
	game.supply_crates.append(crate)
	return crate

func pending_orders() -> int:
	var result := 0 if String(game.pending_training_order_kind).is_empty() else 1
	for reward: Dictionary in game.supply_reward_queue:
		if String(reward.get("type", "")) == "training_order":result += 1
	return result

func reward_count() -> int:
	return game.supply_reward_queue.size() + (0 if String(game.pending_build_permit_kind).is_empty() else 1) + (0 if String(game.pending_training_order_kind).is_empty() else 1)

func queue_count() -> int:
	var result := 0
	for queue: Array in game.squads.training_queues.values():result += queue.size()
	return result

func first_queue_remaining() -> float:
	for queue: Array in game.squads.training_queues.values():
		if not queue.is_empty():return float(queue[0].remaining)
	return -1.0

func legal_build_point(kind: String) -> Vector3:
	for z in range(-11, 12):
		for x in range(-11, 12):
			var placement: Dictionary = game.construction.validity(ground(Vector3(x, 0, z)), -1, kind)
			if bool(placement.valid):return placement.point
	return Vector3.INF

func deploy_permit(kind: String) -> bool:
	game._apply_supply_reward({"type":"building_permit", "kind":kind, "title":String(Catalog.building(kind).title)})
	game.aim = legal_build_point(kind)
	if not game.aim.is_finite():return false
	return bool(game.construction.confirm())

func current_member(kind: String) -> BattleUnit:
	for squad: Dictionary in game.squads.squads:
		if String(squad.kind) != kind:continue
		for member: BattleUnit in squad.members:
			if is_instance_valid(member) and member.alive:return member
	return null

func assert_not_opened(crate: Node3D, message: String) -> void:
	game._try_open_supply_crates()
	check(game.supply_crates.has(crate) and not bool(crate.opened), message)

func pickup_route() -> Array[Vector3]:
	# Prefer a fixed flat wilderness approach, clear of authored castle props.
	# Require the exact production segment before creating the pickup fixture.
	for z: float in [30.0, 40.0, 50.0]:
		for x: float in [45.0, 55.0, 65.0]:
			var start := ground(Vector3(x, 0, z))
			var end := ground(Vector3(x + 4.0, 0, z))
			if game.outpost_walkable(start) and game.can_traverse(start, end) and absf(start.y - end.y) < .15:
				return [start, end]
	return []

func open_with_movement(member: BattleUnit, kind: String) -> void:
	reset_supply()
	var route: Array[Vector3] = pickup_route()
	check(route.size() == 2, "%s requires a legal four-metre flat pickup approach" % kind)
	if route.size() != 2:return
	stand(route[0] + Vector3(-5, 0, -5))
	for squad: Dictionary in game.squads.squads:
		for other: BattleUnit in squad.members:
			if is_instance_valid(other):other.position = ground(route[0] + Vector3(-5, 0, -5))
	member.position = route[0]
	var start := member.position
	var crate := fixture_crate(route[1])
	check(game.can_traverse(start, crate.position), "%s pickup fixture must have a real traversable approach" % kind)
	game._try_open_supply_crates()
	check(game.supply_crates.has(crate), "%s cannot open a crate before reaching it" % kind)
	for _step in 120:
		game.squads._move_member(member, crate.position, STEP)
		game._try_open_supply_crates()
		if game.supply_crates.is_empty():break
	check(member.position.distance_to(start) > 1.0, "%s must actually move before touching the crate" % kind)
	check(game.supply_crates.is_empty() and bool(crate.opened), "%s automatically opens the crate by movement without a key or click" % kind)
	var rewards := reward_count()
	game._try_open_supply_crates()
	check(reward_count() == rewards, "%s pickup must award only once" % kind)

func capture(label: String, focus: Vector3 = Vector3.INF) -> void:
	if not render_test or DisplayServer.get_name() == "headless":return
	# The gameplay fixture is manually stepped. Finish the normal visual fade
	# to its current phase before judging box visibility or Chinese UI text.
	game.world._process(game.world.LIGHT_TRANSITION_SECONDS)
	var previous_transform: Transform3D = game.camera.transform
	var previous_size: float = game.camera.size
	var previous_follow: Vector3 = game.camera_follow
	if focus.is_finite():
		game.camera.size = 17.0
		game.camera.position = focus + Vector3(0, 25, 29)
		game.camera.look_at(focus)
		game.camera_follow = game.camera.position
	game.hud.queue_redraw()
	for _frame in 6:
		await process_frame
		await RenderingServer.frame_post_draw
	var output_dir := "res://build/supply-crates-render"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)) == OK, "Create the local supply rendering evidence directory")
	var picture: Image = root.get_texture().get_image()
	check(picture.get_size() == Vector2i(1920, 1200), "Supply rendering must use the requested full-size viewport")
	var output := output_dir + "/" + label + ".png"
	check(picture.save_png(output) == OK, "Save actual supply crate frame " + label)
	print("SUPPLY_CRATE_FRAME ", ProjectSettings.globalize_path(output))
	game.camera.transform = previous_transform
	game.camera.size = previous_size
	game.camera_follow = previous_follow

func assert_visible_nearby(crate: Node3D, context: String) -> void:
	var planar_distance: float = Vector2(crate.position.x - game.hero.position.x, crate.position.z - game.hero.position.z).length()
	check(planar_distance >= 6.0 - .001 and planar_distance <= 12.0 + .001, context + ": crate must spawn six to twelve metres from the hero")
	check(game.can_traverse(game.hero.position, crate.position), context + ": the nearby crate must have a direct traversable approach")
	var marker_point: Vector3 = game.to_global(crate.position + Vector3.UP * 1.4)
	var viewport_size: Vector2 = game.get_viewport().get_visible_rect().size
	var projected_point: Vector2 = game.camera.unproject_position(marker_point)
	var safe_rect := Rect2(viewport_size * Vector2(.12, .14), viewport_size * Vector2(.76, .60))
	check(not game.camera.is_position_behind(marker_point) and safe_rect.has_point(projected_point), context + ": the default camera must show the marker above the bottom HUD")
	check(game._supply_crate_in_view(crate.position), context + ": the production visibility gate must agree with the rendered projection")
	var start_cell: Vector2i = game.nearest_navigation_cell(game.hero.position, true)
	game.supply_crates.erase(crate)
	check(game._supply_crate_position_legal(crate.position, start_cell), context + ": full crate footprint must remain legal")
	game.supply_crates.append(crate)
	var pending_before: int = reward_count()
	game.advance_supply_crates(0.0)
	check(game.supply_crates.has(crate) and not bool(crate.opened) and reward_count() == pending_before, context + ": a newly spawned crate cannot instantly open under the hero")

func settle_follow_camera() -> void:
	# Call the actual production follow update while paused, so settling the
	# camera does not alter game time, crate clocks or the fixture economy.
	var prior_phase: String = game.phase
	game.phase = "paused"
	for _frame in 30:game._process(.1)
	game.phase = prior_phase
	check(game.camera.position.distance_to(game.hero.position + Vector3(0, 25, 29)) < .02, "Production camera following must settle on the relocated hero")

func nearby_visibility_cases() -> void:
	var hero_before: Vector3 = game.hero.position
	var camera_before: Transform3D = game.camera.transform
	var size_before: float = game.camera.size
	var follow_before: Vector3 = game.camera_follow
	var phase_time_before: float = game.phase_time
	for at_perimeter: bool in [false, true]:
		if at_perimeter:
			# Position an isolated fixture near the outer boundary, then walk
			# four metres through production movement before testing camera follow.
			stand(Vector3(126, 0, 110))
			var move_start: Vector3 = game.hero.position
			var destination: Vector3 = ground(Vector3(130, 0, 110))
			game.plan_hero_path(destination)
			check(not game.hero_path.is_empty(), "The perimeter visibility fixture must have a real four-metre movement path")
			for _step in 120:
				game.move_hero(STEP)
				if game.hero.position.distance_to(destination) < .2:break
			check(game.hero.position.distance_to(move_start) > 3.5, "The hero must actually move on the perimeter before its camera is followed")
		else:stand(hero_before)
		settle_follow_camera()
		for camera_size: float in [38.0, 21.0]:
			game.camera.size = camera_size
			for seed_value: int in [1, 17, 20261009]:
				reset_supply()
				game.supply_rng.seed = seed_value
				var hostile_state: int = game.spawn_rng.state
				game.advance_supply_crates(25.0)
				var context: String = "%s zoom %.0f seed %d" % ["perimeter" if at_perimeter else "castle", camera_size, seed_value]
				check(game.supply_crates.size() == 1, context + ": one due crate must appear in the nearby visible ground")
				check(game.spawn_rng.state == hostile_state, context + ": visibility retries cannot affect hostile spawning")
				if game.supply_crates.size() == 1:
					var crate: Node3D = game.supply_crates[0]
					assert_visible_nearby(crate, context)
					if seed_value == 20261009:
						await capture("visible-%s-zoom-%d-default-camera" % ["perimeter" if at_perimeter else "castle", int(camera_size)])
	reset_supply()
	stand(hero_before)
	game.camera.transform = camera_before
	game.camera.size = size_before
	game.camera_follow = follow_before
	game.phase_time = phase_time_before

func blocked_delivery_retry() -> void:
	reset_supply()
	var old_blocks: Array[Rect2] = game.construction_blocks.duplicate()
	var everywhere: Array[Rect2] = [Rect2(Vector2(-Layout.MAP_HALF_X - 1.0, -Layout.MAP_HALF_Z - 1.0), Vector2(Layout.MAP_HALF_X * 2.0 + 2.0, Layout.MAP_HALF_Z * 2.0 + 2.0))]
	game.construction_blocks = everywhere
	game.advance_supply_crates(25.0)
	check(game.supply_crates.is_empty(), "No legal nearby ground must defer delivery rather than spawn a crate elsewhere on the map")
	check(is_equal_approx(game.supply_crate_clock, 25.0) and is_equal_approx(game.supply_crate_retry, 1.0), "A blocked due delivery must retain its twenty-five-second clock and schedule a one-second retry")
	var rng_after_failure: int = game.supply_rng.state
	game.advance_supply_crates(.49)
	game.advance_supply_crates(.49)
	check(game.supply_rng.state == rng_after_failure and game.supply_crates.is_empty(), "Before the one-second retry delay expires, no position search may consume random values")
	var paused_retry: float = game.supply_crate_retry
	var paused_clock: float = game.supply_crate_clock
	game.phase = "paused"
	game.advance_supply_crates(10.0)
	check(is_equal_approx(game.supply_crate_retry, paused_retry) and is_equal_approx(game.supply_crate_clock, paused_clock) and game.supply_rng.state == rng_after_failure, "Pause must freeze the deferred-delivery retry and random stream")
	game.phase = "day"
	game.construction_blocks = old_blocks
	game.advance_supply_crates(.01)
	check(game.supply_crates.is_empty() and game.supply_rng.state == rng_after_failure, "Released terrain must still respect the remainder of the original one-second retry")
	game.advance_supply_crates(.02)
	check(game.supply_crates.size() == 1 and game.supply_crate_retry == 0.0 and game.supply_crate_clock < 2.0, "When legal ground returns, the due crate must appear at the one-second retry without waiting another twenty-five seconds")
	if game.supply_crates.size() == 1:assert_visible_nearby(game.supply_crates[0], "released deferred delivery")
	reset_supply()
	game.supply_crate_clock = 25.0
	game.supply_crate_retry = .8
	game.begin_day()
	check(game.supply_crate_clock == 0.0 and game.supply_crate_retry == 0.0 and game.supply_crates.is_empty(), "A real phase transition must clear both spawn timing and the pending retry")
	game.phase_time = 10000.0

func navigation_marker_cases() -> void:
	reset_supply()
	var hero_before: Vector3 = game.hero.position
	stand(Vector3(45, 0, 30))
	var east_crate: Node3D = fixture_crate(game.hero.position + Vector3(7, 0, 0))
	var north_crate: Node3D = fixture_crate(game.hero.position + Vector3(0, 0, -10))
	var navigation: Dictionary = game.hud.supply_crate_navigation_snapshot()
	check(int(navigation.get("count", -1)) == 2 and navigation.get("positions", []).size() == 2, "The real navigation snapshot must expose both live map crates as marker positions")
	check(navigation.get("nearest_position", Vector3.INF) == east_crate.global_position and String(navigation.get("direction", "")) == "东" and int(navigation.get("distance_meters", -1)) == 7, "The real HUD must derive nearest direction and distance from the actual world crate")
	check(String(game.hud.supply_crate_navigation_label()) == "补给箱 2 · 东 7米", "The compact HUD navigation line must name the visible crate direction and distance")
	check(navigation.positions.has(east_crate.global_position) and navigation.positions.has(north_crate.global_position), "Expanded-map marker inputs must use exact live crate world positions")
	east_crate.open()
	var queued_crate: Node3D = fixture_crate(game.hero.position + Vector3(2, 0, 0))
	queued_crate.queue_free()
	var detached_crate: Node3D = fixture_crate(game.hero.position + Vector3(0, 0, 1))
	game.remove_child(detached_crate)
	root.add_child(detached_crate)
	navigation = game.hud.supply_crate_navigation_snapshot()
	check(int(navigation.get("count", -1)) == 1 and navigation.positions.size() == 1 and navigation.positions[0] == north_crate.global_position, "Opened, queued-for-deletion and foreign-parent crates cannot leave navigation or map markers")
	check(String(navigation.get("direction", "")) == "北" and int(navigation.get("distance_meters", -1)) == 10 and String(game.hud.supply_crate_navigation_label()) == "补给箱 1 · 北 10米", "Navigation must advance to the next genuinely live crate")
	root.remove_child(detached_crate)
	game.add_child(detached_crate)
	reset_supply()
	stand(hero_before)
	check(int(game.hud.supply_crate_navigation_snapshot().get("count", -1)) == 0, "Clearing crates must leave the marker snapshot empty")

func new_game() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	game.archive.enabled = false
	root.add_child(game)
	game.archive.enabled = false
	current_scene = game
	await create_timer(.25).timeout
	game.set_process(false)

func close_game() -> void:
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.35).timeout

func run() -> void:
	await new_game()
	check(game.phase == "draft", "Run must begin in the normal draft phase")
	check(not game.toggle_tower_construction() and not game.construction.active, "No permit can open a construction catalogue")
	check(game.choose_card(0) and game.phase == "night", "The normal card selection must still start the night")
	# A short real opening observation before any fixture isolation. The
	# original wallet, hero, enemies, damage, clocks and camera all advance
	# through production updates; this does not claim a balanced complete run.
	var opening_night_time: float = game.phase_time
	var opening_elapsed: float = 0.0
	while opening_elapsed < 25.1 and game.phase == "night":
		game._process(STEP)
		opening_elapsed += STEP
	check(opening_elapsed >= 25.1 and game.phase == "night" and game.phase_time <= opening_night_time - 25.0, "The unmodified first-night opening must really advance through the first twenty-five seconds")
	check(game.hero.alive and game.hero.hp > 0.0 and game.beacon_hp > 0.0, "The standing hero and original beacon must survive the real first-night crate observation")
	check(game.supply_crates.size() >= 1, "The original first night must deliver a real nearby crate without clearing threats or advancing its clock directly")
	if not game.supply_crates.is_empty():
		var opening_crate: Node3D = game.supply_crates[0]
		assert_visible_nearby(opening_crate, "real first-night twenty-five-second delivery")
	print("FIRST_NIGHT_SUPPLY_OBSERVATION elapsed=%.3f phase=%s hero_hp=%.3f beacon_hp=%.3f crates=%d" % [opening_elapsed, game.phase, game.hero.hp, game.beacon_hp, game.supply_crates.size()])
	await capture("first-night-default-camera")
	game.begin_day()
	isolate()
	press(KEY_Y)
	check(not game.construction.active, "Y input cannot open a construction catalogue without a permit")
	check(String(game.notice).contains("暂无建筑许可"), "Y must explain that the player needs a supply-crate permit")

	# The fixed game clock and cap run without borrowing the enemy spawn stream.
	game.supply_rng.seed = 20261008
	var spawn_state: int = game.spawn_rng.state
	game.advance_supply_crates(game.SUPPLY_CRATE_INTERVAL - .05)
	check(game.supply_crates.is_empty(), "No supply crate appears before the fixed interval")
	game.advance_supply_crates(.06)
	check(game.supply_crates.size() == 1, "A real supply crate appears after 25 game seconds")
	check(game.spawn_rng.state == spawn_state, "Supply spawning must preserve the enemy spawn RNG stream")
	var navigation_start: Vector2i = game.nearest_navigation_cell(game.hero.position, true)
	for crate: Node3D in game.supply_crates.duplicate():
		check(crate.is_inside_tree() and crate.get_node_or_null("CrateBody") != null and crate.get_node_or_null("SupplyGlow") != null, "A spawned supply crate must be a visible map entity")
		# The placement validator rejects overlap with every already registered box.
		game.supply_crates.erase(crate)
		check(game._supply_crate_position_legal(crate.position, navigation_start), "The complete crate footprint and reachable endpoint must be legal")
		game.supply_crates.append(crate)
		check(game.outpost_walkable(crate.position), "Spawned crates must stand on traversable ground")
		assert_visible_nearby(crate, "first fixed-clock delivery")
		await capture("automatically-spawned-default-camera")
		await capture("automatically-spawned-crate", crate.position)
	for _interval in 8:game.advance_supply_crates(game.SUPPLY_CRATE_INTERVAL)
	check(game.supply_crates.size() == game.SUPPLY_CRATE_MAX, "Elapsed time must never exceed the simultaneous crate cap")
	check(game.spawn_rng.state == spawn_state, "All repeated supply spawns must preserve the hostile RNG state")
	await nearby_visibility_cases()
	blocked_delivery_retry()
	navigation_marker_cases()
	reset_supply()
	check(not game._supply_crate_position_legal(Vector3.INF, navigation_start), "Non-finite supply positions must be rejected")
	check(not game._supply_crate_position_legal(ground(Vector3(12.8, 0, 6)), navigation_start), "A walkable center cannot allow the crate footprint to clip the wall")
	check(not game._supply_crate_position_legal(ground(Vector3(80, 0, -80)), navigation_start), "Lake terrain cannot receive a supply crate")
	check(not game._supply_crate_position_legal(game.hero.position, navigation_start), "A supply crate cannot spawn on an occupied player position")
	# Reuse one genuinely eligible point so rejection is caused by each live
	# occupant, rather than by terrain or an unreachable endpoint.
	var occupied_point: Vector3 = game._supply_crate_spawn_position()
	check(occupied_point.is_finite(), "Occupation fixtures require an otherwise legal supply point")
	if occupied_point.is_finite():
		var enemy := BattleUnit.new()
		game.add_child(enemy)
		enemy.setup("minion", 1)
		enemy.position = occupied_point
		game.enemies.append(enemy)
		check(not game._supply_crate_position_legal(occupied_point, navigation_start), "A real hostile actor must block crate spawning at its occupied position")
		game.enemies.erase(enemy)
		enemy.queue_free()
		var scout: BattleUnit = game.expeditions.camps[0].npc
		var scout_position: Vector3 = scout.position
		scout.position = occupied_point
		check(not game._supply_crate_position_legal(occupied_point, navigation_start), "A real escort NPC must block crate spawning at its occupied position")
		var npc_crate := fixture_crate(occupied_point)
		assert_not_opened(npc_crate, "An allied escort NPC outside the player-controlled roster cannot open crates")
		scout.position = scout_position
		reset_supply()
	var roll_state: int = game.spawn_rng.state
	for _reward in 24:
		var rolled: Dictionary = game._roll_supply_reward()
		if String(rolled.type) == "building_permit":
			check(bool(game.districts.build_eligibility(String(rolled.kind)).available), "Rolled building permits must satisfy current technology")
		else:
			check(bool(game.squads.training_eligibility(String(rolled.kind)).available), "Rolled training orders must satisfy current technology")
	check(game.spawn_rng.state == roll_state, "Supply rewards must not consume the enemy spawn RNG")

	# A fixture deliberately straddles the castle wall at the same height:
	# distance alone would allow pickup, but the solid wall forbids contact.
	stand(Vector3(12.99, 0, 6))
	var blocked_crate := fixture_crate(Vector3(14.61, 0, 6))
	blocked_crate.position.y = game.hero.position.y
	check(game.hero.position.distance_to(blocked_crate.position) <= game.SUPPLY_CRATE_TRIGGER_RADIUS, "The wall fixture must be within the geometric pickup radius")
	check(not game.can_traverse(game.hero.position, blocked_crate.position), "The wall fixture must have a genuinely blocked approach")
	assert_not_opened(blocked_crate, "A nearby hero cannot open a supply crate through a solid wall")
	reset_supply()

	# Fixture positioning isolates the trigger; the hero still traverses the
	# real path and reaches the distance threshold without interaction input.
	var hero_route: Array[Vector3] = pickup_route()
	check(hero_route.size() == 2, "Hero requires a legal four-metre flat pickup approach")
	if hero_route.size() != 2:
		await close_game()
		push_error("NIGHTFALL_SUPPLY_CRATES_FAILED checks=%d failures=%d" % [checks, failures.size()])
		quit(1)
		return
	stand(hero_route[0])
	var hero_start: Vector3 = game.hero.position
	var walking_crate := fixture_crate(hero_route[1])
	game.plan_hero_path(walking_crate.position)
	check(not game.hero_path.is_empty(), "The hero pickup fixture must have an actual planned path")
	game._try_open_supply_crates()
	check(game.supply_crates.has(walking_crate), "A distant hero cannot open the crate")
	await capture("hero-before-contact", (hero_start + walking_crate.position) * .5)
	for _step in 120:
		game.move_hero(STEP)
		game.advance_supply_crates(STEP)
		if game.supply_crates.is_empty():break
	check(game.hero.position.distance_to(hero_start) > 1.0, "The hero must move toward the pickup")
	check(game.supply_crates.is_empty() and bool(walking_crate.opened), "Hero movement automatically opens a touched crate without interaction input")
	var opened_rewards := reward_count()
	game._try_open_supply_crates()
	check(reward_count() == opened_rewards and not walking_crate.open(), "The same world crate cannot award twice")
	reset_supply()

	var paused_crate := fixture_crate(Vector3(-8, 0, 8))
	game.supply_crate_clock = 10.0
	game.advance_supply_crates(.1)
	var frozen_clock: float = game.supply_crate_clock
	var frozen_pulse: float = paused_crate.pulse_time
	game.phase = "paused"
	stand(paused_crate.position)
	game.simulate(8.0)
	game.advance_supply_crates(8.0)
	check(is_equal_approx(game.supply_crate_clock, frozen_clock), "Pause must freeze the supply timer")
	check(is_equal_approx(paused_crate.pulse_time, frozen_pulse), "Pause must freeze crate animation")
	check(game.supply_crates.has(paused_crate) and not bool(paused_crate.opened), "Pause must prevent contact from opening a crate")
	game.phase = "day"
	reset_supply()
	stand(Vector3(5, 0, 9))

	# Three unaffordable/unavailable training rewards used to recursively
	# requeue each other. Finite retry must preserve them and allow a building.
	game.scrap = 500
	for kind: String in ["shield", "engineer", "shield"]:
		game._apply_supply_reward({"type":"training_order", "kind":kind})
	check(pending_orders() == 3 and queue_count() == 0, "All failed training orders must remain unconsumed without a barracks")
	var no_barracks_balance: int = game.scrap
	for _attempt in 5:game._drain_supply_rewards()
	check(pending_orders() == 3 and game.scrap == no_barracks_balance, "Retrying multiple failed orders must terminate and never charge resources")
	game._apply_supply_reward({"type":"building_permit", "kind":"barracks", "title":"兵营"})
	check(game.pending_build_permit_kind == "barracks" and game.construction.active, "Blocked training rewards must not prevent a building preview")
	var previous_aim: Vector3 = game.aim
	game.aim = legal_build_point("barracks")
	game.construction.tick(0.0)
	await capture("barracks-permit-preview", game.aim)
	game.aim = previous_aim
	game.construction.tick(0.0)
	var permit_kind: String = game.construction.kind
	press(KEY_2)
	press(KEY_PAGEDOWN)
	check(game.construction.kind == permit_kind, "Number and page keys cannot browse other building cards")
	var balance: int = game.scrap
	game.aim = Vector3.ZERO
	check(not game.construction.confirm(), "A permit cannot place a building on the occupied core")
	check(game.scrap == balance and game.pending_build_permit_kind == "barracks", "An invalid placement cannot charge or consume its permit")
	var barracks_point := legal_build_point("barracks")
	check(barracks_point.is_finite(), "The shared 26x26 grid must provide a legal barracks location")
	game.aim = barracks_point
	game.scrap = 0
	check(not game.construction.confirm(), "A valid position with insufficient resources must fail")
	check(game.scrap == 0 and game.pending_build_permit_kind == "barracks", "An unaffordable building keeps its permit and wallet")
	game.construction.cancel()
	check(game.pending_build_permit_kind == "barracks", "Cancelling a preview retains its building permit")
	press(KEY_Y)
	check(game.construction.active and game.construction.kind == "barracks", "Y may resume only the already owned building permit")
	game.scrap = balance
	check(game.construction.confirm(), "The retained permit must deploy through the original placement path")
	check(String(game.notice).contains("建筑已部署") and String(game.notice).contains("训练订单已加入"), "Barracks deployment and simultaneous real training must both appear in the receipt")
	for _attempt in 5:game._drain_supply_rewards()
	check(game.pending_build_permit_kind.is_empty() and not game.construction.active, "Successful deployment consumes one permit and closes its preview")
	check(pending_orders() == 0 and queue_count() == 3, "Retained rewards must enter the real barracks training queue")
	check(game.scrap == balance - int(Catalog.building("barracks").cost) - 205, "A barracks and three accepted orders must each charge their original cost once")
	check(game.squads.squads.is_empty(), "Accepted training orders cannot instantly create free soldiers")
	var paid_balance: int = game.scrap
	game._drain_supply_rewards()
	check(game.scrap == paid_balance and queue_count() == 3, "Repeated reward draining cannot duplicate accepted training orders")
	var original_remaining := first_queue_remaining()
	game.phase = "paused"
	game.simulate(20.0)
	check(is_equal_approx(first_queue_remaining(), original_remaining) and game.squads.squads.is_empty(), "Paused training cannot advance or spawn soldiers")
	game.phase = "day"
	game.squads._advance_training(5.99)
	check(game.squads.squads.is_empty() and queue_count() == 3, "A training order must wait its real six-second training duration")
	game.squads._advance_training(.02)
	check(game.squads.squads.size() == 1 and queue_count() == 2, "Only completed training may create its real three-member squad")
	game.squads._advance_training(20.0)
	check(game.squads.squads.size() == 3 and queue_count() == 0 and game.scrap == paid_balance, "Remaining paid training must complete without extra fees or free duplicates")

	# Live technology and budget are revalidated even after a reward was earned.
	game._apply_supply_reward({"type":"training_order", "kind":"hauler"})
	check(pending_orders() == 1 and queue_count() == 0, "A missing live technology prerequisite keeps the training order")
	check(String(game.notice).contains("中转站"), "Training refusal must report its actual missing technology")
	reset_supply()
	game.scrap = 0
	game._apply_supply_reward({"type":"training_order", "kind":"shield"})
	check(pending_orders() == 1 and queue_count() == 0 and game.scrap == 0, "An unaffordable training reward is retained and cannot debit the wallet")
	check(String(game.notice).contains("零件不足"), "Training refusal with an existing barracks must report insufficient resources")
	reset_supply()
	game.scrap = 500
	game._apply_supply_reward({"type":"building_permit", "kind":"recycler"})
	game.aim = ground(Vector3(8, 0, -8))
	check(not game.construction.confirm() and game.pending_build_permit_kind == "recycler" and game.scrap == 500, "A permit cannot bypass a missing building technology prerequisite")
	reset_supply()
	check(deploy_permit("tower"), "A tower reward must deploy through the same grid placement workflow")
	check(game.pending_build_permit_kind.is_empty() and String(game.notice).contains("建筑已部署"), "Tower deployment must consume its permit and display the deployment receipt")

	var soldier := current_member("shield")
	check(is_instance_valid(soldier), "Completed real training must provide a player soldier for pickup checks")
	if is_instance_valid(soldier):
		reset_supply()
		stand(Vector3(4, 0, 8))
		for squad: Dictionary in game.squads.squads:
			for other: BattleUnit in squad.members:
				if is_instance_valid(other):other.position = ground(Vector3(4, 0, 7))
		var restricted_crate := fixture_crate(Vector3(11, 0, 10))
		soldier.position = restricted_crate.position
		var original_hp := soldier.hp
		soldier.hp = 0.0
		assert_not_opened(restricted_crate, "A zero-HP unit cannot open a supply crate even if its alive flag is stale")
		soldier.hp = original_hp
		soldier.alive = false
		assert_not_opened(restricted_crate, "A dead squad member cannot open a supply crate")
		soldier.alive = true
		soldier.team = 1
		assert_not_opened(restricted_crate, "A squad member that has lost player allegiance cannot open a crate")
		soldier.team = 0
		var roster: Array = game.squads.squads[0].members
		var slot := roster.find(soldier)
		roster.remove_at(slot)
		assert_not_opened(restricted_crate, "A former member removed from the current roster cannot open a crate")
		roster.insert(slot, soldier)
		var controller: Node3D = game.squads.game
		game.squads.game = null
		assert_not_opened(restricted_crate, "A squad under a retired controller cannot open a crate")
		game.squads.game = controller
		var parent := soldier.get_parent()
		parent.remove_child(soldier)
		assert_not_opened(restricted_crate, "A detached squad member cannot open a crate")
		parent.add_child(soldier)
		game.hero.position = restricted_crate.position
		game._try_open_supply_crates()
		check(bool(restricted_crate.opened) and game.supply_crates.is_empty(), "Two eligible simultaneous contacts must consume a crate only once")
		var simultaneous_rewards := reward_count()
		game._try_open_supply_crates()
		check(reward_count() == simultaneous_rewards and not restricted_crate.open(), "Simultaneous contacts cannot duplicate the crate reward")
		open_with_movement(soldier, "部队")

	reset_supply()
	game.scrap = 500
	check(deploy_permit("workshop"), "The worker prerequisite workshop must be paid and built normally")
	check(deploy_permit("depot"), "The worker prerequisite depot must be paid and built normally")
	var worker_balance: int = game.scrap
	game._apply_supply_reward({"type":"training_order", "kind":"hauler"})
	check(queue_count() == 1 and pending_orders() == 0 and game.scrap == worker_balance - int(Catalog.troop("hauler").cost), "A worker reward must pay for the real training queue")
	check(not is_instance_valid(current_member("hauler")), "A worker reward cannot spawn an instantaneous free worker")
	game.squads._advance_training(8.01)
	var worker := current_member("hauler")
	check(is_instance_valid(worker), "A worker reward must finish its existing training duration")
	if is_instance_valid(worker):open_with_movement(worker, "工队")

	# Real transition entry points clear map entities but preserve unused permits.
	reset_supply()
	game._apply_supply_reward({"type":"building_permit", "kind":"tower"})
	fixture_crate(Vector3(10, 0, 10))
	game.supply_crate_clock = 12.0
	game.start_night()
	check(game.phase == "night" and game.supply_crates.is_empty() and game.supply_crate_clock == 0.0, "Day-to-night transition must clear world crates and reset their timer")
	check(game.pending_build_permit_kind == "tower" and not game.construction.active, "Day-to-night transition keeps a cancelled building permit")
	fixture_crate(Vector3(10, 0, 10))
	game.begin_day()
	check(game.phase == "day" and game.supply_crates.is_empty() and game.pending_build_permit_kind == "tower", "Night-to-day transition clears entities while preserving an unused permit")
	game.construction.cancel()
	fixture_crate(Vector3(10, 0, 10))
	game.pending_training_order_kind = "hauler"
	game.supply_reward_queue.append({"type":"building_permit", "kind":"barracks"})
	game.end_defeat("Supply crate regression defeat")
	check(game.phase == "ended" and not game.victory, "The failure case must enter the real defeat path from an active phase")
	check(game.supply_crates.is_empty() and reward_count() == 0 and game.supply_crate_clock == 0.0, "Defeat must clear crates, pending rewards and timing")
	game.advance_supply_crates(100.0)
	check(game.supply_crates.is_empty() and reward_count() == 0, "Ended failure cannot create or award supply crates")
	await close_game()

	# Use a new controller for victory so defeat and success test separate real
	# terminal transitions rather than calling end_defeat() on an ended game.
	await new_game()
	check(game.supply_crates.is_empty() and reward_count() == 0 and game.supply_crate_clock == 0.0, "A newly instantiated controller must start without old crates or rewards")
	game.choose_card(0)
	isolate()
	game.pending_build_permit_kind = "tower"
	game.pending_training_order_kind = "shield"
	game.supply_reward_queue.append({"type":"building_permit", "kind":"barracks"})
	fixture_crate(Vector3(10, 0, 10))
	game.phase = "night"
	game.night_clearance_active = true
	game.night_clearance_elapsed = 0.0
	game.final_clearance_active = true
	game.phase_time = 0.0
	game.wave_index = game.WAVES_PER_NIGHT
	game.day_number = game.max_nights()
	game.finish_night()
	check(game.phase == "ended" and game.victory, "The settlement case must enter the real final-clearance victory path")
	check(game.supply_crates.is_empty() and reward_count() == 0 and game.supply_crate_clock == 0.0, "Victory must clear world crates and unconsumed rewards")
	game.advance_supply_crates(100.0)
	check(game.supply_crates.is_empty() and reward_count() == 0, "Ended victory cannot spawn crates or resume rewards")
	await close_game()
	if failures.is_empty():
		print("NIGHTFALL_SUPPLY_CRATES_OK checks=%d" % checks)
	else:
		push_error("NIGHTFALL_SUPPLY_CRATES_FAILED checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
