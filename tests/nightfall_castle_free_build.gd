extends SceneTree
## Production castle placement, real Y/F/mouse controls and live tower combat.
## Graphics: --windowed --position 10000,10000 --audio-driver Dummy -- --render-test.
const Layout = preload("res://scripts/outpost_layout.gd")
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
	# Avoid every suggested foundation independently of the validity result,
	# so successful construction is demonstrably away from fixed pad points.
	for zi in 19:
		for xi in 19:
			var point := Vector3(-10.8 + float(xi) * 1.2, 5, -10.8 + float(zi) * 1.2)
			if Vector2(point.x, point.z).length() < 4.1: continue
			if absf(point.x) < 2.1 and point.z > 3.5: continue
			var separated := true
			for pad: Dictionary in game.world.tower_pads:
				if ground_distance(point, pad.position) < 3.1: separated = false
			for plot: Dictionary in game.districts.plots:
				if ground_distance(point, plot.position) < 3.1: separated = false
			if separated and bool(game.construction.validity(point).valid): return point
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
	check(root.get_texture().get_image().save_png(output) == OK, "Save the actual castle %s frame" % state)
	print("CASTLE_FREE_BUILD_FRAME ", ProjectSettings.globalize_path(output))

func build_with_input(point: Vector3, use_mouse: bool, expected_cost: int) -> int:
	if not game.construction.active: await press(KEY_Y)
	check(game.construction.active, "Actual Y must enter the construction preview")
	await aim_at(point)
	var preview: Dictionary = game.construction.snapshot()
	check(bool(preview.active) and bool(preview.valid), "A separated castle point must produce a valid real preview")
	check(int(preview.cost) == expected_cost, "The preview must use the live workshop construction fee")
	check(ground_distance(preview.point, point) < .06, "The preview must stay under the actual terrain cursor")
	var balance: int = game.scrap
	var count: int = game.world.tower_pads.size()
	var towers: int = game.tower_count()
	if use_mouse: await click_world(point)
	else: await press(KEY_F)
	check(game.world.tower_pads.size() == count + 1, "Confirmation must append one new foundation rather than reuse a fixed plot")
	check(game.tower_count() == towers + 1 and game.scrap == balance - expected_cost,
		"A confirmed placement must build exactly one tower and pay exactly its real fee")
	if game.world.tower_pads.size() != count + 1: return -1
	var pad: Dictionary = game.world.tower_pads[count]
	check(int(pad.level) == 1 and is_equal_approx(float(pad.hp), 280.0) and is_instance_valid(pad.turret),
		"The appended foundation must contain a live level-one turret with 280 durability")
	check(ground_distance(pad.position, point) < .06 and absf(pad.position.y - 5.0) < .001,
		"The actual tower must occupy the chosen castle ground point")
	check(String(pad.zone) == "castle", "A free tower must be a castle tower")
	built_indices.append(count)
	# Repeating at the same point must be rejected without a duplicate or fee.
	var repeat_balance: int = game.scrap
	check(not game.build_tower_at(point), "The same point must reject overlapping repeat placement")
	check(game.scrap == repeat_balance and game.world.tower_pads.size() == count + 1,
		"Rejected repeat placement must retain both budget and foundation count")
	if game.construction.active: await press(KEY_Y)
	return count

func invalid_placements() -> void:
	var points: Array[Vector3] = [Vector3(30, 0, 0), Vector3(12, 5, 0), Vector3(0, 5, 0),
		Vector3(0, 5, 8), game.districts.plots[0].position, game.world.tower_pads[1].position]
	for point in points:
		var balance: int = game.scrap
		var count: int = game.world.tower_pads.size()
		var result: Dictionary = game.construction.validity(point)
		check(not bool(result.valid) and not String(result.reason).is_empty(), "A forbidden location needs an honest reason: %s" % point)
		check(not game.build_tower_at(point), "The production construction call must reject forbidden ground: %s" % point)
		check(game.scrap == balance and game.world.tower_pads.size() == count,
			"Failed placement must not consume budget or create a foundation")
	await press(KEY_Y)
	await aim_at(Vector3.ZERO)
	check(not bool(game.construction.snapshot().valid), "The core exclusion must also appear in the real cursor preview")
	await capture("rejected-preview")
	var balance: int = game.scrap
	var count: int = game.world.tower_pads.size()
	await press(KEY_F)
	await click_world(Vector3.ZERO)
	check(game.scrap == balance and game.world.tower_pads.size() == count, "Neither F nor left-click can confirm a rejected preview")
	await click_world(Vector3.ZERO, MOUSE_BUTTON_RIGHT)
	check(not game.construction.active and game.hero_path.is_empty(),
		"Right-click must cancel construction without issuing movement: active=%s phase=%s path=%d" % [game.construction.active, game.phase, game.hero_path.size()])
	await press(KEY_Y)
	await press(KEY_ESCAPE)
	check(not game.construction.active and game.phase == "day",
		"The first Escape must cancel construction and retain the active phase: active=%s phase=%s" % [game.construction.active, game.phase])

