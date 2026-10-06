class_name NightfallWorld
extends Node3D
## Ash outpost and explorable ruin perimeter; no lanes or opposing bases.
const Layout = preload("res://scripts/outpost_layout.gd")
const Grid = preload("res://scripts/construction_grid.gd")
const FORT_HEIGHT := Layout.FORT_HEIGHT
const LIGHT_TRANSITION_SECONDS := 6.0
const MASONRY_MATERIAL_NAMES := ["Weathered concrete", "Concrete fracture"]
const DECORATION_CULL_NEAR := 84.0
const DECORATION_CULL_FAR := 98.0
const DECORATION_CULL_INTERVAL := 0.16

var terrain: Node3D
var tower_pad_scene: PackedScene
var salvage: Array[Dictionary] = []
var tower_pads: Array[Dictionary] = []
var relays: Array[Dictionary] = []
var nests: Array[Dictionary] = []
var beacon: Node3D
var environment: WorldEnvironment
var sun: DirectionalLight3D
var beacon_light: OmniLight3D
var ashfall: GPUParticles3D
var ash_material: StandardMaterial3D
var gate_lights: Array[OmniLight3D] = []
var gate_spots: Array[SpotLight3D] = []
var gate_flames: Array[MeshInstance3D] = []
var gate_light_drain: Array[float] = [0.0,0.0]
var gate_visual_drain: Array[float] = [0.0,0.0]
var warning_mix := 0.0
var hero_lantern: OmniLight3D
var decorative_nodes: Array[Node3D] = []
var decoration_cull_origin := Vector3(INF, INF, INF)
var decoration_cull_time := 0.0
var decoration_visible_count := 0
var night_active:=false
var night_mix:=0.0
var wave_warning:=false
var light_time:=0.0

func _process(delta: float) -> void:
	if beacon_light==null:return
	var game := get_parent()
	var playing: bool = not game or not game.has_method("simulate") or game.get("phase") in ["day","night"]
	if ashfall:ashfall.speed_scale=1.0 if playing else 0.0
	if not playing:return
	light_time+=delta
	night_mix=move_toward(night_mix,1.0 if night_active else 0.0,delta/LIGHT_TRANSITION_SECONDS)
	# Frame-rate independent short fades keep real warning/drain state intact.
	var response := 1.0-exp(-maxf(delta,0.0)*5.0)
	warning_mix=lerpf(warning_mix,1.0 if wave_warning else 0.0,response)
	for i in gate_visual_drain.size():
		gate_visual_drain[i]=lerpf(gate_visual_drain[i],clampf(gate_light_drain[i],0.0,.85),response)
	apply_lighting()

