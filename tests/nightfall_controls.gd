extends SceneTree

var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func frames(count: int=5) -> void:
	for i in count:await process_frame

func key(code: int) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=true
	Input.parse_input_event(event)
	await frames()
	event.pressed=false
	Input.parse_input_event(event)
	await frames()

func run() -> void:
	game=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await frames(12)
	assert(game.phase=="draft")
	await key(KEY_1)
	assert(game.phase=="night" and game.run.selections==1)
	var starting_z: float=game.hero.position.z
	var move:=InputEventKey.new()
	move.keycode=KEY_Z;move.physical_keycode=KEY_Z;move.pressed=true
	Input.parse_input_event(move)
	await frames(20)
	move.pressed=false;Input.parse_input_event(move)
	assert(game.hero.position.z<starting_z)
	await frames(3)
	game.move_goal=game.hero.position
	var shield_position: Vector3=game.hero.position
	var mana_before: float=game.mana
	await key(KEY_W)
	assert(game.hero.shield>0 and game.cooldowns[1]>0 and game.mana<mana_before,"W should cast the shield")
	assert(game.hero.position.distance_to(shield_position)<.02,"W must not also move the hero")
	var cache: Dictionary=game.world.salvage[0]
	game.hero.position=cache.position+Vector3(1,0,0)
	game.move_goal=game.hero.position
	await key(KEY_F)
	assert(cache.collected and game.scrap>=35)
	# The new world crates may have reached the fixed timer during this long
	# input fixture. Keep this legacy tower interaction isolated from a pending
	# one-shot permit; crate behavior is covered by nightfall_supply_crates.gd.
	game.clear_supply_crates(true)
	game.construction.cancel()
	var pad: Dictionary=game.world.tower_pads[0]
	game.hero.position=pad.position+Vector3(.5,0,.5)
	game.move_goal=game.hero.position
	game.scrap=60
	await key(KEY_F)
	assert(pad.level>=2 and pad.mode=="nearest")
	await key(KEY_G)
	assert(pad.mode=="breaker")
	await key(KEY_G)
	assert(pad.mode=="threat")
	await key(KEY_G)
	assert(pad.mode=="nearest")
	game.hero.position=Vector3(0,5,3)
	game.move_goal=game.hero.position
	var enemy: BattleUnit=game.spawn_creature(false)
	enemy.position=Vector3(4,0,3)
	game.aim=enemy.position
	var hp_before: float=enemy.hp
	await key(KEY_Q)
	assert(not is_instance_valid(enemy) or enemy.hp<hp_before)
	await key(KEY_ESCAPE)
	assert(game.phase=="paused")
	await key(KEY_ESCAPE)
	assert(game.phase=="night")
	print("NIGHTFALL_CONTROLS_OK")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.35).timeout
	quit()