func geometry_and_routes() -> void:
	check(is_equal_approx(Layout.FORT_INNER, 13.0), "The castle's interior half-width must be doubled to 13 metres")
	check(game.world.tower_pads.size() == 12, "The opening must retain exactly twelve suggested foundations")
	for pad: Dictionary in game.world.tower_pads:
		check(absf(pad.position.x) <= 11.6 and absf(pad.position.z) <= 11.6 and absf(pad.position.y - 5.0) < .001,
			"Every original foundation must be inside the enlarged raised castle")
	check(game.world.tower_pads[1].position.distance_to(Vector3(5, 5, 10)) < .001 and
		game.world.tower_pads[2].position.distance_to(Vector3(-5, 5, 10)) < .001,
		"Opening east/west defenders must stand inside the enlarged southern wall")
	var home := Vector3(0, 5, 3.1)
	for start in [Vector3(30, 0, 0), Vector3(-30, 0, 0), Vector3(0, 0, -30)]:
		check(not game.can_traverse(start, home), "The enlarged east/west/north walls must preserve the sole southern entrance")
	check(game.can_traverse(Vector3(0, 0, 32), home), "The actual southern ramp must remain continuously traversable")
	for z in [14.5, 18.0, 22.0, 25.0]:
		var ramp := Vector3(0, game.outpost_height(Vector3(0, 0, z)), z)
		check(game.outpost_walkable(ramp), "The relocated southern ramp must remain walkable at z=%.1f" % z)
		var screen: Vector2 = game.camera.unproject_position(ramp)
		check(game.ground_point(screen).distance_to(ramp) < .035, "Combat cursor rays must resolve the relocated ramp at z=%.1f" % z)
	for start in [Vector3(-30, 0, 35), Vector3(30, 0, 35), Vector3(0, 0, 40)]:
		stand(start)
		game.plan_hero_path(home)
		travel_route(home, "return through expanded gate from %s" % start)
	stand(home)
	var destination := Vector3(25, 0, 0)
	game.plan_hero_path(destination)
	travel_route(destination, "exit through expanded gate to eastern wilderness")
	stand(Vector3(25, 0, 30))
	camera_at(Vector3(0, 5, 7))
	await click_world(home, MOUSE_BUTTON_RIGHT)
	check(game.hero_path.size() > 1, "A real right-click must route through the sole southern entrance")
	travel_route(home, "real right-click return")
	stand(home)
	camera_at(Vector3(0, 5, 0))

func travel_route(destination: Vector3, title: String) -> void:
	check(not game.hero_path.is_empty(), title + ": planner must supply an actual route")
	var reached := false
	var visited_ramp := false
	var stalled := 0
	for _frame in 1000:
		var before: Vector3 = game.hero.position
		game.move_hero(STEP)
		check(game.can_traverse(before, game.hero.position) and game.outpost_walkable(game.hero.position), title + ": no wall crossing")
		check(absf(game.hero.position.y - game.outpost_height(game.hero.position)) < .001, title + ": follow the authored terrain")
		if game.hero.position.z > 15.0 and game.hero.position.z < 24.5 and absf(game.hero.position.x) < 2.6: visited_ramp = true
		if ground_distance(before, game.hero.position) < .0001: stalled += 1
		else: stalled = 0
		if game.hero_path.is_empty() and ground_distance(game.hero.position, destination) < .25:
			reached = true
			break
		if stalled > 12: break
	check(reached and visited_ramp, title + ": actual movement must reach the target through the relocated ramp")
	if reached: routes_finished += 1

