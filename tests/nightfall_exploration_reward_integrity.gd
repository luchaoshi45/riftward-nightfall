extends SceneTree
## Production F rewards: route chains, independent collections and honest timers.
## Run graphics with --position 10000,10000 --audio-driver Dummy -- --render-test.
const POINT := Vector3(18, 0, 0)
const FAR := Vector3(105, 0, 95)
const BASE_REWARDS := {
	"ember_bloom": 12, "memory_crystal": 12,
	"supply_cache": 46, "waylight": 0
}
var game: Node3D
var failures: Array[String] = []
var checks := 0
var render_test := false

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	render_test = "--render-test" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	push_error(message)

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func put_hero() -> void:
	game.hero.position = POINT
	game.move_goal = POINT
	game.hero_path.clear()
	game.hero_keyboard_active = false
	game.hero.speed = game.HERO_MOVE_SPEED

func reset_case() -> void:
	game.phase = "day"
	game.phase_time = 900.0
	game.contracts.status = "idle"
	game.contracts.day_id = game.day_number
	game.exploration.reset_run()
	game.exploration.begin_day(1)
	game.exploration_count = 0
	game.exploration_milestones = 0
	game.scrap = 500
	game.reward_toasts.clear()
	game.hero.hp = game.hero.max_hp
	game.hero.shield = 0.0
	game.hero.shield_time = 0.0
	put_hero()
	for item: Dictionary in game.discoveries.items:
		game.discoveries.begin_cooling(item, 9999.0)
		item.position = FAR
		item.node.position = FAR
	for animal: Dictionary in game.wildlife.animals:
		animal.position = FAR
		animal.node.position = FAR
		animal.anchor = FAR
		animal.target = FAR
		animal.state = "idle"
		animal.timer = 9999.0
		animal.node.visible = false
	for cache: Dictionary in game.world.salvage:
		cache.collected = true
		cache.respawn = 9999.0
		cache.node.visible = false
	for generator: Dictionary in game.expeditions.generators:
		generator.state = "complete"
	for camp: Dictionary in game.expeditions.camps:
		camp.state = "delivered"
	for nest: Dictionary in game.world.nests: nest.cleansed = true
	for relay: Dictionary in game.world.relays: relay.activated = true
	for pad: Dictionary in game.world.tower_pads: pad.position = FAR

func timers() -> Dictionary:
	return {"streak": game.exploration.streak, "last": game.exploration.last_kind,
		"window": game.exploration.streak_time, "speed": game.exploration.speed_time,
		"bonus": game.exploration.speed_bonus, "affinity": game.exploration.affinity_time}

func check_timers(previous: Dictionary, title: String) -> void:
	check(game.exploration.streak == previous.streak and game.exploration.last_kind == previous.last,
		"%s must neither advance nor reset the route chain" % title)
	check(is_equal_approx(game.exploration.streak_time, previous.window),
		"%s must not refresh the 22-second route window" % title)
	check(is_equal_approx(game.exploration.speed_time, previous.speed) and is_equal_approx(game.exploration.speed_bonus, previous.bonus),
		"%s must not refresh or remove route acceleration" % title)
	check(is_equal_approx(game.exploration.affinity_time, previous.affinity),
		"%s must not consume an unmatched contract affinity" % title)

func payout(previous_scrap: int, previous_count: int, base: int, extra: int, title: String) -> void:
	var milestone := 55 if (previous_count + 1) % 5 == 0 else 0
	var expected := base + extra + milestone
	check(game.scrap - previous_scrap == expected,
		"%s scrap: expected %d, got %d" % [title, expected, game.scrap - previous_scrap])
	check(game.exploration_count == previous_count + 1,
		"%s must record exactly one actual exploration" % title)
	check(game.exploration_milestones == game.exploration_count / 5,
		"%s must preserve the independent five-discovery milestone count" % title)

