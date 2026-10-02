extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func make_final_night() -> Node3D:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	assert(game.choose_card(0))
	for creature in game.enemies:
		if is_instance_valid(creature):creature.queue_free()
	game.enemies.clear()
	game.day_number=3
	game.phase="night"
	game.world.set_night(true)
	game.world._process(6.0)
	return game

func capture(game: Node3D, name: String) -> void:
	game.set_process(false)
	game.world.set_process(false)
	game.world._process(6.0)
	game.hud.queue_redraw()
	await create_timer(.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/"+name+".png")

func run() -> void:
	var signal_game: Node3D=await make_final_night()
	for nest in signal_game.world.nests:nest.cleansed=true
	signal_game.finish_night()
	assert(signal_game.victory and signal_game.ending_key=="signal")
	assert(signal_game.phase=="ended" and signal_game.remaining_nests()==0)
	assert(signal_game.world.beacon_light.light_color==Color("96d9d6"))
	await capture(signal_game,"ending-signal")
	signal_game.queue_free()
	await process_frame
	var hold_game: Node3D=await make_final_night()
	hold_game.world.nests[0].cleansed=true
	hold_game.finish_night()
	assert(hold_game.victory and hold_game.ending_key=="hold")
	assert(hold_game.remaining_nests()==2)
	await capture(hold_game,"ending-hold")
	hold_game.end_defeat("测试失守")
	assert(not hold_game.victory and hold_game.ending_key=="defeat")
	print("NIGHTFALL_ENDINGS_OK")
	quit()
