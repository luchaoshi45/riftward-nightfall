extends SceneTree
const Layout = preload("res://scripts/outpost_layout.gd")
const Grid = preload("res://scripts/construction_grid.gd")

# This progression fixture isolates lifecycle behavior with explicit real
# death callbacks. Natural time, money and combat are validated separately.
func resolve_precision_night(game: Node3D) -> void:
	game.phase_time=.01
	game.simulate(.03)
	assert(game.phase=="night" and game.night_clearance_active)
	for enemy in game.enemies.duplicate():
		if is_instance_valid(enemy) and enemy.alive:enemy.hurt(100000.0,game.hero)
	game.simulate(.02)

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.hide()
	call_deferred("run")

func verify_close_building_approach(game: Node3D) -> void:
	# A legal tower can sit against the east wall and touch another building.
	# The old nearest-face destination landed in the wall or adjacent tower.
	game.hero.position=Vector3(80,0,80)
	game.move_goal=game.hero.position
	game.scrap=1000
	var wall_point: Vector3=Grid.placement(Vector3(Layout.FORT_INNER-1.5,5,-7.5),"tower").point
	assert(game.build_tower_at(wall_point))
	var wall_index: int=game.world.tower_pads.size()-1
	assert(game.build_tower_at(wall_point-Vector3(3,0,0)))
	var neighbour_index: int=game.world.tower_pads.size()-1
	for index in game.world.tower_pads.size():
		if index not in [wall_index,neighbour_index] and int(game.world.tower_pads[index].level)>0:game.damage_tower(index,100000.0)
	var half: Vector2=game.construction.footprint("tower")
	assert(not game.outpost_walkable(wall_point+Vector3(half.x+.35,0,0)),"Nearest east face is inside the castle wall")
	assert(not game.outpost_walkable(wall_point-Vector3(half.x+.35,0,0)),"Nearest west face is inside the neighbouring tower")
	var hunter: BattleUnit=game.spawn_creature(true,"sapper")
	hunter.position=Vector3(Layout.FORT_OUTER+4.4,0,-8)
	var approach: Vector3=game.building_approach_position(hunter.position,wall_point,"tower")
	assert(game.outpost_walkable(approach) and game.can_attack_line(approach,wall_point),"Blocked nearest face must choose a real accessible surface")
	var starting_hp: float=game.world.tower_pads[wall_index].hp+game.world.tower_pads[neighbour_index].hp
	for step in range(700):
		var previous:=hunter.position
		hunter.tick(.1)
		game.update_creature(hunter,.1)
		assert(game.can_traverse(previous,hunter.position),"Dense building approach must never cross either tower or castle wall")
		if float(game.world.tower_pads[wall_index].hp)+float(game.world.tower_pads[neighbour_index].hp)<starting_hp:break
	assert(float(game.world.tower_pads[wall_index].hp)+float(game.world.tower_pads[neighbour_index].hp)<starting_hp,"Enemy must travel through the south gate and actually damage one dense wall-side tower")
	game.enemies.erase(hunter)
	hunter.queue_free()
	game.damage_tower(wall_index,100000.0)
	assert(game.outpost_walkable(wall_point) and game.can_traverse(wall_point+Vector3(0,0,-2),wall_point+Vector3(0,0,2)),"Destroyed tower footing must reopen a real crossing")
	game.hero.position=wall_point
	game.move_goal=game.hero.position
	var balance: int=game.scrap
	assert(not game.interact() and game.scrap==balance,"F cannot reconstruct a tower on a live unit standing on its footing")
	game.hero.position=wall_point+Vector3(0,0,2.2)
	game.move_goal=game.hero.position
	assert(game.interact() and int(game.world.tower_pads[wall_index].level)==1 and game.scrap==balance-game.districts.tower_cost(game.TOWER_COSTS[0]),"F pays once to reconstruct the existing footing")
	assert(not game.outpost_walkable(wall_point) and not game.can_traverse(wall_point+Vector3(0,0,-2),wall_point+Vector3(0,0,2)),"Reconstructed live tower must restore its actual movement block")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	game.archive.enabled=false
	root.add_child(game)
	current_scene=game
	await create_timer(.5).timeout
	assert(Vector2(game.hero.position.x,game.hero.position.z).length()<5)
	assert(is_equal_approx(game.hero.position.y,5.0))
	assert(game.world.beacon.position.y==5.0)
	var ramp_middle := (Layout.RAMP_TOP+Layout.RAMP_END)*.5
	assert(game.outpost_height(Vector3(0,0,0))>game.outpost_height(Vector3(0,0,ramp_middle)))
	assert(game.outpost_height(Vector3(0,0,ramp_middle))>game.outpost_height(Vector3(Layout.RAMP_OUTER_HALF+1.1,0,ramp_middle))+2.0)
	assert(game.phase=="draft" and game.run.offer.size()==3)
	assert(game.choose_card(0))
	assert(game.phase=="night" and game.tower_count()==2)
	game.set_process(false)
	game.begin_day()
	for old_enemy in game.enemies:
		if is_instance_valid(old_enemy):old_enemy.queue_free()
	game.enemies.clear()
	for i in 7:game.spawn_creature(false)
	game.spawn_nest_guards()
	assert(game.phase=="day")
	assert(game.world.salvage.size()==36)
	assert(game.world.tower_pads.size()==2)
	assert(game.outpost_walkable(Vector3(115,0,95)))
	assert(game.outpost_walkable(Vector3(127,0,0)))
	assert(not game.outpost_walkable(Vector3(Layout.MAP_HALF_X+1.0,0,0)))
	assert(not game.outpost_walkable(Vector3(82,0,-78)))
	assert(not game.outpost_walkable(Vector3(-99,0,72)))
	assert(not game.outpost_walkable(Vector3(-124,0,-76)))
	assert(not game.outpost_walkable(Vector3(121,0,61)))
	assert(not game.can_traverse(Vector3(55,0,-78),Vector3(118,0,-78)))
	assert(not game.can_attack_line(Vector3(55,0,-78),Vector3(118,0,-78)))
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
	var selected_tower: Vector3=Grid.placement(Vector3(-8,5,-8),"tower").point
	game.hero.position=selected_tower+Vector3(0,0,2.2)
	game.move_goal=game.hero.position
	assert(game.build_tower_at(Vector3(-8,5,-8)))
	var pad: Dictionary=game.world.tower_pads.back()
	assert(pad.level==1 and game.tower_count()==3)
	assert(game.interact() and pad.level==2)
	var tower_target: BattleUnit=game.spawn_creature(true,"basic")
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
	verify_close_building_approach(game)
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
	creature.position=Vector3(0,5.0,3.1)
	creature.attack_timer=0
	game.hero.position=Vector3(20,0,20)
	var before: float=game.beacon_hp
	game.update_creature(creature,.1)
	assert(creature.attack_queued and game.beacon_hp==before)
	creature.tick(creature.windup_duration)
	game.update_creature(creature,.1)
	assert(game.beacon_hp<before)
	game.hero.position=Vector3(3.5,5,0)
	game.scrap=20
	assert(game.interact())
	assert(game.beacon_hp>before-creature.damage)
	game.phase_time=.01
	game.simulate(.03)
	assert(game.phase=="night" and game.night_clearance_active,"The ordinary night deadline must retain living threats")
	for enemy in game.enemies.duplicate():
		if is_instance_valid(enemy) and enemy.alive:enemy.hurt(100000.0,game.hero)
	game.simulate(.02)
	assert(game.phase=="draft" and game.day_number==2)
	assert(game.choose_card(0) and game.phase=="day")
	game.start_night()
	resolve_precision_night(game)
	assert(game.day_number==3 and game.phase=="draft")
	assert(game.choose_card(0) and game.phase=="day")
	game.start_night()
	resolve_precision_night(game)
	assert(game.phase=="ended" and game.victory)
	print("NIGHTFALL_LOOP_OK")
	# Unload the real scene before quitting so the audio mix thread can release
	# its last loop playback; immediate SceneTree.quit skips this fixture step.
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit()
