extends SceneTree
## Production mode selection, four-night progression and the standard wave ledger.

var game: Node3D
var failures: Array[String] = []

func _initialize() -> void:
	root.size = Vector2i(1920,1200)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = root.size
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:return
	failures.append(message)
	push_error(message)

func press(keycode: Key) -> void:
	var event:=InputEventKey.new()
	event.keycode=keycode
	event.physical_keycode=keycode
	event.pressed=true
	event.echo=false
	root.push_input(event,true)
	event.pressed=false
	root.push_input(event,true)

func click_mode(index: int) -> void:
	game.hud.queue_redraw()
	for _frame in 3:await process_frame
	check(index>=0 and index<game.hud.mode_rects.size(),"The production draft must expose the requested real mode card")
	if index<0 or index>=game.hud.mode_rects.size():return
	var rect: Rect2=game.hud.mode_rects[index]
	var pixel: Vector2=rect.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900)
	var motion:=InputEventMouseMotion.new()
	motion.position=pixel;motion.global_position=pixel
	root.push_input(motion,true)
	await process_frame
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	event.button_mask=MOUSE_BUTTON_MASK_LEFT
	event.position=pixel;event.global_position=pixel
	root.push_input(event,true)
	await process_frame
	event.pressed=false;event.button_mask=0
	root.push_input(event,true)
	await process_frame

func transition() -> void:
	game.phase_time=.01
	game.simulate(.02)
	await process_frame

func clear_enemies() -> void:
	for creature in game.enemies:
		if is_instance_valid(creature):creature.queue_free()
	game.enemies.clear()

func defeat_precision_enemies() -> void:
	# Explicit precision damage exercises registered deaths and wave settlement;
	# it does not claim a naturally affordable strategy or balanced run.
	for creature in game.enemies.duplicate():
		if is_instance_valid(creature) and creature.alive:creature.hurt(100000.0,game.hero)

func run() -> void:
	game=load("res://scenes/nightfall.tscn").instantiate()
	game.archive.enabled=false
	root.add_child(game)
	current_scene=game
	await process_frame
	game.set_process(false)
	check(game.phase=="draft" and game.run_mode=="teaching","A new production run must open in the teaching mode draft")
	await click_mode(2)
	check(game.run_mode=="echo" and game.max_nights()==4,"The mode cards must select the four-night Echo mode by mouse")
	press(KEY_8)
	check(game.run_mode=="siege" and game.max_nights()==4,"8 must select the four-night Iron Tide mode")
	check(game.run_mode_description().contains("破城体"),"The selected standard mode must expose its threat identity")
	press(KEY_1)
	check(game.phase=="night" and game.run_mode_locked,"Selecting the opening core must lock the run mode")
	check(game.night_plan.size()==5 and game.night_plan[0].mode=="siege","The production night plan must use the selected standard mode")
	var first_wave: Dictionary=game.wave_rewards.snapshot(0)
	check(first_wave.budget==24 and first_wave.count==int(game.night_plan[0].count) and first_wave.sealed,"The first standard wave must register and seal its real enemy count")
	var first_enemy: BattleUnit=game.enemies[0]
	var before_scrap: int=game.scrap
	first_enemy.hurt(100000.0,game.hero)
	check(game.wave_rewards.snapshot(0).kills==1 and game.wave_rewards.snapshot(0).paid>0 and game.scrap>before_scrap,"A registered standard death must pay its rolling ledger share")
	for creature in game.enemies.duplicate():
		if is_instance_valid(creature) and creature.alive:creature.hurt(100000.0,game.hero)
	await process_frame
	var cleared_wave: Dictionary=game.wave_rewards.snapshot(0)
	check(cleared_wave.paid==24 and cleared_wave.cleared,"Clearing a standard wave must pay the remaining budget exactly once")
	var duplicate_scrap: int=game.scrap
	if is_instance_valid(first_enemy):first_enemy.hurt(100000.0,game.hero)
	check(game.scrap==duplicate_scrap,"A repeated death signal must not pay a second wave reward")
	clear_enemies()

	# Three completed night/day transitions must lead to a fourth standard night.
	for expected_day in [2,3,4]:
		game.phase_time=.01
		game.simulate(.02)
		await process_frame
		check(game.phase=="night" and game.night_clearance_active,"A completed assault timer must enter real clearance before the next draft")
		defeat_precision_enemies()
		game.simulate(.02)
		await process_frame
		check(game.phase=="draft" and game.day_number==expected_day,"A completed night must advance to the next draft")
		press(KEY_1)
		check(game.phase=="day" and game.day_number==expected_day,"The standard draft must enter its daytime phase")
		game.phase_time=.01
		game.simulate(.02)
		await process_frame
		check(game.phase=="night" and game.day_number==expected_day,"A standard daytime phase must start the selected night")
		clear_enemies()
		if expected_day==4 and DisplayServer.get_name()!="headless":
			game.camera.position=game.hero.position+Vector3(0,25,29)
			game.camera.look_at(game.hero.position)
			game.world.night_mix=1.0
			game.world.set_night(true)
			game.world.apply_lighting()
			game.hud.queue_redraw()
			await create_timer(.35).timeout
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://build")
			check(root.get_texture().get_image().save_png("res://build/nightfall-run-modes.png")==OK,"Standard mode night scene must render")

	# Finish the last standard night without combat damage; the four-night rule must end it.
	# The timer crossing still creates the saved final wave, so remove those
	# real units before the next frame verifies the clearance-only ending.
	game.phase_time=.01
	game.simulate(.02)
	defeat_precision_enemies()
	game.simulate(.02)
	await process_frame
	check(game.phase=="ended" and game.victory and game.day_number==4,"A standard run must finish after its fourth night")

	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	if failures.is_empty():
		print("NIGHTFALL_RUN_MODES_OK")
		quit(0)
	else:
		print("NIGHTFALL_RUN_MODES_FAILED ",failures)
		quit(1)
