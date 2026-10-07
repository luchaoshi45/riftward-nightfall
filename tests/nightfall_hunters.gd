extends SceneTree
## Production hunters: real queue, bounded melee pursuit, damage and lifecycle.
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
var output_dir := "res://build/hunters"
var hurt_events: Array[Dictionary] = []
var finished := false
var active_stage := "initialization"
var evidence: Dictionary = {"fixture_parts": 5000, "fixture_phase_seconds": 10000, "seed": SEED,
 "captures": [], "completed": [], "routes": [], "combat": {}, "economy": {}}

func _initialize() -> void:
 var args := OS.get_cmdline_user_args()
 render_test = "--render-test" in args
 var index := args.find("--output-dir")
 if index >= 0 and index + 1 < args.size():
  var candidate := ProjectSettings.globalize_path(args[index + 1]).simplify_path()
  var allowed := ProjectSettings.globalize_path("res://build").simplify_path()
  if candidate.begins_with(allowed + "/"): output_dir = candidate
  else: check(false, "Hunter output is restricted to this project's local build directory")
 root.size = VIEWPORTS[0]; root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
 root.content_scale_size = VIEWPORTS[0]
 if DisplayServer.get_name() != "headless":
  DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
  root.position = Vector2i(10000,10000); root.hide()
 create_timer(300.0,true,false,true).timeout.connect(watchdog)
 call_deferred("run")

func watchdog() -> void:
 if finished: return
 push_error("Hunter acceptance stalled before completing " + active_stage)
 quit(1)

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
 check(game.squads.squads.is_empty() and game.squads.hunter_snapshot().get("units", []).is_empty(), "Actual shutdown clears hunter roster and pursuit state")
 if current_scene == game: current_scene = null
 game.queue_free(); game = null
 for _frame in 4: await process_frame
 await create_timer(.2, true, false, true).timeout
 check(not is_instance_id_valid(squads_token), "Real scene shutdown releases the actual support owner after audio retirement")

func fresh(keep_wave: bool = false, seed_parts: bool = true) -> void:
 await close_game()
 check(RunSession.queue_request(self, SEED, "siege"), "Hunter production accepts the real fixed standard-run seed")
 game = load("res://scenes/nightfall.tscn").instantiate()
 root.add_child(game); current_scene = game
 for _frame in 5: await process_frame
 game.set_process(false); game.world.set_process(false)
 var script := GDScript.new(); script.source_code = OBSERVER
 check(script.reload() == OK, "Fixed hunter observer subclasses and forwards the actual production HUD")
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
 var units: Array[Dictionary] = []
 for squad: Dictionary in game.squads.squads:
  for member: BattleUnit in squad.members:
   if is_instance_valid(member): units.append({"token":member.get_instance_id(), "position":member.position,
    "hp":member.hp, "cooldown":member.attack_timer, "windup":member.attack_windup,
    "queued":member.attack_queued, "target":member.target.get_instance_id() if is_instance_valid(member.target) else -1})
 return {"hunters":game.squads.hunter_snapshot(), "parts":game.scrap, "phase":game.phase,
  "time":game.phase_time, "rng":game.run.rng.state, "spawn_rng":game.spawn_rng.state,
  "units":units, "orders":orders(), "queues":game.squads.training_queues.duplicate(true)}

func capture(label: String, night: bool = true) -> void:
 if not render_test: return
 check(DisplayServer.get_name() != "headless", "Hunter pictures require an actual graphical backend")
 if DisplayServer.get_name() == "headless": return
 var before := read_state()
 for viewport: Vector2i in VIEWPORTS:
  root.size = viewport; root.content_scale_size = viewport
  game.world.set_night(night); game.world.night_mix = 1.0 if night else 0.0
  game.world.apply_lighting(); game.hud.queue_redraw()
  for _frame in 5: await process_frame; await RenderingServer.frame_post_draw
  var picture: Image = root.get_texture().get_image()
  check(picture.get_size() == viewport and Vector2i(game.hud.get_viewport_rect().size) == viewport,
   "Actual hunter picture and HUD match " + str(viewport))
  var stale_draft := false
  for row: Dictionary in game.hud.drawn_labels:
   stale_draft = stale_draft or String(row.text) == "灰烬中的记忆"
  check(not stale_draft and game.hud.card_rects.is_empty() and not game.hud.drawn_rects.is_empty(),
   "Actual hunter capture redraws its current tactical HUD and clears opening-card rectangles")
  for row: Dictionary in game.hud.drawn_labels:
   if bool(row.drawer):
    check(row.point.x >= 36 and row.point.x + float(row.width) <= 544
     and row.point.y + float(row.descent) < 692,
     "Actual new support drawer Chinese text remains inside its own column and above close")
   if String(row.text).contains("猎手"):
    check(row.point.x >= 0 and row.point.x + float(row.width) <= 1440 and row.point.y <= 900,
     "Actual hunter/infirmary Chinese labels stay within the scaled viewport")
  var folder := ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
  var name := "%s-%dx%d" % [label, viewport.x, viewport.y]
  check(picture.save_png(folder.path_join(name + ".png")) == OK, "Actual hunter screenshots stay below local build")
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