func route(kind: String, extra := 0, title := "") -> void:
	var item: Dictionary = {}
	for candidate: Dictionary in game.discoveries.items:
		if String(candidate.kind) == kind:
			item = candidate
			break
	check(not item.is_empty(), "A real %s discovery must exist" % kind)
	if item.is_empty(): return
	item.position = POINT
	item.node.position = POINT
	item.node.visible = true
	item.state = "ready"
	item.progress = 0.0
	item.remaining = 0.0
	game.discoveries.motivation_revision += 1
	put_hero()
	var before_scrap: int = game.scrap
	var before_count: int = game.exploration_count
	await press(KEY_F)
	if kind == "supply_cache":
		check(item.state == "channel", "Production F must start the real supply-cache channel")
		game._process(3.01)
		check(item.state == "cooling", "Only completing the real channel may grant the cache reward")
	else:
		check(item.state == ("active" if kind == "waylight" else "cooling"),
			"Production F must consume the real %s discovery" % kind)
	payout(before_scrap, before_count, BASE_REWARDS[kind], extra, title if not title.is_empty() else kind)
	# A lit lamp is a consumed route discovery, and must not shadow subsequent F.
	if kind == "waylight": game.discoveries.begin_cooling(item, 9999.0)

func ordinary(kind: String) -> void:
	put_hero()
	var base := 0
	var cache: Dictionary = {}
	var animal: Dictionary = {}
	if kind == "salvage":
		cache = game.world.salvage[0]
		cache.collected = false
		cache.respawn = 0.0
		cache.position = POINT
		cache.node.position = POINT
		cache.node.visible = true
		base = int(cache.amount) + 3
	else:
		for candidate: Dictionary in game.wildlife.animals:
			if candidate.kind == kind:
				animal = candidate
				break
		check(not animal.is_empty(), "A real %s animal must exist" % kind)
		if animal.is_empty(): return
		animal.position = POINT
		animal.node.position = POINT
		animal.anchor = POINT
		animal.target = POINT
		animal.state = "idle"
		animal.timer = 9999.0
		animal.node.visible = true
		base = 6 if kind == "stag" else -12
	var previous := timers()
	var before_scrap: int = game.scrap
	var before_count: int = game.exploration_count
	game.hero.hp = game.hero.max_hp - 100.0
	game.mana = game.max_mana - 100.0
	await press(KEY_F)
	if kind == "salvage":
		check(cache.collected and cache.respawn == game.SALVAGE_REFRESH,
			"Real salvage F must retain its collected state and refresh delay")
	else:
		check(animal.state == "leaving", "Real wildlife F must consume the encounter before rewarding it")
		check(is_equal_approx(game.hero.hp, game.hero.max_hp - (40.0 if kind == "stag" else 60.0)),
			"%s must retain its actual base healing" % kind)
		if kind == "stag":
			check(game.hero.shield >= 90.0 and game.hero.shield_time >= 10.0,
				"A real stag touch must retain its 90 shield and ten-second duration")
		else:
			check(is_equal_approx(game.mana, game.max_mana - 20.0),
				"A real beetle exchange must retain its 80 mana recovery")
	payout(before_scrap, before_count, base, 0, "%s with chain %d" % [kind, previous.streak])
	check_timers(previous, kind)
	before_scrap = game.scrap
	before_count = game.exploration_count
	await press(KEY_F)
	check(game.scrap == before_scrap and game.exploration_count == before_count,
		"Repeated F on consumed %s must not replay any reward" % kind)
	check_timers(previous, "repeated " + kind)
	if not animal.is_empty():
		animal.position = FAR
		animal.node.position = FAR

func ordinary_rewards() -> void:
	for length in [0, 2, 3]:
		reset_case()
		if length >= 2:
			await route("ember_bloom")
			await route("memory_crystal", 4)
		if length == 3: await route("supply_cache", 18)
		game._process(5.0)
		game.exploration.arm_contract_affinity(["waylight"])
		await ordinary("salvage")
		await ordinary("stag")
		await ordinary("beetle")
		check(game.exploration.streak == length,
			"Ordinary interactions must preserve the genuine %d-route chain" % length)
		check(game.exploration.run_discoveries == game.exploration_count,
			"Ordinary discoveries must still contribute to the production exploration total")

