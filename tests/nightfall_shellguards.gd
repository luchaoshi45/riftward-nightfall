extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
## True production shellguard births, armor/shields, paid counters, movement and GUI.
## Precision cases isolate offense and extend phases; they are not difficulty proof.
const RunSession := preload("res://scripts/run_session.gd")
const Shellguard := preload("res://scripts/nightfall_shellguard.gd")
const Catalog := preload("res://scripts/outpost_catalog.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
const CleanHud := preload("res://scripts/nightfall_clean_hud.gd")
const SEED := 20261006
const STEP := .05
const HOME := Vector3(0,5,3.1)
const FIELD := Vector3(0,0,32)
const FRONT := Vector3(0,5,10.5)
const STATION := Vector3(-4,5,6)
const VIEWPORTS := [Vector2i(1920,1200),Vector2i(1920,1080),Vector2i(1440,900)]
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
var hits: Array[Dictionary] = []
var output_dir := "res://build/shellguards"
var render_test := false
var active_stage := "initialization"
var finished := false
var evidence := {"seed":SEED,"scope":"production actors/input/hurt;5000 precision parts and extended clocks isolate mechanics,not playable difficulty",
 "completed":[],"captures":[],"ledgers":[],"combat":{},"hud":[]}

func _initialize() -> void:
 var args := OS.get_cmdline_user_args(); render_test = "--render-test" in args
 var index := args.find("--output-dir")
 if index >= 0 and index+1 < args.size():
  var candidate := ProjectSettings.globalize_path(args[index+1]).simplify_path()
  var allowed := ProjectSettings.globalize_path("res://build").simplify_path()
  if candidate.begins_with(allowed+"/"): output_dir = candidate
  else: check(false,"Shellguard evidence must remain below this project's build directory")
 root.size = VIEWPORTS[0]; root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT; root.content_scale_size = VIEWPORTS[0]
 if DisplayServer.get_name() != "headless":
  DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true); root.position=Vector2i(10000,10000); root.hide()
 create_timer(300.0,true,false,true).timeout.connect(watchdog)
 call_deferred("run")

func watchdog() -> void:
 if finished:return
 check(false,"Shellguard acceptance stalled in "+active_stage); await close_game();finished=true;quit(1)

func check(condition: bool,message: String) -> void:
 checks+=1
 if condition:return
 failures.append(message)
 if failures.size()<=30:push_error(message)

func press(code: int) -> void:
 var event := InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true
 root.push_input(event,true);event.pressed=false;root.push_input(event,true);await process_frame

func mouse(point: Vector2,button: int=0) -> void:
 var motion := InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true);await process_frame
 if button==0:return
 var event := InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=button
 event.button_mask=MOUSE_BUTTON_MASK_LEFT if button==MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
 event.pressed=true;root.push_input(event,true);await process_frame
 event.pressed=false;event.button_mask=0;root.push_input(event,true);await process_frame

func click_ui(rect: Rect2) -> void:
 await mouse(rect.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900),MOUSE_BUTTON_LEFT)

func planar(a: Vector3,b: Vector3) -> float:
 return Vector2(a.x-b.x,a.z-b.z).length()

func ground(point: Vector3) -> Vector3:
 point.y=game.outpost_height(point);return point

func stand(point: Vector3) -> void:
 point=ground(point);game.hero.position=point;game.move_goal=point;game.hero_path.clear();game.hero_keyboard_active=false
 game.hero.moving=false;game.hero.set_locomotion_velocity(Vector3.ZERO)

func camera_at(point: Vector3) -> void:
 game.camera.size=38.0;game.camera.position=point+Vector3(0,25,29);game.camera.look_at(point);game.camera_follow=game.camera.position

func aim_at(point: Vector3) -> void:
 camera_at(point);await mouse(game.camera.unproject_position(point));game._process(0.0)

func advance(seconds: float) -> void:
 for frame in ceili(seconds/STEP):
  game.simulate(minf(STEP,seconds-float(frame)*STEP))
  if frame%80==79:await process_frame

func clear_enemies() -> void:
 game.clear_warders();game.clear_summoners();game.clear_lobbers();game.clear_focus();game.cancel_hero_attack()
 for value: Variant in game.enemies:
  if is_instance_valid(value):value.queue_free()
 game.enemies.clear()

func close_game() -> void:
 if not is_instance_valid(game):return
 var token:=game.get_instance_id()
 await game.prepare_shutdown()
 if current_scene==game:current_scene=null
 game.queue_free();game=null
 for _frame in 4:await process_frame
 await create_timer(.2,true,false,true).timeout
 check(not is_instance_id_valid(token),"Actual shutdown frees the original production root and its eager controllers")

func fresh(night: int=2,keep_wave: bool=false) -> void:
 await close_game()
 check(RunSession.queue_request(self,SEED,"siege"),"Production session accepts the fixed standard seed")
 # Instantiate the unchanged packed root. No post-instantiation set_script,
 # which would orphan original eager districts/day-contract controller Nodes.
 game=load("res://scenes/nightfall.tscn").instantiate();root.add_child(game);current_scene=game
 for _frame in 5:await process_frame
 game.set_process(false);game.world.set_process(false)
 var script:=GDScript.new();script.source_code=HUD_OBSERVER
 check(script.reload()==OK,"HUD observer only forwards actual production paint/input")
 var old: Control=game.hud;var layer: Node=old.get_parent();layer.remove_child(old);old.queue_free()
 var observed: Control=script.new();observed.game=game;game.hud=observed;layer.add_child(observed)
 observed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 await press(KEY_1)
 check(game.phase=="night" and game.run_mode=="siege" and game.run.seed_value==SEED,"Real opening input enters production standard night")
 if night!=1:game.day_number=night;game.start_night()
 if not keep_wave:clear_enemies();game.wave_index=game.WAVES_PER_NIGHT
 game.phase_time=10000.0;game.scrap=5000;game.hero.attack_timer=100000.0;game.pulse_timer=100000.0;game.spawn_timer=100000.0
 game.gate_trap_charges=0;game.show_gate_trap_charges()
 for pad: Dictionary in game.world.tower_pads:pad.cooldown=100000.0
 stand(HOME);hits.clear()

