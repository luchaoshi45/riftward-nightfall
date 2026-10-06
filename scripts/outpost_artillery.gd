extends Node3D
## 炮手的前摇/CD由真实BattleUnit.tick唯一推进；已发弹独立拥有落点和伤害。
const MIN_RANGE := 5.5
const MAX_RANGE := 16.0
const WINDUP := 1.0
const FLIGHT := .8
const COOLDOWN := 4.8
const RADIUS := 2.2
const HEIGHT_LIMIT := .9
const IMPACT := .24
const SEGMENTS := 48

var game: Node3D
var _units: Dictionary = {}
var _shots: Array[Dictionary] = []
var _launched := 0
var _impacts := 0
var _hits := 0
var _epoch := 0
var _has_combat := false

func setup(controller: Node3D) -> void:
	clear()
	game = controller
	for property: Dictionary in game.get_property_list():
		if String(property.name) == "combat": _has_combat = true

func register(source: BattleUnit) -> void:
	_units[source.get_instance_id()] = {"unit": weakref(source), "cast": {}}

func _living(unit: Variant) -> bool:
	return is_instance_valid(unit) and unit is BattleUnit and not unit.is_queued_for_deletion() and unit.alive and unit.hp > 0.0

func real_enemy(unit: Variant) -> bool:
	return _living(unit) and unit.kind == "monster" and unit.team == 2 and is_instance_valid(game) and unit in game.get("enemies")

func distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x,from.z).distance_to(Vector2(to.x,to.z))

func _height(point: Vector3) -> float:
	return float(game.call("outpost_height",point)) if game.has_method("outpost_height") else point.y

func _line(from: Vector3, to: Vector3) -> bool:
	# Production attack LOS excludes friendly building footprints, while the
	# actual castle walls remain solid. Movement still uses the full nav map.
	return not game.has_method("can_attack_line") or bool(game.call("can_attack_line",from,to))

func ground_compatible(from: Vector3, to: Vector3) -> bool:
	if not from.is_finite() or not to.is_finite(): return false
	var first := _height(from)
	var second := _height(to)
	var source_offset := from.y-first
	var target_offset := to.y-second
	return is_finite(first) and is_finite(second) and absf(source_offset) <= HEIGHT_LIMIT+.000001 \
		and absf(target_offset) <= HEIGHT_LIMIT+.000001 and absf(source_offset-target_offset) <= HEIGHT_LIMIT+.000001

func legal_target(source: BattleUnit, target: Variant) -> bool:
	if not _living(source) or not real_enemy(target): return false
	var separation := distance(source.position,target.position)
	return separation >= MIN_RANGE and separation <= MAX_RANGE and ground_compatible(source.position,target.position) and _line(source.position,target.position)

func pick_target(source: BattleUnit, preferred: BattleUnit = null) -> BattleUnit:
	if legal_target(source,preferred): return preferred
	var chosen: BattleUnit
	var best := INF
	for candidate: Variant in game.get("enemies"):
		if not legal_target(source,candidate): continue
		var separation := distance(source.position,candidate.position)
		if separation < best: best = separation; chosen = candidate as BattleUnit
	return chosen

func casting(source: BattleUnit) -> bool:
	if not is_instance_valid(source): return false
	return not (_units.get(source.get_instance_id(),{}).get("cast",{}) as Dictionary).is_empty()

func begin(source: BattleUnit, target: BattleUnit) -> bool:
	if not is_instance_valid(game) or String(game.get("phase")) not in ["day","night"]: return false
	if not legal_target(source,target) or source.attack_timer > 0.0 or source.moving or casting(source): return false
	var state: Dictionary = _units.get(source.get_instance_id(),{})
	if state.is_empty(): return false
	var point := target.position
	point.y = _height(point)
	var shot := {"phase": "windup", "remaining": WINDUP, "total": WINDUP, "point": point,
		"source_token": source.get_instance_id(), "target_token": target.get_instance_id(),
		"source_ref": weakref(source), "target_ref": weakref(target), "source_position": source.position,
		"origin": source.position + Vector3.UP*1.25, "damage": 0.0, "visual": null,
		"ring": null, "progress": null, "projectile": null, "progress_radius": -1.0}
	state.cast = shot
	source.target = target
	source.attack_queued = true
	source.attack_windup = WINDUP
	source.face(point,.05)
	_create_warning(shot)
	_update_visual(shot)
	return true

