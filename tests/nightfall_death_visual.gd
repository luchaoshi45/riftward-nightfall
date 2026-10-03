extends SceneTree
## Silent hidden-window render of actual imported death variants at gameplay scale.
var game: Node3D
var failures: Array[String] = []
var original_camera_basis: Basis

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message); push_error(message)

func target(threat: String, point: Vector3) -> BattleUnit:
	for attempt in 200:
		var enemy: BattleUnit = game.spawn_creature(true)
		if enemy.get_meta("threat", "") == threat:
			enemy.position = point
			enemy.position.y = game.outpost_height(point)
			enemy.armor = 0.0; enemy.shield = 0.0
			enemy.speed = 0.0; enemy.damage = 0.0; enemy.attack_timer = 1000.0
			enemy.face(game.hero.position, 1.0)
			enemy.moving = true; enemy.tick(.13)
			var eater := enemy.get_node_or_null("LightEater") as NightLightEater
			if eater: eater.tick(.20)
			return enemy
		game.enemies.erase(enemy); enemy.queue_free()
	check(false, "Find actual imported " + threat)
	return null

func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func tap(code: int) -> void:
	await key(code, true); await key(code, false)

func draw_frame(delta: float = 1.0 / 60.0) -> void:
	game.deaths.tick(delta, game.phase)
	game.hud.queue_redraw()
	await process_frame

