extends SceneTree
## Forward+隐藏窗口验收：首领蓄力、破绽和清场 HUD 必须实际可读。

var game: Node3D
const ROI := Rect2(426,20,588,110)
const CONTENT_VIEWPORT := Vector2i(1920,1200)

func _initialize() -> void:
	root.size=CONTENT_VIEWPORT
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size=CONTENT_VIEWPORT
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.position=Vector2i(-10000,-10000)
		root.hide()
	call_deferred("run")

func frame() -> void:
	game.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw

func photograph(name: String) -> Image:
	for i in 4:await frame()
	var picture: Image=root.get_texture().get_image()
	assert(root.content_scale_size==CONTENT_VIEWPORT and picture.get_size()==root.content_scale_size)
	assert(Vector2(picture.get_size())==game.hud.get_viewport_rect().size)
	assert(picture.save_png("res://build/"+name+".png")==OK)
	return picture

func roi_difference(first: Image, second: Image) -> int:
	var changed: int=0
	var scale:=Vector2(first.get_size())/Vector2(1440,900)
	var pixels:=Rect2i(ROI.position*scale,ROI.size*scale)
	for y in range(pixels.position.y,pixels.end.y):
		for x in range(pixels.position.x,pixels.end.x):
			var a: Color=first.get_pixel(x,y)
			var b: Color=second.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.12:changed+=1
	return changed

func clear_units(keep: BattleUnit = null) -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy) and enemy!=keep:enemy.queue_free()
	game.enemies.clear()
	if is_instance_valid(keep):game.enemies.append(keep)

func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("This test requires Forward+ rendering");quit(1);return
	game=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.set_process(false);game.world.set_process(false)
	game.run_mode="siege";game.run_mode_locked=true;game.day_number=4
	game.start_night();clear_units();game.wave_index=4;game.spawn_night_wave()
	var boss: BattleUnit=null
	for enemy in game.enemies:
		if enemy.get_meta("siege_boss",false):boss=enemy;break
	assert(boss!=null)
	# Use reachable courtyard space outside the blocked core footing. The hero
	# must be inside the actual slam radius for a genuine visible windup.
	boss.position=Vector3(8,5,0);game.hero.position=Vector3(10,5,0);game.move_goal=game.hero.position
	game.hero_path.clear();game.hero_keyboard_active=false;game.hero.moving=false
	assert(game.outpost_walkable(boss.position) and game.outpost_walkable(game.hero.position))
	assert(game.can_traverse(boss.position,game.hero.position))
	assert(boss.position.distance_to(game.hero.position)<=float(game.boss_snapshot().radius))
	game.camera.position=game.hero.position+Vector3(0,25,29);game.camera.look_at(game.hero.position);game.camera.current=true
	game.world.set_night(true);game.world.follow_ashfall(game.hero.position)
	assert(game.siege_boss.advance(8.0))
	assert(game.boss_snapshot().phase=="windup" and (game.boss_snapshot().position as Vector3).is_equal_approx(game.hero.position))
	var windup:=await photograph("nightfall-siege-boss-windup")
	boss.hurt(259.6,game.hero);assert(game.siege_boss.advance(.1))
	assert(game.boss_snapshot().phase=="exposed" and boss.armor==0.0)
	var exposed:=await photograph("nightfall-siege-boss-exposed")
	assert(roi_difference(windup,exposed)>1000,"首领蓄力和破绽 HUD 必须产生可见状态变化")
	var residual: BattleUnit=game.spawn_creature(true,"runner")
	game.register_active_wave_enemy(residual)
	game.wave_index=game.WAVES_PER_NIGHT;game.phase_time=.001;game.simulate(.002)
	assert(game.night_clearance_active and game.final_clearance_active)
	boss.hurt(100000.0,game.hero)
	await photograph("nightfall-siege-boss-clear")
	await game.prepare_shutdown();game.queue_free();await process_frame;await create_timer(.15).timeout
	print("NIGHTFALL_SIEGE_BOSS_VISUAL_OK windup/exposed/clear ROI")
	quit()
