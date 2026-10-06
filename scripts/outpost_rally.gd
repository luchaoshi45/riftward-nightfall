extends RefCounted
## Per-generation barracks destinations. Choosing or drawing a marker never
## issues a squad order; only a finished paid training reads this configuration.
const Layout := preload("res://scripts/outpost_layout.gd")
const Visuals := preload("res://scripts/visuals.gd")
const HEIGHT_TOLERANCE := .075
const MARKER_RADIUS := .55
const MARKER_WIDTH := .045

var game: Node3D
var active := false
var _selected := -1
var _selected_token := -1
var _setting_id := -1
var _setting_token := -1
var _destinations: Dictionary = {}
var _marker: Node3D
var _circle: MeshInstance3D
var _flag: MeshInstance3D
var _marker_point := Vector3.INF
var _marker_preview := false

func setup(controller: Node3D) -> void:
	clear()
	game = controller

func _barracks() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not is_instance_valid(game): return rows
	var districts: Node = game.get("districts") as Node
	if not is_instance_valid(districts): return rows
	var plots: Array = districts.get("plots")
	for index in plots.size():
		var plot: Dictionary = plots[index]
		if bool(plot.get("removed", false)) or String(plot.get("kind", "")) != "barracks": continue
		if int(plot.get("level", 0)) <= 0 or float(plot.get("hp", 0.0)) <= 0.0: continue
		var model: Variant = plot.get("model")
		if not is_instance_valid(model) or not model is Node3D or model.is_queued_for_deletion(): continue
		rows.append({"index": index, "token": int(model.get_instance_id()), "position": plot.position})
	return rows

func _row(id: int, rows: Array[Dictionary]) -> Dictionary:
	for row: Dictionary in rows:
		if int(row.index) == id: return row
	return {}

func _sync(rows: Array[Dictionary]) -> void:
	for id: int in _destinations.keys():
		var row := _row(id, rows)
		if row.is_empty() or int(row.token) != int(_destinations[id].token): _destinations.erase(id)
	if _selected >= 0:
		var selected_row := _row(_selected, rows)
		if selected_row.is_empty() or int(selected_row.token) != _selected_token:
			_selected = -1
			_selected_token = -1
	if active:
		var setting_row := _row(_setting_id, rows)
		if setting_row.is_empty() or int(setting_row.token) != _setting_token: cancel_setting()

func selection_id() -> int:
	_sync(_barracks())
	return _selected

func _can_browse() -> bool:
	return is_instance_valid(game) and String(game.get("phase")) in ["day", "night", "paused"]

func _can_change() -> bool:
	return is_instance_valid(game) and String(game.get("phase")) in ["day", "night"]

func cycle_selection(direction: int) -> int:
	var rows := _barracks()
	_sync(rows)
	if not _can_browse() or direction == 0: return _selected
	var ids: Array[int] = [-1]
	for row: Dictionary in rows: ids.append(int(row.index))
	var current := ids.find(_selected)
	var next := posmod(maxi(0, current) + (1 if direction > 0 else -1), ids.size())
	cancel_setting()
	_selected = ids[next]
	_selected_token = -1 if _selected < 0 else int(_row(_selected, rows).token)
	return _selected

func snapshot() -> Dictionary:
	var id := selection_id()
	var destination := destination_for(id)
	return {"barracks_id": id, "configured": bool(destination.enabled), "point": destination.point,
		"active": active, "title": "自动选营" if id < 0 else "兵营%d" % (id + 1)}

