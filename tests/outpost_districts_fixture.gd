extends SceneTree
const Layout := preload("res://scripts/outpost_layout.gd")
const Districts := preload("res://scripts/outpost_districts.gd")
const Construction := preload("res://scripts/tower_construction.gd")

class FixtureWorld extends RefCounted:
	var tower_pads: Array[Dictionary] = []

class FixtureSquads extends Node:
	var squads: Array[Dictionary] = []
	var health_multiplier := 1.0
	var refreshes := 0
	func set_health_multiplier(value: float) -> void: health_multiplier = value
	func refresh_barracks() -> void: refreshes += 1

class FixtureGame extends Node3D:
	const TOWER_COSTS := [60, 50, 75]
	var phase := "day"
	var scrap := 5000
	var aim := Vector3(8, 5, 8)
	var hero := Node3D.new()
	var squads := FixtureSquads.new()
	var world := FixtureWorld.new()
	var districts: Node3D
	var construction: Node3D
	var navigation_updates := 0
	func _init() -> void:
		add_child(hero)
		add_child(squads)
		hero.position = Vector3(30, 0, 30)
	func outpost_height(point: Vector3) -> float: return Layout.terrain_height(point)
	func outpost_walkable(point: Vector3) -> bool: return Layout.contains_castle(point)
	func refresh_construction_navigation() -> void: navigation_updates += 1
	func build_structure_at(point: Vector3, kind: String) -> bool: return bool(districts.build_at(point, kind).ok)

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	push_error(message)

