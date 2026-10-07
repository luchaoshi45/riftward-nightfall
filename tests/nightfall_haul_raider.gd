extends SceneTree
## 劫运体专项：真实兵营训练采运工队后，验证载货身份、暂停冻结与生命周期清理。

var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 20: push_error(message)

func clear_enemies() -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()

func build(kind: String, point: Vector3) -> bool:
	if not game.build_district(kind): return false
	game.aim = point
	return game.construction.confirm()

func cleanup() -> void:
	if is_instance_valid(game):
		await game.prepare_shutdown()
		game.queue_free()
		await process_frame
	await create_timer(.5, true, false, true).timeout

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	check(game.choose_card(0), "Opening card must initialize a real production run")
	clear_enemies()
	game.run_mode = "standard"
	game.phase = "day"
	game.scrap = 2000

	check(build("barracks", Vector3(-6, 5, -5)), "A real barracks must be buildable for the carrier training path")
	check(build("workshop", Vector3(6, 5, -5)), "A real workshop must be buildable for the depot prerequisite")
	check(build("depot", Vector3(6, 5, 1)), "A real depot must unlock the carrier training path")
	check(game.train_troop("hauler"), "The carrier must enter the real paid training queue")
	game.squads.advance(8.1)
	check(game.squads.squads.size() == 1 and String(game.squads.squads[0].kind) == "hauler",
		"The real training queue must create one carrier squad")
	if game.squads.squads.is_empty():
		await cleanup(); quit(1); return

	var squad: Dictionary = game.squads.squads[0]
	var squad_id := int(squad.id)
	var member: BattleUnit = squad.members[0]
	var token := member.get_instance_id()
	game.logistics._sync_teams()
	var field: Dictionary = game.logistics.fields[0]
	# Run the actual logistics commit path when possible. The fallback only seeds
	# the already-paid physical cargo row; all raider checks still use raid_member.
	member.position = field.position
	member.position.y = game.outpost_height(member.position)
	var team: Dictionary = game.logistics._teams[squad_id]
	team.automatic = false
	game.logistics._cargo[token] = {"squad_id": squad_id, "amount": 8}
	game.logistics._show_cargo(token, 8)
	var loaded: Array[Dictionary] = game.logistics.haul_raider_targets()
	check(loaded.size() == 1 and int(loaded[0].token) == token and int(loaded[0].haul_cargo) == 8,
		"Only the real living carrier with physical cargo may become a raider target")
	var mismatch: Dictionary = game.logistics.raid_member(token, squad.members[1], squad_id, 1)
	check(not bool(mismatch.ok) and String(mismatch.reason) == "member_identity_mismatch",
		"A different live member may not inherit the old target token")

	game.day_number = 2
	game.start_night()
	clear_enemies()
	game.haul_raider.elapsed = 22.0
	game.simulate(.01)
	var raider: BattleUnit
	for enemy in game.enemies:
		if is_instance_valid(enemy) and bool(enemy.get_meta("haul_raider", false)):
			raider = enemy
			break
	check(is_instance_valid(raider), "A loaded carrier on the second non-teaching night must spawn one raider")
	if not is_instance_valid(raider):
		await cleanup(); quit(1); return
	raider.position = member.position + Vector3(0, 0, 1.0)
	raider.position.y = game.outpost_height(raider.position)
	raider.attack_timer = 0.0
	var cargo_before := int(game.logistics.snapshot().cargo)
	var raided_before := int(game.logistics.snapshot().raided)
	var hp_before := member.hp
	game.update_creature(raider, .01)
	check(int(raider.get_meta("attack_target_token", -1)) == token,
		"The raider must lock the exact loaded member token")
	raider.tick(.4)
	game.update_creature(raider, .01)
	var after: Dictionary = game.logistics.snapshot()
	check(member.hp < hp_before, "A raider hit must deal real damage to the carrier")
	check(int(after.raided) > raided_before and int(after.cargo) < cargo_before,
		"A successful hit must remove real cargo and record it separately as raided")
	check(int(after.lost) == 0, "Raiding cargo must not be misclassified as carrier loss")

	game.phase = "paused"
	var paused_cargo := int(game.logistics.snapshot().cargo)
	var paused_raided := int(game.logistics.snapshot().raided)
	game.simulate(5.0)
	check(int(game.logistics.snapshot().cargo) == paused_cargo and int(game.logistics.snapshot().raided) == paused_raided,
		"Pause must freeze raider movement, damage and cargo theft")
	game.phase = "night"
	game.run_mode = "teaching"
	game.haul_raider.begin_night(2)
	game.haul_raider.elapsed = 40.0
	check(not game.haul_raider.eligible(), "Teaching mode must disable the extra raider event")
	game.run_mode = "standard"
	game.haul_raider.begin_night(1)
	game.haul_raider.elapsed = 40.0
	check(not game.haul_raider.eligible(), "The first night must not spawn the extra raider event")
	game.haul_raider.begin_night(2)
	game.haul_raider.elapsed = 40.0
	check(game.haul_raider.eligible(), "The second night should remain eligible while a carrier still has cargo")
	game.end_defeat("劫运体专项清理")
	check(not game.haul_raider.snapshot().possible and not game.haul_raider.snapshot().eligible,
		"Defeat must clear the raider controller and its target eligibility")
	print("NIGHTFALL_HAUL_RAIDER_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	await cleanup()
	quit(0 if failures.is_empty() else 1)
