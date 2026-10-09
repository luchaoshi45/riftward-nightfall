extends SceneTree
const Grid := preload("res://scripts/construction_grid.gd")
const Layout := preload("res://scripts/outpost_layout.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	push_error(message)

func distinct(cells: Array[Vector2i]) -> bool:
	var seen: Dictionary = {}
	for cell: Vector2i in cells: seen[cell] = true
	return seen.size() == cells.size()

func same_cells(left: Array[Vector2i], right: Array[Vector2i]) -> bool:
	if left.size() != right.size(): return false
	for cell: Vector2i in left:
		if not right.has(cell): return false
	return true

func run() -> void:
	check(Grid.CELL_SIZE == 1.0 and Grid.ORIGIN == Vector2(-22, -22) and Grid.CASTLE_CELLS == Rect2i(0, 0, 44, 44), "Grid covers the complete 44-metre castle at the shared layout origin")
	check(Grid.sizes("tower") == Vector2i(3, 3), "Tower uses three by three cells")
	check(Grid.sizes("barracks") == Vector2i(4, 3), "Barracks includes four by three working cells")
	check(Grid.sizes("workshop") == Vector2i(3, 2), "Workshop uses three by two cells")
	check(Grid.sizes("core") == Vector2i(6, 6) and Grid.sizes("unknown") == Vector2i.ZERO, "Core uses six by six cells; unknown kinds have no occupancy")
	for kind: String in ["tower", "barracks", "workshop", "core"]:
		var size := Grid.sizes(kind)
		for z: float in [-30.25, -13.0, -12.5, -8.0, -3.5, -0.5, 0.0, 0.5, 8.0, 11.5, 13.0, 28.75]:
			for x: float in [-28.75, -13.0, -12.5, -8.0, -3.5, -0.5, 0.0, 0.5, 8.0, 11.5, 13.0, 30.25]:
				var point := Vector3(x, 7.125, z)
				var place: Dictionary = Grid.placement(point, kind)
				var repeated: Dictionary = Grid.placement(place.point, kind)
				check(place.size == size and place.cells.size() == size.x * size.y and distinct(place.cells), "Placement owns every unique cell of its declared dimensions")
				check(place.point == repeated.point and place.anchor == repeated.anchor and place.cells == repeated.cells, "Odd/even snapping is idempotent across negative and outer coordinates")
				check(place.point.y == point.y, "Snapping preserves the requested elevation")
				check(same_cells(Grid.cells_for_rect(place.rect), place.cells), "A placed footprint rasters to exactly its declared cells")
				var center: Vector2 = (place.rect as Rect2).get_center()
				check(center == Vector2(place.point.x, place.point.z), "Snapped model center equals the occupied-cell rectangle center")
				check(bool(place.inside) == Grid.CASTLE_CELLS.encloses(Rect2i(place.anchor, size)), "Castle validity checks the entire footprint, including outer cells")
	check(Grid.placement(Vector3(5.5, 5, 10.5), "tower").point == Vector3(5.5, 5, 10.5), "The new right opening defense stays on its exact half-grid center")
	check(Grid.placement(Vector3(-5.5, 5, 10.5), "tower").point == Vector3(-5.5, 5, 10.5), "The new left opening defense stays on its exact half-grid center")
	check(Grid.placement(Vector3.ZERO, "core").point == Vector3.ZERO, "The even-sized core stays at world zero")
	check(Grid.placement(Vector3(-8, 5, -8), "workshop").point == Vector3(-7.5, 5, -8), "Workshop odd X and even Z use their respective half/whole centers")
	check(Grid.placement(Vector3(-8, 5, -8), "barracks").point == Vector3(-8, 5, -7.5), "Barracks even X and odd Z use their respective whole/half centers")
	var left: Dictionary = Grid.placement(Vector3(-8.5, 5, -8.5), "tower")
	var right: Dictionary = Grid.placement(Vector3(-5.5, 5, -8.5), "tower")
	check(not (left.rect as Rect2).intersects(right.rect), "Adjacent complete footprints share a boundary without overlapping")
	for cell: Vector2i in left.cells: check(not right.cells.has(cell), "Adjacent buildings never share an occupied cell")
	for kind: String in ["tower", "barracks", "workshop", "core"]:
		var size := Grid.sizes(kind)
		for anchor: Vector2i in [Vector2i.ZERO, Grid.CASTLE_CELLS.size - size]:
			var corner := Grid.ORIGIN + Vector2(anchor)
			var center := corner + Vector2(size) * .5
			check(bool(Grid.placement(Vector3(center.x, 5, center.y), kind).inside), "A full building may touch the castle grid boundary")
		for anchor: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(45 - size.x, 0), Vector2i(0, 45 - size.y)]:
			var center := Grid.ORIGIN + Vector2(anchor) + Vector2(size) * .5
			check(not bool(Grid.placement(Vector3(center.x, 5, center.y), kind).inside), "A single out-of-castle occupied cell refuses the whole placement")
	var whole := Grid.cells_for_rect(Rect2(Grid.ORIGIN, Vector2(Grid.CASTLE_CELLS.size)))
	check(whole.size() == 1936 and distinct(whole), "The full castle raster contains exactly 1936 unique cells")
	for z in Grid.CASTLE_CELLS.size.y:
		for x in Grid.CASTLE_CELLS.size.x:
			var cell := Vector2i(x, z)
			check(whole.has(cell) and Grid.cells_for_rect(Grid.cell_rect(cell)) == [cell], "Every castle cell round-trips through its exact half-open rectangle")
	check(Grid.cells_for_rect(Rect2(Grid.ORIGIN-Vector2(2, 2), Vector2.ONE)) == [Vector2i(-2, -2)], "Map cell math preserves negative indices outside the castle")
	check(Grid.cells_for_rect(Rect2(Grid.ORIGIN+Vector2(-.25, .25), Vector2(.5, .5))) == [Vector2i(-1, 0), Vector2i(0, 0)], "Partial rectangles include each cell with positive area overlap")
	check(Grid.cells_for_rect(Rect2(Grid.ORIGIN+Vector2.ONE, Vector2.ONE)) == [Vector2i(1, 1)], "Contact at integer end boundaries does not add neighbouring cells")
	check(Grid.placement(Vector3(20.5, 5, -19.5), "tower").inside, "Newly added main-city land accepts a complete tower footprint")
	check(Grid.build_regions().size()==4, "Main castle and three separate satellite courtyards expose four build grids")
	for castle: Dictionary in Layout.SATELLITE_CASTLES:
		var center: Vector3=castle.position
		var region := Grid.region_at(center)
		var size := int(float(castle.half_extent)*2.0)
		check(region.size==Vector2i(size,size), "Satellite grid covers its entire real courtyard")
		check(Grid.placement(center,"barracks").inside and Grid.placement(center,"tower").inside, "City and defense buildings both accept satellite yards")
		check(Layout.buildable_height(center)==0.0 and Layout.terrain_height(center)==0.0, "Satellite building surface is genuine flat outer ground")
		var gate := center+Vector3(0,0,float(castle.half_extent)+Layout.SATELLITE_WALL_WIDTH*.5)
		var gate_clear:=true
		for wall: Rect2 in Layout.satellite_wall_blocks(castle):
			if wall.has_point(Vector2(gate.x,gate.z)):gate_clear=false
		check(gate_clear, "Each satellite castle has a genuine open south gate")
		var boundary := center+Vector3(float(castle.half_extent),0,0)
		check(not Grid.placement(boundary,"barracks").inside, "Satellite placement refuses a footprint intersecting its wall")
		check(Grid.placement(center,"tower").point==Grid.placement(Grid.placement(center,"tower").point,"tower").point, "Satellite grids preserve half-cell snapping")
	var map_cells := Grid.cells_for_rect(Rect2(Vector2(-123, -107), Vector2(246, 214)))
	check(map_cells.size() == 52644 and distinct(map_cells), "A bounded wilderness region remains rasterable beyond castle bounds")
	for point: Vector3 in [Vector3(NAN, 5, 0), Vector3(0, INF, 0), Vector3(0, 5, -INF), Vector3(1e30, 5, 0)]:
		var invalid: Dictionary = Grid.placement(point, "tower")
		check(not bool(invalid.inside) and invalid.cells.is_empty() and invalid.size == Vector2i.ZERO and (invalid.point as Vector3).is_finite(), "Nonfinite or overflowing placement safely returns an empty finite result")
	check(Grid.placement(Vector3.ZERO, "unknown").cells.is_empty(), "Unknown building cannot claim cells")
	for rect: Rect2 in [Rect2(), Rect2(Vector2.ZERO, Vector2(-1, 2)), Rect2(Vector2(NAN, 0), Vector2.ONE), Rect2(Vector2.ZERO, Vector2(INF, 1)), Rect2(Vector2(-1e30, 0), Vector2.ONE), Rect2(Vector2.ZERO, Vector2(100000, 100000))]:
		check(Grid.cells_for_rect(rect).is_empty(), "Invalid or excessive rectangle raster safely returns no cells")
	print("CONSTRUCTION_GRID_FIXTURE_%s checks=%d full_castle=1936 full_map=%d odd_even negative_boundary idempotent safe_inputs" % ["OK" if failures.is_empty() else "FAILED", checks, map_cells.size()])
	quit(0 if failures.is_empty() else 1)
