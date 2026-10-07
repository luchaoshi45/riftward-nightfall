class_name OutpostLayout
extends RefCounted
## Shared authored castle geometry. Movement, scenery and generated terrain
## read these dimensions instead of carrying separate gate coordinates.

const FORT_HEIGHT := 5.0
const FORT_INNER := 13.0
const FORT_OUTER := 14.6
const WALL_CENTER := 13.8
const GATE_HALF := 2.65
const RAMP_INNER_HALF := 2.6
const RAMP_OUTER_HALF := 3.9
const RAMP_SURFACE_HALF := 3.2
const RAMP_TOP := 13.5
const RAMP_WALL_START := 14.5
const RAMP_WALL_END := 25.1
const RAMP_END := 25.5
const FORT_TERRAIN_EDGE := 16.0
const EXPANSION_OFFSET := 6.5
# The castle remains the authored 26 m core. The surrounding wilderness now
# has a wider play envelope so the camera can reveal landmarks before culling.
const MAP_HALF_X := 148.0
const MAP_HALF_Z := 128.0

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
	return [
		Rect2(-FORT_OUTER,-FORT_OUTER,wall_width,side_length),
		Rect2(FORT_INNER,-FORT_OUTER,wall_width,side_length),
		Rect2(-FORT_OUTER,-FORT_OUTER,side_length,wall_width),
		Rect2(-FORT_OUTER,FORT_INNER,south_length,wall_width),
		Rect2(GATE_HALF,FORT_INNER,south_length,wall_width),
		Rect2(-RAMP_OUTER_HALF,RAMP_WALL_START,ramp_width,ramp_length),
		Rect2(RAMP_INNER_HALF,RAMP_WALL_START,ramp_width,ramp_length),
	]

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
