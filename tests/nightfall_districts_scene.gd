extends SceneTree
## Freely built districts: visible assets, actual recovery/discounts, engineering repairs and gate routes.
const Layout := preload("res://scripts/outpost_layout.gd")
var game: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	push_error(message)

func stand(point: Vector3) -> void:
	game.hero.position = point
	game.hero.position.y = game.outpost_height(point)
	game.move_goal = game.hero.position
	game.hero_path.clear()
	game.hero_keyboard_active = false

func route_home(start: Vector3) -> void:
	stand(start)
	game.plan_hero_path(Vector3(0, 5, 4))
	check(not game.hero_path.is_empty(), "A real wilderness return must have a gate-aware route")
	var cursor: Vector3 = game.hero.position
	for waypoint in game.hero_path:
		check(game.can_traverse(cursor, waypoint), "Every return segment must avoid walls and player-built footprints")
		check(game.outpost_walkable(waypoint), "Return waypoints must remain on real walkable ground")
		cursor = waypoint
	check(cursor.distance_to(Vector3(0, 5, 4)) < .1, "A free building must not prevent returning to the walkable core apron")

func construct(point: Vector3, kind: String) -> bool:
	stand(Vector3(0, 5, 3.9))
	check(game.outpost_walkable(point), "A freely chosen district site starts as ordinary walkable castle ground")
	check(game.build_district(kind), "The real controller must enter the requested building preview")
	game.aim = point
	game.aim_sample_pending = false
	var before_count: int = game.districts.plots.size()
	var before_scrap: int = game.scrap
	var built: bool = game.construction.confirm()
	check(built and game.districts.plots.size() == before_count + 1 and game.scrap == before_scrap - 60,
		"A valid free confirmation must append one building and pay sixty exactly once")
	check(game.construction.active, "Successful construction must retain continuous placement")
	game.construction.cancel()
	if not built: return false
	var plot: Dictionary = game.districts.plots[before_count]
	check((plot.position as Vector3).distance_to(point) < .01 and is_equal_approx(plot.position.y, 5.0),
		"Construction must retain the selected position on the five-metre castle")
	check((plot.ring as MeshInstance3D).visible and (plot.model as Node3D).is_visible_in_tree(),
		"The real district model and ground marker must be visible")
	var bounds: AABB = game.districts.model_bounds(plot.model)
	var size: Vector3 = bounds.size * (plot.model as Node3D).scale
	check(size.x <= 2.701 and size.z <= 2.701 and size.y <= 2.151, "District assets must preserve their tested two-point-seven-metre scale")
	check((plot.lamp as OmniLight3D).light_energy > 0.0, "Every completed district must have a real local lamp")
	check(not game.outpost_walkable(plot.position), "A real building footprint must occupy its centre for pathfinding")
	return true

func capture() -> void:
	if DisplayServer.get_name() == "headless": return
	stand(Vector3(0, 5, 1))
	game.camera.position = game.hero.position + Vector3(0, 25, 29)
	game.notice_time = 0.0
	game.phase_time = game.DAY_LENGTH
	game.world.set_night(false)
	game.world.night_mix = 0.0
	game.world.apply_lighting()
	game.hud.queue_redraw()
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build")
	check(root.get_texture().get_image().save_png("res://build/nightfall-districts-day.png") == OK, "Hidden district daylight must render")
	game.phase = "night"
	game.phase_time = game.NIGHT_LENGTH
	game.world.set_night(true)
	game.world.night_mix = 1.0
	game.world.apply_lighting()
	game.hud.queue_redraw()
	await create_timer(.4).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://build/nightfall-districts-night.png") == OK, "Hidden district night must render")

