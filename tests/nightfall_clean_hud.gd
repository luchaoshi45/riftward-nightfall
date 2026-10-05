extends SceneTree
## Production clean-HUD regression with real viewport GUI dispatch. No hidden
## legacy hitboxes, automatic commands behind UI, or fixture-only train actions.
## --render-test records the default battlefield, details and urgent feedback.
const HOME := Vector3(0, 5, 3.1)
const FIELD := Rect2(340, 130, 760, 500)
const VIEW := Rect2(0, 0, 1440, 900)
const TABS := ["contract", "exploration", "army", "defense", "help"]
const TACTICS := Rect2(24, 824, 126, 36)
const MAP := Rect2(164, 824, 96, 36)
const MEMORY := Rect2(1108, 800, 104, 80)
const CLOSE := Rect2(428, 692, 112, 30)
const MINI := Rect2(1252, 106, 164, 164)
const CONSTRUCTION := Rect2(435, 642, 570, 140)
const RunSession = preload("res://scripts/run_session.gd")
const RECORDING_HUD := """extends 'res://scripts/nightfall_hud.gd'
var drawn_labels: Array[Dictionary] = []
var recording_drawer := false
func _draw() -> void:
	drawn_labels.clear()
	recording_drawer = false
	super._draw()
func box(rect: Rect2, fill: Color = Color(.022,.035,.045,.88), outline: Color = Color(\"435455\")) -> void:
	if rect == Rect2(24,112,540,622): recording_drawer = true
	if rect == Rect2(428,692,112,30): recording_drawer = false
	super.box(rect,fill,outline)
func label(value: String, point: Vector2, size_px: int, color: Color = Color(\"e7e1d3\"), latin: bool = false) -> void:
	if recording_drawer:
		var actual_font: Font = display_font if latin else font
		drawn_labels.append({\"text\":value, \"point\":point, \"font_size\":size_px,
			\"width\":actual_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x,
			\"descent\":actual_font.get_descent(size_px)})
	super.label(value,point,size_px,color,latin)
"""
var game: Node3D
var checks := 0
var failures: Array[String] = []
var render_test := false
var evidence: Dictionary = {}

func _initialize() -> void:
	render_test = "--render-test" in OS.get_cmdline_user_args()
	root.size = Vector2i(1920, 1200)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1920, 1200)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 30: push_error(message)

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)

func redraw() -> void:
	game.hud.queue_redraw()
	for frame in 3: await process_frame

