extends SceneTree
## Production unrestricted castle placement and live tower combat.
## Graphics: --windowed --position 10000,10000 --audio-driver Dummy -- --render-test.
const Layout = preload("res://scripts/outpost_layout.gd")
const Grid := preload("res://scripts/construction_grid.gd")
const FAR := Vector3(105, 0, 95)
const STEP := 1.0 / 60.0
var game: Node3D
var checks := 0
var failures: Array[String] = []
var render_test := false
var built_indices: Array[int] = []
var routes_finished := 0
var enemy_routes_finished := 0

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	render_test = "--render-test" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 20: push_error(message)

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func stand(point: Vector3) -> void:
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.move_goal = point
	game.hero_path.clear()
	game.hero_keyboard_active = false
	game.hero.moving = false
	game.hero.set_locomotion_velocity(Vector3.ZERO)

func camera_at(center: Vector3) -> void:
	game.camera.size = 42.0
	game.camera_follow = center + Vector3(0, 25, 29)
	game.camera.position = game.camera_follow
	game.camera.look_at(center)

func aim_at(point: Vector3) -> Vector2:
	point.y = game.outpost_height(point)
	var viewport_point: Vector2 = game.camera.unproject_position(point)
	var motion := InputEventMouseMotion.new()
	motion.position = viewport_point
	motion.global_position = viewport_point
	root.push_input(motion, true)
	await process_frame
	# Consume the real buffered event through the production frame, retaining
	# deterministic time while the ordinary autonomous process is disabled.
	game._process(0.0)
	return viewport_point

func click_world(point: Vector3, button: int = MOUSE_BUTTON_LEFT) -> void:
	var viewport_point: Vector2 = await aim_at(point)
	var event := InputEventMouseButton.new()
	event.position = viewport_point
	event.global_position = viewport_point
	event.button_index = button
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	event.pressed = true
	# Dispatch through the real viewport GUI and unhandled-input pipeline,
	# using local coordinates even when headless has a tiny physical window.
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	event.button_mask = 0
	root.push_input(event, true)
	await process_frame

func isolate() -> void:
	game.contracts.status = "idle"
	game.beacon_hp = game.BEACON_MAX
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	for item: Dictionary in game.discoveries.items:
		game.discoveries.begin_cooling(item, 9999.0)
		item.position = FAR
		item.node.position = FAR
	for animal: Dictionary in game.wildlife.animals:
		animal.position = FAR
		animal.node.position = FAR
		animal.anchor = FAR
		animal.target = FAR
		animal.timer = 9999.0
	for cache: Dictionary in game.world.salvage:
		cache.collected = true
		cache.respawn = 9999.0
	for generator: Dictionary in game.expeditions.generators: generator.state = "complete"
	for camp: Dictionary in game.expeditions.camps: camp.state = "delivered"
	for nest: Dictionary in game.world.nests: nest.cleansed = true
	for relay: Dictionary in game.world.relays: relay.activated = true

func ground_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func free_point() -> Vector3:
	for zi in 22:
		for xi in 22:
			var point := Vector3(-11.0 + float(xi), 5, -11.0 + float(zi))
			var placement: Dictionary = game.construction.validity(point)
			if bool(placement.valid): return placement.point
	return Vector3.INF

func capture(state: String, night: bool = false) -> void:
	if not render_test: return
	check(DisplayServer.get_name() != "headless", "Actual render capture requires a graphics driver")
	if DisplayServer.get_name() == "headless": return
	game.world.night_mix = 1.0 if night else 0.0
	game.world.set_night(night)
	game.world.apply_lighting()
	game.notice_time = 0.0
	game.hud.queue_redraw()
	for _frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var output := "res://build/nightfall-castle-%s.png" % state
	check(root.get_texture().get_image().save_png(output) == OK, "Save actual castle %s frame" % state)
	print("CASTLE_FREE_BUILD_FRAME ", ProjectSettings.globalize_path(output))

