extends SceneTree
## Real playable casts own these lamps; cosmetic reductions never alter combat.
var game: Node3D
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func reset_case() -> void:
	game.skill_lights.clear()
	game.cancel_hero_attack()
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	game.delayed_blasts.clear()
	game.run = RunBuild.new(731)
	game.phase = "day"; game.phase_time = 90.0
	game.hero.position = Vector3(35, 0, 35)
	game.move_goal = game.hero.position; game.hero_path.clear()
	game.hero_keyboard_active = false
	game.hero.moving = false; game.hero.set_locomotion_velocity(Vector3.ZERO)
	game.hero.alive = true; game.hero.hp = game.hero.max_hp
	game.hero.shield = 0.0; game.hero.shield_time = 0.0
	game.hero.attack_timer = 1000.0
	game.cooldowns.fill(0.0); game.mana = 300.0
	game.combat.reduced_effects = false
	game.aim = game.hero.position + Vector3.RIGHT * 10.0

func item_of(kind: String) -> Dictionary:
	for item in game.skill_lights.lights:
		if item.kind == kind: return item
	return {}

func target(offset: Vector3, hp: float = 3000.0) -> BattleUnit:
	var enemy: BattleUnit = game.spawn_creature(false)
	enemy.position = game.hero.position + offset
	enemy.armor = 0.0; enemy.shield = 0.0
	enemy.max_hp = hp; enemy.hp = hp
	enemy.damage = 0.0; enemy.speed = 0.0; enemy.attack_timer = 1000.0
	return enemy

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func check_casts_and_balance() -> void:
	for slot in 5:
		reset_case()
		var inside := target(Vector3.RIGHT * 2.0)
		var outside := target(Vector3.RIGHT * 12.0)
		game.hero.hp = 400.0
		var old_position: Vector3 = game.hero.position
		var expected_damage: float = [110.0, 78.0, 0.0, 260.0, 0.0][slot]
		check(game.cast(slot), "Ready slot %d must cast" % slot)
		var expected_lights := 2 if slot == 2 else 1
		check(game.skill_lights.lights.size() == expected_lights, "Slot %d needs its own actual light" % slot)
		check(is_equal_approx(game.mana, 300.0 - float(game.COSTS[slot])), "Lighting must preserve slot %d mana cost" % slot)
		check(is_equal_approx(game.cooldowns[slot], float(game.COOLDOWNS[slot])), "Lighting must preserve slot %d cooldown" % slot)
		check(is_equal_approx(inside.hp, 3000.0 - expected_damage), "Lighting must preserve slot %d direct damage" % slot)
		check(is_equal_approx(outside.hp, 3000.0), "Out-of-range targets must stay untouched")
		if slot == 1:
			check(is_equal_approx(game.hero.shield, 150.0) and is_equal_approx(game.hero.shield_time, 4.0), "W shield rules must remain intact")
		if slot == 2:
			check(game.hero.position.is_equal_approx(old_position + Vector3.RIGHT * 6.0), "E must retain its legal six-metre movement")
		if slot == 4:
			check(is_equal_approx(game.hero.hp, minf(game.hero.max_hp, 400.0 + game.hero.max_hp * .32)), "X must retain its healing amount")
		var mana_after: float = game.mana
		check(not game.cast(slot), "A cooldown cast must fail")
		check(game.skill_lights.lights.size() == expected_lights and is_equal_approx(game.mana, mana_after), "Rejected cooldown must not make light or spend mana")
		for item in game.skill_lights.lights:
			var light := item.node as OmniLight3D
			check(is_instance_valid(light) and light.is_inside_tree() and light.light_energy > 0.0, "Skill lamp must be a live scene Light3D")
			check(light.light_bake_mode == Light3D.BAKE_DISABLED and light.light_indirect_energy == 0.0, "Skill lighting must stay local and unbaked")
		game.skill_lights.tick(5.0, "day")
		check(game.skill_lights.lights.is_empty(), "Expired slot %d lamps must retire" % slot)
	for phase in ["paused", "draft", "ended"]:
		reset_case(); game.phase = phase
		for slot in 5:
			check(not game.cast(slot), "Phase %s must refuse casts" % phase)
		check(game.skill_lights.lights.is_empty() and game.mana == 300.0 and game.cooldowns == [0.0, 0.0, 0.0, 0.0, 0.0], "Inactive phases must not spend mana, start cooldown or light")
	for slot in 4:
		reset_case(); game.mana = float(game.COSTS[slot]) - 1.0
		var old_mana: float = game.mana
		check(not game.cast(slot), "Insufficient mana must refuse casts")
		check(game.skill_lights.lights.is_empty() and game.mana == old_mana and game.cooldowns[slot] == 0.0, "Insufficient mana must not spend resources or light")
	reset_case()
	check(not game.cast(-1) and not game.cast(5), "Invalid slots must be rejected")
	check(game.skill_lights.lights.is_empty() and game.mana == 300.0, "Invalid slots must not light")
	# A legal-origin dash blocked by the fortress wall has no travelled light.
	game.hero.position = Vector3(7, 0, OutpostLayout.FORT_OUTER + 2.0)
	game.aim = Vector3(7, OutpostLayout.FORT_HEIGHT, OutpostLayout.FORT_INNER - 3.0)
	var direction: Vector3 = (game.aim - game.hero.position).normalized()
	check(not game.can_traverse(game.hero.position, game.hero.position + direction * 6.0), "Blocked-dash fixture must cross the south parapet")
	var blocked_origin: Vector3 = game.hero.position
	game.cast(2)
	check(game.hero.position == blocked_origin and game.skill_lights.lights.is_empty(), "An untravelled dash must not create misleading lamps")
	# A diagonal dash from the raised ramp must resolve to the same safe
	# corridor as ordinary movement instead of parking the hero's mesh in the
	# retaining wall.
	reset_case()
	var ramp_point := Vector3(2.5, 0, OutpostLayout.RAMP_TOP + .6)
	game.hero.position = Vector3(ramp_point.x, game.outpost_height(ramp_point), ramp_point.z)
	game.move_goal = game.hero.position
	var ramp_dash_origin: Vector3 = game.hero.position
	game.aim = game.hero.position + Vector3(.2, 0, .98).normalized() * 10.0
	check(game.cast(2), "A ramp-edge dash must remain usable")
	check(game.can_traverse(ramp_dash_origin, game.hero.position), "A ramp-edge dash must stay on a traversable segment")
	check(game.hero.position.x <= game.hero_ramp_side_limit(game.hero.position.z) + .001, "A ramp-edge dash must keep the hero mesh inside the visual clearance corridor")
	check(game.hero.position.distance_to(ramp_dash_origin) > 5.4, "A ramp-edge dash must preserve almost its full travel distance")
	reset_case(); game.phase = "night"
	for slot in 5:
		check(game.cast(slot), "Night-time slot %d must remain usable" % slot)
	check(game.skill_lights.lights.size() == 6 and game.mana == 105.0, "Five distinct night casts must use all six allowed lamps and only their normal costs")

