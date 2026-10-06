extends SceneTree
## Controlled production-scene regression; its funded rebuilds do not establish
## full-run balance. Movement, targeting, damage and input use the real code.
const Layout = preload("res://scripts/outpost_layout.gd")

var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)
	return condition

func frames(count: int = 3) -> void:
	for _frame in count: await process_frame

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func place_hero(point: Vector3, target: Vector3) -> void:
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.move_goal = point
	game.hero_path.clear()
	game.aim = target
	game.aim_sample_pending = false

func remove_enemies() -> void:
	for creature: BattleUnit in game.enemies:
		if is_instance_valid(creature): creature.queue_free()
	game.enemies.clear()

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://build")
	check(DirAccess.make_dir_recursive_absolute(folder) == OK,
		"Create the local build-only screenshot directory")
	check(root.get_texture().get_image().save_png(folder.path_join(name + ".png")) == OK,
		"Save the actual tower feedback screenshot under build")

func finish() -> void:
	if is_instance_valid(game):
		await game.prepare_shutdown()
		game.queue_free()
		await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_SAPPERS_", "OK" if failures.is_empty() else "FAILED",
		" checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	if not check(game.choose_card(0), "Choose the actual opening core and enter the game"):
		await finish()
		return
	remove_enemies()
	await process_frame
	if not check(game.world.tower_pads.size() == 2 and game.tower_count() == 2,
		"The real opening roster contains only live tower indices 0 and 1"):
		await finish()
		return
	var pad: Dictionary = game.world.tower_pads[1]
	var tower_point: Vector3 = pad.position
	game.damage_tower(1, 10000.0)
	check(int(pad.level) == 0 and float(pad.hp) == 0.0 and game.tower_count() == 1,
		"Destroying tower 1 preserves exactly the other live opening tower")
	check(game.outpost_walkable(tower_point), "The destroyed footing releases its real movement block")
	game.scrap = 150
	place_hero(tower_point + Vector3(.5, 0, .5), tower_point)
	var blocked_balance: int = game.scrap
	check(not game.interact() and int(pad.level) == 0 and game.scrap == blocked_balance,
		"F rebuilding on the living hero's occupied cells is rejected without payment")
	place_hero(tower_point + Vector3(0, 0, -2.2), tower_point)
	if not check(game.nearest_tower_pad() == 1 and bool(game.construction.validity(tower_point, 1, "tower").valid),
		"The hero is outside the footprint, within real F range, and targets a legal footing"):
		await finish()
		return
	await press(KEY_F)
	if not check(int(pad.level) == 1 and float(pad.hp) == 280.0 and game.tower_count() == 2
		and game.scrap == blocked_balance - game.districts.tower_cost(game.TOWER_COSTS[0]),
		"Real F reconstructs tower 1 once and pays its actual construction price"):
		await finish()
		return
	check(not game.outpost_walkable(tower_point), "Reconstruction restores the actual occupied movement block")

	var approacher: BattleUnit = game.spawn_creature(true, "sapper")
	approacher.position = Vector3(tower_point.x, 0, 31)
	approacher.position.y = game.outpost_height(approacher.position)
	var initial_position := approacher.position
	var initial_hp: float = pad.hp
	var travelled := 0.0
	var gate_crossings := 0
	for _step in 700:
		var previous := approacher.position
		approacher.tick(.1)
		game.update_creature(approacher, .1)
		check(game.can_traverse(previous, approacher.position),
			"A real sapper movement segment cannot cross castle walls or live building cells")
		check(is_equal_approx(approacher.position.y, game.outpost_height(approacher.position)),
			"The real sapper stays on the actual ramp and castle surface")
		travelled += previous.distance_to(approacher.position)
		if previous.z >= Layout.WALL_CENTER and approacher.position.z < Layout.WALL_CENTER:
			var crossing := previous.lerp(approacher.position,
				(previous.z - Layout.WALL_CENTER) / (previous.z - approacher.position.z))
			gate_crossings += 1
			check(absf(crossing.x) < Layout.GATE_HALF,
				"The actual south-wall crossing occurs inside the sole gate")
		if approacher.attack_queued: break
	check(travelled > 10.0 and initial_position.distance_to(approacher.position) > 10.0
		and gate_crossings == 1 and approacher.attack_queued and approacher.attack_target_pad == 1,
		"The sapper travels from outside, passes the sole south gate once, and prepares a real tower attack")
	check(float(pad.hp) == initial_hp, "Travel and a queued windup cannot instantly damage the tower")
	game.enemies.erase(approacher)
	approacher.queue_free()
	await process_frame

	var sapper: BattleUnit = game.spawn_creature(true, "sapper")
	var surface: Vector3 = game.building_approach_position(tower_point + Vector3(4, 0, 0), tower_point, "tower")
	if not check(surface.is_finite() and game.outpost_walkable(surface),
		"The live tower has a real accessible attack surface"):
		await finish()
		return
	sapper.position = surface
	sapper.attack_timer = 0.0
	place_hero(surface + Vector3(.3, 0, 0), tower_point)
	var selected: Dictionary = game.choose_enemy_target(sapper)
	check(sapper.get_meta("threat", "") == "sapper" and String(selected.kind) == "tower"
		and int(selected.index) == 1 and sapper.position.distance_to(game.hero.position) < sapper.position.distance_to(tower_point),
		"A formally spawned sapper prefers a live tower even over a nearer living hero")
	var old_hero_hp: float = game.hero.hp
	var old_beacon_hp: float = game.beacon_hp
	game.update_creature(sapper, .01)
	check(sapper.attack_queued and sapper.attack_target_pad == 1 and sapper.attack_windup > 0.0
		and float(pad.hp) == initial_hp, "The real tower attack begins a positive windup without instant damage")
	sapper.tick(.2)
	game.update_creature(sapper, .2)
	check(sapper.attack_queued and sapper.attack_windup > 0.0 and float(pad.hp) == initial_hp,
		"A partially elapsed real windup preserves tower HP")
	sapper.tick(.15)
	game.update_creature(sapper, .15)
	check(is_equal_approx(float(pad.hp), initial_hp - sapper.damage) and int(pad.level) == 1
		and not sapper.attack_queued and sapper.attack_timer > 0.0
		and game.hero.hp == old_hero_hp and game.beacon_hp == old_beacon_hp,
		"The elapsed real windup damages only its tower once and starts the actual cooldown")
	remove_enemies()
	await process_frame
	place_hero(tower_point + Vector3(0, 0, -2.2), tower_point)
	game.damage_tower(1, 130.0)
	check(is_instance_valid(pad.damage_ring) and pad.damage_ring.visible,
		"A genuinely damaged living tower displays its low-durability warning ring")
	await capture("nightfall-sappers-damage")
	var damaged_hp: float = pad.hp
	var old_scrap: int = game.scrap
	await press(KEY_H)
	check(is_equal_approx(float(pad.hp), minf(float(pad.max_hp), damaged_hp + 100.0))
		and game.scrap == old_scrap - 20 and not pad.damage_ring.visible,
		"Actual H repairs up to 100, pays exactly 20 parts, and clears the recovered warning")
	await capture("nightfall-sappers-repair")
	game.damage_tower(1, 50.0)
	game.scrap = 0
	var insufficient_hp: float = pad.hp
	check(not game.repair_tower() and float(pad.hp) == insufficient_hp and game.scrap == 0,
		"An unfunded repair neither changes tower HP nor creates a second resource balance")
	game.damage_tower(0, 10000.0)
	check(game.tower_count() == 1 and int(pad.level) == 1,
		"Destroying tower 0 leaves tower 1 as the only genuinely live tower")
	game.damage_tower(1, 10000.0)
	check(int(pad.level) == 0 and float(pad.hp) == 0.0 and game.tower_count() == 0,
		"Destroying the last genuinely live tower leaves zero live defenses")
	game.phase = "day"
	game.scrap = game.districts.tower_cost(game.TOWER_COSTS[0])
	place_hero(tower_point + Vector3(0, 0, -2.2), tower_point)
	await press(KEY_F)
	check(int(pad.level) == 1 and float(pad.hp) == 280.0 and not pad.damage_ring.visible
		and game.tower_count() == 1 and game.scrap == 0,
		"Real day-phase F reconstructs the last footing, clears its warning, and spends the sole funded price once")
	await finish()
