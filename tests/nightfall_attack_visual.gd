extends SceneTree
## Actual-scene rendering and a silent audio-server probe of melee feedback.
var game: Node3D
var failures: Array[String]=[]
var mix_metrics: Dictionary={}
var capture: AudioEffectCapture
var capture_slot: int=-1
var original_basis: Basis

func _initialize() -> void:call_deferred("run")

func check(condition: bool,message: String) -> void:
	if condition:return
	failures.append(message);push_error(message)

func key(code: int,pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event)
	await process_frame

func tap(code: int) -> void:
	await key(code,true);await key(code,false)

func clear_enemies() -> void:
	game.cancel_hero_attack()
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()

func step(delta: float) -> void:
	# Isolate the real player/contact/feedback methods from tower fire and waves.
	# AudioServer still mixes normally while the game clock is controlled.
	game.move_hero(delta);game.hero.tick(delta)
	game.update_hero_attack(delta);game.update_combat_chains(delta)
	game.combat.tick(delta);game.music.update_game(game,delta)
	game.camera.position=game.camera_follow+game.combat.camera_offset()
	game.world.follow_ashfall(game.hero.position)
	game.hud.queue_redraw()

func frame(delta: float=1.0/60.0) -> void:
	step(delta)
	await process_frame

func frames(count: int) -> void:
	for i in count:await frame()

func screenshot(path: String) -> void:
	game.hud.queue_redraw()
	await process_frame;await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(path)==OK,"Save "+path)

func target(hp: float=1000.0) -> BattleUnit:
	var enemy: BattleUnit=game.spawn_creature(false)
	enemy.position=game.hero.position+Vector3(2.2,0,0)
	enemy.hp=hp;enemy.max_hp=hp;enemy.armor=0.0;enemy.shield=0.0
	enemy.speed=0.0;enemy.damage=0.0;enemy.attack_timer=1000.0
	return enemy

func deterministic_critical(wanted: bool) -> void:
	# Keep the real build's crit probability; choose a reproducible random roll.
	var probe:=RandomNumberGenerator.new()
	for candidate in range(1,2001):
		probe.seed=candidate
		if (probe.randf()<float(game.run.stats.crit))==wanted:
			game.rng.seed=candidate;return
	check(false,"Find deterministic critical roll without changing build stats")

func hit(enemy: BattleUnit,critical: bool=false) -> void:
	deterministic_critical(critical)
	game.auto_attack()
	check(game.hero_attack_target==enemy,"The real automatic attack retains its target")
	var before: float=enemy.hp
	var contact_delay: float=game.hero_attack_delay
	check(contact_delay>0.0 and contact_delay<=.1401,"Contact follows the sword action wind-up")
	await frame(contact_delay-.001)
	check(enemy.hp==before,"No actual damage before the contact frame")
	step(.002)
	check(enemy.hp<before,"Actual damage resolves on the contact frame")
	check(game.camera.basis.is_equal_approx(original_basis),"Impact shake never rotates the camera")
	await process_frame

func capture_mix(name: String,expect_signal: bool) -> void:
	await create_timer(.36).timeout
	var buffer:=capture.get_buffer(capture.get_frames_available())
	var square_sum:=0.0
	var peak:=0.0
	for sample in buffer:
		square_sum+=sample.x*sample.x+sample.y*sample.y
		peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	var rms:=sqrt(square_sum/maxf(1.0,float(buffer.size())*2.0))
	mix_metrics[name]={"frames":buffer.size(),"rms":rms,"peak":peak}
	check(buffer.size()>1000,name+": Dummy driver captures actual mixed frames")
	check(peak<.98,name+": output does not clip")
	check(rms>.0001 if expect_signal else peak<.00001,name+": signal or silence matches the game state")

func silent_prepare() -> void:
	game.combat.clear_transients()
	await create_timer(.12).timeout
	capture.clear_buffer()

