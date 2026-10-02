extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func key(code: int) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=true
	Input.parse_input_event(event)
	for i in 3:await process_frame
	event.pressed=false
	Input.parse_input_event(event)
	for i in 3:await process_frame

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	assert(game.choose_card(0))
	for old_enemy in game.enemies:
		if is_instance_valid(old_enemy):old_enemy.queue_free()
	game.enemies.clear()
	var pad: Dictionary=game.world.tower_pads[0]
	game.hero.position=pad.position+Vector3(.5,0,.5)
	game.move_goal=game.hero.position
	game.scrap=60
	assert(game.interact() and pad.level==1)
	var close_enemy: BattleUnit=game.spawn_creature(false)
	var marked: BattleUnit=game.spawn_creature(false)
	close_enemy.position=pad.position+Vector3(3,0,0)
	marked.position=pad.position+Vector3(6,0,0)
	game.aim=marked.position
	await key(KEY_C)
	assert(game.focus_target==marked and game.focus_time>0 and game.focus_cooldown>0)
	assert(is_instance_valid(game.focus_ring))
	game.set_process(false)
	game.camera.size=22
	game.camera.position=game.hero.position+Vector3(0,25,29)
	game.hud.queue_redraw()
	await create_timer(.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/tower-focus.png")
	var close_hp: float=close_enemy.hp
	var marked_hp: float=marked.hp
	game.update_towers(1.2)
	assert(marked.hp<marked_hp and close_enemy.hp==close_hp)
	assert(not game.issue_focus_order())
	game.update_focus(8.1)
	assert(game.focus_target==null and game.focus_time==0)
	pad.cooldown=0
	game.update_towers(1.2)
	assert(close_enemy.hp<close_hp)
	print("NIGHTFALL_TOWER_FOCUS_OK")
	quit()
