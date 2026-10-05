extends SceneTree
## Production-scene verification: all shots, slows and choices use controller hooks.
const Rules = preload("res://scripts/tower_specializations.gd")
var game: Node3D
var pad: Dictionary
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func clear_enemies() -> void:
	game.cancel_hero_attack()
	game.clear_focus()
	for old: BattleUnit in game.enemies:
		if is_instance_valid(old): old.queue_free()
	game.enemies.clear()

func enemy(threat: String, offset: Vector3) -> BattleUnit:
	var unit: BattleUnit = game.spawn_creature(false)
	unit.set_meta("threat", threat)
	unit.position = pad.position + offset
	unit.max_hp = 10000.0
	unit.hp = unit.max_hp
	unit.armor = 0.0
	return unit

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	for _frame in 3: await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	for _frame in 3: await process_frame

func shot(selected: BattleUnit) -> void:
	game.focus_target = selected
	game.focus_time = 5.0
	pad.cooldown = 0.0
	game.update_towers(0.0)

func capture(branch: String) -> void:
	if DisplayServer.get_name() == "headless": return
	game.hero.position = pad.position + Vector3(-1.6, 0, -.8)
	game.move_goal = game.hero.position
	game.camera.size = 31.0
	game.camera.position = pad.position + Vector3(0, 25, 29)
	game.camera_follow = game.camera.position
	game.world.night_mix = 1.0
	game.world.apply_lighting()
	game.notice_time = 0.0
	game.hud.queue_redraw()
	await create_timer(.10).timeout
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png("res://build/tower-branch-%s.png" % branch)
	check(result == OK, "Real rendered branch screenshot must save")
	game.hero.position = pad.position + Vector3(0, 0, -2.0)
	game.move_goal = game.hero.position

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	for _frame in 8: await process_frame
	game.set_process(false)
	check(game.choose_card(0), "Actual opening enters first night")
	clear_enemies()
	await process_frame
	pad = game.world.tower_pads[1]
	for other: Dictionary in game.world.tower_pads:
		other.cooldown = 10000.0 # Isolate one real built tower, preserving other defenses.
	game.hero.position = pad.position + Vector3(0, 0, -2.0)
	game.move_goal = game.hero.position
	game.scrap = 2000
	var before_scrap: int = game.scrap
	check(pad.level == 1 and not game.choose_tower_specialization(Rules.PIERCING), "Level-one tower cannot specialize")
	check(game.scrap == before_scrap, "Rejected choice does not charge")
	check(game.interact() and pad.level == 2, "Existing interaction upgrades level one to two")
	check(game.scrap == before_scrap - game.TOWER_COSTS[1], "Existing upgrade retains its real cost")
	game.scrap = Rules.COST - 1
	check(not game.choose_tower_specialization(Rules.PIERCING) and game.scrap == Rules.COST - 1, "Insufficient funds preserve branch and coins")
	game.scrap = 2000
	game.phase = "paused"
	check(not game.choose_tower_specialization(Rules.PIERCING), "Paused game rejects branch changes")
	game.phase = "draft"
	check(not game.choose_tower_specialization(Rules.PIERCING), "Draft rejects branch changes")
	game.phase = "night"
	check(not game.choose_tower_specialization("invalid"), "Invalid branch is rejected")
	var heavy := enemy("breaker", Vector3(3, 0, 0))
	var ordinary := enemy("stalker", Vector3(4.5, 0, 0))
	heavy.armor = 100.0
	var base_damage: float = 42.0 + float(pad.level) * 17.0 + float(game.relay_count()) * 2.5
	var before_hp: float = heavy.hp
	shot(heavy)
	check(is_equal_approx(before_hp - heavy.hp, base_damage * .5), "Universal tower retains normal armor damage")
	var original_level: int = pad.level
	var original_hp: float = pad.hp
	var original_mode: String = pad.mode
	before_scrap = game.scrap
	await key(KEY_J)
	check(game.specializations.branch(pad) == Rules.PIERCING and game.scrap == before_scrap - Rules.COST, "Real J input selects piercing and pays once")
	check(pad.level == original_level and pad.hp == original_hp and pad.mode == original_mode, "Specialization preserves level, durability and target mode")
	before_scrap = game.scrap
	check(not game.choose_tower_specialization(Rules.CONTROL) and game.scrap == before_scrap, "Piercing and control are mutually exclusive")
	before_hp = heavy.hp
	var ordinary_before: float = ordinary.hp
	shot(heavy)
	check(is_equal_approx(before_hp - heavy.hp, base_damage * 1.65 * 100.0 / 150.0), "Real piercing shot gives heavy bonus and ignores half armor")
	check(ordinary.hp == ordinary_before, "Piercing never adds collateral splash")
	before_hp = ordinary.hp
	shot(ordinary)
	check(is_equal_approx(before_hp - ordinary.hp, base_damage * .75), "Piercing pays its ordinary-target damage tradeoff")
	check(is_equal_approx(float(pad.cooldown), maxf(.38, 1.05 - float(pad.level) * .18)), "Piercing preserves original shot interval")
	check(game.interact() and pad.level == 3, "Branch tower still upgrades to level three")
	before_hp = ordinary.hp
	shot(heavy)
	check(ordinary.hp == before_hp, "Level-three piercing does not inherit universal splash")
	await capture("piercing")
	game.damage_tower(1, float(pad.hp) + 1.0)
	check(pad.level == 0 and game.specializations.branch(pad) == Rules.STANDARD, "Real tower destruction resets the branch")
	check(not game.choose_tower_specialization(Rules.CONTROL), "Destroyed tower cannot specialize")
	check(game.interact() and pad.level == 1, "Destroyed tower rebuilds through existing interaction")
	check(not game.choose_tower_specialization(Rules.CONTROL), "Rebuilt level one still requires upgrading")
	check(game.interact() and pad.level == 2, "Rebuilt tower upgrades before a new branch choice")
	before_scrap = game.scrap
	await key(KEY_K)
	check(game.specializations.branch(pad) == Rules.CONTROL and game.scrap == before_scrap - Rules.COST, "Real K input chooses control on the new tower body")
	clear_enemies()
	await process_frame
	var selected := enemy("stalker", Vector3(3, 0, 0))
	var close: Array[BattleUnit] = []
	for offset in [.6, 1.2, 1.8, 2.4]:
		close.append(enemy("breaker" if offset == .6 else "runner", Vector3(3 + offset, 0, 0)))
	var overflow := enemy("runner", Vector3(6.1, 0, 0))
	var far := enemy("stalker", Vector3(6.3, 0, 0))
	base_damage = 42.0 + float(pad.level) * 17.0 + float(game.relay_count()) * 2.5
	before_hp = selected.hp
	shot(selected)
	check(is_equal_approx(before_hp - selected.hp, base_damage * .55), "Actual control primary damage is reduced")
	for unit: BattleUnit in close:
		check(is_equal_approx(unit.max_hp - unit.hp, base_damage * .22), "Actual control hits nearby enemies with reduced splash")
		check(is_equal_approx(game.specializations.movement_multiplier(unit), .85 if unit == close[0] else .7), "Control differentiates heavy and ordinary slow")
	check(overflow.hp == overflow.max_hp and far.hp == far.max_hp, "Control target cap and radius exclude excess enemies")
	check(game.specializations.movement_multiplier(overflow) == 1.0, "Excluded enemy has no hidden slow")
	var control_interval: float = maxf(.38, 1.05 - float(pad.level) * .18) * 1.25
	check(is_equal_approx(float(pad.cooldown), control_interval), "Control pays the 25 percent longer interval")
	before_hp = selected.hp
	game.update_towers(control_interval * .5)
	check(selected.hp == before_hp, "Real shot cooldown prevents early re-fire")
	game.update_towers(control_interval * .5 + .0001)
	check(selected.hp < before_hp, "Real shot fires when its slower cooldown expires")
	# Refreshes stay one layer and do not rewrite the unit's base speed.
	var walker: BattleUnit = close[1]
	var speed_before: float = walker.speed
	for _shot in 5: shot(selected)
	check(is_equal_approx(game.specializations.movement_multiplier(walker), .7), "Repeated hits do not stack slows")
	game.hero.position = pad.position + Vector3(0, 0, -2.0)
	walker.position = Vector3(0, 0, 32)
	walker.set_meta("gate_lane", 0.0)
	walker.attack_queued = false
	var position_before := walker.position
	game.update_creature(walker, .5)
	check(is_equal_approx(position_before.distance_to(walker.position), speed_before * .5 * .7), "Actual night enemy navigation uses the reduced speed")
	check(walker.speed == speed_before, "Navigation never rewrites base movement speed")
	game.phase = "paused"
	game.simulate(20.0)
	check(is_equal_approx(game.specializations.movement_multiplier(walker), .7), "Pause freezes the actual control duration")
	game.phase = "draft"
	game.simulate(20.0)
	check(is_equal_approx(game.specializations.movement_multiplier(walker), .7), "Draft freezes the actual control duration")
	game.phase = "night"
	# Keep real simulation quiet while allowing its specialization clock to advance.
	game.spawn_timer = 10000.0
	game.pulse_timer = 10000.0
	game.phase_time = 100.0
	game.hero.attack_timer = 10000.0
	game.move_goal = game.hero.position
	for other: Dictionary in game.world.tower_pads: other.cooldown = 10000.0
	game.simulate(Rules.SLOW_DURATION + .02)
	check(game.specializations.movement_multiplier(walker) == 1.0, "Real active simulation expires slow")
	check(walker.speed == speed_before, "Expiration preserves original speed")
	walker.position = selected.position + Vector3(1, 0, 0)
	shot(selected)
	check(game.specializations.movement_multiplier(walker) < 1.0, "Enemy receives a new real control hit")
	var chain_before: int = game.kill_chain
	walker.hurt(100000.0, game.hero)
	check(game.specializations.movement_multiplier(walker) == 1.0, "Death immediately forgets old control effects")
	check(game.kill_chain == chain_before, "Tower and generic test damage do not impersonate basic-attack kill streaks")
	await capture("control")
	# Phase transitions and failure clear active effects through production hooks.
	shot(selected)
	game.finish_night()
	check(game.specializations.movement_multiplier(selected) == 1.0, "Dawn transition clears effects")
	while game.phase == "draft": game.choose_card(0)
	game.start_night()
	clear_enemies()
	await process_frame
	selected = enemy("stalker", Vector3(3, 0, 0))
	shot(selected)
	game.start_night()
	check(game.specializations.movement_multiplier(selected) == 1.0, "New night clears effects before replacing enemies")
	clear_enemies()
	await process_frame
	selected = enemy("stalker", Vector3(3, 0, 0))
	shot(selected)
	game.end_defeat("验证结束")
	check(game.specializations.movement_multiplier(selected) == 1.0, "Failure clears effects immediately")
	print("NIGHTFALL_TOWER_BRANCHES_OK checks=%d" % checks if failures == 0 else "NIGHTFALL_TOWER_BRANCHES_FAILED failures=%d" % failures)
	await game.prepare_shutdown()
	game.queue_free()
	for _frame in 12: await process_frame
	await create_timer(.5).timeout
	quit(failures)
