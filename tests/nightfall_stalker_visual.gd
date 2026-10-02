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
	var stalker: BattleUnit=game.spawn_creature(true)
	stalker.position=Vector3(25,0,35)
	stalker.face(stalker.position+Vector3(0,0,-3),1.0)
	assert(absf(wrapf(stalker.visual.rotation.y-PI,-PI,PI))<.01,"Imported model must face its pursuit target")
	stalker.moving=false
	stalker.tick(.02)
	assert(stalker.legs.size()==4 and stalker.stalker_head!=null)
	for limb in stalker.legs:assert(limb.get_child_count()>0,"Animated leg pivot must own visible meshes")
	assert(stalker.stalker_head.get_child_count()>0,"Animated head pivot must own visible meshes")
	stalker.moving=true
	stalker.tick(.14)
	assert(absf(stalker.legs[0].rotation.x)>.02,"Visible limb pivot must move with the gait")
	stalker.moving=false
	stalker.tick(.02)
	game.hero.visible=false
	game.hud.visible=false
	game.camera.size=5.2
	game.camera.position=stalker.position+Vector3(0,3,-6)
	game.camera.look_at(stalker.position+Vector3(0,1,0))
	game.camera.current=true
	await create_timer(.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/stalker-v2-close.png")
	print("NIGHTFALL_STALKER_VISUAL_OK")
	quit()
