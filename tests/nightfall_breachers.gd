extends SceneTree
const Helper=preload("res://scripts/outpost_breachers.gd")
var game: Node3D
var checks:=0
var failures:=0
func _initialize() -> void:
 create_timer(120.0,true,false,true).timeout.connect(func():quit(2))
 call_deferred("run")
func check(ok: bool,message: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(message)
func build(kind: String) -> int:
 for z in range(-19,20,2):
  for x in range(-19,20,2):
   var row: Dictionary=game.construction.validity(Vector3(x,5,z),-1,kind)
   if row.valid and game.build_structure_at(row.point,kind):return game.districts.plots.size()-1
 check(false,"Legal paid building "+kind);return -1
func click(rect: Rect2) -> void:
 var point: Vector2=rect.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900)
 for pressed in [true,false]:
  var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
  root.push_input(event,true);await process_frame
func strike(source: BattleUnit,target: BattleUnit) -> void:
 source.attack_timer=0;source.attack_queued=false
 game.squads._attack(source,.05,target)
 check(source.attack_queued,"Actual normal weapon begins windup")
 source.tick(.46);game.squads._attack(source,.05,target)
func run() -> void:
 game=load("res://scenes/nightfall.tscn").instantiate();game.archive.enabled=false;root.add_child(game);current_scene=game
 await process_frame
 game.set_process(false)
 while game.phase=="draft":game.choose_card(0)
 game.phase="day";game.phase_time=10000.0;game.scrap=5000
 var squads: Node3D=game.squads
 var wallet: int=game.scrap
 check(not squads.enqueue("breacher").ok and game.scrap==wallet,"Missing technology cannot pay or train")
 var base:=build("barracks");build("workshop");build("laboratory");var armory:=build("armory")
 check(squads.training_eligibility("breacher").available,"Actual live technology unlocks machine")
 game.districts.plots[armory].hp=0
 wallet=game.scrap
 check(not squads.enqueue("breacher").ok and game.scrap==wallet,"Destroyed armory closes training")
 game.districts.plots[armory].hp=600
 game.scrap=179
 check(not squads.enqueue("breacher").ok and game.scrap==179,"Insufficient light cannot enqueue")
 game.scrap=2000
 var sidebar=game.hud.production_sidebar
 await click(sidebar.page_rect(1));await click(sidebar.page_rect(1))
 check(sidebar.page==2 and sidebar.kinds()==["breacher"],"Actual next-page clicks show third page")
 wallet=game.scrap;var count: int=squads.squads.size()
 await click(sidebar.kind_rect(0))
 check(game.scrap==wallet-180 and squads.squads.size()==count,"Third-page click pays without spawning")
 check(squads.training_queues[base][0].remaining==14.0,"Actual queue requires fourteen seconds")
 game.phase="paused";squads.advance(50)
 check(squads.squads.size()==count and squads.training_queues[base][0].remaining==14.0,"Pause freezes queue")
 game.phase="day";squads.advance(13.9)
 check(squads.squads.size()==count,"No early mechanical unit")
 squads.advance(.11)
 check(squads.squads.size()==count+1,"Actual training completes")
 wallet=game.scrap;check(squads.enqueue("breacher",base).ok,"Second paid order accepted")
 check(squads.cancel_training(base).ok and game.scrap==wallet,"Cancel refunds actual exact cost")
 var group: Dictionary=squads.squads.back();var source: BattleUnit=group.members[0]
 check(group.members.size()==3 and is_equal_approx(source.max_hp,180*squads.health_multiplier) and source.armor==10 and source.speed==3.9,"Three real mechanical members use designed stats")
 check(source.visual.find_child("BreacherVehicle",true,false)!=null,"Mechanical body exists")
 var visible_old:=0
 for part in source.visual.find_children("*","MeshInstance3D",true,false):
  if not source.visual.get_node("BreacherVehicle").is_ancestor_of(part) and part.visible:visible_old+=1
 check(visible_old==0,"Imported humanoid meshes remain hidden")
 var open:=Vector3(20,0,30);source.position=open
 var target: BattleUnit=game.spawn_creature(false)
 target.position=open+Vector3(0,0,3);target.hp=10000;target.max_hp=10000;target.shield=0
 for armor in [0.0,50.0,200.0]:
  target.armor=armor;var hp: float=target.hp
  strike(source,target)
  check(absf(hp-target.hp-30.0*100.0/(100.0+armor*.4))<.001,"Actual armour-adjusted damage "+str(armor))
  check(target.armor==armor,"Attack never changes permanent armour")
 source.attack_timer=0;source.attack_queued=false;game.squads._attack(source,.05,target)
 var before: float=target.hp;target.position=open+Vector3(0,0,8);source.tick(.5);game.squads._attack(source,.05,target)
 check(target.hp==before and not source.attack_queued,"Target leaving range cancels actual windup")
 target.position=open+Vector3(0,0,3);target.position.y=3
 check(not Helper.legal(squads,source,target),"Airborne target cannot be shot")
 target.position.y=-.8;source.position.y=.8
 check(not Helper.legal(squads,source,target),"Opposite ground offsets cannot bypass height limit")
 source.position=open;target.position=Vector3.INF
 check(not Helper.legal(squads,source,target),"Nonfinite world point rejected")
 source.position=Vector3(0,5,-20);target.position=Vector3(0,0,-24)
 check(not Helper.legal(squads,source,target),"Actual castle wall blocks short-range shot")
 source.position=open;target.position=open+Vector3(0,0,3)
 var armored: BattleUnit=game.spawn_creature(false)
 armored.position=open+Vector3(2,0,2);armored.armor=200;armored.hp=1000;armored.max_hp=1000
 check(squads._pick_enemy(source)==armored,"In-range positive armour is preferred automatically")
 game.focus_target=target;game.focus_time=3.0
 check(squads._pick_enemy(source)==target,"Actual C focus priority precedes armour preference")
 game.focus_target=null;game.focus_time=0.0
 source.attack_timer=0;source.attack_queued=false;squads._attack(source,.05,target)
 check(source.target==target,"Explicit in-range designated enemy precedes automatic armour preference")
 source.tick(.5);game.phase="paused";before=target.hp;squads._attack(source,.05,target)
 check(target.hp==before and not source.attack_queued,"Pause rejects pending actual shot")
 game.phase="day"
 source.attack_timer=0;source.attack_queued=false;squads._attack(source,.05,target)
 squads.selected_ids.assign([int(group.id)])
 check(squads.command_move(open+Vector3(1,0,0)).ok and not source.attack_queued,"Original public move cancels uncommitted mechanical shot")
 var original_slot: BattleUnit=group.members[0]
 group.members[0]=group.members[1]
 check(not Helper.source_valid(squads,original_slot),"Removed original member identity cannot fire")
 group.members[0]=original_slot
 game.enemies.erase(target)
 check(not Helper.legal(squads,source,target),"Detached enemy roster cannot be shot")
 game.enemies.append(target)
 var wounded_hp: float=source.hp
 source.hurt(33,target)
 check(absf(wounded_hp-source.hp-30)<.001,"Mechanical unit takes actual armour-reduced damage")
 squads.selected_ids.assign([int(group.id)])
 for member: BattleUnit in group.members:member.position=open+Vector3((int(member.get_meta("squad_slot",0))-1)*1.2,0,0)
 check(squads.command_move(open+Vector3(6,0,0)).ok,"Original move command accepts machines")
 var start: Vector3=source.position
 for frame in 80:squads.advance(.05)
 check(source.position.distance_to(start)>2,"Real squad advance moves machine")
 source.hurt(10000,target)
 check(not source.alive and squads.refill_cost(group.id)==48,"Real death quotes 48-light replacement")
 wallet=game.scrap
 check(squads.refill(group.id).ok and game.scrap==wallet-48,"Original paid replacement restores slot")
 var replacement: BattleUnit=group.members[0]
 check(replacement!=source and replacement.alive and is_equal_approx(replacement.max_hp,180*squads.health_multiplier),"Replacement is new valid machine")
 check(not Helper.source_valid(squads,source),"Dead retired source cannot fire")
 check(float(squads.veterancy.member_snapshot(replacement).xp)==0.0,"Paid replacement starts with zero experience")
 replacement.position=open;target.position=open+Vector3(0,0,3);target.hp=25;target.max_hp=25;target.armor=0
 squads.veterancy.observe_enemies();strike(replacement,target)
 check(float(squads.veterancy.member_snapshot(replacement).xp)>0,"Actual finite HP kill contributes original growth")
 var retained_xp: float=squads.veterancy.member_snapshot(replacement).xp
 var other: BattleUnit=group.members[1]
 other.hurt(100000,game.hero)
 check(squads.refill(group.id).ok and float(squads.veterancy.member_snapshot(replacement).xp)==retained_xp and retained_xp>0.0,"Other-slot paid refill preserves surviving machine experience")
 wallet=game.scrap
 check(squads.enqueue("breacher",base).ok,"Real base holds another paid order")
 game.districts.damage(base,100000)
 squads.refresh_barracks()
 check(game.scrap==wallet and squads.training_queues.get(base,[]).is_empty(),"Destroyed original base refunds exact pending mechanical order")
 game.shutting_down=true
 check(not Helper.source_valid(squads,replacement),"Shutdown rejects weapon source")
 await game.prepare_shutdown();game.queue_free();current_scene=null
 for frame in 4:await process_frame
 await create_timer(.25,true,false,true).timeout
 print("NIGHTFALL_BREACHERS_OK checks=%d failures=%d" % [checks,failures]);quit(0 if failures==0 else 1)