func build_with_input(point: Vector3, use_mouse: bool, expected_cost: int) -> int:
	var snapped: Vector3 = Grid.placement(point, "tower").point
	camera_at(Vector3(point.x, game.outpost_height(point), point.z))
	if not game.construction.active: await press(KEY_Y)
	await press(KEY_1)
	await aim_at(point)
	var preview: Dictionary = game.construction.snapshot()
	check(bool(preview.active) and bool(preview.valid) and String(preview.kind) == "tower",
		"The real tower cursor must show a valid continuous-placement preview")
	check(int(preview.cost) == expected_cost and ground_distance(preview.point, snapped) < .06,
		"The preview must use the fresh grid-snapped terrain position and actual workshop fee")
	var balance: int = game.scrap
	var count: int = game.world.tower_pads.size()
	var towers: int = game.tower_count()
	if use_mouse: await click_world(point)
	else: await press(KEY_F)
	check(game.world.tower_pads.size() == count + 1 and game.tower_count() == towers + 1,
		"Actual confirmation must append exactly one live tower at the free position")
	check(game.scrap == balance - expected_cost and game.construction.active,
		"Confirmation must pay once and retain construction for another tower")
	if game.world.tower_pads.size() != count + 1: return -1
	var pad: Dictionary = game.world.tower_pads[count]
	check(int(pad.level) == 1 and is_equal_approx(float(pad.hp), 280.0) and is_instance_valid(pad.turret),
		"The free foundation must contain a real level-one turret with 280 durability")
	check(ground_distance(pad.position, snapped) < .06 and absf(pad.position.y - 5.0) < .001,
		"Construction must preserve the chosen snapped footprint on the real city floor")
	built_indices.append(count)
	balance = game.scrap
	check(not game.build_tower_at(point), "Repeated construction must reject the actual occupied tower footprint")
	check(game.scrap == balance and game.world.tower_pads.size() == count + 1,
		"Overlapping confirmation must not spend or append a second tower")
	return count

func invalid_placements() -> void:
	var points: Array[Vector3] = [Vector3(30, 0, 0), Vector3(Layout.WALL_CENTER, 5, 0),
		Vector3(0, 5, 0), game.world.tower_pads[0].position]
	for point in points:
		var balance: int = game.scrap
		var count: int = game.world.tower_pads.size()
		var result: Dictionary = game.construction.validity(point)
		check(not bool(result.valid) and not String(result.reason).is_empty(), "An actual forbidden footprint must have an honest reason: %s" % point)
		check(not game.build_tower_at(point), "Production must reject actual blocked construction: %s" % point)
		check(game.scrap == balance and game.world.tower_pads.size() == count,
			"Rejected construction must retain the budget and tower count")
	await press(KEY_Y)
	await aim_at(Vector3.ZERO)
	await capture("rejected-preview")
	var balance: int = game.scrap
	var count: int = game.world.tower_pads.size()
	await press(KEY_F)
	await click_world(Vector3.ZERO)
	check(game.scrap == balance and game.world.tower_pads.size() == count,
		"F and actual left-click must both reject a collision preview")
	await click_world(Vector3.ZERO, MOUSE_BUTTON_RIGHT)
	check(not game.construction.active and game.hero_path.is_empty(),
		"Right-click cancellation must not leak into hero movement")
	await press(KEY_Y)
	await press(KEY_ESCAPE)
	check(not game.construction.active and game.phase == "day", "Escape must cancel construction before pausing")

func geometry_and_routes() -> void:
	check(is_equal_approx(Layout.FORT_INNER, 13.0), "The expanded castle must retain its 26m interior")
	check(game.world.tower_pads.size() == 2 and game.tower_count() == 2,
		"Opening city must have only its two live towers, without fixed empty foundations")
	check(game.districts.plots.is_empty(), "A fresh city cannot reserve fixed district slots")
	check(game.world.tower_pads[0].position.distance_to(Vector3(5.5, 5, 10.5)) < .001 and
		game.world.tower_pads[1].position.distance_to(Vector3(-5.5, 5, 10.5)) < .001,
		"Opening defenders must remain inside the expanded southern wall")
	var home := Vector3(0, 5, 3.1)
	for start in [Vector3(30, 0, 0), Vector3(-30, 0, 0), Vector3(0, 0, -30)]:
		check(not game.can_traverse(start, home), "The east/west/north walls must preserve the sole south entrance")
	check(game.can_traverse(Vector3(0, 0, 32), home), "The southern ramp must remain continuously walkable")
	for z in [14.5, 18.0, 22.0, 25.0]:
		var ramp := Vector3(0, game.outpost_height(Vector3(0, 0, z)), z)
		check(game.outpost_walkable(ramp), "The southern ramp must be walkable at z=%.1f" % z)
		check(game.ground_point(game.camera.unproject_position(ramp)).distance_to(ramp) < .035,
			"Actual cursor rays must resolve the southern ramp at z=%.1f" % z)
	for start in [Vector3(-30, 0, 35), Vector3(30, 0, 35), Vector3(0, 0, 40)]:
		stand(start)
		game.plan_hero_path(home)
		travel_route(home, "return from %s" % start)
	stand(home)
	var destination := Vector3(25, 0, 0)
	game.plan_hero_path(destination)
	travel_route(destination, "exit to eastern wilderness")
	stand(Vector3(25, 0, 30))
	camera_at(Vector3(0, 5, 7))
	await click_world(home, MOUSE_BUTTON_RIGHT)
	check(game.hero_path.size() > 1, "Real hero right-click must use the sole southern entrance")
	travel_route(home, "actual right-click return")
	stand(home)
	camera_at(Vector3(0, 5, 0))

