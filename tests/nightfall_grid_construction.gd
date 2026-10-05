extends SceneTree
## One-metre construction cells through production input, payment and lifetime.
const Grid := preload("res://scripts/construction_grid.gd")
const FAR := Vector3(105, 0, 95)
var game: Node3D
var checks := 0
var failures: Array[String] = []
var render_test := false

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_size = Vector2i(1920, 1200)
	render_test = "--render-test" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 25: push_error(message)

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func stand(point: Vector3) -> void:
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.move_goal = point
	game.hero_path.clear()
	game.hero_keyboard_active = false
	game.hero.moving = false
	game.hero.set_locomotion_velocity(Vector3.ZERO)

func camera_at(point: Vector3) -> void:
	game.camera.size = 38.0
	game.camera.position = point + Vector3(0, 25, 29)
	game.camera.look_at(point)
	game.camera_follow = game.camera.position

func aim_at(point: Vector3) -> Vector2:
	point.y = game.outpost_height(point)
	var screen: Vector2 = game.camera.unproject_position(point)
	var event := InputEventMouseMotion.new()
	event.position = screen
	event.global_position = screen
	root.push_input(event, true)
	await process_frame
	game._process(0.0)
	return screen

func click(point: Vector3, button: int = MOUSE_BUTTON_LEFT) -> void:
	var screen: Vector2 = await aim_at(point)
	var event := InputEventMouseButton.new()
	event.position = screen
	event.global_position = screen
	event.button_index = button
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	event.button_mask = 0
	root.push_input(event, true)
	await process_frame

func capture(state: String, night: bool = false) -> void:
	if not render_test: return
	check(DisplayServer.get_name() != "headless", "Real grid screenshots require a graphical driver")
	if DisplayServer.get_name() == "headless": return
	game.world.night_mix = 1.0 if night else 0.0
	game.world.set_night(night)
	game.world.apply_lighting()
	game.hud.queue_redraw()
	for _frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	check(picture.get_size() == Vector2i(1920, 1200), "Grid render must retain the production 1920x1200 viewport")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	check(picture.save_png("res://build/nightfall-grid-%s.png" % state) == OK, "Save real grid " + state)

func select(kind: String, point: Vector3) -> Dictionary:
	camera_at(point)
	if not game.construction.active: await press(KEY_Y)
	await press({"tower": KEY_1, "barracks": KEY_2, "workshop": KEY_3}[kind])
	await aim_at(point)
	return game.construction.snapshot()

func verify_cells(placement: Dictionary, expected: Vector2i) -> void:
	check(placement.has_all(["anchor", "size", "cells", "rect", "inside", "cell_states"]), "Production placement must expose its complete grid result")
	if not placement.has_all(["size", "cells", "cell_states"]): return
	check(placement.size == expected and placement.cells.size() == expected.x * expected.y,
		"Occupied cells must match the actual displayed building dimensions")
	check(placement.cell_states.size() == placement.cells.size(), "Every occupied cell needs its own valid/blocked state")
	var unique: Dictionary = {}
	for state: Dictionary in placement.cell_states:
		check(state.has_all(["cell", "space_valid", "reason"]), "Each cell state must retain the occupancy reason")
		check(state.cell in placement.cells and not unique.has(state.cell), "Cell states must identify each footprint cell exactly once")
		unique[state.cell] = true
	var repeated: Dictionary = Grid.placement(placement.point, String(placement.kind))
	check(repeated.point == placement.point and repeated.anchor == placement.anchor and repeated.cells == placement.cells,
		"Snapping an already snapped production point must be idempotent")

func mixed_refusal(kind: String, point: Vector3, reason: String, image: String) -> void:
	var placement: Dictionary = await select(kind, point)
	verify_cells(placement, Grid.sizes(kind))
	check(not bool(placement.valid) and not bool(placement.space_valid) and String(placement.reason).contains(reason),
		"The actual blocked footprint must identify " + reason)
	var red := 0
	var green := 0
	for state: Dictionary in placement.get("cell_states", []):
		if bool(state.space_valid): green += 1
		else: red += 1
	check(red > 0 and green > 0, "A partly blocked footprint must show both occupied red cells and usable green cells")
	var balance: int = game.scrap
	var towers: int = game.world.tower_pads.size()
	var buildings: int = game.districts.plots.size()
	await press(KEY_F)
	await click(point)
	check(game.scrap == balance and game.world.tower_pads.size() == towers and game.districts.plots.size() == buildings,
		"Red-cell F and mouse confirmation must never pay or create a partial building")
	await capture(image)