func run() -> void:
	if DisplayServer.get_name()=="headless":
		print("Attack rendering requires the caller's hidden graphical process")
		quit(1);return
	game=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.set_process(false);game.world.set_process(false)
	game.music.persist_settings=false;game.music.set_muted(false)
	var selection:=0
	for i in game.run.offer.size():
		if game.run.offer[i].id!="tempo":selection=i;break
	check(game.choose_card(selection),"The actual initial card enters the first night")
	clear_enemies()
	game.notice_time=0.0
	game.hero.position=Vector3(0,5,3.1);game.move_goal=game.hero.position
	game.hero_path.clear();game.hero_keyboard_active=false
	game.camera.size=21.0
	game.camera_follow=game.hero.position+Vector3(0,25,29)
	game.camera.position=game.camera_follow
	original_basis=game.camera.basis
	game.world.night_mix=1.0;game.world.apply_lighting()
	await tap(KEY_M)
	check(game.music.muted,"Real M input mutes only background music")
	for i in 90:game.music.update_game(game,1.0/60.0)
	await create_timer(.25).timeout

	var enemy:=target()
	game.hero.attack_timer=0.0
	game.auto_attack()
	check(absf(game.hero_attack_delay-.14)<.001,"The opening basic attack uses a 140 ms contact")
	await frame(.07)
	await screenshot("res://build/attack-feedback-swing.png")
	game.cancel_hero_attack();game.hero.attack_timer=0.0
	game.hero.hero_action="";game.combat.clear_transients()
	await hit(enemy)
	check(game.attack_chain==1,"First contact advances the three-hit sequence")
	await frames(2)
	await screenshot("res://build/attack-feedback-normal.png")
	await frames(47)
	await hit(enemy)
	check(game.attack_chain==2,"Second contact arms the third heavy strike")
	await frames(2)
	await screenshot("res://build/attack-feedback-charged.png")
	await frames(47)
	var before: float=enemy.hp
	await hit(enemy)
	check(absf(before-enemy.hp-game.hero.damage*1.3)<.02,"Real third contact deals its 30 percent bonus")
	check(game.attack_chain==0,"Third contact returns to the first sequence step")
	await frames(2)
	game.camera.size=31.0
	await screenshot("res://build/attack-feedback-impact.png")
	game.camera.size=8.0
	await screenshot("res://build/attack-feedback-impact-close.png")
	game.camera.size=21.0
	await frames(47)
	before=enemy.hp
	await hit(enemy,true)
	check(absf(before-enemy.hp-game.hero.damage*1.75)<.02,"A real critical contact deals its 175 percent damage")
	await frames(2)
	await screenshot("res://build/attack-feedback-critical.png")
	await frames(47)
	clear_enemies();game.combat.clear_transients()
	game.kill_chain=0;game.kill_chain_time=0.0
	game.attack_chain=0;game.attack_chain_time=0.0
	var old_scrap: int=game.scrap
	for i in 3:
		enemy=target(1.0)
		await hit(enemy)
		if i<2:await frames(47)
	check(game.kill_chain==3,"Three actual player attacks grant the personal streak")
	check(game.scrap==old_scrap+8*3+9,"Three-hit kill streak grants normal scrap drops and exactly nine additional scrap")
	await frames(2)
	game.camera.size=31.0
	await screenshot("res://build/attack-feedback-streak.png")
	game.camera.size=21.0
	clear_enemies();game.combat.tick(1.0)
	check(game.combat.camera_offset().is_zero_approx(),"Impact camera shake decays back to zero")

	await tap(KEY_F2)
	check(game.combat.reduced_effects,"Real F2 input enables reduced feedback")
	game.combat.impact(game.hero.position+Vector3.RIGHT*2,Vector3.RIGHT,75,true,true)
	game.combat.tick(.01)
	check(game.combat.camera_offset().is_zero_approx(),"Reduced effects keep camera shake at zero")
	for effect in game.combat.effects:
		if effect.has("light"):check(effect.light.light_energy==0.0,"Reduced effects produce no impact flash light")
		if effect.has("flash"):check(not effect.flash.visible,"Reduced effects hide the flash sphere")
	var start: Vector3=game.hero.position
	await key(KEY_D,true)
	for i in 6:game._process(1.0/60.0);await process_frame
	await key(KEY_D,false)
	game._process(1.0/60.0)
	check(game.hero.position.x>start.x+.65,"Real movement remains responsive during reduced impact feedback")
	check(game.camera.basis.is_equal_approx(original_basis),"Actual gameplay updates keep a fixed camera orientation")
	await tap(KEY_ESCAPE);game._process(1.0/60.0)
	check(game.phase=="paused","Real ESC enters the pause panel")
	await screenshot("res://build/attack-feedback-paused.png")
	check(game.combat.effects.is_empty() and game.combat.floats.is_empty(),"Pause clears transient visuals and world floats")
	await tap(KEY_ESCAPE);game._process(1.0/60.0)
	await tap(KEY_F2)
	check(not game.combat.reduced_effects,"F2 restores complete feedback after pause")
	clear_enemies();game.set_process(false)

	capture=AudioEffectCapture.new();capture.buffer_length=1.0
	capture_slot=AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0,capture,capture_slot)
	await silent_prepare()
	game.combat.impact(game.hero.position+Vector3.RIGHT,Vector3.RIGHT,58,false,false)
	await capture_mix("ordinary_hit",true)
	await silent_prepare()
	game.combat.swing(game.hero.position,Vector3.RIGHT*2,2)
	game.combat.impact(game.hero.position+Vector3.RIGHT,Vector3.RIGHT,75,false,true)
	await capture_mix("heavy_contact",true)
	await silent_prepare()
	game.combat.kill(game.hero.position+Vector3.RIGHT,8)
	await capture_mix("kill_chime",true)
	await silent_prepare()
	game.combat.milestone(3,9)
	await capture_mix("milestone_chime",true)
	await silent_prepare()
	for i in 24:
		game.combat.impact(game.hero.position+Vector3.RIGHT,Vector3.RIGHT,75,true,true)
		game.combat.milestone(3,9)
	check(game.combat.players.size()<=6 and game.combat.effects.size()<=14 and game.combat.floats.size()<=16,"Voice, visual effect and float budgets are bounded")
	await capture_mix("bounded_overlap",true)
	await silent_prepare()
	game.combat.impact(game.hero.position+Vector3.RIGHT,Vector3.RIGHT,58,false,false)
	await tap(KEY_ESCAPE);game._process(1.0/60.0)
	await create_timer(.12).timeout;capture.clear_buffer()
	game.combat.impact(game.hero.position,Vector3.RIGHT,58,false,false)
	await capture_mix("paused_silence",false)
	check(game.combat.effects.is_empty() and game.combat.floats.is_empty(),"Paused calls create no effects or floats")
	await tap(KEY_ESCAPE);game._process(1.0/60.0)
	await silent_prepare()
	game.combat.impact(game.hero.position+Vector3.RIGHT,Vector3.RIGHT,58,false,false)
	game.end_defeat("Silent end-state validation");game._process(1.0/60.0)
	await create_timer(.12).timeout;capture.clear_buffer()
	game.combat.milestone(3,9)
	await capture_mix("ended_silence",false)
	AudioServer.remove_bus_effect(0,capture_slot);capture_slot=-1
	var file:=FileAccess.open("res://build/attack-feedback-mix.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(mix_metrics,"\t"));file.close()
	await game.prepare_shutdown()
	game.queue_free();await process_frame;await process_frame
	if failures.is_empty():print("NIGHTFALL_ATTACK_VISUAL_OK contact=140ms sequence critical kills3 fixed_camera F2 movement silent_mix "+JSON.stringify(mix_metrics))
	quit(0 if failures.is_empty() else 1)

func _finalize() -> void:
	if capture_slot>=0 and capture_slot<AudioServer.get_bus_effect_count(0):AudioServer.remove_bus_effect(0,capture_slot)
