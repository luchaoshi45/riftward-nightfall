extends SceneTree
## Production controls for the shield squad: real inputs, stationing, interception and paid recovery.

var game: Node3D
var failures: Array[String] = []

func _initialize() -> void:
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

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	check(game.choose_card(0) and game.phase == "night", "Opening card must enter the production night")
	clear_enemies()

	game.phase = "day"
	game.scrap = 400
	var plot: Dictionary = game.districts.plots[0]
	game.hero.position = plot.position
	check(game.build_district("barracks"), "A real nearby barracks must be constructible before hiring")
	check(is_equal_approx(game.squads.health_multiplier, 1.2), "Barracks must provide the production squad health multiplier")
	game.hero.position = Vector3(0, game.outpost_height(Vector3(0, 0, 3.1)), 3.1)
	game.scrap = 300
	game.phase = "night"

	press(KEY_U)
	check(game.squads.snapshot().count == 1 and game.scrap == 230, "U must hire one shield squad for exactly seventy scrap")
	var first: BattleUnit = game.squads.squads[0].members[0]
	check(is_equal_approx(first.max_hp, 240.0), "Barracks health must apply to newly hired shield members")
	press(KEY_U)
	check(game.squads.snapshot().count == 2 and game.scrap == 160, "A second U hire must allow two squads and charge once")
	var before_scrap: int = game.scrap
	press(KEY_U)
	check(game.squads.snapshot().count == 2 and game.scrap == before_scrap, "A third squad must be rejected without spending")

	press(KEY_O)
	check(game.squads.snapshot().squads.all(func(row: Dictionary): return String(row.order) == "recall"), "O must recall all active squads")
	press(KEY_O)
	check(game.squads.snapshot().squads.all(func(row: Dictionary): return String(row.order) == "hold"), "A second O must return all squads to gate duty")

	for step in 65: game.squads.advance(.1)
	for squad in game.squads.squads:
		for member: BattleUnit in squad.members:
			if not is_instance_valid(member): continue
			check(game.outpost_walkable(member.position), "Shield members must use traversable production stations")
			check(is_equal_approx(member.position.y, game.outpost_height(member.position)), "Shield members must follow the actual raised terrain")

	var defender: BattleUnit = game.squads.squads[0].members[1]
	var attacker: BattleUnit = game.spawn_creature(true)
	attacker.set_meta("threat", "stalker")
	attacker.position = defender.position + Vector3(0, 0, 1.0)
	attacker.position.y = game.outpost_height(attacker.position)
	attacker.damage = 30.0
	attacker.attack_timer = 0.0
	attacker.speed = 0.0
	var hero_hp: float = game.hero.hp
	var beacon_hp: float = game.beacon_hp
	var defender_hp: float = defender.hp
	attacker.tick(.01)
	check(game.squads.intercept_enemy(attacker, .01), "A real night attacker must be intercepted by a holding shield")
	attacker.tick(.35)
	game.squads.intercept_enemy(attacker, .35)
	check(defender.hp < defender_hp and game.hero.hp == hero_hp and game.beacon_hp == beacon_hp, "Interception damage must reach the shield member instead of hero or beacon")

	game.phase = "paused"
	var paused_hp: float = defender.hp
	var paused_attack: float = attacker.attack_windup
	game.squads.advance(10.0)
	game.squads.intercept_enemy(attacker, 10.0)
	check(defender.hp == paused_hp and attacker.attack_windup == paused_attack, "Paused squad actions and enemy interception must freeze")
	game.phase = "night"

	defender.hurt(10000.0, attacker)
	var alive_after_death: int = game.squads.snapshot().alive
	check(alive_after_death == 5, "A defeated defender must immediately leave the live count")
	await process_frame
	check(not is_instance_valid(defender) and game.squads.snapshot().alive == 5, "Defeated defender must be freed while the paid slot remains empty")
	game.phase = "day"
	game.squads.on_day()
	var refill_cost: int = game.squads.refill_cost()
	check(refill_cost > 0, "Daytime refill must expose a real replacement cost")
	game.scrap = refill_cost - 1
	var failed_scrap: int = game.scrap
	press(KEY_L)
	check(game.scrap == failed_scrap and game.squads.snapshot().alive == 5, "Unaffordable L refill must not spend or resurrect")
	game.scrap = 200
	press(KEY_L)
	check(game.squads.snapshot().alive == 6 and game.scrap == 200 - refill_cost, "Affordable L refill must replace the casualty and charge once")

	game.hero.position = Vector3(20, game.outpost_height(Vector3(20, 0, 20)), 20)
	var out_of_range_scrap: int = game.scrap
	press(KEY_U)
	check(game.scrap == out_of_range_scrap and game.squads.snapshot().count == 2, "U outside the inner outpost must reject without spending")

	if DisplayServer.get_name() != "headless":
		game.hero.position = Vector3(0, game.outpost_height(Vector3(0, 0, 3.1)), 3.1)
		game.camera.position = game.hero.position + Vector3(0, 25, 29)
		game.camera.look_at(game.hero.position)
		game.world.night_mix = 1.0
		game.world.set_night(true)
		game.world.apply_lighting()
		game.hud.queue_redraw()
		await create_timer(.4).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build")
		check(root.get_texture().get_image().save_png("res://build/nightfall-squad-controls.png") == OK, "Real squad HUD/night scene must render")

	game.squads.clear()
	clear_enemies()
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	print("NIGHTFALL_SQUAD_CONTROLS_", "OK" if failures.is_empty() else "FAILED")
	quit(0 if failures.is_empty() else 1)