func frozen_and_poor() -> void:
	var point: Vector3 = free_point()
	check(point != Vector3.INF, "A valid spare position must remain for state refusal tests")
	if point == Vector3.INF: return
	var saved_balance: int = game.scrap
	game.scrap = 0
	var count: int = game.world.tower_pads.size()
	check(not bool(game.construction.validity(point).valid) and not game.build_tower_at(point), "Unaffordable construction must be rejected")
	await press(KEY_Y)
	await aim_at(point)
	await press(KEY_F)
	check(game.scrap == 0 and game.world.tower_pads.size() == count, "Actual unaffordable F must not create or pay for a tower")
	if game.construction.active: await press(KEY_Y)
	game.scrap = saved_balance
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "Escape outside construction must retain normal pause controls")
	await press(KEY_Y)
	check(not game.construction.active and not game.build_tower_at(point), "Pause must refuse mode entry and direct construction")
	check(game.scrap == saved_balance and game.world.tower_pads.size() == count, "Paused construction attempts must retain the budget")
	await press(KEY_ESCAPE)
	game.essence = game.run.memory_cost()
	game.collect_memory_upgrades()
	await press(KEY_Y)
	await press(KEY_V)
	game._process(0.0)
	check(game.phase == "draft" and game.construction.active and not game.construction.ghost.visible,
		"Real V must open cards and hide the retained construction preview")
	await press(KEY_Y)
	check(game.construction.active and not game.build_tower_at(point), "The card phase must refuse construction while retaining the selected mode")
	check(game.scrap == saved_balance and game.world.tower_pads.size() == count, "Card-phase refusal must retain the budget")
	await press(KEY_1)
	game._process(0.0)
	check(game.phase == "day" and game.construction.active and game.construction.ghost.visible,
		"A real card selection must return to daytime and resume the construction preview")
	await press(KEY_Y)

func tower_controls_and_combat(index: int) -> void:
	if index < 0: return
	var pad: Dictionary = game.world.tower_pads[index]
	stand(pad.position)
	var balance: int = game.scrap
	await press(KEY_F)
	check(int(pad.level) == 2 and game.scrap == balance - game.districts.tower_cost(50), "Nearby F must upgrade a dynamically built tower")
	balance = game.scrap
	await press(KEY_J)
	check(game.specializations.branch(pad) == "piercing" and game.scrap == balance - 45, "Actual J must apply a fixed-fee branch to the dynamic tower")
	balance = game.scrap
	await press(KEY_K)
	check(game.specializations.branch(pad) == "piercing" and game.scrap == balance, "Actual K cannot replace an already selected branch")
	for expected in ["breaker", "threat", "nearest"]:
		await press(KEY_G)
		check(String(pad.mode) == expected, "Actual G must retain all target modes on the dynamic tower")
	game.damage_tower(index, 135.0)
	var hp: float = pad.hp
	balance = game.scrap
	await press(KEY_H)
	check(is_equal_approx(float(pad.hp), hp + 100.0) and game.scrap == balance - game.districts.repair_cost(20), "Actual H must repair the dynamic tower at the workshop fee")
	game.phase = "night"
	stand(Vector3(30, 0, 35))
	var enemy: BattleUnit = game.spawn_creature(true, "stalker")
	enemy.position = pad.position + Vector3(1.0, 0, 0)
	enemy.attack_timer = 0.0
	var target: Dictionary = game.choose_enemy_target(enemy)
	check(String(target.kind) == "tower" and int(target.index) == index, "A normal monster must select the nearest dynamically built tower")
	game.update_creature(enemy, .1)
	check(enemy.attack_queued and String(enemy.get_meta("attack_target_kind", "")) == "tower", "The monster must actually queue an attack against the new tower")
	hp = pad.hp
	enemy.attack_windup = 0.0
	game.update_creature(enemy, .1)
	check(float(pad.hp) < hp, "The actual monster attack must damage the dynamic tower")
	game.hero.position = enemy.position + Vector3(.3, 0, 0)
	target = game.choose_enemy_target(enemy)
	check(String(target.kind) == "hero", "A nearer hero must still compete with a dynamically built tower for normal enemy attention")
	stand(Vector3(30, 0, 35))
	enemy.max_hp = 100000.0
	enemy.hp = enemy.max_hp
	for other: Dictionary in game.world.tower_pads: other.cooldown = 9999.0
	pad.cooldown = 0.0
	var enemy_hp: float = enemy.hp
	game.update_towers(.1)
	check(enemy.hp < enemy_hp and float(pad.cooldown) > 0.0, "The new tower must genuinely fire and reduce enemy health")
	pad.cooldown = 0.0
	enemy.hp = 1.0
	var chain: int = game.kill_chain
	game.update_towers(.1)
	check(not enemy.alive and game.kill_chain == chain, "Dynamic tower kills must retain correct non-hero combo attribution")
	game.damage_tower(index, 99999.0)
	check(int(pad.level) == 0 and game.specializations.branch(pad) == "standard", "Destruction must reset a dynamic tower and its specialization")
	await process_frame
	stand(pad.position)
	balance = game.scrap
	var count: int = game.world.tower_pads.size()
	check(not bool(game.construction.validity(pad.position).valid) and not game.build_tower_at(pad.position),
		"A destroyed free tower must retain its paid reconstruction foundation and refuse duplicate placement")
	check(game.scrap == balance and game.world.tower_pads.size() == count,
		"Rejected duplicate placement over a ruined free tower must not spend or append a foundation")
	await press(KEY_F)
	check(int(pad.level) == 1 and game.scrap == balance - game.districts.tower_cost(60) and game.world.tower_pads.size() == count,
		"Nearby F must rebuild a destroyed dynamic tower without appending a duplicate foundation")
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
	game.phase = saved_phase
	await process_frame

