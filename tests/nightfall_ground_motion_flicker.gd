extends SceneTree
## Regression for the moving-camera ground shimmer caused by coplanar yard slabs.
## Graphics: --windowed --position 10000,10000 --audio-driver Dummy -- --render-test.
## Add --write-movie build/ground-walk.png --fixed-fps 30 for an internal recording.

const FORT_HEIGHT := 5.0
var game: Node3D
var checks := 0
var failures: Array[String] = []
var render_test := false
var motion_observations: Array[Dictionary] = []
var contact_frames: Array[Image] = []
const STEP := 1.0 / 30.0

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
	if condition:
		return
	failures.append(message)
	if failures.size() <= 20:
		push_error(message)

func frame(count: int = 1) -> void:
	for _index in count:
		await process_frame
		if render_test:
			await RenderingServer.frame_post_draw

func pose(target: Vector3, offset: Vector3 = Vector3(0, 25, 29)) -> void:
	game.camera.position = target + offset
	game.camera.look_at(target)
	game.camera_follow = game.camera.position

func capture(name: String) -> Image:
	if not render_test:
		return null
	var image: Image = root.get_texture().get_image()
	check(image.get_size() == Vector2i(1920, 1200), "Motion regression must use the production 1920x1200 viewport")
	check(image.save_png("res://build/ground-motion-%s.png" % name) == OK, "Motion frame should be saved")
	return image

func image_delta(first: Image, second: Image) -> Dictionary:
	if first == null or second == null:
		return {"changed": 0, "mean": 0.0, "max": 0.0}
	var changed := 0
	var total := 0.0
	var maximum := 0.0
	var samples := 0
	# Exclude HUD margins; this region follows the central yard and ramp.
	for y in range(280, 980, 4):
		for x in range(300, 1600, 4):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			var delta := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			total += delta
			maximum = maxf(maximum, delta)
			if delta > 0.02:
				changed += 1
			samples += 1
	return {"changed": changed, "mean": total / maxf(float(samples), 1.0), "max": maximum}

func verify_slab_clearance() -> void:
	var terrain: MeshInstance3D
	var slabs: Array[MeshInstance3D] = []
	for found in game.world.terrain.find_children("*", "MeshInstance3D", true, false):
		var mesh := found as MeshInstance3D
		if mesh.name.begins_with("Sculpted enlarged castle wasteland"):
			terrain = mesh
		elif mesh.name.begins_with("Fractured castle courtyard"):
			slabs.append(mesh)
	check(is_instance_valid(terrain), "The production castle terrain must be present")
	check(slabs.size() > 0, "The production courtyard slabs must be present")
	if not is_instance_valid(terrain) or slabs.is_empty():
		return
	var terrain_top := (terrain.global_transform * terrain.get_aabb()).end.y
	var slab_top := INF
	for slab in slabs:
		slab_top = minf(slab_top, (slab.global_transform * slab.get_aabb()).end.y)
	check(slab_top - terrain_top > 0.003, "Courtyard slabs need a positive depth gap above the terrain")
	check(slab_top - terrain_top < 0.02, "Courtyard slab lift must remain a shallow surface detail")

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await frame()

func sample_yard(image: Image) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	# Reproject the same interior ground locations into each moving frame.
	# These points are away from the moving hero, towers, core and slab edges.
	for z in [-5.7, -3.34, -0.98]:
		for x in [-8.1, -6.92, -4.56, -2.2]:
			var screen: Vector2 = game.camera.unproject_position(Vector3(x, 5.008, z))
			var ix := floori(screen.x)
			var iy := floori(screen.y)
			check(ix >= 1 and iy >= 1 and ix + 1 < image.get_width() and iy + 1 < image.get_height(), "Tracked ground must remain visible throughout walking")
			if ix < 1 or iy < 1 or ix + 1 >= image.get_width() or iy + 1 >= image.get_height():
				continue
			var sx := screen.x - ix
			var sy := screen.y - iy
			var color: Color = image.get_pixel(ix, iy).lerp(image.get_pixel(ix + 1, iy), sx).lerp(image.get_pixel(ix, iy + 1).lerp(image.get_pixel(ix + 1, iy + 1), sx), sy)
			values.append(color.get_luminance())
	return values

