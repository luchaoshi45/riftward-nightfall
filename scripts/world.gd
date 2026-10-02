class_name BattleWorld
extends Node3D
## Three connected lanes, a traversable river and solid forest islands.
var interactables: Array[Dictionary] = []
var wind_materials: Dictionary = {}

func build() -> void:
	var grass := terrain_material(Color("253d25"),Color("708052"),false)
	var dark_grass := BattleVisuals.material(Color("19372f"))
	var edge := BattleVisuals.material(Color("727c68"))
	var rng := RandomNumberGenerator.new()
	rng.seed=741
	BattleVisuals.box(self,Vector3(0,-.7,0),Vector3(115,1.2,95),dark_grass)
	var terrain := (load("res://assets/models/arena_terrain.glb") as PackedScene).instantiate() as Node3D
	add_child(terrain)
	var stone_shader := load("res://assets/shaders/weathered_stone.gdshader") as Shader
	for part in terrain.find_children("*", "MeshInstance3D", true, false):
		var tile := part as MeshInstance3D
		if "Sculpted" in tile.name:
			tile.material_override = grass
		elif "flagstones" in tile.name or "Riverbank" in tile.name:
			var source := tile.mesh.surface_get_material(0) as StandardMaterial3D
			if source:
				var weathered := ShaderMaterial.new()
				weathered.shader = stone_shader
				weathered.set_shader_parameter("base_color", source.albedo_color)
				tile.material_override = weathered
	var water := ShaderMaterial.new()
	water.shader=load("res://assets/shaders/water.gdshader")
	BattleVisuals.box(self,Vector3(0,-.01,0),Vector3(7,.1,65),water)
	for team in [0,1]:
		var col := Color("4cbed1") if team==0 else Color("d5596d")
		BattleVisuals.ring(self,BattleMap.home(team)+Vector3.UP*.12,4.3,col,.10)
		for lane in range(3):
			for tier in range(2):
				BattleVisuals.ring(self,BattleMap.tower_point(team,lane,tier)+Vector3.UP*.12,1.7,col,.05)
	var tree_scene := load("res://assets/models/oak_v2.glb") as PackedScene
	var cedar_scene := load("res://assets/models/cedar_v2.glb") as PackedScene
	var rock_scene := load("res://assets/models/rock_v2.glb") as PackedScene
	var grass_scene := load("res://assets/models/grass_tuft.glb") as PackedScene
	var reeds_scene := load("res://assets/models/river_reeds.glb") as PackedScene
	var fern_scene := load("res://assets/models/fern_v2.glb") as PackedScene
	var thicket_scene := load("res://assets/models/thicket.glb") as PackedScene
	var flower_scene := load("res://assets/models/wildflowers.glb") as PackedScene
	var mushroom_scene := load("res://assets/models/mushrooms.glb") as PackedScene
	var ruin_scene := load("res://assets/models/ruin_pillar.glb") as PackedScene
	var lantern_scene := load("res://assets/models/aether_lantern.glb") as PackedScene
	for forest in BattleMap.FORESTS:
		for i in range(4):
			var a := i*TAU/4
			var radius := rng.randf_range(.4,1.7)
			plant(tree_scene if i%3 else cedar_scene,forest+Vector3(cos(a)*radius,0,sin(a)*radius),rng.randf_range(.8,1.2),rng.randf_range(0,TAU),"tree")
		for i in range(5):
			var a := i*TAU/5
			prop(rock_scene,forest+Vector3(cos(a)*3,0,sin(a)*3),rng.randf_range(.5,.85),rng.randf_range(0,TAU))
		prop(ruin_scene,forest+Vector3(3.75,0,0),.73,rng.randf_range(0,TAU))
	# Trees on the perimeter frame the arena without masking walkable ground.
	for i in range(100):
		var point := Vector3(rng.randf_range(-50,50),0,rng.randf_range(30,42)*(-1 if i%2==0 else 1))
		plant(tree_scene if i%3 else cedar_scene,point,rng.randf_range(.95,1.7),rng.randf_range(0,TAU),"tree")
		if i%3==0: plant(thicket_scene,point+Vector3(1.5,0,.6),rng.randf_range(.65,1.2),rng.randf_range(0,TAU),"small")
	for camp in BattleMap.CAMPS:
		BattleVisuals.ring(self,camp+Vector3.UP*.1,2.8,Color("ac955f"),.05)
		for i in range(5):
			var a := i*TAU/5
			prop(rock_scene,camp+Vector3(cos(a)*2.8,0,sin(a)*2.8),.42,a)
		prop(ruin_scene,camp+Vector3(3.5,0,3.1),.88,rng.randf_range(0,TAU))
	# Groundcover stays short on traversable terrain; tall canopies mark solid islands.
	for i in range(210):
		var point:=Vector3(rng.randf_range(-41,41),0,rng.randf_range(-27,27))
		if absf(point.x)<4 or not BattleMap.walkable(point): continue
		var on_lane:=false
		for lane in range(3):
			var points:=BattleMap.route(lane)
			for j in range(points.size()-1):
				if Geometry3D.get_closest_point_to_segment(point,points[j],points[j+1]).distance_to(point)<3.8: on_lane=true
		if on_lane: continue
		var groundcover := fern_scene if i%4==0 else (thicket_scene if i%4==1 else (flower_scene if i%4==2 else mushroom_scene))
		plant(groundcover,point,rng.randf_range(.65,1.35),rng.randf_range(0,TAU),"small")
		if i%7==0: prop(rock_scene,point+Vector3(.5,-.08,.3),rng.randf_range(.22,.43),rng.randf_range(0,TAU))
	var meadow_transforms: Array[Transform3D] = []
	for i in range(950):
		var point := Vector3(rng.randf_range(-43,43),.025,rng.randf_range(-30,30))
		if absf(point.x)<5.1 or not BattleMap.walkable(point): continue
		var meadow_patch := sin(point.x*.47+sin(point.z*.23))*sin(point.z*.35-point.x*.11)
		if meadow_patch < -.12: continue
		var close_to_lane := false
		for lane in range(3):
			var route := BattleMap.route(lane)
			for j in range(route.size()-1):
				if Geometry3D.get_closest_point_to_segment(point,route[j],route[j+1]).distance_to(point)<2.2:
					close_to_lane = true
		if close_to_lane: continue
		meadow_transforms.append(Transform3D(Basis(Vector3.UP,rng.randf_range(0,TAU)).scaled(Vector3.ONE*rng.randf_range(.55,1.35)),point))
	add_foliage_multimesh(grass_scene,meadow_transforms,Color("294e2d"),.045,.0,.42)
	var reed_transforms: Array[Transform3D] = []
	for i in range(130):
		var z := rng.randf_range(-31,31)
		if absf(z)<4.7 or absf(absf(z)-22.0)<4.7: continue
		var x := rng.randf_range(4.25,5.25) * (-1.0 if i%2==0 else 1.0)
		var point := Vector3(x,.04,z)
		reed_transforms.append(Transform3D(Basis(Vector3.UP,rng.randf_range(0,TAU)).scaled(Vector3.ONE*rng.randf_range(.75,1.22)),point))
	add_foliage_multimesh(reeds_scene,reed_transforms,Color("294f3d"),.07,.0,1.2)
	# Interactive points are near routes but outside towers and jungle collision islands.
	var well_scene := load("res://assets/models/moonwell.glb") as PackedScene
	var obelisk_scene := load("res://assets/models/rune_obelisk.glb") as PackedScene
	var cache_scene := load("res://assets/models/star_reliquary.glb") as PackedScene
	for pos in [Vector3(-19,0,-15),Vector3(19,0,15)]: place_interactive("well",pos,well_scene)
	for pos in [Vector3(-8,0,6),Vector3(8,0,-6)]: place_interactive("obelisk",pos,obelisk_scene)
	for pos in [Vector3(-30,0,8),Vector3(30,0,-8)]: place_interactive("relic",pos,cache_scene)
	for team in [0,1]:
		var standard_scene := load("res://assets/models/standard_blue.glb") as PackedScene if team==0 else load("res://assets/models/standard_red.glb") as PackedScene
		for lane in range(3):
			var point:=BattleMap.tower_point(team,lane,0)+Vector3(0,0,4)
			prop(standard_scene,point,.88,0)
	for z in [-22,0,22]:
		for x in [-4.1,4.1]:
			for side in [-1,1]:
				var point := Vector3(x,0,z+side*3.7)
				prop(lantern_scene,point,.92,0)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color("10252f")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("aec9d0")
	env.ambient_light_energy=.58
	env.tonemap_mode=Environment.TONE_MAPPER_ACES
	env.glow_enabled=true
	env.glow_intensity=.25
	env.glow_bloom=.06
	env.ssao_enabled=true
	env.ssao_radius=1.3
	env.ssao_intensity=1.1
	env.fog_enabled=true
	env.fog_light_color=Color("263f42")
	env.fog_density=.0005
	env.fog_height=0
	env.fog_height_density=.03
	environment.environment=env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-52,-30,0)
	sun.light_color=Color("fff0cd")
	sun.light_energy=.85
	sun.light_angular_distance=1.4
	sun.shadow_enabled=true
	sun.shadow_bias=.12
	sun.shadow_normal_bias=2.5
	sun.directional_shadow_max_distance=110
	add_child(sun)
	var fill:=DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(-35,150,0)
	fill.light_color=Color("739eb3")
	fill.light_energy=.22
	add_child(fill)

