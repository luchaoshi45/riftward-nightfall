extends SceneTree
## Production ground colour regression using the real scene and native swatches.
## Run with an actual backend, hidden/offscreen, and --audio-driver Dummy.
## Optional --compare-candidate also captures the prior unencoded palette.
const HOME := Vector3(0, 5, 3.1)
const SHADER_PATH := "res://assets/shaders/wasteland.gdshader"
const ALBEDO_ASSIGNMENT := "ALBEDO=mix(earth,rock,cliff);"
const ENCODING_CALL := "if (OUTPUT_IS_SRGB) { ALBEDO=encode_linear_color(ALBEDO); }"
const SAMPLE_POINTS := {
	"yard_soil_a": Vector3(-7.08, 5.0, 0.0),
	"yard_soil_b": Vector3(-4.72, 5.0, 5.90),
	"yard_concrete": Vector3(-5.90, 5.008, 4.72),
	"yard_fracture": Vector3(-4.72, 5.008, 4.72),
	"outer_soil": Vector3(-20.0, 0.0, 8.0),
	"ramp_soil": Vector3(0.0, 0.0, 19.0),
}
var game: Node3D
var soil: MeshInstance3D
var original_override: Material
var unencoded: ShaderMaterial
var production_source := ""
var compare_candidate := false
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}

func _initialize() -> void:
	compare_candidate = "--compare-candidate" in OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.size = Vector2i(1920, 1200)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_size = Vector2i(1920, 1200)
		root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failures.append(message)
	push_error(message)

func frames(count: int = 8) -> void:
	for index in count:
		await process_frame
		await RenderingServer.frame_post_draw

func rgb(color: Color) -> Array:
	return [color.r, color.g, color.b]

func pixel_average(picture: Image, centre: Vector2i, radius: int = 2) -> Color:
	var total := Color(0.0, 0.0, 0.0, 0.0)
	var samples := 0
	for y in range(centre.y - radius, centre.y + radius + 1):
		for x in range(centre.x - radius, centre.x + radius + 1):
			if x >= 0 and y >= 0 and x < picture.get_width() and y < picture.get_height():
				total += picture.get_pixel(x, y)
				samples += 1
	return total / maxf(1.0, samples)

func scene_capture(label: String) -> void:
	await frames()
	var picture: Image = root.get_texture().get_image()
	check(picture.get_size() == Vector2i(1920, 1200), "Actual scene must render at 1920x1200")
	check(picture.save_png("res://build/ground-colour-%s.png" % label) == OK, "Save actual scene %s" % label)
	var samples: Dictionary = {}
	for name: String in SAMPLE_POINTS:
		var point: Vector3 = SAMPLE_POINTS[name]
		if name in ["outer_soil", "ramp_soil"]:
			point.y = game.world.terrain_height(point)
		var screen: Vector2 = game.camera.unproject_position(point)
		var centre := Vector2i(roundi(screen.x), roundi(screen.y))
		check(centre.x >= 2 and centre.x < picture.get_width() - 2 and centre.y >= 2 and centre.y < picture.get_height() - 2,
			"%s must remain in the captured viewport" % name)
		var color := pixel_average(picture, centre)
		samples[name] = {"world": [point.x, point.y, point.z], "pixel": [centre.x, centre.y],
			"mean_rgb": rgb(color), "mean_luminance": color.get_luminance()}
	observations[label] = samples

func world_pairs(night: bool) -> void:
	game.world.night_mix = 1.0 if night else 0.0
	game.world.night_active = night
	game.world.follow_ashfall(HOME)
	game.world.apply_lighting()
	var label := "night" if night else "day"
	soil.material_override = original_override
	await scene_capture(label + "-production")
	soil.material_override = null
	check(soil.get_active_material(0) is StandardMaterial3D,
		"Native A/B must use the actual imported soil StandardMaterial3D")
	await scene_capture(label + "-native")
	soil.material_override = original_override
	if compare_candidate:
		soil.material_override = unencoded
		await scene_capture(label + "-baseline")
		soil.material_override = original_override
		await scene_capture(label + "-candidate")
	# These known scene regions verify local illumination and material scope;
	# they do not require the entire image to be constant or equally bright.
	var production: Dictionary = observations[label + "-production"]
	var native: Dictionary = observations[label + "-native"]
	for name in ["yard_concrete", "yard_fracture"]:
		check(production[name].mean_rgb == native[name].mean_rgb,
			"Changing only the soil material must preserve the fixed %s %s sample" % [label, name])
	if night:
		check(production.yard_soil_a.mean_luminance > production.outer_soil.mean_luminance
			and production.yard_soil_b.mean_luminance > production.outer_soil.mean_luminance,
			"The known locally lit courtyard soil must remain more readable than the unlit outer soil")

