extends "res://tests/nightfall_logistics.gd"
## Artificial phase setup only; natural clearance and victory use real combat.
## Shares the real scene/input/navigation/conservation fixture, never production mocks.
## Precision stages use 5000 parts, extended clocks and direct hero positioning.
## Economy stages separately retain the original wallet, actors and 90-second day.

const ROUTE_OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var drawn_rects: Array[Rect2] = []
var drawn_labels: Array[Dictionary] = []
func _draw() -> void:
\tdrawn_rects.clear(); drawn_labels.clear(); super._draw()
func box(rect: Rect2, fill: Color = Color(.022,.035,.045,.88), outline: Color = Color('435455')) -> void:
\tdrawn_rects.append(rect); super.box(rect,fill,outline)
func label(value: String, point: Vector2, size_px: int, color: Color = Color('e7e1d3'), latin: bool = false) -> void:
\tvar actual: Font = display_font if latin else font
\tdrawn_labels.append({'text':value,'point':point,'width':actual.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x,'ascent':actual.get_ascent(size_px),'descent':actual.get_descent(size_px),'size':size_px,'latin':latin})
\tsuper.label(value,point,size_px,color,latin)
"""

var active_stage := "initialization"
var finished := false
var natural_mode := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	render_test = "--render-test" in args
	output_dir = "res://build/haul-routes"
	var index := args.find("--output-dir")
	if index >= 0 and index + 1 < args.size():
		var candidate := ProjectSettings.globalize_path(args[index + 1]).simplify_path()
		var allowed := ProjectSettings.globalize_path("res://build").simplify_path()
		if candidate.begins_with(allowed + "/"): output_dir = candidate
		else: check(false, "Route evidence must remain below the project build directory")
	root.size = VIEWPORTS[0]; root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT; root.content_scale_size = VIEWPORTS[0]
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.position = Vector2i(10000, 10000); root.hide()
	evidence = {"seed": SEED, "scope": "precision: 5000 parts/extended phases/direct hero positioning; economy: original wallet and clocks; scripted policy is not human difficulty balance", "completed": [], "captures": [], "routes": [], "hud": [], "economy": []}
	create_timer(300.0, true, false, true).timeout.connect(watchdog)
	call_deferred("run")

func watchdog() -> void:
	if finished: return
	check(false, "Haul route acceptance stalled in " + active_stage)
	await close_game(); finished = true; quit(1)

func clear_enemies() -> void:
	if not is_instance_valid(game): return
	game.clear_lobbers(); game.clear_summoners(); game.clear_warders()
	game.focus_target = null; game.focus_time = 0.0
	super.clear_enemies()

func observer() -> void:
	var script := GDScript.new(); script.source_code = ROUTE_OBSERVER
	check(script.reload() == OK, "Route observer forwards the actual HUD")
	var original: Control = game.hud
	var layer: Node = original.get_parent(); layer.remove_child(original); original.queue_free()
	var observed: Control = script.new(); observed.game = game; game.hud = observed; layer.add_child(observed)
	observed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await redraw()

func fresh(keep_wave: bool = false) -> void:
	natural_mode = false
	await super.fresh(keep_wave)
	route_out = 0; route_in = 0
	await observer()

func state() -> Dictionary:
	var result := super.state()
	var orders: Array[Dictionary] = []
	for group: Dictionary in game.squads.squads:
		var units: Array[Dictionary] = []
		for unit: BattleUnit in group.members:
			if not is_instance_valid(unit) or not unit.alive: continue
			units.append({"token":unit.get_instance_id(),"path":unit.path.duplicate(),"path_goal":unit.path_goal,"path_timer":unit.path_timer,"moving":unit.moving})
		var attack: Variant = group.attack_target
		var target: Variant = attack.get_ref() if attack is WeakRef else null
		orders.append({"id":int(group.id),"kind":String(group.kind),"order":String(group.order),"destination":group.destination,"origin":group.origin,"formation_index":group.formation_index,"target":target.get_instance_id() if is_instance_valid(target) else -1,"members":units})
	result.orders = orders
	return result

func route_ready(teams: int = 1) -> void:
	await fresh()
	barracks_index = await build_gui("barracks", BARRACKS)
	await build_gui("workshop", WORKSHOP)
	depot_index = await build_gui("depot", DEPOT)
	await dawn()
	for _team in teams: await train_gui()
	await close_drawer(); await advance(8.0 * teams + .1)
	check(game.squads.squads.size() == teams, "Real paid queues produce the requested carrier teams")
	await press(KEY_TAB)
	check(game.logistics.selected_hauler_count() == teams, "Actual Tab selects only living carrier teams")

func select_building(kind: String) -> void:
	if not game.construction.active: await press(KEY_Y)
	var target_page: int = Catalog.BUILDING_IDS.find(kind) / 3
	for _page in 3:
		var current_page: int = Catalog.BUILDING_IDS.find(String(game.construction.kind)) / 3
		if current_page == target_page: break
		await click_ui(game.hud.construction_page_rect(1 if target_page > current_page else -1))
	await click_ui(game.hud.construction_kind_rect(Catalog.BUILDING_IDS.find(kind) % 3))
	check(game.construction.active and String(game.construction.kind) == kind, "Actual bounded building pagination selects " + kind)

func field_point(index: int) -> Vector3:
	return game.logistics.fields[index].position

func right_field(index: int) -> void:
	await close_drawer(); camera_at(field_point(index))
	await mouse(game.camera.unproject_position(field_point(index)), true, MOUSE_BUTTON_RIGHT)

func only_team(index: int) -> void:
	await close_drawer()
	var member: BattleUnit = game.squads.squads[index].members[1]
	camera_at(member.position)
	await mouse(game.camera.unproject_position(member.position), true)
	check(game.squads.selected_ids == [index], "Actual left click selects the intended living carrier team")

func route_marker(index: int) -> bool:
	var marker: Node3D = game.logistics.fields[index].route_ring
	return is_instance_valid(marker) and marker.visible

func has_live_navigation(index: int = 0) -> bool:
	for member: BattleUnit in game.squads.squads[index].members:
		if is_instance_valid(member) and member.alive and not member.path.is_empty() and member.path_timer > 0.0: return true
	return false

func validate_hud(tag: String, help: bool = false) -> void:
	var before := state()
	for viewport: Vector2i in VIEWPORTS:
		root.size = viewport; root.content_scale_size = viewport; await redraw()
		check(not game.hud.drawn_labels.is_empty(), "Actual HUD observer receives real draws in " + tag)
		var help_bottom := 0.0
		for row: Dictionary in game.hud.drawn_labels:
			check(row.point.x >= 0 and row.point.x + float(row.width) <= 1440 and row.point.y - float(row.ascent) >= 0 and row.point.y + float(row.descent) <= 900, "Actual drawn glyph rectangle fits " + tag + " " + String(row.text))
			for character: String in String(row.text):
				var code := character.unicode_at(0)
				if code >= 0x4e00 and code <= 0x9fff: check(game.hud.font.has_char(code), "Actual HUD font contains " + character)
			if is_equal_approx(row.point.y, 648.0) and String(row.text).begins_with("工队"):
				check(row.point.x + float(row.width) <= 342, "True carrier status fits its296-pixel column")
			if String(row.text).contains("自动采运") and row.point.x >= 356 and row.point.y >= 628:
				check(row.point.x + float(row.width) <= 532 and row.point.y + float(row.descent) <= 660, "True restore caption fits the176-pixel hitbox")
			if help and is_equal_approx(row.point.x, 46.0) and row.point.y >= 230:
				help_bottom = maxf(help_bottom, row.point.y + float(row.descent))
		check(not help or help_bottom <= 692, "Actual final help glyph ends before the close button")
		if game.hud.haul_button_visible() and game.hud.medic_button_visible():
			check(not game.hud.HAUL_BUTTON_RECT.intersects(game.hud.MEDIC_BUTTON_RECT), "Actual mixed support hitboxes remain separate")
			var haul_rows: Array[Rect2] = []; var medic_rows: Array[Rect2] = []
			for row: Dictionary in game.hud.drawn_labels:
				var glyph := Rect2(Vector2(row.point.x,row.point.y-float(row.ascent)),Vector2(float(row.width),float(row.ascent)+float(row.descent)))
				if String(row.text).contains("自动采运"): haul_rows.append(glyph)
				if String(row.text).contains("医护合计") or String(row.text).contains("开启治疗") or String(row.text).contains("医护保持"): medic_rows.append(glyph)
			for haul: Rect2 in haul_rows:
				for medical: Rect2 in medic_rows: check(not haul.intersects(medical), "True mixed medical and route glyphs never overlap")
		(evidence.hud as Array).append({"tag":tag,"viewport":viewport,"labels":game.hud.drawn_labels.size(),"help_bottom":help_bottom})
	check(state() == before, "Real three-viewport HUD measurement cannot mutate resource state")
	root.size = VIEWPORTS[0]; root.content_scale_size = VIEWPORTS[0]; await redraw()

func capture(label: String) -> void:
	if not render_test: return
	check(DisplayServer.get_name() != "headless", "Route captures require a real graphical renderer")
	if DisplayServer.get_name() == "headless": return
	var before := state()
	for viewport: Vector2i in VIEWPORTS:
		root.size = viewport; root.content_scale_size = viewport
		game.world.night_mix = 1.0 if game.phase == "night" else 0.0
		game.world.apply_lighting(); await redraw()
		for _frame in 2: await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		check(image.get_size() == viewport and Vector2i(game.hud.get_viewport_rect().size) == viewport, "Route PNG/content match the real viewport")
		for row: Dictionary in game.hud.drawn_labels:
			if not (String(row.text).contains("采运") or String(row.text).contains("指定堆") or String(row.text).contains("自动") or String(row.text).contains("废料")): continue
			check(row.point.x >= 0 and row.point.x + float(row.width) <= 1440 and row.point.y - float(row.ascent) >= 0 and row.point.y + float(row.descent) <= 900, "Actual Chinese route glyph rectangle stays inside the scaled viewport")
			if row.point.x >= 46 and row.point.x < 542 and row.point.y >= 112 and row.point.y <= 734:
				check(row.point.x + float(row.width) <= 542, "Actual route detail text fits its existing drawer")
			for character: String in String(row.text):
				var code := character.unicode_at(0)
				if code >= 0x4e00 and code <= 0x9fff: check(game.hud.font.has_char(code), "Route font contains actual Chinese glyph " + character)
		var folder := ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
		var name := "%s-%dx%d" % [label, viewport.x, viewport.y]
		check(image.save_png(folder.path_join(name + ".png")) == OK, "Actual route capture saves below build")
		(evidence.captures as Array).append(name)
	check(state() == before, "Capture cannot spend, reserve, move or advance transport")
	root.size = VIEWPORTS[0]; root.content_scale_size = VIEWPORTS[0]
	await redraw()

func picking_and_mixed_orders() -> void:
	await route_ready()
	var center := field_point(0)
	var before := state()
	check(game.logistics.field_at_point(center) == 0, "The real heap center is pickable")
	var edge := center + Vector3(1.299, 0, 0); edge.y = game.outpost_height(edge)
	var outside := center + Vector3(1.301, 0, 0); outside.y = game.outpost_height(outside)
	check(game.logistics.field_at_point(edge) == 0 and game.logistics.field_at_point(outside) == -1, "Heap picking respects its actual 1.3-metre edge")
	check(game.logistics.field_at_point(center + Vector3(0, .751, 0)) == -1 and game.logistics.field_at_point(Vector3.INF) == -1, "Invalid ground height/nonfinite input cannot pick a heap")
	check(state() == before, "All heap hit tests are pure reads")
	for _read in 50: game.logistics.snapshot(); game.logistics.selected_hauler_count(); game.logistics.field_at_point(center)
	check(state() == before, "Repeated real presentation/picking reads cannot plan, reserve, pay or consume randomness")
	for viewport: Vector2i in VIEWPORTS:
		root.size = viewport; root.content_scale_size = viewport; await redraw()
		await only_team(0); await right_field(0)
		check(int(team_row().preferred_field) == 0 and String(game.squads.squads[0].order) == "haul", "True right-click heap assignment works in each viewport")
		camera_at(outside); await mouse(game.camera.unproject_position(outside), true, MOUSE_BUTTON_RIGHT)
		check(int(team_row().preferred_field) == -1 and String(game.squads.squads[0].order) == "move", "Real ground right-click outside the heap cancels its preference")
	root.size = VIEWPORTS[0]; root.content_scale_size = VIEWPORTS[0]
	await open_army(false); var parts: int = game.scrap
	await click_ui(game.hud.training_kind_rect(0)); await close_drawer(); await advance(6.1)
	check(game.squads.squads.size() == 2 and game.scrap == parts - 70, "Actual first-page training creates a paid escort")
	await press(KEY_TAB); await right_field(3)
	check(int(team_row().preferred_field) == 3 and String(game.squads.squads[0].order) == "haul" and String(game.squads.squads[1].order) == "move", "Mixed true right-click assigns the carrier and moves the selected escort")
	await capture("mixed-selected-route")
	var enemy: BattleUnit = game.spawn_creature(false); enemy.position = field_point(3); enemy.attack_timer = 100000.0
	await right_field(3)
	check(String(game.squads.squads[0].order) == "attack" and String(game.squads.squads[1].order) == "attack" and int(team_row().preferred_field) == -1, "Real enemy silhouette wins over the heap behind it")
	clear_enemies()
	game.squads.cancel_selection(); before = game.logistics.snapshot()
	await right_field(2)
	check(game.logistics.snapshot() == before and game.squads.selected_count() == 0, "Unselected heap click keeps ordinary hero movement without changing carrier orders")
	var escort: BattleUnit = game.squads.squads[1].members[1]
	camera_at(escort.position); await mouse(game.camera.unproject_position(escort.position), true)
	check(game.squads.selected_ids == [1], "Actual left click selects the escort alone")
	await right_field(2)
	check(String(game.squads.squads[1].order) == "move" and int(team_row().preferred_field) == -1, "Selected escort alone retains ordinary movement at a heap")
	await build_gui("infirmary", Vector3(-7.5,5,2.5)); await train_gui()
	await click_ui(game.hud.training_kind_rect(2)); await close_drawer(); await advance(17.1)
	check(game.squads.squads.size() == 4, "Real queues produce a second hauler and a medical group alongside the escort")
	if game.squads.squads.size() < 4: return
	await press(KEY_TAB); await open_army(); await click_ui(game.hud.MEDIC_BUTTON_RECT)
	check(bool(game.squads.squads[3].therapy_enabled), "True medical toggle enables the selected medic before mixed movement")
	await close_drawer(); await right_field(3)
	check(int(team_row(0).preferred_field) == 3 and int(team_row(2).preferred_field) == 3 and String(game.squads.squads[0].order) == "haul" and String(game.squads.squads[2].order) == "haul", "True four-group right click assigns both real carrier groups")
	check(String(game.squads.squads[1].order) == "move" and String(game.squads.squads[3].order) == "move" and bool(game.squads.squads[3].therapy_enabled), "True mixed command moves escort and medic while preserving its existing medical switch")
	await capture("two-carriers-escort-enabled-medic-route")
	var heap_node: Node = game.logistics.fields[2].node; heap_node.queue_free()
	before = state()
	check(game.logistics.field_at_point(field_point(2)) == -1 and not bool(game.logistics.command_selected_field(2).ok) and state() == before, "Controlled retiring actual heap node is unpickable and rejects assignment without changing orders")

func repeated_physical_cycle() -> void:
	await route_ready(); await right_field(4)
	if not await wait_for(func() -> bool: return has_live_navigation(), 20, "True assigned carrier has live nonempty south-gate navigation"): return
	var moving_before := state(); await right_field(4)
	check(has_live_navigation() and state() == moving_before, "Repeating the chosen heap while genuinely navigating preserves all three actual path/path_goal/path_timer values and squad destinations")
	camera_at(game.squads.squads[0].members[1].position); await capture("real-moving-route-nonempty-path")
	if not await wait_for(func() -> bool: return float(team_row().loading_progress) > .1, 160, "Real distant heap arrival and loading"): return
	check(int(team_row().field) == 4 and route_out >= 3, "Each actual carrier reaches the assigned far heap through the south gate")
	camera_at(field_point(4)); await capture("distant-real-loading")
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().cargo) == 24, 5, "Completed genuine three-second load"): return
	check(int(game.logistics.fields[4].remaining) == 72, "Three real members withdraw exactly eight each from the chosen heap")
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().delivered) == 24, 160, "First physical station delivery"): return
	check(route_in >= 3 and int(team_row().preferred_field) == 4, "First unload retains the chosen route after each member crosses home")
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().cargo) == 24, 160, "Second physical visit to the same distant heap"): return
	check(int(game.logistics.fields[4].remaining) == 48 and route_out >= 6, "A second true outbound trip revisits the selected heap rather than choosing nearer stock")
	for index in 4: check(game.logistics.fields[index].remaining == 96, "Other heaps remain untouched during the fixed resource line")
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().delivered) == 48, 160, "Second actual per-member unload"): return
	(evidence.routes as Array).append({"field": 4, "delivered": 48, "outward_gate_crossings": route_out, "homeward_gate_crossings": route_in, "seconds": elapsed})
	camera_at(DEPOT); await capture("second-fixed-route-delivered")

func changes_preserve_real_progress() -> void:
	await route_ready(); await right_field(0)
	if not await wait_for(func() -> bool: return float(team_row().loading_progress) >= .96, 140, "Actual2.9-second old-heap load"): return
	var before := state(); await right_field(0)
	check(state() == before, "Repeating the same real heap order preserves exact loading progress")
	await right_field(1)
	check(int(team_row().preferred_field) == 1 and float(team_row().loading_progress) == 0.0 and game.logistics.fields[0].claimed_by == -1 and game.logistics.fields[0].remaining == 96, "Changing heaps cancels incomplete loading and releases the old reservation without withdrawing goods")
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().cargo) == 24, 160, "Actual new-heap load"): return
	if not await wait_for(func() -> bool: return has_live_navigation(), 10, "Loaded carriers own actual nonempty returning paths"): return
	before = state(); await right_field(4)
	check(game.logistics.snapshot().cargo == 24 and game.logistics.fields[1].remaining == 72 and game.logistics.fields[4].remaining == 96 and int(team_row().preferred_field) == 4, "Loaded route change retains real cargo and does not refund already removed stock")
	check((before.stock.teams[0].members as Array) == (game.logistics.snapshot().teams[0].members as Array), "Loaded automatic route change preserves actual returning member paths/timers")
	check(before.orders == state().orders, "Loaded route change preserves actual member path/path timer and squad route")
	if not await wait_for(func() -> bool: return float(team_row().unloading_progress) > .1, 160, "Actual individual unload progress"): return
	step(maxf(0.0, .99 - float(team_row().unloading_progress)))
	before = state(); await right_field(4)
	check(state() == before, "Repeating the chosen route preserves exact per-member unloading progress")
	var timer_token := -1
	for row: Dictionary in team_row().members:
		if int(row.cargo) > 0 and float(row.unloading_progress) >= .98:
			timer_token = int(row.token); break
	check(timer_token >= 0, "A real carrier owns approximately0.99 seconds of unfinished unloading before a changed target")
	before = state(); await right_field(2)
	check(before.orders == state().orders and before.stock.teams[0].members == game.logistics.snapshot().teams[0].members and int(team_row().preferred_field) == 2, "Changing the heap during actual0.99 unloading preserves member path, live station identity and all unload timers")
	check(game.logistics.fields[2].remaining == 96, "Changed new heap cannot withdraw before the old load settles")
	step(.02)
	check(timer_token < 0 or int((instance_from_id(timer_token) as BattleUnit).get_meta("haul_cargo", -1)) == 0, "The actual0.99-second carrier settles at1.01 seconds despite changing its future heap")
	await capture("loaded-changed-route-unload")
	if not await wait_for(func() -> bool: return game.logistics.snapshot().delivered == 24, 5, "Existing goods settle before new route"): return
	check(game.logistics.fields[2].remaining == 96, "New stock cannot load before the old physical cargo is redeemed")
	if not await wait_for(func() -> bool: return int(team_row().field) == 2, 5, "Changed new route begins after unloading"): return
	for order: String in ["move", "guard", "recall", "hold"]:
		await right_field(4)
		if order == "move": game.squads.command_move(HOME)
		elif order == "guard": game.squads.command_guard(HOME)
		else: game.squads.set_order(order)
		check(int(team_row().preferred_field) == -1 and not bool(team_row().automatic), "Manual " + order + " explicitly cancels the heap preference")
	await right_field(4); await aim_at(game.squads.squads[0].members[1].position); await press(KEY_O)
	check(int(team_row().preferred_field) == -1, "Actual O order also clears the selected resource line")
	await right_field(4); await open_army(); await click_ui(game.hud.HAUL_BUTTON_RECT)
	check(int(team_row().preferred_field) == -1 and bool(team_row().automatic), "Actual existing F3 resume control explicitly restores automatic heap selection")
	await close_drawer()

func contention_and_finite_remainder() -> void:
	await route_ready(2); await right_field(4); await advance(.2)
	check(int(team_row(0).preferred_field) == 4 and int(team_row(1).preferred_field) == 4 and int(team_row(0).field) == 4 and int(team_row(1).field) == -1, "Two selected teams retain the same intent while only one reserves the real heap")
	await advance(3.0)
	check(String(team_row(1).state) == "waiting_field" and String(team_row(1).reason).contains("预约"), "Contending team waits for the assigned heap instead of silently taking nearer stock")
	for index in 4: check(game.logistics.fields[index].claimed_by == -1 and game.logistics.fields[index].remaining == 96, "Unchosen heaps stay free during contention")
	await open_army(); await capture("selected-heap-reservation-wait"); await close_drawer()
	if not await wait_for(func() -> bool: return int(game.logistics.snapshot().cargo) >= 24, 160, "First contender actually loads"): return
	if not await wait_for(func() -> bool: return int(team_row(1).field) == 4 or int(team_row(1).cargo) > 0, 1.0, "Second contender's actual next planning interval"): return
	if not await wait_for(func() -> bool: return game.logistics.fields[4].remaining == 0 and int(team_row(0).preferred_field) == -1 and int(team_row(1).preferred_field) == -1, 500, "All genuine fixed-heap goods unload"): return
	check(int(team_row(0).preferred_field) == -1 and int(team_row(1).preferred_field) == -1, "Both teams revert to original automatic choice only after the exhausted line is delivered")
	await open_army(false); await click_ui(game.hud.training_kind_rect(0)); await close_drawer(); await advance(6.1); await press(KEY_TAB)
	var before := state(); await right_field(4)
	check(state() == before and game.squads.squads.size() == 3, "A real empty heap rejects mixed assignment without moving its escort or changing any carrier order")
	# Boundary seed: finite96 is naturally divisible by8. This explicitly injected
	# five-part remainder tests atomic transfer; it is not a production income claim.
	await route_ready(); game.logistics.fields[0].remaining = 5; game.logistics.lost = 91
	game.logistics._refresh_field(game.logistics.fields[0]); ledger("Explicit five-part boundary seed")
	await right_field(0)
	if not await wait_for(func() -> bool: return game.logistics.snapshot().cargo == 5, 160, "Controlled five-part remainder physically loads"): return
	var members: Array = team_row().members
	check(int(members[0].cargo) == 5 and int(members[1].cargo) == 0 and int(members[2].cargo) == 0 and int(team_row().preferred_field) == 0, "Sub-eight remainder belongs only to one real token and retains preference until unload")
	if not await wait_for(func() -> bool: return game.logistics.snapshot().delivered == 5, 160, "Five actual goods physically settle"): return
	check(int(team_row().preferred_field) == -1, "The final small load clears exhausted intent after actual settlement")
	(evidence.routes as Array).append({"fixture": "explicit remainder5/lost91 conservation boundary seed", "actual_loaded": 5, "actual_delivered": 5})

func casualty_and_replacement() -> void:
	await route_ready(); await right_field(0)
	if not await wait_for(func() -> bool: return game.logistics.snapshot().cargo == 24, 160, "Cargo before real token death"): return
	var member: BattleUnit = game.squads.squads[0].members[0]
	var token := member.get_instance_id()
	var enemy: BattleUnit = game.spawn_creature(false); enemy.position = member.position + Vector3(0, 0, 3)
	member.hurt(100000.0, enemy); clear_enemies(); await process_frame; step(.01)
	check(game.logistics.snapshot().lost == 8 and game.logistics.snapshot().cargo == 16 and game.logistics.fields[0].remaining == 72 and int(team_row().preferred_field) == 0, "Actual defeat loses only the dead member's eight goods while preserving the living route")
	var balance: int = game.scrap; await press(KEY_L); step(.01)
	check(game.scrap == balance - 22 and game.logistics.snapshot().cargo == 16 and game.logistics.snapshot().lost == 8, "Actual L replacement charges22 and cannot recreate dead cargo")
	var replacement: BattleUnit = game.squads.squads[0].members[0]
	check(replacement.get_instance_id() != token and int(replacement.get_meta("haul_cargo", -1)) == 0, "Replacement has a genuinely new empty cargo token")
	if not await wait_for(func() -> bool: return game.logistics.snapshot().delivered == 16, 160, "Surviving members' real delivery"): return
	check(int(team_row().preferred_field) == 0 and game.logistics.snapshot().lost == 8, "Survivor settlement preserves fixed intent and does not repay the dead goods")
	await capture("replacement-empty-survivors-delivered")

func sealed_route_and_station_rebuild() -> void:
	await route_ready()
	stand(HOME)
	for index in game.world.tower_pads.size(): game.damage_tower(index, float(game.world.tower_pads[index].hp))
	for x: float in [-11.0, 11.0]: check(game.build_structure_at(Vector3(x, 5, 7.5), "barracks"), "Real flank barracks seal the row ends")
	var gap := -1
	for x: float in [-7.5, -4.5, -1.5, 1.5, 4.5, 7.5]:
		var index: int = game.world.tower_pads.size()
		check(game.build_tower_at(Vector3(x, 5, 7.5)), "Real occupied tower cells seal the route")
		if x == 1.5: gap = index
	await right_field(4); await advance(5.0)
	check(String(team_row().state) == "waiting_field" and int(team_row().preferred_field) == 4 and game.logistics.snapshot().cargo == 0, "Unreachable assigned heap waits instead of selecting a different route")
	for field: Dictionary in game.logistics.fields: check(field.remaining == 96 and field.claimed_by == -1, "A sealed route cannot reserve another heap or remove stock")
	camera_at(Vector3(0, 5, 7.5)); await capture("actual-sealed-preferred-route")
	if gap < 0: return
	game.damage_tower(gap, float(game.world.tower_pads[gap].hp))
	if not await wait_for(func() -> bool: return game.logistics.snapshot().cargo == 24, 200, "Assigned route recovers through the real demolished gap"): return
	var old_model: Node = game.districts.plots[depot_index].model; var old_token := old_model.get_instance_id()
	game.districts.damage(depot_index, 100000.0); await advance(3.0)
	check(game.logistics.snapshot().cargo == 24 and game.logistics.snapshot().delivered == 0 and String(team_row().state) == "waiting_home" and int(team_row().preferred_field) == 4, "Destroyed real station cannot pay remotely or discard the assigned line")
	depot_index = await build_gui("depot", DEPOT)
	check((game.districts.plots[depot_index].model as Node).get_instance_id() != old_token, "Same-site rebuild uses a genuinely different station token")
	if not await wait_for(func() -> bool: return game.logistics.snapshot().delivered == 24, 200, "Loaded members reach the genuine rebuilt station"): return
	check(int(team_row().preferred_field) == 4, "Physical reopened-route settlement retains the chosen heap")
	camera_at(DEPOT); await capture("real-rebuilt-station-delivery")

func freeze_sunset_and_cleanup() -> void:
	await route_ready(); await right_field(0)
	if not await wait_for(func() -> bool: return float(team_row().loading_progress) > .2, 160, "Partial real load before freeze"): return
	await press(KEY_F1); await press(KEY_ESCAPE)
	check(game.phase == "paused", "Actual F1 pauses while preserving the route selection")
	var before := state(); game.simulate(5); game.logistics.advance(5); game.squads.advance(5)
	check(state() == before, "Pause freezes actual fixed-route timers, positions, stock and wallet")
	var rejected: Dictionary = game.logistics.command_selected_field(4)
	check(not bool(rejected.ok) and state() == before, "Paused route commands are inert")
	await open_army(); await capture("paused-fixed-route"); await close_drawer(); await press(KEY_ESCAPE)
	var cost: int = game.run.memory_cost(); var balance: int = game.scrap
	check(game.run.pending == 0, "Paid draft begins without a synthetic free offer")
	await press(KEY_V)
	check(game.phase == "draft" and game.scrap == balance - cost, "Actual V pays the sole wallet for its real offer")
	before = state(); game.simulate(5); game.logistics.advance(5); game.squads.advance(5)
	check(state() == before, "Paid card choice freezes real resource-line progress")
	await press(KEY_1); check(game.phase == "day" and int(team_row().preferred_field) == 0, "Real card selection resumes the original route")
	var stock: Dictionary = game.logistics.snapshot(); night_fixture(); await advance(10)
	check(game.logistics.snapshot().remaining == stock.remaining and game.logistics.snapshot().cargo == 0 and int(team_row().preferred_field) == 0 and float(team_row().loading_progress) == 0.0, "Actual sunset cancels unfinished loading but retains fixed intent without new stock transfer")
	await dawn()
	if not await wait_for(func() -> bool: return game.logistics.snapshot().cargo == 24, 160, "Next real day resumes the retained assigned heap"): return
	await press(KEY_F1); await press(KEY_ESCAPE)
	before = state(); game.simulate(5); game.logistics.advance(5); game.squads.advance(5)
	check(state() == before and game.logistics.snapshot().cargo == 24 and int(team_row().preferred_field) == 0, "Pause also freezes the genuine loaded fixed route without deleting cargo or intent")
	await press(KEY_ESCAPE)
	stock = game.logistics.snapshot(); night_fixture()
	if not await wait_for(func() -> bool: return game.logistics.snapshot().delivered == 24, 160, "Existing loaded cargo physically returns at night"): return
	await advance(6)
	check(game.logistics.snapshot().remaining == stock.remaining and int(team_row().preferred_field) == 0 and game.logistics.snapshot().cargo == 0, "Night permits existing delivery but never renews chosen-heap loading")
	await open_army(); await capture("night-retained-route"); await close_drawer()
	var root_token := game.get_instance_id(); var actor_tokens: Array[int] = []
	for group: Dictionary in game.squads.squads:
		for actor: BattleUnit in group.members:
			if is_instance_valid(actor): actor_tokens.append(actor.get_instance_id())
	game.end_defeat("指定采运生命周期验收")
	check(game.logistics.snapshot().remaining == 0 and game.logistics.snapshot().teams.is_empty() and game.squads.squads.is_empty(), "Real defeat clears all fixed-route intents and actors")
	await press(KEY_ENTER)
	for _frame in 240:
		await create_timer(.02,true,false,true).timeout
		if is_instance_valid(current_scene) and current_scene.get_instance_id() != root_token:
			game = current_scene as Node3D; game.set_process(false); game.world.set_process(false); break
	check(is_instance_valid(game) and game.get_instance_id() != root_token and game.run.seed_value == SEED and game.phase == "draft" and not is_instance_id_valid(root_token), "Actual Enter replaces and releases the old scene using the same production seed")
	if not is_instance_valid(game) or game.get_instance_id() == root_token: return
	game.set_process(false); game.world.set_process(false); await observer()
	for token: int in actor_tokens: check(not is_instance_id_valid(token), "Same-seed retry releases every old actual carrier token")
	check(game.logistics.snapshot().remaining == 480 and game.logistics.snapshot().teams.is_empty(), "Retry starts fresh480 without inherited preferred lines")
	await route_ready(); await right_field(4)
	check(int(team_row().preferred_field) == 4 and route_marker(4), "Victory fixture first owns a real selected fixed route and marker")
	var field_tokens: Array[int] = []
	for field: Dictionary in game.logistics.fields: field_tokens.append((field.node as Node).get_instance_id())
	game.day_number = game.max_nights(); TransitionFixture.finish_for_fixture(game); await process_frame
	check(game.phase == "ended" and game.victory and game.logistics.snapshot().remaining == 0 and game.logistics.snapshot().teams.is_empty(), "Actual victory clears existing fixed intent and finite route state")
	for token: int in field_tokens: check(not is_instance_id_valid(token), "Actual victory releases every real heap and its selected marker")

func natural_scene() -> void:
	await close_game(); natural_mode = true
	check(RunSession.queue_request(self, SEED, "siege"), "Natural economic route accepts the fixed production seed")
	game = load("res://scenes/nightfall.tscn").instantiate(); root.add_child(game); current_scene = game
	for _frame in 5: await process_frame
	game.set_process(false); game.world.set_process(false); await observer(); await press(KEY_1)
	elapsed = 0.0; route_out = 0; route_in = 0
	check(game.scrap == 90 and game.phase_time == 105.0 and game.tower_count() == 2, "Economic route retains original ninety parts,105-second night and two towers")

func natural_tick() -> void:
	game.aim = game.hero.position + Vector3(0, 0, 8)
	if game.gate_pressure() > 0: game.cast(0)
	if game.hero.hp < game.hero.max_hp * .6: game.cast(1); game.cast(4)
	if game.gate_pressure() >= 6: game.cast(3)
	game.simulate(STEP); elapsed += STEP; ledger("Natural unextended economic step")

func natural_walk(point: Vector3, maximum: float = 20.0) -> bool:
	camera_at(point); await mouse(game.camera.unproject_position(point), true, MOUSE_BUTTON_RIGHT)
	for frame in ceili(maximum / STEP):
		if planar(game.hero.position, point) < .35: return true
		if game.phase != "day": break
		natural_tick()
		if frame % 100 == 99: await process_frame
	check(false, "Natural hero route failed to reach its real interaction position")
	return false

func natural_economic_routes() -> void:
	for destination: int in [0, 4]:
		await natural_scene()
		camera_at(Vector3(0, 5, 10)); await mouse(game.camera.unproject_position(Vector3(0, 5, 10)), true, MOUSE_BUTTON_RIGHT)
		var first_night_elapsed := 0.0
		var first_night_cutoff: Dictionary = {}
		# Bound actual residual combat; the production assault deadline is unchanged.
		for frame in ceili(240.0 / STEP):
			if game.phase != "night": break
			natural_tick()
			first_night_elapsed += STEP
			if first_night_cutoff.is_empty() and first_night_elapsed >= game.NIGHT_LENGTH:
				first_night_cutoff = TransitionFixture.deadline_evidence(game, first_night_elapsed)
			if frame % 100 == 99: await process_frame
		TransitionFixture.record_natural_receipt(game, evidence, "opening", first_night_elapsed, first_night_cutoff)
		check(game.phase == "draft" and game.hero.alive and game.beacon_hp > 0, "Unmodified first night survives the fixed actual skill policy")
		if game.phase != "draft": return
		var night_parts: int = game.scrap; var first_deaths: int = game.kills
		await press(KEY_1)
		check(game.phase_time == 90.0 and game.scrap == night_parts, "Actual dawn preserves first-night earnings and the original90-second day")
		var nearest: Dictionary = {}; var distance := INF
		for source: Dictionary in game.world.salvage:
			if source.collected: continue
			var candidate := planar(game.hero.position, source.position)
			if candidate < distance: distance = candidate; nearest = source
		check(not nearest.is_empty(), "Original natural salvage supplies the missing construction budget")
		if nearest.is_empty() or not await natural_walk(nearest.position): return
		var before_parts: int = game.scrap; await press(KEY_F)
		check(game.scrap > before_parts and bool(nearest.collected), "Real F collects the genuine hero crate without adding fixture money")
		var crate_income: int = game.scrap - before_parts
		if not await natural_walk(HOME): return
		for row: Dictionary in [{"kind":"barracks", "point":BARRACKS}, {"kind":"workshop", "point":WORKSHOP}, {"kind":"depot", "point":DEPOT}]:
			await select_building(row.kind); camera_at(row.point); await mouse(game.camera.unproject_position(row.point)); game._process(0)
			var preview: Dictionary = game.construction.snapshot(); var balance: int = game.scrap
			check(bool(preview.valid), "Natural actual paid building preview is valid: " + String(row.kind))
			await mouse(game.camera.unproject_position(row.point), true); await press(KEY_ESCAPE)
			check(game.scrap == balance - int(Catalog.building(row.kind).cost), "Natural construction pays its exact original cost")
		await train_gui(); await close_drawer()
		var after_payments: int = game.scrap
		for frame in 81:
			natural_tick()
			if frame % 50 == 49: await process_frame
		check(game.squads.squads.size() == 1, "Unextended daylight completes the actual paid eight-second training")
		if game.squads.squads.is_empty(): return
		await press(KEY_TAB); await right_field(destination)
		var sent_at: float = 90.0 - game.phase_time
		var first_load := -1.0; var first_delivery := -1.0
		while game.phase == "day":
			if first_load < 0 and int(game.logistics.snapshot().cargo) > 0: first_load = 90.0 - game.phase_time
			if first_delivery < 0 and int(game.logistics.snapshot().delivered) > 0: first_delivery = 90.0 - game.phase_time
			natural_tick()
			if int(elapsed * 10) % 100 == 0: await process_frame
		var sunset: Dictionary = game.logistics.snapshot(); var sunset_parts: int = game.scrap
		check(game.phase == "night" and int(team_row().preferred_field) == destination, "Natural original90-second sunset retains the actual chosen route")
		for frame in 100:
			natural_tick()
			if frame % 50 == 49: await process_frame
		check(game.logistics.snapshot().remaining == sunset.remaining, "Natural first ten night seconds never load additional chosen-heap stock")
		(evidence.economy as Array).append({"field":destination, "opening":90, "first_night_deaths":first_deaths, "first_night_parts":night_parts, "real_crate_income":crate_income, "building_training_cost":290, "after_payments":after_payments, "day_seconds":90, "assigned_at_day_second":sent_at, "first_loaded_at_day_second":first_load, "first_delivered_at_day_second":first_delivery, "sunset":sunset, "sunset_parts":sunset_parts, "ten_night_seconds":game.logistics.snapshot(), "ten_night_parts":game.scrap, "hero_hp":game.hero.hp, "beacon_hp":game.beacon_hp})
		check(first_load >= sent_at and (first_delivery == -1.0 or first_delivery >= first_load), "Natural route reports actual timings without requiring every distance to deliver before sunset")
		camera_at(DEPOT); await open_army(); await capture("natural-route-%d-night-10-seconds" % destination); await close_drawer()
	if (evidence.economy as Array).size() == 2:
		var near: Dictionary = evidence.economy[0]; var far: Dictionary = evidence.economy[1]
		check(near.first_night_parts == far.first_night_parts and near.after_payments == far.after_payments, "Near/far routes use identical naturally earned construction funds")
		if float(near.first_delivered_at_day_second) >= 0 and float(far.first_delivered_at_day_second) >= 0:
			check(float(far.first_delivered_at_day_second) > float(near.first_delivered_at_day_second), "Actual far route has a later first physical delivery than the near route")
		for row: Dictionary in [near,far]:
			if float(row.first_delivered_at_day_second) < 0: check(int(row.sunset.delivered) == 0, "Natural undelivered route is explicitly reported without inventing its arrival")

func contextual_route_hud() -> void:
	await route_ready(); await right_field(4); await redraw()
	check(route_marker(4) and not route_marker(0), "Only the selected assigned heap has the actual local route ring")
	stand(HOME)
	for viewport: Vector2i in VIEWPORTS:
		root.size = viewport; root.content_scale_size = viewport; camera_at(HOME); await redraw()
		var former_prompt := Rect2(435,682,570,40)
		check(game.interaction_prompt().is_empty() and not game.hud.drawn_rects.has(former_prompt) and not game.hud.live_panel_rects().has(former_prompt), "Actual empty-ground selection removes the duplicate central prompt and its hit region")
		var selection_strip: Rect2 = game.hud.SELECTED_SQUAD_RECT
		check(game.hud.drawn_rects.has(selection_strip) and game.hud.live_panel_rects().has(selection_strip), "The actual selected-squad strip remains drawn and intercepts input")
		var before := state(); await click_ui(selection_strip, MOUSE_BUTTON_RIGHT)
		check(state() == before and int(team_row().preferred_field) == 4, "True right-click inside the visible selection strip cannot alter the chosen world route")
		var screen: Vector2 = former_prompt.get_center() * game.hud.get_viewport_rect().size / Vector2(1440,900)
		check(game.ground_point(screen).is_finite(), "Former prompt area contains a genuine world ground target")
		await mouse(screen, true, MOUSE_BUTTON_RIGHT)
		check(int(team_row().preferred_field) == -1 and String(game.squads.squads[0].order) == "move", "True right-click through the freed central prompt area changes the actual world command")
		await right_field(4)
		check(int(team_row().preferred_field) == 4, "Actual heap input restores the chosen route after the released-area regression")
	root.size = VIEWPORTS[0]; root.content_scale_size = VIEWPORTS[0]; await redraw()
	await validate_hud("default-selected-route")
	await capture("default-selected-local-route")
	await open_army(); await redraw()
	var text := ""
	for row: Dictionary in game.hud.drawn_labels: text += String(row.text) + "\n"
	check(text.contains("指定堆5") and text.contains("恢复自动采运"), "Existing F3 carrier detail explains the chosen heap and restoring automatic selection")
	check(game.hud.drawn_rects.has(Rect2(24,112,540,622)) and game.hud.haul_button_visible(), "Actual route details reuse the established F3 drawer and control")
	await validate_hud("f3-real-selected-route")
	# Typography boundary fixtures use the real font, all production state titles,
	# multi-digit identifiers and maximum cargo; they do not change route state.
	for state_title: String in game.logistics.STATE_TITLES.values():
		for identifier: int in [1, 10, 99]:
			var status := "工队%d · 指定堆5 · %s · 货24" % [identifier,state_title]
			check(game.hud.font.get_string_size(status,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x <= 296, "True font fits complete worst-case carrier status: " + status)
	for caption: String in ["恢复自动采运", "暂停 · 自动采运"]:
		check(game.hud.font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x <= 164, "True font fits full restore caption within actual button padding")
	await capture("f3-selected-route-details")
	await close_drawer(); await press(KEY_F3); await click_ui(game.hud.details_tab_rect(4)); await redraw()
	check(game.hud.detail_tab == "help", "Actual F3 operation page exposes revised route help")
	await validate_hud("full-help-with-route-command",true); await capture("f3-complete-route-help")
	await close_drawer(); await build_gui("infirmary",Vector3(-7.5,5,2.5)); await open_army()
	var balance: int = game.scrap; await click_ui(game.hud.training_kind_rect(2)); await close_drawer(); await advance(9.1)
	check(game.squads.squads.size() == 2 and game.scrap == balance - 90, "True paid production creates the medical group for mixed HUD")
	await press(KEY_TAB); await open_army(); await validate_hud("mixed-real-carrier-medic"); await capture("mixed-carrier-medic-details")
	await close_drawer(); await press(KEY_F1); await press(KEY_ESCAPE); await open_army()
	await validate_hud("paused-mixed-carrier-medic"); await capture("paused-mixed-carrier-medic-details")
	await close_drawer(); await press(KEY_ESCAPE); await open_army()
	var before := state(); await click_ui(game.hud.HAUL_BUTTON_RECT, MOUSE_BUTTON_RIGHT)
	check(state() == before, "Right-clicking the existing restore button cannot send a hidden world command")
	await click_ui(game.hud.HAUL_BUTTON_RECT); await close_drawer(); await advance(.1)
	check(int(team_row().preferred_field) == -1 and not route_marker(4), "Actual restore-automatic input removes the selected route ring")
	await capture("restored-original-automatic")
	if not await wait_for(func() -> bool: return game.logistics.snapshot().cargo == 24, 160, "Original automatic closest-heap hauling remains active"): return
	check(game.logistics.fields[0].remaining == 72 or game.logistics.fields[1].remaining == 72, "Original automatic transport still chooses a reachable nearby source")

func run() -> void:
	var cases := {"input":picking_and_mixed_orders, "cycle":repeated_physical_cycle, "redirect":changes_preserve_real_progress, "reservation":contention_and_finite_remainder, "loss":casualty_and_replacement, "barrier":sealed_route_and_station_rebuild, "freeze":freeze_sunset_and_cleanup, "economy":natural_economic_routes, "hud":contextual_route_hud}
	var args := OS.get_cmdline_user_args(); var selected: Array = cases.keys()
	var index := args.find("--case")
	if index >= 0 and index + 1 < args.size(): selected = [args[index + 1]]
	for name: String in selected:
		if not cases.has(name): check(false, "Unknown haul-route stage " + name); break
		active_stage = name; print("HAUL_ROUTE_STAGE_BEGIN ", name)
		await (cases[name] as Callable).call()
		print("HAUL_ROUTE_STAGE_END ", name, " checks=", checks, " failures=", failures.size())
		(evidence.completed as Array).append(name)
		if not failures.is_empty(): break
	await close_game(); evidence.checks = checks; evidence.failures = failures
	var folder := ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("haul-routes.json"), FileAccess.WRITE)
	check(file != null, "Route evidence opens only under build")
	evidence.checks = checks; evidence.failures = failures
	if file != null: file.store_string(JSON.stringify(evidence, "\t")); file.close()
	finished = true; print("HAUL_ROUTE_RESULT checks=", checks, " failures=", failures.size())
	if failures.is_empty():
		if index < 0 and (evidence.completed as Array) == cases.keys():
			print("NIGHTFALL_HAUL_ROUTES_OK checks=",checks," failures=0 full_suite=true")
		else:
			print("NIGHTFALL_HAUL_ROUTES_CASE_OK checks=",checks," failures=0 full_suite=false stages=",JSON.stringify(evidence.completed))
	else:
		print("NIGHTFALL_HAUL_ROUTES_FAILED checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
