extends SceneTree
## Actual limited summoning, production input/counterplay and unchanged ledgers.
## Explicit parts and long nights isolate behavior, not playable difficulty.
const Layout := preload("res://scripts/outpost_layout.gd")
const RunSession := preload("res://scripts/run_session.gd")
const CleanHud := preload("res://scripts/nightfall_clean_hud.gd")
const SEED := 20261006
const STEP := .05
const HOME := Vector3(0, 5, 3.1)
const SOURCE := Vector3(0, 0, 31)
const FRONT_TOWER := Vector3(0, 5, 10.5)
const VIEWPORTS := [Vector2i(1920, 1200), Vector2i(1920, 1080), Vector2i(1440, 900)]
const OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var drawn_rects: Array[Rect2] = []
var drawn_labels: Array[Dictionary] = []
func _draw() -> void:
\tdrawn_rects.clear(); drawn_labels.clear()
\tsuper._draw()
func box(rect: Rect2, fill: Color = Color(.022,.035,.045,.88), outline: Color = Color('435455')) -> void:
\tdrawn_rects.append(rect)
\tsuper.box(rect,fill,outline)
func label(value: String, point: Vector2, size_px: int, color: Color = Color('e7e1d3'), latin: bool = false) -> void:
\tdrawn_labels.append({'text':value,'point':point,'width':font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x,'size_px':size_px})
\tsuper.label(value,point,size_px,color,latin)
"""
var game: Node3D
var checks := 0
var failures: Array[String] = []
var render_test := false
var output_dir := "res://build/summoner"
var damage_events: Array[Dictionary] = []
var gate_crossings := 0
var evidence: Dictionary = {"fixture_parts": 5000, "fixture_night_seconds": 10000,
	"seed": SEED, "captures": [], "completed": [], "summoner": {}}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	render_test = "--render-test" in args
	var index := args.find("--output-dir")
	if index >= 0 and index + 1 < args.size():
		var candidate := ProjectSettings.globalize_path(args[index + 1]).simplify_path()
		var allowed := ProjectSettings.globalize_path("res://build").simplify_path()
		if candidate.begins_with(allowed + "/"): output_dir = candidate
	root.size = VIEWPORTS[0]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = VIEWPORTS[0]
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 25: push_error(message)

func planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func press(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = true
	root.push_input(event, true)
	event.pressed = false; root.push_input(event, true)
	await process_frame

func mouse(point: Vector2, click: bool = false, button: int = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point; motion.global_position = point
	root.push_input(motion, true); await process_frame
	if not click: return
	var event := InputEventMouseButton.new()
	event.position = point; event.global_position = point; event.button_index = button
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	event.pressed = true; root.push_input(event, true); await process_frame
	event.button_mask = 0; event.pressed = false; root.push_input(event, true); await process_frame

func click_ui(rect: Rect2) -> void:
	await mouse(rect.get_center() * game.hud.get_viewport_rect().size / Vector2(1440, 900), true)

func stand(point: Vector3) -> void:
	point.y = game.outpost_height(point)
	game.hero.position = point; game.move_goal = point
	game.hero_path.clear(); game.hero_keyboard_active = false; game.hero.moving = false
	game.hero.set_locomotion_velocity(Vector3.ZERO)

func camera_at(point: Vector3) -> void:
	game.camera.size = 38.0
	game.camera.position = point + Vector3(0, 25, 29)
	game.camera.look_at(point); game.camera_follow = game.camera.position

func aim_at(point: Vector3) -> void:
	camera_at(point)
	await mouse(game.camera.unproject_position(point))
	game._process(0.0)

func remove_enemies() -> void:
	game.clear_summoners(); game.clear_lobbers()
	for enemy: BattleUnit in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()

func close_game() -> void:
	if not is_instance_valid(game): return
	var ids: Array[int] = []
	for controller: Node3D in game.summoners:
		if is_instance_valid(controller): ids.append(controller.get_instance_id())
	await game.prepare_shutdown()
	check(game.summoners.is_empty() and game.summoner_warning_snapshot().is_empty(), "Actual shutdown clears every summoning controller and warning")
	if current_scene == game: current_scene = null
	game.queue_free(); game = null
	for _frame in 4: await process_frame
	# Let the real audio mixer observe the scene/bus removal as well as the
	# production pre-removal stop. Headless frames may all fit in one mix tick.
	await create_timer(.2, true, false, true).timeout
	for token in ids: check(not is_instance_id_valid(token), "Actual shutdown releases previous controller instances")

func fresh(night: int = 3, keep_wave: bool = false) -> void:
	await close_game()
	check(RunSession.queue_request(self, SEED, "siege"), "Production summoning accepts the real fixed standard seed")
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game); current_scene = game
	for _frame in 5: await process_frame
	game.set_process(false); game.world.set_process(false)
	var script := GDScript.new(); script.source_code = OBSERVER
	check(script.reload() == OK, "The fixed observer subclasses and forwards actual production HUD drawing/input")
	var old: Control = game.hud
	var layer: Node = old.get_parent()
	layer.remove_child(old); old.queue_free()
	var observed: Control = script.new()
	observed.game = game; game.hud = observed; layer.add_child(observed)
	observed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await press(KEY_1)
	game.day_number = night; game.start_night()
	check(game.phase == "night" and game.day_number == night and game.run.seed_value == SEED, "Actual opening/start_night create the intended production night")
	if not keep_wave:
		remove_enemies(); game.wave_index = game.WAVES_PER_NIGHT
	game.scrap = 5000; game.phase_time = 10000.0
	# Isolate the summoned runner's path and actual combat from the starter
	# south-ramp mine, which would legitimately kill it before the city gate.
	game.gate_trap_charges = 0; game.show_gate_trap_charges()
	game.hero.attack_timer = 100000.0; game.pulse_timer = 100000.0; game.spawn_timer = 100000.0
	for pad: Dictionary in game.world.tower_pads: pad.cooldown = 100000.0
	stand(HOME); damage_events.clear()

func controller_for(source: BattleUnit) -> Node3D:
	for controller: Node3D in game.summoners:
		if is_instance_valid(controller) and controller.get("host") == source: return controller
	return null

func spawn(point: Vector3 = SOURCE) -> Dictionary:
	var source: BattleUnit = game.spawn_creature(true, "summoner")
	point.y = game.outpost_height(point); source.position = point
	var controller := controller_for(source)
	check(source.get_meta("threat", "") == "summoner" and source.title == "召潮者" and controller != null,
		"Explicit production spawn creates a real summoner and game-owned controller")
	if controller:
		var state: Dictionary = controller.snapshot()
		check(int(state.max_reinforcements) == 2 and int(state.spawned) == 0,
			"Fresh real source begins with the authoritative lifetime two-person budget")
		check(is_equal_approx((state.entry_position as Vector3).z, Layout.RAMP_END + 3.0)
			and absf((state.entry_position as Vector3).x) <= 1.15
			and game.outpost_walkable(state.entry_position), "Actual reinforcement entry stays on safe ground outside the sole south gate")
	return {"source": source, "controller": controller}

func children_of(token: int) -> Array[BattleUnit]:
	var result: Array[BattleUnit] = []
	for enemy: BattleUnit in game.enemies:
		if (is_instance_valid(enemy) and enemy.alive and bool(enemy.get_meta("summoned_reinforcement", false))
			and int(enemy.get_meta("summoner_token", -1)) == token): result.append(enemy)
	return result

func begin(controller: Node3D) -> void:
	game.simulate(.001)
	var state: Dictionary = controller.snapshot()
	check(state.phase == "windup" and is_equal_approx(float(state.remaining), 2.4)
		and int(state.spawned) == 0, "First real advance starts a full 2.4-second windup without prematurely consuming its frame")
	check(game.summoner_warning_snapshot().size() == 1, "Only an actual live summoning windup appears in the production warning snapshot")

func advance(seconds: float) -> void:
	for frame in ceili(seconds / STEP):
		game.simulate(minf(STEP, seconds - float(frame) * STEP))
		if frame % 100 == 99: await process_frame

func read_state() -> Dictionary:
	var states: Array[Dictionary] = []
	for controller: Node3D in game.summoners:
		if is_instance_valid(controller): states.append(controller.snapshot())
	return {"states": states, "warnings": game.summoner_warning_snapshot(), "parts": int(game.scrap),
		"phase": String(game.phase), "time": float(game.phase_time), "rng": game.run.rng.state,
		"spawn_rng": game.spawn_rng.state, "enemy_count": game.enemies.size(), "goal": game.move_goal,
		"path": game.hero_path.duplicate(), "selection": game.squads.selected_ids.duplicate()}

func capture(label: String) -> void:
	if not render_test: return
	check(DisplayServer.get_name() != "headless", "Summoner images require an actual graphical renderer")
	if DisplayServer.get_name() == "headless": return
	var before := read_state()
	for viewport: Vector2i in VIEWPORTS:
		root.size = viewport; root.content_scale_size = viewport
		game.world.night_mix = 1.0; game.world.apply_lighting(); game.hud.queue_redraw()
		for _frame in 5:
			await process_frame
			await RenderingServer.frame_post_draw
		var picture: Image = root.get_texture().get_image()
		check(picture.get_size() == viewport and Vector2i(game.hud.get_viewport_rect().size) == viewport,
			"Actual summoner PNG/HUD content match " + str(viewport))
		for row: Dictionary in game.hud.drawn_labels:
			if String(row.text).contains("召") or String(row.text).contains("增援"):
				check(row.point.x >= 0 and row.point.x + float(row.width) <= 1440 and row.point.y >= 0 and row.point.y <= 900,
					"Actual new Chinese summoning warning/forecast labels remain within the scaled viewport")
			if String(row.text).begins_with("主威胁"):
				check(row.point.x >= 46 and row.point.x + float(row.width) <= 542,
					"Actual saved-plan composition including possible reinforcements stays inside its own defense drawer")
			if game.hud.detail_tab == "help" and is_equal_approx(float(row.point.x), 46.0) and row.point.y >= 183:
				check(row.point.y + 4 < 692 and row.point.x + float(row.width) <= 542,
					"Actual operation help text stays above the drawer close button and within its text column")
		var local_warnings: Array[Dictionary] = []
		for row: Dictionary in game.hud.drawn_labels:
			if String(row.text).begins_with("召援 ") or String(row.text).begins_with("投蚀 "):
				local_warnings.append(row)
		if label == "summoner-mixed-lobber-warning":
			check(local_warnings.size() == 2, "Actual mixed view must retain both readable source and landing timers")
		for a in local_warnings.size():
			var first_rect := Rect2(local_warnings[a].point - Vector2(3, 14), Vector2(float(local_warnings[a].width) + 6, 19))
			for b in range(a + 1, local_warnings.size()):
				var second_rect := Rect2(local_warnings[b].point - Vector2(3, 14), Vector2(float(local_warnings[b].width) + 6, 19))
				check(not first_rect.intersects(second_rect), "Actual mixed summoning/projectile warning labels cannot overlap one another")
		var folder := ProjectSettings.globalize_path(output_dir)
		DirAccess.make_dir_recursive_absolute(folder)
		var name := "%s-%dx%d" % [label, viewport.x, viewport.y]
		check(picture.save_png(folder.path_join(name + ".png")) == OK, "Actual summoner screenshots stay below local build")
		(evidence.captures as Array).append(name)
	check(read_state() == before, "Actual three-viewport observation cannot summon, spend, move, advance clocks or consume randomness")
	root.size = VIEWPORTS[0]; root.content_scale_size = VIEWPORTS[0]
	for _frame in 3: await process_frame

func timing_cap_and_freeze() -> void:
	await fresh()
	var pack := spawn()
	var source: BattleUnit = pack.source
	var controller: Node3D = pack.controller
	var token := source.get_instance_id()
	var initial_panels: Array = game.hud.live_panel_rects().duplicate()
	check(game.spawn_summoned_reinforcement(source, controller.snapshot().entry_position) == null,
		"The root authority rejects an external early reinforcement request")
	begin(controller)
	check(game.hud.live_panel_rects() == initial_panels, "Starting a summoner warning cannot create another permanent HUD panel")
	var before := read_state()
	for _read in 12: controller.snapshot(); game.summoner_warning_snapshot()
	check(read_state() == before, "Snapshot presentation cannot reserve population or advance its cast")
	camera_at(SOURCE); await capture("summoner-live-windup")
	await press(KEY_ESCAPE)
	check(game.phase == "paused", "Actual Escape pauses a production summoning windup")
	before = read_state()
	game.simulate(20.0); controller.advance(20.0)
	check(read_state() == before, "Pause freezes the live cast, entry warning, source budget and world population")
	await capture("summoner-paused-windup")
	await press(KEY_ESCAPE)
	game.run.grant("召潮验证 · 免费选卡冻结夹具"); await press(KEY_V)
	check(game.phase == "draft", "Actual pending V opens production choice during a summoning windup")
	before = read_state()
	game.simulate(20.0); controller.advance(20.0)
	check(read_state() == before, "Actual card choice freezes summoning without reserving or spawning people")
	await press(KEY_1)
	await advance(2.39)
	check(int(controller.snapshot().spawned) == 0 and children_of(token).is_empty(), "Actual windup cannot produce anybody before the full 2.4 seconds")
	game.simulate(.011)
	var state: Dictionary = controller.snapshot()
	var children := children_of(token)
	check(int(state.spawned) == 1 and state.phase == "cooldown" and is_equal_approx(float(state.cooldown), 10.0)
		and children.size() == 1, "Completed actual windup creates one person and starts ten seconds from successful birth")
	var child: BattleUnit = children[0]
	check(not child.has_meta("wave_reward_id") and child.get_meta("threat", "") == "runner"
		and not Layout.contains_castle(child.position), "Real fast reinforcement is outside the castle and is absent from the wave ledger")
	# Only the timer fixture fixes this already-born runner's speed. Otherwise
	# it legitimately hits a tower, wakes its retaliation and may die before
	# the second birth; lifetime population is independent of current survivors.
	child.speed = 0.0
	await capture("summoner-first-real-birth")
	var source_position := source.position
	await advance(9.99)
	check(int(controller.snapshot().spawned) == 1 and controller.snapshot().phase == "cooldown"
		and source.position == source_position, "Valid source remains stationary and cannot summon before ten genuine cooldown seconds")
	game.simulate(.011)
	check(controller.snapshot().phase == "windup" and is_equal_approx(float(controller.snapshot().remaining), 2.4),
		"Cooldown completion begins a new complete preparation instead of immediately spawning again")
	await advance(2.39)
	check(int(controller.snapshot().spawned) == 1, "Second birth also requires the full real preparation")
	game.simulate(.011)
	var born_tokens: Array[int] = []
	for born: BattleUnit in children_of(token): born_tokens.append(born.get_instance_id())
	check(int(controller.snapshot().spawned) == 2 and int(source.get_meta("summoner_spawned", -1)) == 2
		and children_of(token).size() == 2, "Second genuine birth exhausts exactly the source's two-person lifetime budget")
	check(game.spawn_summoned_reinforcement(source, controller.snapshot().entry_position) == null,
		"Root authority refuses a third reinforcement even when invoked directly")
	controller.clear(); controller.setup(game, source)
	check(int(controller.snapshot().spawned) == 2 and int(controller.snapshot().max_reinforcements) == 2,
		"Clearing/recreating source logic cannot reset the host's authoritative lifetime budget")
	await advance(3.0)
	var no_newborn := true
	for survivor: BattleUnit in children_of(token):
		if not survivor.get_instance_id() in born_tokens: no_newborn = false
	check(no_newborn and int(source.get_meta("summoner_spawned", -1)) == 2,
		"An exhausted source never grows another reinforcement after setup or elapsed time")
	check(source.position != source_position and game.summoner_warning_snapshot().is_empty(),
		"An exhausted source rejoins ordinary nearest-target pursuit and removes the special warning")
	for survivor: BattleUnit in children_of(token): survivor.hurt(100000.0, game.hero)
	stand(source.position + Vector3(0, 0, .8))
	var hp: float = game.hero.hp
	game.simulate(.01)
	check(source.attack_queued and source.attack_windup > 0.0 and source.attack_windup < .4,
		"A genuinely exhausted source starts a normal full melee preparation against the actual nearby hero")
	var found_warning := false
	for warning: Dictionary in game.target_warning_snapshot():
		if warning.source == source and warning.target == game.hero: found_warning = true
	check(found_warning, "Spent source ordinary melee retains the real target-side preparation warning")
	await advance(.4)
	check(game.hero.hp < hp, "Genuinely spent source completes its first natural windup and deals actual melee damage")
	hp = game.hero.hp
	await advance(1.6)
	check(game.hero.hp < hp, "Spent source retains subsequent ordinary melee preparation instead of cancelling it every frame")
	await advance(12.5)
	check(source.alive and int(source.get_meta("summoner_spawned", 0)) == 2 and children_of(token).is_empty(),
		"Killing both real children and waiting longer than cooldown plus cast never replenishes this living source")
	camera_at(source.position)
	await capture("summoner-exhausted-melee")
	(evidence.completed as Array).append("exact_2_4_success_10_lifetime_two_authority_pause_choice_exhausted_melee")

func front_tower(control: bool = false) -> int:
	stand(HOME); await press(KEY_Y); await press(KEY_1); await aim_at(FRONT_TOWER)
	var balance: int = game.scrap
	var before: int = game.world.tower_pads.size()
	await mouse(game.camera.unproject_position(FRONT_TOWER), true)
	check(game.world.tower_pads.size() == before + 1 and game.scrap == balance - 60, "Actual build input creates the counterplay tower")
	await press(KEY_ESCAPE)
	stand(FRONT_TOWER + Vector3(2, 0, 0)); await press(KEY_F)
	var pad: Dictionary = game.world.tower_pads[before]
	check(int(pad.level) == 2, "Actual nearby F pays for the level-two counterplay tower")
	if control:
		await press(KEY_K)
		check(game.specializations.branch(pad) == "control", "Actual K selects the genuine tower slow specialization")
	pad.cooldown = 100000.0
	return before

func control_and_zone_cancel() -> void:
	await fresh()
	var tower := await front_tower(true)
	var pack := spawn(Vector3(0, 0, 26.5))
	var source: BattleUnit = pack.source
	var controller: Node3D = pack.controller
	begin(controller)
	source.hurt(1.0, game.hero); game.simulate(.05)
	check(controller.snapshot().phase == "windup" and int(controller.snapshot().cancelled) == 0,
		"Ordinary nonlethal visual recoil is not real control and cannot cancel summoning")
	source.position = Vector3(0, 0, 50)
	game.simulate(.01)
	check(int(controller.snapshot().cancelled) == 1 and int(controller.snapshot().spawned) == 0
		and not String(controller.snapshot().cancel_reason).is_empty(), "Leaving the legal entry radius cancels unfinished summoning without spending a person")
	source.position = Vector3(0, 0, 26.5); game.simulate(.01)
	check(controller.snapshot().phase == "windup" and is_equal_approx(float(controller.snapshot().remaining), 2.4),
		"Returning to legal ground starts an entirely new preparation")
	var point := Vector3(0, 0, 25.99); point.y = game.outpost_height(point)
	source.position = point; game.simulate(.01)
	check(int(controller.snapshot().cancelled) == 2 and int(controller.snapshot().spawned) == 0,
		"Crossing north of the legal gate-exterior boundary also cancels the source")
	source.position = Vector3(0, 0, 26.5); game.simulate(.01)
	var speed := source.speed
	game.specializations.resolve_shot(game.world.tower_pads[tower], source, game.enemies, 1.0, game.hero)
	check(game.specializations.movement_multiplier(source) < 1.0, "Cancellation uses an actual tower-specialization slow")
	game.simulate(.01)
	check(controller.snapshot().cancel_reason == "source_controlled" and int(controller.snapshot().spawned) == 0
		and source.speed == speed, "Actual slow cancels without rewriting the source's original movement speed")
	await capture("summoner-real-control-cancel")
	await advance(.5)
	check(controller.snapshot().phase != "windup" and int(controller.snapshot().spawned) == 0, "Live control prevents fresh summoning")
	await advance(.71)
	check(controller.snapshot().phase == "windup", "Expired actual control permits a new full cast")
	var hp: float = source.hp
	game.world.tower_pads[tower].cooldown = 0.0
	game.simulate(.01)
	check(source.alive and source.hp < hp and game.specializations.movement_multiplier(source) < 1.0,
		"Actual paid K tower fires a genuine nonlethal controlling shot in this root simulation frame")
	check(controller.snapshot().phase != "windup" and controller.snapshot().cancel_reason == "source_controlled"
		and int(controller.snapshot().spawned) == 0 and game.summoner_warning_snapshot().is_empty(),
		"That same actual tower-hit frame cancels summoning and removes the warning before another simulation call")
	(evidence.completed as Array).append("real_tower_control_expiry_visual_recoil_radius_gate_boundary_full_restart")

func ordinary_melee_outside_source_zone() -> void:
	# Keep the natural HP, attack timing and movement. Real root simulation
	# must complete ordinary hits instead of restarting their windup each frame.
	for point in [Vector3(0, 0, 24), Vector3(0, 0, 44)]:
		await fresh()
		var pack := spawn(point)
		var source: BattleUnit = pack.source
		var controller: Node3D = pack.controller
		stand(point + Vector3(0, 0, .8))
		var hp: float = game.hero.hp
		game.simulate(.01)
		check(source.attack_queued and source.attack_windup > 0.0 and source.attack_windup < .4,
			"Real illegal-zone source begins its normal melee preparation against the actual nearby hero")
		var found := false
		for warning: Dictionary in game.target_warning_snapshot():
			if warning.source == source and warning.target == game.hero:
				found = true
				check(is_equal_approx(float(warning.remaining), source.attack_windup),
					"Illegal-zone melee warning uses the exact real pending attack timing")
		check(found, "Real illegal-zone source shows its ordinary queued attack warning on the actual hero")
		var remaining: float = source.attack_windup
		await press(KEY_ESCAPE)
		check(game.phase == "paused", "Actual pause freezes the illegal-zone ordinary pending melee")
		game.simulate(3.0)
		check(is_equal_approx(source.attack_windup, remaining) and is_equal_approx(game.hero.hp, hp)
			and not game.target_warning_snapshot().is_empty(), "Paused fallback warning and real attack share the unchanged actual windup")
		camera_at(point); await capture("summoner-fallback-melee-" + str(int(point.z)))
		await press(KEY_ESCAPE)
		await advance(.4)
		check(game.hero.hp < hp and int(controller.snapshot().spawned) == 0
			and not source.attack_queued and game.summoner_warning_snapshot().is_empty(),
			"Actual illegal-zone ordinary melee completes its real windup and damages the hero without summoning")
		var first_hp: float = game.hero.hp
		await advance(1.6)
		check(game.hero.hp < first_hp and int(source.get_meta("summoner_spawned", 0)) == 0,
			"Subsequent actual illegal-zone melee also completes rather than repeatedly restarting its preparation")
	(evidence.completed as Array).append("actual_zone_range_fallback_hero_two_complete_melee_hits")

func real_r_and_focus_kills() -> void:
	await fresh()
	var pack := spawn(Vector3(0, 0, 26.5))
	var source: BattleUnit = pack.source
	var controller: Node3D = pack.controller
	var token := source.get_instance_id()
	stand(Vector3(0, 0, 28)); begin(controller); await aim_at(source.position)
	var mana: float = game.mana
	await press(KEY_R)
	check(not is_instance_id_valid(token) or not source.alive, "Actual R key must kill the naturally fragile third-night summoner before its birth")
	check(is_equal_approx(game.mana, mana - 85.0) and game.cooldowns[3] > 0.0,
		"Actual R counterplay retains its real 85-mana payment and cooldown")
	game.simulate(.01)
	check(children_of(token).is_empty() and game.summoner_warning_snapshot().is_empty(), "Real R source death cancels unfinished summoning and leaves no newborn")
	await capture("summoner-real-r-counterplay")
	await fresh()
	var tower := await front_tower()
	pack = spawn(Vector3(0, 0, 26.5)); source = pack.source; controller = pack.controller
	token = source.get_instance_id(); stand(HOME); begin(controller); await aim_at(source.position)
	await press(KEY_C)
	check(game.focus_target == source and game.focus_time > 0, "Actual aiming and C key order towers to focus the summoner")
	game.world.tower_pads[tower].cooldown = 0.0
	for _frame in 46:
		if not is_instance_valid(source) or not source.alive: break
		game.simulate(STEP)
	check(not is_instance_valid(source) or not source.alive, "Real focused tower shots kill the source within its 2.4-second summoning window")
	check(children_of(token).is_empty(), "Real tower counterplay cancels the cast before any reinforcement is born")
	game.simulate(.01)
	await capture("summoner-real-focus-counterplay")
	(evidence.completed as Array).append("real_r_cost_source_death_actual_c_focus_tower_kill_cancel")

func record_hurt(member: BattleUnit, source: BattleUnit, hp_loss: float, shield_loss: float) -> void:
	damage_events.append({"member": member.get_instance_id(), "source": source.get_instance_id() if is_instance_valid(source) else -1,
		"hp": hp_loss, "shield": shield_loss})

func paid_ranged_team(kind: String) -> Dictionary:
	check(game.build_structure_at(Vector3(7, 5, -8.5), "barracks"), "Real paid barracks enables " + kind + " production training")
	if kind == "ballista":
		check(game.build_structure_at(Vector3(-7.5, 5, -8), "workshop"), "Actual paid workshop supplies heavy troop technology")
		check(game.build_structure_at(Vector3(7, 5, -3.5), "laboratory"), "Actual paid research building unlocks the real heavy queue")
	var balance: int = game.scrap
	if kind == "ranged": await press(KEY_I)
	else:
		await press(KEY_F3)
		await click_ui(game.hud.details_tab_rect(2))
		await click_ui(game.hud.troop_page_rect(1))
		check(game.hud.visible_training_kinds()[0] == "ballista", "Real army pagination exposes the heavy troop training button")
		await click_ui(game.hud.training_kind_rect(0))
		await press(KEY_F3)
	check(game.scrap == balance - (80 if kind == "ranged" else 110), "Actual training input charges the real " + kind + " queue cost")
	await advance(8.01 if kind == "ranged" else 10.01)
	check(game.squads.squads.size() == 1 and String(game.squads.squads[0].kind) == kind,
		"Actual paid queue time creates the intended three-person " + kind + " group")
	return game.squads.squads[0]

func ranged_source_priority_and_exhaustion() -> void:
	for kind: String in ["ranged", "ballista"]:
		for spent in [false, true]:
			await fresh()
			var squad := await paid_ranged_team(kind)
			var source: BattleUnit
			var controller: Node3D
			if spent:
				var pack := spawn(); source = pack.source; controller = pack.controller
				begin(controller); await advance(2.401); await advance(10.01); await advance(2.401)
				check(int(source.get_meta("summoner_spawned", 0)) == 2 and not bool(source.get_meta("summoner_active", true)),
					"Two genuinely completed births remove the source's ranged counterplay priority")
				for child: BattleUnit in children_of(source.get_instance_id()): child.hurt(100000.0, game.hero)
				# Keep this naturally spent source out of the formation's route
				# while its real selected movement travels through the gate.
				source.position = Vector3(60, 0, 44)
			await press(KEY_TAB); await aim_at(Vector3(0, 0, 26.5)); await press(KEY_O); await advance(15.0)
			check(String(squad.order) == "guard" and planar(squad.destination, Vector3(0, 0, 26.5)) < .1,
				"Real selected O command stations the paid ranged formation outside the sole gate")
			for member: BattleUnit in squad.members:
				check(planar(member.position, squad.destination) < 1.6 and not member.moving,
					"Actual ranged members must genuinely finish their commanded south-gate route")
			if not spent:
				var pack := spawn(Vector3(0, 0, 32)); source = pack.source; controller = pack.controller
			else: source.position = Vector3(0, 0, 32)
			var breaker: BattleUnit = game.spawn_creature(true, "breaker")
			breaker.position = Vector3(0, 0, 30.5)
			var expected: BattleUnit = breaker if spent else source
			var expected_hp: float = expected.hp
			var other_hp: float = source.hp if spent else breaker.hp
			for member: BattleUnit in squad.members: member.attack_timer = 0.0
			game.simulate(.01)
			for member: BattleUnit in squad.members:
				check(member.target == expected and member.attack_queued and member.attack_windup > 0.0,
					"Actual " + kind + " preparation chooses " + ("the breaker after real exhaustion" if spent else "the active source ahead of the nearer breaker"))
			await advance(.45 if kind == "ballista" else .20)
			check(is_equal_approx(expected.hp, expected_hp), "Real ranged preparation cannot hurt its priority target before its natural windup")
			await advance(.12 if kind == "ballista" else .08)
			check(expected.hp < expected_hp and expected.alive,
				"Actual " + kind + " windup delivers a genuine nonlethal priority shot to its original selected target")
			check(is_equal_approx(source.hp if spent else breaker.hp, other_hp), "The other live threat receives no substituted priority-target damage")
			camera_at(Vector3(0, 0, 29)); await capture("summoner-" + kind + ("-spent-priority" if spent else "-active-priority"))
	(evidence.completed as Array).append("paid_i_army_heavy_queue_actual_guard_route_real_windup_active_priority_spent_breaker_priority")

func real_recovery_and_player_chain() -> void:
	await fresh()
	check(game.build_structure_at(Vector3(-7.5, 5, -8), "workshop"), "Actual paid workshop enables the genuine finite recovery station")
	check(game.build_structure_at(Vector3(0, 5, 11.5), "recycler"), "Actual paid recovery station occupies a valid city grid footprint")
	var station: Dictionary = game.districts.plots[-1]
	var pack := spawn()
	var source: BattleUnit = pack.source
	var controller: Node3D = pack.controller
	stand(Vector3(0, 0, 18.5)); begin(controller); await advance(2.401)
	var children := children_of(source.get_instance_id())
	check(children.size() == 1, "Actual recovery case receives one genuinely summoned reinforcement")
	if children.is_empty(): return
	var child: BattleUnit = children[0]
	for _frame in 200:
		if not is_instance_valid(child) or not child.alive or child.position.z < 21.8: break
		game.simulate(STEP)
	check(is_instance_valid(child) and child.alive and child.position.distance_to(station.position) <= 12.0,
		"Natural newborn genuinely walks into the live station's three-dimensional recovery radius")
	var token := child.get_instance_id()
	var point := child.position
	var wallet: int = game.scrap
	await aim_at(point); await press(KEY_R)
	check((not is_instance_valid(child) or not child.alive) and game.scrap == wallet and int(station.pending) == 2 and int(station.recovered) == 0,
		"Actual R death gives zero base parts but queues one real two-part recoverable wreck")
	check(not game.districts.register_wreck(token, point).accepted and int(station.pending) == 2,
		"The already observed genuine summoned death cannot register a second finite wreck")
	await advance(4.01)
	check(game.scrap == wallet + 2 and int(station.pending) == 0 and int(station.recovered) == 2,
		"Actual station processing pays exactly the allowed finite two-part recovery after four genuine seconds")
	camera_at(station.position); await capture("summoned-real-finite-wreck-recovery")
	await fresh()
	pack = spawn(); source = pack.source; controller = pack.controller
	var source_token := source.get_instance_id()
	begin(controller); await advance(2.401); await advance(10.01); await advance(2.401)
	children = children_of(source_token)
	check(children.size() == 2 and int(source.get_meta("summoner_spawned", 0)) == 2,
		"The real auto-attack case begins with exactly two natural births and their spent source")
	wallet = game.scrap
	var ledger_before: Dictionary = game.wave_rewards.snapshot(10)
	if children.is_empty(): return
	stand(children[0].position + Vector3(0, 0, .8))
	game.hero.attack_timer = 0.0 # End the explicit unrelated-action timing isolation.
	for _frame in 240:
		game.simulate(STEP)
		if game.kill_chain >= 1: break
		if _frame % 100 == 99: await process_frame
	check(game.kill_chain == 1, "Actual auto-attack first defeats the older runner at its real nearest tower target")
	await aim_at(Vector3(0, 0, 27))
	await mouse(game.camera.unproject_position(Vector3(0, 0, 27)), true, MOUSE_BUTTON_RIGHT)
	check(not game.hero_path.is_empty(), "Actual right-click moves the attacking hero up the real ramp to meet the remaining source/newborn")
	for _frame in 800:
		game.simulate(STEP)
		if game.kill_chain == 3: break
		if _frame % 100 == 99: await process_frame
	check(game.kill_chain == 3 and game.attack_count >= 3 and game.hero.alive,
		"Natural production auto-attacks genuinely kill the spent source and its two moving newborns inside real kill windows")
	check(game.scrap == wallet + 9 and not game.player_attack_resolving and game.wave_rewards.snapshot(10) == ledger_before,
		"Three actual source/newborn auto-attack kills retain the real nine-part chain bonus without base or original ledger income")
	check(children_of(source_token).is_empty() and game.summoner_warning_snapshot().is_empty(),
		"Dead reinforcements never replenish the spent lifetime budget")
	(evidence.summoner as Dictionary).merge({"actual_player_attack_count": int(game.attack_count), "actual_player_kill_chain": int(game.kill_chain),
		"actual_player_chain_parts": int(game.scrap) - wallet}, true)
	await capture("summoned-real-player-three-kill-chain")
	(evidence.completed as Array).append("actual_r_zero_base_finite_wreck_two_four_seconds_actual_autoattack_three_kill_bonus_no_ledger")

func real_reinforcement_path_and_troops() -> void:
	await fresh()
	check(game.build_structure_at(Vector3(7, 5, -8.5), "barracks"), "Actual paid barracks enables real defender training")
	await press(KEY_U); await advance(6.01)
	check(game.squads.squads.size() == 1, "Actual U and six seconds produce a real three-person shield group")
	await press(KEY_TAB); await aim_at(Vector3(0, 5, 11)); await press(KEY_O); await advance(8.0)
	for member: BattleUnit in game.squads.squads[0].members: member.damage_confirmed.connect(record_hurt)
	var pack := spawn()
	var source: BattleUnit = pack.source
	var controller: Node3D = pack.controller
	var token := source.get_instance_id()
	begin(controller); await advance(2.401)
	var children := children_of(token)
	check(children.size() == 1, "Real completed preparation produces the path-test reinforcement")
	if children.is_empty(): return
	var child: BattleUnit = children[0]
	var child_token := child.get_instance_id()
	check(String(game.choose_enemy_target(child).get("kind", "")) == "squad", "Actual reinforcement picks the nearest real defensive unit before the more distant core/hero")
	# An explicit lethal real source hit isolates the newborn's independent life.
	# This neither advances module progress nor creates a synthetic child.
	source.hurt(100000.0, game.hero)
	game.simulate(.001)
	check(child.alive and children_of(token).size() == 1, "A genuinely born reinforcement survives source death and source-controller cleanup")
	camera_at(child.position); await capture("summoned-runner-source-released")
	var walked := 0.0
	var reached_gate := false
	for frame in 600:
		if not is_instance_valid(child) or not child.alive: break
		var previous := child.position
		game.simulate(STEP)
		if not is_instance_valid(child) or not child.alive: break
		walked += planar(previous, child.position)
		check(game.outpost_walkable(child.position) and game.can_traverse(previous, child.position)
			and absf(child.position.y - game.outpost_height(child.position)) < .001,
			"Real reinforcement follows walkable ground and continuous true geometry")
		check(planar(previous, child.position) <= child.speed * STEP + .001, "Real reinforcement cannot teleport into the city")
		if previous.z > Layout.WALL_CENTER and child.position.z <= Layout.WALL_CENTER:
			var fraction := (Layout.WALL_CENTER - previous.z) / (child.position.z - previous.z)
			check(absf(lerpf(previous.x, child.position.x, fraction)) < Layout.GATE_HALF,
				"Actual reinforcement enters through the only south gate")
			gate_crossings += 1; reached_gate = true
		if frame % 100 == 99: await process_frame
	check(walked > 10.0 and reached_gate and gate_crossings > 0, "Actual newborn must walk from outside through the sole gate")
	check(not is_instance_id_valid(child_token) or not child.alive, "Real shield attacks must eventually defeat the natural reinforcement")
	var genuine_hurt := false
	for event: Dictionary in damage_events:
		if int(event.source) == child_token and float(event.hp) + float(event.shield) > 0: genuine_hurt = true
	check(genuine_hurt, "Actual reinforcement windup/hurt must hit a real defender before being defeated")
	(evidence.summoner as Dictionary).merge({"gate_crossings": gate_crossings, "reinforcement_walked": walked,
		"real_defender_hurt": damage_events.duplicate(true)}, true)
	(evidence.completed as Array).append("actual_birth_source_release_south_gate_nearest_unit_real_troop_combat")

func real_wave_budgets() -> void:
	var ledgers: Array[Dictionary] = []
	for night in [3, 4]:
		await fresh(night, true)
		var baseline: int = game.scrap
		for wave in 5:
			var id: int = (night - 1) * 5 + wave
			var plan: Dictionary = game.night_plan[wave]
			var entry: Dictionary = game.wave_rewards.snapshot(id)
			check(int(entry.count) == int(plan.count) and int(entry.budget) == 24 and bool(entry.sealed),
				"Actual production ledger registers only the unchanged initial saved wave population")
			check(int(plan.reinforcement_cap) == (2 if wave == 2 else 0)
				and (plan.roles as Array).count("summoner") == (1 if wave == 2 else 0),
				"Only the third wave saves one summoner and a separate two-person possible reinforcement cap")
			var balance: int = game.scrap
			var source: BattleUnit
			var victims: Array = game.enemies.duplicate()
			for victim: BattleUnit in victims:
				if not is_instance_valid(victim) or not victim.alive: continue
				if victim.get_meta("threat", "") == "summoner": source = victim
				else: victim.hurt(100000.0, game.hero)
			if is_instance_valid(source):
				source.position = SOURCE
				var controller := controller_for(source)
				var token := source.get_instance_id()
				var before: Dictionary = game.wave_rewards.snapshot(id)
				begin(controller); await advance(2.401)
				check(game.wave_rewards.snapshot(id) == before, "A real reinforcement birth cannot reopen, enlarge or repay the initial wave ledger")
				var child: BattleUnit = children_of(token)[0]
				var wallet: int = game.scrap
				child.hurt(100000.0, game.hero)
				check(game.scrap == wallet and game.wave_rewards.snapshot(id) == before and game.wave_rewards.defeat(child) == 0,
					"Actual reinforcement death has zero base reward and cannot claim the original wave budget")
				child.hurt(100000.0, game.hero)
				check(game.scrap == wallet, "Repeated real reinforcement death cannot create duplicate base income")
				await advance(10.0); await advance(2.401)
				var second := children_of(token)
				check(second.size() == 1 and int(source.get_meta("summoner_spawned", -1)) == 2,
					"Saved-plan summoner produces no more than two real lifetime births")
				if not second.is_empty(): second[0].hurt(100000.0, game.hero)
				check(game.scrap == wallet and game.wave_rewards.snapshot(id) == before, "Second genuine reinforcement death also leaves the exact original ledger untouched")
				source.hurt(100000.0, game.hero)
			entry = game.wave_rewards.snapshot(id)
			check(bool(entry.cleared) and int(entry.paid) == 24 and game.scrap == balance + 24,
				"All genuine initial wave deaths still settle exactly 24 parts")
			ledgers.append(entry)
			await process_frame
			game.enemies.clear()
			if wave < 4: game.spawn_night_wave()
		check(game.scrap == baseline + 120, "All five genuine third/fourth-night waves still pay exactly 120 base parts")
	(evidence.summoner as Dictionary).waves = ledgers
	(evidence.completed as Array).append("actual_saved_third_fourth_waves_unborn_cap_no_extra_registration_zero_base_deaths_24_120")

func lifecycle_cleanup() -> void:
	for action in ["dawn", "victory", "defeat", "shutdown"]:
		await fresh(4 if action == "victory" else 3)
		var pack := spawn()
		var source: BattleUnit = pack.source
		var controller: Node3D = pack.controller
		var token := controller.get_instance_id()
		begin(controller)
		match action:
			"dawn": game.finish_night(); await press(KEY_1)
			"victory": game.finish_night()
			"defeat": game.end_defeat("召潮验证 · 实际败局清理")
			"shutdown": await game.prepare_shutdown()
		check(game.summoners.is_empty() and game.summoner_warning_snapshot().is_empty(), "Actual " + action + " clears unfinished summoning and every visible warning")
		for _frame in 3: await process_frame
		check(not is_instance_id_valid(token), "Actual " + action + " releases the source-controller instance")
		check(not bool(source.get_meta("summoner_spawned", 0)) if is_instance_valid(source) else true,
			"Lifecycle cleanup cannot fabricate an unfinished newborn")
	(evidence.completed as Array).append("actual_dawn_victory_defeat_shutdown_controller_warning_release")

func real_hud_readability() -> void:
	var measured: Array[Dictionary] = []
	for night in [3, 4]:
		await fresh(night)
		game.wave_index = 2
		game.phase_time = game.NIGHT_LENGTH - float(game.night_plan[2].time) + 4.0
		var preview: Dictionary = game.wave_preview()
		var advice := String(preview.advice)
		var wrapped: Array[String] = CleanHud._wrap(game.hud, advice, 552, 14)
		check(wrapped.size() == 1 and wrapped[0] == advice,
			"Actual production summoner advice fully fits the objective's single allowed line with the real system font")
		measured.append({"night": night, "advice": advice, "actual_font_width": game.hud.font.get_string_size(advice, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x,
			"actual_wrapped_lines": wrapped})
		await capture("summoner-third-wave-objective-night-" + str(night))
		await press(KEY_F3); await click_ui(game.hud.details_tab_rect(3))
		await capture("summoner-defense-drawer-night-" + str(night))
		await click_ui(game.hud.details_tab_rect(4))
		await capture("summoner-operation-help-night-" + str(night))
		await press(KEY_F3)
	for next_night in [3, 4]:
		await fresh(next_night - 1)
		game.finish_night(); await press(KEY_1)
		check(game.phase == "day" and game.day_number == next_night,
			"Actual dawn creates the saved-plan reinforcement forecast for night " + str(next_night))
		await press(KEY_F3); await click_ui(game.hud.details_tab_rect(3))
		await capture("summoner-next-night-day-forecast-" + str(next_night))
	await fresh()
	var pack := spawn()
	stand(Vector3(0, 0, 27.6))
	var lobber: BattleUnit = game.spawn_creature(true, "lobber")
	lobber.position = Vector3(0, 0, 31.3)
	game.simulate(.01)
	check(pack.controller.snapshot().phase == "windup" and game.summoner_warning_snapshot().size() == 1
		and game.lobber_warning_snapshot().size() == 1,
		"Actual nearby thrower and source begin simultaneous real preparations in the mixed warning case")
	camera_at(Vector3(0, 0, 29)); await capture("summoner-mixed-lobber-warning")
	(evidence.summoner as Dictionary).actual_font_measurements = measured
	(evidence.completed as Array).append("actual_system_font_single_objective_day_saved_forecast_defense_help_mixed_warning_three_viewports")

func run() -> void:
	await timing_cap_and_freeze()
	if failures.is_empty(): await control_and_zone_cancel()
	if failures.is_empty(): await ordinary_melee_outside_source_zone()
	if failures.is_empty(): await real_r_and_focus_kills()
	if failures.is_empty(): await real_reinforcement_path_and_troops()
	if failures.is_empty(): await ranged_source_priority_and_exhaustion()
	if failures.is_empty(): await real_recovery_and_player_chain()
	if failures.is_empty(): await real_wave_budgets()
	if failures.is_empty(): await lifecycle_cleanup()
	if failures.is_empty(): await real_hud_readability()
	await close_game()
	var folder := ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("summoner.json"), FileAccess.WRITE)
	check(file != null, "Summoner evidence JSON opens only below local build")
	evidence.checks = checks; evidence.failures = failures
	if file: file.store_string(JSON.stringify(evidence, "\t")); file.close()
	print("NIGHTFALL_SUMMONER_", "OK" if failures.is_empty() else "FAILED", " checks=", checks,
		" actual_2_4_10_lifetime_two source_cancel input_counterplay real_gate_troop_combat original_24_120")
	quit(0 if failures.is_empty() else 1)