func build(kind: String, raw: Vector3, expected_point: Vector3, keyboard: bool = false) -> int:
	var placement: Dictionary = await select(kind, raw)
	verify_cells(placement, Grid.sizes(kind))
	check(bool(placement.valid) and placement.point.distance_to(expected_point) < .035,
		"Real cursor must snap %s to its nearest complete cell footprint: %s" % [kind, placement])
	var before: int = game.world.tower_pads.size() if kind == "tower" else game.districts.plots.size()
	var balance: int = game.scrap
	if keyboard: await press(KEY_F)
	else: await click(raw)
	var after: int = game.world.tower_pads.size() if kind == "tower" else game.districts.plots.size()
	check(after == before + 1 and game.scrap == balance - int(placement.cost), "One grid confirmation must create one building and charge its displayed fee once")
	check(game.construction.active, "A grid build must preserve continuous same-type placement")
	if after != before + 1: return -1
	var placed: Dictionary = game.world.tower_pads[before] if kind == "tower" else game.districts.plots[before]
	check(placed.position.distance_to(expected_point) < .035, "Paid building must use the displayed snapped world point")
	balance = game.scrap
	await press(KEY_F)
	await click(raw)
	check(game.scrap == balance and (game.world.tower_pads.size() if kind == "tower" else game.districts.plots.size()) == after,
		"Repeated F and same-cell mouse input must not double-charge or duplicate a building")
	return before

