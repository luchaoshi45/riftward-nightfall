extends Node
## Optional overlay on existing actions. Controller owns rewards and all visuals.
signal progress_changed(text: String)

const TITLES := {"salvage":"废墟补给", "generator":"能源交接", "escort":"哨兵归队", "nest":"封巢报告"}
const REWARD_SCRAP := 30
const REWARD_MEMORY := 8
const EARLY_RETURN_SECONDS := 15.0
const OFFER_RISK_SECONDS := [0.0, 8.0, 16.0]
const OFFER_NAMES := ["稳妥路线", "加码路线", "孤注路线"]
const AFFINITY_KINDS := {"salvage":["ember_bloom", "supply_cache"], "generator":["waylight"], "escort":["memory_crystal"], "nest":["waylight", "ember_bloom"]}
var game: Node3D
var run_seed := 0
var day_id := -1
var kind := ""
var status := "idle"
var targets: Array[Dictionary] = []
var offers: Array[Dictionary] = []
var selected_offer := 0
var progress_started := false
var selected_reward := {"scrap": REWARD_SCRAP, "memory": REWARD_MEMORY, "risk_seconds": 0.0}
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
	offers.clear()
	selected_offer=0
	progress_started=false
	done.clear()
	pending_reward.clear()
	selected_reward={"scrap":REWARD_SCRAP,"memory":REWARD_MEMORY,"risk_seconds":0.0}
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

func seeded_order(values: Array, rng: RandomNumberGenerator) -> Array:
	# Array.shuffle() uses the process-global RNG. Keep offers replayable for a
	# run seed by drawing without replacement from the local RNG. Drawing from
	# the front-sized pool also preserves the previous single-contract first
	# draw, so old seeded runs keep their opening route.
	var remaining: Array = values.duplicate()
	var result: Array = []
	while not remaining.is_empty():
		var pick := rng.randi_range(0, remaining.size() - 1)
		result.append(remaining.pop_at(pick))
	return result

func live_offer(option: Dictionary) -> Dictionary:
	# Keep each target's source dictionary owned by the world/expedition module.
	# A deep duplicate would make F actions update a stale contract copy.
	var offer: Dictionary = option.duplicate(false)
	var live_targets: Array[Dictionary] = []
	for target: Dictionary in option.targets:
		live_targets.append(target.duplicate(false))
	offer["targets"] = live_targets
	return offer

func reachable_range(point: Vector3) -> bool:
	return flat_distance(point, Vector3.ZERO) >= 16.0 and flat_distance(point, Vector3.ZERO) <= 45.0 and game.outpost_walkable(point)

func on_day() -> void:
	if game.phase != "day" or int(game.day_number) <= day_id:
		return
	day_id = int(game.day_number)
	done.clear()
	targets.clear()
	offers.clear()
	selected_offer=0
	progress_started=false
	pending_reward.clear()
	kind = ""
	var options := candidates()
	if options.is_empty():
		status = "unavailable"
	else:
		# Offer up to three distinct routes. The first keeps the old safe reward so
		# existing runs remain predictable; later offers pay for taking a longer route.
		var categories: Array[String] = []
		for option in options:
			if not categories.has(option.kind): categories.append(option.kind)
		var rng := RandomNumberGenerator.new()
		rng.seed = run_seed + day_id * 7919
		var shuffled := seeded_order(categories, rng)
		for offer_index in mini(3,shuffled.size()):
			var offer_kind: String=shuffled[offer_index]
			var matching: Array[Dictionary] = []
			for option in options:
				if option.kind == offer_kind: matching.append(option)
			var chosen: Dictionary = matching[rng.randi_range(0, matching.size()-1)]
			var offer: Dictionary=live_offer(chosen)
			offer["risk"] = offer_index
			offer["risk_seconds"] = OFFER_RISK_SECONDS[offer_index]
			offer["name"] = OFFER_NAMES[offer_index]
			offer["scrap"] = REWARD_SCRAP+offer_index*20
			offer["memory"] = REWARD_MEMORY+offer_index*4
			offers.append(offer)
		_select_offer(0)
		status = "active"
	emit_progress()

func on_night() -> void:
	if status == "active": status = "expired"
	emit_progress()

func choose_offer(index: int) -> bool:
	if game.phase!="day" or status!="active" or progress_started:return false
	if index<0 or index>=offers.size():return false
	_select_offer(index)
	emit_progress()
	return true

func offer_summary(index: int) -> String:
	if index < 0 or index >= offers.size(): return ""
	var offer: Dictionary = offers[index]
	var risk_seconds := int(offer.get("risk_seconds", 0.0))
	var risk_text := "无额外截止" if risk_seconds <= 0 else "提前%d秒截止" % risk_seconds
	return "%s · +%d零件/+%d记忆 · %s" % [String(offer.get("name", "方案%d" % (index + 1))), int(offer.get("scrap", REWARD_SCRAP)), int(offer.get("memory", REWARD_MEMORY)), risk_text]

func _select_offer(index: int) -> void:
	selected_offer=index
	var offer: Dictionary=offers[index]
	kind=String(offer.kind)
	targets.clear()
	for target: Dictionary in offer.targets:targets.append(target)
	selected_reward={"scrap":int(offer.scrap),"memory":int(offer.memory),"risk_seconds":float(offer.get("risk_seconds", 0.0))}

func tick(_delta: float) -> void:
	if not is_instance_valid(game): return
	if game.phase in ["paused", "draft"]: return
	if game.phase != "day" or game.phase_time <= 0.0:
		on_night()
		return
	if status != "active": return
	var risk_seconds := float(selected_reward.get("risk_seconds", 0.0))
	if risk_seconds <= 0.0 and selected_offer < offers.size():
		risk_seconds = float(offers[selected_offer].get("risk_seconds", 0.0))
	if done.size() < targets.size() and risk_seconds > 0.0 and game.phase_time <= risk_seconds:
		status = "expired"
		emit_progress()
		return
	for target in targets:
		var source: Dictionary = target.source
		var completed := false
		match kind:
			"salvage": completed = source.collected
			"generator": completed = source.state == "complete"
			"escort": completed = source.state == "delivered"
			"nest": completed = source.cleansed
		if completed: done[int(target.index)] = true
	if not done.is_empty():progress_started=true
	if done.size() == targets.size() and returned_home():
		status = "completed"
		var early: bool = game.phase_time >= EARLY_RETURN_SECONDS
		pending_reward = {"id":"day_contract_%d" % day_id, "day":day_id, "kind":kind, "scrap":int(selected_reward.scrap) + (10 if early else 0), "memory":int(selected_reward.memory), "early_return":early, "affinity":AFFINITY_KINDS.get(kind, []).duplicate()}
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
	var reward_text: String=offer_summary(selected_offer)
	var switch_hint := " · 4/5/6 可换方案" if not progress_started and offers.size()>1 else (" · 方案已锁定" if progress_started else "")
	return "可选 · 方案%d/%d · %s %d/%d · %s · %s · 日落前交回，提前15秒再+10零件%s" % [selected_offer+1,offers.size(),TITLES[kind], done.size(), targets.size(), instruction, reward_text, switch_hint]

func emit_progress() -> void:
	var value := progress_text()
	if value != last_text:
		last_text = value
		progress_changed.emit(value)
