extends SceneTree
const Layout := preload("res://scripts/outpost_layout.gd")
const Construction := preload("res://scripts/tower_construction.gd")

class FixtureWorld extends RefCounted:
	var tower_pads: Array[Dictionary] = []

class FixtureDistricts extends RefCounted:
	var discount := 0.0
	var plots: Array[Dictionary] = [{"position": Vector3(-5, 5, -4)}, {"position": Vector3(5, 5, -4)}]
	func tower_cost(base: int) -> int:
		return ceili(float(base) * (1.0 - discount))

class FixtureGame extends Node3D:
	const TOWER_COSTS := [60, 50, 75]
	var phase := "day"
	var aim := Vector3(-8, 5, 8)
	var scrap := 90
	var sloped := false
	var reject_commit := false
	var build_requests := 0
	var built_point := Vector3.ZERO
	var construction: Node3D
	var world := FixtureWorld.new()
	var districts := FixtureDistricts.new()
	func outpost_height(point: Vector3) -> float:
		return 4.0 if sloped else Layout.terrain_height(point)
	func build_tower_at(point: Vector3) -> bool:
		build_requests += 1
		if reject_commit: return false
		var placement: Dictionary = construction.validity(point)
		if not bool(placement.valid): return false
		scrap -= int(placement.cost)
		built_point = placement.point
		var foundation := Node3D.new()
		add_child(foundation)
		world.tower_pads.append({"position": built_point, "node": foundation, "level": 1, "hp": 280.0})
		return true

var game: FixtureGame
var module: Node3D
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

func allowed(point: Vector3, message: String) -> void:
	check(bool(module.validity(point).valid), message)

func refused(point: Vector3, reason: String) -> void:
	var result: Dictionary = module.validity(point)
	check(not bool(result.valid) and String(result.reason).contains(reason), "Expected %s rejection at %s, got %s" % [reason, point, result])

