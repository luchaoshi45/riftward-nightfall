extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func frames(count: int=5) -> void:
	for i in count:await process_frame

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await frames(12)
	game.choose_card(0)
	assert(game.phase=="night")
	var pad: Dictionary=game.world.tower_pads[0]
	game.hero.position=pad.position+Vector3(.5,0,.5)
	game.move_goal=game.hero.position
	game.scrap=60
	assert(game.interact())
	assert(pad.level==1)
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
