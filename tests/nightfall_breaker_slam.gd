extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	assert(game.choose_card(0))
	game.start_night()
	for old_enemy in game.enemies:
		if is_instance_valid(old_enemy):old_enemy.queue_free()
	game.enemies.clear()
	var breaker: BattleUnit=null
	for i in range(80):
		var enemy: BattleUnit=game.spawn_creature(true)
		if enemy.get_meta("threat","")=="breaker":
			breaker=enemy
			break
		for other in game.enemies:
			if is_instance_valid(other):other.queue_free()
		game.enemies.clear()
	assert(breaker!=null)
	game.hero.position=Vector3(0,5,3)
	game.move_goal=game.hero.position
	breaker.position=Vector3(0,5,1.35)
	breaker.attack_timer=0
	game.update_creature(breaker,.1)
	assert(breaker.attack_queued and breaker.windup_duration>.5)
	breaker.tick(.3)
	assert(breaker.visual.position.z>.18 and breaker.stalker_head.rotation.x>.3,"Breaker should brace for a heavy strike")
	var hp_before: float=game.beacon_hp
	breaker.tick(.3)
	game.update_creature(breaker,.1)
	assert(game.beacon_hp<hp_before and game.effects.get_node_or_null("BreakerSlam")!=null,"Slam must damage the beacon and create the impact")
	breaker.tick(.025)
	assert(breaker.visual.position.z<-.65,"Breaker must visibly lunge farther than a regular stalker")
	game.set_process(false)
	game.hero.visible=false
	game.hud.visible=false
	game.camera.size=6.0
	game.camera.position=breaker.position+Vector3(0,4,-7)
	game.camera.look_at(breaker.position+Vector3(0,1,0))
	game.camera.current=true
	if DisplayServer.get_name()!="headless":
		await create_timer(.12).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/breaker-slam.png")
	breaker.tick(.35)
	assert(absf(breaker.visual.position.z)<.01,"Breaker must return to its resting pose")
	print("NIGHTFALL_BREAKER_SLAM_OK")
	quit()
