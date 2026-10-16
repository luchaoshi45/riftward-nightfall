extends SceneTree
## Controlled technology/economic/lifecycle fixtures, not natural economy or balance.
const Crate = preload("res://scripts/outpost_supply_crate.gd")
const Catalog = preload("res://scripts/outpost_catalog.gd")
var game: Node3D
var checks := 0
var failures := 0
func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): push_error("Technology supply watchdog expired"); quit(2))
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func vehicle(kind: String) -> Node3D:
	var item := Crate.new()
	item.setup(game.supply_crate_serial, kind, kind)
	game.supply_crate_serial += 1
	item.position = Vector3(10,5,10)
	game.add_child(item)
	game.supply_crates.append(item)
	return item
func legal(kind: String) -> Vector3:
	for z in range(-18,19):
		for x in range(-18,19):
			var result: Dictionary = game.construction.validity(Vector3(x,5,z),-1,kind)
			if result.valid:return result.point
	return Vector3.INF
func run() -> void:
	game = load("res://scenes/nightfall.tscn").instantiate()
	game.archive.enabled = false
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.clear_supply_crates(true)
	game.phase = "day"
	var original_money: int = game.scrap
	var site: Dictionary = game.expeditions.generators[0]
	game.expeditions.complete_generator(site)
	check(not game.tech_supply_pending and game.scrap == original_money,"Inactive generator cannot locate supplies or pay")
	check(game.expeditions.start_generator(0),"Real generator activation creates guarded encounter")
	game.expeditions.complete_generator(site)
	check(not game.tech_supply_pending,"Uncharged generator cannot locate supplies")
	site.progress = game.expeditions.HOLD_SECONDS
	game.expeditions.complete_generator(site)
	check(not game.tech_supply_pending and game.generator_cells == 0,"Living real guards prevent location and completion")
	for guard: BattleUnit in site.guards.duplicate():
		if is_instance_valid(guard) and guard.alive:guard.hurt(100000.0,game.hero)
	var guarded_money: int = game.scrap
	var stale: Dictionary = site.duplicate()
	game.expeditions.complete_generator(stale)
	check(not game.tech_supply_pending and game.scrap == guarded_money,"Copied non-owned site cannot issue technology location")
	site.progress = 0.0
	game.expeditions.complete_generator(site)
	check(not game.tech_supply_pending,"Cleared guards alone do not bypass hold progress")
	site.progress = game.expeditions.HOLD_SECONDS
	game.phase = "paused"
	game.expeditions.complete_generator(site)
	check(not game.tech_supply_pending,"Paused generator completion cannot locate")
	game.phase = "day"
	game.expeditions.complete_generator(site)
	check(site.state == "complete" and game.generator_cells == 1,"Qualified original generator really completes")
	check(game.tech_supply_pending and game.tech_supply_day == game.day_number,"Real completion locates one technology delivery")
	check(game.scrap == guarded_money + 100,"Location adds no currency beyond original 100 generator reward")
	game.expeditions.complete_generator(site)
	check(game.scrap == guarded_money + 100 and not game.locate_tech_supply(),"Duplicate completion/location cannot pay or locate twice same day")
	check(game.hud.supply_crate_navigation_label().contains("科技待配送"),"Navigation preserves discovered pending technology after toast expires")
	var rng_state: int = game.rng.state
	for repeat in 20:
		check(game._roll_supply_reward().kind == "workshop","Missing workshop receives priority over ordinary flag/tower lottery")
	check("laboratory" not in game._tech_supply_candidates() and "armory" not in game._tech_supply_candidates(),"Missing prerequisites cannot enter priority technology pool")
	check(game.rng.state == rng_state and game.tech_supply_pending,"Reward inspection preserves encounter random stream and pending request")
	var workshop_car := vehicle("workshop")
	check(game._roll_supply_reward().kind == "barracks","Existing sealed workshop vehicle prevents duplicate workshop delivery")
	workshop_car.queue_free()
	await process_frame
	check(game._roll_supply_reward().kind == "workshop","Retired vehicle cannot reserve missing technology")
	game.supply_crates.clear()
	for index in 3:vehicle("tower")
	check(not game._spawn_supply_crate() and game.tech_supply_pending,"Full delivery roster retains pending technology request")
	check(game.hud.supply_crate_navigation_label().contains("部署腾位"),"Full roster explains how to free delivery capacity")
	game.clear_supply_crates(false)
	check(game.tech_supply_pending and game.tech_supply_day == game.day_number,"Day/night cleanup preserves unfulfilled request and daily stamp")
	for item: Node3D in game.supply_crates:item.queue_free()
	game.supply_crates.clear()
	await process_frame
	var navigation: AStarGrid2D = game.hero_navigation
	game.hero_navigation = null
	check(not game._spawn_supply_crate() and game.tech_supply_pending,"No navigable spawn retains pending location")
	game.hero_navigation = navigation
	var wallet: int = game.scrap
	check(game._spawn_supply_crate(),"Qualified request spawns real nearby physical box")
	check(not game.tech_supply_pending and game.supply_crates.size() == 1,"Successful physical delivery consumes location once")
	check(not game.hud.supply_crate_navigation_label().contains("科技待配送"),"Successful delivery clears pending navigation without leaking sealed reward")
	if not game.supply_crates.is_empty():
		var box: Node3D = game.supply_crates[0]
		check(box.supply_kind == "workshop" and not box.revealed,"Technology reward is sealed workshop box rather than free structure")
		check(game.can_traverse(game.hero.position,box.position),"Delivered box has actual traversable connection")
		check(not game.districts.has_live("workshop") and game.scrap == wallet,"Delivery does not grant building or deduct money")
		game.plan_hero_path(box.position)
		for step in 220:
			game.move_hero(.05)
			game._try_open_supply_crates()
			if box.revealed:break
		check(box.revealed,"Real hero movement and contact reveal technology without interaction key")
		check(game.select_construction_vehicle(box),"Revealed technology vehicle uses original selection")
		game.scrap = 1000
		var destination := legal("workshop")
		check(destination.is_finite(),"Fixture has legal workshop grid footprint")
		if destination.is_finite():box.position = destination
		game.scrap = 0
		check(not game.deploy_selected_vehicle() and box in game.supply_crates and game.scrap == 0,"Lack of light rejects paid deployment without consuming reward")
		game.construction.cancel()
		check(box in game.supply_crates,"Cancel preserves technology vehicle")
		game.scrap = 1000
		check(game.deploy_selected_vehicle() and game.scrap == 940 and game.districts.has_live("workshop"),"Actual legal grid deployment charges exact original workshop price")
	game.day_number += 1
	check(game.locate_tech_supply(),"Following day allows fresh exploration location")
	check(game._roll_supply_reward().kind == "barracks","Live workshop skips to missing flag prerequisite")
	var flag := vehicle("barracks")
	var candidates: Array[String] = game._tech_supply_candidates()
	check(not candidates.is_empty(),"Workshop enables remaining legal infrastructure candidates")
	for repeat in 30:
		var kind: String = game._roll_supply_reward().kind
		check(kind in candidates and kind not in ["workshop","barracks","tower"],"Priority pool avoids live/vehicle duplicates and respects legal technology")
		check(bool(game.districts.build_eligibility(kind).available),"Technology lottery does not bypass live prerequisites")
	check(is_instance_valid(flag),"Lottery inspection never consumes existing reward")
	for kind: String in Catalog.BUILDING_IDS:
		if kind not in ["tower","workshop","barracks"]:vehicle(kind)
	check(game._tech_supply_candidates().is_empty(),"No duplicate priority remains when every missing kind is already delivered")
	var fallback: Dictionary = game._roll_supply_reward()
	check(fallback.kind in Catalog.BUILDING_IDS and bool(game.districts.build_eligibility(fallback.kind).available),"Exhausted priority pool falls back to legal normal lottery")
	game.phase = "paused"
	var count: int = game.supply_crates.size()
	var clock: float = game.supply_crate_clock
	game.advance_supply_crates(100)
	check(game.supply_crates.size() == count and game.supply_crate_clock == clock and game.tech_supply_pending,"Pause freezes delivery and keeps technology request")
	for phase: String in ["night","draft","ended"]:
		game.phase = phase
		game.day_number += 1
		check(not game.locate_tech_supply(),"Non-day phases cannot issue fresh locations")
	game.clear_supply_crates(true)
	check(not game.tech_supply_pending and game.tech_supply_day == -1,"Terminal/retry cleanup clears pending location and day stamp")
	game.phase = "day"
	check(game.locate_tech_supply(),"Fresh-run cleanup allows new day location")
	game.clear_supply_crates(true)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_TECH_SUPPLY_%s checks=%d failures=%d" % ["OK" if failures == 0 else "FAILED",checks,failures])
	quit(0 if failures == 0 else 1)
