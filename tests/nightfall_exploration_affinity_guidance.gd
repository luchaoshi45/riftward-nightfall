extends SceneTree
## Production P/F guidance: reachable affinity targets, honest fallback and bounded A*.
## Render with --position 10000,10000 --audio-driver Dummy -- --render-test.
const Layout = preload("res://scripts/outpost_layout.gd")
const HOME := Vector3(0, 5, 3.1)
const SOUTH_FIELD := Vector3(0, 0, Layout.RAMP_END + 5.0)
const WALL_SIDE := Vector3(Layout.FORT_TERRAIN_EDGE + .5, 0, Layout.WALL_CENTER + 2.7)
const FIELD := Vector3(18, 0, 0)
const FAR := Vector3(105, 0, 95)
const STEP := 1.0 / 60.0
const LABELS := {"ember_bloom":"余烬花", "memory_crystal":"余烬晶簇", "supply_cache":"补给箱", "waylight":"灯碑"}
var game: Node3D
var failures: Array[String] = []
var checks := 0
var render_test := false
var observed_queries := 0
var walked_distance := 0.0

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	render_test = "--render-test" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	push_error(message)

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func put_hero(point: Vector3) -> void:
	point.y = game.outpost_height(point)
	game.hero.position = point
	game.move_goal = point
	game.hero_path.clear()
	game.hero_keyboard_active = false

func clear_enemies() -> void:
	for enemy: BattleUnit in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()

func reset_case() -> void:
	game.phase = "day"
	game.phase_time = 900.0
	game.contracts.status = "idle"
	game.contracts.day_id = game.day_number
	game.exploration.setup(game, 0)
	game.exploration.begin_day(2)
	game.exploration_count = 0
	game.exploration_milestones = 0
	game.scrap = 500
	game.reward_toasts.clear()
	game.clear_exploration_marker()
	put_hero(HOME)
	for item: Dictionary in game.discoveries.items:
		game.discoveries.begin_cooling(item, 9999.0)
		item.position = FAR
		item.node.position = FAR
	for animal: Dictionary in game.wildlife.animals:
		animal.state = "cooldown"
		animal.refresh = 9999.0
		animal.node.visible = false
	for cache: Dictionary in game.world.salvage:
		cache.collected = true
		cache.respawn = 9999.0
	for generator: Dictionary in game.expeditions.generators: generator.state = "complete"
	for camp: Dictionary in game.expeditions.camps: camp.state = "delivered"
	for nest: Dictionary in game.world.nests: nest.cleansed = true
	for relay: Dictionary in game.world.relays: relay.activated = true
	game.discoveries.motivation_route_queries = 0

func ready(index: int, kind: String, point: Vector3) -> Dictionary:
	var item: Dictionary = game.discoveries.items[index]
	point.y = game.outpost_height(point)
	item.kind = kind
	item.position = point
	item.node.position = point
	item.state = "ready"
	item.progress = 0.0
	item.remaining = 0.0
	item.serial += 1
	game.discoveries.replace_model(item)
	game.discoveries.motivation_revision += 1
	return item

func target_is(target: Dictionary, source: Dictionary, reason: String, title: String) -> void:
	check(not target.is_empty(), title + " must expose an actual available target")
	if target.is_empty(): return
	check(int(target.get("index", -1)) == game.discoveries.items.find(source), title + " must select the authoritative source")
	check(int(target.get("serial", -1)) == int(source.serial), title + " must expose the current source generation")
	check(String(target.get("kind", "")) == String(source.kind), title + " must expose the actual selected kind")
	check(String(target.get("reason", "")) == reason, title + " must report its genuine selection reason")
	check((target.get("position", Vector3.INF) as Vector3).is_equal_approx(source.position), title + " must expose the actual source location")
	var text: String = game.discoveries.motivation_target_text(target)
	check(text.contains("共鸣目标" if reason == "affinity" else "下一站"), title + " HUD must label the selection honestly")
	check(text.contains(String(LABELS[source.kind])), title + " HUD must identify the real resource type")
	check(game.hud.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x <= 302.0,
		title + " HUD target line must stay inside the exploration panel")
	if reason == "route": check(not text.contains("共鸣目标"), title + " fallback must not advertise an affinity reward")

