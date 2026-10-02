extends SceneTree
## Hidden rendering QA of motion in the playable scene. No video recording.
var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func screenshot(path: String) -> void:
	game.world.follow_ashfall(game.hero.position)
	game.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func frame() -> void:
	game.simulate(1.0/60.0)
	await process_frame

func clear_enemies() -> void:
	for creature in game.enemies:
		if is_instance_valid(creature):creature.queue_free()
	game.enemies.clear()

func run() -> void:
	if DisplayServer.get_name()=="headless":
		print("Motion rendering requires the caller's hidden graphical process")
		quit(1);return
	game=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.choose_card(0);game.set_process(false)
	clear_enemies()
	game.hero.position=Vector3(-4,5,2)
	game.move_goal=Vector3(4,5,2)
	game.hud.visible=false;game.camera.size=5.2
	for i in 70:
		await frame()
		game.camera.position=game.hero.position+Vector3(3.6,5.5,6)
		game.camera.look_at(game.hero.position+Vector3.UP*1.35)
		if i in [20,32,44,56]:await screenshot("res://build/hero-motion-game-run-%d.png" % i)
	game.move_goal=game.hero.position
	for i in 45:await frame()
	var target: BattleUnit=game.spawn_creature(false)
	target.position=game.hero.position+Vector3(3,0,0)
	target.position.y=game.outpost_height(target.position)
	target.hp=10000;target.max_hp=10000;target.damage=0
	game.hero.attack_timer=0;game.auto_attack()
	for i in 43:
		game.hero.tick(1.0/60.0)
		await process_frame
		if i in [3,14,29]:await screenshot("res://build/hero-motion-game-attack-%d.png" % i)
	clear_enemies()
	game.start_night();clear_enemies()
	game.world.set_process(false);game.world._process(6)
	game.hero.position=Vector3(0,5,3.1);game.move_goal=game.hero.position
	game.hero.moving=false;game.hero.set_locomotion_velocity(Vector3.ZERO)
	game.hero.face(game.hero.position+Vector3(0,0,3),1)
	game.hero.attack_timer=2;game.mana=game.max_mana;game.cooldowns[3]=0
	game.camera.size=26;game.hud.visible=true
	game.camera.position=game.hero.position+Vector3(0,25,29)
	game.camera.look_at(game.hero.position)
	var input:=InputEventKey.new()
	input.keycode=KEY_R;input.physical_keycode=KEY_R;input.pressed=true
	Input.parse_input_event(input)
	await process_frame
	input.pressed=false;Input.parse_input_event(input)
	for i in 70:
		await frame()
		if i==8:await screenshot("res://build/hero-motion-r-night.png")
	print("NIGHTFALL_MOTION_INGAME_VISUAL_OK running, attack recovery, first-night R input and animation")
	quit()