func advance_unit(source: BattleUnit, delta: float) -> void:
	if not is_instance_valid(game) or String(game.get("phase")) not in ["day","night"] or not is_finite(delta) or delta <= 0.0: return
	var state: Dictionary = _units.get(source.get_instance_id(),{})
	var shot: Dictionary = state.get("cast",{})
	if shot.is_empty(): return
	var target := (shot.target_ref as WeakRef).get_ref() as BattleUnit
	if not _living(source) or source.moving or source.position.distance_to(shot.source_position) > .01 or not legal_target(source,target):
		cancel(source)
		return
	# The owning squad has already called source.tick(delta). Do not subtract
	# delta again or spend a start frame against the complete new preparation.
	shot.remaining = source.attack_windup
	source.face(shot.point,delta)
	_update_visual(shot)
	if source.attack_windup > 0.0: return
	state.cast = {}
	source.target = null
	source.attack_queued = false
	source.attack_windup = 0.0
	source.attack_timer = COOLDOWN
	source.attack_pose = 1.0
	shot.phase = "flight"
	shot.remaining = FLIGHT
	shot.total = FLIGHT
	shot.damage = maxf(0.0,source.damage)
	shot.origin = source.position + Vector3.UP*1.25
	_shots.append(shot)
	_launched += 1
	_create_projectile(shot)
	_update_visual(shot)

func cancel(source: BattleUnit) -> void:
	if not is_instance_valid(source): return
	var state: Dictionary = _units.get(source.get_instance_id(),{})
	var shot: Dictionary = state.get("cast",{})
	if not shot.is_empty(): _free_visual(shot)
	if not state.is_empty(): state.cast = {}
	source.target = null
	source.attack_queued = false
	source.attack_windup = 0.0

func unregister(source: BattleUnit) -> void:
	if not is_instance_valid(source): return
	cancel(source)
	_units.erase(source.get_instance_id())

func advance(delta: float) -> void:
	if not is_instance_valid(game) or String(game.get("phase")) not in ["day","night"] or not is_finite(delta) or delta <= 0.0: return
	var generation := _epoch
	# Damage signals can synchronously clear the entire controller. Iterate a
	# stable view and stop after a lifecycle change, never reuse retired shots.
	for shot: Dictionary in _shots.duplicate():
		if generation != _epoch: return
		shot.remaining = maxf(0.0,float(shot.remaining)-delta)
		_update_visual(shot)
		if float(shot.remaining) > 0.0: continue
		if String(shot.phase) == "flight": _impact(shot,generation)
		else:
			_free_visual(shot)
			_shots.erase(shot)

func _covered(point: Vector3, center: Vector3) -> bool:
	return point.is_finite() and distance(point,center) <= RADIUS+.000001 and ground_compatible(center,point) and _line(center,point)

func _impact(shot: Dictionary, generation: int) -> void:
	# Mark once-only commitment before hurt() can reenter clear, phase changes,
	# or another damage callback. No reacquisition of the original target.
	shot.phase = "impact"
	shot.remaining = IMPACT
	shot.total = IMPACT
	_impacts += 1
	var projectile: Node = shot.projectile as Node
	if is_instance_valid(projectile): projectile.queue_free()
	shot.projectile = null
	var point: Vector3 = shot.point
	var amount := float(shot.damage)
	var victims: Array = game.get("enemies").duplicate()
	var struck: Dictionary = {}
	for value: Variant in victims:
		if generation != _epoch or String(shot.phase) != "impact" or String(game.get("phase")) not in ["day","night"]: return
		if not real_enemy(value) or not _covered(value.position,point): continue
		var token: int = value.get_instance_id()
		if struck.has(token): continue
		struck[token] = true
		var source := (shot.source_ref as WeakRef).get_ref() as BattleUnit
		if not is_instance_valid(source) or source.is_queued_for_deletion(): source = null
		_hits += 1
		(value as BattleUnit).hurt(amount,source)

func _create_warning(shot: Dictionary) -> void:
	var visual := Node3D.new()
	visual.name = "ArtilleryFixedLanding"
	add_child(visual)
	shot.visual = visual
	shot.ring = _ring(shot,RADIUS,.035,.085,Color("73bcb8"))
	(shot.ring as Node).name = "ArtilleryGroundRadius"
	shot.progress_radius = RADIUS*.1
	shot.progress = _ring(shot,float(shot.progress_radius),.022,.12,Color("a1cdca"))
	(shot.progress as Node).name = "ArtilleryGroundCountdown"

