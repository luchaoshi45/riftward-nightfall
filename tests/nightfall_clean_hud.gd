extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
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
const HELP_TOGGLE := Rect2(46, 692, 190, 30)
const MINI := Rect2(1252, 106, 164, 164)
const SELECTED_SQUAD := Rect2(24, 762, 300, 54)
const CONSTRUCTION := Rect2(435, 642, 570, 140)
const RunSession = preload("res://scripts/run_session.gd")
const RECORDING_HUD := """extends 'res://scripts/nightfall_hud.gd'
var drawn_labels: Array[Dictionary] = []
var all_labels: Array[String] = []
var all_drawn_labels: Array[Dictionary] = []
var drawn_boxes: Array[Rect2] = []
var recording_drawer := false
func _draw() -> void:
	drawn_labels.clear()
	all_labels.clear()
	all_drawn_labels.clear()
	drawn_boxes.clear()
	recording_drawer = false
	super._draw()
func box(rect: Rect2, fill: Color = Color(.022,.035,.045,.88), outline: Color = Color(\"435455\")) -> void:
	drawn_boxes.append(rect)
	if rect == Rect2(24,112,540,622): recording_drawer = true
	if rect == Rect2(428,692,112,30): recording_drawer = false
	super.box(rect,fill,outline)
func label(value: String, point: Vector2, size_px: int, color: Color = Color(\"e7e1d3\"), latin: bool = false) -> void:
	all_labels.append(value)
	var actual_font: Font = display_font if latin else font
	var row := {\"text\":value, \"point\":point, \"font_size\":size_px,
		\"width\":actual_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x,
		\"ascent\":actual_font.get_ascent(size_px), \"descent\":actual_font.get_descent(size_px), \"color\":color}
	all_drawn_labels.append(row)
	if recording_drawer:
		drawn_labels.append(row)
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
	check("地图 · 点击展开" not in game.hud.all_labels,
		label + ": the default radar must stay icon-only; map guidance belongs to the bottom shortcut rail")
	check("地图" in game.hud.all_labels,
		label + ": the compact map affordance must retain a short readable label")
	check("F3" in game.hud.all_labels and "Y" in game.hud.all_labels,
		label + ": the default navigation must keep compact key badges for details and build")
	check("F3 详情" not in game.hud.all_labels and "Y 建造" not in game.hud.all_labels,
		label + ": verbose navigation labels must stay out of the default action rail")
	check(game.hud.CleanHud.HERO_FILL.a == 0.0,
		label + ": the default hero dock must remain transparent so the battlefield keeps visual priority")
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

func scene_priority_default() -> void:
	var previous: bool = game.hud.minimal_display
	game.hud.minimal_display=true
	game.squads.cancel_selection()
	clear_transient_hud()
	await redraw()
	var visible: Array = game.hud.visible_hud_rects()
	check(not visible.has(MINI), "Scene-priority HUD must keep the compact radar hidden until the map is requested")
	check(not visible.has(SELECTED_SQUAD), "Scene-priority HUD must not reserve a card for an idle selection")
	check(game.hud.minimal_display, "Scene-priority HUD flag must remain enabled during the live default layout")
	game.hud.minimal_display=previous
	await redraw()

func capture(label: String) -> void:
	if not render_test: return
	game.hud.queue_redraw()
	for frame in 6:
		await process_frame
		await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	check(picture.get_size() == root.content_scale_size and Vector2(picture.get_size()) == game.hud.get_viewport_rect().size, "Actual clean-HUD capture must use the requested content viewport size")
	check(picture.save_png("res://build/clean-hud-%s.png" % label) == OK, "Save the actual clean HUD " + label)

func capture_production_default(label: String) -> void:
	# The recorder normally keeps minimal_display=false so the interaction
	# suite can observe every legacy hitbox. Capture the real player-facing mode
	# separately, otherwise default screenshots can regress to the old card
	# stack while the production HUD itself remains clean.
	var previous: bool = game.hud.minimal_display
	game.hud.minimal_display=true
	await redraw()
	await capture("production-" + label)
	game.hud.minimal_display=previous
	await redraw()

func api_ready() -> bool:
	var complete := true
	for method in ["toggle_details", "toggle_map", "details_tab_rect", "minimap_rect", "visible_hud_rects", "countermeasure_rect"]:
		if not game.hud.has_method(method):
			check(false, "Production HUD interface is not ready: " + method)
			complete = false
	return complete

func assert_interface() -> void:
	var constants: Dictionary = load("res://scripts/nightfall_hud.gd").get_script_constant_map()
	for name in {"DETAIL_CLOSE_RECT": CLOSE, "HELP_TOGGLE_RECT": HELP_TOGGLE, "TACTICS_BUTTON_RECT": TACTICS,
		"MAP_BUTTON_RECT": MAP, "MEMORY_BUTTON_RECT": MEMORY, "CONSTRUCTION_PANEL_RECT": CONSTRUCTION}:
		var expected: Rect2 = {"DETAIL_CLOSE_RECT": CLOSE, "HELP_TOGGLE_RECT": HELP_TOGGLE, "TACTICS_BUTTON_RECT": TACTICS,
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

func pause_notice_priority() -> void:
	var message:="非空通知布局验收"
	game.notify(message,3.0)
	await redraw()
	check(message in game.hud.all_labels,"The notice must be genuinely rendered during live play before the pause check")
	var before:=finances()
	press(KEY_ESCAPE)
	press(KEY_F3)
	await redraw()
	check(game.phase=="paused" and game.hud.detail_tab=="contract","Pause notice coverage must use the real paused drawer state")
	check(message not in game.hud.all_labels and "已暂停 · Esc 先收起详情" in game.hud.all_labels,
		"The actual paused drawer must show its pause hint without an underlying notice crossing it")
	check(game.notice==message and game.notice_time>0.0,"Pause priority must preserve the pending notice for resumption")
	await capture("paused-notice-details")
	await click(MAP)
	await redraw()
	check(game.phase=="paused" and game.hud.map_expanded and message not in game.hud.all_labels,
		"The actual expanded paused map must also keep the notice clear of the pause hint")
	await capture("paused-notice-map")
	press(KEY_ESCAPE)
	press(KEY_ESCAPE)
	await redraw()
	check(game.phase=="day" and message in game.hud.all_labels and finances()==before,
		"Real Esc resumption must restore the preserved notice without spending or issuing orders")
	game.notice_time=0.0

func help_mode_bounds(label: String, full: bool) -> void:
	# Keep the original production-body recorder and close-button bounds. The
	# separate footer is observed through all_drawn_labels, just like exploration.
	await detail_text_bounds(label)
	var body: Array[Dictionary] = []
	var shortcuts: Array[Dictionary] = []
	var text := ""
	for row: Dictionary in game.hud.drawn_labels:
		if row.point.y < 160.0: continue
		body.append(row)
		text += String(row.text) + "\n"
		if row.point.y >= 254.0: shortcuts.append(row)
		for character: String in String(row.text):
			var code := character.unicode_at(0)
			if code >= 0x4e00 and code <= 0x9fff:
				check(game.hud.font.has_char(code),label + ": actual help font must resolve Chinese glyph " + character)
	if full:
		check(body.size() > 12,label + ": expanded help must actually restore the longer production explanations")
		for required in ["科技", "研究所", "医护默认停疗", "每次2零件", "集结", "PgUp"]:
			check(required in text,label + ": detailed help must preserve the real rule " + required)
	else:
		check(body.size() == 12 and shortcuts.size() == 10,
			label + ": default help must render one heading, one introduction and exactly ten quick-operation lines")
		check("常用操作" in text and "科技：" not in text and "每次2零件" not in text,
			label + ": the quick view must defer the long technology and treatment rules to explicit expansion")
		var repair_seen := false
		var advance_seen := false
		var escort_seen := false
		for index in shortcuts.size():
			var row: Dictionary = shortcuts[index]
			check(row.point == Vector2(46,254 + index*36) and int(row.font_size) == 15,
				label + ": each complete quick-operation line must retain its readable production row")
			var line := String(row.text)
			repair_seen = repair_seen or ("H" in line and "维修" in line)
			advance_seen = advance_seen or ("Shift" in line and "推进" in line)
			escort_seen = escort_seen or ("Alt" in line and "护航" in line)
		check(repair_seen and advance_seen and escort_seen,
			label + ": quick help must retain H repair, Shift attack-move and Alt convoy guidance")
	var footer := recorded_text_in(HELP_TOGGLE)
	var caption := "返回快捷操作" if full else "查看详细说明"
	check(game.hud.drawn_boxes.has(HELP_TOGGLE) and footer.size() == 1,
		label + ": the actual help toggle must paint its existing drawer-footer rectangle and one caption")
	for row: Dictionary in footer:
		check(String(row.text) == caption,label + ": the footer must describe the next actual help view")
		check_text_inside(HELP_TOGGLE,row,label + " footer")
		for character: String in caption:
			check(game.hud.font.has_char(character.unicode_at(0)),label + ": footer font must resolve Chinese glyph " + character)
	evidence["help-mode-" + label] = {"full":full, "lines":body.size(), "toggle":rect_data(HELP_TOGGLE),
		"viewport":[game.hud.get_viewport_rect().size.x,game.hud.get_viewport_rect().size.y]}

func help_toggle_click(button: int, label: String) -> void:
	var before_finances := finances()
	var before_orders := orders()
	var before_selection := tag_selection_state()
	var was_full := bool(game.hud.help_details_open)
	await click(HELP_TOGGLE,button)
	check(game.hud.detail_tab == "help" and bool(game.hud.help_details_open) == (not was_full if button == MOUSE_BUTTON_LEFT else was_full),
		label + ": only the actual left click may switch help content inside the same drawer")
	check(finances() == before_finances,label + ": a help toggle must not spend parts, alter training or change the live phase")
	check(orders() == before_orders and tag_selection_state() == before_selection,
		label + ": press/release on the visible help toggle must never order the hero, issue troop commands or change world selection")

func help_folding_gui() -> void:
	var original_size: Vector2i = root.size
	var original_content: Vector2i = root.content_scale_size
	var saved := tag_command_snapshot()
	var before_finances := finances()
	check(game.phase == "day" and game.hud.detail_tab == "" and not game.hud.map_expanded
		and not game.hud.help_details_open,
		"Actual help-folding coverage must begin in the closed, quick-default live game")
	press(KEY_TAB)
	check(game.squads.selected_count() > 0,"Help input coverage must use the actual GUI-trained squad selection")
	var selected := tag_selection_state()
	var commands := orders()
	for size in [Vector2i(1920,1200),Vector2i(1920,1080),Vector2i(1440,900)]:
		root.size = size
		root.content_scale_size = size
		var label := "Help folding %dx%d" % [size.x,size.y]
		await click(TACTICS)
		await click(game.hud.details_tab_rect(4))
		check(Vector2i(game.hud.get_viewport_rect().size) == size,
			label + ": the actual help GUI must use the requested content viewport")
		check(game.hud.detail_tab == "help" and not game.hud.help_details_open,
			label + ": a real operation-tab click must open quick help by default")
		await help_mode_bounds(label + " quick",false)
		var suffix := "" if size == Vector2i(1920,1200) else "-%dx%d" % [size.x,size.y]
		await capture("help-quick" + suffix)
		await help_toggle_click(MOUSE_BUTTON_RIGHT,label + " quick right click with selected troops")
		await help_toggle_click(MOUSE_BUTTON_LEFT,label + " actual expansion")
		await help_mode_bounds(label + " full",true)
		await capture("help-full" + suffix)
		await help_toggle_click(MOUSE_BUTTON_RIGHT,label + " full right click with selected troops")
		await help_toggle_click(MOUSE_BUTTON_LEFT,label + " actual folding")
		await help_mode_bounds(label + " folded",false)
		# Cover hero routing too, without replacing the trained troops or their
		# production commands. Tab restores the same real selection afterwards.
		game.squads.cancel_selection()
		await help_toggle_click(MOUSE_BUTTON_RIGHT,label + " quick right click without selected troops")
		await help_toggle_click(MOUSE_BUTTON_LEFT,label + " hero-view expansion")
		await help_toggle_click(MOUSE_BUTTON_RIGHT,label + " full right click without selected troops")
		press(KEY_TAB)
		check(tag_selection_state() == selected,label + ": actual Tab must restore the original trained-squad selection")
		await click(game.hud.details_tab_rect(0))
		check(game.hud.detail_tab == "contract" and not game.hud.help_details_open,
			label + ": real navigation to another tab must retire the expanded help state")
		check(recorded_text_in(HELP_TOGGLE).is_empty() or not game.hud.drawn_boxes.has(HELP_TOGGLE),
			label + ": help-only footer must not remain visibly drawn on a different tab")
		var other_finances := finances()
		var other_orders := orders()
		await click(HELP_TOGGLE)
		check(game.hud.detail_tab == "contract" and not game.hud.help_details_open
			and finances() == other_finances and orders() == other_orders,
			label + ": the old help-toggle location must not retain its help action on another tab")
		await click(game.hud.details_tab_rect(4))
		await help_toggle_click(MOUSE_BUTTON_LEFT,label + " expansion before map")
		await click(MAP)
		check(game.hud.map_expanded and game.hud.detail_tab == "" and not game.hud.help_details_open,
			label + ": actual map navigation must reset help expansion and dismiss its drawer")
		await click(TACTICS)
		await click(game.hud.details_tab_rect(4))
		check(not game.hud.help_details_open,label + ": reopening help after the map must return to quick operations")
		await help_toggle_click(MOUSE_BUTTON_LEFT,label + " expansion before Esc")
		press(KEY_ESCAPE)
		check(game.hud.detail_tab == "" and not game.hud.help_details_open and game.phase == "day"
			and tag_selection_state() == selected,
			label + ": actual Esc must close expanded help before pausing or deselecting troops")
		await click(TACTICS)
		await click(game.hud.details_tab_rect(4))
		check(game.hud.detail_tab == "help" and not game.hud.help_details_open,
			label + ": reopening after Esc must restore the quick help default")
		await help_mode_bounds(label + " reopened quick",false)
		await click(CLOSE)
		check(game.hud.detail_tab == "" and not game.hud.help_details_open,
			label + ": the actual drawer-close button must also retire any help expansion")
		check(finances() == before_finances and orders() == commands and tag_selection_state() == selected,
			label + ": the complete real help-navigation sequence must leave economy and production orders unchanged")
	root.size = original_size
	root.content_scale_size = original_content
	restore_tag_commands(saved)
	await redraw()
	check(game.hud.detail_tab == "" and not game.hud.map_expanded and not game.hud.help_details_open
		and finances() == before_finances and orders() == saved.orders,
		"Help-folding fixtures must restore the prior live viewport, hero orders and trained-squad selection")

func compact_objective_day_inputs() -> void:
	var saved := tag_command_snapshot()
	var before_finances := finances()
	var old_rect := Rect2(426,20,588,76)
	var free_point := Vector2(1002,90)
	check(game.phase == "day" and game.hud.detail_tab == "" and not game.hud.map_expanded
		and not game.construction.active and not game.hud._has_event_warning(),
		"Dynamic objective input coverage must use the actual warning-free, closed-details day state")
	await redraw()
	var actual_rect := Rect2()
	for rect: Rect2 in game.hud.drawn_boxes:
		if rect.position == old_rect.position:
			actual_rect = rect
			break
	check(actual_rect.has_area() and actual_rect.get_area() < old_rect.get_area(),
		"The actually painted day objective must shrink below its former 588-by-76 rectangle")
	check(game.hud.visible_hud_rects().has(actual_rect) and not game.hud.visible_hud_rects().has(old_rect),
		"Dynamic objective painting and current input exclusion must report the same smaller actual rectangle")
	press(KEY_TAB)
	check(game.squads.selected_count() > 0,
		"Objective-card non-penetration must include the actual GUI-trained squad selection")
	await assert_tag_buttons(actual_rect,"The content-sized day objective card")
	check(finances() == before_finances,
		"Actual left/right clicks inside the smaller objective card must not spend parts or alter production")
	var uncovered := old_rect.has_point(free_point)
	for rect: Rect2 in game.hud.visible_hud_rects():
		uncovered = uncovered and not rect.has_point(free_point)
	check(uncovered,
		"The former objective's lower-right corner must become uncovered battlefield input space")
	# Use the real viewport press, drag and release path. No replacement hitbox
	# or width calculation is used to imitate the production objective layout.
	await tag_mouse_button(free_point,MOUSE_BUTTON_LEFT,true)
	var pixel_start: Vector2 = free_point * game.hud.get_viewport_rect().size / Vector2(1440,900)
	var selection_started: bool = game.selection_dragging and game.selection_start == pixel_start
	check(selection_started,
		"Actual left press on the released former-objective corner must begin battlefield box selection")
	var drag_end := free_point + Vector2(20,20)
	var pixel_end: Vector2 = drag_end * game.hud.get_viewport_rect().size / Vector2(1440,900)
	var motion := InputEventMouseMotion.new()
	motion.position = pixel_end
	motion.global_position = pixel_end
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion,true)
	await process_frame
	var selection_dragged: bool = game.selection_dragging and game.selection_end == pixel_end
	check(selection_dragged,
		"Actual world motion from the released corner must advance the live box-selection rectangle")
	await tag_mouse_button(drag_end,MOUSE_BUTTON_LEFT,false)
	var selection_finished: bool = not game.selection_dragging and finances() == before_finances
	check(selection_finished,
		"Actual box-selection release must finish without spending parts or changing production")
	evidence["compact-objective-day"] = {"painted":rect_data(actual_rect), "former":rect_data(old_rect),
		"released_point":[free_point.x,free_point.y], "actual_box_selection":selection_started and selection_dragged and selection_finished}
	restore_tag_commands(saved)
	await redraw()
	check(orders() == saved.orders and tag_selection_state() == saved.selection and game.aim == saved.aim
		and game.pending_aim_screen == saved.pending_aim_screen and game.aim_sample_pending == saved.aim_sample_pending
		and finances() == before_finances,
		"Dynamic-objective fixtures must restore original hero/troop orders, selection and pending aim")

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
	await redraw()
	check(active_tag_box().has_area(), "Closing the real exploration drawer must expose its active tags")

func active_tag_box() -> Rect2:
	# Observe the actual production box; never duplicate its text/width logic.
	for rect: Rect2 in game.hud.drawn_boxes:
		if rect.position == Vector2(24,100) and is_equal_approx(rect.size.y,29.0): return rect
	return Rect2()

func tag_selection_state() -> Dictionary:
	return {"dragging": game.selection_dragging, "start": game.selection_start,
		"end": game.selection_end, "additive": game.selection_additive,
		"selected": game.squads.selected_ids.duplicate()}

func tag_mouse_button(logical: Vector2, button: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = logical * game.hud.get_viewport_rect().size / Vector2(1440,900)
	event.global_position = event.position
	event.button_index = button
	event.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if pressed else 0
	event.pressed = pressed
	root.push_input(event,true)
	await process_frame

func tag_command_snapshot() -> Dictionary:
	var members: Array[Dictionary] = []
	var formations: Array[int] = []
	for squad: Dictionary in game.squads.squads:
		formations.append(int(squad.formation_index))
		for member: BattleUnit in squad.members:
			members.append({"node": member, "target": member.target, "queued": member.attack_queued,
				"windup": member.attack_windup, "path": member.path.duplicate(), "timer": member.path_timer})
	return {"orders": orders(), "selection": tag_selection_state(), "members": members,
		"formations": formations, "aim": game.aim, "notice": game.notice,
		"notice_time": game.notice_time, "keyboard": game.hero_keyboard_active,
		"pending_aim_screen": game.pending_aim_screen, "aim_sample_pending": game.aim_sample_pending}

func restore_tag_commands(saved: Dictionary) -> void:
	game.move_goal = saved.orders.goal
	game.hero_path = saved.orders.path
	game.hero_keyboard_active = saved.keyboard
	game.aim = saved.aim
	game.pending_aim_screen = saved.pending_aim_screen
	game.aim_sample_pending = saved.aim_sample_pending
	game.notice = saved.notice
	game.notice_time = saved.notice_time
	game.selection_dragging = saved.selection.dragging
	game.selection_start = saved.selection.start
	game.selection_end = saved.selection.end
	game.selection_additive = saved.selection.additive
	game.squads.selected_ids.assign(saved.selection.selected)
	game.squads._refresh_selection()
	for index in game.squads.squads.size():
		var squad: Dictionary = game.squads.squads[index]
		var previous: Dictionary = saved.orders.army[index]
		squad.order = previous.order
		squad.destination = previous.destination
		squad.attack_target = previous.target
		squad.formation_index = saved.formations[index]
	for row: Dictionary in saved.members:
		var member: BattleUnit = row.node
		member.target = row.target
		member.attack_queued = row.queued
		member.attack_windup = row.windup
		member.path = row.path
		member.path_timer = row.timer

func assert_tag_buttons(rect: Rect2, label: String) -> void:
	var saved := tag_command_snapshot()
	var selection := tag_selection_state()
	await tag_mouse_button(rect.get_center(),MOUSE_BUTTON_LEFT,true)
	check(tag_selection_state() == selection, label + ": actual left press must not start/change a world selection")
	await tag_mouse_button(rect.get_center(),MOUSE_BUTTON_LEFT,false)
	check(tag_selection_state() == selection, label + ": actual left release must preserve the prior troop selection")
	check(orders() == saved.orders, label + ": left press/release must retain hero and troop orders")
	restore_tag_commands(saved)
	await assert_no_command(rect.get_center(),label)
	restore_tag_commands(saved)

func drawn_notice_box() -> Rect2:
	# Identify the actually painted notification, independently of its helper.
	for rect: Rect2 in game.hud.drawn_boxes:
		if is_equal_approx(rect.end.y,788.0) and is_equal_approx(rect.get_center().x,720.0): return rect
	return Rect2()

func recorded_text_in(rect: Rect2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in game.hud.all_drawn_labels:
		if rect.has_point(row.point): result.append(row)
	return result

func check_text_inside(rect: Rect2, row: Dictionary, label: String) -> void:
	var point: Vector2 = row.point
	check(point.x >= rect.position.x and point.x + float(row.width) <= rect.end.x,
		label + ": actual font width must fit its painted panel: " + String(row.text))
	check(point.y - float(row.ascent) >= rect.position.y and point.y + float(row.descent) <= rect.end.y,
		label + ": actual ascent/descent must fit its painted panel: " + String(row.text))

func assert_free_world_input(point: Vector2, label: String) -> void:
	var saved := tag_command_snapshot()
	var uncovered := true
	for rect: Rect2 in game.hud.visible_hud_rects(): uncovered = uncovered and not rect.has_point(point)
	check(uncovered,label + ": released screen space must have no current HUD hitbox")
	game.squads.cancel_selection()
	await tag_mouse_button(point,MOUSE_BUTTON_LEFT,true)
	check(game.selection_dragging,label + ": real left press must begin a world selection")
	await tag_mouse_button(point,MOUSE_BUTTON_LEFT,false)
	check(not game.selection_dragging,label + ": real left release must finish the selection")
	restore_tag_commands(saved)
	game.squads.cancel_selection()
	var before := orders()
	await click_at(point,MOUSE_BUTTON_RIGHT)
	check(game.move_goal != before.goal or game.hero_path != before.path,
		label + ": real right click must reach hero path planning")
	check(orders().army == before.army,label + ": a hero command must retain troop orders")
	restore_tag_commands(saved)
	game.squads.cancel_selection()
	press(KEY_TAB)
	check(game.squads.selected_count() == 1,label + ": actual Tab must select the GUI-trained squad")
	before = orders()
	await click_at(point,MOUSE_BUTTON_RIGHT)
	check(orders().army != before.army and game.squads.squads[0].order == game.squads.MOVE,
		label + ": real right click must reach selected-troop movement")
	check(game.move_goal == before.goal and game.hero_path == before.path,
		label + ": selected-troop movement must retain hero path planning")
	restore_tag_commands(saved)
	check(orders() == saved.orders and tag_selection_state() == saved.selection
		and game.aim_sample_pending == saved.aim_sample_pending and game.pending_aim_screen == saved.pending_aim_screen,
		label + ": the input fixture must restore actual orders, selection and deferred aiming")

func compact_notice_inputs() -> void:
	var original_size: Vector2i = root.size
	var original_content: Vector2i = root.content_scale_size
	var saved := tag_command_snapshot()
	var free_point := Vector2(352,772)
	var old_notice := Rect2(344,740,752,48)
	var long_text := "训练完成后可以选中部队，右键前往指定位置并守住南门。白昼探索获得零件，返回城堡后建设防线，入夜优先处理威胁最大的敌人，再保护受伤队员回到安全位置。"
	for size in [Vector2i(1920,1200),Vector2i(1920,1080),Vector2i(1440,900)]:
		root.size = size
		root.content_scale_size = size
		var label := "Compact notification %dx%d" % [size.x,size.y]
		game.notify("部队已就位",3.0)
		await redraw()
		var short_box := drawn_notice_box()
		check(short_box.has_area() and short_box.size.x < old_notice.size.x and short_box.size.y == 34.0,
			label + ": the actually drawn short notice must shrink to one compact line")
		check(game.hud.visible_hud_rects().has(short_box) and not game.hud.visible_hud_rects().has(old_notice),
			label + ": input coverage must match the compact painted notification")
		var short_rows := recorded_text_in(short_box)
		check(short_rows.size() == 1 and String(short_rows[0].text) == "部队已就位",
			label + ": the real short Chinese notification must be drawn completely once")
		for row: Dictionary in short_rows: check_text_inside(short_box,row,label)
		await assert_tag_buttons(short_box,label + " visible short notice")
		await assert_free_world_input(free_point,label + " released former-notice edge")
		if size == Vector2i(1920,1200): await capture("notice-short")
		game.notify(long_text,3.0)
		await redraw()
		var long_box := drawn_notice_box()
		var long_rows := recorded_text_in(long_box)
		check(long_box.has_area() and long_box.size.y == 54.0 and long_box.size.x <= old_notice.size.x,
			label + ": the real long notice must use at most two lines without expanding across the battlefield")
		check(long_rows.size() == 2,label + ": the real Chinese message must actually wrap into two drawn lines")
		var rendered := ""
		for row: Dictionary in long_rows:
			rendered += String(row.text)
			check_text_inside(long_box,row,label + " long notice")
		check(rendered == long_text,label + ": wrapping must preserve the complete real Chinese message")
		check(game.hud.visible_hud_rects().has(long_box),label + ": the two-line notice must register its actual drawn footprint")
		await assert_tag_buttons(long_box,label + " visible long notice")
		if size == Vector2i(1920,1200): await capture("notice-long")
		for empty_text in [""," \t\n "]:
			game.notify(empty_text,3.0)
			await redraw()
			check(not drawn_notice_box().has_area(),label + ": empty or whitespace-only notices must not draw a panel")
			await assert_free_world_input(free_point,label + " empty notice")
		# Expire through the actual controller tick while paused so unrelated
		# production/army/economy does not advance during this input fixture.
		game.squads.cancel_selection()
		game.notify("即将消失的通知",.01)
		press(KEY_ESCAPE)
		var follow: Vector3 = game.camera_follow
		var camera_point: Vector3 = game.camera.position
		var rewards: Array = game.reward_toasts.duplicate(true)
		game._process(.02)
		game.camera_follow = follow
		game.camera.position = camera_point
		game.reward_toasts.assign(rewards)
		press(KEY_ESCAPE)
		await redraw()
		check(game.phase == "day" and game.notice_time == 0.0 and not drawn_notice_box().has_area(),
			label + ": actual notification expiry must remove its paint and current hitbox")
		await assert_free_world_input(free_point,label + " expired notice")
		game.notify("建设时保留的普通通知",3.0)
		press(KEY_Y)
		await redraw()
		check(game.construction.active and not drawn_notice_box().has_area(),
			label + ": real construction must hide the ordinary notification")
		var covered := false
		for rect: Rect2 in game.hud.visible_hud_rects(): covered = covered or rect.has_point(free_point)
		check(not covered,label + ": the former notification edge must not retain a construction-time hitbox")
		await click_at(free_point,MOUSE_BUTTON_RIGHT)
		check(not game.construction.active,label + ": real right click on the released edge must cancel construction")
		restore_tag_commands(saved)
		var hp: float = game.hero.hp
		var shield: float = game.hero.shield
		var damage_time: float = game.hero_damage_flash_time
		var damage_text: String = game.hero_damage_flash_text
		game.notify("受击时保留的普通通知",3.0)
		game.hero.hurt(37.0,null)
		await redraw()
		check(game.hero_damage_flash_time > 0.0 and not drawn_notice_box().has_area(),
			label + ": actual confirmed damage must hide the ordinary notification")
		await assert_free_world_input(free_point,label + " damage-priority released edge")
		game.hero.hp = hp
		game.hero.shield = shield
		game.hero_damage_flash_time = damage_time
		game.hero_damage_flash_text = damage_text
		game.combat.clear_transients()
		await redraw()
		var resource_box := Rect2()
		for rect: Rect2 in game.hud.drawn_boxes:
			if rect.position == Vector2(1080,20): resource_box = rect
		check(resource_box.has_area() and resource_box.size.y == 54.0 and game.hud.visible_hud_rects().has(resource_box),
			label + ": the actually painted resource panel must use its smaller registered footprint")
		var resource_text := recorded_text_in(resource_box)
		check(resource_text.size() == 2,label + ": resources must retain only actual parts and beacon text")
		for row: Dictionary in resource_text:
			check("铭刻" not in String(row.text),label + ": paid-upgrade information must not duplicate the bottom V button")
			check_text_inside(resource_box,row,label + " resources")
		await assert_free_world_input(Vector2(1100,80),label + " released resource-panel bottom")
	root.size = original_size
	root.content_scale_size = original_content
	restore_tag_commands(saved)
	await redraw()
	check(game.phase == "day" and not game.construction.active and game.hud.detail_tab == "",
		"Compact notification fixtures must restore the live gameplay state")

func compact_skill_readability() -> void:
	var saved := tag_command_snapshot()
	var mana: float = game.mana
	var cooldowns: Array = game.cooldowns.duplicate()
	var notice_key: String = game.skill_notice_key
	var notice_until: float = game.skill_notice_until
	var hero_action: Dictionary = {}
	for property: String in ["hero_action","hero_action_time","hero_action_duration","hero_action_weight","hero_action_aim_yaw","hero_attack_variant"]:
		hero_action[property] = game.hero.get(property)
	game.notice_time = 0.0
	await redraw()
	for index in 5:
		var cell := Rect2(558 + index*105,808,105,72)
		check(game.skill_status(index) == "就绪","The live pre-cast skill fixture must begin with a genuinely ready skill")
		var rows := recorded_text_in(cell)
		check(rows.size() == 2,"A ready skill must draw only its actual key and name, without a repeated ready label")
		for row: Dictionary in rows:
			check(String(row.text) != "就绪","Ready skills must not repeat five status labels across the cleaned bottom bar")
			check_text_inside(cell,row,"Ready skill")
		check(not game.hud.drawn_boxes.has(Rect2(558+index*105,810,99,61)),
			"The old large repeated skill frame must not remain painted")
	# Isolate the mana boundary, then spend it through genuine keyboard casting.
	# The fixture does not advance training or regenerate mana through simulate.
	game.mana = float(game.COSTS[0]) + 10.0
	game.aim_sample_pending = false
	game.aim = game.hero.position + Vector3.RIGHT
	press(KEY_Q)
	check(game.mana == 10.0 and is_equal_approx(game.cooldowns[0],float(game.COOLDOWNS[0])*game.run.cooldown_factor()),
		"Actual Q input must pay its real mana cost and start its real production cooldown")
	await redraw()
	var status: String = game.skill_status(0)
	var q_rows := recorded_text_in(Rect2(558,808,105,72))
	check(q_rows.size() == 3 and status != "就绪" and status in game.hud.all_labels,
		"The actual Q cooldown number must remain drawn after removing repeated ready labels")
	for row: Dictionary in q_rows: check_text_inside(Rect2(558,808,105,72),row,"Actual Q cooldown")
	await capture("skill-cooldown")
	var after_cast: float = game.mana
	var cooldown: float = game.cooldowns[0]
	press(KEY_Q)
	check(game.mana == after_cast and game.cooldowns[0] == cooldown and "Q 斩光 · 冷却还剩" in game.notice,
		"A second real Q must show the production cooldown rejection without paying or restarting it")
	press(KEY_E)
	check(game.mana == after_cast and game.cooldowns[2] == 0.0 and "E 突进 · 法力不足" in game.notice,
		"Actual insufficient-mana E input after Q spending must retain its readable production rejection")
	await redraw()
	for index in [1,2,3]:
		var cell := Rect2(558 + index*105,808,105,72)
		var rows := recorded_text_in(cell)
		var shortage := false
		for row: Dictionary in rows:
			check_text_inside(cell,row,"Actual insufficient mana")
			if String(row.text) == "法力不足":
				shortage = true
				check(row.color == game.hud.red,"Actual insufficient-mana skill text must keep its urgent readable color")
		check(shortage,"Each actually unaffordable positive-cost skill must retain its shortage text")
	var rejection_box := drawn_notice_box()
	var rejection_rows := recorded_text_in(rejection_box)
	check(rejection_box.has_area() and not rejection_rows.is_empty(),"The actual mana rejection must retain a visible compact notification")
	for row: Dictionary in rejection_rows: check_text_inside(rejection_box,row,"Mana-rejection notification")
	await capture("skill-mana-shortage")
	for character in "斩光屏障突进灯焰治疗法力不足冷却还剩秒需要":
		check(game.hud.font.has_char(character.unicode_at(0)),"The actual skill and feedback font must resolve glyph " + character)
	game.mana = mana
	game.cooldowns.assign(cooldowns)
	game.skill_notice_key = notice_key
	game.skill_notice_until = notice_until
	for property: String in hero_action: game.hero.set(property,hero_action[property])
	restore_tag_commands(saved)
	await redraw()

func active_exploration_tag_inputs() -> void:
	var original_size: Vector2i = root.size
	var original_content: Vector2i = root.content_scale_size
	var commands := tag_command_snapshot()
	var timers: Dictionary = {}
	for property: String in ["streak","streak_time","speed_time","speed_bonus","network_time","affinity_time","affinity_kinds"]:
		var value: Variant = game.exploration.get(property)
		timers[property] = value.duplicate() if value is Array else value
	check(game.exploration.streak > 0 and game.exploration.affinity_active(), "The real prior exploration actions must retain both active tags")
	check(game.squads.squads.size() == 1, "Active-tag input must include the actual GUI-trained squad")
	for size in [Vector2i(1920,1200),Vector2i(1920,1080),Vector2i(1440,900)]:
		root.size = size
		root.content_scale_size = size
		await redraw()
		var tag := active_tag_box()
		var label := "Active exploration tags %dx%d" % [size.x,size.y]
		check(game.hud.get_viewport_rect().size == Vector2(size) and tag.has_area(),label + ": observe the actual scaled viewport and drawn tag box")
		if not tag.has_area(): continue
		check(game.hud.visible_hud_rects().has(tag),label + ": every actually drawn tag panel must participate in visible-UI input coverage")
		var text := " ".join(game.hud.all_labels)
		check("换类" in text and "共鸣" in text,label + ": the visible state must contain both real exploration effects")
		game.squads.cancel_selection()
		await assert_tag_buttons(tag,label + " hero")
		press(KEY_TAB)
		check(game.squads.selected_count() == 1,label + ": actual Tab must select the trained squad")
		await assert_tag_buttons(tag,label + " selected squad")
		game.squads.cancel_selection()
		if size == Vector2i(1920,1200): await capture("active-exploration-tags")
		# The top edge of the former tag lies outside the drawer; it must become
		# usable world space immediately when that conditional tag is hidden.
		var free_point := tag.position + Vector2(8,2)
		press(KEY_F3)
		await redraw()
		check(not active_tag_box().has_area() and not game.hud.visible_hud_rects().has(tag),label + ": opening details must remove the actual tag and its old hitbox")
		await tag_mouse_button(free_point,MOUSE_BUTTON_LEFT,true)
		check(game.selection_dragging,label + ": the exposed former tag edge must accept a real world-selection press")
		await tag_mouse_button(free_point,MOUSE_BUTTON_LEFT,false)
		restore_tag_commands(commands)
		press(KEY_ESCAPE)
		press(KEY_Y)
		await redraw()
		check(game.construction.active and not active_tag_box().has_area() and not game.hud.visible_hud_rects().has(tag),label + ": construction must hide both the tag panel and old hitbox")
		await click_at(free_point,MOUSE_BUTTON_RIGHT)
		check(not game.construction.active,label + ": right-click on the now-free former tag must reach the actual construction cancel action")
		restore_tag_commands(commands)
		game.exploration.tick(maxf(float(game.exploration.streak_time),float(game.exploration.affinity_time)) + .1)
		await redraw()
		check(not active_tag_box().has_area() and not game.hud.visible_hud_rects().has(tag),label + ": real effect expiry must remove the tag and old hitbox")
		await tag_mouse_button(free_point,MOUSE_BUTTON_LEFT,true)
		check(game.selection_dragging,label + ": an expired tag must restore real world-selection input")
		await tag_mouse_button(free_point,MOUSE_BUTTON_LEFT,false)
		restore_tag_commands(commands)
		for property: String in timers:
			var value: Variant = timers[property]
			game.exploration.set(property,value.duplicate() if value is Array else value)
	root.size = original_size
	root.content_scale_size = original_content
	restore_tag_commands(commands)
	await redraw()
	check(game.hud.detail_tab == "" and not game.construction.active and game.phase == "day", "Active-tag regression must restore the original live HUD state for later fixtures")

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

func event_warning_priority() -> void:
	# Use the squad produced by the preceding real GUI queue, plus normal enemy
	# births and their native attack entry points. Actor placement is an isolated
	# HUD fixture; attack flags, warning snapshots and painting are never mocked.
	check(game.squads.squads.size() == 1, "Event priority requires the genuinely GUI-trained squad")
	if game.squads.squads.size() != 1: return
	check(game.enemies.is_empty(), "Event priority starts without replacing any prior native enemy")
	if not game.enemies.is_empty(): return
	var pad: Dictionary = game.world.tower_pads[0]
	var approach: Vector3 = game.building_approach_position(pad.position + Vector3(0,0,-4), pad.position, "tower")
	check(approach.is_finite() and game.outpost_walkable(approach), "Event-priority tower interaction uses a real reachable approach")
	if not approach.is_finite() or not game.outpost_walkable(approach): return
	var saved := tag_command_snapshot()
	var saved_finances := finances()
	var original_phase: String = game.phase
	var original_phase_time: float = game.phase_time
	var spawn_state: int = game.spawn_rng.state
	var hero_position: Vector3 = game.hero.position
	var original_size: Vector2i = root.size
	var original_content: Vector2i = root.content_scale_size
	var camera_transform: Transform3D = game.camera.transform
	var group: Dictionary = game.squads.squads[0]
	var group_state := group.duplicate(true)
	var member_states: Array[Dictionary] = []
	for member: BattleUnit in group.members:
		var properties: Dictionary = {}
		for key in ["transform","age","attack_timer","shield_time","shield","visual_hit_stop","attack_pose","hit_recoil","moving"]:
			properties[key] = member.get(key)
		var poses: Array[Dictionary] = []
		for part: Node3D in member.find_children("*","Node3D",true,false):
			poses.append({"node":part,"transform":part.transform})
		member_states.append({"node":member,"properties":properties,"poses":poses,
			"had_amove":member.has_meta("amove_engaged"),"amove":member.get_meta("amove_engaged",false)})
	var header := Rect2(566,606,530,32)
	# Temporarily use night targeting without rebuilding the world's actual
	# contracts, discoveries, wave plan or paid training lifecycle.
	game.phase = "night"
	clear_transient_hud()
	game.hud.dismiss_details()
	stand(approach)
	var source: BattleUnit = group.members[1]
	for slot in group.members.size():
		var member: BattleUnit = group.members[slot]
		member.position = Vector3(6 + (slot-1)*1.2,5,-4)
	var enemy: BattleUnit = game.spawn_creature(true,"basic")
	enemy.position = Vector3(6,5,-2.5)
	enemy.speed = 0.0
	var enemy_hp: float = enemy.hp
	var selected: Array[int] = [int(group.id)]
	game.squads.select_ids(selected)
	check(bool(game.squads.command_attack(enemy).ok), "The trained squad accepts a real attack order for the friendly-windup fixture")
	game.squads.advance(.001)
	check(source.attack_queued and source.attack_windup > 0.0 and source.target == enemy and enemy.hp == enemy_hp,
		"Native squad advance starts its full friendly preparation without an early hit")
	check(not game.target_warning_snapshot().is_empty(), "Production snapshots genuinely include the friendly squad preparation")
	for size in [Vector2i(1920,1200),Vector2i(1920,1080),Vector2i(1440,900)]:
		root.size = size
		root.content_scale_size = size
		var label := "Friendly windup %dx%d" % [size.x,size.y]
		game.notify("友军正在攻击，普通通知仍可阅读",3.0)
		await redraw()
		var notice := drawn_notice_box()
		check(notice.has_area() and game.notice in game.hud.all_labels and game.hud.visible_hud_rects().has(notice),
			label + ": a native friendly windup must retain the painted notice and its current input footprint")
		check(not game.hud.drawn_boxes.has(header) and not game.hud.visible_hud_rects().has(header),
			label + ": friendly preparation must never reserve an undrawn hero-danger header")
		if size == Vector2i(1920,1200): await capture("friendly-windup-notice")
		game.notice_time = 0.0
		await redraw()
		var prompt: String = game.interaction_prompt()
		var prompt_area: Rect2 = game.hud.context_prompt_rect()
		check(not prompt.is_empty() and "F" in prompt, label + ": the real nearby live tower supplies an F interaction")
		check(not recorded_text_in(prompt_area).is_empty() and game.hud.visible_hud_rects().has(prompt_area),
			label + ": native friendly preparation must retain the actual F prompt and its input footprint")
		if size == Vector2i(1920,1200): await capture("friendly-windup-prompt")
	# A genuine new move command cancels the friendly preparation before the
	# enemy cases; keep the trained members well away from target arbitration.
	check(bool(game.squads.command_move(Vector3(-12,5,-10)).ok), "A real move command cancels the friendly attack before enemy warning checks")
	for slot in group.members.size():
		(group.members[slot] as BattleUnit).position = Vector3(-12 + (slot-1)*1.2,5,-10)
	game.squads.cancel_selection()
	remove_enemies()
	stand(HOME)
	enemy = game.spawn_creature(true,"basic")
	enemy.position = HOME + Vector3(1.35,0,0)
	enemy.speed = 0.0
	enemy.attack_timer = 0.0
	game.update_creature(enemy,.001)
	check(enemy.attack_queued and enemy.attack_windup > 0.0 and game.attack_target_node(enemy) == game.hero,
		"Native enemy update queues a real visible attack against the hero")
	for size in [Vector2i(1920,1200),Vector2i(1920,1080),Vector2i(1440,900)]:
		root.size = size
		root.content_scale_size = size
		var label := "Hero enemy windup %dx%d" % [size.x,size.y]
		game.notify("敌方锁定英雄时应让位的普通通知",3.0)
		await redraw()
		check(not drawn_notice_box().has_area(), label + ": the actual visible enemy preparation suppresses an ordinary notice")
		check(game.hud.drawn_boxes.has(header) and game.hud.visible_hud_rects().has(header) and not recorded_text_in(header).is_empty(),
			label + ": only a genuine on-screen hero warning paints and reserves the danger header")
		await assert_no_command(header.get_center(),label + " visible hero warning")
		if size == Vector2i(1920,1200): await capture("enemy-hero-windup")
		# Move the camera, not the actors or warning state: the same native hero
		# attack now lies off-screen and must release its formerly visible HUD.
		game.camera.position += Vector3(200,0,0)
		await redraw()
		check(enemy.attack_queued and not game.target_warning_snapshot().is_empty(), label + ": the off-screen case retains its original real preparation")
		check(drawn_notice_box().has_area() and not game.hud.drawn_boxes.has(header) and not game.hud.visible_hud_rects().has(header),
			label + ": an off-screen enemy attack cannot suppress the notice or reserve a false hero header")
		if size == Vector2i(1920,1200): await capture("enemy-offscreen-windup")
		game.camera.transform = camera_transform
	remove_enemies()
	stand(Vector3(12,5,-10))
	enemy = game.spawn_creature(true,"basic")
	enemy.position = approach
	enemy.speed = 0.0
	enemy.attack_timer = 0.0
	game.update_creature(enemy,.001)
	check(enemy.attack_queued and enemy.attack_windup > 0.0 and game.attack_target_node(enemy) == pad.node,
		"Native enemy update really chooses the nearest live tower and starts its preparation")
	for size in [Vector2i(1920,1200),Vector2i(1920,1080),Vector2i(1440,900)]:
		root.size = size
		root.content_scale_size = size
		game.notify("防御塔蓄力警告优先于普通通知",3.0)
		await redraw()
		check(not drawn_notice_box().has_area(), "A real visible tower-targeted enemy preparation retains danger priority")
		check(not game.hud.drawn_boxes.has(header) and not game.hud.visible_hud_rects().has(header),
			"A genuine enemy attack against a tower must never reserve the hero-only danger header")
		var native_label := false
		for text: String in game.hud.all_labels: native_label = native_label or text.begins_with("蓄力 ")
		check(native_label, "Tower-targeted native preparation must retain its actually painted local warning")
		if size == Vector2i(1920,1200): await capture("enemy-tower-windup")
	remove_enemies()
	clear_transient_hud()
	root.size = original_size
	root.content_scale_size = original_content
	game.camera.transform = camera_transform
	stand(hero_position)
	game.phase = original_phase
	game.phase_time = original_phase_time
	game.spawn_rng.state = spawn_state
	game.squads.training_queues.assign(saved_finances.queues)
	group.clear()
	group.merge(group_state)
	restore_tag_commands(saved)
	for row: Dictionary in member_states:
		var member: BattleUnit = row.node
		for key: String in row.properties: member.set(key,row.properties[key])
		for pose: Dictionary in row.poses: (pose.node as Node3D).transform = pose.transform
		if row.had_amove: member.set_meta("amove_engaged",row.amove)
		elif member.has_meta("amove_engaged"): member.remove_meta("amove_engaged")
	check(finances() == saved_finances and game.phase_time == original_phase_time and game.spawn_rng.state == spawn_state,
		"Warning fixtures restore the original game phase, clock, paid queues, wallet and enemy random stream")
	check(orders() == saved.orders and game.enemies.is_empty(),
		"Warning fixtures restore prior hero/troop orders and leave no temporary native enemies")
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
	# The recorder keeps the previous full-observation surface so this
	# regression suite can continue exercising every legacy hitbox. Production
	# HUD instances default to the new scene-priority layout.
	replacement.minimal_display = false
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
	await capture_production_default("night")
	TransitionFixture.finish_for_fixture(game)
	press(KEY_1)
	game.world._process(6.1)
	remove_enemies()
	stand(HOME)
	clear_transient_hud()
	check(game.phase == "day" and game.day_number == 2, "The actual first dawn must generate the HUD's real day state")
	await default_layout("default-day")
	await capture("default-day")
	await capture_production_default("day")
	await scene_priority_default()
	check_live_data()
	await detail_navigation()
	await pause_notice_priority()
	await rich_exploration_page()
	await build_barracks()
	await army_gui()
	await help_folding_gui()
	await compact_objective_day_inputs()
	await compact_notice_inputs()
	await compact_skill_readability()
	await active_exploration_tag_inputs()
	await defense_and_memory_gui()
	await scale_and_hit_testing()
	await event_warning_priority()
	await urgent_feedback()
	if render_test:
		var file := FileAccess.open("res://build/clean-hud-layout.json",FileAccess.WRITE)
		check(file != null, "Open the local layout evidence file")
		if file != null: file.store_string(JSON.stringify(evidence,"\t"))
	print("NIGHTFALL_CLEAN_HUD_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAILED",checks,failures.size()])
	await cleanup()
	quit(0 if failures.is_empty() else 1)
