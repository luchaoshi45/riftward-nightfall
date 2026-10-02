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
	for index in [1,2]:game.damage_tower(index,10000)
	var pad: Dictionary=game.world.tower_pads[1]
	game.hero.position=pad.position+Vector3(.5,0,.5)
	game.move_goal=game.hero.position
	game.scrap=150
	assert(game.interact())
	assert(pad.level==1 and pad.hp==280.0)
	game.phase="night"
	var approacher: BattleUnit=game.spawn_creature(true)
	approacher.set_meta("threat","sapper")
	approacher.position=Vector3(0,0,25)
	for i in 80:game.update_creature(approacher,.1)
	assert(approacher.position.z<19.5 and approacher.position.x>3.6,"Sapper should circle outside the wall toward a tower")
	approacher.queue_free()
	game.enemies.erase(approacher)
	var sapper: BattleUnit=game.spawn_creature(true)
	sapper.set_meta("threat","sapper")
	sapper.position=pad.position+Vector3(1.5,0,0)
	sapper.attack_timer=0
	game.update_creature(sapper,.1)
	assert(sapper.attack_queued and sapper.attack_target_pad==1)
	sapper.attack_windup=0
	game.update_creature(sapper,.1)
	assert(pad.hp<280.0 and pad.level==1)
	game.damage_tower(1,130.0)
	assert(pad.damage_ring.visible)
	await frames(3)
	await RenderingServer.frame_post_draw
	var shot: Image=root.get_texture().get_image()
	shot.save_png("res://tests/nightfall_sappers.png")
	var damaged_hp: float=pad.hp
	var old_scrap: int=game.scrap
	var repair_key:=InputEventKey.new()
	repair_key.keycode=KEY_H
	repair_key.pressed=true
	game._unhandled_input(repair_key)
	assert(pad.hp==minf(pad.max_hp,damaged_hp+100.0))
	assert(game.scrap==old_scrap-20 and not pad.damage_ring.visible)
	await frames(2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/nightfall_tower_repair.png")
	game.damage_tower(1,50.0)
	game.scrap=0
	var insufficient_hp: float=pad.hp
	assert(not game.repair_tower() and pad.hp==insufficient_hp)
	game.damage_tower(1,500.0)
	assert(pad.level==0 and pad.hp==0.0 and game.tower_count()==0)
	game.phase="day"
	game.scrap=60
	assert(game.interact())
	assert(pad.level==1 and pad.hp==280.0 and not pad.damage_ring.visible)
	print("NIGHTFALL_SAPPERS_OK")
	quit()
