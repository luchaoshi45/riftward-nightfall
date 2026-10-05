extends SceneTree
## Real contracts, source dictionaries and P/F movement; no replacement ETA service.
## Actual 1920x1200 HUD frames: -- --render-test, hidden and Dummy audio.
const Contracts := preload("res://scripts/day_contracts.gd")
const Budget := preload("res://scripts/contract_route_budget.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
const HOME := Vector3(0, 5, 3.1)
const STEP := .05
const OUTER_X := Layout.FORT_TERRAIN_EDGE + .9
const HUD_CONTENT_WIDTH := 530.0
var game: Node3D
var failures: Array[String] = []
var checks := 0
var render_test := false
var observed_queries := 0
var observed_ratio := 0.0
var observed_escort := Vector2.ZERO
var shape_checked := false

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.size = Vector2i(1920, 1200)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_size = Vector2i(1920, 1200)
		root.hide()
	render_test = "--render-test" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 24: push_error(message)

func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_input(event)
	event.pressed = false
	game._unhandled_input(event)

func clear_enemies() -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()

func put_hero(point: Vector3) -> void:
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.hero_path.clear()
	game.move_goal = point

func move_source(target: Dictionary, point: Vector3) -> void:
	point.y = game.outpost_height(point)
	target.position = point
	target.source.position = point
	if is_instance_valid(target.source.get("node")): target.source.node.position = point

func seed_for(wanted: String, offer_index: int) -> int:
	var old_phase: String = game.phase
	var old_day: int = game.day_number
	game.phase = "day"
	game.day_number = 2
	var probe := Contracts.new()
	game.add_child(probe)
	var selected := -1
	for seed in 512:
		probe.setup(game, seed)
		probe.on_day()
		if probe.offers.size() > offer_index and String(probe.offers[offer_index].kind) == wanted:
			selected = seed
			break
	probe.queue_free()
	game.phase = old_phase
	game.day_number = old_day
	return selected

func boot_day(wanted: String, offer_index: int = 0) -> bool:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	check(game.choose_card(0) and game.phase == "night", "The actual opening choice must start the first night")
	clear_enemies()
	var seed := seed_for(wanted, offer_index)
	check(seed >= 0, "A real seed must expose %s in risk offer %d" % [wanted, offer_index])
	if seed < 0: return false
	game.run.seed_value = seed
	game.contracts.setup(game, seed)
	game.finish_night()
	check(game.phase == "draft" and game.day_number == 2, "Real first-night completion must enter the dawn draft")
	check(game.choose_card(0) and game.phase == "day", "The real dawn choice must generate the production contract")
	press(KEY_4 + offer_index)
	clear_enemies()
	game.hero.attack_timer = 999.0
	game.pulse_timer = 999.0
	put_hero(HOME)
	check(game.contracts.has_method("primary_budget"), "Production contracts must provide primary_budget")
	check(game.contracts.status == "active" and game.contracts.kind == wanted and game.contracts.selected_offer == offer_index,
		"Actual 4/5/6 input must select the requested real offer")
	return game.contracts.has_method("primary_budget") and game.contracts.kind == wanted

func close_game() -> void:
	if not is_instance_valid(game): return
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout

func budget(index: int = -1) -> Dictionary:
	var value: Dictionary = game.contracts.primary_budget(index)
	if not shape_checked:
		for key: String in ["active", "available", "next_goal", "outbound_distance", "return_distance", "work_seconds", "target_seconds",
			"total_seconds", "deadline_seconds", "deadline_spare_seconds", "spare_seconds", "risk", "combat_required", "guard_count", "escort", "remaining_targets"]:
			check(value.has(key), "The primary budget must expose its %s field" % key)
		shape_checked = true
	return value

func remaining(value: Dictionary) -> int:
	var result: Variant = value.get("remaining_targets", 0)
	return result.size() if result is Array else int(result)

func read_state() -> Dictionary:
	var sources: Array[Dictionary] = []
	for target: Dictionary in game.contracts.targets:
		var source: Dictionary = target.source
		sources.append({"state": source.get("state", ""), "progress": source.get("progress", 0.0),
			"collected": source.get("collected", false), "cleansed": source.get("cleansed", false), "respawn": source.get("respawn", 0.0)})
	return {"done": game.contracts.done.duplicate(true), "sources": sources, "status": game.contracts.status,
		"offer": game.contracts.selected_offer, "kind": game.contracts.kind, "scrap": game.scrap,
		"pending": game.contracts.pending_reward.duplicate(true), "clock": game.phase_time}

func assert_text_width(value: Dictionary, offer_index: int = -1) -> void:
	var index: int = game.contracts.selected_offer if offer_index < 0 else offer_index
	var rows: Array[Dictionary] = [
		{"text": Budget.travel_text(value), "font_size": 14},
		{"text": Budget.timing_text(value), "font_size": 12},
		{"text": game.contracts.offer_summary(index), "font_size": 11},
		{"text": "P指路/F行动 · " + game.contracts.choice_hint() + " · " + Budget.condition_text(value), "font_size": 11}]
	for row: Dictionary in rows:
		var text: String = row.text
		if text.is_empty(): continue
		var width: float = game.hud.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(row.font_size)).x
		check(width <= HUD_CONTENT_WIDTH, "The real %dpx primary HUD line must fit: %.1fpx / %s" % [int(row.font_size), width, text])

