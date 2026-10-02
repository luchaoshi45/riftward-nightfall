extends SceneTree

func _initialize() -> void:
	call_deferred("inspect")

func inspect() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var world := BattleWorld.new()
	stage.add_child(world)
	world.build()
	for faction in [0, 1]:
		var unit := BattleUnit.new()
		stage.add_child(unit)
		unit.setup("hero", faction)
		unit.position = Vector3(-1.35 if faction == 0 else 1.35, 0, 0)
		assert(unit.arms.size() == 2 and unit.legs.size() == 2)
		assert(unit.cloak != null)
		unit.moving = true
		unit.tick(0.08)
		assert(absf(unit.arms[0].rotation.x) > 0.01)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.6
	camera.position = Vector3(4, 5.2, 7)
	camera.look_at(Vector3(0, 1.45, 0))
	camera.current = true
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/showcase/starblade-ingame.png")
	for unit in stage.get_children():
		if unit is BattleUnit:
			unit.visual.rotation.y = PI
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/showcase/starblade-ingame-front.png")
	print("STARBLADE_GAMEPLAY_INSPECTION_OK")
	quit()
