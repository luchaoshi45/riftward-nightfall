extends SceneTree
## Focused acceptance for the two explicit salvage-draw risk modes.  The
## production scene remains covered by the existing salvage-draw harness; this
## fixture isolates wallet/RNG/quota invariants so mode choice cannot hide
## behind a fabricated campaign reward.
const Draw := preload("res://scripts/salvage_draw.gd")
const RunSession := preload("res://scripts/run_session.gd")
const SEED := 20261006

class FakeActor extends Node3D:
	var alive := true
	var hp := 100.0

class FakeExploration extends Node:
	var route_day := 2
	var day_discoveries := 1

class FakeGame extends Node3D:
	var quitting := false
	var restart_pending := false
	var phase := "day"
	var phase_time := 90.0
	var day_number := 2
	var scrap := 1000
	var beacon_hp := 100.0
	var hero := FakeActor.new()
	var exploration := FakeExploration.new()

var checks := 0
var failures: Array[String] = []
var fixtures: Array[Node] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func oracle(seed_value: int, day_id: int = 2) -> RandomNumberGenerator:
	var random := RandomNumberGenerator.new()
	random.seed = RunSession.stream_seed(seed_value ^ 0x5a17c9 ^ (day_id * 104729), "salvage_draw")
	return random

func new_fixture(seed_value: int = SEED) -> Array:
	var game := FakeGame.new()
	game.add_child(game.hero)
	game.add_child(game.exploration)
	fixtures.append(game)
	game.hero.position = Vector3(0, 5, 0)
	var draw := Draw.new()
	draw.setup(game, seed_value)
	draw.begin_day()
	return [game, draw]

func cleanup_fixtures() -> void:
	for fixture: Node in fixtures:
		if is_instance_valid(fixture):fixture.free()
	fixtures.clear()

func _initialize() -> void:
	mode_contract()
	atomic_and_rng()
	lifecycle()
	cleanup_fixtures()
	print("NIGHTFALL_SALVAGE_DRAW_RISK_%s checks=%d modes=safe,jackpot" % ["OK" if failures.is_empty() else "FAILED", checks])
	quit(0 if failures.is_empty() else 1)

func mode_contract() -> void:
	var pair := new_fixture()
	var game: FakeGame = pair[0]
	var draw: RefCounted = pair[1]
	var initial: Dictionary = draw.snapshot()
	check(initial.modes == ["safe", "jackpot"], "Public modes expose the legacy safe mode and the explicit jackpot mode")
	check(String(initial.selected_mode) == "safe" and int(initial.stake) == 30, "A fresh daylight selects the legacy safe stake")
	check(draw.mode_options().size() == 2 and int(draw.mode_options()[1].stake) == 60, "Public mode options expose the jackpot stake")
	var locked: Dictionary = draw.draw("jackpot")
	check(not bool(locked.ok) and String(locked.reason) == "jackpot_requires_first", "Jackpot cannot bypass the first safe draw")
	check(draw.snapshot() == initial and game.scrap == 1000, "Locked jackpot selection leaves quota, receipt, RNG and wallet untouched")
	check(draw.select_mode("jackpot") == false and String(draw.snapshot().selected_mode) == "safe", "Selecting jackpot before the first draw cannot mutate the selected mode")
	var safe: Dictionary = draw.draw()
	check(bool(safe.ok) and String(safe.mode) == "safe" and int(safe.cost) == 30, "Legacy no-argument draw remains a safe 30-part transaction")
	check(int(draw.snapshot().used) == 1 and int(draw.snapshot().stake) == 30, "The first safe draw opens the second-draw choice without changing the daily limit")
	check(draw.select_mode("jackpot") and String(draw.snapshot().selected_mode) == "jackpot" and int(draw.snapshot().stake) == 60, "Jackpot selection is available after the first committed draw")
	check(draw.mode_reason("invalid") == "invalid_mode", "Unknown modes are rejected explicitly")
	check(draw.mode_reason("jackpot").is_empty(), "Jackpot mode is legal after the first draw")

