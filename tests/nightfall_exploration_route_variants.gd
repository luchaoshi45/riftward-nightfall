extends SceneTree
## Seeded exploration routes must vary between runs while remaining replayable.

const MotivationScript=preload("res://scripts/exploration_motivation.gd")

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:return
	push_error(message)
	quit(1)

func run() -> void:
	var owner:=Node3D.new()
	root.add_child(owner)
	var first:=MotivationScript.new()
	var same_seed:=MotivationScript.new()
	var other_seed:=MotivationScript.new()
	owner.add_child(first);owner.add_child(same_seed);owner.add_child(other_seed)
	first.setup(owner,17)
	same_seed.setup(owner,17)
	other_seed.setup(owner,21)
	first.begin_day(1)
	same_seed.begin_day(1)
	other_seed.begin_day(1)
	var first_order: Array[String]=first.route_order.duplicate()
	check(first_order==same_seed.route_order,"The same seed/day must recreate the same exploration order")
	check(first_order!=other_seed.route_order,"Different run seeds must produce a different exploration order")
	var first_day_order:=first_order.duplicate()
	first.begin_day(2)
	same_seed.begin_day(2)
	check(first.route_order==same_seed.route_order,"The same seed must stay deterministic on later daylight phases")
	check(first.route_order!=first_day_order,"A later daylight phase must rotate the route")

	# The complete-search bonus remains a set bonus, so the order changes the
	# next target without making players discover one exact permutation.
	first.reset_run();first.begin_day(1)
	for index in 3:
		var partial: Dictionary=first.record(first.route_order[index],Vector3.ZERO,"day")
		check(not first.full_set_claimed and partial.scrap<52 and not partial.has("memory"),"The full-set reward must wait for all four route types")
	var completed: Dictionary=first.record(first.route_order[3],Vector3.ZERO,"day")
	check(first.full_set_claimed and completed.scrap==52 and not completed.has("memory"),"Any seeded route order must award the full set once")
	var repeat: Dictionary=first.record(first.route_order[0],Vector3.ZERO,"day")
	check(repeat.scrap<52 and not repeat.has("memory"),"Repeating a route type must not replay the full-set reward")

	# Production wiring passes the real RunBuild seed and P guidance follows the
	# current route order rather than the constant declaration order.
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	check(game.exploration.route_seed==game.run.seed_value,"Production exploration must use the run seed")
	game.phase="day"
	game.exploration.setup(game,17)
	game.exploration.begin_day(1)
	var production_order: Array[String]=game.exploration.route_order.duplicate()
	game.exploration.record(production_order[0],game.hero.position,"day")
	var target: Dictionary=game.discoveries.motivation_target()
	check(target.get("kind","")==production_order[1],"P guidance must follow the seeded next route type")
	var frozen_order: Array[String]=game.exploration.route_order.duplicate()
	game.phase="paused"
	game.simulate(10.0)
	game.exploration.tick(10.0)
	check(game.exploration.route_order==frozen_order and game.exploration.next_kind()==production_order[1],"Pause must not advance the exploration route")
	game.phase="draft"
	game.simulate(10.0)
	game.exploration.tick(10.0)
	check(game.exploration.route_order==frozen_order,"Draft must not advance the exploration route")

	print("NIGHTFALL_EXPLORATION_ROUTE_VARIANTS_OK same-seed replay, day rotation, set reward, production P guidance and pause freeze")
	await game.prepare_shutdown()
	game.free()
	first.queue_free();same_seed.queue_free();other_seed.queue_free();owner.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit()