func walking_clip(name: String, start: Vector3, outward_key: int, inward_key: int, half_frames: int, night: bool, track_yard: bool) -> void:
	start.y = game.outpost_height(start)
	game.hero.position = start
	game.hero.speed = 8.4
	game.move_goal = start
	game.hero_path.clear()
	game.hero_keyboard_active = false
	game.world.night_mix = 1.0 if night else 0.0
	game.world.night_active = night
	game.world.apply_lighting()
	pose(start)
	await frame(6)
	var fixed_basis: Basis = game.camera.global_basis
	var first_values := PackedFloat32Array()
	if render_test and track_yard:
		first_values = sample_yard(root.get_texture().get_image())
	var maximum_step := 0.0
	var maximum_mean := 0.0
	var distance := 0.0
	var previous_values := first_values
	for direction in 2:
		var code: int = outward_key if direction == 0 else inward_key
		await key(code, true)
		for index in half_frames:
			var before: Vector3 = game.hero.position
			# Production key handling, collision/substeps, locomotion and camera
			# follow all run. Pause freezes combat and lighting transitions.
			game.move_hero(STEP)
			game.hero.tick(STEP)
			game._process(STEP)
			distance += Vector2(game.hero.position.x - before.x, game.hero.position.z - before.z).length()
			check(game.hero.position.distance_to(before) > .01, "Walking recording must advance the real hero every frame")
			check(game.camera.global_basis.is_equal_approx(fixed_basis), "Walking must preserve the production fixed camera angle")
			await frame()
			if render_test:
				var picture: Image = root.get_texture().get_image()
				if track_yard:
					var values := sample_yard(picture)
					var total := 0.0
					for point in mini(values.size(), previous_values.size()):
						var change := absf(values[point] - previous_values[point])
						total += change
						maximum_step = maxf(maximum_step, change)
					maximum_mean = maxf(maximum_mean, total / maxf(1.0, values.size()))
					previous_values = values
				if index == 0 or index == half_frames - 1:
					check(picture.save_png("res://build/ground-walk-%s-%d-%d.png" % [name, direction, index]) == OK, "Walking evidence should be saved")
					contact_frames.append(picture)
		await key(code, false)
	check(distance > float(half_frames) * STEP * 8.4 * 1.8, "Walking must cover both directions at real speed")
	check(Vector2(game.hero.position.x - start.x, game.hero.position.z - start.z).length() < .1, "Walking must return through the actual movement controller")
	if render_test and track_yard:
		check(maximum_mean < .025, "World-aligned moving ground must avoid broad brightness jumps (mean=%.6f)" % maximum_mean)
	motion_observations.append({"clip": name, "frames": half_frames * 2, "distance": distance, "ground_samples_per_frame": 12 if render_test and track_yard else 0, "max_ground_step": maximum_step if render_test and track_yard else null, "max_ground_mean": maximum_mean if render_test and track_yard else null})

func save_contact_sheet() -> void:
	if not render_test:
		return
	var sheet := Image.create(1920, 1200, false, Image.FORMAT_RGB8)
	for index in mini(16, contact_frames.size()):
		var thumbnail: Image = contact_frames[index].duplicate()
		thumbnail.convert(Image.FORMAT_RGB8)
		thumbnail.resize(480, 300, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(thumbnail, Rect2i(0, 0, 480, 300), Vector2i(index % 4 * 480, index / 4 * 300))
	check(sheet.save_png("res://build/ground-walk-contact.png") == OK, "Continuous walking contact sheet should be saved")

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frame(2)
	game.set_process(false)
	game.world.set_process(false)
	game.phase = "paused"
	game.hud.visible = false
	game.effects.visible = false
	game.world.ashfall.visible = false
	for particle in game.find_children("*", "GPUParticles3D", true, false):
		particle.visible = false
	game.world.night_mix = 0.0
	game.world.night_active = false
	game.world.apply_lighting()
	verify_slab_clearance()
	pose(Vector3(0, FORT_HEIGHT, 0))
	await frame(6)
	var before: Image = await capture("before")
	# Simulate a short walk by moving the orthographic camera across the yard,
	# then return to the exact original pose. A stable surface must reproduce
	# the same pixels after the camera motion.
	pose(Vector3(0.22, FORT_HEIGHT, -0.18))
	await frame(3)
	await capture("during")
	pose(Vector3(0, FORT_HEIGHT, 0))
	await frame(6)
	var after: Image = await capture("after")
	var result := image_delta(before, after)
	check(int(result.changed) < 900, "Returning from a short walk must not produce a large ground shimmer (changed=%d)" % int(result.changed))
	check(float(result.mean) < 0.012, "Returning from a short walk must keep the ground stable (mean=%.5f)" % float(result.mean))
	# The return-pose check above is supplementary: identical poses alone do
	# not prove motion stability. Walk continuously in the actual controller.
	await walking_clip("day-yard", Vector3(-8, 0, 5), KEY_D, KEY_A, 24, false, true)
	await walking_clip("night-yard", Vector3(-8, 0, 5), KEY_D, KEY_A, 24, true, true)
	await walking_clip("day-ramp", Vector3(0, 0, 14.5), KEY_S, KEY_Z, 40, false, false)
	await walking_clip("night-ramp", Vector3(0, 0, 14.5), KEY_S, KEY_Z, 40, true, false)
	save_contact_sheet()

	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_GROUND_MOTION_FLICKER_", "OK" if failures.is_empty() else "FAILED",
		" checks=", checks, " changed=", int(result.changed), " mean=", float(result.mean),
		" max=", float(result.max))
	print("GROUND_WALK_OBSERVATIONS ", JSON.stringify(motion_observations))
	quit(0 if failures.is_empty() else 1)