func check_path(goal: Vector3, title: String) -> void:
	check(not game.hero_path.is_empty(), title + " must create a real player path")
	check(flat_distance(game.move_goal, goal) < .01, title + " must end at the true selected resource")
	var previous: Vector3 = game.hero.position
	for point: Vector3 in game.hero_path:
		check(game.can_traverse(previous, point), title + " must use the unique traversable south-gate route")
		previous = point

func travel(goal: Vector3) -> bool:
	var elapsed := 0.0
	var idle_frames := 0
	while flat_distance(game.hero.position, goal) > .18 and elapsed < 30.0:
		var previous: Vector3 = game.hero.position
		game.simulate(STEP)
		var distance := flat_distance(previous, game.hero.position)
		walked_distance += distance
		check(game.can_traverse(previous, game.hero.position), "Actual P movement must not cross a retaining wall")
		check(is_equal_approx(game.hero.position.y, game.outpost_height(game.hero.position)), "Actual P movement must stay on the authored terrain")
		idle_frames = idle_frames + 1 if distance < .00001 else 0
		if idle_frames > 30: break
		elapsed += STEP
	check(flat_distance(game.hero.position, goal) <= .18, "Actual P movement must reach its true affinity target")
	check(idle_frames <= 30, "Actual P movement must not stick at a gate or wall")
	game.hero_path.clear()
	game.move_goal = game.hero.position
	return flat_distance(game.hero.position, goal) <= .18

func complete_collection() -> void:
	for index in 4:
		var kind: String = game.discoveries.KINDS[index]
		var item := ready(index, kind, FIELD)
		put_hero(FIELD)
		await press(KEY_F)
		if kind == "supply_cache":
			check(item.state == "channel", "Production F must begin the real cache channel during collection")
			game.simulate(3.01)
		check(item.state == ("active" if kind == "waylight" else "cooling"), "Production F must consume every real collection type")
		game.discoveries.begin_cooling(item, 9999.0)
	check(game.exploration.full_set_claimed and game.exploration.next_kind().is_empty(), "The actual four-type collection must be paid and have no ordinary next kind")

func collection_affinity_action() -> void:
	reset_case()
	await complete_collection()
	var flower := ready(0, "ember_bloom", SOUTH_FIELD)
	put_hero(HOME)
	check(game.discoveries.motivation_target().is_empty(), "Collected four types without affinity must have no fake next target")
	game.exploration.arm_contract_affinity(["ember_bloom"])
	var target: Dictionary = game.discoveries.motivation_target()
	target_is(target, flower, "affinity", "Completed collection affinity")
	game.update_exploration_guidance()
	check(is_instance_valid(game.motivation_marker) and flat_distance(game.motivation_marker.position, flower.position) < .01,
		"A completed collection must still show its actual affinity world marker")
	await capture("collection-affinity")
	await press(KEY_P)
	check_path(flower.position, "Completed collection P")
	if not await travel(flower.position): return
	var scrap: int = game.scrap
	var count: int = game.exploration_count
	await press(KEY_F)
	check(flower.state == "cooling" and not game.exploration.affinity_active(), "Real F must consume both the flower and its matching affinity once")
	check(game.scrap - scrap == 75 and game.exploration_count == count + 1,
		"Real F after collection must pay 12 flower + 55 milestone + 8 affinity scrap")
	check(game.discoveries.motivation_target().is_empty(), "Affinity consumption must invalidate the still-fresh cache immediately")
	game.update_exploration_guidance()
	check(not is_instance_valid(game.motivation_marker), "Consumed affinity with no next kind must immediately clear its marker")
	ready(0, "ember_bloom", flower.position)
	scrap = game.scrap
	await press(KEY_F)
	check(game.scrap - scrap == 12,
		"A second real flower interaction must preserve its base reward without repeating the consumed eight scrap")

