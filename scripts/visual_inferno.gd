extends Node3D
## The R artwork follows playable time, including its tween and GPU embers.
var owner_game: Node
var animation: Tween
var shader_materials: Array[ShaderMaterial] = []
var embers: Array[GPUParticles3D] = []
var effect_age := 0.0

func configure(game: Node, effect_tween: Tween, materials: Array[ShaderMaterial]) -> void:
	owner_game = game
	animation = effect_tween
	shader_materials = materials
	for child in find_children("*", "GPUParticles3D", true, false):
		embers.append(child as GPUParticles3D)

func _process(delta: float) -> void:
	var phase := String(owner_game.get("phase")) if is_instance_valid(owner_game) else "night"
	if phase == "ended":
		queue_free()
		return
	var playing := phase in ["day", "night"]
	if animation and animation.is_valid():
		if playing: animation.play()
		else: animation.pause()
	for particles in embers:
		if is_instance_valid(particles): particles.speed_scale = 1.0 if playing else 0.0
	if not playing: return
	effect_age += maxf(delta, 0.0)
	for material in shader_materials:
		material.set_shader_parameter("effect_age", effect_age)
