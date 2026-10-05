extends SceneTree
const Layout = preload("res://scripts/outpost_layout.gd")
## Exercise the real controller with buffered key events and real A* routes.
## The subclass only counts resolver work; movement stays in production code.
class MovementProbe:
	extends "res://scripts/nightfall.gd"
	var resolver_calls := 0
	var travelled_path := 0.0
	var unsafe_step := false
	func move_hero_position(next: Vector3) -> bool:
		resolver_calls += 1
		var before := hero.position
		var accepted := super(next)
		travelled_path += Vector2(hero.position.x-before.x, hero.position.z-before.z).length()
		if accepted and not can_traverse(before, hero.position): unsafe_step = true
		return accepted
	func reset_probe() -> void:
		resolver_calls = 0
		travelled_path = 0.0
		unsafe_step = false

var game: MovementProbe
var failures: Array[String] = []
var checks := 0
var maximum_calls := 0
var minimum_slide_ratio := INF
var routes_finished := 0

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 10: push_error(message)

func movement_keys(direction: Vector2) -> void:
	for pair in [[KEY_A, direction.x < 0], [KEY_D, direction.x > 0], [KEY_Z, direction.y < 0], [KEY_S, direction.y > 0]]:
		var event := InputEventKey.new()
		event.keycode = pair[0]
		event.physical_keycode = pair[0]
		event.pressed = pair[1]
		Input.parse_input_event(event)
	# parse_input_event() buffers events. Flush before moving so this test
	# measures the first requested frame rather than stale keyboard state.
	Input.flush_buffered_events()

func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x-b.x, a.z-b.z).length()

func reset_hero(point: Vector3) -> void:
	movement_keys(Vector2.ZERO)
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.move_goal = point
	game.hero_path.clear()
	game.hero_keyboard_active = false
	game.hero.moving = false
	game.hero.set_locomotion_velocity(Vector3.ZERO)

func frame_checks(before: Vector3, step: float, label: String) -> float:
	var budget: float = game.hero.speed*step
	var travelled := flat_distance(before, game.hero.position)
	maximum_calls = maxi(maximum_calls, game.resolver_calls)
	check(not game.unsafe_step and game.outpost_walkable(game.hero.position), label+": every accepted terrain step must remain outside solid walls")
	check(absf(game.hero.position.y-game.outpost_height(game.hero.position)) < .001, label+": the hero must follow the actual terrain height")
	check(travelled <= budget+.002 and game.travelled_path <= budget+.002, label+": contact correction must stay within this frame's travel budget")
	# Allow ordinary short-step retries, but a blocked contact must never
	# spend a frame resolving dozens of millimetre-sized accepted moves.
	var allowed_calls := ceili(budget/.02)+8
	check(game.resolver_calls <= allowed_calls, label+": bounded contact work (calls=%d, budget=%.4f)" % [game.resolver_calls, budget])
	return travelled

func keyboard_probe(point: Vector3, direction: Vector2, fps: float, free_tangent: bool, label: String) -> void:
	reset_hero(point)
	movement_keys(direction)
	var step := 1.0/fps
	var budget: float = game.hero.speed*step
	var minimum_ratio := INF
	for frame in ceili(fps*.5):
		var before := game.hero.position
		game.reset_probe()
		game.move_hero(step)
		var travelled := frame_checks(before, step, label)
		if free_tangent:
			var ratio := travelled/budget
			minimum_ratio = minf(minimum_ratio, ratio)
			check(ratio > .88, label+": a free exterior tangent must advance each frame (frame=%d, ratio=%.3f)" % [frame, ratio])
			check((game.hero.position.x-before.x)*direction.x >= -.0001, label+": exterior wall clearance must not reverse lateral input")
		if game.travelled_path > .02:
			check(travelled/game.travelled_path > .70, label+": accepted substeps must not undo one another within the frame")
	if free_tangent: minimum_slide_ratio = minf(minimum_slide_ratio, minimum_ratio)
	movement_keys(Vector2.ZERO)
	game.move_hero(step)

func route_probe(start: Vector3, destination: Vector3, fps: float, label: String) -> void:
	reset_hero(start)
	game.plan_hero_path(destination)
	check(not game.hero_path.is_empty(), label+": the route must use the real navigation planner")
	var goal: Vector3 = game.move_goal
	var step := 1.0/fps
	var frame_limit := ceili(fps*18.0)
	var reached := false
	for _frame in frame_limit:
		var before := game.hero.position
		game.reset_probe()
		game.move_hero(step)
		frame_checks(before, step, label)
		if game.hero_path.is_empty() and flat_distance(game.hero.position, goal) < .25:
			reached = true
			break
	check(reached, label+": exterior route must finish instead of being captured by the inner ramp clearance")
	check(flat_distance(goal, destination) < .02, label+": the reachable outer-ground destination must remain the requested point")
	if reached: routes_finished += 1

