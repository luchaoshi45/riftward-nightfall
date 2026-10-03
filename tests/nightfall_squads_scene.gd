extends SceneTree
## Independent manager in the real production terrain and reward controller.
const SquadScript = preload("res://scripts/outpost_squads.gd")
var game: Node3D
var squads: Node3D
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message); push_error(message)

func remove_enemies() -> void:
	for unit in game.enemies:
		if is_instance_valid(unit): unit.queue_free()
	game.enemies.clear()

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false)
	check(game.choose_card(0), "Opening draft must still start the real game")
	remove_enemies()
	game.phase = "night"; game.hero.position = Vector3(35, 0, 35)
	game.scrap = 300; game.essence = 0
	squads = SquadScript.new(); game.add_child(squads); squads.setup(game, true)
	check(squads.hire("shield").ok and squads.hire("ranged").ok and game.scrap == 150, "Mixed real-scene squad hiring must debit exactly 150")
	for step in 65: squads.advance(.1)
	for squad in squads.squads:
		for member: BattleUnit in squad.members:
			check(game.outpost_walkable(member.position), "Every real station must lie in traversable south-gate ground")
			check(is_equal_approx(member.position.y, game.world.terrain_height(member.position)), "Real soldiers must track the height-five ramp")
			check(game.can_traverse(Vector3(member.position.x, 5, 3.5), member.position), "Soldier station must remain reachable through the single south entrance")
			check(member.find_children("*", "CollisionObject3D", true, false).is_empty(), "Friendly models cannot block hero pathing")
	var defender: BattleUnit = squads.squads[0].members[1]
	var attacker: BattleUnit = game.spawn_creature(true)
	attacker.set_meta("threat", "stalker")
	attacker.position = defender.position + Vector3(0, 0, 1.0)
	attacker.position.y = game.outpost_height(attacker.position)
	attacker.damage = 30.0; attacker.attack_timer = 0.0; attacker.speed = 0.0
	var old_beacon: float = game.beacon_hp
	var old_hero: float = game.hero.hp
	var old_hp := defender.hp
	attacker.tick(.01); check(squads.intercept_enemy(attacker, .01), "Real normal attacker must accept the small-squad hook")
	attacker.tick(.35); squads.intercept_enemy(attacker, .35)
	check(defender.hp < old_hp and game.hero.hp == old_hero and game.beacon_hp == old_beacon, "Real interception damage must reach the actual defender, preserving hero/core")
	defender.hurt(10000, attacker)
	var alive_after_death: int = squads.snapshot().alive
	await process_frame
	check(not is_instance_valid(defender) and squads.snapshot().alive == alive_after_death, "Real freed soldiers must not leave unusable slot references")
	squads.on_day(); squads.on_night()
	check(squads.snapshot().alive == alive_after_death, "Actual cross-night casualties must remain dead")
	game.phase = "day"; squads.on_day()
	game.scrap = 100
	var cost: int = squads.refill_cost()
	check(squads.refill().ok and game.scrap == 100 - cost and squads.snapshot().alive == 6, "Actual daytime replacement must consume the announced fee")
	remove_enemies()
	game.phase = "night"; squads.on_night()
	for step in 65: squads.advance(.1)
	var archer: BattleUnit = squads.squads[1].members[1]
	var victim: BattleUnit = game.spawn_creature(true)
	victim.position = archer.position + Vector3(0, 0, 2.0)
	victim.position.y = game.outpost_height(victim.position)
	victim.set_meta("threat", "breaker")
	victim.max_hp = 1.0; victim.hp = 1.0; victim.armor = 0.0
	game.kill_chain = 2; game.kill_chain_time = 6.0; game.player_attack_resolving = true
	var old_kills: int = game.kills
	var old_scrap: int = game.scrap
	for member: BattleUnit in squads.squads[1].members: member.attack_timer = 0.0
	squads.advance(.01); squads.advance(.27)
	check(game.kills == old_kills + 1 and game.kill_chain == 2, "Soldier kill must count normal defeat exactly once without claiming a hero chain milestone")
	check(game.scrap == old_scrap + 8 and game.essence == 12, "Soldier reward must use the real controller's normal kill payout")
	check(not squads.shots.is_empty(), "Actual ranged damage must also produce its owned beam")
	await process_frame
	check(not is_instance_valid(victim), "Actual controller defeat must dispose the killed enemy")
	game.player_attack_resolving = false
	game.phase = "paused"
	var member_position: Vector3 = archer.position
	var attack_timer: float = archer.attack_timer
	var beam_time: float = squads.shots[0].time
	squads.advance(20.0)
	check(archer.position == member_position and archer.attack_timer == attack_timer and squads.shots[0].time == beam_time, "Real pause must freeze movement, attacks, and beam cleanup")
	game.phase = "night"; squads.advance(.20)
	check(squads.shots.is_empty(), "Resumed beams must finish and retire")
	squads.clear(); check(squads.snapshot().alive == 0, "Shutdown must clear remaining soldiers before scene release")
	await game.prepare_shutdown()
	game.queue_free(); await process_frame; await create_timer(.15).timeout
	print("NIGHTFALL_SQUADS_SCENE_", "OK" if failures.is_empty() else "FAILED")
	quit(0 if failures.is_empty() else 1)
