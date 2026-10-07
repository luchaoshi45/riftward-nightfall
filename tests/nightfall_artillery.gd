extends SceneTree
## Production artillery: true GUI technology/queue, delayed area impacts and lifecycle.
## Explicit 5000 parts/long phases isolate rules; they are not difficulty proof.
const Catalog := preload("res://scripts/outpost_catalog.gd")
const Grid := preload("res://scripts/construction_grid.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
const RunSession := preload("res://scripts/run_session.gd")
const SEED := 20261006
const STEP := .05
const HOME := Vector3(0, 5, 3.1)
const BARRACKS := Vector3(7, 5, -8.5)
const WORKSHOP := Vector3(-7.5, 5, -8.5)
const LABORATORY := Vector3(7, 5, -3.5)
const ARMORY := Vector3(-7, 5, -3.5)
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
var output_dir := "res://build/artillery"
var hurt_events: Array[Dictionary] = []
var evidence: Dictionary = {"fixture_parts": 5000, "fixture_phase_seconds": 10000, "seed": SEED,
 "captures": [], "completed": [], "routes": [], "combat": {}}

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
 for enemy: Variant in game.enemies:
  if is_instance_valid(enemy): enemy.queue_free()
 game.enemies.clear()

func close_game() -> void:
 if not is_instance_valid(game): return
 var squads_token: int = game.squads.get_instance_id()
 await game.prepare_shutdown()
 check(int(game.squads.artillery_snapshot().get("pending",0)) == 0 and int(game.squads.artillery_snapshot().get("casting",0)) == 0, "Real shutdown clears support participants and all pending treatment")
 if current_scene == game: current_scene = null
 game.queue_free(); game = null
 for _frame in 4: await process_frame
 await create_timer(.2, true, false, true).timeout
 check(not is_instance_id_valid(squads_token), "Real scene shutdown releases the actual support owner after audio retirement")

func fresh(keep_wave: bool = false, seed_parts: bool = true) -> void:
 await close_game()
 check(RunSession.queue_request(self, SEED, "siege"), "Artillery production accepts the real fixed standard-run seed")
 game = load("res://scenes/nightfall.tscn").instantiate()
 root.add_child(game); current_scene = game
 for _frame in 5: await process_frame
 game.set_process(false); game.world.set_process(false)
 var script := GDScript.new(); script.source_code = OBSERVER
 check(script.reload() == OK, "Fixed artillery observer subclasses and forwards the actual production HUD")
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
 return {"artillery": game.squads.artillery_snapshot(), "parts": int(game.scrap), "phase": String(game.phase),
  "time": game.phase_time, "rng": game.run.rng.state, "spawn_rng": game.spawn_rng.state,
  "units": units, "orders": orders(), "queues": game.squads.training_queues.duplicate(true),
  "logistics": game.logistics.snapshot()}

func capture(label: String, night: bool = true) -> void:
 if not render_test: return
 check(DisplayServer.get_name() != "headless", "Artillery pictures require an actual graphical backend")
 if DisplayServer.get_name() == "headless": return
 var before := read_state()
 for viewport: Vector2i in VIEWPORTS:
  root.size = viewport; root.content_scale_size = viewport
  game.world.set_night(night); game.world.night_mix = 1.0 if night else 0.0
  game.world.apply_lighting(); game.hud.queue_redraw()
  for _frame in 5: await process_frame; await RenderingServer.frame_post_draw
  var picture: Image = root.get_texture().get_image()
  check(picture.get_size() == viewport and Vector2i(game.hud.get_viewport_rect().size) == viewport,
   "Actual artillery picture and HUD match " + str(viewport))
  for row: Dictionary in game.hud.drawn_labels:
   if bool(row.drawer):
    check(row.point.x >= 36 and row.point.x + float(row.width) <= 544
     and row.point.y + float(row.descent) < 692,
     "Actual new support drawer Chinese text remains inside its own column and above close")
   if String(row.text).contains("炮") or String(row.text).contains("救护"):
    check(row.point.x >= 0 and row.point.x + float(row.width) <= 1440 and row.point.y <= 900,
     "Actual artillery/infirmary Chinese labels stay within the scaled viewport")
  var folder := ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
  var name := "%s-%dx%d" % [label, viewport.x, viewport.y]
  check(picture.save_png(folder.path_join(name + ".png")) == OK, "Actual artillery screenshots stay below local build")
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

func artillery() -> Dictionary:
 return game.squads.artillery_snapshot()

func open_army(page: int = 2) -> void:
 if game.construction.active: await press(KEY_ESCAPE)
 if game.hud.detail_tab.is_empty(): await press(KEY_F3)
 if game.hud.detail_tab != "army": await click_ui(game.hud.details_tab_rect(2))
 for _step in 4:
  if game.hud.troop_page == page: break
  await click_ui(game.hud.troop_page_rect(1 if game.hud.troop_page < page else -1))
 await redraw()
 check(game.hud.detail_tab == "army" and game.hud.troop_page == page, "Actual F3 pagination selects artillery troop page " + str(page + 1))

func train_gui(kind: String = "artillery") -> void:
 var index := Catalog.TROOP_IDS.find(kind)
 await open_army(index / 3)
 var slot := index % 3
 check(game.hud.visible_training_kinds()[slot] == kind, "Real troop slot exposes the intended " + kind)
 var balance: int = game.scrap; var before := orders()
 await click_ui(game.hud.training_kind_rect(slot))
 check(game.scrap == balance - int(Catalog.troop(kind).cost) and orders() == before,
  "Actual " + kind + " button uses only parts and never issues a world order")
 await press(KEY_F3)

func guard_selected(point: Vector3) -> void:
 if not game.hud.detail_tab.is_empty(): await press(KEY_F3)
 await press(KEY_TAB); await aim_at(point); await press(KEY_O)

func dependencies() -> Dictionary:
 var barracks := await build_gui("barracks", BARRACKS)
 var workshop := await build_gui("workshop", WORKSHOP)
 var laboratory := await build_gui("laboratory", LABORATORY)
 var armory := await build_gui("armory", ARMORY)
 return {"barracks":barracks,"workshop":workshop,"laboratory":laboratory,"armory":armory}

func ready(one_shooter: bool = true) -> Dictionary:
 await fresh()
 var buildings := await dependencies()
 await train_gui(); await advance(12.001)
 check(game.squads.squads.size() == 1 and game.squads.squads[0].kind == "artillery", "Actual twelve-second paid queue produces one artillery group")
 var group: Dictionary = game.squads.squads[0]
 for member: BattleUnit in group.members:
  check(member.alive and is_equal_approx(member.max_hp,130.0 * game.districts.squad_health_multiplier())
   and member.armor == 0 and member.damage == 32 and member.speed == 2.4
   and member.attack_range == 16.0 and member.attack_interval == 4.8 and member.windup_duration == 1.0,
   "Each actual newborn炮手 exposes real HP, armor, damage, speed, range, windup and cooldown")
 await guard_selected(STATION); await advance(20.0)
 for slot in 3:
  var member: BattleUnit = group.members[slot]
  check(not member.moving and planar(member.position,STATION) < 1.6, "Actual slow炮手 finishes its walkable station route before timed shots")
  check(absf(member.position.x - (STATION.x + float(slot - 1) * 1.25)) < .17
   and absf(member.position.z - STATION.z) < .17, "Each actual炮手 retains its own distinct horizontal slot rather than stacking at the middle")
 if one_shooter:
  group.members[0].hurt(100000.0,null); group.members[2].hurt(100000.0,null)
  await process_frame
  check(group.members[0] == null and group.members[2] == null and group.members[1].alive,
   "Precise single-gun fixture uses two real casualties, not altered internal artillery cooldown")
 stand(HOME)
 hurt_events.clear()
 return {"group":group,"source":group.members[1],"buildings":buildings}

func source_shot(source: BattleUnit) -> Dictionary:
 var token := source.get_instance_id()
 for shot: Dictionary in artillery().get("shots",[]):
  if int(shot.source_token) == token: return shot
 return {}

func casting(source: BattleUnit) -> bool:
 var shot := source_shot(source)
 return not shot.is_empty() and String(shot.phase) in ["casting","windup"]

func firing(source: BattleUnit) -> bool:
 var shot := source_shot(source)
 return not shot.is_empty() and String(shot.phase) == "flight"

func spawn(point: Vector3, hp_value: float = 10000.0) -> BattleUnit:
 var enemy: BattleUnit = game.spawn_creature(true,"basic")
 point.y = game.outpost_height(point)
 enemy.position = point; enemy.speed = 0.0; enemy.damage = 0.0
 enemy.max_hp = hp_value; enemy.hp = hp_value; enemy.armor = 0.0; enemy.shield = 0.0
 enemy.damage_confirmed.connect(record_hurt)
 return enemy

func record_hurt(victim: BattleUnit, source: BattleUnit, hp_loss: float, shield_loss: float) -> void:
 hurt_events.append({"victim":victim.get_instance_id(),"source":source.get_instance_id() if is_instance_valid(source) else -1,
  "hp":hp_loss,"shield":shield_loss})

func step_squads(seconds: float) -> void:
 for frame in ceili(seconds / STEP):
  game.squads.advance(minf(STEP,seconds - float(frame) * STEP))
  if frame % 100 == 99: await process_frame

func launch(source: BattleUnit) -> Dictionary:
 game.squads.advance(.001)
 check(casting(source), "Real legal炮手 starts a complete independent windup")
 var state := source_shot(source)
 check(is_equal_approx(float(state.get("remaining",0)),1.0), "The start frame retains the complete one-second windup")
 await step_squads(.999)
 check(casting(source) and hurt_events.is_empty(), "Actual windup cannot fire or damage at .999 seconds")
 game.squads.advance(.002)
 check(firing(source) and hurt_events.is_empty(), "Only complete actual preparation creates a flight without immediate hurt")
 return source_shot(source)

func land(source: BattleUnit) -> void:
 await step_squads(.799)
 check(firing(source) and hurt_events.is_empty(), "Actual .8-second flight cannot damage at .799 seconds")
 game.squads.advance(.002)
 check(not firing(source), "The complete actual flight retires its committed projectile once")

func catalog_technology_queue() -> void:
 await fresh()
 check(Catalog.BUILDING_IDS == ["tower","barracks","workshop","recycler","laboratory","depot","infirmary","armory","command_relay","signal_beacon","holdfast_beacon"]
  and Catalog.TROOP_IDS.slice(0,7) == ["shield","ranged","engineer","ballista","hauler","medic","artillery"],
  "The expanded building catalog preserves the original seven-troop prefix")
 var building := Catalog.building("armory"); var troop := Catalog.troop("artillery")
 check(building.size == Vector2i(4,3) and building.cost == 140 and building.hp == 600.0
  and building.requires == ["laboratory","workshop"], "Armory real size,140 parts,600 HP and direct live prerequisites match design")
 check(troop.cost == 150 and troop.time == 12.0 and troop.hp == 130.0 and troop.requires == ["armory"],
  "Artillery real150 parts,12 seconds,130 HP and live-armory prerequisite match design")
 var original := artillery().duplicate(true); var balance: int = game.scrap
 for _read in 8: check(artillery() == original and game.scrap == balance, "Artillery read-only snapshot neither advances time nor changes wallet")
 await select_building("armory"); await aim_at(ARMORY)
 var locked: Dictionary = game.construction.snapshot()
 check(not locked.valid and not locked.tech_valid and locked.space_valid, "Actual missing armory technology stays distinct from geometry collision")
 await mouse(game.camera.unproject_position(ARMORY),true)
 check(game.scrap == balance and not game.districts.has_live("armory"), "Locked real armory preview cannot spend or create")
 await capture("armory-locked-third-building-page",false); await press(KEY_ESCAPE)
 await open_army()
 check(game.hud.visible_training_kinds().slice(0,1) == ["artillery"], "Third real troop page preserves its original炮兵 slot when later troops append")
 await click_ui(game.hud.training_kind_rect(0))
 check(game.scrap == balance and game.squads.training_queues.is_empty(), "Missing-armory visible artillery button never charges")
 for viewport: Vector2i in VIEWPORTS:
  root.size = viewport; root.content_scale_size = viewport; await redraw()
  var before := orders()
  for slot in range(game.hud.visible_training_kinds().size(),3):
   await click_ui(game.hud.training_kind_rect(slot)); await click_ui(game.hud.training_kind_rect(slot),MOUSE_BUTTON_RIGHT)
   check(game.scrap == balance and game.squads.training_queues.is_empty() and orders() == before,
    "Actual third-page hidden troop slots are inert and block battlefield pass-through at " + str(viewport))
 root.size = VIEWPORTS[0]; root.content_scale_size = VIEWPORTS[0]
 await press(KEY_F3)
 var buildings := await dependencies()
 var armory: Dictionary = game.districts.plots[int(buildings.armory)]
 check(armory.hp == 600.0 and Grid.placement(armory.position,"armory").cells.size() == 12,
  "Real paid armory has twelve actual grid cells and600 HP")
 for cell: Vector2i in Grid.placement(armory.position,"armory").cells:
  var center := Grid.cell_rect(cell).get_center()
  check(not game.outpost_walkable(Vector3(center.x,5,center.y)), "Every paid armory grid cell blocks navigation")
 camera_at(armory.position); await capture("armory-real-day",false); await capture("armory-real-night")
 stand(armory.position); balance = game.scrap; await press(KEY_F)
 check(armory.level == 2 and armory.max_hp == 780.0 and armory.hp == 780.0 and game.scrap == balance - 80,
  "Actual nearest-building F upgrades armory for80 to780 HP")
 stand(HOME); await train_gui(); await open_army()
 var queue: Array = game.squads.training_queues.get(int(buildings.barracks),[])
 check(queue.size() == 1 and queue[0].kind == "artillery" and is_equal_approx(float(queue[0].remaining),12.0),
  "Actual artillery button escrows150 in the real twelve-second barracks queue")
 balance = game.scrap
 var cancel: Dictionary = game.hud.training_cancel_buttons[0]
 await click_ui(cancel.rect)
 check(game.scrap == balance + 150 and game.squads.training_queues.get(int(buildings.barracks),[]).is_empty(),
  "Actual queue cancel returns exactly150 parts once")
 balance = game.scrap; await click_ui(cancel.rect)
 check(game.scrap == balance, "Stale artillery refund cannot return parts twice")
 await press(KEY_F3); await train_gui(); await open_army(); await capture("artillery-paid-third-troop-page")
 await press(KEY_F3)
 game.districts.damage(int(buildings.armory),100000.0)
 balance = game.scrap
 check(not game.squads.training_eligibility("artillery").available and not game.squads.enqueue("artillery").ok
  and not game.squads.hire("artillery").ok and game.scrap == balance,
  "Same-frame real armory death locks all new creation entry points without touching already-paid order")
 await advance(11.99); check(game.squads.squads.is_empty(), "Paid artillery training cannot complete before twelve true seconds")
 game.simulate(.011)
 check(game.squads.squads.size() == 1 and game.squads.squads[0].kind == "artillery" and game.scrap == balance,
  "Already-paid actual artillery completes after tech death with no second fee")
 await build_gui("armory",ARMORY); await train_gui()
 balance = game.scrap; game.districts.damage(int(buildings.barracks),100000.0); game.squads.refresh_barracks()
 check(game.scrap == balance + 150 and game.squads.training_queues.is_empty(), "Destroyed true producer refunds remaining artillery order once")
 balance = game.scrap; game.squads.refresh_barracks()
 check(game.scrap == balance, "Repeated producer refresh cannot double refund")
 (evidence.completed as Array).append("real8_7catalog_Y12cells_tech_F80upgrade_F3thirdpage_hidden_gui_12s_refunds_paid_survival")

func precise_fixed_area_and_cooldown() -> void:
 var prepared := await ready(); var source: BattleUnit = prepared.source
 var point: Vector3 = source.position + Vector3(10,0,0)
 var target := spawn(point)
 var hp: float = target.hp; var balance: int = game.scrap
 var state := await launch(source)
 check(planar(state.point,point) < .001 and int(state.target_token) == target.get_instance_id()
  and int(state.source_token) == source.get_instance_id(), "Committed actual炮弹 preserves real shooter,target token and locked ground point")
 camera_at(STATION); await capture("artillery-real-fixed-flight")
 await land(source)
 check(hurt_events.size() == 1 and hurt_events[0].source == source.get_instance_id()
  and hurt_events[0].hp == 32.0 and target.hp == hp - 32.0 and artillery().impacts == 1 and artillery().hits == 1
  and game.scrap == balance and game.kill_chain == 0, "One actual shot applies32 via its true炮手 and no ammunition fee or hero chain")
 var launched := int(artillery().launched)
 await step_squads(3.98)
 check(not casting(source) and artillery().launched == launched and hurt_events.size() == 1,
  "The launch-started4.8 cooldown includes flight once and cannot start a new windup early")
 game.squads.advance(.021)
 check(casting(source) and hurt_events.size() == 1, "Expired real cooldown starts a fresh complete windup rather than an immediate hit")
 await capture("artillery-next-complete-windup")
 game.squads.command_move(source.position + Vector3(0,0,3))
 check(not casting(source), "Real move command immediately cancels an unlaunched炮弹")
 prepared = await ready(); source = prepared.source; point = source.position + Vector3(10,0,0)
 target = spawn(point)
 var near := spawn(point + Vector3(2.19,0,0)); var edge := spawn(point + Vector3(2.2,0,0)); var outside := spawn(point + Vector3(2.21,0,0))
 var hero_hp: float = game.hero.hp; var beacon_hp: float = game.beacon_hp
 # Actual launch samples source damage; changing it after commit cannot rewrite this shell.
 source.damage = 40.0; await launch(source); source.damage = 99.0
 await land(source)
 check(target.hp == 9960.0 and near.hp == 9960.0 and edge.hp == 9960.0 and outside.hp == 10000.0
  and hurt_events.size() == 3, "Actual sampled forty-damage shell hurts each true enemy once through2.2 inclusive,not2.21")
 check(game.hero.hp == hero_hp and game.beacon_hp == beacon_hp and game.scrap == 5000 - 60 - 60 - 120 - 140 - 150,
  "Actual friendly hero/core and single wallet remain unchanged by area fire")
 (evidence.combat as Dictionary).area = {"real_hits":hurt_events.duplicate(true),"radius":2.2,"sampled_damage":40}
 await capture("artillery-real-three-enemy-blast")
 prepared = await ready(); source = prepared.source; point = source.position + Vector3(10,0,0)
 target = spawn(point); game.squads.advance(.001)
 target.position += Vector3(0,0,3.5); target.position.y = game.outpost_height(target.position)
 await step_squads(.999); game.squads.advance(.002)
 check(firing(source) and planar(source_shot(source).point,point) < .001, "A still-in-range true target can walk out of the fixed prelaunch landing circle")
 var entrant := spawn(point + Vector3(.4,0,0))
 await land(source)
 check(target.hp == 10000.0 and entrant.hp == 9968.0 and hurt_events.size() == 1,
  "Fixed old blast misses the actual displaced target and damages a genuine late entrant")
 await capture("artillery-real-target-dodged-new-entrant")
 (evidence.completed as Array).append("true1s_08flight_launch48cd_sampledamage_fixedpoint_radius22_multi_once_dodge_newenemy_no_fee_chain")

func true_damage_shield_and_armor() -> void:
 var prepared := await ready(); var source: BattleUnit = prepared.source
 var point: Vector3 = source.position + Vector3(10,0,0)
 var target := spawn(point); target.armor = 60.0; target.shield = 12.0; target.shield_time = 20.0
 await launch(source)
 var shielded := spawn(point + Vector3(.7,0,0)); shielded.shield = 50.0; shielded.shield_time = 20.0
 var balance: int = game.scrap
 await land(source)
 check(is_equal_approx(target.hp,9992.0) and target.shield == 0.0
  and shielded.hp == 10000.0 and shielded.shield == 18.0,
  "Actual32炮弹 goes through genuine60 armor then12 shield,while a fifty-point shield absorbs32 without HP loss")
 check(hurt_events.size() == 2 and hurt_events[0].source == source.get_instance_id()
  and is_equal_approx(float(hurt_events[0].hp),8.0) and is_equal_approx(float(hurt_events[0].shield),12.0)
  and float(hurt_events[1].hp) == 0.0 and float(hurt_events[1].shield) == 32.0,
  "Real damage_confirmed reports exact HP/shield losses and true炮手 for every actual area recipient")
 check(game.scrap == balance and game.kill_chain == 0, "Actual shield/armor impacts do not charge ammunition or manufacture hero連斩")
 (evidence.combat as Dictionary).armor_shield = hurt_events.duplicate(true)
 await capture("artillery-real-armor-shield-damage-confirmed")
 (evidence.completed as Array).append("truehurt32_armor60_shield12_hp8_neighbor_shield32_confirmed_source_no_fee")

func minimum_maximum_and_priority() -> void:
 for distance_value in [5.49,5.5,16.0,16.01]:
  var prepared := await ready(); var source: BattleUnit = prepared.source
  var enemy := spawn(source.position + Vector3(distance_value,0,0))
  game.squads.advance(.001)
  check(casting(source) == (distance_value >= 5.5 and distance_value <= 16.0),
   "True planar artillery range includes5.5/16.0 and rejects5.49/16.01: " + str(distance_value))
  if distance_value < 5.5 or distance_value > 16.0:
   await step_squads(2.0)
   check(artillery().launched == 0 and enemy.hp == 10000.0, "Invalid true range never falls back to immediate ordinary minion damage")
 var prepared := await ready(); var source: BattleUnit = prepared.source
 var close := spawn(source.position + Vector3(2,0,0)); var far := spawn(source.position + Vector3(10,0,0))
 await aim_at(close.position); await mouse(game.camera.unproject_position(close.position),true,MOUSE_BUTTON_RIGHT)
 check(game.squads.squads[0].order == "attack", "Genuine viewport right-click assigns a real designated enemy")
 var old: Vector3 = source.position
 game.squads.advance(.001)
 check(not casting(source) and artillery().launched == 0 and planar(source.position,old) < .001,
  "Explicit inner-range enemy keeps炮手 stationary and silent even when another far enemy is legal")
 await aim_at(far.position); await press(KEY_C); game.squads.advance(.001)
 check(not casting(source) and artillery().launched == 0 and planar(source.position,old) < .001,
  "Real C cannot override an explicit enemy already inside the minimum-range stop order")
 await aim_at(far.position); await mouse(game.camera.unproject_position(far.position),true,MOUSE_BUTTON_RIGHT)
 game.squads.advance(.001)
 check(casting(source) and int(source_shot(source).target_token) == far.get_instance_id(),
  "A genuine new explicit far-target command releases the deliberate inner-range stop")
 await capture("artillery-min-range-deliberate-stop-new-far-command")
 prepared = await ready(); source = prepared.source
 close = spawn(source.position + Vector3(2,0,0))
 await aim_at(close.position); await mouse(game.camera.unproject_position(close.position),true,MOUSE_BUTTON_RIGHT)
 old = source.position; await step_squads(3.0)
 check(planar(source.position,old) < .001 and artillery().launched == 0 and close.hp == 10000.0,
  "A sole explicit too-close enemy leaves real炮手 stationary and silent")
 prepared = await ready(); source = prepared.source
 var nearest := spawn(source.position + Vector3(7,0,0)); far = spawn(source.position + Vector3(10,0,0))
 game.squads.advance(.001)
 check(int(source_shot(source).target_token) == nearest.get_instance_id(), "Unordered炮手 picks the nearest actual legally ranged enemy")
 game.squads.command_guard(STATION)
 await aim_at(far.position); await mouse(game.camera.unproject_position(far.position),true,MOUSE_BUTTON_RIGHT)
 game.squads.advance(.001)
 check(int(source_shot(source).target_token) == far.get_instance_id(), "Actual explicit target takes precedence over a nearer legal enemy")
 game.squads.command_guard(STATION)
 await aim_at(far.position); await press(KEY_C)
 check(game.focus_target == far and game.focus_time > 0.0, "Actual C sets a real focus target")
 game.squads.advance(.001)
 check(int(source_shot(source).target_token) == far.get_instance_id(), "Actual live C focus takes precedence over nearest legal enemy")
 (evidence.completed as Array).append("inclusive55_16_nearest_rightclick_no_order_C_priority_inner_target_fixed_stop_no_auto_switch")

func cancellation_orphan_and_roster() -> void:
 for reason in ["inner_range","outer_range","target_death","move","source_death"]:
  var prepared := await ready(); var source: BattleUnit = prepared.source
  var target := spawn(source.position + Vector3(10,0,0)); var token := source.get_instance_id()
  game.squads.advance(.001); check(casting(source), "Real " + reason + " fixture begins a genuine unlaunched preparation")
  match reason:
   "inner_range": target.position = source.position + Vector3(5.49,0,0)
   "outer_range": target.position = source.position + Vector3(16.01,0,0)
   "target_death": target.hurt(100000.0,null)
   "move": game.squads.command_move(source.position + Vector3(0,0,3))
   "source_death": source.hurt(100000.0,null)
  target.position.y = game.outpost_height(target.position)
  var before := hurt_events.size(); await step_squads(2.0); await process_frame
  check(artillery().launched == 0 and hurt_events.size() == before,
   "Actual " + reason + " cancels before launch without delayed damage")
  if reason == "source_death": check(not is_instance_id_valid(token), "Dead preparation source actually frees rather than leaving invisible artillery")
 var prepared := await ready(); var source: BattleUnit = prepared.source
 var point: Vector3 = source.position + Vector3(10,0,0); var target := spawn(point)
 await launch(source)
 var source_token := source.get_instance_id(); source.hurt(100000.0,null)
 await process_frame
 check(not is_instance_id_valid(source_token) and artillery().pending == 1, "A committed real shell outlives its genuinely freed shooter")
 await capture("artillery-source-freed-still-in-flight")
 await step_squads(.801)
 check(target.hp == 9968.0 and hurt_events.size() == 1 and hurt_events[0].source == -1 and artillery().impacts == 1,
  "Freed-source actual projectile still applies its sampled32 once using null source")
 await step_squads(6.0)
 check(hurt_events.size() == 1 and artillery().pending == 0, "Actual orphan retires with no repeat shell or reward")
 prepared = await ready(); source = prepared.source; point = source.position + Vector3(10,0,0); target = spawn(point)
 await launch(source)
 var detached := spawn(point + Vector3(.2,0,0)); game.enemies.erase(detached)
 var rogue := load("res://scripts/unit.gd").new() as BattleUnit; rogue.setup("monster",2); game.add_child(rogue)
 rogue.position = point; rogue.hp = 10000.0; rogue.max_hp = 10000.0; rogue.armor = 0.0
 rogue.set_meta("threat","basic")
 var friend := load("res://scripts/unit.gd").new() as BattleUnit; friend.setup("monster",1); game.add_child(friend)
 friend.position = point; friend.hp = 10000.0; friend.max_hp = 10000.0; friend.armor = 0.0; game.enemies.append(friend)
 await land(source)
 check(target.hp == 9968.0 and detached.hp == 10000.0 and rogue.hp == 10000.0 and friend.hp == 10000.0,
  "Actual blast only hurts current real living enemy roster,not detached,fake-meta or wrong-team units")
 game.enemies.erase(friend); detached.queue_free(); rogue.queue_free(); friend.queue_free()
 (evidence.completed as Array).append("prelaunch_range_target_source_order_cancel_true_source_release_orphan_once_real_roster_not_meta_friend")
func place(source: BattleUnit, point: Vector3) -> void:
 point.y = game.outpost_height(point)
 check(game.outpost_walkable(point), "Actual cannon placement lies outside real building and wall footprints")
 game.squads.command_guard(point)
 source.position = point; source.path.clear(); source.moving = false

func actual_ground_walls_buildings() -> void:
 var prepared := await ready(); var source: BattleUnit = prepared.source
 place(source,Vector3(0,0,28))
 var point := Vector3(0,0,20); point.y = game.outpost_height(point)
 var target := spawn(point)
 check(absf(source.position.y - point.y) > .9 and game.can_attack_line(source.position,point),
  "True grounded artillery ramp fixture has different world heights and actual open gate LOS")
 await launch(source)
 var uphill := spawn(point + Vector3(0,0,-2.19)); var downhill := spawn(point + Vector3(0,0,2.19))
 var edge := spawn(point + Vector3(2.2,0,0)); var outside := spawn(point + Vector3(0,0,2.21))
 var flying := spawn(point + Vector3(.3,0,0)); flying.position.y += .91
 await land(source)
 check(target.hp == 9968.0 and uphill.hp == 9968.0 and downhill.hp == 9968.0 and edge.hp == 9968.0
  and outside.hp == 10000.0 and flying.hp == 10000.0,
  "Actual slope area covers both true ground elevations and inclusive2.2,but excludes2.21 and .91 airborne recipient")
 await capture("artillery-ramp-ground-relative-area")
 (evidence.combat as Dictionary).slope = {"point":point,"source":source.position,"uphill":uphill.position,"downhill":downhill.position,"hits":hurt_events.duplicate(true)}
 prepared = await ready(); source = prepared.source
 place(source,Vector3(5.7,5,-12)); point = Vector3(12.7,5,-12)
 target = spawn(point); await launch(source)
 var occluded := spawn(Vector3(14.65,0,-12))
 check(planar(point,occluded.position) < 2.2 and not game.can_attack_line(point,occluded.position),
  "Actual blast wall counterexample is truly within radius across the real closed east wall")
 await land(source)
 check(target.hp == 9968.0 and occluded.hp == 10000.0, "Actual blast excludes a true enemy through closed castle wall despite area proximity")
 await capture("artillery-closed-east-wall-blast-exclusion")
 prepared = await ready(); source = prepared.source
 place(source,Vector3(12,5,-10)); target = spawn(Vector3(18,0,-10))
 check(not game.can_attack_line(source.position,target.position), "True aimed target lies across actual closed east wall")
 await step_squads(3.0)
 check(artillery().launched == 0 and target.hp == 10000.0, "Real aiming cannot throw through a closed castle wall")
 prepared = await ready(); source = prepared.source
 place(source,Vector3(2.5,5,-8.5)); target = spawn(Vector3(11,5,-8.5))
 var barracks: Dictionary = game.districts.plots[int(prepared.buildings.barracks)]
 var hp: float = barracks.hp
 check(barracks.position.x > source.position.x and barracks.position.x < target.position.x
  and game.can_attack_line(source.position,target.position), "Real friendly producer lies inside an otherwise actual legal炮弹 firing path")
 await launch(source); await land(source)
 check(target.hp == 9968.0 and barracks.hp == hp, "Real shell flies over an actual friendly building and never damages it")
 await capture("artillery-flies-over-real-barracks-no-friendly-hit")
 prepared = await ready(); source = prepared.source
 source.position.y += .91; target = spawn(source.position + Vector3(10,0,0))
 # Actual ground-relative shooter rejection must occur before its guard move repairs Y.
 game.squads.advance(.001)
 check(not casting(source), "An actual .91-off-ground source cannot aim a fresh artillery shot")
 (evidence.completed as Array).append("true_ramp_world_height_ground_relative09_22_wall_aim_blast_block_friendlybuilding_overfly_no_damage")

func real_height_boundaries() -> void:
 for offset in [.89,.9,.91]:
  var prepared := await ready(); var source: BattleUnit = prepared.source
  var target := spawn(source.position + Vector3(10,0,0)); target.position.y += offset
  game.squads.advance(.001)
  check(casting(source) == (offset <= .9), "Actual target local-height offset accepts.89/.9 and rejects.91: " + str(offset))
  prepared = await ready(); source = prepared.source
  source.position.y += offset; target = spawn(source.position + Vector3(10,0,0))
  game.squads.advance(.001)
  check(casting(source) == (offset <= .9), "Actual source local-height offset accepts.89/.9 and rejects.91: " + str(offset))
 for offset_difference in [.89,.9,.91]:
  var pair := await ready(); var paired_source: BattleUnit = pair.source
  paired_source.position.y += .45
  var paired_target := spawn(paired_source.position + Vector3(10,0,0))
  paired_target.position.y -= offset_difference - .45
  game.squads.advance(.001)
  check(casting(paired_source) == (offset_difference <= .9),
   "Each real unit is locally grounded but their .89/.9/.91 offset difference controls aim: " + str(offset_difference))
 var prepared := await ready(); var source: BattleUnit = prepared.source
 source.position.y += 1.0
 var target := spawn(source.position + Vector3(10,0,0)); target.position.y += 1.0
 game.squads.advance(.001)
 check(not casting(source), "Equal one-metre local offsets never let two genuinely airborne units fake grounded aiming")
 prepared = await ready(); source = prepared.source
 var point: Vector3 = source.position + Vector3(10,0,0); target = spawn(point)
 await launch(source)
 var recipients: Array[BattleUnit] = []
 for index in 3:
  var recipient := spawn(point + Vector3(0,0,float(index+1)*.4))
  recipient.position.y += [.89,.9,.91][index]; recipients.append(recipient)
 await land(source)
 check(recipients[0].hp == 9968.0 and recipients[1].hp == 9968.0 and recipients[2].hp == 10000.0,
  "Actual fixed ground blast includes local-height.89/.9 and excludes.91 independently of world altitude")
 (evidence.combat as Dictionary).height_offsets = [.89,.9,.91]
 (evidence.completed as Array).append("true_source_target_089_09_091_and_both_airborne_rejected_actual_blast_height_boundaries")

func genuine_friends_and_building_inside_blast() -> void:
 var prepared := await ready(); var source: BattleUnit = prepared.source
 var point: Vector3 = source.position + Vector3(10,0,0)
 await train_gui("shield"); await advance(6.001)
 remove_enemies(); hurt_events.clear(); var target := spawn(point)
 var group: Dictionary = game.squads.squads[1]
 game.squads.set_order("recall",int(group.id))
 for slot in 3:
  var friend: BattleUnit = group.members[slot]
  friend.position = point + Vector3(float(slot)*.25,0,.5); friend.position.y = game.outpost_height(friend.position)
  friend.hp = friend.max_hp * .6; friend.shield = 17.0; friend.shield_time = 20.0
 stand(point + Vector3(.3,0,-.5)); game.hero.hp = game.hero.max_hp * .6; game.hero.shield = 19.0; game.hero.shield_time = 20.0
 # True squad members use their genuine owner/roster. Advance only the shell
 # after launch so unrelated recall movement cannot move them outside the circle.
 game.squads.advance(.001); await step_squads(.999); game.squads.advance(.002)
 var before: Array[Dictionary] = []
 for slot in 3:
  var friend: BattleUnit = group.members[slot]
  friend.position = point + Vector3(float(slot)*.25,0,.5); friend.position.y = game.outpost_height(friend.position)
  before.append({"hp":friend.hp,"shield":friend.shield})
 var hero_hp: float = game.hero.hp; var hero_shield: float = game.hero.shield
 game.squads.artillery.advance(.801)
 check(target.hp == 9968.0 and game.hero.hp == hero_hp and game.hero.shield == hero_shield,
  "Actual blast hurts true enemy but leaves a genuinely injured live hero inside the blast unchanged")
 for slot in 3:
  check(group.members[slot].hp == before[slot].hp and group.members[slot].shield == before[slot].shield,
   "Actual blast never harms a genuine active friendly soldier located inside its circle")
 await capture("artillery-true-hero-and-shields-inside-blast-safe")
 prepared = await ready(); source = prepared.source
 var barracks: Dictionary = game.districts.plots[int(prepared.buildings.barracks)]
 var armory: Dictionary = game.districts.plots[int(prepared.buildings.armory)]
 place(source,Vector3(2.5,5,-8.5)); point = barracks.position + Vector3(1.9,0,0)
 target = spawn(point)
 var hp: float = barracks.hp; var armory_hp: float = armory.hp
 check(planar(point,barracks.position) < 2.2, "Actual enemy explosion center puts a true live耐久兵营 inside its radius")
 await launch(source); await land(source)
 check(target.hp == 9968.0 and barracks.hp == hp and armory.hp == armory_hp,
  "Actual projectile damages its true nearby enemy without subtracting any real friendly building durability")
 await capture("artillery-real-barracks-inside-blast-no-durability-loss")
 (evidence.completed as Array).append("true_live_roster_friends_injured_hero_and_durable_barracks_inside_circle_enemy_only")

func impact_reenter(victim: BattleUnit, _attacker: BattleUnit, _hp: float, _shield: float,
 mode: String, reserve: BattleUnit, next_target: BattleUnit, record: Dictionary) -> void:
 record.calls = int(record.calls) + 1
 if int(record.calls) != 1: return
 if mode == "clear": game.squads.artillery.clear_pending()
 elif mode in ["setup","new_generation"]:
  game.squads.artillery.setup(game)
  if mode == "new_generation":
   game.squads.artillery.register(reserve)
   game.squads.command_guard(reserve.position)
   record.started = game.squads.artillery.begin(reserve,next_target)
 elif mode == "defeat": game.end_defeat("炮兵回归 · 真实hurt回调结算")
 elif mode == "victory": game.day_number = 4; game.finish_night()
 record.victim = victim.get_instance_id()

func actual_reentry_and_released_target() -> void:
 for mode in ["clear","setup","new_generation","defeat","victory"]:
  var prepared := await ready(false); var source: BattleUnit = prepared.source
  await train_gui(); await advance(12.001)
  var reserve_group: Dictionary = game.squads.squads[1]
  game.squads.set_order("recall",1); await advance(10.0)
  var reserve: BattleUnit = reserve_group.members[1]
  game.squads.cancel_selection(); game.squads.select_at(reserve.position)
  check(game.squads.selected_ids == [1] and not reserve.moving and reserve.attack_timer == 0.0,
   "New-generation reserve is a genuinely trained idle炮手 with untouched cooldown and a real selected group")
  var point: Vector3 = source.position + Vector3(10,0,0)
  var target := spawn(point); var neighbour := spawn(point + Vector3(.6,0,0))
  var next_target := spawn(reserve.position + Vector3(-10,0,0))
  var hook: Dictionary = {"calls":0,"started":false}
  target.damage_confirmed.connect(impact_reenter.bind(mode,reserve,next_target,hook))
  await launch(source)
  check(artillery().flight == 3, "Three true炮手 create three committed shells before a synchronous " + mode + " damage callback")
  game.squads.artillery.advance(.801)
  check(hook.calls == 1 and hurt_events.size() == 1 and target.hp == 9968.0 and neighbour.hp == 10000.0,
   "First true hurt callback " + mode + " retires old generation before neighbour or another residual shell is damaged")
  if mode == "new_generation":
   check(hook.started and casting(reserve) and is_equal_approx(float(source_shot(reserve).remaining),1.0)
    and next_target.hp == 10000.0 and artillery().flight == 0,
    "New actual registered generation retains full preparation and is never processed by the old flight iteration")
   await capture("artillery-real-hurt-reentry-new-generation-full-windup")
   await step_squads(.999); game.squads.advance(.002); game.squads.artillery.advance(.801)
   check(next_target.hp == 9968.0 and neighbour.hp == 10000.0 and hurt_events.size() == 2,
    "New generation subsequently completes its own actual preparation and flight exactly once")
  else:
   check(artillery().pending == 0 and artillery().casting == 0, "Actual " + mode + " retirement leaves no old pending shot")
  (evidence.combat as Dictionary)["reentry_" + mode] = {"calls":hook.calls,"new_started":hook.started,"events":hurt_events.duplicate(true)}
 var prepared := await ready(); var source: BattleUnit = prepared.source
 var point: Vector3 = source.position + Vector3(10,0,0); var target := spawn(point)
 await launch(source)
 var old_target := target.get_instance_id(); target.hurt(100000.0,null)
 await process_frame
 check(not is_instance_id_valid(old_target) and artillery().flight == 1, "Launched target truly frees without removing its already committed fixed-point shell")
 hurt_events.clear()
 var entrant := spawn(point + Vector3(.4,0,0)); game.enemies.append(entrant)
 game.squads.artillery.advance(.801)
 check(entrant.hp == 9968.0 and hurt_events.size() == 1 and artillery().hits == 1,
  "True late enemy at freed target's old point is hurt once even when the production roster accidentally repeats the same instance")
 game.enemies.erase(entrant)
 (evidence.completed as Array).append("real_damage_confirmed_clear_setup_new_epoch_defeat_victory_stops_residuals_true_target_freed_late_enemy_duplicate_roster_once")

func actual_route_and_far_designated() -> void:
 var prepared := await ready(false); var group: Dictionary = prepared.group
 var point := Vector3(0,0,28)
 await guard_selected(point)
 var crossed: Dictionary = {}; var distances: Dictionary = {}
 for frame in 260:
  var before: Dictionary = {}
  for member: BattleUnit in group.members: before[member.get_instance_id()] = member.position
  game.simulate(STEP)
  for member: BattleUnit in group.members:
   var token := member.get_instance_id(); var old: Vector3 = before[token]
   check(member.position.is_finite() and game.outpost_walkable(member.position)
    and absf(member.position.y - game.outpost_height(member.position)) < .001,
    "Every actual slow three-gun route sample stays on real walkable terrain")
   check(game.can_traverse(old,member.position) and planar(old,member.position) <= 2.4 * STEP + .001,
    "Every actual slow cannon route step obeys terrain navigation and its2.4 speed")
   distances[token] = float(distances.get(token,0.0)) + planar(old,member.position)
   if old.z < Layout.WALL_CENTER and member.position.z >= Layout.WALL_CENTER:
    var fraction := (Layout.WALL_CENTER - old.z) / (member.position.z - old.z)
    check(absf(lerpf(old.x,member.position.x,fraction)) < Layout.GATE_HALF, "Real artillery crosses the unique gate,never castle wall")
    crossed[token] = true
  if frame % 100 == 99: await process_frame
 check(crossed.size() == 3 and artillery().launched == 0, "All three genuine artillery members travel through the sole south gate without phantom attacks")
 for member: BattleUnit in group.members:
  check(not member.moving and planar(member.position,point) < 1.6, "Actual three-gun march reaches its declared outside formation")
 (evidence.routes as Array).append({"crossed":crossed.size(),"distances":distances.values(),"speed":2.4})
 await capture("artillery-three-true-members-outside-south-gate",false)
 prepared = await ready(); var source: BattleUnit = prepared.source
 var target := spawn(Vector3(0,0,32)); target.max_hp = 100000.0; target.hp = 100000.0
 await aim_at(target.position); await mouse(game.camera.unproject_position(target.position),true,MOUSE_BUTTON_RIGHT)
 var old: Vector3 = source.position; var walked := 0.0; var crossed_gate := false; var began := false
 for frame in 360:
  var before: Vector3 = source.position; game.squads.advance(STEP)
  check(game.can_traverse(before,source.position) and game.outpost_walkable(source.position)
   and planar(before,source.position) <= 2.4 * STEP + .001, "Far explicit target approach follows actual paths and2.4 speed")
  walked += planar(before,source.position)
  if before.z < Layout.WALL_CENTER and source.position.z >= Layout.WALL_CENTER: crossed_gate = true
  if casting(source) or firing(source): began = true; break
 check(began and walked > 5.0 and crossed_gate and planar(source.position,target.position) >= 5.5
  and planar(source.position,target.position) <= 16.0 and not source.moving,
  "Far designated enemy induces a real unique-gate approach then stationary legal-range preparation")
 (evidence.routes as Array).append({"far_walked":walked,"from":old,"stopped":source.position,"target":target.position,"crossed":crossed_gate})
 (evidence.completed as Array).append("three_true_24speed_unique_gate_march_far_designated_real_route_stop_in_55_16")

func unit_cd(source: BattleUnit) -> float:
 for row: Dictionary in artillery().get("units",[]):
  if int(row.source_token) == source.get_instance_id(): return float(row.cooldown)
 return -1.0

func freezing_phase_and_shutdown() -> void:
 for stage in ["windup","flight"]:
  var prepared := await ready(); var source: BattleUnit = prepared.source
  var target := spawn(source.position + Vector3(10,0,0))
  game.squads.advance(.001)
  if stage == "flight": await step_squads(1.001)
  game.squads.cancel_selection()
  await press(KEY_ESCAPE)
  check(game.phase == "paused", "Actual Esc enters a real " + stage + " pause")
  var stopped := read_state(); game.squads.advance(4.0); game.simulate(4.0)
  check(read_state() == stopped, "Actual pause freezes artillery clocks,point,units,queue,wallet and orders during " + stage)
  await capture("artillery-paused-" + stage)
  await press(KEY_ESCAPE)
  game.run.grant("炮兵验收 · 免费选卡冻结")
  await press(KEY_V)
  check(game.phase == "draft", "Actual V enters its production choice during " + stage)
  stopped = read_state(); game.squads.advance(4.0); game.simulate(4.0)
  check(read_state() == stopped, "Actual card choice freezes artillery flight/preparation with no hidden hurt during " + stage)
  await capture("artillery-choice-frozen-" + stage)
  await press(KEY_1)
  check(target.hp == 10000.0, "Actual frozen artillery target remains unhurt until active time resumes")
 var prepared := await ready(); var source: BattleUnit = prepared.source
 var target := spawn(source.position + Vector3(10,0,0)); await launch(source)
 var cd := unit_cd(source)
 check(cd > 0.0, "Read-only real炮手 exposes its current launch-started cooldown")
 game.finish_night()
 check(game.phase == "draft" and artillery().pending == 0 and artillery().casting == 0 and is_equal_approx(unit_cd(source),cd),
  "Real dawn cancels residual shells and prelaunch shots while preserving launched cooldown")
 await press(KEY_1)
 check(game.phase == "day" and is_equal_approx(unit_cd(source),cd), "The real free dawn choice cannot refresh炮手 cooldown")
 game.start_night(); remove_enemies(); game.wave_index = game.WAVES_PER_NIGHT; game.phase_time = 10000.0
 check(artillery().pending == 0 and artillery().casting == 0 and is_equal_approx(unit_cd(source),cd),
  "Real dusk also clears pending shots without refreshing survivor cooldown")
 var balance: int = game.scrap
 await press(KEY_TAB); await aim_at(source.position); await press(KEY_O)
 check(is_equal_approx(unit_cd(source),cd) and game.scrap == balance, "Real new guard order cannot reset cooldown or charge ammunition")
 await capture("artillery-dawn-dusk-preserved-cooldown")
 prepared = await ready(); source = prepared.source; target = spawn(source.position + Vector3(10,0,0)); await launch(source)
 var target_hp: float = target.hp; game.end_defeat("炮兵回归 · 真实失败清理")
 check(game.phase == "ended" and artillery().pending == 0 and artillery().casting == 0, "Actual defeat cancels every炮弹 and preparation")
 game.squads.advance(2.0); check(target.hp == target_hp, "Ended gameplay cannot land a retired炮弹")
 prepared = await ready(); source = prepared.source; target = spawn(source.position + Vector3(10,0,0)); await launch(source)
 # Real final-clearance code resolves victory after the only living target dies.
 game.day_number = 4; game.begin_final_clearance(); target.hurt(100000.0,null)
 await process_frame; game.simulate(.01)
 check(game.phase == "ended" and game.victory and artillery().pending == 0 and artillery().casting == 0,
  "Real final victory retires friendly residual fire rather than keeping a fake enemy alive")
 prepared = await ready(); source = prepared.source; target = spawn(source.position + Vector3(10,0,0)); await launch(source)
 var owner_token: int = game.squads.get_instance_id(); await close_game()
 check(not is_instance_id_valid(owner_token), "Actual window/scene shutdown releases owner and committed cannon effects")
 (evidence.completed as Array).append("realEsc_V_pause_draft_freeze_dawn_dusk_keepCD_guard_not_reset_defeat_final_victory_shutdown")

func true_damage_multiplier_refill() -> void:
 var prepared := await ready(false); var group: Dictionary = prepared.group
 var source: BattleUnit = prepared.source
 source.hurt(65.0,null); var ratio := source.hp / source.max_hp
 var barracks: Dictionary = game.districts.plots[int(prepared.buildings.barracks)]
 stand(barracks.position); var balance: int = game.scrap; await press(KEY_F)
 check(barracks.level == 2 and game.scrap == balance - 80
  and is_equal_approx(source.max_hp,130.0 * game.districts.squad_health_multiplier())
  and is_equal_approx(source.hp / source.max_hp,ratio), "Actual F producer upgrade applies130 base HP multiplier while retaining wounded ratio")
 var casualty_token: int = group.members[0].get_instance_id(); group.members[0].hurt(100000.0,null); await process_frame
 check(not is_instance_id_valid(casualty_token), "Actual cannon casualty frees its real member instance")
 game.finish_night(); await press(KEY_1); remove_enemies(); game.phase_time = 10000.0
 var fee: int = game.squads.refill_cost(0); balance = game.scrap
 await press(KEY_L)
 check(fee == 41 and game.scrap == balance - 41 and game.squads.refill_cost(0) == 0,
  "Actual daytime L pays36 for one炮手 plus5 for half-health survivor,with no extra wallet")
 for member: BattleUnit in group.members:
  check(member.alive and member.hp == member.max_hp and member.max_hp == 130.0 * game.districts.squad_health_multiplier(),
   "Real replacement and resting survivor retain catalog130 scaled HP")
 balance = game.scrap; await press(KEY_L)
 check(game.scrap == balance, "Repeated full-health cannon restocking cannot charge twice")
 await capture("artillery-actual-upgraded-refilled-three-member-team",false)
 (evidence.completed as Array).append("truehurt_F80_HP130_keep_ratio_real_freed_casualty_day_L36plus5_refill_once")

func actual_unseeded_economy_and_ledgers() -> void:
 await fresh(true,false)
 check(game.scrap == 90, "Untopped artillery economy starts with the actual90 opening parts")
 var deaths := 0
 for wave in 5:
  var balance: int = game.scrap; var victims: Array = game.enemies.duplicate()
  for enemy: BattleUnit in victims:
   if not is_instance_valid(enemy) or not enemy.alive: continue
   enemy.hurt(100000.0,null); deaths += 1
   var paid: int = game.scrap; enemy.hurt(100000.0,null)
   check(game.scrap == paid and game.wave_rewards.defeat(enemy) == 0, "Duplicate actual death cannot pay another economic ledger entry")
  check(game.scrap == balance + 24 and game.wave_rewards.snapshot(wave).paid == 24,
   "Each true standard first-night wave still pays exactly24 parts")
  await process_frame; game.enemies.clear()
  if wave < 4: game.spawn_night_wave()
 check(deaths == 71 and game.scrap == 210 and game.kill_chain == 0, "First true71 deaths pay120 total without fake hero連斩")
 game.finish_night(); await press(KEY_1); remove_enemies(); game.phase_time = 10000.0
 var earned := 0; var picks := 0; var crate_receipts: Array[Dictionary] = []
 var crates: Array[Dictionary] = []
 for item: Dictionary in game.world.salvage:
  if item.position.z > 26.0 and game.outpost_walkable(item.position): crates.append(item)
 crates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return planar(a.position,Vector3(0,0,28)) < planar(b.position,Vector3(0,0,28)))
 for item: Dictionary in crates:
  if game.scrap >= 530: break
  stand(item.position); camera_at(item.position); var balance: int = game.scrap
  check(game.nearest_salvage() == game.world.salvage.find(item), "Untopped artillery stands by its genuine available salvage crate")
  var exploration_before: int = game.exploration_count
  var base_parts: int = int(item.amount) + 3
  var milestone_parts := 55 if (exploration_before + 1) % 5 == 0 else 0
  await press(KEY_F); var gain: int = game.scrap - balance
  check(item.collected and game.exploration_count == exploration_before + 1 and gain == base_parts + milestone_parts,
   "Real F pays its finite crate plus existing fifth-discovery milestone once into only parts wallet")
  crate_receipts.append({"base":base_parts,"existing_milestone":milestone_parts,"actual":gain,"exploration":game.exploration_count})
  earned += gain; picks += 1; balance = game.scrap; await press(KEY_F)
  check(game.scrap == balance, "Collected artillery-economy crate cannot pay twice")
 check(game.scrap >= 530 and game.scrap == 210 + earned, "Real finite crate earnings plus actual120 night ledger afford530 of declared artillery dependencies")
 await dependencies(); await train_gui(); await advance(12.001)
 check(game.scrap == 210 + earned - 530 and game.squads.squads.size() == 1,
  "Untopped production wallet alone funds60+60+120+140 construction and150 real artillery training")
 var group: Dictionary = game.squads.squads[0]
 await guard_selected(STATION); await advance(20.0)
 group.members[0].hurt(100000.0,null); group.members[2].hurt(100000.0,null); await process_frame
 var source: BattleUnit = group.members[1]
 var target := spawn(source.position + Vector3(10,0,0),16.0)
 var balance: int = game.scrap; var chain: int = game.kill_chain
 await launch(source); await land(source)
 check(not target.alive and game.scrap == balance + 5 and game.kill_chain == chain,
  "True daytime炮手 kill pays only original5 parts,no ammo fee or hero chain")
 await process_frame; remove_enemies()
 game.start_night(); game.phase_time = 10000.0
 var wave_income := 0; var cannon_deaths := 0
 for wave in 5:
  var before: int = game.scrap; var victims: Array = game.enemies.duplicate()
  var reward_id: int = game.active_wave_reward_id
  check(reward_id == 5 + wave, "Real second-night artillery wave uses its actual5..9 production reward ID")
  game.wave_index = wave + 1
  game.squads.command_guard(STATION)
  source.position = STATION; source.moving = false; source.path.clear()
  var anchor: Vector3 = STATION + Vector3(10,0,0)
  for enemy: BattleUnit in victims:
   enemy.position = anchor; enemy.position.y = game.outpost_height(anchor)
   enemy.speed = 0.0; enemy.damage = 0.0; enemy.armor = 0.0; enemy.shield = 0.0; enemy.hp = 16.0
  for _frame in 160:
   game.squads.advance(STEP)
   if bool(game.wave_rewards.snapshot(reward_id).get("cleared",false)): break
  check(bool(game.wave_rewards.snapshot(reward_id).get("cleared",false)) and int(game.wave_rewards.snapshot(reward_id).get("paid",-1)) == 24
   and game.scrap == before + 24 and game.kill_chain == chain,
   "Actual artillery area deaths clear true standard wave for24 and never invent hero連斩 or per-enemy wallet")
  wave_income += game.scrap - before; cannon_deaths += victims.size()
  await process_frame; game.enemies.clear()
  if wave < 4: game.spawn_night_wave()
 check(wave_income == 120, "Five genuine second-night炮弹-cleared waves retain120 ledger total")
 (evidence.combat as Dictionary).unseeded = {"opening":90,"night1_deaths":deaths,"night1_parts":120,"crates":picks,"crate_parts":earned,"crate_receipts":crate_receipts,
  "build_and_training":530,"day_cannon_parts":5,"actual_night2_artillery_deaths":cannon_deaths,"night2_parts":wave_income,"remaining":game.scrap,
  "fixture":"extended stages/passive unrelated defenses/direct crate and combat placements,real callbacks; no wallet topup or真人难度 claim"}
 await open_army(); await capture("artillery-untopped-single-wallet-actual-ledger",false)
 (evidence.completed as Array).append("untopped90_real71deaths120_trueFcrate530dependencies_day5_night5x24_artillery_area_no_chain")