func travel_route(destination: Vector3, title: String) -> void:
	check(not game.hero_path.is_empty(), title + ": planner must provide a real route")
	var reached := false
	var visited_ramp := false
	var stalled := 0
	for _frame in 1000:
		var before: Vector3 = game.hero.position
		game.move_hero(STEP)
		check(game.can_traverse(before, game.hero.position) and game.outpost_walkable(game.hero.position), title + ": no wall crossing")
		check(absf(game.hero.position.y - game.outpost_height(game.hero.position)) < .001, title + ": real terrain height")
		if game.hero.position.z > 15.0 and game.hero.position.z < 24.5 and absf(game.hero.position.x) < 2.6: visited_ramp = true
		if ground_distance(before, game.hero.position) < .0001: stalled += 1
		else: stalled = 0
		if game.hero_path.is_empty() and ground_distance(game.hero.position, destination) < .25:
			reached = true
			break
		if stalled > 12: break
	check(reached and visited_ramp, title + ": real movement must finish through the raised south ramp")
	if reached: routes_finished += 1

func frozen_and_poor() -> void:
	var point: Vector3 = free_point()
	check(point != Vector3.INF, "A spare city position must remain for phase and money refusal")
	if point == Vector3.INF: return
	var saved_balance: int = game.scrap
	game.scrap = 0
	var count: int = game.world.tower_pads.size()
	await aim_at(point)
	check(not bool(game.construction.snapshot().valid) and bool(game.construction.snapshot().space_valid),
		"An unaffordable footprint must remain spatially legal and display its actual fee")
	await press(KEY_F)
	check(game.scrap == 0 and game.world.tower_pads.size() == count, "Unaffordable real F must never build or pay")
	await press(KEY_ESCAPE)
	game.scrap = saved_balance
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "Escape outside build mode must still pause")
	await press(KEY_Y)
	check(not game.construction.active and not game.build_tower_at(point), "Pause must refuse construction mode and direct placement")
	await press(KEY_ESCAPE)
	var upgrade_cost: int = game.run.memory_cost()
	var paid_level: int = game.run.memory_level
	check(saved_balance >= upgrade_cost and game.run.pending == 0,
		"The real city balance must fund a fresh manually requested upgrade")
	await press(KEY_Y)
	await press(KEY_V)
	game._process(0.0)
	check(game.phase == "draft" and game.run.pending == 1 and game.run.memory_level == paid_level + 1
		and game.scrap == saved_balance - upgrade_cost
		and game.construction.active and not game.construction.ghost.visible,
		"Real V must pay shared scrap once and hide the retained construction preview")
	check(not game.build_tower_at(point) and game.scrap == saved_balance - upgrade_cost and game.world.tower_pads.size() == count,
		"Card selection cannot pay for construction")
	await press(KEY_1)
	game._process(0.0)
	check(game.phase == "day" and game.run.pending == 0 and game.scrap == saved_balance - upgrade_cost
		and game.construction.active and game.construction.ghost.visible,
		"Actual card choice must resume the retained city placement preview without paying again")
	await press(KEY_ESCAPE)

