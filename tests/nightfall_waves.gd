extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	assert(game.choose_card(0))
	game.start_night()
	assert(game.wave_index==1 and game.enemies.size()==game.initial_night_pack())
	assert(game.spawn_timer>15 and not game.world.wave_warning)
	game.spawn_timer=4.01
	game.simulate(.02)
	assert(game.wave_index==1 and game.world.wave_warning)
	game.hero.position=Vector3(0,5,3)
	game.move_goal=game.hero.position
	game.camera.position=game.hero.position+Vector3(0,25,29)
	await create_timer(.2).timeout
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/night-wave-warning.png")
	var before: int=game.enemies.size()
	game.spawn_timer=.01
	game.simulate(.02)
	assert(game.wave_index==2 and game.enemies.size()>before)
	assert(not game.world.wave_warning)
	for i in range(game.WAVES_PER_NIGHT-2):game.spawn_night_wave()
	assert(game.wave_index==game.WAVES_PER_NIGHT)
	before=game.enemies.size()
	game.spawn_night_wave()
	assert(game.enemies.size()==before)
	print("NIGHTFALL_WAVES_OK")
	quit()
