extends SceneTree
## Real production actors and hurt signals; fixed placements isolate selection
## rules and do not claim whole-run difficulty or native rendering acceptance.
const RunSession = preload("res://scripts/run_session.gd")

var game: Node3D
var pad: Dictionary
var checks := 0
var failures: Array[String] = []
var hits: Array[Dictionary] = []
var cases: Array[Dictionary] = []
var render_test := false
var output_dir := ""

func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.hide()
	root.mode = Window.MODE_WINDOWED
	root.position = Vector2i(10000, 10000)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1920, 1200)
	root.size = Vector2i(1920, 1200)
	var build_root := ProjectSettings.globalize_path("res://build").simplify_path()
	output_dir = build_root.path_join("tower-targeting")
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--render-test": render_test = true
		elif argument.begins_with("--output-dir="):
			var requested := argument.trim_prefix("--output-dir=")
			if not requested.is_absolute_path(): requested = "res://" + requested
			requested = ProjectSettings.globalize_path(requested).simplify_path()
			if check(requested == build_root or requested.begins_with(build_root + "/"),
				"The requested capture output must stay inside this project's local build directory"):
				output_dir = requested
	call_deferred("run")

func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)
	return condition

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func place_hero(point: Vector3) -> void:
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.move_goal = point
	game.hero_path.clear()
	game.aim_sample_pending = false

func record_hit(unit: BattleUnit, source: BattleUnit, hp_loss: float, shield_loss: float) -> void:
	hits.append({"target": unit.get_instance_id(), "source": source.get_instance_id() if is_instance_valid(source) else -1,
		"hp_loss": hp_loss, "shield_loss": shield_loss})

func enemy(role: String, offset: Vector3) -> BattleUnit:
	var creature: BattleUnit = game.spawn_creature(true, role)
	creature.position = (pad.position as Vector3) + offset
	# A stationary actor cannot move a boundary before the one simulated shot.
	creature.speed = 0.0
	creature.damage_confirmed.connect(record_hit)
	return creature

func reset_case(mode: String) -> void:
	game.clear_focus()
	game.clear_lobbers()
	game.clear_summoners()
	for creature: Variant in game.enemies:
		if is_instance_valid(creature): creature.queue_free()
	game.enemies.clear()
	await process_frame
	hits.clear()
	pad.mode = mode
	pad.cooldown = 0.0
	game.focus_cooldown = 0.0
	game.phase = "night"
	game.phase_time = 10000.0
	game.pulse_timer = 10000.0
	game.countermeasure_tower_time = 0.0
	place_hero((pad.position as Vector3) + Vector3(0, 0, 3.8))

func capture(name: String, tracked: Array = []) -> void:
	if not render_test: return
	var was_paused := paused
	var hud: Control = game.hud
	var actual_draws: Array[Dictionary] = []
	var draw_observer: Callable = func() -> void:
		actual_draws.append({"phase": game.phase, "offers": game.run.offer.size()})
	hud.draw.connect(draw_observer)
	hud.queue_redraw()
	# Preserve the real just-produced beam while the renderer completes its
	# fresh HUD frame; the fixture adds no beam or replacement gameplay drawing.
	paused = true
	for _frame in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	hud.draw.disconnect(draw_observer)
	check(not actual_draws.is_empty() and String(actual_draws.back().get("phase", "")) == "night"
		and int(actual_draws.back().get("offers", -1)) == 0,
		"The real HUD must actually redraw the active night with no offered cards before capture")
	check(game.phase == "night" and game.run.offer.is_empty() and game.hud.card_rects.is_empty()
		and game.hud.mode_rects.is_empty(), "The actually redrawn HUD must contain no draft card or opening mode rectangles")
	var picture := root.get_texture().get_image()
	var actor_points: Array[Dictionary] = []
	var content_rect := Rect2(Vector2.ZERO, Vector2(picture.get_size()))
	for creature: BattleUnit in tracked:
		var point: Vector2 = game.camera.unproject_position(creature.global_position + Vector3.UP)
		check(not game.camera.is_position_behind(creature.global_position) and content_rect.has_point(point),
			"The actual capture camera must show both the near target and farther threat")
		actor_points.append({"role": creature.get_meta("threat", ""), "x": point.x, "y": point.y,
			"distance": (pad.position as Vector3).distance_to(creature.position)})
	print("NIGHTFALL_TOWER_TARGETING_CAPTURE ", JSON.stringify({"name": name,
		"width": picture.get_width(), "height": picture.get_height(),
		"window": str(root.size), "content": str(root.content_scale_size), "scale_mode": root.content_scale_mode,
		"hud_draws": actual_draws, "card_rects": game.hud.card_rects.size(), "mode_rects": game.hud.mode_rects.size(),
		"actor_points": actor_points}))
	check(picture.get_width() == 1920 and picture.get_height() == 1200,
		"The actual capture must be 1920 by 1200: image=%s window=%s content=%s scale_mode=%s" % [
			picture.get_size(), root.size, root.content_scale_size, root.content_scale_mode])
	check(DirAccess.make_dir_recursive_absolute(output_dir) == OK,
		"Create the allowed build-only capture directory")
	check(picture.save_png(output_dir.path_join(name + ".png")) == OK,
		"Save the actual production targeting capture under build")
	paused = was_paused

