extends SceneTree
## Artificial phase/500-part precision fixtures only; not natural economy or clearance proof.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
const BARRACKS := Vector3(7, 5, -8.5)
const WORKSHOP := Vector3(-7.5, 5, -8)
const FREE_TOWER := Vector3(-7.5, 5, -3.5)
const HOME := Vector3(0, 5, 3.1)
var game: Node3D

func _initialize() -> void:
	root.size=Vector2i(1920,1200)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size=Vector2i(1920,1200)
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.position=Vector2i(-10000,-10000)
		root.hide()
	call_deferred("run")

func key(code: int) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=true
	root.push_input(event,true);await process_frame
	event.pressed=false;root.push_input(event,true);await process_frame

func stand(point: Vector3) -> void:
	point.y=game.outpost_height(point)
	assert(game.outpost_walkable(point),"Precision interaction positions must be outside real building footprints")
	game.hero.position=point;game.move_goal=point;game.hero_path.clear()
	game.hero_keyboard_active=false;game.hero.moving=false
	game.hero.set_locomotion_velocity(Vector3.ZERO)

func capture(label: String, night: bool) -> void:
	if DisplayServer.get_name()=="headless":return
	game.world.set_night(night);game.world.night_mix=1.0 if night else 0.0;game.world.apply_lighting()
	game.camera.size=31;game.camera.position=Vector3(0,5,1)+Vector3(0,25,29)
	game.notice_time=0;game.hud.queue_redraw();await RenderingServer.frame_post_draw
	var actual:=root.get_texture().get_image()
	assert(actual.get_size()==Vector2i(1920,1200),"City capture must use the actual requested content viewport")
	assert(actual.save_png("res://build/city-%s.png" % label)==OK,"Actual city screenshots must save in the local build directory")

func close_game() -> void:
	await game.prepare_shutdown()
	current_scene=null
	game.queue_free()
	for i in 4:await process_frame
	await create_timer(.5).timeout

