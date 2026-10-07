extends SceneTree
## Precision route regression, not a natural-budget or whole-night proof.
## Only initial actors are positioned. Subsequent movement, windups and damage
## use the unchanged production creature and actual tick/update_creature chain.
const STEP := 0.04
const MAX_STEPS := 180
var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 12: push_error(message)

func planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func close_game() -> void:
	if not is_instance_valid(game): return
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	game = null

func fresh() -> void:
	await close_game()
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	check(game.choose_card(0) and game.phase == "night", "Precision scene must enter the actual opening night")
	check(game.tower_count() == 2, "Precision scene retains both actual opening towers")

func place_hero(point: Vector3) -> void:
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.move_goal = point
	game.hero_path.clear()

func enemy_at(point: Vector3) -> BattleUnit:
	var enemy: BattleUnit = game.spawn_creature(true, "stalker")
	point.y = game.outpost_height(point)
	enemy.position = point
	return enemy

func actual_step(enemy: BattleUnit, label: String) -> void:
	var previous := enemy.position
	enemy.tick(STEP)
	game.update_creature(enemy, STEP)
	check(enemy.position.is_finite() and game.outpost_walkable(enemy.position), label + ": enemy remains on finite walkable terrain")
	check(game.can_traverse(previous, enemy.position), label + ": every actual movement step respects walls and live buildings")
	check(planar(previous, enemy.position) <= enemy.speed * STEP + 0.001, label + ": movement never teleports")
	check(absf(enemy.position.y - game.outpost_height(enemy.position)) < 0.001, label + ": movement follows the real terrain height")

func pursue_until_damage(enemy: BattleUnit, label: String) -> void:
	var before: float = game.hero.hp
	var saw_legal_windup := false
	for frame in MAX_STEPS:
		actual_step(enemy, label)
		if enemy.attack_queued:
			var real_hero_cast := String(enemy.get_meta("attack_target_kind", "")) == "hero" and enemy.attack_target_hero
			check(real_hero_cast, label + ": queued attack belongs to the actual hero endpoint")
			check(game.can_attack_line(enemy.position, game.hero.position), label + ": queued hero hit has a legal wall-free attack line")
			check(enemy.position.distance_to(game.hero.position) <= enemy.attack_range + 0.001, label + ": queued hero hit is within unchanged melee range")
			if real_hero_cast and enemy.attack_windup > 0.0: saw_legal_windup = true
		if game.hero.hp < before: break
	check(saw_legal_windup, label + ": bounded pursuit must reach a final target and use the real positive windup")
	check(game.hero.hp < before, label + ": bounded pursuit must cause actual hero health loss")
	check(enemy.position.distance_to(game.hero.position) <= enemy.attack_range + 0.001 and game.can_attack_line(enemy.position, game.hero.position), label + ": actual damage occurs only after a legal endpoint approach")

func corner(side: float) -> void:
	await fresh()
	var label := "east gate corner" if side > 0.0 else "west gate corner"
	place_hero(Vector3(side * 2.64, 0.0, 13.4))
	var enemy := enemy_at(Vector3(side * 3.5, 0.0, 12.2))
	check(game.outpost_walkable(game.hero.position) and game.outpost_walkable(enemy.position), label + ": both initial precision positions are legal")
	check(game.hero_safe_destination(game.hero.position).distance_to(game.hero.position) < 0.001, label + ": hero endpoint is permitted by the actual movement clearance")
	check(not game.can_traverse(enemy.position, game.hero.position), label + ": the real south wall requires an actual detour")
	var nearest: Vector2i = game.nearest_navigation_cell(game.hero.position, false)
	var connected: Vector2i = game.nearest_navigation_cell(game.hero.position, true)
	check(nearest != connected, label + ": closest grid point differs from the continuously connected endpoint")
	check(not game.can_traverse(Vector3(nearest.x, 5.0, nearest.y), game.hero.position), label + ": closest grid point has a blocked final segment")
	check(game.can_traverse(Vector3(connected.x, 5.0, connected.y), game.hero.position), label + ": connected endpoint has a legal final segment")
	var chosen: Dictionary = game.choose_enemy_target(enemy)
	check(String(chosen.get("kind", "")) == "hero" and game.enemy_target_reachable(enemy.position, chosen), label + ": real nearest-target selector already considers the hero reachable")
	pursue_until_damage(enemy, label)

func changed_endpoint() -> void:
	await fresh()
	place_hero(Vector3(2.64, 0.0, 13.4))
	var enemy := enemy_at(Vector3(3.5, 0.0, 12.2))
	var before: float = game.hero.hp
	for frame in 2: actual_step(enemy, "moving hero setup")
	check(game.hero.hp == before, "Moving-target precision setup must not claim damage before its windup")
	# This explicit target reposition tests replanning, not player travel.
	place_hero(Vector3(2.0, 0.0, 12.0))
	var chosen: Dictionary = game.choose_enemy_target(enemy)
	check(String(chosen.get("kind", "")) == "hero" and game.enemy_target_reachable(enemy.position, chosen), "Changed legal endpoint remains the actual nearest reachable target")
	pursue_until_damage(enemy, "changed hero endpoint")
	check(enemy.path_goal.distance_to(game.hero.position) < 0.001, "The actual cached route must observe the changed hero endpoint")

func run() -> void:
	await corner(1.0)
	await corner(-1.0)
	await changed_endpoint()
	await close_game()
	print("NIGHTFALL_ENEMY_ROUTE_ENDPOINT_", "OK" if failures.is_empty() else "FAILED", " checks=", checks, " failures=", failures.size(), " precision_mirrored_gate_corner real_steps real_windup real_damage changed_endpoint")
	quit(0 if failures.is_empty() else 1)
