extends SceneTree
## The raised terrain must not trigger a full exploration A* search every
## movement frame. This is a production-scene regression for high-ground
## keyboard movement, where the stale marker is cheaper than a blocking query.
const STEP := 1.0 / 60.0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:return
	push_error(message)
	quit(1)

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	game.phase="day"
	game.exploration.reset_run()
	game.exploration.begin_day()
	var route: Array[String]=game.exploration.route_order.duplicate()
	for index in 3:game.exploration.record(route[index],game.hero.position,"day")
	var remaining_kind: String=route[3]
	var waylight: Dictionary={}
	for item: Dictionary in game.discoveries.items:
		if item.kind!=remaining_kind:continue
		if waylight.is_empty():waylight=item
		else:game.discoveries.begin_cooling(item,60.0)
	check(not waylight.is_empty(),"A production waylight must remain for the raised-terrain route probe")
	var point:=Vector3(10.0,0.0,10.0)
	point.y=game.outpost_height(point)
	waylight.position=point
	waylight.node.position=point
	waylight.state="ready"
	game.hero.position=Vector3(0,NightfallWorld.FORT_HEIGHT,3.1)
	game.move_goal=game.hero.position
	game.discoveries.motivation_route_queries=0
	var first: Dictionary=game.discoveries.motivation_target()
	check(first.get("kind","")==remaining_kind,"The raised-terrain probe must choose the reachable next route type")
	var first_queries: int=game.discoveries.motivation_route_queries
	check(first_queries>0,"The probe must exercise the real A* route around the raised wall")
	for frame in 120:
		var z:=3.1+8.4*STEP*float(frame+1)
		game.hero.position=Vector3(0,game.outpost_height(Vector3(0,0,z)),z)
		game.discoveries.tick(STEP)
		game.discoveries.motivation_target()
	var queries: int=game.discoveries.motivation_route_queries-first_queries
	check(queries<=11,"High-ground guidance must throttle repeated A* queries while moving (queries=%d)" % queries)
	check(game.discoveries.motivation_cache_cell==Vector2i(floori(game.hero.position.x/2.0),floori(game.hero.position.z/2.0)),"Guidance cache must track the coarse ground cell")
	print("NIGHTFALL_TERRAIN_SMOOTHNESS_OK guidance_ASTAR_queries=",queries," first=",first_queries)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit()
