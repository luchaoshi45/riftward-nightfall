class_name NightfallLobber
extends Node3D
## 固定落点投蚀：主机每活跃帧advance一次；源死亡后已抛出弹仍留在game下。
## false只允许主控制器继续南门寻路，不允许退回普通近战攻击。

const RANGE: float = 11.2
const WINDUP_SECONDS: float = 1.15
const FLIGHT_SECONDS: float = 0.75
const ATTACK_INTERVAL: float = 4.8
const BLAST_RADIUS: float = 2.0
const HEIGHT_TOLERANCE: float = 0.75
const IMPACT_SECONDS: float = 0.28
const WARNING_SEGMENTS: int = 48

var game: Node3D
var host: BattleUnit
var _state: String = "idle"
var _remaining: float = 0.0
var _cooldown: float = 0.0
var _point: Vector3 = Vector3.ZERO
var _origin: Vector3 = Vector3.ZERO
var _target: Dictionary = {}
var _damage: float = 0.0
var _cancel_reason: String = ""
var _launched: int = 0
var _impacts: int = 0
var _cancelled: int = 0
var _warning_root: Node3D
var _ring: MeshInstance3D
var _progress_ring: MeshInstance3D
var _projectile: MeshInstance3D
var _prototype_root: Node3D
var _progress_radius: float = -1.0

func setup(owner_game: Node3D, owner_host: BattleUnit) -> void:
	clear()
	game = owner_game
	host = owner_host
	if get_parent() == null and is_instance_valid(game): game.add_child(self)
	_state = "idle"
	_remaining = 0.0
	_cooldown = 0.0
	_cancel_reason = ""
	_launched = 0
	_impacts = 0
	_cancelled = 0
	if not _living(host): return
	host.title = "投蚀体"
	host.set_meta("threat", "lobber")
	host.attack_range = RANGE
	host.attack_interval = ATTACK_INTERVAL
	host.windup_duration = WINDUP_SECONDS
	if not host.defeated.is_connected(_on_host_defeated): host.defeated.connect(_on_host_defeated)
	_attach_prototype()

func advance(delta: float) -> bool:
	if not is_instance_valid(game):
		clear()
		return false
	var phase_name := String(game.get("phase"))
	if phase_name in ["paused", "draft"] or delta <= 0.0 or not is_finite(delta):
		return _state in ["windup", "flight", "impact"]
	if phase_name != "night":
		clear()
		return false
	_cooldown = maxf(0.0, _cooldown - delta)
	if _state == "flight":
		# A launched missile owns its sampled damage and landing position.
		# Never reacquire the target, or discard this shot when its source dies.
		_remaining = maxf(0.0, _remaining - delta)
		_update_warning()
		_update_projectile()
		if _remaining <= 0.0: _impact()
		return true
	if _state == "impact":
		_remaining = maxf(0.0, _remaining - delta)
		_update_warning()
		if _remaining <= 0.0:
			_clear_warning()
			_state = "idle"
		return true
	if not _living(host):
		if _state == "windup": _cancel("source_dead")
		return false
	if _state == "windup":
		var reason := _cast_rejection(_target)
		if not reason.is_empty():
			_cancel(reason)
			return true
		_remaining = maxf(0.0, _remaining - delta)
		host.moving = false
		host.attack_queued = true
		host.attack_windup = _remaining
		host.face(_point, delta)
		_update_warning()
		if _remaining <= 0.0: _launch()
		return true
	_clear_host_attack()
	if _cooldown > 0.0 or _controlled(): return false
	var selected: Dictionary = game.call("choose_enemy_target", host)
	if selected.is_empty() or not _cast_rejection(selected).is_empty(): return false
	_begin(selected)
	return true

func snapshot() -> Dictionary:
	var total := WINDUP_SECONDS + FLIGHT_SECONDS
	var remaining := _remaining + FLIGHT_SECONDS if _state == "windup" else (_remaining if _state == "flight" else 0.0)
	return {"phase": _state, "position": _point, "radius": BLAST_RADIUS,
		"remaining": remaining, "total": total, "stage_remaining": _remaining,
		"progress": 1.0 - clampf(remaining / total, 0.0, 1.0), "cooldown": _cooldown,
		"source": host if is_instance_valid(host) else null, "source_title": "投蚀体",
		"target_kind": String(_target.get("kind", "")), "target_index": int(_target.get("index", -1)),
		"target_token": int(_target.get("token", -1)), "cancel_reason": _cancel_reason,
		"launched": _launched, "impacts": _impacts, "cancelled": _cancelled, "damage": _damage}

func clear() -> void:
	_clear_host_attack()
	if is_instance_valid(host) and host.defeated.is_connected(_on_host_defeated): host.defeated.disconnect(_on_host_defeated)
	_clear_warning()
	if is_instance_valid(_prototype_root): _prototype_root.queue_free()
	_prototype_root = null
	host = null
	_target.clear()
	_state = "idle"
	_remaining = 0.0
	_cooldown = 0.0
	_damage = 0.0

