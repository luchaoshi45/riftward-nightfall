extends SceneTree
## 生产入口回归：四夜末波首领、增援账本与清场结算。

var failures: Array[String] = []
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:return
	failures.append(message)
	push_error(message)

func clear_units(game: Node3D, keep: BattleUnit = null) -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy) and enemy != keep:
			enemy.queue_free()
	game.enemies.clear()
	if is_instance_valid(keep):game.enemies.append(keep)

func find_boss(game: Node3D) -> BattleUnit:
	for enemy in game.enemies:
		if is_instance_valid(enemy) and enemy.get_meta("siege_boss",false):return enemy
	return null

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.set_process(false)
	game.run_mode="siege"
	game.run_mode_locked=true
	game.day_number=4
	game.start_night()
	clear_units(game)
	game.wave_index=4
	game.spawn_night_wave()
	var entry: Dictionary=game.night_plan[4]
	var boss: BattleUnit=find_boss(game)
	check(bool(entry.boss_entry) and int(entry.boss_count)==1,"四夜末波必须标记唯一首领")
	check(int(entry.count)==entry.roles.size()+1,"末波预告人数必须包含首领")
	check(boss!=null and game.enemies.filter(func(unit: BattleUnit)->bool:return is_instance_valid(unit) and unit.get_meta("siege_boss",false)).size()==1,"生产末波只能生成一个首领")
	check(boss!=null and boss.hp==2600.0 and boss.max_hp==2600.0 and boss.armor==18.0,"生产首领生命和护甲必须为2600/18")
	var reward: Dictionary=game.wave_rewards.snapshot(19)
	check(reward.count==entry.count and reward.sealed,"首领必须登记进同一末波账本并封波")
	if boss==null:
		await game.prepare_shutdown()
		game.queue_free()
		await process_frame
		quit(1)
		return

	# Isolate the real boss windup in walkable courtyard space. The old
	# centre-of-core placement was blocked and its hero was outside slam range.
	boss.position=Vector3(8,5,0)
	game.hero.position=Vector3(10,5,0)
	check(game.outpost_walkable(boss.position) and game.outpost_walkable(game.hero.position),"首领与英雄夹具必须都在真实可通行庭院内")
	check(game.can_traverse(boss.position,game.hero.position) and boss.position.distance_to(game.hero.position)<=float(game.boss_snapshot().radius),"真实首领目标必须路径可达且处于原3.2米拍击范围内")
	check(game.siege_boss.advance(8.0) and game.boss_snapshot().phase=="windup","生产首领必须进入真实蓄力")
	check((game.boss_snapshot().position as Vector3).is_equal_approx(game.hero.position),"真实蓄力必须锁定可达邻近英雄而非阻挡内的核心")
	var windup_before: float=float(game.boss_snapshot().windup)
	game.phase="paused"
	check(game.siege_boss.advance(1.0) and is_equal_approx(float(game.boss_snapshot().windup),windup_before),"暂停期间首领蓄力必须冻结")
	game.phase="draft"
	check(game.siege_boss.advance(1.0) and is_equal_approx(float(game.boss_snapshot().windup),windup_before),"选卡期间首领蓄力必须冻结")
	game.phase="night"
	boss.shield=1000.0
	var shield_hp: float=boss.hp
	boss.hurt(118.0,game.hero)
	check(boss.hp==shield_hp and boss.shield<1000.0,"真实hurt必须消耗护盾且不扣首领生命")
	check(game.siege_boss.advance(.1) and float(game.boss_snapshot().interrupt_damage)==0.0,"护盾伤害不能推进蓄力打断")
	boss.shield=0.0
	var interrupt_hp: float=boss.hp
	boss.hurt(259.6,game.hero)
	check(is_equal_approx(interrupt_hp-boss.hp,220.0),"原18护甲下真实hurt必须精确扣除220生命")
	check(game.siege_boss.advance(.1) and game.boss_snapshot().phase=="exposed","220实际生命伤害必须进入4秒破绽")
	check(boss.armor==0.0 and is_equal_approx(float(game.boss_snapshot().exposed),4.0),"破绽必须移除护甲并持续4秒")
	boss.hp=1600.0
	game.siege_boss.advance(.1)
	boss.hp=800.0
	game.siege_boss.advance(.1)
	var state: Dictionary=game.boss_snapshot()
	check(int(state.adds)==6 and int(state.reinforcement_batches)==2,"首领必须分两批生成各3只增援")
	reward=game.wave_rewards.snapshot(19)
	check(reward.count==entry.count+6 and reward.sealed,"两批增援必须登记并重新封回同一账本")

	# 保留一个真实残敌，验证首领死亡不能提前结算。
	clear_units(game,boss)
	var residual: BattleUnit=game.spawn_creature(true,"runner")
	check(game.register_active_wave_enemy(residual),"清场残敌必须登记到当前末波账本")
	game.final_clearance_active=true
	game.wave_index=game.WAVES_PER_NIGHT
	game.phase_time=0.0
	boss.hurt(100000.0,game.hero)
	check(game.boss_snapshot().phase=="dead" and game.phase=="night","首领死亡且仍有残敌时必须保持战斗阶段")
	game.simulate(.02)
	check(game.phase=="night" and game.final_clearance_active,"残敌存活时不能提前迎来日出")
	residual.hurt(100000.0,game.hero)
	game.simulate(.02)
	check(game.phase=="ended" and game.victory,"全部敌人清除后必须只结算一次胜利")
	var ending_notice: String=game.notice
	game.finish_night()
	check(game.notice==ending_notice and game.phase=="ended","结算完成后重复调用不得再次触发")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	if failures.is_empty():
		print("NIGHTFALL_SIEGE_BOSS_OK checks=%d failures=0 production spawn, reachable courtyard, windup freeze, shield-safe interrupt, exposed, reinforcements, clearance" % checks)
		quit(0)
	else:
		print("NIGHTFALL_SIEGE_BOSS_FAILED checks=%d failures=%d " % [checks,failures.size()],failures)
		quit(1)
