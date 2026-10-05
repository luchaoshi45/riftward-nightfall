extends SceneTree
## Production scene, real seeds/actions/routes, production-only reward payout.
## Optional actual render: -- --render-test (hidden window + Dummy audio).
const Contracts = preload("res://scripts/day_contracts.gd")
const HOME := Vector3(0, 5, 3.1)
const STEP := .05
var game: Node3D
var failures: Array[String] = []
var render_test := false
var route_seconds: Dictionary = {}

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.hide()
	render_test = DisplayServer.get_name()!="headless" or "--render-test" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message); push_error(message)

func clear_enemies() -> void:
	for unit in game.enemies:
		if is_instance_valid(unit): unit.queue_free()
	game.enemies.clear()

func route_length(from: Vector3, to: Vector3) -> float:
	if game.can_traverse(from, to): return Vector2(from.x - to.x, from.z - to.z).length()
	var start: Vector2i = game.nearest_navigation_cell(from, true)
	var finish: Vector2i = game.nearest_navigation_cell(to, false)
	if start.x == 999 or finish.x == 999: return INF
	var route: PackedVector2Array = game.hero_navigation.get_point_path(start, finish)
	if route.is_empty(): return INF
	var previous := Vector2(from.x, from.z)
	var distance := 0.0
	for point in route:
		distance += previous.distance_to(point)
		previous = point
	return distance + previous.distance_to(Vector2(to.x, to.z))

func option_budget(option: Dictionary, spare_seconds: float = 15.0) -> float:
	var previous := HOME
	var seconds := 0.0
	for target: Dictionary in option.targets:
		seconds += route_length(previous, target.position) / game.hero.speed
		previous = target.position
	var return_speed: float = 5.4 if option.kind == "escort" else game.hero.speed
	seconds += route_length(previous, HOME) / return_speed
	seconds += float({"salvage": 2.0, "generator": 16.0, "escort": 8.0, "nest": 10.0}.get(option.kind, 0.0))
	return seconds + spare_seconds

func seed_for(wanted: String, respawn_wait: bool) -> int:
	var options: Array = game.contracts.candidates()
	for option: Dictionary in options:
		check(option_budget(option) <= game.DAY_LENGTH,
			"Available candidate %s must have a real gate route and action/return budget below ninety seconds" % option.kind)
	var previous_phase: String = game.phase
	var previous_day: int = game.day_number
	game.phase = "day"
	game.day_number = 2
	var probe = Contracts.new()
	game.add_child(probe)
	for seed in 2000:
		probe.setup(game, seed)
		probe.on_day()
		if probe.status != "active" or probe.offers.is_empty() or probe.offers[0].kind != wanted: continue
		var chosen: Dictionary = probe.offers[0]
		if respawn_wait and option_budget(chosen, 55.2 + 15.0) >= game.DAY_LENGTH: continue
		probe.queue_free()
		game.phase = previous_phase
		game.day_number = previous_day
		return seed
	probe.queue_free()
	game.phase = previous_phase
	game.day_number = previous_day
	return -1

func start_day(wanted: String, respawn_wait: bool = false) -> bool:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false)
	if not game.has_method("update_day_contracts") or not is_instance_valid(game.get("contracts")):
		check(false, "Production scene must install contracts and update_day_contracts before this test runs")
		return false
	check(game.choose_card(0) and game.phase == "night", "Actual opening card must start the first night")
	clear_enemies()
	var seed := seed_for(wanted, respawn_wait)
	check(seed >= 0, "A real seed must select the requested reachable %s candidate" % wanted)
	if seed < 0: return false
	game.run.seed_value = seed
	game.contracts.setup(game, seed)
	game.finish_night()
	check(game.phase == "draft" and game.day_number == 2, "First night completion must reach the real second-day draft")
	check(game.choose_card(0) and game.phase == "day", "Dawn choice must call production begin_day")
	clear_enemies()
	check(game.contracts.status == "active" and game.contracts.kind == wanted,
		"Production day generation must select the requested real %s candidate" % wanted)
	check(game.contracts.day_id == 2 and game.phase_time == game.DAY_LENGTH, "Production contract must belong to the new ninety-second day")
	if game.contracts.offers.size() > 1:
		var key := InputEventKey.new()
		key.pressed = true
		key.keycode = KEY_5
		var before_offer: int = game.contracts.selected_offer
		game._unhandled_input(key)
		check(game.contracts.selected_offer == 1 and before_offer != game.contracts.selected_offer,
			"Production 5 key must switch to the second untouched contract offer")
		key.keycode = KEY_4
		game._unhandled_input(key)
		check(game.contracts.selected_offer == 0 and game.contracts.kind == wanted,
			"Production 4 key must restore the requested safe route before its actual movement test")
	return game.contracts.status == "active" and game.contracts.kind == wanted

