extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
## Actual production scene, simulation, shield damage, finite quotas and input.
## Precision cases isolate unrelated offense; economy keeps natural clocks/stats.
const RunSession := preload("res://scripts/run_session.gd")
const UnitScript := preload("res://scripts/unit.gd")
const Catalog := preload("res://scripts/outpost_catalog.gd")
const CleanHud := preload("res://scripts/nightfall_clean_hud.gd")
const SEED := 20261006
const STEP := .05
const HOME := Vector3(0, 5, 3.1)
const FIELD := Vector3(0, 0, 32)
const STATION := Vector3(-4, 5, 6)
const VIEWPORTS := [Vector2i(1920,1200),Vector2i(1920,1080),Vector2i(1440,900)]
const ROOT_OBSERVER := """extends 'res://scripts/nightfall.gd'
var support_hook: Callable
var hook_armed := false
var hook_origin := Vector3.INF
func can_attack_line(origin: Vector3, destination: Vector3) -> bool:
\tvar result := super.can_attack_line(origin,destination)
\tif hook_armed and origin.distance_to(hook_origin) < .00001:
\t\thook_armed = false
\t\tsupport_hook.call()
\treturn result
"""
const HUD_OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var drawn_labels: Array[Dictionary] = []
var drawn_rects: Array[Rect2] = []
var drawer := false
func _draw() -> void:
\tdrawn_labels.clear(); drawn_rects.clear(); drawer = false
\tsuper._draw()
func box(rect: Rect2, fill: Color = Color(.022,.035,.045,.88), outline: Color = Color('435455')) -> void:
\tdrawn_rects.append(rect)
\tif rect == Rect2(24,112,540,622): drawer = true
\tif rect == Rect2(428,692,112,30): drawer = false
\tsuper.box(rect,fill,outline)
func label(value: String, point: Vector2, size_px: int, color: Color = Color('e7e1d3'), latin: bool = false) -> void:
\tvar actual: Font = display_font if latin else font
\tdrawn_labels.append({'text':value,'point':point,'width':actual.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x,'ascent':actual.get_ascent(size_px),'descent':actual.get_descent(size_px),'font_size':size_px,'drawer':drawer})
\tsuper.label(value,point,size_px,color,latin)
"""
var game: Node3D
var checks := 0
var failures: Array[String] = []
var render_test := false
var output_dir := "res://build/warders"
var active_stage := "initialization"
var finished := false
var hurt_events: Array[Dictionary] = []
var evidence := {"seed":SEED,"precision_fixture":"unrelated offense disabled, extended phase, stationary precision enemies; not difficulty proof",
 "captures":[],"completed":[],"combat":{},"economy":{}}

func _initialize() -> void:
 var args := OS.get_cmdline_user_args()
 render_test = "--render-test" in args
 var index := args.find("--output-dir")
 if index >= 0 and index + 1 < args.size():
  var candidate := ProjectSettings.globalize_path(args[index+1]).simplify_path()
  var allowed := ProjectSettings.globalize_path("res://build").simplify_path()
  if candidate.begins_with(allowed+"/"): output_dir = candidate
  else: check(false,"Warder artifacts are restricted to this project's build directory")
 root.size = VIEWPORTS[0]; root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT; root.content_scale_size = VIEWPORTS[0]
 if DisplayServer.get_name() != "headless":
  DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
  root.position = Vector2i(10000,10000); root.hide()
 create_timer(300.0,true,false,true).timeout.connect(watchdog)
 call_deferred("run")

func watchdog() -> void:
 if finished: return
 check(false,"Warder acceptance stalled in "+active_stage)
 await close_game()
 finished = true; quit(1)

func check(condition: bool, message: String) -> void:
 checks += 1
 if condition: return
 failures.append(message)
 if failures.size() <= 30: push_error(message)

func press(code: int) -> void:
 var event := InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = true
 root.push_input(event,true); event.pressed = false; root.push_input(event,true)
 await process_frame

func mouse(point: Vector2, button: int = 0) -> void:
 var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point
 root.push_input(motion,true); await process_frame
 if button == 0: return
 var event := InputEventMouseButton.new(); event.position = point; event.global_position = point; event.button_index = button
 event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
 event.pressed = true; root.push_input(event,true); await process_frame
 event.pressed = false; event.button_mask = 0; root.push_input(event,true); await process_frame

func click_ui(rect: Rect2) -> void:
 await mouse(rect.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900),MOUSE_BUTTON_LEFT)

func planar(a: Vector3,b: Vector3) -> float:
 return Vector2(a.x-b.x,a.z-b.z).length()

func on_ground(point: Vector3) -> Vector3:
 point.y = game.outpost_height(point); return point

func stand(point: Vector3) -> void:
 point = on_ground(point); game.hero.position = point; game.move_goal = point; game.hero_path.clear()
 game.hero_keyboard_active = false; game.hero.moving = false; game.hero.set_locomotion_velocity(Vector3.ZERO)

func camera_at(point: Vector3) -> void:
 game.camera.size = 38.0; game.camera.position = point+Vector3(0,25,29)
 game.camera.look_at(point); game.camera_follow = game.camera.position

func aim_at(point: Vector3) -> void:
 camera_at(point); await mouse(game.camera.unproject_position(point)); game._process(0.0)

func advance(seconds: float) -> void:
 for frame in ceili(seconds/STEP):
  game.simulate(minf(STEP,seconds-float(frame)*STEP))
  if frame % 80 == 79: await process_frame

func clear_enemies() -> void:
 game.clear_warders(); game.clear_summoners(); game.clear_lobbers(); game.clear_focus()
 game.cancel_hero_attack()
 for value: Variant in game.enemies:
  if is_instance_valid(value): value.queue_free()
 game.enemies.clear()

func close_game() -> void:
 if not is_instance_valid(game): return
 var tokens: Array[int] = []
 for controller: Node3D in game.warders:
  if is_instance_valid(controller): tokens.append(controller.get_instance_id())
 await game.prepare_shutdown()
 check(game.warders.is_empty() and game.warder_warning_snapshot().is_empty(),"Actual shutdown clears shield controllers and warnings")
 if current_scene == game: current_scene = null
 game.queue_free(); game = null
 for _frame in 4: await process_frame
 await create_timer(.2,true,false,true).timeout
 for token: int in tokens: check(not is_instance_id_valid(token),"Actual shutdown releases every old shield controller")

func fresh(night: int = 2, precision: bool = true, keep_wave: bool = false) -> void:
 await close_game()
 check(RunSession.queue_request(self,SEED,"siege"),"Actual standard session accepts the fixed test seed")
 var observer := GDScript.new(); observer.source_code = ROOT_OBSERVER
 check(observer.reload() == OK,"Fixed root observer only forwards actual line checks plus explicit reentry hooks")
 # Replace the fixed scene's root script before instantiation. Calling
 # set_script on an already instantiated root would orphan the original
 # script's eager districts/day_contracts nodes while constructing new ones.
 var packed: PackedScene = load("res://scenes/nightfall.tscn").duplicate()
 var bundled: Dictionary = packed.get("_bundled").duplicate(true)
 var replaced := 0
 for variant_index in bundled.variants.size():
  var value: Variant = bundled.variants[variant_index]
  if value is Script and value.resource_path == "res://scripts/nightfall.gd":
   bundled.variants[variant_index] = observer; replaced += 1
 check(replaced == 1,"Fixed production scene replaces only its one root script before constructing real controllers")
 packed.set("_bundled",bundled); game = packed.instantiate()
 root.add_child(game); current_scene = game
 for _frame in 5: await process_frame
 game.set_process(false); game.world.set_process(false)
 var hud_script := GDScript.new(); hud_script.source_code = HUD_OBSERVER
 check(hud_script.reload() == OK,"Fixed HUD observer forwards actual production drawing and input")
 var old: Control = game.hud; var layer: Node = old.get_parent(); layer.remove_child(old); old.queue_free()
 var observed: Control = hud_script.new(); observed.game = game; game.hud = observed; layer.add_child(observed)
 observed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 await press(KEY_1)
 check(game.phase == "night" and game.run_mode == "siege" and game.run.seed_value == SEED,"Real opening core input enters the intended production run")
 if night != 1: game.day_number = night; game.start_night()
 if not keep_wave: clear_enemies(); game.wave_index = game.WAVES_PER_NIGHT
 if precision:
  game.phase_time = 10000.0; game.scrap = 5000
  game.hero.attack_timer = 100000.0; game.pulse_timer = 100000.0; game.spawn_timer = 100000.0
  game.gate_trap_charges = 0; game.show_gate_trap_charges()
  for pad: Dictionary in game.world.tower_pads: pad.cooldown = 100000.0
 stand(HOME); hurt_events.clear()

func record_hurt(victim: BattleUnit,source: BattleUnit,hp_loss: float,shield_loss: float) -> void:
 hurt_events.append({"victim":victim.get_instance_id(),"source":source.get_instance_id() if is_instance_valid(source) else -1,"hp":hp_loss,"shield":shield_loss})

func spawn(point: Vector3 = FIELD,role: String = "basic",missing: float = 0.0,stationary: bool = true) -> BattleUnit:
 var enemy: BattleUnit = game.spawn_creature(true,role); enemy.position = on_ground(point)
 if stationary: enemy.speed = 0.0; enemy.attack_timer = 100000.0
 if missing > 0: enemy.hurt(missing,null)
 enemy.damage_confirmed.connect(record_hurt)
 return enemy

func controller_for(source: BattleUnit) -> Node3D:
 for controller: Node3D in game.warders:
  if is_instance_valid(controller) and controller.get("host") == source: return controller
 return null

func pack(point: Vector3 = FIELD) -> Dictionary:
 var source := spawn(point,"warder"); var target := spawn(point+Vector3(2,0,0),"basic",60.0)
 var controller := controller_for(source)
 check(controller != null and source.get_meta("threat","") == "warder","Explicit production spawn attaches a real shield controller")
 return {"source":source,"target":target,"controller":controller}

func begin(controller: Node3D,target: BattleUnit) -> void:
 game.simulate(.001)
 var state: Dictionary = controller.snapshot()
 check(state.phase == "windup" and state.target == target and is_equal_approx(float(state.remaining),1.0),"Actual simulate starts the complete one-second cast on the selected actual enemy")
 check(game.warder_warning_snapshot().size() >= 1,"Only a real live cast produces the world warning snapshot")

func state() -> Dictionary:
 var controllers: Array = []; var enemies: Array = []
 for controller: Node3D in game.warders:
  if is_instance_valid(controller): controllers.append(controller.snapshot())
 for enemy: Variant in game.enemies:
  if is_instance_valid(enemy): enemies.append([enemy.get_instance_id(),enemy.position,enemy.hp,enemy.shield,enemy.shield_time,enemy.attack_timer,enemy.attack_windup])
 return {"controllers":controllers,"enemies":enemies,"parts":game.scrap,"phase":game.phase,"time":game.phase_time,
  "rng":game.run.rng.state,"spawn_rng":game.spawn_rng.state,"focus":game.focus_time,"warnings":game.warder_warning_snapshot()}

func capture(label: String,night: bool = true) -> void:
 if not render_test: return
 check(DisplayServer.get_name() != "headless","Warder PNGs require an actual graphical backend")
 if DisplayServer.get_name() == "headless": return
 var before := state()
 for viewport: Vector2i in VIEWPORTS:
  root.size = viewport; root.content_scale_size = viewport
  game.world.set_night(night); game.world.night_mix = 1.0 if night else 0.0; game.world.apply_lighting(); game.hud.queue_redraw()
  for _frame in 5: await process_frame; await RenderingServer.frame_post_draw
  var picture: Image = root.get_texture().get_image()
  check(picture.get_size() == viewport and Vector2i(game.hud.get_viewport_rect().size) == viewport,"Actual shield PNG and HUD content match "+str(viewport))
  check(not game.hud.drawn_rects.is_empty(),"Actual current HUD redraw produces observed geometry")
  for row: Dictionary in game.hud.drawn_labels:
   if bool(row.drawer): check(row.point.x >= 36 and row.point.x+float(row.width) <= 544 and row.point.y+float(row.descent) < 692,"Actual shield defense drawer text remains within its column and above close")
   if String(row.text).contains("织壳") or String(row.text).contains("护盾"):
    check(row.point.x >= 0 and row.point.x+float(row.width) <= 1440 and row.point.y >= 0 and row.point.y <= 900,"Actual new Chinese shield labels stay inside the scaled viewport")
  var folder := ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
  var name := "%s-%dx%d" % [label,viewport.x,viewport.y]
  check(picture.save_png(folder.path_join(name+".png")) == OK,"Real warder screenshots stay in local build")
  evidence.captures.append(name)
 check(state() == before,"Three-viewport capture cannot advance shielding, spend, move or consume RNG")
 root.size = VIEWPORTS[0]; root.content_scale_size = VIEWPORTS[0]
 for _frame in 3: await process_frame

func catalog_and_budget() -> void:
 var receipts: Array = []
 for night in [1,2,3,4]:
  await fresh(night,true,true)
  var balance: int = game.scrap
  for wave in 5:
   var entry: Dictionary = game.night_plan[wave]
   var id: int = game.active_wave_reward_id
   var actual_warders := 0; var actual_roles: Array[String] = []
   for enemy: BattleUnit in game.enemies:
    if not is_instance_valid(enemy) or not enemy.alive: continue
    if enemy.get_meta("siege_boss",false): continue
    var role := String(enemy.get_meta("threat","")); actual_roles.append("basic" if role == "stalker" else role)
    if role == "warder":
     actual_warders += 1
     check(is_equal_approx(enemy.max_hp,(155.0+night*28)*.82) and enemy.hp == enemy.max_hp
      and enemy.armor == 0.0 and enemy.speed == 3.0 and enemy.damage == 12.0
      and enemy.attack_range == 1.6 and enemy.attack_interval == 1.4,"Actual planned shield source has its declared fragile melee values")
     var controller := controller_for(enemy)
     check(controller != null and controller.snapshot().casts == 0 and controller.snapshot().max_casts == 3,"Actual saved-wave shield source begins with three lifetime successes")
   check(actual_roles == entry.roles and actual_warders == int(entry.warder_count),"Actual spawn order/roles and shield sources match the saved preview")
   check(int(entry.shield_cast_cap) == actual_warders*3 and int(entry.reinforcement_cap) == (2 if night >= 3 and wave == 2 else 0),"Shield quotas remain distinct from unchanged future reinforcement ceilings")
   var ledger: Dictionary = game.wave_rewards.snapshot(id)
   check(ledger.count == entry.count and ledger.budget == 24,"Actual unchanged initial actors register against the original twenty-four-part ledger")
   var before: int = game.scrap
   for value: Variant in game.enemies.duplicate():
    if is_instance_valid(value) and value.alive: value.hurt(100000.0,null)
   ledger = game.wave_rewards.snapshot(id)
   check(ledger.cleared and ledger.paid == 24 and game.scrap == before+24,"Every real source and original wave death settles exactly twenty-four once")
   receipts.append({"night":night,"wave":wave+1,"warders":actual_warders,"count":ledger.count,"paid":ledger.paid})
   await process_frame; game.enemies.clear()
   if wave < 4: game.spawn_night_wave()
  check(game.scrap == balance+120,"Five natural production ledgers retain one-hundred-twenty base parts")
 evidence.combat.ledgers = receipts; evidence.completed.append("catalog")

func selection_rules() -> void:
 await fresh(); var source := spawn(FIELD,"warder"); var controller := controller_for(source)
 var near := spawn(FIELD+Vector3(1,0,0),"basic",40.0)
 var low := spawn(FIELD+Vector3(3,0,0),"basic",100.0)
 begin(controller,low); check(near.shield == 0.0,"Nearer healthier target does not displace lowest health ratio")
 controller.clear(); controller.setup(game,source); low.hurt(100000.0,null); await process_frame
 var equal_far := spawn(FIELD+Vector3(3,0,0),"basic",40.0)
 begin(controller,near); check(equal_far.shield == 0.0,"Equal health ratios choose the genuinely nearer target")
 await fresh(); source = spawn(FIELD,"warder"); controller = controller_for(source)
 var threshold := spawn(FIELD+Vector3(2,0,0),"basic",12.0)
 var too_healthy := spawn(FIELD+Vector3(1,0,0),"basic",11.0)
 begin(controller,threshold); await advance(1.001)
 check(threshold.shield == 32.0 and too_healthy.shield == 0.0,"Twelve missing health is eligible; eleven is not")
 await fresh(); source = spawn(FIELD,"warder"); controller = controller_for(source); source.hurt(50.0,null)
 var other_source := spawn(FIELD+Vector3(1,0,0),"warder",100.0)
 var boss := spawn(FIELD+Vector3(2,0,0),"breaker",100.0); boss.set_meta("siege_boss",true)
 var shielded := spawn(FIELD+Vector3(1,0,1),"basic",120.0); shielded.shield = 7.0; shielded.shield_time = 20.0
 var absent := spawn(FIELD+Vector3(2,0,1),"basic",120.0); game.enemies.erase(absent)
 var friendly := UnitScript.new() as BattleUnit; game.add_child(friendly); friendly.setup("minion",0)
 friendly.position = on_ground(FIELD+Vector3(1,0,-1)); friendly.hurt(80.0,null); game.enemies.append(friendly)
 var valid := spawn(FIELD+Vector3(3,0,0),"basic",20.0)
 begin(controller,valid); await advance(1.001)
 check(valid.shield == 32.0 and source.shield == 0.0 and other_source.shield == 0.0
  and boss.shield == 0.0 and absent.shield == 0.0 and friendly.shield == 0.0
  and shielded.shield == 7.0,"Source/other sources/boss/non-roster/friendly/already-shielded targets are genuinely excluded")
 check(game.beacon_hp == game.BEACON_MAX,"Shield support cannot change core health")
 camera_at(FIELD); await capture("warder-real-target-exclusions")
 evidence.completed.append("selection")

func full_cast_damage_and_expiry() -> void:
 await fresh(); var p := pack(); var controller: Node3D = p.controller; var target: BattleUnit = p.target
 var hp: float = target.hp; var parts: int = game.scrap; begin(controller,target)
 var frozen := state(); for _read in 12: controller.snapshot(); game.warder_warning_snapshot()
 check(state() == frozen,"Warning and state reads cannot advance or reserve a shield")
 await advance(.99); check(target.shield == 0.0 and controller.snapshot().casts == 0,"Full one-second preparation is required before shielding")
 camera_at(FIELD); await capture("warder-live-one-second-windup")
 game.simulate(.011)
 check(target.shield == 32.0 and is_equal_approx(target.shield_time,4.0)
  and target.hp == hp and game.scrap == parts,"Real completed cast grants thirty-two for four seconds, without healing or spending")
 check(controller.snapshot().casts == 1 and is_equal_approx(float(controller.snapshot().cooldown),6.0),"Successful cast debits one quota and starts six-second cooldown")
 hurt_events.clear(); target.hurt(20.0,game.hero)
 check(target.hp == hp and target.shield == 12.0 and hurt_events.size() == 1
  and hurt_events[0].shield == 20.0 and hurt_events[0].hp == 0.0,"Real hurt absorbs twenty from granted shield before health")
 target.hurt(18.0,game.hero)
 check(target.shield == 0.0 and is_equal_approx(target.hp,hp-6.0) and hurt_events.back().shield == 12.0
  and hurt_events.back().hp == 6.0,"Next real hurt consumes the final twelve and deals six health damage")
 await advance(5.99); check(controller.snapshot().casts == 1,"Target without shield still cannot bypass six seconds")
 game.simulate(.011); check(controller.snapshot().phase == "windup" and is_equal_approx(float(controller.snapshot().remaining),1.0),"Cooldown expiry starts a new full windup")
 await advance(1.001); check(target.shield == 32.0,"Second natural successful preparation grants a fresh finite shield")
 var lifetime: float = target.shield_time; camera_at(FIELD); await capture("warder-live-thirty-two-shield")
 await advance(lifetime-.001); check(target.shield == 32.0 and target.shield_time > 0.0,"Granted shield persists until its actual remaining lifespan")
 game.simulate(.002); check(target.shield == 0.0 and target.shield_time == 0.0,"Actual target tick expires the shield without source-side refreshing")
 evidence.combat.damage = hurt_events.duplicate(true); evidence.completed.append("timing")

func finite_quota_and_rebuild() -> void:
 await fresh(); var p := pack(); var controller: Node3D = p.controller; var source: BattleUnit = p.source; var target: BattleUnit = p.target
 begin(controller,target); await advance(1.001)
 await advance(2.0); var saved: float = controller.snapshot().cooldown
 controller.clear(); controller.setup(game,source)
 check(controller.snapshot().casts == 1 and is_equal_approx(float(controller.snapshot().cooldown),saved)
  and int(source.get_meta("warder_casts",-1)) == 1,"Same real source clear/setup preserves successful quota and remaining cooldown")
 await advance(saved+.001); check(controller.snapshot().phase == "windup","Same-source rebuild waits the saved cooldown before full new preparation")
 await advance(1.001); check(controller.snapshot().casts == 2,"Second real success remains second across rebuilding")
 await advance(6.001); await advance(1.001)
 check(controller.snapshot().casts == 3 and controller.snapshot().phase == "exhausted"
  and not bool(source.get_meta("warder_active",true)),"Third real success naturally exhausts this source for its whole lifetime")
 controller.clear(); controller.setup(game,source); await advance(15.0)
 check(controller.snapshot().casts == 3 and target.shield == 0.0 and controller.snapshot().phase == "exhausted","Spent same-source rebuild and twenty further seconds cannot replenish or grant a fourth shield")
 camera_at(FIELD); await capture("warder-three-real-successes-exhausted")
 evidence.completed.append("quota")

func geometry_rules() -> void:
 var results: Array = []
 for radius in [4.79,4.8,4.81]:
  await fresh(); var source := spawn(FIELD,"warder"); var target := spawn(FIELD+Vector3(radius,0,0),"basic",50.0)
  game.simulate(.001); var controller := controller_for(source)
  check((controller.snapshot().target == target and controller.snapshot().phase == "windup") if radius <= 4.8 else controller.snapshot().phase != "windup","Real planar cast boundary enforces "+str(radius))
  await advance(1.001); check(target.shield == (32.0 if radius <= 4.8 else 0.0),"Actual shield completion respects "+str(radius)+" meters")
  results.append({"distance":radius,"shield":target.shield})
 for scenario in ["source","target","difference"]:
  for offset in [.89,.9,.91]:
   await fresh(); var p := pack(); var source: BattleUnit = p.source; var target: BattleUnit = p.target
   if scenario == "source": source.position.y += offset
   elif scenario == "target": target.position.y += offset
   else: source.position.y += offset*.5; target.position.y -= offset*.5
   # Ordinary creature movement snaps its actual feet to terrain, including
   # speed-zero precision actors. Artificial airborne boundary inputs must be
   # checked by the attached real controller without a movement tick erasing
   # them. Normal slope/wall/building cases below use the full root simulate.
   var source_offset: float = source.position.y-game.outpost_height(source.position)
   var target_offset: float = target.position.y-game.outpost_height(target.position)
   p.controller.advance(.001); p.controller.advance(1.001)
   check(is_equal_approx(source.position.y-game.outpost_height(source.position),source_offset)
    and is_equal_approx(target.position.y-game.outpost_height(target.position),target_offset),"Actual controller boundary precision preserves both supplied artificial ground offsets")
   check(target.shield == (32.0 if offset <= .9 else 0.0),"Attached real controller "+scenario+" relative-ground offset boundary enforces "+str(offset))
   results.append({"case":scenario,"input_offset":offset,"source_offset":source_offset,"target_offset":target_offset,
    "shield":target.shield,"scope":"direct attached production controller boundary; artificial offsets, without root movement tick"})
 await fresh(); var p := pack(Vector3(0,0,18)); var target: BattleUnit = p.target
 target.position = on_ground(Vector3(0,0,22))
 check(absf(p.source.position.y-target.position.y) > .9,"Natural four-meter south slope pair has world-height difference larger than offset cap")
 begin(p.controller,target); await advance(1.001)
 check(target.shield == 32.0,"Natural ground-following slope remains supportable despite different world heights")
 camera_at(Vector3(0,0,20)); await capture("warder-natural-slope-shield")
 await fresh(); p = pack(Vector3(12,0,8)); target = p.target
 target.position = on_ground(Vector3(16,0,8)); game.simulate(.001); await advance(1.001)
 check(target.shield == 0.0,"Actual east castle wall prevents support across otherwise close world points")
 await fresh(); p = pack(Vector3(-8.5,0,6)); target = p.target; target.position = on_ground(Vector3(-4.5,0,6))
 check(game.build_structure_at(Vector3(-6.5,5,6),"workshop"),"Paid actual workshop creates a live construction-grid obstruction")
 game.simulate(.001); await advance(1.001); check(target.shield == 0.0,"Actual live workshop footprint blocks a four-meter support segment")
 camera_at(Vector3(-6.5,5,6)); await capture("warder-live-workshop-blocks-support")
 var plot_id := -1
 for index in game.districts.plots.size():
  var plot: Dictionary = game.districts.plots[index]
  if plot.kind == "workshop" and int(plot.level) > 0: plot_id = index
 check(plot_id >= 0,"Blocking workshop is found by its actual live production plot")
 game.districts.damage(plot_id,100000.0)
 game.simulate(.001); await advance(1.001); check(target.shield == 32.0,"Real building destruction frees the same support segment")
 evidence.combat.geometry = results; evidence.completed.append("geometry")

func competing_sources_and_source_death() -> void:
 await fresh(); var first := spawn(FIELD,"warder"); var second := spawn(FIELD+Vector3(0,0,1),"warder")
 var target := spawn(FIELD+Vector3(2,0,0),"basic",60.0); var a := controller_for(first); var b := controller_for(second)
 game.simulate(.001); check(a.snapshot().phase == "windup" and b.snapshot().phase == "windup","Two actual sources may begin preparation toward one unshielded target")
 await advance(.99); game.simulate(.011)
 check(int(a.snapshot().casts)+int(b.snapshot().casts) == 1 and target.shield == 32.0
  and is_equal_approx(target.shield_time,4.0),"Actual competing completion grants exactly one shield with its full four seconds, without stacking or refreshing")
 var remaining: float = target.shield_time; var hp: float = target.hp
 first.hurt(100000.0,null); second.hurt(100000.0,null); await process_frame; game.simulate(.01)
 check(target.alive and target.hp == hp and target.shield == 32.0 and target.shield_time < remaining,"Real source death/releases leave the already-granted target shield on its original clock")
 var lifetime: float = target.shield_time; camera_at(target.position); await capture("warder-shield-survives-both-source-deaths")
 await advance(lifetime+.001); check(target.shield == 0.0,"Granted shield expires naturally after both original sources were released")
 evidence.completed.append("contention")

func cancellation_and_control() -> void:
 for action in ["target_dead","target_release","source_dead","source_release","target_roster","range","shielded"]:
  await fresh(); var p := pack(); var source: BattleUnit = p.source; var target: BattleUnit = p.target; var controller: Node3D = p.controller
  begin(controller,target)
  match action:
   "target_dead": target.hurt(100000.0,null)
   "target_release": target.queue_free()
   "source_dead": source.hurt(100000.0,null)
   "source_release": source.queue_free()
   "target_roster": game.enemies.erase(target)
   "range": target.position = on_ground(FIELD+Vector3(4.81,0,0))
   "shielded": target.shield = 9.0; target.shield_time = 10.0
  game.simulate(.02)
  check(int(source.get_meta("warder_casts",0)) == 0 if is_instance_valid(source) else true,"Cancellation "+action+" cannot consume an unfinished success")
  check(target.shield == (9.0 if action == "shielded" else 0.0) if is_instance_valid(target) else true,"Cancellation "+action+" cannot produce or overwrite a shield")
  check(game.warder_warning_snapshot().is_empty(),"Actual "+action+" removes the cancelled world warning in the same frame")
  await process_frame; await advance(1.1)
 for obstruction in ["wall","building"]:
  await fresh()
  var p := pack(Vector3(12,0,8) if obstruction == "wall" else Vector3(-8.5,0,6))
  var source: BattleUnit = p.source; var target: BattleUnit = p.target; var controller: Node3D = p.controller
  target.position = on_ground(Vector3(11,0,8) if obstruction == "wall" else Vector3(-4.5,0,6))
  begin(controller,target); await advance(.3)
  check(controller.snapshot().phase == "windup" and target.shield == 0.0,"Actual "+obstruction+" cancellation begins with an unfinished real cast")
  if obstruction == "wall": target.position = on_ground(Vector3(16,0,8))
  else: check(game.build_structure_at(Vector3(-6.5,5,6),"workshop"),"Actual paid live workshop is built during the incomplete shield cast")
  game.simulate(.02)
  var cancelled: Dictionary = controller.snapshot()
  check(cancelled.phase != "windup" and cancelled.cancel_reason in ["line_blocked","path_blocked"]
   and cancelled.cancelled == 1 and cancelled.casts == 0 and target.shield == 0.0
   and game.warder_warning_snapshot().is_empty(),"New real "+obstruction+" obstruction cancels in the same frame without granting shield or spending quota")
  await advance(1.1)
  check(target.shield == 0.0 and int(source.get_meta("warder_casts",0)) == 0,"Persisting actual "+obstruction+" prevents the old preparation from completing later")
 await fresh(); var p := pack(Vector3(0,0,24.5)); var source: BattleUnit = p.source; var target: BattleUnit = p.target; var controller: Node3D = p.controller
 target.position = on_ground(Vector3(0,0,26.5))
 var tower: Dictionary = game.world.tower_pads[0]; stand(tower.position+Vector3(0,0,-2)); await press(KEY_F); await press(KEY_K)
 check(tower.level == 2 and game.specializations.branch(tower) == "control","Real F/K input pays for existing tower control specialization")
 stand(HOME); begin(controller,target); await aim_at(source.position); await press(KEY_C)
 check(game.focus_target == source and game.focus_time > 0.0,"Actual legal C input focuses the shielding source")
 tower.cooldown = 0.0; game.simulate(.02)
 check(controller.snapshot().phase != "windup" and controller.snapshot().cancel_reason == "source_controlled"
  and target.shield == 0.0 and source.get_meta("warder_casts",0) == 0
  and game.warder_warning_snapshot().is_empty(),"Actual control tower hit cancels the unfinished cast in this same production frame")
 camera_at(Vector3(0,0,24)); await capture("warder-real-c-control-same-frame-cancel")
 evidence.completed.append("cancel")

func freeze_lifecycle_and_reentry() -> void:
 await fresh(); var p := pack(); var controller: Node3D = p.controller; var target: BattleUnit = p.target
 begin(controller,target); await advance(.3); await press(KEY_ESCAPE); var before := state()
 game.simulate(10.0); controller.advance(10.0); check(state() == before,"Actual pause freezes support progress, quota, target shield and clocks")
 camera_at(FIELD); await capture("warder-paused-real-windup"); await press(KEY_ESCAPE)
 game.run.grant("织壳验收免费冻结夹具"); await press(KEY_V); before = state()
 game.simulate(10.0); controller.advance(10.0); check(state() == before,"Real V card choice freezes support and does not refresh quota")
 await press(KEY_1); await advance(.701); check(target.shield == 32.0,"Unpaused actual partial windup resumes remaining time and completes once")
 var source: BattleUnit = p.source; var quota: int = int(source.get_meta("warder_casts",0)); var cooldown: float = source.get_meta("warder_cooldown",0.0)
 TransitionFixture.finish_for_fixture(game); await press(KEY_1); check(game.phase == "day" and game.warders.is_empty(),"Actual dawn clears controllers and enters real day")
 check(int(source.get_meta("warder_casts",0)) == quota and is_equal_approx(float(source.get_meta("warder_cooldown",0.0)),cooldown) if is_instance_valid(source) else true,"Dawn cannot reset successful lifetime quota or saved cooldown on a retained source")
 for action in ["clear","setup","target_release","victory","defeat","shutdown"]:
  await fresh(4); p = pack(); source = p.source; target = p.target; controller = p.controller
  begin(controller,target); var controller_token := controller.get_instance_id()
  var replacement: BattleUnit = spawn(FIELD+Vector3(0,0,-1),"warder") if action == "setup" else null
  if action == "shutdown":
   await game.prepare_shutdown()
  else:
   game.hook_origin = source.position
   game.support_hook = func() -> void:
    if action == "clear": controller.clear()
    elif action == "setup": controller.setup(game,replacement)
    elif action == "target_release": target.queue_free()
    elif action == "victory": TransitionFixture.finish_for_fixture(game)
    elif action == "defeat": game.end_defeat("织壳同步结算验收")
   game.hook_armed = true; game.simulate(1.001)
   check(not game.hook_armed,"Actual support-line recheck executes the armed "+action+" production callback")
  check(int(source.get_meta("warder_casts",0)) == 0 and target.shield == 0.0 if is_instance_valid(source) and is_instance_valid(target) else true,"Synchronous "+action+" callback cannot let the retired generation debit quota or grant shield")
  if action == "setup": check(controller.host == replacement and controller.snapshot().casts == 0,"Reentrant setup preserves the new actual source with a fresh unused quota")
  if action in ["victory","defeat","shutdown"]:
   check(game.warders.is_empty() and game.warder_warning_snapshot().is_empty(),"Actual "+action+" clears every controller and warning")
   await process_frame; check(not is_instance_id_valid(controller_token),"Actual "+action+" releases its real controller instance")
 evidence.completed.append("freeze")

func trained_counter(kind: String, one: bool = true) -> Dictionary:
 check(game.build_structure_at(Vector3(7,5,-8.5),"barracks"),"Actual paid barracks supports real counter training")
 if kind == "hunter": check(game.build_structure_at(Vector3(-7.5,5,-8.5),"workshop"),"Actual paid workshop unlocks hunters")
 if kind == "ranged": await press(KEY_I)
 else:
  await press(KEY_F3); await click_ui(game.hud.details_tab_rect(2)); await click_ui(game.hud.troop_page_rect(1)); await click_ui(game.hud.troop_page_rect(1))
  await click_ui(game.hud.training_kind_rect(1)); await press(KEY_F3)
 await advance(10.01 if kind == "hunter" else 8.01)
 check(game.squads.squads.size() == 1 and game.squads.squads[0].kind == kind,"Real production queue creates three actual "+kind+" members")
 var group: Dictionary = game.squads.squads[0]
 await press(KEY_TAB); await aim_at(STATION); await press(KEY_O); await advance(12.0)
 check(group.order == "guard" and planar(group.destination,STATION) < .17
  and planar(group.members[1].position,STATION) < .17,"Actual counter guard input records the intended destination and the middle member really reaches it")
 for member: BattleUnit in group.members: check(not member.moving,"Real counter members finish their guard route")
 if one:
  group.members[0].hurt(100000.0,null); group.members[2].hurt(100000.0,null); await process_frame
  check(group.members[0] == null and group.members[2] == null,"Single-counter precision uses genuinely removed casualties")
 return group

func active_and_spent_counterplay() -> void:
 for kind in ["ranged","hunter"]:
  for spent in [false,true]:
   await fresh(); var group := await trained_counter(kind); var soldier: BattleUnit = group.members[1]
   var p := pack(FIELD); var source: BattleUnit = p.source; var target: BattleUnit = p.target; var controller: Node3D = p.controller
   if spent:
    begin(controller,target); await advance(1.001); await advance(6.001); await advance(1.001); await advance(6.001); await advance(1.001)
    check(controller.snapshot().casts == 3 and not bool(source.get_meta("warder_active",true)),"Countercase consumes three real successes before declaring source ordinary")
   target.hurt(100000.0,null); await process_frame
   source.position = on_ground(STATION+Vector3(2,0,0)); var ordinary := spawn(STATION+Vector3(1,0,0),"basic")
   var breaker := spawn(STATION+Vector3(1.5,0,0),"breaker") if kind == "ranged" else null
   soldier.attack_timer = 0.0; hurt_events.clear(); var expected: BattleUnit = source if not spent else (breaker if kind == "ranged" else ordinary)
   var hp: float = expected.hp; game.simulate(.001)
   check(soldier.attack_queued and soldier.target == expected,"Actual "+kind+" priority selects "+("active shield source" if not spent else "normal non-source threat after real exhaustion"))
   await advance(.221 if kind == "hunter" else .261)
   var expected_damage := 30.0 if kind == "hunter" and not spent else (12.0 if kind == "hunter" else 16.0)
   check(is_equal_approx(expected.hp,hp-expected_damage),"Actual counter completes its natural windup and declared source-specific damage")
   if spent:
    soldier.attack_timer = 0.0; game.clear_focus(); await aim_at(source.position); await press(KEY_C); game.simulate(.001)
    check(soldier.target == source,"Actual C can still choose an exhausted source inside legal range")
    hp = source.hp; await advance(.221 if kind == "hunter" else .261)
    check(is_equal_approx(source.hp,hp-(12.0 if kind == "hunter" else 16.0)),"Actual spent source receives ordinary base damage without the active-source bonus")
   camera_at(STATION); await capture("warder-"+kind+("-exhausted-real-priority" if spent else "-active-real-priority"))
 evidence.completed.append("counter")

func natural_budget_counterplay() -> void:
 await fresh(1,false,true)
 check(game.scrap == 90 and game.phase_time == 105.0 and game.tower_count() == 2,"Natural defense starts with the untouched ninety-part opening and two original towers")
 camera_at(Vector3(0,5,10)); await mouse(game.camera.unproject_position(Vector3(0,5,10)),MOUSE_BUTTON_RIGHT)
 var first_deaths := 0
 var first_night_elapsed := 0.0
 var first_night_cutoff: Dictionary = {}
 # Bound actual residual combat; the production assault deadline is unchanged.
 for frame in ceili(240.0 / .1):
  if game.phase != "night": break
  game.aim = game.hero.position+Vector3(0,0,8)
  if game.gate_pressure() > 0: game.cast(0)
  if game.hero.hp < game.hero.max_hp*.6: game.cast(1); game.cast(4)
  if game.gate_pressure() >= 6: game.cast(3)
  game.simulate(.1)
  first_night_elapsed += .1
  if first_night_cutoff.is_empty() and first_night_elapsed >= game.NIGHT_LENGTH:
   first_night_cutoff = TransitionFixture.deadline_evidence(game, first_night_elapsed)
  if frame % 100 == 99: await process_frame
 TransitionFixture.record_natural_receipt(game, evidence, "opening", first_night_elapsed, first_night_cutoff)
 first_deaths = game.kills
 check(game.phase == "draft" and game.hero.alive and game.beacon_hp > 0.0,"Natural first-night defense survives using actual hero skills, two opening towers and original enemy stats")
 if game.phase != "draft": return
 await press(KEY_1); var starting_parts: int = game.scrap
 check(game.phase == "day" and game.phase_time == 90.0 and starting_parts >= 95,"Natural first-night earnings afford one existing tower upgrade and control specialization in the actual ninety-second day")
 var tower: Dictionary = game.world.tower_pads[1]
 camera_at(tower.position); var destination: Vector3 = tower.position+Vector3(2,0,0)
 await mouse(game.camera.unproject_position(destination),MOUSE_BUTTON_RIGHT); await advance(4.0)
 check(planar(game.hero.position,destination) < .25,"Real right-click routes the hero to the original tower's interaction edge")
 await press(KEY_F); await press(KEY_K)
 check(tower.level == 2 and game.specializations.branch(tower) == "control" and game.scrap == starting_parts-95,"Actual F/K pays fifty plus forty-five from the single naturally earned wallet")
 var remaining_day: float = game.phase_time; await advance(remaining_day+.001)
 check(game.phase == "night" and game.day_number == 2,"Actual remaining ninety-second day naturally reaches the second night without extension")
 var controlled_frames := 0; var cancellation_events := 0; var windup_frames := 0; var focus_commands := 0
 var observed_cancellations := 0; var real_source_token := -1; var source_paid := 0; var saw_original_stats := false
 var second_night_elapsed := 0.0
 var second_night_cutoff: Dictionary = {}
 # Bound actual residual combat; the production assault deadline is unchanged.
 for frame in ceili(240.0 / STEP):
  if game.phase != "night": break
  for controller: Node3D in game.warders:
   if not is_instance_valid(controller): continue
   var source: BattleUnit = controller.host
   if not is_instance_valid(source) or not source.alive: continue
   real_source_token = source.get_instance_id()
   saw_original_stats = is_equal_approx(source.max_hp,(155.0+2*28)*.82) and source.speed == 3.0 and source.damage == 12.0
   var shield_state: Dictionary = controller.snapshot()
   if shield_state.phase == "windup": windup_frames += 1
   var total_cancelled := int(shield_state.cancelled)
   cancellation_events += maxi(0,total_cancelled-observed_cancellations); observed_cancellations = total_cancelled
   if tower.position.distance_to(source.position) < 17.0 and game.focus_cooldown <= 0.0:
    await aim_at(source.position); await press(KEY_C)
    if game.focus_target == source and game.focus_time > 0.0: focus_commands += 1
   if game.specializations.movement_multiplier(source) < .9999: controlled_frames += 1
   source_paid = int(source.get_meta("warder_casts",0))
  game.aim = game.hero.position+Vector3(0,0,8)
  if game.gate_pressure() > 0: game.cast(0)
  if game.hero.hp < game.hero.max_hp*.6: game.cast(1); game.cast(4)
  if game.gate_pressure() >= 6: game.cast(3)
  game.simulate(STEP)
  second_night_elapsed += STEP
  if second_night_cutoff.is_empty() and second_night_elapsed >= game.NIGHT_LENGTH:
   second_night_cutoff = TransitionFixture.deadline_evidence(game, second_night_elapsed)
  if frame % 100 == 99: await process_frame
 TransitionFixture.record_natural_receipt(game, evidence, "second", second_night_elapsed, second_night_cutoff)
 check(real_source_token != -1 and saw_original_stats,"The real saved fourth wave naturally spawns its unmodified shield source")
 check(focus_commands > 0 and controlled_frames > 0 and source_paid == 0,"Naturally funded legal C/control defense really slows the moving source and prevents a successful shield")
 check(game.phase == "draft" and game.hero.alive and game.beacon_hp > 0.0,"Actual second night completes with original enemy HP/damage/speed and no wallet supplementation")
 evidence.economy = {"opening":90,"night1_actual_deaths":first_deaths,"day_start":starting_parts,"control_cost":95,
  "day_seconds":90,"night_seconds":105,"source_token":real_source_token,"observed_controlled_frames":controlled_frames,
  "observed_actual_cancel_events":cancellation_events,"observed_windup_frames":windup_frames,"legal_focus_commands":focus_commands,
  "successful_shields":source_paid,"final_parts":game.scrap,"hero_hp":game.hero.hp,"beacon_hp":game.beacon_hp,
  "scope":"one fixed-seed scripted input policy, natural clocks and enemy stats; not all-build or human difficulty balance"}
 if game.phase == "draft": await press(KEY_1)
 camera_at(Vector3(0,5,10)); await capture("warder-natural-single-wallet-defense",false)
 evidence.completed.append("economy")

func redraw_hud() -> void:
 game.hud.queue_redraw()
 for _frame in 4: await process_frame

func hud_chinese_bounds(row: Dictionary,tag: String) -> void:
 var text_value := String(row.text)
 for character in text_value.length():
  var codepoint := text_value.unicode_at(character)
  if codepoint > 127:
   check(game.hud.font.has_char(codepoint),"Actual Chinese HUD font has the displayed glyph in "+tag+": "+text_value.substr(character,1))
 if bool(row.drawer):
  check(row.point.x >= 36 and row.point.x+float(row.width) <= 544
   and row.point.y-float(row.ascent) >= 120 and row.point.y+float(row.descent) < 692,
   "Actual drawer Chinese width/top/bottom fit above close in "+tag)

func hud_layout(tag: String,kind: String,baseline_panels: Array = []) -> void:
 var before := state()
 for viewport: Vector2i in VIEWPORTS:
  root.size = viewport; root.content_scale_size = viewport; await redraw_hud()
  check(Vector2i(game.hud.get_viewport_rect().size) == viewport and not game.hud.drawn_labels.is_empty(),"Actual HUD redraw uses the requested viewport for "+tag)
  var observed: Array = []; var advice: Array[Dictionary] = []; var warnings: Array[Dictionary] = []
  for row: Dictionary in game.hud.drawn_labels:
   hud_chinese_bounds(row,tag)
   var value := String(row.text)
   if kind == "preview" and row.point == Vector2(444,66): advice.append(row)
   if kind == "defense" and bool(row.drawer) and row.point.x == 46.0 and row.point.y >= 286 and row.point.y <= 308: advice.append(row)
   if kind == "hunter" and value.begins_with("未耗尽召潮/织壳"): advice.append(row)
   if kind == "mixed" and (value.begins_with("投蚀 ") or value.begins_with("召援 ") or value.begins_with("织壳 ")): warnings.append(row)
   if bool(row.drawer) or value.contains("织壳") or value.begins_with("召援 ") or value.begins_with("投蚀 "):
    observed.append({"text":value,"point":row.point,"width":row.width,"ascent":row.ascent,"descent":row.descent,"font_size":row.font_size})
  var joined := ""
  for row: Dictionary in advice: joined += String(row.text)
  if kind == "preview":
   check(advice.size() == 1 and joined == "织壳1秒 · 32盾/4秒 · 最多3次 · 击杀或牵制打断 · F3 防线","Actual saved-wave preview displays its full short counter hint without clipping")
   if not advice.is_empty():
    var row: Dictionary = advice[0]
    check(row.point.x >= 426 and row.point.x+float(row.width) <= 1014
     and row.point.y-float(row.ascent) >= 20 and row.point.y+float(row.descent) <= 96,"Actual preview counter hint fits both horizontal and vertical objective bounds")
  elif kind == "defense":
   check(advice.size() >= 1 and advice.size() <= 2 and joined == "召潮2.4秒/最多2援军；织壳1秒/32盾4秒/最多3次；击杀或牵制打断。甲壳60甲，J破甲忽略半甲/C集火。","Actual F3 defense shows the complete combined counter rule within its real one-or-two-line font budget")
  elif kind == "hunter":
   check(advice.size() == 1 and joined == "未耗尽召潮/织壳、疾行/噬灯/投蚀30伤；其余12","Actual selected hunter third page includes the full active-source thirty-damage rule")
  elif kind == "mixed":
   check(warnings.size() == 3,"Actual mixed production windups display all three Chinese world warnings")
   for index in warnings.size():
    var row: Dictionary = warnings[index]
    var rect := Rect2(row.point-Vector2(0,float(row.ascent)),Vector2(float(row.width),float(row.ascent)+float(row.descent)))
    check(Rect2(0,0,1440,900).encloses(rect),"Actual mixed warning Chinese text stays inside the logical viewport")
    for other_index in range(index+1,warnings.size()):
     var other: Dictionary = warnings[other_index]
     var other_rect := Rect2(other.point-Vector2(0,float(other.ascent)),Vector2(float(other.width),float(other.ascent)+float(other.descent)))
     check(not rect.intersects(other_rect),"Actual mixed warning Chinese glyph rectangles do not overlap")
   check(game.hud.live_panel_rects() == baseline_panels,"Actual world warning labels do not add constant panels or mouse hitboxes")
  evidence.hud.layouts.append({"tag":tag,"viewport":viewport,"labels":observed,"panels":game.hud.live_panel_rects()})
 check(state() == before,"Three-view actual HUD observation cannot advance simulation, shielding, spend or RNG")
 root.size = VIEWPORTS[0]; root.content_scale_size = VIEWPORTS[0]; await redraw_hud()

func hud_clarity_and_input() -> void:
 evidence.hud = {"fixture":"actual production waves/controllers/input; explicit precision parts, stationary unrelated enemies and long phases isolate HUD; controlled capture lighting",
  "layouts":[],"world_commands":[]}
 await fresh(2,true,true)
 while game.wave_index < 3:
  for value: Variant in game.enemies.duplicate():
   if is_instance_valid(value) and value.alive: value.hurt(100000.0,null)
  await process_frame; game.enemies.clear(); game.spawn_night_wave()
 var upcoming: Dictionary = game.night_plan[3]
 game.phase_time = game.NIGHT_LENGTH-float(upcoming.time)+4.0
 var preview: Dictionary = game.wave_preview()
 check(game.day_number == 2 and game.wave_index == 3 and int(preview.warder_count) == 1
  and is_equal_approx(float(preview.remaining),4.0),"Actual second-night saved fourth wave is genuinely next after three production spawns")
 camera_at(HOME); await hud_layout("second-night-fourth-wave-preview","preview")
 await capture("warder-hud-real-fourth-wave-preview")
 await fresh(3); await press(KEY_F3); await click_ui(game.hud.details_tab_rect(3))
 var reinforcement_cap := 0; var shield_cap := 0
 for entry: Dictionary in game.night_plan:
  reinforcement_cap += int(entry.reinforcement_cap); shield_cap += int(entry.shield_cast_cap)
 check(game.hud.detail_tab == "defense" and reinforcement_cap == 2 and shield_cap == 6,"Real third-night F3 defense reads both saved summoning and shielding ceilings")
 await hud_layout("third-night-combined-defense","defense")
 await capture("warder-hud-real-combined-defense")
 await fresh(); var group := await trained_counter("hunter",false)
 await press(KEY_F3); await click_ui(game.hud.details_tab_rect(2))
 check(game.hud.detail_tab == "army" and game.hud.troop_page == 2
  and game.hud.selected_hunter_ids() == [int(group.id)] and group.members.size() == 3,
  "Real paid hunter training/selection opens the actual third army page with all three living members")
 for member: BattleUnit in group.members:
  check(is_instance_valid(member) and member.alive,"Actual selected third-page hunter group retains each of its three living trained members")
 camera_at(STATION); await hud_layout("selected-hunter-third-page","hunter")
 await capture("warder-hud-real-selected-hunter-third-page")
 await fresh(3); stand(Vector3(2,0,35.5)); camera_at(Vector3(0,0,33.5))
 await redraw_hud(); var baseline_panels: Array = game.hud.live_panel_rects().duplicate()
 # Urgent warnings suppress ordinary copy and release its transient hitboxes.
 # Preserve exact equality for every persistent HUD area, including input.
 baseline_panels.erase(CleanHud.notice_rect(game.hud,game))
 baseline_panels.erase(game.hud.context_prompt_rect())
 var p := pack(FIELD)
 var summon_source := spawn(Vector3(.6,0,32.1),"summoner")
 var throw_source := spawn(Vector3(3.5,0,32.1),"lobber")
 game.simulate(.001)
 check(p.controller.snapshot().phase == "windup" and game.warder_warning_snapshot().size() == 1
  and game.summoner_warning_snapshot().size() == 1 and game.lobber_warning_snapshot().size() == 1
  and is_instance_valid(summon_source) and is_instance_valid(throw_source),"Actual root simulate begins all three distinct live production warning controllers")
 await hud_layout("mixed-real-world-warnings","mixed",baseline_panels)
 await capture("warder-hud-real-mixed-world-warnings")
 for viewport: Vector2i in VIEWPORTS:
  root.size = viewport; root.content_scale_size = viewport; await redraw_hud()
  stand(Vector3(2,0,35.5)); var destination := on_ground(Vector3(7,0,36))
  var screen: Vector2 = game.camera.unproject_position(destination)
  var logical := screen*Vector2(1440,900)/Vector2(viewport)
  var empty := true
  for rect: Rect2 in game.hud.live_panel_rects():
   if rect.has_point(logical): empty = false
  for rect: Rect2 in game.hud.world_warning_rects:
   if rect.has_point(logical): empty = false
  check(empty,"Actual test click lies in visible blank world space between all panels and warning labels")
  var frozen := state(); var old_goal: Vector3 = game.move_goal
  await mouse(screen,MOUSE_BUTTON_RIGHT)
  check(planar(game.move_goal,destination) < .35 and game.move_goal != old_goal and not game.hero_path.is_empty(),"Real blank-world right click still issues a reachable hero movement command beside the warnings")
  check(state() == frozen,"Actual world command input leaves shielding, windups, budget and RNG frozen until simulation")
  evidence.hud.world_commands.append({"viewport":viewport,"screen":screen,"logical":logical,"goal":game.move_goal,"path_points":game.hero_path.size()})
 root.size = VIEWPORTS[0]; root.content_scale_size = VIEWPORTS[0]
 evidence.completed.append("hud")

func run() -> void:
 var cases := {"catalog":catalog_and_budget,"selection":selection_rules,"timing":full_cast_damage_and_expiry,
  "quota":finite_quota_and_rebuild,"geometry":geometry_rules,"contention":competing_sources_and_source_death,
  "cancel":cancellation_and_control,"freeze":freeze_lifecycle_and_reentry,"counter":active_and_spent_counterplay,"economy":natural_budget_counterplay,"hud":hud_clarity_and_input}
 var selected: Array = cases.keys(); var args := OS.get_cmdline_user_args(); var index := args.find("--case")
 if index >= 0:
  if index+1 < args.size() and cases.has(args[index+1]): selected = [args[index+1]]
  else: check(false,"Warder case names must identify a known local case")
 var ready_api := false; var production: Script = load("res://scripts/nightfall.gd")
 for method: Dictionary in production.get_script_method_list():
  if String(method.name) == "warder_warning_snapshot": ready_api = true
 check(ready_api,"Production controller integration must exist before shield acceptance")
 evidence.selected_cases = selected
 if failures.is_empty():
  for case_name: String in selected:
   active_stage = case_name; print("WARDER_STAGE_BEGIN ",case_name)
   await (cases[case_name] as Callable).call()
   print("WARDER_STAGE_END ",case_name," checks=",checks," failures=",failures.size())
   if not failures.is_empty(): break
 await close_game()
 check(evidence.completed == selected if failures.is_empty() else true,"Every selected warder case reaches its actual final evidence stage")
 var folder := ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
 var file := FileAccess.open(folder.path_join("warders.json"),FileAccess.WRITE)
 check(file != null,"Shield evidence opens only below local build")
 evidence.checks = checks; evidence.failures = failures
 if file: file.store_string(JSON.stringify(evidence,"\t")); file.close()
 print("NIGHTFALL_WARDERS_","OK" if failures.is_empty() else "FAILED"," checks=",checks," real_shields_finite_sources_original_budget")
 finished = true; quit(0 if failures.is_empty() else 1)
