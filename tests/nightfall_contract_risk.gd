extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
## Production test for real daytime contract risk hunters.
const STEP := 0.05
var game: Node3D
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:return
	failures.append(message)
	push_error(message)

func clear_enemies() -> void:
	for unit in game.enemies:
		if is_instance_valid(unit):unit.queue_free()
	game.enemies.clear()

func boot_day() -> bool:
	game=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.set_process(false)
	check(game.choose_card(0) and game.phase=="night", "Opening card must enter the production night before risk testing")
	clear_enemies()
	game.run.seed_value=0
	game.contracts.setup(game,0)
	TransitionFixture.finish_for_fixture(game)
	check(game.phase=="draft" and game.day_number==2, "Finishing the first night must reach the second-day draft")
	check(game.choose_card(0) and game.phase=="day", "Dawn card must enter the production day with contracts")
	return game.phase=="day" and game.contracts.status=="active"

func contract_hunters() -> Array[BattleUnit]:
	var result: Array[BattleUnit]=[]
	for creature: BattleUnit in game.enemies:
		if is_instance_valid(creature) and creature.get_meta("contract_hunter",false):result.append(creature)
	return result

func move_hero_to_target(target: Dictionary) -> void:
	var point: Vector3=target.position
	point.y=game.outpost_height(point)
	game.hero.position=point
	game.hero_path.clear();game.move_goal=game.hero.position

func run_case(index: int, expected_hunters: int) -> void:
	if not await boot_day():return
	check(game.contracts.offers.size()>=3, "Seed zero must expose all three risk offers")
	for offer_index in mini(3,game.contracts.offers.size()):
		var offer: Dictionary=game.contracts.offers[offer_index]
		check(int(offer.get("risk",-1))==offer_index, "Offer risk index must remain deterministic")
		check(int(offer.get("risk_hunters",-1))==offer_index, "Offer hunter count must map to 0/1/2")
		check(int(offer.get("risk_seconds",-1.0))==offer_index*8, "Offer deadline pressure must remain deterministic")
	check(game.contracts.choose_offer(index), "The selected risk offer must be switchable before the first action")
	var target: Dictionary=game.contracts.targets[0]
	clear_enemies()
	move_hero_to_target(target)
	var acted: bool=game.interact()
	check(acted, "The selected contract must trigger through its real F action")
	var hunters:=contract_hunters()
	check(hunters.size()==expected_hunters, "Risk %d must create exactly %d contract hunters, got %d" % [index,expected_hunters,hunters.size()])
	check(game.contracts.risk_spawned and game.contracts.risk_spawn_count==expected_hunters, "Risk trigger must be recorded once in the contract state")
	for hunter: BattleUnit in hunters:
		check(hunter.alive and hunter.get_meta("day_hunter",false), "Contract hunter must be a living daytime pursuer")
		check(hunter.get_meta("contract_hunter",false), "Contract hunter must carry its cleanup marker")
	var before_count:=hunters.size()
	game.interact()
	check(contract_hunters().size()==before_count, "Repeated F must not duplicate contract hunters")
	if not hunters.is_empty():
		var before_distance: float=hunters[0].position.distance_to(game.hero.position)
		game.simulate(.5)
		var after_distance: float=hunters[0].position.distance_to(game.hero.position)
		check(after_distance<before_distance, "A contract hunter must pursue the hero during the day")
		game.hero.attack_timer=999.0
		hunters[0].position=game.hero.position+Vector3(0,0,.8)
		hunters[0].position.y=game.outpost_height(hunters[0].position)
		var before_hp: float=game.hero.hp
		for step in 30:
			hunters[0].tick(.1)
			game.update_creature(hunters[0],.1)
		check(game.hero.hp<before_hp, "A contract hunter must deal real damage when it reaches the hero")
		var hunter:=hunters[0]
		hunter.hurt(99999.0,game.hero)
		game.simulate(STEP)
		check(not hunter.alive or not is_instance_valid(hunter), "A contract hunter must be killable by real combat damage")
	var pause_hunters:=contract_hunters()
	var pause_position: Vector3=pause_hunters[0].position if not pause_hunters.is_empty() else Vector3.ZERO
	var pause_clock: float=game.phase_time
	game.phase="paused"
	game.simulate(1.0);game.update_day_contracts(1.0)
	check(game.phase_time==pause_clock and (pause_hunters.is_empty() or pause_hunters[0].position==pause_position), "Pause must freeze contract hunter motion and the day clock")
	game.phase="day"
	game.start_night()
	check(contract_hunters().is_empty(), "Dusk must clear contract hunters before the night begins")
	check(game.phase=="night", "Dusk cleanup must leave the game in the real night phase")
	await game.prepare_shutdown()
	game.free();await process_frame;await create_timer(.5).timeout

func run() -> void:
	await run_case(0,0)
	await run_case(1,1)
	await run_case(2,2)
	print("NIGHTFALL_CONTRACT_RISK_", "OK" if failures.is_empty() else "FAILED", " real_f_action_risk_hunters_pause_cleanup")
	quit(0 if failures.is_empty() else 1)
