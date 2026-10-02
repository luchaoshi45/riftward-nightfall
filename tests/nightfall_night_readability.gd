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
	assert(game.world.gate_spots.size()==2 and game.world.gate_spots[0].light_energy>7.0)
	var enemy: BattleUnit=game.spawn_creature(true)
	enemy.position=Vector3(0,game.world.terrain_height(Vector3(0,0,18)),18)
	game.hero.visible=false
	game.hud.visible=false
	var center:=Vector3(0,1.4,16)
	game.camera.size=23
	game.camera.position=center+Vector3(0,24,25)
	game.camera.look_at(center)
	game.camera.current=true
	await create_timer(.18).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/night-gate-lit.png")
	print("NIGHTFALL_NIGHT_READABILITY_OK")
	quit()
