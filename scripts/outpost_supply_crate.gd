extends Node3D
class_name OutpostSupplyCrate

const BODY_CLEARANCE := 1.12
const MAX_MOVEMENT_STEP := .12

## A mobile, one-use building permit. The controller owns its reward identity,
## selection/deployment input and payment. This actor owns only visuals and an
## independent navigation route; it never changes the hero's path or wallet.

var serial: int = -1
var opened := false
var supply_kind := "tower"
var display_name := "炮塔"
var selected := false
var path_points: Array[Vector3] = []
var move_speed := 5.0
var pulse_time := 0.0
var body: MeshInstance3D
var lid: MeshInstance3D
var marker: MeshInstance3D
var ring: MeshInstance3D
var glow: OmniLight3D
var chassis: Node3D
var wheels: Array[MeshInstance3D] = []
var caption: Label3D
var ring_material: StandardMaterial3D

func setup(crate_serial: int, kind: String = "tower", label: String = "炮塔") -> void:
	serial = crate_serial
	supply_kind = kind
	display_name = label
	name = "BuildingVehicle_%d" % serial
	chassis = Node3D.new()
	chassis.name = "VehicleChassis"
	add_child(chassis)
	var hull_material := _material(Color("566b61"), Color("152f25"))
	var cargo_material := _material(Color("b59657"), Color("503b15"))
	var gold_material := _material(Color("f4d889"), Color("e4a94d"))
	var tire_material := _material(Color("242c29"), Color.BLACK)
	body = _box(chassis, "VehicleHull", Vector3(1.45, .43, 1.70), Vector3(0, .46, 0), hull_material)
	lid = _box(chassis, "CargoDeck", Vector3(1.24, .12, 1.31), Vector3(0, .72, -.12), cargo_material)
	_box(chassis, "DriverCab", Vector3(.89, .48, .52), Vector3(0, .83, .57), hull_material)
	_box(chassis, "CabWindow", Vector3(.73, .18, .035), Vector3(0, .95, .845), _material(Color("87bcbd"), Color("244846")))
	for side: float in [-1.0, 1.0]:
		for axle: float in [-.53, .53]:
			var wheel := MeshInstance3D.new()
			wheel.name = "Wheel"
			var tire := CylinderMesh.new()
			tire.top_radius = .27
			tire.bottom_radius = .27
			tire.height = .24
			tire.radial_segments = 12
			wheel.mesh = tire
			wheel.material_override = tire_material
			wheel.position = Vector3(side * .66, .27, axle)
			wheel.rotation.z = PI * .5
			chassis.add_child(wheel)
			wheels.append(wheel)
			_box(chassis, "Headlamp", Vector3(.15, .13, .055), Vector3(side * .49, .53, .88), gold_material)
	# A miniature building on the cargo deck distinguishes the deployed permit
	# from a loot box without relying on a permanently open HUD catalogue.
	if kind == "tower":
		_box(chassis, "TurretIcon", Vector3(.45, .28, .43), Vector3(0, .96, -.22), gold_material)
		_box(chassis, "TurretBarrel", Vector3(.12, .12, .54), Vector3(0, 1.03, -.61), cargo_material)
	elif kind == "barracks":
		_box(chassis, "BarracksIcon", Vector3(.59, .40, .51), Vector3(0, 1.00, -.23), gold_material)
		_box(chassis, "BarracksRoof", Vector3(.70, .09, .62), Vector3(0, 1.245, -.23), cargo_material)
	else:
		for column in 3:
			var height := .22 + float(column) * .10
			_box(chassis, "BuildingIcon", Vector3(.19, height, .48), Vector3((column - 1) * .23, .79 + height * .5, -.23), gold_material)
	marker = _box(chassis, "GoldFlagPole", Vector3(.055, 1.02, .055), Vector3(.52, 1.16, -.51), cargo_material)
	_box(chassis, "GoldFlag", Vector3(.39, .23, .04), Vector3(.35, 1.56, -.51), gold_material)

	ring = MeshInstance3D.new()
	ring.name = "VehicleSelectionRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = .98
	ring_mesh.outer_radius = 1.04
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 8
	ring.mesh = ring_mesh
	ring.position.y = .035
	ring_material = _material(Color("d8c16c"), Color("f0bc55"))
	ring.material_override = ring_material
	add_child(ring)
	glow = OmniLight3D.new()
	glow.name = "VehicleSignalGlow"
	glow.light_color = Color("e7bb69")
	glow.light_energy = .75
	glow.omni_range = 3.2
	glow.position = Vector3(0, 1.1, 0)
	add_child(glow)
	caption = Label3D.new()
	caption.name = "SelectedBuildingLabel"
	caption.text = display_name + "部署车"
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Hiragino Sans GB", "Microsoft YaHei", "Noto Sans CJK SC", "Arial Unicode MS"])
	font.allow_system_fallback = true
	caption.font = font
	caption.font_size = 28
	caption.pixel_size = .009
	caption.outline_size = 5
	caption.modulate = Color("f4d889")
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.position = Vector3(0, 1.96, 0)
	add_child(caption)
	set_selected(false)

