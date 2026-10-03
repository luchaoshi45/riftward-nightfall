extends SceneTree
## Compare native and production stone in the real game without relighting the art.
const MASONRY_NAMES := ["Weathered concrete", "Concrete fracture"]
const MASONRY_SHADER := "res://assets/shaders/outpost_masonry.gdshader"
var game: Node3D
var failures: Array[String] = []
var surfaces: Array[Dictionary] = []
var observations: Dictionary = {}
var gameplay_basis: Basis
const PIPELINE_KEYS := {
	"canvas": RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS,
	"mesh": RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
	"surface": RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,
	"draw": RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
	"specialization": RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION,
}

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message); push_error(message)

func original_surfaces(enabled: bool) -> void:
	for entry in surfaces:
		entry.node.set_surface_override_material(entry.index, null if enabled else entry.production)

func assert_production() -> void:
	for entry in surfaces:
		var active := entry.node.get_active_material(entry.index) as ShaderMaterial
		check(active == entry.production and active.shader.resource_path == MASONRY_SHADER and active.resource_name == "Ash-worn " + entry.original.resource_name,
			"After screenshots use the actual production hook and identifiable imported palette")

func frame() -> void:
	game.hud.queue_redraw()
	await process_frame; await RenderingServer.frame_post_draw

func photograph(name: String) -> Image:
	for index in 5: await frame()
	var picture := root.get_texture().get_image()
	check(picture.get_width() >= 1000 and not picture.is_empty(), "Capture an actual gameplay-resolution Vulkan frame")
	check(picture.save_png("res://build/masonry-game-" + name + ".png") == OK, "Save actual " + name + " image")
	return picture

func view(target: Vector3, offset: Vector3, size: float) -> void:
	game.camera.position = target + offset
	game.camera.look_at(target, Vector3.UP)
	game.camera.size = size
	game.camera_follow = game.camera.position

func daytime(day: bool) -> void:
	game.phase = "day" if day else "night"
	game.phase_time = game.DAY_LENGTH if day else game.NIGHT_LENGTH
	game.world.night_active = not day
	game.world.night_mix = 0.0 if day else 1.0
	game.world.apply_lighting()

func pair(name: String) -> void:
	original_surfaces(true); await photograph(name + "-before")
	original_surfaces(false); assert_production(); await photograph(name + "-after")

func mean_value(picture: Image, region: Rect2i) -> float:
	var total := 0.0
	var samples := 0
	for y in range(region.position.y, region.end.y, 2):
		for x in range(region.position.x, region.end.x, 2):
			var pixel := picture.get_pixel(x, y)
			total += pixel.r + pixel.g + pixel.b; samples += 3
	return total / maxf(samples, 1)

func frame_cost(original: bool) -> Dictionary:
	original_surfaces(original)
	for index in 12:
		await process_frame; await RenderingServer.frame_post_draw
	var samples: Array[float] = []
	var total := 0.0
	for index in 48:
		var begin := Time.get_ticks_usec()
		await process_frame; await RenderingServer.frame_post_draw
		var elapsed := float(Time.get_ticks_usec() - begin) / 1000.0
		samples.append(elapsed); total += elapsed
	var actual_frames := samples.duplicate()
	samples.sort()
	return {"mean_ms": total / samples.size(), "median_ms": samples[24], "p95_ms": samples[45],
		"min_ms": samples[0], "max_ms": samples[-1], "samples": samples.size(), "all_frames_ms": actual_frames}