func record_hurt(victim: BattleUnit,source: BattleUnit,hp_loss: float,shield_loss: float) -> void:
 hits.append({"victim":victim.get_instance_id(),"source":source.get_instance_id() if is_instance_valid(source) else -1,"hp":hp_loss,"shield":shield_loss})

func spawn(point: Vector3=FIELD,role: String="shellguard",stationary: bool=true) -> BattleUnit:
 var creature: BattleUnit=game.spawn_creature(true,role);creature.position=ground(point)
 if stationary:creature.speed=0.0;creature.attack_timer=100000.0
 creature.damage_confirmed.connect(record_hurt);return creature

func snapshot() -> Dictionary:
 var enemies: Array=[]
 for value: Variant in game.enemies:
  if is_instance_valid(value):enemies.append([value.get_instance_id(),value.position,value.hp,value.armor,value.shield,value.shield_time,value.attack_timer,value.attack_windup,value.attack_queued])
 return {"enemies":enemies,"parts":game.scrap,"time":game.phase_time,"rng":game.run.rng.state,"spawn_rng":game.spawn_rng.state,"focus":game.focus_time}

func redraw() -> void:
 game.hud.queue_redraw()
 for _frame in 4:await process_frame

func capture(label: String) -> void:
 if not render_test:return
 check(DisplayServer.get_name()!="headless","Actual screenshots require a graphical backend")
 if DisplayServer.get_name()=="headless":return
 var frozen:=snapshot()
 for viewport: Vector2i in VIEWPORTS:
  root.size=viewport;root.content_scale_size=viewport;game.world.set_night(true);game.world.night_mix=1.0;game.world.apply_lighting()
  await redraw();await RenderingServer.frame_post_draw
  var picture: Image=root.get_texture().get_image()
  check(picture.get_size()==viewport and Vector2i(game.hud.get_viewport_rect().size)==viewport,"Actual PNG and HUD use requested content viewport")
  var folder:=ProjectSettings.globalize_path(output_dir);DirAccess.make_dir_recursive_absolute(folder)
  var name:="%s-%dx%d"%[label,viewport.x,viewport.y]
  check(picture.save_png(folder.path_join(name+".png"))==OK,"Actual shellguard PNG stays below build")
  evidence.captures.append(name)
 check(snapshot()==frozen,"Capturing three views does not advance actors,armor,shields,spend or RNG")
 root.size=VIEWPORTS[0];root.content_scale_size=VIEWPORTS[0];await redraw()

func catalog_and_budget() -> void:
 var born:=0
 for night in [1,2,3,4]:
  await fresh(night,true);var balance: int=game.scrap
  for wave in 5:
   var entry: Dictionary=game.night_plan[wave];var actual: Array[String]=[];var shell_count:=0
   for enemy: BattleUnit in game.enemies:
    if bool(enemy.get_meta("siege_boss",false)):continue
    var role:=String(enemy.get_meta("threat",""));actual.append("basic" if role=="stalker" else role)
    if role!="shellguard":continue
    shell_count+=1;born+=1
    check(enemy.title=="甲壳卫" and is_equal_approx(enemy.max_hp,(155.0+night*28.0)*1.15) and enemy.hp==enemy.max_hp,
     "Actual saved shellguard has declared ordinary-health multiplier and original Chinese identity")
    check(enemy.armor==60.0 and enemy.speed==2.7 and enemy.damage==22.0 and enemy.attack_interval==1.5 and enemy.attack_range==1.6 and is_equal_approx(enemy.windup_duration,.34),
     "Actual saved shellguard exposes genuine60 armor,2.7 speed,22 damage,1.5 interval,1.6 reach,.34 preparation")
    check(enemy.visual.scene_file_path=="res://assets/models/night_stalker_v2.glb" and not enemy.legs.is_empty(),"Actual shellguard keeps the original GLB instance and bound articulated limbs")
    var prototype: Node3D=enemy.visual.get_node_or_null("ShellguardNativeCarapace")
    check(prototype!=null and prototype.get_child_count()==5 and enemy.visual.scale==Vector3.ONE*1.18,"Five actual native shell plates attach once to the scaled original visual")
    var hp: float=enemy.hp;Shellguard.configure(enemy);Shellguard.configure(enemy)
    check(enemy.hp==hp and is_equal_approx(enemy.max_hp,(155.0+night*28.0)*1.15) and prototype.get_child_count()==5,"Reconfiguration cannot multiply health,heal or duplicate shell meshes")
   var expected:=1 if (night==2 and wave==2) or (night>=3 and wave in [0,4]) else 0
   check(actual==entry.roles and shell_count==expected and int(entry.shellguard_count)==expected,"True production saved order and exact armored replacement schedule agree")
   var reward_id: int=game.active_wave_reward_id;var ledger: Dictionary=game.wave_rewards.snapshot(reward_id)
   check(ledger.count==entry.count and ledger.budget==24,"Real shellguard retains unchanged initial population and24-part wave ledger")
   var before: int=game.scrap
   for value: Variant in game.enemies.duplicate():
    if not is_instance_valid(value) or not value.alive:continue
    value.hurt(100000.0,null);var paid: int=game.scrap;var kills: int=game.kills
    value.hurt(100000.0,null)
    check(game.wave_rewards.defeat(value)==0 and game.scrap==paid and game.kills==kills,"A duplicate real shellguard/ordinary/boss death cannot repeat income or kills")
   ledger=game.wave_rewards.snapshot(reward_id)
   check(ledger.cleared and ledger.paid==24 and game.scrap==before+24,"Every real saved-wave death pays exactly24 once")
   evidence.ledgers.append({"night":night,"wave":wave+1,"shellguards":shell_count,"count":ledger.count,"paid":ledger.paid})
   await process_frame;game.enemies.clear()
   if wave<4:game.spawn_night_wave()
  check(game.scrap==balance+120,"All five natural death ledgers settle exactly120 base parts")
 check(born==5,"Four actual nights create all five declared armored replacements")
 evidence.completed.append("catalog")