func finish() -> void:
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_DISTRICTS_SCENE_", "OK" if failures.is_empty() else "FAILED", " checks=", checks,
		" freely_placed visible_assets actual_regen discounts engineering_label three_gate_routes")
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	check(game.choose_card(0), "The actual opening choice must start a playable run")
	game.set_process(false)
	for enemy: BattleUnit in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	await process_frame
	game.phase = "day"
	game.phase_time = game.DAY_LENGTH
	game.scrap = 400
	check(game.districts.plots.is_empty(), "A new run must not contain fixed district slots")
	if not construct(Vector3(-7.3, 5, -6), "barracks") or not construct(Vector3(7.3, 5, -6), "workshop"):
		await finish()
		return
	check(game.scrap == 280 and game.districts.active_barracks().size() == 1,
		"Two actual free buildings must spend 120 and expose the single surviving producer")
	check(game.districts.tower_cost(60) == 54 and game.districts.repair_cost(20) == 18,
		"A freely placed workshop must discount the real tower and repair budgets")
	check(not game.can_traverse(Vector3(Layout.FORT_OUTER + 5, 0, 0), Vector3(0, 5, 0)), "The east wall must remain closed")
	check(not game.can_traverse(Vector3(-Layout.FORT_OUTER - 5, 0, 0), Vector3(0, 5, 0)), "The west wall must remain closed")
	check(not game.can_traverse(Vector3(0, 0, -Layout.FORT_OUTER - 5), Vector3(0, 5, 0)), "The north wall must remain closed")
	for start: Vector3 in [Vector3(-25, 0, 25), Vector3(25, 0, 25), Vector3(0, 0, 40)]: route_home(start)
	stand(Vector3(-10, 5, 9))
	game.hero.hp = game.hero.max_hp - 100.0
	var hp_before: float = game.hero.hp
	game.simulate(1.0)
	check(is_equal_approx(game.hero.hp - hp_before, 5.0 + float(game.run.stats.regen)),
		"Actual simulation must apply the freely built barracks recovery across castle ground")
	check(game.districts.guard_regen(Vector3(-10, 0, 9)) == 0.0 and game.districts.guard_regen(Vector3(0, 0, 40)) == 0.0,
		"Recovery must reject false altitude and wilderness")
	var workshop: Dictionary = game.districts.plots[1]
	stand(workshop.position + Vector3(0, 0, 2.3))
	var before: int = game.scrap
	check(game.interact() and int(workshop.level) == 2 and game.scrap == before - 80,
		"Real F beside the player-built workshop must perform its paid second-level upgrade")
	check(game.districts.tower_cost(60) == 48 and game.districts.repair_cost(20) == 16,
		"The actual upgraded workshop must immediately change real budgets")
	var barracks: Dictionary = game.districts.plots[0]
	check(game.squads.enqueue("engineer", 0).ok, "The actual free barracks must accept engineer training")
	game.squads.advance(7.0)
	check(game.squads.snapshot().count == 1 and game.squads.snapshot().alive == 3,
		"Timed engineer production must produce three actual friendly units")
	check(game.districts.damage(0, 55.0).ok and float(barracks.hp) == float(barracks.max_hp) - 55.0,
		"A district must retain actual damage and its visible durability label")
	var prior_label: String = barracks.label.text
	var squad: Dictionary = game.squads.squads[0]
	game.squads.select_all()
	game.squads.command_guard(barracks.position + Vector3(0, 0, 3))
	for slot in game.squads.MEMBERS_PER_SQUAD:
		var soldier: BattleUnit = squad.members[slot]
		soldier.position = game.squads._station(squad, slot, "guard")
		soldier.speed = 0.0
	before = game.scrap
	game.squads.advance(1.0)
	check(float(barracks.hp) == float(barracks.max_hp) and game.scrap == before - 6,
		"Three engineers must pay real workshop repair prices and cap district restoration")
	check(barracks.label.text != prior_label and str(barracks.label.text).contains("600/600"),
		"Engineering repairs must immediately refresh the real 3D district durability text")
	game.squads.cancel_selection()
	await capture()
	game.phase = "day"
	check(game.districts.damage(0, float(barracks.hp)).ok and game.districts.guard_regen(Vector3(-10, 5, 9)) == 0.0,
		"Destroyed free barracks must lose its recovery immediately")
	check(game.districts.active_barracks().is_empty(), "Destroyed barracks must leave the actual producer list")
	await finish()
