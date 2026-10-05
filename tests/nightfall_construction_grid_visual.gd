extends SceneTree
## Actual construction input, grid colors, paused visibility and hidden renderer.
const Layout := preload("res://scripts/outpost_layout.gd")
var game: Node3D
var checks := 0
var failures: Array[String] = []
var render_test := false
var observations: Dictionary = {}

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1920, 1200)
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

func frame() -> void:
	await process_frame
	if render_test: await RenderingServer.frame_post_draw

func aim_at(point: Vector3) -> void:
	point.y = Layout.terrain_height(point)
	var pixel: Vector2 = game.camera.unproject_position(point)
	var event := InputEventMouseMotion.new()
	event.position = pixel
	event.global_position = pixel
	root.push_input(event, true)
	await process_frame
	game._process(0.0)
	game.construction.tick(0.0)

func photograph(state: String) -> Image:
	if not render_test: return null
	game.hud.queue_redraw()
	for _frame in 4: await frame()
	var picture := root.get_texture().get_image()
	check(not picture.is_empty() and picture.get_size() == Vector2i(1920, 1200), "Capture the actual 1920x1200 renderer")
	check(picture.save_png("res://build/construction-grid-%s.png" % state) == OK, "Save actual construction " + state)
	return picture

func pixel_delta(a: Image, b: Image, point: Vector3) -> Vector3:
	var pixel := Vector2i(game.camera.unproject_position(point))
	var total := Vector3.ZERO
	var count := 0
	for y in range(pixel.y - 3, pixel.y + 4):
		for x in range(pixel.x - 3, pixel.x + 4):
			if x < 0 or y < 0 or x >= a.get_width() or y >= a.get_height(): continue
			var previous := a.get_pixel(x, y)
			var current := b.get_pixel(x, y)
			total += Vector3(current.r - previous.r, current.g - previous.g, current.b - previous.b)
			count += 1
	return total / maxf(float(count), 1.0)

func actual_color_comparison() -> void:
	var preview: Node3D = game.construction.grid_preview
	var state: Dictionary = game.construction.snapshot()
	var blocked_point := Vector3.INF
	var free_point := Vector3.INF
	for cell_state: Dictionary in state.cell_states:
		var rect: Rect2 = game.construction.Grid.cell_rect(cell_state.cell)
		var center := rect.get_center()
		var point := Vector3(center.x, Layout.FORT_HEIGHT + 0.07, center.y)
		if bool(cell_state.space_valid): free_point = point
		else: blocked_point = point
	check(blocked_point.is_finite() and free_point.is_finite(), "Production collision must expose both blocked and free footprint cells")
	if not blocked_point.is_finite() or not free_point.is_finite(): return
	var ghost_visible: bool = game.construction.ghost.visible
	var beacon_visible: bool = game.world.beacon.visible
	game.construction.ghost.visible = false
	# The opaque core occludes the blocked ground correctly; temporarily hiding
	# only its artwork allows this A/B to measure the actual red cell material.
	game.world.beacon.visible = false
	preview.hide()
	var off := await photograph("cell-overlay-off")
	preview.show()
	var on := await photograph("cell-overlay-on")
	var green_delta := pixel_delta(off, on, free_point)
	var red_delta := pixel_delta(off, on, blocked_point)
	observations["actual_free_cell_rgb_delta"] = [green_delta.x, green_delta.y, green_delta.z]
	observations["actual_blocked_cell_rgb_delta"] = [red_delta.x, red_delta.y, red_delta.z]
	check(green_delta.y > green_delta.x + 0.025, "Spatially free cells must actually render green on the terrain")
	check(red_delta.x > red_delta.y + 0.025, "A blocked cell must actually render red on the terrain")
	game.construction.ghost.visible = ghost_visible
	game.world.beacon.visible = beacon_visible

func stable_actual_frames() -> void:
	var ghost_visible: bool = game.construction.ghost.visible
	game.construction.ghost.visible = false
	var state: Dictionary = game.construction.snapshot()
	var point: Vector3 = state.point + Vector3.UP * 0.07
	var previous := await photograph("steady-cell")
	var max_delta := 0.0
	for _sample in 8:
		await frame()
		var current := root.get_texture().get_image()
		max_delta = maxf(max_delta, pixel_delta(previous, current, point).length())
		previous = current
	observations["steady_cell_max_rgb_step"] = max_delta
	check(max_delta < 0.005, "The actual grid cell stays steady across rendered frames without temporal glow or depth fighting")
	game.construction.ghost.visible = ghost_visible