func _exit_tree() -> void:
	clear()

func _living(unit: Variant) -> bool:
	return is_instance_valid(unit) and unit is BattleUnit and not unit.is_queued_for_deletion() and unit.alive

func _controlled() -> bool:
	if not _living(host): return false
	var specializations: Variant = game.get("specializations")
	# Actual tower control is a simulation slow; visual recoil is not a stun.
	return specializations != null and float(specializations.movement_multiplier(host)) < 0.9999

func _target_point(selected: Dictionary) -> Vector3:
	var kind := String(selected.get("kind", ""))
	match kind:
		"hero":
			var hero: BattleUnit = game.get("hero") as BattleUnit
			return hero.position if _living(hero) else Vector3.INF
		"squad":
			var member: BattleUnit = game.call("squad_member_by_token", int(selected.get("token", -1))) as BattleUnit
			return member.position if _living(member) else Vector3.INF
		"tower":
			var pads: Array = game.get("world").tower_pads
			var index := int(selected.get("index", -1))
			if index >= 0 and index < pads.size():
				var pad: Dictionary = pads[index]
				if int(pad.level) > 0 and float(pad.hp) > 0.0 and _same_building(selected, pad.get("turret")): return pad.position
		"district":
			var plots: Array = game.get("districts").plots
			var index := int(selected.get("index", -1))
			if index >= 0 and index < plots.size():
				var plot: Dictionary = plots[index]
				if int(plot.level) > 0 and float(plot.hp) > 0.0 and _same_building(selected, plot.get("model")): return plot.position
		"barricade":
			var barricade: Node3D = game.get("gate_barricade") as Node3D
			if is_instance_valid(barricade) and float(game.get("gate_barricade_hp")) > 0.0: return barricade.position
		"beacon":
			var beacon: Node3D = game.get("world").beacon as Node3D
			if is_instance_valid(beacon) and float(game.get("beacon_hp")) > 0.0: return beacon.position
	return Vector3.INF

func _same_building(selected: Dictionary, model: Variant) -> bool:
	# Destruction followed by same-frame rebuilding must not revive the old cast.
	if not selected.has("building_token"): return true
	return is_instance_valid(model) and not model.is_queued_for_deletion() and model.get_instance_id() == int(selected.building_token)

func _cast_rejection(selected: Dictionary) -> String:
	if not _living(host): return "source_dead"
	if _controlled(): return "source_controlled"
	var point := _target_point(selected)
	if not point.is_finite(): return "target_dead"
	if _distance(host.position, point) > RANGE: return "target_range"
	if absf(host.position.y - point.y) > HEIGHT_TOLERANCE: return "target_height"
	if not bool(game.call("can_attack_line", host.position, point)): return "line_blocked"
	return ""

func _distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))

func _begin(selected: Dictionary) -> void:
	_target = {"kind": String(selected.kind), "index": int(selected.get("index", -1)), "token": int(selected.get("token", -1))}
	if String(_target.kind) in ["tower", "district"]:
		var model: Node3D
		if String(_target.kind) == "tower": model = game.get("world").tower_pads[int(_target.index)].get("turret") as Node3D
		else: model = game.get("districts").plots[int(_target.index)].get("model") as Node3D
		if is_instance_valid(model): _target["building_token"] = model.get_instance_id()
	_point = _target_point(_target)
	_state = "windup"
	_remaining = WINDUP_SECONDS
	_cancel_reason = ""
	host.moving = false
	host.attack_queued = true
	host.attack_windup = WINDUP_SECONDS
	host.set_meta("attack_target_kind", String(_target.kind))
	host.set_meta("attack_target_index", int(_target.index))
	host.set_meta("attack_target_token", int(_target.token))
	_clear_warning()
	_warning_root = Node3D.new()
	_warning_root.name = "LobberLandingWarning"
	add_child(_warning_root)
	_ring = _terrain_ring(BLAST_RADIUS, 0.075, 0.085, Color("da8b55"))
	_ring.name = "LobberGroundDangerRadius"
	_progress_radius = BLAST_RADIUS * 0.10
	_progress_ring = _terrain_ring(_progress_radius, 0.045, 0.12, Color("bbcb79"))
	_progress_ring.name = "LobberGroundCountdown"
	_update_warning()

func _ground_height(point: Vector3) -> float:
	return float(game.call("outpost_height", point))

