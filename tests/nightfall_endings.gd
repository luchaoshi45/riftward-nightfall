extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")

var failures: Array[String] = []
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	push_error(message)

func _initialize() -> void:
	call_deferred("run")

func make_final_night() -> Node3D:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.set_process(false);game.world.set_process(false)
	check(game.choose_card(0), "The actual opening card must start its production night")
	for creature in game.enemies:
		if is_instance_valid(creature):creature.queue_free()
	game.enemies.clear()
	game.day_number=game.max_nights()
	game.phase="night"
	game.world.set_night(true)
	game.world._process(6.0)
	return game

func capture(game: Node3D, name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	game.set_process(false)
	game.world.set_process(false)
	game.world._process(6.0)
	game.hud.queue_redraw()
	await create_timer(.2).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://build/"+name+".png")==OK,
		"The actual ending capture must save successfully: "+name)

func close_game(game: Node3D) -> void:
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5,true,false,true).timeout

func run() -> void:
	var signal_game: Node3D=await make_final_night()
	for nest in signal_game.world.nests:nest.cleansed=true
	check(TransitionFixture.finish_for_fixture(signal_game), "Artificial final-night setup must invoke the real completion lifecycle")
	check(signal_game.victory and signal_game.ending_key=="signal", "The precision cleared-nest fixture selects the production signal ending")
	check(signal_game.phase=="ended" and signal_game.remaining_nests()==0, "Signal victory ends the actual scene with all three nests sealed")
	check(signal_game.world.beacon_light.light_color==Color("96d9d6"), "The real signal result updates the beacon color")
	await capture(signal_game,"ending-signal")
	await close_game(signal_game)
	var hold_game: Node3D=await make_final_night()
	hold_game.world.nests[0].cleansed=true
	check(TransitionFixture.finish_for_fixture(hold_game), "Artificial hold fixture reaches the production completion lifecycle")
	check(hold_game.victory and hold_game.ending_key=="hold", "Uncleared nests select the real hold ending")
	check(hold_game.remaining_nests()==2, "The hold result preserves its actual two unsealed nests")
	await capture(hold_game,"ending-hold")
	var notice: String=hold_game.notice
	hold_game.end_defeat("测试失守")
	check(hold_game.phase=="ended" and hold_game.victory and hold_game.ending_key=="hold" and hold_game.notice==notice,
		"Repeated defeat after an ended victory must retain its original result and notice")
	await close_game(hold_game)
	# Lethal production damage is a precision failure probe, not a natural run.
	var defeat_game: Node3D=await make_final_night()
	var beacon_before: float=defeat_game.beacon_hp
	var loss: float=defeat_game.apply_beacon_damage(100000.0,"结局精度验证 · 灯塔失守")
	check(is_equal_approx(loss,beacon_before) and defeat_game.beacon_hp==0.0,
		"Real lethal beacon damage reports the actual remaining health loss")
	check(defeat_game.phase=="ended" and not defeat_game.victory and defeat_game.ending_key=="defeat",
		"Real lethal beacon damage enters the production failure result")
	check(not TransitionFixture.finish_for_fixture(defeat_game) and not defeat_game.victory,
		"Artificial lifecycle setup must reject failure rather than revive it")
	await capture(defeat_game,"ending-defeat")
	await close_game(defeat_game)
	if failures.is_empty(): print("NIGHTFALL_ENDINGS_OK checks=%d failures=0" % checks)
	else: print("NIGHTFALL_ENDINGS_FAILED checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
