extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	assert(game.choose_card(0))
	assert(game.world.ashfall!=null and game.world.ashfall.emitting)
	assert(is_equal_approx(game.world.ashfall.amount_ratio,.35))
	game.hero.position=Vector3(40,0,40)
	game.move_goal=game.hero.position
	game.world.follow_ashfall(game.hero.position)
	assert(game.world.ashfall.position.distance_to(game.hero.position+Vector3(0,8,0))<.01)
	game.hero.position=Vector3(0,5,3)
	game.move_goal=game.hero.position
	game.camera.position=game.hero.position+Vector3(0,25,29)
	game.world.follow_ashfall(game.hero.position)
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/ashfall-day.png")
	game.start_night()
	game.world._process(6.0)
	assert(is_equal_approx(game.world.ashfall.amount_ratio,.8))
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/ashfall-night.png")
	print("NIGHTFALL_ASHFALL_OK")
	quit()