func observe_shot(name: String, expected: BattleUnit, targets: Array, through_simulation: bool = false) -> void:
	if render_test and name == "outside-threat-falls-back-to-legal-basic":
		game.world.apply_lighting()
		var center: Vector3 = (pad.position as Vector3) + Vector3(7.5, 0, 0)
		game.camera.position = center + Vector3(0, 25, 29)
		game.camera.look_at(center)
		game.notice = ""
		game.notice_time = 0.0
		await capture("outside-threat-ready", targets)
	var before: Dictionary = {}
	for creature: BattleUnit in targets:
		before[creature.get_instance_id()] = {"hp": creature.hp, "shield": creature.shield}
	var initial_failures := failures.size()
	var balance: int = game.scrap
	var mana: float = game.mana
	hits.clear()
	if through_simulation: game.simulate(.01)
	else: game.update_towers(.01)
	var expected_id := expected.get_instance_id() if is_instance_valid(expected) else -1
	check(hits.size() == (1 if expected_id >= 0 else 0)
		and (expected_id < 0 or (not hits.is_empty() and int(hits[0].target) == expected_id)),
		name + ": actual damage_confirmed must identify only the expected primary target")
	var observations: Array[Dictionary] = []
	for creature: BattleUnit in targets:
		var previous: Dictionary = before[creature.get_instance_id()]
		if creature == expected:
			check(creature.hp < float(previous.hp) or creature.shield < float(previous.shield),
				name + ": the legal selected actor must receive a real hurt")
		else:
			check(creature.hp == float(previous.hp) and creature.shield == float(previous.shield),
				name + ": other actors must retain their actual health and shield")
		observations.append({"id": creature.get_instance_id(), "role": creature.get_meta("threat", ""),
			"distance": (pad.position as Vector3).distance_to(creature.position),
			"hp_loss": float(previous.hp) - creature.hp, "shield_loss": float(previous.shield) - creature.shield})
	check(float(pad.cooldown) > 0.0 if expected_id >= 0 else float(pad.cooldown) == 0.0,
		name + ": only a real shot may start the tower cooldown")
	check(game.scrap == balance, name + ": nonlethal tower targeting cannot spend or award parts")
	if not through_simulation: check(game.mana == mana, name + ": a tower shot cannot consume hero mana")
	for hit: Dictionary in hits:
		check(int(hit.source) == game.hero.get_instance_id(), name + ": preserve the real production hurt source")
	cases.append({"name": name, "passed": failures.size() == initial_failures, "expected": expected_id,
		"actors": observations, "hits": hits.duplicate(true), "cooldown": pad.cooldown})
	if render_test and name in ["outside-threat-falls-back-to-legal-basic", "actual-C-overrides-threat"]:
		await capture(name + "-shot", targets)

