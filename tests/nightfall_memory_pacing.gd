extends SceneTree
var game: Node3D
func _initialize() -> void:call_deferred("run")
func run() -> void:
	game=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	for i in 8:await process_frame
	game.set_process(false);game.choose_card(0)
	for enemy in game.enemies:enemy.queue_free()
	game.enemies.clear();await process_frame
	assert(game.run.memory_level==0 and game.run.memory_cost()==200)
	var attack_target: BattleUnit=game.spawn_creature(false)
	attack_target.position=game.hero.position+Vector3.RIGHT
	attack_target.hp=3000;attack_target.max_hp=3000
	game.auto_attack()
	game.essence=190
	var victim: BattleUnit=game.spawn_creature(false)
	victim.hp=1;victim.hurt(50,null)
	assert(game.phase=="night" and game.run.pending==1 and game.essence==2)
	assert(game.run.memory_cost()==450 and game.hero_attack_target==attack_target,"Memory must not cancel ongoing combat")
	game.update_hero_attack(1)
	assert(attack_target.hp<3000)
	if DisplayServer.get_name()!="headless":
		game.notice_time=0;game.hud.queue_redraw();await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/memory-ready.png")
	var event:=InputEventKey.new();event.keycode=KEY_V;event.pressed=true
	Input.parse_input_event(event);await process_frame
	assert(game.phase=="draft")
	var remaining: float=game.phase_time
	var chain: float=game.attack_chain_time
	game.simulate(5)
	assert(game.phase_time==remaining and game.attack_chain_time==chain)
	game.choose_card(0)
	assert(game.phase=="night" and game.phase_time==remaining and game.run.memory_level==1)
	game.run.memory_level=0;game.essence=4200
	game.collect_memory_upgrades()
	assert(game.run.memory_level==5 and game.run.pending==5 and game.essence==200 and game.phase=="night")
	game.phase="paused";assert(not game.request_upgrade())
	game.phase="night";assert(game.request_upgrade())
	for i in 5:assert(game.choose_card(0))
	assert(game.run.memory_level==5 and game.phase=="night")
	game.finish_night()
	assert(game.run.memory_level==5 and game.run.pending==1)
	game.choose_card(0);assert(game.phase=="day" and game.phase_time==90)
	if DisplayServer.get_name()!="headless":
		game.notice_time=0;game.hud.queue_redraw();await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/memory-dawn.png")
	await game.prepare_shutdown();game.queue_free()
	for i in 4:await process_frame
	print("NIGHTFALL_MEMORY_PACING_OK");quit()
