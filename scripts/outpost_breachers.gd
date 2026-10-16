extends RefCounted
## Single-hit armour conversion; ownership and normal weapon windup stay in the roster.
static func source_valid(roster: Node3D, source: BattleUnit) -> bool:
 var game: Node3D=roster.game
 return is_instance_valid(game) and game.squads==roster and not game.is_queued_for_deletion() and not game.shutting_down and not game.quitting and not game.restart_pending and not roster.is_queued_for_deletion() and roster._owns_member(source,roster._epoch) and source.is_inside_tree() and source.hp>0.0 and source.kind=="minion" and source.team==0 and String(source.get_meta("squad_kind",""))=="breacher"
static func legal(roster: Node3D, source: BattleUnit, target: BattleUnit) -> bool:
 if not source_valid(roster,source) or not roster._enemy(target) or target not in roster.game.enemies or not target.is_inside_tree() or target.hp<=0.0:return false
 var game: Node3D=roster.game
 var from: Vector3=source.position
 var to: Vector3=target.position
 if not from.is_finite() or not to.is_finite():return false
 var source_offset:=from.y-float(game.outpost_height(from))
 var target_offset:=to.y-float(game.outpost_height(to))
 if absf(source_offset)>.9 or absf(target_offset)>.9 or absf(source_offset-target_offset)>.9:return false
 return Vector2(from.x-to.x,from.z-to.z).length()<=source.attack_range and game.can_attack_line(from,to) and source_valid(roster,source) and is_instance_valid(target) and target in game.enemies and target.alive and not target.is_queued_for_deletion() and source.position==from and target.position==to
static func damage(source: BattleUnit, target: BattleUnit) -> float:
 var armour:=maxf(0.0,target.armor)
 return source.damage*(100.0+armour)/(100.0+armour*.4)
static func style(source: BattleUnit) -> void:
 # Keep imported skeleton references alive, hiding only its meshes. Vehicle
 # geometry is attached to visual root, outside animated arms and legs.
 for part in source.visual.find_children("*","MeshInstance3D",true,false):part.visible=false
 var hull:=Node3D.new();hull.name="BreacherVehicle";source.visual.add_child(hull)
 _box(hull,Vector3(1.08,.46,1.35),Vector3(0,.49,0),Color("476b73"))
 _box(hull,Vector3(.70,.34,.65),Vector3(0,.88,.12),Color("bba675"))
 _box(hull,Vector3(.19,.19,.80),Vector3(0,.86,-.48),Color("374a50"))
 _box(hull,Vector3(.26,.12,.08),Vector3(0,.87,-.90),Color("86e1ed"))
 for side in [-1,1]:
  for axle in [-.44,.44]:
   var wheel:=MeshInstance3D.new();var mesh:=CylinderMesh.new()
   mesh.top_radius=.29;mesh.bottom_radius=.29;mesh.height=.18;mesh.radial_segments=10
   wheel.mesh=mesh;wheel.rotation.z=PI*.5;wheel.position=Vector3(side*.56,.29,axle)
   wheel.material_override=BattleVisuals.material(Color("263237"),0.0);hull.add_child(wheel)
static func _box(root: Node3D,size: Vector3,point: Vector3,tint: Color) -> void:
 var part:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;part.mesh=mesh
 part.position=point;part.material_override=BattleVisuals.material(tint,.10);root.add_child(part)
