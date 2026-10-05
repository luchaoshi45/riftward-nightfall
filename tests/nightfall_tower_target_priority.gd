extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	assert(game.choose_card(0))
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()
	var pad: Dictionary=game.world.tower_pads[0]
	game.hero.position=pad.position+Vector3(.5,0,.5)
	game.move_goal=game.hero.position
	game.scrap=60
	assert(game.interact() and pad.level==1)
	for other: Dictionary in game.world.tower_pads:
		if other!=pad:other.cooldown=10000.0
	var nearest: BattleUnit=game.spawn_creature(false)
	var eater: BattleUnit=game.spawn_creature(false)
	var sapper: BattleUnit=game.spawn_creature(false)
	nearest.position=pad.position+Vector3(2.0,0,0)
	eater.position=pad.position+Vector3(8.0,0,0)
	sapper.position=pad.position+Vector3(9.0,0,0)
	eater.set_meta("threat","light_eater")
	sapper.set_meta("threat","sapper")
	var nearest_hp: float=nearest.hp
	var eater_hp: float=eater.hp
	var sapper_hp: float=sapper.hp
	pad.mode="threat"
	game.update_towers(1.2)
	assert(eater.hp<eater_hp and nearest.hp==nearest_hp and sapper.hp==sapper_hp,
		"Threat mode must prioritize the light eater over a nearby normal enemy")
	eater.alive=false
	eater.hp=0.0
	pad.cooldown=0.0
	game.update_towers(1.2)
	assert(sapper.hp<sapper_hp and nearest.hp==nearest_hp,
		"Threat mode must fall back to the sapper after the light eater dies")
	pad.mode="breaker"
	var breaker: BattleUnit=game.spawn_creature(false)
	breaker.position=pad.position+Vector3(10,0,0)
	breaker.set_meta("threat","breaker")
	var breaker_hp: float=breaker.hp
	pad.cooldown=0.0
	game.update_towers(1.2)
	assert(breaker.hp<breaker_hp,
		"Breaker mode must preserve breaker priority")
	pad.mode="nearest"
	assert(game.toggle_tower_mode() and pad.mode=="breaker")
	assert(game.toggle_tower_mode() and pad.mode=="threat")
	assert(game.toggle_tower_mode() and pad.mode=="nearest")
	game.hero.position=pad.position+Vector3(.2,0,.2)
	game.move_goal=game.hero.position
	pad.mode="threat"
	var prompt: String=game.interaction_prompt()
	assert(prompt.contains("威胁优先"),"Tower interaction prompt must show threat mode")
	assert(game.tower_mode_label("threat")=="威胁优先","Tower mode label must be localized")
	game.aim=nearest.position
	game.focus_target=null
	game.focus_time=0.0
	game.focus_cooldown=0.0
	assert(game.issue_focus_order(),"Focus order must still be available in threat mode")
	pad.cooldown=0.0
	var focused_hp: float=nearest.hp
	game.update_towers(1.2)
	assert(nearest.hp<focused_hp,"Focus order must override automatic threat priority")
	print("NIGHTFALL_TOWER_TARGET_PRIORITY_OK")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit()