func slow_collection() -> void:
	reset_case()
	for kind: String in ["ember_bloom", "memory_crystal", "supply_cache", "waylight"]:
		await route(kind, 52 if kind == "waylight" else 0,
			"slow independent collection " + kind)
		if kind != "waylight": game._process(23.0)
	check(game.exploration.streak == 1 and game.exploration.full_set_claimed,
		"Four slow discoveries must pay the once-only collection despite an expired chain")
	check(game.scrap == 622,
		"Slow four-type collection must pay exactly 70 base plus 52 collection scrap")
	await capture("full-set")
	await route("waylight", 0, "same-day collection must not replay")
	game.phase = "night"
	game.exploration.begin_night()
	await route("waylight", 9, "night keeps collection consumed and its own first-search bonus")
	check(game.exploration.full_set_claimed, "Beginning night must retain the paid collection flag")
	game.phase = "day"
	game.exploration.begin_day(2)
	check(not game.exploration.full_set_claimed and game.exploration.next_kind() != "",
		"Beginning the next day must start a fresh four-type collection")
	for kind: String in ["ember_bloom", "memory_crystal", "supply_cache", "waylight"]:
		await route(kind, 52 if kind == "waylight" else 0,
			"next-day independent collection " + kind)
		if kind != "waylight": game._process(23.0)
	check(game.exploration.full_set_claimed, "A new day must allow its collection reward exactly once")

func collection_stacking() -> void:
	reset_case()
	await route("ember_bloom")
	await route("memory_crystal", 4)
	await route("supply_cache", 18)
	await route("waylight", 52)
	check(game.scrap == 644,
		"Fast four-type route must retain exactly 70 base plus 74 route reward scrap")
	for ending_chain in [2, 3]:
		reset_case()
		await route("ember_bloom")
		await route("memory_crystal", 4)
		await route("supply_cache", 18)
		game._process(23.0)
		await route("ember_bloom")
		if ending_chain == 3: await route("memory_crystal", 4)
		game.exploration.arm_contract_affinity(["waylight"])
		var chain := 4 if ending_chain == 2 else 18
		await route("waylight", 52 + chain + 8,
			"collection + genuine chain %d + affinity" % ending_chain)
		check(game.exploration.streak == ending_chain and game.exploration.full_set_claimed,
			"Collection must stack with genuine chain %d without replacing it" % ending_chain)
		check(not game.exploration.affinity_active(), "Matched affinity must be consumed once alongside collection")
		await route("waylight", 0, "consumed collection and affinity must not replay")
		check(game.exploration.streak == 1,
			"Repeating the same route type must reset its chain without repaying chain rewards")

func stacked_feedback() -> void:
	reset_case()
	await route("ember_bloom")
	await route("waylight", 4)
	await route("supply_cache", 18)
	game._process(23.0)
	game.phase = "night"
	game.exploration.begin_night()
	game.grant_exploration_reward("夜行续段", POINT, 0, 0, 0, "ember_bloom")
	game.exploration.set_waylight_count(2)
	game.exploration.arm_contract_affinity(["memory_crystal"])
	var previous_scrap: int = game.scrap
	var previous_count: int = game.exploration_count
	game.grant_exploration_reward("叠加奖励验证", Vector3(50, 0, 0), 0, 0, 0, "memory_crystal")
	payout(previous_scrap, previous_count, 0, 83, "six independent route bonuses")
	var toast: Dictionary = game.reward_toasts.back()
	for source: String in ["探索连段 2", "完整搜寻", "深入荒原", "夜行搜寻", "灯网共鸣", "委托共鸣"]:
		check(String(toast.title).contains(source), "Stacked reward feedback must retain its %s source" % source)
	check(String(toast.detail).contains("+83零件") and String(toast.detail).contains("加速18秒"), "The route toast must show the actual combined addition separately from the five-visit milestone")
	var title_size: Vector2 = game.hud.font.get_multiline_string_size(String(toast.title), HORIZONTAL_ALIGNMENT_LEFT, 304, 13)
	check(title_size.y <= game.hud.font.get_height(13)*2.0+.1, "All six actual reward sources must fit in two lines")
	check(game.hud.font.get_string_size(String(toast.detail), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= 304.0, "The combined route payout must fit inside the actual HUD toast")
	await capture("stacked-sources")

func freeze_windows() -> void:
	reset_case()
	await route("ember_bloom")
	await route("memory_crystal", 4)
	check(is_equal_approx(game.exploration.streak_time, 22.0), "A genuine route must start the published 22-second window")
	game.exploration.arm_contract_affinity(["waylight"])
	await capture("affinity")
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "Actual Esc must enter pause for the timer regression")
	for phase_name: String in ["paused", "draft"]:
		if phase_name == "draft":
			await press(KEY_ESCAPE)
			game.run.grant("生产冻结验证")
			await press(KEY_V)
			check(game.phase == "draft", "Actual V must open the queued production reinforcement draft")
		var before := timers()
		var clock: float = game.phase_time
		var scrap: int = game.scrap
		var count: int = game.exploration_count
		game._process(30.0)
		await press(KEY_F)
		game.grant_exploration_reward("冻结拒绝验证", POINT, 160, 0, 0, "waylight")
		check(game.phase_time == clock and game.scrap == scrap and game.exploration_count == count,
			"%s must freeze the phase clock and reject exploration rewards" % phase_name)
		check_timers(before, phase_name)
	game.phase = "day"
	game._process(20.1)
	check(game.exploration.streak_time > 1.8 and game.exploration.streak_time < 2.0,
		"Resumed gameplay must reduce the published window by real simulation time")
	check(game.exploration.speed_bonus_value() == 0.0,
		"The separate 18-second acceleration must expire before the 22-second chain")
	await capture("window-ending")
	game._process(2.0)
	check(game.exploration.streak == 0 and game.exploration.streak_time == 0.0,
		"The genuine route chain must expire after its full 22-second window")

