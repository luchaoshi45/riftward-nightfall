extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	assert(game.choose_card(0))
	game.set_process(false)
	assert(game.tower_count()==2 and game.scrap==90,"Use the real opening defenses without test-only upgrades")
	game.hero.position=Vector3(0,5,3.1)
	game.move_goal=game.hero.position
	var remaining:=1150
	while remaining>0 and game.phase!="ended":
		if game.phase=="draft":assert(game.choose_card(0))
		if game.phase=="night":
			game.aim=game.hero.position+Vector3(0,0,8)
			if game.hero.hp<game.hero.max_hp*.65:
				game.cast(4)
				game.cast(1)
			if game.gate_pressure()>0:game.cast(0)
			game.simulate(.1)
		remaining-=1
	print("NIGHTFALL_BALANCE first-night beacon=",int(game.beacon_hp)," hero=",int(game.hero.hp)," kills=",game.kills," phase=",game.phase)
	assert(game.beacon_hp>0 and game.hero.alive,"A fortified first night must be survivable")
	assert(game.day_number==2 and game.phase=="day","First-night defense must advance to the second day")
	quit()