func automatic_modes() -> void:
	await reset_case("threat")
	var outside := enemy("sapper", Vector3(15.51, 0, 0))
	var ordinary := enemy("basic", Vector3(5, 0, 0))
	await observe_shot("outside-threat-falls-back-to-legal-basic", ordinary, [outside, ordinary])

	await reset_case("nearest")
	var near_sapper := enemy("sapper", Vector3(3, 0, 0))
	var far_breaker := enemy("breaker", Vector3(10, 0, 0))
	ordinary = enemy("basic", Vector3(6, 0, 0))
	await observe_shot("nearest-ignores-threat-rank", near_sapper, [far_breaker, ordinary, near_sapper])

	await reset_case("breaker")
	var near_basic := enemy("basic", Vector3(3, 0, 0))
	far_breaker = enemy("breaker", Vector3(10, 0, 0))
	await observe_shot("breaker-prefers-legal-heavy", far_breaker, [near_basic, far_breaker])
	await reset_case("breaker")
	outside = enemy("breaker", Vector3(20, 0, 0))
	ordinary = enemy("basic", Vector3(4, 0, 0))
	await observe_shot("outside-breaker-falls-back-to-legal-basic", ordinary, [outside, ordinary])
	await reset_case("breaker")
	far_breaker = enemy("breaker", Vector3(10, 0, 0))
	var nearer_breaker := enemy("breaker", Vector3(7, 0, 0))
	ordinary = enemy("basic", Vector3(3, 0, 0))
	await observe_shot("breaker-chooses-nearer-heavy", nearer_breaker, [far_breaker, ordinary, nearer_breaker])

	# Named role pairs are independent expected outcomes, not a copied selector.
	for roles: Array in [["summoner", "light_eater"], ["light_eater", "lobber"],
		["lobber", "sapper"], ["sapper", "breaker"], ["breaker", "basic"]]:
		await reset_case("threat")
		var lower := enemy(String(roles[1]), Vector3(4, 0, 0))
		var higher := enemy(String(roles[0]), Vector3(10, 0, 0))
		await observe_shot("threat-priority-%s-before-%s" % [roles[0], roles[1]], higher, [lower, higher])
	await reset_case("threat")
	var far_sapper := enemy("sapper", Vector3(10, 0, 0))
	near_sapper = enemy("sapper", Vector3(4, 0, 0))
	await observe_shot("equal-threat-chooses-nearer-actor", near_sapper, [far_sapper, near_sapper])
	await reset_case("threat")
	ordinary = enemy("basic", Vector3(4, 0, 0))
	var far_basic := enemy("basic", Vector3(8, 0, 0))
	await observe_shot("threat-without-special-actors-uses-nearest", ordinary, [far_basic, ordinary])
	await reset_case("threat")
	outside = enemy("sapper", Vector3(14, 7, 0))
	ordinary = enemy("basic", Vector3(4, 0, 0))
	check((pad.position as Vector3).distance_to(outside.position) > 15.5,
		"The vertical-offset fixture lies beyond the preserved three-dimensional range")
	await observe_shot("threat-preserves-three-dimensional-range", ordinary, [outside, ordinary])

func strict_boundary(radius: float, label: String) -> void:
	for row: Array in [["nearest", "basic"], ["breaker", "breaker"], ["threat", "sapper"]]:
		for offset in [-.01, 0.0, .01]:
			await reset_case(String(row[0]))
			var actor := enemy(String(row[1]), Vector3(radius + offset, 0, 0))
			var distance := (pad.position as Vector3).distance_to(actor.position)
			check(distance < radius if offset < 0.0 else (distance > radius if offset > 0.0 else distance == radius),
				"The %s %s fixture must actually occupy its strict boundary side" % [label, row[0]])
			await observe_shot("%s-%s-boundary-%+.2f" % [label, row[0], offset], actor if offset < 0.0 else null, [actor])

