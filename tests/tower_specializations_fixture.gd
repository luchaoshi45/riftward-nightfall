extends SceneTree

const Rules = preload("res://scripts/tower_specializations.gd")
var game: Node3D
var rules = Rules.new()
var checks := 0
var failures: Array[String] = []
var finished := false
var finishing := false

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		root.set_flag(Window.FLAG_NO_FOCUS, true)
		root.hide()
		root.position = Vector2i(10000, 10000)
	create_timer(20.0, true, false, true).timeout.connect(watchdog)
	call_deferred("run")

func check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)
	return condition

func watchdog() -> void:
	if finished: return
	check(false, "Tower fixture did not finish within its twenty-second watchdog")
	# A script error aborts its coroutine. The independent watchdog still
	# performs the production shutdown before reporting a failed process.
	if finishing:
		quit(1)
		return
	await finish(1)

func finish(exit_code: int) -> void:
	if finishing: return
	finishing = true
	if is_instance_valid(game):
		await game.prepare_shutdown()
		game.queue_free()
	for _frame in 12: await process_frame
	finished = true
	print("TOWER_SPECIALIZATIONS_FIXTURE_%s checks=%d failures=%d: actual scene enemies, damage, cap, lifecycle, legal-edge rebuild" % ["OK" if exit_code == 0 and failures.is_empty() else "FAILED", checks, failures.size()])
	quit(exit_code)

