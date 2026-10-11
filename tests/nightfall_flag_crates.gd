extends SceneTree
## Precision economic/identity fixtures; not a natural full-game balance claim.
const Crate = preload("res://scripts/outpost_supply_crate.gd")
const Grid = preload("res://scripts/construction_grid.gd")
const Encounter = preload("res://scripts/nightfall_encounters.gd")
var game: Node3D
var failures := 0
var checks := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func crate(kind: String, point: Vector3, variant: String="standard") -> Node3D:
	var item:=Crate.new()
	item.setup(game.supply_crate_serial,kind,"国旗基地" if kind=="barracks" else "光塔")
	item.tower_variant=variant
	game.supply_crate_serial+=1
	point.y=game.outpost_height(point)
	item.position=point
	game.add_child(item)
	game.supply_crates.append(item)
	return item
func legal(kind: String) -> Vector3:
	for z in range(-18,19):
		for x in range(-18,19):
			var point:=Vector3(x,5,z)
			var result: Dictionary=game.construction.validity(point,-1,kind)
			if result.valid:return result.point
	return Vector3.INF
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless":return
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/flag-crates-20261011/"+label+".png")
func run() -> void:
	game=load("res://scenes/nightfall.tscn").instantiate()
	game.archive.enabled=false
	root.add_child(game)
	current_scene=game
	await process_frame
	await process_frame
	game.set_process(false)
	check(game.supply_crates.size()==1,"Opening draft must contain an actual sealed crate")
	var first: Node3D=game.supply_crates[0]
	check(not first.revealed and not first.chassis.visible and first.sealed_body.visible,"Before contact only the small box is visible")
	check(not first.caption.text.contains(first.display_name),"Sealed crate must not disclose its reward")
	await capture("sealed-opening")
	game.choose_card(0)
	var y:=InputEventKey.new()
	y.keycode=KEY_Y;y.physical_keycode=KEY_Y;y.pressed=true
	root.push_input(y,true)
	await process_frame
	y.pressed=false;root.push_input(y,true)
	await process_frame
	check(not game.construction.active and game.pending_build_permit_kind.is_empty(),"Actual Y input must not open building catalog")
	check(not game.select_construction_vehicle(first),"Sealed box cannot be selected/deployed")
	await capture("sealed-night")
	game.plan_hero_path(first.position)
	for step in 180:
		game.move_hero(.05)
		game.advance_supply_crates(.05)
		if first.revealed:break
	check(first.revealed and first.chassis.visible and not first.sealed_body.visible,"Real hero path movement must automatically reveal without an interaction key")
	await capture("contact-revealed")
	var balance: int=game.scrap
	var count: int=game.supply_crates.size()
	game._try_open_supply_crates();game._try_open_supply_crates()
	check(game.scrap==balance and game.supply_crates.size()==count,"Contact is idempotent and does not pay deployment fees")
	var origin:=first.position
	var destination:=Vector3.INF
	for offset: Vector3 in [Vector3(3,0,0),Vector3(-3,0,0),Vector3(0,0,3),Vector3(0,0,-3)]:
		var candidate:=origin+offset
		candidate.y=game.outpost_height(candidate)
		if first._segment_clear(origin,candidate,game):destination=candidate;break
	check(destination.is_finite(),"Real revealed deployment object needs a traversable drag destination")
	if destination.is_finite():
		var mouse:=InputEventMouseButton.new()
		mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=true
		mouse.position=game.camera.unproject_position(first.global_position+Vector3.UP*.8)
		root.push_input(mouse,true)
		await process_frame
		mouse=InputEventMouseButton.new()
		mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=false
		mouse.position=game.camera.unproject_position(game.to_global(destination))
		root.push_input(mouse,true)
		await process_frame
		check(game.selected_construction_vehicle==first and not first.path_points.is_empty() and first.position==origin,"Actual mouse drag queues movement without teleportation")
		for step in 120:first.advance_movement(.05,game)
		check(first.position.distance_to(destination)<.2,"Dragged deployment object really walks its route")
	game.clear_supply_crates(true)
	game.phase="day"
	game.hero.position=Vector3(0,5,8)
	game.move_goal=game.hero.position
	game.hero_path.clear()
	var flag_point:=legal("barracks")
	check(flag_point.is_finite(),"Flag fixture needs real legal ground")
	var flag:=crate("barracks",flag_point)
	game.hero.position=flag.position+Vector3(0,0,1.3)
	game.hero.alive=false
	game._try_open_supply_crates()
	check(not flag.revealed,"Dead hero cannot reveal")
	game.hero.alive=true
	game.phase="paused";game._try_open_supply_crates()
	check(not flag.revealed,"Pause prevents revealing")
	game.phase="day";game._try_open_supply_crates()
	check(flag.revealed,"Living owned hero reveals on contact")
	game.hero.position=Vector3(0,5,8)
	game.move_goal=game.hero.position
	game.scrap=0
	check(game.select_construction_vehicle(flag),"Revealed flag can be selected")
	check(not game.deploy_selected_vehicle() and game.scrap==0 and flag in game.supply_crates,"Insufficient funds preserve revealed flag")
	game.construction.cancel()
	check(flag in game.supply_crates,"Cancellation preserves reward")
	game.scrap=1000
	check(game.deploy_selected_vehicle(),"Flag deploys through original valid grid placement")
	check(game.scrap==940,"Flag charges exactly original deployment cost on success")
	var plot: Dictionary=game.districts.plots.back()
	var index: int=game.districts.plots.size()-1
	check(plot.hp==1800.0 and not game.outpost_walkable(plot.position),"High-health flag is a real navigation blocker")
	check(plot.model.find_child("NationalFlag",true,false)!=null,"Flag has actual flag geometry")
	game.districts.damage(index,100.0)
	game.districts.tick(.9)
	check(plot.hp==1700.0 and game.scrap==940,"Auto repair waits for full game second")
	game.districts.tick(.1)
	check(plot.hp==1718.0 and game.scrap==939,"Auto repair pays one light for 18 HP")
	game.phase="paused";game.districts.tick(5)
	check(plot.hp==1718.0 and game.scrap==939,"Paused flag cannot spend or repair")
	game.phase="day";game.scrap=0;game.districts.tick(5)
	check(plot.hp==1718.0,"No light means no free repair")
	check(not game.squads.enqueue("shield").ok,"Training cannot bypass funds")
	game.scrap=1000
	var training: Dictionary=game.squads.enqueue("shield",index)
	check(training.ok and game.scrap==930,"Flag uses real paid training queue")
	var before: int=game.squads.squads.size()
	game.squads._advance_training(5.9)
	check(game.squads.squads.size()==before,"Flag cannot create instant free troops")
	game.squads._advance_training(.2)
	check(game.squads.squads.size()==before+1,"Actual training duration creates a real squad")
	# Actual enemy movement/attack must damage the flag without crossing it.
	game.phase="night"
	game.hero.position=Vector3(80,0,80)
	var monster: BattleUnit=game.spawn_creature(true,"basic")
	monster.position=plot.position+Vector3(0,0,-3.5)
	var target: Dictionary=game.choose_enemy_target(monster)
	check(target.get("kind","")=="district" and int(target.get("index",-1))==index,"Nearby enemy must choose the flag as an actual target")
	var flag_hp: float=plot.hp
	for step in 100:
		var monster_origin:=monster.position
		monster.tick(.05)
		game.update_creature(monster,.05)
		check(game.can_traverse(monster_origin,monster.position),"Attacking enemy cannot walk through flag footprint")
		if plot.hp<flag_hp:break
	check(plot.hp<flag_hp,"Enemy must actually hit flag, not only select it")
	game.enemies.erase(monster);monster.queue_free()
	game.phase="day"
	# A paid trained squad walks into a sealed box through real squad commands.
	var squad: Dictionary=game.squads.squads.back()
	var member: BattleUnit=squad.members[0]
	var squad_destination:=member.position+Vector3(0,0,5)
	if not game.can_traverse(member.position,squad_destination):squad_destination=member.position+Vector3(5,0,0)
	var squad_box:=crate("tower",squad_destination)
	game.squads.select_all()
	check(game.squads.command_move(squad_box.position).ok,"Trained squad gets a real move order toward sealed box")
	for step in 300:
		game.squads.advance(.05)
		game.advance_supply_crates(.05)
		if squad_box.revealed:break
	check(squad_box.revealed,"Owned trained squad must reveal box through actual movement")
	game.clear_supply_crates(true)
	game.hero.position=Vector3(0,5,8)
	game.move_goal=game.hero.position
	for variant: String in ["standard","piercing","control","flame","chain"]:
		game.select_construction_vehicle(null)
		var point:=legal("tower")
		var tower:=crate("tower",point,variant)
		tower.reveal()
		game.scrap=1000
		game.select_construction_vehicle(tower)
		check(game.deploy_selected_vehicle(),"Each tower variant deploys legally: "+variant)
		var pad: Dictionary=game.world.tower_pads.back()
		var expected: int=60 if variant=="standard" else 105
		check(game.scrap==1000-expected and game.specializations.branch(pad)==variant,"Tower pays base plus actual specialization fee: "+variant)
		var targets: Array[BattleUnit]=[]
		for offset in 3:
			var victim: BattleUnit=game.spawn_creature(true,"basic")
			victim.max_hp=2000;victim.hp=2000
			victim.position=point+Vector3(5+offset,0,0)
			targets.append(victim)
		var hits: Array[Dictionary]=game.specializations.resolve_shot(pad,targets[0],targets,100.0,game.hero)
		check(not hits.is_empty() and targets[0].hp<2000,"Variant causes real damage: "+variant)
		if variant in ["control","flame","chain"]:check(hits.size()==3,"Area/chain variant damages actual nearby units: "+variant)
		if variant=="control":check(game.specializations.movement_multiplier(targets[0])<1.0,"Control variant applies real slow")
		for victim in targets:game.enemies.erase(victim);victim.queue_free()
		var tower_index: int=game.world.tower_pads.size()-1
		check(game.build_or_upgrade_tower(tower_index) and pad.level==2,"Tower second level is paid")
		check(game.scrap==1000-expected-80,"Second level costs 80 light")
		check(game.build_or_upgrade_tower(tower_index) and pad.level==3,"Tower third level is paid")
		check(game.scrap==1000-expected-220,"Third level costs 140 light, more than second")
	if DisplayServer.get_name()!="headless":
		game.camera.position=plot.position+Vector3(8,25,29)
		game.camera.look_at(plot.position+Vector3(6,0,3))
		game.hud.queue_redraw()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/flag-crates-20261011/flag-tower-render.png")
	game.districts.damage(index,100000.0)
	balance=game.scrap;game.districts.tick(10)
	check(plot.level==0 and plot.hp==0.0 and game.scrap==balance and game.outpost_walkable(plot.position),"Destroyed flag cannot resurrect and releases blocking")
	game.clear_supply_crates(true)
	game.hero.position=Vector3(0,5,8)
	game.camera.position=game.hero.position+Vector3(0,25,29)
	game.camera.look_at(game.hero.position)
	game.camera.force_update_transform()
	game.advance_supply_crates(24.9)
	check(game.supply_crates.is_empty(),"Periodic delivery must wait 25 game seconds")
	game.advance_supply_crates(.2)
	check(game.supply_crates.size()==1,"Periodic delivery must create a physical sealed box")
	if not game.supply_crates.is_empty():
		var spawned: Node3D=game.supply_crates[0]
		check(not spawned.revealed and game.can_traverse(game.hero.position,spawned.position),"Delivery is sealed and actually reachable")
		var clock: float=game.supply_crate_clock
		game.phase="paused";game.advance_supply_crates(50)
		check(game.supply_crate_clock==clock,"Pause freezes supply clock")
	game.phase="day";game.clear_supply_crates(false)
	check(game.supply_crates.size()==1,"Phase transition keeps actual unopened box")
	game.clear_supply_crates(true)
	check(game.supply_crates.is_empty() and not is_instance_valid(game.selected_construction_vehicle),"Terminal cleanup clears boxes and selection")
	var planner:=Encounter.new()
	var normal: Array=planner.make_plan("standard",1,123,0)
	var teaching: Array=planner.make_plan("teaching",1,123,0)
	check(normal[0].roles.size()==teaching[0].roles.size()+2,"Standard gets three extra first-wave monsters; teaching gets one")
	for mode: String in ["teaching","standard","siege","echo"]:
		for night in range(1,5):
			for seed_value in [17,45,29045]:
				var plan: Array=planner.make_plan(mode,night,seed_value,0)
				var reduced: Array=planner.make_plan(mode,night,seed_value,3)
				check(plan==planner.make_plan(mode,night,seed_value,0),"Larger waves remain seeded and deterministic")
				for wave_index in 5:
					var base: int=8+night*3 if wave_index==0 else 8+night*2+wave_index*2
					var bonus: int=1 if mode=="teaching" else 2+night
					check(plan[wave_index].roles.size()==base+bonus,"Every wave gets the declared ordinary-monster increase")
					check(int(plan[wave_index].count)-int(reduced[wave_index].count)==6,"Cleared nests retain real reduction")
					for role: String in Encounter.KNOWN_ROLES:
						if role!="basic":check(plan[wave_index].roles.count(role)==reduced[wave_index].roles.count(role),"Nest clearing must preserve every special enemy")
	game.queue_free()
	await process_frame
	await create_timer(.6).timeout
	print("NIGHTFALL_FLAG_CRATES_%s checks=%d failures=%d" % ["OK" if failures==0 else "FAILED",checks,failures])
	quit(0 if failures==0 else 1)
