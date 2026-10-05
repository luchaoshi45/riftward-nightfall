extends SceneTree
## Real R input freezes and resumes every authored layer over real frames.
var game: Node3D
var failures: Array[String] = []

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1920, 1200)
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func tap_r() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_R; event.physical_keycode = KEY_R; event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.world.set_process(false)
	check(game.choose_card(0), "The production opening must enter playable night")
	for enemy in game.enemies: enemy.queue_free()
	game.enemies.clear()
	game.hero.position = Vector3(0, OutpostLayout.FORT_HEIGHT, 4)
	game.move_goal = game.hero.position; game.hero_path.clear()
	game.mana = 300.0; game.cooldowns[3] = 0.0
	var enemy: BattleUnit = game.spawn_creature(false)
	enemy.position = game.hero.position + Vector3(0, 0, 6)
	enemy.hp = 2000.0; enemy.max_hp = 2000.0; enemy.armor = 0.0
	var damage: float = 260.0 + float(game.run.stats.spell) * 1.2
	await tap_r()
	check(is_equal_approx(enemy.hp, 2000.0 - damage) and game.mana == 215.0 and is_equal_approx(game.cooldowns[3], 28.0 * game.run.cooldown_factor()), "The new artwork must preserve real R damage, cost and cooldown")
	var blast: Node3D = game.effects.get_node_or_null("LanternInferno")
	check(blast != null and blast.get_script().resource_path == "res://scripts/visual_inferno.gd", "Actual R must install its playable-time visual driver")
	if blast != null:
		var ground: MeshInstance3D = blast.get_node("InfernoGroundGlow")
		var tongues: Node3D = blast.get_node("InfernoFlameTongues")
		var boundary: MeshInstance3D = blast.get_node("InfernoDamageBoundary")
		var ground_material := ground.material_override as ShaderMaterial
		check(tongues.get_child_count() == 12, "R must retain its twelve authored flame tongues")
		check(absf((boundary.mesh as TorusMesh).outer_radius - (8.0 * float(game.run.stats.area) + .13)) < .001, "The outer rim must continue to describe the real damage radius")
		var count := 0
		for particles in blast.embers:
			count += particles.amount
			var process := particles.process_material as ParticleProcessMaterial
			var gradient: Gradient = process.color_ramp.gradient
			check(gradient.get_color(0).a == 0.0 and gradient.get_color(gradient.get_point_count() - 1).a == 0.0, "The larger embers must fade into and out of existence")
		check(count == 28, "R must use a bounded twenty-eight readable embers")
		await create_timer(.10).timeout
		for phase in ["paused", "draft"]:
			game.phase = phase
			await process_frame; await process_frame
			var age: float = blast.effect_age
			var scale_before := ground.scale
			var opacity: float = ground_material.get_shader_parameter("opacity")
			var shader_age: float = ground_material.get_shader_parameter("effect_age")
			await create_timer(.20).timeout
			for frame_index in 5: await process_frame
			check(is_instance_valid(blast) and blast.effect_age == age and ground.scale == scale_before, "Real paused/draft frames must freeze the R lifetime and expansion")
			check(ground_material.get_shader_parameter("effect_age") == shader_age and ground_material.get_shader_parameter("opacity") == opacity and not blast.animation.is_running(), "Real paused/draft frames must freeze the fire shader and its fade tween")
			for particles in blast.embers: check(particles.speed_scale == 0.0, "Real paused/draft frames must stop GPU ember simulation")
		game.phase = "night"
		var frozen_age: float = blast.effect_age
		await create_timer(.08).timeout
		check(blast.effect_age > frozen_age and blast.animation.is_running(), "Returning to play must resume visual time and the R tween")
		for particles in blast.embers: check(particles.speed_scale == 1.0, "Returning to play must resume the existing embers")
		await create_timer(1.1).timeout
		check(game.effects.get_node_or_null("LanternInferno") == null, "A resumed effect must expire and release all of its child layers")
	game.phase = "night"; game.mana = 300; game.cooldowns[3] = 0
	await tap_r()
	game.phase = "ended"
	await process_frame; await process_frame
	check(game.effects.get_node_or_null("LanternInferno") == null, "Ending a run must clear a live R effect immediately")
	await game.prepare_shutdown(); game.queue_free(); await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_INFERNO_STABILITY_", "OK" if failures.is_empty() else "FAILED", " real_R damage radius twelve_tongues embers actual_pause_frames resume cleanup")
	quit(0 if failures.is_empty() else 1)
