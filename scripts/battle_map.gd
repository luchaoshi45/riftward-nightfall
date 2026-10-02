class_name BattleMap
extends RefCounted
## Single source of truth for terrain, navigation, lane routes and minimap.
const HALF_WIDTH := 42.0
const HALF_HEIGHT := 27.0
const LANE_NAMES := ["上路", "中路", "下路"]
const FORESTS := [Vector3(-24,0,-9),Vector3(24,0,-9),Vector3(-24,0,9),Vector3(24,0,9),Vector3(-7,0,-13),Vector3(7,0,-13),Vector3(-7,0,13),Vector3(7,0,13)]
const FOREST_RADIUS := 3.5
const CAMPS := [Vector3(-15,0,-11),Vector3(-15,0,11),Vector3(15,0,-11),Vector3(15,0,11)]

static func home(team: int) -> Vector3:
	return Vector3(-38 if team == 0 else 38,0,0)

static func route(lane: int, team: int = 0) -> PackedVector3Array:
	var points := PackedVector3Array()
	if lane == 1:
		points = PackedVector3Array([Vector3(-38,0,0),Vector3(-28,0,0),Vector3(-12,0,0),Vector3(0,0,0),Vector3(12,0,0),Vector3(28,0,0),Vector3(38,0,0)])
	else:
		var side := -1.0 if lane == 0 else 1.0
		points = PackedVector3Array([Vector3(-38,0,0),Vector3(-30,0,side*16),Vector3(-22,0,side*22),Vector3(-12,0,side*22),Vector3(0,0,side*22),Vector3(12,0,side*22),Vector3(22,0,side*22),Vector3(30,0,side*16),Vector3(38,0,0)])
	if team == 1: points.reverse()
	return points

static func tower_point(team: int, lane: int, tier: int) -> Vector3:
	var side := -1.0 if team == 0 else 1.0
	if lane == 1: return Vector3(side * (12 if tier == 0 else 28),0,0)
	return Vector3(side * (12 if tier == 0 else 29.5),0,(-1 if lane == 0 else 1) * (22.0 if tier == 0 else 16.4))

static func bounded(point: Vector3) -> Vector3:
	return Vector3(clampf(point.x,-HALF_WIDTH,HALF_WIDTH),0,clampf(point.z,-HALF_HEIGHT,HALF_HEIGHT))

static func walkable(point: Vector3) -> bool:
	if absf(point.x)>HALF_WIDTH or absf(point.z)>HALF_HEIGHT: return false
	for forest in FORESTS:
		if point.distance_to(forest) < FOREST_RADIUS + .45: return false
	return true

static func segment_clear(from: Vector3, to: Vector3) -> bool:
	if not walkable(to): return false
	for forest in FORESTS:
		if Geometry3D.get_closest_point_to_segment(forest,from,to).distance_to(forest)<FOREST_RADIUS+.45: return false
	return true

static func minimap_position(point: Vector3, area: Rect2) -> Vector2:
	return area.position + Vector2((point.x+44)/88.0,(point.z+30)/60.0)*area.size

static func minimap_world(point: Vector2, area: Rect2) -> Vector3:
	var uv := (point-area.position)/area.size
	return bounded(Vector3(uv.x*88-44,0,uv.y*60-30))
