extends SceneTree
var game: Node3D
var checks:=0
var failures:=0
func _initialize() -> void:
 create_timer(90.0,true,false,true).timeout.connect(func():quit(2))
 call_deferred("run")
func check(ok: bool,message: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(message)
func same(a: Basis,b: Basis) -> bool:return a.is_equal_approx(b)
func run() -> void:
 game=load("res://scenes/nightfall.tscn").instantiate();game.archive.enabled=false;root.add_child(game);current_scene=game
 await process_frame;game.set_process(false)
 while game.phase=="draft":game.choose_card(0)
 game.phase="day";game.phase_time=10000.0
 var roster: Node3D=game.squads
 var origin:=Vector3(20,0,30)
 var id: int=roster._create_squad("breacher",origin)
 var squad: Dictionary=roster.squads[id]
 var source: BattleUnit=squad.members[0]
 var hull: Node3D=source.visual.get_node("BreacherVehicle")
 var wheel: MeshInstance3D=hull.get_node("Wheel_-1_-44")
 var gun: Node3D=hull.get_node("GunSlide")
 for child in hull.get_children():
  if child is MeshInstance3D and String(child.name).begins_with("Wheel_"):
   var spoke: MeshInstance3D=child.get_child(0)
   var offset: Vector3=spoke.global_position-child.global_position
   check(offset.x*child.position.x>0.0,"Every wheel spoke faces outward on its actual axle")
 roster.selected_ids.assign([id])
 check(roster.command_move(origin+Vector3(6,0,0)).ok,"Production move order accepted")
 var before: Vector3=source.position
 var basis:=wheel.basis
 roster.advance(.05)
 var distance:=Vector2(source.position.x-before.x,source.position.z-before.z).length()
 var expected:=basis.rotated(basis.y.normalized(),distance/(.29*absf(source.visual.global_basis.get_scale().x)))
 check(distance>0.0 and same(wheel.basis,expected),"Real roster movement turns wheel exactly by distance / world radius")
 check(source.visual.position.y==0.0,"Mechanical body does not use infantry hopping")
 for frame in 160:roster.advance(.05)
 before=source.position;basis=wheel.basis
 for frame in 10:roster.advance(.05)
 check(source.position.distance_to(before)<.001 and same(wheel.basis,basis),"Stationary vehicle wheels do not spin")
 check(not roster.command_move(Vector3.INF).ok,"Nonfinite destination is rejected by production movement")
 for frame in 10:roster.advance(.05)
 check(source.position.distance_to(before)<.001 and same(wheel.basis,basis),"Rejected move cannot spin stationary wheels")
 var target: BattleUnit=game.spawn_creature(false)
 target.position=source.position+Vector3(0,0,3);target.hp=10000;target.max_hp=10000;target.armor=0;target.shield=0
 check(roster.command_attack(target).ok,"Production attack command accepted")
 source.attack_timer=0.0
 roster.advance(.05)
 check(source.attack_queued and gun.position.z==0.0 and target.hp==10000,"Real attack windup does not recoil or hit early")
 var struck:=false
 for frame in 15:
  roster.advance(.05)
  if gun.position.z>0.0:struck=true;break
 check(struck and target.hp<10000,"Real committed attack starts cannon recoil with actual damage")
 var recoil: float=gun.position.z;basis=wheel.basis;before=source.position
 for phase in ["paused","draft"]:
  game.phase=phase;roster.advance(5.0)
  check(gun.position.z==recoil and same(wheel.basis,basis) and source.position==before,"Pause / selection freeze recoil, wheel and movement")
 game.phase="day";source.attack_timer=100.0
 roster.advance(.05)
 check(gun.position.z<recoil,"Resume recovers recoil using game time")
 for frame in 10:roster.advance(.05)
 check(gun.position.z==0.0,"Cannon returns exactly to rest")
 basis=wheel.basis
 for member: BattleUnit in squad.members:member.position+=Vector3(60,0,0)
 roster.advance(.05)
 check(same(wheel.basis,basis),"Relocation never accumulates giant wheel rotation")
 var shield_id: int=roster._create_squad("shield",origin)
 var shield: BattleUnit=roster.squads[shield_id].members[0]
 roster.selected_ids.assign([shield_id]);roster.command_move(origin+Vector3(5,0,0))
 roster.advance(.05);roster.advance(.05)
 check(shield.moving and shield.visual.position.y>0.0,"Original non-mechanical infantry hopping remains unchanged")
 # Controlled relocation into an actual paid footprint exercises the blocked
 # production movement step, rather than replacing path or traversal methods.
 game.scrap=1000
 var blocker:=Vector3.INF
 for z in range(-18,19,2):
  for x in range(-18,19,2):
   var placement: Dictionary=game.construction.validity(Vector3(x,5,z),-1,"barracks")
   if placement.valid and game.build_structure_at(placement.point,"barracks"):
    blocker=placement.point;break
  if blocker.is_finite():break
 check(blocker.is_finite(),"Actual paid navigation-blocking flag fixture exists")
 source.position=blocker;source.path.clear();source.path_timer=0
 roster.selected_ids.assign([id]);roster.command_move(origin)
 roster.advance(.05)
 before=source.position;basis=wheel.basis
 roster.advance(.05)
 check(source.moving and source.position==before and same(wheel.basis,basis),"Real traversal blocked by footprint causes no wheel spin despite movement intent")
 await game.prepare_shutdown();game.queue_free();current_scene=null
 for frame in 4:await process_frame
 await create_timer(.25,true,false,true).timeout
 print("NIGHTFALL_BREACHER_ANIMATION_OK checks=%d failures=%d" % [checks,failures]);quit(0 if failures==0 else 1)
