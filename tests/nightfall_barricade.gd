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
	game.phase="night"
	game.hero.position=Vector3(0,game.world.terrain_height(Vector3(0,0,8)),8)
	game.move_goal=game.hero.position
	game.scrap=100
	var build_key:=InputEventKey.new()
	build_key.keycode=KEY_B
	build_key.pressed=true
	game._unhandled_input(build_key)
	assert(game.gate_barricade_hp==game.BARRICADE_MAX and game.gate_barricade.visible)
	assert(game.scrap==100-game.BARRICADE_COST)
	assert(not game.build_gate_barricade())
	assert(game.outpost_walkable(game.gate_barricade.position),"The hero must be able to vault the temporary barricade")
	var creature: BattleUnit=game.spawn_creature(true)
	creature.position=Vector3(0,game.world.terrain_height(Vector3(0,0,15)),15)
	creature.set_meta("threat","breaker")
	creature.attack_timer=0.0
	for i in 10:
		creature.tick(.1)
		game.update_creature(creature,.1)
	assert(creature.attack_target_barricade and creature.position.z>game.gate_barricade.position.z)
	var old_hp: float=game.gate_barricade_hp
	creature.attack_windup=0.0
	game.update_creature(creature,.1)
	assert(game.gate_barricade_hp<old_hp and game.beacon_hp==game.BEACON_MAX)
	game.damage_gate_barricade(350.0)
	assert(game.gate_barricade_ring.material_override.albedo_color==Color("d35f54"))
	await frames(2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/nightfall_barricade.png")
	game.damage_gate_barricade(1000.0)
	assert(game.gate_barricade_hp==0.0 and not game.gate_barricade.visible)
	var old_z: float=creature.position.z
	for i in 15:
		creature.tick(.1)
		game.update_creature(creature,.1)
	assert(creature.position.z<old_z,"Night creature should resume gate attack after the barricade breaks")
	assert(not game.build_gate_barricade() and game.scrap==35)
	game.scrap=game.BARRICADE_COST
	assert(game.build_gate_barricade())
	game.finish_night()
	assert(game.gate_barricade_hp==0.0 and not game.gate_barricade.visible)
	print("NIGHTFALL_BARRICADE_OK")
	quit()