func open_army() -> void:
 if game.construction.active: await press(KEY_ESCAPE)
 if game.hud.detail_tab.is_empty(): await press(KEY_F3)
 if game.hud.detail_tab != "army": await click_ui(game.hud.details_tab_rect(2))
 for _page in 4:
  if game.hud.troop_page == 2: break
  await click_ui(game.hud.troop_page_rect(1))
 await redraw()
 check(game.hud.detail_tab == "army" and game.hud.troop_page == 2,
  "Actual F3 selects the existing third troop page")

func train_gui() -> void:
 await open_army()
 check(game.hud.visible_training_kinds() == ["artillery","hunter","flamer"], "Third page exposes cannon, hunter and flamethrower entries")
 var balance: int = game.scrap; var before := orders()
 await click_ui(game.hud.training_kind_rect(1))
 check(game.scrap == balance - 110 and orders() == before,
  "Actual hunter button escrows110 parts once without issuing a world order")
 await press(KEY_F3)

func guard_selected(point: Vector3) -> void:
 if not game.hud.detail_tab.is_empty(): await press(KEY_F3)
 await press(KEY_TAB); await aim_at(point); await press(KEY_O)

func ready(one: bool = true) -> Dictionary:
 await fresh()
 var barracks := await build_gui("barracks", BARRACKS)
 var workshop := await build_gui("workshop", WORKSHOP)
 await train_gui(); await advance(10.001)
 check(game.squads.squads.size() == 1 and game.squads.squads[0].kind == "hunter",
  "Actual ten-second production queue creates a real hunter group")
 var group: Dictionary = game.squads.squads[0]
 for member: BattleUnit in group.members:
  check(member.alive and is_equal_approx(member.max_hp,125.0 * game.districts.squad_health_multiplier())
   and member.armor == 0 and member.speed == 5.4 and member.damage == 12
   and member.attack_range == 2.3 and member.attack_interval == 1.4 and member.windup_duration == .22,
   "Each genuinely trained hunter has its actual combat and health values")
 await guard_selected(STATION); await step(12.0)
 check(not group.members[1].moving and planar(group.members[1].position,STATION) < .17,
  "Actual hunter reaches its issued guard station before precision combat")
 if one:
  group.members[0].hurt(100000.0,null); group.members[2].hurt(100000.0,null)
  await process_frame
  check(group.members[0] == null and group.members[2] == null, "Single-attacker fixture uses genuine casualties")
 hurt_events.clear(); stand(HOME)
 return {"group":group,"source":group.members[1],"barracks":barracks,"workshop":workshop}

func step(seconds: float) -> void:
 for frame in ceili(seconds / STEP):
  game.squads.advance(minf(STEP,seconds - float(frame) * STEP))
  if frame % 100 == 99: await process_frame

func spawn(point: Vector3, role: String = "basic", hp_value: float = 10000.0) -> BattleUnit:
 var enemy: BattleUnit = game.spawn_creature(true,role)
 point.y = game.outpost_height(point)
 enemy.position = point; enemy.speed = 0.0; enemy.damage = 0.0
 enemy.max_hp = hp_value; enemy.hp = hp_value; enemy.armor = 0.0; enemy.shield = 0.0
 enemy.damage_confirmed.connect(record_hurt)
 return enemy

func record_hurt(victim: BattleUnit, source: BattleUnit, hp_loss: float, shield_loss: float) -> void:
 hurt_events.append({"victim":victim.get_instance_id(),"source":source.get_instance_id() if is_instance_valid(source) else -1,
  "hp":hp_loss,"shield":shield_loss})

func exhaust(enemy: BattleUnit) -> void:
 enemy.set_meta("summoner_spawned",2)
 for controller: Node3D in game.summoners:
  if int(controller.snapshot().source_token) == enemy.get_instance_id(): controller.advance(.001)
 check(not bool(enemy.get_meta("summoner_active",true)), "Real summon controller recognizes its consumed lifetime quota")

func begin(source: BattleUnit, target: BattleUnit) -> void:
 game.squads.advance(.001)
 check(source.attack_queued and source.target == target and is_equal_approx(source.attack_windup,.22),
  "Actual legal melee selection starts a complete .22-second preparation")