func run() -> void:
	game = MovementProbe.new()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	game.phase = "day"
	game.hero.speed = 8.4
	# These two exterior diagonals previously travelled .14 m of substeps but
	# advanced only .02 m on the third frame, including a backwards correction.
	for fps in [30.0, 60.0, 144.0]:
		for side in [-1.0, 1.0]:
			keyboard_probe(Vector3((Layout.FORT_INNER-.6)*side,0,8.2+Layout.EXPANSION_OFFSET), Vector2(side, -1), fps, true, "outer south wall %.0f fps side %.0f" % [fps, side])
			keyboard_probe(Vector3(4.0*side,0,10+Layout.EXPANSION_OFFSET), Vector2(side, -1), fps, true, "outer slope %.0f fps side %.0f" % [fps, side])
			# These genuine closed corners previously generated 70–83 resolver
			# calls in a single 60-FPS frame. Stopping at the wall is legitimate;
			# taking an unbounded series of tiny corrections is not.
			keyboard_probe(Vector3(3.95*side,0,8.2+Layout.EXPANSION_OFFSET), Vector2(-side, -1), fps, false, "blocked ramp corner %.0f fps side %.0f" % [fps, side])
			keyboard_probe(Vector3(4.0*side,0,10+Layout.EXPANSION_OFFSET), Vector2(-side, -1), fps, false, "blocked slope approach %.0f fps side %.0f" % [fps, side])
	var routes := [
		[Vector3(11.14113+Layout.EXPANSION_OFFSET,0,7.402695+Layout.EXPANSION_OFFSET), Vector3(-3.955423,0,11.92685+Layout.EXPANSION_OFFSET)],
		[Vector3(-9.305244,0,19.52816+Layout.EXPANSION_OFFSET), Vector3(4.283041,0,10.1293+Layout.EXPANSION_OFFSET)],
		[Vector3(2.518933, 5, -3.192418), Vector3(4.175524,0,18.20419+Layout.EXPANSION_OFFSET)],
	]
	# Captured production routes previously oscillated forever at x=±2.23.
	# Check both directions and slow/fast frame clocks through the south gate.
	for fps in [30.0, 60.0, 144.0]:
		for index in routes.size():
			for side in [-1.0, 1.0]:
				var start: Vector3 = routes[index][0]
				var goal: Vector3 = routes[index][1]
				start.x *= side
				goal.x *= side
				route_probe(start, goal, fps, "route %d %.0f fps side %.0f" % [index, fps, side])
	if DisplayServer.get_name() != "headless":
		# Hidden Forward+ execution still exercises the real terrain and unit
		# renderer; do not replace that validation with a headless OK line.
		reset_hero(Vector3(Layout.FORT_INNER-.6,0,8.2+Layout.EXPANSION_OFFSET))
		game.camera_follow = game.hero.position+Vector3(0, 25, 29)
		game.camera.position = game.camera_follow
		game.camera.look_at(game.camera_follow-Vector3(0, 25, 29))
		game.world.night_mix = 0.0
		game.world.set_night(false)
		game.hud.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var rendered: Image = root.get_texture().get_image()
		check(not rendered.is_empty(), "Hidden render must produce the actual outer high-ground image")
		DirAccess.make_dir_recursive_absolute("res://build")
		check(rendered.save_png("res://build/nightfall_outer_terrain_movement.png") == OK, "Save the actual outer high-ground image")
		print("NIGHTFALL_OUTER_TERRAIN_RENDER_OK")
	movement_keys(Vector2.ZERO)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	if failures.is_empty():
		print("NIGHTFALL_OUTER_TERRAIN_MOVEMENT_OK checks=", checks, " routes=", routes_finished, " min_slide_ratio=", minimum_slide_ratio, " max_calls=", maximum_calls)
		quit(0)
	else:
		print("NIGHTFALL_OUTER_TERRAIN_MOVEMENT_FAILED failures=", failures.size(), " routes=", routes_finished, " min_slide_ratio=", minimum_slide_ratio, " max_calls=", maximum_calls)
		quit(1)