func placement_near_empty_foundation() -> void:
	await press(KEY_1)
	check(game.phase == "night", "The restarted run must accept its real opening card before placement regression")
	game.phase = "day"
	game.scrap = 1000
	isolate()
	stand(Vector3(0, 5, 3.1))
	camera_at(Vector3(0, 5, 0))
	var nearby_empty: Dictionary = game.world.tower_pads[0]
	check(int(nearby_empty.level) == 0 and ground_distance(nearby_empty.position, Vector3(10, 5, 6)) < .001,
		"The snap regression must begin with the untouched eastern empty foundation")
	# The second cursor is 3.1 m from the first live tower, but the nearby
	# authored foundation is only 2.6 m away. Its old centre must not replace
	# the valid chosen point during confirmation.
	var first: int = await build_with_input(Vector3(7.4, 5, 6), false, 60)
	var second: int = await build_with_input(Vector3(10.5, 5, 6), true, 60)
	check(first >= 0 and second >= 0 and first != second,
		"A green cursor beside a blocked empty foundation must still build a separate tower")
	check(int(nearby_empty.level) == 0 and ground_distance(nearby_empty.position, Vector3(10, 5, 6)) < .001,
		"Nearby free placement must neither build nor move the authored empty foundation")
	if second >= 0:
		check(ground_distance(game.world.tower_pads[second].position, Vector3(10.5, 5, 6)) < .01,
			"The near-foundation tower must stay at the valid real mouse point")
	# A cursor directly on a different legal suggestion still reuses that
	# foundation, and the GUI/unhandled-input pair may charge only once.
	var exact: Dictionary = game.world.tower_pads[5]
	check(int(exact.level) == 0, "The exact-position reuse regression needs an empty northern foundation")
	await press(KEY_Y)
	await aim_at(exact.position)
	var preview: Dictionary = game.construction.snapshot()
	check(bool(preview.valid) and ground_distance(preview.point, exact.position) < .01,
		"The actual cursor on a legal authored foundation must remain a valid preview")
	var balance: int = game.scrap
	var count: int = game.world.tower_pads.size()
	var towers: int = game.tower_count()
	await click_world(exact.position)
	check(game.world.tower_pads.size() == count and game.tower_count() == towers + 1,
		"Exact-position confirmation must reuse one foundation without appending a duplicate")
	check(int(exact.level) == 1 and is_instance_valid(exact.turret) and game.scrap == balance - 60,
		"Exact-position mouse confirmation must construct once and spend one real construction fee")
	check(not game.construction.active, "Successful exact-position confirmation must leave placement mode")
	balance = game.scrap
	await click_world(exact.position)
	check(int(exact.level) == 1 and game.scrap == balance and game.world.tower_pads.size() == count,
		"A repeated left click after confirmation must neither upgrade, charge nor append")

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	await press(KEY_1)
	check(game.phase == "night" and game.tower_count() == 2, "Real opening card input must start with two towers")
	game.phase = "day"
	game.scrap = 10000
	isolate()
	await process_frame
	camera_at(Vector3(0, 5, 0))
	await geometry_and_routes()
	await invalid_placements()
	# Fill valid authored suggestions before free placement can occupy their
	# spacing. The next real mouse confirmation must exceed twelve live towers.
	for index in 12:
		var pad: Dictionary = game.world.tower_pads[index]
		if int(pad.level) > 0: continue
		stand(pad.position)
		await press(KEY_F)
	check(game.tower_count() == 12, "Production F must build twelve valid original suggestions before free placement")
	var point: Vector3 = free_point()
	check(point != Vector3.INF, "Expanded castle must provide a non-fixed construction point")
	if point == Vector3.INF:
		await finish()
		return
	await press(KEY_Y)
	await aim_at(point)
	await capture("valid-preview")
	if game.construction.active: await press(KEY_Y)
	var first: int = await build_with_input(point, true, 60)
	check(game.tower_count() == 13 and game.world.tower_pads.size() == 13,
		"A freely confirmed thirteenth tower must exceed both the live-tower and foundation count of twelve")
	point = free_point()
	check(point != Vector3.INF, "A second separate construction point must remain")
	if point != Vector3.INF: await build_with_input(point, false, 60)
	stand(game.districts.plots[0].position)
	await press(KEY_2)
	check(String(game.districts.plots[0].kind) == "workshop" and int(game.districts.plots[0].level) == 1, "Actual 2 must build the workshop")
	point = free_point()
	if point != Vector3.INF: await build_with_input(point, true, 54)
	else: check(false, "A discounted third free position must remain")
	stand(game.districts.plots[0].position)
	await press(KEY_3)
	check(int(game.districts.plots[0].level) == 2, "Actual 3 must upgrade the workshop")
	point = free_point()
	if point != Vector3.INF: await build_with_input(point, false, 48)
	else: check(false, "A fourth free position must remain after the larger workshop discount")
	point = free_point()
	if point != Vector3.INF: await build_with_input(point, true, 48)
	else: check(false, "The expanded castle must retain room beyond twelve active towers")
	check(game.tower_count() > 12 and game.world.tower_pads.size() > 12, "Free construction must exceed twelve actual towers and twelve foundations")
	await frozen_and_poor()
	await tower_controls_and_combat(first)
	await enemy_routes_to_dynamic_tower(first)
	stand(Vector3(0, 5, 3.1))
	camera_at(Vector3(0, 5, 0))
	await capture("expanded-day")
	game.phase = "night"
	await capture("expanded-night", true)
	if render_test:
		point=free_point()
		check(point!=Vector3.INF,"The night preview must still have a valid castle position")
		if point!=Vector3.INF:
			await press(KEY_Y)
			await aim_at(point)
			check(game.construction.ghost.visible and bool(game.construction.snapshot().valid),"The night cursor must show a valid construction preview")
			await capture("night-preview",true)
			await press(KEY_Y)
	# Exercise the real new-run entry, then verify transient foundations and
	# budget cannot survive scene reload into a fresh draft.
	await game.prepare_shutdown()
	game.phase = "ended"
	await press(KEY_ENTER)
	for _frame in 6: await process_frame
	game = current_scene as Node3D
	game.set_process(false)
	game.world.set_process(false)
	check(game.world.tower_pads.size() == 12 and game.tower_count() == 2 and game.scrap == 90,
		"Actual Enter restart must discard all free towers and restore the opening budget")
	check(game.phase == "draft" and not game.construction.active and game.run.memory_level == 0,
		"The fresh run must reset cards and construction mode")
	await placement_near_empty_foundation()
	await finish()

func finish() -> void:
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	if failures.is_empty():
		print("NIGHTFALL_CASTLE_FREE_BUILD_OK checks=", checks, " free_towers=", built_indices.size(), " routes=", routes_finished, " enemy_routes=", enemy_routes_finished)
		quit(0)
	else:
		print("NIGHTFALL_CASTLE_FREE_BUILD_FAILED checks=", checks, " failures=", failures.size())
		quit(1)