func catalog_queue() -> void:
 await fresh()
 check(Catalog.BUILDING_IDS.size() == 10 and Catalog.TROOP_IDS == ["shield","ranged","engineer","ballista","hauler","medic","artillery","hunter","flamer"],
  "Hunter and flamethrower preserve the expanded building catalog and troop roster")
 var troop: Dictionary = Catalog.troop("hunter")
 check(troop.cost == 110 and troop.time == 10.0 and troop.hp == 125.0 and troop.requires == ["workshop"],
  "Actual hunter catalog matches110 parts/10 seconds/125 HP/live workshop")
 var original: Dictionary = game.squads.hunter_snapshot(); var balance: int = game.scrap
 check(original.has("units") and game.squads.hunter_snapshot() == original and game.scrap == balance,
  "Hunter snapshot is read-only before any group exists")
 var barracks := await build_gui("barracks",BARRACKS)
 await open_army(); balance = game.scrap
 await click_ui(game.hud.training_kind_rect(1))
 check(game.scrap == balance and game.squads.training_queues.is_empty(), "Visible hunter button cannot spend without a live workshop")
 for viewport: Vector2i in VIEWPORTS:
  root.size = viewport; root.content_scale_size = viewport; await redraw()
  var before := orders()
  await click_ui(game.hud.training_kind_rect(2)); await click_ui(game.hud.training_kind_rect(2),MOUSE_BUTTON_RIGHT)
  check(game.scrap == balance and orders() == before and game.squads.training_queues.is_empty(),
   "Locked third-page flamethrower entry neither trades nor sends world orders at " + str(viewport))
 root.size = VIEWPORTS[0]; root.content_scale_size = VIEWPORTS[0]; await press(KEY_F3)
 var workshop := await build_gui("workshop",WORKSHOP)
 await train_gui(); await open_army(); balance = game.scrap
 var cancel: Dictionary = game.hud.training_cancel_buttons[0]
 await click_ui(cancel.rect)
 check(game.scrap == balance + 110 and game.squads.training_queues.get(barracks,[]).is_empty(),
  "Real cancellation refunds the entire hunter escrow")
 balance = game.scrap; await click_ui(cancel.rect)
 check(game.scrap == balance, "Stale visible refund cannot return110 twice")
 await press(KEY_F3); await train_gui(); await open_army(); await capture("hunter-paid-third-page",false)
 await press(KEY_F3); balance = game.scrap
 game.districts.damage(workshop,100000.0)
 check(not game.squads.training_eligibility("hunter").available and not game.squads.enqueue("hunter").ok
  and not game.squads.hire("hunter").ok and game.scrap == balance,
  "Actual workshop death locks every new creation entry while retaining the paid queue")
 await advance(9.99)
 check(game.squads.squads.is_empty(), "Real hunter queue does not complete early at9.99 seconds")
 game.simulate(.011)
 check(game.squads.squads.size() == 1 and game.squads.squads[0].kind == "hunter" and game.scrap == balance,
  "Already-paid hunter survives its prerequisite destruction without a second payment")
 await build_gui("workshop",WORKSHOP); await train_gui(); balance = game.scrap
 game.districts.damage(barracks,100000.0); game.squads.refresh_barracks()
 check(game.scrap == balance + 110 and game.squads.training_queues.is_empty(), "Destroyed producer refunds its remaining hunter order")
 balance = game.scrap; game.squads.refresh_barracks()
 check(game.scrap == balance and game.squads.squads.size() == 1, "Producer refund occurs once and does not erase existing hunters")
 evidence.completed.append("catalog")

func timing_and_damage() -> void:
 var prepared := await ready(); var source: BattleUnit = prepared.source
 var target := spawn(source.position + Vector3(1.8,0,0))
 await begin(source,target); await step(.219)
 check(target.hp == 10000 and source.attack_queued, "Incomplete .219 melee windup causes no damage")
 await capture("hunter-real-incomplete-melee-windup")
 game.squads.advance(.002)
 check(target.hp == 9988 and hurt_events.size() == 1 and is_equal_approx(source.attack_timer,1.4),
  "Complete preparation performs one actual12 hurt and starts1.4 seconds from impact")
 await step(.3)
 check(is_equal_approx(source.attack_timer,1.1) and not source.attack_queued, "Actual unit tick reduces hunter cooldown once per elapsed step")
 await step(1.099)
 check(target.hp == 9988 and not source.attack_queued, "Hunter cannot prepare another hit before the real interval expires")
 game.squads.advance(.002)
 check(source.attack_queued and is_equal_approx(source.attack_windup,.22), "Cooldown completion begins another full windup")
 await step(.219); check(target.hp == 9988, "Second incomplete preparation cannot shortcut damage")
 game.squads.advance(.002)
 check(target.hp == 9976 and hurt_events.size() == 2 and hurt_events[0].source == source.get_instance_id(),
  "Second real hit occurs once and credits the hunter rather than hero")
 await open_army(); await capture("hunter-selected-third-page-real-cooldown"); await press(KEY_F3)
 evidence.completed.append("timing")

