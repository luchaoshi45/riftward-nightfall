extends SceneTree
## A real dense tower row seals the city; attackers break exposed buildings,
## cannot damage sealed targets remotely, and regain a route through destroyed footings.
const Layout := preload("res://scripts/outpost_layout.gd")
const STEP := .05
var game: Node3D
var failures: Array[String] = []
var checks := 0
var row: Array[int] = []
var gap_x := 0.0

func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 20: push_error(message)

func planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func advance_enemy(enemy: BattleUnit, frames: int) -> void:
	for frame in frames:
		var previous := enemy.position
		enemy.tick(STEP)
		game.update_creature(enemy, STEP)
		check(enemy.position.is_finite() and game.outpost_walkable(enemy.position), "The real attacker must remain on reachable finite ground")
		check(game.can_traverse(previous, enemy.position), "An actual movement step must not cross the dense building row")
		check(planar(previous, enemy.position) <= enemy.speed * STEP + .001, "An actual attacker cannot teleport through a blocked row")

func finish() -> void:
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_DENSE_CONSTRUCTION_PATH_", "OK" if failures.is_empty() else "FAILED", " checks=", checks,
		" actual_dense_towers reachable_structure_damage sealed_target_no_remote_damage destroyed_gap pursuit")
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	check(game.choose_card(0) and game.phase == "night", "The actual opening choice must enter the production night")
	for enemy: BattleUnit in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	await process_frame
	game.scrap = 10000
	game.phase_time = 10000.0
	var row_limit: float = Layout.FORT_INNER - game.construction.footprint("tower").x
	gap_x = row_limit / 9.0
	game.hero.position = Vector3(gap_x, Layout.FORT_HEIGHT, 5.1)
	game.move_goal = game.hero.position
	game.hero_path.clear()
	game.hero.attack_timer = 999.0
	game.pulse_timer = 999.0
	# Remove the two opening defenses through the real damage/rebuild system,
	# so every live obstacle below is one of the newly player-built row towers.
	for index in game.world.tower_pads.size():
		var pad: Dictionary = game.world.tower_pads[index]
		game.damage_tower(index, float(pad.hp))
	check(game.outpost_walkable(game.hero.position), "The sealed hero must stand on genuine free ground")
	for column in 10:
		var point := Vector3(-row_limit + float(column) * row_limit * 2.0 / 9.0, Layout.FORT_HEIGHT, 7.0)
		var before: int = game.world.tower_pads.size()
		var balance: int = game.scrap
		var built: bool = game.build_tower_at(point)
		check(built and game.world.tower_pads.size() == before + 1 and game.scrap == balance - 60,
			"Each dense obstacle must be a real freely placed and paid live tower")
		if not built:
			await finish()
			return
		row.append(before)
	var middle: int = row[5]
	var middle_pad: Dictionary = game.world.tower_pads[middle]
	check(planar(middle_pad.position, Vector3(gap_x, 5, 7)) < .001, "The eventual gap must use the actual centre-right tower")
	var attacker: BattleUnit = game.spawn_creature(true, "stalker")
	attacker.position = Vector3(gap_x, Layout.FORT_HEIGHT, 11.0)
	attacker.speed = 3.2
	attacker.damage = 20.0
	attacker.attack_timer = 0.0
	attacker.attack_interval = 1.2
	var hero_target := {"kind": "hero", "index": -1, "position": game.hero.position}
	check(not game.enemy_target_reachable(attacker.position, hero_target), "The dense physical row must seal the real hero route")
	var core_target := {"kind": "beacon", "index": -1, "position": Vector3(0, 5, 0)}
	check(not game.enemy_target_reachable(attacker.position, core_target), "The dense row must also seal every core approach")
	var inaccessible: Vector3 = game.building_approach_position(attacker.position, Vector3(0, 5, 0), "core")
	check(not inaccessible.is_finite(), "No reachable building approach must return INF, never the attacker's remote origin")
	var target: Dictionary = game.choose_enemy_target(attacker)
	check(String(target.get("kind", "")) == "tower" and int(target.get("index", -1)) in row,
		"A normal attacker must select an exposed player-built blocker instead of sealed targets")
	check(game.enemy_target_reachable(attacker.position, target), "The actual selected blocker must have a reachable attack surface")
	var hero_hp: float = game.hero.hp
	var core_hp: float = game.beacon_hp
	var tower_hp: float = middle_pad.hp
	advance_enemy(attacker, 120)
	check(float(middle_pad.hp) < tower_hp and int(middle_pad.level) > 0,
		"Real enemy windup and strikes must deduct durability from the reachable blocker")
	check(game.hero.hp == hero_hp and game.beacon_hp == core_hp,
		"Six seconds of real blocked assault must not remotely damage the sealed hero or core")
	check(planar(attacker.position, middle_pad.position) <= attacker.attack_range + game.construction.footprint("tower").x + .4,
		"Building strikes must occur at an actual reachable melee surface")
	game.damage_tower(middle, float(middle_pad.hp))
	check(int(middle_pad.level) == 0 and bool(middle_pad.get("free_built", false)),
		"Destroying the actual blocker must preserve its paid reconstruction identity")
	check(game.outpost_walkable(middle_pad.position), "The destroyed low footing must become physically traversable")
	check(game.can_traverse(Vector3(gap_x, 5, 9), Vector3(gap_x, 5, 5.1)),
		"The exact destroyed middle footprint must reopen continuous north/south traversal")
	check(game.enemy_target_reachable(attacker.position, hero_target), "Destruction must invalidate cached reachability and reopen the hero route")
	game.hero.position = Vector3(gap_x, 5, 7.7)
	game.plan_hero_path(Vector3(gap_x, 5, 5.1))
	check(not game.hero_path.is_empty() and planar(game.move_goal, Vector3(gap_x, 5, 5.1)) < .01,
		"The real navigation grid must also regain a valid hero route through the destroyed row gap")
	# Start the same living attacker in the now-open gap to isolate its next
	# closest-target decision; a short melee range makes it actually cross the
	# former row before its real windup can hit the north-side hero.
	game.hero.position = Vector3(gap_x, 5, 5.1)
	attacker.position = Vector3(gap_x, 5, 7.7)
	attacker.attack_range = 1.2
	attacker.attack_queued = false
	attacker.attack_windup = 0.0
	attacker.attack_timer = 0.0
	attacker.path.clear()
	attacker.path_timer = 0.0
	target = game.choose_enemy_target(attacker)
	check(String(target.get("kind", "")) == "hero", "After opening the gap, the same normal enemy must regain its closest living hero target")
	hero_hp = game.hero.hp
	advance_enemy(attacker, 60)
	check(attacker.position.z < 7.0 and game.hero.hp < hero_hp,
		"Real post-destruction pursuit must walk across the former row and damage the hero only in melee range")
	check(planar(attacker.position, game.hero.position) <= attacker.attack_range + .01 and game.beacon_hp == core_hp,
		"The recovered attack must hit the nearby hero without distant core damage")
	await finish()
