extends SceneTree
const Layout := preload("res://scripts/outpost_layout.gd")
const Construction := preload("res://scripts/tower_construction.gd")
const Districts := preload("res://scripts/outpost_districts.gd")

class FixtureWorld extends RefCounted:
	var tower_pads: Array[Dictionary] = []

class FixtureUnit extends Node3D:
	var hp := 100.0

class FixtureSquads extends Node:
	var squads: Array[Dictionary] = []
	var health_multiplier := 1.0
	func set_health_multiplier(value: float) -> void: health_multiplier = value

class FixtureGame extends Node3D:
	const TOWER_COSTS := [60, 50, 75]
	var phase := "day"
	var aim := Vector3(-8, 5, 8)
	var scrap := 1000
	var sloped := false
	var reject_commit := false
	var build_requests := 0
	var navigation_updates := 0
	var built_point := Vector3.ZERO
	var construction: Node3D
	var districts: Node3D
	var hero := FixtureUnit.new()
	var squads := FixtureSquads.new()
	var world := FixtureWorld.new()
	func _init() -> void:
		add_child(hero)
		add_child(squads)
		hero.position = Vector3(-11, 5, 11)
	func outpost_height(point: Vector3) -> float: return 4.0 if sloped else Layout.terrain_height(point)
	func outpost_walkable(point: Vector3) -> bool: return Layout.contains_castle(point)
	func refresh_construction_navigation() -> void: navigation_updates += 1
	func damage_tower(index: int, amount: float) -> void:
		var pad: Dictionary = world.tower_pads[index]
		pad.hp = maxf(0.0, float(pad.hp) - amount)
		if float(pad.hp) <= 0.0: pad.level = 0
		refresh_construction_navigation()
	func rebuild_tower(index: int) -> bool:
		var pad: Dictionary = world.tower_pads[index]
		var placement: Dictionary = construction.validity(pad.position, index)
		if int(pad.level) > 0 or not bool(placement.valid): return false
		scrap -= int(placement.cost)
		pad.level = 1
		pad.hp = 280.0
		refresh_construction_navigation()
		return true
	func build_structure_at(point: Vector3, kind: String) -> bool:
		build_requests += 1
		if reject_commit: return false
		if kind != "tower": return bool(districts.build_at(point, kind).ok)
		var placement: Dictionary = construction.validity(point)
		if not bool(placement.valid): return false
		scrap -= int(placement.cost)
		built_point = placement.point
		world.tower_pads.append({"position": built_point, "level": 1, "hp": 280.0, "free_built": true})
		refresh_construction_navigation()
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

func allowed(point: Vector3, message: String, kind: String = "tower") -> void:
	check(bool(module.validity(point, -1, kind).valid), message)

func refused(point: Vector3, reason: String, kind: String = "tower") -> void:
	var result: Dictionary = module.validity(point, -1, kind)
	check(not bool(result.valid) and String(result.reason).contains(reason), "Expected %s rejection at %s, got %s" % [reason, point, result])

