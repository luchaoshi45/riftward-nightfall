extends SceneTree
## High-ground input regression: coalesce mouse terrain samples and keep the
## hero advancing when a short edge step is temporarily rejected.
const STEP := 1.0 / 30.0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:return
	push_error(message)
	quit(1)

func key(code: int, pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	game.phase="day"

	# A trackpad can emit many motion events before one rendered frame. The
	# latest event should replace the pending point instead of solving the
	# sloped terrain once per event.
	game.ground_point_queries=0
	for index in 120:
		var motion:=InputEventMouseMotion.new()
		motion.position=Vector2(280.0+float(index)*.7,330.0+sin(float(index)*.12)*18.0)
		game._unhandled_input(motion)
	check(game.ground_point_queries==0,"High-ground mouse motion must defer terrain sampling until the frame flush")
	check(game.aim_sample_pending,"The latest mouse position must remain pending")
	game.flush_pending_aim()
	check(game.ground_point_queries==1,"A burst of mouse motion must collapse to one terrain sample")
	check(not game.aim_sample_pending,"Flushing the pending aim must clear the sample")

	# A right-click is an intentional route request and still resolves
	# immediately, so a click never waits for the deferred aim update.
	var before_click: int=game.ground_point_queries
	var click:=InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_RIGHT
	click.button_mask=MOUSE_BUTTON_MASK_RIGHT
	click.position=Vector2(420,360)
	click.global_position=click.position
	click.pressed=true
	game._unhandled_input(click)
	check(game.ground_point_queries==before_click+1,"A right-click must sample its route point immediately")
	check(not game.aim_sample_pending,"A click must consume the stale deferred mouse sample")

	# Entering the raised ramp beside its retaining wall must not produce
	# repeated zero-distance frames at a low render cadence.
	var point:=Vector3(2.45,0,7.55)
	point.y=game.outpost_height(point)
	game.hero.position=point
	game.move_goal=point
	game.hero_path.clear()
	game.hero_keyboard_active=false
	var previous:=point
	var minimum_step:=INF
	var zero_frames:=0
	await key(KEY_D,true)
	await key(KEY_S,true)
	for _frame in 36:
		game.simulate(STEP)
		var travelled:=Vector2(previous.x-game.hero.position.x,previous.z-game.hero.position.z).length()
		minimum_step=minf(minimum_step,travelled)
		if travelled<.025:zero_frames+=1
		else:zero_frames=0
		previous=game.hero.position
	check(game.hero.position.z>10.0,"Low-FPS diagonal input must enter the raised ramp")
	check(minimum_step>.05,"Raised-ramp edge input must keep a visible movement step")
	check(zero_frames<=1,"Raised-ramp edge input must not stall for consecutive frames")
	await key(KEY_D,false)
	await key(KEY_S,false)

	print("NIGHTFALL_HIGH_GROUND_INPUT_OK samples=",game.ground_point_queries," min_step=",minimum_step)
	await game.prepare_shutdown()
	game.free()
	await process_frame
	await create_timer(.5).timeout
	quit()