func save_shot(path: String) -> void:
	game.hud.queue_redraw()
	await process_frame; await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	check(picture.get_width() >= 1000 and picture.get_height() >= 600,
		"Actual graphical frame uses gameplay resolution")
	check(picture.save_png(path) == OK, "Save actual rendered frame " + path)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Death visual verification requires a hidden graphical process")
		quit(1); return
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.world.set_process(false)
	game.music.persist_settings = false; game.music.set_muted(true)
	check(game.choose_card(0), "Actual opening draft enters the playable night")
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear(); game.deaths.clear()
	game.hero.position = Vector3(0, 5, 1.3)
	game.move_goal = game.hero.position; game.hero_path.clear()
	game.notice_time = 0.0; game.essence = 0
	game.camera.size = 31.0
	game.camera.position = game.hero.position + Vector3(0, 25, 29)
	game.camera_follow = game.camera.position
	original_camera_basis = game.camera.basis
	game.world.night_mix = 1.0; game.world.night_active = true
	game.world.apply_lighting(); game.world.follow_ashfall(game.hero.position)
	var variants: Array[String] = ["stalker", "breaker", "runner", "light_eater"]
	var positions: Array[Vector3] = [Vector3(-3.5, 5, 4.4), Vector3(-1.2, 5, 4.2), Vector3(1.3, 5, 4.4), Vector3(3.5, 5, 4.2)]
	var enemies: Array[BattleUnit] = []
	for index in variants.size():
		var enemy := target(variants[index], positions[index])
		if enemy: enemies.append(enemy)
	await process_frame
	await save_shot("res://build/death-before.png")
	for enemy in enemies: enemy.hurt(10000.0, game.hero)
	check(game.deaths.corpses.size() == 4 and game.kills >= 4,
		"All four actual enemy variants transfer their meshes after real lethal damage")
	await process_frame
	for index in 16: await draw_frame()
	check(game.camera.basis.is_equal_approx(original_camera_basis),
		"Collapse feedback leaves the gameplay camera direction fixed")
	await save_shot("res://build/death-collapse.png")
	game.camera.size = 15.0
	await save_shot("res://build/death-collapse-close.png")
	game.camera.size = 31.0
	for index in 38: await draw_frame()
	await save_shot("res://build/death-resting.png")
	game.camera.size = 15.0
	await save_shot("res://build/death-resting-close.png")
	game.camera.size = 31.0
	# Actual ESC inputs preserve the same corpse data and imported geometry.
	var corpse: Dictionary = game.deaths.corpses[0]
	var prior_time: float = corpse.time
	var prior_transform: Transform3D = corpse.node.transform
	await tap(KEY_ESCAPE)
	check(game.phase == "paused", "Real ESC enters pause during a collapse")
	for index in 12: await draw_frame(.25)
	check(corpse.time == prior_time and corpse.node.transform.is_equal_approx(prior_transform),
		"Actual paused frames preserve the corpse's clock and pose")
	await save_shot("res://build/death-paused.png")
	await tap(KEY_ESCAPE)
	check(game.phase == "night", "Real ESC resumes the same night")
	# The fast runner may already expire; retain the actual staggered variant lifetimes.
	var ash_time := 0.0
	for item in game.deaths.corpses: ash_time = maxf(ash_time, float(item.dissolve_start) + .30)
	while not game.deaths.corpses.is_empty() and float(game.deaths.corpses[0].time) < ash_time:
		await draw_frame()
	check(not game.deaths.corpses.is_empty(), "At the ash stage there are still visible original corpse nodes")
	await save_shot("res://build/death-embers.png")
	game.camera.size = 15.0
	await save_shot("res://build/death-embers-close.png")
	game.camera.size = 31.0
	# Unlike the headless Dummy rendering server, Vulkan exposes real instance data.
	var ash_corpse: Dictionary = game.deaths.corpses[0]
	for item in game.deaths.corpses:
		if float(item.duration) > float(ash_corpse.duration): ash_corpse = item
	check(ash_corpse.settled and ash_corpse.ash_started,
		"The actual ash screenshot contains a settled model and active ember instances")
	var body_before: Transform3D = ash_corpse.node.transform
	var ash_before: Transform3D = ash_corpse.ash_node.multimesh.get_instance_transform(0)
	var alpha_before: float = ash_corpse.alpha
	check(ash_corpse.ash_node.multimesh.get_instance_color(0).a > .01,
		"A real Vulkan ember instance is visible during its drift")
	for index in 4: await draw_frame(.02)
	await RenderingServer.frame_post_draw
	check(ash_corpse.node.transform.is_equal_approx(body_before) and ash_corpse.alpha < alpha_before,
		"Supported geometry stays still while its actual imported mesh fades")
	check(not ash_corpse.ash_node.multimesh.get_instance_transform(0).is_equal_approx(ash_before),
		"Vulkan ember instances continue moving after rigid geometry settles")
	await tap(KEY_ESCAPE)
	ash_before = ash_corpse.ash_node.multimesh.get_instance_transform(0)
	alpha_before = ash_corpse.alpha
	var ash_clock: float = ash_corpse.time
	for index in 3: await draw_frame(.5)
	await RenderingServer.frame_post_draw
	check(game.phase == "paused" and ash_corpse.time == ash_clock and ash_corpse.alpha == alpha_before and ash_corpse.ash_node.multimesh.get_instance_transform(0).is_equal_approx(ash_before),
		"Actual pause freezes a live GPU ash instance and the mesh fade")
	await tap(KEY_ESCAPE)
	# Preserve player agency while corpse animations are running.
	var player_start: Vector3 = game.hero.position
	await key(KEY_D, true)
	for index in 6:
		game.move_hero(1.0 / 60.0); game.hero.tick(1.0 / 60.0)
		await draw_frame()
	await key(KEY_D, false)
	check(game.hero.position.x > player_start.x + .6,
		"Real keyboard movement remains responsive throughout corpse decay")
	check(game.camera.basis.is_equal_approx(original_camera_basis), "Keyboard movement does not rotate the camera")
	game.deaths.tick(10.0, "night"); await process_frame
	check(game.deaths.corpses.is_empty(), "Rendered death meshes and ash expire after their finite lifetime")
	game.queue_free(); await process_frame; await process_frame
	await create_timer(.15).timeout
	if failures.is_empty(): print("NIGHTFALL_DEATH_VISUAL_OK graphical_four_variants gameplay_scale PBR_collapse ash_stage settled_rigid_active_GPU_ash paused_GPU_ash fixed_camera actual_ESC responsive_keyboard scene_exit")
	quit(0 if failures.is_empty() else 1)
