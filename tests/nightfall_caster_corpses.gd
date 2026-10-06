extends SceneTree
## Actual caster deaths retain the original GLB while controller-owned additions retire.
## The extra limb case deliberately retires one real rig subtree to check safe recovery.

const SEED: int = 20261006
const STEP: float = 1.0 / 60.0
const RunSession = preload("res://scripts/run_session.gd")
var game: Node3D
var checks: int = 0
var failures: Array[String] = []
var receipts: Array[Dictionary] = []
var finished: bool = false

func _initialize() -> void:
	create_timer(90.0, true, false, true).timeout.connect(watchdog)
	call_deferred("run")

func watchdog() -> void:
	if finished: return
	push_error("Caster corpse acceptance did not finish its real lifecycle")
	quit(1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 30: push_error(message)

func clean_case() -> void:
	game.cancel_hero_attack()
	game.clear_summoners(); game.clear_lobbers()
	for enemy: Variant in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	game.deaths.clear()
	game.combat.clear_transients()
	game.phase = "night"; game.phase_time = 10000.0
	game.hero.position = Vector3(0, 5, 3.1)
	game.move_goal = game.hero.position; game.hero_path.clear()
	game.hero_keyboard_active = false; game.hero.moving = false
	game.hero.attack_timer = 100000.0
	game.spawn_timer = 100000.0; game.wave_index = game.WAVES_PER_NIGHT
	game.pulse_timer = 100000.0; game.gate_trap_charges = 0
	for pad: Dictionary in game.world.tower_pads: pad.cooldown = 100000.0

func material_state(visual: Node3D, prototype: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		if prototype.is_ancestor_of(mesh) or mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			result.append({"node": mesh, "surface": surface,
				"mesh": mesh.mesh, "material": mesh.get_active_material(surface)})
	return result

func current_materials_preserved(materials: Array[Dictionary]) -> bool:
	var seen := false
	for entry: Dictionary in materials:
		var value: Variant = entry.node
		if not is_instance_valid(value): continue
		var mesh := value as MeshInstance3D
		seen = true
		if mesh.mesh != entry.mesh or mesh.get_active_material(entry.surface) != entry.material: return false
	return seen

func live_meshes_faded(corpse: Dictionary) -> bool:
	var seen := false
	for value: Variant in corpse.meshes:
		if not is_instance_valid(value): continue
		var mesh := value as MeshInstance3D
		seen = true
		if mesh.transparency <= 0.0: return false
	return seen

func actual_vertex_clearance(visual: Node3D) -> float:
	var result := INF
	for value: Variant in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var point := mesh.to_global(vertex)
				result = minf(result, point.y - game.outpost_height(point))
	return result

func prepare_corpse(role: String, point: Vector3) -> Dictionary:
	clean_case(); await process_frame
	var enemy: BattleUnit = game.spawn_creature(true, role)
	check(is_instance_valid(enemy) and enemy.get_meta("threat", "") == role,
		"Real production spawn installs the " + role + " class")
	if not is_instance_valid(enemy): return {}
	enemy.position = point; enemy.position.y = game.outpost_height(point)
	enemy.speed = 0.0; enemy.attack_timer = 100000.0
	var controllers: Array = game.summoners if role == "summoner" else game.lobbers
	check(controllers.size() == 1 and controllers[0].host == enemy,
		"The actual " + role + " controller belongs to the living source")
	if controllers.size() != 1: return {}
	var controller: Node3D = controllers[0]
	var prototype: Node3D = controller.get("_prototype_root")
	check(is_instance_valid(prototype) and enemy.visual.is_ancestor_of(prototype),
		"The production controller has its actual additions inside the original GLB")
	if not is_instance_valid(prototype): return {}
	var prototype_token := prototype.get_instance_id()
	var controller_token := controller.get_instance_id()
	var enemy_token := enemy.get_instance_id()
	var native_tokens: Array[int] = []
	for value: Variant in prototype.find_children("*", "MeshInstance3D", true, false):
		native_tokens.append(value.get_instance_id())
	var visual: Node3D = enemy.visual
	var materials := material_state(visual, prototype)
	check(not materials.is_empty() and not native_tokens.is_empty(),
		"The real source has imported material surfaces and controller-owned native meshes")
	var kills_before: int = game.kills
	enemy.hurt(100000.0, null)
	check(not enemy.alive and game.kills == kills_before + 1 and game.deaths.corpses.size() == 1,
		"Real lethal hurt submits one corpse through the actual death signal")
	if game.deaths.corpses.size() != 1: return {}
	var corpse: Dictionary = game.deaths.corpses[0]
	check(corpse.visual == visual and visual.get_parent() == corpse.node and visual.is_visible_in_tree(),
		"The original visible GLB is reparented into the actual corpse wrapper")
	var collected_native := 0
	for value: Variant in corpse.meshes:
		if is_instance_valid(value) and value.get_instance_id() in native_tokens: collected_native += 1
	check(collected_native == native_tokens.size(),
		"The actual corpse collection initially includes all controller-owned native meshes")
	game.simulate(.001)
	await process_frame; await process_frame
	check(not is_instance_id_valid(enemy_token) and game.enemies.is_empty(),
		"The genuinely dead simulation host is released from the actual enemy roster")
	check(not is_instance_id_valid(controller_token) and game.summoners.is_empty() and game.lobbers.is_empty(),
		"Real simulation retires the dead caster controller")
	check(not is_instance_id_valid(prototype_token),
		"Controller cleanup truly frees its transferred native prototype subtree")
	for token: int in native_tokens:
		check(not is_instance_id_valid(token), "The real native mesh instance is actually released")
	var stale_meshes := 0
	for value: Variant in corpse.meshes:
		if not is_instance_valid(value): stale_meshes += 1
	check(stale_meshes == native_tokens.size(),
		"The real corpse array retains released additions, reproducing the production lifecycle")
	check(is_instance_valid(corpse.node) and is_instance_valid(visual) and current_materials_preserved(materials),
		"The actual wrapper and original imported PBR geometry survive native cleanup")
	check(corpse.time == 0.0 and not corpse.settled, "The new corpse has not been advanced or force-settled by the fixture")
	return {"corpse": corpse, "visual": visual, "materials": materials,
		"role": role, "point": point, "stale_meshes": stale_meshes}

func natural_lifecycle(role: String, point: Vector3) -> void:
	print("CASTER_CORPSE_BEGIN ", role, " ", point)
	var prepared := await prepare_corpse(role, point)
	if prepared.is_empty(): return
	var corpse: Dictionary = prepared.corpse
	var visual: Node3D = prepared.visual
	var shadow: MeshInstance3D = corpse.shadow
	var start_pose: Transform3D = corpse.node.global_transform
	game.deaths.tick(.02, "night")
	check(corpse.time == .02 and not corpse.settled and not start_pose.is_equal_approx(corpse.node.global_transform),
		"An unsettled real caster corpse advances its actual fall after native mesh release")
	check(not shadow.visible and shadow.transparency > 0.0,
		"The first actual pose completes its shadow update after released native meshes")
	var early_time: float = corpse.time
	game._process(0.0)
	check(corpse.time == early_time and not shadow.visible,
		"Real controller _process zero also completes the early corpse pose without advancing age")
	var lowest := actual_vertex_clearance(visual)
	for frame in 54:
		game.deaths.tick(STEP, "night")
		lowest = minf(lowest, actual_vertex_clearance(visual))
	check(corpse.settled and corpse.landed and is_instance_valid(visual),
		"The original caster GLB naturally finishes its fall and bounce")
	var settled_gap := actual_vertex_clearance(visual)
	check(lowest >= -.03 and settled_gap <= .12,
		"Retained imported caster geometry stays on actual terrain (lowest %.5f, rest %.5f)" % [lowest, settled_gap])
	check(shadow.visible and shadow.transparency < .001,
		"Settled pose still updates the actual shadow after released native geometry")
	var settled_pose: Transform3D = corpse.node.global_transform
	var settled_time: float = corpse.time
	game._process(0.0)
	check(corpse.time == settled_time and corpse.node.global_transform.is_equal_approx(settled_pose),
		"Real zero-delta controller updates a settled corpse without changing its supported pose")
	for phase in ["paused", "draft"]:
		game.deaths.tick(20.0, phase)
		check(corpse.time == settled_time and corpse.node.global_transform.is_equal_approx(settled_pose),
			"Real " + phase + " freezes the released-addition corpse")
	while float(corpse.time) < float(corpse.dissolve_start) + .2:
		game.deaths.tick(STEP, "night")
	check(corpse.ash_started and corpse.alpha < 1.0 and live_meshes_faded(corpse),
		"All surviving real imported meshes fade and the genuine ash stage starts")
	check(current_materials_preserved(prepared.materials),
		"Retained imported mesh and material references remain unchanged throughout the fade")
	check(shadow.transparency > .0,
		"The actual shadow also fades after the model reaches its natural dissolve stage")
	var fade_time: float = corpse.time
	var fade_alpha: float = corpse.alpha
	game._process(0.0)
	check(corpse.time == fade_time and corpse.alpha == fade_alpha and live_meshes_faded(corpse),
		"The production zero-delta input update preserves genuine active fade")
	var corpse_tokens: Array[int] = [corpse.node.get_instance_id(), visual.get_instance_id(),
		corpse.ash_node.get_instance_id(), shadow.get_instance_id()]
	var limit := ceili(float(corpse.duration) / STEP) + 2
	for frame in limit:
		if game.deaths.corpses.is_empty(): break
		game.deaths.tick(STEP, "night")
	check(game.deaths.corpses.is_empty(), "Natural production lifetime removes the real caster corpse")
	await process_frame; await process_frame
	for token: int in corpse_tokens:
		check(not is_instance_id_valid(token), "Natural expiry truly releases each corpse-owned subtree")
	receipts.append({"role": role, "point": point, "stale_meshes": prepared.stale_meshes,
		"lowest_gap": lowest, "settled_gap": settled_gap, "natural_expiry": true})
	print("CASTER_CORPSE_END ", role, " checks=", checks, " failures=", failures.size())

func retired_real_joint() -> void:
	var prepared := await prepare_corpse("summoner", Vector3(0, 5, 3))
	if prepared.is_empty(): return
	var corpse: Dictionary = prepared.corpse
	check(not corpse.joints.is_empty(), "The actual imported caster rig provides real fall joints")
	if corpse.joints.is_empty(): return
	# This controlled recovery case is an intentionally retired real limb,
	# beyond the naturally retired caster additions exercised above.
	var joint_value: Variant = corpse.joints[0].node
	var joint_token: int = joint_value.get_instance_id()
	joint_value.queue_free(); await process_frame; await process_frame
	check(not is_instance_id_valid(joint_token), "The controlled real-rig limb subtree is genuinely released")
	game.deaths.tick(.1, "night")
	check(corpse.time == .1 and corpse.shadow.visible and corpse.shadow.transparency < .8,
		"Actual fall and shadow continue after a real joint reference becomes invalid")
	check(current_materials_preserved(prepared.materials),
		"Surviving original PBR surfaces remain intact after the controlled limb retirement")
	game.deaths.tick(0.8, "night")
	check(corpse.settled and is_instance_valid(prepared.visual),
		"Surviving real-rig geometry still settles after the controlled missing joint")
	game.deaths.clear(); await process_frame; await process_frame
	check(not is_instance_valid(prepared.visual) and game.deaths.corpses.is_empty(),
		"Explicit production clear releases the remaining original rig subtree")

func final_cleanup() -> void:
	var prepared := await prepare_corpse("lobber", Vector3(0, 5, 3))
	if prepared.is_empty(): return
	var corpse: Dictionary = prepared.corpse
	var visual_token: int = prepared.visual.get_instance_id()
	game.deaths.tick(.1, "ended")
	check(game.deaths.corpses.is_empty(), "Actual ended phase clears a caster corpse with released native additions")
	await process_frame; await process_frame
	check(not is_instance_id_valid(visual_token), "Actual ended cleanup releases its retained original GLB")
	prepared = await prepare_corpse("summoner", Vector3(0, 5, 3))
	if prepared.is_empty(): return
	corpse = prepared.corpse
	var tokens: Array[int] = [corpse.node.get_instance_id(), prepared.visual.get_instance_id(),
		corpse.ash_node.get_instance_id(), corpse.shadow.get_instance_id(), game.deaths.get_instance_id()]
	await game.prepare_shutdown()
	if current_scene == game: current_scene = null
	game.queue_free(); game = null
	for frame in 4: await process_frame
	await create_timer(.2, true, false, true).timeout
	for token: int in tokens:
		check(not is_instance_id_valid(token), "Actual prepared scene shutdown releases each retained caster subtree")

func run() -> void:
	check(RunSession.queue_request(self, SEED, "siege"), "The actual session accepts the fixed standard-run seed")
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game); current_scene = game
	for frame in 5: await process_frame
	game.set_process(false); game.world.set_process(false)
	game.music.persist_settings = false
	check(game.choose_card(0) and game.phase == "night", "The genuine opening card enters the first production night")
	for role in ["summoner", "lobber"]:
		for point: Vector3 in [Vector3(0, 5, 3), Vector3(0, 2.5, 19.5)]:
			await natural_lifecycle(role, point)
	await retired_real_joint()
	await final_cleanup()
	if is_instance_valid(game):
		await game.prepare_shutdown()
		if current_scene == game: current_scene = null
		game.queue_free(); game = null
		for frame in 4: await process_frame
		await create_timer(.2, true, false, true).timeout
	finished = true
	print("NIGHTFALL_CASTER_CORPSES_", "OK" if failures.is_empty() else "FAILED",
		" checks=", checks, " failures=", failures.size(), " real_death_controller_retirement_original_GLB_fall_fade_expiry ", JSON.stringify(receipts))
	quit(0 if failures.is_empty() else 1)
