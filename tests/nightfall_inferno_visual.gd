extends SceneTree

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.hide()
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size=Vector2i(1920,1200)
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Inferno visual verification requires actual rendering")
		quit(1);return
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	assert(game.choose_card(0))
	game.day_number=2
	game.start_night()
	game.set_process(false)
	game.world.set_process(false)
	game.world._process(6.0)
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()
	game.hero.position=Vector3(0,5,5)
	game.move_goal=game.hero.position
	game.world.follow_ashfall(game.hero.position)
	game.mana=game.max_mana
	game.cooldowns[3]=0.0
	assert(game.cast(3))
	assert(game.effects.get_node_or_null("LanternInferno")!=null)
	game.hud.visible=false
	game.camera.size=27
	game.camera.position=game.hero.position+Vector3(0,25,29)
	game.camera.look_at(game.hero.position)
	game.camera.current=true
	game.skill_lights.tick(.23,"night")
	await create_timer(.28).timeout
	await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image()
	assert(picture.get_size()==Vector2i(1920,1200))
	assert(picture.save_png("res://build/lantern-inferno-night.png")==OK)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_INFERNO_VISUAL_OK")
	quit()