func _result(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": reason}

func begin_setting() -> Dictionary:
	if not _can_change(): return _result(false, "暂停或选卡时不能设置集结点")
	var rows := _barracks()
	_sync(rows)
	var row := _row(_selected, rows)
	if row.is_empty(): return _result(false, "先选择一座存活兵营")
	_setting_id = _selected
	_setting_token = int(row.token)
	active = true
	return _result(true, "左键指定集结点 · 右键/Esc取消")

func cancel_setting() -> void:
	active = false
	_setting_id = -1
	_setting_token = -1

func _on_map(point: Vector3) -> bool:
	return point.is_finite() and absf(point.x) <= Layout.MAP_HALF_X and absf(point.z) <= Layout.MAP_HALF_Z

func _ground_height(point: Vector3) -> float:
	var squads: Node = game.get("squads") as Node
	if is_instance_valid(squads) and squads.has_method("_ground_height"):
		return float(squads.call("_ground_height", point))
	return float(game.call("outpost_height", point))

func _movement_route_reaches(origin: Vector3, destination: Vector3) -> bool:
	if bool(game.call("can_traverse", origin, destination)): return true
	var navigation: AStarGrid2D = game.get("hero_navigation") as AStarGrid2D
	if not is_instance_valid(navigation): return false
	var start: Vector2i = game.call("nearest_navigation_cell", origin, true)
	var finish: Vector2i = game.call("nearest_navigation_cell", destination, false)
	if start.x == 999 or finish.x == 999: return false
	var path := navigation.get_point_path(start, finish)
	if path.is_empty(): return false
	# Match build_day_hunter_route's cell choice and continuous smoothing. A
	# generic reachability query can choose a different last cell beside a wall.
	var cursor := origin
	var index := 0
	while index < path.size():
		var furthest := index
		for candidate in range(index, path.size()):
			var point := Vector3(path[candidate].x, 0, path[candidate].y)
			if bool(game.call("can_traverse", cursor, point)): furthest = candidate
			else: break
		var waypoint := Vector3(path[furthest].x, 0, path[furthest].y)
		if not bool(game.call("can_traverse", cursor, waypoint)): return false
		cursor = waypoint
		index = furthest + 1
	return bool(game.call("can_traverse", cursor, destination))

func _validation(row: Dictionary, point: Vector3) -> Dictionary:
	if not _on_map(point): return _result(false, "集结点必须位于可通行地图内")
	var height := _ground_height(point)
	if not is_finite(height) or absf(point.y - height) > HEIGHT_TOLERANCE:
		return _result(false, "请选择贴合真实地面的集结点")
	var grounded := Vector3(point.x, height, point.z)
	if not bool(game.call("outpost_walkable", grounded)):
		return _result(false, "集结点不能位于城墙或建筑内")
	var squads: Node = game.get("squads") as Node
	if not is_instance_valid(squads): return _result(false, "部队系统尚未初始化")
	var births: Array[Vector3] = squads.call("rally_spawn_points", row.position)
	var stations: Array[Vector3] = squads.call("rally_station_points", grounded)
	if births.size() != 3 or stations.size() != 3: return _result(false, "兵营出生站位无效")
	for slot in stations.size():
		var birth: Vector3 = births[slot]
		var station: Vector3 = stations[slot]
		if not _on_map(birth) or not _on_map(station): return _result(false, "三员集结站位必须位于地图内")
		if not bool(game.call("outpost_walkable", birth)) or not bool(game.call("outpost_walkable", station)):
			return _result(false, "兵营出口或三员集结站位被建筑阻挡")
		if absf(birth.y - _ground_height(birth)) > HEIGHT_TOLERANCE or absf(station.y - _ground_height(station)) > HEIGHT_TOLERANCE:
			return _result(false, "出生与集结站位必须贴合真实地面")
		if not _movement_route_reaches(birth, station):
			return _result(false, "该兵营三员无法沿真实路径抵达集结点")
	return {"ok": true, "reason": "", "point": grounded}

func commit(point: Vector3) -> Dictionary:
	if not active: return _result(false, "先开启集结点选择")
	var rows := _barracks()
	var row := _row(_setting_id, rows)
	if row.is_empty() or int(row.token) != _setting_token:
		cancel_setting()
		_sync(rows)
		return _result(false, "原兵营已失效，请重新选择")
	if not _can_change(): return _result(false, "暂停或选卡时不能设置集结点")
	var validation := _validation(row, point)
	if not bool(validation.ok): return validation
	_destinations[_setting_id] = {"token": _setting_token, "point": validation.point}
	cancel_setting()
	return _result(true, "该营后续出兵前往集结点 · 已出部队命令保留")

func reset_selected() -> Dictionary:
	if not _can_change(): return _result(false, "暂停或选卡时不能恢复默认集结")
	var id := selection_id()
	if id < 0: return _result(false, "先选择一座存活兵营")
	_destinations.erase(id)
	cancel_setting()
	return _result(true, "该营后续出兵恢复默认 · 已出部队命令保留")

func destination_for(barracks_id: int) -> Dictionary:
	var rows := _barracks()
	_sync(rows)
	var row := _row(barracks_id, rows)
	var destination: Dictionary = _destinations.get(barracks_id, {})
	if row.is_empty() or destination.is_empty() or int(row.token) != int(destination.token):
		return {"enabled": false, "point": Vector3.ZERO}
	return {"enabled": true, "point": destination.point}

func _ensure_marker() -> void:
	if is_instance_valid(_marker): return
	_marker = Node3D.new()
	_marker.name = "BarracksRallyMarker"
	game.add_child(_marker)
	_circle = MeshInstance3D.new()
	_marker.add_child(_circle)
	_circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pole := Visuals.box(_marker, Vector3(0, .58, 0), Vector3(.045, 1.16, .045), Visuals.material(Color("82948b")))
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flag = Visuals.box(_marker, Vector3(.16, .98, 0), Vector3(.32, .24, .035), Visuals.material(Color("a6ccb5")))
	_flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false

func _circle_point(center: Vector3, angle: float, radius: float) -> Vector3:
	var point := center + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
	return Vector3(point.x - center.x, _ground_height(point) - center.y + .055, point.z - center.z)

func _update_marker(point: Vector3, preview: bool) -> void:
	_ensure_marker()
	_marker.position = point
	_marker.visible = true
	if point == _marker_point and preview == _marker_preview: return
	_marker_point = point
	_marker_preview = preview
	var color := Color("b9b3a3") if preview else Color("a6ccb5")
	var material := Visuals.material(color, .08)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flag.material_override = material
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for index in 32:
		var first := TAU * float(index) / 32.0
		var next := TAU * float(index + 1) / 32.0
		var a := _circle_point(point, first, MARKER_RADIUS - MARKER_WIDTH)
		var b := _circle_point(point, first, MARKER_RADIUS + MARKER_WIDTH)
		var c := _circle_point(point, next, MARKER_RADIUS - MARKER_WIDTH)
		var d := _circle_point(point, next, MARKER_RADIUS + MARKER_WIDTH)
		for vertex: Vector3 in [a, b, c, b, d, c]:
			mesh.surface_set_normal(Vector3.UP)
			mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	_circle.mesh = mesh

func tick(_delta: float) -> void:
	_sync(_barracks())
	if not is_instance_valid(game): return
	var phase := String(game.get("phase"))
	var point := Vector3.INF
	var preview := false
	if active and phase in ["day", "night", "paused"]:
		var aimed: Vector3 = game.get("aim")
		if _on_map(aimed):
			point = Vector3(aimed.x, _ground_height(aimed), aimed.z)
			preview = true
	elif _can_browse():
		var hud: Control = game.get("hud") as Control
		if is_instance_valid(hud) and String(hud.get("detail_tab")) == "army":
			var destination := destination_for(_selected)
			if bool(destination.enabled): point = destination.point
	if point.is_finite(): _update_marker(point, preview)
	elif is_instance_valid(_marker): _marker.visible = false

func clear() -> void:
	cancel_setting()
	_selected = -1
	_selected_token = -1
	_destinations.clear()
	if is_instance_valid(_marker): _marker.queue_free()
	_marker = null
	_circle = null
	_flag = null
	_marker_point = Vector3.INF
	_marker_preview = false
	game = null
