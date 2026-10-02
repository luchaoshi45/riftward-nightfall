extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	assert(game.choose_card(0))
	game.set_process(false)
	var hero: BattleUnit=game.hero
	assert(hero.visual.scene_file_path.ends_with("hero_ashwarden_blue.glb"),"The playable guardian must use the new model")
	assert(hero.arms.size()==2 and hero.legs.size()==2)
	assert(hero.knees.size()==2 and hero.feet.size()==2,"Knee and foot joints must survive glTF export")
	assert(hero.cloak!=null and hero.cloak.get_child_count()>0,"Animated mantle must own its visible cloth")
	for joint in hero.knees:
		assert(joint.get_child_count()>0,"The shin must move with the knee")
	for joint in hero.feet:
		assert(joint.get_child_count()>0,"The boot must move with the foot")
	hero.position=Vector3(0,0,18)
	hero.face(hero.position+Vector3(0,0,-3),1.0)
	hero.moving=true
	var most_knee_bend: float=0.0
	var most_foot_bend: float=0.0
	for i in 24:
		hero.tick(.045)
		most_knee_bend=maxf(most_knee_bend,absf(hero.knees[0].rotation.x))
		most_foot_bend=maxf(most_foot_bend,absf(hero.feet[0].rotation.x))
	assert(most_knee_bend>.18 and most_foot_bend>.07,"Walking must articulate knees and boots")
	hero.moving=false
	for i in 15: hero.tick(.045)
	assert(hero.gait_blend<.01 and absf(hero.legs[0].rotation.x)<.01,"The gait must settle when movement stops")
	hero.moving=true
	for i in 7: hero.tick(.045)
	if DisplayServer.get_name()=="headless":
		print("NIGHTFALL_HERO_VISUAL_OK headless articulation")
		quit()
		return
	game.hud.visible=false
	game.camera.size=5.4
	game.camera.position=hero.position+Vector3(3.2,4.0,7.3)
	game.camera.look_at(hero.position+Vector3(0,1.35,0))
	game.camera.current=true
	await create_timer(.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/hero-ashwarden-close.png")
	print("NIGHTFALL_HERO_VISUAL_OK")
	quit()
