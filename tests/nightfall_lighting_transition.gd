extends SceneTree

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.hide()
	call_deferred("run")

func capture(game: Node3D, name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	game.hud.queue_redraw()
	await create_timer(.18).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/"+name+".png")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	assert(game.choose_card(0))
	game.hero.position=Vector3(0,5,3)
	game.move_goal=game.hero.position
	game.camera.position=game.hero.position+Vector3(0,25,29)
	game.set_process(false)
	game.world.set_process(false)
	game.world.night_mix=0.0;game.world.set_night(false)
	var day_ambient: float=game.world.environment.environment.ambient_light_energy
	game.start_night()
	assert(game.world.night_active and game.world.night_mix==0)
	assert(is_equal_approx(game.world.environment.environment.ambient_light_energy,day_ambient))
	game.world._process(3.0)
	assert(is_equal_approx(game.world.night_mix,.5))
	var dusk_ambient: float=game.world.environment.environment.ambient_light_energy
	assert(dusk_ambient<day_ambient and dusk_ambient>.20)
	await capture(game,"outpost-dusk")
	game.world._process(3.0)
	assert(is_equal_approx(game.world.night_mix,1.0))
	assert(is_equal_approx(game.world.environment.environment.ambient_light_energy,.028))
	assert(game.world.sun.light_energy<.03 and game.world.hero_lantern.light_energy>3.0)
	assert(game.world.gate_spots.size()==2 and game.world.gate_spots[0].light_energy>10.0)
	await capture(game,"outpost-full-night")
	game.world.set_night(false)
	game.world._process(3.0)
	assert(game.world.night_mix>0 and game.world.night_mix<1)
	game.world._process(3.0)
	assert(is_equal_approx(game.world.night_mix,0.0))
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_LIGHTING_TRANSITION_OK")
	quit()