func enemy(threat: String, point: Vector3) -> BattleUnit:
	var unit: BattleUnit = game.spawn_creature(false)
	unit.set_meta("threat", threat)
	unit.position = point
	unit.hp = 10000
	unit.max_hp = 10000
	return unit

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	if not check(game.choose_card(0), "Actual opening card enters the live game"):
		await finish(1)
		return
	game.set_process(false)
	for old in game.enemies:
		if is_instance_valid(old): old.queue_free()
	game.enemies.clear()
	var pad: Dictionary = game.world.tower_pads[1]
	# Interact from the genuine two-metre outside edge, within the 2.6m
	# interaction radius. Occupying the foundation prevents a legal rebuild.
	game.hero.position = (pad.position as Vector3) + Vector3(2, 0, 0)
	game.scrap = 500
	check(game.nearest_tower_pad() == 1, "Actual outside-edge standing position selects the intended tower")
	check(game.interact(), "Real outside-edge interaction builds or upgrades the tower")
	if pad.level < 2: check(game.interact(), "Real interaction completes the second tower level")
	var failed: Dictionary = rules.choose(pad, Rules.CONTROL, 44, "night")
	check(not failed.ok and failed.scrap == 44 and rules.branch(pad) == Rules.STANDARD, "Insufficient funds keep the original branch and balance")
	check(not rules.choose(pad, Rules.CONTROL, 100, "night", true).ok, "Frozen gameplay rejects specialization changes")
	var paid: Dictionary = rules.choose(pad, Rules.PIERCING, 100, "day")
	check(paid.ok and paid.scrap == 55, "Actual piercing branch charges the original forty-five parts")
	check(not rules.choose(pad, Rules.CONTROL, 100, "night").ok, "An already specialized tower cannot buy another branch")
	var health: float = pad.hp
	var mode: String = pad.mode
	var level: int = pad.level
	var point := Vector3(0, 0, 26)
	var breaker := enemy("breaker", point)
	var sapper := enemy("sapper", point + Vector3(1, 0, 0))
	var runner := enemy("runner", point + Vector3(2, 0, 0))
	var stalker := enemy("stalker", point + Vector3(2.5, 0, 0))
	var eater := enemy("light_eater", point + Vector3(3, 0, 0))
	var overflow := enemy("runner", point + Vector3(3.1, 0, 0))
	var far := enemy("stalker", point + Vector3(3.3, 0, 0))
	breaker.armor = 100
	var hp := breaker.hp
	var hits: Array = rules.resolve_shot(pad, breaker, game.enemies, 100, game.hero)
	check(hits.size() == 1 and is_equal_approx(hp - breaker.hp, 110.0), "Piercing against the original hundred-armor breaker deals exactly 110 damage to one target")
	hp = runner.hp
	rules.resolve_shot(pad, runner, game.enemies, 100, game.hero)
	check(is_equal_approx(hp - runner.hp, 75.0), "Piercing preserves the original seventy-five damage against a light runner")
	# 改装不动原耐久、目标模式、等级；真实蚀塔毁塔路径仍生效。
	check(pad.hp == health and pad.mode == mode and pad.level == level, "Specializing keeps the original durability, mode and tower level")
	game.damage_tower(1, health + 1)
	rules.on_destroyed(pad)
	check(pad.level == 0 and rules.branch(pad) == Rules.STANDARD, "Real destruction removes the tower and resets its branch")
	check(not rules.choose(pad, Rules.CONTROL, 100, "night").ok, "A destroyed tower cannot specialize")
	check(bool(game.construction.validity(pad.position, 1, "tower").valid), "Outside-edge standing leaves the actual destroyed foundation legally rebuildable")
	check(game.interact() and pad.level == 1, "Real interaction rebuilds exactly the first tower level from the legal outside edge")
	check(not rules.choose(pad, Rules.CONTROL, 100, "night").ok, "A rebuilt first-level tower still cannot specialize")
	check(game.interact() and pad.level == 2, "Real outside-edge interaction upgrades the rebuilt tower to level two")
	check(rules.choose(pad, Rules.CONTROL, 100, "night").scrap == 55, "Rebuilt level-two control branch charges the original forty-five parts")
	var speeds: Array[float] = []
	for unit in game.enemies: speeds.append(unit.speed)
	hp = breaker.hp
	hits = rules.resolve_shot(pad, breaker, game.enemies, 100, game.hero)
	check(hits.size() == 5 and is_equal_approx(hp - breaker.hp, 27.5), "Control keeps its five-target cap and original 27.5 breaker damage")
	check(is_equal_approx(rules.movement_multiplier(breaker), .85), "Control slows the original breaker by fifteen percent")
	check(is_equal_approx(rules.movement_multiplier(sapper), .85), "Control slows the original sapper by fifteen percent")
	check(is_equal_approx(rules.movement_multiplier(runner), .70), "Control slows the original runner by thirty percent")
	check(rules.movement_multiplier(overflow) == 1 and rules.movement_multiplier(far) == 1, "Overflow and out-of-circle targets receive no control slow")
	check(rules.cooldown_multiplier(pad) == 1.25, "Control retains its original cooldown multiplier")
	# 实例敌群的实际位移 fixture 使用待接入的移动表达式，无基础移速写入。
	var before := runner.position
	runner.position += Vector3.FORWARD * runner.speed * rules.movement_multiplier(runner) * .5
	check(is_equal_approx(before.distance_to(runner.position), runner.speed * .7 * .5), "Isolated displacement expression respects the actual movement multiplier")
	runner.position = before
	rules.advance(.8)
	rules.advance(20, false) # 暂停/选卡冻结。
	check(is_equal_approx(rules.movement_multiplier(runner), .7), "Paused rule advancement leaves the existing slow frozen")
	for i in 12: rules.resolve_shot(pad, breaker, game.enemies, 1, game.hero)
	check(is_equal_approx(rules.movement_multiplier(runner), .7), "Repeated hits retain the original thirty-percent slow")
	rules.advance(1.21)
	check(rules.movement_multiplier(runner) == 1, "The original slow naturally expires after its remaining lifetime")
	rules.resolve_shot(pad, breaker, game.enemies, 1, game.hero)
	runner.hurt(20000, game.hero)
	runner.revive(point + Vector3(2, 0, 0))
	check(rules.movement_multiplier(runner) == 1, "Real death and revival do not retain an old slow")
	runner.alive = false
	rules.advance(0, false)
	check(rules.movement_multiplier(runner) == 1, "Dead targets stay free of a stale slow while advancement is frozen")
	for i in game.enemies.size(): check(game.enemies[i].speed == speeds[i], "Specialization never rewrites an enemy's base speed")
	rules.reset_effects() # 昼夜、结束、新局。
	check(rules.movement_multiplier(breaker) == 1, "Effect reset removes the original breaker's active slow")
	# 通用三级保持现有原伤及36%溅射，不覆盖外部基础伤害加成。
	pad.specialization = Rules.STANDARD
	pad.level = 3
	breaker.armor = 0
	hp = sapper.hp
	hits = rules.resolve_shot(pad, breaker, game.enemies, 125, game.hero)
	check(hits.size() == 3 and is_equal_approx(hp - sapper.hp, 45.0), "Standard level-three fire keeps its three hits and thirty-six-percent splash")
	pad.specialization = Rules.CONTROL
	hits = rules.resolve_shot(pad, breaker, game.enemies, 100, game.hero)
	check(hits.size() == 5, "Level-three control keeps five targets without standard splash")
	pad.specialization = Rules.PIERCING
	hits = rules.resolve_shot(pad, breaker, game.enemies, 100, game.hero)
	check(hits.size() == 1, "Level-three piercing remains single-target")
	var friendly := BattleUnit.new()
	root.add_child(friendly)
	friendly.kind = "monster"
	friendly.team = 0
	check(rules.resolve_shot(pad, friendly, game.enemies, 100, game.hero).is_empty(), "Specialized fire cannot harm the actual friendly unit")
	friendly.queue_free()
	rules.reset_effects()
	await finish(0 if failures.is_empty() else 1)
