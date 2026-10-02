extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await create_timer(.2).timeout
	assert(game.choose_card(0))
	game.begin_day();game.spawn_nest_guards()
	assert(game.world.nests.size()==3 and game.remaining_nests()==3)
	var base_pack: int=game.initial_night_pack()
	var base_interval: float=game.night_spawn_interval()
	var nest: Dictionary=game.world.nests[0]
	game.hero.position=nest.position+Vector3(1,0,0)
	game.move_goal=game.hero.position
	game.camera.position=game.hero.position+Vector3(0,25,29)
	game.notice_time=0
	await create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/night-nest.png")
	assert(game.nest_guarded(nest.position))
	assert(not game.interact(),"Nest cannot be closed while guards remain")
	for creature in game.enemies:
		if creature.position.distance_to(nest.position)<6.5:creature.position=Vector3(90,0,90)
	assert(game.interact() and nest.cleansed)
	assert((nest.sealed_node as Node3D).visible)
	await create_timer(.75).timeout
	assert(not (nest.node as Node3D).visible)
	assert(is_equal_approx((nest.sealed_node as Node3D).scale.x,1.0))
	assert(nest.sealed_light.light_energy>.7)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/sealed-nest.png")
	assert(game.remaining_nests()==2 and game.scrap>=90)
	assert(game.initial_night_pack()==base_pack-2)
	assert(game.night_spawn_interval()>base_interval)
	game.start_night()
	assert(game.enemies.size()==game.initial_night_pack())
	for creature in game.enemies:assert(creature.position.z>30)
	print("NIGHTFALL_NESTS_OK")
	quit()
