extends SceneTree
## Real viewport input, unrestricted city placement, barracks production and
## troop commands in the actual Nightfall controller and terrain.
## Graphics: --windowed --position 10000,10000 --audio-driver Dummy -- --render-test.
const Layout := preload("res://scripts/outpost_layout.gd")
const Grid := preload("res://scripts/construction_grid.gd")
const FAR := Vector3(105, 0, 95)
const STEP := 1.0 / 30.0
var game: Node3D
var checks := 0
var failures: Array[String] = []
var render_test := false
var barracks: Array[int] = []
var workshop := -1
var completed_routes := 0

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
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

func planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func ground(point: Vector3) -> Vector3:
	point.y = game.outpost_height(point)
	return point

func stand(point: Vector3) -> void:
	point = ground(point)
	game.hero.position = point
	game.move_goal = point
	game.hero_path.clear()
	game.hero_keyboard_active = false
	game.hero.moving = false
	game.hero.set_locomotion_velocity(Vector3.ZERO)

func camera_at(point: Vector3, size: float = 42.0) -> void:
	game.camera.size = size
	game.camera_follow = point + Vector3(0, 25, 29)
	game.camera.position = game.camera_follow
	game.camera.look_at(point)

func aim_at(point: Vector3) -> Vector2:
	point = ground(point)
	var screen: Vector2 = game.camera.unproject_position(point)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	root.push_input(motion, true)
	await process_frame
	game._process(0.0)
	return screen

