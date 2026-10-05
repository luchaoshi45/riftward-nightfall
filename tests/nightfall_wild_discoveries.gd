extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message);quit(1)
	return condition

func find_item(events: WildDiscoveries, kind: String) -> Dictionary:
	for item: Dictionary in events.items:
		if item.kind==kind and item.state=="ready":return item
	return {}

func capture(game: Node3D, point: Vector3, filename: String) -> void:
	if DisplayServer.get_name()=="headless":return
	game.hero.position=point+Vector3(0,0,3.2)
	game.hero.position.y=game.outpost_height(game.hero.position)
	game.move_goal=game.hero.position
	game.world.follow_ashfall(game.hero.position)
	game.camera.size=13.0
	game.camera.position=point+Vector3(6,10,11)
	game.camera.look_at(point+Vector3.UP*.9)
	game.hud.visible=false
	game.discoveries.tick(0.0)
	await create_timer(.15).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/"+filename+".png")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.choose_card(0);game.set_process(false)
	game.world.set_process(false)
	game.world.set_night(true);game.world._process(6.0)
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()
	var events: WildDiscoveries=game.discoveries
	events.rng.seed=470135
	if not check(game.phase=="night","The first card must begin the first night"):return
	if not check(events.items.size()==18,"Eighteen refreshing discoveries must be present"):return
	for index in events.items.size():
		var item: Dictionary=events.items[index]
		if not check(events.position_available(item.position,index),"Discovery clearance must reserve old interactions and walls"):return
		if not check(is_equal_approx((item.position as Vector3).y,game.outpost_height(item.position)),"A discovery must stand on the real terrain"):return
		var radius:=Vector2(item.position.x,item.position.z).length()
		if not check(radius<=65.01 and radius>=9.99,"Discoveries must be within the playable expedition perimeter"):return
		if index<4 and not check(radius<=24.01,"Four discoveries must remain close enough for the first night"):return
		game.plan_hero_path(item.position)
		if not check(not game.hero_path.is_empty(),"A discovery must be reachable from the fort via the gate"):return
	var bloom:=find_item(events,"ember_bloom")
	var crystal:=find_item(events,"memory_crystal")
	var cache:=find_item(events,"supply_cache")
	var light:=find_item(events,"waylight")
	game.hero.position=bloom.position;game.move_goal=game.hero.position
	game.hero.hp=game.hero.max_hp-150.0
	var before_scrap: int=game.scrap
	var before_hp: float=game.hero.hp
	if not check(game.interaction_prompt().contains("余烬花") and game.interact(),"A flower must be usable through the game's F interaction in the first night"):return
	if not check(bloom.state=="cooling" and game.scrap>=before_scrap+12 and is_equal_approx(game.hero.hp,before_hp+70.0),"A flower must award its base supplies and recovery, plus any active route bonus"):return
	if not check(bloom.respawn>=45.0 and bloom.respawn<=65.0,"Harvested discoveries must set a real refresh timer"):return
	before_scrap=game.scrap
	if not check(not events.interact() and game.scrap==before_scrap,"A harvested flower must not award twice"):return
	game.hero.position=crystal.position;game.move_goal=game.hero.position
	game.mana=game.max_mana-120.0
	before_scrap=game.scrap
	var before_mana: float=game.mana
	if not check(game.interact(),"An ember crystal must be usable in the first night"):return
	if not check(crystal.state=="cooling" and game.scrap>=before_scrap+12 and is_equal_approx(game.mana,before_mana+45.0),"A crystal must award its base scrap and mana once, plus any active route bonus"):return
	before_scrap=game.scrap
	events.tick(0.0);events.interact()
	if not check(game.scrap==before_scrap,"Consumed crystal interaction must not duplicate scrap"):return
	game.hero.position=cache.position;game.move_goal=game.hero.position
	before_scrap=game.scrap
	if not check(game.interact() and cache.state=="channel","A supply cache must begin a three-second opening"):return
	events.tick(1.1);events.interact()
	if not check(is_equal_approx(cache.progress,1.1) and game.scrap==before_scrap,"Repeated F must not restart a cache or award before completion"):return
	for frozen_phase: String in ["paused","draft","ended"]:
		game.phase=frozen_phase
		var old_respawn: float=bloom.respawn
		events.tick(100.0)
		if not check(is_equal_approx(cache.progress,1.1) and is_equal_approx(bloom.respawn,old_respawn),"Pause, card draft and ending must freeze cache and refresh timers"):return
	game.phase="night"
	game.hero.position=cache.position+Vector3(4.2,0,0)
	events.tick(.1)
	if not check(cache.state=="ready" and cache.progress==0.0 and game.scrap==before_scrap,"Leaving the cache radius must cancel without rewards"):return
	game.hero.position=cache.position;game.move_goal=game.hero.position
	events.interact();events.tick(2.9)
	if not check(cache.state=="channel" and game.scrap==before_scrap,"Opening progress must remain incomplete before three seconds"):return
	before_scrap=game.scrap
	events.tick(.1)
	if not check(cache.state=="cooling" and game.scrap>=before_scrap+46,"A completed cache must award its base supplies exactly once, plus any active route bonus"):return
	before_scrap=game.scrap
	events.tick(0.0);events.interact()
	if not check(game.scrap==before_scrap,"Completed caches must never award duplicate supplies"):return
	game.hero.position=light.position;game.move_goal=game.hero.position
	game.hero.shield=0.0;game.hero.shield_time=0.0
	if not check(game.interact() and light.state=="active" and light.remaining==30.0,"F must ignite a waylight for thirty seconds"):return
	if not check(game.hero.shield==50.0 and game.hero.shield_time==2.0 and light.lamp.light_energy>2.0,"The active light must illuminate a real protective circle"):return
	var old_count: int=game.exploration_count
	events.interact()
	if not check(game.exploration_count==old_count,"An active waylight must not repeat exploration rewards"):return
	game.hero.position=light.position+Vector3(6.5,0,0)
	game.hero.tick(2.1);events.tick(.1)
	if not check(game.hero.shield==50.0,"The protective light must replenish its small shield inside seven metres"):return
	game.hero.shield=200.0;game.hero.shield_time=4.0
	events.tick(.1)
	if not check(game.hero.shield==200.0 and game.hero.shield_time==4.0,"A waylight must preserve a stronger existing W shield"):return
	game.hero.shield=150.0;game.hero.shield_time=4.0
	for step in 50:
		game.hero.tick(.1);events.tick(.1)
	if not check(game.hero.shield==50.0 and game.hero.shield_time==2.0,"A W shield must expire on its own after four seconds inside the field, leaving only the lamp's fifty-point shield"):return
	game.hero.position=light.position+Vector3(7.2,0,0)
	game.hero.tick(4.1);events.tick(.1)
	if not check(game.hero.shield==0.0,"Leaving the light radius must stop protection"):return
	game.phase="paused"
	var old_remaining: float=light.remaining
	events.tick(70.0)
	if not check(is_equal_approx(light.remaining,old_remaining),"Paused waylights must not burn down"):return
	game.phase="night"
	game.hero.position=light.position;game.move_goal=game.hero.position
	await capture(game,light.position,"wild-waylight-active")
	events.tick(light.remaining)
	if not check(light.state=="cooling" and light.respawn==50.0 and light.lamp.light_energy==0.0,"Waylights must burn out and wait fifty seconds"):return
	var old_position: Vector3=light.position
	var old_kind: String=light.kind
	events.tick(50.0)
	if not check(light.state=="ready" and light.serial==1 and light.kind!=old_kind and events.flat_distance(light.position,old_position)>=7.0,"A refresh must rotate both location and discovery type"):return
	for item: Dictionary in events.items:
		game.hero.position=item.position
		events.update_lights()
		var lights:=0
		for candidate: Dictionary in events.items:
			if candidate.lamp.light_energy>0:
				lights+=1
				if not check(game.hero.position.distance_to(candidate.position)<=40.01 and candidate.state!="cooling","Only nearby live discoveries may light the scene"):return
		if not check(lights<=6,"The discovery light budget must never exceed six"):return
	for kind: String in WildDiscoveries.KINDS:
		var item:=find_item(events,kind)
		if not item.is_empty():await capture(game,item.position,"wild-"+kind)
	print("NIGHTFALL_WILD_DISCOVERIES_OK 18 reachable sites, recovery/scrap/cache rewards, cancelled opening, frozen timers, rotating refresh, shield field, 6-light budget")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit()