func specialist_bonus() -> void:
 var prepared := await ready(); var source: BattleUnit = prepared.source
 var receipts: Array[Dictionary] = []
 for role in ["basic","breaker","sapper","runner","light_eater","lobber","summoner","spent"]:
  remove_enemies(); game.squads.command_guard(STATION); await step(2.0); hurt_events.clear()
  var enemy := spawn(source.position + Vector3(1.5,0,0),"summoner" if role == "spent" else role)
  if role == "spent": exhaust(enemy)
  var bonus: bool = role in ["runner","light_eater","lobber","summoner"]
  var damage := 30.0 if bonus else 12.0
  await begin(source,enemy); await step(.221)
  check(enemy.hp == 10000.0 - damage and hurt_events.size() == 1,
   "Actual " + role + " receives only its declared hunter base and specialist bonus")
  receipts.append({"role":role,"hp_loss":10000.0 - enemy.hp})
 remove_enemies(); game.squads.command_guard(STATION); await step(2.0); hurt_events.clear()
 var armored := spawn(source.position + Vector3(1.5,0,0),"runner")
 armored.armor = 100.0; armored.shield = 7.0
 await begin(source,armored); await step(.221)
 check(armored.hp == 9992.0 and armored.shield == 0.0 and hurt_events.size() == 1
  and hurt_events[0].hp == 8.0 and hurt_events[0].shield == 7.0,
  "Combined30 base damage passes through real100 armor and7 shield before8 HP loss")
 evidence.combat.bonus = receipts; await capture("hunter-specialist-shield-armor")
 evidence.completed.append("bonus")

func target_priority() -> void:
 var prepared := await ready(); var source: BattleUnit = prepared.source
 var expected: Array[BattleUnit] = []
 for role in ["summoner","lobber","light_eater","runner","basic","breaker","sapper"]:
  expected.append(spawn(source.position + Vector3(1.0 + .1 * expected.size(),0,0),role))
 for target: BattleUnit in expected:
  game.squads.advance(.001)
  check(source.attack_queued and source.target == target, "Real hunter priority selects " + str(target.get_meta("threat","")))
  await step(.221)
  check(hurt_events.back().victim == target.get_instance_id(), "Actual hurt follows the selected priority target")
  target.hurt(100000.0,null); await process_frame; await step(1.401)
  # The interval step may already have started the next preparation. An
  # explicit guard command cancels it without modifying the consumed CD.
  game.squads.command_guard(STATION)
 remove_enemies(); await step(2.0)
 var close := spawn(source.position + Vector3(1.0,0,0),"runner")
 var far := spawn(source.position + Vector3(2.0,0,0),"runner")
 await begin(source,close); await step(.221)
 check(close.hp == 9970 and far.hp == 10000, "Equal specialist priority uses nearest genuine enemy")
 remove_enemies(); game.squads.command_guard(STATION); await step(2.0)
 var specialist := spawn(source.position + Vector3(1,0,0),"lobber")
 var focus := spawn(source.position + Vector3(2,0,0))
 stand(HOME); await aim_at(focus.position); await press(KEY_C)
 check(game.focus_target == focus and game.focus_time > 0, "Real C input installs an actual live focus")
 await begin(source,focus); await step(.221)
 check(focus.hp == 9988 and specialist.hp == 10000, "Legal shared C focus precedes automatic specialist priority")
 game.focus_time = 0.0
 remove_enemies(); game.squads.command_guard(STATION); await advance(22.001)
 var outside := spawn(STATION + Vector3(8.01,0,0),"lobber")
 var inside := spawn(source.position + Vector3(1,0,0))
 await aim_at(outside.position); await press(KEY_C)
 check(game.focus_target == outside and game.focus_time > 0, "Actual tower focus can address an enemy beyond this hunter's guard boundary")
 await begin(source,inside); await step(.221)
 check(inside.hp == 9988 and outside.hp == 10000, "Shared C does not authorize hunter pursuit outside its8m anchor")
 game.focus_time = 0.0
 evidence.completed.append("priority")

