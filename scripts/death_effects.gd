class_name NightDeathEffects
extends Node3D
## Real exported creatures fall, settle and return to ash. Gameplay removes the host
## immediately; only the material-preserving visual and its joints survive here.

const MAX_CORPSES := 12
const CONTACT_GAP := .018
var corpses: Array[Dictionary] = []
var game: Node
var rng := RandomNumberGenerator.new()
var ash_mesh: BoxMesh
var ash_material: StandardMaterial3D
var shadow_material: StandardMaterial3D
var support_cache: Dictionary = {}

func setup(owner_game: Node) -> void:
	game=owner_game
	rng.seed=281003
	ash_mesh=BoxMesh.new();ash_mesh.size=Vector3.ONE
	ash_material=StandardMaterial3D.new()
	ash_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ash_material.vertex_color_use_as_albedo=true
	ash_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	ash_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	ash_material.albedo_color=Color.WHITE
	shadow_material=StandardMaterial3D.new()
	shadow_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.albedo_color=Color(.018,.025,.026,.18)
	shadow_material.no_depth_test=false

func spawn(unit: BattleUnit, source_position: Vector3) -> void:
	if not is_instance_valid(unit) or not is_instance_valid(unit.visual):return
	if ash_mesh==null:setup(get_parent())
	while corpses.size()>=MAX_CORPSES:_remove(0)
	var start:=unit.global_position
	var threat: String=unit.get_meta("threat","stalker")
	var heavy:=threat=="breaker"
	var moth:=threat=="light_eater"
	var runner:=threat=="runner"
	var body:=Node3D.new();body.name="Fallen_%s" % threat
	add_child(body);body.global_position=start
	var model:=unit.visual
	# Reparent the original instance rather than making a differently shaded copy.
	# Selection rings, damage/gameplay logic and lamp suppression remain on the host.
	model.reparent(body,true)
	var meshes: Array[MeshInstance3D] = []
	for child in model.find_children("*","MeshInstance3D",true,false):
		var mesh:=child as MeshInstance3D
		if mesh.mesh!=null:meshes.append(mesh)
	var joints: Array[Dictionary] = []
	for i in unit.legs.size():
		var limb:=unit.legs[i]
		if not is_instance_valid(limb) or not model.is_ancestor_of(limb):continue
		var side: float=-1.0 if i%2==0 else 1.0
		var fold:=Vector3(.62 if i<2 else -.54,side*.13,side*.39)
		joints.append({"node":limb,"start":limb.rotation,"target":fold,"delay":.012*float(i)})
	if is_instance_valid(unit.stalker_head) and model.is_ancestor_of(unit.stalker_head):
		joints.append({"node":unit.stalker_head,"start":unit.stalker_head.rotation,"target":Vector3(.42,0,.18),"delay":.05})
	for entry in [{"name":"MothWingLeft","side":-1.0},{"name":"MothWingRight","side":1.0}]:
		var wing:=model.find_child(entry.name,true,false) as Node3D
		if wing:
			joints.append({"node":wing,"start":wing.rotation,"target":Vector3(.15,0,float(entry.side)*1.05),"delay":0.0})
	var direction:=start-source_position;direction.y=0
	if direction.length_squared()<.0001:direction=Vector3(.7,0,.7)
	direction=direction.normalized()
	# A little side roll makes a four-legged silhouette visibly leave its live pose.
	var side_roll:=rng.randf_range(-.32,.32)
	direction=direction.rotated(Vector3.UP,side_roll)
	var axis:=Vector3(direction.z,0,-direction.x)
	var bounds:=_bounds(meshes)
	var center: Vector3=bounds.get_center()-start
	center.y=maxf(center.y,.45)
	var fall_duration:=.66 if heavy else (.31 if runner else (.56 if moth else .45))
	var duration:=2.50 if heavy else (1.78 if runner else (2.22 if moth else 2.12))
	var ash_node:=MultiMeshInstance3D.new();ash_node.name="DriftingAsh"
	var multimesh:=MultiMesh.new()
	multimesh.transform_format=MultiMesh.TRANSFORM_3D
	multimesh.use_colors=true;multimesh.mesh=ash_mesh
	multimesh.instance_count=24 if heavy else (20 if moth else 16)
	ash_node.multimesh=multimesh;ash_node.material_override=ash_material
	ash_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ash_node)
	var ash: Array[Dictionary] = []
	for i in multimesh.instance_count:
		var angle:=rng.randf_range(0,TAU)
		var radial:=Vector3(cos(angle),0,sin(angle))
		var bright:=i%5==0
		ash.append({"origin":Vector3.ZERO,"velocity":radial*rng.randf_range(.20,.68)+Vector3(0,rng.randf_range(.60,1.30),0),
			"offset":radial*rng.randf_range(.12,.64)+Vector3(0,rng.randf_range(.12,.45),0),
			"spin":rng.randf_range(-3.0,3.0),"angle":angle,"size":rng.randf_range(.055,.10),
			"delay":rng.randf_range(0,.18),"lifetime":rng.randf_range(.65,.95),
			"color":Color("d4a474") if bright else Color("8aabb0")})
		multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))
		multimesh.set_instance_color(i,Color(0,0,0,0))
	var shadow:=MeshInstance3D.new();shadow.name="FaintAshScuff"
	var disk:=CylinderMesh.new();disk.top_radius=.70 if heavy else .47;disk.bottom_radius=disk.top_radius;disk.height=.005;disk.radial_segments=24
	shadow.mesh=disk;shadow.material_override=shadow_material
	shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow);shadow.global_position=start+Vector3(0,.024,0)
	var corpse: Dictionary={"node":body,"visual":model,"meshes":meshes,"joints":joints,"ash_node":ash_node,"ash":ash,"shadow":shadow,
		"threat":threat,"time":0.0,"duration":duration,"fall_duration":fall_duration,"dissolve_start":duration-.83,
		"ground":start.y,"start_position":start,"source_position":source_position,"center":center,"axis":axis,
		"direction":direction,"angle":1.38 if heavy else (1.06 if moth else 1.48),"slide":.17 if heavy else (.40 if runner else .27),
		"min_clearance":_clearance(meshes,start.y),"initial_clearance":maxf(CONTACT_GAP,_clearance(meshes,start.y)),"alpha":1.0,"landed":false,"settled":false,"ash_started":false}
	corpses.append(corpse)