func no_legal_target_and_cooldown() -> void:
	for row: Array in [["nearest", "basic"], ["breaker", "breaker"], ["threat", "sapper"]]:
		await reset_case(String(row[0]))
		var actor := enemy(String(row[1]), Vector3(20, 0, 0))
		await observe_shot("%s-no-legal-target" % row[0], null, [actor])
	await reset_case("threat")
	await observe_shot("empty-roster-does-not-fire", null, [])
	var defeated := enemy("sapper", Vector3(4, 0, 0))
	defeated.hurt(10000.0, game.hero)
	check(not defeated.alive, "The dead-target fixture must die through the actual hurt/defeat path")
	await observe_shot("actual-dead-actor-does-not-fire", null, [defeated])
	await process_frame
	await reset_case("nearest")
	var actor := enemy("basic", Vector3(4, 0, 0))
	await observe_shot("real-shot-calibration", actor, [actor])
	check(not hits.is_empty() and is_equal_approx(float(hits[0].hp_loss), 59.0)
		and is_equal_approx(float(pad.cooldown), .87), "A real standard first-level shot retains 59 damage and .87 second cooldown")
	var remaining_hp := actor.hp
	var remaining_cooldown: float = pad.cooldown
	hits.clear()
	game.update_towers(.1)
	check(actor.hp == remaining_hp and hits.is_empty() and is_equal_approx(float(pad.cooldown), remaining_cooldown - .1),
		"An unexpired production cooldown suppresses a second shot and decreases once")
	await reset_case("nearest")
	actor = enemy("basic", Vector3(4, 0, 0))
	actor.armor = 100.0
	actor.shield = 12.0
	actor.shield_time = 5.0
	await observe_shot("actual-hurt-armor-and-shield", actor, [actor])
	check(not hits.is_empty() and is_equal_approx(float(hits[0].hp_loss), 17.5)
		and is_equal_approx(float(hits[0].shield_loss), 12.0),
		"The real hurt signal retains armor reduction and shield absorption")

func actual_focus_controls() -> void:
	for row: Array in [["nearest", "basic"], ["breaker", "breaker"], ["threat", "sapper"]]:
		await reset_case(String(row[0]))
		var automatic := enemy(String(row[1]), Vector3(3, 0, 0))
		var focused := enemy("basic", Vector3(8, 0, 0))
		game.aim = focused.position
		await press(KEY_C)
		check(game.focus_target == focused and game.focus_time == 8.0 and game.focus_cooldown == 22.0,
			"Actual C must establish its real target and existing duration/cooldown")
		await observe_shot("actual-C-overrides-%s" % row[0], focused, [automatic, focused])
	await reset_case("threat")
	var automatic := enemy("sapper", Vector3(4, 0, 0))
	var focused := enemy("basic", Vector3(15.49, 0, 0))
	game.aim = focused.position
	await press(KEY_C)
	check(game.focus_target == focused, "C accepts the actual just-inside actor")
	focused.position = (pad.position as Vector3) + Vector3(15.51, 0, 0)
	await observe_shot("focused-actor-leaves-this-tower-range", automatic, [automatic, focused])
	await reset_case("threat")
	focused = enemy("basic", Vector3(15.5, 0, 0))
	game.aim = focused.position
	await press(KEY_C)
	check(not is_instance_valid(game.focus_target) and game.focus_time == 0.0 and game.focus_cooldown == 0.0,
		"Actual C rejects the strict boundary without starting its command cooldown")
	await observe_shot("rejected-boundary-focus-cannot-fire", null, [focused])
	await reset_case("nearest")
	var actor := enemy("basic", Vector3(4, 0, 0))
	place_hero((pad.position as Vector3) + Vector3(0, 0, 2.2))
	pad.cooldown = .5
	game.aim = actor.position
	await press(KEY_G)
	await press(KEY_C)
	var previous_hp := actor.hp
	hits.clear()
	game.update_towers(.1)
	check(String(pad.mode) == "breaker" and game.focus_target == actor and actor.hp == previous_hp
		and hits.is_empty() and is_equal_approx(float(pad.cooldown), .4),
		"Actual mode cycling and C cannot refresh or bypass an existing tower cooldown")

func real_simulation_gate() -> void:
	await reset_case("threat")
	var outside := enemy("sapper", Vector3(20, 0, 0))
	var ordinary := enemy("basic", Vector3(5, 0, 0))
	await observe_shot("actual-simulate-uses-the-same-legal-target", ordinary, [outside, ordinary], true)
	var previous_hp := ordinary.hp
	var previous_cooldown: float = pad.cooldown
	var previous_time: float = game.phase_time
	for frozen_phase in ["paused", "draft"]:
		game.phase = frozen_phase
		hits.clear()
		game.simulate(.4)
		check(ordinary.hp == previous_hp and float(pad.cooldown) == previous_cooldown
			and game.phase_time == previous_time and hits.is_empty(),
			"The actual %s simulation entry freezes tower cooldown and damage" % frozen_phase)
	await reset_case("threat")
	outside = enemy("sapper", Vector3(20, 0, 0))
	await observe_shot("actual-simulate-without-legal-target-does-not-fire", null, [outside], true)

