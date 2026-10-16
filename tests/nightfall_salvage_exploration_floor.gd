extends SceneTree
## Controlled day/positions/wallet; discoveries use unchanged original actors and
## production interaction/reward methods, not an injected positive ledger.
const Draw=preload("res://scripts/salvage_draw.gd")
const RunSession=preload("res://scripts/run_session.gd")
var game: Node3D
var checks:=0
var failures:=0
func click(rect: Rect2) -> void:
 var point: Vector2=rect.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900)
 for pressed in [true,false]:
  var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point
  root.push_input(event,true);await process_frame
func _initialize() -> void:
 create_timer(180.0,true,false,true).timeout.connect(func():quit(2))
 call_deferred("run")
func check(ok: bool,message: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(message)
func oracle(seed_value: int,day: int=2) -> RandomNumberGenerator:
 var rng:=RandomNumberGenerator.new()
 rng.seed=RunSession.stream_seed(seed_value ^ Draw.STREAM_SALT ^ (day*Draw.DAY_SALT),"salvage_draw")
 return rng
func discover(kind: String) -> void:
 for index in game.discoveries.items.size():
  var item: Dictionary=game.discoveries.items[index]
  if item.kind==kind and item.state=="ready":
   var before: int=game.exploration.day_discoveries
   game.hero.position=item.position
   check(game.discoveries.interact_index(index),"Real original discovery interaction "+kind)
   check(game.exploration.day_discoveries==before+1 and game.exploration.day_kinds.get(kind,false),"Production reward records actual discovery "+kind)
   return
 check(false,"Original ready discovery exists "+kind)
func home() -> void:game.hero.position=Vector3(0,5,0);game.move_goal=game.hero.position
func run() -> void:
 game=load("res://scenes/nightfall.tscn").instantiate();game.archive.enabled=false;root.add_child(game);current_scene=game
 await process_frame;game.set_process(false)
 while game.phase=="draft":game.choose_card(0)
 game.phase="day";game.day_number=2;game.phase_time=10000.0
 game.exploration.begin_day(2);game.salvage_draw.setup(game,7);game.salvage_draw.begin_day();game.scrap=5000
 var draw: RefCounted=game.salvage_draw
 check(draw.exploration_count()==0 and draw.snapshot().results[0].payout==10,"Fresh day starts with unchanged low payout")
 discover("ember_bloom");discover("ember_bloom");home()
 check(draw.exploration_count()==1 and draw.snapshot().exploration_status.begins_with("已发现1/3种"),"Repeated real category counts once")
 game.grant_exploration_reward("非路线测试",game.hero.position,0,0,0,"other")
 check(draw.exploration_count()==1,"Actual nonwhite-listed reward cannot unlock protection")
 var before: int=game.scrap
 var first: Dictionary=game.draw_salvage_supply("safe")
 var first_copy:=first.duplicate(true)
 check(first.ok and not first.exploration_floor and first.results[0].payout==10 and game.scrap==before-30+int(first.payout),"Before unlock original cost and actual unprotected receipt settle")
 discover("memory_crystal")
 check(draw.exploration_count()==2 and draw.mode_results("safe")[0].payout==10,"Two distinct production types do not unlock")
 discover("waylight");home()
 var state: Dictionary=draw.snapshot()
 check(draw.snapshot().last==first_copy,"Unlock leaves internal previous settlement receipt unchanged")
 var low_seed:=0
 while oracle(low_seed).randi_range(0,99)>=60:low_seed+=1
 draw.setup(game,low_seed);draw.begin_day();game.scrap=1000
 game.hud.detail_tab="exploration";game.hud.salvage_draw_open=true
 before=game.scrap
 await click(game.hud.SALVAGE_DRAW_RECT)
 check(draw.snapshot().last.payout==20 and draw.snapshot().last.net==-10 and game.scrap==before-10,"Real viewport safe purchase applies unlocked twenty-light low payout")
 for viewport in [Vector2i(1440,900),Vector2i(1920,1080),Vector2i(1920,1200)]:
  root.size=viewport;await process_frame
  var font: Font=game.hud.font
  var line: String="探索保底已解锁 · 稳妥低档20光 · 首抽稳妥"
  check(font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x<=496 and 215+font.get_descent(14)<249-font.get_ascent(14),"Actual font metrics fit single-line status before table header at "+str(viewport))
 game.hud.detail_tab="";game.hud.salvage_draw_open=false
 state=draw.snapshot()
 check(state.exploration_count==3 and state.exploration_floor and state.exploration_status.begins_with("探索保底已解锁"),"Three distinct original discovery types unlock")
 check(first==first_copy and not first.exploration_floor and first.results[0].payout==10,"Discovering more types never retroactively changes prior receipt")
 check(state.results[0].payout==20 and state.results[0].net==-10 and state.results_by_mode.safe==state.results and draw.mode_results("safe")==state.results and draw.mode_options()[0].results==state.results,"All published safe result tables agree on actual protected payout")
 check(state.results_by_mode.jackpot==Draw.JACKPOT_RESULTS,"Jackpot results remain unchanged")
 var rng_before: int=state.rng_state;before=game.scrap
 for index in 20:
  draw.snapshot();draw.select_mode("jackpot");draw.mode_results("safe");draw.select_mode("safe")
 check(draw.snapshot().rng_state==rng_before and game.scrap==before and draw.snapshot().used==1,"Viewing tables and switching modes consume no RNG, quota or wallet")
 var external_rng: Array=[game.rng.state,game.spawn_rng.state,game.run.rng.state,game.discoveries.rng.state,game.wildlife.rng.state]
 var buckets: Dictionary={}
 for seed_value in 100:
  draw.setup(game,seed_value);draw.begin_day();game.scrap=1000
  var rng:=oracle(seed_value);var roll:=rng.randi_range(0,99)
  before=game.scrap
  var result: Dictionary=game.draw_salvage_supply("safe")
  var expected: int=120 if roll>=90 else (40 if roll>=60 else 20)
  buckets[expected]=true
  check(result.ok and result.roll==roll and result.payout==expected and result.net==expected-30 and result.exploration_floor and result.results[0].payout==20 and game.scrap==before-30+expected,"Protected real settlement follows unchanged RNG buckets "+str(seed_value))
  check(game.reward_toasts.back().detail.contains("探索保底已解锁"),"Production receipt toast describes applied protection")
  draw.select_mode("jackpot");var second_roll:=rng.randi_range(0,99);before=game.scrap
  var jackpot: Dictionary=draw.draw("jackpot")
  expected=600 if second_roll>=95 else (120 if second_roll>=70 else 0)
  check(jackpot.roll==second_roll and jackpot.payout==expected and jackpot.results==Draw.JACKPOT_RESULTS and game.scrap==before-60+expected,"Protected exploration never changes jackpot buckets")
  check(not draw.draw().ok and draw.snapshot().used==2,"Daily limit remains two")
 check(buckets.size()==3,"Actual seeds exercised all safe payout tiers")
 check(external_rng==[game.rng.state,game.spawn_rng.state,game.run.rng.state,game.discoveries.rng.state,game.wildlife.rng.state],"Settlements preserve all original production RNG streams")
 draw.setup(game,7);draw.begin_day();home();game.scrap=1000
 game.phase="paused";game.paused_from="day"
 state=draw.snapshot();before=game.scrap;rng_before=state.rng_state
 check(state.exploration_floor and state.results_by_mode.safe[0].payout==20 and not draw.draw().ok and game.scrap==before and draw.snapshot().rng_state==rng_before,"Paused daytime detail preserves protected tables while payment is frozen")
 for phase in ["draft","night","ended"]:
  game.phase=phase;state=draw.snapshot();before=game.scrap;rng_before=state.rng_state
  check(not state.exploration_floor and state.results_by_mode.safe[0].payout==10 and not draw.draw().ok and game.scrap==before and draw.snapshot().rng_state==rng_before,"Non-day state rejects payment and displays no stale protection")
 game.phase="day";game.day_number=3
 check(not draw.snapshot().exploration_floor and not draw.draw().ok,"Cross-day mismatch cannot reuse old discovery ledger")
 game.exploration.begin_day(3);draw.begin_day()
 check(draw.exploration_count()==0 and draw.snapshot().remaining==2 and draw.snapshot().results[0].payout==10,"Actual next-day reset clears protection and restores quota")
 discover("memory_crystal");home()
 check(draw.exploration_count()==1 and not draw.snapshot().exploration_floor,"Next-day production discovery starts new category progress")
 var retired: RefCounted=draw
 await game.prepare_shutdown();before=game.scrap
 check(not retired.draw().ok and not retired.snapshot().exploration_floor and game.scrap==before,"Shutdown retires old module without protected payment")
 game.queue_free();current_scene=null
 for frame in 4:await process_frame
 await create_timer(.25,true,false,true).timeout
 print("NIGHTFALL_SALVAGE_EXPLORATION_FLOOR_OK checks=%d failures=%d" % [checks,failures]);quit(0 if failures==0 else 1)
