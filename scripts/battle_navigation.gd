class_name BattleNavigation
extends RefCounted
var grid := AStarGrid2D.new()

func _init() -> void:
	grid.region = Rect2i(-21,-13,43,27)
	grid.cell_size = Vector2(2,2)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for x in range(-21,22):
		for y in range(-13,14):
			grid.set_point_solid(Vector2i(x,y),not BattleMap.walkable(Vector3(x*2,0,y*2)))

func nearest_cell(point: Vector3) -> Vector2i:
	var cell := Vector2i(roundi(clampf(point.x/2,-21,21)),roundi(clampf(point.z/2,-13,13)))
	if not grid.is_point_solid(cell): return cell
	var best := cell
	var distance := INF
	for x in range(-4,5):
		for y in range(-4,5):
			var candidate := cell+Vector2i(x,y)
			if not grid.region.has_point(candidate) or grid.is_point_solid(candidate): continue
			var d := Vector2(candidate).distance_to(Vector2(point.x,point.z)/2)
			if d<distance:
				distance=d
				best=candidate
	return best

func destination(point: Vector3) -> Vector3:
	var bounded := BattleMap.bounded(point)
	if BattleMap.walkable(bounded): return bounded
	var cell := nearest_cell(bounded)
	return Vector3(cell.x*2,0,cell.y*2)

func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var goal := destination(to)
	if BattleMap.segment_clear(from,goal): return PackedVector3Array([goal])
	var result := PackedVector3Array()
	for point in grid.get_point_path(nearest_cell(from),nearest_cell(goal)):
		result.append(Vector3(point.x,0,point.y))
	result.append(goal)
	return result

func dash(from: Vector3, to: Vector3) -> Vector3:
	var result := from
	var steps := maxi(1,ceili(from.distance_to(to)/.2))
	for i in range(1,steps+1):
		var point := from.lerp(to,float(i)/steps)
		if not BattleMap.walkable(point): break
		result=point
	return result
