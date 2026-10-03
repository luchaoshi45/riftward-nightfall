extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	var seen: Dictionary = {}
	var per_type: Dictionary = {}
	for attempt in 100:
		var unit = game.spawn_creature(true)
		var threat: String = unit.get_meta("threat", "stalker")
		if not per_type.has(threat):
			var vertices := 0
			var hull_vertices := 0
			var count := 0
			for child in unit.visual.find_children("*", "MeshInstance3D", true, false):
				var mesh = child.mesh
				if not mesh: continue
				count += 1
				var raw_count := 0
				for surface in mesh.get_surface_count():
					raw_count += mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()
				var hull = mesh.create_convex_shape(true, false)
				var hull_count: int = hull.points.size() if hull else 0
				vertices += raw_count
				hull_vertices += hull_count
				if not seen.has(mesh.get_instance_id()):
					seen[mesh.get_instance_id()] = true
					print("SUPPORT_MESH ", child.name, " raw=", raw_count, " hull=", hull_count)
			per_type[threat] = {"meshes": count, "vertices": vertices, "hull": hull_vertices}
		game.enemies.erase(unit)
		unit.queue_free()
		if per_type.size() == 4: break
	print("SUPPORT_PROBE ", JSON.stringify(per_type))
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit()