func rendering_snapshot() -> Dictionary:
	var counters: Dictionary = {}
	for label in PIPELINE_KEYS: counters[label] = RenderingServer.get_rendering_info(PIPELINE_KEYS[label])
	var viewport := root.get_viewport_rid()
	return {"pipelines": counters, "frames_drawn": Engine.get_frames_drawn(),
		"setup_cpu_ms": RenderingServer.get_frame_setup_time_cpu(),
		"viewport_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(viewport),
		"viewport_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(viewport),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"static_memory": Performance.get_monitor(Performance.MEMORY_STATIC)}

func profiled_cost(original: bool) -> Dictionary:
	original_surfaces(original)
	for index in 12:
		await process_frame; await RenderingServer.frame_post_draw
	var samples: Array[float] = []
	var details: Array[Dictionary] = []
	var total := 0.0
	for index in 48:
		var start := Time.get_ticks_usec()
		var before := rendering_snapshot()
		var wait_start := Time.get_ticks_usec()
		await process_frame; await RenderingServer.frame_post_draw
		var wait_end := Time.get_ticks_usec()
		var after := rendering_snapshot()
		var end := Time.get_ticks_usec()
		var elapsed := float(end - start) / 1000.0
		samples.append(elapsed); total += elapsed
		details.append({"sample": index, "wall_ms": elapsed, "await_draw_ms": float(wait_end - wait_start) / 1000.0,
			"before_query_ms": float(wait_start - start) / 1000.0, "after_query_ms": float(end - wait_end) / 1000.0,
			"before": before, "after": after})
	var actual_frames := samples.duplicate()
	samples.sort()
	return {"mean_ms": total / samples.size(), "median_ms": samples[24], "p95_ms": samples[45],
		"min_ms": samples[0], "max_ms": samples[-1], "samples": samples.size(),
		"all_frames_ms": actual_frames, "frame_details": details}

func alternating_cost() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for original in [true, false, true, false]:
		var timing: Dictionary
		if "--profile-timing" in OS.get_cmdline_user_args(): timing = await profiled_cost(original)
		else: timing = await frame_cost(original)
		timing["material"] = "native" if original else "production"
		result.append(timing)
	return result

func finish() -> void:
	original_surfaces(false); assert_production()
	var timing_only := "--timing-only" in OS.get_cmdline_user_args()
	var profiling := "--profile-timing" in OS.get_cmdline_user_args()
	var file := FileAccess.open("res://build/masonry-game-profile.json" if profiling else ("res://build/masonry-game-timing.json" if timing_only else "res://build/masonry-game-metrics.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(observations, "\t")); file.close()
	game.queue_free(); await process_frame; await process_frame; await create_timer(.15).timeout
	if profiling:
		var summary: Array[Dictionary] = []
		for entry in observations.frame_timing.rounds:
			var spikes: Array[Dictionary] = []
			for detail in entry.frame_details:
				if float(detail.wall_ms) > 50.0: spikes.append(detail)
			summary.append({"material": entry.material, "mean_ms": entry.mean_ms, "max_ms": entry.max_ms, "spikes_over_50ms": spikes})
		print("NIGHTFALL_MASONRY_PROFILE_", "OK" if failures.is_empty() else "FAILED", " alternating_ABAB_no_readback ", JSON.stringify(summary))
	else: print("NIGHTFALL_MASONRY_", "TIMING_" if timing_only else "VISUAL_", "OK" if failures.is_empty() else "FAILED", " actual_production alternating_ABAB_no_readback " if timing_only else " actual_production native_comparison night_day_ramp_wall transition attack_warning emission_off fixed_gameplay_camera ", JSON.stringify(observations))
	quit(0 if failures.is_empty() else 1)

func warning_enemy() -> BattleUnit:
	var enemy: BattleUnit = game.spawn_creature(false)
	enemy.position = game.hero.position + Vector3(1.2, 0, .6)
	enemy.position.y = game.outpost_height(enemy.position)
	enemy.attack_timer = 0.0; enemy.damage = 0.0
	game.update_creature(enemy, .01); enemy.tick(.14)
	check(enemy.alive and enemy.attack_queued and enemy.attack_windup > 0 and enemy.selection.visible,
		"The living actual stalker retains its attack tell on weathered paving")
	return enemy

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Actual stone rendering requires hidden Vulkan")
		quit(1); return
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.world.set_process(false)
	game.music.persist_settings = false; game.music.set_muted(true)
	check(game.choose_card(0), "The real first-night draft enters the playable world")
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	game.notice_time = 0.0
	game.hero.position = Vector3(0, 5, 3.1)
	game.move_goal = game.hero.position; game.hero_path.clear()
	game.world.follow_ashfall(game.hero.position)
	for node in game.world.terrain.find_children("*", "MeshInstance3D", true, false):
		for index in node.mesh.get_surface_count():
			var original := node.mesh.surface_get_material(index) as StandardMaterial3D
			if original != null and original.resource_name in MASONRY_NAMES:
				var production := node.get_active_material(index) as ShaderMaterial
				check(production != null and production.shader.resource_path == MASONRY_SHADER,
					"Production material must already be hooked before the fixture's native comparisons")
				if production: surfaces.append({"node": node, "index": index, "original": original, "production": production})
	check(surfaces.size() == 2, "Capture both actual production concrete surfaces")
	if surfaces.size() != 2: game.queue_free(); await process_frame; await create_timer(.15).timeout; quit(1); return
	gameplay_basis = game.camera.basis
	daytime(false)
	view(game.hero.position, Vector3(0, 25, 29), 31.0)
	if "--timing-only" in OS.get_cmdline_user_args() or "--profile-timing" in OS.get_cmdline_user_args():
		if "--profile-timing" in OS.get_cmdline_user_args(): RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
		observations.frame_timing = {"view": "31_night_actual_world", "warmup_each": 12, "readback": false,
			"rounds": await alternating_cost()}
		await finish(); return
	await pair("yard-night")
	check(game.camera.basis.is_equal_approx(gameplay_basis), "Gameplay stone comparisons preserve the normal fixed camera direction")
	view(Vector3(0.8, 5.0, 2.3), Vector3(3.5, 6.0, 6.0), 6.4)
	await pair("paving-night-close")
	daytime(true)
	view(game.hero.position, Vector3(0, 25, 29), 31.0)
	await pair("yard-day")
	view(Vector3(0, 2.5, 12.0), Vector3(0, 25, 29), 31.0)
	await pair("ramp-day")
	view(Vector3(0.3, 2.8, 12.0), Vector3(4, 8, 12), 13.0)
	await pair("ramp-day-close")
	view(Vector3(5.4, 2.5, 7.0), Vector3(8, 7, 12), 13.0)
	await pair("wall-day-close")
	# Use the existing six-second production transition, without adjusting its light values.
	view(game.hero.position, Vector3(0, 25, 29), 31.0)
	game.world.set_night(true)
	game.world._process(3.0)
	check(absf(game.world.night_mix - .5) < .001 and game.world.sun.light_energy < .86 and game.world.sun.light_energy > .018,
		"The weathered ground follows the actual gradual day-to-night lighting")
	await photograph("dusk-halfway-after")
	game.world._process(3.0); game.phase = "night"
	check(game.world.night_mix == 1.0, "The unchanged transition reaches its original dark night")
	await photograph("dusk-night-after")
	var enemy := warning_enemy()
	game.world.wave_warning = true; game.world.apply_lighting()
	await photograph("enemy-warning-after")
	check(enemy.selection.visible and enemy.selection.scale.x > 1.0,
		"The actual warm-up ring remains visible above the new stone")
	enemy.queue_free(); game.enemies.clear(); await process_frame
	game.world.wave_warning = false; game.world.apply_lighting()
	# Isolate material emission: remove fog, particles, bloom and ambient only for
	# both diagnostic images, keeping identical camera and pixel locations.
	var environment: Environment = game.world.environment.environment
	var saved_fog := environment.fog_enabled
	var saved_glow := environment.glow_enabled
	var saved_ambient := environment.ambient_light_energy
	game.hud.visible = false; game.hero.visible = false; game.world.ashfall.visible = false
	environment.fog_enabled = false; environment.glow_enabled = false; environment.ambient_light_energy = 0.0
	var probe_point := Vector3(-4.6, 5.06, -2.8)
	var pixel_center: Vector2 = game.camera.unproject_position(probe_point)
	var region := Rect2i(Vector2i(pixel_center) - Vector2i(12, 12), Vector2i(24, 24))
	check(Rect2i(Vector2i.ZERO, root.size).encloses(region), "The probe samples the same visible concrete patch inside the frame")
	var lit := await photograph("emission-probe-lit")
	var lighting: Array[Dictionary] = []
	for light in game.find_children("*", "Light3D", true, false):
		lighting.append({"node": light, "energy": light.light_energy}); light.light_energy = 0.0
	var dark := await photograph("emission-probe-dark")
	var lit_mean := mean_value(lit, region)
	var dark_mean := mean_value(dark, region)
	observations.emission_probe = {"pixel": pixel_center, "region": region, "lit_mean": lit_mean, "dark_mean": dark_mean,
		"dark_to_lit": dark_mean / maxf(lit_mean, .00001)}
	check(lit_mean > .05 and dark_mean < .04 and dark_mean < lit_mean * .12,
		"Stone receives scene lighting and does not emit its own light when all lights are off")
	for entry in lighting: entry.node.light_energy = entry.energy
	environment.fog_enabled = saved_fog; environment.glow_enabled = saved_glow; environment.ambient_light_energy = saved_ambient
	game.hud.visible = true; game.hero.visible = true; game.world.ashfall.visible = true
	observations.frame_timing = {"view": "31_night_actual_world", "warmup_each": 12, "readback": false,
		"rounds": await alternating_cost()}
	await finish()
