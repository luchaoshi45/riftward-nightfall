extends SceneTree
## Production regression for target-side enemy telegraphs and confirmed hero damage.

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func clear_enemies(game: Node3D) -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()

func reset_damage_target(hero: BattleUnit, hp: float = 500.0, shield: float = 0.0) -> void:
	hero.alive=true
	hero.hp=hp
	hero.max_hp=hp
	hero.shield=shield
	hero.armor=0.0

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	check(game.choose_card(0) and game.phase=="night", "Opening card must enter the production night")
	clear_enemies(game)
	game.hero.position=Vector3(0,game.outpost_height(Vector3(0,0,3.1)),3.1)
	game.move_goal=game.hero.position

	var attacker: BattleUnit=game.spawn_creature(true)
	attacker.set_meta("threat","stalker")
	attacker.title="测试夜行体"
	attacker.position=Vector3(1.35,game.outpost_height(Vector3(1.35,0,3.1)),3.1)
	attacker.speed=0.0
	attacker.damage=30.0
	attacker.attack_timer=0.0
	var hero_hp: float=game.hero.hp
	game.update_creature(attacker,.1)
	check(attacker.attack_queued and attacker.attack_windup>0.0, "A nearby enemy must enter a live windup")
	var warnings: Array[Dictionary]=game.target_warning_snapshot()
	check(warnings.size()==1 and warnings[0].target==game.hero, "The enemy windup must expose the actual hero target")
	check(float(warnings[0].progress)>=0.0 and float(warnings[0].remaining)<=float(warnings[0].duration), "Target warning progress must follow the live windup")
	game.phase="paused"
	var frozen_windup:=attacker.attack_windup
	game.simulate(10.0)
	check(is_equal_approx(attacker.attack_windup,frozen_windup) and game.target_warning_snapshot().size()==1, "Pause must freeze both the windup and its warning")
	game.phase="night"
	attacker.tick(frozen_windup)
	game.update_creature(attacker,.01)
	check(game.hero.hp<hero_hp and game.target_warning_snapshot().is_empty(), "A confirmed hit must clear the warning after applying damage")

	# The new signal is emitted after shield/HP deltas are known, before death.
	var order: Array[String]=[]
	game.hero.damaged.connect(func(_unit: BattleUnit,_source: BattleUnit): order.append("damaged"))
	game.hero.shield_absorbed.connect(func(_amount: float): order.append("shield"))
	game.hero.damage_confirmed.connect(func(_unit: BattleUnit,_source: BattleUnit,_hp_loss: float,_shield_loss: float): order.append("confirmed"))
	game.hero.defeated.connect(func(_unit: BattleUnit,_source: BattleUnit): order.append("defeated"))
	reset_damage_target(game.hero,500.0,40.0)
	order.clear();game.hero.hurt(20.0,null)
	check(order==["damaged","shield","confirmed"], "Shield-only damage must confirm after absorption without defeating the hero")
	check(is_equal_approx(game.hero.hp,500.0) and is_equal_approx(game.hero.shield,20.0), "Shield-only damage must leave HP untouched and report the real shield delta")
	reset_damage_target(game.hero,500.0,0.0)
	order.clear();game.hero.hurt(35.0,null)
	check(order==["damaged","confirmed"], "HP-only damage must confirm after the real HP delta")
	check(is_equal_approx(game.hero.hp,465.0), "HP-only damage must subtract the actual amount")
	reset_damage_target(game.hero,20.0,0.0)
	order.clear();game.hero.hurt(100.0,null)
	check(order==["damaged","confirmed","defeated"], "Lethal damage must confirm before defeated")
	var order_after_death:=order.size()
	game.hero.hurt(100.0,null)
	check(order.size()==order_after_death, "A defeated unit must not emit a second damage confirmation")

	# An unresolvable raised-ground target must never leave a stale windup.
	game.hero.revive(Vector3(0,game.outpost_height(Vector3(0,0,15.0)),15.0))
	game.phase="night"
	attacker.revive(Vector3(4.2,game.outpost_height(Vector3(4.2,0,15.0)),15.0))
	attacker.attack_timer=0.0;attacker.attack_queued=false;attacker.attack_windup=0.0
	game.update_creature(attacker,.1)
	check(not attacker.attack_queued and attacker.attack_windup<=0.0, "An unreachable raised-ground hero must clear enemy windup state")

	if is_instance_valid(game.squads):
		game.squads.hire("shield")
		game.squads.on_night()
		var blocker: BattleUnit=game.squads.squads[0].members[1]
		blocker.position=Vector3(0,game.outpost_height(Vector3(0,0,10.0)),10.0)
		attacker.revive(Vector3(0,game.outpost_height(Vector3(0,0,11.0)),11.0))
		attacker.attack_timer=0.0;attacker.attack_queued=false
		check(game.squads.intercept_enemy(attacker,.01), "A nearby shield must intercept the enemy before it strikes")
		var intercepted: Array[Dictionary]=game.target_warning_snapshot()
		check(intercepted.size()==1, "A shield intercept must produce one target warning")
		if intercepted.size()==1:
			check(intercepted[0].target==blocker, "A shield intercept must expose the blocker as the warned target")

	print("NIGHTFALL_TARGET_WARNING_HIT_CONFIRM_", "OK" if failures.is_empty() else "FAILED", " warnings damage_signal shield_only hp_only lethal intercept")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit(0 if failures.is_empty() else 1)