func run() -> void:
	game = FixtureGame.new()
	root.add_child(game)
	game.districts = Districts.new()
	game.districts.setup(game)
	module = Construction.new()
	game.construction = module
	module.setup(game)
	check(game.districts.plots.is_empty(), "Buildings must have no authored empty plots")
	check(not module.active and module.ghost == null, "Placement begins inactive without preview allocations")
	var tower_half: Vector2 = module.footprint("tower")
	var core_half: Vector2 = module.footprint("core")
	check(tower_half == Vector2(1.5, 1.5) and core_half == Vector2(3, 3), "Tower and core navigation must use their complete three/six-cell footprint")
	var model_tower: Vector2 = module.model_footprint("tower")
	check(model_tower.x > 1.25 and model_tower.x < 1.3, "Original upgrade-safe tower model measurement must remain available")
	check(is_equal_approx(module.model_footprint("core").x, 2.7), "Original core model measurement must remain available")
	check(module.footprint("barracks") == Vector2(2, 1.5) and module.footprint("workshop") == Vector2(1.5, 1), "Both build types expose their full grid footprint")
	for phase: String in ["paused", "draft", "ended"]:
		game.phase = phase
		check(not module.begin(), "Construction cannot begin in %s" % phase)
	game.phase = "day"
	allowed(Vector3(-8, 0, 8), "Cursor height normalizes to the castle floor")
	check(is_equal_approx(float(module.validity(Vector3(-8, 0, 8)).point.y), 5.0), "Normalized placement returns actual height")
	allowed(Vector3(11.5, 5, .5), "A complete grid footprint may touch the inner wall")
	refused(Vector3(12.5, 5, .5), "城墙")
	refused(Vector3(13.01, 5, 0), "城内")
	for point: Vector3 in [Vector3(NAN, 5, 8), Vector3(8, INF, 8), Vector3(8, 5, -INF)]: refused(point, "无效")
	refused(Vector3.ZERO, "核心")
	allowed(Vector3(4.5, 5, .5), "Core and tower grid footprints may touch")
	allowed(Vector3(4.5, 5, 4.5), "Only actual occupied core cells exclude construction")
	allowed(Vector3(0, 5, 8), "The former south passage is freely buildable")
	allowed(Vector3(-5.4, 5, -4), "Unbuilt former district plots do not reserve land")
	game.sloped = true
	refused(Vector3(-8, 5, 8), "平坦")
	game.sloped = false
	game.world.tower_pads.append({"position": Vector3(8.5, 5, 8.5), "level": 0, "hp": 0.0})
	allowed(Vector3(8.5, 5, 8.5), "An unused suggestion does not reserve a footprint")
	game.world.tower_pads[0].free_built = true
	refused(Vector3(8.5, 5, 8.5), "残基")
	check(bool(module.validity(Vector3(8.5, 5, 8.5), 0).valid), "Original-site tower rebuilding can ignore its own foundation")
	refused(Vector3(6.5, 5, 8.5), "防御塔")
	allowed(Vector3(5.5, 5, 8.5), "Adjacent tower footprints may touch without sharing a cell")
	check(module.navigation_blocks().size() == 1, "A destroyed low foundation reserves identity without blocking movement")
	game.world.tower_pads[0].level = 1
	game.world.tower_pads[0].hp = 280.0
	check(module.navigation_blocks().size() == 2, "A living tower adds its real movement block")
	game.damage_tower(0, 280.0)
	check(module.navigation_blocks().size() == 1, "Destroying a tower immediately reopens its movement footprint")
	game.hero.position = Vector3(8.5, 5, 8.5)
	var rebuild_balance: int = game.scrap
	check(not game.rebuild_tower(0) and game.scrap == rebuild_balance, "A unit standing on the traversable remains must move before reconstruction")
	game.hero.position = Vector3(-11, 5, 11)
	check(game.rebuild_tower(0) and game.scrap == rebuild_balance - 60 and module.navigation_blocks().size() == 2, "Paid original-site reconstruction restores the movement block once")
	game.world.tower_pads.clear()
	var built: Dictionary = game.districts.build_at(Vector3(5, 5, -5.5), "barracks")
	check(bool(built.ok), "A live building can be placed away from old district coordinates")
	refused(Vector3(7.5, 5, -5.5), "已有建筑")
	allowed(Vector3(8.5, 5, -5.5), "A tower may touch an actual building grid boundary")
	check(bool(module.validity(Vector3(5, 5, -5.5), -1, "barracks", 0).valid), "Ignoring a building excludes only that physical structure")
	check(module.navigation_blocks().size() == 2, "Built district contributes exactly one physical navigation block")
	check(bool(game.districts.damage(0, 600).destroyed), "Building damage can remove the live structure")
	allowed(Vector3(5.5, 5, -5.5), "Destroyed building no longer blocks new construction")
	check(module.navigation_blocks().size() == 1, "Destroyed district immediately loses its navigation block")
	refused(game.hero.position, "单位")
	game.hero.hp = 0.0
	allowed(game.hero.position, "Defeated hero is not a permanent construction exclusion")
	game.hero.hp = 100.0
	game.hero.position = Vector3(9.3, 5, 9.3)
	refused(Vector3(8.5, 5, 8.5), "单位")
	game.hero.position = Vector3(-11, 5, 11)
	var soldier := FixtureUnit.new()
	game.squads.add_child(soldier)
	soldier.position = Vector3(-8, 5, -8)
	game.squads.squads.append({"members": [soldier]})
	refused(soldier.position, "单位", "workshop")
	soldier.hp = 0.0
	allowed(soldier.position, "Dead squad member does not block a real building", "workshop")
	game.scrap = 59
	refused(game.aim, "零件不足")
	check(bool(module.snapshot().space_valid) and int(module.snapshot().cost) == 60, "Advice retains real cost deficit on usable land")
	game.scrap = 1000
	game.districts.build_at(Vector3(8.5, 5, -8), "workshop")
	check(int(module.snapshot().cost) == 54, "Workshop changes the live tower price")
	game.districts.upgrade(1)
	check(int(module.snapshot().cost) == 48, "Upgraded workshop changes the price to 48")
	game.districts.damage(1, 630)
	check(int(module.snapshot().cost) == 60, "Destroyed workshop loses its discount immediately")
	game.scrap = 1000
	check(module.begin() and module.active and module.ghost.visible, "Placement activates a reused preview")
	var ghost_id: int = module.ghost.get_instance_id()
	var ring_id: int = module.ring.get_instance_id()
	var ghost_mat_id: int = module.ghost_material.get_instance_id()
	var ring_mat_id: int = module.ring_material.get_instance_id()
	var children: int = module.ghost.get_child_count()
	var preview_id: int = module.grid_preview.get_instance_id()
	var grid_id: int = module.grid_preview.grid_node.get_instance_id()
	var fill_id: int = module.grid_preview.footprint_node.get_instance_id()
	var border_id: int = module.grid_preview.border_node.get_instance_id()
	var fill_mesh_id: int = module.grid_preview.footprint_node.mesh.get_instance_id()
	var grid_material_id: int = module.grid_preview.grid_node.material_override.get_instance_id()
	for frame in 120:
		game.aim = Vector3(-8, 5, 8) if frame % 2 == 0 else Vector3(0, 5, 0)
		module.tick(1.0 / 60.0)
		check(module.ghost.get_instance_id() == ghost_id and module.ring.get_instance_id() == ring_id, "Preview frames reuse nodes")
		check(module.ghost_material.get_instance_id() == ghost_mat_id and module.ring_material.get_instance_id() == ring_mat_id, "Preview frames reuse materials")
		check(module.ghost.get_child_count() == children and module.ghost.find_children("*", "Light3D", true, false).is_empty(), "Preview frames never allocate lights or extra models")
		check(module.grid_preview.get_instance_id() == preview_id and module.grid_preview.grid_node.get_instance_id() == grid_id and
			module.grid_preview.footprint_node.get_instance_id() == fill_id and module.grid_preview.border_node.get_instance_id() == border_id,
			"Grid frames reuse the city, fill and border nodes")
		check(module.grid_preview.footprint_node.mesh.get_instance_id() == fill_mesh_id and
			module.grid_preview.grid_node.material_override.get_instance_id() == grid_material_id and module.grid_preview.get_child_count() == 3,
			"Grid frames retain their meshes and materials without allocating additional nodes")
		check(module.ghost_material.albedo_color == (Construction.VALID_COLOR if frame % 2 == 0 else Construction.INVALID_COLOR), "Current geometry drives green/red tint")
	for structure_kind: String in ["barracks", "workshop", "tower"]:
		check(module.select_kind(structure_kind) and String(module.snapshot().kind) == structure_kind, "Selection switches to %s" % structure_kind)
		check(module.ghost.get_instance_id() == ghost_id and module.ring.get_instance_id() == ring_id and module.grid_preview.get_instance_id() == preview_id,
			"Selection switches retain the preview root and grid overlay")
	check(not module.select_kind("other"), "Unknown building cannot change construction mode")
	game.aim = Vector3(-8, 5, 8)
	for phase: String in ["paused", "draft"]:
		game.phase = phase
		module.tick(1.0)
		check(module.active and not module.ghost.visible, "Paused placement preserves selection and hides preview")
		check(not module.confirm() and game.build_requests == 0, "Paused placement cannot invoke controller payment")
	game.phase = "night"
	module.tick(0.0)
	check(module.active and module.ghost.visible, "Night restores the preview")
	game.aim = Vector3.ZERO
	check(not bool(module.snapshot().valid) and not module.confirm() and game.build_requests == 0, "Current cursor is checked again before commit")
	game.aim = Vector3(-8.5, 0, -8.5)
	game.scrap = 59
	check(not module.confirm() and game.build_requests == 0, "Current budget is checked before controller commit")
	game.scrap = 1000
	game.reject_commit = true
	check(not module.confirm() and module.active and game.scrap == 1000, "Controller refusal retains budget and selection")
	game.reject_commit = false
	check(module.confirm() and game.built_point == Vector3(-8.5, 5, -8.5), "Commit uses fresh normalized and grid-snapped cursor")
	check(game.scrap == 940 and module.active and module.ghost.visible, "Successful construction retains continuous placement mode")
	check(not module.confirm() and game.scrap == 940, "Repeated confirmation cannot build on the same occupied point")
	game.aim = Vector3(-5.5, 0, -8.5)
	check(module.confirm() and game.scrap == 880, "Second free point builds without reopening placement")
	var before: Array[Dictionary] = game.world.tower_pads.duplicate(true)
	var requests: int = game.build_requests
	for frame in 120:
		module.snapshot()
		check(game.scrap == 880 and game.world.tower_pads == before and game.build_requests == requests, "Snapshots cannot alter payments or structure state")
	module.cancel()
	check(not module.active and not module.ghost.visible and not module.grid_preview.visible, "Explicit cancellation exits continuous placement")
	module.clear()
	check(module.game == null and module.ghost == null and module.ring == null and module.grid_preview == null, "Shutdown releases preview references")
	game.queue_free()
	await process_frame
	print("TOWER_CONSTRUCTION_FIXTURE_%s checks=%d tower_half=%s core_half=%s physical_overlap continuous_kind live_budget navigation units" % ["OK" if failures.is_empty() else "FAILED", checks, tower_half, core_half])
	quit(0 if failures.is_empty() else 1)