func build() -> void:
	terrain = (load("res://assets/models/castle_ground.glb") as PackedScene).instantiate() as Node3D
	add_child(terrain)
	var masonry_shader:=load("res://assets/shaders/outpost_masonry.gdshader") as Shader
	var masonry_materials: Dictionary = {}
	for part in terrain.find_children("*","MeshInstance3D",true,false):
		var surface := part as MeshInstance3D
		if "Sculpted" in surface.name:
			var ash := ShaderMaterial.new()
			ash.shader=load("res://assets/shaders/wasteland.gdshader")
			surface.material_override=ash
			continue
		if surface.mesh==null:continue
		for index in surface.mesh.get_surface_count():
			var original:=surface.mesh.surface_get_material(index) as StandardMaterial3D
			if original==null or original.resource_name not in MASONRY_MATERIAL_NAMES:continue
			if not masonry_materials.has(original):
				var stone:=ShaderMaterial.new()
				stone.resource_name="Ash-worn %s" % original.resource_name
				stone.shader=masonry_shader
				stone.set_shader_parameter("base_color",original.albedo_color)
				masonry_materials[original]=stone
			surface.set_surface_override_material(index,masonry_materials[original])
	beacon=place("res://assets/models/watch_beacon.glb",Vector3(0,FORT_HEIGHT,0),1.0,0)
	var fence_scene := load("res://assets/models/barricade.glb") as PackedScene
	for offset in [-11.45,-8.2,-4.9,-1.6,1.6,4.9,8.2,11.45]:
		place_scene(fence_scene,Vector3(offset,FORT_HEIGHT,-Layout.WALL_CENTER),1.45,0)
		if absf(offset)>3.6:
			place_scene(fence_scene,Vector3(offset,FORT_HEIGHT,Layout.WALL_CENTER),1.45,0)
		for side in [-1,1]:
			place_scene(fence_scene,Vector3(side*Layout.WALL_CENTER,FORT_HEIGHT,offset),1.45,PI*.5)
	for side in [-1,1]:create_gate_lamp(Vector3(side*2.45,FORT_HEIGHT,Layout.WALL_CENTER-.15))
	var tree_scene := load("res://assets/models/dead_tree.glb") as PackedScene
	var ruin_scene := load("res://assets/models/ruined_house.glb") as PackedScene
	var rock_scene := load("res://assets/models/rock_v2.glb") as PackedScene
	var relay_scene := load("res://assets/models/relay_mast.glb") as PackedScene
	var truck_scene := load("res://assets/models/truck_wreck.glb") as PackedScene
	tower_pad_scene=load("res://assets/models/tower_pad.glb") as PackedScene
	var rng := RandomNumberGenerator.new();rng.seed=99431
	for i in range(210):
		var angle := rng.randf_range(0,TAU)
		var radius := rng.randf_range(29,104)
		place_scene(tree_scene,outskirts_point(angle,radius),rng.randf_range(.74,1.35),angle,true)
	for i in range(48):
		var angle := TAU*i/48.0+rng.randf_range(-.18,.18)
		var radius := rng.randf_range(30,102)
		place_scene(ruin_scene,outskirts_point(angle,radius),rng.randf_range(.8,1.18),angle,true)
	for i in range(160):
		var angle := rng.randf_range(0,TAU)
		var radius := rng.randf_range(29,104)
		place_scene(rock_scene,outskirts_point(angle,radius),rng.randf_range(.25,.68),angle,true)
	for i in range(8):
		var angle := TAU*i/8.0+.26
		var radius := 46.0+float(i%3)*21.0
		var point:=Vector3(cos(angle)*radius,0,sin(angle)*radius)
		var relay:=place_scene(relay_scene,point,1.0,angle)
		var relay_light:=OmniLight3D.new()
		relay_light.position=point+Vector3(0,3.1,0)
		relay_light.light_color=Color("79d9df")
		relay_light.omni_range=13
		relay_light.light_energy=0.0
		relay_light.shadow_enabled=false
		add_child(relay_light)
		relays.append({"node":relay,"position":point,"activated":false,"light":relay_light})
	for i in range(18):
		var angle := TAU*i/18.0+.43
		var radius := 30.0+float(i%4)*19.0
		place_scene(truck_scene,outskirts_point(angle,radius),rng.randf_range(.82,1.1),angle,true)
	var nest_scene:=load("res://assets/models/night_nest.glb") as PackedScene
	var sealed_scene:=load("res://assets/models/sealed_nest.glb") as PackedScene
	for point in [Vector3(-22,0,31),Vector3(34,0,46),Vector3(-42,0,65)]:
		var nest:=place_scene(nest_scene,point,1.0,0)
		var sealed:=place_scene(sealed_scene,point,.05,0)
		sealed.visible=false
		var nest_light:=OmniLight3D.new()
		nest_light.position=Vector3(0,1.15,0)
		nest_light.light_color=Color("d46269")
		nest_light.light_energy=1.25
		nest_light.omni_range=7.5
		nest_light.shadow_enabled=false
		nest.add_child(nest_light)
		var sealed_light:=OmniLight3D.new()
		sealed_light.position=Vector3(0,.7,0)
		sealed_light.light_color=Color("7ac9c5")
		sealed_light.light_energy=0.0
		sealed_light.omni_range=6.0
		sealed_light.shadow_enabled=false
		sealed.add_child(sealed_light)
		nests.append({"node":nest,"sealed_node":sealed,"light":nest_light,"sealed_light":sealed_light,"position":point,"cleansed":false})
	# Only the two actual opening defenses have foundations. Every later
	# tower is authored by the player; there are no empty fixed construction slots.
	for point in [Vector3(5.5,0,10.5),Vector3(-5.5,0,10.5)]:
		add_tower_pad(point)
	var salvage_scene := load("res://assets/models/salvage_crate.glb") as PackedScene
	for i in range(36):
		var angle := TAU*i/36.0+.23
		var radius := 31.0+float(i%6)*14.0
		if i%6==1:radius=40.0
		var point := outskirts_point(angle,radius)
		var crate := place_scene(salvage_scene,point,1.0,angle)
		salvage.append({"node":crate,"position":point,"collected":false,"amount":35+int(i%5==0)*25})
	environment=WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("101a20")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("a6b2ac")
	env.ambient_light_energy=.42
	env.tonemap_mode=Environment.TONE_MAPPER_ACES
	env.glow_enabled=true
	env.glow_intensity=.24
	env.ssao_enabled=true
	env.ssao_radius=1.05
	env.ssao_intensity=.85
	env.fog_enabled=true
	env.fog_light_color=Color("303c42")
	env.fog_density=.012
	env.fog_height_density=.025
	environment.environment=env
	add_child(environment)
	sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-38,-42,0)
	sun.light_color=Color("d6bbb0")
	sun.light_energy=.75
	sun.shadow_enabled=true
	sun.light_angular_distance=1.0
	# The fixed orthographic view needs one consistent texel density, not
	# cascade boundaries sweeping across the courtyard while the camera pans.
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance=80
	sun.shadow_bias=.035
	sun.shadow_normal_bias=.65
	add_child(sun)
	beacon_light=OmniLight3D.new()
	beacon_light.position=Vector3(0,FORT_HEIGHT+4.5,0)
	beacon_light.light_color=Color("ffaf59")
	beacon_light.light_energy=1.9
	beacon_light.omni_range=25
	beacon_light.shadow_enabled=true
	beacon_light.omni_shadow_mode=OmniLight3D.SHADOW_CUBE
	beacon_light.shadow_bias=.06
	beacon_light.shadow_normal_bias=.8
	add_child(beacon_light)
	hero_lantern=OmniLight3D.new()
	hero_lantern.light_color=Color("ffd0a0")
	hero_lantern.omni_range=10.5
	hero_lantern.light_energy=0.0
	hero_lantern.shadow_enabled=false
	add_child(hero_lantern)
	create_ashfall()
	set_night(false)

