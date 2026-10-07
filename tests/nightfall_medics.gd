extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
## Production infirmary, selected paid support, real movement/damage and ledgers.
## Explicit 5000 parts/long phases isolate rules; they are not difficulty proof.
const Catalog := preload("res://scripts/outpost_catalog.gd")
const Grid := preload("res://scripts/construction_grid.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
const RunSession := preload("res://scripts/run_session.gd")
const SEED := 20261006
const STEP := .05
const HOME := Vector3(0, 5, 3.1)
const BARRACKS := Vector3(7, 5, -8.5)
const INFIRMARY := Vector3(-7.5, 5, -8.5)
const STATION := Vector3(-4, 5, 6)
const VIEWPORTS := [Vector2i(1920, 1200), Vector2i(1920, 1080), Vector2i(1440, 900)]
const OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var drawn_rects: Array[Rect2] = []
var drawn_labels: Array[Dictionary] = []
var drawer := false
func _draw() -> void:
\tdrawn_rects.clear(); drawn_labels.clear(); drawer = false
\tsuper._draw()
func box(rect: Rect2, fill: Color = Color(.022,.035,.045,.88), outline: Color = Color('435455')) -> void:
\tdrawn_rects.append(rect)
\tif rect == Rect2(24,112,540,622): drawer = true
\tif rect == Rect2(428,692,112,30): drawer = false
\tsuper.box(rect,fill,outline)
func label(value: String, point: Vector2, size_px: int, color: Color = Color('e7e1d3'), latin: bool = false) -> void:
\tvar actual: Font = display_font if latin else font
\tdrawn_labels.append({'text':value,'point':point,'width':actual.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x,'descent':actual.get_descent(size_px),'drawer':drawer})
\tsuper.label(value,point,size_px,color,latin)
"""
var game: Node3D
var checks := 0
var failures: Array[String] = []
var render_test := false
var output_dir := "res://build/medics"
var hurt_events: Array[Dictionary] = []
var evidence: Dictionary = {"fixture_parts": 5000, "fixture_phase_seconds": 10000, "seed": SEED,
 "captures": [], "completed": [], "routes": [], "support": {}}

func _initialize() -> void:
 var args := OS.get_cmdline_user_args()
 render_test = "--render-test" in args
 var index := args.find("--output-dir")
 if index >= 0 and index + 1 < args.size():
  var candidate := ProjectSettings.globalize_path(args[index + 1]).simplify_path()
  var allowed := ProjectSettings.globalize_path("res://build").simplify_path()
  if candidate.begins_with(allowed + "/"): output_dir = candidate
 root.size = VIEWPORTS[0]; root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
 root.content_scale_size = VIEWPORTS[0]
 if DisplayServer.get_name() != "headless":
  DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true); root.hide()
 call_deferred("run")

func check(condition: bool, message: String) -> void:
 checks += 1
 if condition: return
 failures.append(message)
 if failures.size() <= 30: push_error(message)

func planar(a: Vector3, b: Vector3) -> float:
 return Vector2(a.x - b.x, a.z - b.z).length()

func press(code: int) -> void:
 var event := InputEventKey.new()
 event.keycode = code; event.physical_keycode = code; event.pressed = true
 root.push_input(event, true); event.pressed = false; root.push_input(event, true)
 await process_frame

func mouse(point: Vector2, click: bool = false, button: int = MOUSE_BUTTON_LEFT) -> void:
 var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point
 root.push_input(motion, true); await process_frame
 if not click: return
 var event := InputEventMouseButton.new()
 event.position = point; event.global_position = point; event.button_index = button
 event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
 event.pressed = true; root.push_input(event, true); await process_frame
 event.button_mask = 0; event.pressed = false; root.push_input(event, true); await process_frame

func click_ui(rect: Rect2, button: int = MOUSE_BUTTON_LEFT) -> void:
 await mouse(rect.get_center() * game.hud.get_viewport_rect().size / Vector2(1440, 900), true, button)

func redraw() -> void:
 game.hud.queue_redraw()
 for _frame in 3: await process_frame

func stand(point: Vector3) -> void:
 point.y = game.outpost_height(point)
 game.hero.position = point; game.move_goal = point; game.hero_path.clear()
 game.hero_keyboard_active = false; game.hero.moving = false
 game.hero.set_locomotion_velocity(Vector3.ZERO)

func camera_at(point: Vector3) -> void:
 game.camera.size = 38.0; game.camera.position = point + Vector3(0, 25, 29)
 game.camera.look_at(point); game.camera_follow = game.camera.position

func aim_at(point: Vector3) -> void:
 camera_at(point); await mouse(game.camera.unproject_position(point)); game._process(0.0)

func advance(seconds: float) -> void:
 for frame in ceili(seconds / STEP):
  game.simulate(minf(STEP, seconds - float(frame) * STEP))
  if frame % 100 == 99: await process_frame

func remove_enemies() -> void:
 game.clear_summoners(); game.clear_lobbers()
 for enemy: BattleUnit in game.enemies:
  if is_instance_valid(enemy): enemy.queue_free()
 game.enemies.clear()

func close_game() -> void:
 if not is_instance_valid(game): return
 var squads_token: int = game.squads.get_instance_id()
 await game.prepare_shutdown()
 check(game.squads.medic_snapshot().count == 0, "Real shutdown clears support participants and all pending treatment")
 if current_scene == game: current_scene = null
 game.queue_free(); game = null
 for _frame in 4: await process_frame
 await create_timer(.2, true, false, true).timeout
 check(not is_instance_id_valid(squads_token), "Real scene shutdown releases the actual support owner after audio retirement")

func fresh(keep_wave: bool = false, seed_parts: bool = true) -> void:
 await close_game()
 check(RunSession.queue_request(self, SEED, "siege"), "Medic production accepts the real fixed standard-run seed")
 game = load("res://scenes/nightfall.tscn").instantiate()
 root.add_child(game); current_scene = game
 for _frame in 5: await process_frame
 game.set_process(false); game.world.set_process(false)
 var script := GDScript.new(); script.source_code = OBSERVER
 check(script.reload() == OK, "Fixed medic observer subclasses and forwards the actual production HUD")
 var old: Control = game.hud; var layer: Node = old.get_parent()
 layer.remove_child(old); old.queue_free()
 var observed: Control = script.new(); observed.game = game; game.hud = observed
 layer.add_child(observed); observed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 await press(KEY_1)
 check(game.phase == "night" and game.run_mode == "siege" and game.run.seed_value == SEED,
  "Real opening input creates the actual standard production night")
 if not keep_wave: remove_enemies(); game.wave_index = game.WAVES_PER_NIGHT
 if seed_parts: game.scrap = 5000
 game.phase_time = 10000.0
 game.hero.attack_timer = 100000.0; game.pulse_timer = 100000.0; game.spawn_timer = 100000.0
 game.gate_trap_charges = 0; game.show_gate_trap_charges()
 for pad: Dictionary in game.world.tower_pads: pad.cooldown = 100000.0
 stand(HOME); hurt_events.clear()

func orders() -> Dictionary:
 var rows: Array[Dictionary] = []
 for squad: Dictionary in game.squads.squads:
  rows.append({"id": squad.id, "order": squad.order, "destination": squad.destination, "target": squad.attack_target})
 return {"goal": game.move_goal, "path": game.hero_path.duplicate(), "army": rows,
  "dragging": game.selection_dragging, "selection": game.squads.selected_ids.duplicate()}

func read_state() -> Dictionary:
 var units: Array[Dictionary] = [{"token": game.hero.get_instance_id(), "hp": game.hero.hp,
  "shield": game.hero.shield, "position": game.hero.position}]
 for squad: Dictionary in game.squads.squads:
  for member: BattleUnit in squad.members:
   if is_instance_valid(member): units.append({"token": member.get_instance_id(), "hp": member.hp,
    "shield": member.shield, "position": member.position, "alive": member.alive})
 return {"support": game.squads.medic_snapshot(), "parts": int(game.scrap), "phase": String(game.phase),
  "time": game.phase_time, "rng": game.run.rng.state, "spawn_rng": game.spawn_rng.state,
  "units": units, "orders": orders(), "queues": game.squads.training_queues.duplicate(true),
  "logistics": game.logistics.snapshot()}

func capture(label: String, night: bool = true) -> void:
 if not render_test: return
 check(DisplayServer.get_name() != "headless", "Medic pictures require an actual graphical backend")
 if DisplayServer.get_name() == "headless": return
 var before := read_state()
 for viewport: Vector2i in VIEWPORTS:
  root.size = viewport; root.content_scale_size = viewport
  game.world.set_night(night); game.world.night_mix = 1.0 if night else 0.0
  game.world.apply_lighting(); game.hud.queue_redraw()
  for _frame in 5: await process_frame; await RenderingServer.frame_post_draw
  var picture: Image = root.get_texture().get_image()
  check(picture.get_size() == viewport and Vector2i(game.hud.get_viewport_rect().size) == viewport,
   "Actual medic picture and HUD match " + str(viewport))
  for row: Dictionary in game.hud.drawn_labels:
   if bool(row.drawer):
    check(row.point.x >= 36 and row.point.x + float(row.width) <= 544
     and row.point.y + float(row.descent) < 692,
     "Actual new support drawer Chinese text remains inside its own column and above close")
   if String(row.text).contains("医护") or String(row.text).contains("救护"):
    check(row.point.x >= 0 and row.point.x + float(row.width) <= 1440 and row.point.y <= 900,
     "Actual medic/infirmary Chinese labels stay within the scaled viewport")
  var folder := ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
  var name := "%s-%dx%d" % [label, viewport.x, viewport.y]
  check(picture.save_png(folder.path_join(name + ".png")) == OK, "Actual medic screenshots stay below local build")
  (evidence.captures as Array).append(name)
 check(read_state() == before, "Three-viewport observation cannot heal, spend, move, advance clocks or random state")
 root.size = VIEWPORTS[0]; root.content_scale_size = VIEWPORTS[0]
 for _frame in 3: await process_frame

func select_building(kind: String) -> void:
 if not game.construction.active: await press(KEY_Y)
 var wanted := Catalog.BUILDING_IDS.find(kind) / 3
 for _page in 4:
  var current := Catalog.BUILDING_IDS.find(String(game.construction.kind)) / 3
  if current == wanted: break
  await click_ui(game.hud.construction_page_rect(1 if wanted > current else -1))
 await click_ui(game.hud.construction_kind_rect(Catalog.BUILDING_IDS.find(kind) % 3))
 check(game.construction.active and game.construction.kind == kind, "Actual paginated building GUI selects " + kind)

func plot_at(kind: String, point: Vector3) -> int:
 for plot: Dictionary in game.districts.plots:
  if plot.kind == kind and int(plot.level) > 0 and planar(plot.position, point) < .01: return int(plot.index)
 return -1

func build_gui(kind: String, point: Vector3) -> int:
 stand(HOME); await select_building(kind); await aim_at(point)
 var preview: Dictionary = game.construction.snapshot()
 check(bool(preview.valid), "Actual valid paid building preview permits " + kind + ": " + String(preview.reason))
 var balance: int = game.scrap
 await mouse(game.camera.unproject_position(point), true)
 var id := plot_at(kind, preview.point)
 check(id >= 0 and game.scrap == balance - int(Catalog.building(kind).cost), "Actual building confirmation charges " + kind + " once")
 await press(KEY_F)
 check(game.scrap == balance - int(Catalog.building(kind).cost), "Occupied building confirmation cannot charge a duplicate " + kind)
 await press(KEY_ESCAPE)
 return id

func open_army(second: bool = true) -> void:
 if game.construction.active: await press(KEY_ESCAPE)
 if game.hud.detail_tab.is_empty(): await press(KEY_F3)
 if game.hud.detail_tab != "army": await click_ui(game.hud.details_tab_rect(2))
 if (game.hud.troop_page > 0) != second: await click_ui(game.hud.troop_page_rect(1 if second else -1))
 await redraw()
 check(game.hud.detail_tab == "army" and (game.hud.troop_page > 0) == second, "Actual F3 troop pagination exposes the intended medic page")

func train_gui(kind: String = "medic") -> void:
 await open_army(Catalog.TROOP_IDS.find(kind) >= 3)
 var slot := Catalog.TROOP_IDS.find(kind) % 3
 check(game.hud.visible_training_kinds()[slot] == kind, "Real army slot displays the intended " + kind + " training entry")
 var balance: int = game.scrap; var before := orders()
 await click_ui(game.hud.training_kind_rect(slot))
 check(game.scrap == balance - int(Catalog.troop(kind).cost) and orders() == before,
  "Actual " + kind + " training button charges its only parts balance without issuing world orders")
 await press(KEY_F3)

func guard_selected(point: Vector3) -> void:
 if not game.hud.detail_tab.is_empty(): await press(KEY_F3)
 await press(KEY_TAB); await aim_at(point); await press(KEY_O)

func ready_medic(shield_team: bool = false) -> Dictionary:
 await fresh()
 await build_gui("barracks", BARRACKS); await build_gui("infirmary", INFIRMARY)
 await train_gui(); await advance(9.01)
 check(game.squads.squads.size() == 1 and game.squads.squads[0].kind == "medic", "Real nine-second queue produces one three-person medic group")
 var group: Dictionary = game.squads.squads[0]
 if shield_team: await train_gui("shield"); await advance(6.01)
 await guard_selected(STATION); await advance(15.0)
 for member: BattleUnit in group.members:
  check(not member.moving and planar(member.position, STATION) < 1.6, "Actual medic members finish their genuine station route before support timing")
 stand(STATION + Vector3(0, 0, 1.6))
 return group

func medic_row(id: int = 0) -> Dictionary:
 for row: Dictionary in game.squads.medic_snapshot().squads:
  if int(row.id) == id: return row
 return {}

func toggle_gui(enabled: bool) -> void:
 await open_army()
 check(game.hud.medic_button_visible() and game.hud.selected_medic_ids().size() > 0,
  "Actual selected live medics expose the explicit paid-support switch")
 var before := orders(); var balance: int = game.scrap
 await click_ui(game.hud.MEDIC_BUTTON_RECT, MOUSE_BUTTON_RIGHT)
 check(orders() == before and game.scrap == balance, "Right-click on medic switch never commands troops or spends parts")
 await click_ui(game.hud.MEDIC_BUTTON_RECT)
 for id: int in game.hud.selected_medic_ids():
  check(bool(medic_row(id).therapy_enabled) == enabled, "Actual medic switch applies its intended therapy state to selected medics")
 check(orders() == before and game.scrap == balance, "Medic therapy switch does not pass through as a world command or charge for toggling")
 await press(KEY_F3)

func record_hurt(victim: BattleUnit, source: BattleUnit, hp_loss: float, shield_loss: float) -> void:
 hurt_events.append({"victim": victim.get_instance_id(), "source": source.get_instance_id() if is_instance_valid(source) else -1,
  "hp": hp_loss, "shield": shield_loss})

func catalog_build_and_training() -> void:
 await fresh()
 check(Catalog.BUILDING_IDS.slice(0,7) == ["tower","barracks","workshop","recycler","laboratory","depot","infirmary"]
  and Catalog.TROOP_IDS.slice(0,6) == ["shield","ranged","engineer","ballista","hauler","medic"], "Support catalog retains its original seven-building/six-troop prefix after artillery appends")
 var building: Dictionary = Catalog.building("infirmary"); var troop: Dictionary = Catalog.troop("medic")
 check(building.size == Vector2i(3, 3) and int(building.cost) == 100 and is_equal_approx(float(building.hp), 480.0)
  and building.requires == ["barracks"], "Infirmary authoritative footprint, cost, durability and live prerequisite match the design")
 check(int(troop.cost) == 90 and is_equal_approx(float(troop.time), 9.0) and is_equal_approx(float(troop.hp), 100.0)
  and troop.requires == ["infirmary"], "Medic authoritative paid queue and base HP match the design")
 await select_building("infirmary"); await aim_at(INFIRMARY)
 var locked: Dictionary = game.construction.snapshot()
 check(not bool(locked.valid) and not bool(locked.tech_valid) and bool(locked.space_valid)
  and locked.missing == ["barracks"] and locked.cells.size() == 9, "Real third building page shows independent live-barracks technology rejection on nine otherwise free cells")
 var balance: int = game.scrap; await mouse(game.camera.unproject_position(INFIRMARY), true)
 check(game.scrap == balance and plot_at("infirmary", INFIRMARY) < 0, "Actual locked infirmary click cannot spend or create a hidden building")
 await capture("infirmary-locked-third-page", false); await press(KEY_ESCAPE)
 await open_army(); check(game.hud.visible_training_kinds() == ["ballista","hauler","medic"], "Medic occupies the true third advanced troop slot")
 balance = game.scrap; await click_ui(game.hud.training_kind_rect(2))
 check(game.scrap == balance and game.squads.training_queues.is_empty(), "Actual missing-infirmary medic button cannot charge or enqueue")
 await press(KEY_F3)
 var barracks := await build_gui("barracks", BARRACKS)
 var infirmary := await build_gui("infirmary", INFIRMARY)
 var plot: Dictionary = game.districts.plots[infirmary]
 check(int(plot.level) == 1 and is_equal_approx(float(plot.hp), 480.0) and is_instance_valid(plot.model), "Actual paid infirmary retains its genuine durability and visible prototype")
 for cell: Vector2i in Grid.placement(plot.position, "infirmary").cells:
  var center := Grid.cell_rect(cell).get_center()
  check(not game.outpost_walkable(Vector3(center.x, 5, center.y)), "Every real infirmary cell blocks production navigation")
 camera_at(INFIRMARY); await capture("infirmary-paid-day", false); await capture("infirmary-paid-night")
 await train_gui(); await open_army()
 var queue: Array = game.squads.training_queues.get(barracks, [])
 check(queue.size() == 1 and queue[0].kind == "medic" and is_equal_approx(float(queue[0].remaining), 9.0), "Actual paid medic queue starts at the complete real nine seconds")
 await capture("medic-paid-order-army")
 balance = game.scrap
 var cancel: Dictionary = game.hud.training_cancel_buttons[0]
 await click_ui(cancel.rect)
 check(game.scrap == balance + 90 and game.squads.training_queues.get(barracks, []).is_empty(), "Actual medic cancel button refunds exactly its paid ninety parts once")
 var paid: int = game.scrap; await click_ui(cancel.rect)
 check(game.scrap == paid, "Stale medic refund button cannot pay twice")
 await press(KEY_F3); await train_gui()
 game.districts.damage(infirmary, 100000.0)
 check(not game.squads.training_eligibility("medic").available and not game.districts.has_live("infirmary"), "Genuine infirmary death immediately blocks new medic training")
 await advance(8.99)
 check(game.squads.squads.is_empty(), "Destroying the prerequisite does not finish the already paid queue early")
 game.simulate(.011)
 check(game.squads.squads.size() == 1 and game.squads.squads[0].kind == "medic", "Already paid medic order survives prerequisite death and completes naturally")
 for member: BattleUnit in game.squads.squads[0].members:
  check(is_equal_approx(member.max_hp, 100.0 * game.districts.squad_health_multiplier()) and member.damage == 0.0,
   "Real newborn medical member has the scaled one-hundred base HP and zero enemy damage")
 check(medic_row().therapy_enabled == false and game.squads.medic_snapshot().treatments == 0, "Fresh real medical support is explicitly off and never precharges")
 (evidence.completed as Array).append("actual_catalog_third_page_live_prerequisite_9_cells_day_night_gui_queue_refund_paid_order_survival_default_off")

func precise_support_freeze_and_cooldown() -> void:
 await ready_medic()
 game.hero.hurt(500.0, null)
 var balance: int = game.scrap
 await advance(1.0)
 check(game.squads.medic_snapshot().treatments == 0 and game.scrap == balance, "Default-off live medics cannot spend on a genuinely injured hero")
 await toggle_gui(true)
 game.simulate(.001)
 var row := medic_row()
 check(int(row.casting) == 3, "Three real stationary medical members independently start support")
 for member: Dictionary in row.members:
  check(member.target == game.hero and is_equal_approx(float(member.remaining), .65), "Actual lowest-ratio hero starts a full nonconsumed 0.65-second treatment preparation")
 await open_army(); await capture("medic-real-windup-three-person")
 var before := read_state(); await press(KEY_ESCAPE)
 check(game.hud.detail_tab.is_empty() and game.phase == "night", "First Escape dismisses actual army details without pausing")
 await press(KEY_ESCAPE)
 check(game.squads.selected_count() == 0 and game.phase == "night", "Next Escape clears genuine unit selection before pause")
 await press(KEY_ESCAPE); check(game.phase == "paused", "Actual Escape pauses a pending medical treatment")
 before = read_state(); game.simulate(10.0); game.squads.advance(10.0)
 check(read_state() == before, "Actual pause freezes HP, support clocks, wallet and all medical participants")
 await capture("medic-paused-live-windup")
 await press(KEY_ESCAPE)
 game.run.grant("医护验证 · 免费选卡冻结夹具"); await press(KEY_V)
 check(game.phase == "draft", "Actual V opens a real free pending choice during support")
 before = read_state(); game.simulate(10.0); game.squads.advance(10.0)
 check(read_state() == before, "Actual card choice freezes support and its only parts balance")
 await press(KEY_1)
 await advance(.649)
 check(game.squads.medic_snapshot().treatments == 0 and game.scrap == balance, "No real medical fee or healing occurs before full preparation")
 var hp: float = game.hero.hp; game.simulate(.002)
 var state: Dictionary = game.squads.medic_snapshot()
 check(int(state.treatments) == 3 and int(state.spent) == 6 and is_equal_approx(float(state.healed_hp), 108.0)
  and game.scrap == balance - 6 and game.hero.hp > hp + 107.9,
  "Three genuine completed treatments each restore thirty-six HP and spend exactly two actual parts")
 for member: Dictionary in medic_row().members:
  check(is_equal_approx(float(member.cooldown), 4.0) and int(member.treatments) == 1, "Each actual medical member starts an independent complete four-second success cooldown")
 await press(KEY_TAB)
 await toggle_gui(false); var cooldown_state: Dictionary = game.squads.medic_snapshot()
 await toggle_gui(true)
 for slot in 3:
  check(is_equal_approx(float(medic_row().members[slot].cooldown), float(cooldown_state.squads[0].members[slot].cooldown)), "Off/on cannot refresh a genuine medical success cooldown")
 await advance(3.99)
 check(game.squads.medic_snapshot().treatments == 3, "Actual continuous cooldown prevents another charged treatment before four seconds")
 game.simulate(.011)
 check(medic_row().casting == 3, "Cooldown completion starts fresh full preparations instead of instant repeat healing")
 await advance(.649); check(game.squads.medic_snapshot().treatments == 3, "Every repeated treatment also requires its complete preparation")
 game.simulate(.002)
 check(game.squads.medic_snapshot().treatments == 6 and game.scrap == balance - 12,
  "Repeated real support charges six independent successes exactly once each")
 (evidence.support as Dictionary).independent_success = support_totals()
 await open_army(); await capture("medic-real-six-treatments-cooldown")
 (evidence.completed as Array).append("default_off_actual_switch_three_independent_065_36_two_parts_pause_choice_four_second_cd_no_toggle_refresh")

func support_totals() -> Dictionary:
 var state: Dictionary = game.squads.medic_snapshot()
 return {"count": state.count, "alive": state.alive, "enabled_count": state.enabled_count,
  "treatments": state.treatments, "healed_hp": state.healed_hp, "spent": state.spent}

func treatment_cancellation_and_last_parts() -> void:
 await ready_medic()
 game.hero.hurt(500.0, null); await toggle_gui(true); game.simulate(.001); await advance(.3)
 var balance: int = game.scrap
 stand(Vector3(20, 0, 31)); game.simulate(.01)
 check(medic_row().casting == 0 and game.scrap == balance and game.squads.medic_snapshot().treatments == 0,
  "Actual hero leaving medical range cancels every unfinished treatment in that simulation frame without a fee")
 stand(STATION + Vector3(0, 0, 1.6)); game.simulate(.01)
 check(medic_row().casting == 3, "Returning injured hero starts fresh genuine support preparations")
 await aim_at(STATION + Vector3(3, 0, 0)); await press(KEY_O)
 check(medic_row().casting == 0 and game.scrap == balance, "Actual manual medical order cancels pending treatment immediately without payment")
 await advance(.2)
 check(medic_row().casting == 0 and game.scrap == balance, "Actually moving medics cannot complete their cancelled stationary treatment")
 await toggle_gui(false)
 await guard_selected(STATION); await advance(6.0)
 check(game.scrap == balance, "Actual return travel with support off cannot spend medical parts")
 await toggle_gui(true); game.simulate(.001)
 check(medic_row().casting == 3, "Real returned stationary medics can prepare new treatment after movement")
 await toggle_gui(false)
 check(medic_row().casting == 0 and game.scrap == balance, "Actual support disable cancels unfinished work without charging or refreshing cooldown")
 await toggle_gui(true); game.simulate(.001)
 game.scrap = 1 # Explicit low-wallet rejection fixture, not an earned economy.
 game.simulate(.01)
 check(medic_row().casting == 0 and game.scrap == 1 and game.squads.medic_snapshot().treatments == 0,
  "Actual wallet falling below two parts cancels unfinished treatment before consuming any parts")
 await advance(1.0)
 check(game.scrap == 1 and game.squads.medic_snapshot().treatments == 0, "Insufficient actual wallet never starts or funds support")
 game.scrap = 2; game.simulate(.001); await advance(.651)
 check(game.scrap == 0 and game.squads.medic_snapshot().treatments == 1 and game.squads.medic_snapshot().spent == 2,
  "Three simultaneous real medics sharing the last two parts complete exactly one paid treatment without a negative wallet")
 await open_army(); await capture("medic-last-two-parts-single-success")
 (evidence.support as Dictionary).last_parts = support_totals()
 await ready_medic(true)
 var patient: BattleUnit = game.squads.squads[1].members[2]
 patient.hurt(patient.max_hp * .8, null)
 await toggle_gui(true); game.simulate(.001)
 check(medic_row().casting > 0, "Real injured current squad member can become an actual support target")
 balance = game.scrap; patient.hurt(100000.0, null)
 check(medic_row().casting == 0 and game.scrap == balance, "Real target-member death cancels medical preparations in the death callback frame without reviving or charging")
 await advance(.8)
 check(not is_instance_valid(patient) or not patient.alive, "Medical support never resurrects a genuinely dead squad member")
 var healer: BattleUnit = game.squads.squads[0].members[0]
 game.hero.hurt(500.0, null); game.simulate(.001)
 var token := healer.get_instance_id(); healer.hurt(100000.0, null)
 for member: Dictionary in medic_row().members: check(int(member.token) != token, "Real medical source death removes its pending support state")
 (evidence.completed as Array).append("actual_range_order_movement_off_cancel_insufficient_last_two_atomic_target_and_source_death")

func real_targets_limits_and_no_enemy_damage() -> void:
 await ready_medic(true)
 var group: Dictionary = game.squads.squads[0]
 var shield_group: Dictionary = game.squads.squads[1]
 var patient: BattleUnit = shield_group.members[2]
 var healer: BattleUnit = group.members[1]
 healer.hurt(healer.max_hp * .8, null)
 patient.hurt(patient.max_hp * .5, null)
 var patient_injured: float = patient.hp
 await toggle_gui(true); game.simulate(.001)
 check(medic_row().members[1].target == healer, "Actual medical source may heal itself when it is the lowest-ratio genuine injured friendly unit")
 for member: Dictionary in medic_row().members:
  if bool(member.casting): check(member.target == healer, "Eligible real medical members prefer the lowest HP proportion over another missing-health ally")
 await advance(.651)
 check(healer.hp > healer.max_hp * .2 and healer.hp <= healer.max_hp and healer.shield == 0,
  "Actual self/friendly treatment restores bounded HP without generating shield")
 await open_army(); camera_at(STATION); await capture("medic-real-self-heal-low-light-feedback")
 await press(KEY_F3)
 await advance(5.0)
 check(patient.hp > patient_injured and patient.hp <= patient.max_hp, "Actual paid medical cooldowns eventually increase the other genuine squad member's recorded post-armor injured HP")
 await toggle_gui(false)
 var rogue := preload("res://scripts/unit.gd").new() as BattleUnit
 game.add_child(rogue); rogue.setup("minion", 0); rogue.position = STATION + Vector3(0, 0, .5)
 rogue.hurt(rogue.max_hp * .9, null); rogue.set_meta("squad_kind", "shield")
 var enemy: BattleUnit = game.spawn_creature(true, "basic")
 enemy.position = STATION + Vector3(0, 0, 3); enemy.hurt(enemy.max_hp * .8, null); enemy.attack_timer = 100000.0
 var rogue_hp: float = rogue.hp; var enemy_hp: float = enemy.hp
 # Complete genuine allies before observing adversarial candidates. No HP
 # assignment supplies the observed heal: every deficit below uses real hurt.
 var live: Array[BattleUnit] = []
 for squad: Dictionary in game.squads.squads:
  for member: BattleUnit in squad.members:
   if is_instance_valid(member) and member.alive: live.append(member)
 # Place invalid objects near but outside the selected formation's real march.
 await guard_selected(Vector3(0, 0, 28)); await advance(18.0)
 stand(Vector3(20, 0, 31))
 rogue.position = Vector3(0, 0, 28.5); enemy.position = Vector3(0, 0, 28.8)
 await toggle_gui(true); game.simulate(.001); await advance(.8)
 check(is_equal_approx(rogue.hp, rogue_hp) and enemy.hp <= enemy_hp, "Unregistered forged friendly metadata and injured enemy never receive medical HP")
 await toggle_gui(false)
 var outsider: BattleUnit = live[0]
 var owner_group: Dictionary = game.squads.squads[0]
 var old_slot: int = owner_group.members.find(outsider)
 if old_slot >= 0:
  owner_group.members[old_slot] = null # Explicit stale-membership rejection fixture.
  outsider.hurt(outsider.max_hp * .5, null)
  var hp: float = outsider.hp
  await toggle_gui(true); game.simulate(.001); await advance(.8)
  check(is_equal_approx(outsider.hp, hp), "An alive detached former member cannot be healed using its old metadata")
  owner_group.members[old_slot] = outsider
 await toggle_gui(false)
 remove_enemies(); rogue.queue_free()
 await ready_medic()
 group = game.squads.squads[0]
 # All medical members follow the same genuine attack command while their
 # zero attack behavior must leave the designated enemy untouched.
 game.squads.cancel_selection(); await aim_at(group.members[1].position)
 await mouse(game.camera.unproject_position(group.members[1].position), true)
 check(game.squads.selected_ids == [int(group.id)], "Actual world click selects only the genuine medical group before enemy-damage isolation")
 enemy = game.spawn_creature(true, "basic"); enemy.position = STATION + Vector3(0, 0, 4)
 enemy.attack_timer = 100000.0; enemy_hp = enemy.hp
 await aim_at(enemy.position); await mouse(game.camera.unproject_position(enemy.position), true, MOUSE_BUTTON_RIGHT)
 check(group.order == "attack", "Actual selected medic right-click retains the real designated attack order")
 await advance(4.0)
 check(enemy.alive and is_equal_approx(enemy.hp, enemy_hp), "Actual medical attack command cannot damage its live enemy target")
 camera_at(STATION); await capture("medic-real-friend-self-and-noncombat")
 (evidence.completed as Array).append("real_current_friend_and_self_lowest_ratio_no_shield_no_enemy_rogue_detached_or_attack_damage")

func bounded_small_deficit_and_full_health() -> void:
 await ready_medic()
 var patient: BattleUnit = game.squads.squads[0].members[2]
 # This genuine target is inside at least the closest medic's eligibility.
 patient.hurt(12.0, null)
 check(is_equal_approx(patient.max_hp - patient.hp, 12.0), "Actual unarmored medic hurt creates a recorded twelve-HP deficit")
 var balance: int = game.scrap
 await toggle_gui(true); game.simulate(.001); await advance(.649)
 check(is_equal_approx(patient.max_hp - patient.hp, 12.0) and game.scrap == balance
  and game.squads.medic_snapshot().treatments == 0,
  "Actual injured medical member HP and wallet remain unchanged before the complete 0.65-second preparation")
 game.simulate(.002)
 check(is_equal_approx(patient.hp, patient.max_hp) and game.scrap == balance - 2
  and game.squads.medic_snapshot().treatments == 1 and is_equal_approx(float(game.squads.medic_snapshot().healed_hp), 12.0),
  "A genuine twelve-HP deficit heals only twelve and only the first valid caster pays two parts")
 await advance(8.0)
 check(game.scrap == balance - 2 and game.squads.medic_snapshot().treatments == 1,
  "Actual full-health genuine allies cannot generate repeated fees or overhealing")
 patient.hurt(11.0, null); await advance(1.0)
 check(is_equal_approx(patient.max_hp - patient.hp, 11.0), "Actual second unarmored medic hurt creates a recorded eleven-HP deficit")
 check(game.squads.medic_snapshot().treatments == 1 and game.scrap == balance - 2,
  "A genuine sub-twelve deficit does not start medical payment")
 var infirmary := plot_at("infirmary", INFIRMARY)
 game.districts.damage(infirmary, 100.0)
 var building_hp: float = game.districts.plots[infirmary].hp
 await advance(1.0)
 check(game.districts.plots[infirmary].hp == building_hp and game.scrap == balance - 2,
  "Actual damaged infirmary cannot be repaired or charged by medical support")
 (evidence.completed as Array).append("real_twelve_deficit_bounded_hp_single_fee_full_health_subtwelve_no_spend")

func route_to(point: Vector3, seconds: float) -> Dictionary:
 await guard_selected(point)
 var crossed: Dictionary = {}; var distance: Dictionary = {}
 for frame in ceili(seconds / STEP):
  var before: Dictionary = {}
  for squad: Dictionary in game.squads.squads:
   for member: BattleUnit in squad.members:
    if is_instance_valid(member) and member.alive: before[member.get_instance_id()] = member.position
  game.simulate(STEP)
  for squad: Dictionary in game.squads.squads:
   for member: BattleUnit in squad.members:
    if not is_instance_valid(member) or not member.alive: continue
    var old: Vector3 = before[member.get_instance_id()]
    check(member.position.is_finite() and game.outpost_walkable(member.position)
     and absf(member.position.y - game.outpost_height(member.position)) < .001,
     "Actual medical march remains on the finite walkable production terrain")
    check(game.can_traverse(old, member.position) and planar(old, member.position) <= member.speed * STEP + .001,
     "Every real medical march step obeys actual navigation and speed")
    distance[member.get_instance_id()] = float(distance.get(member.get_instance_id(), 0.0)) + planar(old, member.position)
    if old.z < Layout.WALL_CENTER and member.position.z >= Layout.WALL_CENTER:
     var factor := (Layout.WALL_CENTER - old.z) / (member.position.z - old.z)
     check(absf(lerpf(old.x, member.position.x, factor)) < Layout.GATE_HALF,
      "Every actual medical member exits through the unique south-gate opening")
     crossed[member.get_instance_id()] = true
  if frame % 100 == 99: await process_frame
 return {"crossed": crossed.size(), "distances": distance.values()}

func real_gate_and_geometry() -> void:
 await ready_medic()
 var balance: int = game.scrap
 var route := await route_to(Vector3(0, 0, 28), 15.0)
 check(route.crossed == 3 and game.scrap == balance and game.squads.medic_snapshot().treatments == 0,
  "All three genuinely produced medical members cross the south gate without default medical spending")
 for member: BattleUnit in game.squads.squads[0].members:
  check(not member.moving and planar(member.position, Vector3(0, 0, 28)) < 1.6, "Actual medical group finishes its exterior marching destination")
 (evidence.routes as Array).append(route)
 game.hero.hurt(500.0, null)
 await guard_selected(Vector3(1.2, 0, 24.6)); await advance(4.0)
 stand(Vector3(4.2, 0, 24.6))
 for member: BattleUnit in game.squads.squads[0].members:
  check(planar(member.position, game.hero.position) <= 4.8 and absf(member.position.y - game.hero.position.y) <= 1.0,
   "Actual slope-wall counterexample is in medical range and on the same height layer")
  check(not game.can_attack_line(member.position, game.hero.position), "The genuine slope wall blocks each otherwise close medical source")
 await toggle_gui(true); game.simulate(.001); await advance(.8)
 check(medic_row().casting == 0 and game.scrap == balance and game.squads.medic_snapshot().treatments == 0,
  "Real slope-wall obstruction prevents medical preparation and fees")
 await open_army(); camera_at(Vector3(2, 0, 24.6)); await capture("medic-slope-wall-los-rejection")
 await press(KEY_F3); await toggle_gui(false)
 await guard_selected(Vector3(0, 0, 24)); await advance(3.0)
 stand(Vector3(0, 0, 21))
 for member: BattleUnit in game.squads.squads[0].members:
  check(planar(member.position, game.hero.position) <= 4.8 and absf(member.position.y - game.hero.position.y) > 1.0,
   "Actual ramp medical counterexample is near but exceeds one metre of real terrain height")
 await toggle_gui(true); game.simulate(.001); await advance(.8)
 check(game.scrap == balance and game.squads.medic_snapshot().treatments == 0 and medic_row().casting == 0,
  "Real ramp height separation rejects medical preparation despite planar proximity")
 stand(Vector3(0, 0, 21.8)); game.simulate(.001)
 check(medic_row().casting == 3, "Moving the genuine injured hero to the ramp's allowed one-metre layer starts actual treatment")
 await advance(.651)
 check(game.squads.medic_snapshot().treatments == 3 and game.scrap == balance - 6,
  "Actual unblocked nearby ramp support completes three independently paid treatments")
 await open_army(); camera_at(Vector3(0, 0, 23)); await capture("medic-ramp-height-accepted-treatment")
 await ready_medic()
 var source: BattleUnit = game.squads.squads[0].members[2]
 game.hero.hurt(500.0, null); stand(source.position + Vector3(4.81, 0, 0))
 balance = game.scrap; await toggle_gui(true); game.simulate(.001); await advance(.8)
 check(medic_row().casting == 0 and game.scrap == balance and game.squads.medic_snapshot().treatments == 0,
  "Actual 4.81-metre target is outside every genuine source and cannot spend")
 stand(source.position + Vector3(4.79, 0, 0)); game.simulate(.001)
 check(medic_row().casting == 1 and medic_row().members[2].target == game.hero,
  "Actual 4.79-metre target starts support from only the nearest genuine source")
 await advance(.651)
 check(game.squads.medic_snapshot().treatments == 1 and game.scrap == balance - 2,
  "Just-inside medical range completes exactly one real paid treatment")
 (evidence.completed as Array).append("all_three_real_unique_gate_steps_speed_walkable_slope_wall_height_and_479_481_range")

func actual_building_los_release() -> void:
 await ready_medic()
 await guard_selected(Vector3(3.45, 5, -8.5)); await advance(10.0)
 stand(Vector3(9.3, 5, -8.5)); game.hero.hurt(500.0, null)
 var nearest: BattleUnit = game.squads.squads[0].members[2]
 check(game.outpost_walkable(nearest.position) and game.outpost_walkable(game.hero.position)
  and planar(nearest.position, game.hero.position) < 4.8 and absf(nearest.position.y - game.hero.position.y) < .001,
  "Actual medic and hero stand on accessible same-height faces within range across the genuine live barracks")
 check(game.can_attack_line(nearest.position, game.hero.position) and not game.can_traverse(nearest.position, game.hero.position),
  "Actual live barracks counterexample distinguishes existing projectile rules from medical building obstruction")
 var balance: int = game.scrap; await toggle_gui(true); game.simulate(.001); await advance(.8)
 check(medic_row().casting == 0 and game.scrap == balance and game.squads.medic_snapshot().treatments == 0,
  "Medical support cannot prepare or pay through the genuine live barracks footprint")
 await open_army(); camera_at(Vector3(7, 5, -8.5)); await capture("medic-real-barracks-los-blocked")
 await press(KEY_F3)
 game.districts.damage(plot_at("barracks", BARRACKS), 100000.0)
 game.simulate(.001)
 check(medic_row().casting == 1 and medic_row().members[2].target == game.hero,
  "Actual building destruction removes medical line obstruction for only the nearest surviving medic")
 await advance(.651)
 check(game.squads.medic_snapshot().treatments == 1 and game.scrap == balance - 2,
  "Genuine prior medical group continues paid support after its prerequisite building dies and the line becomes clear")
 await open_army(); await capture("medic-real-barracks-destroyed-los-release")
 (evidence.completed as Array).append("true_building_footprint_medical_los_block_dynamic_destruction_release_no_global_projectile_change")

func active_member_detachment() -> void:
 await ready_medic(true)
 var patient_group: Dictionary = game.squads.squads[1]
 var patient: BattleUnit = patient_group.members[2]
 patient.hurt(patient.max_hp * .8, null)
 await toggle_gui(true); game.simulate(.001)
 var cast_before: int = medic_row().casting
 check(cast_before > 0, "Real wounded shield member is the original target of genuine pending medical preparations")
 for row: Dictionary in medic_row().members:
  if row.casting: check(row.target == patient, "Pending genuine medical casts retain the actual current roster member identity")
 var balance: int = game.scrap; var hp: float = patient.hp
 patient_group.members[2] = null # Explicit alive-but-detached roster negative fixture.
 game.simulate(.01)
 check(patient.alive and patient.hp == hp and medic_row().casting == 0 and game.scrap == balance,
  "An original still-living target removed from the actual roster cancels pending medical work in that frame without healing or fees")
 patient_group.members[2] = patient
 game.simulate(.001)
 check(medic_row().casting == cast_before, "Restoring genuine live roster ownership starts fresh eligible medical preparation")
 for row: Dictionary in medic_row().members:
  if row.casting: check(is_equal_approx(float(row.remaining), .65), "Restored ownership cannot resume the detached target's old partial preparation")
 (evidence.completed as Array).append("actual_pending_target_identity_alive_roster_detachment_cancels_no_fee_restore_fresh065")

func selected_switch_and_default_layout() -> void:
 await ready_medic(true)
 await press(KEY_ESCAPE); stand(HOME)
 game._process(3.1)
 check(game.notice_time == 0.0, "Actual production frame expires the temporary order notice before idle default HUD coverage")
 await redraw()
 check(game.hud.detail_tab.is_empty() and not game.hud.map_expanded and not game.hud.medic_button_visible(),
  "Default battlefield with medics retains its closed drawer and hides the optional support switch")
 for viewport: Vector2i in VIEWPORTS:
  root.size = viewport; root.content_scale_size = viewport; await redraw()
  var area := 0.0
  for rect: Rect2 in game.hud.visible_hud_rects():
   check(Rect2(0,0,1440,900).encloses(rect), "Default medic HUD reports only logical-viewport UI")
   area += rect.get_area()
  check(area / (1440.0 * 900.0) < .16, "Actual default medical battlefield keeps permanent UI below its sixteen-percent budget at every viewport")
  (evidence.support as Dictionary)["default_coverage_%dx%d" % [viewport.x,viewport.y]] = area / (1440.0 * 900.0)
 root.size = VIEWPORTS[0]; root.content_scale_size = VIEWPORTS[0]
 await capture("medic-default-clear-battlefield")
 await press(KEY_TAB)
 await open_army(false)
 check(not game.hud.medic_button_visible(), "Original troop page hides the optional medical switch even with medics selected")
 var before := read_state(); await click_ui(game.hud.MEDIC_BUTTON_RECT)
 check(read_state() == before, "Hidden first-page medical button position cannot change actual medical state or issue world commands")
 await press(KEY_F3); await press(KEY_ESCAPE)
 check(game.squads.selected_count() == 0, "Actual Escape clears the real troop selection before medical authorization testing")
 await open_army()
 check(not game.hud.medic_button_visible(), "Real advanced army page requires explicit selected live medics to expose treatment")
 before = read_state(); await click_ui(game.hud.MEDIC_BUTTON_RECT)
 check(read_state() == before and not game.squads.set_medic_enabled(0, true).ok,
  "Unselected medical group rejects both real hidden-location input and its authoritative support switch")
 await press(KEY_F3)
 var shield: BattleUnit = game.squads.squads[1].members[1]
 await aim_at(shield.position); await mouse(game.camera.unproject_position(shield.position), true)
 check(game.squads.selected_ids == [1], "Actual world click selects the ordinary shield group by itself")
 await open_army(); before = read_state()
 check(not game.hud.medic_button_visible(), "Selecting only ordinary troops cannot expose the medical control")
 await click_ui(game.hud.MEDIC_BUTTON_RECT)
 check(read_state() == before, "Ordinary selected troops cannot use the medical button's dormant rectangle")
 await press(KEY_F3); await press(KEY_TAB); await open_army()
 check(game.hud.medic_button_visible(), "Actual Tab selection exposes the selected medic switch on its intended page")
 await press(KEY_ESCAPE); await press(KEY_ESCAPE); await press(KEY_ESCAPE)
 check(game.phase == "paused", "Actual three-level Escape sequence pauses selected medical gameplay")
 await open_army(); before = read_state()
 await click_ui(game.hud.MEDIC_BUTTON_RECT)
 check(read_state() == before and not game.squads.set_medic_enabled(0, true).ok,
  "Real paused army input cannot toggle medical support through either GUI or authority")
 await capture("medic-actual-paused-control-rejection")
 await press(KEY_F3); await press(KEY_ESCAPE)
 await build_gui("workshop", Vector3(7.5, 5, -3))
 await build_gui("depot", Vector3(9.5, 5, 3.5))
 await train_gui("hauler"); await advance(8.01)
 await press(KEY_TAB); await open_army()
 check(game.hud.medic_button_visible() and game.hud.haul_button_visible()
  and not game.hud.MEDIC_BUTTON_RECT.intersects(game.hud.HAUL_BUTTON_RECT),
  "Actual mixed selected medical and carrier groups display both independent nonoverlapping optional controls")
 before = read_state(); await click_ui(game.hud.MEDIC_BUTTON_RECT)
 check(medic_row().therapy_enabled and orders() == before.orders and game.scrap == before.parts,
  "Mixed medical switch changes only selected support state without carrier or hero commands or parts fees")
 await capture("medic-hauler-mixed-both-controls")
 before = read_state(); await click_ui(game.hud.HAUL_BUTTON_RECT)
 check(medic_row().therapy_enabled and game.scrap == before.parts
  and game.squads.squads[0].order == before.orders.army[0].order,
  "Mixed carrier control retains genuine medical state and medical orders without a treatment fee")
 await press(KEY_F3); await press(KEY_ESCAPE); await press(KEY_ESCAPE)
 check(game.phase == "paused", "Actual mixed selected support/carrier gameplay can pause after closing its real drawer and clearing selection")
 before = read_state(); game.simulate(5.0); game.squads.advance(5.0); game.logistics.advance(5.0)
 check(read_state() == before, "Actual mixed pause freezes medical state, real carrier stock/cargo, movement, both queues and the only wallet")
 await open_army(); await capture("medic-hauler-actual-mixed-pause")
 (evidence.completed as Array).append("three_viewport_default15percent_firstpage_unselected_ordinary_paused_rejection_mixed_carrier_switch_nonpenetration")

func actual_damage_upgrade_refill_and_phase() -> void:
 await ready_medic()
 var group: Dictionary = game.squads.squads[0]
 var patient: BattleUnit = group.members[1]
 patient.damage_confirmed.connect(record_hurt)
 var enemy: BattleUnit = game.spawn_creature(true, "basic")
 enemy.position = patient.position + Vector3(0, 0, 1)
 enemy.attack_timer = 0.0
 stand(Vector3(20, 0, 31))
 for frame in 80:
  if not hurt_events.is_empty(): break
  game.simulate(STEP)
 check(not hurt_events.is_empty(), "A genuine nearby enemy completes its actual production attack against a real medical member")
 var real_loss := 0.0
 for event: Dictionary in hurt_events:
  if event.victim == patient.get_instance_id() and event.source == enemy.get_instance_id(): real_loss += float(event.hp)
 check(real_loss >= 12.0 and patient.hp < patient.max_hp,
  "Actual damage_confirmed records the genuine enemy source and post-defense medical HP loss")
 remove_enemies(); var hp: float = patient.hp; var balance: int = game.scrap
 await toggle_gui(true); game.simulate(.001); await advance(.651)
 check(patient.hp > hp and game.scrap < balance and game.squads.medic_snapshot().healed_hp > 0.0,
  "Real paid medical completion restores HP that an actual enemy attack removed")
 await toggle_gui(false)
 patient.hurt(42.0, null)
 var ratio := patient.hp / patient.max_hp
 var barracks := plot_at("barracks", BARRACKS)
 balance = game.scrap; stand(BARRACKS + Vector3(0, 0, 2.1)); await press(KEY_F)
 check(game.districts.plots[barracks].level == 2 and game.scrap == balance - 80
  and is_equal_approx(patient.max_hp, 140.0) and is_equal_approx(patient.hp / patient.max_hp, ratio),
  "Actual F upgrades the live barracks for eighty parts and preserves real injured medic HP proportion with 1.4 authority")
 TransitionFixture.finish_for_fixture(game); check(game.phase == "draft", "Actual first dawn enters its genuine free production draft")
 await press(KEY_1); check(game.phase == "day", "Actual dawn card input resumes real day before medical replacement")
 remove_enemies(); var lost: BattleUnit = group.members[0]; lost.hurt(100000.0, null)
 var survivor: BattleUnit = group.members[2]; survivor.hurt(70.0, null)
 var expected := 26 + ceili((patient.max_hp - patient.hp) / patient.max_hp * 10.0) + 5
 check(game.squads.refill_cost() == expected, "Actual one missing medic costs twenty-six plus the real survivors' proportional injured fees")
 balance = game.scrap; await press(KEY_L)
 check(game.scrap == balance - expected and game.squads.refill_cost() == 0 and medic_row().alive == 3,
  "Real daytime L pays the sole wallet once and creates one actual medical replacement while restoring injured survivors")
 for member: BattleUnit in group.members:
  check(member.alive and is_equal_approx(member.hp, member.max_hp) and is_equal_approx(member.max_hp, 140.0),
   "Actual restocked medical roster retains authoritative upgraded HP")
 balance = game.scrap; await press(KEY_L); check(game.scrap == balance, "Repeated real L cannot pay again on a fully restored medical group")
 await guard_selected(STATION); await advance(10.0)
 patient = group.members[1]; patient.hurt(80.0, null)
 await toggle_gui(true); game.simulate(.001); await advance(.651)
 var cooldowns: Array = []
 for member: Dictionary in medic_row().members: cooldowns.append(float(member.cooldown))
 await aim_at(STATION + Vector3(1, 0, 0)); await press(KEY_O)
 for slot in 3:
  check(is_equal_approx(float(medic_row().members[slot].cooldown), float(cooldowns[slot])),
   "Actual medical order changes retain each independent success cooldown")
 game.start_night(); remove_enemies(); game.wave_index = game.WAVES_PER_NIGHT
 for slot in 3:
  check(is_equal_approx(float(medic_row().members[slot].cooldown), float(cooldowns[slot])),
   "Actual dusk transition preserves each real medical success cooldown")
 check(medic_row().casting == 0, "Actual dusk cancels all unfinished medical preparations")
 await toggle_gui(false); await guard_selected(STATION); await advance(5.0)
 patient.hurt(60.0, null); await toggle_gui(true); game.simulate(.001)
 check(medic_row().casting > 0, "Actual settled night medical group can prepare again after its genuine preserved cooldown")
 balance = game.scrap; TransitionFixture.finish_for_fixture(game)
 check(medic_row().casting == 0 and game.scrap == balance, "Actual dawn cancels genuine active treatment before any preparation fee")
 await press(KEY_1); remove_enemies()
 game.end_defeat("医护测试 · 真实结束清理")
 check(game.phase == "ended" and game.squads.medic_snapshot().count == 0, "Actual defeat releases every medical participant and its prepared treatment state")
 (evidence.completed as Array).append("real_enemy_attack_damage_confirmed_heal_F_health_ratio_L26_proportional_refill_order_cd_dusk_dawn_defeat")

func actual_unseeded_economy() -> void:
 await fresh(true, false)
 check(game.scrap == 90, "Unseeded route starts with the actual untouched ninety-part opening wallet")
 for wave in 5:
  check(game.wave_index == wave + 1 and game.wave_rewards.snapshot(wave).budget == 24,
   "Actual unseeded route records the genuine sequential first-night twenty-four-part wave")
  var before: int = game.scrap
  var victims: Array = game.enemies.duplicate()
  for enemy: BattleUnit in victims:
   if not is_instance_valid(enemy) or not enemy.alive: continue
   enemy.hurt(100000.0, game.hero)
   var paid: int = game.scrap; enemy.hurt(100000.0, game.hero)
   check(game.wave_rewards.defeat(enemy) == 0 and game.scrap == paid, "Duplicate real defeated enemy cannot mint another economic reward")
  check(game.wave_rewards.snapshot(wave).paid == 24 and game.scrap == before + 24,
   "Actual first-night lethal production callbacks pay exactly twenty-four parts per cleared wave")
  await process_frame; game.enemies.clear()
  if wave < 4: game.spawn_night_wave()
 check(game.scrap == 210 and game.kills == 71, "Real unseeded first night pays exactly one-hundred-twenty parts from seventy-one actual deaths")
 TransitionFixture.finish_for_fixture(game); await press(KEY_1); remove_enemies()
 check(game.phase == "day" and game.scrap == 210, "Actual dawn and its free card leave the unique economic wallet unchanged")
 game.phase_time = 10000.0 # Explicit long-day isolation, not extra currency.
 var crates: Array[Dictionary] = []
 for item: Dictionary in game.world.salvage:
  if item.position.z > 26.0 and game.outpost_walkable(item.position): crates.append(item)
 crates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return planar(a.position, Vector3(0, 0, 28)) < planar(b.position, Vector3(0, 0, 28)))
 var earned := 0
 for index in 2:
  var item: Dictionary = crates[index]
  # Direct positioning isolates pickup economy; production F still resolves
  # the genuine crate, reward owner, collected flag and only wallet.
  stand(item.position); camera_at(item.position)
  check(game.nearest_salvage() == game.world.salvage.find(item), "Unseeded route positions the hero by the true available outside salvage crate")
  var before: int = game.scrap; await press(KEY_F)
  var gain: int = game.scrap - before
  check(item.collected and gain == int(item.amount) + 3, "Actual F collects each genuine first-day crate and pays its exact real parts reward")
  earned += gain; before = game.scrap; await press(KEY_F)
  check(game.scrap == before, "Repeated real F on a collected salvage crate cannot mint parts")
 check(game.scrap == 210 + earned and earned >= 76, "Two genuine outside F rewards join the same unseeded parts balance")
 await build_gui("barracks", BARRACKS); await build_gui("infirmary", INFIRMARY)
 await train_gui(); await advance(9.01)
 await guard_selected(STATION); await advance(15.0)
 var patient: BattleUnit = game.squads.squads[0].members[1]
 patient.hurt(20.0, null)
 var before: int = game.scrap; await toggle_gui(true); game.simulate(.001); await advance(.651)
 check(game.squads.medic_snapshot().treatments == 1 and game.squads.medic_snapshot().spent == 2
  and is_equal_approx(patient.hp, patient.max_hp) and game.scrap == before - 2
  and game.scrap == 210 + earned - 60 - 100 - 90 - 2,
  "Untopped production wallet alone funds sixty-part barracks, hundred-part infirmary, ninety-part medic order and one two-part treatment")
 (evidence.support as Dictionary).unseeded_economy = {"opening":90,"real_wave_deaths":71,"five_wave_income":120,
  "real_crate_income":earned,"barracks":60,"infirmary":100,"training":90,"therapy":2,"remaining":game.scrap,
  "fixture":"long phases/passive existing defenses/direct crate positioning; no wallet assignment or difficulty claim"}
 await open_army(); camera_at(STATION); await capture("medic-unseeded-only-wallet-paid-success", false)
 (evidence.completed as Array).append("no_seed_parts_open90_real_5x24_71deaths_two_F_crates_60_100_90_then_two_only_wallet")

func run() -> void:
 await catalog_build_and_training()
 if failures.is_empty(): await precise_support_freeze_and_cooldown()
 if failures.is_empty(): await treatment_cancellation_and_last_parts()
 if failures.is_empty(): await real_targets_limits_and_no_enemy_damage()
 if failures.is_empty(): await bounded_small_deficit_and_full_health()
 if failures.is_empty(): await real_gate_and_geometry()
 if failures.is_empty(): await actual_building_los_release()
 if failures.is_empty(): await active_member_detachment()
 if failures.is_empty(): await selected_switch_and_default_layout()
 if failures.is_empty(): await actual_damage_upgrade_refill_and_phase()
 if failures.is_empty(): await actual_unseeded_economy()
 await close_game()
 var folder := ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
 var file := FileAccess.open(folder.path_join("medics.json"), FileAccess.WRITE)
 check(file != null, "Medic evidence opens only below local build")
 evidence.checks = checks; evidence.failures = failures
 if file: file.store_string(JSON.stringify(evidence, "\t")); file.close()
 print("NIGHTFALL_MEDICS_", "OK" if failures.is_empty() else "FAILED", " checks=", checks, " real_build_queue_selected_support_only_parts")
 quit(0 if failures.is_empty() else 1)