func check_motion_and_pause() -> void:
	reset_case(); game.cast(0)
	var slash := item_of("slash")
	var slash_start: Vector3 = slash.node.global_position
	game.skill_lights.tick(.10, "day")
	check(slash.node.global_position.x > slash_start.x + 1.0, "Q lamp must travel with the blade")
	check(slash.node.light_energy < float(slash.energy), "Travelling light must decay")
	game.skill_lights.tick(.20, "day")
	check(slash.node.global_position.is_equal_approx(slash.endpoint), "Q travel must reach its defined endpoint before retiring")
	reset_case(); game.cast(2)
	var dash := item_of("dash")
	var dash_start: Vector3 = dash.node.global_position
	game.skill_lights.tick(.10, "day")
	check(dash.node.global_position.distance_to(dash_start) > 1.0, "E lamp must travel between actual endpoints")
	game.skill_lights.tick(.15, "day")
	check(dash.node.global_position.is_equal_approx(dash.endpoint), "E lamp must reach the hero's actual arrival point")
	reset_case(); game.cast(1); game.cast(4)
	var shield := item_of("shield")
	var heal := item_of("heal")
	game.hero.position += Vector3(2, .4, 3)
	game.skill_lights.tick(.1, "day")
	for item in [shield, heal]:
		check(item.node.global_position.is_equal_approx(game.hero.position + (item.offset as Vector3)), "W/X lamps must follow the hero")
	var frozen_position: Vector3 = shield.node.global_position
	var frozen_age: float = shield.time
	var frozen_energy: float = shield.node.light_energy
	game.hero.position += Vector3.RIGHT * 5
	for phase in ["paused", "draft"]:
		game.phase = phase
		game.skill_lights.tick(12.0, phase)
		check(shield.time == frozen_age and shield.node.global_position == frozen_position and shield.node.light_energy == frozen_energy, "Pause and card choice must freeze lifetime, following and decay")
	game.phase = "day"; game.skill_lights.tick(.01, "day")
	check(shield.node.global_position.is_equal_approx(game.hero.position + (shield.offset as Vector3)), "Following resumes after pause")
	game.hero.hurt(300.0, null)
	check(game.hero.shield == 0.0 and game.hero.alive and game.phase == "day", "Damage fixture must break the shield while its owner stays alive")
	game.skill_lights.tick(.01, "day")
	check(shield.node.light_energy < 1.35, "Broken W shield must begin fading immediately")
	game.skill_lights.tick(.5, "day")
	check(item_of("shield").is_empty(), "Broken W shield light must retire quickly")
	game.phase = "ended"; game.skill_lights.tick(0.0, "ended")
	check(game.skill_lights.lights.is_empty(), "End-of-run must clear skill lighting")