func _box(parent: Node3D, part_name: String, size: Vector3, offset: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = part_name
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.position = offset
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _material(albedo: Color, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = .32
	material.roughness = .74
	return material

func set_selected(value: bool) -> void:
	selected = value and not opened
	if is_instance_valid(caption):caption.visible = selected
	if is_instance_valid(ring_material):
		ring_material.albedo_color = Color("8ce1bc") if selected else Color("c6a354")
		ring_material.emission = Color("70d4a2") if selected else Color("a88232")
		ring_material.emission_energy_multiplier = .6 if selected else .22

func advance_visual(delta: float) -> void:
	if opened:return
	pulse_time += maxf(0.0, delta)
	var pulse := 1.0 + sin(pulse_time * 2.7) * .035
	if is_instance_valid(ring):ring.scale = Vector3.ONE * pulse
	if is_instance_valid(glow):glow.light_energy = .65 + (sin(pulse_time * 2.7) + 1.0) * .12

func _movement_active(controller: Node3D) -> bool:
	return not opened and not is_queued_for_deletion() and is_inside_tree() \
		and is_instance_valid(controller) and not controller.is_queued_for_deletion() \
		and get_parent() == controller and controller.get("phase") in ["day", "night"] \
		and not controller.quitting and not controller.restart_pending and not controller.shutting_down \
		and controller._valid_construction_vehicle(self)

func _body_clear(point: Vector3, controller: Node3D) -> bool:
	if not point.is_finite():return false
	var center := Vector2(point.x, point.z)
	for blocks: Array in [controller.WALK_BLOCKS, controller.TERRAIN_BLOCKS, controller.construction_blocks]:
		for block: Rect2 in blocks:
			if block.grow(BODY_CLEARANCE).has_point(center):return false
	for offset: Vector2 in [Vector2.ZERO, Vector2(-BODY_CLEARANCE, -BODY_CLEARANCE), Vector2(BODY_CLEARANCE, -BODY_CLEARANCE), Vector2(-BODY_CLEARANCE, BODY_CLEARANCE), Vector2(BODY_CLEARANCE, BODY_CLEARANCE)]:
		if not controller.outpost_walkable(point + Vector3(offset.x, 0, offset.y)):return false
	return true

func _segment_clear(origin: Vector3, target: Vector3, controller: Node3D) -> bool:
	if not _body_clear(origin, controller) or not _body_clear(target, controller):return false
	var start := Vector2(origin.x, origin.z)
	var direction := Vector2(target.x - origin.x, target.z - origin.z)
	for blocks: Array in [controller.WALK_BLOCKS, controller.TERRAIN_BLOCKS, controller.construction_blocks]:
		for block: Rect2 in blocks:
			if controller.segment_crosses_wall(start, direction, block.grow(BODY_CLEARANCE)):return false
	return bool(controller.can_traverse(origin, target))

func _vehicle_navigation(controller: Node3D) -> AStarGrid2D:
	var source: AStarGrid2D = controller.get("hero_navigation") as AStarGrid2D
	if not is_instance_valid(source):return null
	var navigation := AStarGrid2D.new()
	navigation.region = source.region
	navigation.cell_size = Vector2.ONE
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	navigation.update()
	var region := navigation.region
	# Only rasterize the bounded obstacle rectangles. The wider car owns this
	# map rather than mutating the hero's grid or testing every terrain cell.
	for blocks: Array in [controller.WALK_BLOCKS, controller.TERRAIN_BLOCKS, controller.construction_blocks]:
		for block: Rect2 in blocks:
			var padded := block.grow(BODY_CLEARANCE)
			var min_x := maxi(region.position.x, floori(padded.position.x))
			var max_x := mini(region.end.x - 1, ceili(padded.end.x))
			var min_z := maxi(region.position.y, floori(padded.position.y))
			var max_z := mini(region.end.y - 1, ceili(padded.end.y))
			for z in range(min_z, max_z + 1):
				for x in range(min_x, max_x + 1):
					if padded.has_point(Vector2(x, z)):navigation.set_point_solid(Vector2i(x, z))
	# A vehicle centre cannot use the grid's outermost cells when its wheels
	# would overhang the map. This remains a bounded perimeter operation.
	for z in range(region.position.y, region.end.y):
		for x in [region.position.x, region.position.x + 1, region.end.x - 2, region.end.x - 1]:
			navigation.set_point_solid(Vector2i(x, z))
	for x in range(region.position.x, region.end.x):
		for z in [region.position.y, region.position.y + 1, region.end.y - 2, region.end.y - 1]:
			navigation.set_point_solid(Vector2i(x, z))
	return navigation

func _nearest_vehicle_cell(point: Vector3, navigation: AStarGrid2D, controller: Node3D) -> Vector2i:
	var center := Vector2i(roundi(point.x), roundi(point.z))
	for radius in range(0, 7):
		var best := Vector2i(999, 999)
		var best_distance := INF
		for z in range(center.y - radius, center.y + radius + 1):
			for x in range(center.x - radius, center.x + radius + 1):
				var cell := Vector2i(x, z)
				if not navigation.is_in_boundsv(cell) or navigation.is_point_solid(cell):continue
				var waypoint := Vector3(x, controller.outpost_height(Vector3(x, 0, z)), z)
				if not _segment_clear(point, waypoint, controller):continue
				var distance := Vector2(point.x - x, point.z - z).length_squared()
				if distance < best_distance:best = cell;best_distance = distance
		if best.x != 999:return best
	return Vector2i(999, 999)

func command_move(destination: Vector3, controller: Node3D) -> bool:
	if not _movement_active(controller) or not destination.is_finite():return false
	var origin: Vector3 = controller.to_local(global_position)
	var goal := destination
	goal.y = controller.outpost_height(goal)
	if not _body_clear(origin, controller) or not _body_clear(goal, controller):return false
	var route: Array[Vector3] = []
	if _segment_clear(origin, goal, controller):
		route.append(goal)
	else:
		var navigation := _vehicle_navigation(controller)
		if not is_instance_valid(navigation):return false
		var start_cell := _nearest_vehicle_cell(origin, navigation, controller)
		var end_cell := _nearest_vehicle_cell(goal, navigation, controller)
		if start_cell.x == 999 or end_cell.x == 999:return false
		var grid_path: PackedVector2Array = navigation.get_point_path(start_cell, end_cell)
		if grid_path.is_empty():return false
		var cursor := origin
		var index := 0
		while index < grid_path.size():
			var furthest := index
			for step in range(index, grid_path.size()):
				var point := Vector3(grid_path[step].x, 0, grid_path[step].y)
				if _segment_clear(cursor, point, controller):furthest = step
				else:break
			var waypoint := Vector3(grid_path[furthest].x, 0, grid_path[furthest].y)
			if not _segment_clear(cursor, waypoint, controller):return false
			waypoint.y = controller.outpost_height(waypoint)
			route.append(waypoint)
			cursor = waypoint
			index = furthest + 1
		if not _segment_clear(cursor, goal, controller):return false
		route.append(goal)
	# Commit only a complete reachable route. An invalid right-click preserves
	# the prior destination, permit identity and all economic state.
	path_points.assign(route)
	return true

func advance_movement(delta: float, controller: Node3D) -> void:
	if not _movement_active(controller) or delta <= 0.0 or path_points.is_empty():return
	var budget := maxf(0.0, move_speed) * delta
	while budget > .00001 and not path_points.is_empty():
		var origin: Vector3 = controller.to_local(global_position)
		var goal: Vector3 = path_points[0]
		var direction := Vector3(goal.x - origin.x, 0, goal.z - origin.z)
		var distance := direction.length()
		if distance < .02:
			path_points.pop_front()
			continue
		var travelled := minf(MAX_MOVEMENT_STEP, minf(distance, budget))
		var next := origin + direction / distance * travelled
		next.y = controller.outpost_height(next)
		if not next.is_finite() or not _segment_clear(origin, next, controller):
			path_points.clear()
			return
		global_position = controller.to_global(next)
		if is_instance_valid(chassis):chassis.rotation.y = lerp_angle(chassis.rotation.y, atan2(direction.x, direction.z), minf(1.0, travelled / maxf(.001, move_speed) * 8.0))
		for wheel: MeshInstance3D in wheels:
			if is_instance_valid(wheel):wheel.rotate_object_local(Vector3.UP, travelled / .27)
		budget -= travelled
		if travelled >= distance - .00001:path_points.pop_front()

func open() -> bool:
	if opened:return false
	opened = true
	path_points.clear()
	set_selected(false)
	visible = false
	return true