func armor_and_real_shield() -> void:
 await fresh();var enemy:=spawn();var hp: float=enemy.hp;var balance: int=game.scrap
 enemy.hurt(16.0,game.hero)
 check(hits.size()==1 and is_equal_approx(enemy.hp,hp-10.0) and hits[0].hp==10.0 and hits[0].shield==0.0 and hits[0].source==game.hero.get_instance_id(),"True16 hurt becomes10 after60 armor and emits original source")
 Shellguard.configure(enemy)
 check(enemy.hp==hp-10.0 and enemy.armor==60.0,"Repeated setup after actual damage cannot heal or clear armor")
 enemy.hurt(48.0,game.hero);check(is_equal_approx(enemy.hp,hp-40.0),"True48 hurt loses30 health through genuine60 armor")
 var source:=spawn(FIELD+Vector3(2,0,0),"warder");var controller: Node3D
 for value: Node3D in game.warders:
  if value.get("host")==source:controller=value
 game.simulate(.001)
 check(controller!=null and controller.snapshot().phase=="windup" and controller.snapshot().target==enemy,"Real injured armor unit is eligible for actual warder selection")
 await advance(.99);check(enemy.shield==0.0,"Actual warder does not grant armor target a premature shield")
 game.simulate(.011)
 check(enemy.shield==32.0 and is_equal_approx(enemy.shield_time,4.0) and enemy.hp==hp-40.0,"Real one-second cast grants32 for4 seconds without healing shellguard")
 await press(KEY_ESCAPE);var frozen:=snapshot();game.simulate(5.0)
 check(game.phase=="paused" and snapshot()==frozen,"Real granted armor-shield lifespan freezes through actual Escape")
 await press(KEY_ESCAPE);await press(KEY_V);frozen=snapshot();game.simulate(5.0)
 check(game.phase=="draft" and snapshot()==frozen,"Real granted armor-shield lifespan freezes while choosing actual cards")
 await press(KEY_1)
 hits.clear();enemy.hurt(48.0,game.hero)
 check(enemy.shield==2.0 and enemy.hp==hp-40.0 and hits.size()==1 and hits[0].shield==30.0 and hits[0].hp==0.0,"Armor reduction happens before real shield absorption")
 enemy.hurt(16.0,game.hero)
 check(enemy.shield==0.0 and is_equal_approx(enemy.hp,hp-48.0) and hits.back().shield==2.0 and hits.back().hp==8.0,"Next genuine10 impact consumes2 shield then8 health")
 balance=game.scrap;source.hurt(100000.0,null);await process_frame;game.simulate(.001)
 check(enemy.alive and enemy.armor==60.0 and game.scrap==balance,"Source death leaves the separate armored unit and adds no unregistered base income")
 evidence.combat.armor_shield=hits.duplicate(true);camera_at(FIELD);await capture("shellguard-real-warder-armor-shield")
 evidence.completed.append("armor")

func front_tower() -> Dictionary:
 stand(HOME);await press(KEY_Y);await press(KEY_1);await aim_at(FRONT)
 var before: int=game.world.tower_pads.size();var balance: int=game.scrap
 await mouse(game.camera.unproject_position(FRONT),MOUSE_BUTTON_LEFT);await press(KEY_ESCAPE)
 check(game.world.tower_pads.size()==before+1 and game.scrap==balance-60,"Actual GUI builds a paid freely placed front tower")
 var pad: Dictionary=game.world.tower_pads[before];stand(FRONT+Vector3(2,0,0));await press(KEY_F)
 check(pad.level==2 and game.scrap==balance-110,"Actual F pays50 to upgrade to genuine second level")
 pad.cooldown=100000.0;return pad