func fixed_anchor_and_gate() -> void:
 var prepared := await ready(); var source: BattleUnit = prepared.source
 for radius in [7.99,8.0,8.01]:
  remove_enemies(); game.squads.command_guard(STATION); await step(3.0)
  var origin: Vector3 = source.position
  var target := spawn(STATION + Vector3(radius,0,0),"lobber")
  game.squads.advance(.1)
  check((source.position != origin and source.target == target) if radius <= 8.0 else (source.position == origin and source.target == null),
   "Actual fixed guard anchor applies the " + str(radius) + "m chase boundary")
  if radius <= 8.0:
   target.position = STATION + Vector3(8.01,0,0); target.position.y = game.outpost_height(target.position)
   await step(3.0)
   check(planar(source.position,STATION) < .17 and target.hp == 10000,
    "A moving hunter never moves its anchor or follows a threat beyond8m")
 remove_enemies()
 prepared = await ready(false); var group: Dictionary = prepared.group
 var anchor := Vector3(0,5,11.8); await guard_selected(anchor); await step(8.0)
 var target := spawn(Vector3(0,0,19.5),"lobber")
 var crossed: Dictionary = {}; var valid_route := true; var obeys_speed := true; var distances: Dictionary = {}
 for frame in 100:
  var previous: Dictionary = {}
  for member: BattleUnit in group.members: previous[member.get_instance_id()] = member.position
  game.squads.advance(STEP)
  for member: BattleUnit in group.members:
   var old: Vector3 = previous[member.get_instance_id()]; var token := member.get_instance_id()
   valid_route = valid_route and game.outpost_walkable(member.position) and game.can_traverse(old,member.position)
   obeys_speed = obeys_speed and planar(old,member.position) <= 5.4 * STEP + .001
   distances[token] = float(distances.get(token,0.0)) + planar(old,member.position)
   if old.z < Layout.WALL_CENTER and member.position.z >= Layout.WALL_CENTER:
    var ratio := (Layout.WALL_CENTER - old.z) / (member.position.z - old.z)
    valid_route = valid_route and absf(lerpf(old.x,member.position.x,ratio)) < Layout.GATE_HALF
    crossed[token] = true
 check(valid_route and obeys_speed and crossed.size() == 3 and target.hp < 10000,
  "All three real hunters pursue through the unique south gate at their actual speed and attack")
 await capture("hunter-three-members-real-south-gate",false)
 target.hurt(100000.0,null); await process_frame; await step(8.0)
 var returned := true
 for member: BattleUnit in group.members: returned = returned and planar(member.position,anchor) < 1.6 and not member.attack_queued
 check(returned, "Actual target death returns all three hunters to their distinct original guard slots")
 evidence.routes.append({"gate_crossed":crossed.size(),"walked":distances.values(),"returned":returned})
 # MOVE and RECALL are orders, not implicit automatic chase permissions.
 remove_enemies(); await guard_selected(STATION); await step(8.0)
 source = group.members[1]; var idle := spawn(source.position + Vector3(1,0,0),"runner")
 game.squads.command_move(source.position + Vector3(0,0,3)); await step(1.0)
 check(idle.hp == 10000 and not source.attack_queued, "MOVE does not chase or strike a nearby specialist")
 game.squads.set_order("recall",0); await step(8.0)
 idle.position = source.position + Vector3(1,0,0); idle.position.y = game.outpost_height(idle.position)
 await step(1.0)
 check(idle.hp == 10000 and not source.attack_queued, "RECALL remains noncombat even beside a genuine enemy")
 remove_enemies(); game.squads.set_order("hold",0); await step(12.0)
 var held: Vector3 = source.position
 var held_enemy := spawn(held + Vector3(0,0,6),"runner")
 game.squads.advance(.1)
 check(source.position != held and source.target == held_enemy, "Default HOLD also permits bounded pursuit from its actual fixed station")
 held_enemy.hurt(100000.0,null); await process_frame; await step(6.0)
 check(planar(source.position,held) < .17, "Default HOLD returns to its original station after actual target death")
 evidence.completed.append("anchor")

func explicit_attack_and_roster() -> void:
 for rejection in ["boundary","death","released","removed"]:
  var prepared := await ready(); var source: BattleUnit = prepared.source; var group: Dictionary = prepared.group
  var issued := STATION + Vector3(0,0,6); var target := spawn(issued)
  await aim_at(target.position); await mouse(game.camera.unproject_position(target.position),true,MOUSE_BUTTON_RIGHT)
  check(group.order == "attack", "Actual selected-army right click issues a genuine attack command")
  var anchor: Vector3 = group.destination; var old: Vector3 = source.position
  await step(.4)
  check(source.position != old and game.can_traverse(old,source.position), "Explicit attack approaches along actual traversable terrain")
  var spare := spawn(source.position + Vector3(1,0,0),"lobber")
  if rejection == "boundary":
   target.position = anchor + Vector3(8.01,0,0); target.position.y = game.outpost_height(target.position)
  elif rejection == "removed": game.enemies.erase(target)
  elif rejection == "death": target.hurt(100000.0,null)
  else:
   target.queue_free(); await process_frame
  hurt_events.clear(); game.squads.advance(.01)
  check(group.order == "guard" and planar(group.destination,anchor) < .01 and not source.attack_queued
   and source.target == null and spare.hp == 10000 and hurt_events.is_empty(),
   "Actual " + rejection + " rejects designated pursuit, returns to issued anchor and never switches enemies in that frame")
  remove_enemies(); await step(6.0)
  check(planar(source.position,anchor) < .17, "Rejected explicit attack returns physically to its immutable issued position")
  if rejection == "boundary": await capture("hunter-explicit-target-boundary-return",false)
 var prepared := await ready(); var source: BattleUnit = prepared.source
 var target := spawn(source.position + Vector3(1,0,0))
 game.enemies.erase(target); var balance: int = game.scrap
 check(not game.squads.command_attack(target).ok and game.scrap == balance,
  "A live monster absent from the actual enemy roster cannot masquerade as a designated target")
 target.queue_free(); await process_frame
 evidence.completed.append("attack")

