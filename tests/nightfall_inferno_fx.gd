extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var effects := Node3D.new()
	root.add_child(effects)
	BattleVisuals.lantern_inferno(effects, Vector3(2, 5, 3), 8.0)
	var blast: Node3D = effects.get_node_or_null("LanternInferno")
	assert(blast != null and blast.position == Vector3(2, 5.13, 3))
	var boundary: MeshInstance3D = blast.get_node_or_null("InfernoDamageBoundary")
	assert(boundary != null and boundary.mesh is TorusMesh)
	assert(absf((boundary.mesh as TorusMesh).outer_radius - 8.13) < .001, "The visible boundary must match the damage radius")
	var tongues: Node3D = blast.get_node_or_null("InfernoFlameTongues")
	assert(tongues != null and tongues.get_child_count() == 12)
	var flash: OmniLight3D = blast.get_node_or_null("InfernoFlashLight")
	assert(flash != null and flash.light_energy >= 4.9)
	await create_timer(.18).timeout
	assert(flash.light_energy < 5.0 and flash.light_energy > 0.0, "The flash light should fade")
	await create_timer(.9).timeout
	assert(effects.get_node_or_null("LanternInferno") == null, "The effect must clean itself up")
	print("NIGHTFALL_INFERNO_FX_OK")
	quit()