func run() -> void:
	var game := FixtureGame.new()
	root.add_child(game)
	game.districts = Districts.new()
	game.districts.setup(game)
	game.construction = Construction.new()
	game.construction.setup(game)
	var districts: Node3D = game.districts
	check(districts.plots.is_empty() and districts.snapshots().is_empty(), "No fixed construction slots are allocated")
	check(districts.tower_cost(60) == 60 and districts.repair_cost(20) == 20, "Unbuilt city does not grant discounts")
	check(districts.guard_regen(Vector3(0, 5, 6)) == 0.0 and districts.squad_health_multiplier() == 1.0, "Unbuilt city does not grant regeneration or unit health")
	check(not bool(districts.choose(-1, "barracks").ok) and not bool(districts.upgrade(0).ok), "Invalid stable ids refuse changes")
	check(not bool(districts.build_at(Vector3(-8, 5, -8), "other").ok), "Unsupported building types refuse changes")
	for phase: String in ["paused", "draft", "ended"]:
		game.phase = phase
		check(not bool(districts.build_at(Vector3(-8, 5, -8), "barracks").ok), "No buildings can be paid during %s" % phase)
		check(game.scrap == 5000 and districts.plots.is_empty(), "Rejected phase leaves economy and building list intact")
	game.phase = "night"
	game.scrap = 59
	check(not bool(districts.build_at(Vector3(-8, 5, -8), "barracks").ok) and game.scrap == 59 and districts.plots.is_empty(), "Unaffordable construction does not create a plot")
	game.scrap = 5000
	var paid: Dictionary = districts.build_at(Vector3(-8, 0, -8), "barracks")
	check(bool(paid.ok) and paid.cost == 60 and game.scrap == 4940, "Remote nighttime building pays exactly once")
	check(districts.plots.size() == 1 and districts.plots[0].position == Vector3(-8, 5, -8), "Building keeps the freely selected floor position")
	check(districts.plots[0].hp == 600.0 and districts.plots[0].max_hp == 600.0, "Barracks has real 600 health")
	check(game.navigation_updates == 1 and game.squads.refreshes == 1, "Building refreshes actual navigation and barracks training")
	check(not bool(districts.build_at(Vector3(-8, 5, -8), "workshop").ok) and game.scrap == 4940, "Repeated placement cannot double-spend or change a live building")
	check(not bool(districts.choose(0, "workshop").ok), "Compatibility chooser cannot replace a live building")
	check(districts.guard_regen(Vector3(0, 5, 6)) == 3.0 and is_equal_approx(districts.squad_health_multiplier(), 1.2), "Only live barracks grants actual benefits")
	check(is_equal_approx(game.squads.health_multiplier, 1.2), "Barracks updates recruited units immediately")
	check(districts.guard_regen(Vector3(0, 0, 6)) == 0.0 and districts.guard_regen(Vector3(18, 5, 0)) == 0.0, "Regeneration applies only on actual city floor")
	var bounds: AABB = districts.model_bounds(districts.plots[0].model)
	var factor: float = (districts.plots[0].model as Node3D).scale.x
	var half: Vector2 = districts.footprint("barracks")
	check(half.distance_to(Vector2(bounds.size.x, bounds.size.z) * factor * .5) < .001, "Placement footprint matches the displayed scaled model")
	game.scrap = 79
	check(not bool(districts.upgrade(0).ok) and game.scrap == 79, "Upgrade rechecks the real balance")
	game.scrap = 4940
	check(bool(districts.damage(0, 40).ok) and districts.plots[0].hp == 560, "Nonfatal real damage lowers building health")
	check(bool(districts.upgrade(0).ok) and game.scrap == 4860 and districts.plots[0].level == 2 and districts.plots[0].hp == 780, "Remote nighttime upgrade pays 80 and restores upgraded health")
	check(not bool(districts.upgrade(0).ok) and game.scrap == 4860, "Level two building cannot pay for another upgrade")
	check(districts.guard_regen(Vector3(0, 5, 6)) == 6.0 and is_equal_approx(districts.squad_health_multiplier(), 1.4), "Level two barracks supplies level two benefits")
	for amount: float in [0.0, -20.0, INF, NAN]:
		check(not bool(districts.damage(0, amount).ok) and districts.plots[0].hp == 780, "Invalid damage does not affect building health")
	game.phase = "paused"
	check(not bool(districts.damage(0, 100).ok) and districts.plots[0].hp == 780, "Paused simulation cannot damage a building")
	game.phase = "day"
	var nav_before: int = game.navigation_updates
	var refresh_before: int = game.squads.refreshes
	var destroyed: Dictionary = districts.damage(0, 900)
	check(bool(destroyed.destroyed) and destroyed.damage == 780 and districts.plots[0].level == 0 and districts.plots[0].hp == 0, "Lethal damage records actual dealt health and stable destroyed state")
	check(game.navigation_updates == nav_before + 1 and game.squads.refreshes == refresh_before + 1, "Destruction invalidates navigation and refunds destroyed-barracks queues immediately")
	check(districts.guard_regen(Vector3(0, 5, 6)) == 0.0 and districts.squad_health_multiplier() == 1.0 and districts.active_barracks().is_empty(), "Destroyed barracks cannot grant benefits or train")
	check(game.construction.navigation_blocks().size() == 1, "Destroyed building leaves no phantom navigation collider")
	check(not bool(districts.damage(0, 100).ok) and not bool(districts.upgrade(0).ok), "Destroyed building cannot be damaged or upgraded into free resurrection")
	check(bool(districts.choose(0, "barracks").ok) and districts.plots.size() == 1 and districts.plots[0].index == 0 and districts.plots[0].id == 0, "Paid original-site rebuilding reuses stable building identity")
	check(game.scrap == 4800 and districts.plots[0].level == 1 and districts.plots[0].hp == 600, "Rebuilding costs 60 and does not restore old level-two benefits")
	for point: Vector3 in [Vector3(8, 5, -8), Vector3(8, 5, -4), Vector3(8, 5, 0)]:
		var build: Dictionary = districts.build_at(point, "workshop")
		check(bool(build.ok), "Multiple freely positioned workshops can be constructed")
		if not bool(build.ok): continue
		check(districts.plots[int(build.index)].hp == 450, "Workshop begins at 450 health")
	check(districts.plots.size() == 4, "City construction exceeds the historical two slots")
	check(districts.tower_cost(60) == 48 and districts.repair_cost(20) == 16 and districts.tower_cost(-3) == 0, "Workshop bonuses retain the real 20 percent cap")
	check(bool(districts.upgrade(1).ok) and districts.plots[1].hp == 630, "Workshop upgrade adds exactly 180 health")
	check(districts.tower_cost(75) == 60, "Additional workshop levels do not break the bounded economy")
	var balance: int = game.scrap
	districts.damage(1, 630)
	districts.damage(2, 450)
	districts.damage(3, 450)
	check(districts.tower_cost(60) == 60 and game.scrap == balance, "Destroying all workshops removes discounts and does not invent refunds")
	for z: float in [-10.0, -7.0, -4.0, -1.0, 2.0, 5.0, 8.0, 11.0]:
		for x: float in [-10.0, -7.0, -4.0, -1.0, 2.0, 5.0, 8.0, 11.0]:
			if districts.active_barracks().size() >= 12: break
			var point := Vector3(x, 5, z)
			if not bool(game.construction.validity(point, -1, "barracks").valid): continue
			check(bool(districts.build_at(point, "barracks").ok), "Usable land supports another barracks without a fixed building count")
	check(districts.active_barracks().size() == 12 and districts.plots.size() > 12, "Real building state can contain twelve active barracks and destroyed sites")
	check(districts.squad_health_multiplier() == 3.0 and game.squads.health_multiplier == 3.0, "Army health benefits remain bounded despite unlimited building count")
	var snapshots: Array[Dictionary] = districts.snapshots()
	check(snapshots.size() == districts.plots.size() and int(snapshots[0].id) == 0 and snapshots[1].hp == 0.0, "City snapshot exposes stable identities and real health")
	snapshots[0].level = 0
	check(districts.plots[0].level == 1, "Snapshots cannot mutate authoritative building state")
	game.hero.position = districts.plots[0].position + Vector3(0, 0, 2.0)
	check(districts.nearest() == 0 and "升级" in districts.prompt(), "Nearby interaction selects the freely placed building")
	districts.clear()
	game.construction.clear()
	await process_frame
	check(districts.plots.is_empty() and districts.get_child_count() == 0, "Cleanup releases all dynamic buildings")
	game.queue_free()
	await process_frame
	print("OUTPOST_DISTRICTS_FIXTURE_%s checks=%d dynamic_buildings stable_rebuild real_damage training_invalidation night_remote bounded_benefits" % ["OK" if failures.is_empty() else "FAILED", checks])
	quit(0 if failures.is_empty() else 1)
