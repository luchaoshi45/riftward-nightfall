extends SceneTree
## Isolated staged GLB study. Does not replace models or mutate NightfallWorld.

var stage: Node3D
var camera: Camera3D
var environment: Environment
var sun: DirectionalLight3D
var lantern: OmniLight3D
var old_tree: Node3D
var new_tree: Node3D
var wood_material: StandardMaterial3D
var grey: StandardMaterial3D
var cluster: Node3D

func _initialize() -> void:
	call_deferred("run")

func load_glb(path: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file(ProjectSettings.globalize_path(path), state) == OK)
	var result := document.generate_scene(state) as Node3D
	assert(result != null)
	return result

func mesh_instances(tree: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for found in tree.find_children("*", "MeshInstance3D", true, false):
		result.append(found as MeshInstance3D)
	return result

func geometry(tree: Node3D) -> Dictionary:
	var vertices := 0
	var triangles := 0
	var draws := 0
	var bounds := AABB()
	var started := false
	for instance in mesh_instances(tree):
		for surface in instance.mesh.get_surface_count():
			draws += 1
			var arrays := instance.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			vertices += points.size()
			triangles += indices.size() / 3
			for local_point in points:
				var point: Vector3 = tree.global_transform.affine_inverse() * instance.global_transform * local_point
				if not started:
					bounds = AABB(point, Vector3.ZERO)
					started = true
				else:
					bounds = bounds.expand(point)
	return {"vertices": vertices, "triangles": triangles, "draws": draws, "bounds": bounds}

func photo(label: String) -> Image:
	for i in 6: await process_frame
	await create_timer(.14).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(not image.is_empty())
	assert(image.save_png("res://build/tree-stage-" + label + ".png") == OK)
	return image

func look(target: Vector3, offset: Vector3, size: float) -> void:
	camera.size = size
	camera.position = target + offset
	camera.look_at(target, Vector3.UP)

func illuminate(night: bool) -> void:
	environment.ambient_light_color = Color("697587") if night else Color("b8b3a5")
	environment.ambient_light_energy = .028 if night else .56
	environment.fog_light_color = Color("090f1a") if night else Color("565b57")
	environment.fog_density = .020 if night else .010
	sun.light_color = Color("587090") if night else Color("e4c6a7")
	sun.light_energy = .018 if night else .86
	lantern.light_energy = 4.2 if night else 0

func grey_mode(enabled: bool) -> void:
	for tree in [old_tree, new_tree]:
		for mesh in mesh_instances(tree):
			mesh.material_override = grey if enabled else null

func mean(image: Image) -> float:
	var value := 0.0
	var count := 0
	for y in range(210, 710, 6):
		for x in range(790, 1050, 6):
			var pixel := image.get_pixel(x, y)
			value += pixel.r + pixel.g + pixel.b
			count += 3
	return value / count

func frame_cost(model: Node3D) -> float:
	for child in cluster.get_children():
		child.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99431
	for i in 210:
		var angle := rng.randf_range(0, TAU)
		var radius := rng.randf_range(15, 104)
		var instance := model.duplicate() as Node3D
		cluster.add_child(instance)
		instance.visible = true
		instance.position = Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		instance.rotation.y = angle
		instance.scale = Vector3.ONE * rng.randf_range(.74, 1.35)
	old_tree.visible = false
	new_tree.visible = false
	for i in 16:
		await process_frame
		await RenderingServer.frame_post_draw
	var start := Time.get_ticks_usec()
	for i in 60:
		await process_frame
		await RenderingServer.frame_post_draw
	return (Time.get_ticks_usec() - start) / 60000.0

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	old_tree = load_glb("res://assets/models/dead_tree.glb")
	new_tree = load_glb("res://build/dead-tree-v2-staged.glb")
	stage.add_child(old_tree)
	stage.add_child(new_tree)
	var old_stats := geometry(old_tree)
	var new_stats := geometry(new_tree)
	assert(new_stats.draws <= 3 and new_stats.triangles < 10000)
	assert(new_stats.bounds.size.y >= old_stats.bounds.size.y * .9)
	assert(new_stats.bounds.size.y <= old_stats.bounds.size.y * 1.15)
	assert(new_stats.bounds.size.x <= old_stats.bounds.size.x * 1.18)
	assert(new_stats.bounds.size.z <= old_stats.bounds.size.z * 1.18)
	var textured_surfaces := 0
	for mesh in mesh_instances(new_tree):
		for index in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(index) as StandardMaterial3D
			assert(material != null and not material.emission_enabled)
			assert(material.metallic == 0)
			if material.albedo_texture:
				assert(material.roughness_texture != null)
				assert(material.normal_enabled and material.normal_texture != null)
				wood_material = material
				textured_surfaces += 1
	assert(textured_surfaces == 1)
	print("WASTELAND_TREE_GEOMETRY_OK old=", old_stats, " new=", new_stats,
		" baked_albedo_roughness_tangent_normal=", textured_surfaces)
	if DisplayServer.get_name() == "headless":
		stage.queue_free()
		await process_frame
		quit(0)
		return
	old_tree.position.x = -2.8
	new_tree.position.x = 2.8
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 240)
	floor.mesh = plane
	floor.position.y = -.05
	var dirt := StandardMaterial3D.new()
	dirt.albedo_color = Color(.072, .076, .068)
	dirt.roughness = .98
	floor.material_override = dirt
	stage.add_child(floor)
	var world := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("03060b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.ssao_enabled = true
	environment.ssao_radius = 1.3
	environment.ssao_intensity = 1.5
	environment.fog_enabled = true
	world.environment = environment
	stage.add_child(world)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -42, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100
	stage.add_child(sun)
	lantern = OmniLight3D.new()
	lantern.position = Vector3(1, 3.1, 3.8)
	lantern.light_color = Color("ffaf59")
	lantern.omni_range = 11
	lantern.shadow_enabled = true
	stage.add_child(lantern)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	stage.add_child(camera)
	grey = StandardMaterial3D.new()
	grey.albedo_color = Color(.34, .34, .34)
	grey.roughness = .9
	illuminate(false)
	look(Vector3(0, 1.3, 0), Vector3(5, 7, 10), 9.2)
	await photo("day-comparison")
	grey_mode(true)
	await photo("grey-comparison")
	grey_mode(false)
	old_tree.visible = false
	look(Vector3(2.8, 1.45, 0), Vector3(3.5, 3.6, 5.8), 4.6)
	await photo("bark-near")
	grey_mode(true)
	await photo("grey-near")
	grey_mode(false)
	old_tree.visible = true
	new_tree.rotation.y = PI * .7
	look(Vector3(0, 1.3, 0), Vector3(0, 5, 10), 9.2)
	await photo("crown-other-side")
	new_tree.rotation.y = 0
	illuminate(true)
	look(Vector3(0, 0, 0), Vector3(0, 25, 29), 31)
	var lit := await photo("night-default-31")
	lantern.light_energy = 0
	environment.ambient_light_energy = 0
	sun.light_energy = 0
	var dark := await photo("no-lights")
	assert(mean(dark) < .04, "Tree has no emission when all light sources are removed")
	illuminate(false)
	cluster = Node3D.new()
	stage.add_child(cluster)
	look(Vector3(0, 0, 24), Vector3(0, 25, 29), 31)
	var old_ms := await frame_cost(old_tree)
	await photo("forest-before")
	var new_ms := await frame_cost(new_tree)
	await photo("forest-after")
	print("WASTELAND_TREE_STAGE_OK old_ms=", old_ms, " new_ms=", new_ms,
		" lit_mean=", mean(lit), " dark_mean=", mean(dark), " instance_count=210")
	stage.queue_free()
	await process_frame
	quit(0)
