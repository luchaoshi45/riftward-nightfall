extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
## Exercise the real escort route and its persistent, local homecoming lights.
const STEP := .04
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:return
	failures.append(message);push_error(message)

func clear_enemies(game: Node3D) -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()

func press_escape(game: Node3D) -> void:
	var event:=InputEventKey.new()
	event.keycode=KEY_ESCAPE;event.pressed=true
	game._unhandled_input(event)

func no_collisions(node: Node) -> bool:
	if node is CollisionObject3D:return false
	for child in node.get_children():
		if not no_collisions(child):return false
	return true

func check_summary(game: Node3D, people: int) -> void:
	var previous_victory: bool=game.victory
	var previous_phase: String=game.phase
	game.phase="ended"
	var responses: Array[String]=[]
	for won in [false,true]:
		game.victory=won
		var summary: Dictionary=game.homecoming_summary()
		check(summary.people==people and summary.repair_cost==game.beacon_repair_cost(),"The result must use the actual returned people and real repair fee")
		check(String(summary.record).contains("%d / 2" % people),"The return record must report the actual escort outcome")
		var real_names: Array[String]=[]
		for camp in game.expeditions.camps:
			if camp.state=="delivered":real_names.append(camp.scout_name)
		check(summary.names==real_names,"The ending must remember the identities of actual returnees")
		for name in real_names:check(String(summary.record).contains(name),"Actual returned names must appear in the result")
		var response: String=summary.response
		check(not response.is_empty(),"Each real return count must receive a concrete story response")
		check(not response.contains("死亡") and not response.contains("牺牲"),"The result must not invent unimplemented deaths for rescued or waiting scouts")
		responses.append(response)
	check(responses[0]!=responses[1],"Victory and loss must respond differently without rewriting the actual rescue record")
	game.victory=previous_victory
	game.phase=previous_phase

