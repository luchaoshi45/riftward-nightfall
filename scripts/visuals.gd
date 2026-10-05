class_name BattleVisuals
extends RefCounted
static var painted_cache: Dictionary = {}

static func paint_model(root: Node, only_cloth: bool = false) -> void:
	if root is MeshInstance3D:
		for index in root.mesh.get_surface_count():
			var original = root.mesh.surface_get_material(index)
			if not original is StandardMaterial3D or original.emission_enabled: continue
			var label: String = original.resource_name.to_lower()
			var cloth := "cloth" in label or "woven" in label or "cloak" in label or "velvet" in label
			if only_cloth and not cloth: continue
			var key: String = original.resource_path + original.resource_name
			if not painted_cache.has(key):
				var mat := ShaderMaterial.new()
				mat.shader = load("res://assets/shaders/painted_surface.gdshader")
				mat.set_shader_parameter("base_color", original.albedo_color)
				var foliage := "foliage" in label or "canopy" in label
				mat.set_shader_parameter("surface_kind", 2.0 if foliage else (1.0 if cloth else 0.0))
				mat.set_shader_parameter("metal", minf(original.metallic, .25))
				painted_cache[key] = mat
			root.set_surface_override_material(index, painted_cache[key])
	for child in root.get_children(): paint_model(child, only_cloth)
## Shared low-poly geometry and short-lived combat effects.

static func material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.88
	if glow > 0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	return mat