func tower_controls_and_combat(index: int) -> void:
	if index < 0: return
	var pad: Dictionary = game.world.tower_pads[index]
	stand(pad.position + Vector3(0, 0, -1.9))
	var balance: int = game.scrap
	await press(KEY_F)
	check(int(pad.level) == 2 and game.scrap == balance - game.districts.tower_cost(50), "F must upgrade a real nearby freely placed tower")
	balance = game.scrap
	await press(KEY_J)
	check(game.specializations.branch(pad) == "piercing" and game.scrap == balance - 45, "J must apply the real dynamic tower specialization")
	balance = game.scrap
	await press(KEY_K)
	check(game.specializations.branch(pad) == "piercing" and game.scrap == balance, "Mutually exclusive K cannot replace or charge another branch")
	for expected in ["breaker", "threat", "nearest"]:
		await press(KEY_G)
		check(String(pad.mode) == expected, "G must preserve every dynamic tower target mode")
	game.damage_tower(index, 135.0)
	var hp: float = pad.hp
	balance = game.scrap
	await press(KEY_H)
	check(is_equal_approx(float(pad.hp), hp + 100.0) and game.scrap == balance - game.districts.repair_cost(20), "H must perform real paid dynamic tower repair")
	game.phase = "night"
	stand(FAR)
	var enemy: BattleUnit = game.spawn_creature(true, "stalker")
	enemy.position = pad.position + Vector3(-1.8, 0, 0)
	enemy.attack_timer = 0.0
	enemy.attack_range = 2.5
	var target: Dictionary = game.choose_enemy_target(enemy)
	check(String(target.kind) == "tower" and int(target.index) == index, "A normal monster must select the nearest actual free tower")
	game.update_creature(enemy, .01)
	hp = pad.hp
	enemy.tick(.6)
	game.update_creature(enemy, .6)
	check(float(pad.hp) < hp, "The monster's real windup must damage the free tower")
	enemy.max_hp = 100000.0
	enemy.hp = enemy.max_hp
	for other: Dictionary in game.world.tower_pads: other.cooldown = 9999.0
	pad.cooldown = 0.0
	var enemy_hp: float = enemy.hp
	game.update_towers(.1)
	check(enemy.hp < enemy_hp and float(pad.cooldown) > 0.0, "The free tower must actually fire and damage its enemy")
	pad.cooldown = 0.0
	enemy.hp = 1.0
	var chain: int = game.kill_chain
	game.update_towers(.1)
	check(not enemy.alive and game.kill_chain == chain, "Tower kills cannot claim the hero's personal combo reward")
	game.damage_tower(index, 99999.0)
	check(int(pad.level) == 0 and game.specializations.branch(pad) == "standard", "Tower destruction must reset its paid specialization")
	await process_frame
	check(game.outpost_walkable(pad.position), "A destroyed low foundation must release its navigation footprint")
	stand(pad.position)
	balance = game.scrap
	await press(KEY_F)
	check(int(pad.level) == 0 and game.scrap == balance,
		"Reconstruction must refuse to erect a tower over the living hero standing on its low foundation")
	stand(pad.position + Vector3(0, 0, -1.9))
	balance = game.scrap
	var count: int = game.world.tower_pads.size()
	await press(KEY_F)
	check(int(pad.level) == 1 and game.scrap == balance - game.districts.tower_cost(60) and game.world.tower_pads.size() == count,
		"F must rebuild the same damaged tower without appending a duplicate foundation")
	game.phase = "day"

