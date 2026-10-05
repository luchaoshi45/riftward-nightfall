extends SceneTree
## Production E dash must honor each owned 踏风者 layer without bypassing walls.

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:return
	push_error(message)
	quit(1)

func reset_case(game: Node3D, layers: int, origin: Vector3, direction: Vector3) -> void:
	game.phase="day"
	game.run.owned["stride"]=layers
	game.run.recalculate()
	game.hero.position=origin
	game.hero.position.y=game.outpost_height(game.hero.position)
	game.move_goal=game.hero.position
	game.hero_path.clear()
	game.aim=game.hero.position+direction.normalized()*20.0
	game.cooldowns[2]=0.0
	game.hero.moving=false

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	game.mana=game.max_mana
	var origin:=Vector3(-30.0,0.0,0.0)
	var direction:=Vector3.FORWARD
	var expected: Array[float]=[6.0,6.8,7.6]
	for layers in 3:
		reset_case(game,layers,origin,direction)
		var before: Vector3=game.hero.position
		check(game.cast(2),"E must cast with %d 踏风者层数" % layers)
		var travel:=Vector2(game.hero.position.x-before.x,game.hero.position.z-before.z).length()
		check(absf(travel-expected[layers])<.001,"E distance must be %.1f metres at %d layers, got %.3f" % [expected[layers],layers,travel])
		check(is_equal_approx(game.hero.position.y,game.outpost_height(game.hero.position)),"E arrival must stay on the terrain profile")

	# A paused cast cannot consume cooldown or move, even when a longer dash is
	# equipped.
	reset_case(game,2,origin,direction)
	game.phase="paused"
	var paused_position: Vector3=game.hero.position
	check(not game.cast(2),"Paused E must be rejected")
	check(game.hero.position.is_equal_approx(paused_position) and game.cooldowns[2]==0.0,"Paused E must not move or start cooldown")

	# The longer request still respects the fortress clearance corridor.
	var wall_origin:=Vector3(6.0,0.0,-4.0)
	wall_origin.y=game.outpost_height(wall_origin)
	reset_case(game,2,wall_origin,Vector3.RIGHT)
	var wall_before: Vector3=game.hero.position
	check(game.cast(2),"E near the raised wall must remain usable")
	check(game.outpost_walkable(game.hero.position),"E must not place the hero inside the raised wall")
	check(game.can_traverse(wall_before,game.hero.position),"E must not cross a retaining wall")
	check(Vector2(game.hero.position.x-wall_before.x,game.hero.position.z-wall_before.z).length()<=game.dash_distance()+.001,"A blocked longer E must not overshoot its requested distance")

	# A dash starting inside the ramp keeps that corridor's clearance even
	# when its raw endpoint lies in a side wall. Resolve using its real origin.
	for side in [-1.0,1.0]:
		reset_case(game,0,Vector3(side*2.5,0,7.6),Vector3(side*.2,0,.98))
		var ramp_before: Vector3=game.hero.position
		check(game.cast(2),"Ramp-edge E must cast on side %.0f" % side)
		check(game.can_traverse(ramp_before,game.hero.position),"Ramp-edge E must remain on its side of the wall")
		check(absf(game.hero.position.x)<=game.hero_ramp_side_limit(game.hero.position.z)+.001,"Ramp-edge E must arrive inside the visual corridor")
		check(Vector2(game.hero.position.x-ramp_before.x,game.hero.position.z-ramp_before.z).length()>5.4,"Ramp-edge E must preserve useful travel instead of consuming mana in place")
	reset_case(game,0,Vector3(5,0,1),Vector3.BACK)
	var courtyard_before: Vector3=game.hero.position
	check(game.cast(2),"Courtyard E towards the south wall must cast")
	check(game.can_traverse(courtyard_before,game.hero.position),"Courtyard E must not cross the south retaining wall")
	check(absf(game.hero.position.z-game.HERO_FORT_SAFE_EDGE)<.001 and game.hero.position.z-courtyard_before.z>5.0,"Courtyard E must shorten to the inner safe edge instead of stopping in place")

	print("NIGHTFALL_STRIDE_DASH_OK layers=0/1/2 distances=6.0/6.8/7.6, pause and wall clearance")
	await game.prepare_shutdown()
	game.free()
	await process_frame
	await create_timer(.5).timeout
	quit()
