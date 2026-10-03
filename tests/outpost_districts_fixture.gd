extends SceneTree

const Districts = preload("res://scripts/outpost_districts.gd")

class FixtureGame extends Node3D:
	var phase: String = "day"
	var scrap: int = 400
	var hero: Node3D = Node3D.new()
	func _init() -> void:
		add_child(hero)
	func outpost_height(_point: Vector3) -> float:
		return 5.0
	func outpost_walkable(point: Vector3) -> bool:
		return absf(point.x) < 7.0 and absf(point.z) < 7.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: FixtureGame = FixtureGame.new()
	root.add_child(game)
	var districts: Node3D = Districts.new()
	districts.setup(game)
	assert(districts.plots.size() == 2)
	assert(districts.tower_cost(60) == 60 and districts.repair_cost(20) == 20)
	assert(districts.guard_regen(Vector3(0, 5, 0)) == 0.0)
	assert(districts.squad_health_multiplier() == 1.0)
	game.hero.position = districts.plots[0].position
	assert(districts.nearest() == 0)
	assert(not districts.choose(-1, "barracks").ok)
	assert(not districts.choose(0, "other").ok)
	assert(not districts.upgrade(0).ok)
	for phase in ["night", "paused", "draft", "ended"]:
		game.phase = phase
		assert(districts.nearest() == -1)
		assert(not districts.choose(0, "barracks").ok and game.scrap == 400)
	game.phase = "day"
	game.scrap = 59
	assert(not districts.choose(0, "barracks").ok and game.scrap == 59)
	game.scrap = 400
	var paid: Dictionary = districts.choose(0, "barracks")
	assert(paid.ok and paid.cost == 60 and game.scrap == 340)
	assert(not districts.choose(0, "workshop").ok and game.scrap == 340)
	assert(districts.guard_regen(Vector3(0, 5, 0)) == 3.0)
	assert(districts.guard_regen(Vector3(0, 0, 0)) == 0.0)
	assert(districts.guard_regen(Vector3(0, 4, 10)) == 0.0)
	assert(is_equal_approx(districts.squad_health_multiplier(), 1.2))
	game.hero.position = Vector3(0, 5, 0)
	assert(not districts.upgrade(0).ok and game.scrap == 340)
	game.hero.position = districts.plots[0].position
	game.scrap = 79
	assert(not districts.upgrade(0).ok and game.scrap == 79)
	game.scrap = 340
	assert(districts.upgrade(0).ok and game.scrap == 260)
	assert(not districts.upgrade(0).ok and game.scrap == 260)
	assert(districts.guard_regen(Vector3(0, 5, 0)) == 6.0)
	assert(is_equal_approx(districts.squad_health_multiplier(), 1.4))
	game.hero.position = districts.plots[1].position
	assert(districts.choose(1, "workshop").ok and game.scrap == 200)
	assert(districts.tower_cost(60) == 54 and districts.repair_cost(20) == 18)
	assert(districts.tower_cost(75) == 68 and districts.repair_cost(1) == 1)
	assert(districts.upgrade(1).ok and game.scrap == 120)
	assert(districts.tower_cost(60) == 48 and districts.repair_cost(20) == 16)
	assert(districts.tower_cost(75) == 60 and districts.tower_cost(-3) == 0)
	var snapshots: Array[Dictionary] = districts.snapshots()
	assert(snapshots.size() == 2 and snapshots[0].kind == "barracks")
	snapshots[0].level = 0
	assert(districts.plots[0].level == 2)
	assert("建设完成" in districts.prompt())
	# 第二座工坊不能使费用突破20%的下限。
	districts.plots[0].kind = "workshop"
	assert(districts.tower_cost(60) == 48)
	districts.clear()
	assert(districts.plots.is_empty())
	await process_frame
	assert(districts.get_child_count() == 0)
	game.queue_free()
	await process_frame
	print("OUTPOST_DISTRICTS_FIXTURE_OK paid choice, 2-level cap, phase/distance, fortress regen, bounded real costs")
	quit()
