extends SceneTree
## Production bridge for the optional opening contract. Rescue movement reuses
## the real expedition route; only the final-night state is arranged so the
## archive bridge can be checked without pretending to be a natural victory.

const RunArchive = preload("res://scripts/run_archive.gd")
const RunSession = preload("res://scripts/run_session.gd")
const STEP := .04
const HOME := Vector3(0, 5, 3.1)
const CONTRACT_RECT := Rect2(205,700,1025,38)

var checks := 0
var failures: Array[String] = []
var profile_path := "user://riftward-opening-contract-%d.json" % Time.get_ticks_usec()

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:return
	failures.append(message)
	push_error(message)

func clear_enemies(game: Node3D) -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy):enemy.queue_free()
	game.enemies.clear()

func press(game: Node3D, code: int) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=true
	game._unhandled_input(event)
	event.pressed=false;game._unhandled_input(event)

func escort_home(game: Node3D, camp: Dictionary) -> void:
	game.plan_hero_path(HOME)
	var npc: BattleUnit=camp.npc
	for step in 1800:
		game.move_hero(STEP)
		game.expeditions.tick(STEP)
		if camp.state=="delivered":break
	check(camp.state=="delivered" and npc.position.y>4.8,
		"The selected opening contract must use the real south-gate escort route")

func rescue_both(game: Node3D) -> void:
	game.begin_day()
	clear_enemies(game)
	for camp: Dictionary in game.expeditions.camps:
		game.hero.position=camp.position;game.move_goal=game.hero.position
		check(game.interact() and camp.state=="escort","Each contract scout must be recruited through the real interaction")
		for guard in camp.guards:
			if is_instance_valid(guard) and guard.alive:guard.hurt(10000.0,game.hero)
		clear_enemies(game)
		escort_home(game,camp)
	check(game.survivors_rescued==2,"Two actual deliveries must advance the contract progress")

func prepare_final_victory(game: Node3D) -> void:
	clear_enemies(game)
	game.set_process(false);game.world.set_process(false)
	game.day_number=game.max_nights()
	game.phase="night";game.return_phase="night";game.phase_time=0.0
	game.wave_index=game.WAVES_PER_NIGHT
	game.world.set_night(true)
	game.begin_night_clearance()

func close_game(game: Node3D) -> void:
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.35).timeout

func cleanup_profile() -> void:
	for candidate in [profile_path,profile_path+".tmp",profile_path+".bak",profile_path+".incomplete",profile_path+".incomplete.bak",profile_path+".incomplete.tmp"]:
		if FileAccess.file_exists(candidate):DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))

func run_selected_contract() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.set_process(false);game.world.set_process(false)
	check(game.phase=="draft" and game.opening_night_pending,"The production scene must expose the opening draft")
	check(game.opening_contract_summary().status=="未选择","A new seed starts without a contract")
	# Test the actual mouse hit region as well as the keyboard shortcut.
	var event:=InputEventMouseButton.new()
	event.position=CONTRACT_RECT.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900);event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	game.hud._gui_input(event)
	event.pressed=false;game.hud._gui_input(event)
	check(game.opening_contract_id=="homecoming_pair","The C contract entry must be selectable by mouse")
	press(game,KEY_C)
	check(game.opening_contract_id.is_empty(),"C must toggle the optional contract before lock-in")
	press(game,KEY_C)
	check(game.opening_contract_id=="homecoming_pair","C must restore the same contract choice")
	check(game.choose_card(0) and game.phase=="night","Choosing a card must start the real night")
	check(game.opening_contract_locked and not game.toggle_opening_contract(),"The contract must lock with the opening core")
	rescue_both(game)
	game.archive=RunArchive.new(profile_path,true)
	prepare_final_victory(game)
	game.finish_night()
	check(game.phase=="ended" and game.victory and game.opening_contract_completed,"Only the real final-clearance path may complete the contract")
	check(game.archive.has_challenge("homecoming_pair"),"Two actual rescue returns plus final victory must unlock the archive challenge")
	check(game.archive.snapshot().run_history.size()==1 and bool(game.archive.snapshot().run_history[0].contract_completed),"History must preserve the completed contract state")
	await close_game(game)

func run_incomplete_contract() -> void:
	var path:=profile_path+".incomplete"
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.set_process(false);game.world.set_process(false)
	check(game.toggle_opening_contract() and game.choose_card(0),"A second run can select and lock the same contract")
	game.survivors_rescued=1
	game.archive=RunArchive.new(path,true)
	prepare_final_victory(game)
	game.finish_night()
	check(game.victory and not game.opening_contract_completed,"A main victory must remain possible when only one scout returns")
	check(not game.archive.has_challenge("homecoming_pair"),"An incomplete contract must not unlock the archive")
	check(game.archive.snapshot().run_history[0].contract_id=="homecoming_pair" and not bool(game.archive.snapshot().run_history[0].contract_completed),"Incomplete contract history must remain explicit")
	await close_game(game)

func run_session_contract() -> void:
	check(RunSession.queue_request(self,20261012,"siege","homecoming_pair"),"Same-seed retry must accept the contract id")
	var request:=RunSession.consume_request(self)
	check(request.contract_id=="homecoming_pair","The scene handoff must preserve the same-seed contract")
	check(RunSession.queue_request(self,20261012,"siege"),"A new-seed request without a contract remains valid")
	request=RunSession.consume_request(self)
	check(String(request.get("contract_id",""))=="","A new-seed request must be able to clear the contract")
	check(not RunSession.queue_request(self,20261012,"siege","unknown"),"Unknown contract ids must be rejected at the session boundary")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	cleanup_profile()
	run_session_contract()
	await run_selected_contract()
	await run_incomplete_contract()
	cleanup_profile()
	print("NIGHTFALL_OPENING_CONTRACT_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAILED",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
