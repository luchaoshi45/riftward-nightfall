extends SceneTree
## 三重裂光 must be three independent 70% Q hits, not one opaque multiplier.

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:return
	push_error(message)
	quit(1)

func clear_enemies(game: Node3D) -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()

func make_enemy(game: Node3D, position: Vector3) -> BattleUnit:
	var enemy: BattleUnit=game.spawn_creature(false)
	enemy.position=position
	enemy.max_hp=10000.0
	enemy.hp=10000.0
	enemy.armor=0.0
	return enemy

func reset_case(game: Node3D) -> void:
	game.phase="day"
	game.mana=game.max_mana
	game.cooldowns[0]=0.0
	game.hero.position=Vector3(-30.0,0.0,-20.0)
	game.hero.position.y=game.outpost_height(game.hero.position)
	game.move_goal=game.hero.position
	game.hero_path.clear()
	game.aim=game.hero.position+Vector3.FORWARD*20.0

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	clear_enemies(game)

	# Without the card Q remains one 110-damage hit.
	game.run.owned.erase("split")
	game.run.recalculate()
	reset_case(game)
	var regular:=make_enemy(game,game.hero.position+Vector3.FORWARD*5.0)
	check(game.cast(0),"A regular Q must cast")
	check(is_equal_approx(regular.hp,9890.0),"A regular Q must deal one base hit")

	# With split, a centred target is eligible for each of the three blades.
	clear_enemies(game)
	game.run.owned["split"]=1
	game.run.recalculate()
	reset_case(game)
	var centre:=make_enemy(game,game.hero.position+Vector3.FORWARD*5.0)
	check(game.cast(0),"A split Q must cast")
	check(is_equal_approx(centre.hp,9769.0),"A centred target must receive three independent 70%% hits")

	# Targets separated across the fan are still resolved independently; each
	# edge target should take at least one blade and not be skipped by the loop.
	clear_enemies(game)
	reset_case(game)
	var left:=make_enemy(game,game.hero.position+Vector3(-1.95,0,-4.60))
	var right:=make_enemy(game,game.hero.position+Vector3(1.95,0,-4.60))
	check(game.cast(0),"A split Q fan must cast against multiple targets")
	check(left.hp<10000.0 and right.hp<10000.0,"Each side of the split fan must be independently hittable")
	check(left.hp>9769.0 and right.hp>9769.0,"Separated fan targets should not receive all three overlapping centre hits")

	# A paused cast remains inert and cannot produce a second damage pass.
	clear_enemies(game)
	reset_case(game)
	var paused_target:=make_enemy(game,game.hero.position+Vector3.FORWARD*5.0)
	game.phase="paused"
	check(not game.cast(0),"Paused split Q must be rejected")
	check(is_equal_approx(paused_target.hp,10000.0),"Paused split Q must not damage a target")

	print("NIGHTFALL_SPLIT_Q_OK regular single hit, split triple hit, independent fan targets and pause freeze")
	await game.prepare_shutdown()
	game.free()
	await process_frame
	await create_timer(.5).timeout
	quit()