func advanced_range_and_secondary_damage() -> void:
	await reset_case("nearest")
	game.scrap = 50
	check(game.build_or_upgrade_tower(game.world.tower_pads.size() - 1) and int(pad.level) == 2 and game.scrap == 0,
		"The actual paid upgrade establishes the real second-level tower")
	await strict_boundary(17.0, "level-two")
	game.scrap = 75
	check(game.build_or_upgrade_tower(game.world.tower_pads.size() - 1) and int(pad.level) == 3 and game.scrap == 0,
		"The actual paid upgrade establishes the real third-level tower")
	await strict_boundary(18.5, "level-three")
	# Secondary splash is intentionally allowed past the tower's own radius.
	await reset_case("nearest")
	var primary := enemy("basic", Vector3(18.49, 0, 0))
	var secondary := enemy("basic", Vector3(20, 0, 0))
	var primary_hp := primary.hp
	var secondary_hp := secondary.hp
	hits.clear()
	game.update_towers(.01)
	check(hits.size() == 2 and is_equal_approx(primary_hp - primary.hp, 93.0)
		and is_equal_approx(secondary_hp - secondary.hp, 33.48),
		"Preserve real third-level splash on a neighbour outside primary targeting range")
	await reset_case("nearest")
	place_hero((pad.position as Vector3) + Vector3(0, 0, 2.2))
	game.scrap = 45
	await press(KEY_K)
	check(game.specializations.branch(pad) == "control" and game.scrap == 0,
		"Actual K buys the control specialization on the real advanced tower")
	primary = enemy("basic", Vector3(18.49, 0, 0))
	secondary = enemy("basic", Vector3(20, 0, 0))
	primary_hp = primary.hp
	secondary_hp = secondary.hp
	hits.clear()
	game.update_towers(.01)
	check(hits.size() == 2 and is_equal_approx(primary_hp - primary.hp, 51.15)
		and is_equal_approx(secondary_hp - secondary.hp, 20.46),
		"Preserve real control-area secondary damage outside primary targeting range")

func finish() -> void:
	if is_instance_valid(game):
		await game.prepare_shutdown()
		current_scene = null
		game.queue_free()
		await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_TOWER_TARGETING_CASES ", JSON.stringify(cases))
	print("NIGHTFALL_TOWER_TARGETING_", "OK" if failures.is_empty() else "FAILED",
		" checks=", checks, " cases=", cases.size(), " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	if not failures.is_empty():
		await finish()
		return
	if render_test and not check(DisplayServer.get_name() != "headless",
		"Render acceptance requires an actual graphics backend"):
		await finish()
		return
	check(RunSession.queue_request(self, 20261006, "teaching"), "Supply the reproducible real-scene seed")
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	if not check(game.choose_card(0), "Choose the real opening core before targeting tests"):
		await finish()
		return
	game.clear_lobbers()
	game.clear_summoners()
	for creature: Variant in game.enemies:
		if is_instance_valid(creature): creature.queue_free()
	game.enemies.clear()
	await process_frame
	for index in game.world.tower_pads.size(): game.damage_tower(index, 10000.0)
	place_hero(Vector3(-8, 5, -4.2))
	game.scrap = 60
	if not check(game.build_tower_at(Vector3(-8, 5, -8)), "Build the real sole standard tower outside the living hero footprint"):
		await finish()
		return
	pad = game.world.tower_pads.back()
	if not check(int(pad.level) == 1 and game.tower_count() == 1 and game.relay_count() == 0
		and game.specializations.branch(pad) == "standard", "Use one genuine first-level standard tower without relay bonuses"):
		await finish()
		return
	await automatic_modes()
	await strict_boundary(15.5, "level-one")
	await no_legal_target_and_cooldown()
	await actual_focus_controls()
	await real_simulation_gate()
	await advanced_range_and_secondary_damage()
	await finish()
