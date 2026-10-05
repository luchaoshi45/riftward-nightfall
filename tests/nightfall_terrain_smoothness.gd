extends SceneTree
## The raised terrain must not trigger a full exploration A* search every
## movement frame. This is a production-scene regression for high-ground
## keyboard movement, where the stale marker is cheaper than a blocking query.
const STEP := 1.0 / 60.0
const START_Z := 3.5
var game: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:return
	failures.append(message)
	push_error(message)

func finish(queries: int, first_queries: int) -> void:
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_TERRAIN_SMOOTHNESS_", "OK" if failures.is_empty() else "FAILED",
		" checks=", checks, " guidance_ASTAR_queries=", queries, " first=", first_queries)
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	game=load("res://scenes/nightfall.tscn").instantiate()
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
	if waylight.is_empty():
		await finish(0,0)
		return
	# The expanded castle now contains (10, 10). Place the discovery outside
	# its east wall so guidance still has to search the real south-gate route.
	var point:=Vector3(20.0,0.0,10.0)
	point.y=game.outpost_height(point)
	waylight.position=point
	waylight.node.position=point
	waylight.state="ready"
	game.hero.position=Vector3(0,NightfallWorld.FORT_HEIGHT,START_Z)
	game.move_goal=game.hero.position
	check(game.outpost_walkable(game.hero.position) and game.outpost_walkable(point),"Both route endpoints must be genuinely walkable beyond the six-cell core footprint")
	check(not game.can_traverse(game.hero.position,point),"The first guidance probe must need a wall-aware route rather than a direct line")
	game.discoveries.motivation_route_queries=0
	var first: Dictionary=game.discoveries.motivation_target()
	check(first.get("kind","")==remaining_kind,"The raised-terrain probe must choose the reachable next route type")
	var first_queries: int=game.discoveries.motivation_route_queries
	check(first_queries>0,"The probe must exercise the real A* route around the raised wall")
	for frame in 120:
		var previous: Vector3=game.hero.position
		var z:=START_Z+8.4*STEP*float(frame+1)
		game.hero.position=Vector3(0,game.outpost_height(Vector3(0,0,z)),z)
		check(game.can_traverse(previous,game.hero.position),"High-ground guidance samples must follow the actual open south-gate corridor")
		game.discoveries.tick(STEP)
		var target: Dictionary=game.discoveries.motivation_target()
		check(target.get("kind","")==remaining_kind,"Cached guidance must retain the real reachable discovery throughout movement")
	var queries: int=game.discoveries.motivation_route_queries-first_queries
	check(queries<=11,"High-ground guidance must throttle repeated A* queries while moving (queries=%d)" % queries)
	check(game.discoveries.motivation_cache_cell==Vector2i(floori(game.hero.position.x/2.0),floori(game.hero.position.z/2.0)),"Guidance cache must track the coarse ground cell")
	await finish(queries,first_queries)
