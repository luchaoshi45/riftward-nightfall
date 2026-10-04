extends SceneTree

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
	print("NIGHTFALL_EXPLORATION_MOTIVATION_SCENE_OK production reward hook and route HUD state")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	quit()
