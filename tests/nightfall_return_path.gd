extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func follow(game: Node3D, from: Vector3, destination: Vector3, require_detour: bool) -> bool:
	game.hero.position=from
	game.move_goal=from
	game.plan_hero_path(destination)
	if require_detour and game.hero_path.size()<2:
		push_error("Blocked straight line did not produce a route through the south gate")
		return false
	var previous: Vector3=game.hero.position
	for step in range(1100):
		game.move_hero(.06)
		if not game.outpost_walkable(game.hero.position) or not game.can_traverse(previous,game.hero.position):
			push_error("Path crossed a wall")
			return false
		previous=game.hero.position
		if game.hero.position.distance_to(destination)<.28:break
	if game.hero.position.distance_to(destination)>=.28:
		push_error("Click-to-move did not reach the requested destination")
		return false
	return true

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	assert(game.choose_card(0))
	game.set_process(false)
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()
	var home:=Vector3(0,5,3.1)
	if not follow(game,Vector3(7,0,25),home,true):quit(1);return
	if not follow(game,Vector3(-8,0,26),home,true):quit(1);return
	if not follow(game,Vector3(0,0,29),home,false):quit(1);return
	if not follow(game,home,Vector3(8,0,27),true):quit(1);return
	print("NIGHTFALL_RETURN_PATH_OK")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit()
