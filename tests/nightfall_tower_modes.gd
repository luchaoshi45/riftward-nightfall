extends SceneTree

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.hide()
	call_deferred("run")

func frames(count: int=5) -> void:
	for i in count:await process_frame

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await frames(12)
	game.choose_card(0)
	assert(game.phase=="night")
	game.set_process(false)
	game.hero.position=Vector3(-8,5,-5.8)
	game.move_goal=game.hero.position
	game.scrap=60
	assert(game.build_tower_at(Vector3(-8,5,-8)))
	var pad: Dictionary=game.world.tower_pads.back()
	assert(pad.level==1 and game.tower_count()==3)
	for other: Dictionary in game.world.tower_pads:
		if other!=pad:other.cooldown=10000.0
	var close_enemy: BattleUnit=game.spawn_creature(false)
	var breaker: BattleUnit=game.spawn_creature(false)
	close_enemy.position=pad.position+Vector3(3,0,0)
	breaker.position=pad.position+Vector3(6,0,0)
	breaker.set_meta("threat","breaker")
	var close_hp: float=close_enemy.hp
	var breaker_hp: float=breaker.hp
	pad.mode="breaker"
	game.update_towers(1.2)
	assert(close_enemy.hp==close_hp)
	assert(breaker.hp<breaker_hp)
	close_hp=close_enemy.hp
	pad.mode="nearest"
	game.update_towers(1.2)
	assert(close_enemy.hp<close_hp)
	print("NIGHTFALL_TOWER_MODES_OK")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit()
