extends SceneTree
## Controlled wallet, vehicle and stage fixtures; not a natural economy or balance run.
const Crate = preload("res://scripts/outpost_supply_crate.gd")
var game: Node3D
var checks := 0
var failures := 0
func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("Vehicle recycling watchdog"); quit(2))
	call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func press(code: int) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event,true)
		await process_frame
func vehicle(revealed: bool = true) -> Node3D:
	var item := Crate.new()
	item.setup(game.supply_crate_serial,"tower","光炮塔")
	game.supply_crate_serial += 1
	item.position = Vector3(10,5,10)
	game.add_child(item)
	game.supply_crates.append(item)
	if revealed:item.reveal()
	return item
func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	game.archive.enabled = false
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	while game.phase == "draft":game.choose_card(0)
	game.phase = "day"
	game.clear_supply_crates(true)
	game.scrap = 100
	var sealed := vehicle(false)
	check(not game.select_construction_vehicle(sealed),"Sealed boxes cannot be selected for salvage")
	game.selected_construction_vehicle = sealed
	check(not game.recycle_selected_vehicle() and not game.recycle_selected_vehicle() and game.scrap == 100,"Even forged sealed selection cannot salvage an unrevealed reward")
	sealed.reveal()
	game.select_construction_vehicle(sealed)
	await press(KEY_DELETE)
	check(game.scrap == 100 and sealed in game.supply_crates and not sealed.opened,"First real Delete only requests confirmation")
	check(game.hud.supply_reward_instruction(true).contains("Del回收8光"),"Selected reward exposes real salvage price")
	await press(KEY_BACKSPACE)
	check(game.scrap == 108 and sealed not in game.supply_crates and game.selected_construction_vehicle == null,"Mac Backspace confirms exactly eight light and releases slot")
	await press(KEY_DELETE)
	check(not game.recycle_selected_vehicle() and game.scrap == 108,"Repeated key or direct call cannot pay twice")
	var first := vehicle()
	var second := vehicle()
	game.select_construction_vehicle(first)
	check(not game.recycle_selected_vehicle(),"First object enters confirmation")
	game.select_construction_vehicle(second)
	check(not game.recycle_selected_vehicle() and second in game.supply_crates,"Changing object cannot reuse another confirmation")
	game.select_construction_vehicle(first)
	check(not game.recycle_selected_vehicle(),"Returning to original object needs new confirmation")
	game.advance_supply_crates(3.1)
	check(not game.recycle_selected_vehicle() and game.scrap == 108,"Three game seconds expire confirmation without payment")
	game.phase = "paused"
	game.advance_supply_crates(10)
	check(not game.recycle_selected_vehicle(),"Pause cannot recycle")
	game.phase = "day"
	check(game.recycle_selected_vehicle() and game.scrap == 116,"Pause freezes confirmation timer rather than consuming game seconds")
	game.select_construction_vehicle(second)
	for state: String in ["draft","ended","paused"]:
		game.phase = state
		await press(KEY_DELETE)
		check(not game.recycle_selected_vehicle() and second in game.supply_crates and game.scrap == 116,"Non-playing state rejects recycling: "+state)
	game.phase = "day"
	for flag: String in ["quitting","restart_pending","shutting_down"]:
		game.set(flag,true)
		check(not game.recycle_selected_vehicle(),"Shutdown boundary rejects recycling: "+flag)
		game.set(flag,false)
	game.select_construction_vehicle(second)
	game.recycle_selected_vehicle()
	game.clear_supply_crates(false)
	check(not game.recycle_selected_vehicle() and second in game.supply_crates,"Day/night cleanup clears confirmation while retaining the vehicle")
	game.select_construction_vehicle(null)
	game.select_construction_vehicle(second)
	game.recycle_selected_vehicle()
	game.supply_crates.erase(second)
	check(not game.recycle_selected_vehicle() and game.scrap == 116,"Roster removal invalidates confirmation")
	game.supply_crates.append(second)
	game.select_construction_vehicle(null)
	game.select_construction_vehicle(second)
	game.recycle_selected_vehicle()
	game.remove_child(second)
	var foreign := Node3D.new()
	root.add_child(foreign)
	foreign.add_child(second)
	check(not game.recycle_selected_vehicle() and game.scrap == 116,"Foreign controller object cannot salvage through stale roster")
	foreign.remove_child(second)
	game.add_child(second)
	foreign.queue_free()
	game.select_construction_vehicle(second)
	game.hud.detail_tab = "army"
	check(not game.recycle_selected_vehicle(),"Open details cannot salvage behind overlay")
	game.hud.detail_tab = ""
	game.hud.map_expanded = true
	check(not game.recycle_selected_vehicle(),"Open map cannot salvage behind overlay")
	game.hud.map_expanded = false
	game.music_credits_open = true
	check(not game.recycle_selected_vehicle(),"Music credits cannot salvage behind overlay")
	game.music_credits_open = false
	game.rally.active = true
	check(not game.recycle_selected_vehicle(),"Rally placement cannot recycle selected vehicle")
	game.rally.cancel_setting()
	game.scrap = 0
	check(not game.deploy_selected_vehicle() and game.construction.active,"Insufficient money opens original grid preview without consuming car")
	await press(KEY_DELETE)
	check(game.construction.active and game.construction.sell_mode and second in game.supply_crates and game.scrap == 0,"Delete during grid preview retains original demolition priority")
	check(not game.recycle_selected_vehicle(),"Direct recycling also rejects active construction")
	game.construction.cancel()
	game.clear_supply_crates(true)
	await process_frame
	game.phase = "day"
	var chosen := vehicle()
	vehicle()
	vehicle()
	game.tech_supply_pending = true
	game.supply_crate_clock = game.SUPPLY_CRATE_INTERVAL
	check(not game._spawn_supply_crate() and game.tech_supply_pending,"Full roster holds discovered technology")
	game.select_construction_vehicle(chosen)
	await press(KEY_DELETE)
	await press(KEY_DELETE)
	check(game.scrap == 8 and game.supply_crates.size() == 2 and game.tech_supply_pending,"Confirmed salvage frees one slot without spending technology request")
	game.advance_supply_crates(.05)
	check(game.supply_crates.size() == 3 and not game.tech_supply_pending,"Freed slot receives physical technology through existing due delivery")
	var delivered: Node3D = game.supply_crates.back()
	check(delivered.supply_kind == "workshop" and not delivered.revealed and game.scrap == 8,"Delivery is sealed technology, no free building and no extra cash")
	game.select_construction_vehicle(delivered)
	delivered.reveal()
	game.select_construction_vehicle(delivered)
	game.recycle_selected_vehicle()
	game.clear_supply_crates(true)
	check(game.vehicle_recycle_id == 0 and game.vehicle_recycle_time == 0 and game.supply_crates.is_empty(),"Terminal/retry clear removes roster and pending salvage confirmation")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_VEHICLE_RECYCLING_%s checks=%d failures=%d" % ["OK" if failures == 0 else "FAILED",checks,failures])
	quit(0 if failures == 0 else 1)
