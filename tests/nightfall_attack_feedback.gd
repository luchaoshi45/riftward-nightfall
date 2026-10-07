extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
## Contact, attribution and pause checks in the real playable scene.
var game: Node3D
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func reset_case() -> void:
	game.cancel_hero_attack()
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()
	game.phase="day";game.phase_time=90.0
	game.run=RunBuild.new(402);game.run.stats.crit=0.0
	game.scrap=0;game.kills=0;game.attack_count=0
	game.run.memory_level=0
	game.attack_chain=0;game.attack_chain_time=0.0
	game.kill_chain=0;game.kill_chain_time=0.0
	game.hero.position=Vector3(35,0,35)
	game.move_goal=game.hero.position;game.hero_path.clear()
	game.hero_keyboard_active=false
	game.hero.moving=false;game.hero.set_locomotion_velocity(Vector3.ZERO)
	game.hero.alive=true;game.hero.hp=game.hero.max_hp
	game.hero.damage=100.0;game.hero.attack_interval=.8
	game.hero.attack_timer=0.0;game.hero.hero_action=""
	game.hero.visual_hit_stop=0.0
	game.cooldowns.fill(0.0);game.mana=300.0
	game.combat.reduced_effects=false

func target(offset: Vector3=Vector3.RIGHT*2, hp: float=1000.0) -> BattleUnit:
	var enemy: BattleUnit=game.spawn_creature(false)
	enemy.position=game.hero.position+offset
	enemy.armor=0.0;enemy.shield=0.0;enemy.hp=hp;enemy.max_hp=hp
	enemy.speed=0.0;enemy.damage=0.0;enemy.attack_timer=1000.0
	return enemy

func strike() -> void:
	game.hero.attack_timer=0.0;game.hero.hero_action=""
	game.auto_attack()
	game.update_hero_attack(.15)

