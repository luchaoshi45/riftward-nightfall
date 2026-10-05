extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func make_hunter(game: Node3D, point: Vector3) -> BattleUnit:
	var hunter: BattleUnit=game.spawn_creature(false)
	hunter.set_meta("day_hunter",true)
	hunter.position=point
	hunter.position.y=game.outpost_height(point)
	hunter.speed=3.4
	return hunter

func chase_home(game: Node3D, from: Vector3) -> bool:
	var hunter:=make_hunter(game,from)
	var passed_gate:=false
	for step in 1600:
		var previous:=hunter.position
		hunter.tick(.04)
		game.update_creature(hunter,.04)
		if not check(game.can_traverse(previous,hunter.position),"Daytime hunter crossed a fortress or ramp wall"):return false
		if absf(hunter.position.x)<2.65 and hunter.position.z>=18.5 and hunter.position.z<20.5:passed_gate=true
		if hunter.position.distance_to(game.hero.position)<=hunter.attack_range:break
	if not check(passed_gate,"A side pursuer did not use the south gate"):return false
	if not check(hunter.position.y>4.8 and hunter.position.distance_to(game.hero.position)<=hunter.attack_range,"A side pursuer got stuck before reaching the hero inside the fortress"):return false
	hunter.queue_free();game.enemies.erase(hunter)
	return true

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.choose_card(0);game.set_process(false)
	game.begin_day()
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()
	game.hero.position=Vector3(0,5,3.1)
	game.hero.hp=game.hero.max_hp
	if not chase_home(game,Vector3(-10,0,10)):return
	if not chase_home(game,Vector3(10,0,10)):return
	var hunter:=make_hunter(game,Vector3(10,0,10))
	hunter.tick(.04);game.update_creature(hunter,.04)
	if not check(hunter.path.size()>=2,"An obstructed pursuer must plan a detour"):return
	game.hero.position=Vector3(-4,5,-4)
	for step in 15:
		var previous:=hunter.position
		hunter.tick(.04);game.update_creature(hunter,.04)
		if not check(game.can_traverse(previous,hunter.position),"Replanning cut a wall corner"):return
	if not check(hunter.path_goal.distance_to(game.hero.position)<.01,"A hunter must replan when the hero moves inside the fortress"):return
	game.hero.position=Vector3(18,0,24)
	for step in 1000:
		var previous:=hunter.position
		hunter.tick(.04);game.update_creature(hunter,.04)
		if not check(game.can_traverse(previous,hunter.position),"Changed-target pursuit crossed a wall"):return
		if hunter.position.distance_to(game.hero.position)<=hunter.attack_range:break
	if not check(hunter.position.distance_to(game.hero.position)<=hunter.attack_range,"A hunter failed to follow the hero's changed destination"):return
	game.phase="night"
	var ordinary: BattleUnit=game.spawn_creature(true)
	ordinary.position=Vector3(0,0,25);ordinary.set_meta("threat","stalker");ordinary.set_meta("gate_lane",0.0)
	game.hero.position=Vector3(20,0,30)
	var previous:=ordinary.position
	game.update_creature(ordinary,.1)
	if not check(ordinary.position.z<previous.z and is_equal_approx(ordinary.position.x,0),"Ordinary night creatures must retain their south-gate lane"):return
	# Night pursuers must also route through the gate when the hero is on the
	# raised courtyard. A straight-line chase used to stall against the east
	# ramp wall and could queue a hit on an intermediate waypoint.
	for pad: Dictionary in game.world.tower_pads:
		pad.level=0;pad.hp=0.0
	game.gate_barricade_hp=0.0
	game.hero.position=Vector3(.8,5,1.0)
	var night_hunter: BattleUnit=game.spawn_creature(true,"runner")
	night_hunter.position=Vector3(8.5,0,18)
	night_hunter.position.y=game.outpost_height(night_hunter.position)
	var entered_courtyard:=false
	var reached_hero:=false
	for step in 1800:
		var before:=night_hunter.position
		night_hunter.tick(.04)
		game.update_creature(night_hunter,.04)
		if not check(game.can_traverse(before,night_hunter.position),"Night pursuer crossed a raised-terrain wall"):return
		if night_hunter.position.y>4.8:entered_courtyard=true
		if night_hunter.position.distance_to(game.hero.position)<=night_hunter.attack_range:
			reached_hero=true
			break
	if not check(entered_courtyard and reached_hero,"Night pursuer got stuck before reaching a high-ground hero"):return
	if not check(not night_hunter.attack_queued or night_hunter.attack_target_hero,"A high-ground waypoint must never queue a non-hero attack"):return
	print("NIGHTFALL_DAY_HUNTER_PATH_OK both fortress sides, south-gate pursuit, target replanning, continuous wall checks, unchanged night lane")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit()
