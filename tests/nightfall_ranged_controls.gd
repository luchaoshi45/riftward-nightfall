extends SceneTree
## Production controls for ranged squads: real I input, targeting, mixed formations and paid recovery.

var game: Node3D
var failures: Array[String] = []

func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func press(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.echo = false
	game._unhandled_input(event)

func clear_enemies() -> void:
	for creature in game.enemies:
		if is_instance_valid(creature): creature.queue_free()
	game.enemies.clear()

func at_gate() -> void:
	game.hero.position = Vector3(0, game.outpost_height(Vector3(0, 0, 3.1)), 3.1)

func disable_external_damage() -> void:
	game.cancel_hero_attack()
	game.hero.attack_timer = 999.0
	game.hero.attack_range = 0.0
	game.run.stats.range = -100.0
	game.hero.attack_queued = false
	game.hero.target = null
	game.delayed_blasts.clear()
	game.pulse_timer = 999.0
	for pad: Dictionary in game.world.tower_pads:
		pad.level = 0

func reset_squads() -> void:
	clear_enemies()
	game.squads.clear()
	game.squads.setup(game, true)
	game.squads.set_health_multiplier(game.districts.squad_health_multiplier())
	game.scrap = 500
	game.phase = "night"
	at_gate()
	game.squads.on_night()

func place(unit: BattleUnit, point: Vector3) -> void:
	unit.position = point
	unit.position.y = game.outpost_height(unit.position)
	unit.speed = 0.0

func make_target(archer: BattleUnit, offset: Vector3, threat: String = "stalker", hp: float = 1000.0) -> BattleUnit:
	var target: BattleUnit = game.spawn_creature(true, threat)
	place(target, archer.position + offset)
	target.max_hp = hp
	target.hp = hp
	target.speed = 0.0
	target.attack_timer = 999.0
	return target

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	check(game.choose_card(0) and game.phase == "night", "Opening card must enter the production night")
	clear_enemies()
	disable_external_damage()

	game.phase = "day"
	game.scrap = 500
	game.hero.position = Vector3(-5.4, 5, 1)
	check(game.build_district("barracks"), "A real freely positioned barracks must begin construction")
	game.aim = Vector3(-5.4, 5, -4)
	check(game.construction.confirm(), "Confirming a valid location must construct the production barracks")
	var plot: Dictionary = game.districts.plots[0]
	at_gate()
	game.scrap = 500
	press(KEY_I)
	check(game.squads.snapshot().count == 0 and game.scrap == 420, "I must debit eighty into a timed training queue")
	game.squads.advance(8.0)
	check(game.squads.snapshot().count == 1, "Eight seconds of ranged training must produce three archers")
	check(String(game.squads.snapshot().squads[0].kind) == "ranged", "I must create a ranged squad in the real manager")
	check(String(game.squads.snapshot().squads[0].order) == "recall", "A squad hired during daytime must begin recalled")
	var archer: BattleUnit = game.squads.squads[0].members[1]
	check(is_equal_approx(archer.max_hp, 132.0), "Barracks health must apply to newly hired ranged members")
	check(game.notice.contains("弩手"), "I input must provide a visible ranged arrival notice")

	game.phase = "night"
	game.squads.on_night()
	press(KEY_U)
	game.squads.advance(6.0)
	check(game.squads.snapshot().count == 2 and game.scrap == 350, "U plus I must allow a mixed shield/ranged formation")
	check(String(game.squads.snapshot().squads[1].kind) == "shield", "U must preserve the shield squad kind beside ranged")
	var before_reject: int = game.scrap
	press(KEY_I)
	check(game.squads.snapshot().count == 2 and game.scrap == before_reject - 80, "A third ranged formation must queue without a fixed cap")
	check(game.squads.cancel_training(int(plot.get("index", 0))).ok and game.scrap == before_reject, "Cancelled ranged escrow must refund exactly eighty")
	game.squads.set_order("recall", 1)
	for member: BattleUnit in game.squads.squads[0].members:
		member.attack_timer = 999.0
	for step in 65: game.simulate(.1)
	for member: BattleUnit in game.squads.squads[0].members:
		check(game.outpost_walkable(member.position), "Ranged members must use traversable production stations")
		check(is_equal_approx(member.position.y, game.outpost_height(member.position)), "Ranged members must follow raised terrain")

	# A special enemy farther away must beat a nearby ordinary enemy, proving real target priority.
	for member: BattleUnit in game.squads.squads[0].members:
		member.attack_timer = 0.0 if member == archer else 999.0
	var ordinary := make_target(archer, Vector3(0, 0, 2.0), "stalker", 10000.0)
	var breaker := make_target(archer, Vector3(0, 0, 5.5), "breaker", 10000.0)
	archer.attack_timer = 0.0
	game.squads.advance(.01)
	check(archer.target == breaker, "Ranged targeting must prioritize a reachable breaker over a nearer ordinary enemy")
	check(ordinary.hp == 10000.0, "Priority selection must leave the nearer filler untouched")
	game.squads.advance(.27)
	check(breaker.hp < 10000.0 and not game.squads.shots.is_empty(), "Production simulate must commit ranged damage and create its beam")
	var kill_chain_before: int = game.kill_chain
	var scrap_before: int = game.scrap

	game.phase = "paused"
	var paused_position := archer.position
	var paused_windup := archer.attack_windup
	var paused_beam: float = float(game.squads.shots[0].time)
	game.simulate(10.0)
	check(archer.position == paused_position and archer.attack_windup == paused_windup, "Paused production must freeze ranged movement and windup")
	check(game.squads.shots[0].time == paused_beam and breaker.hp < 10000.0, "Paused production must freeze beam lifetime and target HP")
	game.phase = "night"
	game.simulate(.20)
	check(game.squads.shots.is_empty(), "Resumed production must retire completed ranged beams")
	check(game.kill_chain == kill_chain_before, "Ranged squad damage must never advance the hero kill chain")

	clear_enemies()
	await process_frame
	# Out-of-range targets must not queue, and leaving range during windup must cancel the shot.
	var outside := make_target(archer, Vector3(0, 0, 9.2), "stalker")
	for member: BattleUnit in game.squads.squads[0].members: member.attack_timer = 999.0
	archer.attack_timer = 0.0
	game.squads.advance(.01)
	check(archer.target == null and not archer.attack_queued, "Targets outside 8.6 meters must not queue a ranged attack")
	place(outside, archer.position + Vector3(0, 0, 7.0))
	game.squads.advance(.01)
	check(archer.target == outside and archer.attack_queued, "An in-range target must enter ranged windup")
	var outside_hp := outside.hp
	place(outside, archer.position + Vector3(0, 0, 10.0))
	game.squads.advance(.10)
	check(archer.target == null and not archer.attack_queued and outside.hp == outside_hp, "Leaving range during windup must cancel without damage")

	clear_enemies()
	await process_frame
	var dying := make_target(archer, Vector3(0, 0, 7.0), "stalker")
	archer.attack_timer = 0.0
	game.squads.advance(.01)
	check(archer.target == dying, "A live in-range target must be queued before death cancellation")
	dying.hurt(10000.0, archer)
	await process_frame
	game.squads.advance(.10)
	check(archer.target == null and not archer.attack_queued, "A dead target must cancel its ranged windup")
	scrap_before = game.scrap

	var victim := make_target(archer, Vector3(0, 0, 7.0), "breaker", 1.0)
	archer.attack_timer = 0.0
	var kills_before: int = game.kills
	game.simulate(.01)
	game.simulate(.27)
	check(game.kills == kills_before + 1, "A ranged kill must use the real production defeat callback")
	check(game.scrap == scrap_before + 8, "Ranged kill must receive exactly the normal eight scrap night reward")
	check(game.kill_chain == kill_chain_before, "Ranged kill rewards must still exclude hero chain bonuses")
	await process_frame
	check(not is_instance_valid(victim), "Production ranged kill must free the enemy")

	# The ranged replacement price is 26 per casualty and only L during daytime may pay it.
	archer.hurt(10000.0, null)
	await process_frame
	game.phase = "day"
	game.squads.on_day()
	var refill_cost: int = game.squads.refill_cost()
	check(refill_cost == 26, "A single ranged casualty must announce the exact 26 scrap replacement cost")
	game.scrap = 25
	var failed_scrap: int = game.scrap
	press(KEY_L)
	check(game.scrap == failed_scrap and game.squads.snapshot().alive == 5, "Unaffordable daytime ranged refill must not spend or resurrect")
	game.scrap = 200
	press(KEY_L)
	check(game.scrap == 174 and game.squads.snapshot().alive == 6, "Affordable L must replace the ranged casualty and charge exactly 26")
	game.phase = "night"
	var night_scrap: int = game.scrap
	press(KEY_L)
	check(game.scrap == night_scrap, "Nighttime L must reject ranged refill")

	# Reset the real manager to prove all three supported formations remain selectable.
	reset_squads()
	press(KEY_U); press(KEY_U); game.squads.advance(12.0)
	check(game.squads.snapshot().count == 2 and game.scrap == 360 and game.squads.squads.all(func(row: Dictionary): return String(row.kind) == "shield"), "U plus U must support a double-shield formation")
	reset_squads()
	press(KEY_U); press(KEY_I); game.squads.advance(14.0)
	check(game.squads.snapshot().count == 2 and game.scrap == 350 and String(game.squads.squads[0].kind) == "shield" and String(game.squads.squads[1].kind) == "ranged", "U plus I must support a shield/ranged formation")
	reset_squads()
	press(KEY_I); press(KEY_I); game.squads.advance(16.0)
	check(game.squads.snapshot().count == 2 and game.scrap == 340 and game.squads.squads.all(func(row: Dictionary): return String(row.kind) == "ranged"), "I plus I must support a double-ranged formation")

	if DisplayServer.get_name() != "headless":
		game.camera.position = game.hero.position + Vector3(0, 25, 29)
		game.camera.look_at(game.hero.position)
		game.world.night_mix = 1.0
		game.world.set_night(true)
		game.world.apply_lighting()
		game.hud.queue_redraw()
		await create_timer(.4).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build")
		check(root.get_texture().get_image().save_png("res://build/nightfall-ranged-controls.png") == OK, "Ranged HUD/night scene must render")

	game.squads.clear()
	clear_enemies()
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_RANGED_CONTROLS_", "OK" if failures.is_empty() else "FAILED")
	quit(0 if failures.is_empty() else 1)