func tower_tradeoffs() -> void:
 for branch in ["standard","piercing","control"]:
  await fresh();var pad:=await front_tower();var balance: int=game.scrap
  if branch!="standard":
   await press(KEY_J if branch=="piercing" else KEY_K)
   check(game.specializations.branch(pad)==branch and game.scrap==balance-45,"Actual J/K chooses paid45 branch "+branch)
  await press(KEY_F);check(pad.level==3,"Actual second F upgrades the paid branch to third level")
  var enemy:=spawn(FRONT+Vector3(4,0,0));var nearby:=spawn(FRONT+Vector3(4,0,1),"basic")
  var hp: float=enemy.hp;var neighbor_hp: float=nearby.hp;hits.clear();pad.mode="nearest";pad.cooldown=0.0
  game.update_towers(.001)
  var expected:=93.0/1.6 if branch=="standard" else (93.0*1.65/1.3 if branch=="piercing" else 93.0*.55/1.6)
  check(is_equal_approx(enemy.hp,hp-expected) and enemy.armor==60.0,"True third-level "+branch+" deals its declared armor-adjusted primary damage without changing unit armor")
  var splash:=93.0*.36 if branch=="standard" else (0.0 if branch=="piercing" else 93.0*.22)
  check(is_equal_approx(nearby.hp,neighbor_hp-splash),"Third-level "+branch+" retains the real standard/control splash versus piercing's single-target tradeoff")
  check(hits.size()==(1 if branch=="piercing" else 2) and hits[0].source==game.hero.get_instance_id(),"Actual tower signals preserve source and expected true hurt count")
  if branch=="control":
   check(is_equal_approx(game.specializations.movement_multiplier(enemy),.85) and is_equal_approx(game.specializations.movement_multiplier(nearby),.70),"Real heavy shellguard receives15 percent control while ordinary receives30")
   check(enemy.speed==0.0,"Control does not overwrite precision base speed")
   game.specializations.advance(1.201);check(game.specializations.movement_multiplier(enemy)==1.0,"Live slow expires after1.2 seconds")
  if branch=="piercing":
   hp=enemy.hp;enemy.hurt(16.0,game.hero);check(is_equal_approx(enemy.hp,hp-10.0),"Later ordinary damage does not inherit piercing shot's temporary half-armor treatment")
  evidence.combat[branch]=hits.duplicate(true);camera_at(FRONT);await capture("shellguard-tower-"+branch)
 await fresh();var pad:=await front_tower();var enemy:=spawn(FRONT+Vector3(5,0,0));var near:=spawn(FRONT+Vector3(2,0,0),"basic")
 await aim_at(enemy.position);await press(KEY_C)
 check(game.focus_target==enemy and game.focus_time==8.0 and game.focus_cooldown==22.0,"Actual C establishes legal armored focus with genuine cooldown")
 var hp: float=enemy.hp;var near_hp: float=near.hp;pad.cooldown=0.0;game.update_towers(.001)
 check(is_equal_approx(enemy.hp,hp-76.0/1.6) and near.hp==near_hp,"Actual C picks shellguard over nearer ordinary while preserving second-level damage")
 clear_enemies();await process_frame
 var outside:=spawn(FRONT+Vector3(17.01,0,0));near=spawn(FRONT+Vector3(4,0,0),"basic");pad.mode="threat";pad.cooldown=0.0
 hp=outside.hp;near_hp=near.hp;game.update_towers(.001)
 check(outside.hp==hp and near.hp<near_hp,"Armored priority cannot expand the tower's strict17-metre level-two radius")
 clear_enemies();await process_frame
 enemy=spawn(FRONT+Vector3(8,0,0));near=spawn(FRONT+Vector3(4,0,0),"basic");pad.cooldown=0.0;hits.clear()
 hp=enemy.hp;near_hp=near.hp;game.update_towers(.001)
 check(is_equal_approx(enemy.hp,hp-76.0/1.6) and near.hp==near_hp,"True threat mode selects farther armored enemy over nearer ordinary inside unchanged range")
 var breaker:=spawn(FRONT+Vector3(6,0,0),"breaker");hp=enemy.hp;var breaker_hp: float=breaker.hp;pad.cooldown=0.0;game.update_towers(.001)
 check(enemy.hp==hp and breaker.hp<breaker_hp,"True threat mode preserves original breaker priority above added armor role")
 await fresh();pad=await front_tower();await press(KEY_K)
 stand(Vector3(0,0,35));enemy=spawn(Vector3(0,0,23),"shellguard",false);near=spawn(Vector3(3,0,23),"basic")
 pad.cooldown=0.0;game.update_towers(.001);pad.cooldown=100000.0
 check(enemy.speed==2.7 and is_equal_approx(game.specializations.movement_multiplier(enemy),.85),"Actual control shot retains natural2.7 base and applies15 percent live effect")
 var previous:=enemy.position;game.simulate(.2)
 check(is_equal_approx(planar(previous,enemy.position),2.7*.85*.2) and enemy.speed==2.7,"Full real simulate moves true armored unit at2.7 times.85")
 await advance(.801);check(is_equal_approx(game.specializations.movement_multiplier(enemy),.85),"True1.2-second control still exists before its exact expiry")
 await advance(.201);check(game.specializations.movement_multiplier(enemy)==1.0 and enemy.speed==2.7,"Full real simulate expires slow while keeping original2.7 speed")
 previous=enemy.position;game.simulate(.1)
 check(is_equal_approx(planar(previous,enemy.position),2.7*.1),"Real movement returns to2.7 after genuine control expiry")
 evidence.combat.control_motion={"base_speed":enemy.speed,"before_expiry_multiplier":.85,"after_expiry_multiplier":game.specializations.movement_multiplier(enemy)}
 evidence.completed.append("towers")

func trained_group(kind: String) -> Dictionary:
 check(game.build_structure_at(Vector3(7,5,-8.5),"barracks"),"True paid barracks permits counter training")
 if kind in ["hunter","ballista"]:check(game.build_structure_at(Vector3(-7.5,5,-8.5),"workshop"),"True paid workshop supports advanced counter")
 if kind=="ballista":check(game.build_structure_at(Vector3(-7.5,5,6),"laboratory"),"True paid laboratory permits heavy crossbows")
 var balance: int=game.scrap;var eligibility: Dictionary=game.squads.training_eligibility(kind)
 check(eligibility.available,"True current live buildings unlock "+kind)
 var result: Dictionary=game.squads.enqueue(kind)
 check(result.ok and game.scrap==balance-int(Catalog.troop(kind).cost),"Real production queue deducts declared "+kind+" parts once")
 await advance(float(Catalog.troop(kind).time)+.01)
 check(game.squads.squads.size()==1 and game.squads.squads[0].kind==kind,"True elapsed paid queue creates actual3-member "+kind+" group")
 var group: Dictionary=game.squads.squads[0]
 await press(KEY_TAB);await aim_at(STATION);await press(KEY_O);await advance(12.0)
 check(group.order=="guard" and planar(group.members[1].position,STATION)<.17,"Real O command moves center counter member to intended station")
 group.members[0].hurt(100000.0,null);group.members[2].hurt(100000.0,null);await process_frame
 check(group.members[0]==null and group.members[2]==null,"Single-counter precision removes genuine side casualties")
 return group

