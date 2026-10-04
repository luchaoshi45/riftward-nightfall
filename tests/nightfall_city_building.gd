extends SceneTree
var game: Node3D
func _initialize() -> void:call_deferred("run")
func key(code: int) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true
	Input.parse_input_event(event);await process_frame
	event.pressed=false;Input.parse_input_event(event);await process_frame
func stand(point: Vector3) -> void:
	game.hero.position=point;game.move_goal=point;game.hero_path.clear()
func capture(label: String, night: bool) -> void:
	if DisplayServer.get_name()=="headless":return
	game.world.set_night(night);game.world.night_mix=1.0 if night else 0.0;game.world.apply_lighting()
	game.camera.size=31;game.camera.position=Vector3(0,5,1)+Vector3(0,25,29)
	game.notice_time=0;game.hud.queue_redraw();await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/city-%s.png" % label)
func run() -> void:
	game=load("res://scenes/nightfall.tscn").instantiate();root.add_child(game);current_scene=game
	for i in 8:await process_frame
	game.set_process(false);game.choose_card(0)
	assert(game.districts.plots.size()==2)
	stand(game.districts.plots[0].position)
	assert(not game.build_district("barracks") and game.scrap==90,"Night construction must be refused")
	game.finish_night();game.choose_card(0)
	for enemy in game.enemies:enemy.queue_free()
	game.enemies.clear();await process_frame
	game.scrap=500
	await key(KEY_1)
	assert(game.districts.plots[0].kind=="barracks" and game.scrap==440)
	assert(not game.build_district("workshop") and game.scrap==440,"Built plot cannot be switched for another benefit")
	game.hero.hp=400;game.simulate(1)
	assert(is_equal_approx(game.hero.hp,405),"Production simulation must add three health per second at home")
	await key(KEY_3);assert(game.districts.plots[0].level==2 and game.scrap==360)
	assert(not game.upgrade_district() and game.scrap==360)
	stand(Vector3(0,0,30));game.hero.hp=400;game.simulate(1)
	assert(is_equal_approx(game.hero.hp,402),"Barracks cannot heal the entire map")
	stand(game.districts.plots[1].position);await key(KEY_2)
	assert(game.scrap==300 and game.districts.plots[1].kind=="workshop")
	var pad: Dictionary=game.world.tower_pads[1]
	stand(pad.position);assert(game.interaction_prompt().contains("升级45"))
	await key(KEY_F);assert(pad.level==2 and game.scrap==255,"F must charge the actual discounted upgrade")
	pad.hp-=120;await key(KEY_H)
	assert(game.scrap==237 and pad.hp==pad.max_hp-20,"H must charge the actual discounted repair")
	stand(game.districts.plots[1].position);await key(KEY_3)
	assert(game.scrap==157 and game.districts.tower_cost(75)==60)
	game.phase="paused";assert(not game.build_district("barracks") and not game.upgrade_district())
	game.phase="day";await capture("day",false)
	for start in [Vector3(-25,0,25),Vector3(25,0,25),Vector3(0,0,40)]:
		stand(start);game.plan_hero_path(Vector3(0,5,2))
		assert(not game.hero_path.is_empty())
		var previous: Vector3=start
		for point in game.hero_path:assert(game.can_traverse(previous,point));previous=point
	stand(game.districts.plots[0].position);game.start_night();await capture("night",true)
	assert(not game.upgrade_district())
	await game.prepare_shutdown();game.queue_free()
	for i in 4:await process_frame
	game=load("res://scenes/nightfall.tscn").instantiate();root.add_child(game);current_scene=game
	for i in 5:await process_frame
	game.set_process(false)
	assert(game.scrap==90 and game.districts.plots[0].level==0 and game.districts.plots[1].level==0,"New run resets all construction and resources")
	await game.prepare_shutdown();game.queue_free()
	for i in 4:await process_frame
	print("NIGHTFALL_CITY_BUILDING_OK actual_keys costs healing plots home_routes new_run_reset");quit()
