extends SceneTree
## Actual castle, production camera and fixed-step lighting; captures stay in build.
var game: Node3D
var failures: Array[String] = []
var observations: Dictionary = {}
var stage := "baseline"
var render_test := false
var stabilized := false

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_size = Vector2i(1920,1200)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="): stage = arg.trim_prefix("--stage=").validate_filename()
		if arg == "--render-test": render_test = true
		if arg == "--stabilized": stabilized = true
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func view(point: Vector3, size: float = 38.0) -> void:
	game.camera.size = size
	game.camera.position = point + Vector3(0,25,29)
	game.camera.look_at(point)
	game.camera_follow = game.camera.position

func frame() -> void:
	await process_frame
	if render_test: await RenderingServer.frame_post_draw

func photograph(name: String) -> Image:
	if not render_test: return null
	game.hud.queue_redraw()
	for _frame in 4: await frame()
	var picture: Image = root.get_texture().get_image()
	observations["render_size"] = [picture.get_width(),picture.get_height()]
	check(not picture.is_empty() and picture.get_width() == 1920 and picture.get_height() == 1200,
		"Capture must use the actual 1920x1200 renderer")
	check(picture.save_png("res://build/visual-%s-%s.png" % [stage,name]) == OK, "Save actual " + name)
	return picture

func frame_difference(a: Image, b: Image) -> float:
	var total := 0.0
	var count := 0
	# Fixed castle surfaces, outside HUD; coarse sampling keeps the test cheap.
	for y in range(360,850,8):
		for x in range(490,1400,8):
			var ca := a.get_pixel(x,y)
			var cb := b.get_pixel(x,y)
			total += absf(ca.r-cb.r)*.2126 + absf(ca.g-cb.g)*.7152 + absf(ca.b-cb.b)*.0722
			count += 1
	return total / float(count)

func lighting_samples() -> void:
	game.phase = "night"
	game.world.night_mix = 1.0
	game.world.night_active = true
	game.world.light_time = 0.0
	game.world.wave_warning = false
	game.world.apply_lighting()
	var previous: float = game.world.gate_lights[0].light_energy
	var previous_color: Color = game.world.gate_lights[0].light_color
	var max_jump := 0.0
	var max_color_jump := 0.0
	var peak := 0.0
	for index in 180:
		if index == 0: game.world.wave_warning = true
		if index == 60: game.world.gate_light_drain[0] = .85
		if index == 120:
			game.world.gate_light_drain[0] = 0.0
			game.world.wave_warning = false
		game.world._process(1.0/60.0)
		var energy: float = game.world.gate_lights[0].light_energy
		var color: Color = game.world.gate_lights[0].light_color
		max_jump = maxf(max_jump,absf(energy-previous))
		max_color_jump = maxf(max_color_jump,Vector3(color.r-previous_color.r,color.g-previous_color.g,color.b-previous_color.b).length())
		peak = maxf(peak,energy)
		previous = energy
		previous_color = color
	observations["warning_and_drain"] = {"max_energy_step_60fps":max_jump,"max_color_step":max_color_jump,"peak_energy":peak}
	if stabilized:
		check(max_jump < .5 and max_color_jump < .08,"Warning and drain must blend without an abrupt light/color step")
		var held_time: float = game.world.light_time
		var held_energy: float = game.world.beacon_light.light_energy
		game.phase = "paused"
		game.world._process(1.0)
		check(game.world.light_time == held_time and game.world.beacon_light.light_energy == held_energy,"Pause freezes world flicker and transitions")
	game.phase = "night"
	game.world.wave_warning = false
	game.world.gate_light_drain[0] = 0.0
	game.world._process(2.0)

func actual_frames() -> void:
	game.phase = "day"
	game.world.night_mix = 0.0
	game.world.set_night(false)
	await photograph("day")
	game.phase = "night"
	game.world.night_mix = 1.0
	game.world.set_night(true)
	await photograph("night")
	game.hud.visible = false
	var prior: Image = await photograph("still")
	var max_difference := 0.0
	for _sample in 8:
		game.world._process(1.0/30.0)
		for _frame in 2: await frame()
		var next: Image = root.get_texture().get_image()
		max_difference = maxf(max_difference,frame_difference(prior,next))
		prior = next
	observations["fixed_view_max_luminance_step"] = max_difference
	# A one-pixel orthographic translation, for aligned material inspection.
	game.camera.position.x += 38.0/1920.0
	await photograph("pan")
	view(Vector3(0,5,0),52.0)
	await photograph("wide")
	view(Vector3(33,0,32),38.0)
	game.hero.position = Vector3(33,0,32)
	game.world.follow_ashfall(game.hero.position)
	game.phase = "day"
	game.world.night_mix = 0.0
	game.world.set_night(false)
	await photograph("wilderness")
	view(Vector3(17,3,0),21.0)
	await photograph("embankment")
	view(Vector3(8,5,-4),12.0)
	await photograph("stone-close")
	view(Vector3(33,0,32),12.0)
	await photograph("close")
	game.hud.visible = true
	game.effects.visible = true
	game.phase = "night"
	game.world.night_mix = 1.0
	game.world.set_night(true)
	game.aim = game.hero.position + Vector3.RIGHT*5.0
	game.mana = game.max_mana
	game.cooldowns[3] = 0.0
	check(game.cast(3),"R still casts in the actual scene")
	game.skill_lights.tick(.08,game.phase)
	view(game.hero.position,31.0)
	await photograph("inferno")

func run() -> void:
	if render_test and DisplayServer.get_name() == "headless":
		push_error("Rendering validation requires an actual graphics driver")
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
	check(game.choose_card(0),"The production card enters the real game")
	game.notice_time = 0.0
	game.hero.position = Vector3(0,5,3.1)
	game.move_goal = game.hero.position
	game.world.follow_ashfall(game.hero.position)
	game.world.ashfall.visible = false
	game.effects.visible = false
	for child in game.find_children("*","GPUParticles3D",true,false): child.visible = false
	if stage == "baseline":
		for shader_material in game.world.terrain.find_children("*","MeshInstance3D",true,false):
			for index in shader_material.mesh.get_surface_count():
				var material := shader_material.get_active_material(index) as ShaderMaterial
				if material:
					var path := "res://build/visual-baseline/" + material.shader.resource_path.get_file()
					if FileAccess.file_exists(path): material.shader = load(path)
	game.scrap = 10000
	for point in [Vector3(-9,5,-8),Vector3(0,5,-8),Vector3(9,5,-8),Vector3(-9,5,0),Vector3(9,5,0),Vector3(-9,5,7),Vector3(9,5,7)]:
		check(game.build_tower_at(point),"Visual stress scene uses actual free-built towers")
	check(game.tower_count() == 9,"Nine live towers in the visual stress scene")
	var enemy: BattleUnit = game.spawn_creature(false,"stalker")
	enemy.position = Vector3(34.4,0,31.0)
	game.notice_time = 0.0
	view(Vector3(0,5,0))
	lighting_samples()
	if render_test: await actual_frames()
	observations["renderer"] = RenderingServer.get_current_rendering_method()
	observations["quality"] = {"msaa":root.msaa_3d,"camera_near":game.camera.near,"shadow_mode":game.world.sun.directional_shadow_mode}
	observations["stage"] = stage
	observations["failures"] = failures
	var file := FileAccess.open("res://build/visual-%s.json" % stage,FileAccess.WRITE)
	file.store_string(JSON.stringify(observations,"\t"))
	file.close()
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_VISUAL_STABILITY_", "OK" if failures.is_empty() else "FAILED", " ", JSON.stringify(observations))
	quit(0 if failures.is_empty() else 1)
