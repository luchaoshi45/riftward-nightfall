extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")

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
	assert(cache.collected and game.scrap==before+cache.amount+3 and game.exploration_count==1)
	assert(cache.respawn==game.SALVAGE_REFRESH and game.reward_toasts.size()==1)
	await press(KEY_F)
	assert(game.scrap==before+cache.amount+3 and game.exploration_count==1,"Holding or repeating F must not grant twice")
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
	assert(game.exploration_count==2 and game.scrap==before+(cache.amount+3)*2)
	for i in 3:game.grant_exploration_reward("探索验证",game.hero.position,10,0)
	assert(game.exploration_count==5 and game.exploration_milestones==1)
	assert(game.scrap==before+(cache.amount+3)*2+30+55)
	assert(game.run.pending==0 and game.reward_toasts.back().title.contains("里程碑"),"Exploration milestones add shared scrap without automatically queuing cards")
	game.scrap=game.run.memory_cost()-8
	game.grant_exploration_reward("零件铭刻补给",game.hero.position,8)
	assert(game.phase=="night" and game.scrap==game.run.memory_cost() and game.run.pending==0)
	assert(game.request_upgrade() and game.phase=="draft" and game.scrap==0,"The real V action must buy one legal inscription from the shared scrap balance")
	game.simulate(5)
	assert(game.phase_time==clock,"Reward card selection must freeze the night clock")
	assert(game.choose_card(0) and game.phase=="night" and game.phase_time==clock)
	TransitionFixture.finish_for_fixture(game)
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
	game.scrap=game.run.memory_cost()-24;game.mana=game.max_mana;game.cooldowns[3]=0
	before=game.scrap
	assert(game.cast(3) and game.phase=="night" and game.run.pending==0)
	assert(game.scrap==before+24,"R multi-kills must retain the actual night scrap budget without automatic card purchases")
	assert(game.request_upgrade() and game.phase=="draft" and game.scrap==0,"A funded multi-kill must allow one explicit shared-scrap inscription")
	assert(game.choose_card(0) and game.phase=="night")
	for item in game.discoveries.items:
		if item.kind!="memory_crystal" or item.state!="ready":continue
		game.hero.position=item.position;game.move_goal=game.hero.position
		game.scrap=game.run.memory_cost()-12
		var rerolls: int=game.run.rerolls
		await press(KEY_F)
		assert(game.phase=="night" and item.state=="cooling" and game.run.pending==0 and game.scrap>=game.run.memory_cost())
		assert(game.request_upgrade() and game.phase=="draft","A real ember crystal must fund an explicitly purchased inscription")
		await press(KEY_F)
		assert(game.run.rerolls==rerolls,"A quick repeated gathering tap must not consume a card reroll")
		break
	assert(game.phase=="draft","The repeat-input check must actually visit a ready crystal")
	game.choose_card(0)
	var charging: Dictionary={}
	for item_index in game.discoveries.items.size():
		var item: Dictionary=game.discoveries.items[item_index]
		# The earlier lifecycle fixture retires actors rather than earning the
		# daily guarded box. Exercise the channel with another original open box.
		if item.kind=="supply_cache" and item.state=="ready" and game.outpost_walkable(item.position) and game.discoveries.cache_guards.can_open(item_index):
			charging=item
			break
	assert(not charging.is_empty(), "The channel fixture must find a real ready box satisfying the actual guard prerequisite")
	game.hero.position=charging.position;game.move_goal=game.hero.position
	game.scrap=game.run.memory_cost()-46
	assert(game.interact() and charging.state=="channel")
	charging.progress=2.9
	var later: Dictionary=game.discoveries.items.back()
	assert(charging!=later)
	game.discoveries.begin_cooling(later,40)
	game.discoveries.tick(.2)
	assert(game.phase=="night" and game.run.pending==0 and game.scrap>=game.run.memory_cost(),"A cache reward must fund the shared balance without interrupting the night")
	assert(game.request_upgrade() and game.phase=="draft","A funded cache reward must allow an explicit inscription")
	var frozen_later_respawn: float=later.respawn
	game.discoveries.tick(100.0)
	assert(is_equal_approx(later.respawn,frozen_later_respawn),"A cache reward opening cards must freeze later refresh entries")
	print("NIGHTFALL_EXPLORATION_LOOP_OK opening night, refreshing F, milestones, pause/draft clocks, R multi-kill payouts, rapid F protection")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	quit()
