extends SceneTree


func _initialize() -> void:
	call_deferred("run")

func route_home(game: Node3D, start: Vector3) -> void:
	game.hero.position = start
	game.hero.position.y = game.outpost_height(start)
	game.plan_hero_path(Vector3(0, 5, 2))
	assert(not game.hero_path.is_empty())
	var cursor: Vector3 = game.hero.position
	for waypoint in game.hero_path:
		assert(game.can_traverse(cursor, waypoint))
		assert(game.outpost_walkable(waypoint))
		cursor = waypoint
	assert(cursor.distance_to(Vector3(0, 5, 2)) < 0.1)

func run() -> void:
	var game: Node3D = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	assert(game.choose_card(0))
	game.set_process(false)
	var districts: Node3D = game.districts
	game.phase = "day"
	game.scrap = 400
	for index in range(districts.plots.size()):
		var plot: Dictionary = districts.plots[index]
		assert(game.outpost_walkable(plot.position))
		assert(is_equal_approx(plot.position.y, 5.0))
		assert(is_equal_approx(plot.position.y, game.outpost_height(plot.position)))
		assert((plot.ring as MeshInstance3D).visible)
		game.hero.position = plot.position
		assert(districts.choose(index, "barracks" if index == 0 else "workshop").ok)
		assert((plot.model as Node3D).is_visible_in_tree())
		var bounds: AABB = districts.model_bounds(plot.model)
		var size: Vector3 = bounds.size * (plot.model as Node3D).scale
		assert(size.x <= 2.701 and size.z <= 2.701 and size.y <= 2.151)
		assert((plot.lamp as OmniLight3D).light_energy > 0.0)
	assert(not game.can_traverse(Vector3(12, 0, 0), Vector3(0, 5, 0)))
	assert(not game.can_traverse(Vector3(-12, 0, 0), Vector3(0, 5, 0)))
	assert(not game.can_traverse(Vector3(0, 0, -12), Vector3(0, 5, 0)))
	for start in [Vector3(-25, 0, 25), Vector3(25, 0, 25), Vector3(0, 0, 40)]:
		route_home(game, start)
	if DisplayServer.get_name() != "headless":
		game.hero.position = Vector3(0, 5, 1)
		game.camera.position = game.hero.position + Vector3(0, 25, 29)
		game.notice_time = 0.0
		game.phase_time = game.DAY_LENGTH
		game.world.set_night(false)
		game.world.night_mix = 0.0
		game.world.apply_lighting()
		game.hud.queue_redraw()
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build")
		assert(root.get_texture().get_image().save_png("res://build/nightfall-districts-day.png") == OK)
		game.phase = "night"
		game.phase_time = game.NIGHT_LENGTH
		game.world.set_night(true)
		game.world.night_mix = 1.0
		game.world.apply_lighting()
		game.hud.queue_redraw()
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png("res://build/nightfall-districts-night.png") == OK)
	print("NIGHTFALL_DISTRICTS_SCENE_OK real 5m plots, buildings <=2.7m, visible lamps, three home routes intact")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit()