func nearest_types_and_gate() -> void:
	reset_case()
	var ordinary := ready(0, "ember_bloom", Vector3(-18, 0, 0))
	var crystal := ready(1, "memory_crystal", SOUTH_FIELD)
	var lamp := ready(2, "waylight", Vector3(35, 0, 20))
	target_is(game.discoveries.motivation_target(), ordinary, "route", "Ordinary seeded route")
	game.exploration.arm_contract_affinity(["waylight", "memory_crystal"])
	target_is(game.discoveries.motivation_target(), crystal, "affinity", "Nearest among matching types")
	game.exploration.arm_contract_affinity(["waylight"])
	target_is(game.discoveries.motivation_target(), lamp, "affinity", "Changed matching set inside cache window")
	game.exploration.arm_contract_affinity(["memory_crystal"])
	target_is(game.discoveries.motivation_target(), crystal, "affinity", "Restored matching set inside cache window")
	reset_case()
	var behind_wall := ready(0, "ember_bloom", WALL_SIDE)
	crystal = ready(1, "memory_crystal", SOUTH_FIELD)
	game.exploration.arm_contract_affinity(["ember_bloom", "memory_crystal"])
	check(flat_distance(HOME, behind_wall.position) < flat_distance(HOME, crystal.position), "Gate fixture must make the wall-side source look nearer in a straight line")
	check(not game.can_traverse(HOME, behind_wall.position) and game.can_traverse(HOME, crystal.position), "Gate fixture must really require a detour for the wall-side source")
	check(game.discoveries.route_distance(HOME, behind_wall.position) > game.discoveries.route_distance(HOME, crystal.position),
		"Actual gate routes must make the southern source closer")
	target_is(game.discoveries.motivation_target(), crystal, "affinity", "Reachable gate distance beats straight-line proximity")
	await press(KEY_P)
	check_path(crystal.position, "Gate distance P")

func unavailable_and_expiry() -> void:
	reset_case()
	var ordinary := ready(0, "ember_bloom", Vector3(-18, 0, 0))
	game.exploration.arm_contract_affinity(["memory_crystal"])
	target_is(game.discoveries.motivation_target(), ordinary, "route", "No ready match falls back")
	ready(1, "memory_crystal", Vector3(180, 0, 180))
	target_is(game.discoveries.motivation_target(), ordinary, "route", "Unreachable match falls back")
	game.discoveries.begin_cooling(ordinary, 9999.0)
	check(game.discoveries.motivation_target().is_empty(), "No reachable affinity or ordinary point must return an empty target")
	var empty_text: String = game.discoveries.motivation_target_text({})
	check(empty_text.contains("暂无可达共鸣点"), "An empty active-affinity HUD must honestly state that no matching point is reachable")
	game.update_exploration_guidance()
	check(not is_instance_valid(game.motivation_marker), "Unavailable affinity must not leave a misleading world marker")
	await capture("no-reachable-affinity")
	reset_case()
	ordinary = ready(0, "ember_bloom", Vector3(-18, 0, 0))
	var crystal := ready(1, "memory_crystal", SOUTH_FIELD)
	game.exploration.arm_contract_affinity(["memory_crystal"])
	game.simulate(74.99)
	target_is(game.discoveries.motivation_target(), crystal, "affinity", "Affinity just before actual expiration")
	game.update_exploration_guidance()
	game.simulate(.02)
	check(not game.exploration.affinity_active() and game.discoveries.motivation_refresh_time > 0.0,
		"Affinity must expire while its geometry cache is still fresh")
	target_is(game.discoveries.motivation_target(), ordinary, "route", "Expiration immediately restores the ordinary route")
	game.update_exploration_guidance()
	check(is_instance_valid(game.motivation_marker) and flat_distance(game.motivation_marker.position, ordinary.position) < .01,
		"Expiration must immediately move the world marker to the real fallback")
	await capture("expired-fallback")
	# If the ordinary collection is already complete, expiration clears rather
	# than inventing a replacement target.
	for kind: String in game.discoveries.KINDS: game.exploration.day_kinds[kind] = true
	game.exploration.full_set_claimed = true
	game.exploration.arm_contract_affinity(["memory_crystal"])
	game.exploration.affinity_time = .01
	game.update_exploration_guidance()
	game.simulate(.02)
	game.update_exploration_guidance()
	check(game.discoveries.motivation_target().is_empty() and not is_instance_valid(game.motivation_marker),
		"Expiration after a completed collection must clear its still-fresh marker")

