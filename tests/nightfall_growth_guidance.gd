extends SceneTree
## Exercise growth advice against the real F/J/K/V and district/card inputs.
## Optional screenshots: Dummy audio, an offscreen window and -- --render-test.
const FAR := Vector3(105, 0, 95)
const Layout := preload("res://scripts/outpost_layout.gd")
const DISCOVERY_POINT := Vector3(18, 0, 0)
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

func click(point: Vector2) -> void:
	# parse_input_event takes window coordinates. Headless uses a 64px window
	# while canvas stretching retains the logical 1440x900 HUD viewport.
	var viewport_point: Vector2 = point * game.hud.get_viewport_rect().size / Vector2(1440, 900)
	var position: Vector2 = root.get_final_transform() * viewport_point
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	await process_frame
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.button_mask = 0
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func stand(point: Vector3) -> void:
	game.hero.position = point
	game.move_goal = point
	game.hero_path.clear()
	game.hero_keyboard_active = false

func isolate_interactions() -> void:
	game.contracts.status = "idle"
	game.beacon_hp = game.BEACON_MAX
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
	for cache: Dictionary in game.world.salvage:
		cache.collected = true
		cache.respawn = 9999.0
	for generator: Dictionary in game.expeditions.generators: generator.state = "complete"
	for camp: Dictionary in game.expeditions.camps: camp.state = "delivered"
	for nest: Dictionary in game.world.nests: nest.cleansed = true
	for relay: Dictionary in game.world.relays: relay.activated = true

func wilderness_boundaries() -> void:
	for item: Dictionary in game.discoveries.items:
		check(not Layout.contains_castle(item.position) and game.discoveries.position_available(item.position, game.discoveries.items.find(item)),
			"Real discoveries must start outside the enlarged castle, walls and travel ramp")
	for index in 36:
		var item_index: int = index % game.discoveries.items.size()
		var next: Vector3 = game.discoveries.choose_position(item_index, game.discoveries.items[item_index].position)
		check(game.discoveries.position_available(next, item_index), "Discovery refresh candidates must preserve castle/ramp/landmark clearances")
	for animal: Dictionary in game.wildlife.animals:
		check(game.wildlife.wilderness_walkable(animal.position), "Real wildlife must start outside castle walls and ramp")
		for _sample in 8:
			var next: Vector3 = game.wildlife.random_point(animal.position)
			check(game.wildlife.wilderness_walkable(next), "Wildlife refresh candidates must remain in wilderness")
			game.wildlife.choose_walk(animal)
			check(game.wildlife.wilderness_walkable(animal.target), "Wildlife roaming targets must stay clear of castle and ramp")
	for point: Vector3 in [Vector3(8, 5, 8), Vector3(0, 5, 16), Vector3(0, 0, 23), Vector3(13.8, 5, 0)]:
		check(not game.discoveries.position_available(point) and not game.wildlife.wilderness_walkable(point),
			"Castle interior, walls and the entire south ramp must reject exploration refreshes")

