extends SceneTree

const Siege = preload("res://scripts/nightfall_siege_boss.gd")
const Squads = preload("res://scripts/outpost_squads.gd")

class FixtureGame extends Node3D:
	var phase: String = "night"
	var scrap: int = 999
	var hero: BattleUnit
	var squads: Node3D
	var beacon_hp: float = 1200.0
	var recorded: float = 0.0
	var adds: Array[BattleUnit] = []
	var last_notice: String = ""
	func _init() -> void:
		hero = make_unit("hero", Vector3(0, 5, 1.5))
	func make_unit(kind: String, point: Vector3) -> BattleUnit:
		var unit: BattleUnit = BattleUnit.new()
		add_child(unit)
		unit.kind = kind
		unit.hp = 850.0
		unit.max_hp = 850.0
		unit.visual = Node3D.new()
		unit.add_child(unit.visual)
		unit.position = point
		return unit
	func outpost_height(_point: Vector3) -> float:
		return 5.0
	func can_traverse(_from: Vector3, _to: Vector3) -> bool:
		return true
	func notify(message: String, _seconds: float) -> void:
		last_notice = message
	func record_beacon_hit(amount: float) -> void:
		recorded += amount
	func end_defeat(_message: String) -> void:
		phase = "ended"
	func spawn_creature(night: bool, role: String = "") -> BattleUnit:
		assert(night and role == "runner")
		var unit: BattleUnit = make_unit("monster", Vector3(0, 0, 45))
		unit.set_meta("threat", role)
		adds.append(unit)
		return unit

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: FixtureGame = FixtureGame.new()
	root.add_child(game)
	game.squads = Squads.new()
	game.add_child(game.squads)
	game.squads.setup(game, true)
	assert(game.squads.hire("shield").ok)
	assert(game.squads.hire("ranged").ok)
	var boss: BattleUnit = game.make_unit("monster", Vector3(0, 5, 0))
	var siege: Node = Siege.new()
	siege.setup(game, boss)
	assert(boss.hp == 2600.0 and boss.armor == 18.0 and boss.damage == 70.0)
	assert(boss.speed == 2.1 and boss.visual.scale == Vector3.ONE * 1.85)
	assert(boss.get_meta("threat") == "breaker" and boss.get_meta("siege_boss"))
	assert(not siege.advance(7.9))
	assert(siege.advance(0.11) and siege.snapshot().phase == "windup")
	assert(is_equal_approx(siege.snapshot().windup, 2.4))
	var hp: float = boss.hp
	boss.shield = 1000.0
	boss.hurt(118.0, game.hero)
	assert(boss.hp == hp)
	assert(siege.advance(0.1) and siege.snapshot().interrupt_damage == 0.0)
	boss.shield = 0.0
	boss.hurt(118.0, game.hero)
	assert(siege.advance(0.1))
	assert(is_equal_approx(siege.snapshot().interrupt_damage, 100.0))
	var remaining: float = siege.snapshot().windup
	for phase in ["paused", "draft", "day"]:
		game.phase = phase
		assert(siege.advance(100.0))
		assert(siege.snapshot().windup == remaining)
	game.phase = "night"
	boss.hurt(141.6, game.hero)
	assert(siege.advance(0.01))
	assert(siege.snapshot().phase == "exposed" and boss.armor == 0.0)
	assert(game.beacon_hp == 1200.0 and game.hero.hp == 850.0)
	assert(not siege.advance(3.99) and boss.armor == 0.0)
	assert(not siege.advance(0.02) and boss.armor == 18.0)
	assert(siege.snapshot().phase == "approach")
	assert(siege.advance(4.0) and siege.snapshot().phase == "windup")
	var locked: Vector3 = siege.snapshot().position
	assert(locked == Vector3(0, 5, 0)) # 核心更近；随后锁点保持不动。
	game.hero.position = Vector3(10, 5, 1.5)
	var soldier: BattleUnit = game.squads.squads[0].members[0]
	var outside: BattleUnit = game.squads.squads[0].members[1]
	var ranged: BattleUnit = game.squads.squads[1].members[0]
	for group: Dictionary in game.squads.squads:
		for unit: BattleUnit in group.members:
			unit.position = Vector3(12, 5, 12)
	soldier.position = locked
	ranged.position = locked
	outside.position = locked + Vector3(3.21, 0, 0)
	var shield_hp: float = soldier.hp
	var ranged_hp: float = ranged.hp
	var outside_hp: float = outside.hp
	assert(siege.advance(2.4))
	assert(siege.snapshot().phase == "approach")
	assert(game.hero.hp == 850.0 and outside.hp == outside_hp)
	assert(is_equal_approx(shield_hp - soldier.hp, 56.0))
	assert(is_equal_approx(ranged_hp - ranged.hp, 70.0))
	assert(game.beacon_hp == 1130.0 and game.recorded == 70.0)
	assert(not siege.advance(0.1) and game.beacon_hp == 1130.0)
	# 第二次锁点在门口，与核心超过3.2，不应打全图灯塔。
	boss.position = Vector3(0, 5, 12)
	game.hero.position = Vector3(0, 5, 13)
	assert(siege.advance(8.0))
	assert(siege.snapshot().position == Vector3(0, 5, 13))
	assert(siege.advance(2.4))
	assert(game.hero.hp == 780.0 and game.beacon_hp == 1130.0)
	game.hero.position = Vector3(40, 5, 40)
	assert(not siege.advance(8.0))
	assert(siege.snapshot().phase == "approach")
	# 盾卫将巨兽拦在坡道时，首领仍可锁定近处小队，不能站着失效。
	soldier.position = Vector3(0, 5, 13.4)
	assert(siege.advance(0.1))
	assert(siege.snapshot().position == soldier.position)
	shield_hp = soldier.hp
	assert(siege.advance(2.4))
	assert(is_equal_approx(shield_hp - soldier.hp, 56.0))
	assert(game.beacon_hp == 1130.0)
	soldier.position = Vector3(20, 5, 20)
	assert(not siege.advance(8.0))
	# 增援只能两批，从spawn_creature的远端南门出生，不复活后重复触发。
	boss.hp = 1600.0
	assert(not siege.advance(0.1) and game.adds.size() == 3)
	assert(not siege.advance(0.1) and game.adds.size() == 3)
	boss.hp = 800.0
	assert(not siege.advance(0.1) and game.adds.size() == 6)
	boss.hp = 2400.0
	assert(not siege.advance(0.1) and game.adds.size() == 6)
	boss.hp = 400.0
	assert(not siege.advance(0.1) and game.adds.size() == 6)
	for add in game.adds:
		assert(add.position.z >= 34.0 and add.get_meta("threat") == "runner")
	# z>16始终走原路线，不能在南方原地蓄力。
	boss.position = Vector3(0, 5, 20)
	game.hero.position = boss.position
	assert(not siege.advance(10.0))
	boss.position = Vector3(0, 5, 0)
	game.hero.position = Vector3(0, 5, 1)
	assert(siege.advance(0.1))
	boss.hurt(10000.0, game.hero)
	assert(siege.snapshot().phase == "dead")
	assert(not siege.advance(10.0) and game.adds.size() == 6)
	boss.queue_free()
	await process_frame
	assert(not siege.advance(10.0) and siege.snapshot().hp == 0.0)
	# clear不泄露灯/预警，正在破绽的活首领恢复正常护甲。
	boss = game.make_unit("monster", Vector3(0, 5, 0))
	siege.setup(game, boss)
	assert(siege.advance(8.0))
	boss.hurt(259.6, game.hero)
	assert(siege.advance(0.1) and boss.armor == 0.0)
	siege.clear()
	assert(boss.armor == 18.0)
	await process_frame
	assert(siege.get_child_count() == 0)
	# 伤害回调反伤杀死首领，也只能提交当前锁区的一次攻势。
	siege.setup(game, boss)
	assert(siege.advance(8.0))
	var counters: Dictionary = {"hits": 0}
	var reflect: Callable = func(_unit: BattleUnit, _source: BattleUnit) -> void:
		counters.hits = int(counters.hits) + 1
		boss.hurt(10000.0, game.hero)
	game.hero.damaged.connect(reflect)
	var hero_hp: float = game.hero.hp
	var beacon_hp: float = game.beacon_hp
	assert(siege.advance(2.4))
	assert(siege.snapshot().phase == "dead" and counters.hits == 1)
	assert(game.hero.hp == hero_hp - 70.0 and game.beacon_hp == beacon_hp - 70.0)
	assert(not siege.advance(10.0) and counters.hits == 1)
	game.hero.damaged.disconnect(reflect)
	game.squads.clear()
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("NIGHTFALL_SIEGE_BOSS_FIXTURE_OK real HP interrupt, frozen windup, local locked AOE, armor recovery, 2 add batches, death cleanup")
	quit()