func capture(name: String, value: Dictionary) -> void:
	assert_text_width(value)
	if not render_test: return
	if DisplayServer.get_name() == "headless":
		check(false, "--render-test requires actual graphics")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	game.world.night_mix = 0.0
	game.world.apply_lighting()
	game.camera.size = 31.0
	game.camera.position = game.hero.position + Vector3(0, 25, 29)
	game.camera.look_at(game.hero.position)
	game.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered: Image = root.get_texture().get_image()
	check(rendered.get_size() == Vector2i(1920, 1200), "The actual %s HUD frame must render at 1920x1200" % name)
	check(rendered.save_png("res://build/primary-route-%s.png" % name) == OK,
		"The actual %s primary route HUD frame must save" % name)

func travel(destination: Vector3, expected_speed: float = -1.0) -> bool:
	check(game.contract_goal().is_equal_approx(destination), "P must follow the actual remaining contract target or home")
	press(KEY_P)
	check(not game.hero_path.is_empty(), "The real P input must generate a route")
	var elapsed := 0.0
	var stopped := 0
	var continuous := true
	var follows_height := true
	var speed_stable := true
	while flat(game.hero.position, destination) > .18:
		if game.phase != "day" or elapsed >= 40.0:
			check(false, "The real contract route must arrive before dusk without endless movement")
			return false
		var previous: Vector3 = game.hero.position
		game.simulate(STEP)
		elapsed += STEP
		continuous = continuous and game.can_traverse(previous, game.hero.position)
		follows_height = follows_height and absf(game.hero.position.y - game.outpost_height(game.hero.position)) < .01
		if expected_speed > 0.0: speed_stable = speed_stable and is_equal_approx(float(game.hero.speed), expected_speed)
		stopped = stopped + 1 if previous.distance_squared_to(game.hero.position) < .000001 else 0
		if stopped > 30:
			check(false, "The real P route must not stall at a wall")
			return false
	check(continuous and follows_height, "Every actual P movement step must respect fortress walls and ramp height")
	if expected_speed > 0.0:
		check(speed_stable and is_equal_approx(float(game.hero.speed), expected_speed),
			"The actual run-stat speed increase must remain applied throughout and after real P travel")
	game.move_goal = game.hero.position
	game.hero_path.clear()
	return true

