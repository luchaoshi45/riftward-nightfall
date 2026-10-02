extends SceneTree

func _initialize() -> void:
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
	game.hero.position=Vector3(20,0,20)
	game.move_goal=game.hero.position
	game.aim=game.hero.position+Vector3(0,0,-10)
	var inside: BattleUnit=game.spawn_creature(false)
	inside.position=game.hero.position+Vector3(0,0,-6)
	var outside: BattleUnit=game.spawn_creature(false)
	outside.position=game.hero.position+Vector3(7,0,-6)
	var inside_hp: float=inside.hp
	var outside_hp: float=outside.hp
	assert(game.cast(0))
	assert(inside.hp<inside_hp and outside.hp==outside_hp)
	var slash: Node=game.effects.find_child("SlashArc",false,false)
	assert(slash!=null and slash.find_child("SlashField",false,false)!=null and slash.find_child("SlashEdge",false,false)!=null)
	game.hud.visible=false
	var middle: Vector3=game.hero.position+Vector3(0,0,-4)
	game.camera.size=23
	game.camera.position=middle+Vector3(0,23,22)
	game.camera.look_at(middle)
	game.camera.current=true
	await create_timer(.12).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/slash-arc.png")
	await create_timer(.5).timeout
	assert(game.effects.find_child("SlashArc",false,false)==null)
	print("NIGHTFALL_SLASH_FX_OK")
	quit()