func atomic_and_rng() -> void:
	var pair := new_fixture()
	var game: FakeGame = pair[0]
	var draw: RefCounted = pair[1]
	var random := oracle(SEED)
	var first_roll := random.randi_range(0, 99)
	var safe: Dictionary = draw.draw("safe")
	check(int(safe.roll) == first_roll and int(safe.payout) == (120 if first_roll >= 90 else (40 if first_roll >= 60 else 10)), "Safe mode keeps the original exact seeded payout buckets")
	var rng_before := int(draw.snapshot().rng_state)
	var wallet_before := game.scrap
	var selected: bool = draw.select_mode("jackpot")
	check(selected and int(draw.snapshot().rng_state) == rng_before and game.scrap == wallet_before, "Switching modes consumes neither RNG nor wallet")
	var second_roll := random.randi_range(0, 99)
	var jackpot: Dictionary = draw.draw("jackpot")
	var expected := 600 if second_roll >= 95 else (120 if second_roll >= 70 else 0)
	check(int(jackpot.roll) == second_roll and int(jackpot.payout) == expected, "Jackpot uses the independent second RNG draw and exact 70/25/5 buckets")
	check(int(jackpot.cost) == 60 and int(jackpot.net) == expected - 60 and int(jackpot.wallet_before) == wallet_before, "Jackpot receipt records its 60-part atomic stake and net")
	check(game.scrap == wallet_before - 60 + expected and int(draw.snapshot().used) == 2, "Jackpot commits one wallet assignment and the second quota slot")
	var before: Dictionary = draw.snapshot()
	var rejected: Dictionary = draw.draw("safe")
	check(not bool(rejected.ok) and String(rejected.reason) == "daily_limit" and draw.snapshot() == before, "A third draw rejects without wallet, receipt, quota or RNG mutation")

func lifecycle() -> void:
	var pair := new_fixture()
	var game: FakeGame = pair[0]
	var draw: RefCounted = pair[1]
	check(draw.draw("safe").ok, "Lifecycle fixture can commit the first draw")
	check(draw.select_mode("jackpot"), "Lifecycle fixture can select jackpot")
	var before_night: Dictionary = draw.snapshot()
	draw.on_night()
	check(int(draw.snapshot().used) == 1 and String(draw.snapshot().selected_mode) == "safe" and int(draw.snapshot().stake) == 30 and int(draw.snapshot().remaining) == 0, "Night closes purchases while preserving the earned receipt and resetting the pending mode")
	game.phase = "night"
	check(not bool(draw.draw("jackpot").ok), "Night rejects a retained jackpot attempt")
	game.day_number = 3
	game.exploration.route_day = 3
	game.phase = "day"
	game.phase_time = 90.0
	draw.begin_day()
	var next: Dictionary = draw.snapshot()
	check(int(next.used) == 0 and String(next.selected_mode) == "safe" and int(next.stake) == 30 and int(next.remaining) == 2 and next.last == before_night.last, "A new daylight clears the pending mode and quota while retaining the prior receipt history")
	check(int(next.rng_state) == int(oracle(SEED, 3).state), "A new daylight starts its own deterministic draw stream")
	var retained: RefCounted = draw
	var parts_before_clear: int = game.scrap
	draw.clear()
	var cleared: Dictionary = draw.snapshot()
	check(not bool(cleared.available) and int(cleared.used) == 0 and String(cleared.selected_mode) == "safe" and int(cleared.stake) == 30, "Clear retires the current draw state and restores the safe defaults")
	check(not bool(retained.draw("jackpot").ok) and game.scrap == parts_before_clear, "An externally retained cleared draw cannot charge the new run")
	check(before_night.last.is_empty() == false, "The lifecycle fixture retains a real first receipt before dusk")
