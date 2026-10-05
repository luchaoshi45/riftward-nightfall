extends SceneTree
## Isolated lifecycle/economy/targeting checks using real BattleUnit assets.
const SquadScript = preload("res://scripts/outpost_squads.gd")
var failures: Array[String] = []
var game: FixtureGame
var squads: Node3D
var last_source: BattleUnit

class FixtureWorld extends Node3D:
	var tower_pads: Array[Dictionary] = []
	func terrain_height(point: Vector3) -> float:
		var rise := clampf((19.0 - point.z) / 12.0, 0, 1)
		return 5.0 * rise * rise * (3.0 - 2.0 * rise)

class FixtureDistricts extends Node3D:
	var plots: Array[Dictionary] = [
		{"index": 0, "position": Vector3(0, 5, 5), "level": 1, "kind": "barracks", "hp": 300.0, "max_hp": 300.0},
		{"index": 1, "position": Vector3(0, 5, 7), "level": 1, "kind": "barracks", "hp": 300.0, "max_hp": 300.0}]
	func active_barracks() -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		for plot in plots:
			if int(plot.level) > 0 and float(plot.hp) > 0.0: result.append(plot)
		return result
	func repair_cost(base: int) -> int: return base

class FixtureGame extends Node3D:
	var phase := "night"
	var scrap := 500
	var enemies: Array[BattleUnit] = []
	var focus_target: BattleUnit
	var focus_time := 0.0
	var world: FixtureWorld
	var districts: FixtureDistricts
	func outpost_height(point: Vector3) -> float: return world.terrain_height(point)
	func can_traverse(_from: Vector3, to: Vector3) -> bool:
		return absf(to.x) <= 2.5 and to.z >= 3.0 and to.z <= 20.0

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func enemy(point: Vector3, threat: String = "stalker", hp: float = 1000.0) -> BattleUnit:
	var unit := BattleUnit.new()
	game.add_child(unit); unit.setup("monster", 2)
	unit.position = point
	unit.set_meta("threat", threat)
	unit.hp = hp; unit.max_hp = hp; unit.armor = 0.0
	unit.defeated.connect(func(_unit: BattleUnit, source: BattleUnit): last_source = source)
	game.enemies.append(unit)
	return unit

func remove_enemies() -> void:
	for unit in game.enemies:
		if is_instance_valid(unit): unit.queue_free()
	game.enemies.clear()
	game.focus_target = null; game.focus_time = 0.0

func _flat_distance(a: Vector3, b: Vector3) -> float: return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func settle() -> void:
	for step in 50: squads.advance(.1)