func create_ashfall() -> void:
	ashfall=GPUParticles3D.new()
	ashfall.amount=110
	ashfall.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ashfall.lifetime=10.0
	ashfall.preprocess=8.0
	ashfall.visibility_aabb=AABB(Vector3(-30,-15,-27),Vector3(60,36,54))
	var drift:=ParticleProcessMaterial.new()
	drift.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_BOX
	drift.emission_box_extents=Vector3(26,6,22)
	drift.direction=Vector3(-.6,-.45,-.2)
	drift.spread=38.0
	drift.initial_velocity_min=.6
	drift.initial_velocity_max=1.6
	drift.gravity=Vector3(0,-.13,0)
	drift.scale_min=.55
	drift.scale_max=1.45
	var lifetime_gradient:=Gradient.new()
	lifetime_gradient.offsets=PackedFloat32Array([0.0,.18,.7,1.0])
	lifetime_gradient.colors=PackedColorArray([Color(1,1,1,0),Color.WHITE,Color.WHITE,Color(1,1,1,0)])
	var lifetime_texture:=GradientTexture1D.new()
	lifetime_texture.gradient=lifetime_gradient
	drift.color_ramp=lifetime_texture
	ashfall.process_material=drift
	var flake:=QuadMesh.new()
	flake.size=Vector2(.18,.12)
	ash_material=StandardMaterial3D.new()
	ash_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ash_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	ash_material.vertex_color_use_as_albedo=true
	ash_material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	ash_material.albedo_color=Color(.55,.51,.46,.22)
	# Soft, filtered flakes avoid hard one-pixel rectangles flashing in
	# front of silhouettes. Both radial edges and birth/death fade continuously.
	var edge_gradient:=Gradient.new()
	edge_gradient.offsets=PackedFloat32Array([0.0,.35,1.0])
	edge_gradient.colors=PackedColorArray([Color.WHITE,Color(1,1,1,.65),Color(1,1,1,0)])
	var edge_texture:=GradientTexture2D.new()
	edge_texture.width=64
	edge_texture.height=64
	edge_texture.gradient=edge_gradient
	edge_texture.fill=GradientTexture2D.FILL_RADIAL
	edge_texture.fill_from=Vector2(.5,.5)
	edge_texture.fill_to=Vector2(1.0,.5)
	ash_material.albedo_texture=edge_texture
	flake.material=ash_material
	ashfall.draw_pass_1=flake
	add_child(ashfall)
	ashfall.emitting=true

func follow_ashfall(point: Vector3) -> void:
	if ashfall:ashfall.position=point+Vector3(0,8,0)
	if hero_lantern:hero_lantern.position=point+Vector3(0,2.25,0)
	update_decoration_culling(point)

