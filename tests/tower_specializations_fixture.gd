extends SceneTree

const Rules = preload("res://scripts/tower_specializations.gd")
var game: Node3D
var rules = Rules.new()

func _initialize() -> void:
	call_deferred("run")

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
	assert(game.choose_card(0))
	game.set_process(false)
	for old in game.enemies:
		if is_instance_valid(old): old.queue_free()
	game.enemies.clear()
	var pad: Dictionary = game.world.tower_pads[1]
	game.hero.position = pad.position
	game.scrap = 500
	assert(game.interact())
	if pad.level < 2: assert(game.interact())
	var failed: Dictionary = rules.choose(pad, Rules.CONTROL, 44, "night")
	assert(not failed.ok and failed.scrap == 44 and rules.branch(pad) == Rules.STANDARD)
	assert(not rules.choose(pad, Rules.CONTROL, 100, "night", true).ok)
	var paid: Dictionary = rules.choose(pad, Rules.PIERCING, 100, "day")
	assert(paid.ok and paid.scrap == 55)
	assert(not rules.choose(pad, Rules.CONTROL, 100, "night").ok)
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
	assert(hits.size() == 1 and is_equal_approx(hp - breaker.hp, 110.0))
	hp = runner.hp
	rules.resolve_shot(pad, runner, game.enemies, 100, game.hero)
	assert(is_equal_approx(hp - runner.hp, 75.0))
	# 改装不动原耐久、目标模式、等级；真实蚀塔毁塔路径仍生效。
	assert(pad.hp == health and pad.mode == mode and pad.level == level)
	game.damage_tower(1, health + 1)
	rules.on_destroyed(pad)
	assert(pad.level == 0 and rules.branch(pad) == Rules.STANDARD)
	assert(not rules.choose(pad, Rules.CONTROL, 100, "night").ok)
	assert(game.interact() and pad.level == 1)
	assert(not rules.choose(pad, Rules.CONTROL, 100, "night").ok)
	assert(game.interact() and pad.level == 2)
	assert(rules.choose(pad, Rules.CONTROL, 100, "night").scrap == 55)
	var speeds: Array[float] = []
	for unit in game.enemies: speeds.append(unit.speed)
	hp = breaker.hp
	hits = rules.resolve_shot(pad, breaker, game.enemies, 100, game.hero)
	assert(hits.size() == 5 and is_equal_approx(hp - breaker.hp, 27.5))
	assert(is_equal_approx(rules.movement_multiplier(breaker), .85))
	assert(is_equal_approx(rules.movement_multiplier(sapper), .85))
	assert(is_equal_approx(rules.movement_multiplier(runner), .70))
	assert(rules.movement_multiplier(overflow) == 1 and rules.movement_multiplier(far) == 1)
	assert(rules.cooldown_multiplier(pad) == 1.25)
	# 实例敌群的实际位移 fixture 使用待接入的移动表达式，无基础移速写入。
	var before := runner.position
	runner.position += Vector3.FORWARD * runner.speed * rules.movement_multiplier(runner) * .5
	assert(is_equal_approx(before.distance_to(runner.position), runner.speed * .7 * .5))
	runner.position = before
	rules.advance(.8)
	rules.advance(20, false) # 暂停/选卡冻结。
	assert(is_equal_approx(rules.movement_multiplier(runner), .7))
	for i in 12: rules.resolve_shot(pad, breaker, game.enemies, 1, game.hero)
	assert(is_equal_approx(rules.movement_multiplier(runner), .7))
	rules.advance(1.21)
	assert(rules.movement_multiplier(runner) == 1)
	rules.resolve_shot(pad, breaker, game.enemies, 1, game.hero)
	runner.hurt(20000, game.hero)
	runner.revive(point + Vector3(2, 0, 0))
	assert(rules.movement_multiplier(runner) == 1)
	runner.alive = false
	rules.advance(0, false)
	assert(rules.movement_multiplier(runner) == 1)
	for i in game.enemies.size(): assert(game.enemies[i].speed == speeds[i])
	rules.reset_effects() # 昼夜、结束、新局。
	assert(rules.movement_multiplier(breaker) == 1)
	# 通用三级保持现有原伤及36%溅射，不覆盖外部基础伤害加成。
	pad.specialization = Rules.STANDARD
	pad.level = 3
	breaker.armor = 0
	hp = sapper.hp
	hits = rules.resolve_shot(pad, breaker, game.enemies, 125, game.hero)
	assert(hits.size() == 3 and is_equal_approx(hp - sapper.hp, 45.0))
	pad.specialization = Rules.CONTROL
	hits = rules.resolve_shot(pad, breaker, game.enemies, 100, game.hero)
	assert(hits.size() == 5) # 三级牵制没有额外原溅射。
	pad.specialization = Rules.PIERCING
	hits = rules.resolve_shot(pad, breaker, game.enemies, 100, game.hero)
	assert(hits.size() == 1) # 三级破甲仍仅单体。
	var friendly := BattleUnit.new()
	root.add_child(friendly)
	friendly.kind = "monster"
	friendly.team = 0
	assert(rules.resolve_shot(pad, friendly, game.enemies, 100, game.hero).is_empty())
	friendly.queue_free()
	rules.reset_effects()
	print("TOWER_SPECIALIZATIONS_FIXTURE_OK: actual scene enemies, damage, cap, lifecycle, rebuild")
	await game.prepare_shutdown()
	game.queue_free()
	for i in 12: await process_frame
	quit(0)