func terrain_material(dark: Color, light: Color, is_stone: bool) -> ShaderMaterial:
	var material:=ShaderMaterial.new()
	material.shader=load("res://assets/shaders/terrain.gdshader")
	var a:=dark.srgb_to_linear()
	var b:=light.srgb_to_linear()
	material.set_shader_parameter("tint_a",Vector3(a.r,a.g,a.b))
	material.set_shader_parameter("tint_b",Vector3(b.r,b.g,b.b))
	material.set_shader_parameter("stone",1.0 if is_stone else 0.0)
	material.set_shader_parameter("ground_texture",load("res://assets/art/forest_ground_v03.png"))
	return material

func prop(scene: PackedScene, point: Vector3, size_factor: float, angle: float) -> void:
	var node := scene.instantiate() as Node3D
	add_child(node)
	node.position=point
	node.scale=Vector3.ONE*size_factor
	node.rotation.y=angle

func plant(scene: PackedScene, point: Vector3, size_factor: float, angle: float, category: String) -> void:
	var node := scene.instantiate() as Node3D
	add_child(node)
	node.position = point
	node.scale = Vector3.ONE * size_factor
	node.rotation.y = angle
	for part in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := part as MeshInstance3D
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var original := mesh_instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if original == null: continue
			var name := original.resource_name.to_lower()
			var foliage := "leaf" in name or "needles" in name or "fern" in name or "petal" in name or "flower" in name or "mushroom" in name
			if not foliage: continue
			var cache_key := original.resource_name + category
			if not wind_materials.has(cache_key):
				var windy := ShaderMaterial.new()
				windy.shader = load("res://assets/shaders/foliage_wind.gdshader")
				windy.set_shader_parameter("foliage_color",original.albedo_color)
				windy.set_shader_parameter("roughness_value",original.roughness)
				windy.set_shader_parameter("sway",.19 if category == "tree" else .065)
				windy.set_shader_parameter("root_height",1.15 if category == "tree" else .02)
				windy.set_shader_parameter("tip_height",3.65 if category == "tree" else .65)
				windy.set_shader_parameter("wind_speed",1.05 if category == "tree" else 1.35)
				wind_materials[cache_key] = windy
			mesh_instance.set_surface_override_material(surface,wind_materials[cache_key])

