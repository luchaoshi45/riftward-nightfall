class_name NightfallSummoner
extends Node3D
## 有限召援：根控制器拥有已出生计数，模块只处理可打断引导与真实冷却。

const Layout = preload("res://scripts/outpost_layout.gd")
const WINDUP_SECONDS: float = 2.4
const SUMMON_INTERVAL: float = 10.0
const MAX_REINFORCEMENTS: int = 2
const SOURCE_RANGE: float = 14.0

var game: Node3D
var host: BattleUnit
var _state: String = "idle"
var _remaining: float = 0.0
var _cooldown: float = 0.0
var _entry: Vector3 = Vector3.ZERO
var _cancel_reason: String = ""
var _cancelled: int = 0
var _generation: int = 0
var _normal_windup: float = 0.34
var _prototype_root: Node3D
var _core_material: StandardMaterial3D
var _bead_materials: Array[StandardMaterial3D] = []

func setup(owner_game: Node3D, owner_host: BattleUnit) -> void:
	clear()
	game = owner_game
	host = owner_host
	if get_parent() == null and is_instance_valid(game): game.add_child(self)
	_state = "idle"
	_cancel_reason = ""
	_cancelled = 0
	if not _living(host): return
	_normal_windup = host.windup_duration
	host.title = "召潮者"
	host.set_meta("threat", "summoner")
	host.set_meta("summoner_active", _spawned() < MAX_REINFORCEMENTS)
	var lane := clampf(float(host.get_meta("gate_lane", 0.0)), -1.15, 1.15)
	if not is_finite(lane): lane = 0.0
	_entry = Vector3(lane, 0.0, Layout.RAMP_END + 3.0)
	_entry.y = _ground_height(_entry)
	if not host.defeated.is_connected(_on_host_defeated): host.defeated.connect(_on_host_defeated)
	_attach_prototype()
	_update_prototype()

func advance(delta: float) -> bool:
	if not is_instance_valid(game):
		clear()
		return false
	var phase_name := String(game.get("phase"))
	if phase_name in ["paused", "draft"] or delta <= 0.0 or not is_finite(delta):
		return _state in ["windup", "cooldown", "committing"]
	if phase_name != "night":
		clear()
		return false
	# A synchronous callback cannot start another cast while the root is
	# accepting this emission. No timer or count changes inside this guard.
	if _state == "committing": return true
	if not _living(host):
		if _state == "windup": _cancel("source_dead")
		return false
	if _spawned() >= MAX_REINFORCEMENTS:
		if _state != "exhausted": _exhaust()
		return false # Preserve ordinary queued melee on all subsequent frames.
	host.set_meta("summoner_active", true)
	_cooldown = maxf(0.0, _cooldown - delta)
	var rejection := _source_rejection()
	if not rejection.is_empty():
		if _state == "windup": _cancel(rejection)
		else:
			_cancel_reason = rejection
			_state = "cooldown" if _cooldown > 0.0 else "idle"
		# The original controller owns ordinary combat outside the source
		# zone. Preserve its queued attack across frames until a real cast
		# starts, otherwise every normal melee windup would restart forever.
		host.windup_duration = _normal_windup
		_update_prototype()
		return false # Existing south-gate navigation remains authoritative.
	if _controlled():
		if _state == "windup": _cancel("source_controlled")
		else: _cancel_reason = "source_controlled"
		_clear_host_attack()
		host.moving = false
		_update_prototype()
		return true
	if _state == "windup":
		_remaining = maxf(0.0, _remaining - delta)
		host.moving = false
		host.attack_queued = true
		host.attack_windup = _remaining
		host.face(_entry, delta)
		if _remaining <= 0.0: _emit()
		_update_prototype()
		return true
	_clear_host_attack()
	host.moving = false
	if _cooldown > 0.0:
		_state = "cooldown"
		_update_prototype()
		return true
	_begin()
	return true