func cancellation_and_walls() -> void:
 var prepared := await ready(); var source: BattleUnit = prepared.source
 var target := spawn(source.position + Vector3(2.29,0,0))
 await begin(source,target); await step(.1)
 target.position = source.position + Vector3(2.31,0,0)
 game.squads.advance(.13)
 check(target.hp == 10000 and hurt_events.is_empty() and source.attack_timer == 0.0,
  "An enemy leaving2.3m cancels its unfinished true melee hit without consuming cooldown")
 remove_enemies(); game.squads.command_guard(STATION); await step(3.0)
 target = spawn(source.position + Vector3(1.5,0,0))
 await begin(source,target); await step(.1)
 game.squads.command_move(STATION + Vector3(0,0,2)); await step(.2)
 check(target.hp == 10000 and not source.attack_queued and source.attack_timer == 0.0,
  "Actual movement command cancels an incomplete hunter windup")
 remove_enemies(); game.squads.command_guard(STATION); await step(3.0)
 target = spawn(source.position + Vector3(1.5,0,0))
 await begin(source,target); var token := source.get_instance_id()
 source.hurt(100000.0,null); await process_frame; await step(.3)
 check(not is_instance_id_valid(token) and target.hp == 10000, "A genuinely dead and freed hunter cannot finish its queued melee hit")
 prepared = await ready(); source = prepared.source
 var wall_station := Vector3(6.5,5,Layout.WALL_CENTER - 1.0)
 game.squads.command_guard(wall_station); await step(12.0)
 target = spawn(Vector3(6.5,0,Layout.WALL_CENTER + 1.0))
 check(planar(source.position,target.position) < 2.3 and not game.can_attack_line(source.position,target.position),
  "Actual close enemy and hunter are separated by the real south wall")
 await step(.5)
 check(target.hp == 10000 and not source.attack_queued, "Hunters cannot deliver close melee damage through the actual castle wall")
 await capture("hunter-wall-blocks-melee",false)
 prepared = await ready(); source = prepared.source
 var offsets := [[0.0,.89,true],[0.0,.9,true],[0.0,.91,false],
  [.89,.89,true],[.9,.9,true],[.91,.91,false],[-.45,.45,true],[-.451,.45,false]]
 for row: Array in offsets:
  remove_enemies(); source.position.y = game.outpost_height(source.position)
  game.squads.command_guard(STATION); await step(2.0)
  source.position.y += float(row[0])
  target = spawn(source.position + Vector3(1.5,0,0))
  target.position.y = game.outpost_height(target.position) + float(row[1])
  game.squads.advance(.001); await step(.221)
  check(target.hp == (9988.0 if bool(row[2]) else 10000.0),
   "Actual hunter contact respects source/target ground offsets " + str(row.slice(0,2)))
 # The building is created through actual Y selection after a full melee
 # preparation has started. Both actors remain outside its real occupied
 # cells; only their close contact segment crosses the corner of the wall.
 prepared = await ready(); source = prepared.source
 var plot_point := Vector3(7.5,5,1.0)
 var footprint: Rect2 = Grid.placement(plot_point,"workshop").rect
 var corner: Vector2 = footprint.end
 var east := Vector3(corner.x + .55,5,corner.y - 1.0)
 var north := Vector3(corner.x - 1.0,5,corner.y + .55)
 await guard_selected(east); await step(12.0)
 target = spawn(north)
 check(game.can_traverse(source.position,target.position) and planar(source.position,target.position) < 2.3,
  "Real close bodies are on walkable terrain before the new corner building exists")
 await begin(source,target)
 var new_workshop := await build_gui("workshop",plot_point)
 evidence.combat.contact = {"source":source.position,"target":target.position,
  "actual_building":game.districts.plots[new_workshop].position,"expected_building":Grid.placement(plot_point,"workshop").point,
  "source_walkable":game.outpost_walkable(source.position),"target_walkable":game.outpost_walkable(target.position),
  "contact_walkable":game.can_traverse(source.position,target.position)}
 check(game.outpost_walkable(source.position) and game.outpost_walkable(target.position)
  and not game.can_traverse(source.position,target.position),
  "A real newly-built workshop blocks contact without placing either live actor inside a building cell")
 game.squads.advance(.221)
 check(target.hp == 10000 and not source.attack_queued and source.attack_timer == 0,
  "Real-time construction across contact cancels the already-started melee hit before any damage or cooldown")
 await capture("hunter-real-workshop-cancels-contact",false)
 game.districts.damage(new_workshop,100000.0)
 game.squads.select_at(source.position); game.squads.command_move(east); await step(2.0)
 game.squads.command_guard(east)
 check(game.can_traverse(source.position,target.position), "Actual workshop demolition removes its contact blocker")
 hurt_events.clear(); await begin(source,target); await step(.221)
 check(target.hp == 9988 and hurt_events.size() == 1,
  "After actual blocker demolition the hunter completes a new full melee preparation and one real hurt")
 evidence.completed.append("cancel")