func _ring(shot: Dictionary, radius: float, width: float, lift: float, tint: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var material := BattleVisuals.material(tint,.06)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.a = .54
	material.albedo_color = tint
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(shot.visual as Node).add_child(node)
	node.position = shot.point
	_resample_ring(node,shot.point,radius,width,lift)
	return node

func _resample_ring(node: MeshInstance3D, center: Vector3, radius: float, width: float, lift: float) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for step in SEGMENTS:
		var radial := Vector2(cos(TAU*float(step)/SEGMENTS),sin(TAU*float(step)/SEGMENTS))
		for edge_radius in [maxf(.02,radius-width),radius+width]:
			var offset := radial*float(edge_radius)
			var point := center+Vector3(offset.x,0,offset.y)
			vertices.append(Vector3(offset.x,_height(point)+lift-center.y,offset.y))
			normals.append(Vector3.UP)
		var current := step*2
		var next := ((step+1)%SEGMENTS)*2
		indices.append_array(PackedInt32Array([current,next,current+1,current+1,next,next+1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	node.mesh = mesh

func _create_projectile(shot: Dictionary) -> void:
	var projectile := MeshInstance3D.new()
	projectile.name = "ArtilleryNativeShell"
	var mesh := SphereMesh.new()
	mesh.radius = .12
	mesh.height = .24
	mesh.radial_segments = 8
	mesh.rings = 4
	projectile.mesh = mesh
	projectile.material_override = BattleVisuals.material(Color("9bc4be"),.10)
	projectile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(shot.visual as Node).add_child(projectile)
	shot.projectile = projectile

func _reduced() -> bool:
	if not _has_combat or not is_instance_valid(game): return false
	var combat: Variant = game.get("combat")
	return combat != null and bool(combat.reduced_effects)

func _update_visual(shot: Dictionary) -> void:
	var reduced := _reduced()
	for key in ["ring","progress"]:
		var ring: MeshInstance3D = shot[key] as MeshInstance3D
		if not is_instance_valid(ring): continue
		var material := ring.material_override as StandardMaterial3D
		var tint := material.albedo_color
		tint.a = .30 if reduced else .54
		material.albedo_color = tint
		material.emission_energy_multiplier = .02 if reduced else .06
	var progress: MeshInstance3D = shot.progress as MeshInstance3D
	var remaining := float(shot.remaining)+(FLIGHT if String(shot.phase)=="windup" else 0.0)
	var fraction := 1.0 if String(shot.phase)=="impact" else 1.0-clampf(remaining/(WINDUP+FLIGHT),0.0,1.0)
	var radius := RADIUS*maxf(.1,fraction)
	if is_instance_valid(progress) and not is_equal_approx(float(shot.progress_radius),radius):
		shot.progress_radius = radius
		_resample_ring(progress,shot.point,radius,.022,.12)
	var projectile: MeshInstance3D = shot.projectile as MeshInstance3D
	if is_instance_valid(projectile):
		var flight_progress := 1.0-clampf(float(shot.remaining)/FLIGHT,0.0,1.0)
		projectile.position = (shot.origin as Vector3).lerp((shot.point as Vector3)+Vector3.UP*.14,flight_progress)+Vector3.UP*(3.2*4.0*flight_progress*(1.0-flight_progress))
		(projectile.material_override as StandardMaterial3D).emission_energy_multiplier = .02 if reduced else .10

func _free_visual(shot: Dictionary) -> void:
	var visual: Node = shot.get("visual") as Node
	if is_instance_valid(visual): visual.queue_free()
	for key in ["visual","ring","progress","projectile"]: shot[key] = null

func clear_pending() -> void:
	_epoch += 1
	for state: Dictionary in _units.values():
		var source := (state.unit as WeakRef).get_ref() as BattleUnit
		if is_instance_valid(source): cancel(source)
		else:
			var shot: Dictionary = state.cast
			if not shot.is_empty(): _free_visual(shot)
			state.cast = {}
	for shot: Dictionary in _shots: _free_visual(shot)
	_shots.clear()

func clear() -> void:
	clear_pending()
	_units.clear()
	_launched = 0
	_impacts = 0
	_hits = 0
	_has_combat = false

func snapshot() -> Dictionary:
	# No clock advancement, roster pruning, visual creation or target lookup
	# mutates a gameplay state when the HUD reads this presentation snapshot.
	var shots: Array[Dictionary] = []
	var units: Array[Dictionary] = []
	var casting_count := 0
	for state: Dictionary in _units.values():
		var source := (state.unit as WeakRef).get_ref() as BattleUnit
		if not _living(source): continue
		var cast: Dictionary = state.cast
		var is_casting := not cast.is_empty()
		if is_casting:
			casting_count += 1
			shots.append(_shot_snapshot(cast,source.attack_windup))
		units.append({"source_token": source.get_instance_id(), "cooldown": source.attack_timer,
			"casting": is_casting, "remaining": source.attack_windup if is_casting else 0.0,
			"target_token": int(cast.get("target_token",-1))})
	var flight_count := 0
	for shot: Dictionary in _shots:
		shots.append(_shot_snapshot(shot,float(shot.remaining)))
		if String(shot.phase) == "flight": flight_count += 1
	return {"launched": _launched, "impacts": _impacts, "hits": _hits,
		"pending": casting_count+flight_count, "casting": casting_count, "flight": flight_count,
		"shots": shots, "units": units}

func _shot_snapshot(shot: Dictionary, remaining: float) -> Dictionary:
	return {"phase": String(shot.phase), "point": shot.point, "position": shot.point,
		"remaining": remaining, "total": float(shot.total), "radius": RADIUS,
		"source_token": int(shot.source_token), "target_token": int(shot.target_token)}

func _exit_tree() -> void:
	clear()
