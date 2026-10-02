extends SceneTree

func _initialize() -> void:
	call_deferred("inspect")

func inspect() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var world := BattleWorld.new()
	stage.add_child(world)
	world.build()
	var terrain: MeshInstance3D
	for part in world.find_children("*", "MeshInstance3D", true, false):
		if "Sculpted" in part.name: terrain = part as MeshInstance3D
	assert(terrain != null and terrain.material_override != null)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 23
	camera.position = Vector3(8, 17, 16)
	camera.look_at(Vector3(0, 0, 0))
	camera.current = true
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/terrain-ingame.png")
	print("TERRAIN_GAMEPLAY_INSPECTION_OK")
	quit()
