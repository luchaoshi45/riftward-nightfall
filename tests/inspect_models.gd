extends SceneTree
func _initialize() -> void:
	call_deferred("inspect")
func inspect() -> void:
	var root3d := Node3D.new()
	root.add_child(root3d)
	var world := BattleWorld.new()
	root3d.add_child(world)
	world.build()
	var knight := BattleUnit.new()
	root3d.add_child(knight)
	knight.setup("hero",0)
	assert(knight.arms.size()==2 and knight.legs.size()==2, 'Articulated limbs retained')
	assert(knight.cloak != null, 'Cloak animation target retained')
	knight.moving=true
	knight.tick(.1)
	assert(absf(knight.arms[0].rotation.x)>0.01, 'Walk animation moves the new limbs')
	knight.moving=false
	knight.position=Vector3(-2,0,0)
	knight.visual.rotation.y=.35
	var tower := BattleUnit.new()
	root3d.add_child(tower)
	tower.setup("tower",0)
	tower.position=Vector3(2,0,0)
	var camera := Camera3D.new()
	root3d.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=8.7
	camera.position=Vector3(5,6,9)
	camera.look_at(Vector3(0,1.4,0))
	camera.current=true
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/models-v032.png")
	print("MODEL_INSPECTION_OK")
	quit()

