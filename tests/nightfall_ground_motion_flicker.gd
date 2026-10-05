extends SceneTree
## Regression for the moving-camera ground shimmer caused by coplanar yard slabs.
## Graphics: --windowed --position 10000,10000 --audio-driver Dummy -- --render-test.

const FORT_HEIGHT := 5.0
var game: Node3D
var checks := 0
var failures: Array[String] = []
var render_test := false

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

	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_GROUND_MOTION_FLICKER_", "OK" if failures.is_empty() else "FAILED",
		" checks=", checks, " changed=", int(result.changed), " mean=", float(result.mean),
		" max=", float(result.max))
	quit(0 if failures.is_empty() else 1)