func troop_armor_rules() -> void:
 for kind in ["ranged","ballista","hunter"]:
  await fresh();var group:=await trained_group(kind);var soldier: BattleUnit=group.members[1]
  var enemy:=spawn(soldier.position+Vector3(3 if kind!="hunter" else 1,0,0))
  var ordinary: BattleUnit=spawn(soldier.position+Vector3(1,0,0),"basic") if kind!="hunter" else null
  var hp: float=enemy.hp;hits.clear();soldier.attack_timer=0.0
  game.simulate(.001)
  check(soldier.attack_queued and soldier.target==enemy,"Real "+kind+" starts its genuine attack preparation on shellguard")
  await advance(soldier.windup_duration+.001)
  var expected:=16.0/1.6 if kind=="ranged" else (46.0/1.6 if kind=="ballista" else 12.0/1.6)
  check(is_equal_approx(enemy.hp,hp-expected) and hits.size()==1 and hits[0].source==soldier.get_instance_id(),"True "+kind+" hurt preserves60 armor;hunter gets no18 bonus and heavy crossbow has no penetration")
  check(enemy.armor==60.0,"Actual counter leaves shellguard's armor unmodified")
  if is_instance_valid(ordinary):check(ordinary.hp==ordinary.max_hp,"Real "+kind+" armored priority leaves the nearer ordinary unharmed")
  evidence.combat[kind]=hits.duplicate(true);camera_at(STATION);await capture("shellguard-paid-"+kind)
 await fresh();var group:=await trained_group("hunter");var soldier: BattleUnit=group.members[1]
 var enemy:=spawn(soldier.position+Vector3(.6,0,0));var ordinary:=spawn(soldier.position+Vector3(1.1,0,0),"basic")
 var hp: float=ordinary.hp;var armor_hp: float=enemy.hp;hits.clear();soldier.attack_timer=0.0;game.simulate(.001)
 check(soldier.target==ordinary and soldier.attack_queued,"Actual hunter deprioritizes nearer armored target behind ordinary nonheavy")
 await advance(.221)
 check(ordinary.hp==hp-12.0 and enemy.hp==armor_hp and hits.size()==1 and hits[0].source==soldier.get_instance_id(),"True hunter completes ordinary12 hit without accidentally striking nearby armor")
 evidence.combat.hunter_competition=hits.duplicate(true)
 await aim_at(enemy.position);await press(KEY_C);check(game.focus_target==enemy,"Actual legal C can override hunter's ordinary-before-armor default priority")
 hp=enemy.hp;var ordinary_hp: float=ordinary.hp;hits.clear();await advance(soldier.attack_timer+.001)
 check(soldier.target==enemy and soldier.attack_queued,"Real hunter cooldown completion starts actual focused armored preparation")
 await advance(.221)
 check(is_equal_approx(enemy.hp,hp-7.5) and ordinary.hp==ordinary_hp and hits.size()==1 and hits[0].source==soldier.get_instance_id(),"Actual focused hunter deals only12 divided by1.6 armor with no18 bonus")
 evidence.combat.hunter_focused_armor=hits.duplicate(true)
 await capture("shellguard-hunter-real-focused-armor")
 evidence.completed.append("troops")

