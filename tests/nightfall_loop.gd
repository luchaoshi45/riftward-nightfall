extends SceneTree
const Layout = preload("res://scripts/outpost_layout.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await create_timer(.5).timeout
	assert(Vector2(game.hero.position.x,game.hero.position.z).length()<5)
	assert(is_equal_approx(game.hero.position.y,5.0))
	assert(game.world.beacon.position.y==5.0)
	var ramp_middle := (Layout.RAMP_TOP+Layout.RAMP_END)*.5
	assert(game.outpost_height(Vector3(0,0,0))>game.outpost_height(Vector3(0,0,ramp_middle)))
	assert(game.outpost_height(Vector3(0,0,ramp_middle))>game.outpost_height(Vector3(5,0,ramp_middle))+2.0)
	assert(game.phase=="draft" and game.run.offer.size()==3)
	assert(game.choose_card(0))
	assert(game.phase=="night" and game.tower_count()==2)
	game.begin_day()
	for old_enemy in game.enemies:
		if is_instance_valid(old_enemy):old_enemy.queue_free()
	game.enemies.clear()
	for i in 7:game.spawn_creature(false)
	game.spawn_nest_guards()
	assert(game.phase=="day")
	assert(game.world.salvage.size()==36)
	assert(game.world.tower_pads.size()==12)
	assert(game.outpost_walkable(Vector3(115,0,95)))
	assert(not game.outpost_walkable(Vector3(127,0,0)))
	assert(not game.outpost_walkable(Vector3(0,0,-Layout.WALL_CENTER)))
	assert(not game.outpost_walkable(Vector3(Layout.WALL_CENTER,0,0)))
	assert(game.outpost_walkable(Vector3(0,0,Layout.WALL_CENTER)))
	assert(not game.can_traverse(Vector3(Layout.FORT_OUTER+1,0,0),Vector3(4,0,0)))
	assert(game.can_traverse(Vector3(0,0,ramp_middle),Vector3(0,0,4)))
	var idle: BattleUnit=game.enemies[0]
	var idle_position:=idle.position
	game.update_creature(idle,.2)
	assert(idle.position==idle_position,"Daytime creature should guard ruins, not rush the outpost")
	await create_timer(.35).timeout
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/outpost-day.png")
	var first: Dictionary=game.world.salvage[0]
	game.hero.position=first.position+Vector3(1.0,0,0)
	assert(game.interact())
	assert(game.scrap>=35 and first.collected)
	game.scrap=120
	var pad: Dictionary=game.world.tower_pads[0]
	game.hero.position=pad.position+Vector3(1,0,0)
	game.move_goal=game.hero.position
	assert(game.interact() and pad.level==1 and game.tower_count()==3)
	assert(game.interact() and pad.level==2)
	var tower_target: BattleUnit=game.spawn_creature(true)
	assert(tower_target.legs.size()==4 and tower_target.stalker_head!=null)
	tower_target.position=pad.position+Vector3(5,0,0)
	var target_hp: float=tower_target.hp
	game.update_towers(1.2)
	assert(tower_target.hp<target_hp,"Constructed tower must damage approaching enemies")
	game.scrap=75
	assert(game.interact() and pad.level==3)
	for old_enemy in game.enemies:
		if is_instance_valid(old_enemy):old_enemy.queue_free()
	game.enemies.clear()
	var first_target: BattleUnit=game.spawn_creature(true)
	var second_target: BattleUnit=game.spawn_creature(true)
	first_target.position=pad.position+Vector3(6,0,0)
	second_target.position=pad.position+Vector3(7,0,0)
	var second_hp: float=second_target.hp
	game.update_towers(1.2)
	assert(second_target.hp<second_hp,"Level-three tower blast must hit clustered enemies")
	game.hero.position=Vector3(85,0,40)
	game.move_goal=game.hero.position
	var camera_rotation: Vector3=game.camera.rotation
	await create_timer(.2).timeout
	assert(game.camera.rotation.is_equal_approx(camera_rotation),"Camera orientation should remain fixed while tracking")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/outpost-perimeter.png")
	var relay: Dictionary=game.world.relays[0]
	game.hero.position=relay.position+Vector3(1,0,0)
	game.move_goal=game.hero.position
	var scrap_before: int=game.scrap
	assert(game.interact() and relay.activated and game.scrap==scrap_before+85)
	assert(game.relay_count()==1)
	game.phase_time=.01
	game.simulate(.03)
	assert(game.phase=="night")
	# Isolate the gate-ingress assertion from the constructed-defense targeting
	# behavior exercised above: with no living towers, a wave must reach the
	# south entrance before selecting the beacon.
	for i in game.world.tower_pads.size():
		if game.world.tower_pads[i].level>0:game.damage_tower(i,100000.0)
	var route_test: BattleUnit=game.spawn_creature(true,"basic")
	route_test.position=Vector3(8,0,Layout.RAMP_END+3.0)
	game.hero.position=Vector3(80,5.0,80)
	for step in range(120):game.update_creature(route_test,.1)
	assert(route_test.position.z<Layout.WALL_CENTER and absf(route_test.position.x)<Layout.GATE_HALF,"Night wave must enter through south gate")
	game.hero.position=Vector3(0,5.0,3.5)
	game.move_goal=game.hero.position
	await create_timer(.5).timeout
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/outpost-night.png")
	var creature: BattleUnit=game.spawn_creature(true)
	creature.position=Vector3(0,5.0,1.3)
	creature.attack_timer=0
	game.hero.position=Vector3(20,0,20)
	var before: float=game.beacon_hp
	game.update_creature(creature,.1)
	assert(creature.attack_queued and game.beacon_hp==before)
	creature.tick(creature.windup_duration)
	game.update_creature(creature,.1)
	assert(game.beacon_hp<before)
	game.hero.position=Vector3(1,5,0)
	game.scrap=20
	assert(game.interact())
	assert(game.beacon_hp>before-creature.damage)
	game.phase_time=.01
	game.simulate(.03)
	assert(game.phase=="draft" and game.day_number==2)
	assert(game.choose_card(0) and game.phase=="day")
	game.start_night()
	game.finish_night()
	assert(game.day_number==3 and game.phase=="draft")
	assert(game.choose_card(0) and game.phase=="day")
	game.start_night()
	game.finish_night()
	assert(game.phase=="ended" and game.victory)
	print("NIGHTFALL_LOOP_OK")
	# Unload the real scene before quitting so the audio mix thread can release
	# its last loop playback; immediate SceneTree.quit skips this fixture step.
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit()