func enemy_routes_to_dynamic_tower(index: int) -> void:
	if index < 0: return
	var pad: Dictionary = game.world.tower_pads[index]
	var saved_towers: Array[Dictionary] = []
	for i in game.world.tower_pads.size():
		var other: Dictionary = game.world.tower_pads[i]
		saved_towers.append({"index": i, "level": other.level, "hp": other.hp, "cooldown": other.cooldown})
		other.cooldown = 9999.0
		if i != index:
			other.level = 0
			other.hp = 0.0
	game.refresh_construction_navigation()
	var saved_phase: String = game.phase
	var saved_hp: float = pad.hp
	game.phase = "night"
	stand(FAR)
	# Sappers retain their actual tower-hunting role while traveling, whereas
	# ordinary enemies may legitimately switch to the closer beacon at the gate.
	for start: Vector3 in [Vector3(30, 0, 0), Vector3(-30, 0, 0), Vector3(0, 0, -30)]:
		pad.hp = saved_hp
		var creature: BattleUnit = game.spawn_creature(true, "sapper")
		creature.position = start
		creature.attack_timer = 0.0
		var queued := false
		var damaged := false
		var visited_ramp := false
		var crossed_gate := false
		var stalled := 0
		for _frame in 1000:
			var before: Vector3 = creature.position
			creature.tick(.05)
			game.update_creature(creature, .05)
			check(game.can_traverse(before, creature.position) and game.outpost_walkable(creature.position),
				"A distant tower hunter must follow traversable terrain without crossing a castle wall")
			check(absf(creature.position.y - game.outpost_height(creature.position)) < .001,
				"A distant tower hunter must follow the actual castle ramp height")
			if creature.position.z > Layout.RAMP_WALL_START and creature.position.z < Layout.RAMP_WALL_END and absf(creature.position.x) < Layout.RAMP_INNER_HALF:
				visited_ramp = true
			if before.z >= Layout.WALL_CENTER and creature.position.z < Layout.WALL_CENTER and absf(creature.position.x) < Layout.GATE_HALF:
				crossed_gate = true
			if creature.attack_queued and String(creature.get_meta("attack_target_kind", "")) == "tower" and int(creature.get_meta("attack_target_index", -1)) == index:
				queued = true
			if float(pad.hp) < saved_hp:
				damaged = true
				break
			if ground_distance(before, creature.position) < .0001 and not creature.attack_queued: stalled += 1
			else: stalled = 0
			if stalled > 20: break
		check(visited_ramp and crossed_gate and queued and damaged,
			"A tower hunter from %s must enter through the sole southern gate, then wind up and damage the dynamic tower; end=%s ramp=%s gate=%s queued=%s damage=%s" % [start, creature.position, visited_ramp, crossed_gate, queued, damaged])
		if visited_ramp and crossed_gate and queued and damaged: enemy_routes_finished += 1
		game.enemies.erase(creature)
		creature.queue_free()
	for saved: Dictionary in saved_towers:
		var other: Dictionary = game.world.tower_pads[int(saved.index)]
		other.level = saved.level
		other.hp = saved.hp
		other.cooldown = saved.cooldown
	game.refresh_construction_navigation()
	game.phase = saved_phase
	await process_frame

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	await press(KEY_1)
	check(game.phase == "night" and game.tower_count() == 2, "Opening real card input must begin with two actual towers")
	game.phase = "day"
	game.scrap = 10000
	isolate()
	await process_frame
	camera_at(Vector3(0, 5, 0))
	await geometry_and_routes()
	await invalid_placements()
	# City positions are chosen freely, including the former reserved passage.
	var first: int = await build_with_input(Vector3(-4.5, 5, -.5), false, 60)
	await build_with_input(Vector3(.5, 5, 7.5), true, 60)
	await build_with_input(Vector3(.5, 5, 10.5), false, 60)
	check(game.world.tower_pads.size() >= 5,
		"Two adjacent towers may touch grid boundaries without reserving an extra gap")
	await aim_at(Vector3(10.5, 5, 6.5))
	await capture("valid-preview")
	await build_with_input(Vector3(10.5, 5, 6.5), true, 60)
	for _extra in 9:
		var point: Vector3 = free_point()
		check(point != Vector3.INF, "Continuous placement must retain free city space beyond twelve towers")
		if point == Vector3.INF: break
		await build_with_input(point, _extra % 2 == 0, 60)
	check(game.tower_count() > 12 and game.world.tower_pads.size() > 12,
		"Production free placement must exceed the previous twelve-tower slot limit")
	await frozen_and_poor()
	await tower_controls_and_combat(first)
	await enemy_routes_to_dynamic_tower(first)
	stand(Vector3(0, 5, 3.1))
	camera_at(Vector3(0, 5, 0))
	await capture("expanded-day")
	await capture("expanded-night", true)
	var previous_scene_id: int = game.get_instance_id()
	game.phase = "ended"
	await press(KEY_ENTER)
	# Restart retires real audio for .15 seconds before replacing the scene.
	# A fixed frame count can still inspect the old run on fast headless hosts.
	var restart_elapsed := 0.0
	while (current_scene == null or current_scene.get_instance_id() == previous_scene_id) and restart_elapsed < 12.0:
		await create_timer(.02).timeout
		restart_elapsed += .02
	check(current_scene != null and current_scene.get_instance_id() != previous_scene_id,
		"Actual Enter must replace the real scene before the restart deadline")
	if current_scene == null or current_scene.get_instance_id() == previous_scene_id:
		await finish()
		return
	game = current_scene as Node3D
	game.set_process(false)
	game.world.set_process(false)
	check(game.world.tower_pads.size() == 2 and game.tower_count() == 2 and game.scrap == 90,
		"Actual Enter restart must discard free towers and restore only the two opening towers")
	check(game.phase == "draft" and game.districts.plots.is_empty() and not game.construction.active,
		"A new run must reset districts, cards and continuous build mode")
	await finish()

func finish() -> void:
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_CASTLE_FREE_BUILD_", "OK" if failures.is_empty() else "FAILED", " checks=", checks,
		" free_towers=", built_indices.size(), " routes=", routes_finished, " enemy_routes=", enemy_routes_finished, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
