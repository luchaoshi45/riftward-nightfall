extends SceneTree
func _initialize() -> void: call_deferred("inspect")
func inspect() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var world := BattleWorld.new()
	scene.add_child(world)
	world.build()
	var model=load("res://assets/models/golem.glb").instantiate()
	scene.add_child(model)
	BattleVisuals.paint_model(model)
	model.rotation.y=.3
	var camera:=Camera3D.new()
	scene.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=4.4
	camera.position=Vector3(3,3.0,5)
	camera.look_at(Vector3(0,1.3,0))
	camera.current=true
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/golem-refined.png")
	print("GOLEM_RENDER_OK")
	quit()
