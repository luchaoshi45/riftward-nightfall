extends Node3D
class_name OutpostSupplyCrate

## A small, self-contained world pickup.  The controller owns spawning,
## collision checks and rewards; the crate only owns its presentation and the
## one-shot opened state.

var serial: int = -1
var opened := false
var pulse_time := 0.0
var body: MeshInstance3D
var lid: MeshInstance3D
var marker: MeshInstance3D
var ring: MeshInstance3D
var glow: OmniLight3D

func setup(crate_serial: int) -> void:
	serial = crate_serial
	name = "SupplyCrate_%d" % serial
	body = MeshInstance3D.new()
	body.name = "CrateBody"
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.15, 0.68, 0.92)
	body.mesh = body_mesh
	body.position = Vector3(0.0, 0.38, 0.0)
	body.material_override = _material(Color("596b62"), Color("1a332c"))
	add_child(body)

	lid = MeshInstance3D.new()
	lid.name = "CrateLid"
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(1.22, 0.16, 0.98)
	lid.mesh = lid_mesh
	lid.position = Vector3(0.0, 0.79, 0.0)
	lid.material_override = _material(Color("b28a4e"), Color("6f3f1b"))
	add_child(lid)

	marker = MeshInstance3D.new()
	marker.name = "SupplyMarker"
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.08
	marker_mesh.bottom_radius = 0.08
	marker_mesh.height = 0.72
	marker.mesh = marker_mesh
	marker.position = Vector3(0.0, 1.28, 0.0)
	marker.material_override = _material(Color("f4d889"), Color("e4a94d"))
	add_child(marker)

	ring = MeshInstance3D.new()
	ring.name = "SupplyRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.72
	ring_mesh.outer_radius = 0.82
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 8
	ring.mesh = ring_mesh
	ring.position.y = 0.04
	ring.material_override = _material(Color("d8c16c", 0.54), Color("f0bc55"))
	add_child(ring)

	glow = OmniLight3D.new()
	glow.name = "SupplyGlow"
	glow.light_color = Color("e7bb69")
	glow.light_energy = 1.25
	glow.omni_range = 4.2
	glow.position = Vector3(0.0, 1.05, 0.0)
	add_child(glow)

func _material(albedo: Color, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = 0.42
	material.roughness = 0.68
	return material

func advance_visual(delta: float) -> void:
	if opened:return
	pulse_time += delta
	var pulse := 1.0 + sin(pulse_time * 2.7) * 0.055
	if is_instance_valid(ring):ring.scale = Vector3.ONE * pulse
	if is_instance_valid(marker):marker.rotation.y += delta * 1.8
	if is_instance_valid(glow):glow.light_energy = 1.05 + (sin(pulse_time * 2.7) + 1.0) * 0.18

func open() -> bool:
	if opened:return false
	opened = true
	if is_instance_valid(body):body.visible = false
	if is_instance_valid(lid):lid.visible = false
	if is_instance_valid(marker):marker.visible = false
	if is_instance_valid(ring):ring.visible = false
	if is_instance_valid(glow):glow.visible = false
	return true
