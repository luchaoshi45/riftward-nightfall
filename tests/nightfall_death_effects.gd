extends SceneTree
## Real combatants, reward lifecycle and transferred imported corpse geometry.
var game: Node3D
var failures: Array[String] = []
var measurements: Array[Dictionary] = []
var budget_timing: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func clean_case() -> void:
	game.cancel_hero_attack()
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	game.deaths.clear()
	game.combat.clear_transients()
	game.phase = "night"
	game.phase_time = 100.0
	game.kills = 0; game.scrap = 0; game.essence = 0
	game.run = RunBuild.new(411)
	game.run.stats.crit = 0.0
	game.hero.position = Vector3(0, 5, 3.1)
	game.move_goal = game.hero.position
	game.hero_path.clear(); game.hero_keyboard_active = false
	game.hero.hero_action = ""; game.hero.attack_timer = 0.0
	game.hero.hp = game.hero.max_hp
	game.hero.damage = 100.0
	game.kill_chain = 0; game.kill_chain_time = 0.0
	game.attack_chain = 0; game.attack_chain_time = 0.0
	game.spawn_timer = 10000.0; game.wave_index = game.WAVES_PER_NIGHT
	game.pulse_timer = 10000.0; game.gate_trap_charges = 0
	for pad in game.world.tower_pads: pad.level = 0

func target(threat: String, point: Vector3) -> BattleUnit:
	for attempt in 200:
		var enemy: BattleUnit = game.spawn_creature(true)
		if enemy.get_meta("threat", "") == threat:
			enemy.position = point
			enemy.position.y = game.outpost_height(point)
			enemy.hp = 1.0; enemy.max_hp = 1.0
			enemy.armor = 0.0; enemy.shield = 0.0
			enemy.speed = 0.0; enemy.attack_timer = 1000.0
			enemy.face(game.hero.position, 1.0)
			return enemy
		game.enemies.erase(enemy); enemy.queue_free()
	check(false, "Find an actual " + threat + " spawn within the deterministic budget")
	return null

