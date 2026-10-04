extends SceneTree
var game: Node3D
func _initialize() -> void:call_deferred("run")
func clear_enemies() -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()
func verify_wave(entry: Dictionary) -> void:
	assert(game.enemies.size()==entry.count)
	var expected: Dictionary={};var actual: Dictionary={}
	for role in entry.roles:
		var kind: String="stalker" if role=="basic" else role
		expected[kind]=int(expected.get(kind,0))+1
	if bool(entry.get("boss_entry",false)):
		expected["breaker"]=int(expected.get("breaker",0))+1
	for enemy in game.enemies:
		var kind: String=enemy.get_meta("threat","")
		actual[kind]=int(actual.get(kind,0))+1
	assert(actual==expected,"Preview composition must equal actual spawned roles")
func run() -> void:
	game=load("res://scenes/nightfall.tscn").instantiate();root.add_child(game);current_scene=game
	for i in 8:await process_frame
	game.set_process(false);game.choose_card(0)
	assert(game.night_plan.size()==5 and game.spawn_timer==20)
	verify_wave(game.night_plan[0])
	assert(game.wave_preview().threat=="runner")
	var copy: Dictionary=game.wave_preview();copy.roles.clear()
	assert(not game.night_plan[1].roles.is_empty())
	game.phase="paused";game.simulate(21);assert(game.phase_time==105)
	game.phase="night"
	for wave in range(1,5):
		clear_enemies();await process_frame
		game.phase_time=105-float(game.night_plan[wave].time)+.1
		game.simulate(.11)
		assert(game.wave_index==wave+1)
		verify_wave(game.night_plan[wave])
		if wave==3 and DisplayServer.get_name()!="headless":
			game.notice_time=0;game.hud.queue_redraw();await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/wave-preview.png")
	assert(game.wave_preview().is_empty())
	clear_enemies();game.day_number=2;game.start_night()
	verify_wave(game.night_plan[0]);assert(game.night_plan[0].roles.has("light_eater"))
	var count: int=game.night_plan[0].count
	for nest in game.world.nests:nest.cleansed=true
	game.prepare_next_night_plan(false);assert(game.night_plan[0].count==count-6)
	clear_enemies();game.wave_index=0;game.spawn_night_wave()
	verify_wave(game.night_plan[0])
	await game.prepare_shutdown();game.queue_free()
	for i in 4:await process_frame
	print("NIGHTFALL_PLANNED_WAVES_OK");quit()