func mouse_at(screen: Vector2, button: int, pressed: bool, shifted: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.position = screen
	event.global_position = screen
	event.button_index = button
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	event.pressed = pressed
	event.shift_pressed = shifted
	root.push_input(event, true)
	await process_frame

func click(point: Vector3, button: int = MOUSE_BUTTON_LEFT, shifted: bool = false) -> void:
	var screen: Vector2 = await aim_at(point)
	await mouse_at(screen, button, true, shifted)
	await mouse_at(screen, button, false, shifted)

func click_ui(rect: Rect2) -> void:
	var screen := rect.get_center() * root.get_visible_rect().size / Vector2(1440, 900)
	await mouse_at(screen, MOUSE_BUTTON_LEFT, true)
	await mouse_at(screen, MOUSE_BUTTON_LEFT, false)

func redraw_hud() -> void:
	game.hud.queue_redraw()
	for _frame in 3: await process_frame

func drag_rect(rect: Rect2, shifted: bool = false) -> void:
	await mouse_at(rect.position, MOUSE_BUTTON_LEFT, true, shifted)
	var motion := InputEventMouseMotion.new()
	motion.position = rect.end
	motion.global_position = rect.end
	motion.relative = rect.size
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.shift_pressed = shifted
	root.push_input(motion, true)
	await process_frame
	if render_test:
		check(game.selection_dragging and Rect2(game.selection_start, game.selection_end - game.selection_start).abs().size.length() > 8.0,
			"A real drag must expose the active selection rectangle before release")
		await capture("selection-rectangle")
	await mouse_at(rect.end, MOUSE_BUTTON_LEFT, false, shifted)

func remove_enemies() -> void:
	for enemy: BattleUnit in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()

func isolate() -> void:
	remove_enemies()
	game.contracts.status = "idle"
	game.phase_time = 10000.0
	game.beacon_hp = game.BEACON_MAX
	for item: Dictionary in game.discoveries.items:
		game.discoveries.begin_cooling(item, 9999.0)
		item.position = FAR
		item.node.position = FAR
	for cache: Dictionary in game.world.salvage:
		cache.collected = true
		cache.respawn = 9999.0
	for generator: Dictionary in game.expeditions.generators: generator.state = "complete"
	for camp: Dictionary in game.expeditions.camps: camp.state = "delivered"
	for nest: Dictionary in game.world.nests: nest.cleansed = true
	for relay: Dictionary in game.world.relays: relay.activated = true
	for pad: Dictionary in game.world.tower_pads: pad.cooldown = 9999.0

func members(kind: String = "") -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for squad: Dictionary in game.squads.squads:
		if not kind.is_empty() and String(squad.kind) != kind: continue
		for soldier: BattleUnit in squad.members:
			if is_instance_valid(soldier) and soldier.alive: result.append(soldier)
	return result

func training_rows() -> Array:
	return game.squads.snapshot().get("queues", [])

func advance(seconds: float) -> void:
	var remaining := seconds
	while remaining > .00001:
		var elapsed := minf(STEP, remaining)
		game.squads.advance(elapsed)
		remaining -= elapsed

func squad_id(soldier: BattleUnit) -> int:
	for squad: Dictionary in game.squads.squads:
		if soldier in squad.members: return int(squad.id)
	return -1

func build(kind: String, point: Vector3, mouse: bool = true) -> int:
	var snapped: Vector3 = Grid.placement(point, kind).point
	# Keep the actual world click in the unobscured centre of the viewport;
	# the construction panel correctly consumes clicks within its own bounds.
	camera_at(ground(point))
	if not game.construction.active: await press(KEY_Y)
	await press({"tower": KEY_1, "barracks": KEY_2, "workshop": KEY_3}[kind])
	await aim_at(point)
	var preview: Dictionary = game.construction.snapshot()
	check(game.construction.active and String(preview.get("kind", "")) == kind,
		"Y and 1/2/3 must select the actual %s preview" % kind)
	check(bool(preview.valid) and planar(preview.point, snapped) < .06,
		"A freely chosen %s point must have a fresh legal terrain preview: %s" % [kind, preview])
	var balance: int = game.scrap
	var before: int = game.world.tower_pads.size() if kind == "tower" else game.districts.plots.size()
	if mouse: await click(point)
	else: await press(KEY_F)
	var after: int = game.world.tower_pads.size() if kind == "tower" else game.districts.plots.size()
	check(after == before + 1 and game.scrap == balance - int(preview.cost),
		"One real confirmation must create one %s and debit the displayed live fee" % kind)
	check(game.construction.active, "Successful construction must retain continuous placement")
	if after != before + 1: return -1
	var placed: Dictionary = game.world.tower_pads[before] if kind == "tower" else game.districts.plots[before]
	check(planar(placed.position, snapped) < .06 and absf(placed.position.y - Layout.FORT_HEIGHT) < .001,
		"A real %s must remain at the grid-snapped cursor on the city floor" % kind)
	return before

func capture(state: String, night: bool = false) -> void:
	if not render_test: return
	if DisplayServer.get_name() == "headless":
		check(false, "Render validation requires an actual graphics driver")
		return
	game.world.night_mix = 1.0 if night else 0.0
	game.world.set_night(night)
	game.world.apply_lighting()
	game.notice_time = 0.0
	game.hud.queue_redraw()
	for _frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var output := "res://build/nightfall-rts-%s.png" % state
	check(root.get_texture().get_image().save_png(output) == OK, "Save actual RTS %s frame" % state)
	print("RTS_PRODUCTION_FRAME ", ProjectSettings.globalize_path(output))

func construction_and_economy() -> void:
	check(game.world.tower_pads.size() == 2 and game.tower_count() == 2,
		"The production opening must contain only its two real towers")
	check(game.districts.plots.is_empty(), "New cities must not reserve two hardcoded district plots")
	# Deliberately build in the old south passage and at arbitrary city
	# positions, while retaining collisions against complete grid footprints.
	var near_core := Vector3(-4.5, 5, -.5)
	var corridor := Vector3(.5, 5, 7.5)
	await build("tower", near_core, false)
	await build("tower", corridor)
	barracks.append(await build("barracks", Vector3(-7, 5, -7.5)))
	barracks.append(await build("barracks", Vector3(7, 5, -7.5), false))
	workshop = await build("workshop", Vector3(-7.5, 5, 1.0))
	check(game.districts.plots.size() == 3 and game.districts.active_barracks().size() == 2,
		"Free construction must support three buildings and two independent barracks")
	if workshop >= 0:
		var plot: Dictionary = game.districts.plots[workshop]
		check(is_equal_approx(float(plot.hp), 450.0), "A new workshop must have 450 real durability")
		await press(KEY_ESCAPE)
		stand(plot.position + Vector3(0, 0, 2.3))
		var balance: int = game.scrap
		await press(KEY_F)
		check(int(plot.level) == 2 and game.scrap == balance - 80 and is_equal_approx(float(plot.max_hp), 630.0),
			"F at a real workshop must upgrade once for 80 and add 180 maximum durability")
		check(game.districts.tower_cost(60) == 48, "A second-level workshop must apply the actual bounded 20% tower discount")
	for index: int in barracks:
		if index >= 0:
			check(is_equal_approx(float(game.districts.plots[index].hp), 600.0), "A barracks must start at 600 durability")
	if not game.construction.active: await press(KEY_Y)
	await press(KEY_2)
	await aim_at(Vector3(7, 5, -7.5))
	var balance: int = game.scrap
	var plots: int = game.districts.plots.size()
	check(not bool(game.construction.snapshot().space_valid), "Real overlapping building footprints must remain forbidden")
	await press(KEY_F)
	await click(Vector3(7, 5, -7.5))
	check(game.scrap == balance and game.districts.plots.size() == plots,
		"Failed F and mouse placement must neither charge nor create a duplicate building")
	var towers: int = game.world.tower_pads.size()
	for index in 3:
		await click_ui(game.hud.construction_kind_rect(index))
		check(String(game.construction.kind) == ["tower", "barracks", "workshop"][index],
			"The actual construction type button must select its displayed structure")
		check(game.scrap == balance and game.world.tower_pads.size() == towers and game.districts.plots.size() == plots,
			"Construction type-button clicks must not leak through into world placement or payments")
		check(not game.selection_dragging and game.hero_path.is_empty(), "Construction panel clicks must not begin a world selection or move")
	check(game.hud.font.get_string_size("鼠标选址 · 左键/F建造 · 右键/Esc/Y退出", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x <= 548,
		"The Chinese construction controls must fit inside their visible panel")
	await capture("construction-panel")
	await click(Vector3(8, 5, -8), MOUSE_BUTTON_RIGHT)
	check(not game.construction.active and game.hero_path.is_empty(), "Right-click must leave building mode before issuing any unit or hero command")

func hud_training_buttons() -> void:
	var balance: int = game.scrap
	var towers: int = game.world.tower_pads.size()
	var plots: int = game.districts.plots.size()
	for index in 3:
		await click_ui(game.hud.training_kind_rect(index))
	check(game.scrap == balance - 215 and members().is_empty(),
		"All three actual HUD training buttons must enqueue and charge their displayed troop fees")
	check(game.world.tower_pads.size() == towers and game.districts.plots.size() == plots and not game.selection_dragging,
		"Production button clicks must not construct, select or move units underneath the HUD")
	await redraw_hud()
	check(game.hud.training_cancel_buttons.size() == 3, "Every displayed training order must expose a real cancellation button")
	await capture("training-panel")
	for _order in 3:
		await redraw_hud()
		if game.hud.training_cancel_buttons.is_empty():
			check(false, "The next unfinished HUD order must remain cancellable")
			break
		var button: Dictionary = game.hud.training_cancel_buttons[0]
		await click_ui(button.rect)
	check(game.scrap == balance and members().is_empty(), "Actual HUD cancellation buttons must refund every unfinished order once")
	check(game.hud.font.get_string_size("点选/框选 · Shift追加 · 右键指挥 · O驻守", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x <= 344,
		"The Chinese troop instructions must fit inside their visible panel")
	await click_ui(Rect2(1071, 689, 200, 20))
	check(not game.selection_dragging and game.scrap == balance, "Passive troop-panel text must consume world clicks without spending")
	check(not Rect2(190, 746, 840, 129).intersects(game.hud.GROWTH_PANEL_RECT),
		"The skill panel and growth panel must have separate visible bounds")
	for index in 6:
		check(game.squads.enqueue(["shield", "ranged", "engineer"][index % 3], barracks[index % 2]).ok,
			"Independent barracks must retain more unfinished orders than fit on one HUD page")
	await redraw_hud()
	await click_ui(game.hud.training_page_rect(1))
	await redraw_hud()
	check(game.hud.training_page == 1 and game.hud.training_cancel_buttons.size() == 3,
		"The real next-page button must expose the next three exact unfinished orders")
	if not game.hud.training_cancel_buttons.is_empty():
		var page_button: Dictionary = game.hud.training_cancel_buttons[0]
		var id: int = page_button.barracks
		var order_index: int = page_button.queue_index
		var expected: Array = game.squads.training_queues[id].duplicate(true)
		var refund: int = expected[order_index].cost
		expected.remove_at(order_index)
		var current_balance: int = game.scrap
		await click_ui(page_button.rect)
		check(game.scrap == current_balance + refund and game.squads.training_queues[id] == expected,
			"A second-page cancellation must remove and refund only its displayed barracks/queue order")
		check(not game.selection_dragging and members().is_empty(), "Training page controls must never leak into world selection or spawn troops")
	await click_ui(game.hud.training_page_rect(-1))
	await redraw_hud()
	check(game.hud.training_page == 0, "The real previous-page button must return to the current first orders")
	for id: int in barracks:
		while not game.squads.training_queues.get(id, []).is_empty():
			check(game.squads.cancel_training(id, 0).ok, "Pagination cleanup must cancel each remaining paid order once")
	check(game.scrap == balance and members().is_empty(), "All paginated unfinished orders must refund their exact original balance")

func queues_and_freezing() -> void:
	if barracks.size() != 2 or barracks[0] < 0 or barracks[1] < 0: return
	stand(game.districts.plots[barracks[0]].position + Vector3(2.3, 0, 0))
	var balance: int = game.scrap
	await press(KEY_U)
	await press(KEY_I)
	await press(KEY_N)
	check(game.scrap == balance - 215 and members().is_empty(),
		"U/I/N must charge shield 70, ranged 80 and engineer 65 exactly once without instant soldiers")
	check(not training_rows().is_empty(), "Real queued orders must be visible in the production snapshot")
	var before: Array = training_rows().duplicate(true)
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "Escape outside a selection must retain the normal pause operation")
	var paused_balance: int = game.scrap
	await press(KEY_U)
	check(not game.squads.cancel_training(barracks[0], 0).ok and game.scrap == paused_balance,
		"Paused production inputs and cancellation must leave paid queues and funds unchanged")
	advance(20.0)
	check(training_rows() == before and members().is_empty(), "Paused training must freeze every queue and cannot create troops")
	await press(KEY_ESCAPE)
	game.phase = "draft"
	advance(20.0)
	check(training_rows() == before and members().is_empty(), "Card selection must freeze production just like pause")
	game.phase = "day"
	advance(5.9)
	check(members().is_empty(), "Two parallel shield orders must not finish before six seconds")
	advance(.15)
	check(members("shield").size() == 3 and members().size() == 3,
		"A real shield order must finish its three-person group at six seconds")
	advance(2.05)
	check(members("ranged").size() == 3 and members("engineer").is_empty(),
		"The independent second barracks must finish its ranged order at eight seconds while engineering continues")
	advance(5.05)
	check(members("engineer").size() == 3 and game.squads.squads.size() == 3,
		"Paid production must complete an engineer group and allow more than two squads")
	await press(KEY_U)
	advance(6.05)
	check(members("shield").size() == 6 and game.squads.squads.size() == 4,
		"Continued production must add another paid group beyond the previous two-squad cap")
	for soldier: BattleUnit in members():
		check(game.outpost_walkable(soldier.position) and absf(soldier.position.y - game.outpost_height(soldier.position)) < .001,
			"Trained soldiers must spawn on actual walkable ground outside their barracks footprint")
	balance = game.scrap
	check(game.squads.enqueue("ranged", barracks[1]).ok and game.scrap == balance - 80,
		"Direct production must use the same real ranged payment as the input path")
	advance(1.0)
	check(game.squads.cancel_training(barracks[1], 0).ok and game.scrap == balance,
		"Canceling an unfinished paid order must refund its full fee once")
	check(not game.squads.cancel_training(barracks[1], 0).ok and game.scrap == balance,
		"A repeated cancellation must not manufacture a second refund")
	var alive: int = members().size()
	check(game.squads.enqueue("shield", barracks[1]).ok and game.squads.enqueue("engineer", barracks[1]).ok,
		"The second barracks must accept two independently paid unfinished orders")
	check(game.scrap == balance - 135, "Two new queued orders must debit their full 135 fee")
	game.districts.damage(barracks[1], 99999.0)
	advance(.1)
	check(game.scrap == balance and members().size() == alive,
		"A destroyed barracks must refund every unfinished order once without spawning or erasing existing troops")
	advance(.1)
	check(game.scrap == balance, "Repeated updates of a destroyed barracks must not repeat refunds")
	check(not game.squads.enqueue("shield", barracks[1]).ok and game.scrap == balance,
		"A destroyed barracks cannot train or charge another group")
	stand(FAR)
	await press(KEY_U)
	check(game.scrap == balance - 70, "Global production controls must remain usable while the hero explores away from the city")
	await press(KEY_TAB)
	await capture("training-selected")
	await press(KEY_ESCAPE)

func selection_and_commands() -> void:
	var soldiers: Array[BattleUnit] = members()
	if soldiers.size() < 2:
		check(false, "Selection regression requires the paid production groups")
		return
	game.squads.cancel_selection()
	stand(FAR)
	camera_at(Vector3(0, 5, 0))
	var first: BattleUnit = soldiers[1]
	var second: BattleUnit = soldiers.back()
	# Place the two live members in separate legal city positions so selection
	# proves identity and additive input, independently of spawn formations.
	first.position = ground(Vector3(-4.5, 5, -4.5))
	second.position = ground(Vector3(4.5, 5, -4.5))
	await click(first.position)
	check(game.squads.selected_count() == 1 and squad_id(first) in game.squads.selected_ids,
		"A real left click must select the paid formation under the cursor")
	await click(second.position, MOUSE_BUTTON_LEFT, true)
	check(game.squads.selected_count() == 2 and squad_id(second) in game.squads.selected_ids,
		"Shift-left-click must add another formation without dropping the first")
	var hero_before: Vector3 = game.hero.position
	await click(Vector3(6, 5, -2), MOUSE_BUTTON_RIGHT)
	advance(1.0)
	check(game.hero.position == hero_before and game.hero_path.is_empty(),
		"Right-click with selected troops must command them while preserving the hero's exploration position")
	check(planar(first.position, Vector3(-4.5, 5, -4.5)) > .2,
		"The real selected-troop move input must produce actual soldier displacement")
	await press(KEY_ESCAPE)
	check(game.phase == "day" and game.squads.selected_count() == 0,
		"Escape must clear selected troops before pausing active play")
	await click(Vector3(25, 0, 32), MOUSE_BUTTON_RIGHT)
	check(not game.hero_path.is_empty(), "Right-click without troop selection must still plan the hero's route")
	game.hero_path.clear()
	var a: Vector2 = game.camera.unproject_position(first.position)
	var b: Vector2 = game.camera.unproject_position(second.position)
	var corner := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(35, 45)
	var end := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(35, 45)
	await drag_rect(Rect2(corner, end - corner))
	check(game.squads.selected_count() >= 2, "Real mouse dragging must select soldiers inside the on-screen rectangle")
	await press(KEY_TAB)
	check(game.squads.selected_count() == game.squads.squads.size(), "Tab must select every currently living trained formation")
	await aim_at(Vector3(0, 5, 11))
	await press(KEY_O)
	advance(.1)
	check(game.squads.selected_count() == game.squads.squads.size(), "A guard order must retain the selected army")
	await capture("three-roles-selected", true)
	game.squads.cancel_selection()
	game.squads.select_at(first.position)
	first.position = ground(Vector3(8, 5, -3))
	var destination := Vector3(28, 0, 32)
	check(game.squads.command_move(destination).ok, "A selected shield must accept an outside-city move order")
	game.squads.on_night()
	game.squads.on_day()
	check(String(game.squads.squads[squad_id(first)].order) == "move",
		"A deliberate RTS move order must survive normal day/night station changes")
	travel_soldier(first, destination, true)
	check(game.squads.command_move(Vector3(9, 5, -3)).ok, "A selected soldier must accept a return into the city")
	travel_soldier(first, Vector3(9, 5, -3), true)
	var dead_id: int = squad_id(first)
	first.hurt(99999.0, null)
	advance(.1)
	check(dead_id in game.squads.selected_ids and game.squads.selected_count() == 1,
		"One casualty must retain command selection for surviving members of its formation")
	for soldier: BattleUnit in game.squads.squads[dead_id].members:
		if is_instance_valid(soldier) and soldier.alive: soldier.hurt(99999.0, null)
	advance(.1)
	check(not dead_id in game.squads.selected_ids and game.squads.selected_count() == 0,
		"An actually defeated formation must immediately leave command selection")
	await process_frame
	check(not is_instance_valid(first), "Soldier death must free its model across frames")

func travel_soldier(soldier: BattleUnit, destination: Vector3, require_ramp: bool) -> void:
	var reached := false
	var visited_ramp := false
	for _frame in 1800:
		if not is_instance_valid(soldier) or not soldier.alive: break
		var before: Vector3 = soldier.position
		game.squads.advance(STEP)
		check(game.can_traverse(before, soldier.position) and game.outpost_walkable(soldier.position),
			"Troop routes must continuously respect castle walls and dynamic building footprints")
		check(absf(soldier.position.y - game.outpost_height(soldier.position)) < .001,
			"Troop route movement must remain attached to real raised terrain")
		if soldier.position.z > Layout.RAMP_WALL_START and soldier.position.z < Layout.RAMP_WALL_END and absf(soldier.position.x) < Layout.RAMP_INNER_HALF:
			visited_ramp = true
		if planar(soldier.position, destination) < 1.2:
			reached = true
			break
	check(reached and (visited_ramp or not require_ramp),
		"Actual troops must reach %s through the sole southern ramp; end=%s" % [destination, soldier.position])
	if reached: completed_routes += 1

func attacks_and_engineering() -> void:
	remove_enemies()
	game.phase = "night"
	stand(FAR)
	var archers: Array[BattleUnit] = members("ranged")
	if archers.is_empty(): return
	var archer: BattleUnit = archers[0]
	archer.position = ground(Vector3(7, 5, 4))
	game.squads.cancel_selection()
	game.squads.select_at(archer.position)
	var enemy: BattleUnit = game.spawn_creature(true, "stalker")
	enemy.position = ground(Vector3(10, 5, 4))
	enemy.max_hp = 10000.0
	enemy.hp = enemy.max_hp
	enemy.armor = 0.0
	enemy.speed = 0.0
	var hp: float = enemy.hp
	var head_screen: Vector2 = game.camera.unproject_position(enemy.position + Vector3(0, 1.3, 0))
	await mouse_at(head_screen, MOUSE_BUTTON_RIGHT, true)
	await mouse_at(head_screen, MOUSE_BUTTON_RIGHT, false)
	advance(2.0)
	check(enemy.hp < hp, "Right-clicking a live monster with a selected archer must cause real timed damage")
	var chosen: Dictionary = game.choose_enemy_target(enemy)
	check(String(chosen.kind) == "squad", "A normal monster must recognize the nearer freely commanded soldier as its target")
	var army_hp := 0.0
	for soldier: BattleUnit in members(): army_hp += soldier.hp
	var hero_hp: float = game.hero.hp
	var beacon_hp: float = game.beacon_hp
	enemy.attack_range = 8.0
	enemy.attack_timer = 0.0
	game.update_creature(enemy, .01)
	enemy.tick(.6)
	game.update_creature(enemy, .6)
	var after_hp := 0.0
	for soldier: BattleUnit in members(): after_hp += soldier.hp
	check(after_hp < army_hp and game.hero.hp == hero_hp and game.beacon_hp == beacon_hp,
		"An actual normal-monster windup must hurt its selected soldier instead of the distant hero or core")
	remove_enemies()
	game.squads.cancel_selection()
	if workshop >= 0:
		var plot: Dictionary = game.districts.plots[workshop]
		var attacker: BattleUnit = game.spawn_creature(true, "stalker")
		attacker.position = ground(plot.position + Vector3(0, 0, 2.4))
		attacker.attack_range = 3.0
		attacker.speed = 0.0
		attacker.attack_timer = 0.0
		var target: Dictionary = game.choose_enemy_target(attacker)
		check(String(target.kind) == "district" and int(target.index) == workshop,
			"A freely constructed workshop must compete in the real closest-target selector")
		hp = plot.hp
		game.update_creature(attacker, .01)
		attacker.tick(.6)
		game.update_creature(attacker, .6)
		check(float(plot.hp) < hp, "A real monster windup must damage the actual dynamic workshop")
		remove_enemies()
		var engineers: Array[BattleUnit] = members("engineer")
		if not engineers.is_empty():
			var engineer: BattleUnit = engineers[0]
			engineer.position = ground(plot.position + Vector3(0, 0, 2.3))
			game.squads.select_at(engineer.position)
			check(game.squads.command_guard(engineer.position).ok, "The engineering group must accept the same guard command")
			game.districts.damage(workshop, 100.0)
			hp = plot.hp
			var balance: int = game.scrap
			advance(3.0)
			check(float(plot.hp) > hp and float(plot.hp) <= float(plot.max_hp) and game.scrap < balance,
				"A nearby engineer must perform bounded real repairs and debit its announced repair fee")
			game.scrap = 0
			game.districts.damage(workshop, 60.0)
			hp = plot.hp
			advance(3.0)
			check(float(plot.hp) == hp and game.scrap == 0, "An unaffordable engineer repair must neither heal nor make the balance negative")
			game.scrap = balance
			game.phase = "paused"
			hp = plot.hp
			var position: Vector3 = engineer.position
			advance(20.0)
			check(float(plot.hp) == hp and engineer.position == position, "Pause must freeze engineering repair and troop movement")
			game.phase = "night"
			game.districts.damage(workshop, 99999.0)
			balance = game.scrap
			advance(3.0)
			check(int(plot.level) == 0 and float(plot.hp) == 0.0 and game.scrap == balance,
				"Engineering support cannot repair a destroyed building back to life or charge for it")

func fresh_run() -> void:
	await game.prepare_shutdown()
	game.phase = "ended"
	await press(KEY_ENTER)
	for _frame in 6: await process_frame
	game = current_scene as Node3D
	game.set_process(false)
	game.world.set_process(false)
	check(game.phase == "draft" and game.scrap == 90 and game.world.tower_pads.size() == 2,
		"The actual Enter new-run input must restore the opening draft, budget and two real towers")
	check(game.districts.plots.is_empty() and game.squads.squads.is_empty() and training_rows().is_empty(),
		"A new run must discard dynamic districts, trained groups and all pending production")
	check(game.squads.selected_count() == 0 and not game.construction.active,
		"A new run must also reset army selection and continuous build mode")

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	await press(KEY_1)
	check(game.phase == "night", "The real opening card must still enter the first production night")
	game.phase = "day"
	game.scrap = 10000
	isolate()
	stand(Vector3(0, 5, 3.1))
	camera_at(Vector3(0, 5, 0))
	await construction_and_economy()
	await hud_training_buttons()
	await queues_and_freezing()
	await selection_and_commands()
	await attacks_and_engineering()
	await fresh_run()
	await finish()

func finish() -> void:
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_RTS_CONSTRUCTION_TROOPS_", "OK" if failures.is_empty() else "FAILED",
		" checks=", checks, " completed_routes=", completed_routes, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
