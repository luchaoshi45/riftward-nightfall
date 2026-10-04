extends SceneTree
## Production behavior checks for core expansion plots and nearest-unit targeting.

var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func frames(count: int = 6) -> void:
	for _i in count: await process_frame

func run() -> void:
	game=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await frames(12)
	assert(game.world.tower_pads.size()==12)
	var core_indices: Array[int]=[]
	for i in game.world.tower_pads.size():
		if String(game.world.tower_pads[i].get("zone","outer"))=="core": core_indices.append(i)
	assert(core_indices.size()==4)
	assert(game.choose_card(0) and game.phase=="night")
	var core_index: int=core_indices[0]
	var core_pad: Dictionary=game.world.tower_pads[core_index]
	game.hero.position=core_pad.position+Vector3(.5,0,.5)
	game.move_goal=game.hero.position
	game.scrap=1000
	assert(game.interact() and core_pad.level==1)
	assert(game.tower_count()==3)
	assert(game.interaction_prompt().contains("核心防线"))

	# An approaching ordinary enemy selects the closest constructed tower.
	game.hero.position=Vector3(20,0,20)
	var enemy: BattleUnit=game.spawn_creature(true,"stalker")
	enemy.position=core_pad.position+Vector3(1.0,0,0)
	enemy.attack_timer=0.0
	var target: Dictionary=game.choose_enemy_target(enemy)
	assert(String(target.kind)=="tower" and int(target.index)==core_index)
	game.update_creature(enemy,.1)
	assert(enemy.attack_queued and String(enemy.get_meta("attack_target_kind"))=="tower")
	var tower_hp: float=core_pad.hp
	enemy.attack_windup=0.0
	game.update_creature(enemy,.1)
	assert(core_pad.hp<tower_hp)

	# Moving the hero beside the same enemy changes the target and cancels windup.
	game.hero.position=enemy.position+Vector3(.8,0,0)
	enemy.attack_timer=0.0
	enemy.attack_queued=false
	game.update_creature(enemy,.1)
	assert(String(enemy.get_meta("attack_target_kind"))=="hero")

	# Exposed ranged defenders are valid nearest targets; shields still intercept
	# through outpost_squads before this controller is reached.
	game.hero.position=Vector3(20,0,20)
	game.scrap=1000
	assert(game.squads.hire("ranged").ok)
	var archer: BattleUnit=game.squads.squads[0].members[0]
	enemy.position=archer.position+Vector3(-.5,0,0)
	enemy.attack_timer=0.0
	enemy.attack_queued=false
	var squad_target: Dictionary=game.choose_enemy_target(enemy)
	var squad_member: BattleUnit=squad_target.get("unit") as BattleUnit
	assert(String(squad_target.kind)=="squad" and is_instance_valid(squad_member))
	game.update_creature(enemy,.1)
	assert(enemy.attack_queued and int(enemy.get_meta("attack_target_token"))==squad_member.get_instance_id())
	var archer_hp: float=squad_member.hp
	enemy.attack_windup=0.0
	game.update_creature(enemy,.1)
	assert(squad_member.hp<archer_hp)

	# A defeated target is removed on the next selection and the enemy falls back
	# to a surviving structure/core instead of striking a stale reference.
	for member: BattleUnit in game.squads.squads[0].members:
		if is_instance_valid(member) and member.alive: member.hurt(99999.0,enemy)
	assert(not squad_member.alive)
	enemy.attack_timer=0.0
	enemy.attack_queued=false
	var fallback: Dictionary=game.choose_enemy_target(enemy)
	assert(String(fallback.kind)!="squad")

	print("NIGHTFALL_OUTPOST_DEFENSE_OK")
	await game.prepare_shutdown()
	game.queue_free()
	await frames(4)
	quit()