func material_state(visual: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.mesh: continue
		for surface in mesh.mesh.get_surface_count():
			result.append({"node": mesh, "surface": surface,
				"material": mesh.get_active_material(surface), "mesh": mesh.mesh})
	return result

func model_center_height(visual: Node3D) -> float:
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		if "thorax" in str(node.name).to_lower():
			return (node.global_transform * node.get_aabb().get_center()).y
	var highest := -INF
	var lowest := INF
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.mesh: continue
		var bounds := mesh.get_aabb()
		for corner in 8:
			var point := mesh.to_global(bounds.get_endpoint(corner))
			highest = maxf(highest, point.y); lowest = minf(lowest, point.y)
	return (highest + lowest) * .5

func actual_vertex_clearance(visual: Node3D) -> float:
	var result := INF
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.mesh: continue
		for surface in mesh.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point := mesh.to_global(vertex)
				result = minf(result, point.y - game.outpost_height(point))
	return result

func rigid_pose(corpse: Dictionary) -> Array[Transform3D]:
	var result: Array[Transform3D] = [corpse.node.global_transform, corpse.visual.transform]
	for joint in corpse.joints: result.append(joint.node.transform)
	return result

func pose_fingerprint(corpse: Dictionary) -> Array[Transform3D]:
	var result := rigid_pose(corpse)
	for mote in corpse.ash:
		if mote.has("node") and is_instance_valid(mote.node): result.append(mote.node.transform)
	if corpse.has("ash_node") and DisplayServer.get_name() != "headless":
		for index in corpse.ash_node.multimesh.instance_count:
			result.append(corpse.ash_node.multimesh.get_instance_transform(index))
	return result

func same_pose(first: Array[Transform3D], second: Array[Transform3D]) -> bool:
	if first.size() != second.size(): return false
	for index in first.size():
		if not first[index].is_equal_approx(second[index]): return false
	return true

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game); current_scene = game
	await process_frame
	game.set_process(false); game.world.set_process(false)
	game.music.persist_settings = false
	check(game.choose_card(0), "The opening card enters the real first night")
	clean_case()
	await process_frame
	var enemy := target("stalker", game.hero.position + Vector3.RIGHT * 2.2)
	if not enemy: game.queue_free(); await process_frame; quit(1); return
	var visual := enemy.visual
	var preserved_materials := material_state(visual)
	check(not preserved_materials.is_empty(), "Actual imported stalker has mesh surfaces")
	enemy.attack_queued = true; enemy.attack_target_hero = true; enemy.attack_windup = 0.0
	game.auto_attack(); game.update_hero_attack(.15)
	check(not enemy.alive and not enemy.moving and not enemy.attack_queued,
		"A lethal basic attack removes the enemy's live state and queued attack immediately")
	check(game.kills == 1 and game.scrap == 8 and game.essence == 12 and game.kill_chain == 1,
		"A lethal personal basic grants the ordinary reward and one personal kill once")
	check(game.deaths.corpses.size() == 1, "One lethal basic creates exactly one retained corpse")
	if game.deaths.corpses.is_empty(): game.queue_free(); await process_frame; quit(1); return
	var corpse: Dictionary = game.deaths.corpses[0]
	check(corpse.visual == visual and visual.get_parent() == corpse.node,
		"The actual GLB is transferred into the corpse wrapper instead of replaced")
	check(not enemy.is_ancestor_of(visual) and visual.is_visible_in_tree(),
		"Hiding and freeing the dead simulation unit cannot hide its transferred visual")
	for entry in preserved_materials:
		check(entry.node.mesh == entry.mesh and entry.node.get_active_material(entry.surface) == entry.material,
			"The transferred corpse retains its imported PBR mesh and material reference")
	enemy.hurt(100.0, game.hero); enemy.hurt(100.0, null)
	check(game.kills == 1 and game.scrap == 8 and game.essence == 12 and game.deaths.corpses.size() == 1,
		"Further damage to a defeated unit cannot duplicate rewards or corpse submission")
	var hero_hp: float = game.hero.hp
	var beacon_hp: float = game.beacon_hp
	game.simulate(.01)
	check(game.enemies.is_empty() and game.hero.hp >= hero_hp and game.beacon_hp == beacon_hp,
		"The next simulation pass excludes the corpse from enemy attacks and objective damage")
	await process_frame
	check(not is_instance_valid(enemy) and is_instance_valid(visual) and visual.is_inside_tree(),
		"The BattleUnit is actually released while its original model remains alive")
	game.deaths.tick(.24, "night")
	var prior_pose := pose_fingerprint(corpse)
	var prior_time: float = corpse.time
	for frozen_phase in ["paused", "draft"]:
		game.deaths.tick(20.0, frozen_phase)
		check(corpse.time == prior_time and same_pose(prior_pose, pose_fingerprint(corpse)),
			frozen_phase + " freezes lifetime, collapse joints and ember transforms")
	game.deaths.tick(.04, "night")
	check(corpse.time > prior_time and not same_pose(prior_pose, pose_fingerprint(corpse)),
		"Resuming progresses the preserved collapse instead of recreating it")
	game.deaths.tick(float(corpse.dissolve_start) + .25 - float(corpse.time), "night")
	check(corpse.ash_started and corpse.alpha < 1.0, "The original mesh actually reaches its fading ember stage")
	prior_pose = pose_fingerprint(corpse); prior_time = corpse.time
	var prior_alpha: float = corpse.alpha
	for frozen_phase in ["paused", "draft"]:
		game.deaths.tick(20.0, frozen_phase)
		check(corpse.time == prior_time and corpse.alpha == prior_alpha and same_pose(prior_pose, pose_fingerprint(corpse)),
			frozen_phase + " freezes active drifting ash and imported mesh transparency")
	game.deaths.tick(float(corpse.duration) + 1.0, "night")
	check(game.deaths.corpses.is_empty(), "Expired corpses leave the bounded manager")
	await process_frame
	check(not is_instance_valid(visual), "Expired original mesh nodes are actually freed")

	# Exercise all real variants at both flat and sloped outpost surfaces.
	for threat in ["stalker", "breaker", "runner", "light_eater"]:
		for surface in [Vector3(0, 0, 14.0), Vector3(0, 5, 3.0), Vector3(20, 0, 27)]:
			clean_case(); await process_frame
			enemy = target(threat, surface)
			if not enemy: continue
			visual = enemy.visual
			var eater := enemy.get_node_or_null("LightEater") as NightLightEater
			if eater:
				eater.tick(.16)
				check(eater.drain_at(enemy.position) > .65, "The living moth has a real lamp-drain aura")
			enemy.hurt(100.0, game.hero)
			if eater:
				check(eater.drain_at(enemy.position) == 0.0, "Death immediately stops the moth's lamp drain")
				eater.tick(.01)
				check(eater.cold_glow.light_energy == 0.0, "Death immediately disables the moth's stolen-light aura")
			check(game.deaths.corpses.size() == 1, threat + " creates exactly one corpse")
			if game.deaths.corpses.is_empty(): continue
			corpse = game.deaths.corpses[0]
			check(corpse.threat == threat and corpse.visual == visual,
				"The " + threat + " corpse retains its actual class and original asset")
			var start_height := model_center_height(visual)
			var start_basis: Basis = visual.global_basis.orthonormalized()
			await process_frame
			check(not is_instance_valid(enemy) and is_instance_valid(visual), threat + " survives its simulation host release")
			var lowest := INF
			for frame in 70:
				game.deaths.tick(.01, "night")
				lowest = minf(lowest, actual_vertex_clearance(visual))
			check(lowest >= -.03,
				"The " + threat + " collapse stays above actual terrain (lowest gap %.4f)" % lowest)
			var landed_gap := actual_vertex_clearance(visual)
			check(landed_gap <= .12,
				"The " + threat + " real mesh settles on terrain instead of floating (gap %.4f)" % landed_gap)
			check(not visual.global_basis.orthonormalized().is_equal_approx(start_basis),
				"The " + threat + " model visibly changes its collapse orientation")
			if threat == "light_eater":
				check(model_center_height(visual) < start_height - .10,
					"The defeated flying moth falls from its hover height")
			measurements.append({"threat": threat, "position": surface, "lowest_gap": lowest,
				"actual_vertex_gap": landed_gap, "duration": corpse.duration, "fall_duration": corpse.fall_duration})
			game.deaths.tick(float(corpse.duration) + 1.0, "night")
			await process_frame

	clean_case(); await process_frame
	var retained: Array[Node3D] = []
	for index in 16:
		game.essence = 0
		enemy = target("breaker", Vector3(float(index % 4), 5, 3.0 + float(index / 4) * .4))
		if not enemy: continue
		visual = enemy.visual
		enemy.hurt(100.0, game.hero)
		retained.append(visual)
		check(game.deaths.corpses.size() <= game.deaths.MAX_CORPSES,
			"A burst of simultaneous deaths respects the corpse budget")
		await process_frame
	check(game.deaths.corpses.size() == game.deaths.MAX_CORPSES,
		"The budget retains exactly its most recent corpse capacity")
	check(not is_instance_valid(retained[0]) and is_instance_valid(retained[-1]),
		"Corpse capacity frees the oldest mesh while preserving the latest death")
	# Measure the maximum simultaneous heavy-corpse workload after support caching.
	# Report observed times; a machine-specific speed threshold would be misleading.
	game.deaths.tick(1.9, "night")
	var cache_size: int = game.deaths.support_cache.size()
	var settled_count := 0
	var poses: Array[Array] = []
	for body in game.deaths.corpses:
		if body.get("settled", false): settled_count += 1
		poses.append(rigid_pose(body))
	check(settled_count == game.deaths.MAX_CORPSES,
		"All twelve heavy corpses finish their bounce before the ash-stage timing")
	var alpha_before: float = game.deaths.corpses[0].alpha
	var samples: Array[int] = []
	var total_usec := 0
	for index in 60:
		var begin := Time.get_ticks_usec()
		game.deaths.tick(1.0 / 120.0, "night")
		var elapsed := Time.get_ticks_usec() - begin
		samples.append(elapsed); total_usec += elapsed
	check(game.deaths.corpses.size() == game.deaths.MAX_CORPSES,
		"Timing samples keep all twelve heavy meshes and active ash alive")
	check(game.deaths.support_cache.size() == cache_size,
		"Animation frames reuse the cached imported mesh support points")
	for index in game.deaths.corpses.size():
		check(game.deaths.corpses[index].settled and same_pose(poses[index], rigid_pose(game.deaths.corpses[index])),
			"Settled corpses keep their supported body and joint poses fixed during the fade")
	check(game.deaths.corpses[0].alpha < alpha_before and game.deaths.corpses[0].ash_started,
		"Settled geometry still fades and keeps its ash stage active")
	samples.sort()
	budget_timing = {"case": "12_breaker_active_ash", "samples": samples.size(),
		"mean_usec": float(total_usec) / samples.size(), "median_usec": samples[30],
		"p95_usec": samples[56], "max_usec": samples[-1], "cached_meshes": cache_size,
		"settled_count": settled_count}
	game.deaths.tick(.1, "ended")
	check(game.deaths.corpses.is_empty(), "Ending the match clears every retained corpse immediately")
	await process_frame
	for node in retained: check(not is_instance_valid(node), "End cleanup frees every original transferred model")
	clean_case(); await process_frame
	enemy = target("breaker", Vector3(0, 5, 3))
	if enemy:
		visual = enemy.visual
		enemy.hurt(100, game.hero)
		var module: Node3D = game.deaths
		game.queue_free(); await process_frame; await process_frame
		check(not is_instance_valid(module) and not is_instance_valid(visual),
			"Freeing the actual game scene leaves no death manager or corpse subtree")
	else:
		game.queue_free(); await process_frame
	await create_timer(.15).timeout
	print("NIGHTFALL_DEATH_EFFECTS_", "OK" if failures.is_empty() else "FAILED", " immediate_dead rewards_once retained_PBR frozen_pause_draft terrain_four_variants bounded_capacity expiry_end_scene_cleanup " + JSON.stringify({"terrain": measurements, "budget_timing": budget_timing}))
	quit(0 if failures.is_empty() else 1)