func natural_route_and_melee() -> void:
 await fresh();check(game.build_structure_at(Vector3(7,5,-8.5),"barracks"),"Real paid barracks supports route defenders")
 await press(KEY_U);await advance(6.01);check(game.squads.squads.size()==1,"Actual U creates three natural shield defenders")
 await press(KEY_TAB);await aim_at(Vector3(0,5,11));await press(KEY_O);await advance(8.0)
 var group: Dictionary=game.squads.squads[0]
 for member: BattleUnit in group.members:member.attack_timer=100000.0;member.damage_confirmed.connect(record_hurt)
 var enemy:=spawn(Vector3(0,0,31),"shellguard",false);enemy.attack_timer=0.0;var token:=enemy.get_instance_id();hits.clear()
 check(game.choose_enemy_target(enemy).kind=="squad","Natural shellguard selects nearest actual defender before distant beacon")
 var walked:=0.0;var crossings:=0;var windups:=0;var real_hit:=false
 for frame in 800:
  var previous:=enemy.position;game.simulate(STEP);walked+=planar(previous,enemy.position)
  check(game.outpost_walkable(enemy.position) and game.can_traverse(previous,enemy.position) and absf(enemy.position.y-game.outpost_height(enemy.position))<.001,"Natural armored route remains on continuous real walkable ground")
  check(planar(previous,enemy.position)<=2.7*STEP+.001,"True2.7 movement cannot teleport across walls")
  if previous.z>Layout.WALL_CENTER and enemy.position.z<=Layout.WALL_CENTER:
   var fraction:=(Layout.WALL_CENTER-previous.z)/(enemy.position.z-previous.z)
   check(absf(lerpf(previous.x,enemy.position.x,fraction))<Layout.GATE_HALF,"Actual shellguard crosses only the real south opening")
   crossings+=1
  if enemy.attack_queued:
   windups+=1;check(enemy.attack_windup>=0.0 and enemy.attack_windup<=.34,"Actual intercepted shellguard uses ordinary.34 preparation")
  for hit: Dictionary in hits:
   if hit.source==token:
    real_hit=true;check(is_equal_approx(float(hit.hp),22.0/1.25) and hit.shield==0.0,"Real shellguard22 attack respects shield defender25 armor")
  if real_hit:break
  if frame%80==79:await process_frame
 check(walked>10.0 and crossings==1 and windups>0 and real_hit,"Natural shellguard actually walks unique south gate then winds up and hurts live shield defender")
 check(game.beacon_hp==game.BEACON_MAX,"A nearby genuine defender takes the actual attack before core")
 evidence.combat.route={"walked":walked,"crossings":crossings,"windup_frames":windups,"hits":hits.duplicate(true)}
 camera_at(enemy.position);await capture("shellguard-real-south-gate-interception")
 # Separately preserve true normal melee and cancellation through hero input.
 await fresh();stand(FIELD);enemy=spawn(FIELD+Vector3(1,0,0));enemy.attack_timer=0.0;game.hero.damage_confirmed.connect(record_hurt)
 game.simulate(.001);check(enemy.attack_queued and is_equal_approx(enemy.attack_windup,.34),"Actual nearest hero selection starts full ordinary windup")
 var hp: float=game.hero.hp;await aim_at(FIELD-Vector3(5,0,0));await press(KEY_E);await advance(.4)
 check(not enemy.attack_queued and game.hero.hp==hp,"Real E leaving melee contact cancels pending shellguard damage")
 await fresh();check(game.build_structure_at(Vector3(7,5,-8.5),"barracks"),"True paid barracks is a genuine nearest building target")
 var plot_index: int=game.districts.plots.size()-1;var plot: Dictionary=game.districts.plots[plot_index]
 var approach: Vector3=game.building_approach_position(Vector3(12,5,-8.5),plot.position,"barracks")
 check(approach.is_finite() and game.outpost_walkable(approach),"Actual built barracks has a reachable true attack approach")
 enemy=spawn(approach);enemy.attack_timer=0.0;var building_hp: float=plot.hp
 game.simulate(.001)
 check(game.choose_enemy_target(enemy).kind=="district" and int(enemy.get_meta("attack_target_index",-1))==plot_index and enemy.attack_queued and is_equal_approx(enemy.attack_windup,.34),"Actual nearest barracks enters real.34 melee prep instead of distant core")
 await advance(.331);check(plot.hp==building_hp,"Real building prep cannot deal early damage")
 game.simulate(.01)
 check(plot.hp==building_hp-22.0 and game.beacon_hp==game.BEACON_MAX,"True completed shellguard melee takes22 from nearest live building")
 enemy.attack_timer=0.0;game.simulate(.001);check(enemy.attack_queued,"Real second building attack begins before destruction cancellation")
 game.districts.damage(plot_index,100000.0);game.simulate(.4)
 check(not enemy.attack_queued and game.beacon_hp==game.BEACON_MAX,"Real nearest building death cancels pending melee without leaking distant core damage")
 evidence.combat.building={"index":plot_index,"true_damage":22.0,"cancel_after_real_destruction":true}
 evidence.completed.append("route")

func freeze_and_lifecycle() -> void:
 await fresh();stand(FIELD);var enemy:=spawn(FIELD+Vector3(1,0,0));enemy.attack_timer=0.0;game.simulate(.001)
 check(enemy.attack_queued and is_equal_approx(enemy.attack_windup,.34),"True shellguard windup exists before freeze")
 await press(KEY_ESCAPE);check(game.phase=="paused","Real Escape pauses the live melee windup")
 var frozen:=snapshot();game.simulate(5.0);check(snapshot()==frozen,"Real paused simulation freezes position,HP,armor,shield,timers,parts and RNG")
 await press(KEY_ESCAPE);await press(KEY_V);check(game.phase=="draft","Real paid V opens production cards during armor melee")
 frozen=snapshot();game.simulate(5.0);check(snapshot()==frozen,"Real card choice freezes same production actor state")
 await press(KEY_1);check(game.phase=="night","Real selected card returns to the same active night")
 var native: Node3D=enemy.visual.get_node_or_null("ShellguardNativeCarapace");var visual:=enemy.visual
 var visual_token:=visual.get_instance_id();var native_token:=native.get_instance_id();var host_token:=enemy.get_instance_id()
 var plate_tokens: Array[int]=[]
 for plate: Node in native.get_children():plate_tokens.append(plate.get_instance_id())
 enemy.hurt(100000.0,null);await process_frame
 check(not is_instance_id_valid(host_token) and is_instance_id_valid(visual_token) and is_instance_id_valid(native_token),"Real death releases gameplay host while keeping original GLB and attached shell in genuine corpse")
 check(game.deaths.corpses.size()>0 and game.deaths.corpses.back().visual==visual,"Actual corpse owns original shellguard visual rather than a copied model")
 await press(KEY_ESCAPE);var corpse_time: float=game.deaths.corpses.back().time;game.deaths.tick(5.0,"paused")
 check(game.deaths.corpses.back().time==corpse_time,"Real pause freezes corpse fall/fade")
 await press(KEY_ESCAPE)
 var corpse: Dictionary=game.deaths.corpses.back()
 for frame in ceili(float(corpse.duration)/STEP)+2:
  if not is_instance_id_valid(visual_token):break
  game._process(STEP)
  if frame%20==19:await process_frame
 await process_frame;await process_frame
 check(not is_instance_id_valid(visual_token) and not is_instance_id_valid(native_token),"Natural corpse expiry frees original GLB and native shell together")
 for plate_token: int in plate_tokens:check(not is_instance_id_valid(plate_token),"Every attached native shell plate actually frees at corpse expiry")
 for action in ["dawn","defeat","shutdown"]:
  await fresh();enemy=spawn();native=enemy.visual.get_node_or_null("ShellguardNativeCarapace");native_token=native.get_instance_id();host_token=enemy.get_instance_id()
  if action=="dawn":TransitionFixture.finish_for_fixture(game);await process_frame;check(game.phase in ["day","draft"],"Artificial actor retirement prepares the genuine dawn lifecycle; it is not natural clearance proof")
  elif action=="defeat":game.end_defeat("甲壳验收");enemy.hurt(100000.0,null);game.deaths.tick(.01,"ended");await process_frame
  else:await close_game()
  if action=="dawn" or action=="shutdown":check(not is_instance_id_valid(host_token) and not is_instance_id_valid(native_token),"Fixture actor retirement or actual shutdown frees the armored actor and native additions: "+action)
  else:check(not is_instance_id_valid(native_token),"Actual ended corpse cleanup releases all native armor")
 await fresh();enemy=spawn();native=enemy.visual.get_node_or_null("ShellguardNativeCarapace")
 host_token=enemy.get_instance_id();native_token=native.get_instance_id();var old_root: WeakRef=weakref(game)
 game.end_defeat("甲壳同局重试验收");await press(KEY_ENTER)
 for frame in 240:
  await create_timer(.02,true,false,true).timeout
  if is_instance_valid(current_scene) and current_scene!=old_root.get_ref():
   game=current_scene;game.set_process(false);game.world.set_process(false);break
 check(is_instance_valid(game) and game!=old_root.get_ref() and not is_instance_valid(old_root.get_ref()),"Actual Enter replaces and truly frees original production root")
 check(not is_instance_id_valid(host_token) and not is_instance_id_valid(native_token),"Actual retry releases original armored host and all attached native additions")
 check(game.phase=="draft" and game.run.seed_value==SEED and game.run_mode=="siege" and game.enemies.is_empty() and game.squads.squads.is_empty(),"True same challenge retains seed/mode while clearing old actors and roster")
 await press(KEY_1);check(game.phase=="night" and game.day_number==1 and game.night_plan[0].shellguard_count==0,"Actual retried opening stays unchanged first night without armor substitution")
 evidence.completed.append("freeze")

