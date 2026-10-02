extends SceneTree
var game: Node3D
var failures: int=0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: print("PASS: ",message)
	else:
		failures+=1
		push_error("FAIL: "+message)

func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.auto_test=true
	game.start_match()
	game.select_card(0)
	check(game.units.size()==24,"Two cores, twelve towers, six heroes, four camps")
	var transient: BattleUnit=game.spawn_unit("minion",1,Vector3.ZERO)
	var stale: Variant=transient
	game.units.erase(transient)
	transient.free()
	check(not game.valid_target(stale,0),"Freed target references are safely rejected")
	game.spawn_wave()
	for team in [0,1]:
		for lane in range(3):
			var count:=0
			for unit in game.units:
				if unit.kind=="minion" and unit.team==team and unit.lane==lane: count+=1
			check(count==3,"Three minions per team/lane %d/%d" % [team,lane])
	# Traverse a forest island using real movement code.
	game.player.position=Vector3(-31,0,-9)
	game.player.path.clear()
	var safe:=true
	for i in range(600):
		game.player.tick(1.0/60)
		game.move_unit(game.player,Vector3(-16,0,-9),1.0/60)
		if not BattleMap.walkable(game.player.position): safe=false
	check(safe,"Route never enters forest collision")
	check(game.player.position.distance_to(Vector3(-16,0,-9))<.5,"Route reaches other side of forest")
	game.player.position=Vector3(-29,0,-9)
	game.player.destination=game.player.position
	game.aim=Vector3(-20,0,-9)
	game.mana=300
	game.cast(2)
	check(game.player.position.x < -27.9,"Dash stops before solid forest")
	# Camp aggro, leash, reward and timed respawn.
	var monster: BattleUnit
	for unit in game.units:
		if unit.kind=="monster": monster=unit; break
	game.player.position=monster.home_point+Vector3(2,0,0)
	var hp: float=monster.hp
	game.deal_damage(monster,30,game.player)
	check(monster.hp<hp and monster.target==game.player,"Neutral camp retaliates only after damage")
	game.player.position=monster.home_point+Vector3(11,0,0)
	game.update_monster(monster,.1)
	check(monster.resetting and monster.target==null,"Camp leashes when target leaves")
	for i in range(100): game.update_monster(monster,.1)
	check(not monster.resetting and monster.hp==monster.max_hp,"Leashed camp returns and heals")
	game.player.position=monster.home_point+Vector3(2,0,0)
	var essence: float=game.essence
	game.deal_damage(monster,99999,game.player)
	check(not monster.alive and game.essence==essence+70,"Camp rewards exactly 70 essence")
	check(game.vigor_time==45 and game.jungle_kills==1,"Camp grants timed regeneration buff")
	game.update_respawns(44)
	check(not monster.alive,"Camp does not respawn early")
	game.update_respawns(1.1)
	check(monster.alive and monster.position==monster.home_point,"Camp respawns at home")
	game.player.shield=100
	game.recall()
	game.player.hurt(1,game.enemy)
	check(game.recall_time==0,"Shielded hit still interrupts recall")
	# Every side-lane AI actually leaves the base on its assigned lane.
	for hero in game.heroes:
		if hero.lane==1: continue
		for i in range(150):
			hero.tick(1.0/30)
			game.update_bot(hero,1.0/30)
		check(absf(hero.position.z)>8,"Side-lane AI advances on assigned route: "+hero.title)
	# Minions follow bends instead of taking a diagonal shortcut through jungle.
	for lane in [0,2]:
		var scout: BattleUnit=game.spawn_unit("minion",0,BattleMap.home(0))
		scout.lane=lane
		for i in range(450):
			scout.tick(1.0/30)
			game.follow_lane(scout,1.0/30)
		check(absf(scout.position.z)>19,"Minion follows outer lane bend %d" % lane)
	print("RIFTWARD_THREE_LANES_OK" if failures==0 else "RIFTWARD_THREE_LANES_FAILED: %d" % failures)
	await process_frame
	quit(failures)