func run() -> void:
	game = FixtureGame.new()
	root.add_child(game)
	module = Construction.new()
	game.construction = module
	module.setup(game)
	check(not module.active and module.ghost == null, "A new construction module must start inactive without preview allocations")
	for phase: String in ["paused", "draft", "ended"]:
		game.phase = phase
		check(not module.begin() and not module.active, "Construction must not start during %s" % phase)
	game.phase = "day"
	allowed(Vector3(-8, 0, 8), "Cursor altitude must normalize to the actual five-metre castle floor")
	check(is_equal_approx(float(module.validity(Vector3(-8, 0, 8)).point.y), 5.0), "Valid placement must return actual floor height")
	allowed(Vector3(11.6, 5, 0), "The exact 1.4m wall margin must remain usable")
	refused(Vector3(11.61, 5, 0), "城墙")
	refused(Vector3(13.01, 5, 0), "城内")
	refused(Vector3(NAN, 5, 8), "无效")
	refused(Vector3(8, INF, 8), "无效")
	refused(Vector3(8, 5, -INF), "无效")
	refused(Vector3(0, 5, 0), "核心")
	allowed(Vector3(0, 5, -4), "The exact four-metre core clearance must be usable")
	refused(Vector3(0, 5, 8), "南门通道")
	allowed(Vector3(2, 5, 8), "The authored passage boundary must retain placements outside its reserved centre")
	refused(Vector3(5, 5, -4), "城区")
	allowed(Vector3(8, 5, -4), "The exact three-metre district clearance must be usable")
	game.sloped = true
	refused(Vector3(-8, 5, 8), "平坦")
	game.sloped = false
	var foundation := Node3D.new()
	game.add_child(foundation)
	game.world.tower_pads.append({"position": Vector3(8, 5, 8), "node": foundation, "level": 0, "hp": 0.0})
	allowed(Vector3(6, 5, 8), "An optional initial empty pad must not reserve a three-metre exclusion circle")
	game.world.tower_pads[0].free_built = true
	refused(Vector3(6, 5, 8), "残基")
	check(bool(module.validity(Vector3(8, 5, 8), 0).valid), "Rebuilding the same foundation must ignore only its own pad")
	game.world.tower_pads.append({"position": Vector3(9, 5, 8), "level": 1, "hp": 280.0})
	check(not bool(module.validity(Vector3(8, 5, 8), 0).valid), "Rebuilding exclusion must still reject another nearby tower")
	game.world.tower_pads.pop_back()
	allowed(Vector3(5, 5, 8), "The exact three-metre tower clearance must be usable")
	game.world.tower_pads.clear()
	foundation.queue_free()
	game.world.tower_pads.append({"position": Vector3(8, 5, 8), "level": 1, "hp": 280.0})
	refused(Vector3(6, 5, 8), "防御塔")
	game.world.tower_pads.clear()
	game.scrap = 59
	refused(game.aim, "零件不足")
	check(int(module.snapshot().cost) == 60, "Default placement cost must use real economy")
	game.districts.discount = 0.1
	check(int(module.snapshot().cost) == 54 and bool(module.snapshot().valid), "A workshop must update live affordability immediately")
	game.districts.discount = 0.2
	check(int(module.snapshot().cost) == 48, "Two workshop levels must charge the actual 48-scrap price")
	game.districts.discount = 0.0
	game.scrap = 90
	check(module.begin() and module.active and module.ghost.visible, "Day construction must enable the reused preview")
	var ghost_id: int = module.ghost.get_instance_id()
	var ring_id: int = module.ring.get_instance_id()
	var ghost_mat_id: int = module.ghost_material.get_instance_id()
	var ring_mat_id: int = module.ring_material.get_instance_id()
	var children: int = module.ghost.get_child_count()
	for frame in 120:
		game.aim = Vector3(-8, 5, 8) if frame % 2 == 0 else Vector3(0, 5, 8)
		module.tick(1.0 / 60.0)
		check(module.ghost.get_instance_id() == ghost_id and module.ring.get_instance_id() == ring_id,
			"Repeated previews must not replace nodes")
		check(module.ghost_material.get_instance_id() == ghost_mat_id and module.ring_material.get_instance_id() == ring_mat_id,
			"Repeated previews must not create new materials")
		check(module.ghost.get_child_count() == children and module.ghost.find_children("*", "Light3D", true, false).is_empty(),
			"Placement previews must not add nodes or lights each frame")
		check(module.ghost_material.albedo_color == (Construction.VALID_COLOR if frame % 2 == 0 else Construction.INVALID_COLOR),
			"Preview validity must select the green/red material")
	game.aim = Vector3(-8, 5, 8)
	for phase: String in ["paused", "draft"]:
		game.phase = phase
		module.tick(1.0)
		check(module.active and not module.ghost.visible, "Paused/draft placement must hide while preserving build mode")
		check(not module.confirm() and game.build_requests == 0, "Paused/draft confirmation must not call construction")
	game.phase = "night"
	module.tick(0.0)
	check(module.active and module.ghost.visible, "Resuming the playable night must restore the existing preview")
	game.aim = Vector3(0, 5, 8)
	check(not bool(module.snapshot().valid) and module.snapshot().point == game.aim,
		"Snapshot must read the current cursor without waiting for tick")
	check(not module.confirm() and game.build_requests == 0 and module.active,
		"Confirmation must refuse a moved-invalid cursor despite the old green preview")
	game.aim = Vector3(-8, 5, 8)
	module.tick(0.0)
	game.scrap = 59
	check(not module.confirm() and game.build_requests == 0 and module.active,
		"Money spent after preview must be rechecked before the controller is called")
	game.scrap = 90
	game.reject_commit = true
	check(not module.confirm() and module.active and game.scrap == 90,
		"A controller refusal must retain preview mode and never spend through the display")
	game.reject_commit = false
	game.aim = Vector3(-8, 0, -8)
	check(module.confirm() and game.built_point == Vector3(-8, 5, -8),
		"Confirmation must submit the fresh normalized cursor rather than the previous tick point")
	check(game.scrap == 30 and not module.active and not module.ghost.visible,
		"Only a successful controller construction may spend and cancel preview mode")
	check(not module.confirm() and game.build_requests == 2, "Inactive confirmation must not construct twice")
	var before: Array[Dictionary] = game.world.tower_pads.duplicate(true)
	for frame in 120:
		module.snapshot()
		module.snapshot()
		check(game.scrap == 30 and game.world.tower_pads == before and game.build_requests == 2,
			"Repeated validity snapshots must not alter economy, tower state or commit count")
	game.scrap = 90
	check(module.begin() and module.ghost.get_instance_id() == ghost_id, "Re-entering construction must reuse the same preview")
	module.cancel()
	check(not module.active and not module.ghost.visible, "Explicit cancellation must hide and disable the preview")
	module.clear()
	check(module.game == null and module.ghost == null and module.ring == null and not module.active,
		"Shutdown must release preview references and construction mode")
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("TOWER_CONSTRUCTION_FIXTURE_OK checks=", checks, " margins core districts passage foundation live_cursor live_cost reuse pause cleanup")
		quit()
	else:
		print("TOWER_CONSTRUCTION_FIXTURE_FAILED checks=", checks, " failures=", failures.size())
		quit(1)
