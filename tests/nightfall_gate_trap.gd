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
	game.choose_card(0)
	game.gate_trap_charges=0;game.show_gate_trap_charges()
	game.hero.position=Vector3(0,5,7.0)
	game.move_goal=game.hero.position
	game.scrap=90
	await key(KEY_T)
	assert(game.gate_trap_charges==1 and game.scrap==45)
	assert(game.gate_trap_marks[0].visible)
	assert(game.arm_gate_trap())
	assert(game.gate_trap_charges==2 and game.scrap==0)
	assert(not game.arm_gate_trap())
	game.camera.position=game.hero.position+Vector3(0,25,29)
	await create_timer(.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/gate-trap.png")
	game.phase="night"
	var target: BattleUnit=game.spawn_creature(true)
	target.position=Vector3(0,game.world.terrain_height(Vector3(0,0,9.5)),9.5)
	var previous_hp: float=target.hp
	game.update_gate_trap(.1)
	assert(target.hp<previous_hp)
	assert(game.gate_trap_charges==1)
	game.update_gate_trap(.1)
	assert(game.gate_trap_charges==1)
	var next_target: BattleUnit=game.spawn_creature(true)
	next_target.position=Vector3(0,game.world.terrain_height(Vector3(0,0,9.5)),9.5)
	game.update_gate_trap(.8)
	assert(game.gate_trap_charges==0)
	assert(not game.gate_trap_marks[0].visible and not game.gate_trap_marks[1].visible)
	print("NIGHTFALL_GATE_TRAP_OK")
	quit()
