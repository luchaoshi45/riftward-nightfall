extends SceneTree

var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func frames(count: int = 3) -> void:
	for i in count:await process_frame

func key(code: int, echo: bool = false) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code
	event.pressed=true;event.echo=echo
	Input.parse_input_event(event)
	await frames()
	event.pressed=false;event.echo=false
	Input.parse_input_event(event)
	await frames()

func enemy_at(offset: Vector3) -> BattleUnit:
	var enemy: BattleUnit=game.spawn_creature(false)
	enemy.position=game.hero.position+offset
	enemy.max_hp=2000;enemy.hp=2000
	return enemy

func capture(path: String) -> void:
	if DisplayServer.get_name()=="headless":return
	game.hud.queue_redraw()
	await frames(2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	game=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await frames(8)
	game.set_process(false)
	await key(KEY_1)
	assert(game.phase=="night" and game.day_number==1)
	game.begin_day()
	assert(game.phase=="day" and game.day_number==1)
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()
	await frames()
	var inside:=enemy_at(Vector3(2,0,0))
	var outside:=enemy_at(Vector3(8.0*float(game.run.stats.area)+.5,0,0))
	var mana_before: float=game.mana
	var health_before: float=inside.hp
	await key(KEY_R)
	assert(game.cooldowns[3]>0,"First-day KEY_R must release lantern inferno")
	assert(is_equal_approx(game.mana,mana_before-85.0),"R must cost exactly 85 mana")
	assert(is_equal_approx(game.cooldowns[3],28.0*game.run.cooldown_factor()),"R must retain the 28-second base cooldown")
	assert(is_equal_approx(health_before-inside.hp,260.0+float(game.run.stats.spell)*1.2),"R damage must retain its existing balance")
	assert(is_equal_approx(outside.hp,2000.0),"Targets outside R radius must not take damage")
	assert(game.effects.get_node_or_null("LanternInferno")!=null,"Actual KEY_R must create the inferno effect")
	assert(game.hero.hero_action=="inferno","R input must also trigger the character's casting animation")
	await capture("res://build/r-firstday-key.png")
	var mana_after: float=game.mana
	await key(KEY_R)
	assert(is_equal_approx(game.mana,mana_after),"Repeated R cannot consume mana during cooldown")
	assert(game.notice.contains("冷却"),"Cooldown rejection must explain the reason")
	var notice_time: float=game.notice_time
	game.notice_time-=.3
	await key(KEY_R)
	assert(game.notice_time<notice_time,"Repeated cooldown keypresses must not continually refresh the message")
	game.cooldowns[3]=0;game.mana=84
	assert(game.skill_status(3)=="法力不足","R HUD must distinguish insufficient mana from ready")
	await key(KEY_R)
	assert(game.cooldowns[3]==0 and game.mana==84,"Insufficient mana must not start cooldown or consume mana")
	assert(game.notice.contains("法力不足") and game.notice.contains("85"),"Mana rejection must show the required amount")
	if DisplayServer.get_name()!="headless":await create_timer(1.15).timeout
	await capture("res://build/r-mana-hud.png")
	game.mana=300;game.phase="paused"
	game.notice="暂停时保持安静";game.notice_time=1.5
	await key(KEY_R)
	assert(game.cooldowns[3]==0 and game.mana==300 and game.notice=="暂停时保持安静","R input must remain quiet while paused")
	game.phase="draft"
	await key(KEY_R)
	assert(game.cooldowns[3]==0 and game.mana==300,"R cannot release while choosing cards")
	game.phase="night";game.day_number=1
	await key(KEY_R,true)
	assert(game.cooldowns[3]==0,"Held-key echo must not trigger R")
	await key(KEY_R)
	assert(game.cooldowns[3]>0 and game.mana==215,"First-night KEY_R must also release inferno")
	assert(game.skill_status(3).ends_with(" s"),"HUD must show the active cooldown")
	game.cooldowns[3]=0
	assert(game.skill_status(3)=="就绪","HUD must return to ready after cooldown with enough mana")
	game.hero.tick(1.0)
	game.hero.moving=true
	game.hero.set_locomotion_velocity(Vector3(0,0,game.hero.speed))
	game.hero.face(game.hero.position+Vector3.FORWARD*-1,1.0)
	var travel_yaw: float=game.hero.visual.rotation.y
	game.hero.attack_timer=0
	game.auto_attack()
	assert(game.hero.hero_action=="attack","Automatic attacks must trigger the authored attack animation")
	assert(is_equal_approx(game.hero.visual.rotation.y,travel_yaw),"Automatic attacks must preserve travel facing while running")
	print("NIGHTFALL_R_SKILL_CONTROLS_OK")
	quit()