func check_budget_and_reduction() -> void:
	reset_case()
	for index in 14:
		game.cooldowns[3] = 0.0; game.mana = 300.0
		game.cast(3)
		var shadow_count := 0
		for item in game.skill_lights.lights:
			if item.node.shadow_enabled: shadow_count += 1
		check(game.skill_lights.lights.size() <= 6 and shadow_count <= 1, "Repeated casts must respect the six-light, one-shadow cap")
	var newest: Dictionary = game.skill_lights.lights.back()
	check(newest.node.shadow_enabled, "The newest R must own the available shadow")
	var full_energy: float = newest.node.light_energy
	await press(KEY_F2)
	game.skill_lights.tick(0.0, "day")
	check(game.combat.reduced_effects and is_equal_approx(newest.node.light_energy, full_energy * .45), "Actual F2 input must reduce current skill light energy to 45 percent")
	game.cooldowns[3] = 0.0; game.mana = 300.0
	var inside := target(Vector3.RIGHT * 2.0)
	game.cast(3)
	check(is_equal_approx(inside.hp, 2740.0) and game.mana == 215.0 and game.cooldowns[3] == 28.0, "Reduced lighting must not reduce R damage or change its cost/cooldown")
	await press(KEY_F2)
	game.skill_lights.tick(0.0, "day")
	check(not game.combat.reduced_effects and is_equal_approx(game.skill_lights.lights.back().node.light_energy, full_energy), "F2 must restore the current onset intensity without creating a full-bright flash")
	var retired_nodes: Array[Node] = []
	for item in game.skill_lights.lights: retired_nodes.append(item.node)
	game.skill_lights.clear()
	for light in retired_nodes:
		check(light.is_queued_for_deletion() and not light.visible and light.light_energy == 0.0, "Retiring lights must disable rendering immediately")
	await process_frame
	for light in retired_nodes:
		check(not is_instance_valid(light), "Retiring lights must actually release their nodes")

func check_smooth_envelopes_and_retirement() -> void:
	reset_case(); game.cast(3)
	var item := item_of("inferno")
	var light := item.node as OmniLight3D
	check(light.light_energy > 0.0 and light.light_energy < .25, "A real R lamp must begin softly instead of flashing at peak intensity")
	var previous := light.light_energy
	var peak := previous
	for index in 90:
		game.skill_lights.tick(1.0 / 120.0, "day")
		if not is_instance_valid(light): break
		var current := light.light_energy
		check(absf(current - previous) < 1.2, "The skill light must change continuously over rendered frames")
		if index > 6: check(current <= previous + .001, "The light tail must fade monotonically without a second flash")
		peak = maxf(peak, current)
		previous = current
	check(peak > 3.8 and peak <= 4.8, "Soft onset must retain useful local illumination within its authored peak")
	reset_case()
	for slot in [1, 4, 2, 0, 3]: game.cast(slot)
	var shield := item_of("shield").node as OmniLight3D
	var short_travel := item_of("dash_start").node as OmniLight3D
	game.skill_lights.tick(.12, "day")
	game.cooldowns[3] = 0.0; game.mana = 300.0; game.cast(3)
	check(game.skill_lights.lights.size() == 6 and item_of("shield").node == shield, "A new effect must respect the six-lamp budget while preserving a live shield")
	check(short_travel.is_queued_for_deletion() and short_travel.light_energy == 0.0 and not short_travel.visible, "The shortest-lived travel light must retire cleanly when the budget is full")

func check_echo() -> void:
	reset_case()
	game.run.owned["echo"] = 1; game.run.recalculate()
	var inside := target(Vector3.RIGHT * 2.0)
	game.cast(3)
	check(game.skill_lights.lights.size() == 1 and game.delayed_blasts.size() == 1, "R must not light the echo before it detonates")
	var original_hp: float = inside.hp
	for phase in ["paused", "draft"]:
		game.phase = phase
		game.simulate(2.0)
		game.skill_lights.tick(2.0, phase)
		check(game.delayed_blasts.size() == 1 and game.delayed_blasts[0].delay == .55 and game.skill_lights.lights.size() == 1 and inside.hp == original_hp, "Paused/draft echo must not spend delay, deal damage or light")
	game.phase = "day"
	game.simulate(.54)
	check(game.delayed_blasts.size() == 1 and game.skill_lights.lights.size() == 1 and inside.hp == original_hp, "Echo must wait its full delay")
	game.simulate(.02)
	check(game.delayed_blasts.is_empty() and game.skill_lights.lights.size() == 2, "Actual delayed blast must create its own lamp when triggered")
	check(is_equal_approx(inside.hp, original_hp - 130.0), "Echo must retain its existing half-strength damage")
	game.skill_lights.tick(1.0, "day")
	check(game.skill_lights.lights.is_empty(), "Both R lamps must decay after the echo")

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false)
	check(game.choose_card(0), "Real opening choice must start the game")
	check(is_instance_valid(game.skill_lights), "The production scene must install its skill lighting manager")
	check_casts_and_balance()
	check_motion_and_pause()
	check_smooth_envelopes_and_retirement()
	await check_budget_and_reduction()
	check_echo()
	await game.prepare_shutdown()
	check(game.skill_lights.lights.is_empty(), "Shutdown must clear all remaining skill lights")
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	if failures.is_empty(): print("NIGHTFALL_SKILL_LIGHTING_OK")
	else: print("NIGHTFALL_SKILL_LIGHTING_FAILED ", failures.size())
	quit(0 if failures.is_empty() else 1)