func refresh_generations() -> void:
	reset_case()
	var ordinary := ready(0, "ember_bloom", Vector3(-18, 0, 0))
	var near := ready(1, "memory_crystal", SOUTH_FIELD)
	var far := ready(2, "memory_crystal", Vector3(30, 0, 30))
	game.exploration.arm_contract_affinity(["memory_crystal"])
	target_is(game.discoveries.motivation_target(), near, "affinity", "Ready generation before cooling")
	game.discoveries.begin_cooling(near, .01)
	target_is(game.discoveries.motivation_target(), far, "affinity", "Cooling immediately selects another real match")
	var old_serial: int = near.serial
	var old_kind: String = near.kind
	game.discoveries.tick(.02)
	check(near.state == "ready" and near.serial == old_serial + 1 and near.kind != old_kind,
		"Actual respawn must change source kind and generation")
	target_is(game.discoveries.motivation_target(), far, "affinity", "Respawned different kind must not retain a stale affinity match")
	game.discoveries.begin_cooling(ordinary, 9999.0)
	game.exploration.arm_contract_affinity([String(near.kind)])
	target_is(game.discoveries.motivation_target(), near, "affinity", "New affinity must use the actual respawned kind and serial")

func contract_priority() -> void:
	reset_case()
	for cache: Dictionary in game.world.salvage: cache.collected = false
	for generator: Dictionary in game.expeditions.generators: generator.state = "ready"
	for camp: Dictionary in game.expeditions.camps: camp.state = "waiting"
	for nest: Dictionary in game.world.nests: nest.cleansed = false
	game.contracts.setup(game, 0)
	game.contracts.on_day()
	check(game.contracts.status == "active" and not game.contracts.offers.is_empty(), "The real day generator must provide a main contract")
	if game.contracts.status != "active": return
	if game.contracts.offers.size() > 1:
		await press(KEY_5)
		check(game.contracts.selected_offer == 1, "Actual 5 must select a real untouched main contract")
		await press(KEY_4)
		check(game.contracts.selected_offer == 0, "Actual 4 must restore the real safe main contract")
	var goal: Vector3 = game.contract_goal()
	var point := SOUTH_FIELD
	if flat_distance(goal, point) < 1.0: point = Vector3(-20, 0, 20)
	var crystal := ready(1, "memory_crystal", point)
	game.exploration.arm_contract_affinity(["memory_crystal"])
	target_is(game.discoveries.motivation_target(), crystal, "affinity", "Main contract preserves the true affinity suggestion")
	var text: String = game.discoveries.motivation_target_text(game.discoveries.motivation_target())
	check(text.contains("P优先委托"), "The shared HUD text must state that P follows the active main contract first")
	game.update_day_contracts(0.0)
	game.update_exploration_guidance()
	await capture("contract-priority")
	await press(KEY_P)
	check_path(goal, "Main contract priority P")
	check(flat_distance(game.move_goal, crystal.position) > 1.0, "Actual P must not replace the main contract with an affinity suggestion")
	game.contracts.status = "completed"
	put_hero(HOME)
	await press(KEY_P)
	check_path(crystal.position, "Completed contract releases P to affinity")