func tick(delta: float, phase: String) -> void:
	if phase=="ended":clear();return
	if phase=="paused" or phase=="draft":return
	if phase!="day" and phase!="night":return
	for i in range(corpses.size()-1,-1,-1):
		var corpse: Dictionary=corpses[i]
		if not is_instance_valid(corpse.node):_remove(i);continue
		corpse.time=float(corpse.time)+maxf(delta,0.0)
		if float(corpse.time)>=float(corpse.duration):_remove(i);continue
		_pose(corpse)
		_ash(corpse)

func _pose(corpse: Dictionary) -> void:
	if not corpse.settled:_fall(corpse)
	var age: float=corpse.time
	var p:=clampf(age/float(corpse.fall_duration),0,1)
	var dissolve:=smoothstep(float(corpse.dissolve_start),float(corpse.duration)-.06,age)
	corpse.alpha=1.0-dissolve
	for mesh: MeshInstance3D in corpse.meshes:
		if is_instance_valid(mesh):mesh.transparency=dissolve
	var shadow:=corpse.shadow as MeshInstance3D
	var point: Vector3=(corpse.node as Node3D).global_position
	point.y=_floor(point,float(corpse.ground))+.024
	shadow.global_position=point
	shadow.transparency=1.0-(.45+.55*smoothstep(0.0,.70,p))*(1.0-dissolve)
	shadow.visible=p>.2

func _fall(corpse: Dictionary) -> void:
	var age: float=corpse.time
	var fall: float=corpse.fall_duration
	var p:=clampf(age/fall,0,1)
	for joint: Dictionary in corpse.joints:
		var node:=joint.node as Node3D
		if not is_instance_valid(node):continue
		var joint_p:=clampf((age-float(joint.delay))/(fall*.74),0,1)
		node.rotation=(joint.start as Vector3).lerp(joint.target,smoothstep(0,1,joint_p))
	var after:=maxf(0.0,age-fall)
	var bounce:=sin(after*23.0)*exp(-after*13.0)*(.065 if corpse.threat=="breaker" else .10) if p>=1.0 and after<.35 else 0.0
	var angle:=float(corpse.angle)*p*p+bounce
	var basis:=Basis(corpse.axis,angle)
	var body:=corpse.node as Node3D
	body.global_basis=basis
	var center: Vector3=corpse.center
	body.global_position=(corpse.start_position as Vector3)+(corpse.direction as Vector3)*float(corpse.slide)*smoothstep(0,1,p)+center-basis*center
	# Use actual convex hull vertices rather than the empty corners of an AABB.
	# Imported curved shells otherwise hover when an imaginary corner hits first.
	var clearance:=_clearance(corpse.meshes,float(corpse.ground))
	var target_gap:=lerpf(float(corpse.initial_clearance),CONTACT_GAP,smoothstep(0,1,p))
	target_gap+=maxf(0.0,sin(after*23.0))*exp(-after*13.0)*(.025 if corpse.threat=="breaker" else .055) if p>=1.0 and after<.35 else 0.0
	body.global_position.y+=target_gap-clearance
	corpse.min_clearance=target_gap
	corpse.landed=p>=1.0
	# Terrain and detached joints are static after this final rest pose. Do not
	# resample hundreds of support points throughout the remaining ash lifetime.
	corpse.settled=p>=1.0 and after>=.35