func choose_return() -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_4
	game._unhandled_input(key)
	check(game.contracts.status == "returning", "Production 4 must explicitly choose the primary guarantee and actual return route")

func close_game() -> void:
	if not is_instance_valid(game): return
	await game.prepare_shutdown()
	game.queue_free(); await process_frame; await create_timer(.5).timeout

func travel(destination: Vector3) -> bool:
	check(game.contract_goal().is_equal_approx(destination), "Production guidance must point to the actual remaining action or return goal")
	if not game.follow_contract():
		check(false, "Production P guidance must create a real player navigation route")
		return false
	var elapsed := 0.0
	var idle_steps := 0
	while Vector2(game.hero.position.x - destination.x, game.hero.position.z - destination.z).length() > .18:
		if game.phase != "day" or elapsed >= 90.0:
			check(false, "Actual movement must arrive before dusk: %s -> %s" % [game.hero.position, destination])
			return false
		var before: Vector3 = game.hero.position
		game.simulate(STEP) # Uses production move_hero, expeditions, refresh and contracts.
		elapsed += STEP
		check(game.can_traverse(before, game.hero.position), "Actual navigation must not cross a fortress wall")
		check(is_equal_approx(game.hero.position.y, game.outpost_height(game.hero.position)), "Actual navigation must follow the raised ramp")
		idle_steps = idle_steps + 1 if before.distance_squared_to(game.hero.position) < .000001 else 0
		if idle_steps > 30:
			check(false, "Actual contract route must not stall at a wall: %s" % game.hero.position)
			return false
	game.move_goal = game.hero.position; game.hero_path.clear()
	route_seconds[game.contracts.kind] = float(route_seconds.get(game.contracts.kind, 0.0)) + elapsed
	return true