func _terrain_ring(radius: float, width: float, lift: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mat := BattleVisuals.material(color, 0.12)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warning_root.add_child(node)
	node.position = _point
	_resample_ring(node, radius, width, lift)
	return node

func _resample_ring(node: MeshInstance3D, radius: float, width: float, lift: float) -> void:
	# A horizontal torus is buried uphill and floats downhill. Sample every
	# strip vertex in game coordinates; resizing a previous ramp mesh is wrong.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for step in WARNING_SEGMENTS:
		var angle := TAU * float(step) / float(WARNING_SEGMENTS)
		var radial := Vector2(cos(angle), sin(angle))
		for edge_radius in [maxf(0.02, radius - width), radius + width]:
			var offset := radial * float(edge_radius)
			var world_point := _point + Vector3(offset.x, 0.0, offset.y)
			vertices.append(Vector3(offset.x, _ground_height(world_point) + lift - _point.y, offset.y))
			normals.append(Vector3.UP)
		var next := ((step + 1) % WARNING_SEGMENTS) * 2
		var current := step * 2
		indices.append_array(PackedInt32Array([current, next, current + 1, current + 1, next, next + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	node.mesh = mesh

func _launch() -> void:
	# Commit state before any external damage callbacks can re-enter this module.
	_state = "flight"
	_remaining = FLIGHT_SECONDS
	_cooldown = ATTACK_INTERVAL
	_damage = maxf(0.0, host.damage)
	_origin = host.position + Vector3.UP * 1.45
	_launched += 1
	_clear_host_attack()
	host.attack_timer = ATTACK_INTERVAL
	host.attack_pose = 1.0
	_projectile = MeshInstance3D.new()
	_projectile.name = "LobberAcidProjectile"
	var mesh := SphereMesh.new()
	mesh.radius = 0.23
	mesh.height = 0.46
	mesh.radial_segments = 12
	mesh.rings = 6
	_projectile.mesh = mesh
	_projectile.material_override = BattleVisuals.material(Color("a6b96a"), 0.18)
	_projectile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warning_root.add_child(_projectile)
	_update_projectile()
	_update_warning()

func _cancel(reason: String) -> void:
	_state = "idle"
	_remaining = 0.0
	_cooldown = maxf(_cooldown, 0.4)
	_cancel_reason = reason
	_cancelled += 1
	_clear_host_attack()
	_clear_warning()

func _clear_host_attack() -> void:
	if not is_instance_valid(host): return
	host.attack_queued = false
	host.attack_windup = 0.0
	host.set_meta("attack_target_kind", "")
	host.set_meta("attack_target_index", -1)
	host.set_meta("attack_target_token", -1)

func _on_host_defeated(_unit: BattleUnit, _source: BattleUnit) -> void:
	if _state == "windup": _cancel("source_dead")

func _update_projectile() -> void:
	if not is_instance_valid(_projectile): return
	var progress := 1.0 - clampf(_remaining / FLIGHT_SECONDS, 0.0, 1.0)
	_projectile.position = _origin.lerp(_point + Vector3.UP * 0.14, progress) + Vector3.UP * (3.0 * 4.0 * progress * (1.0 - progress))
	_projectile.rotation = Vector3(progress * 3.0, progress * 4.0, 0.0)

func _reduced() -> bool:
	var combat: Variant = game.get("combat") if is_instance_valid(game) else null
	return combat != null and bool(combat.reduced_effects)

func _update_warning() -> void:
	var reduced := _reduced()
	if is_instance_valid(_ring):
		var mat := _ring.material_override as StandardMaterial3D
		mat.emission_energy_multiplier = 0.04 if reduced else 0.16
	if is_instance_valid(_progress_ring):
		var remaining: float = float(snapshot().remaining)
		var progress := 1.0 - remaining / (WINDUP_SECONDS + FLIGHT_SECONDS)
		var radius := BLAST_RADIUS * maxf(0.10, progress)
		if not is_equal_approx(_progress_radius, radius):
			_progress_radius = radius
			_resample_ring(_progress_ring, radius, 0.045, 0.12)
		(_progress_ring.material_override as StandardMaterial3D).emission_energy_multiplier = 0.02 if reduced else 0.12
	if is_instance_valid(_projectile):
		(_projectile.material_override as StandardMaterial3D).emission_energy_multiplier = 0.03 if reduced else 0.18

func _clear_warning() -> void:
	if is_instance_valid(_warning_root): _warning_root.queue_free()
	_warning_root = null
	_ring = null
	_progress_ring = null
	_projectile = null
	_progress_radius = -1.0

func _covered(point: Vector3) -> bool:
	if not point.is_finite() or _distance(point, _point) > BLAST_RADIUS: return false
	# The announced circle follows the whole ramp. Grounded recipients inside
	# it are eligible despite slope height changes; a flying/underground unit is
	# still rejected relative to its own local surface, and walls still block.
	var recipient_offset := point.y - _ground_height(point)
	var landing_offset := _point.y - _ground_height(_point)
	return absf(recipient_offset - landing_offset) <= HEIGHT_TOLERANCE and bool(game.call("can_attack_line", _point, point))

func _building_covered(center: Vector3, kind: String) -> bool:
	var half: Vector2 = game.get("construction").footprint(kind)
	var contact := Vector3(clampf(_point.x, center.x - half.x, center.x + half.x), center.y, clampf(_point.z, center.z - half.y, center.z + half.y))
	return _covered(contact) and bool(game.call("can_attack_line", _point, center))

func _impact() -> void:
	# Set the once-only state before hurt(), which may reflect damage or end the run.
	_state = "impact"
	_remaining = IMPACT_SECONDS
	_impacts += 1
	if is_instance_valid(_projectile): _projectile.queue_free()
	_projectile = null
	var amount := _damage
	var source: BattleUnit = host if is_instance_valid(host) else null
	var fighters: Array[BattleUnit] = []
	var hero: BattleUnit = game.get("hero") as BattleUnit
	if _living(hero): fighters.append(hero)
	var squads: Node = game.get("squads") as Node
	if is_instance_valid(squads):
		for group: Dictionary in squads.get("squads"):
			for member: BattleUnit in group.members:
				if _living(member) and not fighters.has(member): fighters.append(member)
	for fighter: BattleUnit in fighters:
		if not _active_impact(): return
		if _living(fighter) and _covered(fighter.position): _hurt_unit(fighter, amount, source)
	var pads: Array = game.get("world").tower_pads
	for index in pads.size():
		if not _active_impact(): return
		var pad: Dictionary = pads[index]
		if int(pad.level) > 0 and float(pad.hp) > 0.0 and _building_covered(pad.position, "tower"):
			game.call("damage_tower", index, amount)
	var districts: Node = game.get("districts") as Node
	var plots: Array = districts.get("plots")
	for index in plots.size():
		if not _active_impact(): return
		var plot: Dictionary = plots[index]
		if int(plot.level) > 0 and float(plot.hp) > 0.0 and _building_covered(plot.position, String(plot.kind)):
			districts.call("damage", index, amount)
	if not _active_impact(): return
	var barricade: Node3D = game.get("gate_barricade") as Node3D
	if is_instance_valid(barricade) and float(game.get("gate_barricade_hp")) > 0.0 and _covered(barricade.position):
		game.call("damage_gate_barricade", amount)
	if not _active_impact(): return
	var beacon: Node3D = game.get("world").beacon as Node3D
	if is_instance_valid(beacon) and float(game.get("beacon_hp")) > 0.0 and _building_covered(beacon.position, "core"):
		var before := float(game.get("beacon_hp"))
		game.set("beacon_hp", maxf(0.0, before - amount))
		game.call("record_beacon_hit", before - float(game.get("beacon_hp")))
		if float(game.get("beacon_hp")) <= 0.0: game.call("end_defeat", "投蚀体击碎灯塔 · 哨站失守")

func _hurt_unit(fighter: BattleUnit, amount: float, source: BattleUnit) -> void:
	# damage_confirmed is synchronous. Preserve the real projectile identity even
	# after its source was freed, without manufacturing a living attacker.
	var had_title := fighter.has_meta("delayed_enemy_hit_title")
	var previous: Variant = fighter.get_meta("delayed_enemy_hit_title", "")
	fighter.set_meta("delayed_enemy_hit_title", "投蚀体")
	fighter.hurt(amount, source)
	if not is_instance_valid(fighter): return
	if had_title: fighter.set_meta("delayed_enemy_hit_title", previous)
	else: fighter.remove_meta("delayed_enemy_hit_title")

func _active_impact() -> bool:
	return is_instance_valid(game) and String(game.get("phase")) == "night" and _state == "impact"

func _attach_prototype() -> void:
	# Original stalker rig remains intact; these native sacks/spines are a prototype.
	if not is_instance_valid(host.visual): return
	_prototype_root = Node3D.new()
	_prototype_root.name = "LobberNativeAcidSacks"
	host.visual.add_child(_prototype_root)
	var flesh := BattleVisuals.material(Color("79814c"))
	for side in [-1.0, 1.0]:
		var sac := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.32
		sphere.height = 0.64
		sphere.radial_segments = 12
		sphere.rings = 8
		sac.mesh = sphere
		sac.material_override = flesh
		_prototype_root.add_child(sac)
		sac.position = Vector3(side * 0.3, 1.04, 0.15)
		sac.scale = Vector3(0.9, 1.1, 1.25)
	for step in 3:
		var spine := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.025
		cone.bottom_radius = 0.13
		cone.height = 0.42
		cone.radial_segments = 6
		spine.mesh = cone
		spine.material_override = BattleVisuals.material(Color("b2b488"))
		_prototype_root.add_child(spine)
		spine.position = Vector3(0.0, 1.37, float(step - 1) * 0.28)
		spine.rotation.x = 0.30
