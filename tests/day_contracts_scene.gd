extends SceneTree
const Contracts = preload("res://scripts/day_contracts.gd")
var requests := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	assert(game.phase == "draft")
	assert(game.choose_card(0) and game.phase == "night")
	var module := Contracts.new()
	game.add_child(module)
	module.setup(game, 17)
	module.on_day()
	assert(module.status == "idle", "Opening night must not create a contract")
	game.finish_night()
	assert(game.day_number == 2 and game.phase == "draft")
	assert(game.choose_card(0) and game.phase == "day")
	module.on_day()
	var available := module.candidates()
	var kinds: Dictionary = {}
	for candidate in available: kinds[candidate.kind] = true
	assert(kinds.size() == 4, "Real scene must offer four existing action categories")
	var chosen_kind: String = module.kind
	var chosen_index: int = module.targets[0].index
	module.on_day()
	assert(module.kind == chosen_kind and module.targets[0].index == chosen_index)
	var replay := Contracts.new()
	game.add_child(replay)
	replay.setup(game, 17)
	replay.on_day()
	assert(replay.kind == chosen_kind and replay.targets[0].index == chosen_index)
	replay.queue_free()
	# Find a reproducible seed for each category; execute existing real scene actions.
	for category: String in ["salvage", "generator", "escort", "nest"]:
		var found := false
		for seed_value in 200:
			module.setup(game, seed_value)
			module.on_day()
			if module.kind == category:
				found = true
				break
		assert(found)
		game.hero.position = module.targets[0].position
		game.move_goal = game.hero.position
		game.phase = "paused"
		module.tick(100.0)
		assert(module.done.is_empty() and module.status == "active")
		game.phase = "draft"
		module.tick(100.0)
		assert(module.done.is_empty())
		game.phase = "day"
		game.phase_time = 60.0
		var original_scrap: int = game.scrap
		for target in module.targets:
			var source: Dictionary = target.source
			match category:
				"salvage":
					# Exercise the actual controller interaction and original rewards.
					game.hero.position = target.position
					assert(game.nearest_salvage() == int(target.index))
					assert(game.interact() and source.collected)
				"generator":
					game.hero.position = source.position
					assert(game.expeditions.interact())
					# Remove fixture ambushes to isolate existing hold-circle completion.
					for enemy in source.guards: enemy.queue_free()
					source.guards = []
					game.expeditions.tick(6.0)
					module.tick(0.0)
					assert("50%" in module.progress_text() and module.done.is_empty())
					game.phase = "paused"
					module.tick(100.0)
					assert(source.progress == 6.0)
					game.phase = "day"
					game.expeditions.tick(6.0)
					assert(source.state == "complete")
				"escort":
					game.hero.position = source.position
					assert(game.expeditions.interact())
					source.npc.position = Vector3(0,5,0)
					game.hero.position = Vector3(0,5,0)
					game.expeditions.tick(0.0)
					assert(source.state == "delivered")
				"nest":
					game.hero.position = source.position
					for enemy in game.enemies: enemy.queue_free()
					game.enemies.clear()
					assert(game.interact() and source.cleansed)
			# Real exploration can open a card; the module must wait for resume.
			game.phase = "day"
			module.on_action()
			if category == "salvage" and module.done.size() == 1:
				assert(module.status == "active" and "1/2" in module.progress_text())
				assert(module.take_reward_request().is_empty())
		assert(module.done.size() == module.targets.size())
		assert(not module.progress_text().is_empty())
		if category == "generator": game.phase_time = 10.0
		game.hero.position = Vector3(0,0,0)
		module.tick(0.0)
		if category != "escort": assert(module.status == "active", "Ground below fort is not a hand-in")
		game.hero.position = Vector3(0,5,0)
		module.tick(0.0)
		assert(module.status == "completed")
		var after_action_scrap: int = game.scrap
		var reward := module.take_reward_request()
		assert(reward.scrap == (30 if category == "generator" else 40) and reward.memory == 8 and reward.day == 2)
		assert(game.scrap == after_action_scrap, "Module must request, never silently apply rewards")
		assert(game.scrap >= original_scrap)
		for repeat in 3:
			module.tick(1.0)
			module.on_day()
			assert(module.take_reward_request().is_empty())
		requests += 1
	assert(requests == 4)
	module.setup(game, 9)
	module.on_day()
	var hp: float = game.beacon_hp
	game.phase_time = 0.0
	module.tick(0.1)
	assert(module.status == "expired" and module.take_reward_request().is_empty())
	assert(game.beacon_hp == hp and not game.victory)
	module.on_day()
	assert(module.status == "expired", "Same day must not redraw after sunset")
	game.start_night()
	module.on_night()
	game.finish_night()
	assert(game.day_number == 3 and game.phase == "draft")
	assert(game.choose_card(0) and game.phase == "day")
	module.on_day()
	assert(module.day_id == 3 and module.status in ["active", "unavailable"])
	game.start_night()
	module.on_night()
	game.finish_night()
	assert(game.phase == "ended" and game.victory)
	module.tick(10.0)
	assert(module.take_reward_request().is_empty())
	# Exhausted objectives are optional: no impossible or already-completed target.
	game.phase = "day"
	game.day_number = 4
	for source in game.world.salvage: source.collected = true
	for source in game.world.nests: source.cleansed = true
	for source in game.expeditions.generators: source.state = "complete"
	for source in game.expeditions.camps: source.state = "delivered"
	module.on_day()
	assert(module.status == "unavailable" and module.targets.is_empty())
	assert(module.take_reward_request().is_empty())
	print("DAY_CONTRACTS_SCENE_OK: four real actions, replay, freeze, one-shot, sunset, three nights")
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	quit()