static func box(parent: Node3D, pos: Vector3, dimensions: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	node.material_override = mat
	parent.add_child(node)
	node.position = pos
	return node

static func ring(parent: Node3D, pos: Vector3, radius: float, color: Color, width: float = 0.06) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(0.02, radius - width)
	mesh.outer_radius = radius + width
	mesh.rings = 48
	mesh.ring_segments = 6
	node.mesh = mesh
	var mat := material(color, 0.28)
	# Markers describe selection and range; their brightness should not react
	# to moving shadow maps or throw a second thin shadow onto the ground.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.position = pos
	return node

static func burst(parent: Node3D, pos: Vector3, radius: float, color: Color, duration: float = 0.4) -> void:
	sparks(parent,pos+Vector3.UP*.3,color,12)
	var node := ring(parent, pos + Vector3.UP * 0.12, radius, color, 0.13)
	node.scale = Vector3(0.15, 1, 0.15)
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3.ONE, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(node.queue_free)

## The lamp's overload is a single, readable blast. Its final rim matches the
## damage radius, while the brief point light gives it a presence in darkness.
static func lantern_inferno(parent: Node3D, pos: Vector3, radius: float, scene_light: bool = true) -> void:
	var blast := Node3D.new()
	blast.name = "LanternInferno"
	parent.add_child(blast)
	blast.position = pos + Vector3(0, 0.13, 0)

	var ground_mat := ShaderMaterial.new()
	ground_mat.shader = load("res://assets/shaders/lantern_inferno.gdshader")
	var opacity_scale := 1.0 if scene_light else .14
	ground_mat.set_shader_parameter("opacity",opacity_scale)
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2.ONE * radius * 2.0
	var ground := MeshInstance3D.new()
	ground.name = "InfernoGroundGlow"
	ground.mesh = ground_mesh
	ground.material_override = ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blast.add_child(ground)
	ground.position.y = 0.025
	ground.scale = Vector3(0.08, 1.0, 0.08)

	var rim_color := Color(1.0, 0.68, 0.26, 0.95)
	var rim_mat := material(rim_color, 2.8)
	rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var rim := ring(blast, Vector3(0, 0.085, 0), radius, rim_color, 0.13)
	rim.name = "InfernoDamageBoundary"
	rim.material_override = rim_mat
	rim.scale = Vector3(0.06, 1.0, 0.06)

	var inner_color := Color(1.0, 0.40, 0.10, 0.63 if scene_light else .25)
	var inner_mat := material(inner_color, 1.8)
	inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var inner := ring(blast, Vector3(0, 0.11, 0), radius * 0.63, inner_color, 0.12)
	inner.name = "InfernoInnerShockwave"
	inner.material_override = inner_mat
	inner.scale = Vector3(0.08, 1.0, 0.08)

	var tongue_color := Color(1.0, 0.54, 0.15, 0.72 if scene_light else .30)
	var tongue_mat := material(tongue_color, 1.9)
	tongue_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tongue_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tongue_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tongues := Node3D.new()
	tongues.name = "InfernoFlameTongues"
	blast.add_child(tongues)
	tongues.scale = Vector3(0.05, 1.0, 0.05)
	for i in range(12):
		var tongue := sector_band(radius * 0.12, radius * (0.77 + 0.06 * float(i % 3)), 0.095, tongue_mat, true)
		tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tongues.add_child(tongue)
		tongue.rotation.y = float(i) * TAU / 12.0 + float(i % 3) * 0.08
		tongue.position.y = 0.055 + float(i % 2) * 0.008

	var flare_color := Color(1.0, 0.84, 0.49, 0.78 if scene_light else .40)
	var flare_mat := material(flare_color, 3.4)
	flare_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flare_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flare_mesh := SphereMesh.new()
	flare_mesh.radius = 1.0
	flare_mesh.height = 2.0
	flare_mesh.radial_segments = 16
	flare_mesh.rings = 8
	var flare := MeshInstance3D.new()
	flare.name = "InfernoFlash"
	flare.mesh = flare_mesh
	flare.material_override = flare_mat
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blast.add_child(flare)
	flare.position.y = 1.4
	flare.scale = Vector3(0.35, 1.7, 0.35)

	var light := OmniLight3D.new()
	light.name = "InfernoFlashLight"
	light.light_color = Color("ff9c42")
	light.light_energy = 5.0
	light.omni_range = maxf(9.0, radius * 1.5)
	light.shadow_enabled = false
	if scene_light:
		blast.add_child(light)
		light.position.y = 2.2
	else:
		light.free()
		# Luminous particles are not solid occluders for the actual skill lamp.
		for mesh in blast.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	sparks(parent, pos + Vector3.UP * 0.5, Color("ffd084"), 42)
	sparks(parent, pos + Vector3.UP * 0.4, Color("ed672d"), 24)
	var tween := blast.create_tween().set_parallel(true)
	tween.tween_property(ground, "scale", Vector3.ONE, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(rim, "scale", Vector3.ONE, 0.40).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(inner, "scale", Vector3.ONE, 0.27).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(tongues, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(tongues, "rotation:y", 0.16, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(flare, "scale", Vector3(1.1, 2.4, 1.1), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if scene_light:
		tween.tween_property(light, "light_energy", 0.0, 0.70).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_method(func(value: float) -> void: ground_mat.set_shader_parameter("opacity", value * opacity_scale), 1.0, 0.0, 0.31)
	tween.tween_property(rim_mat, "albedo_color", Color(rim_color.r, rim_color.g, rim_color.b, 0.0), 0.31)
	tween.tween_property(inner_mat, "albedo_color", Color(inner_color.r, inner_color.g, inner_color.b, 0.0), 0.31)
	tween.tween_property(tongue_mat, "albedo_color", Color(tongue_color.r, tongue_color.g, tongue_color.b, 0.0), 0.31)
	tween.tween_property(flare_mat, "albedo_color", Color(flare_color.r, flare_color.g, flare_color.b, 0.0), 0.22)
	tween.tween_property(flare, "scale", Vector3(0.08, 0.08, 0.08), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(blast.queue_free)

static func breaker_slam(parent: Node3D, pos: Vector3) -> void:
	var slam:=Node3D.new()
	slam.name="BreakerSlam"
	parent.add_child(slam)
	slam.position=pos+Vector3(0,.22,0)
	var cracks:=material(Color("f5a456"),1.8)
	cracks.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var rubble:=material(Color("3d332b"))
	for i in range(8):
		var angle:=float(i)*TAU/8.0+.17
		var direction:=Vector3(sin(angle),0,cos(angle))
		var length:=2.1+float(i%3)*.28
		var fissure:=box(slam,direction*(length*.52),Vector3(.1,.025,length),cracks)
		fissure.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fissure.rotation.y=angle
		var shard:=box(slam,direction*(length*.95)+Vector3(0,.04,0),Vector3(.3,.13,.36),rubble)
		shard.rotation.y=angle*.7
	var inner:=ring(slam,Vector3(0,.04,0),.9,Color("ffb66b"),.12)
	inner.name="BreakerShockwave"
	var inner_glow:=material(Color("ffb66b"),2.5)
	inner_glow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	inner.material_override=inner_glow
	var outer:=ring(slam,Vector3(0,.055,0),2.25,Color("b9885d"),.16)
	var outer_glow:=material(Color("c9895a"),1.1)
	outer_glow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	outer.material_override=outer_glow
	var flash:=MeshInstance3D.new()
	flash.name="BreakerImpactFlash"
	var flash_mesh:=SphereMesh.new()
	flash_mesh.radius=.55
	flash_mesh.height=1.1
	flash.mesh=flash_mesh
	flash.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flash_mat:=material(Color(1.0,.55,.26,.62),2.0)
	flash_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.material_override=flash_mat
	slam.add_child(flash)
	flash.position=Vector3(0,1.0,0)
	inner.scale=Vector3(.15,1,.15)
	outer.scale=Vector3(.15,1,.15)
	sparks(parent,pos+Vector3.UP*.3,Color("c9aa80"),16)
	var tween:=slam.create_tween().set_parallel(true)
	tween.tween_property(inner,"scale",Vector3.ONE,.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(outer,"scale",Vector3.ONE,.43).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash,"scale",Vector3(.08,.08,.08),.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(slam,"scale",Vector3(1.35,.1,1.35),.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(slam.queue_free)

static func sparks(parent: Node3D, point: Vector3, color: Color, count: int=8) -> void:
	var particles := GPUParticles3D.new()
	particles.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.one_shot=true
	particles.amount=count
	particles.lifetime=.65
	particles.explosiveness=1.0
	var process := ParticleProcessMaterial.new()
	process.direction=Vector3.UP
	process.spread=75
	process.initial_velocity_min=2
	process.initial_velocity_max=4
	process.gravity=Vector3(0,-5,0)
	process.scale_min=.025
	process.scale_max=.085
	particles.process_material=process
	var mesh := SphereMesh.new()
	mesh.radius=1
	mesh.height=2
	mesh.radial_segments=6
	mesh.rings=3
	mesh.material=material(color,2.0)
	particles.draw_pass_1=mesh
	parent.add_child(particles)
	particles.position=point
	particles.emitting=true
	particles.finished.connect(particles.queue_free)

static func beam(parent: Node3D, from: Vector3, to: Vector3, color: Color, width: float = 0.06) -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = width
	mesh.bottom_radius = width
	mesh.height = maxf(0.01, from.distance_to(to))
	mesh.radial_segments = 6
	node.mesh = mesh
	var mat := material(color, 0.7)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.position = (from + to) * 0.5
	var direction := (to - from).normalized()
	if absf(direction.dot(Vector3.UP)) < 0.999:
		node.quaternion = Quaternion(Vector3.UP, direction)
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3(0.01, 1, 0.01), 0.19)
	tween.tween_callback(node.queue_free)

static func tower_shot(parent: Node3D, from: Vector3, to: Vector3, level: int) -> void:
	var distance:=from.distance_to(to)
	if distance<.05:return
	var shot:=Node3D.new()
	shot.name="TowerShot"
	parent.add_child(shot)
	shot.position=(from+to)*.5
	var direction:=(to-from).normalized()
	if absf(direction.dot(Vector3.UP))<.999:shot.quaternion=Quaternion(Vector3.UP,direction)
	var beam_mesh:=CylinderMesh.new()
	beam_mesh.top_radius=.13+float(level)*.025
	beam_mesh.bottom_radius=beam_mesh.top_radius
	beam_mesh.height=distance
	beam_mesh.radial_segments=8
	var halo:=MeshInstance3D.new()
	halo.name="AmberHalo"
	halo.mesh=beam_mesh
	halo.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo_mat:=material(Color(1.0,.53,.18,.22),.6)
	halo_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.material_override=halo_mat
	shot.add_child(halo)
	var core_mesh:=CylinderMesh.new()
	core_mesh.top_radius=.037+float(level)*.009
	core_mesh.bottom_radius=core_mesh.top_radius
	core_mesh.height=distance
	core_mesh.radial_segments=8
	var core:=MeshInstance3D.new()
	core.name="BrightCore"
	core.mesh=core_mesh
	core.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core_mat:=material(Color("ffeac0"),1.35)
	core_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override=core_mat
	shot.add_child(core)
	var muzzle:=MeshInstance3D.new()
	muzzle.name="MuzzleFlash"
	var flash_mesh:=SphereMesh.new()
	flash_mesh.radius=.21+float(level)*.045
	flash_mesh.height=flash_mesh.radius*2.0
	muzzle.mesh=flash_mesh
	muzzle.material_override=core_mat
	muzzle.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(muzzle)
	muzzle.position=from
	var impact:=ring(parent,to-Vector3(0,.85,0),1.18+float(level)*.13,Color("f6ad65"),.11)
	impact.name="TowerImpact"
	impact.scale=Vector3(.2,1,.2)
	var tween:=shot.create_tween().set_parallel(true)
	tween.tween_property(shot,"scale",Vector3(.02,1,.02),.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(muzzle,"scale",Vector3.ZERO,.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(impact,"scale",Vector3.ONE,.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(shot.queue_free)
	tween.tween_callback(muzzle.queue_free)
	tween.tween_callback(impact.queue_free)

static func sector_band(inner_radius: float, outer_radius: float, half_angle: float, mat: Material, tapered: bool=false) -> MeshInstance3D:
	var vertices:=PackedVector3Array()
	var indices:=PackedInt32Array()
	var segments:=28
	for i in range(segments+1):
		var fraction:=float(i)/float(segments)
		var angle: float=-half_angle+fraction*half_angle*2.0
		var inner:=inner_radius
		var outer:=outer_radius
		if tapered:
			var midpoint:=(inner_radius+outer_radius)*.5
			var width:=(outer_radius-inner_radius)*.5*pow(maxf(.015,sin(fraction*PI)),.7)
			inner=midpoint-width
			outer=midpoint+width
		vertices.append(Vector3(sin(angle)*inner,0,-cos(angle)*inner))
		vertices.append(Vector3(sin(angle)*outer,0,-cos(angle)*outer))
	for i in segments:
		var n:=i*2
		indices.append_array(PackedInt32Array([n,n+1,n+2,n+1,n+3,n+2]))
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node:=MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=mat
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func slash_arc(parent: Node3D, origin: Vector3, direction: Vector3) -> void:
	var slash:=Node3D.new()
	slash.name="SlashArc"
	parent.add_child(slash)
	slash.position=origin+Vector3(0,.22,0)
	var flat:=Vector3(direction.x,0,direction.z).normalized()
	var yaw:=atan2(-flat.x,-flat.z)
	slash.rotation.y=yaw-.11
	slash.scale=Vector3(.16,1,.16)
	var fill_color:=Color(.21,.75,.86,.065)
	var fill_mat:=material(fill_color,.55)
	fill_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	var fill:=sector_band(.55,9.8,.67,fill_mat)
	fill.name="SlashField"
	slash.add_child(fill)
	var edge_color:=Color(.43,.89,1.0,.85)
	var edge_mat:=material(edge_color,1.7)
	edge_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	edge_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	var edge:=sector_band(8.95,10.25,.67,edge_mat,true)
	edge.name="SlashEdge"
	edge.position.y=.025
	slash.add_child(edge)
	var trail_color:=Color(.30,.84,.97,.28)
	var trail_mat:=material(trail_color,.8)
	trail_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	var trail:=sector_band(6.95,7.35,.67,trail_mat,true)
	trail.name="SlashTrail"
	trail.position.y=.035
	slash.add_child(trail)
	var tween:=slash.create_tween().set_parallel(true)
	tween.tween_property(slash,"scale",Vector3.ONE,.19).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(slash,"rotation:y",yaw+.11,.19).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(fill_mat,"albedo_color",Color(fill_color.r,fill_color.g,fill_color.b,0),.18)
	tween.tween_property(edge_mat,"albedo_color",Color(edge_color.r,edge_color.g,edge_color.b,0),.18)
	tween.tween_property(trail_mat,"albedo_color",Color(trail_color.r,trail_color.g,trail_color.b,0),.18)
	tween.chain().tween_callback(slash.queue_free)