func hud_bounds(row: Dictionary) -> void:
 var value:=String(row.text)
 for index in value.length():
  var codepoint:=value.unicode_at(index)
  if codepoint>127:check(game.hud.font.has_char(codepoint),"Actual Chinese glyph exists for "+value.substr(index,1))
 if bool(row.drawer):check(row.point.x>=36 and row.point.x+float(row.width)<=544 and row.point.y-float(row.ascent)>=120 and row.point.y+float(row.descent)<692,"Actual drawer text fits real width and close-button baseline")

func hud_layout(tag: String,kind: String) -> void:
 var frozen:=snapshot()
 for viewport: Vector2i in VIEWPORTS:
  root.size=viewport;root.content_scale_size=viewport;await redraw()
  check(Vector2i(game.hud.get_viewport_rect().size)==viewport and not game.hud.drawn_labels.is_empty(),"Actual armor HUD redraw uses requested viewport")
  var relevant: Array=[];var joined:="";var lines:=0
  for row: Dictionary in game.hud.drawn_labels:
   hud_bounds(row);var value:=String(row.text)
   if (kind=="preview" and row.point==Vector2(444,66)) or (kind=="defense" and bool(row.drawer) and row.point.x==46 and row.point.y>=286 and row.point.y<=308):
    joined+=value;lines+=1;relevant.append(row)
   if kind=="world" and value.begins_with("甲60"):
    relevant.append(row)
    check(Rect2(0,0,1440,900).encloses(Rect2(row.point-Vector2(0,float(row.ascent)),Vector2(float(row.width),float(row.ascent)+float(row.descent)))),"Actual local armor label fits logical viewport")
  if kind=="preview":
   check(lines==1 and joined=="甲壳卫60甲 · 二级塔J破甲忽略半甲 · C集火 · F3 防线","Actual saved-wave short preview displays the complete60 armor,half-armor J and C rules without truncation")
   var objective: Rect2=CleanHud.objective_rect(game.hud,game)
   check(CleanHud.OBJECTIVE_RECT.encloses(objective) and game.hud.drawn_rects.has(objective)
    and game.hud.live_panel_rects().count(objective)==1,"Actual armor preview paints and reports one existing content-sized compact objective")
   for row: Dictionary in relevant:
    var glyphs:=Rect2(row.point-Vector2(0,float(row.ascent)),Vector2(float(row.width),float(row.ascent)+float(row.descent)))
    check(int(row.font_size)==12 and float(row.width)<=552.0 and objective.encloses(glyphs),"Actual complete armor preview glyph bounds fit its painted compact objective")
  elif kind=="defense":check(lines>=1 and lines<=2 and joined.contains("甲壳60甲") and joined.contains("J破甲") and joined.contains("C集火") and joined.contains("召潮2.4") and joined.contains("织壳1秒"),"Actual three-threat F3 advice keeps all counter rules in at most2 lines")
  else:check(not relevant.is_empty(),"Actual live local warning reads true armor value60")
  evidence.hud.append({"tag":tag,"viewport":viewport,"labels":relevant,"panels":game.hud.live_panel_rects()})
 check(snapshot()==frozen,"Three viewport observation cannot advance enemy,armor,shield,parts or RNG")
 root.size=VIEWPORTS[0];root.content_scale_size=VIEWPORTS[0];await redraw()