func freeze_phase_and_reentry() -> void:
 var prepared := await ready(); var source: BattleUnit = prepared.source
 var target := spawn(source.position + Vector3(1.5,0,0))
 await begin(source,target); game.squads.cancel_selection(); await press(KEY_ESCAPE)
 check(game.phase == "paused", "Actual Esc pauses the hunter preparation")
 var stopped := read_state(); game.squads.advance(4.0); game.simulate(4.0)
 check(read_state() == stopped, "Pause freezes real hunters, pursuit, windup, queues, random state and wallet")
 await capture("hunter-paused-real-windup"); await press(KEY_ESCAPE)
 game.run.grant("猎手回归 · 免费选卡夹具"); await press(KEY_V)
 check(game.phase == "draft", "Actual V opens the real pending card choice")
 stopped = read_state(); game.squads.advance(4.0); game.simulate(4.0)
 check(read_state() == stopped, "Card selection freezes the same actual hunter state")
 await press(KEY_1); await step(.221)
 check(target.hp == 9988 and source.attack_timer > 0, "Resumed actual hunter completes one original preparation")
 var cooldown := source.attack_timer
 game.squads.command_guard(STATION); game.squads.on_day()
 check(not source.attack_queued and source.target == null and source.attack_timer == cooldown
  and prepared.group.order == "guard", "Dawn cancels pursuit while preserving manual guard and consumed cooldown")
 game.squads.on_night()
 check(source.attack_timer == cooldown and prepared.group.order == "guard", "Night transition also preserves manual guard and consumed cooldown")
 for mode in ["clear","setup","defeat","victory"]:
  prepared = await ready(false); source = prepared.source
  target = spawn(source.position + Vector3(0,0,1))
  var hook: Dictionary = {"calls":0}
  target.damage_confirmed.connect(on_reentry.bind(mode,hook))
  game.squads.advance(.001)
  var all_preparing := true
  for member: BattleUnit in prepared.group.members: all_preparing = all_preparing and member.attack_queued
  check(all_preparing, "All three true hunters have complete windups before synchronous " + mode)
  game.squads.advance(.221)
  check(hook.calls == 1 and hurt_events.size() == 1 and target.hp == 9988,
   "First actual hurt callback " + mode + " stops residual old-generation hunter attacks")
  check(game.squads.hunter_snapshot().get("units",[]).is_empty(), "Actual reentrant " + mode + " removes old hunter pursuit state")
 evidence.completed.append("lifecycle")

func on_reentry(_victim: BattleUnit, _source: BattleUnit, _hp: float, _shield: float, mode: String, hook: Dictionary) -> void:
 hook.calls = int(hook.calls) + 1
 if int(hook.calls) != 1: return
 if mode == "clear": game.squads.clear()
 elif mode == "setup": game.squads.setup(game,true)
 elif mode == "defeat": game.end_defeat("猎手回归 · 实际伤害回调")
 elif mode == "victory": game.day_number = 4; game.finish_night()