func run() -> void:
	game=load("res://scenes/nightfall.tscn").instantiate();root.add_child(game);current_scene=game
	for i in 8:await process_frame
	game.set_process(false);game.world.set_process(false)
	assert(game.districts.plots.is_empty(),"A new run must not invent fixed city plots")
	assert(game.choose_card(0) and game.phase=="night")
	assert(game.build_district("barracks"),"Night must permit selecting a free-grid building")
	game.construction.cancel()
	assert(TransitionFixture.finish_for_fixture(game))
	assert(game.choose_card(0) and game.phase=="day")
	# Isolate transactions/regeneration from hostile actors in this precision
	# fixture; clearing actors and seeding funds are not natural-play evidence.
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear();await process_frame
	game.scrap=500
	stand(HOME)
	game.aim=BARRACKS
	await key(KEY_Y)
	assert(game.construction.active,"Y must enter the actual construction mode")
	assert(game.construction.begin("barracks"))
	assert(bool(game.construction.snapshot().valid))
	await key(KEY_F)
	assert(game.districts.plots.size()==1 and game.districts.plots[0].kind=="barracks" and game.scrap==440)
	assert((game.districts.plots[0].position as Vector3).is_equal_approx(BARRACKS),"The real building must use the freely chosen snapped location")
	assert(game.construction.begin("workshop"))
	assert(not bool(game.construction.snapshot().valid) and not game.construction.confirm(),"A different building cannot overlap occupied cells")
	assert(game.districts.plots.size()==1 and game.scrap==440,"Rejected overlap cannot create a plot or charge parts")
	await key(KEY_Y)
	assert(not game.construction.active,"Y must leave construction mode")
	assert(is_equal_approx(game.districts.guard_regen(HOME),3.0))
	game.hero.hp=400;game.simulate(1)
	assert(is_equal_approx(game.hero.hp,400+2.0+float(game.run.stats.regen)+3.0),"Production simulation must add the real barracks regeneration inside the castle")
	stand(Vector3(7,5,-6.65))
	assert(game.districts.nearest()==0 and game.interaction_prompt().contains("F升级80"))
	await key(KEY_F)
	assert(game.districts.plots[0].level==2 and game.scrap==360,"Actual F must charge 80 parts for the selected building upgrade")
	assert(not game.upgrade_district() and game.scrap==360,"A max-level building must reject another charge")
	assert(is_equal_approx(game.districts.guard_regen(HOME),6.0))
	stand(Vector3(-25,0,25));game.hero.hp=400
	assert(is_zero_approx(game.districts.guard_regen(game.hero.position)))
	game.simulate(1)
	assert(is_equal_approx(game.hero.hp,400+2.0+float(game.run.stats.regen)),"Barracks regeneration cannot cover the exterior map")
	stand(HOME)
	game.aim=WORKSHOP
	assert(game.construction.begin("workshop"))
	await key(KEY_F)
	assert(game.districts.plots.size()==2 and game.scrap==300 and game.districts.plots[1].kind=="workshop")
	assert((game.districts.plots[1].position as Vector3).is_equal_approx(WORKSHOP))
	await key(KEY_Y)
	var pad: Dictionary=game.world.tower_pads[1]
	stand(Vector3(-5.5,5,8.65))
	assert(game.nearest_tower_pad()==1 and game.interaction_prompt().contains("升级45"))
	await key(KEY_F);assert(pad.level==2 and game.scrap==255,"F must charge the actual discounted tower upgrade")
	pad.hp-=120;await key(KEY_H)
	assert(game.scrap==237 and pad.hp==pad.max_hp-20,"H must charge the actual discounted repair")
	stand(Vector3(-7.5,5,-6.65))
	assert(game.districts.nearest()==1 and game.districts.plots[1].level==1)
	game.aim=FREE_TOWER
	assert(game.construction.begin("tower") and bool(game.construction.snapshot().valid))
	for blocked_phase: String in ["paused","draft"]:
		game.phase=blocked_phase
		assert(not game.build_district("barracks") and not game.construction.confirm() and not game.upgrade_district(),"Paused/draft must reject both real construction and an otherwise eligible building upgrade")
		assert(game.scrap==237 and game.districts.plots.size()==2 and game.districts.plots[1].level==1)
	game.phase="day";game.construction.cancel()
	await capture("day",false)
	for start: Vector3 in [Vector3(-25,0,25),Vector3(25,0,25),Vector3(0,0,40)]:
		stand(start);game.plan_hero_path(HOME)
		assert(not game.hero_path.is_empty(),"Each exterior approach must retain a home route around freely placed buildings")
		var previous: Vector3=game.hero.position
		for point: Vector3 in game.hero_path:
			assert(game.can_traverse(previous,point));previous=point
	stand(Vector3(-7.5,5,-6.65))
	game.start_night()
	var night_budget: int=game.scrap
	assert(game.phase=="night" and game.districts.nearest()==1)
	await key(KEY_F)
	assert(game.districts.plots[1].level==2 and game.scrap==night_budget-80 and game.districts.tower_cost(75)==60,"Night must allow the real F upgrade and apply the second workshop discount")
	stand(HOME);game.aim=FREE_TOWER
	assert(game.construction.begin("tower") and bool(game.construction.snapshot().valid))
	var tower_count: int=game.world.tower_pads.size()
	await key(KEY_F)
	assert(game.world.tower_pads.size()==tower_count+1 and game.scrap==night_budget-80-48,"Night must confirm a real free-grid tower using the actual 20-percent workshop discount")
	await key(KEY_Y)
	await capture("night",true)
	await close_game()
	game=load("res://scenes/nightfall.tscn").instantiate();root.add_child(game);current_scene=game
	for i in 5:await process_frame
	game.set_process(false)
	assert(game.scrap==90 and game.districts.plots.is_empty(),"A new run must reset paid buildings and resources without fixed empty slots")
	assert(is_zero_approx(game.districts.guard_regen(HOME)) and game.districts.tower_cost(75)==75,"A new run must not inherit city benefits")
	await close_game()
	print("NIGHTFALL_CITY_BUILDING_OK actual_keys free_grid costs healing home_routes night_build new_run_reset")
	quit(0)
