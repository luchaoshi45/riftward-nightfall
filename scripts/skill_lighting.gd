extends Node3D
## Real, local skill lighting. Simulation time owns lifetime, movement and pause.
const MAX_LIGHTS := 6
const MAX_SHADOW_LIGHTS := 1
var game: Node3D
var lights: Array[Dictionary] = []

func setup(owner_game: Node3D) -> void:
	game = owner_game

func emit_skill(slot: int, origin: Vector3, direction: Vector3, endpoint: Vector3 = Vector3.INF, radius: float = 0.0) -> void:
	if not is_instance_valid(game) or game.phase not in ["day", "night"]: return
	var flat := Vector3(direction.x, 0, direction.z).normalized()
	if flat.length_squared() < .01: flat = Vector3.RIGHT
	match slot:
		0:
			add_light("slash", origin + flat * .8 + Vector3.UP * 1.15,
				origin + flat * 8.2 + Vector3.UP * 1.15, Color("97dfff"), 3.2, 5.2, .42)
		1:
			add_light("shield", origin + Vector3.UP * 1.35, origin + Vector3.UP * 1.35,
				Color("8cd9e5"), 1.35, maxf(4.8, radius * 1.12), 4.0, true)
		2:
			if not endpoint.is_finite() or origin.distance_squared_to(endpoint) < .01: return
			add_light("dash_start", origin + Vector3.UP * 1.0, origin + Vector3.UP * 1.0,
				Color("9cdcff"), 2.3, 4.2, .28)
			add_light("dash", origin + Vector3.UP * 1.2, endpoint + Vector3.UP * 1.2,
				Color("9cdcff"), 3.0, 4.6, .38)
		3:
			add_light("inferno", origin + Vector3.UP * 2.3, origin + Vector3.UP * 2.3,
				Color("ffbb73"), 4.8, maxf(10.2, radius * 1.4), .95, false, true)
		4:
			add_light("heal", origin + Vector3.UP * 1.25, origin + Vector3.UP * 1.25,
				Color("a5e5be"), 2.1, 5.2, 1.15, true)

func add_light(kind: String, origin: Vector3, endpoint: Vector3, color: Color,
		energy: float, radius: float, duration: float, follow: bool = false, shadows: bool = false) -> void:
	while lights.size() >= MAX_LIGHTS:
		retire(0)
	# Only the newest ultimate spends the single dynamic shadow budget.
	if shadows:
		for item in lights:
			if is_instance_valid(item.node): (item.node as OmniLight3D).shadow_enabled = false
	var light := OmniLight3D.new()
	light.name = "SkillLight_" + kind
	light.light_color = color
	light.omni_range = clampf(radius, 1.0, 18.0)
	light.omni_attenuation = 1.3
	light.light_indirect_energy = 0.0
	light.light_bake_mode = Light3D.BAKE_DISABLED
	light.light_volumetric_fog_energy = .22 if kind == "inferno" else .08
	light.light_specular = .65
	light.shadow_enabled = shadows
	light.light_size = .18 if shadows else 0.0
	light.shadow_bias = .045
	light.shadow_normal_bias = .65
	light.distance_fade_enabled = true
	light.distance_fade_begin = 48.0
	light.distance_fade_length = 18.0
	light.distance_fade_shadow = 50.0
	add_child(light)
	light.global_position = origin
	var item := {"node":light, "kind":kind, "origin":origin, "endpoint":endpoint,
		"offset":origin - game.hero.global_position, "follow":follow,
		"time":0.0, "duration":duration, "energy":energy}
	lights.append(item)
	apply_light(item)

func feedback_scale() -> float:
	return .45 if game.combat and game.combat.reduced_effects else 1.0

func apply_light(item: Dictionary) -> void:
	var light := item.node as OmniLight3D
	var age: float = item.time
	var duration: float = item.duration
	var progress := clampf(age / duration, 0.0, 1.0)
	if item.follow:
		light.global_position = game.hero.global_position + (item.offset as Vector3)
	elif item.kind in ["slash", "dash"]:
		var travel := clampf(age / (duration * .62), 0.0, 1.0)
		light.global_position = (item.origin as Vector3).lerp(item.endpoint, 1.0 - pow(1.0 - travel, 2.0))
	var envelope := pow(1.0 - progress, 1.4)
	if item.kind == "shield": envelope = minf(1.0, (duration - age) / .65)
	light.light_energy = float(item.energy) * maxf(0.0, envelope) * feedback_scale()
	light.visible = light.light_energy > .001

func tick(delta: float, phase: String) -> void:
	if phase == "ended":
		clear()
		return
	if phase not in ["day", "night"]: return
	for index in range(lights.size() - 1, -1, -1):
		var item: Dictionary = lights[index]
		if not is_instance_valid(item.node):
			lights.remove_at(index)
			continue
		item.time = float(item.time) + maxf(delta, 0.0)
		if item.kind == "shield" and (game.hero.shield <= 0.0 or game.hero.shield_time <= 0.0):
			item.time = maxf(float(item.time), float(item.duration) - .4)
		if float(item.time) >= float(item.duration):
			retire(index)
			continue
		apply_light(item)

func retire(index: int) -> void:
	var light := lights[index].node as OmniLight3D
	if is_instance_valid(light):
		light.light_energy = 0.0
		light.visible = false
		light.queue_free()
	lights.remove_at(index)

func clear() -> void:
	while not lights.is_empty(): retire(lights.size() - 1)

func _exit_tree() -> void:
	clear()
	game = null
