class_name NightLightEater
extends Node
## Wing and hovering motion plus a measurable, reversible lamp-suppression aura.
## The world owns light values; callers sample drain_at() before lighting is applied.

const DRAIN_INNER_RADIUS: float = 2.5
const DRAIN_OUTER_RADIUS: float = 12.5
const MAX_DRAIN: float = 0.84

var host: BattleUnit
var wing_left: Node3D
var wing_right: Node3D
var cold_glow: OmniLight3D
var age: float = 0.0


func setup(creature: BattleUnit) -> void:
	host = creature
	wing_left = host.visual.find_child("MothWingLeft", true, false) as Node3D
	wing_right = host.visual.find_child("MothWingRight", true, false) as Node3D
	assert(wing_left != null and wing_right != null, "Night light eater needs both exported wing pivots")
	cold_glow = OmniLight3D.new()
	cold_glow.name = "StolenLightGlow"
	cold_glow.position = Vector3(0.0, 1.85, 0.0)
	cold_glow.light_color = Color("74c7c3")
	cold_glow.light_energy = 2.0
	cold_glow.omni_range = 5.4
	cold_glow.shadow_enabled = false
	host.add_child(cold_glow)


func tick(delta: float) -> void:
	if host == null or not is_instance_valid(host) or not host.alive:
		if is_instance_valid(cold_glow):
			cold_glow.light_energy = 0.0
		return
	age += delta
	var flap: float = sin(age * (11.8 if host.moving else 4.8))
	wing_left.rotation.z = -0.31 - flap * (0.48 if host.moving else 0.14)
	wing_right.rotation.z = 0.31 + flap * (0.48 if host.moving else 0.14)
	host.visual.position.y = 0.36 + sin(age * 3.4) * 0.13
	host.visual.rotation.x = sin(age * 2.2) * 0.055 - host.attack_pose * 0.18
	host.visual.rotation.z = sin(age * 1.6) * 0.07 + host.hit_recoil * 0.08
	cold_glow.light_energy = 1.9 + sin(age * 5.1) * 0.30


func drain_at(point: Vector3) -> float:
	if host == null or not is_instance_valid(host) or not host.alive:
		return 0.0
	var horizontal_distance: float = Vector2(host.position.x - point.x, host.position.z - point.z).length()
	var t: float = clampf((DRAIN_OUTER_RADIUS - horizontal_distance) /
		(DRAIN_OUTER_RADIUS - DRAIN_INNER_RADIUS), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return MAX_DRAIN * t * (0.94 + 0.06 * sin(age * 4.2))
