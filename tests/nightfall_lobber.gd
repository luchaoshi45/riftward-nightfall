extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
## Real-scene lobber regression. Production simulate owns every attack clock;
## viewport-dispatched commands test dodges. Combat isolation explicitly gives
## 5000 parts, disables unrelated attacks and sets the hero's armour to zero.
const RunSession := preload("res://scripts/run_session.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
const SEED := 20261006
const HERO_POINT := Vector3(-4, 5, -10)
const SOURCE_POINT := Vector3(-10, 5, -10)
const VIEWPORTS := [Vector2i(1920, 1200), Vector2i(1920, 1080), Vector2i(1440, 900)]
var game: Node3D
var checks := 0
var failures: Array[String] = []
var completed: Array[String] = []
var render_test := false
var output_dir := "res://build/lobber"
var damage_events: Array[Dictionary] = []
var member_damage: Dictionary = {}
var evidence: Dictionary = {"seed": SEED, "fixture_parts": 5000, "captures": [], "dodges": {}, "targets": {}}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	render_test = "--render-test" in args
	var output_index := args.find("--output-dir")
	if output_index >= 0 and output_index + 1 < args.size():
		var candidate := ProjectSettings.globalize_path(args[output_index + 1]).simplify_path()
		var build_root := ProjectSettings.globalize_path("res://build").simplify_path()
		if candidate.begins_with(build_root + "/"): output_dir = candidate
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
	if failures.size() <= 35: push_error(message)

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func mouse(point: Vector3, button: int = 0) -> void:
	var pixel: Vector2 = game.camera.unproject_position(point)
	var motion := InputEventMouseMotion.new()
	motion.position = pixel
	motion.global_position = pixel
	root.push_input(motion, true)
	await process_frame
	if button == 0: return
	var event := InputEventMouseButton.new()
	event.position = pixel
	event.global_position = pixel
	event.button_index = button
	event.button_mask = MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	event.button_mask = 0
	root.push_input(event, true)
	await process_frame

func stand(point: Vector3) -> void:
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.move_goal = point
	game.hero_path.clear()
	game.hero_keyboard_active = false
	game.hero.moving = false
	game.hero.set_locomotion_velocity(Vector3.ZERO)

func camera_at(point: Vector3) -> void:
	game.camera.size = 30.0
	game.camera.position = point + Vector3(0, 25, 29)
	game.camera.look_at(point)
	game.camera_follow = game.camera.position

func clear_enemies() -> void:
	for value in game.enemies:
		if is_instance_valid(value): value.queue_free()
	game.enemies.clear()
	game.clear_lobbers()

func close_game() -> void:
	if not is_instance_valid(game): return
	var controller_ids: Array[int] = []
	for controller in game.lobbers:
		if is_instance_valid(controller): controller_ids.append(controller.get_instance_id())
	await game.prepare_shutdown()
	check(game.lobbers.is_empty(), "Actual prepare_shutdown must empty every lobber controller")
	if current_scene == game: current_scene = null
	game.queue_free()
	game = null
	for _frame in 4: await process_frame
	for id in controller_ids: check(not is_instance_id_valid(id), "Actual shutdown must release the previous lobber scene instance")

func record_damage(_hero: BattleUnit, source: BattleUnit, hp_loss: float, shield_loss: float) -> void:
	damage_events.append({"source": source.get_instance_id() if is_instance_valid(source) else -1,
		"health": hp_loss, "shield": shield_loss})

func record_member_damage(_member: BattleUnit, _source: BattleUnit, hp_loss: float, _shield_loss: float, id: int) -> void:
	if not member_damage.has(id): member_damage[id] = []
	member_damage[id].append(hp_loss)

func fresh(night: int = 1, keep_wave: bool = false) -> void:
	await close_game()
	check(RunSession.queue_request(self, SEED, "siege"), "The production lobber scene must accept the fixed standard seed")
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for _frame in 4: await process_frame
	game.set_process(false)
	game.world.set_process(false)
	await press(KEY_1)
	if night != 1:
		game.day_number = night
		game.start_night()
	check(game.phase == "night" and game.run.seed_value == SEED, "Actual opening/start_night must create the intended production night")
	if not keep_wave:
		clear_enemies()
		# Isolate attack timing from subsequent wave arrivals and dawn. The
		# saved-plan/ledger stage below retains the unmodified wave controls.
		game.phase_time = 1000.0
		game.wave_index = game.WAVES_PER_NIGHT
	game.scrap = 5000
	game.hero.max_hp = 10000.0
	game.hero.hp = game.hero.max_hp
	game.hero.armor = 0.0
	game.hero.shield = 0.0
	game.hero.attack_timer = 9999.0
	game.pulse_timer = 9999.0
	for pad: Dictionary in game.world.tower_pads: pad.cooldown = 9999.0
	damage_events.clear()
	member_damage.clear()
	game.hero.damage_confirmed.connect(record_damage)
	stand(HERO_POINT)
	camera_at(Vector3(-7, 5, -9))

func module_for(source: BattleUnit) -> Node3D:
	for controller in game.lobbers:
		if is_instance_valid(controller) and controller.get("host") == source: return controller
	return null

func spawn(point: Vector3 = SOURCE_POINT) -> Dictionary:
	var source: BattleUnit = game.spawn_creature(true, "lobber")
	point.y = game.outpost_height(point)
	source.position = point
	var controller := module_for(source)
	check(source.get_meta("threat", "") == "lobber" and source.title == "投蚀体" and controller != null,
		"Explicit production spawn must create a genuine thrower and independent game-owned attack controller")
	check(is_equal_approx(source.damage, 22.0) and is_equal_approx(source.attack_range, 11.2)
		and is_equal_approx(source.windup_duration, 1.15) and is_equal_approx(source.attack_interval, 4.8),
		"The actual spawned threat must expose its declared damage, ranged reach, windup and cooldown")
	check(source.legs.size() == 4 and source.stalker_head != null
		and is_instance_valid(source.visual.find_child("LobberNativeAcidSacks", true, false)),
		"The playable prototype must preserve the original animated rig and add its native acid-sack silhouette")
	return {"source": source, "controller": controller}

func begin(controller: Node3D, kind: String = "hero") -> Dictionary:
	game.simulate(.001)
	var state: Dictionary = controller.snapshot()
	check(String(state.phase) == "windup" and String(state.target_kind) == kind,
		"The real controller must begin its nearest live " + kind + " windup: " + String(state.phase) + "/" + String(state.target_kind))
	check(is_equal_approx(float(state.stage_remaining), 1.15) and is_equal_approx(float(state.remaining), 1.90)
		and is_equal_approx(float(state.radius), 2.0), "A new cast must expose 1.15 seconds of preparation plus .75 seconds of fixed-point flight")
	return state

func launch(controller: Node3D) -> Dictionary:
	var before: Dictionary = controller.snapshot()
	var count: int = damage_events.size()
	game.simulate(maxf(0.0, float(before.stage_remaining) - .01))
	check(String(controller.snapshot().phase) == "windup" and damage_events.size() == count,
		"The actual windup must not launch early or deal preparation damage")
	game.simulate(.011)
	var state: Dictionary = controller.snapshot()
	check(String(state.phase) == "flight" and is_equal_approx(float(state.stage_remaining), .75)
		and int(state.launched) == int(before.launched) + 1 and damage_events.size() == count,
		"Completed real preparation must launch once, retain .75 seconds of flight and cause no immediate damage")
	check(is_equal_approx(float(state.cooldown), 4.8), "The real 4.8-second cooldown must start at actual launch")
	return state

func land(controller: Node3D) -> Dictionary:
	var before: Dictionary = controller.snapshot()
	var count: int = damage_events.size()
	game.simulate(maxf(0.0, float(before.stage_remaining) - .01))
	check(String(controller.snapshot().phase) == "flight" and damage_events.size() == count,
		"The projectile must not apply damage before its complete flight interval")
	game.simulate(.011)
	var state: Dictionary = controller.snapshot()
	check(String(state.phase) == "impact" and int(state.impacts) == int(before.impacts) + 1,
		"Actual projectile arrival must commit exactly one impact")
	return state

func capture(label: String) -> void:
	if not render_test: return
	check(DisplayServer.get_name() != "headless", "Lobber evidence needs an actual graphical renderer")
	if DisplayServer.get_name() == "headless": return
	var snapshot_before: Array = game.lobber_warning_snapshot().duplicate(true)
	var phase_before: String = game.phase
	for viewport: Vector2i in VIEWPORTS:
		root.size = viewport
		root.content_scale_size = viewport
		game.world.night_mix = 1.0
		game.world.apply_lighting()
		game.hud.queue_redraw()
		for _frame in 5:
			await process_frame
			await RenderingServer.frame_post_draw
		var picture: Image = root.get_texture().get_image()
		check(picture.get_size() == viewport and Vector2i(game.hud.get_viewport_rect().size) == viewport,
			"Actual threat PNG/HUD content must use the requested " + str(viewport) + " viewport")
		var folder := ProjectSettings.globalize_path(output_dir)
		DirAccess.make_dir_recursive_absolute(folder)
		var name := "%s-%dx%d" % [label, viewport.x, viewport.y]
		check(picture.save_png(folder.path_join(name + ".png")) == OK, "Actual lobber evidence must be written only below local build")
		evidence.captures.append(name)
	check(game.phase == phase_before and game.lobber_warning_snapshot() == snapshot_before,
		"Sampling three actual viewports must not advance live attack timing or change the production stage")
	root.size = Vector2i(1920, 1200)
	root.content_scale_size = Vector2i(1920, 1200)
	for _frame in 3: await process_frame

func ground_ring(controller: Node3D, node_name: String, lift: float, label: String) -> Dictionary:
	var ring := controller.get(node_name) as MeshInstance3D
	check(is_instance_valid(ring), "The actual " + label + " warning must expose its live world mesh")
	if not is_instance_valid(ring): return {}
	check(ring.mesh is ArrayMesh and ring.scale.is_equal_approx(Vector3.ONE),
		"The " + label + " must use an unscaled terrain-sampled mesh, including changing progress radii")
	if not ring.mesh is ArrayMesh: return {}
	var mesh := ring.mesh as ArrayMesh
	var min_gap := INF
	var max_gap := -INF
	var min_terrain := INF
	var max_terrain := -INF
	var count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			var point := ring.to_global(vertex)
			var ground: float = game.outpost_height(point)
			var gap := point.y - ground
			check(point.is_finite() and absf(gap - lift) < .0001,
				"Every real " + label + " mesh vertex must retain its declared ground clearance on the south slope")
			min_gap = minf(min_gap, gap)
			max_gap = maxf(max_gap, gap)
			min_terrain = minf(min_terrain, ground)
			max_terrain = maxf(max_terrain, ground)
			count += 1
	check(count >= 48 and count <= 128 and max_terrain - min_terrain > .1,
		"The actual " + label + " must sample both uphill and downhill terrain with a bounded readable strip mesh")
	return {"vertices": count, "min_gap": min_gap, "max_gap": max_gap, "height_span": max_terrain - min_terrain}

func real_slope_warning_and_damage() -> void:
	await fresh()
	var point := Vector3(0, 0, 19.5)
	point.y = game.outpost_height(point)
	stand(point)
	camera_at(point)
	check(is_equal_approx(point.y, 2.5), "The slope regression must use the real authored halfway-down south ramp")
	for _group in 2:
		check(bool(game.squads.hire("shield").ok), "The slope fixture must create genuine living shield members")
	game.squads.select_all()
	game.squads.command_guard(point)
	var members: Array[BattleUnit] = []
	for group: Dictionary in game.squads.squads:
		# Ground members remain stationary to isolate true impact coverage.
		# The second group's middle member is at its exact guard station so
		# normal movement cannot silently ground the deliberate airborne case.
		group.formation_index = 0
		for member: BattleUnit in group.members:
			member.speed = 0.0
			member.armor = 0.0
			member.attack_timer = 9999.0
			member.damage_confirmed.connect(record_member_damage.bind(member.get_instance_id()))
			members.append(member)
	var offsets := [Vector3(0, 0, -1.5), Vector3(0, 0, 1.5), Vector3(0, 0, 2.01),
		Vector3(90, 0, 90), Vector3.ZERO, Vector3(-90, 0, 90)]
	for index in members.size():
		var position: Vector3 = point + offsets[index]
		position.y = game.outpost_height(position) + (1.0 if index == 4 else 0.0)
		members[index].position = position
	check(absf(members[0].position.y - point.y) > .75 and absf(members[1].position.y - point.y) > .75,
		"Both real ground defenders at 1.5m uphill/downhill must differ in world height enough to expose the old AoE defect")
	var spawned := spawn(Vector3(0, 0, 20))
	var controller: Node3D = spawned.controller
	check(absf(spawned.source.position.y - point.y) < .75 and game.can_attack_line(spawned.source.position, point),
		"The real south-ramp cast must still satisfy unchanged caster/target height and wall rules")
	var state := begin(controller)
	check((state.position as Vector3).distance_to(point) < .0001, "The real slope warning must lock the actual hero's ground point")
	var geometry: Array[Dictionary] = []
	geometry.append(ground_ring(controller, "_ring", .085, "slope outer windup"))
	geometry.append(ground_ring(controller, "_progress_ring", .12, "slope progress initial"))
	game.simulate(.50)
	geometry.append(ground_ring(controller, "_ring", .085, "slope outer mid-windup"))
	geometry.append(ground_ring(controller, "_progress_ring", .12, "slope progress mid-windup"))
	await capture("slope-windup")
	launch(controller)
	geometry.append(ground_ring(controller, "_ring", .085, "slope outer flight"))
	geometry.append(ground_ring(controller, "_progress_ring", .12, "slope progress flight"))
	await capture("slope-flight")
	land(controller)
	check(damage_events.size() == 1 and is_equal_approx(float(damage_events[0].health), 22.0),
		"The real warned slope hero must receive one twenty-two-damage impact")
	for index in members.size():
		var hits: Array = member_damage.get(members[index].get_instance_id(), [])
		if index in [0, 1]:
			check(hits.size() == 1 and is_equal_approx(float(hits[0]), 22.0),
				"A ground defender truly 1.5m along the slope inside the warning must take one actual twenty-two-damage hit")
		else:
			check(hits.is_empty(), "Actual slope impact must exclude a 2.01m-outside, remote or differently airborne defender")
	evidence.slope = {"point": point, "ground_offsets": [-1.5, 1.5], "outside_offset": 2.01,
		"airborne_offset": 1.0, "geometry": geometry}
	# A second production shot isolates wall occlusion from height rejection:
	# each unit stands on its own real ground, but the closed east wall lies
	# between the fixed point and a defender within the two-metre ground circle.
	await fresh()
	point = Vector3(12.7, 5, -10)
	stand(point)
	check(bool(game.squads.hire("shield").ok), "The wall-impact fixture must create actual living defenders")
	var group: Dictionary = game.squads.squads[0]
	for slot in 3:
		var member: BattleUnit = group.members[slot]
		member.speed = 0.0
		member.armor = 0.0
		member.attack_timer = 9999.0
		member.position = Vector3(14.65 if slot == 1 else 90.0 + slot, 0, -10)
		member.position.y = game.outpost_height(member.position)
		member.damage_confirmed.connect(record_member_damage.bind(member.get_instance_id()))
	var blocked: BattleUnit = group.members[1]
	check(Vector2(blocked.position.x - point.x, blocked.position.z - point.z).length() < 2.0
		and not game.can_attack_line(point, blocked.position), "The counterexample must use a true within-circle defender across the real east wall")
	spawned = spawn(point + Vector3(-4, 0, 0))
	controller = spawned.controller
	begin(controller)
	launch(controller)
	land(controller)
	check(damage_events.size() == 1 and member_damage.get(blocked.get_instance_id(), []).is_empty(),
		"A real impact must damage its reachable hero while excluding a nearby defender occluded by an actual closed wall")
	completed.append("slope")

func saved_plan_and_rewards() -> void:
	await fresh(1, true)
	check(game.night_plan.all(func(wave: Dictionary) -> bool: return not (wave.roles as Array).has("lobber")),
		"The existing first-night teaching pace must not silently gain the new ranged specialist")
	game.day_number = 2
	game.start_night()
	game.hero.attack_timer = 9999.0
	game.pulse_timer = 9999.0
	for pad: Dictionary in game.world.tower_pads: pad.cooldown = 9999.0
	var plan: Array = game.night_plan.duplicate(true)
	check(plan == game.encounters.make_plan("siege", 2, SEED, game.cleansed_nests()),
		"The production second night must retain the exact deterministic saved encounter plan")
	var lobber_count := 0
	var deaths := 0
	var income := 0
	for index in 5:
		var expected: Dictionary = plan[index]
		var actual: Array[String] = []
		var victims: Array = game.enemies.duplicate()
		check(victims.size() == int(expected.count), "The saved real wave count must equal its actual created combatants")
		var ledger: Dictionary = game.wave_rewards.snapshot(5 + index)
		check(int(ledger.budget) == 24 and int(ledger.count) == victims.size() and bool(ledger.sealed),
			"New ranged threats must remain inside the original sealed twenty-four-part wave budget")
		var balance: int = game.scrap
		for value in victims:
			if not is_instance_valid(value): continue
			var enemy := value as BattleUnit
			var role := String(enemy.get_meta("threat", "stalker"))
			actual.append("basic" if role == "stalker" else role)
			if role == "lobber":
				lobber_count += 1
				check(module_for(enemy) != null, "Every saved lobber role must spawn its independent actual projectile controller")
			enemy.hurt(100000.0, game.hero)
			deaths += 1
			var paid: int = game.scrap
			enemy.hurt(100000.0, game.hero)
			check(game.wave_rewards.defeat(enemy) == 0 and game.scrap == paid,
				"A real lobber/wave death must not grant a second ledger payment")
		actual.sort()
		var saved: Array = expected.roles.duplicate()
		saved.sort()
		check(actual == saved, "The actual wave must spawn the stored role multiset without rerolling specialist roles")
		ledger = game.wave_rewards.snapshot(5 + index)
		check(int(ledger.paid) == 24 and bool(ledger.cleared) and game.scrap == balance + 24,
			"Every completely defeated real wave including throwers must pay exactly twenty-four parts")
		income += game.scrap - balance
		await process_frame
		game.simulate(.001)
		game.enemies.clear()
		if index < 4: game.spawn_night_wave()
	check(lobber_count == 2 and income == 120 and game.night_plan == plan,
		"Second-night siege must introduce two planned throwers and retain five original wave budgets without modifying the saved plan")
	evidence.plan = {"actual_deaths": deaths, "lobbers": lobber_count, "parts": income, "wave_budget": 24}
	completed.append("plan")

func hero_timing_and_cooldown() -> void:
	await fresh()
	var spawned := spawn()
	var controller: Node3D = spawned.controller
	var source: BattleUnit = spawned.source
	var first := begin(controller)
	check((first.position as Vector3).distance_to(game.hero.position) < .01 and game.lobber_warning_snapshot().size() == 1
		and game.target_warning_snapshot().is_empty(), "The visible ranged warning must belong to the locked landing point rather than a second moving-target ring")
	var rng_before: int = game.spawn_rng.state
	for _read in 12: controller.snapshot(); game.lobber_warning_snapshot()
	check(controller.snapshot() == first and game.spawn_rng.state == rng_before,
		"Read-only attack/warning snapshots must preserve attack timing, point and random streams")
	await capture("windup")
	launch(controller)
	check(is_instance_valid(controller.find_child("LobberAcidProjectile", true, false)), "Actual launch must create the visible acid projectile")
	await capture("flight")
	var hp: float = game.hero.hp
	land(controller)
	check(damage_events.size() == 1 and is_equal_approx(float(damage_events[0].health), 22.0)
		and is_equal_approx(game.hero.hp, hp - 22.0), "Real arrival must submit one actual twenty-two-health-loss confirmation")
	await capture("impact")
	var after: Dictionary = controller.snapshot()
	game.simulate(.29)
	check(int(controller.snapshot().impacts) == 1 and damage_events.size() == 1 and game.lobber_warning_snapshot().is_empty(),
		"Impact visual retirement must not repeat damage or leave an old warning")
	var remainder: float = controller.snapshot().cooldown
	game.simulate(remainder - .01)
	check(controller.snapshot().phase == "idle" and int(controller.snapshot().launched) == 1 and damage_events.size() == 1,
		"The actual cooldown must prevent another ranged or ordinary melee hit before expiry")
	game.simulate(.011)
	check(controller.snapshot().phase == "windup" and int(controller.snapshot().launched) == 1,
		"Cooldown expiry must start another complete preparation rather than an instant repeat hit")
	source.hurt(1.0, game.hero)
	game.simulate(.02)
	check(controller.snapshot().phase == "windup" and int(controller.snapshot().cancelled) == 0,
		"Ordinary nonlethal hit recoil must not act as a stun or cancel a legitimate cast")
	launch(controller)
	land(controller)
	check(damage_events.size() == 2 and int(controller.snapshot().impacts) == 2,
		"A second complete preparation and flight may deliver one further real hit")
	check(float(after.cooldown) > 4.0 and float(after.cooldown) < 4.1,
		"Flight time must consume the source's launch-started cooldown exactly once per simulation step")
	completed.append("timing")

func real_dodges() -> void:
	await fresh()
	var spawned := spawn()
	var controller: Node3D = spawned.controller
	var state := begin(controller)
	var point: Vector3 = state.position
	var destination := HERO_POINT + Vector3(0, 0, 3.5)
	await mouse(destination, MOUSE_BUTTON_RIGHT)
	check(not game.hero_path.is_empty() and game.move_goal.distance_to(destination) < .2,
		"A genuine viewport right-click must give the hero a real dodge route")
	for _step in 5: game.simulate(.1)
	check(game.hero.position.distance_to(point) > 3.0 and controller.snapshot().position == point
		and controller.snapshot().phase == "windup", "Actual walking must leave the warned circle while the still-in-range cast retains its sampled landing point")
	launch(controller)
	land(controller)
	check(damage_events.is_empty() and int(controller.snapshot().impacts) == 1,
		"A real hero who walked outside the fixed two-metre blast must avoid the actual impact")
	evidence.dodges.walk = {"distance": game.hero.position.distance_to(point), "actual_hits": damage_events.size()}
	await capture("walking-dodge")
	await fresh()
	spawned = spawn()
	controller = spawned.controller
	state = begin(controller)
	point = state.position
	await mouse(HERO_POINT + Vector3(0, 0, 6))
	var mana_before: float = game.mana
	await press(KEY_E)
	check(game.hero.position.distance_to(point) > 5.5 and game.mana < mana_before and float(game.cooldowns[2]) > 0.0,
		"The real E input must spend mana/cooldown and move the hero out of the warned landing circle")
	launch(controller)
	land(controller)
	check(controller.snapshot().position == point and damage_events.is_empty(),
		"The actual launched throw must retain its old point and miss a real E dodge")
	evidence.dodges.dash = {"distance": game.hero.position.distance_to(point), "actual_hits": damage_events.size()}
	await capture("dash-dodge")
	completed.append("dodges")

func nearest_targets() -> void:
	for kind in ["squad", "tower", "district", "beacon", "barricade"]:
		await fresh()
		stand(Vector3(90, 0, 90))
		var point := Vector3.ZERO
		var before := 0.0
		var index := -1
		var member: BattleUnit
		match kind:
			"squad":
				check(bool(game.squads.hire("shield").ok), "Target fixture must create a genuine living shield squad")
				var group: Dictionary = game.squads.squads[0]
				game.squads.select_all()
				game.squads.command_guard(HERO_POINT)
				for slot in 3:
					var soldier: BattleUnit = group.members[slot]
					soldier.position = HERO_POINT + Vector3((slot - 1) * 1.25, 0, 0)
					soldier.attack_timer = 9999.0
					soldier.armor = 0.0
				member = group.members[0]
				point = member.position
				before = member.hp
			"tower":
				index = 0
				point = game.world.tower_pads[index].position
				before = game.world.tower_pads[index].hp
			"district":
				point = Vector3(-7.5, 5, -8)
				check(game.build_structure_at(point, "workshop"), "Target fixture must construct a real live workshop")
				index = game.districts.plots.size() - 1
				before = game.districts.plots[index].hp
			"beacon":
				point = Vector3(0, 5, 0)
				before = game.beacon_hp
			"barricade":
				stand(Vector3(0, 5, Layout.RAMP_TOP))
				await press(KEY_B)
				check(game.gate_barricade_hp > 0.0, "Target fixture must build a genuine paid gate barricade through B")
				stand(Vector3(90, 0, 90))
				point = game.gate_barricade.position
				before = game.gate_barricade_hp
		var source_point := point + Vector3(-4, 0, 0)
		if kind == "squad": source_point = SOURCE_POINT
		# The real barricade sits halfway down the south ramp. Keep the
		# attacker on that same sloped surface within its .75m height tolerance.
		if kind == "barricade": source_point = point + Vector3(0, 0, .5)
		var spawned := spawn(source_point)
		var controller: Node3D = spawned.controller
		if kind == "barricade":
			check(absf(spawned.source.position.y - point.y) <= .75
				and game.can_attack_line(spawned.source.position, point),
				"Real ramp geometry must keep the barricade fixture within height and line-of-sight rules")
		var state := begin(controller, kind)
		check((state.position as Vector3).distance_to(point) < .01,
			"The real nearest " + kind + " must supply the fixed landing position")
		if kind == "squad":
			check(int(state.target_token) == member.get_instance_id() and not game.squads.intercept_enemy(spawned.source, .01),
				"A shield can be a ranged target without forcing the thrower into the ordinary melee intercept path")
		launch(controller)
		land(controller)
		var hp := 0.0
		match kind:
			"squad": hp = member.hp
			"tower": hp = game.world.tower_pads[index].hp
			"district": hp = game.districts.plots[index].hp
			"beacon": hp = game.beacon_hp
			"barricade": hp = game.gate_barricade_hp
		check(is_equal_approx(before - hp, 22.0), "The actual nearest " + kind + " must take one real twenty-two-damage impact")
		evidence.targets[kind] = {"before": before, "after": hp, "damage": before - hp}
	completed.append("targets")

func area_boundaries_and_host_damage() -> void:
	await fresh()
	check(bool(game.squads.hire("shield").ok), "Area fixture must produce an actual living squad")
	var group: Dictionary = game.squads.squads[0]
	game.squads.select_all()
	game.squads.command_guard(HERO_POINT)
	for slot in 3:
		var member: BattleUnit = group.members[slot]
		member.position = HERO_POINT + Vector3([.4, 1.5, 2.01][slot], 0, 0)
		member.speed = 0.0
		member.attack_timer = 9999.0
		member.armor = 0.0
		member.damage_confirmed.connect(record_member_damage.bind(member.get_instance_id()))
	var spawned := spawn()
	var source: BattleUnit = spawned.source
	var controller: Node3D = spawned.controller
	source.damage = 35.0
	begin(controller)
	launch(controller)
	source.damage = 99.0
	land(controller)
	check(damage_events.size() == 1 and is_equal_approx(float(damage_events[0].health), 35.0),
		"Actual launch must sample host.damage once rather than hardcode22 or read a changed post-launch value")
	for slot in 3:
		var member: BattleUnit = group.members[slot]
		var hits: Array = member_damage.get(member.get_instance_id(), [])
		check(hits == [35.0] if slot < 2 else hits.is_empty(),
			"A genuine squad member must receive one sampled hit inside the fixed radius and zero outside it")
	await fresh()
	stand(Vector3(90, 0, 90))
	var left := Vector3(-7.5, 5, -8.5)
	var right := Vector3(-4.5, 5, -8.5)
	check(game.build_structure_at(left, "tower") and game.build_structure_at(right, "tower"),
		"Blast footprint fixture must build two genuinely adjacent three-cell towers")
	var first: int = game.world.tower_pads.size() - 2
	var second: int = first + 1
	for pad: Dictionary in game.world.tower_pads: pad.cooldown = 9999.0
	var hp_first: float = game.world.tower_pads[first].hp
	var hp_second: float = game.world.tower_pads[second].hp
	spawned = spawn(left + Vector3(-4, 0, 0))
	controller = spawned.controller
	begin(controller, "tower")
	launch(controller)
	land(controller)
	check(is_equal_approx(hp_first - float(game.world.tower_pads[first].hp), 22.0)
		and is_equal_approx(hp_second - float(game.world.tower_pads[second].hp), 22.0),
		"The actual blast must cover a neighbouring building's real footprint even when its center is three metres away")
	completed.append("area")

func interrupted_and_cancelled() -> void:
	await fresh()
	var spawned := spawn()
	var controller: Node3D = spawned.controller
	var source: BattleUnit = spawned.source
	begin(controller)
	var id := controller.get_instance_id()
	source.hurt(100000.0, game.hero)
	check(controller.snapshot().cancel_reason == "source_dead" and int(controller.snapshot().launched) == 0,
		"Real lethal damage during preparation must immediately cancel the unlaunched attack")
	await process_frame
	game.simulate(2.0)
	check(damage_events.is_empty() and game.lobbers.is_empty(), "A truly released preparation source must not leave damage or a stale controller")
	await process_frame
	check(not is_instance_id_valid(id), "The actually cancelled dead-source controller must be freed")
	await fresh()
	spawned = spawn()
	controller = spawned.controller
	begin(controller)
	stand(Vector3(-4, 0, -30))
	game.simulate(.01)
	check(controller.snapshot().cancel_reason == "target_range" and int(controller.snapshot().launched) == 0,
		"Moving the true target beyond eleven-point-two metres during preparation must cancel before launch")
	await fresh()
	spawned = spawn()
	controller = spawned.controller
	begin(controller)
	stand(Vector3(-4, 0, -18))
	game.simulate(.01)
	check(controller.snapshot().cancel_reason == "target_height" and int(controller.snapshot().launched) == 0,
		"A real lower-terrain target within horizontal range must cancel a height-invalid preparation")
	await fresh()
	stand(Vector3(-6, 5, -10))
	spawned = spawn(Vector3(-11, 5, -10))
	controller = spawned.controller
	source = spawned.source
	begin(controller)
	# Equal-height unit fixture isolates the actual closed-wall line test from
	# the separate five-metre terrain-height rejection above; no wall is edited.
	source.position = Vector3(-14, 5, -10)
	check(not game.can_attack_line(source.position, game.hero.position), "The wall-cancel fixture must cross a genuine production closed wall")
	game.simulate(.01)
	check(controller.snapshot().cancel_reason == "line_blocked" and int(controller.snapshot().launched) == 0,
		"Crossing a real castle wall during preparation must cancel a still-in-range equal-height shot")
	await fresh()
	stand(Vector3(90, 0, 90))
	var pad: Dictionary = game.world.tower_pads[0]
	spawned = spawn(pad.position + Vector3(-4, 0, 0))
	controller = spawned.controller
	begin(controller, "tower")
	game.damage_tower(0, 100000.0)
	game.simulate(.01)
	check(controller.snapshot().cancel_reason == "target_dead" and int(controller.snapshot().launched) == 0,
		"Real destruction of the locked target structure must cancel its unlaunched attack")
	for kind in ["tower", "workshop"]:
		await fresh()
		stand(Vector3(90, 0, 90))
		var point: Vector3 = game.world.tower_pads[0].position
		var index := 0
		if kind == "workshop":
			point = Vector3(-7.5, 5, -8)
			check(game.build_structure_at(point, kind), "The same-frame replacement fixture must construct a real workshop")
			index = game.districts.plots.size() - 1
		var old_model: Node3D = game.world.tower_pads[index].turret if kind == "tower" else game.districts.plots[index].model
		var old_token := old_model.get_instance_id()
		spawned = spawn(point + Vector3(-4, 0, 0))
		controller = spawned.controller
		begin(controller, "tower" if kind == "tower" else "district")
		if kind == "tower": game.damage_tower(index, 100000.0)
		else: game.districts.damage(index, 100000.0)
		# No simulate/frame occurs between destruction and reconstruction. The
		# genuine placement/payment paths must create a new model in the old slot.
		var rebuilt: bool = game.build_or_upgrade_tower(index) if kind == "tower" else game.build_structure_at(point, kind)
		var replacement: Node3D = game.world.tower_pads[index].turret if kind == "tower" else game.districts.plots[index].model
		check(rebuilt and is_instance_valid(replacement) and replacement.get_instance_id() != old_token,
			"Real same-frame " + kind + " reconstruction must replace the captured building instance")
		game.simulate(.01)
		check(controller.snapshot().cancel_reason == "target_dead" and int(controller.snapshot().launched) == 0,
			"A rebuilt " + kind + " at the identical point must not revive the dead building's unfinished cast")
	await fresh()
	pad = game.world.tower_pads[0]
	stand(pad.position + Vector3(2, 0, 0))
	await press(KEY_F)
	await press(KEY_K)
	check(int(pad.level) == 2 and game.specializations.branch(pad) == "control",
		"Interrupt fixture must actually pay for a level-two tower and its live control specialization")
	stand(Vector3(-8, 5, 8))
	spawned = spawn(Vector3(-10, 5, 8))
	controller = spawned.controller
	source = spawned.source
	begin(controller)
	var speed := source.speed
	game.specializations.resolve_shot(pad, source, game.enemies, 1.0, game.hero)
	check(game.specializations.movement_multiplier(source) < 1.0, "Interrupt fixture must apply the real tower-control effect")
	game.simulate(.01)
	check(controller.snapshot().cancel_reason == "source_controlled" and int(controller.snapshot().launched) == 0
		and is_equal_approx(source.speed, speed), "Real tower control must cancel preparation without rewriting the enemy's base movement speed")
	game.simulate(.5)
	check(controller.snapshot().phase == "idle" and damage_events.is_empty(), "Live control must also prevent a fresh ranged preparation or melee hit")
	game.simulate(.71)
	check(controller.snapshot().phase == "windup", "Expired actual tower control must let the surviving enemy begin a new complete cast")
	completed.append("cancel")

func frozen_feedback_and_source_release() -> void:
	await fresh()
	var spawned := spawn()
	var source: BattleUnit = spawned.source
	var controller: Node3D = spawned.controller
	begin(controller)
	if not game.combat.reduced_effects: await press(KEY_F2)
	game.simulate(.02)
	var ring := controller.get("_ring") as MeshInstance3D
	var material := ring.material_override as StandardMaterial3D
	check(game.combat.reduced_effects and ring.is_visible_in_tree() and material.albedo_color.a > .5
		and material.emission_energy_multiplier > 0.0, "Actual F2 must reduce glare while retaining an opaque readable world landing warning")
	await capture("reduced-effects-warning")
	await press(KEY_ESCAPE)
	var stopped: Dictionary = controller.snapshot()
	var warning: Array = game.lobber_warning_snapshot().duplicate(true)
	game.simulate(8.0)
	check(game.phase == "paused" and controller.snapshot() == stopped and game.lobber_warning_snapshot() == warning,
		"A real pause must freeze the whole preparation, fixed landing point and warning progress")
	await capture("paused-warning")
	await press(KEY_ESCAPE)
	game.run.grant("投蚀回归 · 免费选卡冻结夹具")
	await press(KEY_V)
	stopped = controller.snapshot()
	game.simulate(8.0)
	check(game.phase == "draft" and controller.snapshot() == stopped and damage_events.is_empty(),
		"A real ability draft must freeze the existing ranged preparation without an invisible hit")
	await capture("draft-frozen")
	await press(KEY_1)
	# A real chosen card reapplies RunBuild armour/shield. Restore this
	# explicitly documented zero-defence fixture before checking raw damage.
	game.hero.armor = 0.0
	game.hero.shield = 0.0
	launch(controller)
	await press(KEY_ESCAPE)
	stopped = controller.snapshot()
	var projectile := controller.get("_projectile") as MeshInstance3D
	var position := projectile.position
	game.simulate(8.0)
	check(controller.snapshot() == stopped and projectile.position == position and damage_events.is_empty(),
		"A real pause during committed flight must freeze trajectory and impact timing")
	await press(KEY_ESCAPE)
	var source_id := source.get_instance_id()
	source.hurt(100000.0, game.hero)
	await process_frame
	check(not is_instance_id_valid(source_id) and is_instance_valid(controller)
		and controller.snapshot().phase == "flight", "A launched projectile must actually outlive a freed original source instance")
	await capture("source-freed-flight")
	land(controller)
	check(damage_events.size() == 1 and is_equal_approx(float(damage_events[0].health), 22.0)
		and int(controller.snapshot().impacts) == 1,
		"The truly orphaned projectile must still land once with its sampled real damage")
	check(damage_events.size() == 1 and int(damage_events[0].source) == -1
		and game.hero_damage_flash_text.contains("投蚀体") and not game.hero.has_meta("delayed_enemy_hit_title"),
		"A source-freed actual hit must identify its real Chinese threat without inventing a live source or leaving temporary metadata")
	game.simulate(.29)
	await process_frame
	check(game.lobbers.is_empty() and damage_events.size() == 1, "An orphaned impact must retire its controller without a second hit")
	completed.append("freeze")

func range_and_defender_priority() -> void:
	await fresh()
	stand(Vector3(-1, 5, -10))
	var spawned := spawn(Vector3(-12.3, 5, -10))
	var controller: Node3D = spawned.controller
	var source: BattleUnit = spawned.source
	source.speed = 0.0
	game.simulate(.1)
	check(controller.snapshot().phase == "idle" and int(controller.snapshot().launched) == 0 and damage_events.is_empty(),
		"A target just outside true11.2-metre reach must not begin a distant ranged or fallback melee attack")
	source.position = Vector3(-12.19, 5, -10)
	begin(controller)
	check(not game.squads.intercept_enemy(source, .01), "A lobber must retain its independent ranged attack path")
	await fresh()
	stand(Vector3(-5, 5, -10))
	spawned = spawn(Vector3(-6, 5, -10))
	controller = spawned.controller
	begin(controller)
	game.simulate(.34)
	check(damage_events.is_empty() and controller.snapshot().phase == "windup",
		"Even at melee distance a thrower must retain its longer cast instead of doing an ordinary .34-second pounce")
	launch(controller)
	land(controller)
	check(damage_events.size() == 1, "A close-range thrower still applies just its one full-flight impact")
	await fresh()
	stand(Vector3(90, 0, 90))
	check(game.build_structure_at(Vector3(7, 5, -8.5), "barracks")
		and game.build_structure_at(Vector3(7.5, 5, -3), "workshop")
		and game.build_structure_at(Vector3(-7, 5, -3.5), "laboratory"), "Defender-priority fixture must build genuine heavy-troop prerequisites")
	check(bool(game.squads.hire("ballista").ok), "Defender-priority fixture must produce a real heavy-crossbow squad")
	var group: Dictionary = game.squads.squads[0]
	var origin := Vector3(-4, 5, -11)
	game.squads.select_all()
	game.squads.command_guard(origin)
	for slot in 3:
		var soldier: BattleUnit = group.members[slot]
		soldier.position = origin + Vector3((slot - 1) * 1.25, 0, 0)
		soldier.attack_timer = 9999.0 if slot != 1 else 0.0
	var ordinary: BattleUnit = game.spawn_creature(true, "basic")
	ordinary.position = origin + Vector3(2.5, 0, 0)
	ordinary.speed = 0.0
	spawned = spawn(origin + Vector3(8, 0, 0))
	source = spawned.source
	source.speed = 0.0
	game.simulate(.001)
	var shooter: BattleUnit = group.members[1]
	check(shooter.attack_queued and shooter.target == source,
		"The actual heavy-crossbow attack path must prioritize an in-range throwing specialist over a closer basic creature")
	await capture("heavy-counter")
	completed.append("range")

func phase_cleanup_and_last_projectile() -> void:
	await fresh()
	var spawned := spawn()
	var controller: Node3D = spawned.controller
	begin(controller)
	launch(controller)
	var controller_id := controller.get_instance_id()
	TransitionFixture.finish_for_fixture(game)
	check(game.phase == "draft" and game.lobbers.is_empty(), "Artificial hostile-flight retirement prepares the genuine dawn draft; it is not natural projectile-clearance proof")
	await process_frame
	check(not is_instance_id_valid(controller_id), "Fixture retirement and the genuine dawn transition must release the old ranged controller instance")
	await press(KEY_1)
	var events := damage_events.size()
	game.simulate(1.0)
	check(game.phase == "day" and damage_events.size() == events,
		"A retired night projectile must not damage the actual next daytime hero")
	await fresh()
	spawned = spawn()
	controller = spawned.controller
	begin(controller)
	launch(controller)
	controller_id = controller.get_instance_id()
	game.end_defeat("投蚀回归 · 真实失败清理")
	check(game.phase == "ended" and game.lobbers.is_empty(), "Actual defeat must clear every pending throw and landing warning")
	await process_frame
	check(not is_instance_id_valid(controller_id), "Actual defeat must release the old projectile controller")
	await fresh(4)
	spawned = spawn()
	controller = spawned.controller
	begin(controller)
	launch(controller)
	game.wave_index = game.WAVES_PER_NIGHT
	game.phase_time = .001
	game.simulate(.002)
	check(game.night_clearance_active and game.final_clearance_active, "The real timer crossing must retain the committed hostile flight for clearance")
	var source: BattleUnit = spawned.source
	source.hurt(100000.0, game.hero)
	await process_frame
	game.simulate(.1)
	check(game.phase == "night" and game.final_clearance_active and game._has_living_night_enemies(),
		"The real last-night clearance must wait for a committed throw after its last living source is actually freed")
	game.simulate(float(controller.snapshot().stage_remaining) + .001)
	check(game.phase == "ended" and game.victory and game.lobbers.is_empty() and damage_events.size() == 1,
		"Only after the real last projectile lands once may final clearance award victory and retire its warning")
	await fresh()
	spawned = spawn()
	controller = spawned.controller
	begin(controller)
	launch(controller)
	controller_id = controller.get_instance_id()
	await close_game()
	check(not is_instance_id_valid(controller_id), "Closing an actual scene during committed flight must release the controller completely")
	completed.append("cleanup")

func run() -> void:
	await saved_plan_and_rewards()
	await hero_timing_and_cooldown()
	await real_dodges()
	await nearest_targets()
	await area_boundaries_and_host_damage()
	await real_slope_warning_and_damage()
	await interrupted_and_cancelled()
	await frozen_feedback_and_source_release()
	await range_and_defender_priority()
	await phase_cleanup_and_last_projectile()
	check(completed == ["plan", "timing", "dodges", "targets", "area", "slope", "cancel", "freeze", "range", "cleanup"],
		"Every full scene regression stage must finish; an aborted coroutine must not be reported as success")
	await close_game()
	# Let the audio server retire the final scene's playback handles before
	# quitting; successful combat assertions do not prove clean teardown.
	await create_timer(.5, true, false, true).timeout
	evidence.checks = checks
	evidence.failures = failures
	var folder := ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("results.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(evidence, "\t")); file.close()
	print("NIGHTFALL_LOBBER_EVIDENCE " + JSON.stringify(evidence))
	print("NIGHTFALL_LOBBER_OK checks=%d" % checks if failures.is_empty()
		else "NIGHTFALL_LOBBER_FAILED checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