func run() -> void:
	game = FixtureGame.new(); root.add_child(game)
	game.world = FixtureWorld.new(); game.add_child(game.world)
	squads = SquadScript.new(); game.add_child(squads); squads.setup(game)
	var before := game.scrap
	check(not squads.hire("ranged").ok and game.scrap == before, "Ranged must require explicit enablement without spending")
	check(not squads.hire("typo").ok and game.scrap == before, "Unknown kind must not spend")
	game.scrap = 69
	check(not squads.hire("shield").ok and squads.snapshot().count == 0 and game.scrap == 69, "Insufficient hiring must not create or spend")
	game.scrap = 300
	game.phase = "draft"
	check(not squads.hire("shield").ok and game.scrap == 300, "Drafting must refuse hiring")
	game.phase = "night"
	check(squads.hire("shield").ok and game.scrap == 230, "Shield squad must charge seventy once")
	check(squads.hire("shield").ok and game.scrap == 160, "Two same-kind squads must be allowed")
	check(squads.hire("shield").ok and game.scrap == 90 and squads.snapshot().alive == 9, "A third paid squad must be supported without a fixed count limit")
	settle()
	for squad in squads.squads:
		for member: BattleUnit in squad.members:
			check(is_equal_approx(member.position.y, game.outpost_height(member.position)), "Members must stand on the actual slope")
			check(member.get_children().all(func(child: Node): return not child is CollisionObject3D), "Soldiers must not introduce gate-blocking bodies")
	var defender: BattleUnit = squads.squads[0].members[0]
	var foe := enemy(defender.position + Vector3(0, 0, 1.0))
	foe.damage = 25; foe.attack_timer = 0.0
	check(squads.blocker_for(foe) == defender, "Nearby shield must offer a real interception target")
	var defender_hp := defender.hp
	foe.tick(.01)
	check(squads.intercept_enemy(foe, .01) and foe.attack_queued and defender.hp == defender_hp, "Enemy must wind up before striking a soldier")
	game.phase = "paused"
	var windup := foe.attack_windup
	var soldier_age := defender.age
	squads.advance(10.0)
	squads.intercept_enemy(foe, 10.0)
	check(foe.attack_windup == windup and defender.hp == defender_hp and defender.age == soldier_age, "Paused squad/interception calls must not consume actions or HP")
	game.phase = "night"
	foe.tick(.35); squads.intercept_enemy(foe, .35)
	check(is_equal_approx(defender.hp, defender_hp - 20.0), "Actual enemy strike must damage shield through its twenty-five armor")
	foe.set_meta("threat", "sapper")
	# A changed special role must regain its original tower behavior.
	check(squads.blocker_for(foe) == null, "Sappers must retain their independent tower priority")
	check(not squads.intercept_enemy(foe, .1) and not foe.attack_queued, "A previously intercepted sapper must regain its actual controller target")
	foe.set_meta("threat", "light_eater")
	check(squads.blocker_for(foe) == null, "Light eaters must retain their original lamp behavior")
	remove_enemies()
	defender.hurt(10000, null)
	check(squads.snapshot().alive == 8, "Death immediately removes a soldier from live counts")
	await process_frame
	check(not is_instance_valid(defender) and squads.snapshot().alive == 8, "Cross-frame death must really free the unit and retain an empty paid slot")
	squads.on_day(); squads.on_night()
	check(squads.snapshot().alive == 8 and not squads.refill().ok, "Day/night transitions never resurrect and night refill is rejected")
	game.phase = "day"; squads.on_day()
	var refill_price: int = squads.refill_cost()
	check(refill_price >= 22, "Replacement and existing wounds must carry a repair price")
	game.scrap = refill_price - 1
	check(not squads.refill().ok and squads.snapshot().alive == 8, "Unaffordable refill must preserve casualties")
	game.scrap = 200; before = game.scrap
	check(squads.refill().ok and game.scrap == before - refill_price and squads.snapshot().alive == 9, "Day refill must pay once and replace only losses, heal charged wounds")
	check(not squads.refill().ok and game.scrap == before - refill_price, "An intact squad cannot be charged a second time")
	check(squads.set_order("recall").ok and squads.blocker_for(foe) == null, "Recall must not offer a blocking target")
	check(not squads.set_order("unknown").ok and not squads.set_order("hold", 9).ok, "Invalid orders and squad ids must be rejected")
	squads.clear(); squads.setup(game, true)
	game.phase = "night"; game.scrap = 500
	check(squads.hire("ranged").ok and game.scrap == 420, "Enabled ranged squad must charge eighty")
	settle()
	var archer: BattleUnit = squads.squads[0].members[0]
	var weak := enemy(archer.position + Vector3(0, 0, 2.0), "runner")
	var heavy := enemy(archer.position + Vector3(0, 0, 6.0), "breaker")
	for member: BattleUnit in squads.squads[0].members: member.attack_timer = 0.0
	squads.advance(.01)
	check(archer.target == heavy and weak.hp == 1000.0 and heavy.hp == 1000.0, "Ranged prioritizes a reachable heavy with real windup rather than nearest filler")
	game.phase = "draft"
	var queued_delay := archer.attack_windup
	squads.advance(5.0)
	check(heavy.hp == 1000.0 and archer.attack_windup == queued_delay, "Drafting freezes ranged windup and damage")
	game.phase = "night"; squads.advance(.27)
	check(heavy.hp < 1000.0 and weak.hp == 1000.0 and not squads.shots.is_empty(), "Ranged commits damage with a beam to its selected target")
	var shot_time: float = squads.shots[0].time
	squads.advance(9.0, false)
	check(squads.shots[0].time == shot_time, "Explicit inactive advance must also freeze beam lifetime")
	heavy.hp = 1.0
	for member: BattleUnit in squads.squads[0].members: member.attack_timer = 0.0
	squads.advance(.01); squads.advance(.27)
	check(not heavy.alive and is_instance_valid(last_source) and last_source.kind == "minion", "Ranged kill source must remain its soldier, never the hero")
	remove_enemies(); await process_frame; squads.advance(.2)
	check(squads._intercepts.is_empty(), "Disposed enemies must not leave interception entries")
	squads.clear()
	check(squads.snapshot().alive == 0 and squads.shots.is_empty(), "Clear must retire all soldiers and pending beams")
	# Independent barracks produce in parallel, with ordered queues and real escrow.
	game.districts = FixtureDistricts.new(); game.add_child(game.districts)
	game.phase = "night"; game.scrap = 1000
	check(squads.enqueue("shield", 0).ok and squads.enqueue("ranged", 1).ok, "Two active barracks must accept independent training")
	check(game.scrap == 850 and squads.snapshot().count == 0, "Enqueue pays exactly once and cannot instantly create units")
	squads.advance(3.0)
	var queues: Array = squads.snapshot().queues
	check(is_equal_approx(queues[0].queue[0].remaining, 3.0) and is_equal_approx(queues[1].queue[0].remaining, 5.0), "Barracks timers must advance concurrently")
	game.phase = "paused"; squads.advance(10.0)
	check(is_equal_approx(squads.snapshot().queues[0].queue[0].remaining, 3.0), "Pause must freeze training escrow and timers")
	game.phase = "draft"; squads.advance(10.0)
	check(not squads.cancel_training(0).ok and is_equal_approx(squads.snapshot().queues[1].queue[0].remaining, 5.0), "Cards must freeze training and refuse economic mutations")
	game.phase = "night"; squads.advance(3.0)
	check(squads.snapshot().count == 1 and is_equal_approx(squads.snapshot().queues[1].queue[0].remaining, 2.0), "Six-second shield completion must leave the other barracks running")
	check(squads.enqueue("engineer", 0).ok and squads.enqueue("shield", 0).ok, "One barracks must accept an ordered unbounded queue")
	before = game.scrap
	check(squads.cancel_training(0, 1).ok and game.scrap == before + 70, "Cancelling a waiting entry must fully refund its paid price")
	before = game.scrap
	game.districts.plots[0].hp = 0.0
	squads.refresh_barracks()
	check(game.scrap == before + 65 and not squads.training_queues.has(0), "Destroyed barracks must immediately fully refund unfinished production")
	squads.advance(.1)
	check(game.scrap == before + 65, "Destroyed production must refund once")
	game.districts.plots[1].hp = 0.0
	check(not squads.enqueue("shield").ok, "No surviving barracks must refuse recruitment")
	game.districts.plots[0].hp = 300.0; game.districts.plots[1].hp = 300.0
	squads.advance(2.0)
	check(squads.snapshot().count == 2, "Already-paid ranged training must complete after the barracks survives")
	check(squads.select_all() == 2 and squads.selected_count() == 2, "Select all must select every live paid formation")
	check(squads.command_guard(Vector3(0, 5, 12)).ok, "Selected formations must accept an arbitrary guard destination")
	squads.on_day(); squads.on_night()
	check(squads.snapshot().squads.all(func(row: Dictionary): return row.order == "guard"), "Day/night must preserve player-issued orders")
	squads.cancel_selection()
	check(squads.selected_count() == 0 and not squads.command_move(Vector3(0, 5, 12)).ok, "Orders must require explicit selection")
	var member: BattleUnit = squads.squads[0].members[1]
	check(squads.select_at(member.position) == 0 and squads.selected_count() == 1 and member.selection.visible, "Clicking a living member must select its formation and show the ring")
	check(squads.command_move(Vector3(0, 5, 11)).ok, "A selected formation must accept moving to a free destination")
	for step in 100: squads.advance(.1)
	check(_flat_distance(member.position, Vector3(0, 5, 11)) < .25, "Formation movement must reach its issued destination")
	squads.clear(); game.scrap = 1000
	check(squads.hire("engineer").ok and game.scrap == 935, "Engineers must be recruitable as a third distinct kind")
	var engineer: BattleUnit = squads.squads[0].members[1]
	for soldier: BattleUnit in squads.squads[0].members:
		soldier.position = Vector3(0, game.outpost_height(Vector3(0, 0, 10)), 10)
		soldier.speed = 0.0
	squads.select_all(); squads.command_guard(Vector3(0, 5, 10))
	# One selected repairer acts; the other formation members retain real movement intent.
	game.world.tower_pads = [{"position": engineer.position + Vector3(0, 0, 2), "level": 1, "hp": 95.0, "max_hp": 100.0}]
	before = game.scrap
	squads.advance(1.0)
	check(game.world.tower_pads[0].hp == 100.0 and game.scrap == before - 2, "Engineer repair must pay real scrap and cap restored tower HP")
	game.world.tower_pads[0].hp = 0.0
	squads.advance(1.0)
	check(game.world.tower_pads[0].hp == 0.0, "Engineers cannot resurrect destroyed structures")
	game.world.tower_pads[0].hp = 30.0; game.scrap = 1
	squads.advance(1.0)
	check(game.world.tower_pads[0].hp == 30.0 and game.scrap == 1, "Engineers with insufficient scrap cannot repair for free")
	game.scrap = 500
	check(squads.enqueue("shield", 0).ok, "A final queued training must be accepted before reset")
	before = game.scrap; squads.clear()
	check(game.scrap == before and squads.training_queues.is_empty(), "New-run clear must discard queue state without cross-run refunds")
	game.queue_free(); await process_frame; await process_frame
	print("OUTPOST_SQUADS_FIXTURE_", "OK" if failures.is_empty() else "FAILED")
	quit(0 if failures.is_empty() else 1)