func key(code: int, pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	game=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.set_process(false);game.world.set_process(false)
	check(game.choose_card(0),"Opening draft must enter the real playable scene")
	reset_case()
	var enemy:=target()
	game.auto_attack()
	check(game.hero_attack_target==enemy and enemy.hp==1000.0,"A basic swing must queue its original target without instant damage")
	check(absf(game.hero_attack_delay-.14)<.001,"Default attack contact must follow the 140 ms wind-up")
	game.update_hero_attack(.139)
	check(enemy.hp==1000.0 and game.attack_count==0,"The sword must not damage before contact")
	game.update_hero_attack(.002)
	check(enemy.hp==900.0 and game.attack_count==1,"First contact must deliver one normal hit")
	game.update_hero_attack(1.0)
	check(enemy.hp==900.0,"A committed contact must never deliver twice")
	check(enemy.visual_hit_stop>0 and game.hero.visual_hit_stop>0,"A real contact must briefly hold both local impact poses")
	reset_case();enemy=target();game.hero.attack_interval=.36
	game.auto_attack()
	var fast_contact: float=game.hero.hero_action_duration*.20
	check(game.hero_attack_delay==fast_contact and fast_contact<.14,"An attack-speed build must shorten contact and match the actual sword action")
	game.hero.tick(fast_contact-.0005);game.update_hero_attack(fast_contact-.0005)
	check(enemy.hp==1000,"An accelerated swing must still respect its own contact frame")
	game.hero.tick(.001);game.update_hero_attack(.001)
	check(enemy.hp==900,"An accelerated sword action must deliver its contact without a stale default delay")

	reset_case();enemy=target()
	strike();check(enemy.hp==900.0 and game.attack_chain==1,"First successful hit advances to the second strike")
	game.update_combat_chains(.7);strike()
	check(enemy.hp==800.0 and game.attack_chain==2,"Second successful hit arms the third strike")
	game.update_combat_chains(.7);strike()
	check(enemy.hp==670.0 and game.attack_chain==0,"Third successful hit adds 30 percent damage and returns to the opener")
	strike();game.update_combat_chains(2.801)
	check(game.attack_chain==0 and game.attack_chain_time==0,"A 2.8 second interruption must reset the attack chain")

	reset_case();enemy=target()
	game.attack_chain=1;game.attack_chain_time=2.0
	game.auto_attack();enemy.position+=Vector3.RIGHT*8
	var replacement:=target(Vector3.RIGHT)
	game.update_hero_attack(.15)
	check(enemy.hp==1000 and replacement.hp==1000 and game.attack_count==0,"Leaving reach during the wind-up must miss without selecting a replacement")
	check(game.attack_chain==1,"A missed swing must not consume the next successful strike")
	reset_case();enemy=target()
	game.auto_attack();replacement=target(Vector3.RIGHT*3)
	enemy.hurt(1001.0,null)
	game.update_hero_attack(.15)
	check(replacement.hp==1000 and game.attack_count==0 and game.kill_chain==0,"A target killed by another source cancels the pending contact and grants no personal chain")

	reset_case();enemy=target()
	game.attack_chain=1;game.attack_chain_time=1.4
	game.kill_chain=2;game.kill_chain_time=3.5
	game.auto_attack()
	var pending: float=game.hero_attack_delay
	for stopped_phase in ["paused","draft"]:
		game.phase=stopped_phase
		game.simulate(10.0);game.update_hero_attack(10.0)
		check(enemy.hp==1000 and game.hero_attack_delay==pending,"Pause and card selection must preserve the pending contact")
		check(game.attack_chain_time==1.4 and game.kill_chain_time==3.5,"Pause and card selection must preserve both chain windows")
	game.phase="day";game.update_hero_attack(.15)
	check(enemy.hp==900 and game.attack_chain==2,"Resuming must submit the preserved strike exactly once")

	reset_case();enemy=target()
	game.auto_attack();game.aim=enemy.position
	check(game.cast(3),"R must remain available during a basic wind-up")
	var hp_after_r: float=enemy.hp
	game.update_hero_attack(1.0);game.hero.attack_timer=0.0;game.auto_attack()
	check(game.hero.hero_action=="inferno" and game.hero_attack_target==null,"R must cancel an old contact and prevent new basics from stealing its cast")
	check(enemy.hp==hp_after_r and game.kill_chain==0,"No stale basic damage or personal-chain credit may follow R")

	# Lethal contacts pay one shared balance. Income alone must never queue cards.
	reset_case()
	var bonus_scrap:=0
	for i in range(1,12):
		var before_scrap: int=game.scrap
		var before_pending: int=game.run.pending
		target(Vector3.RIGHT*2,1.0);strike()
		var extra_scrap:=9 if i==3 else (14 if i==6 else (22 if i==10 else 0))
		bonus_scrap+=extra_scrap
		check(game.kill_chain==i and is_equal_approx(game.kill_chain_time,6.0),"Only a lethal personal contact may advance the six second kill chain")
		check(game.scrap-before_scrap==5+extra_scrap,"Milestone %d must grant its exact scrap reward once" % i)
		check(game.run.pending==before_pending and game.phase=="day","Kill income must not debit scrap, queue growth or force a draft")
	check(bonus_scrap==45,"The three personal-chain thresholds grant exactly 45 additional scrap in total")
	game.phase="day";game.update_combat_chains(6.001)
	check(game.kill_chain==0,"A six second kill-chain interruption must expire")
	target(Vector3.RIGHT*2,1.0);strike()
	check(game.kill_chain==1,"A kill after expiration must start a fresh chain")

	reset_case();enemy=target(Vector3.RIGHT*2,1.0)
	game.aim=enemy.position;check(game.cast(0),"Q must execute on its own")
	check(game.kills==1 and game.kill_chain==0,"A skill kill must grant its ordinary reward without a personal attack chain")
	game.hero.hero_action="";game.cooldowns[0]=0.0
	enemy=target(Vector3.RIGHT*2,1.0);enemy.hurt(100.0,null)
	check(game.kill_chain==0,"A non-hero source kill must not count as a personal attack")

	reset_case();game.run.owned["chain"]=1;game.run.stats.crit=0.0
	game.attack_count=2;game.attack_chain=2;game.attack_chain_time=1.0
	target(Vector3.RIGHT*2,1.0);target(Vector3(3,0,.3),1.0);target(Vector3(3,0,-.3),1.0)
	game.scrap=184
	strike()
	check(game.kills==3 and game.kill_chain==3,"Third-strike chain attachments retain their personal kill rewards")
	check(game.scrap==208 and game.run.pending==0 and game.phase=="day","Enough shared scrap must remain unspent until the player explicitly requests growth")
	await key(KEY_V,true);await key(KEY_V,false)
	check(game.phase=="draft" and game.scrap==88 and game.run.pending==1 and game.run.memory_level==1,
		"Real V pays exactly 120 shared scrap and opens one upgrade")
	var kills_before: int=game.kills
	game.auto_attack();game.update_hero_attack(1.0)
	check(game.kills==kills_before and game.hero_attack_target==null,"The manually paid draft must not resubmit the lethal contact")
	check(game.choose_card(0) and game.scrap==88 and game.run.pending==0 and game.phase=="day",
		"Selecting the already paid card must resume gameplay without charging again")

	reset_case();enemy=target(Vector3.RIGHT*2,25.0)
	game.hero.hp=400;game.run.stats.lifesteal=.5
	strike()
	check(game.hero.hp==412.5,"Attack lifesteal must heal only the 25 actual HP removed, never overkill damage")

	reset_case();enemy=target();game.combat.reduced_effects=true
	strike()
	check(game.hero.visual_hit_stop==0 and enemy.visual_hit_stop==0,"Reduced effects must remove the local impact hold")
	check(game.combat.camera_offset().length()<.0001,"Reduced effects must remove impact camera motion")
	check(Engine.time_scale==1.0,"Combat feedback must never slow the whole game clock")
	reset_case();enemy=target()
	strike()
	var before: Vector3=game.hero.position
	await key(KEY_D,true)
	game.simulate(1.0/60.0)
	await key(KEY_D,false)
	check(game.hero.position.distance_to(before)>.10,"Local pose hold must leave movement and real keyboard input responsive")
	check(game.hero.attack_timer<.8,"Local pose hold must not freeze the attack cooldown")
	for i in 32:game.combat.impact(game.hero.position+Vector3.UP,Vector3.RIGHT,10.0,false,false)
	check(game.combat.floats.size()<=16,"Crowded combat must cap damage floats at 16")
	for effect in game.combat.effects:
		for mesh in effect.node.find_children("*","MeshInstance3D",true,false):
			check(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Melee feedback geometry must not cast moving sliver shadows")
	var last_offset: Vector3=game.combat.camera_offset()
	for frame_index in 45:
		game.combat.tick(1.0/120.0)
		var offset: Vector3=game.combat.camera_offset()
		check(offset.length()<.075 and offset.distance_to(last_offset)<.016,"The strongest impact must keep low-frequency camera translation smooth and bounded")
		last_offset=offset
	game.combat.tick(5.0)
	check(game.combat.floats.is_empty(),"Damage floats must expire instead of accumulating permanently")
	reset_case();enemy=target()
	game.attack_chain=2;game.attack_chain_time=1.0
	game.kill_chain=5;game.kill_chain_time=4.0
	game.auto_attack();game.start_night()
	check(game.phase=="night" and game.hero_attack_target==null and game.hero_attack_delay==0,"A new night must discard the previous daytime wind-up")
	check(game.attack_chain==0 and game.attack_chain_time==0 and game.kill_chain==0 and game.kill_chain_time==0,"A new night must reset both attack and personal-kill chains")
	game.attack_chain=2;game.attack_chain_time=1.0
	game.kill_chain=5;game.kill_chain_time=4.0
	game.day_number=1;TransitionFixture.finish_for_fixture(game)
	check(game.phase=="draft" and game.attack_chain==0 and game.kill_chain==0 and game.hero_attack_target==null,"Surviving the night must start its dawn draft without stale attack chains or pending contact")
	print("NIGHTFALL_ATTACK_FEEDBACK_", "OK" if failures.is_empty() else "FAILED", " contact=140ms single_commit three_strikes miss attribution milestones draft pause ultimate_priority lifesteal movement feedback_budget")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit(0 if failures.is_empty() else 1)