func wait_day(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds and game.phase == "day":
		var delta := minf(STEP, seconds - elapsed)
		game.simulate(delta); elapsed += delta

func collect_target(target: Dictionary) -> bool:
	if not travel(target.position): return false
	check(game.nearest_salvage() == int(target.index), "The real marked cache must be the actionable nearby cache")
	var acted: bool = game.interact()
	check(acted and target.source.collected, "F at the actual candidate must collect its authoritative cache")
	game.update_day_contracts(0.0)
	return acted and target.source.collected

func check_freeze() -> void:
	for phase: String in ["paused", "draft"]:
		var done: Dictionary = game.contracts.done.duplicate()
		var scrap: int = game.scrap
		var clock: float = game.phase_time
		game.phase = phase
		game.simulate(20.0); game.update_day_contracts(20.0)
		check(not game.follow_contract(), "Inactive phases must not accept the production contract navigation command")
		check(game.contracts.done == done and game.scrap == scrap and game.phase_time == clock,
			"%s must freeze authoritative contract progress, rewards and day clock" % phase)
	game.phase = "day"

func capture(path: String) -> void:
	if not render_test: return
	if DisplayServer.get_name() == "headless":
		check(false, "--render-test requires real graphics; headless is not a render check")
		return
	game.world.night_mix = 0.0; game.world.apply_lighting()
	game.camera.size = 31.0
	game.camera.position = game.hero.position + Vector3(0, 25, 29)
	game.camera.look_at(game.hero.position)
	game.hud.queue_redraw()
	await process_frame; await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(path)
	check(result == OK, "Actual contract HUD/world/reward frame must save successfully")

func check_early_salvage() -> void:
	if not await start_day("salvage", true): await close_game(); return
	var selected: Array = game.contracts.targets.duplicate()
	if not collect_target(selected[0]): await close_game(); return
	check(game.contracts.done.size() == 1 and game.contracts.status == "active", "One genuine cache must give partial progress without a return reward")
	check_freeze()
	await capture("res://build/day-contract-active.png")
	var before_scrap: int = game.scrap
	wait_day(55.1)
	check(game.phase == "day" and not selected[0].source.collected and game.contracts.done.has(int(selected[0].index)),
		"Actual fifty-five-second cache respawn must preserve already completed contract progress")
	check(game.scrap == before_scrap, "Cache respawn and waiting cannot grant a contract payout")
	if not collect_target(selected[1]): await close_game(); return
	check(game.contracts.done.size() == 2 and game.contracts.status == "bonus_offer", "Completed field actions must offer the optional detour without pretending delivery occurred")
	choose_return()
	before_scrap = game.scrap
	if not travel(HOME): await close_game(); return
	check(game.phase_time >= 15.0, "Selected real route plus respawn must retain the fifteen-second early-return margin")
	check(game.contracts.status == "completed" and game.contracts.pending_reward.is_empty(), "Production update must consume the actual completed contract request")
	check(game.scrap == before_scrap + 48, "Actual early return must pay forty-eight scrap exactly once")
	check(game.exploration.affinity_active() and game.exploration.affinity_kinds.has("ember_bloom"),
		"Returning a salvage contract must arm a one-shot ember/supply exploration affinity")
	var affinity_before: int = game.scrap
	game.grant_exploration_reward("委托共鸣测试", game.hero.position, 0, 0.0, 0.0, "ember_bloom")
	check(game.scrap >= affinity_before + 8 and not game.exploration.affinity_active(),
		"The next matching production discovery must consume the affinity exactly once")
	await capture("res://build/day-contract-return.png")
	before_scrap = game.scrap
	for step in 20: game.update_day_contracts(.1)
	check(game.scrap == before_scrap, "Repeated production payout updates must never pay the contract twice")
	await close_game()

func check_generator() -> void:
	if not await start_day("generator"): await close_game(); return
	var site: Dictionary = game.contracts.targets[0].source
	if not travel(site.position): await close_game(); return
	check(game.interact() and site.state == "active", "Real generator candidate must start through F")
	check(game.cast(3), "A real R cast must clear the three reachable generator ambushers")
	check(not game.expeditions.guards_alive(site), "Actual R damage must defeat all three real generator ambushers")
	wait_day(6.0)
	check(site.state == "active" and game.contracts.done.is_empty(), "Half a real charge must not complete the contract")
	check_freeze()
	wait_day(6.1)
	check(site.state == "complete" and game.generator_cells == 1 and game.contracts.done.size() == 1,
		"Actual twelve-second charge and defeated guards must complete the field action")
	check(game.contracts.status == "bonus_offer", "Field energy reward must offer a detour without pretending the contract has already returned")
	choose_return()
	var before_scrap: int = game.scrap
	if not travel(HOME): await close_game(); return
	check(game.phase_time >= 15.0 and game.contracts.status == "completed", "Real generator round trip plus combat and hold must fit an early ninety-second return")
	check(game.scrap == before_scrap + 48, "Generator contract must use the same real production payout, separately from its energy reward")
	await close_game()

func check_late_or_dusk(dusk: bool) -> void:
	if not await start_day("salvage"): await close_game(); return
	for target: Dictionary in game.contracts.targets:
		if not collect_target(target): await close_game(); return
	check(game.contracts.done.size() == 2 and game.contracts.status == "bonus_offer", "Both caches away from home must offer the explicit primary-or-detour decision")
	var before_scrap: int = game.scrap
	if dusk:
		wait_day(game.phase_time + .1)
		check(game.phase == "night" and game.contracts.status == "completed", "Actual dusk must preserve a genuinely completed primary contract as a guarantee")
		check(game.scrap == before_scrap + 38,
			"Dusk must grant the completed primary guarantee without early-return or extra-supply rewards")
		before_scrap = game.scrap
		game.update_day_contracts(20.0)
		check(game.scrap == before_scrap and game.contracts.pending_reward.is_empty(),
			"Dusk and later production updates must never duplicate the guaranteed primary payout")
	else:
		choose_return()
		var return_seconds: float = route_length(game.hero.position, HOME) / game.hero.speed
		wait_day(maxf(0.0, game.phase_time - return_seconds - 6.0))
		if not travel(HOME): await close_game(); return
		check(game.phase == "day" and game.phase_time < 15.0 and game.contracts.status == "completed", "Actual late arrival must remain valid without an early bonus")
		check(game.scrap == before_scrap + 38, "Late arrival must pay thirty-eight scrap, and no ten-supply early bonus")
	await close_game()

func check_incomplete_dusk() -> void:
	if not await start_day("salvage"): await close_game(); return
	if not collect_target(game.contracts.targets[0]): await close_game(); return
	check(game.contracts.status == "active" and game.contracts.done.size() == 1,
		"Only one of two real caches must leave the primary contract incomplete")
	var before_scrap: int = game.scrap
	wait_day(game.phase_time + .1)
	check(game.phase == "night" and game.contracts.status == "expired",
		"Actual dusk must expire an incomplete primary contract")
	check(game.scrap == before_scrap and game.contracts.pending_reward.is_empty(),
		"Partial primary field work must not receive the completed-work guarantee")
	await close_game()

func run() -> void:
	await check_early_salvage()
	await check_generator()
	await check_late_or_dusk(false)
	await check_late_or_dusk(true)
	await check_incomplete_dusk()
	check(route_seconds.has("salvage") and route_seconds.has("generator"),
		"The production regression must actually travel both requested route kinds rather than silently skip its cases")
	print("NIGHTFALL_DAY_CONTRACTS_", "OK" if failures.is_empty() else "FAILED", " actual_routes=", route_seconds,
		" production_rewards respawn_progress pause_draft early_late dusk", " rendered" if render_test else "")
	quit(0 if failures.is_empty() else 1)