func update_decoration_culling(point: Vector3) -> void:
	decoration_cull_time=maxf(0.0,decoration_cull_time-get_process_delta_time())
	var flat_point:=Vector2(point.x,point.z)
	if decoration_cull_time>0.0 and flat_point.distance_squared_to(Vector2(decoration_cull_origin.x,decoration_cull_origin.z))<9.0:return
	decoration_cull_time=DECORATION_CULL_INTERVAL
	decoration_cull_origin=point
	var near_squared:=DECORATION_CULL_NEAR*DECORATION_CULL_NEAR
	var far_squared:=DECORATION_CULL_FAR*DECORATION_CULL_FAR
	decoration_visible_count=0
	for node in decorative_nodes:
		if not is_instance_valid(node):continue
		var node_point:=Vector2(node.position.x,node.position.z)
		var distance_squared:=flat_point.distance_squared_to(node_point)
		# Hysteresis keeps a tree from popping while the hero walks across the
		# boundary. Only background decoration is culled; gameplay landmarks and
		# the terrain mesh remain available at every distance.
		var visible:=distance_squared<=far_squared if node.visible else distance_squared<=near_squared
		node.visible=visible
		if visible:decoration_visible_count+=1

func create_gate_lamp(point: Vector3) -> void:
	var metal:=StandardMaterial3D.new()
	metal.albedo_color=Color("353b39")
	metal.metallic=.55
	metal.roughness=.75
	var post:=MeshInstance3D.new()
	var post_mesh:=CylinderMesh.new()
	post_mesh.top_radius=.12;post_mesh.bottom_radius=.17;post_mesh.height=2.35
	post.mesh=post_mesh;post.material_override=metal
	add_child(post);post.position=point+Vector3(0,1.18,0)
	var flame:=MeshInstance3D.new()
	var globe:=SphereMesh.new()
	globe.radius=.27;globe.height=.48
	flame.mesh=globe
	var amber:=StandardMaterial3D.new()
	amber.albedo_color=Color("e99a45")
	amber.emission_enabled=true
	amber.emission=Color("ffad57")
	amber.emission_energy_multiplier=3.2
	flame.material_override=amber
	add_child(flame);flame.position=point+Vector3(0,2.5,0);gate_flames.append(flame)
	var lamp:=OmniLight3D.new()
	lamp.position=point+Vector3(0,2.5,0)
	lamp.light_color=Color("ff9d53")
	lamp.omni_range=12
	lamp.light_energy=2.0
	lamp.shadow_enabled=false
	add_child(lamp);gate_lights.append(lamp)
	var searchlight:=SpotLight3D.new()
	searchlight.position=point+Vector3(0,2.65,0)
	searchlight.light_color=Color("ffc080")
	searchlight.light_energy=0.0
	searchlight.spot_range=34.0
	searchlight.spot_angle=36.0
	searchlight.spot_attenuation=.62
	searchlight.shadow_enabled=false
	add_child(searchlight)
	searchlight.look_at(Vector3(point.x,terrain_height(Vector3(point.x,0,point.z+17.0)),point.z+17.0),Vector3.UP)
	gate_spots.append(searchlight)

func terrain_height(point: Vector3) -> float:
	return Layout.terrain_height(point)

func add_tower_pad(point: Vector3, zone: String="castle") -> int:
	# The controller validates spacing and construction cost. The world still
	# refuses points outside the protected yard so every runtime tower remains
	# on the castle plane, including dynamically appended positions.
	var placement := Grid.placement(point,"tower")
	if not point.is_finite() or not bool(placement.inside):return -1
	point=placement.point
	if tower_pad_scene==null:tower_pad_scene=load("res://assets/models/tower_pad.glb") as PackedScene
	point.y=terrain_height(point)
	var core_zone := zone=="core"
	var pad := place_scene(tower_pad_scene,point,.82 if core_zone else 1.0,0.0)
	pad.name="CastleTowerPad%d" % tower_pads.size()
	var tower_light:=OmniLight3D.new()
	tower_light.position=point+Vector3(0,2.0 if core_zone else 2.4,0)
	tower_light.light_color=Color("83d7c5") if core_zone else Color("ffb56c")
	tower_light.omni_range=9.0 if core_zone else 12.0
	tower_light.light_energy=0.0
	tower_light.shadow_enabled=false
	add_child(tower_light)
	tower_pads.append({"node":pad,"position":point,"zone":zone,"turret":null,"level":0,"cooldown":0.0,"mode":"nearest","hp":0.0,"max_hp":0.0,"damage_ring":null,"light":tower_light,"removed":false,"paid_investment":0})
	return tower_pads.size()-1