func snapshot() -> Dictionary:
	var source: BattleUnit = host if is_instance_valid(host) else null
	return {"phase": _state, "remaining": _remaining, "total": WINDUP_SECONDS,
		"progress": 1.0 - clampf(_remaining / WINDUP_SECONDS, 0.0, 1.0) if _state in ["windup", "committing"] else 0.0,
		"cooldown": _cooldown, "spawned": _spawned(), "max_reinforcements": MAX_REINFORCEMENTS,
		"source": source, "source_token": source.get_instance_id() if is_instance_valid(source) else -1,
		"source_title": "召潮者", "position": source.position if is_instance_valid(source) else Vector3.ZERO,
		"entry_position": _entry, "cancel_reason": _cancel_reason, "cancelled": _cancelled}

func entry_position() -> Vector3:
	return _entry

func clear() -> void:
	_generation += 1
	_clear_host_attack()
	if is_instance_valid(host):
		host.set_meta("summoner_active", false)
		host.windup_duration = _normal_windup
		if host.defeated.is_connected(_on_host_defeated): host.defeated.disconnect(_on_host_defeated)
	if is_instance_valid(_prototype_root): _prototype_root.queue_free()
	_prototype_root = null
	_core_material = null
	_bead_materials.clear()
	host = null
	_state = "idle"
	_remaining = 0.0
	_cooldown = 0.0
	_entry = Vector3.ZERO

func _exit_tree() -> void:
	clear()

func _living(unit: Variant) -> bool:
	return is_instance_valid(unit) and unit is BattleUnit and not unit.is_queued_for_deletion() and unit.alive

func _spawned() -> int:
	# setup/clear never replenish this source's lifetime budget.
	return maxi(0, int(host.get_meta("summoner_spawned", 0))) if is_instance_valid(host) else 0

func _ground_height(point: Vector3) -> float:
	return float(game.call("outpost_height", point)) if is_instance_valid(game) else point.y

func _controlled() -> bool:
	if not _living(host): return false
	var specializations: Variant = game.get("specializations") if is_instance_valid(game) else null
	# The simulation slow is the interruption; visual recoil is not a stun.
	return specializations != null and float(specializations.movement_multiplier(host)) < 0.9999

func _source_rejection() -> String:
	if not _living(host): return "source_dead"
	if not host.position.is_finite() or not _entry.is_finite(): return "source_position"
	if host.position.z < Layout.RAMP_END + 0.5: return "source_zone"
	if Vector2(host.position.x, host.position.z).distance_to(Vector2(_entry.x, _entry.z)) > SOURCE_RANGE: return "source_range"
	if not bool(game.call("outpost_walkable", host.position)): return "source_blocked"
	if not bool(game.call("outpost_walkable", _entry)): return "entry_blocked"
	if not is_equal_approx(_entry.y, _ground_height(_entry)): return "entry_height"
	# The chosen point is outside the ramp and has a real central approach.
	# Reject it rather than snapping to the courtyard or a wall-side point.
	var approach := Vector3(_entry.x, 0.0, Layout.RAMP_END)
	approach.y = _ground_height(approach)
	if not bool(game.call("can_traverse", _entry, approach)): return "entry_path"
	return ""

func _begin() -> void:
	_state = "windup"
	_remaining = WINDUP_SECONDS
	_cancel_reason = ""
	host.moving = false
	host.windup_duration = WINDUP_SECONDS
	host.attack_queued = true
	host.attack_windup = _remaining
	host.set_meta("attack_target_kind", "")
	host.set_meta("attack_target_index", -1)
	host.set_meta("attack_target_token", -1)
	_update_prototype()