func rebuild_with_released_occupants(index: int, soldiers: Array[BattleUnit]) -> void:
	if index < 0 or soldiers.is_empty() or game.expeditions.camps.is_empty(): return
	game.construction.cancel()
	var pad: Dictionary = game.world.tower_pads[index]
	game.damage_tower(index, float(pad.hp))
	stand(pad.position + Vector3(-2.2, 0, 0))
	var enemy: BattleUnit = game.spawn_creature(true, "stalker")
	enemy.position = pad.position
	var enemy_index: int = game.enemies.size() - 1
	var squad: Dictionary = game.squads.squads[0]
	var camp: Dictionary = game.expeditions.camps[0]
	var member: BattleUnit = soldiers[0]
	var scout: BattleUnit = camp.npc
	member.position = pad.position
	scout.position = pad.position
	# Isolate the placement authority from unrelated troop HUD iteration while
	# retaining all three dangling references until after the actual F result.
	game.hud.hide()
	enemy.queue_free()
	member.queue_free()
	scout.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(game.enemies[enemy_index]) and not is_instance_valid(squad.members[0]) and not is_instance_valid(camp.npc),
		"Released enemy, member and NPC must remain as real stale entries during the occupancy regression")
	check(bool(game.construction.validity(pad.position, index).valid), "Freed occupants must neither crash grid validation nor retain occupied cells")
	var balance: int = game.scrap
	var count: int = game.world.tower_pads.size()
	var living_member: BattleUnit = squad.members[1]
	living_member.path = PackedVector3Array([Vector3(1, 5, 1)])
	living_member.path_timer = 10.0
	await press(KEY_F)
	check(int(pad.level) == 1 and game.world.tower_pads.size() == count and game.scrap == balance - game.districts.tower_cost(60),
		"Real F reconstruction must succeed once while all freed occupant references are still present")
	check(not is_instance_valid(game.enemies[enemy_index]) and not is_instance_valid(squad.members[0]) and not is_instance_valid(camp.npc),
		"Construction success must come from safe occupant scanning rather than clearing its source lists")
	check(living_member.path.is_empty() and is_zero_approx(living_member.path_timer),
		"F reconstruction must complete real navigation refresh for living units after skipping stale entries")
	# Only after both validity and F have completed, release the stale test
	# entries so other independently tested modules can shut down normally.
	game.enemies.remove_at(enemy_index)
	squad.members[0] = null
	camp.npc = null
	game.hud.show()

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	await press(KEY_1)
	check(game.phase == "night", "The real opening card must enter production play")
	game.phase = "day"
	game.phase_time = 10000.0
	game.scrap = 10000
	for enemy: BattleUnit in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	game.contracts.status = "idle"
	for item: Dictionary in game.discoveries.items:
		item.position = FAR
		item.node.position = FAR
	for animal: Dictionary in game.wildlife.animals:
		animal.position = FAR
		animal.node.position = FAR
	stand(Vector3(-11.5, 5, 1.5))
	check(game.world.tower_pads[0].position == Vector3(5.5, 5, 10.5) and game.world.tower_pads[1].position == Vector3(-5.5, 5, 10.5),
		"Both real opening towers must align symmetrically to three-cell footprints")
	var raw := Vector3(-8.18, 5, -8.26)
	var placement: Dictionary = await select("tower", raw)
	check(placement.point == Vector3(-8.5, 5, -8.5), "Odd-sized tower footprint centres must use half-metre coordinates")
	await capture("tower-valid")
	var first: int = await build("tower", raw, Vector3(-8.5, 5, -8.5), true)
	await mixed_refusal("tower", Vector3(-6.5, 5, -8.5), "防御塔", "partial-tower")
	await build("tower", Vector3(-5.42, 5, -8.21), Vector3(-5.5, 5, -8.5))
	var a: Rect2 = Grid.placement(Vector3(-8.5, 5, -8.5), "tower").rect
	var b: Rect2 = Grid.placement(Vector3(-5.5, 5, -8.5), "tower").rect
	check(not a.intersects(b) and is_equal_approx(a.end.x, b.position.x), "Adjacent complete tower footprints may share an edge without sharing a cell")
	await mixed_refusal("tower", Vector3(12.5, 5, -7.5), "城墙", "partial-wall")
	await mixed_refusal("tower", Vector3(3.5, 5, 3.5), "核心", "partial-core")
	for kind: String in ["tower", "barracks", "workshop", "tower"]:
		placement = await select(kind, Vector3(7.18, 5, -7.14))
		verify_cells(placement, Grid.sizes(kind))
		var expected: Vector3 = {"tower": Vector3(7.5, 5, -7.5), "barracks": Vector3(7, 5, -7.5), "workshop": Vector3(7.5, 5, -7)}[kind]
		check(placement.point.distance_to(expected) < .035, "Changing 1/2/3 must recompute odd/even grid alignment")
	var barracks: int = await build("barracks", Vector3(7.18, 5, -7.14), Vector3(7, 5, -7.5))
	await capture("barracks-built")
	var workshop: int = await build("workshop", Vector3(-7.31, 5, 7.12), Vector3(-7.5, 5, 7), true)
	await capture("workshop-built")
	stand(Vector3(10.2, 5, 4.2))
	await mixed_refusal("tower", Vector3(9.5, 5, 3.5), "单位", "partial-unit")
	stand(Vector3(-11.5, 5, 1.5))
	placement = await select("tower", Vector3(2.5, 5, -8.5))
	var saved_balance: int = game.scrap
	game.scrap = 0
	placement = game.construction.snapshot()
	check(bool(placement.space_valid) and not bool(placement.valid), "Insufficient funds must leave every spatially legal cell usable")
	for state: Dictionary in placement.cell_states: check(bool(state.space_valid), "Money refusal must not paint usable grid cells as occupied")
	await press(KEY_F)
	await click(Vector3(2.5, 5, -8.5))
	check(game.scrap == 0, "Unaffordable grid input must never debit a negative balance")
	game.scrap = saved_balance
	await click(Vector3(2.5, 5, -8.5), MOUSE_BUTTON_RIGHT)
	check(not game.construction.active and game.hero_path.is_empty(), "Grid right-click cancellation must not issue a hidden hero move")
	await press(KEY_U)
	check(game.scrap == saved_balance - 70, "Grid-based barracks must retain real paid production")
	game.squads.advance(6.1)
	var soldiers: Array[BattleUnit] = []
	for squad: Dictionary in game.squads.squads:
		for soldier: BattleUnit in squad.members:
			if is_instance_valid(soldier) and soldier.alive: soldiers.append(soldier)
	check(soldiers.size() == 3, "The aligned barracks must train its original three-member shield group")
	for soldier: BattleUnit in soldiers: soldier.position = FAR
	if not soldiers.is_empty():
		soldiers[0].position = Vector3(10.2, 5, 4.2)
		await mixed_refusal("tower", Vector3(9.5, 5, 3.5), "单位", "partial-soldier")
		soldiers[0].position = FAR
	await press(KEY_ESCAPE)
	if first >= 0:
		var pad: Dictionary = game.world.tower_pads[first]
		game.damage_tower(first, float(pad.hp))
		check(game.outpost_walkable(pad.position), "Destroyed tower cells must release movement while retaining construction identity")
		check(not bool(game.construction.validity(pad.position, -1, "workshop").space_valid), "Destroyed tower cells stay reserved for paid original-site reconstruction")
		stand(pad.position)
		var balance: int = game.scrap
		await press(KEY_F)
		check(int(pad.level) == 0 and game.scrap == balance, "F cannot rebuild occupied rubble under a living hero")
		stand(pad.position + Vector3(-2.2, 0, 0))
		balance = game.scrap
		var count: int = game.world.tower_pads.size()
		await press(KEY_F)
		check(int(pad.level) == 1 and game.world.tower_pads.size() == count and game.scrap == balance - game.districts.tower_cost(60),
			"Original-site F must restore the same grid tower and charge exactly one current workshop-adjusted fee")
	stand(Vector3(-11.5, 5, 1.5))
	if barracks >= 0:
		game.districts.damage(barracks, 99999.0)
		check(bool(game.construction.validity(Vector3(7.5, 5, -7.5)).space_valid), "Destroyed barracks must release its entire former grid footprint")
		await build("tower", Vector3(7.5, 5, -7.5), Vector3(7.5, 5, -7.5))
	if workshop >= 0:
		game.districts.damage(workshop, 99999.0)
		check(bool(game.construction.validity(Vector3(-7.5, 5, 7.5)).space_valid), "Destroyed workshop must release its complete footprint")
		await build("tower", Vector3(-7.5, 5, 7.5), Vector3(-7.5, 5, 7.5))
	await rebuild_with_released_occupants(first, soldiers)
	await capture("grid-lifetime")
	await capture("grid-night", true)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_GRID_CONSTRUCTION_", "OK" if failures.is_empty() else "FAILED", " checks=", checks,
		" real_input odd_even_alignment complete_cells partial_red single_payment adjacent_towers units rubble_rebuild district_release")
	quit(0 if failures.is_empty() else 1)