func freeze_and_cache() -> void:
	reset_case()
	ready(0, "ember_bloom", Vector3(-18, 0, 0))
	var crystal := ready(1, "memory_crystal", WALL_SIDE)
	ready(2, "waylight", Vector3(-WALL_SIDE.x, 0, WALL_SIDE.z))
	game.exploration.arm_contract_affinity(["memory_crystal", "waylight"])
	game.discoveries.motivation_target()
	var initial_queries: int = game.discoveries.motivation_route_queries
	check(initial_queries >= 2, "Cache regression must exercise both actual A* routes around the high-ground walls")
	for _frame in 120:
		game.simulate(STEP)
		var first: Dictionary = game.discoveries.motivation_target()
		var second: Dictionary = game.discoveries.motivation_target()
		check(first == second, "Two HUD reads in one stable frame must share the same live affinity target")
	observed_queries = game.discoveries.motivation_route_queries - initial_queries
	check(observed_queries <= 18, "Two stable HUD reads over 120 frames must throttle A* refreshes (queries=%d)" % observed_queries)
	var previous_queries: int = game.discoveries.motivation_route_queries
	put_hero(Vector3(.4, 5, 3.3))
	game.discoveries.motivation_target()
	check(game.discoveries.motivation_route_queries == previous_queries, "Moving inside the same two-metre cell must reuse the fresh route cache")
	put_hero(HOME)
	game.discoveries.motivation_target()
	# Reordering the same matching set must not be a new geometry request.
	previous_queries = game.discoveries.motivation_route_queries
	game.exploration.arm_contract_affinity(["waylight", "memory_crystal"])
	game.discoveries.motivation_target()
	check(game.discoveries.motivation_route_queries == previous_queries, "The same affinity kind set in another order must retain its normalized cache key")
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "Actual Esc must pause the affinity regression")
	for phase_name: String in ["paused", "draft"]:
		if phase_name == "draft":
			await press(KEY_ESCAPE)
			game.run.grant("共鸣指引冻结验证")
			await press(KEY_V)
			check(game.phase == "draft", "Actual V must enter the production queued-card selection")
		var affinity_time: float = game.exploration.affinity_time
		var refresh_time: float = game.discoveries.motivation_refresh_time
		var clock: float = game.phase_time
		previous_queries = game.discoveries.motivation_route_queries
		var source_serial: int = crystal.serial
		game._process(30.0)
		game.discoveries.motivation_target()
		game.discoveries.motivation_target()
		await press(KEY_P)
		await press(KEY_F)
		check(game.exploration.affinity_time == affinity_time and game.discoveries.motivation_refresh_time == refresh_time and game.phase_time == clock,
			"%s must freeze affinity, geometry-cache and phase clocks" % phase_name)
		check(game.discoveries.motivation_route_queries == previous_queries,
			"%s HUD reads must not rebuild the frozen affinity route" % phase_name)
		check(crystal.serial == source_serial and crystal.state == "ready" and game.hero_path.is_empty(),
			"%s P/F must not move, consume or respawn the real affinity source" % phase_name)

func capture(state: String) -> void:
	if not render_test: return
	check(DisplayServer.get_name() != "headless", "Render verification must use an actual graphics renderer")
	if DisplayServer.get_name() == "headless": return
	# Cases advance simulate directly, so earlier transient notices do not age
	# through _process. Capture the current target rather than an old P/F toast.
	game.notice = ""
	game.notice_time = 0.0
	game.world.night_mix = 0.0
	game.world.set_night(false)
	game.camera.size = 31.0
	game.camera_follow = game.hero.position + Vector3(0, 25, 29)
	game.camera.position = game.camera_follow
	game.hud.queue_redraw()
	for _frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var path := "res://build/nightfall-affinity-guidance-%s.png" % state
	check(root.get_texture().get_image().save_png(path) == OK, "Hidden %s affinity HUD frame must save" % state)
	print("AFFINITY_GUIDANCE_FRAME ", ProjectSettings.globalize_path(path))

func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	await press(KEY_1)
	check(game.phase == "night", "Actual opening card must enter the playable production scene")
	clear_enemies()
	game.day_number = 2
	await process_frame
	check(game.discoveries.has_method("motivation_target_text"), "Production discoveries must supply the shared truthful guidance text")
	if game.discoveries.has_method("motivation_target_text"):
		await collection_affinity_action()
		await nearest_types_and_gate()
		await unavailable_and_expiry()
		await refresh_generations()
		await contract_priority()
		await freeze_and_cache()
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	if failures.is_empty():
		print("NIGHTFALL_EXPLORATION_AFFINITY_GUIDANCE_OK checks=", checks, " queries_120_frames=", observed_queries,
			" actual_P_travel=", walked_distance, " four_set_affinity_F nearest_gate fallback consume_expire generation main_contract freeze")
		quit()
	else:
		print("NIGHTFALL_EXPLORATION_AFFINITY_GUIDANCE_FAILED checks=", checks, " failures=", failures.size())
		quit(1)