func escort_home(game: Node3D, camp: Dictionary) -> float:
	game.plan_hero_path(Vector3(0,NightfallWorld.FORT_HEIGHT,3.1))
	var elapsed:=0.0
	var npc: BattleUnit=camp.npc
	for step in 1800:
		var before:=npc.position
		game.move_hero(STEP)
		game.expeditions.tick(STEP)
		game.phase_time-=STEP;elapsed+=STEP
		if camp.state=="delivered":break
		check(game.can_traverse(before,npc.position),"The follower must use the south gate without crossing walls")
	return elapsed

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.set_process(false);game.world.set_process(false)
	var expeditions: DayExpeditions=game.expeditions
	check(expeditions.camps.size()==2,"There must be exactly two returnable scouts")
	for camp in expeditions.camps:
		check(camp.home_lantern==null and camp.home_light==null,"Waiting scouts must not have homecoming lights")
	check(game.choose_card(0) and game.phase=="night","The first card must lead straight into the opening night")
	game.begin_day();clear_enemies(game)
	check_summary(game,0)
	var first: Dictionary=expeditions.camps[0]
	var second: Dictionary=expeditions.camps[1]
	var initial_scrap: int=game.scrap
	expeditions.light_home_lantern(first,0)
	check(first.home_lantern==null and first.home_light==null,"A waiting scout may not light a home lamp even if its helper is called")
	expeditions.deliver_scout(first,0)
	check(first.state=="waiting" and game.scrap==initial_scrap and game.survivors_rescued==0,"Calling delivery for a waiting scout must not fabricate a return or reward")
	game.hero.position=first.position;game.move_goal=game.hero.position
	check(game.interact() and first.state=="escort","F must recruit the western scout through the real interaction")
	check(game.notice.begins_with(first.scout_name),"Recruitment must give the actual scout a short personal response")
	expeditions.deliver_scout(first,0)
	check(first.state=="escort" and first.home_light==null and game.survivors_rescued==0,"Starting an escort outside the fort must not count as homecoming")
	for guard in first.guards:guard.hurt(10000,game.hero)
	clear_enemies(game)
	game.phase_time-=2.0
	var npc: BattleUnit=first.npc
	var paused_position:=npc.position
	var paused_time: float=game.phase_time
	press_escape(game);game.simulate(3.0);expeditions.tick(3.0)
	check(game.phase=="paused" and npc.position==paused_position and game.phase_time==paused_time,"Actual pause input must freeze escort movement and the daylight budget")
	check(first.home_light==null,"Pause must not create a homecoming light")
	press_escape(game)
	game.run.grant("返家测试能力");game.open_draft()
	game.simulate(3.0);expeditions.tick(3.0)
	check(game.phase=="draft" and npc.position==paused_position and game.phase_time==paused_time,"Card selection must freeze the real escort and daylight timer")
	check(game.choose_card(0) and game.phase=="day","Choosing the card must resume this daytime escort")
	game.beacon_hp=900;game.hero.hp=600
	var before_scrap: int=game.scrap
	var elapsed:=escort_home(game,first)
	check(first.state=="delivered" and game.survivors_rescued==1,"Only an actual trip up the south ramp may commit the first return")
	check(elapsed<game.DAY_LENGTH and game.phase_time>0,"A real western escort must fit the ninety-second daylight budget")
	check(game.scrap==before_scrap+80 and game.beacon_hp==1020 and game.hero.hp==700,"Homecoming must preserve the existing supplies and recovery amounts")
	check(game.beacon_repair_cost()==17,"The returned person must make actual beacon repair cost seventeen")
	check_summary(game,1)
	check(is_instance_valid(first.home_lantern) and is_instance_valid(first.home_light),"A completed escort must leave a real lantern model and 3D light at home")
	var first_lamp: OmniLight3D=first.home_light
	var first_lantern: Node3D=first.home_lantern
	check(first_lamp.light_energy>0 and first_lamp.omni_range>=3.0 and first_lamp.omni_range<=4.0,"Home light must illuminate a small local area rather than the entire map")
	check(first_lantern.position.distance_to(npc.position)<1.1 and no_collisions(first_lantern),"The home lantern must stay beside its scout without adding navigation blockers")
	check((first.label as Label3D).position.distance_to(npc.position+Vector3.UP*2.5)<.001,"The return label must move from the empty camp to the actual person at home")
	var first_light_id: int=first_lamp.get_instance_id()
	before_scrap=game.scrap
	expeditions.deliver_scout(first,0);expeditions.tick(.5)
	check(game.scrap==before_scrap and game.survivors_rescued==1 and (first.home_light as OmniLight3D).get_instance_id()==first_light_id,"Duplicate delivery must not mint rewards, people or lanterns")
	game.hero.position=second.position;game.move_goal=game.hero.position
	check(game.interact() and second.state=="escort","The second scout must also be recruitable")
	check(second.home_light==null,"A started eastern escort must not prematurely light a home lamp")
	game.start_night()
	check(second.state=="waiting" and second.home_light==null and second.home_lantern==null,"Dusk must withdraw an unfinished escort without pretending the person returned")
	check((second.npc as BattleUnit).position.distance_to(second.position)<3.0,"The interrupted scout must return to the retryable camp")
	check(first.state=="delivered" and first_lamp.light_energy>0 and first_lantern.visible and first.label.visible,"The delivered scout, label and real home light must persist through night")
	check(game.beacon_repair_cost()==17 and game.survivors_rescued==1,"Dusk must retain only the completed scout's repair help")
	clear_enemies(game)
	game.hero.position=Vector3(0,NightfallWorld.FORT_HEIGHT,3.1);game.move_goal=game.hero.position
	game.beacon_hp=800;before_scrap=game.scrap
	check(game.interact() and game.scrap==before_scrap-17 and game.beacon_hp==950,"Nighttime beacon repair must actually spend the discounted seventeen supplies")
	var before_hp: float=game.beacon_hp
	expeditions.tick(5.0)
	check(game.beacon_hp==before_hp and game.scrap==before_scrap-17,"Returned scouts must not secretly auto-repair or pay additional rewards")
	TransitionFixture.finish_for_fixture(game);check(game.choose_card(0) and game.phase=="day","The next dawn must restore the retryable daytime activity")
	clear_enemies(game)
	game.hero.position=second.position;game.move_goal=game.hero.position
	check(game.interact() and second.state=="escort","The withdrawn scout must be available again after dawn")
	for guard in second.guards:guard.hurt(10000,game.hero)
	clear_enemies(game)
	before_scrap=game.scrap
	elapsed=escort_home(game,second)
	check(second.state=="delivered" and game.survivors_rescued==2 and elapsed<game.DAY_LENGTH,"The eastern route must also genuinely deliver within one daylight phase")
	check(game.scrap==before_scrap+80 and game.beacon_repair_cost()==14,"The second returned person must preserve the eighty-supply reward and fourteen-supply repair fee")
	check_summary(game,2)
	check(is_instance_valid(second.home_light) and second.home_light!=first.home_light,"Each returned person must leave their own home light")
	game.start_night();clear_enemies(game)
	for camp in expeditions.camps:
		check(camp.state=="delivered" and camp.home_light.light_energy>0 and camp.label.visible,"Both actual returns must remain visible in the following night")
	game.hero.position=Vector3(0,NightfallWorld.FORT_HEIGHT,3.1);game.move_goal=game.hero.position
	game.beacon_hp=800;before_scrap=game.scrap
	check(game.interact() and game.scrap==before_scrap-14 and game.beacon_hp==950,"Two returnees must make a real nighttime repair spend fourteen supplies")
	expeditions.deliver_scout(second,1)
	check(game.scrap==before_scrap-14 and game.survivors_rescued==2,"Retrying second delivery must also be harmless")
	await game.prepare_shutdown()
	game.queue_free();await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_HOMECOMING_STORY_", "OK" if failures.is_empty() else "FAILED", " real_gate_routes once_only pause_draft dusk_retry local_home_lights persistent_repair_help")
	quit(0 if failures.is_empty() else 1)
