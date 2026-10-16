extends "res://tests/nightfall_veterancy.gd"
## Original-wallet scripted hero expedition. No precision helper or actor placement.
var route_record: Dictionary = {}
var hero_travel := 0.0
var vehicle_travel := 0.0
func _initialize() -> void:
	profile_path = "user://riftward-tech-route-%d.json" % Time.get_ticks_usec()
	evidence = {"payments":[]}
	root.child_entered_tree.connect(inject_archive)
	create_timer(240.0,true,false,true).timeout.connect(func(): quit(2))
	call_deferred("run")
func step(delta: float = STEP) -> void:
	observe()
	var before: int = game.scrap
	var prior: String = game.phase
	var origin: Vector3 = game.hero.position
	game._process(delta)
	var movement := planar(origin,game.hero.position)
	hero_travel += movement
	if movement > .00001:
		check(game.can_traverse(origin,game.hero.position),"Hero path step remains physically traversable")
	if prior in ["day","night"]: elapsed += delta
	if before != game.scrap: wallets.append({"at":elapsed,"before":before,"after":game.scrap,"phase":game.phase})
	observe()
func combat_step() -> void:
	var target: BattleUnit
	var closest := INF
	for raw: Variant in game.enemies:
		if living(raw) and raw.position.distance_to(game.hero.position) < closest:
			target = raw; closest = raw.position.distance_to(game.hero.position)
	game.aim = target.position if living(target) else game.hero.position + Vector3(0,0,8)
	if closest < 10.0: game.cast(0)
	if game.hero.hp < game.hero.max_hp * .7: game.cast(1); game.cast(4)
	if closest < 7.0: game.cast(3)
	step(.1)
func deploy_real_box(box: Node3D) -> bool:
	game.plan_hero_path(box.position)
	for frame in 400:
		if box.revealed: break
		combat_step()
		if game.phase not in ["day","night"]: return false
		if frame % 100 == 99: await process_frame
	if not box.revealed: return false
	var points: Array[Vector3] = []
	for z in range(-17,18):
		for x in range(-17,18):
			var result: Dictionary = game.construction.validity(Vector3(x,5,z),-1,box.supply_kind)
			if result.valid: points.append(result.point)
	points.sort_custom(func(a: Vector3,b: Vector3): return a.distance_squared_to(box.position)<b.distance_squared_to(box.position))
	var destination := Vector3.INF
	for point: Vector3 in points:
		if box.command_move(point,game): destination=point; break
	if not destination.is_finite() or not game.select_construction_vehicle(box): return false
	var vehicle_origin: Vector3 = box.position
	for frame in 1200:
		if box.position.distance_to(destination)<.1: break
		var previous: Vector3 = box.position
		combat_step()
		var moved := planar(previous,box.position)
		vehicle_travel += moved
		check(moved <= box.move_speed*.1+.001,"Vehicle real step obeys original movement speed")
		if game.phase not in ["day","night"]: return false
		if frame % 100 == 99: await process_frame
	var before: int = game.scrap
	var kind: String = box.supply_kind
	var paid_cost: int = int(game.districts.tower_cost(int(Catalog.building(kind).cost))) + (45 if box.tower_variant != "standard" else 0) if kind == "tower" else int(Catalog.building(kind).cost)
	var deployed: bool = game.deploy_selected_vehicle()
	check(not deployed or game.scrap == before-paid_cost,"Successful actual deployment pays original catalog cost")
	if kind == "workshop":
		check(planar(vehicle_origin,destination) > .1 and box.position.distance_to(destination) < .1,"Workshop vehicle actually drives from delivered position to legal city plot")
	if not route_record.has("payments"): route_record.payments=[]
	route_record.payments.append({"kind":kind,"ok":deployed,"before":before,"after":game.scrap,"cost":paid_cost,"time":game.phase_time,"phase":game.phase})
	return deployed
func run() -> void:
	if not await fresh(false): await route_finish(); return
	game.plan_hero_path(Vector3(0,5,10))
	for frame in 2600:
		if game.phase != "night": break
		combat_step()
		if frame % 100 == 99: await process_frame
	route_record.opening = {"phase":game.phase,"hero_hp":game.hero.hp,"beacon_hp":game.beacon_hp,"time":game.phase_time,"elapsed":elapsed,"kills":game.kills,"wallet":game.scrap}
	check(game.phase == "draft" and game.hero.alive,"Original first night survives without fixture funding")
	if game.phase != "draft": await route_finish(); return
	await press(KEY_1)
	if game.supply_crates.size() >= 3:
		var first: Node3D = game.supply_crates[0]
		check(await deploy_real_box(first),"Original existing box really deploys to free capacity")
	var serial_before: int = game.supply_crate_serial
	var site: Dictionary = game.expeditions.generators[0]
	route_record.dawn = {"wallet":game.scrap,"seconds":game.phase_time,"hero_hp":game.hero.hp,"site":vec(site.position)}
	game.plan_hero_path(site.position)
	for frame in 900:
		if game.phase != "day" or not game.hero.alive: break
		if site.state == "ready" and game.hero.position.distance_to(site.position) <= 3.0: game.interact()
		combat_step()
		if site.state == "complete": break
		if frame % 100 == 99: await process_frame
	route_record.capture = {"state":site.state,"progress":site.progress,"seconds":game.phase_time,"wallet":game.scrap,"hero_hp":game.hero.hp,"position":vec(game.hero.position)}
	check(site.state == "complete","Hero really reaches generator, charges and defeats original guards within original daylight")
	if site.state != "complete": await route_finish(); return
	check(site.guard_tokens.size()==3 and site.guard_deaths.size()==3,"All three real generated guards have authoritative death receipts")
	check(game.tech_supply_pending and not game.districts.has_live("workshop"),"Completed exploration records pending technology without free building")
	serial_before = game.supply_crate_serial
	route_record.located = {"pending":game.tech_supply_pending,"serial_next":game.supply_crate_serial,"crates":[]}
	for item: Node3D in game.supply_crates: route_record.located.crates.append({"serial":item.serial,"kind":item.supply_kind})
	if game.tech_supply_pending and game.supply_crates.size() >= 3:
		check(await deploy_real_box(game.supply_crates[0]),"Pending technology survives full capacity until real paid deployment")
	var box: Node3D
	for frame in 300:
		for item: Node3D in game.supply_crates:
			if item.supply_kind == "workshop" and item.serial >= serial_before: box = item; break
		if is_instance_valid(box): break
		combat_step()
		if frame % 100 == 99: await process_frame
	check(is_instance_valid(box) and not game.tech_supply_pending,"Automatic original delivery produces technology workshop and consumes pending location")
	if not is_instance_valid(box): await route_finish(); return
	route_record.technology_serial = box.serial
	check(await deploy_real_box(box) and game.districts.has_live("workshop"),"New technology box requires real hero contact, vehicle movement and original paid workshop deployment")
	await route_finish()
func route_finish() -> void:
	route_record.seed = SEED
	route_record.run_mode = "siege"
	route_record.scope = "Original-wallet scripted route; no source/actor placement, funding, enemy stat changes, direct damage, permit injection or deadline extension; headless only, not human/full-campaign balance"
	route_record.hero_travel = hero_travel
	route_record.vehicle_travel = vehicle_travel
	route_record.wallet_changes = wallets
	print("TECH_SUPPLY_ROUTE_EVIDENCE ",JSON.stringify(route_record))
	await close_game()
	for suffix: String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(profile_path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path+suffix))
	print("NIGHTFALL_TECH_SUPPLY_ROUTE_", "OK" if failures.is_empty() else "FAILED", " checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
