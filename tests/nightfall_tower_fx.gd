extends SceneTree

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.hide()
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	assert(game.choose_card(0))
	game.set_process(false)
	for old_enemy in game.enemies:
		if is_instance_valid(old_enemy):old_enemy.queue_free()
	game.enemies.clear()
	var pad: Dictionary=game.world.tower_pads[1]
	game.hero.position=pad.position+Vector3(0,0,-2.0)
	game.move_goal=game.hero.position
	game.scrap=60
	assert(game.interact())
	await create_timer(.8).timeout
	var enemy: BattleUnit=game.spawn_creature(false)
	enemy.position=pad.position+Vector3(0,0,5)
	enemy.position.y=game.world.terrain_height(enemy.position)
	var hp_before: float=enemy.hp
	game.update_towers(1.2)
	assert(enemy.hp<hp_before)
	var shot: Node=game.effects.find_child("TowerShot",false,false)
	var impact: Node=game.effects.find_child("TowerImpact",false,false)
	assert(shot!=null and impact!=null)
	assert(shot.find_child("AmberHalo",false,false)!=null and shot.find_child("BrightCore",false,false)!=null)
	game.hero.visible=false
	game.hud.visible=false
	var midpoint: Vector3=(pad.position+enemy.position)*.5
	game.camera.size=14
	game.camera.position=midpoint+Vector3(0,17,15)
	game.camera.look_at(midpoint)
	game.camera.current=true
	await create_timer(.07).timeout
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png("res://build/tower-shot-v2.png")==OK)
	await create_timer(.4).timeout
	assert(game.effects.find_child("TowerShot",false,false)==null)
	assert(game.effects.find_child("TowerImpact",false,false)==null)
	print("NIGHTFALL_TOWER_FX_OK")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit()
