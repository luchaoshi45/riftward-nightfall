extends SceneTree
var game: Node3D
func _initialize() -> void:
	call_deferred("run")

func enemy_at(offset: Vector3) -> BattleUnit:
	var enemy: BattleUnit=game.spawn_creature(false)
	enemy.position=game.hero.position+offset
	enemy.hp=4000;enemy.max_hp=4000;enemy.armor=0
	return enemy

func run() -> void:
	for core_index in 3:
		game=load("res://scenes/nightfall.tscn").instantiate()
		root.add_child(game);current_scene=game
		for i in 8:await process_frame
		game.set_process(false)
		assert(game.run.offer.size()==3)
		assert(game.run.offer[core_index].id==["core_storm","core_flame","core_guard"][core_index])
		if core_index==0 and DisplayServer.get_name()!="headless":
			game.notice_time=0;game.hud.queue_redraw()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/core-opening.png")
		assert(game.choose_card(core_index))
		for enemy in game.enemies:enemy.queue_free()
		game.enemies.clear()
		await process_frame
		var primary:=enemy_at(Vector3(1,0,0))
		var nearby:=enemy_at(Vector3(2.7,0,0))
		game.aim=game.hero.position+Vector3.RIGHT*10
		if core_index==0:
			game.hero_attack_target=primary;game.hero_attack_delay=0
			game.hero_attack_step=2;game.attack_chain_time=2
			game.update_hero_attack(0)
			assert(nearby.hp<4000,"Third strike must chain to an actual enemy")
			var previous: float=nearby.hp
			game.hero_attack_target=primary;game.hero_attack_step=0
			game.update_hero_attack(0)
			assert(nearby.hp==previous,"First strike must not chain")
		elif core_index==1:
			assert(game.cast(0));assert(game.cores.marks.size()==2)
			game.phase="paused";game.simulate(9)
			assert(game.cores.marks[0].time==4.0,"Pause freezes mark lifetime")
			game.phase="night"
			var previous: float=primary.hp
			assert(game.cast(3))
			assert(is_equal_approx(previous-primary.hp,320.0),"Marked R adds 60 real damage")
			assert(game.cores.marks.is_empty())
			game.cooldowns[0]=0;game.cast(0);game.cores.advance(4.1)
			assert(game.cores.consume(primary)==0,"Expired marks cannot grant damage")
		else:
			assert(game.cast(1))
			var previous: float=primary.hp
			game.hero.hurt(20,primary)
			assert(is_equal_approx(previous-primary.hp,50.0))
			assert(not game.cores.guard_ready)
			previous=primary.hp;game.hero.hurt(20,primary)
			assert(primary.hp==previous,"Only one shock per W cast")
			game.cooldowns[1]=0;game.cast(1);game.hero.shield=0
			game.cores.advance(.01);assert(not game.cores.guard_ready)
		if DisplayServer.get_name()!="headless":
			game.notice_time=0;game.hud.queue_redraw()
			await create_timer(.12).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/core-%d.png" % core_index)
		game.cores.clear()
		await game.prepare_shutdown();game.queue_free()
		for i in 4:await process_frame
	print("NIGHTFALL_COMBAT_CORES_OK")
	quit()
