extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	assert(game.choose_card(0))
	game.start_night()
	for old_enemy in game.enemies:
		if is_instance_valid(old_enemy):old_enemy.queue_free()
	game.enemies.clear()
	var creature: BattleUnit=game.spawn_creature(true)
	assert(creature.legs.size()==4 and creature.stalker_head!=null,"Refined stalker must preserve the animated limb and head pivots")
	game.hero.position=Vector3(0,5,3)
	game.move_goal=game.hero.position
	creature.position=Vector3(1.4,5,3)
	creature.attack_timer=0
	var hp_before: float=game.hero.hp
	game.update_creature(creature,.1)
	assert(creature.attack_queued and creature.attack_windup>0)
	assert(game.hero.hp==hp_before)
	creature.tick(.15)
	assert(creature.selection.visible and creature.selection.scale.x>1)
	assert(creature.visual.position.y<0)
	assert(creature.visual.position.z>0,"Windup should visibly pull the stalker back")
	game.set_process(false)
	game.camera.size=21
	game.camera.position=game.hero.position+Vector3(0,25,29)
	game.hud.queue_redraw()
	await create_timer(.2).timeout
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/enemy-windup.png")
	game.set_process(true)
	creature.tick(.4)
	game.update_creature(creature,.1)
	assert(game.hero.hp<hp_before and not creature.attack_queued)
	creature.tick(.025)
	assert(creature.visual.position.z<-.3,"Impact should visibly lunge the stalker forward")
	game.set_process(false)
	game.hud.queue_redraw()
	await create_timer(.05).timeout
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/enemy-pounce.png")
	creature.tick(.3)
	assert(absf(creature.visual.position.z)<.01,"Pounce should return to the normal pose")
	creature.attack_timer=0
	game.update_creature(creature,.1)
	assert(creature.attack_queued)
	creature.position=Vector3(8,5,3)
	game.update_creature(creature,.1)
	assert(not creature.attack_queued and creature.attack_windup==0)
	print("NIGHTFALL_ENEMY_WINDUP_OK")
	quit()
