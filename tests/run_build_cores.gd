extends SceneTree
const Build = preload("res://scripts/run_build.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func ids(cards: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for card: Dictionary in cards:
		result.append(card.id)
	return result

func run() -> void:
	check(Build.CARDS.size() == 18, "The existing card pool remains available")
	for core_index in range(3):
		for seed_value in [1, 17, 333, 99001]:
			var build = Build.new(seed_value)
			build.grant(Build.OPENING_SOURCE)
			check(build.draft(), "Opening draft is available")
			check(ids(build.offer) == ["core_storm", "core_flame", "core_guard"], "All opening paths are guaranteed")
			check(build.redraw() and build.rerolls == 2, "Opening redraw consumes its charge")
			check(ids(build.offer) == ["core_storm", "core_flame", "core_guard"], "Redraw cannot bypass opening cores")
			var chosen: Dictionary = build.choose(core_index)
			check(chosen.id == Build.CORE_CARDS[core_index].id, "Selected core matches the actual choice")
			check(build.has_core(chosen.id) and build.core_school() == core_index, "Core identity and school are explicit")
			check(build.stats[chosen.stat] == 1.0, "Combat core is exposed through stats")
			check(build.school_count(core_index) == 1, "Core counts toward its school without free numerical power")
			check(build.stats.attack == 0.0 and build.stats.spell == 0.0 and build.stats.health == 0.0, "Core grants behavior without full legendary stats")
			check(build.choose(core_index).is_empty(), "Choice cannot be claimed twice")
			for draft_number in range(12):
				build.grant("黎明或记忆奖励")
				check(build.draft(), "Later draft is available")
				var compatible := false
				var offered_ids: Dictionary = {}
				var legendary := false
				for card: Dictionary in build.offer:
					compatible = compatible or card.school == core_index
					legendary = legendary or card.rarity == 2
					check(not bool(card.get("core", false)), "Later drafts never grant a second behavior core")
					check(build.count(card.id) < card.cap, "Maxed cards are excluded")
					check(not offered_ids.has(card.id), "Offer contains unique candidates")
					offered_ids[card.id] = true
				check(compatible, "A supporting card is guaranteed while its school has candidates")
				if (build.selections + 1) % 5 == 0:
					check(legendary, "Every fifth choice retains its legendary guarantee")
				build.choose(draft_number % build.offer.size())
			check(build.memory_level == 0, "Opening and day choices do not advance memory costs")
	var explicit = Build.new(8)
	explicit.grant_opening("新的开局文字")
	explicit.draft()
	check(ids(explicit.offer) == ["core_storm", "core_flame", "core_guard"], "Explicit opening is independent of display wording")
	for remaining in [2, 1, 0]:
		check(explicit.redraw() and explicit.rerolls == remaining, "All opening rerolls consume exactly one charge")
	check(not explicit.redraw() and explicit.offer.size() == 3, "No-charge redraw keeps the available opening choice")
	explicit.choose(0)
	# A queued stale opening cannot bypass exclusive ownership.
	explicit.grant_opening()
	explicit.draft()
	for card: Dictionary in explicit.offer:
		check(not bool(card.get("core", false)), "Repeated opening requests become ordinary rewards")
	explicit.offer.clear()
	explicit.offer.append(Build.CORE_CARDS[1])
	check(explicit.choose(0).is_empty() and explicit.core_id() == "core_storm", "A stale injected core choice cannot replace or stack starting paths")
	var exhausted = Build.new(8)
	exhausted.grant_opening()
	exhausted.draft()
	exhausted.choose(1)
	for card: Dictionary in Build.CARDS:
		exhausted.owned[card.id] = card.cap
	exhausted.grant("所有卡已满")
	check(not exhausted.draft() and exhausted.pending == 0 and exhausted.queue.is_empty(), "An exhausted pool closes safely")
	var depleted_school = Build.new(8)
	depleted_school.grant_opening()
	depleted_school.draft()
	depleted_school.choose(2)
	for card: Dictionary in Build.CARDS:
		if card.school == 2:
			depleted_school.owned[card.id] = card.cap
	depleted_school.grant("相容卡已满")
	check(depleted_school.draft() and depleted_school.offer.size() == 3, "A depleted compatible school falls back to other legal cards")
	for card: Dictionary in depleted_school.offer:
		check(card.school != 2 and not bool(card.get("core", false)), "Fallback never grants capped or different cores")
	var capped_choice = Build.new(6)
	capped_choice.grant("测试")
	capped_choice.offer.append(Build.CARDS[0])
	capped_choice.owned.edge = 3
	check(capped_choice.choose(0).is_empty() and capped_choice.pending == 1, "A cap reached after drafting cannot be exceeded")
	var a = Build.new(333)
	var b = Build.new(333)
	a.grant_opening(); b.grant_opening(); a.draft(); b.draft(); a.choose(0); b.choose(0)
	for _step in range(20):
		a.grant("seed"); b.grant("seed"); a.draft(); b.draft()
		check(a.offer == b.offer, "Identical seeds and choices reproduce supporting drafts")
		a.choose(0); b.choose(0)
	var seeded_offers: Dictionary = {}
	for run_seed in [3, 9, 71, 819, 8001]:
		var seeded = Build.new(run_seed)
		seeded.grant_opening(); seeded.draft(); seeded.choose(1)
		seeded.grant("记忆奖励"); seeded.draft()
		seeded_offers[str(ids(seeded.offer))] = true
	check(seeded_offers.size() > 1, "Different run seeds vary later legal choices")
	var memory = Build.new(7)
	var costs: Array[int] = [120, 180, 260, 360, 500, 680, 884, 1150, 1495, 1944, 2528]
	for level in range(costs.size()):
		check(memory.memory_cost() == costs[level] and memory.memory_cost(level) == costs[level], "Next memory fee follows its independent sequence")
		check(memory.register_memory_upgrade() == costs[level] and memory.memory_level == level + 1, "Exactly one registration advances exactly one paid fee")
		memory.grant("记忆升级")
		memory.draft()
		memory.redraw()
		check(memory.memory_level == level + 1, "Opening or redrawing queued upgrades never charges another fee")
		memory.choose(0)
		check(memory.memory_level == level + 1, "Choosing queued upgrades never charges another fee")
	var fresh = Build.new(7)
	check(fresh.memory_level == 0 and fresh.memory_cost() == 120 and fresh.core_id().is_empty(), "A new run resets behavior and inscription progression")
	print("RUN_BUILD_CORES_OK checks=%d" % checks if failures == 0 else "RUN_BUILD_CORES_FAILED failures=%d" % failures)
	quit(failures)