func click_at(logical: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	# Push through the actual viewport so accept_event() and the controller's
	# unhandled-input stage participate in the non-penetration assertion.
	var pixel: Vector2 = logical * game.hud.get_viewport_rect().size / Vector2(1440, 900)
	var motion := InputEventMouseMotion.new()
	motion.position = pixel
	motion.global_position = pixel
	root.push_input(motion, true)
	await process_frame
	var event := InputEventMouseButton.new()
	event.position = pixel
	event.global_position = pixel
	event.button_index = button
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.button_mask = 0
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func click(rect: Rect2, button: int = MOUSE_BUTTON_LEFT) -> void:
	await click_at(rect.get_center(), button)

func remove_enemies() -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()

func stand(point: Vector3) -> void:
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.move_goal = point
	game.hero_path.clear()
	game.hero_keyboard_active = false

func clear_transient_hud() -> void:
	game.notice_time = 0.0
	game.reward_toasts.clear()
	game.beacon_alarm_time = 0.0
	game.hero_damage_flash_time = 0.0
	game.combat_milestone_time = 0.0
	game.kill_chain = 0
	game.kill_chain_time = 0.0
	game.combat.clear_transients()

func orders() -> Dictionary:
	var army: Array = []
	for squad: Dictionary in game.squads.squads:
		army.append({"id": int(squad.id), "order": String(squad.order),
			"destination": squad.destination, "target": squad.attack_target})
	return {"goal": game.move_goal, "path": game.hero_path.duplicate(), "army": army,
		"dragging": game.selection_dragging}

func finances() -> Dictionary:
	var queues: Dictionary = game.squads.training_queues.duplicate(true)
	return {"scrap": game.scrap, "pending": game.run.pending,
		"owned": game.run.owned.duplicate(true), "queues": queues,
		"countermeasure": game.countermeasure_selected, "phase": game.phase}

func assert_no_command(point: Vector2, label: String) -> void:
	var before := orders()
	await click_at(point, MOUSE_BUTTON_RIGHT)
	check(orders() == before, label + ": right-click on visible UI must never order the hero or troops")
	await click_at(point)
	check(orders() == before, label + ": left-click on visible UI must never initiate a world selection or command")

func rect_data(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func default_layout(label: String) -> void:
	await redraw()
	check(game.hud.detail_tab == "" and not game.hud.map_expanded,
		label + ": default gameplay must show no tactical drawer or expanded map")
	check(game.hud.minimap_rect() == MINI, label + ": the default minimap must retain the compact 164-pixel size")
	var visible: Array = game.hud.visible_hud_rects()
	var area := 0.0
	var rects: Array = []
	for rect: Rect2 in visible:
		check(VIEW.encloses(rect) and rect.size.x > 0.0 and rect.size.y > 0.0,
			label + ": each reported visible HUD rectangle must lie inside the logical viewport")
		check(not rect.intersects(FIELD), label + ": permanent HUD must leave the central battlefield clear")
		area += rect.get_area()
		rects.append(rect_data(rect))
	check(area / VIEW.get_area() < .25,
		label + ": conservative total permanent-UI coverage must stay below one quarter of the screen")
	check(visible.has(MINI) and visible.has(TACTICS) and visible.has(MAP) and visible.has(MEMORY),
		label + ": visible UI accounting must include the actual compact map and reachable bottom buttons")
	for obsolete in [Rect2(24,197,340,244), Rect2(1050,480,365,240), Rect2(1050,732,365,111)]:
		check(not visible.has(obsolete), label + ": old exploration, army and growth panels must not remain visible")
	evidence[label] = {"area_fraction_upper_bound": area / VIEW.get_area(), "rects": rects,
		"viewport": [game.hud.get_viewport_rect().size.x, game.hud.get_viewport_rect().size.y]}

func capture(label: String) -> void:
	if not render_test: return
	game.hud.queue_redraw()
	for frame in 6:
		await process_frame
		await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	check(picture.get_size() == root.content_scale_size and Vector2(picture.get_size()) == game.hud.get_viewport_rect().size, "Actual clean-HUD capture must use the requested content viewport size")
	check(picture.save_png("res://build/clean-hud-%s.png" % label) == OK, "Save the actual clean HUD " + label)

func api_ready() -> bool:
	var complete := true
	for method in ["toggle_details", "toggle_map", "details_tab_rect", "minimap_rect", "visible_hud_rects", "countermeasure_rect"]:
		if not game.hud.has_method(method):
			check(false, "Production HUD interface is not ready: " + method)
			complete = false
	return complete

func assert_interface() -> void:
	var constants: Dictionary = load("res://scripts/nightfall_hud.gd").get_script_constant_map()
	for name in {"DETAIL_CLOSE_RECT": CLOSE, "TACTICS_BUTTON_RECT": TACTICS,
		"MAP_BUTTON_RECT": MAP, "MEMORY_BUTTON_RECT": MEMORY, "CONSTRUCTION_PANEL_RECT": CONSTRUCTION}:
		var expected: Rect2 = {"DETAIL_CLOSE_RECT": CLOSE, "TACTICS_BUTTON_RECT": TACTICS,
			"MAP_BUTTON_RECT": MAP, "MEMORY_BUTTON_RECT": MEMORY, "CONSTRUCTION_PANEL_RECT": CONSTRUCTION}[name]
		check(constants.get(name, Rect2()) == expected, "Production HUD must expose the clickable " + name)
	for index in 5:
		check(game.hud.details_tab_rect(index) == Rect2(36 + index * 104,124,100,34),
			"Each detail tab must expose its actual new location")
	for index in 3:
		check(game.hud.training_kind_rect(index) == Rect2(44 + index * 168,230,160,32),
			"Each training choice must live inside the army drawer")
		check(game.hud.construction_kind_rect(index) == Rect2(457 + index * 175,658,166,31),
			"Each construction choice must live in its actual new conditional bar")
		check(game.hud.countermeasure_rect(index) == Rect2(44 + index * 168,280,160,62),
			"Each defensive countermeasure must expose its actual drawer button")
	check(game.hud.training_page_rect(-1) == Rect2(456,188,29,26)
		and game.hud.training_page_rect(1) == Rect2(493,188,29,26),
		"Training pagination must live beside the new army header")

func detail_text_bounds(label: String) -> void:
	await redraw()
	var labels: Array = game.hud.drawn_labels
	check(not labels.is_empty(), label + ": production drawer must actually draw its own text")
	var recorded: Array = []
	for row: Dictionary in labels:
		var point: Vector2 = row.point
		if point.y < 160: continue
		check(point.y <= 680.0 and point.y + float(row.descent) < CLOSE.position.y,
			label + ": drawer text must end before the close control: " + String(row.text))
		check(point.x >= 36.0 and point.x + float(row.width) <= 548.0,
			label + ": actual font width must fit the drawer body: " + String(row.text))
		recorded.append({"text":row.text,"baseline":[point.x,point.y],"font_size":row.font_size,"width":row.width})
	evidence["text-" + label] = recorded

func detail_navigation() -> void:
	var before := finances()
	await click(TACTICS)
	check(game.hud.detail_tab == "contract", "The default tactics button must open the contract drawer")
	for index in 5:
		if game.hud.detail_tab == TABS[index]: await click(game.hud.details_tab_rect((index + 1) % 5))
		await click(game.hud.details_tab_rect(index))
		check(game.hud.detail_tab == TABS[index] and not game.hud.map_expanded,
			"A real tab click must select exactly one %s detail view" % TABS[index])
		var visible: Array = game.hud.visible_hud_rects()
		check(not visible.has(MINI) or game.hud.minimap_rect() == MINI,
			"Opening details may keep only the compact minimap")
		await assert_no_command(Vector2(31,375), "The %s drawer body" % TABS[index])
		await detail_text_bounds(TABS[index])
		await capture("details-%s" % TABS[index])
	check(finances() == before, "Navigating/drawing the five details pages must not spend resources, issue training or change the chosen countermeasure")
	await click(game.hud.details_tab_rect(4))
	check(game.hud.detail_tab == "", "Clicking the already selected tab must fold the drawer away")
	press(KEY_F3)
	check(game.hud.detail_tab == "contract", "F3 must open the default contract drawer")
	press(KEY_F3)
	check(game.hud.detail_tab == "", "A second F3 must close the current drawer")
	await click(TACTICS)
	await click(CLOSE)
	check(game.hud.detail_tab == "", "The visible drawer close button must really close it")
	game.hud.toggle_details("exploration")
	check(game.hud.detail_tab == "exploration", "The documented detail API must select the requested single page")
	await click(MAP)
	check(game.hud.detail_tab == "" and game.hud.map_expanded and game.hud.minimap_rect().get_area() > MINI.get_area(),
		"Opening the expanded map must dismiss the old drawer")
	await assert_no_command(game.hud.minimap_rect().get_center(), "The expanded tactical map")
	await click(TACTICS)
	check(game.hud.detail_tab == "contract" and not game.hud.map_expanded,
		"Opening any details drawer must dismiss the expanded map")
	press(KEY_ESCAPE)
	check(game.hud.detail_tab == "" and game.phase == "day", "Esc must close a drawer before pausing active gameplay")
	press(KEY_ESCAPE)
	check(game.phase == "paused", "A later Esc must retain the original pause action")
	press(KEY_F3)
	check(game.phase == "paused" and game.hud.detail_tab == "contract", "F3 must remain usable while the game is paused")
	await capture("paused-details")
	press(KEY_ESCAPE)
	check(game.phase == "paused" and game.hud.detail_tab == "", "Esc must close paused details before resuming")
	press(KEY_ESCAPE)
	check(game.phase == "day", "A following Esc must resume the real paused phase")
	press(KEY_F3)
	press(KEY_F1)
	check(game.music_credits_open and game.phase == "paused", "F1 must retain the actual credits/pause behavior")
	press(KEY_F3)
	check(game.hud.detail_tab == "contract", "F3 must not toggle tactical pages through the open credits")
	press(KEY_ESCAPE)
	check(not game.music_credits_open and game.phase == "paused" and game.hud.detail_tab == "contract",
		"Esc must dismiss music credits before touching the underlying drawer or pause")
	press(KEY_ESCAPE)
	check(game.phase == "paused" and game.hud.detail_tab == "", "A later Esc must close the still-paused drawer")
	press(KEY_ESCAPE)
	check(game.phase == "day", "A final Esc must resume active play after the credits and drawer close")

func rich_exploration_page() -> void:
	var point := Vector3(45,0,45)
	game.exploration.set_waylight_count(2)
	game.hero.hp -= 120.0
	game.mana -= 100.0
	game.exploration.arm_contract_affinity(["ember_bloom"])
	game.grant_exploration_reward("余烬花",point,34,18,24,"ember_bloom")
	game.grant_exploration_reward("余烬晶簇",point,47,15,22,"memory_crystal")
	game.grant_exploration_reward("补给箱",point,78,25,32,"supply_cache")
	game.grant_exploration_reward("灯碑",point,56,22,30,"waylight")
	game.exploration.arm_contract_affinity(game.exploration.ROUTE_KINDS)
	check(game.exploration.affinity_active() and game.exploration.network_active()
		and game.exploration.speed_bonus_value() > 0.0 and game.reward_toasts.size() == 4,
		"Real exploration actions must create the full affinity/speed/network/four-reward drawer state")
	game.hud.toggle_details("exploration")
	await detail_text_bounds("exploration-full-rewards")
	var all_text := ""
	for row: Dictionary in game.hud.drawn_labels: all_text += String(row.text)
	for required in ["共鸣", "加速", "灯网", "最近收益"]:
		check(required in all_text, "The real full exploration page must draw " + required)
	await capture("details-exploration-full-rewards")
	press(KEY_ESCAPE)

func check_live_data() -> void:
	var before := finances()
	var budget: Dictionary = game.contracts.primary_budget()
	check(game.contracts.offers.size() == 3 and bool(budget.available)
		and not game.contracts.primary_travel_text(budget).is_empty()
		and not game.contracts.primary_timing_text(budget).is_empty(),
		"Contract details must have three actual offers and a readable real route/time budget")
	check(not game.exploration.route_text().is_empty() and not game.exploration.collection_reward_text().is_empty(),
		"Exploration details must retain the actual seeded route and collection reward")
	var growth: Dictionary = game.growth_snapshot()
	check(int(growth.memory.cost) == game.run.memory_cost() and int(growth.memory.balance) == game.scrap
		and not game.hud.growth_memory_text(growth).is_empty() and game.hud.growth_lines(growth).size() == 3,
		"Defense details must retain real balances, paid memory cost and the current free-build/upgrade recommendation")
	var army: Dictionary = game.squads.snapshot()
	check(int(army.count) == game.squads.squads.size(), "Army details must use the actual troop population")
	check(finances() == before, "Read-only detail data queries must not spend memory or mutate orders/choices")
	var font: Font = game.hud.font
	for value in ["日间委托", "荒原探索", "部队训练", "防线准备", "操作帮助"]:
		check(font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x <= 84.0,
			"Chinese tab text must fit the actual 100-pixel tab: " + value)
	for character in "委托探索训练防线帮助守望":
		check(font.has_char(character.unicode_at(0)), "The selected HUD font must resolve Chinese glyph " + character)

func build_barracks() -> void:
	game.scrap = 1600
	stand(HOME)
	game.hud.toggle_details("help")
	press(KEY_Y)
	await redraw()
	check(game.construction.active and game.hud.detail_tab == "", "Entering real construction must dismiss the old detail page")
	check(game.hud.visible_hud_rects().has(CONSTRUCTION), "Only active construction must report the live placement bar")
	press(KEY_F3)
	check(game.hud.detail_tab == "", "F3 must not cover the active construction preview with a drawer")
	for index in 3:
		await click(game.hud.construction_kind_rect(index))
		check(game.construction.kind == ["tower", "barracks", "workshop"][index],
			"A real placement-bar click must select the advertised structure kind")
	game.aim = Vector3(-8,5,-6)
	await click(game.hud.construction_kind_rect(1))
	var preview: Dictionary = game.construction.snapshot()
	check(bool(preview.valid), "The real barracks preview must be legal before confirmation")
	game.aim = Vector3(-8,5,-6)
	game.aim_sample_pending = false
	press(KEY_F)
	check(game.districts.plots.size() == 1 and game.districts.active_barracks().size() == 1,
		"Real F must construct the barracks used by GUI production verification")
	await assert_no_command(Vector2(444,770), "The current placement bar background")
	await capture("construction")
	press(KEY_ESCAPE)
	await redraw()
	check(not game.construction.active and game.hud.detail_tab == ""
		and not game.hud.visible_hud_rects().has(CONSTRUCTION),
		"Exiting placement must remove the bar and must not unexpectedly restore the old help page")

func queue_total() -> int:
	var result := 0
	for queue: Array in game.squads.training_queues.values(): result += queue.size()
	return result

func army_gui() -> void:
	var before := finances()
	var commands := orders()
	for index in 3:
		await click(Rect2(1071 + index * 108,551,101,30))
		await click(game.hud.training_kind_rect(index))
	check(finances() == before and orders().goal == commands.goal and orders().army == commands.army,
		"Closed army details must not retain either old or newly hidden training hitboxes")
	await click(TACTICS)
	await click(game.hud.details_tab_rect(2))
	var kinds := ["shield", "ranged", "engineer", "shield", "ranged", "engineer", "shield"]
	for index in kinds.size():
		var balance: int = game.scrap
		var total := queue_total()
		await click(game.hud.training_kind_rect(index % 3))
		check(queue_total() == total + 1 and game.scrap == balance - int(game.squads.HIRE_COST[kinds[index]]),
			"The visible %s training button must create one real queued order and debit its actual cost" % kinds[index])
	await redraw()
	check(game.hud.training_cancel_buttons.size() == 3, "Army drawing must generate real cancellation targets for its visible three rows")
	if not game.hud.training_cancel_buttons.is_empty():
		var row: Dictionary = game.hud.training_cancel_buttons[0]
		check(row.rect == Rect2(422,300,110,28), "A visible cancellation target must occupy the actual drawer row")
		var cost: int = game.squads.training_queues[int(row.barracks)][int(row.queue_index)].cost
		var balance: int = game.scrap
		var total := queue_total()
		await click(row.rect)
		check(queue_total() == total - 1 and game.scrap == balance + cost,
			"A real cancel click must refund that exact production order once")
	await click(game.hud.training_page_rect(1))
	await redraw()
	check(game.hud.training_page == 1 and game.hud.training_cancel_buttons.size() == 3,
		"The live next-page button must expose the remaining production orders")
	if not game.hud.training_cancel_buttons.is_empty():
		var row: Dictionary = game.hud.training_cancel_buttons[0]
		var cost: int = game.squads.training_queues[int(row.barracks)][int(row.queue_index)].cost
		var balance: int = game.scrap
		var total := queue_total()
		await click(row.rect)
		check(queue_total() == total - 1 and game.scrap == balance + cost,
			"A later-page cancellation must address the displayed real queue index")
	await click(game.hud.training_page_rect(-1))
	check(game.hud.training_page == 0, "The live previous-page control must return to the first page")
	var cached_cancel: Rect2 = game.hud.training_cancel_buttons[0].rect if not game.hud.training_cancel_buttons.is_empty() else Rect2()
	press(KEY_ESCAPE)
	check(game.hud.detail_tab == "", "Esc must close army details before processing troop selection")
	if cached_cancel.get_area() > 0.0:
		var balance: int = game.scrap
		var total := queue_total()
		check(game.hud.training_cancel_buttons.is_empty(), "Closing army details must immediately invalidate cached cancellation hitboxes")
		await click(cached_cancel)
		check(queue_total() == total and game.scrap == balance,
			"Clicking a formerly drawn cancellation row immediately after closing must not refund any hidden order")
	await world_command(Vector3(8,5,1), false)
	var live_queue: Array = game.squads.training_queues.values()[0]
	check(not live_queue.is_empty(), "GUI cancellations must leave actual production orders available")
	if not live_queue.is_empty(): game.squads.advance(float(live_queue[0].remaining) + .1)
	check(game.squads.squads.size() == 1, "The actual retained first order must finish into one live squad")
	var visible_before: Array = game.hud.visible_hud_rects().duplicate()
	press(KEY_TAB)
	await redraw()
	check(game.squads.selected_count() == 1, "The real Tab command must still select trained troops")
	var selection_bar := Rect2()
	for rect: Rect2 in game.hud.visible_hud_rects():
		if not visible_before.has(rect): selection_bar = rect
	check(selection_bar.get_area() > 0.0, "Selecting troops must expose a current conditional command strip")
	if selection_bar.get_area() > 0.0: await assert_no_command(selection_bar.get_center(), "The selected-squad command strip")
	await world_command(Vector3(6,5,-4), true)
	await capture("selected-squad")
	press(KEY_ESCAPE)
	check(game.squads.selected_count() == 0 and game.phase == "day",
		"Once details are closed, Esc must retain the original troop-deselection precedence")

func world_command(target: Vector3, selected: bool) -> void:
	var pixel: Vector2 = game.camera.unproject_position(target)
	var logical: Vector2 = pixel * Vector2(1440,900) / game.hud.get_viewport_rect().size
	var blocked := false
	for rect: Rect2 in game.hud.visible_hud_rects(): blocked = blocked or rect.has_point(logical)
	check(not blocked, "The positive right-click command must use actual uncovered battlefield space")
	var previous: Vector3 = game.move_goal
	await click_at(logical, MOUSE_BUTTON_RIGHT)
	if selected:
		check(game.squads.squads[0].order == game.squads.MOVE
			and game.squads.squads[0].destination.distance_to(target) < .3,
			"A real uncovered right-click must still issue a move order to the Tab-selected trained squad")
		check(game.move_goal == previous, "A selected-squad world command must not also move the hero")
	else:
		check(game.move_goal.distance_to(target) < .3 and game.move_goal != previous,
			"A real uncovered right-click without selected troops must still set the hero's reachable destination")

func defense_and_memory_gui() -> void:
	game.hud.toggle_details("defense")
	for index in 3:
		await click(game.hud.countermeasure_rect(index))
		check(game.countermeasure_selected == index,
			"A real defense-drawer button must choose the actual next-night countermeasure")
	for index in 3:
		press(KEY_7 + index)
		check(game.countermeasure_selected == index, "Existing 7/8/9 input must remain usable for the same real preparations")
	press(KEY_ESCAPE)
	game.run.grant("清爽界面生产回归")
	var pending: int = game.run.pending
	await click(MEMORY)
	check(game.phase == "draft" and game.run.pending == pending,
		"The permanent memory button must open the actual queued upgrade without claiming it early")
	press(KEY_F3)
	check(game.hud.detail_tab == "", "F3 must not open hidden tactical controls during real card selection")
	press(KEY_1)
	check(game.phase == "day" and game.run.pending == pending - 1,
		"A real card choice must consume exactly the pending upgrade opened by the memory button")

func scale_and_hit_testing() -> void:
	clear_transient_hud()
	for size in [Vector2i(1920,1200), Vector2i(1920,1080), Vector2i(1440,900)]:
		root.size = size
		root.content_scale_size = size
		await redraw()
		check(game.hud.get_viewport_rect().size == Vector2(size), "HUD input scaling must use the actual requested 16:10/16:9 viewport")
		await default_layout("scaled-%dx%d" % [size.x,size.y])
		await assert_no_command(MINI.get_center(), "The scaled compact minimap")
		await assert_no_command(Vector2(1070,820), "The scaled main bottom-bar background")
		await click(TACTICS)
		check(game.hud.detail_tab == "contract", "Scaled tactics input must hit the real button")
		await click(game.hud.details_tab_rect(4))
		check(game.hud.detail_tab == "help", "Scaled detail input must hit the selected real tab")
		await click(CLOSE)
		check(game.hud.detail_tab == "", "Scaled close input must fold the actual drawer")
	root.size = Vector2i(1920,1200)
	root.content_scale_size = root.size
	await redraw()

func urgent_feedback() -> void:
	game.start_night()
	remove_enemies()
	game.world._process(6.1)
	game.hero.tick(2.0)
	stand(HOME)
	var attacker: BattleUnit = game.spawn_creature(true, "basic")
	attacker.position = HOME + Vector3(1.35,0,0)
	attacker.speed = 0.0
	attacker.attack_timer = 0.0
	game.hero.hurt(58.0, attacker)
	game.update_creature(attacker, .1)
	game.beacon_hp -= 60.0
	game.record_beacon_hit(60.0)
	game.exploration.arm_contract_affinity(["memory_crystal"])
	check(game.hero_damage_flash_time > 0.0 and not game.hero_damage_flash_text.is_empty(),
		"Actual damage confirmation must remain available with details closed")
	check(not game.target_warning_snapshot().is_empty(),
		"Actual target warning must remain available with details closed: queued=%s windup=%s target=%s enemy=%s" % [attacker.attack_queued,attacker.attack_windup,attacker.get_meta("attack_target_kind",""),attacker.position])
	check(game.beacon_alarm_time > 0.0, "Actual beacon alarm must remain available with details closed")
	check(game.exploration.affinity_active(), "Actual affinity source must remain available with details closed")
	await capture("urgent-feedback")
	remove_enemies()
	for kill in 3:
		var target: BattleUnit = game.spawn_creature(false)
		target.position = HOME + Vector3(0,0,1.5)
		target.hp = 1.0
		game.hero.attack_timer = 0.0
		game.auto_attack()
		game.update_hero_attack(1.0)
		game.hero.tick(1.0)
	check(game.kill_chain == 3 and game.combat_milestone_time > 0.0 and not game.combat_milestone_title.is_empty(),
		"Three actual player attack resolutions must retain the real kill-chain milestone")
	await capture("combat-chain")
	remove_enemies()
	game.day_number = 4
	game.run_mode = "siege"
	game.start_night()
	remove_enemies()
	game.wave_index = 4
	game.spawn_night_wave()
	var boss: BattleUnit
	for enemy: BattleUnit in game.enemies:
		if is_instance_valid(enemy) and enemy.get_meta("siege_boss",false): boss = enemy
	check(is_instance_valid(boss) and not game.boss_snapshot().is_empty(), "The real fourth-night last wave must still expose the boss HUD source")
	if is_instance_valid(boss):
		boss.position = Vector3(0,5,5)
		game.siege_boss.advance(8.0)
		check(game.boss_snapshot().phase == "windup", "The actual boss must retain its visible windup/interrupt decision")
	await capture("boss-warning")
	press(KEY_ESCAPE)
	check(game.phase == "paused", "The real boss scene must still pause through Esc")
	await capture("paused")
	game.end_defeat("清爽界面结算入口回归")
	press(KEY_F3)
	check(game.phase == "ended" and game.hud.detail_tab == "", "F3 must not open tactical details over the actual ended-run scene")

func cleanup() -> void:
	if is_instance_valid(game):
		await game.prepare_shutdown()
		game.queue_free()
		await process_frame
	await create_timer(.5).timeout

func run() -> void:
	check(RunSession.queue_request(self, 20261006, "teaching"),
		"The real session handoff must supply a reproducible HUD comparison seed")
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	# The recorder inherits every production method and forwards every draw.
	# Its fixed local source adds observation only, never duplicate HUD logic.
	var recorder := GDScript.new()
	recorder.source_code = RECORDING_HUD
	check(recorder.reload() == OK, "Compile the fixed recording subclass of the actual production HUD")
	var old_hud: Control = game.hud
	var layer: Node = old_hud.get_parent()
	layer.remove_child(old_hud)
	old_hud.queue_free()
	var replacement: Control = recorder.new()
	replacement.game = game
	game.hud = replacement
	layer.add_child(replacement)
	replacement.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await redraw()
	check(game.hud.game == game and game.hud.get_rect().size == game.hud.get_viewport_rect().size,
		"The observing HUD must retain the actual game reference and full viewport anchors: rect=%s viewport=%s root=%s" % [game.hud.get_rect(),game.hud.get_viewport_rect(),root.size])
	if not api_ready():
		await cleanup()
		quit(1)
		return
	assert_interface()
	press(KEY_F3)
	check(game.phase == "draft" and game.hud.detail_tab == "", "F3 must remain blocked during the real opening draft")
	press(KEY_8)
	press(KEY_1)
	game.world._process(6.1)
	remove_enemies()
	clear_transient_hud()
	await default_layout("default-night")
	await capture("default-night")
	game.finish_night()
	press(KEY_1)
	game.world._process(6.1)
	remove_enemies()
	stand(HOME)
	clear_transient_hud()
	check(game.phase == "day" and game.day_number == 2, "The actual first dawn must generate the HUD's real day state")
	await default_layout("default-day")
	await capture("default-day")
	check_live_data()
	await detail_navigation()
	await rich_exploration_page()
	await build_barracks()
	await army_gui()
	await defense_and_memory_gui()
	await scale_and_hit_testing()
	await urgent_feedback()
	if render_test:
		var file := FileAccess.open("res://build/clean-hud-layout.json",FileAccess.WRITE)
		check(file != null, "Open the local layout evidence file")
		if file != null: file.store_string(JSON.stringify(evidence,"\t"))
	print("NIGHTFALL_CLEAN_HUD_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAILED",checks,failures.size()])
	await cleanup()
	quit(0 if failures.is_empty() else 1)
