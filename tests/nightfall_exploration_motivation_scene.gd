extends SceneTree
const Layout = preload("res://scripts/outpost_layout.gd")

func _initialize() -> void:
	call_deferred("run")

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	await press(KEY_1)
	assert(game.phase=="night")
	game.essence=0
	game.grant_exploration_reward("路线花",game.hero.position,0,0,0.0,0.0,"ember_bloom")
	game.grant_exploration_reward("路线晶簇",game.hero.position,0,0,0.0,0.0,"memory_crystal")
	assert(game.exploration.streak==2)
	assert(game.exploration.speed_bonus_value()>.7)
	game.exploration.set_waylight_count(2)
	var before: int=game.essence
	game.grant_exploration_reward("路线箱",game.hero.position,0,0,0.0,0.0,"supply_cache")
	assert(game.essence>=before+6,"A three-step route grants its memory bonus")
	assert(game.exploration.route_text().contains("路线"))
	# Production route guidance must choose a reachable next type rather than
	# the nearest straight-line point. Put the only remaining waylight behind
	# the raised-wall geometry and require the real A* route for P guidance.
	game.finish_night()
	await press(KEY_1)
	assert(game.phase=="day")
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
	assert(not waylight.is_empty())
	var waylight_point:=Vector3(Layout.FORT_TERRAIN_EDGE+.5,0.0,Layout.WALL_CENTER+2.7)
	waylight_point.y=game.outpost_height(waylight_point)
	waylight.position=waylight_point
	waylight.node.position=waylight_point
	waylight.state="ready"
	game.hero.position=Vector3(0,5,3.1)
	var target: Dictionary=game.discoveries.motivation_target()
	assert(int(target.index)>=0 and target.kind==remaining_kind)
	assert(float(target.distance)>game.hero.position.distance_to(waylight_point),"Motivation distance must use the reachable route around the raised wall")
	game.update_exploration_guidance()
	assert(is_instance_valid(game.motivation_marker),"The next exploration type must receive a world marker")
	assert(game.follow_exploration() and not game.hero_path.is_empty(),"P guidance must create a route to the next exploration type")
	var previous: Vector3=game.hero.position
	for point in game.hero_path:
		assert(game.can_traverse(previous,point),"Exploration guidance must use traversable route points")
		previous=point
	game.discoveries.begin_cooling(waylight,60.0)
	game.update_exploration_guidance()
	assert(game.discoveries.motivation_target().is_empty(),"Consumed next type must clear its guidance target")
	print("NIGHTFALL_EXPLORATION_MOTIVATION_SCENE_OK production reward hook, route HUD state, reachable next-type guidance")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	quit()
