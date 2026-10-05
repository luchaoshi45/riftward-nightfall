extends SceneTree
## Production regression for the daytime forecast and one-shot countermeasures.

var game: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:return
	failures.append(message)
	push_error(message)

func clear_enemies() -> void:
	for creature in game.enemies:
		if is_instance_valid(creature):creature.queue_free()
	game.enemies.clear()

func press(keycode: Key) -> void:
	var event:=InputEventKey.new()
	event.keycode=keycode;event.physical_keycode=keycode;event.pressed=true;event.echo=false
	game._unhandled_input(event)

func expected_roles(entry: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for role in entry.roles:
		var threat: String="stalker" if String(role)=="basic" else String(role)
		result[threat]=int(result.get(threat,0))+1
	if bool(entry.get("boss_entry",false)):result["breaker"]=int(result.get("breaker",0))+1
	return result

func actual_roles() -> Dictionary:
	var result: Dictionary={}
	for creature in game.enemies:
		if not is_instance_valid(creature) or not creature.alive:continue
		var threat:=String(creature.get_meta("threat",""))
		result[threat]=int(result.get(threat,0))+1
	return result

func run() -> void:
	game=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.set_process(false)
	check(game.choose_card(0) and game.phase=="night","Opening card must enter the first night")
	check(game.countermeasure_active=="" and game.gate_barricade_hp==0.0,"An unselected opening night must not receive a hidden countermeasure")
	# Move through the real night-to-draft transition, then let choose_card call
	# begin_day(), which is the production point where the forecast is created.
	game.phase_time=.01;game.simulate(.02);await process_frame
	check(game.phase=="draft" and game.day_number==2,"A survived night must open the second-night draft")
	check(game.choose_card(0) and game.phase=="day","The second-night draft must enter daytime planning")
	check(game.night_plan.size()==5,"Daytime must save all five waves before the next night")
	var saved_plan: Array[Dictionary]=game.night_plan.duplicate(true)
	check(saved_plan[2].roles.count("lobber")==1 and saved_plan[4].roles.count("lobber")==1,
		"The actual second-day forecast must preserve both planned lobber arrivals")
	check(saved_plan[2].threat=="lobber" and String(saved_plan[2].advice).contains("2米") and String(saved_plan[2].advice).contains("集火"),
		"Saved lobber preview must explain moving out of the landing area and ranged focus")
	check(game.forecast_primary_threat()!="基础夜行体" and game.forecast_specialist_count()>0,"Forecast must expose a real specialist threat")
	check(game.countermeasure_recommended(0) or game.countermeasure_recommended(1) or game.countermeasure_recommended(2),"One countermeasure must match the saved threat plan")

	# Keyboard 8 is a real daytime choice and never spends scrap.
	var scrap_before: int=game.scrap
	press(KEY_8)
	check(game.countermeasure_selected==1 and game.scrap==scrap_before,"Daytime countermeasure selection must be free and visible")
	check(game.night_plan==saved_plan,"Choosing a countermeasure must not reroll the saved night")
	# The player may change their mind before dusk.
	check(game.select_countermeasure(2) and game.countermeasure_selected==2,"Countermeasure choice must remain changeable before dusk")
	check(game.select_countermeasure(1) and game.countermeasure_selected==1,"Changing back must keep the choice idempotent")

	game.start_night()
	check(game.night_plan==saved_plan,"Night start must consume the exact daytime plan")
	check(game.countermeasure_active=="gate_reinforce","Selected south-gate order must activate once at dusk")
	check(is_equal_approx(game.gate_barricade_hp,game.BARRICADE_MAX+260.0),"South-gate order must deploy its free reinforced barricade")
	check(actual_roles()==expected_roles(game.night_plan[0]),"Actual first wave must match the daytime forecast roles")
	check(game.countermeasure_selected==1,"Night HUD state must retain which order was consumed")
	clear_enemies()
	for wave in range(1,5):
		await process_frame
		game.spawn_night_wave()
		check(actual_roles()==expected_roles(saved_plan[wave]),"Every actual later wave must consume the exact daytime roles including lobbers")
		check(game.night_plan==saved_plan,"Consuming a planned wave must not reroll later warnings or their advice")
		clear_enemies()

	# The next daytime plan is generated from the new day number, not silently
	# reused from the previous night.
	game.finish_night();await process_frame
	check(game.phase=="draft" and game.day_number==3,"The second night must lead to the third-night draft")
	check(game.choose_card(0) and game.phase=="day","The third-night draft must reopen daytime planning")
	var third_plan: Array[Dictionary]=game.night_plan.duplicate(true)
	check(third_plan!=saved_plan,"A new day must receive a new deterministic night plan")
	check(game.select_countermeasure(2),"Tower fire order must be selectable in daytime")
	game.start_night()
	check(game.countermeasure_active=="tower_barrage" and game.countermeasure_tower_time>0.0,"Tower fire order must activate a timed buff")
	clear_enemies()
	var pad: Dictionary=game.world.tower_pads[1]
	var target: BattleUnit=game.spawn_creature(true,"basic")
	target.position=pad.position+Vector3(4,0,0);target.position.y=game.outpost_height(target.position)
	var target_hp: float=target.hp
	pad.cooldown=0.0;game.update_towers(.01)
	var buff_damage:=target_hp-target.hp
	target.hp=target_hp;pad.cooldown=0.0;game.countermeasure_tower_time=0.0;game.update_towers(.01)
	var normal_damage:=target_hp-target.hp
	check(buff_damage>normal_damage*1.2,"Tower fire order must increase real tower damage")
	clear_enemies()

	game.finish_night();await process_frame
	check(game.phase=="ended" and game.victory,"The third teaching night must still end the run normally")
	await game.prepare_shutdown();game.queue_free();await process_frame;await create_timer(.15).timeout

	# A fresh production scene verifies the light guard against an actual
	# light-eater aura, rather than only checking its timer label.
	game=load("res://scenes/nightfall.tscn").instantiate();root.add_child(game);current_scene=game
	await process_frame;game.set_process(false)
	check(game.choose_card(0) and game.phase=="night","Fresh run must enter the opening night")
	game.phase_time=.01;game.simulate(.02);await process_frame
	check(game.phase=="draft" and game.choose_card(0) and game.phase=="day","Fresh run must reach daytime forecast")
	check(game.select_countermeasure(0),"Light guard order must be selectable")
	game.start_night();clear_enemies()
	var moth: BattleUnit=game.spawn_creature(true,"light_eater")
	var lamp_point: Vector3=game.world.gate_lights[0].position
	moth.position=Vector3(lamp_point.x,game.outpost_height(lamp_point),lamp_point.z)
	moth.speed=0.0;moth.attack_timer=100.0
	game.simulate(.1)
	var guarded_drain: float=game.world.gate_light_drain[0]
	game.countermeasure_light_time=0.0;game.simulate(.1)
	var normal_drain: float=game.world.gate_light_drain[0]
	check(guarded_drain<normal_drain*.7,"Light guard order must reduce the real light-eater drain")
	clear_enemies();await process_frame
	# Isolate a genuine fourth iron-tide plan, where progressive replacement
	# makes lobbers the most numerous specialist without inventing forecast roles.
	game.run_mode="siege";game.day_number=4;game.phase="day"
	for nest in game.world.nests:nest.cleansed=false
	game.prepare_next_night_plan(true)
	var lobber_plan: Array[Dictionary]=game.night_plan.duplicate(true)
	var specialist_total:=0
	var lobber_total:=0
	for entry: Dictionary in lobber_plan:
		for role in entry.roles:
			if String(role)!="basic":specialist_total+=1
			if String(role)=="lobber":lobber_total+=1
		if bool(entry.boss_entry):specialist_total+=1
	check(lobber_total==10,"Fourth-night iron-tide forecast must expose the actual ten planned lobbers")
	check(game.forecast_primary_threat_id()=="lobber" and game.forecast_primary_threat()=="投蚀体",
		"Primary threat selection and Chinese title must recognize the dominant real lobber role")
	check(game.forecast_specialist_count()==specialist_total,"The daytime specialist count must include real lobbers and the original boss exactly once")
	check(game.countermeasure_recommended(2) and not game.countermeasure_recommended(0) and not game.countermeasure_recommended(1),
		"The actual dominant lobber plan must recommend the visible tower-fire order")
	check(game.night_plan==lobber_plan,"Reading names, counts and recommendations must preserve the saved plan")
	check(game.select_countermeasure(2),"The lobber-recommended order must remain available through the production selection API")
	game.start_night()
	check(game.night_plan==lobber_plan and game.countermeasure_active=="tower_barrage",
		"Night start must consume the same lobber forecast and activate its selected order once")
	clear_enemies()
	for wave in range(1,5):
		await process_frame
		game.spawn_night_wave()
		check(actual_roles()==expected_roles(lobber_plan[wave]),"The dominant-lobber forecast must match its real later births and final boss")
		clear_enemies()
	await game.prepare_shutdown();game.queue_free();await process_frame;await create_timer(.15).timeout
	if failures.is_empty():
		print("NIGHTFALL_NEXT_NIGHT_FORECAST_OK checks=",checks)
		quit(0)
	else:
		print("NIGHTFALL_NEXT_NIGHT_FORECAST_FAILED ",failures)
		quit(1)
