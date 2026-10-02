extends SceneTree

func _initialize() -> void:
	call_deferred("inspect")

func inspect() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var world := BattleWorld.new()
	stage.add_child(world)
	world.build()
	var windy_surfaces := 0
	for part in world.find_children("*", "MeshInstance3D", true, false):
		var mesh_part := part as MeshInstance3D
		for index in range(mesh_part.mesh.get_surface_count()):
			var surface := mesh_part.get_surface_override_material(index) as ShaderMaterial
			if surface and surface.shader.resource_path.ends_with("foliage_wind.gdshader"):
				windy_surfaces += 1
	assert(windy_surfaces > 100)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 23
	camera.position = Vector3(8,17,16)
	camera.look_at(Vector3(0,0,0))
	camera.current = true
	await create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	var first := root.get_texture().get_image()
	first.save_png("res://build/tree-wind-a.png")
	await create_timer(.8).timeout
	await RenderingServer.frame_post_draw
	var second := root.get_texture().get_image()
	second.save_png("res://build/tree-wind-b.png")
	var changed := 0
	for y in range(470,680,3):
		for x in range(100,350,3):
			var before := first.get_pixel(x,y)
			var after := second.get_pixel(x,y)
			if absf(before.r-after.r)+absf(before.g-after.g)+absf(before.b-after.b) > .035:
				changed += 1
	assert(changed > 50, "Tree crown must visibly move with wind")
	print("FOLIAGE_WIND_OK surfaces=",windy_surfaces," changed_pixels=",changed)
	quit()