func run() -> void:
	if render_test and DisplayServer.get_name() == "headless":
		push_error("Actual construction rendering requires a graphics driver")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	game.music.persist_settings = false
	check(game.choose_card(0), "Actual initial card enters the production game")
	game.phase = "day"
	game.notice_time = 0.0
	game.scrap = 10000
	game.hero.position = Vector3(0, 5, 6)
	game.move_goal = game.hero.position
	game.hero_path.clear()
	game.camera.size = 38.0
	game.camera.position = Vector3(0, 30, 29)
	game.camera.look_at(Vector3(0, 5, 0))
	game.camera_follow = game.camera.position
	game.world.ashfall.visible = false
	for particle in game.find_children("*", "GPUParticles3D", true, false): particle.visible = false
	game.effects.visible = false
	game.world.set_night(false)
	game.world.night_mix = 0.0
	game.world.apply_lighting()
	await press(KEY_Y)
	await aim_at(Vector3(7.5, 5, -7.5))
	var preview: Node3D = game.construction.grid_preview
	check(game.construction.active and is_instance_valid(preview), "Actual Y input starts the production grid preview")
	if not is_instance_valid(preview):
		await game.prepare_shutdown()
		game.queue_free()
		await process_frame
		await create_timer(0.5).timeout
		quit(1)
		return
	var state: Dictionary = game.construction.snapshot()
	check(bool(state.valid) and preview.visible and preview.current_cells.size() == 9 and preview.current_states.count(false) == 0,
		"Actual mouse input shows a valid nine-cell tower at its snapped location")
	check(not game.construction.ring.visible, "Legacy circular footprint remains hidden under grid placement")
	await photograph("day-valid")
	if render_test: await stable_actual_frames()
	var fills: int = preview.fill_rebuilds
	var borders: int = preview.border_rebuilds
	for _frame in 90: game.construction.tick(1.0 / 60.0)
	check(preview.fill_rebuilds == fills and preview.border_rebuilds == borders, "Stationary production frames must never rebuild the overlay")
	game.scrap = 0
	game.construction.tick(0.0)
	state = game.construction.snapshot()
	check(not bool(state.valid) and bool(state.space_valid) and preview.budget_limited and preview.current_states.count(false) == 0,
		"Real insufficient funds keep free cells green and show an amber budget outline")
	await photograph("budget-limited")
	game.scrap = 10000
	await aim_at(Vector3(3.5, 5, 0.5))
	state = game.construction.snapshot()
	check(not bool(state.space_valid) and preview.current_states.count(false) > 0 and preview.current_states.count(true) > 0,
		"Actual core overlap marks its cells red while preserving adjacent free cells")
	await photograph("mixed-core-overlap")
	if render_test: await actual_color_comparison()
	await aim_at(Vector3(7.5, 5, -7.5))
	game.world.set_night(true)
	game.world.night_mix = 1.0
	game.world.apply_lighting()
	await photograph("night-valid")
	game.phase = "paused"
	game._process(0.0)
	check(not preview.visible and not game.construction.ghost.visible, "Actual paused controller frames immediately hide every construction layer")
	game.phase = "draft"
	game._process(0.0)
	check(not preview.visible, "Actual card-selection frames keep the construction grid hidden")
	game.phase = "day"
	game._process(0.0)
	check(preview.visible and game.construction.active, "Returning to play resumes the same active construction grid")
	await press(KEY_ESCAPE)
	check(not game.construction.active and not preview.visible and game.phase == "day", "Escape cancels the preview before opening pause")
	await photograph("cancelled")
	await press(KEY_Y)
	game.world.set_night(false)
	game.world.night_mix = 0.0
	game.world.apply_lighting()
	var embankment_view := Vector3(14.5, Layout.terrain_height(Vector3(14.5, 0, 0.5)), 0.5)
	game.camera.size = 16.0
	game.camera.position = embankment_view + Vector3(0, 25, 29)
	game.camera.look_at(embankment_view)
	game.camera_follow = game.camera.position
	game.hud.visible = false
	await aim_at(Vector3(14.5, 0, 0.5))
	state = game.construction.snapshot()
	check(not bool(state.valid) and not bool(state.inside) and preview.visible and preview.current_states.count(true) == 0,
		"Actual exterior cursor shows red cells draped over the embankment")
	await photograph("outside-embankment")
	game.construction.cancel()
	check(not preview.visible, "Explicit cancellation hides all cached layers")
	observations["renderer"] = RenderingServer.get_current_rendering_method()
	observations["checks"] = checks
	observations["fill_rebuilds"] = preview.fill_rebuilds
	observations["border_rebuilds"] = preview.border_rebuilds
	observations["failures"] = failures
	if render_test:
		var file := FileAccess.open("res://build/construction-grid-visual.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(observations, "\t"))
		file.close()
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("NIGHTFALL_CONSTRUCTION_GRID_VISUAL_", "OK" if failures.is_empty() else "FAILED", " ", JSON.stringify(observations))
	quit(0 if failures.is_empty() else 1)
