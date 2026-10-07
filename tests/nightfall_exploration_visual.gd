extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
const CONTENT_VIEWPORT := Vector2i(1920, 1200)

func _initialize() -> void:
	root.size = CONTENT_VIEWPORT
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = CONTENT_VIEWPORT
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.position = Vector2i(-10000, -10000)
		root.hide()
	call_deferred("run")

func capture(game: Node3D, path: String) -> void:
	game.hud.queue_redraw()
	await create_timer(.18).timeout
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(picture.get_size() == CONTENT_VIEWPORT and game.hud.get_viewport_rect().size == Vector2(CONTENT_VIEWPORT), "Rendered evidence must use the requested 1920x1200 content viewport")
	assert(picture.save_png(path) == OK, "Actual exploration PNG must save successfully: " + path)

func center_on(game: Node3D, point: Vector3) -> void:
	game.hero.position=point+Vector3(0,0,2.0)
	game.hero.position.y=game.outpost_height(game.hero.position)
	game.move_goal=game.hero.position
	game.hero_path.clear()
	game.world.follow_ashfall(game.hero.position)
	game.camera.size=24
	game.camera.position=game.hero.position+Vector3(0,25,29)
	game.camera.look_at(game.hero.position)
	game.discoveries.tick(0);game.wildlife.tick(0)

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("This test verifies the real rendered viewport");quit(1);return
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.set_process(false)
	assert(game.choose_card(0) and game.phase=="night")
	await capture(game,"res://build/exploration-opening-night.png")
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()
	game.notice_time=0
	for i in 4:
		var item: Dictionary=game.discoveries.items[i]
		center_on(game,item.position)
		await capture(game,"res://build/exploration-"+item.kind+"-game.png")
		assert(game.interact())
		if item.kind=="supply_cache":game.simulate(3.0)
	var cache: Dictionary=game.world.salvage[0]
	center_on(game,cache.position)
	assert(game.interact())
	assert(game.exploration_count==5 and game.exploration_milestones==1)
	await capture(game,"res://build/exploration-milestone-game.png")
	for animal in game.wildlife.animals:
		if animal.kind!="stag":continue
		center_on(game,animal.position)
		await capture(game,"res://build/exploration-neutral-stag-game.png")
		assert(game.interact())
		await capture(game,"res://build/exploration-neutral-reward-game.png")
		break
	TransitionFixture.finish_for_fixture(game);game.choose_card(0)
	assert(game.phase=="day" and game.phase_time==90)
	game.world._process(6)
	center_on(game,game.expeditions.generators[0].position)
	await capture(game,"res://build/exploration-short-day-game.png")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_EXPLORATION_VISUAL_OK real opening, four item prompts, five-visit milestone, neutral reward, ninety-second day")
	quit(0)
