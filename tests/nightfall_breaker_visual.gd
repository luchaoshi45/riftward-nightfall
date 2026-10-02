extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	assert(game.choose_card(0))
	game.set_process(false)
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()
	var breaker: BattleUnit=null
	for i in range(80):
		var enemy: BattleUnit=game.spawn_creature(true)
		if enemy.get_meta("threat","")=="breaker":
			breaker=enemy
			break
		for other in game.enemies:
			if is_instance_valid(other):other.queue_free()
		game.enemies.clear()
	assert(breaker!=null,"A siege monster must spawn")
	assert(breaker.visual.scene_file_path.ends_with("night_breaker_v2.glb"),"Siege monster must use its distinct model")
	assert(breaker.legs.size()==4 and breaker.stalker_head!=null)
	for limb in breaker.legs:assert(limb.get_child_count()>0,"Armored limbs must remain animated")
	assert(breaker.stalker_head.get_child_count()>0,"Battering crown must follow head motion")
	breaker.position=Vector3(25,0,35)
	breaker.face(breaker.position+Vector3(0,0,-3),1.0)
	breaker.moving=true
	breaker.tick(.14)
	assert(absf(breaker.legs[0].rotation.x)>.02,"Visible armored limbs must swing")
	breaker.moving=false
	breaker.tick(.02)
	game.hero.visible=false
	game.hud.visible=false
	game.camera.size=6.2
	game.camera.position=breaker.position+Vector3(0,3,-8)
	game.camera.look_at(breaker.position+Vector3(0,1.2,0))
	game.camera.current=true
	await create_timer(.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/breaker-v2-close.png")
	print("NIGHTFALL_BREAKER_VISUAL_OK")
	quit()
