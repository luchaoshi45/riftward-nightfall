extends RefCounted
## 常规近战甲壳卫。只有出生数值与静态识别壳甲，行动、甲盾和死亡仍用真实单位。

const ROLE := "shellguard"
const HEALTH_MULTIPLIER := 1.15
const ARMOR := 60.0
const SPEED := 2.7
const DAMAGE := 22.0
const ATTACK_INTERVAL := 1.5
const ATTACK_RANGE := 1.6
const WINDUP_SECONDS := .34
const VISUAL_SCALE := 1.18
const PROTOTYPE_NAME := "ShellguardNativeCarapace"

static func configure(creature: BattleUnit) -> void:
	if not is_instance_valid(creature) or creature.is_queued_for_deletion(): return
	# Spawn supplies the current night's ordinary health and actual bound GLB.
	# A repeated call on that same instance must not multiply health or heal it.
	if bool(creature.get_meta("shellguard_configured", false)): return
	creature.set_meta("threat", ROLE)
	creature.title = "甲壳卫"
	creature.max_hp *= HEALTH_MULTIPLIER
	creature.hp = creature.max_hp
	creature.armor = ARMOR
	creature.speed = SPEED
	creature.damage = DAMAGE
	creature.attack_interval = ATTACK_INTERVAL
	creature.attack_range = ATTACK_RANGE
	creature.windup_duration = WINDUP_SECONDS
	creature.set_meta("shellguard_configured", true)
	if not is_instance_valid(creature.visual): return
	creature.visual.scale = Vector3.ONE * VISUAL_SCALE
	_attach_carapace(creature.visual)

static func _attach_carapace(visual: Node3D) -> void:
	if visual.get_node_or_null(PROTOTYPE_NAME) != null: return
	var root := Node3D.new()
	root.name = PROTOTYPE_NAME
	visual.add_child(root)
	# Thick, opaque volumes distinguish this low, broad armor from a warder's
	# three upright quota shells. No ground decals, coplanar overlay, glow or
	# separate lifetime: the original visual carries the plates into its corpse.
	var dorsal_material := BattleVisuals.material(Color("a7a28b"))
	dorsal_material.metallic = .12
	var shoulder_material := BattleVisuals.material(Color("c6b68c"))
	shoulder_material.metallic = .08
	for index in 3:
		var width := 1.24 if index == 1 else 1.10
		var plate := _plate(root, "ShellguardDorsalPlate%d" % (index + 1),
			Vector3(width, .30, .38), dorsal_material)
		plate.position = Vector3(0, 1.73, float(index - 1) * .43)
	for side in [-1, 1]:
		var name := "ShellguardShoulderGuardLeft" if side < 0 else "ShellguardShoulderGuardRight"
		var plate := _plate(root, name, Vector3(.30, .54, .57), shoulder_material)
		plate.position = Vector3(float(side) * .60, 1.40, .43)
		plate.rotation.z = -float(side) * .24

static func _plate(parent: Node3D, label: String, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var plate := MeshInstance3D.new()
	plate.name = label
	var mesh := PrismMesh.new()
	mesh.size = dimensions
	plate.mesh = mesh
	plate.material_override = material
	# Native armor is lit with the body; suppress extra tiny contact shadows.
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(plate)
	return plate
