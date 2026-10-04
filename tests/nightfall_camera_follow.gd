extends SceneTree
## Production-scene regression for camera response over the raised outpost.
## Outer-ground travel keeps the readable glide; high-ground travel must not
## leave the fixed-angle camera far enough behind to look like a terrain snag.
const STEP := 1.0 / 60.0
const CAMERA_OFFSET := Vector3(0, 25, 29)

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:return
	push_error(message)
	quit(1)

func target_for(point: Vector3) -> Vector3:
	return point+CAMERA_OFFSET

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	var camera_basis: Basis=game.camera.global_transform.basis

	# The outer ground retains the old deliberate glide so the view does not
	# become twitchy while travelling through the open perimeter.
	var flat:=Vector3(35.0,0.0,35.0)
	game.hero.position=flat
	game.camera_follow=target_for(flat)
	for frame in 30:
		flat.z-=game.hero.speed*STEP
		game.hero.position=flat
		game._process(STEP)
	var flat_lag:=absf(game.camera_follow.z-target_for(flat).z)
	check(flat_lag>.8 and flat_lag<1.6,
		"Outer-ground camera follow must retain a readable horizontal glide")

	# On the raised courtyard the faster response keeps the fixed camera close
	# while the hero crosses the same distance at full movement speed.
	var high:=Vector3(-2.0,0.0,3.1)
	high.y=game.outpost_height(high)
	check(high.y>=1.0,"High-ground camera probe must begin on the raised outpost")
	game.hero.position=high
	game.camera_follow=target_for(high)
	for frame in 30:
		high.x+=game.hero.speed*STEP
		high.y=game.outpost_height(high)
		game.hero.position=high
		game._process(STEP)
	var high_lag:=absf(game.camera_follow.x-target_for(high).x)
	check(high_lag>.35 and high_lag<.9,
		"High-ground camera follow must stay responsive without snapping")
	check(game.camera.global_transform.basis.is_equal_approx(camera_basis),
		"Camera response must preserve the fixed view direction")
	print("NIGHTFALL_CAMERA_FOLLOW_OK flat_lag=",flat_lag," high_lag=",high_lag)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit()
