extends SceneTree
const Rewards = preload("res://scripts/wave_rewards.gd")
var checks: int = 0
var failures: int = 0
var rewards = Rewards.new()
var income: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func enemy() -> BattleUnit:
	var unit := BattleUnit.new()
	unit.kind = "monster"
	unit.team = 2
	unit.hp = 100.0
	unit.max_hp = 100.0
	root.add_child(unit)
	unit.defeated.connect(func(defeated: BattleUnit, _source: BattleUnit) -> void:
		income += rewards.defeat(defeated))
	return unit

func pack(id: int, count: int, budget: int = 24) -> Array[BattleUnit]:
	check(rewards.begin_wave(id, budget), "New wave budget can be opened once")
	var units: Array[BattleUnit] = []
	for _index in count:
		var unit := enemy()
		check(rewards.register_enemy(id, unit), "Real enemy can register")
		check(unit.get_meta("wave_reward_id", -1) == id, "Enemy carries its wave reward identifier")
		units.append(unit)
	var before_income: int = income
	check(rewards.seal_wave(id), "Initial pack registration can be sealed")
	check(income == before_income and rewards.snapshot(id).paid == 0, "Sealing is never an extra reward")
	return units

func dispose(units: Array[BattleUnit]) -> void:
	for unit: BattleUnit in units:
		if is_instance_valid(unit): unit.queue_free()

func run() -> void:
	var hero := BattleUnit.new()
	hero.kind = "hero"
	root.add_child(hero)
	var tower_source := BattleUnit.new()
	tower_source.kind = "tower"
	root.add_child(tower_source)
	var units := pack(1, 10)
	var wave_income := income
	for index in 9:
		units[index].hurt(1000, hero if index % 2 == 0 else tower_source)
		var expected: int = int(floor(float((index + 1) * 24 * 7) / 100.0))
		check(income - wave_income == expected, "Hero and tower kills share cumulative rolling payout")
		check(rewards.defeat(units[index]) == 0, "Duplicate death cannot claim again")
		check(not rewards.snapshot(1).cleared and rewards.snapshot(1).paid < 24, "Incomplete wave cannot claim completion remainder")
	check(income - wave_income == 15, "Rolling floors accumulate rather than losing fractions per kill")
	units[9].hurt(1000, tower_source)
	check(income - wave_income == 24 and rewards.snapshot(1).cleared, "Final real kill returns the complete wave budget")
	check(rewards.defeat(units[9]) == 0 and not rewards.seal_wave(1), "Completion is one-time")
	check(not rewards.begin_wave(1), "Beginning a used id cannot reset its paid budget")
	var late := enemy()
	check(not rewards.register_enemy(1, late), "Cleared wave cannot reopen itself through late adds")
	late.queue_free()
	dispose(units)
	units = pack(2, 2)
	wave_income = income
	units[0].hurt(1000, hero)
	check(income - wave_income == 8, "Early kill can pay its original rolling share")
	var reinforcements: Array[BattleUnit] = []
	for _index in 4:
		var added := enemy()
		check(rewards.register_enemy(2, added), "Boss reinforcement registers before completion")
		reinforcements.append(added)
	check(not rewards.snapshot(2).sealed and rewards.snapshot(2).count == 6, "Adds expand count and reopen registration")
	check(rewards.seal_wave(2) and rewards.snapshot(2).paid == 8, "Re-sealing neither refunds nor pays")
	units[1].hurt(1000, tower_source)
	check(income - wave_income == 8, "A lower cumulative target after adds never produces negative income")
	for index in reinforcements.size():
		var previous_income: int = income
		reinforcements[index].hurt(1000, hero)
		check(income >= previous_income and income - wave_income <= 24, "Dynamic count maintains monotonic payouts within budget")
	check(income - wave_income == 24 and rewards.snapshot(2).cleared, "Final reinforcement still settles only the original fixed budget")
	dispose(units)
	dispose(reinforcements)
	units = pack(3, 3)
	check(rewards.defeat(units[0]) == 0, "Living units cannot impersonate death")
	check(not rewards.register_enemy(3, units[0]), "Duplicate registration cannot increase the denominator")
	check(rewards.begin_wave(4), "Another wave may coexist")
	check(not rewards.register_enemy(4, units[0]), "One instance cannot register in two waves")
	wave_income = income
	units[0].hurt(1000, hero)
	var lost: BattleUnit = units[1]
	lost.queue_free()
	await process_frame
	check(not is_instance_valid(lost), "Ledger does not own dead nodes strongly")
	check(rewards.defeat(lost) == 0, "A freed object cannot cause typed-reference errors or fake kills")
	units[2].hurt(1000, tower_source)
	check(income - wave_income == 11 and not rewards.snapshot(3).cleared, "Freed unreported enemy never silently becomes a completion reward")
	check(rewards.snapshot(3).remaining == 13, "Unclaimed completion remains unclaimed")
	rewards.reset()
	check(rewards.snapshot(3).is_empty() and not units[0].has_meta("wave_reward_id"), "Phase reset clears ledgers and live-node metadata")
	check(rewards.defeat(units[0]) == 0, "Old deaths cannot pay after reset")
	dispose(units)
	check(rewards.begin_wave(5), "Empty wave can open")
	check(rewards.seal_wave(5) and rewards.snapshot(5).cleared and rewards.snapshot(5).paid == 0, "Empty wave never gives free budget")
	check(not rewards.begin_wave(-1) and not rewards.begin_wave(6, -1), "Invalid wave identifiers and budgets are rejected")
	check(rewards.begin_wave(7), "Eligibility test opens a valid wave")
	check(not rewards.register_enemy(7, hero) and not rewards.register_enemy(7, tower_source), "Friendly and building units cannot register as payable enemies")
	check(not rewards.register_enemy(7, 7) and rewards.defeat(7) == 0, "Invalid scalar references are safely rejected")
	var ignored := enemy()
	check(not rewards.register_enemy(999, ignored), "Unknown wave cannot become an implicit extra budget")
	ignored.alive = false
	check(not rewards.register_enemy(7, ignored), "Dead enemy cannot register")
	ignored.queue_free()
	# Even an out-of-order caller that kills before sealing cannot mint final money.
	check(rewards.begin_wave(8), "Out-of-order caller opens a budget")
	var unsealed := enemy()
	check(rewards.register_enemy(8, unsealed), "Unsealed caller registers its one unit")
	wave_income = income
	unsealed.hurt(1000, hero)
	check(income - wave_income == 16 and not rewards.snapshot(8).cleared, "Unsealed last death gets only rolling money")
	check(rewards.seal_wave(8) and income - wave_income == 16, "Late sealing never synthesizes a payout")
	check(rewards.defeat(unsealed) == 0, "Repeating death after late sealing cannot recover completion money")
	unsealed.queue_free()
	rewards.reset()
	var run_start_income: int = income
	for wave_id in 20:
		units = pack(wave_id, 4 + wave_id % 7)
		for index in units.size():
			units[index].hurt(1000, hero if index % 2 == 0 else tower_source)
			check(rewards.defeat(units[index]) == 0, "Every standard-wave death remains idempotent")
		check(rewards.snapshot(wave_id).paid == 24, "Every fully cleared standard wave pays exactly 24")
		dispose(units)
	check(income - run_start_income == 480, "Twenty completed waves have exactly 480 total budget")
	rewards.reset()
	hero.queue_free()
	tower_source.queue_free()
	for _frame in 3: await process_frame
	print("WAVE_REWARDS_FIXTURE_OK checks=%d" % checks if failures == 0 else "WAVE_REWARDS_FIXTURE_FAILED failures=%d" % failures)
	quit(failures)