func simulation_clock_order() -> void:
	reset_case()
	await route("ember_bloom")
	# Completing a three-second real cache channel creates the second-link
	# buff at the end of that frame. Its new timers must not lose those seconds.
	await route("supply_cache", 4, "channel completion creates a fresh second-link acceleration")
	check(is_equal_approx(game.exploration.speed_time, 18.0),
		"Acceleration granted at the end of a real channel frame must retain all 18 seconds")
	check(is_equal_approx(game.exploration.streak_time, 22.0),
		"A route window granted after that channel must retain all 22 seconds")
	var normal_speed: float = game.HERO_MOVE_SPEED + float(game.run.stats.speed)
	game.simulate(17.5)
	check(is_equal_approx(game.exploration.speed_time, .5) and is_equal_approx(game.hero.speed, normal_speed + .8),
		"Direct production simulation must consume the buff clock once and apply its live speed")
	game.simulate(.5)
	check(game.exploration.speed_time == 0.0 and is_equal_approx(game.hero.speed, normal_speed),
		"The exact expiration frame must restore normal movement speed before movement runs")
	check(is_equal_approx(game.exploration.streak_time, 4.0),
		"The longer route window must remain after the separate acceleration expires")
	game.simulate(4.0)
	check(game.exploration.streak == 0 and game.exploration.streak_time == 0.0,
		"Direct production simulation must expire the route chain at exactly 22 seconds")

func capture(state: String) -> void:
	if not render_test: return
	check(DisplayServer.get_name() != "headless", "Render verification must use the actual graphics renderer")
	if DisplayServer.get_name() == "headless": return
	game.world.night_mix = 0.0
	game.world.set_night(false)
	game.camera_follow = game.hero.position + Vector3(0, 25, 29)
	game.camera.position = game.camera_follow
	game.camera.size = 31.0
	game.hud.queue_redraw()
	for _frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var output := "res://build/nightfall-exploration-integrity-%s.png" % state
	check(root.get_texture().get_image().save_png(output) == OK, "The hidden %s HUD frame must save successfully" % state)
	print("EXPLORATION_INTEGRITY_FRAME ", ProjectSettings.globalize_path(output))

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	await press(KEY_1)
	check(game.phase == "night", "The production opening card must enter the playable scene")
	for enemy: BattleUnit in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	await process_frame
	await ordinary_rewards()
	await slow_collection()
	await collection_stacking()
	await stacked_feedback()
	await freeze_windows()
	await simulation_clock_order()
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	if failures.is_empty():
		print("NIGHTFALL_EXPLORATION_REWARD_INTEGRITY_OK checks=", checks,
			" real_F=supply/salvage/stag/beetle milestone=55 slow_collection=52 shared_scrap chain_affinity_stack pause_draft")
		quit()
	else:
		print("NIGHTFALL_EXPLORATION_REWARD_INTEGRITY_FAILED checks=", checks, " failures=", failures.size())
		quit(1)
