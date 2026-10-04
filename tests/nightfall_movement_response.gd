extends SceneTree
## Real input events with a fixed simulation clock: rendering frame rate cannot
## inflate movement distance or hide one-frame input / animation delay.
const STEP := 1.0 / 60.0
const MOVEMENT_KEYS := [KEY_Z, KEY_A, KEY_S, KEY_D]
var game: Node3D
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func tap(code: int) -> void:
	await key(code, true)
	await key(code, false)

func reset_hero(point: Vector3, heading: Vector3 = Vector3.RIGHT) -> void:
	game.phase = "day"
	game.phase_time = 90.0
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.move_goal = point
	game.hero_path.clear()
	game.hero_keyboard_active = false
	game.hero.moving = false
	game.hero.set_locomotion_velocity(Vector3.ZERO)
	game.hero.face(point + heading, 1.0)
	game.hero.tick(1.0)
	game.hero.attack_timer = 1000.0

func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func face_alignment(direction: Vector3) -> float:
	var facing: Vector3 = game.hero.visual.global_basis.z
	facing.y = 0.0
	return facing.normalized().dot(direction.normalized())

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	# Vertical camera follow used to share the slow horizontal response. On the
	# steep ramp that left the fixed-angle camera almost a metre behind the
	# hero, even though the simulated movement stayed at full speed.
	var start_position: Vector3 = game.hero.position
	var camera_ramp_z := 15.5
	var ramp_position := Vector3(0, game.outpost_height(Vector3(0, 0, camera_ramp_z)), camera_ramp_z)
	game.hero.position = ramp_position
	game.camera_follow = ramp_position + Vector3(0, 25, 29)
	var camera_basis: Basis = game.camera.global_transform.basis
	var vertical_lag := 0.0
	for frame in 30:
		camera_ramp_z -= game.hero.speed * STEP
		game.hero.position = Vector3(0, game.outpost_height(Vector3(0, 0, camera_ramp_z)), camera_ramp_z)
		game._process(STEP)
		vertical_lag = maxf(vertical_lag, absf(game.camera_follow.y - (game.hero.position.y + 25.0)))
	check(vertical_lag < .35,
		"The fixed camera must catch a moving hero's raised-ramp height without visible vertical drag")
	var horizontal_lag := absf(game.camera_follow.z - (game.hero.position.z + 29.0))
	check(horizontal_lag > .8 and horizontal_lag < 1.6,
		"Raised-ramp camera follow must keep its deliberate horizontal glide")
	check(game.camera.global_transform.basis.is_equal_approx(camera_basis),
		"Raised-ramp camera follow must preserve the fixed view direction")
	game.hero.position = start_position
	game.camera_follow = game.hero.position + Vector3(0, 25, 29)
	await tap(KEY_1)
	check(game.phase == "night", "Real card input must start the playable scene")
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	await process_frame
	check(is_equal_approx(game.hero.speed, 8.4 + float(game.run.stats.speed)), "The playable hero must retain the new 8.4 m/s base speed after choosing a card")
	# A route node may carry a stale elevated Y while its ground position is
	# already reached. Completion must use the walkable plane so the hero does
	# not wait forever at the high-ground edge.
	reset_hero(Vector3(0, 0, 15.5))
	var reached_ground: Vector3 = game.hero.position
	game.hero_path = PackedVector3Array([reached_ground + Vector3(0, 1.4, 0)])
	game.move_goal = reached_ground
	game.simulate(STEP)
	check(game.hero_path.is_empty(), "A raised-ramp waypoint must complete by ground distance")
	var measured_speed: float = game.hero.speed
	var directions := [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3(1, 0, -1).normalized(), Vector3(-1, 0, -1).normalized(), Vector3(1, 0, 1).normalized(), Vector3(-1, 0, 1).normalized()]
	var combinations := [[KEY_D], [KEY_A], [KEY_Z], [KEY_S], [KEY_D, KEY_Z], [KEY_A, KEY_Z], [KEY_D, KEY_S], [KEY_A, KEY_S]]
	for i in directions.size():
		reset_hero(Vector3(35, 0, 35), directions[i])
		var start: Vector3 = game.hero.position
		for code in combinations[i]: await key(code, true)
		game.simulate(STEP)
		check(game.hero.moving and game.hero.gait_was_moving and game.hero.gait_blend > .01, "Direction %d: the first movement frame must also animate" % i)
		for frame in 59: game.simulate(STEP)
		var travel: Vector3 = game.hero.position - start
		travel.y = 0.0
		check(absf(travel.length() - measured_speed) < .025, "Direction %d: one second must move %.2f m, not faster diagonally" % [i, measured_speed])
		check(travel.normalized().dot(directions[i]) > .999, "Direction %d: actual Z/A/S/D input must move in the requested direction" % i)
		for code in combinations[i]: await key(code, false)
		var release_position: Vector3 = game.hero.position
		game.simulate(STEP)
		check(flat_distance(release_position, game.hero.position) < .0001, "Direction %d: releasing keys must stop on the next frame instead of finishing a stale 2 m target" % i)
		check(not game.hero.moving and not game.hero.gait_was_moving and game.hero.locomotion_velocity.length() < .001, "Direction %d: the stop frame must report zero motion to animation" % i)
		for frame in 30: game.simulate(STEP)
		check(flat_distance(release_position, game.hero.position) < .0001, "Direction %d: there must be no delayed keyboard drift" % i)
	print("MOVEMENT_EIGHT_DIRECTIONS_AND_RELEASE_OK speed=", measured_speed)

	# A sub-centimetre per-frame displacement must still turn the visible model.
	reset_hero(Vector3(35, 0, 35), Vector3.FORWARD)
	await key(KEY_D, true)
	game.simulate(1.0 / 144.0)
	check(face_alignment(Vector3.RIGHT) > .01, "At 144 fps, the first lateral frame must turn; facing may not depend on displacement > 0.1 m")
	for frame in 11: game.simulate(1.0 / 144.0)
	check(face_alignment(Vector3.RIGHT) > .90, "At 144 fps, a 90-degree change must face the new travel direction within 0.084 s")
	await key(KEY_D, false)
	game.simulate(STEP)
	reset_hero(Vector3(35, 0, 35), Vector3.LEFT)
	await key(KEY_D, true)
	for frame in 15: game.simulate(1.0 / 144.0)
	check(face_alignment(Vector3.RIGHT) > .75, "A reversal must stop visibly skating backward within 0.105 s")
	await key(KEY_D, false)
	game.simulate(STEP)
	print("MOVEMENT_HIGH_FPS_FACING_CHECKED")

	# Continuous wall checks must survive the increased speed and corner inputs.
	reset_hero(Vector3(5.7, 0, 5.7), Vector3(1, 0, 1).normalized())
	await key(KEY_D, true)
	await key(KEY_S, true)
	for frame in 45:
		var previous: Vector3 = game.hero.position
		game.simulate(STEP)
		check(game.outpost_walkable(game.hero.position) and game.can_traverse(previous, game.hero.position), "Fast diagonal keyboard movement must not pass through a fortress corner")
	check(game.hero.position.x < 6.5 and game.hero.position.z < 6.5, "The fortress corner must stop diagonal movement at the actual walls")
	await key(KEY_D, false)
	await key(KEY_S, false)
	game.simulate(STEP)
	print("MOVEMENT_FORTRESS_CORNER_OK")

	# Near the raised ramp's side wall, a diagonal input must slide along the
	# free downhill axis instead of freezing both axes at the corner.
	reset_hero(Vector3(2.45, 0, 10.5), Vector3(1, 0, 1).normalized())
	await key(KEY_D, true)
	await key(KEY_S, true)
	var ramp_start: Vector3=game.hero.position
	for frame in 45: game.simulate(STEP)
	check(game.hero.position.x<2.25 and game.hero.position.z>ramp_start.z+2.0, "Raised-ramp diagonal movement must keep the hero mesh clear of the side wall while sliding")
	check(flat_distance(game.hero.position,ramp_start)>5.7, "Raised-ramp wall sliding must preserve near-full movement speed")
	await key(KEY_D, false)
	await key(KEY_S, false)
	game.simulate(STEP)
	reset_hero(Vector3(-2.45, 0, 10.5), Vector3(-1, 0, 1).normalized())
	await key(KEY_A, true)
	await key(KEY_S, true)
	var left_ramp_start: Vector3=game.hero.position
	for frame in 45: game.simulate(STEP)
	check(game.hero.position.x>-2.25 and game.hero.position.z>left_ramp_start.z+2.0,
		"Mirrored raised-ramp movement must keep the hero mesh clear of the west side wall")
	check(flat_distance(game.hero.position,left_ramp_start)>5.7,
		"Mirrored raised-ramp wall sliding must preserve near-full movement speed")
	await key(KEY_A, false)
	await key(KEY_S, false)
	game.simulate(STEP)
	print("MOVEMENT_RAISED_RAMP_SLIDE_OK")

	# The raised courtyard's east/west and north retaining walls need the same
	# visual clearance as the ramp. A diagonal move along the east wall should
	# keep advancing on the courtyard plane instead of scraping the wall edge.
	reset_hero(Vector3(6.0, 0, -4.0), Vector3(1, 0, 1).normalized())
	await key(KEY_D, true)
	await key(KEY_S, true)
	var courtyard_wall_start: Vector3 = game.hero.position
	for frame in 45: game.simulate(STEP)
	check(game.hero.position.x < game.HERO_FORT_SAFE_EDGE + .03,
		"Raised courtyard movement must keep the hero mesh clear of the east retaining wall")
	check(game.hero.position.z > courtyard_wall_start.z + 2.0,
		"Raised courtyard wall sliding must preserve forward travel")
	check(flat_distance(game.hero.position,courtyard_wall_start) > 5.7,
		"Raised courtyard wall sliding must preserve near-full movement speed")
	await key(KEY_D, false)
	await key(KEY_S, false)
	game.simulate(STEP)
	reset_hero(Vector3(-4.0, 0, -6.0), Vector3(1, 0, -1).normalized())
	await key(KEY_D, true)
	await key(KEY_Z, true)
	var north_wall_start: Vector3 = game.hero.position
	for frame in 45: game.simulate(STEP)
	check(game.hero.position.z > -game.HERO_FORT_SAFE_EDGE - .03,
		"Raised courtyard movement must keep the hero mesh clear of the north retaining wall")
	check(game.hero.position.x > north_wall_start.x + 2.0,
		"Raised courtyard north-wall sliding must preserve lateral travel")
	await key(KEY_D, false)
	await key(KEY_Z, false)
	game.simulate(STEP)
	print("MOVEMENT_RAISED_COURTYARD_WALLS_OK")

	# Entering the ramp straight on must ease the visual clearance in over
	# several frames instead of snapping sideways at the platform lip.
	reset_hero(Vector3(2.45, 0, 7.55), Vector3.FORWARD)
	await key(KEY_S, true)
	var lip_previous: Vector3 = game.hero.position
	var lip_min_step := INF
	var lip_max_side_step := 0.0
	for frame in 24:
		game.simulate(STEP)
		var lip_step: Vector3 = game.hero.position-lip_previous
		lip_min_step=minf(lip_min_step,flat_distance(lip_previous,game.hero.position))
		lip_max_side_step=maxf(lip_max_side_step,absf(lip_step.x))
		check(flat_distance(lip_previous,game.hero.position)>.05,
			"Straight raised-ramp entry must keep advancing every frame")
		lip_previous=game.hero.position
	check(game.hero.position.z>10.0 and game.hero.position.x<2.25,
		"Straight raised-ramp entry must reach the safe centre corridor")
	check(lip_max_side_step<.10,
		"Raised-ramp lip clearance must ease in without a sideways snap")
	await key(KEY_S, false)
	game.simulate(STEP)
	print("MOVEMENT_RAISED_RAMP_LIP_SMOOTH_OK min_step=",lip_min_step," max_side_step=",lip_max_side_step)

	# Once the hero leaves the ramp, the visual clearance must release so
	# horizontal movement on the outer ground is not still constrained by it.
	reset_hero(Vector3(2.2, 0, 18.45), Vector3(1, 0, 1).normalized())
	await key(KEY_D, true)
	await key(KEY_S, true)
	var ramp_exit_start: Vector3 = game.hero.position
	for frame in 24: game.simulate(STEP)
	check(game.hero.position.z>20.5 and game.hero.position.x>3.2,
		"Leaving the raised ramp must release the side clearance on outer ground")
	check(flat_distance(game.hero.position,ramp_exit_start)>3.0,
		"Leaving the raised ramp must preserve diagonal movement")
	await key(KEY_D, false)
	await key(KEY_S, false)
	game.simulate(STEP)
	print("MOVEMENT_RAISED_RAMP_EXIT_OK")

	# At the elevated platform lip, the side wall and retaining wall form an
	# L-shaped corner. Holding the diagonal toward the ramp must ease inward
	# and continue downhill instead of stopping at that single corner.
	reset_hero(Vector3(2.45, 0, 7.7), Vector3(1, 0, 1).normalized())
	await key(KEY_D, true)
	await key(KEY_S, true)
	var ramp_lip_start: Vector3 = game.hero.position
	for frame in 30: game.simulate(STEP)
	check(game.hero.position.x < 2.61 and game.hero.position.z > ramp_lip_start.z + 2.0,
		"Diagonal movement at the raised-ramp lip must enter the ramp instead of sticking at the corner")
	check(flat_distance(game.hero.position, ramp_lip_start) > 2.4,
		"Raised-ramp lip escape must preserve continuous travel")
	await key(KEY_D, false)
	await key(KEY_S, false)
	game.simulate(STEP)
	print("MOVEMENT_RAISED_RAMP_LIP_OK")

	# A slower render cadence must still advance smoothly up the raised ramp.
	# The controller uses short terrain substeps so one long frame cannot
	# reject the whole move when it reaches the ramp's wall corner.
	reset_hero(Vector3(0, 0, 18.8), Vector3.FORWARD)
	await key(KEY_Z, true)
	var low_fps_min_step:=INF
	var low_fps_zero_frames:=0
	var low_fps_previous: Vector3=game.hero.position
	for frame in 75:
		game.simulate(1.0/30.0)
		var low_fps_step: float=flat_distance(low_fps_previous,game.hero.position)
		low_fps_min_step=minf(low_fps_min_step,low_fps_step)
		if low_fps_step<.20:low_fps_zero_frames+=1
		check(absf(game.hero.position.y-game.outpost_height(game.hero.position))<.001,
			"Low-FPS raised-ramp movement must stay on the terrain profile")
		low_fps_previous=game.hero.position
	check(low_fps_min_step>.24,"Low-FPS raised-ramp movement must not lose a frame to corner collision")
	check(low_fps_zero_frames<=1,"Low-FPS raised-ramp movement may not stall for consecutive frames")
	await key(KEY_Z, false)
	game.simulate(STEP)
	print("MOVEMENT_RAISED_RAMP_LOW_FPS_OK min_step=",low_fps_min_step)

	# Actual right-click input retains its autonomous route after the user has
	# released movement keys, and must enter by the only southern gateway.
	reset_hero(Vector3(10, 0, 25))
	await key(KEY_D, true)
	game.simulate(STEP)
	check(game.hero_keyboard_active, "The right-click transition must start during a real held keyboard move")
	var home := Vector3(0, 5, 3.1)
	game.camera.size = 48.0
	game.camera.position = Vector3(5, 25, 43)
	game.camera.look_at(Vector3(5, 0, 14))
	var screen: Vector2 = game.camera.unproject_position(home)
	check(game.ground_point(screen).distance_to(home) < .15, "The real click ray must resolve the elevated courtyard accurately")
	# The ramp is where a flat-ground approximation used to miss the visible
	# surface by over a metre. Test several actual slope points so right-click
	# movement starts from the location under the cursor instead of correcting
	# late and appearing to stick near the high ground.
	for ramp_z in [9.0, 12.0, 15.0]:
		var ramp_point := Vector3(0, game.outpost_height(Vector3(0, 0, ramp_z)), ramp_z)
		var ramp_screen: Vector2 = game.camera.unproject_position(ramp_point)
		check(game.ground_point(ramp_screen).distance_to(ramp_point) < .025,
			"The real click ray must converge on the raised ramp at z=%.1f" % ramp_z)
	var click := InputEventMouseButton.new()
	# Input.parse_input_event receives window pixels. Headless Godot uses a
	# tiny physical window even though the stretched viewport is 1440 x 900.
	var window_screen: Vector2 = root.get_final_transform() * screen
	click.button_index = MOUSE_BUTTON_RIGHT
	click.button_mask = MOUSE_BUTTON_MASK_RIGHT
	click.position = window_screen
	click.global_position = window_screen
	click.pressed = true
	Input.parse_input_event(click)
	await process_frame
	click.pressed = false
	click.button_mask = 0
	Input.parse_input_event(click)
	await process_frame
	check(game.hero_path.size() > 1, "The actual right-click must create a detour through the south gate")
	await key(KEY_D, false)
	check(not game.hero_keyboard_active, "A right-click must own the route so releasing the prior key cannot erase it")
	var visited_south_road := false
	for frame in 600:
		var previous: Vector3 = game.hero.position
		game.simulate(STEP)
		check(game.can_traverse(previous, game.hero.position), "Click-to-move must never clip fortress walls")
		if game.hero.position.z > 8.2 and game.hero.position.z < 18.0 and absf(game.hero.position.x) < 2.6: visited_south_road = true
		if flat_distance(game.hero.position, home) < .2: break
	check(visited_south_road and game.hero.position.distance_to(home) < .3, "The high-speed right-click route must actually reach the raised home through the south gate")
	await key(KEY_D, true)
	game.simulate(STEP)
	check(game.hero_path.is_empty() and game.hero_keyboard_active, "Keyboard movement must immediately override the click route")
	await key(KEY_D, false)
	game.simulate(STEP)
	print("MOVEMENT_REAL_RIGHT_CLICK_SOUTH_GATE_OK")

	reset_hero(Vector3(35, 0, 35))
	await key(KEY_D, true)
	for frame in 10: game.simulate(STEP)
	await tap(KEY_ESCAPE)
	check(game.phase == "paused", "Escape must pause while movement is held")
	var pause_position: Vector3 = game.hero.position
	game.simulate(.5)
	check(game.hero.position.is_equal_approx(pause_position), "A paused simulation must not move the hero")
	await key(KEY_D, false)
	await tap(KEY_ESCAPE)
	check(game.phase == "day", "Escape must resume the original phase")
	game.simulate(STEP)
	check(game.hero.position.is_equal_approx(pause_position) and not game.hero.moving, "Releasing movement while paused must not resume a stale destination")
	print("MOVEMENT_PAUSE_RELEASE_RESUME_OK")

	reset_hero(Vector3(35, 0, 35))
	game.mana = game.max_mana
	for slot in game.cooldowns.size(): game.cooldowns[slot] = 0.0
	game.aim = game.hero.position - Vector3.RIGHT * 8.0
	await key(KEY_D, true)
	var cast_start: Vector3 = game.hero.position
	for frame in 60:
		game.simulate(STEP)
		if frame in [10, 20, 30]:
			var code: int = KEY_Q if frame == 10 else (KEY_W if frame == 20 else KEY_R)
			var slot: int = 0 if frame == 10 else (1 if frame == 20 else 3)
			var yaw: float = game.hero.visual.rotation.y
			await tap(code)
			check(game.cooldowns[slot] > 0.0, "Actual moving skill input must release Q/W/R")
			check(absf(wrapf(game.hero.visual.rotation.y - yaw, -PI, PI)) < .001, "Casting opposite travel direction must not steal the moving character's heading")
	check(absf(flat_distance(cast_start, game.hero.position) - measured_speed) < .025, "Q/W/R animations must not reduce one-second movement distance")
	await key(KEY_D, false)
	game.simulate(STEP)
	print("MOVEMENT_CAST_SPEED_AND_HEADING_OK")

	for code in MOVEMENT_KEYS: await key(code, false)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	if failures.is_empty():
		print("NIGHTFALL_MOVEMENT_RESPONSE_OK")
		quit(0)
	else:
		print("NIGHTFALL_MOVEMENT_RESPONSE_FAILED count=", failures.size())
		quit(1)