func _emit() -> void:
	var rejection := _source_rejection()
	if _controlled(): rejection = "source_controlled"
	if not rejection.is_empty():
		_cancel(rejection)
		return
	var generation := _generation
	_state = "committing"
	_remaining = 0.0
	_clear_host_attack()
	var reinforcement: Variant = game.call("spawn_summoned_reinforcement", host, _entry)
	if generation != _generation or not is_instance_valid(game) or not _living(host) or String(game.get("phase")) != "night": return
	if not _living(reinforcement):
		_cancel("spawn_rejected")
		return
	host.attack_pose = 1.0
	_cancel_reason = ""
	if _spawned() >= MAX_REINFORCEMENTS:
		_exhaust()
	else:
		_state = "cooldown"
		_cooldown = SUMMON_INTERVAL
		host.moving = false

func _cancel(reason: String) -> void:
	_state = "cooldown" if _cooldown > 0.0 else "idle"
	_remaining = 0.0
	_cancel_reason = reason
	_cancelled += 1
	_clear_host_attack()
	if is_instance_valid(host): host.windup_duration = _normal_windup
	_update_prototype()

func _exhaust() -> void:
	_state = "exhausted"
	_remaining = 0.0
	_cooldown = 0.0
	_clear_host_attack()
	if is_instance_valid(host):
		host.set_meta("summoner_active", false)
		host.windup_duration = _normal_windup
	_update_prototype()

func _clear_host_attack() -> void:
	if not is_instance_valid(host): return
	host.attack_queued = false
	host.attack_windup = 0.0
	host.set_meta("attack_target_kind", "")
	host.set_meta("attack_target_index", -1)
	host.set_meta("attack_target_token", -1)

func _on_host_defeated(_unit: BattleUnit, _source: BattleUnit) -> void:
	if _state == "windup": _cancel("source_dead")
	if is_instance_valid(host): host.set_meta("summoner_active", false)

func _attach_prototype() -> void:
	# The original night creature rig remains intact. Native antennae and
	# two budget beads are a playable silhouette prototype, not a new GLB.
	if not is_instance_valid(host.visual): return
	_prototype_root = Node3D.new()
	_prototype_root.name = "SummonerNativeSignalCrest"
	host.visual.add_child(_prototype_root)
	var shell := BattleVisuals.material(Color("6b6255"))
	for side in [-1.0, 1.0]:
		var fork := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.035
		mesh.bottom_radius = 0.085
		mesh.height = 0.78
		mesh.radial_segments = 8
		fork.mesh = mesh
		fork.material_override = shell
		fork.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_prototype_root.add_child(fork)
		fork.position = Vector3(side * 0.32, 1.4, 0.08)
		fork.rotation.z = -side * 0.26
		var bead := MeshInstance3D.new()
		var bead_mesh := SphereMesh.new()
		bead_mesh.radius = 0.115
		bead_mesh.height = 0.23
		bead_mesh.radial_segments = 10
		bead_mesh.rings = 6
		bead.mesh = bead_mesh
		var material := BattleVisuals.material(Color("d3ba7c"), 0.05)
		bead.material_override = material
		_bead_materials.append(material)
		bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_prototype_root.add_child(bead)
		bead.position = Vector3(side * 0.42, 1.76, 0.08)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.18
	core_mesh.height = 0.36
	core_mesh.radial_segments = 12
	core_mesh.rings = 6
	core.mesh = core_mesh
	_core_material = BattleVisuals.material(Color("bdae7b"), 0.04)
	core.material_override = _core_material
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prototype_root.add_child(core)
	core.position = Vector3(0.0, 1.3, 0.18)

func _update_prototype() -> void:
	if _core_material == null: return
	var combat: Variant = game.get("combat") if is_instance_valid(game) else null
	var reduced := combat != null and bool(combat.reduced_effects)
	_core_material.emission_energy_multiplier = (0.035 if reduced else 0.12) if _state == "windup" else 0.025
	var available := maxi(0, MAX_REINFORCEMENTS - _spawned())
	for index in _bead_materials.size():
		var material := _bead_materials[index]
		material.albedo_color = Color("d3ba7c") if index < available else Color("625e50")
		material.emission_energy_multiplier = (0.02 if reduced else 0.07) if index < available else 0.0
