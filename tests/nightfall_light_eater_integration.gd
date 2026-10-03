extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	assert(game.choose_card(0))
	game.start_night()
	game.set_process(false)
	game.world.set_process(false)
	game.world._process(6.0)
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()
	var moth: BattleUnit=null
	for i in range(80):
		var enemy: BattleUnit=game.spawn_creature(true)
		if enemy.get_meta("threat","")=="light_eater":
			moth=enemy
			break
		if is_instance_valid(enemy):enemy.queue_free()
		game.enemies.clear()
	assert(moth!=null,"Night waves must contain a light-eating creature")
	assert(moth.visual.scene_file_path.ends_with("night_light_eater.glb"),"Light eater needs its own model")
	var eater:=moth.get_node_or_null("LightEater") as NightLightEater
	assert(eater!=null and eater.wing_left!=null and eater.wing_right!=null)
	var lamp: OmniLight3D=game.world.gate_lights[0]
	var baseline: float=lamp.light_energy
	moth.position=lamp.position+Vector3(1,0,0)
	game.simulate(.05)
	game.world.apply_lighting()
	assert(game.world.gate_light_drain[0]>.7 and lamp.light_energy<baseline*.3,"Approaching the gate must dim the nearby lamp")
	assert(absf(eater.wing_left.rotation.z)>.05,"Moth wings must flap")
	moth.hurt(10000,game.hero)
	game.simulate(.05)
	game.world.apply_lighting()
	assert(game.world.gate_light_drain[0]==0.0 and is_equal_approx(lamp.light_energy,baseline),"Killing the moth must restore the lamp")
	print("NIGHTFALL_LIGHT_EATER_INTEGRATION_OK")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit()
