extends SceneTree
## Isolated editable-lamp asset QA; no playable scene, save, or release mutation.

var stage: Node3D
var old_beacon: Node3D
var beacon: Node3D
var camera: Camera3D
var environment: Environment
var sun: DirectionalLight3D
var lamp_light: OmniLight3D
var materials: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func photograph(name: String) -> Image:
	for i in 5: await process_frame
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	assert(not frame.is_empty())
	assert(frame.save_png("res://build/watch-beacon-stage-" + name + ".png") == OK)
	return frame

func assert_visible_lamp(frame: Image) -> void:
	var center := Vector2i(camera.unproject_position(beacon.position + Vector3(0, 2.50, 0.25)))
	var warm_pixels := 0
	for y in range(max(center.y - 22, 0), min(center.y + 23, frame.get_height())):
		for x in range(max(center.x - 18, 0), min(center.x + 19, frame.get_width())):
			var color := frame.get_pixel(x, y)
			if color.r > 0.72 and color.g > 0.35 and color.b < color.r * 0.70:
				warm_pixels += 1
	assert(warm_pixels > 12, "The hood must not hide the warm focus at the real size-31 camera")
	print("WATCH_BEACON_FOCAL_VISIBILITY_OK warm_pixels=", warm_pixels)

func frame_beacon(target: Vector3, offset: Vector3, size: float) -> void:
	camera.size = size
	camera.position = target + offset
	camera.look_at(target, Vector3.UP)

func illuminate(night: bool) -> void:
	environment.ambient_light_color = Color("697587") if night else Color("b8b3a5")
	environment.ambient_light_energy = 0.028 if night else 0.56
	environment.fog_light_color = Color("090f1a") if night else Color("565b57")
	environment.fog_density = 0.020 if night else 0.010
	sun.light_color = Color("587090") if night else Color("e4c6a7")
	sun.light_energy = 0.018 if night else 0.86
	lamp_light.light_energy = 8.2 if night else 1.4

func inspect_asset() -> void:
	var first := true
	var bounds := AABB()
	for found in beacon.find_children("*", "MeshInstance3D", true, false):
		var node := found as MeshInstance3D
		var region: AABB = node.global_transform * node.get_aabb()
		bounds = region if first else bounds.merge(region)
		first = false
		for index in node.mesh.get_surface_count():
			var material := node.mesh.surface_get_material(index) as StandardMaterial3D
			assert(material != null, "glTF must preserve real PBR materials")
			materials[material.resource_name] = material
	assert(materials.size() == 9, "Stone, iron, glass and protected core must remain distinct")
	var iron: StandardMaterial3D = materials["Beacon V2 ash-worn forged iron"]
	var stone: StandardMaterial3D = materials["Beacon V2 carved basalt footing"]
	var glass: StandardMaterial3D = materials["Beacon V2 enclosed amber lamp glass"]
	var core: StandardMaterial3D = materials["Beacon V2 protected incandescent core"]
	assert(iron.albedo_texture != null and iron.normal_texture != null and iron.roughness_texture != null)
	assert(stone.albedo_texture != null and stone.normal_texture != null and stone.roughness_texture != null)
	assert(iron.metallic > 0.7 and stone.metallic == 0.0 and stone.roughness > 0.8)
	assert(glass.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and glass.albedo_color.a < 0.3)
	assert(not glass.emission_enabled and core.emission_enabled, "Only the enclosed element emits light")
	assert(bounds.size.x > 4.8 and bounds.size.x < 5.5)
	assert(bounds.size.y > 3.5 and bounds.size.y < 4.1)
	assert(bounds.position.y >= 4.98 and bounds.position.y < 5.08, "Foundation rests on the 5m courtyard")
	print("WATCH_BEACON_IMPORTED_PBR_OK materials=", materials.size(), " bounds=", bounds)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Lamp stage requires hidden graphical rendering")
		quit(1)
		return
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var ground := (load("res://assets/models/outpost_ground.glb") as PackedScene).instantiate() as Node3D
	stage.add_child(ground)
	for found in ground.find_children("*", "MeshInstance3D", true, false):
		var node := found as MeshInstance3D
		for index in node.mesh.get_surface_count():
			var original := node.mesh.surface_get_material(index) as StandardMaterial3D
			if original == null: continue
			var replacement := ShaderMaterial.new()
			if original.resource_name == "Ash compacted earth":
				replacement.shader = load("res://assets/shaders/wasteland.gdshader")
			elif original.resource_name in ["Weathered concrete", "Concrete fracture"]:
				replacement.shader = load("res://assets/shaders/outpost_masonry.gdshader")
				replacement.set_shader_parameter("base_color", original.albedo_color)
			else: continue
			node.set_surface_override_material(index, replacement)
	old_beacon = (load("res://assets/models/watch_beacon.glb") as PackedScene).instantiate() as Node3D
	stage.add_child(old_beacon)
	old_beacon.position.y = 5.0
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var path := "res://assets/models/watch_beacon_v2.glb"
	if FileAccess.file_exists("res://build/watch-beacon-v2-staged.glb"):
		path = "res://build/watch-beacon-v2-staged.glb"
	assert(document.append_from_file(path, state) == OK)
	beacon = document.generate_scene(state)
	assert(beacon != null)
	stage.add_child(beacon)
	beacon.position.y = 5.0
	beacon.visible = false
	inspect_asset()
	var world_environment := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("03060b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.ssao_enabled = true
	environment.ssao_radius = 1.7
	environment.ssao_intensity = 1.55
	environment.glow_enabled = true
	environment.glow_intensity = 0.36
	environment.fog_enabled = true
	environment.fog_height_density = 0.04
	world_environment.environment = environment
	stage.add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -42, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100.0
	stage.add_child(sun)
	lamp_light = OmniLight3D.new()
	lamp_light.position = Vector3(0, 9.5, 0)
	lamp_light.light_color = Color("ffaf59")
	lamp_light.omni_range = 22.0
	lamp_light.shadow_enabled = true
	stage.add_child(lamp_light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	stage.add_child(camera)
	illuminate(false)
	frame_beacon(Vector3(0, 5.0, 3.0), Vector3(0, 25, 29), 31)
	await photograph("game-day-before")
	old_beacon.visible = false
	beacon.visible = true
	var day_image := await photograph("game-day-after")
	assert_visible_lamp(day_image)
	frame_beacon(Vector3(0, 6.65, 0), Vector3(4, 4.2, 7), 6.5)
	await photograph("close-day")
	var gray := StandardMaterial3D.new()
	gray.albedo_color = Color(0.35, 0.35, 0.35)
	gray.roughness = 0.85
	for found in beacon.find_children("*", "MeshInstance3D", true, false):
		(found as MeshInstance3D).material_override = gray
	await photograph("gray-structure")
	for found in beacon.find_children("*", "MeshInstance3D", true, false):
		(found as MeshInstance3D).material_override = null
	illuminate(true)
	await photograph("close-night")
	frame_beacon(Vector3(0, 5.0, 3.0), Vector3(0, 25, 29), 31)
	beacon.visible = false
	old_beacon.visible = true
	await photograph("game-night-before")
	beacon.visible = true
	old_beacon.visible = false
	var night_image := await photograph("game-night-after")
	assert_visible_lamp(night_image)
	print("WATCH_BEACON_STAGE_OK source=", path)
	stage.queue_free()
	await process_frame
	quit(0)