func constant_shader(color: Color, production: bool) -> ShaderMaterial:
	var shader := Shader.new()
	if production:
		# Keep the real shader's output path. Only replace the scene-derived
		# palette and lighting, so missing production encoding fails this test.
		shader.code = production_source.replace("render_mode diffuse_burley, specular_schlick_ggx;", "render_mode unshaded;")
		shader.code = shader.code.replace("shader_type spatial;", "shader_type spatial;\nuniform vec3 linear_color;")
		shader.code = shader.code.replace(ALBEDO_ASSIGNMENT, "ALBEDO=linear_color;")
	else:
		shader.code = "shader_type spatial;\nrender_mode unshaded;\nuniform vec3 linear_color;\nvoid fragment() { ALBEDO=linear_color; }\n"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("linear_color", Vector3(color.r, color.g, color.b))
	return material

func reference_swatches() -> void:
	# An independent viewport removes scene lighting, fog, exposure and geometry.
	# Columns: native StandardMaterial, hardcoded linear shader, production shader.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 360)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.0
	environment.environment = env
	stage.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	camera.position = Vector3(0.0, 0.0, 5.0)
	stage.add_child(camera)
	camera.current = true
	var values: Array[Color] = [Color(.051, .055, .047), Color(.075, .072, .061), Color(.13, .14, .13)]
	for row in values.size():
		for column in 3:
			var instance := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(1.7, .7)
			instance.mesh = quad
			instance.position = Vector3(float(column - 1) * 2.0, float(1 - row) * .9, 0.0)
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if column == 0:
				var native := StandardMaterial3D.new()
				native.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				native.albedo_color = values[row].linear_to_srgb()
				instance.material_override = native
			else:
				instance.material_override = constant_shader(values[row], column == 2)
			stage.add_child(instance)
	await frames(12)
	var picture: Image = viewport.get_texture().get_image()
	check(picture.get_size() == Vector2i(720, 360), "Reference swatches must render at their actual viewport size")
	check(picture.save_png("res://build/ground-colour-reference.png") == OK, "Save controlled native/linear/production swatches")
	var rows: Array[Dictionary] = []
	for row in values.size():
		var colors: Array[Color] = []
		for column in 3:
			var point := Vector3(float(column - 1) * 2.0, float(1 - row) * .9, 0.0)
			var screen := camera.unproject_position(point)
			colors.append(pixel_average(picture, Vector2i(roundi(screen.x), roundi(screen.y)), 4))
		var difference := Vector3(colors[0].r - colors[2].r, colors[0].g - colors[2].g, colors[0].b - colors[2].b).abs()
		check(maxf(difference.x, maxf(difference.y, difference.z)) < 3.0 / 255.0,
			"Production unshaded output should match its native StandardMaterial reference within RGB quantization")
		rows.append({"linear_input": rgb(values[row]), "native_rgb": rgb(colors[0]),
			"raw_shader_rgb": rgb(colors[1]), "production_shader_rgb": rgb(colors[2]), "native_production_difference": [difference.x, difference.y, difference.z]})
	observations["reference_swatches"] = rows
	viewport.queue_free()
	await process_frame

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Ground colour diagnosis requires an actual rendering backend")
		quit(1)
		return
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	game.phase = "paused"
	game.hud.visible = false
	game.effects.visible = false
	for particle in game.find_children("*", "GPUParticles3D", true, false):
		particle.visible = false
	game.hero.position = HOME
	game.camera.size = 31.0
	game.camera.position = HOME + Vector3(0, 25, 29)
	game.camera.look_at(HOME)
	game.camera_follow = game.camera.position
	for found in game.world.terrain.find_children("*", "MeshInstance3D", true, false):
		if String(found.name).begins_with("Sculpted enlarged castle wasteland"):
			soil = found
			break
	check(is_instance_valid(soil), "A/B must target the actual production soil surface")
	if is_instance_valid(soil):
		original_override = soil.material_override
		check(original_override is ShaderMaterial, "Baseline must retain the production wasteland shader")
		if original_override is ShaderMaterial:
			check((original_override as ShaderMaterial).shader.resource_path == SHADER_PATH,
				"The scene must bind the exact production wasteland shader under regression")
		production_source = FileAccess.get_file_as_string(SHADER_PATH)
		check(production_source.count(ALBEDO_ASSIGNMENT) == 1, "Controlled swatches replace only the single production ALBEDO palette")
		check(production_source.count("render_mode diffuse_burley, specular_schlick_ggx;") == 1,
			"Controlled swatches must replace the actual production lighting mode")
		if compare_candidate:
			check(production_source.count(ENCODING_CALL) == 1, "Diagnostic baseline removes only the actual production encoding call")
			var shader := Shader.new()
			shader.code = production_source.replace(ENCODING_CALL, "")
			unencoded = ShaderMaterial.new()
			unencoded.shader = shader
		await world_pairs(false)
		await world_pairs(true)
		await reference_swatches()
	observations["backend"] = RenderingServer.get_current_rendering_method()
	var output := FileAccess.open("res://build/ground-colour-observations.json", FileAccess.WRITE)
	check(output != null, "Open local colour diagnosis observations")
	observations["checks"] = checks
	observations["failures"] = failures
	if output:
		output.store_string(JSON.stringify(observations, "\t"))
		output.close()
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_GROUND_COLOR_SPACE_", "OK" if failures.is_empty() else "FAILED", " checks=", checks)
	print("GROUND_COLOR_OBSERVATIONS ", JSON.stringify(observations))
	quit(0 if failures.is_empty() else 1)
