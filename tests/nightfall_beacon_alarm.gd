extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	assert(game.choose_card(0))
	game.start_night()
	game.hero.position=Vector3(20,0,20)
	game.move_goal=game.hero.position
	var creature: BattleUnit=game.spawn_creature(true)
	creature.position=Vector3(0,5,1.3)
	creature.attack_timer=0
	var before: float=game.beacon_hp
	game.update_creature(creature,.1)
	assert(creature.attack_queued and game.beacon_alarm_time==0)
	creature.tick(creature.windup_duration)
	game.update_creature(creature,.1)
	assert(game.beacon_hp<before)
	assert(game.beacon_alarm_time>0 and game.beacon_alarm_damage>0)
	var first_damage: float=game.beacon_alarm_damage
	game.set_process(false)
	game.world.set_process(false)
	game.camera.position=game.hero.position+Vector3(0,25,29)
	game.hud.queue_redraw()
	if DisplayServer.get_name()!="headless":
		await create_timer(.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/beacon-alarm.png")
	game.record_beacon_hit(12.0)
	assert(game.beacon_alarm_damage==first_damage+12.0)
	game.update_beacon_alarm(3.1)
	assert(game.beacon_alarm_time==0 and game.beacon_alarm_damage==0)
	print("NIGHTFALL_BEACON_ALARM_OK")
	quit()
