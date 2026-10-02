extends SceneTree
func _initialize() -> void: call_deferred("inspect")
func inspect() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var world := BattleWorld.new()
	scene.add_child(world)
	world.build()
	var unit := BattleUnit.new()
	scene.add_child(unit)
	unit.setup("minion", 0)
	var spear := unit.visual.find_child("Ash polearm shaft", true, false) as Node3D
	assert(spear != null, "Minion polearm imported")
	var spear_before := spear.global_transform
	var enemy := BattleUnit.new()
	scene.add_child(enemy)
	enemy.setup("minion", 1)
	enemy.position = Vector3(1.4, 0, 0)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.4
	camera.position = Vector3(3, 3.1, 4.5)
	camera.look_at(Vector3(.5,.9,0))
	camera.current = true
	for i in 14:
		unit.moving = true
		unit.tick(.08)
		enemy.moving = false
		enemy.tick(.08)
		await process_frame
	unit.moving = false
	assert(spear.global_transform != spear_before, "Polearm follows the articulated arm")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/showcase/minion-ingame.png")
	print("MINION_RENDER_OK")
	quit()

