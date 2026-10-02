extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
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
	game.hero.position=Vector3(0,5,3)
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
	await create_timer(.28).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/lantern-inferno-night.png")
	print("NIGHTFALL_INFERNO_VISUAL_OK")
	quit()
