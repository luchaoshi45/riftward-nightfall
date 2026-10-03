extends SceneTree
## Isolated Vulkan material study; never changes the playable scene or saves.

const MATERIAL_LABELS := ["Weathered concrete", "Concrete fracture"]
var stage: Node3D
var ground: Node3D
var camera: Camera3D
var environment: Environment
var sun: DirectionalLight3D
var lantern: OmniLight3D
var masonry: Array[Dictionary] = []
var shader: Shader

func _initialize() -> void:
	call_deferred("run")

func photograph(name: String) -> Image:
	for i in 5: await process_frame
	await create_timer(0.18).timeout
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	assert(not image.is_empty())
	assert(image.save_png("res://build/masonry-stage-" + name + ".png") == OK)
	return image

func stone_view(target: Vector3, offset: Vector3, size: float) -> void:
	camera.size = size
	camera.position = target + offset
	camera.look_at(target, Vector3.UP)

func use_weathering(enabled: bool) -> void:
	for surface in masonry:
		(surface.node as MeshInstance3D).set_surface_override_material(surface.index,
			surface.weathered if enabled else null)

func illuminate(night: bool) -> void:
	environment.ambient_light_color = Color("697587") if night else Color("b8b3a5")
	environment.ambient_light_energy = 0.028 if night else 0.56
	environment.fog_light_color = Color("090f1a") if night else Color("565b57")
	environment.fog_density = 0.020 if night else 0.010
	sun.light_color = Color("587090") if night else Color("e4c6a7")
	sun.light_energy = 0.018 if night else 0.86
	lantern.light_energy = 8.2 if night else 1.4

func mean_value(image: Image, region: Rect2i) -> float:
	var sum := 0.0
	var count := 0
	for y in range(region.position.y, region.end.y, 4):
		for x in range(region.position.x, region.end.x, 4):
			var pixel := image.get_pixel(x, y)
			sum += pixel.r + pixel.g + pixel.b
			count += 3
	return sum / max(count, 1)

func measure_frames(weathered: bool) -> float:
	use_weathering(weathered)
	for i in 8:
		await process_frame
		await RenderingServer.frame_post_draw
	var began := Time.get_ticks_usec()
	for i in 48:
		await process_frame
		await RenderingServer.frame_post_draw
	return (Time.get_ticks_usec() - began) / 48000.0

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Masonry stage requires hidden graphical Vulkan rendering")
		quit(1)
		return
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	ground = (load("res://assets/models/outpost_ground.glb") as PackedScene).instantiate()
	stage.add_child(ground)
	shader = load("res://assets/shaders/outpost_masonry.gdshader") as Shader
	assert(shader != null)
	for found in ground.find_children("*", "MeshInstance3D", true, false):
		var node := found as MeshInstance3D
		for index in node.mesh.get_surface_count():
			var material := node.mesh.surface_get_material(index) as StandardMaterial3D
			if material == null: continue
			if material.resource_name in MATERIAL_LABELS:
				var weathered := ShaderMaterial.new()
				weathered.shader = shader
				weathered.set_shader_parameter("base_color", material.albedo_color)
				masonry.append({"node": node, "index": index, "weathered": weathered})
			elif material.resource_name == "Ash compacted earth":
				var ash := ShaderMaterial.new()
				ash.shader = load("res://assets/shaders/wasteland.gdshader")
				node.set_surface_override_material(index, ash)
	assert(masonry.size() == 2, "Both imported joined concrete materials must be recognised")
	assert(masonry[0].weathered.get_shader_parameter("base_color") != masonry[1].weathered.get_shader_parameter("base_color"))
	var world_environment := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("03060b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.ssao_enabled = true
	environment.ssao_radius = 1.7
	environment.ssao_intensity = 1.55
	environment.fog_enabled = true
	environment.fog_height_density = 0.04
	world_environment.environment = environment
	stage.add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -42, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100.0
	stage.add_child(sun)
	lantern = OmniLight3D.new()
	lantern.position = Vector3(0, 9.5, 0)
	lantern.light_color = Color("ffaf59")
	lantern.omni_range = 22.0
	lantern.shadow_enabled = true
	stage.add_child(lantern)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	stage.add_child(camera)
	illuminate(false)
	stone_view(Vector3(0, 5.0, 1.0), Vector3(0, 16, 19), 16.0)
	use_weathering(false)
	await photograph("yard-day-before")
	use_weathering(true)
	await photograph("yard-day-after")
	stone_view(Vector3(0.6, 5.0, 2.8), Vector3(3.5, 6.0, 6.0), 5.2)
	use_weathering(false)
	await photograph("paving-close-before")
	use_weathering(true)
	await photograph("paving-close-after")
	stone_view(Vector3(4.8, 2.7, 7.0), Vector3(9, 8, 11), 12.0)
	use_weathering(false)
	await photograph("wall-day-before")
	use_weathering(true)
	await photograph("wall-day-after")
	stone_view(Vector3(0, 2.7, 11.0), Vector3(4, 9, 13), 15.0)
	await photograph("causeway-day-after")
	illuminate(true)
	stone_view(Vector3(0, 5.0, 0), Vector3(0, 25, 29), 24.0)
	use_weathering(false)
	await photograph("yard-night-before")
	use_weathering(true)
	var lit := await photograph("yard-night-after")
	lantern.light_energy = 0.0
	environment.ambient_light_energy = 0.0
	sun.light_energy = 0.0
	var dark := await photograph("lights-off")
	var region := Rect2i(Vector2i(540, 315), Vector2i(360, 270))
	var lit_mean := mean_value(lit, region)
	var dark_mean := mean_value(dark, region)
	assert(lit_mean > 0.05, "Lit stone must actually be drawn")
	assert(dark_mean < lit_mean * 0.08, "Stone has no emission and must disappear with the lights")
	illuminate(false)
	stone_view(Vector3(0.6, 5.0, 2.8), Vector3(3.5, 6.0, 6.0), 5.2)
	var before_ms := await measure_frames(false)
	var after_ms := await measure_frames(true)
	print("OUTPOST_MASONRY_STAGE_OK surfaces=", masonry.size(), " lit=", lit_mean, " dark=", dark_mean,
		" close_view_before_ms=", before_ms, " close_view_after_ms=", after_ms)
	stage.queue_free()
	await process_frame
	quit(0)
