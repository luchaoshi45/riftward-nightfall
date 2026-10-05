extends SceneTree
const Layout = preload("res://scripts/outpost_layout.gd")
## Side-wall cursor regression: clicking the raised ramp flank must resolve to
## the nearest walkable ramp edge instead of the low outer ground.
const TARGET_ZS := [8.0, 9.0, 12.0, 15.0]
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(condition: bool, message: String) -> void:
	if condition:return
	failures.append(message)
	push_error(message)
func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	game.phase="day"
	game.camera.size=48.0
	game.camera.position=Vector3(5,25,43+Layout.EXPANSION_OFFSET)
	game.camera.look_at(Vector3(5,0,14+Layout.EXPANSION_OFFSET))
	for side in [-1.0,1.0]:
		for original_z in TARGET_ZS:
			var z:float=original_z+Layout.EXPANSION_OFFSET
			var wall_point:=Vector3(3.2*side,game.outpost_height(Vector3(3.2*side,0,z)),z)
			var screen: Vector2=game.camera.unproject_position(wall_point)
			var resolved: Vector3=game.ground_point(screen)

			check(absf(resolved.x)<=game.hero_ramp_side_limit(resolved.z)+.001,
				"Side-wall click must resolve inside the ramp visual corridor at x=%.1f z=%.1f" % [wall_point.x,z])
			check(resolved.z>=7.49+Layout.EXPANSION_OFFSET and resolved.z<=18.56+Layout.EXPANSION_OFFSET,
				"Side-wall click must remain on the raised ramp z corridor at x=%.1f z=%.1f" % [wall_point.x,z])
			check(absf(resolved.z-z)<1.21,
				"Side-wall click must preserve nearby forward position at x=%.1f z=%.1f (resolved z=%.2f)" % [wall_point.x,z,resolved.z])
			check(game.outpost_walkable(resolved),
				"Side-wall click must resolve to a walkable endpoint at x=%.1f z=%.1f" % [wall_point.x,z])
			game.hero.position=Vector3(15.0+Layout.EXPANSION_OFFSET,0,25.0+Layout.EXPANSION_OFFSET)
			game.hero.position.y=game.outpost_height(game.hero.position)
			game.plan_hero_path(resolved)
			check(not game.hero_path.is_empty() or game.move_goal.distance_to(resolved)<.25,
				"Side-wall route must produce a reachable endpoint at x=%.1f z=%.1f" % [wall_point.x,z])
			# The imported side wall is wider than the ramp's walkable centre. A
			# cursor ray through that outer edge must still resolve to the nearby
			# ramp corridor instead of the low ground behind it.
			for outer_x in [2.8,3.2,3.8,3.94]:
				var outer_seed:=Vector3(outer_x*side,game.outpost_height(Vector3(3.2*side,0,z)),z)
				var outer_screen: Vector2=game.camera.unproject_position(outer_seed)
				var outer_resolved: Vector3=game.ground_point(outer_screen)
				check(outer_resolved.y>0.0 and absf(outer_resolved.x)<=game.hero_ramp_side_limit(outer_resolved.z)+.01,
					"Outer ramp-wall ray must stay on the raised corridor at x=%.2f z=%.1f" % [outer_seed.x,z])
				check(absf(outer_resolved.z-z)<1.3,
					"Outer ramp-wall ray must preserve its nearby z at x=%.2f z=%.1f (resolved z=%.2f)" % [outer_seed.x,z,outer_resolved.z])
	print("NIGHTFALL_HIGH_GROUND_EDGE_CLICK_", "OK" if failures.is_empty() else "FAILED")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit(0 if failures.is_empty() else 1)
