extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func press(code: int) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.pressed=true
	Input.parse_input_event(event)
	await process_frame
	event.pressed=false;Input.parse_input_event(event)
	await process_frame

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.set_process(false)
	assert(game.phase=="draft" and game.return_phase=="night")
	assert(game.world.night_active and game.world.night_mix>.99,"Opening draft must already show the dark world")
	await press(KEY_1)
	assert(game.phase=="night" and game.day_number==1 and game.wave_index==1)
	assert(game.phase_time==game.NIGHT_LENGTH and game.enemies.size()==game.initial_night_pack())
	assert(game.tower_count()==2 and game.scrap==90 and game.gate_trap_charges==1,"Opening defense must be funded and playable immediately")
	assert(game.DAY_LENGTH==90.0)
	var cache: Dictionary=game.world.salvage[0]
	game.hero.position=cache.position;game.move_goal=game.hero.position
	var before: int=game.scrap
	await press(KEY_F)
	assert(cache.collected and game.scrap==before+cache.amount and game.exploration_count==1)
	assert(cache.respawn==game.SALVAGE_REFRESH and game.reward_toasts.size()==1)
	await press(KEY_F)
	assert(game.scrap==before+cache.amount and game.exploration_count==1,"Holding or repeating F must not grant twice")
	game.update_salvage_refresh(54)
	assert(cache.collected)
	await press(KEY_ESCAPE)
	assert(game.phase=="paused")
	var clock: float=game.phase_time
	game.simulate(10);game.update_salvage_refresh(10)
	assert(game.phase_time==clock and cache.respawn==1,"Pause must freeze both phase and refresh timers")
	await press(KEY_ESCAPE)
	game.update_salvage_refresh(1)
	assert(not cache.collected and cache.node.visible)
	await press(KEY_F)
	assert(game.exploration_count==2 and game.scrap==before+cache.amount*2)
	for i in 3:game.grant_exploration_reward("探索验证",game.hero.position,10,0)
	assert(game.exploration_count==5 and game.exploration_milestones==1)
	assert(game.scrap==before+cache.amount*2+30+35)
	assert(game.essence==26 and game.reward_toasts.back().title.contains("里程碑"))
	game.essence=game.run.memory_cost()-1
	game.grant_exploration_reward("晶簇记忆",game.hero.position,0,8)
	assert(game.phase=="night" and game.essence==7 and game.run.pending>0 and game.return_phase=="night")
	assert(game.request_upgrade() and game.phase=="draft","A queued memory inscription must open its draft through the real upgrade action")
	game.simulate(5)
	assert(game.phase_time==clock,"Reward card selection must freeze the night clock")
	assert(game.choose_card(0) and game.phase=="night" and game.phase_time==clock)
	game.finish_night()
	assert(game.day_number==2 and game.phase=="draft")
	assert(game.choose_card(0) and game.phase=="day" and game.phase_time==90)
	game.phase_time=.01;game.simulate(.02)
	assert(game.phase=="night" and game.day_number==2)
	assert(game.discoveries.items.size()==18 and game.wildlife.animals.size()==4)
	for creature in game.enemies:
		if is_instance_valid(creature):creature.queue_free()
	game.enemies.clear()
	game.hero.position=Vector3(0,5,3.1);game.move_goal=game.hero.position
	for i in 3:
		var creature: BattleUnit=game.spawn_creature(true)
		creature.position=game.hero.position+Vector3(1+i,0,0)
		creature.hp=50
	game.essence=game.run.memory_cost()-36;game.mana=game.max_mana;game.cooldowns[3]=0
	before=game.scrap
	assert(game.cast(3) and game.phase=="night" and game.run.pending>0)
	assert(game.scrap==before+24 and game.essence==0,"R multi-kills must retain night rewards while queuing the next memory inscription")
	assert(game.request_upgrade() and game.phase=="draft","A queued multi-kill memory inscription must open through the real upgrade action")
	assert(game.choose_card(0) and game.phase=="night")
	for item in game.discoveries.items:
		if item.kind!="memory_crystal" or item.state!="ready":continue
		game.hero.position=item.position;game.move_goal=game.hero.position
		game.essence=game.run.memory_cost()-12
		var rerolls: int=game.run.rerolls
		await press(KEY_F)
		assert(game.phase=="night" and item.state=="cooling" and game.run.pending>0)
		assert(game.request_upgrade() and game.phase=="draft","A memory crystal reaching the threshold must queue, then open through the upgrade action")
		await press(KEY_F)
		assert(game.run.rerolls==rerolls,"A quick repeated gathering tap must not consume a card reroll")
		break
	assert(game.phase=="draft","The repeat-input check must actually visit a ready crystal")
	game.choose_card(0)
	var charging: Dictionary={}
	for item in game.discoveries.items:
		if item.kind=="supply_cache" and item.state=="ready":charging=item;break
	assert(not charging.is_empty())
	game.hero.position=charging.position;game.move_goal=game.hero.position
	game.essence=game.run.memory_cost()-6
	assert(game.interact() and charging.state=="channel")
	charging.progress=2.9
	var later: Dictionary=game.discoveries.items.back()
	assert(charging!=later)
	game.discoveries.begin_cooling(later,40)
	game.discoveries.tick(.2)
	assert(game.phase=="night" and game.run.pending>0,"A cache reward must queue an upgrade without interrupting the night")
	assert(game.request_upgrade() and game.phase=="draft","A queued cache memory reward must open through the upgrade action")
	var frozen_later_respawn: float=later.respawn
	game.discoveries.tick(100.0)
	assert(is_equal_approx(later.respawn,frozen_later_respawn),"A cache reward opening cards must freeze later refresh entries")
	print("NIGHTFALL_EXPLORATION_LOOP_OK opening night, refreshing F, milestones, pause/draft clocks, R multi-kill payouts, rapid F protection")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit()