func _ash(corpse: Dictionary) -> void:
	var age:=float(corpse.time)-float(corpse.dissolve_start)
	if age<0:return
	if not corpse.ash_started:
		corpse.ash_started=true
		var origin: Vector3=(corpse.node as Node3D).global_position
		origin.y=_floor(origin,float(corpse.ground))+.12
		for particle: Dictionary in corpse.ash:particle.origin=origin+particle.offset
	var mesh:=corpse.ash_node as MultiMeshInstance3D
	for i in corpse.ash.size():
		var particle: Dictionary=corpse.ash[i]
		var t:=maxf(0.0,age-float(particle.delay))
		var q:=clampf(t/float(particle.lifetime),0,1)
		var color: Color=particle.color
		color.a=smoothstep(0,.10,t)*(1.0-smoothstep(.30,1.0,q))
		if age<float(particle.delay):color.a=0.0
		var scale:=float(particle.size)*(1.0-.60*q)
		var basis:=Basis(Vector3(.3,.8,.5).normalized(),float(particle.angle)+t*float(particle.spin)).scaled(Vector3(scale,scale*.28,scale*.75))
		var position: Vector3=particle.origin+(particle.velocity as Vector3)*t+Vector3(sin(t*5+float(i))*.035,t*t*.16,0)
		mesh.multimesh.set_instance_transform(i,Transform3D(basis,mesh.to_local(position)))
		mesh.multimesh.set_instance_color(i,color)

func _bounds(meshes: Array[MeshInstance3D]) -> AABB:
	var bounds:=AABB()
	var first:=true
	for mesh: MeshInstance3D in meshes:
		var box:=mesh.get_aabb()
		for i in 8:
			var point:=mesh.global_transform*_corner(box,i)
			if first:bounds=AABB(point,Vector3.ZERO);first=false
			else:bounds=bounds.expand(point)
	return bounds

func _clearance(meshes: Array[MeshInstance3D], fallback: float) -> float:
	var clearance:=INF
	for mesh: MeshInstance3D in meshes:
		if not is_instance_valid(mesh):continue
		var transform:=mesh.global_transform
		for local_point: Vector3 in _support_points(mesh.mesh):
			var point:=transform*local_point
			clearance=minf(clearance,point.y-_floor(point,fallback))
	return 0.0 if is_inf(clearance) else clearance

func _support_points(mesh: Mesh) -> PackedVector3Array:
	if support_cache.has(mesh):return support_cache[mesh]
	# The cleaned, unsimplified hull keeps real mesh positions. Cache once per
	# shared imported Mesh (roughly 500-940 points per complete enemy), not per body
	# or animation frame. No collision node or physics body is created.
	var hull:=mesh.create_convex_shape(true,false)
	var points:=PackedVector3Array()
	if hull!=null:points=hull.points
	if points.is_empty():
		for surface in mesh.get_surface_count():
			points.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	support_cache[mesh]=points
	return points

func _corner(box: AABB, index: int) -> Vector3:
	return box.position+box.size*Vector3(float(index&1),float((index>>1)&1),float((index>>2)&1))

func _floor(point: Vector3, fallback: float) -> float:
	if is_instance_valid(game) and game.has_method("outpost_height"):return float(game.outpost_height(point))
	return fallback

func _remove(index: int) -> void:
	var corpse: Dictionary=corpses[index]
	for key in ["node","ash_node","shadow"]:
		if is_instance_valid(corpse[key]):corpse[key].queue_free()
	corpses.remove_at(index)

func clear() -> void:
	while not corpses.is_empty():_remove(corpses.size()-1)

func _exit_tree() -> void:
	clear()
	support_cache.clear()
