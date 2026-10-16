extends SceneTree
var game: Node3D
var checks := 0
var failures := 0
func _initialize() -> void:
 create_timer(120.0,true,false,true).timeout.connect(func(): quit(2))
 call_deferred("run")
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok: failures += 1; push_error(message)
func run() -> void:
 game = load("res://scenes/nightfall.tscn").instantiate()
 root.add_child(game); current_scene=game
 await process_frame
 game.set_process(false); game.archive.enabled=false
 game.phase="day"; game.phase_time=10000.0
 var events: Node3D=game.discoveries
 var cover: RefCounted=events.expedition_cover
 var item: Dictionary=events.items[3]
 item.kind="waylight"; item.position=Vector3(8,0,42); item.position.y=game.outpost_height(item.position); item.node.position=item.position
 game.hero.position=item.position; game.move_goal=item.position
 check(events.interact_index(3) and item.state=="active" and item.remaining==30.0,"Actual original lamp activation remains free and finite")
 var original: int=game.scrap
 check(not cover.purchase(item).ok and game.scrap==original,"No live workshop means no payment")
 game.scrap=1000
 var built: bool=game.build_structure_at(Vector3(-7,5,-8.5),"workshop")
 check(built,"Real paid workshop establishes technology")
 original=game.scrap; game.scrap=11
 check(not cover.purchase(item).ok and game.scrap==11,"Insufficient light cannot debit")
 game.scrap=original
 var press := InputEventKey.new();press.keycode=KEY_F;press.physical_keycode=KEY_F;press.pressed=true
 root.push_input(press,true);press.pressed=false;root.push_input(press,true)
 await process_frame
 check(cover.snapshot(item).get("paid",false) and game.scrap==original-12,"Actual active-lamp purchase debits exactly 12 light")
 check(not cover.purchase(item).ok and game.scrap==original-12,"One lamp incarnation cannot charge twice")
 check(events.interaction_prompt().contains("远征掩护"),"Nearby original interaction displays committed cover status")
 var id: int=game.squads._create_squad("shield",Vector3(8,0,51))
 var soldier: BattleUnit=game.squads.squads[id].members[0]
 soldier.position=Vector3(8,0,51); soldier.shield=0.0; soldier.shield_time=0.0
 cover.tick(.01)
 check(soldier.shield==0.0,"Distant roster member does not receive remote shield")
 var traveled:=0.0
 var previous: Vector3=soldier.position
 for frame in 150:
  game.squads._move_member(soldier,item.position,.05)
  traveled+=previous.distance_to(soldier.position);previous=soldier.position
  cover.tick(.05)
  if soldier.shield>0.0: break
 check(traveled>4.0 and soldier.position.distance_to(item.position)<=4.8 and soldier.shield==20.0 and soldier.shield_time==4.0,"Real troop movement enters radius and receives actual finite shield")
 soldier.tick(1.0); var remaining: float=soldier.shield_time
 cover.tick(.05)
 check(soldier.shield_time==remaining,"Remaining shield duration is never refreshed")
 soldier.tick(5.0);cover.tick(.05)
 check(soldier.shield==0.0,"Same troop cannot claim shield a second time")
 var protected: BattleUnit=game.squads.squads[id].members[1]
 protected.position=item.position; protected.shield=50.0;protected.shield_time=2.0
 cover.tick(.05)
 check(protected.shield==50.0 and protected.shield_time==2.0,"Existing shield and duration are preserved verbatim")
 var fake: BattleUnit=load("res://scripts/unit.gd").new()
 game.squads.add_child(fake);fake.setup("minion",0);fake.position=item.position
 cover.tick(.05)
 check(fake.shield==0.0,"Unrostered friendly cannot receive shield")
 fake.queue_free()
 var state: Dictionary=cover.snapshot(item)
 game.phase="paused";cover.tick(100.0)
 check(cover.snapshot(item).remaining==state.remaining,"Pause freezes snapshot service clock")
 game.phase="day"
 check(cover.snapshot(item).remaining==state.remaining,"Pause leaves actual service time frozen")
 game.districts.damage(0,100000.0)
 protected.shield=0.0;protected.shield_time=0.0;cover.tick(.05)
 check(protected.shield==20.0,"Committed service survives workshop destruction")
 game.phase="night";cover.tick(.05)
 var third: BattleUnit=game.squads.squads[id].members[2]
 third.position=item.position;cover.tick(.05)
 check(third.shield==20.0 and cover.snapshot(item).paid,"Cross-night service keeps original remaining duration")
 item.serial=int(item.serial)+1
 check(not cover.snapshot(item).paid,"Refreshed serial cannot inherit prior purchase")
 game.phase="day"
 item.remaining=2.0
 check(not cover.purchase(item).ok,"Destroyed workshop rejects fresh incarnation")
 check(game.build_structure_at(Vector3(-7,5,-8.5),"workshop"),"Workshop can rebuild at original footprint")
 game.hero.position=item.position
 check(cover.purchase(item).ok and cover.snapshot(item).remaining==2.0,"New incarnation cannot extend original two-second lamp remainder")
 game.shutting_down=true
 original=game.scrap;item.serial=int(item.serial)+1
 check(not cover.purchase(item).ok and game.scrap==original,"Shutdown refuses payment on newly changed source")
 game.shutting_down=false
 var old_node: Node3D=item.node
 item.node=Node3D.new();events.add_child(item.node);item.node.position=item.position
 check(not cover.snapshot(item).paid,"Replacement node cannot inherit paid source identity")
 old_node.queue_free()
 check(cover.purchase(item).ok,"Legitimate replacement source can be purchased once")
 var fourth_id: int=game.squads._create_squad("hauler",Vector3(8,0,42))
 var fourth: BattleUnit=game.squads.squads[fourth_id].members[0]
 fourth.position=item.position+Vector3(0,3,0);cover.tick(.05)
 check(fourth.shield==0.0,"Wrong terrain layer cannot receive shield")
 fourth.position=item.position
 fourth.alive=false;cover.tick(.05)
 check(fourth.shield==0.0,"Dead actual roster member cannot receive shield")
 fourth.alive=true
 var group: Dictionary=game.squads.squads[fourth_id]
 group.members.erase(fourth);cover.tick(.05)
 check(fourth.shield==0.0,"Removed actual member cannot receive shield")
 group.members.append(fourth)
 fourth.position=item.position
 cover.tick(.05)
 check(fourth.shield==20.0,"Real owned hauler receives same finite service")
 # Bind a fresh paid lamp across the actual east wall, within planar radius.
 item.serial=int(item.serial)+1
 var inner: float=preload("res://scripts/outpost_layout.gd").FORT_INNER
 item.position=Vector3(inner-1.0,5,0);item.node.position=item.position
 game.hero.position=item.position
 check(cover.purchase(item).ok,"Fresh wall-side lamp remains a valid paid source")
 fourth.shield=0.0;fourth.shield_time=0.0
 fourth.position=Vector3(inner+1.0,0,0);fourth.position.y=game.outpost_height(fourth.position)
 cover.tick(.05)
 check(fourth.shield==0.0,"Real castle wall prevents nearby troop cover through terrain")
 events.begin_cooling(item,50.0)
 check(cover.bindings.is_empty(),"Cooling immediately releases original source and per-member bookkeeping")
 cover.tick(.05)
 check(cover.snapshot(item).is_empty(),"Retired original lamp cannot deliver shields")
 await game.prepare_shutdown()
 check(cover.bindings.is_empty(),"Actual shutdown clears every paid source binding")
 game.queue_free();current_scene=null
 for frame in 4:await process_frame
 await create_timer(.25,true,false,true).timeout
 print("NIGHTFALL_WAYLIGHT_COVER_OK checks=%d failures=%d" % [checks,failures])
 quit(0 if failures==0 else 1)
