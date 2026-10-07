extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
## Single-wallet economics through the production scene, actual wave deaths,
## viewport-dispatched keyboard/mouse, city placement and training queues.
## Resource income is never fabricated to make either first-night route pass.
const RunSession = preload("res://scripts/run_session.gd")
const Build = preload("res://scripts/run_build.gd")
const SEED := 20261006
const SCENE := "res://scenes/nightfall.tscn"
const TOWER_POINT := Vector3(7.5, 5, -6.5)
const BARRACKS_POINT := Vector3(-7, 5, -6.5)
var game: Node3D
var checks := 0
var failures: Array[String] = []
var routes: Dictionary = {}

func _initialize() -> void:
	root.size = Vector2i(1920, 1200)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1920, 1200)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 30: push_error(message)

func press(code: int, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.echo = echo
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func mouse(pixel: Vector2, click: bool = false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pixel
	motion.global_position = pixel
	root.push_input(motion, true)
	await process_frame
	if not click: return
	var event := InputEventMouseButton.new()
	event.position = pixel
	event.global_position = pixel
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	event.button_mask = 0
	root.push_input(event, true)
	await process_frame

func click_ui(rect: Rect2) -> void:
	await mouse(rect.get_center() * game.hud.get_viewport_rect().size / Vector2(1440, 900), true)

func redraw() -> void:
	game.hud.queue_redraw()
	for _frame in 3: await process_frame

func freeze() -> void:
	game.set_process(false)
	game.world.set_process(false)

func stand(point: Vector3) -> void:
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.move_goal = point
	game.hero_path.clear()
	game.hero_keyboard_active = false
	game.hero.moving = false
	game.hero.set_locomotion_velocity(Vector3.ZERO)

func state() -> Dictionary:
	return {"scrap": int(game.scrap), "paid_level": int(game.run.memory_level),
		"cost": int(game.run.memory_cost()), "pending": int(game.run.pending),
		"queue": game.run.queue.duplicate(), "offer": game.run.offer.duplicate(true),
		"owned": game.run.owned.duplicate(true), "rng": game.run.rng.state,
		"training": game.squads.training_queues.duplicate(true), "phase": String(game.phase),
		"time": float(game.phase_time), "goal": game.move_goal, "path": game.hero_path.duplicate()}

func close_game() -> void:
	if not is_instance_valid(game): return
	await game.prepare_shutdown()
	if current_scene == game: current_scene = null
	game.queue_free()
	game = null
	for _frame in 4: await process_frame

func fresh() -> void:
	await close_game()
	check(RunSession.queue_request(self, SEED, "siege"), "A standard run must accept the fixed production session seed")
	game = load(SCENE).instantiate()
	root.add_child(game)
	current_scene = game
	for _frame in 5: await process_frame
	freeze()
	check(game.run.seed_value == SEED and game.run_mode == "siege", "The actual production run must consume seed 20261006 and standard mode")
	check(game.phase == "draft" and game.scrap == 90 and game.run.pending == 1
		and game.run.memory_level == 0 and game.run.memory_cost() == 120,
		"Opening must have exactly 90 parts, one free core and the first 120-part paid fee")
	var property_names: Array[String] = []
	for item: Dictionary in game.get_property_list(): property_names.append(String(item.name))
	check("essence" not in property_names and not game.has_method("collect_memory_upgrades"),
		"The current game must expose neither a second essence wallet nor automatic memory spending")
	await press(KEY_V)
	await press(KEY_V, true)
	check(game.scrap == 90 and game.run.memory_level == 0 and game.run.pending == 1,
		"V and key-repeat on the free opening must never purchase a second card")
	await press(KEY_1)
	check(game.phase == "night" and game.run_mode_locked and game.scrap == 90
		and game.run.memory_level == 0 and game.run.pending == 0,
		"The actual opening 1 key must enter night without spending or advancing paid growth")

func pure_fees() -> void:
	var build = Build.new(SEED)
	var costs := [120, 180, 260, 360, 500, 680, 884, 1150, 1495, 1944, 2528]
	for level in costs.size():
		check(build.memory_cost() == int(costs[level]) and build.memory_cost(level) == int(costs[level]),
			"Paid inscription fee %d must match the declared increasing parts schedule" % level)
		var random_state: int = build.rng.state
		for _read in 4: check(build.has_available_upgrade(), "A fresh supporting pool must contain a legal upgrade")
		check(build.rng.state == random_state and build.pending == 0 and build.memory_level == level,
			"Read-only card eligibility must neither draw randomness nor register a payment")
		check(build.register_memory_upgrade() == int(costs[level]) and build.memory_level == level + 1,
			"One successful registration advances exactly one paid fee")
	for card: Dictionary in Build.CARDS: build.owned[card.id] = int(card.cap)
	var before: int = build.rng.state
	check(not build.has_available_upgrade() and build.rng.state == before and build.pending == 0,
		"An exhausted supporting pool must be detected without drawing or queueing")

func reject_insufficient(label: String) -> void:
	var before := state()
	await press(KEY_V)
	await click_ui(game.hud.MEMORY_BUTTON_RECT)
	await press(KEY_V, true)
	check(state() == before, label + ": insufficient V, visible GUI and key-repeat must not spend, queue, reroll or command")

func earn_first_night() -> void:
	var before: int = game.scrap
	var death_count := 0
	for wave in 5:
		check(game.wave_index == wave + 1, "The production controller must create the actual sequential standard wave")
		var entry: Dictionary = game.wave_rewards.snapshot(wave)
		check(not entry.is_empty() and int(entry.budget) == 24 and bool(entry.sealed)
			and int(entry.count) == int(game.night_plan[wave].count),
			"Each standard wave must register its real saved enemy count against exactly 24 parts")
		var balance: int = game.scrap
		var victims: Array = game.enemies.duplicate()
		for creature: BattleUnit in victims:
			if not is_instance_valid(creature) or not creature.alive: continue
			creature.hurt(100000.0, game.hero)
			death_count += 1
			check(not creature.alive, "The ledger must receive a real lethal production hurt")
			var paid: int = game.scrap
			var kills: int = game.kills
			creature.hurt(100000.0, game.hero)
			check(game.wave_rewards.defeat(creature) == 0 and game.scrap == paid and game.kills == kills,
				"A repeated lethal hurt and duplicate ledger claim must never create another reward")
			check(game.run.pending == 0 and game.run.memory_level == 0,
				"Combat income must not automatically purchase an inscription")
		entry = game.wave_rewards.snapshot(wave)
		check(bool(entry.cleared) and int(entry.paid) == 24 and int(entry.kills) == int(entry.count)
			and game.scrap == balance + 24,
			"A fully cleared real standard wave must pay exactly 24 parts, without a hidden per-enemy twelve-part conversion")
		await process_frame
		game.enemies.clear()
		if wave == 0:
			check(game.scrap == 114, "The first standard wave alone must not fund a 120-part inscription")
			await reject_insufficient("First standard wave")
		if wave < 4: game.spawn_night_wave()
	check(death_count == 71 and game.kills == 71 and game.scrap == before + 120 and game.scrap == 210,
		"Five real first-night waves must yield exactly 120 parts and the untouched opening must total 210")
	var snapshot := state()
	for _read in 16:
		check(game.run.has_available_upgrade(), "A real run must retain available supporting cards")
		game.growth_snapshot()
	check(state() == snapshot, "Growth advice and card-pool reads must preserve the same parts wallet and all production state")

func build_gui(kind: String, point: Vector3) -> int:
	stand(Vector3(0, 5, 3.1))
	game.camera.size = 38.0
	game.camera.position = point + Vector3(0, 25, 29)
	game.camera.look_at(point)
	game.camera_follow = game.camera.position
	if not game.construction.active: await press(KEY_Y)
	check(game.construction.active, "Actual Y must enter city placement before purchasing " + kind)
	var kind_index := ["tower", "barracks", "workshop"].find(kind)
	await click_ui(game.hud.construction_kind_rect(kind_index))
	await mouse(game.camera.unproject_position(point))
	game._process(0.0)
	var placement: Dictionary = game.construction.snapshot()
	check(String(placement.kind) == kind and bool(placement.valid) and int(placement.cost) == 60,
		"The actual GUI/cursor must expose an affordable valid sixty-part " + kind)
	var count: int = game.world.tower_pads.size() if kind == "tower" else game.districts.plots.size()
	var balance: int = game.scrap
	await mouse(game.camera.unproject_position(point), true)
	var after: int = game.world.tower_pads.size() if kind == "tower" else game.districts.plots.size()
	check(after == count + 1 and game.scrap == balance - 60,
		"One real world click must place " + kind + " and pay the displayed shared-wallet fee once")
	var paid: int = game.scrap
	await mouse(game.camera.unproject_position(point), true)
	await press(KEY_F)
	check(game.scrap == paid and (game.world.tower_pads.size() if kind == "tower" else game.districts.plots.size()) == after,
		"Repeated occupied-cell mouse/F confirmation must not charge or duplicate " + kind)
	await press(KEY_ESCAPE)
	check(not game.construction.active and game.phase == "night", "Esc must close placement and retain active night play")
	return count if after == count + 1 else -1

func repair_gui(index: int) -> void:
	if index < 0: return
	var pad: Dictionary = game.world.tower_pads[index]
	game.damage_tower(index, 55.0)
	stand(pad.position + Vector3(2.1, 0, 0))
	var balance: int = game.scrap
	await press(KEY_H)
	check(game.scrap == balance - 20 and is_equal_approx(float(pad.hp), float(pad.max_hp)),
		"A real H repair must spend twenty shared-wallet parts and restore actual damaged tower durability")
	await press(KEY_H)
	check(game.scrap == balance - 20, "A second H on the repaired tower must not charge again")

func buy_inscription(mouse_first: bool) -> void:
	var balance: int = game.scrap
	var fee: int = game.run.memory_cost()
	var level: int = game.run.memory_level
	if mouse_first: await click_ui(game.hud.MEMORY_BUTTON_RECT)
	else: await press(KEY_V)
	check(game.phase == "draft" and game.scrap == balance - fee and game.run.memory_level == level + 1
		and game.run.pending == 1 and game.run.offer.size() == 3,
		"A successful real inscription input must charge one declared parts fee and open one legal draft")
	var before := state()
	await press(KEY_V)
	await press(KEY_V, true)
	await click_ui(game.hud.MEMORY_BUTTON_RECT)
	await click_ui(game.hud.MEMORY_BUTTON_RECT)
	game.simulate(5.0)
	check(state() == before, "Repeated V/GUI taps and draft simulation must not charge again, advance time or change choices")
	await redraw()
	check(not game.hud.card_rects.is_empty(), "Actual production draft must expose its real clickable card geometry")
	if not game.hud.card_rects.is_empty(): await click_ui(game.hud.card_rects[0])
	else: await press(KEY_1)
	check(game.phase == "night" and game.scrap == balance - fee and game.run.memory_level == level + 1
		and game.run.pending == 0,
		"Actual card confirmation must resume the interrupted night without charging the card again")

func route_hero() -> void:
	await fresh()
	await reject_insufficient("Untouched opening")
	await earn_first_night()
	await buy_inscription(false)
	check(game.scrap == 90 and game.run.memory_cost() == 180, "The first paid hero route must leave ninety parts and publish the next 180-part fee")
	var tower := await build_gui("tower", TOWER_POINT)
	await repair_gui(tower)
	check(game.scrap == 10 and game.run.memory_level == 1,
		"The first-night hero route must fund 120 inscription, 60 tower and 20 repair from real 210 income, leaving ten")
	routes.hero = {"earned": 120, "opening": 90, "inscription": 120, "tower": 60, "repair": 20, "remaining": int(game.scrap)}
	TransitionFixture.finish_for_fixture(game)
	check(game.phase == "draft" and game.run.pending == 1 and game.run.memory_level == 1 and game.scrap == 10,
		"Real dawn must grant a free card while preserving the paid level and low shared balance")
	await press(KEY_1)
	check(game.phase == "day" and game.run.memory_level == 1 and game.scrap == 10,
		"Selecting the dawn card must not require parts or advance paid growth")
	var victim: BattleUnit = game.spawn_creature(false, "basic")
	var balance: int = game.scrap
	victim.hurt(100000.0, game.hero)
	check(game.scrap == balance + 5 and game.run.pending == 0,
		"A real daytime enemy must keep its five-part payout without silently converting the removed twelve-memory drop")
	victim.hurt(100000.0, game.hero)
	check(game.scrap == balance + 5, "Repeated daytime lethal hurt must not pay again")

func open_army() -> void:
	if game.hud.detail_tab != "army":
		if game.hud.detail_tab.is_empty(): await press(KEY_F3)
		await click_ui(game.hud.details_tab_rect(2))
	await redraw()
	check(game.hud.detail_tab == "army", "The actual F3/tab GUI must open the compact army drawer")

func train_gui() -> void:
	await open_army()
	var balance: int = game.scrap
	var count := 0
	for queue: Array in game.squads.training_queues.values(): count += queue.size()
	await click_ui(game.hud.training_kind_rect(0))
	var after := 0
	for queue: Array in game.squads.training_queues.values(): after += queue.size()
	check(after == count + 1 and game.scrap == balance - 70,
		"A real visible army button must enqueue one shield squad and spend seventy shared-wallet parts")

func route_army() -> void:
	await fresh()
	await earn_first_night()
	var barracks := await build_gui("barracks", BARRACKS_POINT)
	check(barracks >= 0 and game.scrap == 150, "The first-night army route must buy an actual sixty-part barracks")
	await train_gui()
	check(game.scrap == 80 and game.squads.squads.is_empty(), "Shield order must be paid once before the actual training delay")
	var queue: Dictionary = game.squads.training_queues.duplicate(true)
	await press(KEY_ESCAPE)
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "Actual Esc must close the drawer before pausing play")
	var paused := state()
	game._process(4.0)
	game.simulate(4.0)
	await press(KEY_V)
	await click_ui(game.hud.MEMORY_BUTTON_RECT)
	check(state() == paused and game.squads.training_queues == queue and game.squads.squads.is_empty(),
		"Pause must freeze the actual night clock/training and reject both purchase inputs")
	await open_army()
	await click_ui(game.hud.training_kind_rect(0))
	check(game.scrap == 80 and game.squads.training_queues == queue, "Paused GUI training must not spend the shared parts wallet")
	await press(KEY_ESCAPE)
	await press(KEY_ESCAPE)
	check(game.phase == "night", "Actual Esc must return to the same interrupted night")
	var tower := await build_gui("tower", TOWER_POINT)
	await repair_gui(tower)
	check(game.scrap == 0 and game.run.memory_level == 0 and game.squads.training_queues == queue,
		"The first-night army route must fund barracks60/shield70/tower60/repair20 from the real 210 balance, ending at zero")
	routes.army = {"earned": 120, "opening": 90, "barracks": 60, "shield": 70, "tower": 60, "repair": 20, "remaining": int(game.scrap)}
	TransitionFixture.finish_for_fixture(game)
	check(game.phase == "draft" and game.run.pending == 1 and game.scrap == 0,
		"A genuine free dawn draft must remain available even with a zero shared wallet")
	var drafted := state()
	game._process(8.0)
	game.simulate(8.0)
	await press(KEY_V)
	await click_ui(game.hud.MEMORY_BUTTON_RECT)
	check(state() == drafted and game.squads.training_queues == queue,
		"A free pending draft must freeze real training/time and never become a repeated paid purchase")
	await press(KEY_1)
	check(game.phase == "day" and game.scrap == 0 and game.run.memory_level == 0,
		"A free dawn choice must resume day with zero parts and unchanged paid growth")
	game._process(6.1)
	check(game.squads.squads.size() == 1 and game.squads.squads[0].members.size() == 3
		and game.squads.training_queues.get(barracks, []).is_empty() and game.scrap == 0,
		"Resumed real training must produce three shield troops after six seconds without charging a second time")

func refunds_and_empty_pool() -> void:
	await fresh()
	await earn_first_night()
	var barracks := await build_gui("barracks", BARRACKS_POINT)
	await train_gui()
	await redraw()
	check(not game.hud.training_cancel_buttons.is_empty(), "Actual paid army order must expose its visible cancellation control")
	if not game.hud.training_cancel_buttons.is_empty():
		var button: Rect2 = game.hud.training_cancel_buttons[0].rect
		await click_ui(button)
		check(game.scrap == 150 and game.squads.training_queues.get(barracks, []).is_empty(),
			"Actual GUI cancellation must refund exactly the paid seventy parts to the same wallet")
		await redraw()
		await click_ui(button)
		check(game.scrap == 150, "Repeated empty cancellation input must not refund again")
	await train_gui()
	await train_gui()
	check(game.scrap == 10 and game.squads.training_queues.get(barracks, []).size() == 2,
		"Two real unfinished shield orders must have exactly 140 parts invested")
	if barracks >= 0:
		var plot: Dictionary = game.districts.plots[barracks]
		var result: Dictionary = game.districts.damage(barracks, float(plot.hp))
		check(bool(result.destroyed) and game.scrap == 150 and not game.squads.training_queues.has(barracks),
			"Production barracks destruction must release both unfinished orders and refund their real 140 parts once")
		game.districts.damage(barracks, 100000.0)
		game.squads.refresh_barracks()
		check(game.scrap == 150, "Repeated destruction/refresh must not refund the same orders twice")
	await press(KEY_ESCAPE)
	var owned: Dictionary = game.run.owned.duplicate(true)
	for card: Dictionary in Build.CARDS: game.run.owned[card.id] = int(card.cap)
	game.run.recalculate()
	var empty := state()
	await press(KEY_V)
	await click_ui(game.hud.MEMORY_BUTTON_RECT)
	check(not game.run.has_available_upgrade() and state() == empty,
		"An affordable but exhausted real card pool must reject V/GUI without charging, queueing, changing time or drawing randomness")
	game.run.owned = owned
	game.run.recalculate()
	game.run.grant("回归验证 · 免费待选能力")
	var balance: int = game.scrap
	await press(KEY_V)
	check(game.phase == "draft" and game.scrap == balance and game.run.memory_level == 0
		and game.run.pending == 1,
		"V must open an already pending free choice without purchasing or advancing a paid level")
	var pending := state()
	await press(KEY_V)
	await click_ui(game.hud.MEMORY_BUTTON_RECT)
	check(state() == pending, "Repeated input on an existing free draft must never purchase a second card")
	await press(KEY_1)
	check(game.phase == "night" and game.scrap == balance and game.run.memory_level == 0,
		"Choosing the existing free card must preserve the same wallet and paid fee")
	await buy_inscription(true)
	check(game.scrap == 30 and game.run.memory_level == 1,
		"Restored card eligibility must let the actual GUI purchase one 120-part inscription from the refunded wallet")

func await_restart(old_id: int) -> bool:
	for _frame in 600:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.scene_file_path == SCENE \
			and current_scene.get_instance_id() != old_id:
			game = current_scene
			freeze()
			for _settle in 4: await process_frame
			return true
	check(false, "Actual production restart must replace the scene within the bounded wait")
	return false

func assert_reset(label: String) -> void:
	check(game.phase == "draft" and game.opening_night_pending and game.scrap == 90
		and game.run.memory_level == 0 and game.run.memory_cost() == 120 and game.run.pending == 1
		and game.run.owned.is_empty() and game.run.selections == 0,
		label + ": shared parts, paid progression and free opening must reset completely")
	check(game.districts.plots.is_empty() and game.squads.squads.is_empty()
		and game.squads.training_queues.is_empty() and game.enemies.is_empty()
		and game.wave_rewards.snapshot(0).is_empty() and game.kills == 0,
		label + ": paid buildings, troops, queues, rewards and kills must not leak into the new scene")
	check(game.world.tower_pads.size() == 2 and game.run_mode == "siege",
		label + ": only the actual two opening towers and selected standard mode survive")

func real_restarts() -> void:
	var old_id: int = game.get_instance_id()
	game.end_defeat("单币回归 · 真实重开")
	await press(KEY_ENTER)
	if not await await_restart(old_id): return
	assert_reset("Same challenge")
	check(game.run.seed_value == SEED, "Real Enter retry must preserve the exact challenge seed")
	await press(KEY_1)
	await earn_first_night()
	await buy_inscription(false)
	old_id = game.get_instance_id()
	game.end_defeat("单币回归 · 另一守望")
	await press(KEY_R)
	if not await await_restart(old_id): return
	assert_reset("New challenge")
	check(game.run.seed_value != SEED and game.run.seed_value != 0,
		"Real R new challenge must reset the economy and choose a different nonzero production seed")

func run() -> void:
	var probe = Build.new(SEED)
	if not probe.has_method("has_available_upgrade"):
		check(false, "Production single-resource API is not yet implemented")
		print("NIGHTFALL_SINGLE_RESOURCE_ECONOMY_FAILED checks=%d failures=%d" % [checks, failures.size()])
		quit(1)
		return
	pure_fees()
	await route_hero()
	await route_army()
	await refunds_and_empty_pool()
	await real_restarts()
	await close_game()
	print("NIGHTFALL_SINGLE_RESOURCE_ROUTES " + JSON.stringify(routes))
	print("NIGHTFALL_SINGLE_RESOURCE_ECONOMY_OK checks=%d" % checks if failures.is_empty() \
		else "NIGHTFALL_SINGLE_RESOURCE_ECONOMY_FAILED checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