func advance(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds and game.phase == "day":
		var delta := minf(STEP, seconds - elapsed)
		game.simulate(delta)
		elapsed += delta

func check_freeze() -> void:
	var frozen := read_state()
	var frozen_budget := budget()
	var frozen_queries: int = game.contracts.budget_route_queries
	game.paused_from = "day"
	game.return_phase = "day"
	for phase: String in ["paused", "draft"]:
		game.phase = phase
		game.simulate(10.0)
		game.contracts.tick(10.0)
		var value := budget()
		check(read_state() == frozen, "%s must freeze source progress, day clock, completed targets and rewards" % phase)
		check(is_equal_approx(float(value.total_seconds), float(frozen_budget.total_seconds))
			and is_equal_approx(float(value.work_seconds), float(frozen_budget.work_seconds))
			and game.contracts.budget_route_queries == frozen_queries,
			"%s must preserve the frozen travel/work ETA and not age the route-query cache" % phase)
		game.phase = "day"

func set_asymmetric_caches() -> void:
	put_hero(Vector3(OUTER_X, 0, -6.0))
	move_source(game.contracts.targets[0], Vector3(OUTER_X + .5, 0, -6.0))
	move_source(game.contracts.targets[1], Vector3(OUTER_X + .5, 0, -8.0))
	game.contracts.clear_budget_cache()

func check_salvage_geometry_and_reads() -> void:
	if not await boot_day("salvage"): await close_game(); return
	set_asymmetric_caches()
	var initial := budget()
	check(bool(initial.active) and bool(initial.available) and remaining(initial) == 2,
		"The real two-cache contract must include both remaining sources")
	check(flat(initial.next_goal, game.contracts.targets[0].position) < .001,
		"The budget next goal must match the first production P target")
	check(float(initial.outbound_distance) > 0.0 and float(initial.outbound_distance) < 3.0,
		"The actual two-cache outbound route must remain short beside the east wall")
	observed_ratio = float(initial.return_distance) / maxf(float(initial.outbound_distance), .001)
	check(observed_ratio > 8.0 and not game.can_traverse(game.contracts.targets[1].position, HOME),
		"The long south-gate return must not duplicate the short outbound leg or cut through a wall")
	check(is_zero_approx(float(initial.work_seconds)), "Primary salvage F is instantaneous; it must not acquire a discovery-cache channel")
	check(absf(float(initial.total_seconds) - (float(initial.outbound_distance) + float(initial.return_distance)) / game.hero.speed) < .02,
		"Primary salvage ETA must count the two outbound legs and distinct home route exactly once")
	var before := read_state()
	for index in game.contracts.offers.size():
		var offer_budget := budget(index)
		assert_text_width(offer_budget, index)
	check(read_state() == before, "Reading unselected offer budgets and text must not select, complete, or pay any contract")
	var total: float = initial.total_seconds
	game.phase_time = total + 20.0
	var safe := budget()
	check(String(safe.risk) == "ready", "Twenty spare seconds must report safe preparation time")
	await capture("safe", safe)
	game.phase_time = total + 4.0
	var tight := budget()
	check(String(tight.risk) == "tight", "Four spare seconds must report tight preparation time")
	await capture("tight", tight)
	game.phase_time = maxf(.1, total - .5)
	var late := budget()
	check(String(late.risk) == "late", "An impossible complete round trip must report late")
	await capture("late", late)
	game.phase_time = 90.0
	put_hero(game.contracts.targets[0].position)
	press(KEY_F)
	check(game.contracts.done.size() == 1 and bool(game.contracts.targets[0].source.collected),
		"Actual F must finish the first authoritative cache while leaving the primary contract active")
	var partial := budget()
	check(remaining(partial) == 1 and flat(partial.next_goal, game.contracts.targets[1].position) < .001,
		"The remaining budget must remove the collected cache and guide to the second source")
	check(float(partial.outbound_distance) < float(initial.outbound_distance), "Completed outbound work must reduce the remaining route")
	advance(55.1)
	check(not bool(game.contracts.targets[0].source.collected) and game.contracts.done.size() == 1,
		"Real 55-second cache refresh must retain the contract's completed source identity")
	check(remaining(budget()) == 1, "A refreshed but already completed cache must never return to the remaining budget")
	check_freeze()
	move_source(game.contracts.targets[1], Vector3(180, 0, 180))
	var unreachable := budget()
	check(not bool(unreachable.available) and String(unreachable.risk) == "unreachable",
		"A source outside real navigation must never advertise a zero-second safe trip")
	move_source(game.contracts.targets[1], Vector3(OUTER_X + .5, 0, -8.0))
	game.contracts.targets[1].source.collected = true
	game.phase_time = .1
	var finished_field := budget()
	check(remaining(finished_field) == 0 and String(finished_field.risk) == "late"
		and Budget.timing_text(finished_field).contains("保底"),
		"Already completed primary field work must retain its guarantee even during the pre-update late-return frame")
	game.contracts.status = "completed"
	var inactive := budget()
	check(not bool(inactive.active) and String(inactive.risk) == "inactive", "A completed contract must not retain an active primary budget")
	await close_game()

func check_generator_circle_edge_deadline() -> void:
	if not await boot_day("generator", 1): await close_game(); return
	var target: Dictionary = game.contracts.targets[0]
	var site: Dictionary = target.source
	if not travel(target.position): await close_game(); return
	press(KEY_F)
	for enemy in game.enemies.duplicate():
		if is_instance_valid(enemy) and enemy.alive: enemy.hurt(99999.0, game.hero)
	advance(11.0)
	check(site.state == "active" and absf(float(site.progress) - 11.0) < .02,
		"The actual cleared generator must retain one second of field work")
	put_hero(site.position + Vector3(4.0, 0, 0))
	var edge_position: Vector3 = game.hero.position
	game.phase_time = float(game.contracts.selected_reward.risk_seconds) + 1.2
	var edge := budget()
	check(bool(edge.available) and is_zero_approx(float(edge.outbound_distance)) and absf(float(edge.target_seconds) - 1.0) < .02,
		"Four metres inside the live hold circle must count one second of work and no unnecessary centre walk")
	check(String(edge.risk) != "late" and float(edge.deadline_spare_seconds) > 0.0,
		"One second of actual remaining hold must fit the 1.2-second field deadline at the circle edge")
	check(absf(float(edge.return_distance) - float(game.contracts.route_distance(edge_position, HOME))) < .02,
		"After holding at the edge, the return estimate must start at the hero's real position")
	advance(1.05)
	check(site.state == "complete" and game.contracts.status == "bonus_offer" and game.hero.position.distance_to(edge_position) < .001,
		"Real simulation must complete the generator before its cutoff without first moving to the centre")
	await close_game()

func check_generator_work_and_combat() -> void:
	if not await boot_day("generator"): await close_game(); return
	var target: Dictionary = game.contracts.targets[0]
	var site: Dictionary = target.source
	check(is_equal_approx(float(budget().work_seconds), game.expeditions.HOLD_SECONDS),
		"A ready generator must count its real twelve-second hold")
	if not travel(target.position): await close_game(); return
	press(KEY_F)
	check(site.state == "active" and site.guards.size() == 3, "Actual F must start the real generator and three ambushers")
	advance(6.0)
	var half := budget()
	check(absf(float(site.progress) - 6.0) < .02 and absf(float(half.work_seconds) - 6.0) < .02,
		"Six real seconds inside the generator circle must halve its remaining work")
	check_freeze()
	var held_progress: float = site.progress
	put_hero(site.position + Vector3(0, 0, 5.6))
	advance(2.0)
	check(is_equal_approx(float(site.progress), held_progress) and absf(float(budget().work_seconds) - 6.0) < .02,
		"Leaving the actual hold circle must not reduce remaining generator work")
	put_hero(site.position)
	advance(6.1)
	var guarded := budget()
	check(site.state == "active" and game.expeditions.guards_alive(site) and game.contracts.done.is_empty(),
		"Full charge with living ambushers must remain a real unfinished field action")
	check(bool(guarded.combat_required) and int(guarded.guard_count) > 0 and remaining(guarded) == 1,
		"Budget conditions must expose the living generator guards instead of advertising completion")
	check(is_zero_approx(float(guarded.work_seconds)) and not Budget.condition_text(guarded).is_empty(),
		"Completed charging must count zero hold seconds while still explicitly requiring combat")
	await capture("combat", guarded)
	var freed_guard: BattleUnit = site.guards[0]
	freed_guard.queue_free()
	await process_frame
	var after_release := budget()
	check(site.guards.size() == 3 and int(after_release.guard_count) == 2 and bool(after_release.combat_required),
		"Budget reads must ignore an already freed guard reference retained in the authoritative array")
	for guard in site.guards:
		if is_instance_valid(guard) and guard.alive: guard.hurt(99999.0, game.hero)
	advance(STEP)
	check(site.state == "complete" and game.contracts.status == "bonus_offer", "Actual guard deaths must release the generator field completion")
	await close_game()

func wait_for_scout(camp: Dictionary) -> bool:
	var elapsed := 0.0
	var continuous := true
	while String(camp.state) == "escort" and game.phase == "day" and elapsed < 35.0:
		var old_position: Vector3 = camp.npc.position
		game.simulate(STEP)
		if String(camp.state) == "escort": continuous = continuous and game.can_traverse(old_position, camp.npc.position)
		elapsed += STEP
	check(continuous, "The actual slower follower must not cut through walls while catching up")
	check(String(camp.state) == "delivered", "The actual NPC must reach the elevated home before the real escort can complete")
	return String(camp.state) == "delivered"

func check_escort_speed_and_delivery(living_ambush: bool) -> void:
	if not await boot_day("escort"): await close_game(); return
	var target: Dictionary = game.contracts.targets[0]
	var camp: Dictionary = target.source
	if not travel(target.position): await close_game(); return
	press(KEY_F)
	check(camp.state == "escort" and not camp.guards.is_empty(), "Actual F must recruit the real scout and create the camp ambush")
	if not living_ambush:
		for guard in camp.guards:
			if is_instance_valid(guard) and guard.alive: guard.hurt(99999.0, game.hero)
	var normal := budget()
	var normal_speed: float = game.hero.speed
	var target_speed := normal_speed * 2.0
	var exploration_bonus: float = game.exploration.speed_bonus_value() if is_instance_valid(game.exploration) else 0.0
	game.run.stats.speed = target_speed - game.HERO_MOVE_SPEED - exploration_bonus
	game.simulate(0.0)
	check(is_equal_approx(float(game.hero.speed), target_speed), "Real simulation must apply the speed increase from run stats")
	var accelerated := budget()
	var npc_distance_lower_bound: float = maxf(0.0, flat(camp.npc.position, Vector3.ZERO) - 6.2) / 5.4
	check(bool(accelerated.escort) and float(accelerated.total_seconds) >= npc_distance_lower_bound,
		"Hero acceleration must retain the actual scout's 5.4m/s return lower bound")
	check(float(accelerated.total_seconds) <= float(normal.total_seconds) + .01,
		"A faster hero cannot make an unchanged scout route estimate slower")
	if living_ambush:
		check(not bool(accelerated.combat_required), "Camp ambushers are a threat, not a mandatory kill gate for delivery")
	else:
		await capture("escort", accelerated)
	var predicted: float = accelerated.total_seconds
	var started_clock: float = game.phase_time
	if not travel(HOME, target_speed): await close_game(); return
	check(String(camp.state) == "escort" and flat(camp.npc.position, Vector3.ZERO) >= 6.2,
		"The accelerated hero must genuinely reach home before the slower scout")
	check(float(budget().total_seconds) > 0.0 and game.contracts.status == "active",
		"Hero arrival alone must not erase the still-exterior scout's ETA or complete the contract")
	if not wait_for_scout(camp): await close_game(); return
	check(is_equal_approx(float(game.hero.speed), target_speed), "The hero's real speed increase must remain applied while waiting for scout delivery")
	if living_ambush:
		var alive := 0
		for guard in camp.guards:
			if is_instance_valid(guard) and guard.alive: alive += 1
		check(alive > 0 and game.contracts.status == "bonus_offer", "Real scout delivery must remain possible while at least one camp ambusher lives")
	else:
		var actual: float = started_clock - game.phase_time
		observed_escort = Vector2(predicted, actual)
		check(absf(actual - predicted) <= maxf(2.0, predicted * .25),
			"Without combat, real P/F and slower-scout arrival must agree with ETA: %.2fs estimated / %.2fs actual" % [predicted, actual])
	press(KEY_4)
	game.update_day_contracts(0.0)
	check(game.contracts.status == "completed", "After genuine NPC return, the actual return choice may deliver the primary reward")
	var paid := read_state()
	budget()
	game.update_day_contracts(0.0)
	check(read_state() == paid, "A delivered escort budget and repeated update must never pay twice")
	await close_game()

func check_escort_deadline_radius() -> void:
	if not await boot_day("escort", 1): await close_game(); return
	var target: Dictionary = game.contracts.targets[0]
	var camp: Dictionary = target.source
	if not travel(target.position): await close_game(); return
	press(KEY_F)
	for enemy in game.enemies.duplicate():
		if is_instance_valid(enemy) and enemy.alive: enemy.hurt(99999.0, game.hero)
	put_hero(HOME)
	camp.npc.position = Vector3(0, Layout.FORT_HEIGHT, 6.3)
	camp.npc.path.clear()
	camp.trail = [HOME]
	game.phase_time = float(game.contracts.selected_reward.risk_seconds) + .2
	var near_home := budget()
	var warning: String = Budget.timing_text(near_home)
	check(String(near_home.risk) == "late" and warning.contains("风险") and not warning.contains("赶不上"),
		"A centre-route estimate near the actual hand-in radius must express deadline risk rather than guaranteed failure")
	advance(.1)
	check(camp.state == "delivered" and game.contracts.status == "bonus_offer",
		"Within two real frames, the scout may cross the 6.2m home radius and finish before the earlier cutoff")
	await close_game()

func check_early_field_deadlines() -> void:
	for offer_index in [1, 2]:
		if not await boot_day("salvage", offer_index): await close_game(); continue
		set_asymmetric_caches()
		var first := budget()
		var cutoff: float = game.contracts.selected_reward.risk_seconds
		check(is_equal_approx(cutoff, 8.0 * offer_index), "The actual selected risk must retain its eight/sixteen-second field deadline")
		game.phase_time = float(first.target_seconds) + cutoff - .25
		var field_late := budget()
		check(float(field_late.deadline_spare_seconds) < 0.0 and String(field_late.risk) == "late",
			"Field work that misses the earlier risk cutoff must warn even before the real dusk")
		game.phase_time = maxf(float(first.total_seconds) + 4.0, float(first.target_seconds) + cutoff + .25)
		var return_tight := budget()
		check(float(return_tight.deadline_spare_seconds) >= 0.0 and float(return_tight.spare_seconds) < 15.0,
			"An on-time field action must still show the separate tight return-home margin")
		check(String(return_tight.risk) == "tight", "Successful field timing must not hide a tight home-return budget")
		for target: Dictionary in game.contracts.targets.duplicate():
			put_hero(target.position)
			press(KEY_F)
		check(game.contracts.status == "bonus_offer", "Real completion before the field cutoff must preserve the primary guarantee")
		press(KEY_4)
		var home_seconds: float = game.contracts.return_budget().total_seconds
		game.phase_time = minf(cutoff - .1, home_seconds * .5)
		game.update_day_contracts(0.0)
		check(game.contracts.status == "returning", "The field cutoff must not expire a genuinely finished primary contract on its home leg")
		check(String(game.contracts.return_budget().risk) == "late", "The long remaining home leg must independently warn about actual dusk")
		await close_game()

func check_nest_combat_condition() -> void:
	if not await boot_day("nest"): await close_game(); return
	var target: Dictionary = game.contracts.targets[0]
	put_hero(target.position)
	var guard: BattleUnit = game.spawn_creature(true, "stalker")
	guard.position = target.position + Vector3(.8, 0, 0)
	guard.position.y = game.outpost_height(guard.position)
	var guarded := budget()
	press(KEY_F)
	check(not bool(target.source.cleansed) and bool(guarded.combat_required) and int(guarded.guard_count) != 0,
		"The real nest guard must block F and appear as a mandatory combat condition")
	guard.hurt(99999.0, game.hero)
	check(is_zero_approx(float(budget().work_seconds)), "Clearing a nest must not fabricate a fixed ten-second action")
	press(KEY_F)
	advance(STEP)
	check(bool(target.source.cleansed) and game.contracts.status == "bonus_offer", "After the real guard dies, actual F must seal the nest instantly")
	await close_game()

func check_navigation_invalidation() -> void:
	if not await boot_day("salvage"): await close_game(); return
	put_hero(Vector3(1.5, Layout.FORT_HEIGHT, 5.1))
	game.scrap = 10000
	for index in game.world.tower_pads.size():
		game.damage_tower(index, float(game.world.tower_pads[index].hp))
	var before := budget()
	check(bool(before.available), "Before construction, the actual field sources must have a valid south-gate route")
	for x: float in [-11.0, 11.0]:
		check(game.build_structure_at(Vector3(x, Layout.FORT_HEIGHT, 7.5), "barracks"), "Real paid barracks must form the ends of the full-width row")
	var gap_index := -1
	for x: float in [-7.5, -4.5, -1.5, 1.5, 4.5, 7.5]:
		var index: int = game.world.tower_pads.size()
		var built: bool = game.build_tower_at(Vector3(x, Layout.FORT_HEIGHT, 7.5))
		check(built, "Real paid towers must close the remaining grid-aligned row")
		if built and is_equal_approx(x, 1.5): gap_index = index
	var sealed := budget()
	check(not bool(sealed.available) and String(sealed.risk) == "unreachable",
		"Construction must immediately invalidate a primed budget route, without waiting for a cache timer")
	if gap_index >= 0:
		game.damage_tower(gap_index, float(game.world.tower_pads[gap_index].hp))
		var reopened := budget()
		check(bool(reopened.available) and is_finite(float(reopened.total_seconds)),
			"Actual tower destruction must immediately replace cached no-route geometry with the reopened route")
	await close_game()

func check_query_cadence() -> void:
	if not await boot_day("salvage"): await close_game(); return
	set_asymmetric_caches()
	put_hero(HOME)
	budget()
	var before: int = game.contracts.budget_route_queries
	var source_state := read_state()
	for _frame in 120:
		game.contracts.tick(1.0 / 60.0)
		budget()
		budget()
	observed_queries = game.contracts.budget_route_queries - before
	check(observed_queries > 0 and observed_queries <= 40,
		"120 double-read HUD frames must refresh actual A* geometry in bounded batches: %d queries" % observed_queries)
	check(read_state() == source_state, "Read-only route queries and contract ticks must not change work, rewards, or the day clock")
	await close_game()

func run() -> void:
	await check_salvage_geometry_and_reads()
	await check_generator_work_and_combat()
	await check_generator_circle_edge_deadline()
	await check_escort_speed_and_delivery(false)
	await check_escort_speed_and_delivery(true)
	await check_escort_deadline_radius()
	await check_early_field_deadlines()
	await check_nest_combat_condition()
	await check_navigation_invalidation()
	await check_query_cadence()
	print("NIGHTFALL_PRIMARY_ROUTE_BUDGET_", "OK" if failures.is_empty() else "FAILED", " checks=", checks,
		" gate_ratio=", observed_ratio, " queries_120_frames=", observed_queries, " escort_estimated_actual=", observed_escort,
		" real_P_F source_work field_deadlines navigation_invalidation readonly_pause", " rendered" if render_test else "")
	quit(0 if failures.is_empty() else 1)
