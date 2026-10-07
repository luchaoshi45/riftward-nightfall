extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
const Layout := preload("res://scripts/outpost_layout.gd")

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.position = Vector2i(-10000, -10000)
		root.hide()
	call_deferred("run")

func frames(count: int=5) -> void:
	for i in count:await process_frame

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await frames(12)
	game.set_process(false)
	assert(game.choose_card(0) and game.phase=="night")
	# Independent positioning fixture; actual building still requires the
	# current authored gate controls, and movement/hits below use production.
	game.hero.position=Vector3(0,game.world.terrain_height(Vector3(0,0,8)),8)
	game.scrap=100
	assert(not game.near_gate_controls() and not game.build_gate_barricade() and game.scrap==100, "The old pre-expansion position must not bypass the current building distance")
	game.hero.position=Layout.gate_point(-.3)
	game.move_goal=game.hero.position
	game.hero_path.clear()
	assert(game.near_gate_controls() and game.outpost_walkable(game.hero.position), "The real shared gate position must satisfy the building controls")
	var build_key:=InputEventKey.new()
	build_key.keycode=KEY_B
	build_key.pressed=true
	game._unhandled_input(build_key)
	assert(game.gate_barricade_hp==game.BARRICADE_MAX and game.gate_barricade.visible)
	assert(game.scrap==100-game.BARRICADE_COST)
	assert(not game.build_gate_barricade())
	assert(game.outpost_walkable(game.gate_barricade.position),"The hero must be able to vault the temporary barricade")
	var creature: BattleUnit=game.spawn_creature(true,"breaker")
	creature.position=game.gate_barricade.position+Vector3(0,0,.9)
	creature.position.y=game.outpost_height(creature.position)
	assert(game.outpost_walkable(creature.position) and String(game.choose_enemy_target(creature).kind)=="barricade", "Original-role breaker must legally target the nearby real roadblock")
	var old_hp: float=game.gate_barricade_hp
	var saw_windup:=false
	for i in 40:
		var previous:=creature.position
		creature.tick(.05)
		game.update_creature(creature,.05)
		assert(game.can_traverse(previous,creature.position), "Actual breaker steps must respect the authored ramp")
		if creature.attack_queued and creature.attack_windup>0:
			saw_windup=true
			assert(creature.attack_target_barricade and game.gate_barricade_hp==old_hp, "Original breaker windup must target the roadblock without early damage")
		if game.gate_barricade_hp<old_hp:break
	assert(saw_windup and creature.attack_target_barricade and creature.position.z>game.gate_barricade.position.z)
	assert(game.gate_barricade_hp<old_hp and game.beacon_hp==game.BEACON_MAX)
	game.damage_gate_barricade(350.0)
	assert(game.gate_barricade_ring.material_override.albedo_color==Color("d35f54"))
	if DisplayServer.get_name()!="headless":
		await frames(2)
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png("res://build/nightfall-barricade.png")==OK, "Actual roadblock screenshot must save in the local build directory")
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
	TransitionFixture.finish_for_fixture(game)
	assert(game.gate_barricade_hp==0.0 and not game.gate_barricade.visible)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_BARRICADE_OK")
	quit(0)