func hud_and_input() -> void:
 await fresh(2,true)
 while game.wave_index<2:
  for value: Variant in game.enemies.duplicate():
   if is_instance_valid(value) and value.alive:value.hurt(100000.0,null)
  await process_frame;game.enemies.clear();game.spawn_night_wave()
 var next: Dictionary=game.night_plan[2];game.phase_time=game.NIGHT_LENGTH-float(next.time)+4.0
 check(game.wave_preview().shellguard_count==1,"True second-night saved third-wave preview carries armor replacement")
 camera_at(HOME);await hud_layout("second-night-third-wave-preview","preview");await capture("shellguard-hud-actual-preview")
 await fresh(3);await press(KEY_F3);await click_ui(game.hud.details_tab_rect(3));await hud_layout("three-threat-defense","defense");await capture("shellguard-hud-three-threat-defense")
 for viewport: Vector2i in VIEWPORTS:
  root.size=viewport;root.content_scale_size=viewport;await redraw();var goal: Vector3=game.move_goal;var balance: int=game.scrap
  await mouse(Vector2(180,310)*Vector2(viewport)/Vector2(1440,900),MOUSE_BUTTON_RIGHT)
  check(game.move_goal==goal and game.scrap==balance,"Real visible armor defense UI consumes right click without world order or payment")
  await mouse(Vector2(180,310)*Vector2(viewport)/Vector2(1440,900),MOUSE_BUTTON_LEFT)
  check(game.move_goal==goal and not game.selection_dragging and game.scrap==balance,"Real visible defense UI consumes left click without selection or payment")
 await press(KEY_F3);root.size=VIEWPORTS[0];root.content_scale_size=VIEWPORTS[0]
 var baseline: Array=game.hud.live_panel_rects();var enemy:=spawn();camera_at(FIELD);await hud_layout("true-armor-local-label","world")
 check(game.hud.live_panel_rects()==baseline,"Actual armor labels add no permanent tactical panel")
 await capture("shellguard-hud-native-carapace-world-label")
 enemy.hurt(48.0,game.hero);var source:=spawn(FIELD+Vector3(2,0,0),"warder");game.simulate(.001);await advance(1.001)
 check(enemy.shield==32.0 and is_instance_valid(source),"Actual HUD capture uses real warder-granted armor shield")
 await capture("shellguard-hud-real-shield-on-armor")
 await hud_warning_geometry("real-armor-shield",["甲60","护盾32"])
 await fresh();var group:=await trained_group("shield");var soldier: BattleUnit=group.members[1];soldier.attack_timer=100000.0
 enemy=spawn(soldier.position+Vector3(1,0,0));enemy.attack_timer=0.0;game.simulate(.001)
 check(enemy.attack_queued and game.squads.intercept_target_for(enemy)==soldier,"Real selected shield defender receives genuine shellguard windup warning")
 camera_at(soldier.position);await hud_warning_geometry("real-armor-and-melee",["甲60","蓄力 0.3"])
 await capture("shellguard-hud-real-armor-melee-warning")
 evidence.completed.append("hud")

func hud_warning_geometry(tag: String,prefixes: Array) -> void:
 var frozen:=snapshot()
 for viewport: Vector2i in VIEWPORTS:
  root.size=viewport;root.content_scale_size=viewport;await redraw()
  var rows: Array[Dictionary]=[]
  for prefix: String in prefixes:
   var found:=false
   for row: Dictionary in game.hud.drawn_labels:
    if String(row.text).begins_with(prefix):
     found=true;rows.append(row);hud_bounds(row)
   check(found,"Actual "+tag+" draws true live label "+prefix+" at "+str(viewport))
  for index in rows.size():
   var row: Dictionary=rows[index]
   var rect:=Rect2(row.point-Vector2(0,float(row.ascent)),Vector2(float(row.width),float(row.ascent)+float(row.descent)))
   check(Rect2(0,0,1440,900).encloses(rect),"True local warning glyph bounds remain on screen in "+tag)
   for next in range(index+1,rows.size()):
    var other: Dictionary=rows[next]
    var other_rect:=Rect2(other.point-Vector2(0,float(other.ascent)),Vector2(float(other.width),float(other.ascent)+float(other.descent)))
    check(not rect.intersects(other_rect),"Actual concurrent "+tag+" glyph rectangles do not overlap at "+str(viewport))
  evidence.hud.append({"tag":tag,"viewport":viewport,"live_warning_rows":rows})
 check(snapshot()==frozen,"Three-view live warning geometry cannot advance actual melee or shield timing")
 root.size=VIEWPORTS[0];root.content_scale_size=VIEWPORTS[0];await redraw()

func run() -> void:
 var cases:={"catalog":catalog_and_budget,"armor":armor_and_real_shield,"towers":tower_tradeoffs,"troops":troop_armor_rules,"route":natural_route_and_melee,"freeze":freeze_and_lifecycle,"hud":hud_and_input}
 var args:=OS.get_cmdline_user_args();var selected: Array=cases.keys();var index:=args.find("--case")
 if index>=0:
  if index+1<args.size() and cases.has(args[index+1]):selected=[args[index+1]]
  else:check(false,"Shellguard case must identify a known production case")
 evidence.selected_cases=selected
 for case_name: String in selected:
  if not failures.is_empty():break
  active_stage=case_name;print("SHELLGUARD_STAGE_BEGIN ",case_name)
  await (cases[case_name] as Callable).call()
  print("SHELLGUARD_STAGE_END ",case_name," checks=",checks," failures=",failures.size())
 await close_game()
 check(evidence.completed==selected if failures.is_empty() else true,"Each requested production case completes its final receipt")
 var folder:=ProjectSettings.globalize_path(output_dir);DirAccess.make_dir_recursive_absolute(folder)
 var file:=FileAccess.open(folder.path_join("shellguards.json"),FileAccess.WRITE);check(file!=null,"Evidence only opens under local build")
 evidence.checks=checks;evidence.failures=failures
 if file:file.store_string(JSON.stringify(evidence,"\t"));file.close()
 print("NIGHTFALL_SHELLGUARDS_","OK" if failures.is_empty() else "FAILED"," checks=",checks," true_armor_shield_paid_counters_gate_melee_24_120_gui")
 finished=true;quit(0 if failures.is_empty() else 1)