func actual_economy_refill() -> void:
 await fresh(true,false)
 check(game.scrap == 90, "Economy fixture preserves the actual ninety-part opening wallet")
 var deaths := 0
 for wave in 5:
  var balance: int = game.scrap
  for enemy: BattleUnit in game.enemies.duplicate():
   if is_instance_valid(enemy) and enemy.alive: enemy.hurt(100000.0,null); deaths += 1
  check(game.scrap == balance + 24 and game.wave_rewards.snapshot(wave).paid == 24,
   "Each real standard first-night wave keeps its original24-part ledger")
  await process_frame; game.enemies.clear()
  if wave < 4: game.spawn_night_wave()
 check(deaths == 71 and game.scrap == 210 and game.kill_chain == 0, "Seventy-one genuine first-night deaths yield120 without hero kill-chain reward")
 game.finish_night(); await press(KEY_1); remove_enemies(); game.phase_time = 10000.0
 var crate: Dictionary = {}
 for item: Dictionary in game.world.salvage:
  if not item.collected and item.position.z > 26.0 and game.outpost_walkable(item.position): crate = item; break
 check(not crate.is_empty(), "Actual finite outside crate exists for the production economy")
 if crate.is_empty(): return
 stand(crate.position); camera_at(crate.position); var balance: int = game.scrap
 await press(KEY_F)
 var crate_income: int = game.scrap - balance
 check(crate.collected and crate_income == int(crate.amount) + 3, "Real first F crate pays its original finite single-currency income")
 await press(KEY_F); check(game.scrap == balance + crate_income, "Repeated F cannot pay that crate again")
 await build_gui("barracks",BARRACKS); await build_gui("workshop",WORKSHOP); await train_gui(); await advance(10.001)
 check(game.scrap == 210 + crate_income - 230 and game.squads.squads.size() == 1,
  "Untopped wallet funds real60+60 buildings and110 hunter queue")
 var group: Dictionary = game.squads.squads[0]
 await guard_selected(STATION); await step(12.0); var source: BattleUnit = group.members[1]
 var victim := spawn(source.position + Vector3(0,0,1),"runner",20.0)
 balance = game.scrap; var chain: int = game.kill_chain
 await step(.3)
 check(not victim.alive and game.scrap == balance + 5 and game.kill_chain == chain,
  "True day hunter kill pays only the original5 parts and never hero kill-chain bonus")
 await process_frame; remove_enemies()
 source.hurt(100000.0,null); await process_frame; balance = game.scrap
 check(game.squads.refill_cost(0) == 32 and not game.squads.refill(0).ok and game.scrap == balance,
  "Real dead-hunter slot costs32 and an insufficient wallet cannot refill")
 for item: Dictionary in game.world.salvage:
  if not item.collected and item.position.z > 26.0 and game.outpost_walkable(item.position):
   stand(item.position); camera_at(item.position); await press(KEY_F); break
 balance = game.scrap; await press(KEY_L)
 check(is_instance_valid(group.members[1]) and group.members[1].alive and game.scrap == balance - 32,
  "Actual daylight L creates one replacement hunter for exactly32 parts")
 balance = game.scrap; await press(KEY_L)
 check(game.scrap == balance, "Full group cannot pay a duplicate replacement fee")
 evidence.economy = {"opening":90,"deaths":deaths,"wave_income":120,"crate_income":crate_income,
  "build_train":230,"day_kill":5,"refill":32,"final":game.scrap}
 stand(HOME); camera_at(STATION); await open_army()
 await capture("hunter-actual-day-refill-economy",false)
 await press(KEY_F3)
 evidence.completed.append("economy")

func run() -> void:
 var cases := {"catalog":catalog_queue,"timing":timing_and_damage,"bonus":specialist_bonus,
  "priority":target_priority,"anchor":fixed_anchor_and_gate,"attack":explicit_attack_and_roster,
  "cancel":cancellation_and_walls,"lifecycle":freeze_phase_and_reentry,"economy":actual_economy_refill}
 var selected: Array = cases.keys(); var args := OS.get_cmdline_user_args(); var index := args.find("--case")
 if index >= 0:
  if index + 1 < args.size() and cases.has(args[index + 1]): selected = [args[index + 1]]
  else: check(false,"Hunter case argument must name a known local test case")
 var ready_api := false
 var squad_script: Script = load("res://scripts/outpost_squads.gd")
 for method: Dictionary in squad_script.get_script_method_list():
  if String(method.name) == "hunter_snapshot": ready_api = true
 if not Catalog.TROOP_IDS.has("hunter") or not ready_api:
  check(false,"Actual production hunter catalog and read-only API must exist before executing acceptance")
 evidence.selected_cases = selected
 if failures.is_empty():
  for case_name: String in selected:
   active_stage = case_name
   print("HUNTER_STAGE_BEGIN ",case_name)
   await (cases[case_name] as Callable).call()
   print("HUNTER_STAGE_END ",case_name," checks=",checks," failures=",failures.size())
   if not failures.is_empty(): break
 await close_game()
 check(evidence.completed == selected if failures.is_empty() else true, "Every selected hunter process reaches its actual final stage")
 var folder := ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
 var file := FileAccess.open(folder.path_join("hunters.json"),FileAccess.WRITE)
 check(file != null,"Hunter evidence opens only below local build")
 evidence.checks = checks; evidence.failures = failures
 if file: file.store_string(JSON.stringify(evidence,"\t")); file.close()
 print("NIGHTFALL_HUNTERS_","OK" if failures.is_empty() else "FAILED"," checks=",checks," bounded_true_melee_queue_only_parts")
 finished = true
 quit(0 if failures.is_empty() else 1)
