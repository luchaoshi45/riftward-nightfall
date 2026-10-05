extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message);quit(1)
	return condition

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.choose_card(0);game.set_process(false);game.world.set_process(false)
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear();game.phase="night"
	var wildlife: NeutralWildlife=game.wildlife
	wildlife.rng.seed=8164
	if not check(wildlife.animals.size()==4,"Each run should have exactly four peaceful wildlife"):return
	var stag: Dictionary={}
	var beetle: Dictionary={}
	for animal in wildlife.animals:
		if animal.kind=="stag" and stag.is_empty():stag=animal
		if animal.kind=="beetle" and beetle.is_empty():beetle=animal
		if not check(not animal.node is BattleUnit and game.enemies.is_empty(),"Neutral wildlife must not be combat targets"):return
		if not check(game.outpost_walkable(animal.position) and is_equal_approx(animal.position.y,game.outpost_height(animal.position)),"Wildlife should spawn on accessible terrain"):return
		if not check(not wildlife.occupied(animal.position,animal.node),"Wildlife should have space away from other interactions"):return
		if not check(animal.lamp.light_energy>0 and animal.limbs.size()==(4 if animal.kind=="stag" else 6),"Both species need real lights and articulated legs"):return
		var textured:=0
		var emissive:=0
		for surface: MeshInstance3D in animal.model.find_children("*","MeshInstance3D",true,false):
			for index in surface.mesh.get_surface_count():
				var mat: Material=surface.mesh.surface_get_material(index)
				if mat is StandardMaterial3D:
					if mat.albedo_texture and mat.normal_enabled and mat.roughness_texture:textured+=1
					if mat.emission_enabled:emissive+=1
		if not check(textured>0 and emissive>0,"Portable PBR microtextures and glow should both survive the real Godot import"):return
		for limb in animal.limbs:
			if not check(limb.hip!=null and limb.knee!=null,"All limb pivots must survive GLB export"):return
	if not check(not stag.is_empty() and not beetle.is_empty(),"Both kinds should occur in every run"):return
	game.hero.position=stag.position;game.move_goal=game.hero.position
	game.hero.hp=400;game.hero.shield=0;game.hero.shield_time=0
	game.exploration_count=0;game.essence=0
	if not check("荧角鹿" in wildlife.interaction_prompt() and wildlife.interact(),"F should pet a nearby deer at night"):return
	if not check(game.hero.hp==460 and game.hero.shield==90 and game.hero.shield_time==10 and game.essence==6 and game.exploration_count==1,"Petting must grant a meaningful health, shield and memory reward"):return
	if not check(not wildlife.interact() and game.exploration_count==1,"Repeated F may not consume the same encounter twice"):return
	var old_stag_point: Vector3=stag.position
	wildlife.tick(3.1)
	if not check(stag.state=="cooldown" and not stag.node.visible and not stag.lamp.visible,"Consumed deer should leave and hide its light"):return
	game.phase="paused"
	var refresh_before: float=stag.refresh
	var age_before: float=stag.age
	wildlife.tick(80)
	if not check(stag.refresh==refresh_before and stag.age==age_before,"Pausing must freeze movement and respawn timers"):return
	game.phase="night";wildlife.tick(56.8)
	if not check(stag.state=="cooldown","The respawn must take a complete 60 gameplay seconds"):return
	wildlife.tick(.2)
	if not check(stag.state=="idle" and stag.node.visible and stag.lamp.visible and stag.position.distance_to(old_stag_point)>=12,"Wildlife should renew in a different location"):return
	if not check(game.exploration_count==1 and not wildlife.occupied(stag.position,stag.node),"Respawning does not award anything and keeps landmark clearance"):return
	game.hero.position=beetle.position;game.move_goal=game.hero.position
	game.scrap=19;game.mana=100;game.hero.hp=400
	if not check(wildlife.interact() and beetle.state in ["idle","walk"] and game.scrap==19 and game.mana==100 and game.exploration_count==1,"A poor trade should show feedback without charging or consuming the beetle"):return
	game.scrap=50
	if not check(wildlife.interact() and game.scrap==30 and game.mana==180 and game.hero.hp==440 and game.essence==14 and game.exploration_count==2,"A beetle trade should charge exactly 20 supplies and grant recovery and memory"):return
	if not check(not wildlife.interact() and game.scrap==30,"A completed beetle trade may not be repeated"):return
	wildlife.tick(60.01)
	if not check(beetle.state=="idle" and beetle.node.visible,"Traded beetles should also refresh"):return
	for animal in wildlife.animals:animal.timer=1000
	stag.target=stag.position+Vector3(0,0,3)
	if not game.can_traverse(stag.position,stag.target):stag.target=stag.position+Vector3(3,0,0)
	stag.state="walk";stag.node.rotation.y=atan2(-(stag.target.x-stag.position.x),-(stag.target.z-stag.position.z))
	var first_hip: Node3D=stag.limbs[0].hip
	var rest_rotation:=first_hip.rotation
	var old_position: Vector3=stag.position
	for step in 14:wildlife.tick(.06)
	if not check(stag.position.distance_to(old_position)>.3 and first_hip.rotation.distance_to(rest_rotation)>.01,"Actual movement must animate independently jointed legs"):return
	stag.state="idle";stag.timer=10
	wildlife.tick(1)
	if not check(stag.moving_weight==0 and first_hip.rotation.distance_to(stag.limbs[0].hip_rest)<.001,"Idle should blend the legs back to their rest pose"):return
	var idle_head: Vector3=stag.head.rotation
	wildlife.tick(.5)
	if not check(stag.head.rotation.distance_to(idle_head)>.001,"Idle deer should breathe and scan instead of freezing"):return
	for animal in wildlife.animals:animal.timer=0
	for step in 1200:
		var before: Array[Vector3]=[]
		for animal in wildlife.animals:before.append(animal.position)
		wildlife.tick(.1)
		for index in wildlife.animals.size():
			var animal: Dictionary=wildlife.animals[index]
			if not check(game.can_traverse(before[index],animal.position) and is_equal_approx(animal.position.y,game.outpost_height(animal.position)),"Every roaming segment must respect fortress walls and terrain height"):return
	game.hero.position=stag.position;game.mana=300;game.cooldowns[3]=0;game.phase="night"
	game.cast(3)
	if not check(stag.state in ["idle","walk"] and stag.node.visible,"R must leave peaceful wildlife unharmed"):return
	if "--visual" in OS.get_cmdline_user_args():await render_checks(game,wildlife)
	print("NIGHTFALL_NEUTRAL_WILDLIFE_OK two original assets, night interactions, exact trade, no duplicates, 60s renewal, pause, lights, gait, walls, immune to R")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	quit()

func render_checks(game: Node3D, wildlife: NeutralWildlife) -> void:
	if DisplayServer.get_name()=="headless":return
	game.hud.visible=false
	game.effects.visible=false;game.hero.visible=false
	game.world.set_night(true);game.world._process(10)
	for animal in wildlife.animals:
		animal.state="idle";animal.timer=1000;animal.node.visible=true;animal.lamp.visible=true
		game.hero.position=animal.position+Vector3(2,0,2)
		game.hero.position.y=game.outpost_height(game.hero.position)
		game.world.follow_ashfall(game.hero.position)
		game.camera.size=5.2 if animal.kind=="stag" else 3.8
		game.camera.position=animal.position+Vector3(3.4,5.2,4.5)
		game.camera.look_at(animal.position+Vector3.UP*(1.45 if animal.kind=="stag" else .6))
		for frame in 5:
			wildlife.animate(animal,1.0/60.0,false)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/neutral-"+animal.kind+"-close.png")
		# One close image for each species.
		if animal.kind=="beetle":break
