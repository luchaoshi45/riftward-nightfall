extends SceneTree
## Focused production/combat regression for the armory-locked flamethrower squad.
## The fixture uses the real Nightfall scene and roster; it does not grant
## combat rewards or alter the user's project configuration.

const Catalog := preload("res://scripts/outpost_catalog.gd")
const RunSession := preload("res://scripts/run_session.gd")
const SCENE := "res://scenes/nightfall.tscn"
const SEED := 20261007

var game: Node3D
var checks := 0
var failures: Array[String] = []

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
	if failures.size() <= 20: push_error(message)

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func members(kind: String = "") -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for squad: Dictionary in game.squads.squads:
		if not kind.is_empty() and String(squad.kind) != kind: continue
		for soldier: BattleUnit in squad.members:
			if is_instance_valid(soldier) and soldier.alive: result.append(soldier)
	return result

func advance_module(source: BattleUnit, seconds: float) -> void:
	var remaining := seconds
	while remaining > .00001:
		var step := minf(.05, remaining)
		source.tick(step)
		game.squads.flamethrower.advance_unit(source, step)
		remaining -= step

func close_game() -> void:
	if not is_instance_valid(game): return
	if game.has_method("prepare_shutdown"): await game.prepare_shutdown()
	if current_scene == game: current_scene = null
	game.queue_free()
	game = null
	for _frame in 4: await process_frame

func run() -> void:
	check(Catalog.TROOP_IDS.has("flamer"), "The catalog must expose the flamethrower troop id")
	var definition := Catalog.troop("flamer")
	check(String(definition.title) == "喷火队" and int(definition.cost) == 125
		and is_equal_approx(float(definition.time), 11.0)
		and String(definition.requires[0]) == "armory",
		"The flamethrower must cost 125, train for 11 seconds and require a live armory")
	check(is_equal_approx(float(Catalog.troop("flamer").hp), 150.0), "The flamethrower must use its 150 HP definition")
	check(Catalog.TROOP_IDS.size() == 10 and ceili(Catalog.TROOP_IDS.size() / 3.0) == 4,
		"The appended control troop must preserve three choices per page and the flamethrower's third page")

	check(RunSession.queue_request(self, SEED, "siege"), "The real scene must accept the fixed flamethrower seed")
	game = load(SCENE).instantiate()
	root.add_child(game)
	current_scene = game
	for _frame in 5: await process_frame
	await press(KEY_1)
	check(game.phase == "night", "The production scene must enter an active night before spawning the fixture")
	game.set_process(false)
	game.world.set_process(false)
	game.scrap = 1000
	for enemy: BattleUnit in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()

	var locked: Dictionary = game.squads.training_eligibility("flamer")
	check(not bool(locked.available) and String(locked.reason).contains("军械厂"),
		"A flamethrower order must be refused until a live armory exists")
	check(not bool(game.squads.enqueue("flamer").ok), "The production queue must reject the armory-locked troop without a barracks")

	var squad_id: int = game.squads._create_squad("flamer", Vector3(0, 5, 3.1))
	var flamers := members("flamer")
	check(squad_id >= 0 and flamers.size() == 3, "A real flamethrower squad must spawn three members")
	var roster_state: Dictionary = game.squads.flamethrower_snapshot()
	check(int(roster_state.get("alive", 0)) == 3, "Every spawned flamethrower must register with the live roster")
	if flamers.is_empty():
		await close_game()
		print("NIGHTFALL_FLAMETHROWER_FAILED checks=%d failures=%d" % [checks, failures.size()])
		quit(1)
		return

	var source: BattleUnit = flamers[0]
	var enemy: BattleUnit = game.spawn_creature(true, "basic")
	enemy.position = source.position + Vector3(4.0, 0, 0)
	enemy.position.y = game.outpost_height(enemy.position)
	for other: BattleUnit in game.enemies:
		if other != enemy and is_instance_valid(other): other.queue_free()
	game.enemies.clear()
	game.enemies.append(enemy)
	var hp_before := enemy.hp
	check(game.squads.flamethrower.legal_target(source, enemy), "A target inside range and line of sight must be legal")
	check(game.squads.flamethrower.begin(source, enemy), "A legal target must start the real flamethrower windup")
	check(game.squads.flamethrower.casting(source), "The windup must be visible through the module state")
	advance_module(source, .7)
	check(enemy.hp < hp_before and int(game.squads.flamethrower_snapshot().get("hits", 0)) == 1,
		"A completed windup must apply one real armored BattleUnit hit")

	# A new order and a phase transition both cancel a pending cone before impact.
	source.attack_timer = 0.0
	check(game.squads.flamethrower.begin(source, enemy), "The same live source must be able to start a second windup")
	game.squads._set_squad_order(game.squads.squads[squad_id], "move")
	check(not game.squads.flamethrower.casting(source), "A manual order must cancel the pending cone")
	game.squads.on_day()
	check(not game.squads.flamethrower.casting(source), "Day transition must leave no pending cone cast")

	# Defeated members are removed from the exact registered roster slot.
	source.hurt(source.max_hp + 999.0, enemy)
	await process_frame
	check(int(game.squads.flamethrower_snapshot().get("alive", 0)) == 2,
		"A defeated flamethrower must unregister without leaving an orphan module state")

	game.hud.toggle_details("army")
	game.hud.troop_page = 2
	var page_kinds: Array[String] = game.hud.visible_training_kinds()
	check(page_kinds.size() == 3 and page_kinds.has("flamer"), "The third army page must expose the flamethrower button")
	check(game.hud.font.get_string_size("喷火队 · 射程2.5–6.5米 / 22伤 · 扇形32° · 最多4目标", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= 496,
		"The Chinese flamethrower description must fit the compact army drawer")

	await close_game()
	print("NIGHTFALL_FLAMETHROWER_FAILED checks=%d failures=%d" % [checks, failures.size()] if not failures.is_empty()
		else "NIGHTFALL_FLAMETHROWER_OK checks=%d" % checks)
	quit(0 if failures.is_empty() else 1)