func add_foliage_multimesh(scene: PackedScene, transforms: Array[Transform3D], tint: Color, sway: float, root_height: float, tip_height: float) -> void:
	if transforms.is_empty(): return
	var sample := scene.instantiate() as Node3D
	var mesh_parts := sample.find_children("*", "MeshInstance3D", true, false)
	assert(not mesh_parts.is_empty())
	var instance := MultiMeshInstance3D.new()
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/shaders/foliage_wind.gdshader")
	material.set_shader_parameter("foliage_color",tint)
	material.set_shader_parameter("sway",sway)
	material.set_shader_parameter("root_height",root_height)
	material.set_shader_parameter("tip_height",tip_height)
	material.set_shader_parameter("wind_speed",1.3)
	instance.material_override = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = (mesh_parts[0] as MeshInstance3D).mesh
	multi.instance_count = transforms.size()
	for index in range(transforms.size()): multi.set_instance_transform(index,transforms[index])
	instance.multimesh = multi
	add_child(instance)
	sample.free()

func place_interactive(kind: String, point: Vector3, scene: PackedScene) -> void:
	var node := scene.instantiate() as Node3D
	add_child(node)
	node.position = point
	var color := Color("7bdfd4") if kind=="well" else (Color("b5bdff") if kind=="obelisk" else Color("deb775"))
	BattleVisuals.ring(self,point+Vector3.UP*.06,1.15,color,.045)
	interactables.append({"kind":kind,"position":point,"node":node,"cooldown":0.0,"used":false})

