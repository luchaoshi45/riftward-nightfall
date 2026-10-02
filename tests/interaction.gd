extends SceneTree
## Exercises the actual input pipeline and HUD hit regions, not only methods.
var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func frames(count: int = 3) -> void:
	for i in count: await process_frame

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames()
	event.pressed = false
	Input.parse_input_event(event)
	await frames()

func click(point: Vector2, which: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await frames()
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = which
	event.pressed = true
	Input.parse_input_event(event)
	await frames()
	event.pressed = false
	Input.parse_input_event(event)
	await frames()

func verify(condition: bool, message: String) -> void:
	if not condition:
		push_error("INTERACTION FAILED: " + message)
		quit(1)
		assert(condition, message)
	print("PASS: ", message)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(12)
	game.auto_test = true
	verify(game.mode == "menu", "Starts at menu")
	await click(Vector2(300,655))
	verify(game.mode=="draft","Start opens fate draft")
	await key(KEY_F)
	verify(game.run.rerolls==2,"F rerolls offer")
	await click(Vector2(360,480))
	verify(game.run.selections==1 and game.mode=="playing","Mouse selects card and resumes battle")
	game.run.grant("Input test reward")
	game.open_draft()
	await frames()
	await key(KEY_1)
	verify(game.run.selections==2 and game.mode=="playing","Number key selects card and resumes battle")
	await click(Vector2(810, 500), MOUSE_BUTTON_RIGHT)
	verify(game.player.destination.distance_to(game.player.position) > 1, "Right-click issues move command through HUD")
	await key(KEY_Q)
	verify(game.cooldowns[0] > 0, "Q keyboard input casts")
	await key(KEY_TAB)
	verify(game.build_open,"Tab opens build panel")
	await key(KEY_ESCAPE)
	verify(not game.build_open and game.mode == "playing", "Escape closes build first")
	await key(KEY_ESCAPE)
	verify(game.mode == "paused", "Escape pauses")
	await click(Vector2(700, 435))
	verify(game.mode == "playing", "Resume button")
	await key(KEY_F1)
	verify(game.help_open, "Help opens")
	await key(KEY_ESCAPE)
	verify(not game.help_open, "Help closes")
	await key(KEY_B)
	verify(game.recall_time > 0, "Recall keyboard input")
	await click(Vector2(860, 510), MOUSE_BUTTON_RIGHT)
	verify(game.recall_time == 0, "Moving interrupts recall")
	await key(KEY_B)
	game.player.hurt(10,game.enemy)
	verify(game.recall_time == 0, "Damage interrupts recall")
	game.player.shield = 50
	var hp: float = game.player.hp
	game.player.hurt(25, game.enemy)
	verify(game.player.hp == hp and game.player.shield > 25, "Armor and shield absorb damage")
	game.mana = 0
	game.cooldowns[1] = 0
	await key(KEY_W)
	verify(game.cooldowns[1] == 0, "Insufficient mana rejects cast")
	await click(Vector2(1300,735))
	verify(not game.camera_locked and game.camera_focus.z<0,"Left minimap pans to upper lane")
	await key(KEY_SPACE)
	verify(game.camera_locked,"Space restores camera follow")
	await click(Vector2(1300,842),MOUSE_BUTTON_RIGHT)
	verify(game.player.destination.z>15,"Right minimap moves to bottom lane")
	var core: BattleUnit = game.cores[1]
	var inner: BattleUnit
	var outer: BattleUnit
	for unit in game.units:
		if unit.kind=="tower" and unit.team==1 and unit.lane==1:
			if unit.tier==0: outer=unit
			else: inner=unit
	game.deal_damage(core, 99999, game.player)
	verify(core.alive, "Protected core rejects damage")
	game.deal_damage(outer, 99999, game.player)
	verify(not outer.alive and not game.protected_structure(inner), "Outer tower unlocks inner")
	verify(game.protected_structure(core), "Inner tower still protects core")
	game.deal_damage(inner, 99999, game.player)
	verify(not game.protected_structure(core), "Inner tower unlocks core")
	var other_towers := 0
	for unit in game.units:
		if unit.kind=="tower" and unit.team==1 and unit.alive: other_towers+=1
	verify(other_towers==4,"One open lane unlocks core while other lanes remain")
	game.deal_damage(core, 99999, game.player)
	verify(game.mode == "ended" and game.winner == 0, "Victory through normal damage path")
	await frames()
	game = null
	current_scene.queue_free()
	await frames()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.start_match()
	game.select_card(0)
	game.auto_test = true
	for unit in game.units:
		if unit.kind=="tower" and unit.team==0 and unit.lane==1: unit.hurt(99999,game.enemy)
	game.deal_damage(game.cores[0], 99999, game.enemy)
	verify(game.mode == "ended" and game.winner == 1, "Defeat through core destruction")
	print("RIFTWARD_INTERACTION_OK")
	await frames()
	quit()

