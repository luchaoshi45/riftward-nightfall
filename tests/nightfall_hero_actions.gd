extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var hero := BattleUnit.new()
	stage.add_child(hero)
	hero.setup("hero", 0)
	assert(hero.elbows.size() == 2)
	hero.tick(.01)
	var resting_arm := hero.arms[1].rotation
	hero.play_action("attack", Vector3.FORWARD)
	assert(hero.hero_action == "attack")
	var greatest_arm := 0.0
	var smallest_elbow := 0.0
	for i in 45:
		hero.tick(1.0 / 60.0)
		greatest_arm = maxf(greatest_arm, hero.arms[1].rotation.distance_to(resting_arm))
		smallest_elbow = minf(smallest_elbow, hero.elbows[1].rotation.x)
		assert(minf(hero.hero_boot_lowest(0), hero.hero_boot_lowest(1)) > .018)
	assert(greatest_arm > .9 and smallest_elbow < -.60, "Attack must draw, swing and recover the sword through the elbow")
	assert(hero.hero_action == "" and hero.arms[1].rotation.distance_to(resting_arm) < .01)
	hero.play_action("inferno", Vector3(1, 0, 0))
	hero.tick(.06)
	assert(hero.arms[0].rotation.z < -.65 and hero.arms[1].rotation.z > .65, "R must open both arms in the immediate burst frame")
	assert(hero.elbows[0].rotation.x < -.5 and hero.elbows[1].rotation.x < -.5)
	hero.play_action("attack", Vector3.FORWARD)
	assert(hero.hero_action == "inferno", "Automatic attacks must not interrupt the ultimate recoil")
	for i in 65: hero.tick(1.0 / 60.0)
	assert(hero.hero_action == "" and hero.hero_action_weight == 0.0)
	assert(hero.arms[1].rotation.distance_to(resting_arm) < .01 and absf(hero.elbows[1].rotation.x + .12) < .01)
	hero.moving = true
	hero.set_locomotion_velocity(Vector3.FORWARD * hero.speed)
	hero.face(hero.position + Vector3.FORWARD, 1.0)
	var moving_heading := hero.visual.rotation.y
	hero.play_action("attack", Vector3.RIGHT)
	assert(absf(wrapf(hero.visual.rotation.y - moving_heading, -PI, PI)) < .001, "Moving attacks must not snap the travel heading")
	hero.tick(.10)
	assert(hero.gait_blend > .40 and absf(hero.hero_upper_body.rotation.y) < .75)
	print("NIGHTFALL_HERO_ACTIONS_OK sword_arc=", greatest_arm, " elbow=", smallest_elbow, " R_spread_and_return=pass moving_heading=pass")
	if DisplayServer.get_name() == "headless":
		quit()
		return
	await capture_poses(stage, hero)
	await capture_game_distance()
	quit()

func capture_poses(stage: Node3D, hero: BattleUnit) -> void:
	hero.speed = 8.4
	hero.position = Vector3.ZERO
	hero.visual.rotation.y = 0
	hero.gait_turn = 0
	hero.gait_turn_target = 0
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202720")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c8d7dc")
	environment.environment.ambient_light_energy = .48
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, -35, 0)
	light.light_energy = 1.7
	stage.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(18, 18)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("373e34")
	floor_mesh.material_override = floor_mat
	stage.add_child(floor_mesh)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.5
	camera.position = Vector3(4.5, 2.6, 5)
	stage.add_child(camera)
	camera.look_at(Vector3(0, 1.2, 0))
	camera.current = true
	hero.hero_action = ""
	hero.moving = true
	hero.gait_blend = 1.0
	hero.set_locomotion_velocity(Vector3(0, 0, hero.speed))
	for i in 6:
		hero.gait_phase = (.04 + float(i)/6.0) * TAU
		hero.tick(0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/hero-motion-run-%d.png" % i)
	# Validate rendered poses during actual 8.4 m/s root travel. The camera tracks
	# translation only; animation is ticked consecutively rather than posing
	# disconnected stills that could hide foot sliding or cadence problems.
	hero.gait_phase = 0
	for i in 48:
		hero.position.z += hero.speed / 60.0
		hero.tick(1.0 / 60.0)
		camera.position = hero.position + Vector3(4.5, 2.6, 5)
		camera.look_at(hero.position + Vector3(0, 1.2, 0))
		await process_frame
		if i % 8 == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/hero-motion-travel-%d.png" % (i/8))
	hero.position = Vector3.ZERO
	camera.position = Vector3(4.5, 2.6, 5)
	camera.look_at(Vector3(0, 1.2, 0))
	hero.moving = false
	hero.gait_blend = 0
	hero.set_locomotion_velocity(Vector3.ZERO)
	for action in ["attack", "inferno"]:
		for i in 4:
			hero.play_action(action, Vector3.ZERO)
			hero.hero_action_time = [0.06, .18, .35, .65][i]
			hero.tick(0.0)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/hero-motion-%s-%d.png" % [action, i])
			hero.hero_action = ""
	print("NIGHTFALL_HERO_ACTIONS_CLOSE_VISUAL_OK")

func capture_game_distance() -> void:
	current_scene.queue_free()
	await process_frame
	var game: Node3D = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	assert(game.choose_card(0))
	game.set_process(false)
	game.hud.queue_redraw()
	var hero: BattleUnit = game.hero
	hero.position = Vector3(-4, 5, 2)
	game.move_goal = Vector3(4, 5, 2)
	game.camera.current = true
	for i in 48:
		game.simulate(1.0 / 60.0)
		game.camera.position = hero.position + Vector3(0, 25, 29)
		game.camera.look_at(hero.position)
		await process_frame
		if i % 8 == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/hero-fast-run-game-%d.png" % (i / 8))
	print("NIGHTFALL_HERO_ACTIONS_GAME_DISTANCE_VISUAL_OK actual_8.4_mps=pass")
