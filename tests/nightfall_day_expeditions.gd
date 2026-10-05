extends SceneTree
const Layout = preload("res://scripts/outpost_layout.gd")

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
	game.choose_card(0);game.set_process(false)
	game.begin_day()
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()
	var events: DayExpeditions=game.expeditions
	if not check(events.generators.size()==3 and events.camps.size()==2,"Daytime objectives must be present"):return
	var site: Dictionary=events.generators[0]
	game.hero.position=site.position;game.move_goal=game.hero.position
	if not check(game.interact() and site.state=="active","F must activate the nearby generator"):return
	if not check(site.guards.size()==3,"A generator should wake three ambushers"):return
	var hunter: BattleUnit=site.guards[0]
	var previous_distance: float=hunter.position.distance_to(game.hero.position)
	game.update_creature(hunter,.1)
	if not check(hunter.position.distance_to(game.hero.position)<previous_distance,"Event ambushers must pursue beyond the normal four-metre aggro range"):return
	events.tick(4)
	game.hero.position=site.position+Vector3(9,0,0)
	events.tick(5)
	if not check(is_equal_approx(site.progress,4.0),"Generator progress must pause outside its circle"):return
	game.hero.position=site.position
	events.tick(10)
	if not check(site.state=="active" and game.generator_cells==0,"Surviving ambushers must block completion"):return
	var before_scrap: int=game.scrap
	for guard in site.guards:guard.hurt(10000,game.hero)
	events.tick(.1)
	if not check(site.state=="complete" and game.generator_cells==1 and game.scrap>=before_scrap+100,"A secured generator must award one cell and supplies"):return
	if not check(game.beacon_pulse_interval()<3.1,"An energy cell must improve night defence"):return
	before_scrap=game.scrap
	events.tick(20)
	if not check(game.scrap==before_scrap and game.generator_cells==1,"Completed generators must not award duplicate rewards"):return
	var camp: Dictionary=events.camps[0]
	game.hero.position=camp.position;game.move_goal=game.hero.position
	if not check(game.interact() and camp.state=="escort","F must recruit a waiting scout"):return
	for guard in camp.guards:guard.hurt(10000,game.hero)
	game.beacon_hp=900;game.hero.hp=600
	before_scrap=game.scrap
	var home:=Vector3(0,5,3.1)
	game.plan_hero_path(home)
	var npc: BattleUnit=camp.npc
	for step in 1400:
		var old_npc:=npc.position
		game.move_hero(.04)
		events.tick(.04)
		if camp.state=="delivered":break
		if not check(game.can_traverse(old_npc,npc.position),"The escorted scout must follow through the gate without crossing walls"):return
	if not check(camp.state=="delivered" and game.survivors_rescued==1,"The scout must reach the elevated fortress: hero=%s npc=%s trail=%s" % [game.hero.position,npc.position,camp.trail]):return
	if not check(game.scrap==before_scrap+80 and game.beacon_hp==1020 and game.hero.hp==700,"Rescuing a scout must award supplies and recovery"):return
	if not check(game.beacon_repair_cost()==17,"The rescued scout must reduce the beacon repair cost"):return
	before_scrap=game.scrap
	events.tick(10)
	if not check(game.scrap==before_scrap,"A rescued scout must not grant duplicate rewards"):return
	game.hero.position=home;game.move_goal=home
	if not check(game.interact() and game.scrap==before_scrap-17 and game.beacon_hp==1170,"F repair must actually charge the discounted cost"):return
	var outside_corner:=Vector3(-Layout.RAMP_OUTER_HALF-.2,0,Layout.RAMP_END+.15)
	var inside_corner:=Vector3(-1.405,0,Layout.RAMP_WALL_START-.263)
	inside_corner.y=game.outpost_height(inside_corner)
	if not check(game.outpost_walkable(outside_corner) and game.outpost_walkable(inside_corner),"Corner-cut fixture must start and end at legal terrain points"):return
	if not check(not game.can_traverse(outside_corner,inside_corner),"Continuous wall checks must reject a shallow ramp corner cut"):return
	var second: Dictionary=events.generators[1]
	game.hero.position=second.position;game.move_goal=game.hero.position
	game.interact();events.tick(2)
	var unfinished_camp: Dictionary=events.camps[1]
	game.hero.position=unfinished_camp.position;game.move_goal=game.hero.position
	game.interact()
	game.phase="draft";events.tick(10)
	if not check(is_equal_approx(second.progress,2.0),"Draft selection must freeze expedition timers"):return
	game.phase="day";game.start_night()
	if not check(second.state=="ready" and second.progress==0 and game.generator_cells==1,"Dusk must reset unfinished work while retaining earned upgrades"):return
	if not check(camp.state=="delivered","Rescued scouts must remain at the fortress after dark"):return
	if not check(unfinished_camp.state=="waiting" and (unfinished_camp.npc as BattleUnit).position.distance_to(unfinished_camp.position)<3,"Unfinished escorts must withdraw to camp at dusk"):return
	game.finish_night();game.choose_card(0)
	game.hero.position=unfinished_camp.position;game.move_goal=game.hero.position
	if not check(game.interact() and unfinished_camp.state=="escort","A withdrawn escort must be available again the next day"):return
	for guard in unfinished_camp.guards:guard.hurt(10000,game.hero)
	game.plan_hero_path(home)
	npc=unfinished_camp.npc
	for step in 1400:
		var old_npc:=npc.position
		game.move_hero(.04);events.tick(.04)
		if unfinished_camp.state=="delivered":break
		if not check(game.can_traverse(old_npc,npc.position),"The eastern scout must also avoid every wall"):return
	if not check(unfinished_camp.state=="delivered" and game.survivors_rescued==2 and game.beacon_repair_cost()==14,"The eastern scout must reach home and provide the second repair discount"):return
	print("NIGHTFALL_DAY_EXPEDITIONS_OK generator hold, ambush, gate escort, persistent night rewards, dusk reset")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit()
