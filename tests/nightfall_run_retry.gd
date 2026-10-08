extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
const Catalog := preload("res://scripts/outpost_catalog.gd")
## Cross-scene production retries. Uses the real input, scene reload, exploration,
## expedition, construction and troop systems rather than replacing their state.
## --render-test captures the two endings and all three opening modes offscreen.
const SCENE_PATH := "res://scenes/nightfall.tscn"
const HOME := Vector3(0, 5, 3.1)
const STEP := .05
const RETRY_RECT := Rect2(397, 648, 304, 52)
const NEW_RECT := Rect2(739, 648, 304, 52)
var game: Node3D
var checks := 0
var failures: Array[String] = []
var render_test := false
var scene_entries := 0
var evidence: Dictionary = {}

func _initialize() -> void:
	render_test = "--render-test" in OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.size = Vector2i(1920, 1200)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_size = Vector2i(1920, 1200)
		root.hide()
	root.child_entered_tree.connect(_root_entry)
	call_deferred("run")

func _root_entry(node: Node) -> void:
	if node.scene_file_path == SCENE_PATH: scene_entries += 1

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 30: push_error(message)

func press(code: int, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	game._unhandled_input(event)
	event.pressed = false
	game._unhandled_input(event)

func click_result(rect: Rect2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = rect.get_center() * game.hud.get_viewport_rect().size / Vector2(1440, 900)
	event.button_index = button
	event.pressed = true
	game.hud._gui_input(event)
	event.pressed = false
	game.hud._gui_input(event)

func freeze_current() -> void:
	game.set_process(false)
	game.world.set_process(false)

func stand(point: Vector3) -> void:
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.move_goal = point
	game.hero_path.clear()
	game.hero_keyboard_active = false

func remove_enemies() -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()

func vec(point: Vector3) -> Array:
	return [point.x, point.y, point.z]

func discovery_signature() -> Array:
	var result: Array = []
	for item: Dictionary in game.discoveries.items:
		result.append({"kind": String(item.kind), "position": vec(item.position),
			"rotation": vec(item.visual.rotation), "serial": int(item.serial),
			"state": String(item.state), "respawn": float(item.respawn)})
	return result

func wildlife_signature() -> Array:
	var result: Array = []
	for animal: Dictionary in game.wildlife.animals:
		result.append({"kind": String(animal.kind), "anchor": vec(animal.anchor),
			"position": vec(animal.position), "heading": float(animal.node.rotation.y),
			"state": String(animal.state), "timer": float(animal.timer)})
	return result

func opening_signature() -> Dictionary:
	var plans: Array = []
	for night in range(1, game.max_nights() + 1):
		plans.append(game.encounters.make_plan(game.run_mode, night, game.run.seed_value, 0).duplicate(true))
	return {"seed": game.run.seed_value, "mode": game.run_mode,
		"discoveries": discovery_signature(), "wildlife": wildlife_signature(),
		"route": game.exploration.route_order.duplicate(), "plans": plans}

func contract_signature() -> Array:
	var result: Array = []
	for offer: Dictionary in game.contracts.offers:
		var targets: Array = []
		for target: Dictionary in offer.targets:
			var source: Dictionary = target.source
			targets.append({"index": int(target.index), "position": vec(target.position),
				"state": String(source.get("state", "")), "serial": int(source.get("serial", 0)),
				"collected": bool(source.get("collected", false)), "cleansed": bool(source.get("cleansed", false))})
		result.append({"kind": String(offer.kind), "targets": targets,
			"scrap": int(offer.scrap), "risk": int(offer.risk),
			"risk_seconds": float(offer.risk_seconds), "risk_hunters": int(offer.risk_hunters)})
	return result

func assert_clean_opening(mode: String, label: String) -> void:
	check(current_scene == game and game.scene_file_path == SCENE_PATH, label + ": current_scene must be the real game scene")
	check(game.phase == "draft" and game.opening_night_pending and not game.run_mode_locked,
		label + ": retry must return to an unlocked opening draft")
	check(game.run_mode == mode and game.day_number == 1 and game.phase_time == game.NIGHT_LENGTH,
		label + ": mode is preselected while day and clock reset")
	check(not game.restart_pending and not game.victory and game.ending_key.is_empty(),
		label + ": restart and ending flags reset")
	check(game.scrap == 90 and game.kills == 0 and game.attack_count == 0,
		label + ": the shared scrap balance, kills and attack counters reset")
	check(game.run.owned.is_empty() and game.run.selections == 0 and game.run.memory_level == 0
		and game.run.pending == 1 and game.run.rerolls == 3,
		label + ": cards and paid growth reset with exactly one opening offer")
	check(game.run.offer.size() == 3 and game.run.core_id().is_empty(), label + ": all three starting cores remain available")
	check(game.hero.alive and game.hero.hp == 850.0 and game.hero.max_hp == 850.0
		and game.hero.damage == 58.0 and game.hero.armor == 0.0,
		label + ": hero health and combat attributes reset")
	check(game.mana == 300.0 and game.max_mana == 300.0 and game.hero.shield == 0.0
		and game.cooldowns == [0.0, 0.0, 0.0, 0.0, 0.0],
		label + ": energy, shield and all skill cooldowns reset")
	check(game.beacon_hp == game.BEACON_MAX and game.gate_trap_charges == 1 and game.gate_barricade_hp == 0,
		label + ": beacon and opening gate defenses reset")
	var live_towers := 0
	for pad: Dictionary in game.world.tower_pads:
		if int(pad.level) <= 0: continue
		live_towers += 1
		check(int(pad.level) == 1 and float(pad.hp) == 280.0 and float(pad.max_hp) == 280.0,
			label + ": opening towers must be undamaged level one")
	check(live_towers == 2, label + ": only the two opening towers survive")
	check(game.districts.plots.is_empty() and game.squads.squads.is_empty()
		and game.squads.training_queues.is_empty() and game.squads.selected_ids.is_empty(),
		label + ": city buildings, troops, training and selections are cleared")
	check(not game.construction.active and not game.selection_dragging and game.enemies.is_empty(),
		label + ": old previews, selection drags and enemies are cleared")
	check(game.generator_cells == 0 and game.survivors_rescued == 0 and game.cleansed_nests() == 0,
		label + ": expedition and nest progress reset")
	for generator: Dictionary in game.expeditions.generators:
		check(generator.state == "ready" and float(generator.progress) == 0.0,
			label + ": generator sites reset")
	for camp: Dictionary in game.expeditions.camps:
		check(camp.state == "waiting" and not is_instance_valid(camp.home_lantern),
			label + ": scouts wait outside without a previous home lantern")
	check(game.contracts.status == "idle" and game.contracts.offers.is_empty()
		and game.contracts.done.is_empty() and game.contracts.bonus_target.is_empty()
		and not game.contracts.bonus_done and game.contracts.bonus_choice.is_empty()
		and not game.contracts.progress_started and not game.contracts.risk_spawned,
		label + ": offers, work, bonus commitment and pursuit reset")
	check(game.exploration.run_discoveries == 0 and game.exploration.best_streak == 0
		and game.exploration.run_kinds.is_empty() and not game.exploration.full_set_claimed,
		label + ": exploration rewards and collection history reset")
	check(game.discoveries.items.size() == 18 and game.wildlife.animals.size() == 4,
		label + ": complete discovery and wildlife populations are rebuilt")
	for item: Dictionary in game.discoveries.items:
		check(item.state == "ready" and int(item.serial) == 0, label + ": discoveries restart before any refresh")

func assert_no_restart(label: String) -> void:
	var id := game.get_instance_id()
	var entries := scene_entries
	var seed_value: int = game.run.seed_value
	var phase: String = game.phase
	game.request_run_restart(true)
	game.request_run_restart(false)
	press(KEY_ENTER)
	# Result coordinates overlap legitimate cards/world controls outside ended.
	# Exercise the guarded APIs and Enter here; actual result clicks are tested
	# in ended rather than accidentally selecting an opening card as a fixture.
	await create_timer(.22).timeout
	check(is_instance_valid(game) and current_scene == game and game.get_instance_id() == id
		and scene_entries == entries and game.run.seed_value == seed_value and game.phase == phase
		and not game.restart_pending,
		label + ": ordinary gameplay/draft/pause must not reload through restart APIs or result controls")

func spawn_signature(extra_combat_draws: int) -> Array:
	for draw in extra_combat_draws: game.rng.randf()
	var result: Array = []
	for index in 12:
		var night: bool = index % 2 == 0
		var enemy: BattleUnit = game.spawn_creature(night, "runner" if night else "")
		result.append({"position": vec(enemy.position), "lane": float(enemy.get_meta("gate_lane")),
			"threat": String(enemy.get_meta("threat", "")), "night": night})
		check(enemy.position.is_finite(), "Production spawning must retain finite positions")
	remove_enemies()
	return result

func reach_second_day() -> Dictionary:
	press(KEY_1)
	check(game.phase == "night" and game.day_number == 1, "The real opening core key must begin night one")
	var first_plan: Array = game.night_plan.duplicate(true)
	remove_enemies()
	TransitionFixture.finish_for_fixture(game)
	check(game.phase == "draft" and game.day_number == 2, "Finishing the real first night must reach its dawn draft")
	press(KEY_1)
	check(game.phase == "day" and game.contracts.status == "active" and game.contracts.offers.size() == 3,
		"The real second-day draft must generate the three production contract candidates")
	remove_enemies()
	return {"first_plan": first_plan, "contracts": contract_signature(),
		"route": game.exploration.route_order.duplicate(), "next_plan": game.night_plan.duplicate(true)}

func exercise_refresh() -> Dictionary:
	var item: Dictionary = game.discoveries.items[0]
	check(item.kind == "ember_bloom" and item.state == "ready", "The first original discovery must be a ready bloom")
	stand(item.position)
	var previous: int = game.exploration.run_discoveries
	press(KEY_F)
	check(item.state == "cooling" and game.exploration.run_discoveries == previous + 1,
		"Ordinary F must collect the original discovery and grant its exploration reward")
	var delay: float = item.respawn
	check(delay >= 45.0 and delay <= 65.0, "The real collection must retain its random 45–65 second cooldown")
	var animal: Dictionary = game.wildlife.animals[0]
	var previous_anchor: Vector3 = animal.anchor
	stand(animal.position)
	var wildlife_visits: int = game.exploration.run_discoveries
	press(KEY_F)
	check(animal.kind == "stag" and animal.state == "leaving"
		and game.exploration.run_discoveries == wildlife_visits + 1,
		"Ordinary F must actually consume the original stag encounter and its exploration reward")
	check(float(animal.refresh) == game.wildlife.REFRESH_SECONDS,
		"The real wildlife encounter must begin its sixty-second renewal window")
	stand(HOME)
	# Advance the two real renewal systems with an identical operation sequence.
	# The controller clock/AI stay isolated so this tests seeded renewal, not survival.
	for tick in 1400:
		game.discoveries.tick(STEP)
		game.wildlife.tick(STEP)
	check(int(item.serial) == 1 and item.state == "ready", "The collected bloom must refresh once through the real tick path")
	check(animal.state in ["idle", "walk"] and animal.node.visible and animal.anchor != previous_anchor,
		"The touched stag must naturally respawn at a different real anchor through wildlife.tick")
	return {"cooldown": delay, "discoveries": discovery_signature(), "wildlife": wildlife_signature()}

func build_via_keys(kind: String, point: Vector3) -> void:
	var before: int = game.world.tower_pads.size() if kind == "tower" else game.districts.plots.size()
	game.aim = point
	game._apply_supply_reward({"type":"building_permit","kind":kind,
		"title":String(Catalog.building(kind).get("title",kind))})
	var placement: Dictionary = game.construction.snapshot()
	check(game.construction.active and game.construction.kind == kind and bool(placement.valid), "A real %s supply permit must select a legal live preview" % kind)
	if not bool(placement.valid): return
	var balance: int = game.scrap
	press(KEY_F)
	var after: int = game.world.tower_pads.size() if kind == "tower" else game.districts.plots.size()
	check(after == before + 1 and game.scrap == balance - int(placement.cost),
		"Real F must build one %s and charge its displayed fee" % kind)
	check(not game.construction.active and game.pending_build_permit_kind.is_empty(),
		"A successful %s permit placement must close the one-shot preview" % kind)

func clear_site_guards(site: Dictionary) -> void:
	for guard in site.guards:
		if is_instance_valid(guard) and guard.alive: guard.hurt(100000.0, game.hero)

func escort_home(camp: Dictionary) -> void:
	var npc: BattleUnit = camp.npc
	var begin: Vector2i = game.nearest_navigation_cell(game.hero.position, true)
	var end: Vector2i = game.nearest_navigation_cell(HOME, false)
	var route: PackedVector2Array = game.hero_navigation.get_point_path(begin, end)
	check(not route.is_empty(), "The actual escort must have a route through the only south gate")
	var steps := 0
	for cell in route:
		var target := Vector3(cell.x, 0, cell.y)
		target.y = game.outpost_height(target)
		game.move_goal = target
		while game.hero.position.distance_to(target) > .08 and steps < 4000:
			game.move_hero(STEP)
			game.expeditions.tick(STEP)
			steps += 1
	game.move_goal = HOME
	while camp.state == "escort" and steps < 4800:
		game.move_hero(STEP)
		game.expeditions.tick(STEP)
		steps += 1
	check(camp.state == "delivered" and npc.position.y > 4.8 and steps < 4800,
		"The recruited scout must actually follow the terrain route and reach home")

func complete_selected_contract() -> void:
	for target: Dictionary in game.contracts.targets:
		var source: Dictionary = target.source
		stand(source.position)
		press(KEY_F)
		match game.contracts.kind:
			"generator":
				clear_site_guards(source)
				game.expeditions.tick(game.expeditions.HOLD_SECONDS + STEP)
				check(source.state == "complete", "The marked generator must charge and clear its real guards")
			"escort":
				clear_site_guards(source)
				escort_home(source)
			"salvage": check(bool(source.collected), "The marked salvage must be gathered through real F")
			"nest": check(bool(source.cleansed), "The marked nest must be sealed through real F")
		game.update_day_contracts(0.0)
	check(game.contracts.status == "bonus_offer", "Actual main-objective completion must reach the production bonus decision")
	stand(Vector3(0, 0, 36))
	if game.contracts.status == "bonus_offer":
		press(KEY_4)
		check(game.contracts.status == "returning" and game.contracts.bonus_choice == "return",
			"A real bonus choice must leave a committed unclaimed return in the dirty run")

func dirty_run() -> void:
	remove_enemies()
	complete_selected_contract()
	# Contract categories vary by seed. Always establish real energy and rescue
	# progress as well, so their reset assertions cannot pass vacuously.
	if game.generator_cells == 0:
		for generator: Dictionary in game.expeditions.generators:
			if generator.state != "ready": continue
			stand(generator.position)
			press(KEY_F)
			check(generator.state == "active", "Ordinary F must start a real extra generator before retry")
			clear_site_guards(generator)
			game.expeditions.tick(game.expeditions.HOLD_SECONDS + STEP)
			break
	if game.survivors_rescued == 0:
		for camp: Dictionary in game.expeditions.camps:
			if camp.state != "waiting": continue
			stand(camp.position)
			press(KEY_F)
			check(camp.state == "escort", "Ordinary F must recruit a real scout before retry")
			clear_site_guards(camp)
			escort_home(camp)
			break
	check(game.generator_cells > 0 and game.survivors_rescued > 0,
		"Dirty run must contain completed real generator and delivered-scout progress")
	# Budget scaffolding funds real construction/queue actions. Their mutations
	# and debits are asserted; the reset must remove the resulting objects.
	game.scrap = 1600
	stand(HOME)
	build_via_keys("barracks", Vector3(-8, 5, -6))
	build_via_keys("workshop", Vector3(8, 5, -6))
	build_via_keys("tower", Vector3(-8, 5, 1))
	press(KEY_U)
	check(not game.squads.training_queues.is_empty(), "Real U must enqueue a shield squad at the new barracks")
	game.squads.advance(6.1)
	check(game.squads.squads.size() == 1 and game.squads.squads[0].members.size() == 3,
		"The real barracks queue must train all three shield members")
	press(KEY_I)
	check(not game.squads.training_queues.is_empty(), "Real I must leave unfinished ranged training for reset")
	press(KEY_TAB)
	check(game.squads.selected_count() == 1, "A real selection command must select the trained squad")
	press(KEY_ESCAPE)
	var before_reward: int = game.scrap
	var before_pending: int = game.run.pending
	# Real preceding contracts differ by seed; the next discovery may be the
	# fifth and must keep its native milestone rather than pretending it is 23.
	var milestone_reward: int=55 if (game.exploration_count+1)%5==0 else 0
	game.grant_exploration_reward("回归夹具物资", game.hero.position, 23, 0.0, 0.0, "salvage")
	check(game.scrap == before_reward + 23 + milestone_reward and game.run.pending == before_pending and game.phase == "day",
		"Exploration income and its real fifth-discovery milestone must credit shared scrap without automatically purchasing or opening cards")
	var before_upgrade: int = game.scrap
	var upgrade_cost: int = game.run.memory_cost()
	var before_level: int = game.run.memory_level
	press(KEY_V)
	check(game.phase == "draft" and game.run.pending == 1 and game.scrap == before_upgrade - upgrade_cost
		and game.run.memory_level == before_level + 1,
		"Real V must pay one announced fee from shared scrap and immediately open one upgrade")
	press(KEY_1)
	check(game.phase == "day" and game.run.pending == 0 and game.scrap == before_upgrade - upgrade_cost,
		"Choosing the already paid upgrade must resume the day without a second debit")
	check(game.run.selections >= 3 and game.run.memory_level >= 1, "Dirty run must contain actual paid growth and chosen cards")
	game.hero.hp = maxf(1.0, game.hero.hp - 123.0)
	game.beacon_hp -= 200.0
	press(KEY_W)
	check(game.mana < game.max_mana and game.cooldowns[1] > 0.0 and game.hero.shield > 0.0,
		"Real W must leave spent energy, an active shield and cooldown")
	game._apply_supply_reward({"type":"building_permit","kind":"tower","title":"炮塔"})
	check(game.construction.active, "The dirty run must also leave an active construction preview")
	check(game.districts.plots.size() == 2 and game.world.tower_pads.size() > 2,
		"Dirty run must contain real buildings and an additional tower")
	check(game.exploration.run_discoveries > 0 and game.contracts.done.size() > 0,
		"Dirty run must contain actual exploration and contract progress")

func finish_victory(expected_plans: Array) -> void:
	if game.construction.active: press(KEY_ESCAPE)
	for transition in 32:
		if game.phase == "ended": break
		if game.phase == "draft": press(KEY_1)
		elif game.phase == "day": game.start_night()
		elif game.phase == "night":
			var expected: Array = expected_plans[game.day_number - 1]
			if game.cleansed_nests() > 0:
				expected = game.encounters.make_plan(game.run_mode, game.day_number, game.run.seed_value, game.cleansed_nests())
			check(game.night_plan == expected,
				"Actual night %d must consume its seed-derived full plan" % game.day_number)
			remove_enemies()
			TransitionFixture.finish_for_fixture(game)
		else:
			check(false, "Victory fixture reached an unexpected phase")
			return
	check(game.victory and game.day_number == game.max_nights(), "The real final-night completion must expose the victory result")

func capture(label: String) -> void:
	if not render_test: return
	game.hud.queue_redraw()
	for frame in 6:
		await process_frame
		await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	check(picture.get_size() == Vector2i(1920, 1200), "The retry HUD must render at the actual 1920x1200 test size")
	check(picture.save_png("res://build/run-retry-%s.png" % label) == OK, "Save the actual retry HUD state " + label)

func assert_result_layout() -> void:
	var constants: Dictionary = game.hud.get_script().get_script_constant_map()
	check(constants.get("RESULT_RETRY_RECT", Rect2()) == RETRY_RECT
		and constants.get("RESULT_NEW_RECT", Rect2()) == NEW_RECT,
		"Both real result buttons must expose the agreed clickable rectangles")
	for rect in [RETRY_RECT, NEW_RECT]:
		check(Rect2(340, 215, 760, 515).encloses(rect), "Result buttons must remain inside the actual panel")
	check(not RETRY_RECT.intersects(NEW_RECT), "Same-run and new-run controls must not overlap")
	var font: Font = game.hud.font
	check(font.get_string_size("Enter · 同一守望再挑战", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x <= RETRY_RECT.size.x - 74.0,
		"The actual Chinese retry label must fit the production button's text inset")
	check(font.get_string_size("R · 全新守望", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x <= NEW_RECT.size.x - 156.0,
		"The actual Chinese new-run label must fit the production button's text inset")
	check(font.get_string_size("守望编号 %d" % game.run.seed_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= 280.0,
		"The current run identifier must fit before the adjacent result hint")
	for character in "守望全新再挑战":
		check(font.has_char(character.unicode_at(0)), "The selected result font must resolve Chinese glyph " + character)

func restart(same: bool, mouse: bool, label: String, opposite_second: bool = false) -> bool:
	var old_id := game.get_instance_id()
	var old_weak: WeakRef = weakref(game)
	var old_seed: int = game.run.seed_value
	var mode: String = game.run_mode
	var entries := scene_entries
	assert_result_layout()
	# Echo and secondary mouse buttons must never start a scene replacement.
	press(KEY_ENTER, true)
	click_result(RETRY_RECT, MOUSE_BUTTON_RIGHT)
	check(not game.restart_pending and game.get_instance_id() == old_id,
		label + ": echoed keys and right-clicks must be ignored")
	if mouse: click_result(RETRY_RECT if same else NEW_RECT)
	else: press(KEY_ENTER if same else KEY_R)
	check(game.restart_pending, label + ": the first real result action must reserve the restart synchronously")
	# Submit a second full action before the async audio/reload path yields.
	if mouse: click_result(NEW_RECT if opposite_second else (RETRY_RECT if same else NEW_RECT))
	else: press(KEY_R if opposite_second else (KEY_ENTER if same else KEY_R))
	var elapsed := 0.0
	while (current_scene == null or current_scene.get_instance_id() == old_id) and elapsed < 12.0:
		await create_timer(.02).timeout
		elapsed += .02
	check(current_scene != null and current_scene.get_instance_id() != old_id,
		label + ": actual reload_current_scene must replace current_scene before the deadline")
	if current_scene == null or current_scene.get_instance_id() == old_id: return false
	game = current_scene as Node3D
	freeze_current()
	await create_timer(.23).timeout
	check(old_weak.get_ref() == null and not is_instance_id_valid(old_id), label + ": the previous game instance must be released")
	check(scene_entries == entries + 1 and current_scene == game,
		label + ": duplicate result actions must create exactly one replacement scene")
	check((game.run.seed_value == old_seed) if same else (game.run.seed_value != old_seed),
		label + ": the result choice must preserve or replace the exact run seed")
	assert_clean_opening(mode, label)
	evidence[label] = {"old_id": old_id, "new_id": game.get_instance_id(),
		"old_seed": old_seed, "new_seed": game.run.seed_value, "scene_entries": scene_entries,
		"same_seed": same, "mode": game.run_mode}
	return true

func cleanup() -> void:
	if is_instance_valid(game):
		await game.prepare_shutdown()
		game.queue_free()
		await process_frame
	await create_timer(.5).timeout

func run() -> void:
	game = load(SCENE_PATH).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	freeze_current()
	if not game.has_method("request_run_restart"):
		check(false, "Production request_run_restart is missing; this regression cannot claim retry support")
		await cleanup()
		quit(1)
		return
	press(KEY_8)
	assert_clean_opening("siege", "initial iron-tide opening")
	for mode_index in 3:
		press(KEY_7 + mode_index)
		check(game.run_mode == ["teaching", "siege", "echo"][mode_index] and not game.run_mode_locked,
			"Each real opening mode key must remain available before choosing a core")
		await capture("opening-%s" % game.run_mode)
	press(KEY_8)
	var opening := opening_signature()
	await assert_no_restart("Opening draft")
	var first_day := reach_second_day()
	check(first_day.first_plan == opening.plans[0] and first_day.next_plan == opening.plans[1],
		"Both real night-one and next-night forecast must match their seeded plans")
	var spawn := spawn_signature(0)
	var refresh := exercise_refresh()
	evidence["baseline"] = {"opening": opening, "second_day": first_day, "spawn": spawn, "refresh": refresh}
	await assert_no_restart("Day gameplay")
	press(KEY_ESCAPE)
	check(game.phase == "paused", "Real Esc must pause the dirty-capable day")
	await assert_no_restart("Paused gameplay")
	press(KEY_ESCAPE)
	dirty_run()
	game.end_defeat("重试回归：真实失败入口")
	check(game.phase == "ended" and not game.victory, "Real defeat must expose the result input phase")
	await capture("defeat")
	if not await restart(true, false, "defeat-key-same", true):
		await cleanup(); quit(1); return
	check(opening_signature() == opening, "First same-run retry must reproduce every initial discovery, wildlife, route and night plan")
	var retry_day := reach_second_day()
	check(retry_day == first_day, "Same-run retry must reproduce the real second-day contracts, route and forecast")
	check(spawn_signature(257) == spawn, "Extra combat RNG draws must not change any actual subsequent creature spawn or lane")
	check(exercise_refresh() == refresh, "Identical real gathering and renewal operations must reproduce discovery and wildlife refreshes")
	dirty_run()
	finish_victory(opening.plans)
	await capture("victory")
	if not await restart(true, true, "victory-mouse-same"):
		await cleanup(); quit(1); return
	check(opening_signature() == opening, "The second consecutive same-run retry must still reproduce the original whole opening")
	check(reach_second_day() == first_day, "A second same-run retry must not retain the previous day or alter candidate generation")
	check(spawn_signature(509) == spawn, "Repeated retries must keep production spawn sampling independent of combat draws")
	check(exercise_refresh() == refresh, "A second retry must reset and reproduce the same renewal sequence")
	game.end_defeat("新局回归：失败入口")
	if not await restart(false, false, "defeat-key-new"):
		await cleanup(); quit(1); return
	var new_opening := opening_signature()
	check(new_opening.mode == opening.mode and new_opening.seed != opening.seed,
		"New-run keyboard choice must keep the requested mode while generating another seed")
	check(new_opening.discoveries != opening.discoveries and new_opening.wildlife != opening.wildlife,
		"A genuinely new run must vary the playable discovery and wildlife layouts")
	check(game.select_run_mode(2) and game.run_mode == "echo", "Even a preselected new run must allow the player to change its opening mode")
	check(game.select_run_mode(1), "The original standard mode remains selectable in the replacement opening")
	finish_victory(new_opening.plans)
	if not await restart(false, true, "victory-mouse-new"):
		await cleanup(); quit(1); return
	check(game.run.seed_value != new_opening.seed and game.run_mode == "siege",
		"The victory new-run button must replace the seed and preserve the player's last selected mode")
	check(game.select_run_mode(0) and game.run_mode == "teaching" and game.choose_card(2)
		and game.phase == "night" and game.run.has_core("core_guard"),
		"After every replacement the player must still be able to select another mode and starting core")
	await assert_no_restart("Night gameplay")
	if render_test:
		var file := FileAccess.open("res://build/run-retry-evidence.json", FileAccess.WRITE)
		check(file != null, "Open local retry evidence output")
		if file != null: file.store_string(JSON.stringify(evidence, "\t"))
	print("NIGHTFALL_RUN_RETRY_%s checks=%d reloads=%d failures=%d" %
		["OK" if failures.is_empty() else "FAILED", checks, scene_entries - 1, failures.size()])
	await cleanup()
	quit(0 if failures.is_empty() else 1)
