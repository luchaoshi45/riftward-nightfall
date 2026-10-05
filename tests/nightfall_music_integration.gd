extends SceneTree
## Real key/mouse input and a silent Dummy-driver mix probe. Never opens links.
var game: Node3D
var failures: Array[String] = []
var mix_metrics: Dictionary = {}
var capture: AudioEffectCapture
var capture_slot := -1
var graphical := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func frame(count: int = 2) -> void:
	for i in count:
		game.music.update_game(game, 1.0 / 60.0)
		game.hud.queue_redraw()
		await process_frame

func tap(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frame()
	event.pressed = false
	Input.parse_input_event(event)
	await frame()

func click(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var window_point: Vector2 = point * game.hud.get_viewport_rect().size / Vector2(1440,900)
	var motion := InputEventMouseMotion.new()
	motion.position = window_point
	motion.global_position = window_point
	root.push_input(motion, true)
	await frame()
	var event := InputEventMouseButton.new()
	event.position = window_point
	event.global_position = window_point
	event.button_index = button
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else (MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else 0)
	event.pressed = true
	root.push_input(event, true)
	await frame()
	event.button_mask = 0
	event.pressed = false
	root.push_input(event, true)
	await frame()

func settle(seconds: float = 3.0) -> void:
	# The game uses a fixed test clock; the audio server has its own mix clock.
	for i in ceili(seconds * 60.0):
		game.music.update_game(game, 1.0 / 60.0)
	await frame()

func screenshot(path: String) -> void:
	if not graphical: return
	game.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(path) == OK, "Save visual check " + path)

func sample_mix(name: String, expect_signal: bool) -> void:
	capture.clear_buffer()
	await create_timer(.18).timeout
	capture.clear_buffer()
	await create_timer(.36).timeout
	var buffer := capture.get_buffer(capture.get_frames_available())
	var square_sum := 0.0
	var peak := 0.0
	for sample in buffer:
		square_sum += sample.x * sample.x + sample.y * sample.y
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	var rms := sqrt(square_sum / maxf(1.0, buffer.size() * 2.0))
	mix_metrics[name] = {"frames": buffer.size(), "rms": rms, "peak": peak}
	check(buffer.size() > 1000, name + ": Dummy driver must deliver actual mix frames")
	check(peak < .98, name + ": mixed music must not clip")
	check(rms > .0002 if expect_signal else peak < .00001, name + ": actual signal / silence must match controls")

func clear_enemies() -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()

func run() -> void:
	graphical = DisplayServer.get_name() != "headless"
	game = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	game.music.persist_settings = false
	game.music.set_muted(false)
	game.music.set_volume(.65)
	check(game.phase == "draft", "First-night card choice is the actual initial phase")
	check(game.music.missing_tracks.is_empty(), "All three packaged music tracks must load")
	await settle()
	check(game.music.active_track == "night", "The opening night draft starts the quiet night cue")
	if graphical:
		await screenshot("res://build/music-opening.png")
	check(game.hud.card_rects.size() == 3, "Actual production draft drawing exposes three card hit areas")
	await tap(KEY_F1)
	check(game.music_credits_open and game.phase == "draft", "Credits over the initial choice preserve draft")
	var selections: int = game.run.selections
	await tap(KEY_1)
	await click(Vector2(350,430))
	check(game.run.selections == selections and game.phase == "draft", "Credits block both card shortcuts and the underlying card mouse hit area")
	await tap(KEY_M)
	check(game.music.muted, "M remains available inside credits")
	await tap(KEY_M)
	await tap(KEY_BRACKETLEFT)
	check(is_equal_approx(game.music.get_volume(), .55), "The left bracket reduces music by ten percentage points")
	await tap(KEY_BRACKETRIGHT)
	check(is_equal_approx(game.music.get_volume(), .65), "The right bracket restores the music volume")
	await tap(KEY_ESCAPE)
	check(not game.music_credits_open and game.phase == "draft", "ESC closes only the initial credits panel")
	await click(Vector2(350,430))
	check(game.phase == "night" and game.run.selections == selections + 1, "The same real mouse click chooses a card once the overlay is closed")
	clear_enemies()
	game.wave_warning_issued = false
	game.spawn_timer = 1000.0
	game.wave_index = game.WAVES_PER_NIGHT
	await frame()
	await settle()
	check(game.music.active_track == "night", "Calm night uses the night cue")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	capture_slot = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, capture)
	await sample_mix("night_playing", true)
	var current_player: AudioStreamPlayer = game.music.players[game.music.target_player]
	var before_mute: float = current_player.get_playback_position()
	await tap(KEY_M)
	await sample_mix("muted_night", false)
	check(current_player.playing and current_player.get_playback_position() > before_mute, "Muting preserves advancing music playback instead of restarting the cue")
	var enemy: BattleUnit = game.spawn_creature(false)
	enemy.position = game.hero.position + Vector3(3,0,0)
	enemy.hp = 10000
	enemy.damage = 0
	await settle()
	check(game.music.active_track == "combat" and game.music.muted, "A real nearby enemy switches to combat while preserving mute")
	await sample_mix("muted_combat", false)
	await tap(KEY_M)
	await sample_mix("combat_restored", true)
	clear_enemies()
	await frame()
	await settle(6.5)
	check(game.music.active_track == "night", "Combat has a hold interval and returns to calm night after the threat leaves")
	await tap(KEY_F1)
	check(game.music_credits_open and game.phase == "paused" and game.paused_from == "night", "F1 pauses a playable night before displaying credits")
	var remaining: float = game.phase_time
	var goal: Vector3 = game.move_goal
	var camera_size: float = game.camera.size
	var mana: float = game.mana
	await tap(KEY_R)
	await click(Vector2(1340,600), MOUSE_BUTTON_RIGHT)
	await click(Vector2(1340,600), MOUSE_BUTTON_WHEEL_UP)
	check(game.move_goal == goal and is_equal_approx(game.camera.size, camera_size) and is_equal_approx(game.mana, mana), "Credits block movement, zoom and skill commands")
	for i in 10: game._process(.05)
	check(is_equal_approx(game.phase_time, remaining), "Opening music credits freezes the real game simulation")
	check(game.music.paused and current_player.stream_paused, "Pausing suspends the music playback clock")
	await sample_mix("paused_credits", false)
	await screenshot("res://build/music-credits.png")
	await tap(KEY_F1)
	check(not game.music_credits_open and game.phase == "paused", "Closing F1 preserves pause instead of resuming gameplay")
	await screenshot("res://build/music-pause.png")
	await tap(KEY_BRACKETLEFT)
	check(is_equal_approx(game.music.get_volume(), .55), "Music volume controls still work while paused")
	await tap(KEY_BRACKETRIGHT)
	await tap(KEY_ESCAPE)
	check(game.phase == "night" and not game.music.paused, "ESC explicitly resumes the original playable phase and music")
	await settle()
	await sample_mix("resumed_night", true)
	await tap(KEY_BRACKETLEFT)
	for i in 20: await tap(KEY_BRACKETLEFT)
	check(is_equal_approx(game.music.get_volume(), 0.0), "Music volume is clamped at zero")
	await sample_mix("zero_volume", false)
	for i in 20: await tap(KEY_BRACKETRIGHT)
	check(is_equal_approx(game.music.get_volume(), 1.0), "Music volume is clamped at one")
	await sample_mix("maximum_volume", true)
	game.phase = "day"
	await settle()
	check(game.music.active_track == "day", "The daytime exploration cue follows a day transition")
	await sample_mix("day_playing", true)
	await tap(KEY_F1)
	check(game.paused_from == "day" and game.phase == "paused", "Day credits also remember the correct phase")
	await tap(KEY_ESCAPE)
	check(game.phase == "paused" and not game.music_credits_open, "ESC closes credits and keeps the day paused")
	await tap(KEY_ESCAPE)
	check(game.phase == "day", "A second ESC resumes the original day phase")
	game.phase = "ended"
	await settle()
	check(game.music.target_player == -1 and is_zero_approx(game.music.context_gain), "Ending the run fades out gameplay music")
	await sample_mix("ended", false)
	await tap(KEY_F1)
	await tap(KEY_ENTER)
	check(game.music_credits_open and game.phase == "ended" and current_scene == game, "Credits at the ending block accidental run restart")
	await tap(KEY_ESCAPE)
	check(game.phase == "ended" and not game.music_credits_open, "Closing end credits preserves the result")
	AudioServer.remove_bus_effect(0, capture_slot)
	var report := FileAccess.open("res://build/music-integration-mix.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(mix_metrics, "\t"))
	report.close()
	print("MUSIC_MIX_METRICS ", JSON.stringify(mix_metrics))
	if failures.is_empty():
		print("NIGHTFALL_MUSIC_INTEGRATION_OK")
		quit(0)
	else:
		print("NIGHTFALL_MUSIC_INTEGRATION_FAILED count=", failures.size())
		quit(1)
