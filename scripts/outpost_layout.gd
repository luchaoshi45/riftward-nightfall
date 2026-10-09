class_name OutpostLayout
extends RefCounted
## Shared authored castle geometry. Movement, scenery and generated terrain
## read these dimensions instead of carrying separate gate coordinates.

const FORT_HEIGHT := 5.0
const FORT_INNER := 22.0
const CASTLE_HORIZONTAL_SCALE := FORT_INNER / 13.0
const FORT_OUTER := 24.70769230769231
const WALL_CENTER := 23.35384615384615
const GATE_HALF := 4.484615384615385
const RAMP_INNER_HALF := 4.4
const RAMP_OUTER_HALF := 6.6
const RAMP_SURFACE_HALF := 5.415384615384616
const RAMP_TOP := 22.84615384615385
const RAMP_WALL_START := 24.53846153846154
const RAMP_WALL_END := 42.47692307692308
const RAMP_END := 43.15384615384615
const FORT_TERRAIN_EDGE := 27.07692307692308
const EXPANSION_OFFSET := 15.5
# X/Z dimensions match the horizontally enlarged authored ground; Y remains
# five metres. The wider wilderness contains three open satellite castles.
const MAP_HALF_X := 190.0
const MAP_HALF_Z := 160.0
const SATELLITE_WALL_WIDTH := 1.35
const SATELLITE_WALL_HEIGHT := 3.4
const SATELLITE_CASTLES: Array[Dictionary] = [
	{"name":"西北石堡", "position":Vector3(-90.0,0.0,-65.0), "half_extent":16.0, "gate_half":3.5},
	{"name":"东北旧堡", "position":Vector3(100.0,0.0,-45.0), "half_extent":17.0, "gate_half":3.5},
	{"name":"南部边堡", "position":Vector3(-75.0,0.0,105.0), "half_extent":15.0, "gate_half":3.5},
]

# Natural obstacles are deliberately placed in the far perimeter. They make
# route choice matter without sealing the south gate, contract staging area or
# the three existing nest approaches.
const LAKE_AREAS: Array[Rect2] = [
	Rect2(70.0, -91.0, 34.0, 26.0),
	Rect2(-112.0, 61.0, 30.0, 22.0),
]
const MOUNTAIN_AREAS: Array[Rect2] = [
	Rect2(-139.0, -101.0, 30.0, 48.0),
	Rect2(101.0, 46.0, 40.0, 30.0),
]

static func terrain_blocks() -> Array[Rect2]:
	var blocks: Array[Rect2] = []
	for area: Rect2 in LAKE_AREAS:
		blocks.append(area.grow(.65))
	for area: Rect2 in MOUNTAIN_AREAS:
		blocks.append(area.grow(.35))
	return blocks

static func terrain_blocked(point: Vector3, margin: float = 0.0) -> bool:
	if not point.is_finite():return true
	for area: Rect2 in LAKE_AREAS:
		if area.grow(margin).has_point(Vector2(point.x, point.z)):return true
	for area: Rect2 in MOUNTAIN_AREAS:
		if area.grow(margin).has_point(Vector2(point.x, point.z)):return true
	return false

static func wall_blocks() -> Array[Rect2]:
	var wall_width := FORT_OUTER-FORT_INNER
	var side_length := FORT_OUTER*2.0
	var south_length := FORT_OUTER-GATE_HALF
	var ramp_width := RAMP_OUTER_HALF-RAMP_INNER_HALF
	var ramp_length := RAMP_WALL_END-RAMP_WALL_START
	var blocks: Array[Rect2] = [
		Rect2(-FORT_OUTER,-FORT_OUTER,wall_width,side_length),
		Rect2(FORT_INNER,-FORT_OUTER,wall_width,side_length),
		Rect2(-FORT_OUTER,-FORT_OUTER,side_length,wall_width),
		Rect2(-FORT_OUTER,FORT_INNER,south_length,wall_width),
		Rect2(GATE_HALF,FORT_INNER,south_length,wall_width),
		Rect2(-RAMP_OUTER_HALF,RAMP_WALL_START,ramp_width,ramp_length),
		Rect2(RAMP_INNER_HALF,RAMP_WALL_START,ramp_width,ramp_length),
	]
	for castle: Dictionary in SATELLITE_CASTLES:
		blocks.append_array(satellite_wall_blocks(castle))
	return blocks

static func satellite_wall_blocks(castle: Dictionary) -> Array[Rect2]:
	var point: Vector3 = castle.position
	var inner: float = float(castle.half_extent)
	var outer := inner + SATELLITE_WALL_WIDTH
	var gate: float = float(castle.gate_half)
	var corner := Vector2(point.x,point.z)
	# A seven-metre south opening is genuine free navigation space. The stone
	# is represented by these same rectangles for rendering and traversal.
	return [
		Rect2(corner+Vector2(-outer,-outer),Vector2(SATELLITE_WALL_WIDTH,outer*2.0)),
		Rect2(corner+Vector2(inner,-outer),Vector2(SATELLITE_WALL_WIDTH,outer*2.0)),
		Rect2(corner+Vector2(-outer,-outer),Vector2(outer*2.0,SATELLITE_WALL_WIDTH)),
		Rect2(corner+Vector2(-outer,inner),Vector2(outer-gate,SATELLITE_WALL_WIDTH)),
		Rect2(corner+Vector2(gate,inner),Vector2(outer-gate,SATELLITE_WALL_WIDTH)),
	]

static func satellite_contains(point: Vector3, margin: float=0.0) -> bool:
	if not point.is_finite():return false
	for castle: Dictionary in SATELLITE_CASTLES:
		var center: Vector3 = castle.position
		var limit := float(castle.half_extent) + margin
		if absf(point.x-center.x)<=limit and absf(point.z-center.z)<=limit:return true
	return false

static func buildable_height(point: Vector3) -> float:
	if not point.is_finite():return INF
	if contains_castle(point):return FORT_HEIGHT
	if satellite_contains(point):return 0.0
	return INF

static func terrain_height(point: Vector3) -> float:
	var edge := maxf(absf(point.x),absf(point.z))
	var rise: float
	if point.z>RAMP_TOP and absf(point.x)<RAMP_SURFACE_HALF:
		rise=clampf((RAMP_END-point.z)/(RAMP_END-RAMP_TOP),0.0,1.0)
	else:
		rise=clampf((FORT_TERRAIN_EDGE-edge)/(FORT_TERRAIN_EDGE-RAMP_TOP),0.0,1.0)
	return FORT_HEIGHT*rise*rise*(3.0-2.0*rise)

static func contains_castle(point: Vector3, margin: float=0.0) -> bool:
	var limit := maxf(0.0,FORT_INNER-margin)
	return absf(point.x)<=limit and absf(point.z)<=limit

static func gate_point(z_offset: float=0.0) -> Vector3:
	var point := Vector3(0.0,0.0,WALL_CENTER+z_offset)
	point.y=terrain_height(point)
	return point
