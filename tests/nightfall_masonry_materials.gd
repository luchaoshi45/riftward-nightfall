extends SceneTree
## Production surface selection, original palette and unchanged traversable terrain.
const MASONRY_NAMES := ["Weathered concrete", "Concrete fracture"]
const MASONRY_SHADER := "res://assets/shaders/outpost_masonry.gdshader"
var game: Node3D
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message); push_error(message)

func walk_home(from: Vector3) -> void:
	var home := Vector3(0, 5, 3.1)
	game.hero.position = from
	game.hero.position.y = game.outpost_height(from)
	game.move_goal = game.hero.position
	game.hero_keyboard_active = false
	game.plan_hero_path(home)
	check(not game.hero_path.is_empty(), "Returning home creates an actual route")
	var prior: Vector3 = game.hero.position
	var ramp_visited := false
	for index in 900:
		game.move_hero(.04)
		check(game.outpost_walkable(game.hero.position) and game.can_traverse(prior, game.hero.position),
			"The textured ramp route cannot cut through a fortress wall")
		check(absf(game.hero.position.y - game.outpost_height(game.hero.position)) < .0001,
			"The returning hero follows the original actual surface height")
		if absf(game.hero.position.x) < 2.6 and game.hero.position.z > 13.5 and game.hero.position.z < 25.5:
			ramp_visited = true
		prior = game.hero.position
		if game.hero.position.distance_to(home) < .28: break
	check(ramp_visited and game.hero.position.distance_to(home) < .28,
		"Returning from either side reaches the elevated home through the single south ramp")

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.world.set_process(false)
	game.music.persist_settings = false
	check(game.choose_card(0), "The real opening card enters the playable first night")
	check(is_instance_valid(game.world.terrain), "The production world exposes its actual imported terrain")
	var terrain: Node3D = game.world.terrain
	var reference: Node3D = load("res://assets/models/castle_ground.glb").instantiate()
	root.add_child(reference)
	var masonry_count := 0
	var ash_count := 0
	var iron_count := 0
	var palette: Array[Color] = []
	var per_original: Dictionary = {}
	for found in terrain.find_children("*", "MeshInstance3D", true, false):
		var mesh := found as MeshInstance3D
		if not mesh.mesh: continue
		var original_node := reference.get_node_or_null(terrain.get_path_to(mesh)) as MeshInstance3D
		check(original_node != null and original_node.mesh == mesh.mesh and original_node.transform.is_equal_approx(mesh.transform),
			"Material weathering preserves the imported terrain mesh and local geometry")
		for index in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(index) as StandardMaterial3D
			check(original != null, "Native terrain surface retains its original standard PBR resource")
			if original == null: continue
			var active := mesh.get_active_material(index)
			if original.resource_name in MASONRY_NAMES:
				masonry_count += 1
				var material := active as ShaderMaterial
				check(material != null and material.shader != null and material.shader.resource_path == MASONRY_SHADER,
					"Production hooks each named concrete surface into the masonry shader")
				if not material: continue
				check(material.resource_name == "Ash-worn " + original.resource_name,
					"The production weathered surface retains an identifiable original material label")
				var color: Color = material.get_shader_parameter("base_color")
				check(color.is_equal_approx(original.albedo_color), "The actual shader keeps the imported concrete palette")
				palette.append(color)
				if per_original.has(original): check(per_original[original] == material, "Shared original concrete uses one cached shader material")
				else: per_original[original] = material
			elif original.resource_name == "Ash compacted earth":
				ash_count += 1
				var material := active as ShaderMaterial
				check(material != null and material.shader.resource_path == "res://assets/shaders/wasteland.gdshader",
					"The ash wasteland keeps its own material instead of becoming concrete")
			elif original.resource_name == "Old iron rust":
				iron_count += 1
				check(active == original and mesh.get_surface_override_material(index) == null,
					"Rust surfaces retain their imported metal PBR material without a concrete override")
			else: check(active == original, "Unrelated imported surfaces remain unchanged")
	check(masonry_count == 2 and ash_count == 1 and iron_count == 1,
		"The real terrain contains exactly two intended concrete surfaces and both protected material families")
	check(palette.size() == 2 and not palette[0].is_equal_approx(palette[1]),
		"Paving concrete and fracture rubble keep their distinct color palettes")
	reference.queue_free(); await process_frame
	var heights := [[Vector3(0, 0, 0), 5.0], [Vector3(0, 0, 7), 5.0],
		[Vector3(0, 0, 16.5), 4.21875], [Vector3(0, 0, 19.5), 2.5],
		[Vector3(0, 0, 22.5), .78125], [Vector3(0, 0, 25.5), 0.0],
		[Vector3(19, 0, 19), 0.0]]
	for sample in heights:
		check(absf(game.outpost_height(sample[0]) - float(sample[1])) < .0001,
			"The fortress and south-ramp height profile retain the playable baseline")
	walk_home(Vector3(7, 0, 25)); walk_home(Vector3(-8, 0, 26)); walk_home(Vector3(0, 0, 29))
	await game.prepare_shutdown()
	game.queue_free(); await process_frame
	await create_timer(.5).timeout
	if failures.is_empty(): print("NIGHTFALL_MASONRY_MATERIALS_OK production_two_surfaces native_palette protected_ash_rust shared_geometry baseline_heights three_home_routes audio_scene_cleanup")
	quit(0 if failures.is_empty() else 1)