func complete_model_geometry() -> void:
 await fresh()
 var model: Node3D = game.districts.create_model("armory")
 game.add_child(model)
 var bounds: AABB = game.districts.model_bounds(model)
 check(model.scale.is_equal_approx(Vector3.ONE) and bounds.position.x >= -2.0001 and bounds.end.x <= 2.0001
  and bounds.position.z >= -1.5001 and bounds.end.z <= 1.5001 and bounds.size.x > 1.0 and bounds.size.z > 1.0,
  "Complete actual armory model including炮管 and crates fits4x3 with root scale1,not a second preview shrink")
 (evidence.combat as Dictionary).armory_geometry = {"min":bounds.position,"max":bounds.end,"size":bounds.size,"scale":model.scale}
 model.queue_free()
 (evidence.completed as Array).append("actual_complete_armory_factory_bounds_all_meshes_root_scale1_fit4x3")

func run() -> void:
 var probe: Node = load("res://scripts/outpost_squads.gd").new()
 var ready_api := probe.has_method("artillery_snapshot")
 probe.free()
 var cases := {"geometry":complete_model_geometry,"catalog":catalog_technology_queue,
  "timing":precise_fixed_area_and_cooldown,"armor":true_damage_shield_and_armor,
  "range":minimum_maximum_and_priority,"cancel":cancellation_orphan_and_roster,
  "terrain":actual_ground_walls_buildings,"height":real_height_boundaries,
  "friends":genuine_friends_and_building_inside_blast,"reentry":actual_reentry_and_released_target,
  "route":actual_route_and_far_designated,
  "freeze":freezing_phase_and_shutdown,"refill":true_damage_multiplier_refill,
  "economy":actual_unseeded_economy_and_ledgers}
 var selected: Array = cases.keys()
 var args := OS.get_cmdline_user_args(); var at := args.find("--case")
 if at >= 0 and at + 1 < args.size():
  if cases.has(args[at + 1]): selected = [args[at + 1]]
  else: check(false,"Artillery case argument must name a known local test case")
 evidence.selected_cases = selected
 if not ready_api:
  check(false,"Actual production artillery_snapshot must exist before executing new acceptance")
 elif failures.is_empty():
  for case_name: String in selected:
   print("ARTILLERY_STAGE_BEGIN ",case_name)
   await (cases[case_name] as Callable).call()
   print("ARTILLERY_STAGE_END ",case_name," checks=",checks," failures=",failures.size())
   if not failures.is_empty(): break
 await close_game()
 var folder := ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
 var file := FileAccess.open(folder.path_join("artillery.json"),FileAccess.WRITE)
 check(file != null,"Artillery evidence opens only below local build")
 evidence.checks = checks; evidence.failures = failures
 if file: file.store_string(JSON.stringify(evidence,"\t")); file.close()
 print("NIGHTFALL_ARTILLERY_","OK" if failures.is_empty() else "FAILED"," checks=",checks," actual_fixed_area_minrange_lifecycle_only_parts")
 quit(0 if failures.is_empty() else 1)
