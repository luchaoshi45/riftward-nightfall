extends Node
## Optional overlay on existing actions. Controller owns rewards and all visuals.
signal progress_changed(text: String)

const TITLES := {"salvage":"废墟补给", "generator":"能源交接", "escort":"哨兵归队", "nest":"封巢报告"}
const REWARD_SCRAP := 30
const REWARD_MEMORY := 8
const EARLY_RETURN_SECONDS := 15.0
var game: Node3D
var run_seed := 0
var day_id := -1
var kind := ""
var status := "idle"
var targets: Array[Dictionary] = []
var done: Dictionary = {}
var pending_reward: Dictionary = {}
var last_text := ""

func setup(owner_game: Node3D, seed_value: int = -1) -> void:
	game = owner_game
	run_seed = seed_value
	if seed_value == -1:
		var seed_rng := RandomNumberGenerator.new()
		seed_rng.randomize()
		run_seed = seed_rng.randi()
	day_id = -1
	status = "idle"
	kind = ""
	targets.clear()
	done.clear()
	pending_reward.clear()
	last_text = ""

func candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var salvage: Array[Dictionary] = []
	for i in game.world.salvage.size():
		var item: Dictionary = game.world.salvage[i]
		if not item.collected and reachable_range(item.position):
			salvage.append({"index":i, "source":item, "position":item.position})
	# A compact pair makes one excursion useful, rather than demanding a map sweep.
	for a in salvage.size():
		for b in range(a + 1, salvage.size()):
			if flat_distance(salvage[a].position, salvage[b].position) <= 14.0:
				result.append({"kind":"salvage", "targets":[salvage[a], salvage[b]]})
	for category: String in ["generator", "escort", "nest"]:
		var sources: Array = game.world.nests if category == "nest" else (game.expeditions.generators if category == "generator" else game.expeditions.camps)
		for i in sources.size():
			var source: Dictionary = sources[i]
			var available: bool = not source.cleansed if category == "nest" else source.state == ("ready" if category == "generator" else "waiting")
			if available and reachable_range(source.position):
				result.append({"kind":category, "targets":[{"index":i, "source":source, "position":source.position}]})
	return result

func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x-b.x, a.z-b.z).length()

func reachable_range(point: Vector3) -> bool:
	return flat_distance(point, Vector3.ZERO) >= 16.0 and flat_distance(point, Vector3.ZERO) <= 45.0 and game.outpost_walkable(point)

func on_day() -> void:
	if game.phase != "day" or int(game.day_number) <= day_id:
		return
	day_id = int(game.day_number)
	done.clear()
	targets.clear()
	pending_reward.clear()
	kind = ""
	var options := candidates()
	if options.is_empty():
		status = "unavailable"
	else:
		# Choose the category first: many salvage pairs must not drown out other types.
		var categories: Array[String] = []
		for option in options:
			if not categories.has(option.kind): categories.append(option.kind)
		var rng := RandomNumberGenerator.new()
		rng.seed = run_seed + day_id * 7919
		kind = categories[rng.randi_range(0, categories.size()-1)]
		var matching: Array[Dictionary] = []
		for option in options:
			if option.kind == kind: matching.append(option)
		var chosen: Dictionary = matching[rng.randi_range(0, matching.size()-1)]
		for target: Dictionary in chosen.targets: targets.append(target)
		status = "active"
	emit_progress()

func on_night() -> void:
	if status == "active": status = "expired"
	emit_progress()

func tick(_delta: float) -> void:
	if not is_instance_valid(game): return
	if game.phase in ["paused", "draft"]: return
	if game.phase != "day" or game.phase_time <= 0.0:
		on_night()
		return
	if status != "active": return
	for target in targets:
		var source: Dictionary = target.source
		var completed := false
		match kind:
			"salvage": completed = source.collected
			"generator": completed = source.state == "complete"
			"escort": completed = source.state == "delivered"
			"nest": completed = source.cleansed
		if completed: done[int(target.index)] = true
	if done.size() == targets.size() and returned_home():
		status = "completed"
		var early: bool = game.phase_time >= EARLY_RETURN_SECONDS
		pending_reward = {"id":"day_contract_%d" % day_id, "day":day_id, "kind":kind, "scrap":REWARD_SCRAP + (10 if early else 0), "memory":REWARD_MEMORY, "early_return":early}
	emit_progress()

func returned_home() -> bool:
	return game.hero.alive and game.hero.position.y > 4.8 and flat_distance(game.hero.position, Vector3.ZERO) < 6.2

func take_reward_request() -> Dictionary:
	# The only payout interface; progress signals carry no spendable reward.
	var result := pending_reward.duplicate(true)
	pending_reward.clear()
	return result

func on_action() -> void:
	# Call after a successful existing action, before a respawn can replace its state.
	# This reads authoritative state; it never accepts an unverified completion claim.
	tick(0.0)

func progress_text() -> String:
	match status:
		"idle": return ""
		"unavailable": return "今日委托 · 无可用目标，可自由探索"
		"expired": return "日落收尾 · 委托未交回，无惩罚"
		"completed": return "委托已交回 · 奖励已请求"
	var locations: Array[String] = []
	for target in targets:
		locations.append("(%d, %d)" % [roundi(target.position.x), roundi(target.position.z)])
	var action: String = "采集指定两处废墟" if kind == "salvage" else ("取回指定能源芯" if kind == "generator" else ("护送指定哨兵" if kind == "escort" else "封闭指定夜巢"))
	var instruction: String = "返回灯塔交回" if done.size() == targets.size() else action + " " + "、".join(locations)
	if done.is_empty() and not targets.is_empty():
		var source: Dictionary = targets[0].source
		if kind == "generator" and source.state == "active":
			instruction += " · 充能%d%%，清除来袭" % roundi(float(source.progress)/12.0*100.0)
		elif kind == "escort" and source.state == "escort":
			instruction += " · 哨兵跟随中"
	return "可选 · %s %d/%d · %s · 日落前交回 +30零件/+8记忆，提前15秒再+10零件" % [TITLES[kind], done.size(), targets.size(), instruction]

func emit_progress() -> void:
	var value := progress_text()
	if value != last_text:
		last_text = value
		progress_changed.emit(value)
