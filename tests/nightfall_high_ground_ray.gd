extends SceneTree
## Production camera-ray regression for the raised outpost's outer slope.

const X_SAMPLES := [4.0,4.5,5.0,6.0]
const Z_SAMPLES := [8.0,9.0,10.0,12.0]
var failures: Array[String]=[]

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
	game.camera.position=Vector3(5,25,43)
	game.camera.look_at(Vector3(5,0,14))
	for side in [-1.0,1.0]:
		for x_value in X_SAMPLES:
			for z_value in Z_SAMPLES:
				var point:=Vector3(side*x_value,0,z_value)
				point.y=game.outpost_height(point)
				var screen: Vector2=game.camera.unproject_position(point)
				var resolved: Vector3=game.ground_point(screen)
				check(resolved.distance_to(point)<.30,
					"Outer high-ground ray must converge near x=%.1f z=%.1f (resolved %s)" % [point.x,z_value,resolved])
				check(absf(resolved.z-z_value)<.30,
					"Outer high-ground ray must not jump along z at x=%.1f z=%.1f" % [point.x,z_value])
	print("NIGHTFALL_HIGH_GROUND_RAY_", "OK" if failures.is_empty() else "FAILED", " samples=", X_SAMPLES.size()*Z_SAMPLES.size()*2)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit(0 if failures.is_empty() else 1)