func outskirts_point(angle: float, radius: float) -> Vector3:
	# Keep large tree/ruin footprints away from both the expanded embankment
	# and the only southern approach. These are decorations, not obstructions.
	var point:=Vector3(cos(angle)*radius,0.0,sin(angle)*radius)
	for _attempt in 12:
		var raised:=false
		for offset in [Vector3.ZERO,Vector3(2.4,0,0),Vector3(-2.4,0,0),Vector3(0,0,2.4),Vector3(0,0,-2.4)]:
			if terrain_height(point+offset)>.01:raised=true;break
		if not raised and not Layout.contains_castle(point,-2.4):return point
		radius+=2.0
		point=Vector3(cos(angle)*radius,0.0,sin(angle)*radius)
	return point

func place(path: String, point: Vector3, size_factor: float, angle: float) -> Node3D:
	return place_scene(load(path) as PackedScene,point,size_factor,angle)

func place_scene(scene: PackedScene, point: Vector3, size_factor: float, angle: float, decorative: bool=false) -> Node3D:
	var node := scene.instantiate() as Node3D
	add_child(node)
	node.position=point
	node.scale=Vector3.ONE*size_factor
	node.rotation.y=angle
	if decorative:decorative_nodes.append(node)
	return node

func set_night(is_night: bool) -> void:
	night_active=is_night
	apply_lighting()

func apply_lighting() -> void:
	if environment==null:return
	var blend:=night_mix*night_mix*(3.0-2.0*night_mix)
	var pulse_scale := 1.0
	var game := get_parent()
	if game and game.has_method("simulate") and is_instance_valid(game.get("combat")):
		if game.combat.reduced_effects:pulse_scale=0.0
	if ashfall:
		ashfall.amount_ratio=lerpf(.35,.65,blend)
		ash_material.albedo_color=Color(.55,.51,.46,.22).lerp(Color(.54,.59,.64,.26),blend)
	var env := environment.environment
	env.background_color=Color("343a3d").lerp(Color("03060b"),blend)
	env.ambient_light_color=Color("b8b3a5").lerp(Color("697587"),blend)
	env.ambient_light_energy=lerpf(.56,.028,blend)
	env.fog_light_color=Color("4a5252").lerp(Color("090f1a"),blend)
	env.fog_density=lerpf(.0065,.014,blend)
	sun.light_color=Color("e4c6a7").lerp(Color("587090"),blend)
	sun.light_energy=lerpf(.86,.018,blend)
	beacon_light.light_energy=lerpf(1.4,8.2,blend)+sin(light_time*1.1)*.045*pulse_scale
	beacon_light.omni_range=lerpf(25.0,22.0,blend)
	hero_lantern.light_energy=blend*3.4
	hero_lantern.visible=hero_lantern.light_energy>.001
	for relay in relays:
		(relay.light as OmniLight3D).light_energy=blend*3.2 if relay.activated else 0.0
		(relay.light as OmniLight3D).visible=relay.light.light_energy>.001
	for pad in tower_pads:
		if bool(pad.get("removed",false)) or not is_instance_valid(pad.get("light")):continue
		(pad.light as OmniLight3D).light_energy=blend*(1.65+float(pad.level)*.45) if pad.level>0 else 0.0
		(pad.light as OmniLight3D).visible=pad.light.light_energy>.001
	for i in gate_lights.size():
		var drain:=1.0-gate_visual_drain[i]
		var pulse:=sin(light_time*1.8+float(i)*1.7)*pulse_scale
		gate_lights[i].light_energy=lerpf(lerpf(.9,5.2,blend)+pulse*.035,5.0+pulse*.12,warning_mix)*drain
		gate_lights[i].light_color=Color("ff9d53").lerp(Color("df5f4c"),warning_mix)
		gate_spots[i].light_energy=lerpf(0.0,11.0,blend)*lerpf(1.0,1.25,warning_mix)*drain
		gate_spots[i].visible=gate_spots[i].light_energy>.001
		(gate_flames[i].material_override as StandardMaterial3D).emission_energy_multiplier=3.2*drain