func check_text(snapshot: Dictionary, title: String) -> void:
	var lines: Array[String] = game.hud.growth_lines(snapshot)
	check(lines.size() == 3, "%s must fit three tower advice lines" % title)
	for index in lines.size():
		var size_px: int = [13, 12, 11][index]
		var width: float = game.hud.font.get_string_size(lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		check(width <= 322.0, "%s line %d exceeds the 322px content width: %.1f" % [title, index, width])
	var memory_text: String = game.hud.growth_memory_text(snapshot)
	var memory_width: float = game.hud.font.get_string_size(memory_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	check(memory_width <= 322.0, "%s memory text exceeds the 322px content width: %.1f" % [title, memory_width])
	for character in "防线南门核心东西外围塔建造升级改装零件铭刻记忆":
		check(game.hud.font.has_char(character.unicode_at(0)), "The actual HUD font must support Chinese glyph %s" % character)

func advice(index: int, action: String, cost: int, shortfall: int, title: String) -> Dictionary:
	var snapshot: Dictionary = game.growth_snapshot()
	var tower: Dictionary = snapshot.tower
	check(not tower.is_empty(), "%s must provide a tower action" % title)
	if tower.is_empty(): return snapshot
	check(int(tower.index) == index and String(tower.action) == action,
		"%s expected tower %d/%s, got %s" % [title, index, action, tower])
	check(int(tower.cost) == cost and int(tower.shortfall) == shortfall and bool(tower.affordable) == (shortfall == 0),
		"%s must publish the actual cost, deficit and affordability" % title)
	check_text(snapshot, title)
	return snapshot

func capture(state: String) -> void:
	if not render_test: return
	check(DisplayServer.get_name() != "headless", "Render verification requires the actual graphics renderer")
	if DisplayServer.get_name() == "headless": return
	game.notice_time = 0.0
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
	var output := "res://build/nightfall-growth-%s.png" % state
	check(root.get_texture().get_image().save_png(output) == OK, "The hidden %s growth HUD frame must save" % state)
	print("GROWTH_GUIDANCE_FRAME ", ProjectSettings.globalize_path(output))

func opening_upgrade() -> void:
	stand(game.world.tower_pads[0].position)
	check(game.scrap == 90 and game.run.pending == 0, "A real opening must retain 90 scrap and consume its opening card")
	var initial: Dictionary = advice(0, "upgrade", 50, 0, "opening affordable upgrade")
	check(int(initial.memory.cost) == 120 and int(initial.memory.shortfall) == 30,
		"The first inscription must share the real 90 scrap and show a 30-scrap deficit")
	await capture("affordable")
	await press(KEY_F)
	check(game.scrap == 40 and int(game.world.tower_pads[0].level) == 2,
		"Production F must spend the advised 50 scrap and upgrade the selected south-gate tower")
	check(int(initial.tower.target_level) == 2 and game.hud.growth_lines(initial)[0].contains("升至2级"),
		"Formatting a prior snapshot must preserve its target level after the live tower changes")
	advice(0, "specialize", 45, 5, "all unaffordable chooses smallest deficit")
	await capture("shortfall")
	await press(KEY_J)
	check(game.scrap == 40 and game.specializations.branch(game.world.tower_pads[0]) == "standard",
		"An unaffordable production J must retain both money and branch")
	game.scrap = 50
	advice(1, "upgrade", 50, 0, "affordable south-gate upgrade precedes modification")
	stand(game.world.tower_pads[1].position)
	await press(KEY_F)
	check(game.scrap == 0 and int(game.world.tower_pads[1].level) == 2,
		"The other actual south-gate F must also charge 50 scrap")

func complete_towers() -> void:
	game.phase = "day"
	game.scrap = 10000
	for index in game.world.tower_pads.size():
		var pad: Dictionary = game.world.tower_pads[index]
		stand(pad.position)
		while int(pad.level) < 3:
			var previous: int = int(pad.level)
			check(game.interact(), "Production F action must construct/upgrade fixture tower %d" % index)
			if int(pad.level) == previous: return
		if game.specializations.branch(pad) == "standard":
			check(game.choose_tower_specialization("piercing"), "Production branch action must finish fixture tower %d" % index)
	check(game.world.tower_pads.size() == 2, "The new castle must start with only two actual towers and no authored empty pads")
	stand(Vector3(0, 5, 3.9))
	await press(KEY_Y)
	for point: Vector3 in [Vector3(-8, 5, 4), Vector3(8, 5, 4), Vector3(0, 5, -8)]:
		game.aim = point
		game.aim_sample_pending = false
		var count: int = game.world.tower_pads.size()
		await press(KEY_F)
		check(game.world.tower_pads.size() == count + 1 and game.construction.active,
			"Real Y/F placement must append another tower and retain continuous construction")
	await press(KEY_ESCAPE)
	for index in range(2, game.world.tower_pads.size()):
		if not finish_production_tower(index, "actual free tower %d" % index): return
	var snapshot: Dictionary = game.growth_snapshot()
	check(int(snapshot.tower.index) == -1 and snapshot.tower.action == "place" and snapshot.tower.key == "Y" and snapshot.tower.label == "城内空地",
		"Completed suggested towers must retain a real Y free-placement opportunity")
	advice(-1, "place", 60, 0, "completed defense offers more castle towers")
	check_text(snapshot, "completed defense")
	await capture("castle-place")
	game.aim = Vector3(-6, 5, 6)
	await press(KEY_Y)
	check(game.construction.active, "The suggested actual Y input must open free placement")
	await press(KEY_ESCAPE)
	check(not game.construction.active and game.phase == "day", "Esc must cancel Y placement before pausing the day")

func candidate(index: int, level: int, branch := "piercing") -> void:
	# All fixture towers were built by production actions. Only their levels and
	# branch choices are varied to isolate recommendation order, never its result.
	var pad: Dictionary = game.world.tower_pads[index]
	pad.level = level
	pad.max_hp = 280.0 + maxf(0, level - 1) * 110.0
	pad.hp = pad.max_hp if level > 0 else 0.0
	pad.specialization = branch

func recommendation_order() -> void:
	stand(game.world.tower_pads[2].position)
	candidate(2, 1)
	candidate(0, 2, "standard")
	game.scrap = 100
	advice(0, "upgrade", 75, 0, "south-gate upgrade before closer core upgrade")
	game.scrap = 60
	advice(2, "upgrade", 50, 0, "affordable core upgrade before expensive south-gate upgrade")
	candidate(0, 3, "standard")
	advice(2, "upgrade", 50, 0, "other existing upgrade before existing modification")
	candidate(2, 3)
	candidate(3, 0, "standard")
	advice(0, "specialize", 45, 0, "existing modification before empty construction")
	candidate(0, 3)
	advice(3, "build", 60, 0, "empty pad follows completed existing towers")
	candidate(3, 3)
	game.world.tower_pads[3].hp = 0.0
	game.world.tower_pads[3].specialization = "standard"
	check(game.growth_snapshot().tower.action == "place", "An inconsistent dead tower must offer free placement instead of an invalid upgrade or modification")
	candidate(3, 3)

func district_discounts_and_branches() -> void:
	game.scrap = 500
	stand(Vector3(0, 5, 3.9))
	game.aim = Vector3(-8, 5, -7)
	game.aim_sample_pending = false
	await press(KEY_2)
	await press(KEY_F)
	await press(KEY_ESCAPE)
	check(game.districts.plots.size() == 1, "Real 2/F must append the first freely placed barracks")
	if game.districts.plots.is_empty(): return
	check(game.districts.plots[0].kind == "barracks" and game.scrap == 440,
		"Production 2/F must freely construct the actual 60-scrap barracks")
	stand(Vector3(-10, Layout.FORT_HEIGHT, 9))
	game.hero.hp = game.hero.max_hp - 100.0
	var hp_before: float = game.hero.hp
	game.simulate(1.0)
	check(is_equal_approx(game.hero.hp - hp_before, 5.0 + float(game.run.stats.regen)),
		"Production simulation must apply barracks recovery throughout the expanded castle")
	check(game.districts.guard_regen(Vector3(-10, 0, 9)) == 0.0 and game.districts.guard_regen(Vector3(0, 0, 30)) == 0.0,
		"Expanded barracks recovery must still reject wrong altitude and wilderness")
	stand(Vector3(0, 5, 3.9))
	game.aim = Vector3(8, 5, -7)
	game.aim_sample_pending = false
	await press(KEY_3)
	await press(KEY_F)
	await press(KEY_ESCAPE)
	check(game.districts.plots.size() == 2, "Real 3/F must append the freely placed workshop")
	if game.districts.plots.size() < 2: return
	check(game.districts.plots[1].kind == "workshop" and game.scrap == 380,
		"Production 3/F must freely construct the actual 60-scrap workshop")
	candidate(0, 2)
	stand(game.world.tower_pads[0].position)
	game.scrap = 68
	advice(0, "upgrade", 68, 0, "workshop level one uses ceiling rounding")
	game.scrap = 66
	advice(-1, "place", 54, 0, "affordable discounted new tower before unaffordable upgrade")
	await press(KEY_F)
	check(game.scrap == 66 and int(game.world.tower_pads[0].level) == 2,
		"Real F must refuse a 68-scrap upgrade when the live balance is 66")
	game.scrap = 200
	stand(game.districts.plots[1].position)
	await press(KEY_F)
	check(int(game.districts.plots[1].level) == 2 and game.scrap == 120,
		"Production F at a completed workshop must charge eighty to upgrade it")
	stand(game.world.tower_pads[0].position)
	game.scrap = 66
	advice(0, "upgrade", 60, 0, "workshop level two immediately changes affordability")
	await capture("workshop")
	await press(KEY_F)
	check(game.scrap == 6 and int(game.world.tower_pads[0].level) == 3,
		"Real F must use the newly advised 60-scrap upgrade cost")
	for choice: int in [KEY_J, KEY_K]:
		candidate(0, 3, "standard")
		game.scrap = 45
		advice(0, "specialize", 45, 0, "workshop never discounts third-level modification")
		await press(choice)
		var expected := "piercing" if choice == KEY_J else "control"
		check(game.scrap == 0 and game.specializations.branch(game.world.tower_pads[0]) == expected,
			"Production J/K must charge the undiscounted 45 and select the requested branch")
		advice(-1, "place", 48, 48, "selected branch leaves discounted free placement")
		await press(choice)
		check(game.scrap == 0, "Repeated specialization input must not charge again")
	game.damage_tower(0, float(game.world.tower_pads[0].hp))
	check(int(game.world.tower_pads[0].level) == 0 and game.specializations.branch(game.world.tower_pads[0]) == "standard",
		"Actual tower destruction must reset level and branch")
	game.scrap = 48
	stand(game.world.tower_pads[0].position + Vector3(2.1, 0, 0))
	advice(0, "build", 48, 0, "destroyed tower offers discounted reconstruction")
	await press(KEY_F)
	check(game.scrap == 0 and int(game.world.tower_pads[0].level) == 1,
		"Real F must spend 48 to rebuild without retaining its old branch")

func reset_memory() -> void:
	game.phase = "day"
	game.return_phase = "day"
	game.phase_time = 90.0
	game.run.pending = 0
	game.run.queue.clear()
	game.run.offer.clear()
	game.run.memory_level = 0
	game.scrap = 0
	game.exploration_count = 0
	game.exploration_milestones = 0
	game.exploration.reset_run()
	game.exploration.begin_day(1)

func memory_rewards_and_inputs() -> void:
	reset_memory()
	game.scrap = 108
	stand(DISCOVERY_POINT)
	var crystal: Dictionary = {}
	for item: Dictionary in game.discoveries.items:
		if item.kind == "memory_crystal": crystal = item; break
	check(not crystal.is_empty(), "The production world must contain a genuine memory crystal")
	if crystal.is_empty(): return
	crystal.position = DISCOVERY_POINT
	crystal.node.position = DISCOVERY_POINT
	crystal.state = "ready"
	await press(KEY_F)
	var memory: Dictionary = game.growth_snapshot().memory
	check(int(memory.pending) == 0 and int(memory.balance) == 120 and int(memory.cost) == 120 and int(memory.shortfall) == 0,
		"A real +12 crystal must update the common balance without automatic payment or queuing")
	check(game.phase == "day", "The actual reward must keep gameplay active until V")
	check_text(game.growth_snapshot(), "one queued imprint")
	await capture("queued")
	await press(KEY_V)
	check(game.phase == "draft", "Production V must open the queued improvement")
	var before: Dictionary = readonly_state()
	game._process(5.0)
	check(readonly_state() == before, "Draft simulation and growth reads must not consume a second memory payment")
	await press(KEY_1)
	check(game.phase == "day" and game.run.pending == 0 and game.scrap == 0 and game.run.memory_level == 1,
		"A real card selection must preserve the single 120-scrap payment and advance the price once")
	reset_memory()
	game.grant_exploration_reward("成长验证", DISCOVERY_POINT, 4200)
	memory = game.growth_snapshot().memory
	check(int(memory.pending) == 0 and int(memory.balance) == 4200 and int(memory.cost) == 120 and int(memory.shortfall) == 0,
		"A genuine income must remain available for buildings, troops or deliberate inscriptions")
	check_text(game.growth_snapshot(), "five queued imprints")
	await click(Vector2(1230, 500))
	check(game.phase == "day" and game.run.pending == 0 and game.scrap == 4200,
		"The old squad-panel memory hit area must not open queued cards")
	await click(Vector2(1230, 700))
	check(game.phase == "day" and game.run.pending == 0 and game.scrap == 4200,
		"Tower-growth advice rows must not open queued cards")
	await click(game.hud.MEMORY_BUTTON_RECT.get_center())
	check(game.phase == "draft" and game.run.pending == 1 and game.scrap == 4080,
		"The visible inscription button must purchase and open exactly one real upgrade")
	var balance: int = 4200
	for code: int in [KEY_1, KEY_2, KEY_3, KEY_1, KEY_2]:
		if game.phase == "day":await press(KEY_V)
		balance -= game.run.memory_cost(game.run.memory_level - 1)
		await press(code)
		check(game.run.pending == 0 and game.scrap == balance,
			"Each real V purchase and 1/2/3 choice must pay one fee from the common balance")
	check(game.phase == "day" and game.run.pending == 0, "The final real imprint must resume the interrupted day")
	var relay: Dictionary = game.world.relays[0]
	relay.activated = false
	stand(relay.position)
	var scrap_before: int = game.scrap
	await press(KEY_F)
	check(relay.activated and game.scrap == scrap_before + 85,
		"A real communication relay must grant its non-exploration 85 scrap")
	check(bool(game.growth_snapshot().tower.affordable), "Non-exploration income must immediately update tower affordability")

func finish_production_tower(index: int, title: String) -> bool:
	var pad: Dictionary = game.world.tower_pads[index]
	stand(pad.position + Vector3(2.1, 0, 0))
	while int(pad.level) < 3:
		var previous: int = int(pad.level)
		var built: bool = game.build_or_upgrade_tower(index)
		check(built and int(pad.level) == previous + 1, "%s must complete through production tower upgrades" % title)
		if not built or int(pad.level) == previous: return false
	if game.specializations.branch(pad) == "standard":
		var specialized: bool = game.choose_tower_specialization("piercing")
		check(specialized, "%s must complete through the actual specialization action" % title)
		if not specialized: return false
	return true

func blocked_empty_foundation() -> void:
	game.phase = "day"
	game.scrap = 10000
	for index in game.world.tower_pads.size():
		if not finish_production_tower(index, "isolated recommendation tower %d" % index): return
	var blocked: Dictionary = game.world.tower_pads[2]
	var legal: Dictionary = game.world.tower_pads[3]
	game.damage_tower(2, float(blocked.hp))
	game.damage_tower(3, float(legal.hp))
	check(int(blocked.level) == 0 and bool(blocked.get("free_built", false)) and int(legal.level) == 0,
		"Actual destruction must retain stable reconstruction identities for freely built towers")
	stand(blocked.position)
	var blocked_space: Dictionary = game.construction.validity(blocked.position, 2)
	check(not bool(blocked_space.space_valid) and not bool(blocked_space.valid),
		"A reconstruction position occupied by a real living unit must fail physical placement")
	var cost: int = game.districts.tower_cost(game.TOWER_COSTS[0])
	advice(3, "build", cost, 0, "occupied reconstruction yields to a clear destroyed tower")
	game.scrap = 0
	var legal_space: Dictionary = game.construction.validity(legal.position, 3)
	check(bool(legal_space.space_valid) and not bool(legal_space.valid),
		"A physically clear reconstruction must retain space validity despite insufficient money")
	advice(3, "build", cost, cost, "clear unaffordable reconstruction retains its full deficit")
	game.scrap = cost
	await press(KEY_F)
	check(int(blocked.level) == 0 and game.scrap == cost,
		"Real F must not build a tower underneath a living unit or spend its sufficient budget")
	stand(blocked.position + Vector3(2.1, 0, 0))
	advice(2, "build", cost, 0, "moving aside exposes the actual nearest reconstruction")
	await press(KEY_F)
	check(int(blocked.level) == 1 and game.scrap == 0,
		"Real F beside the wreck must pay once and rebuild its stable tower identity")
	game.scrap = 10000
	if not finish_production_tower(2, "reconstructed free tower"): return
	if not finish_production_tower(3, "other free reconstruction"): return
	game.scrap = 0
	advice(-1, "place", cost, cost, "completed actual towers retain unrestricted Y expansion and its deficit")

func readonly_state() -> Dictionary:
	var towers: Array[Dictionary] = []
	for pad: Dictionary in game.world.tower_pads:
		towers.append({"level": int(pad.level), "hp": float(pad.hp), "max_hp": float(pad.max_hp),
			"branch": game.specializations.branch(pad), "cooldown": float(pad.cooldown), "mode": String(pad.mode)})
	return {"scrap": game.scrap, "pending": game.run.pending,
		"memory_level": game.run.memory_level, "queue": game.run.queue.duplicate(), "offer": game.run.offer.duplicate(true),
		"towers": towers, "path": game.hero_path.duplicate(), "phase_time": game.phase_time,
		"discoveries_queries": game.discoveries.motivation_route_queries, "budget_queries": game.contracts.budget_route_queries}

func readonly_frames() -> void:
	await process_frame
	var before: Dictionary = readonly_state()
	var expected: Dictionary = game.growth_snapshot()
	for _frame in 120:
		check(game.growth_snapshot() == expected and game.growth_snapshot() == expected,
			"Repeated growth reads must remain stable without any live action")
		check(readonly_state() == before, "Two reads per frame must not spend, queue, mutate towers or request A*")
		await process_frame
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "Real Esc must freeze the growth state")
	before = readonly_state()
	for _frame in 5:
		game.growth_snapshot()
		game._process(1.0)
		check(readonly_state() == before, "Paused HUD growth reads must not consume gameplay clocks or resources")
	await press(KEY_ESCAPE)
	check(game.phase == "day", "Real Esc must resume the same day")
	var detached: Dictionary = game.growth_snapshot()
	detached.memory.balance = -999
	if not detached.tower.is_empty(): detached.tower.cost = -999
	check(readonly_state() == before, "Changing a returned display snapshot must never alter production state")

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	await press(KEY_1)
	check(game.phase == "night", "The actual opening card must start the playable scene")
	for enemy: BattleUnit in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	await process_frame
	wilderness_boundaries()
	isolate_interactions()
	await opening_upgrade()
	await complete_towers()
	recommendation_order()
	await district_discounts_and_branches()
	await memory_rewards_and_inputs()
	await blocked_empty_foundation()
	await readonly_frames()
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	if failures.is_empty():
		print("NIGHTFALL_GROWTH_GUIDANCE_OK checks=", checks,
			" actual_F_J_K_V_1_2_3 workshop=68/60 branch=45 progressive_memory readonly_240_reads_no_Astar Chinese_322px")
		quit()
	else:
		print("NIGHTFALL_GROWTH_GUIDANCE_FAILED checks=", checks, " failures=", failures.size())
		quit(1)
