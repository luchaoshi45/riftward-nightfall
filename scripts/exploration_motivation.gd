extends Node
class_name ExplorationMotivation
## Small, readable incentives that turn repeated scavenging into route decisions.

const STREAK_WINDOW := 22.0
const DEEP_RADIUS := 42.0
const ROUTE_KINDS := ["ember_bloom", "memory_crystal", "supply_cache", "waylight"]
const KIND_NAMES := {"ember_bloom":"余烬花", "memory_crystal":"余烬晶簇", "supply_cache":"补给箱", "waylight":"灯碑"}

var game: Node3D
var route_seed := 0
var route_day := 1
var route_order: Array[String] = []
var day_kinds: Dictionary = {}
var run_kinds: Dictionary = {}
var last_kind := ""
var streak := 0
var streak_time := 0.0
var best_streak := 0
var deep_discoveries := 0
var night_discoveries := 0
var phase_night_discoveries := 0
var day_discoveries := 0
var run_discoveries := 0
var full_set_claimed := false
var waylight_count := 0
var network_time := 0.0
var speed_time := 0.0
var speed_bonus := 0.0
var last_event := ""
var event_history: Array[String] = []
var affinity_kinds: Array[String] = []
var affinity_time := 0.0

func setup(owner_game: Node3D, seed_value: int = 0) -> void:
	game = owner_game
	route_seed = seed_value
	reset_run()

func reset_run() -> void:
	set_route_order(1)
	day_kinds.clear()
	run_kinds.clear()
	last_kind = ""
	streak = 0
	streak_time = 0.0
	best_streak = 0
	deep_discoveries = 0
	night_discoveries = 0
	phase_night_discoveries = 0
	day_discoveries = 0
	run_discoveries = 0
	full_set_claimed = false
	waylight_count = 0
	network_time = 0.0
	speed_time = 0.0
	speed_bonus = 0.0
	last_event = ""
	event_history.clear()
	affinity_kinds.clear()
	affinity_time = 0.0

func begin_day(day_id: int = 1) -> void:
	set_route_order(day_id)
	day_kinds.clear()
	last_kind = ""
	streak = 0
	streak_time = 0.0
	full_set_claimed = false
	day_discoveries = 0
	phase_night_discoveries = 0
	affinity_kinds.clear()
	affinity_time = 0.0
	last_event = "新的白昼路线：换一种发现类型，连段奖励会更高"

func set_route_order(day_id: int) -> void:
	var previous_order: Array[String]=route_order.duplicate()
	route_day = maxi(1, day_id)
	route_order = route_template()
	# A zero seed is reserved for standalone module tests and keeps the
	# historical order. Production runs pass RunBuild.seed_value, so the same
	# seed/day pair always recreates the same route while another run can ask
	# for a different next discovery without changing rewards.
	if route_seed == 0:return
	var route_rng := RandomNumberGenerator.new()
	route_rng.seed = abs(route_seed ^ (route_day * 10007 + 7919))
	for index in range(route_order.size()-1, 0, -1):
		var swap_index:=route_rng.randi_range(0, index)
		var swap_kind: String=route_order[index]
		route_order[index]=route_order[swap_index]
		route_order[swap_index]=swap_kind
	if route_day>1 and route_order==previous_order:
		var last_kind: String=route_order.pop_back()
		route_order.push_front(last_kind)

func route_template() -> Array[String]:
	var result: Array[String] = []
	for kind: String in ROUTE_KINDS:
		result.append(kind)
	return result

func begin_night() -> void:
	last_kind = ""
	streak = 0
	streak_time = 0.0
	phase_night_discoveries = 0

func tick(delta: float) -> void:
	if not is_instance_valid(game):
		return
	if game.phase in ["paused", "draft", "ended"]:
		return
	streak_time = maxf(0.0, streak_time-delta)
	if streak_time <= 0.0:
		streak = 0
	speed_time = maxf(0.0, speed_time-delta)
	if speed_time <= 0.0:
		speed_bonus = 0.0
	network_time = maxf(0.0, network_time-delta)
	affinity_time = maxf(0.0, affinity_time-delta)
	if affinity_time <= 0.0:
		affinity_kinds.clear()

func set_waylight_count(count: int) -> void:
	waylight_count = maxi(0, count)
	if waylight_count >= 2:
		network_time = maxf(network_time, 18.0)

func speed_bonus_value() -> float:
	return speed_bonus if speed_time > 0.0 else 0.0

func network_active() -> bool:
	return network_time > 0.0 and waylight_count >= 2

func arm_contract_affinity(kinds: Array) -> void:
	affinity_kinds.clear()
	for kind in kinds:
		if not affinity_kinds.has(String(kind)):
			affinity_kinds.append(String(kind))
	affinity_time = 75.0 if not affinity_kinds.is_empty() else 0.0
	if not affinity_kinds.is_empty():
		last_event = "委托共鸣已准备 · 下一次匹配探索额外获得零件"

func affinity_active() -> bool:
	return affinity_time > 0.0 and not affinity_kinds.is_empty()

func record(kind: String, point: Vector3, phase_name: String) -> Dictionary:
	var result := {"scrap": 0, "event": "", "speed_seconds": 0.0}
	var events: Array[String] = []
	var category := kind if not kind.is_empty() else "other"
	run_kinds[category] = int(run_kinds.get(category, 0))+1
	day_kinds[category] = true
	day_discoveries += 1
	run_discoveries += 1
	var route_kind: bool = category in ROUTE_KINDS
	if phase_name == "night" and route_kind:
		night_discoveries += 1
		phase_night_discoveries += 1

	if route_kind and category != last_kind and streak_time > 0.0:
		streak += 1
	elif route_kind:
		streak = 1
	if route_kind:
		last_kind = category
		streak_time = STREAK_WINDOW
		best_streak = maxi(best_streak, streak)
		# Ordinary salvage and wildlife still count towards the five-visit
		# milestone, but may not replay a previously reached route tier.
		if streak == 2:
			result.scrap += 4
			speed_bonus = .8
			speed_time = 18.0
			result.speed_seconds = 18.0
			events.append("探索连段 2")
		elif streak == 3:
			result.scrap += 18
			events.append("探索连段 3")
	# Collecting all four types is a set reward, independent of the 22-second
	# chain. It can share the final discovery with a chain or affinity reward.
	if route_kind and not full_set_claimed and _has_full_set():
		full_set_claimed = true
		result.scrap += 52
		events.append("完整搜寻")

	if route_kind and point.distance_to(Vector3.ZERO) >= DEEP_RADIUS:
		deep_discoveries += 1
		result.scrap += 8
		events.append("深入荒原")
	if route_kind and phase_name == "night" and phase_night_discoveries <= 2:
		result.scrap += 9
		events.append("夜行搜寻")
	if route_kind and network_active() and category != "waylight":
		result.scrap += 2
		events.append("灯网共鸣")
	if category in affinity_kinds and affinity_active():
		result.scrap += 8
		events.append("委托共鸣")
		affinity_kinds.clear()
		affinity_time = 0.0

	result.event = " · ".join(events)
	if not result.event.is_empty():
		last_event = result.event
		event_history.push_back(result.event)
		if event_history.size() > 6:
			event_history.pop_front()
	return result

func _has_full_set() -> bool:
	for kind: String in ROUTE_KINDS:
		if not day_kinds.has(kind):
			return false
	return true

func next_kind() -> String:
	for kind: String in route_order:
		if not day_kinds.has(kind):
			return kind
	return ""

func route_text() -> String:
	var collected := 0
	for kind: String in route_order:
		if day_kinds.has(kind):
			collected += 1
	var next := next_kind()
	if next.is_empty():
		return "完整搜寻已完成" if full_set_claimed else "四类已齐 · 合集尚未领取"
	return "路线 %d/4 · 下一站 %s" % [collected, KIND_NAMES.get(next, next)]

func streak_text() -> String:
	if streak<=0 or streak_time<=0.0:return "换类连段 · 22秒内采集不同类型"
	return "换类连段 %d · 余时 %.1f秒" % [streak, streak_time]

func streak_reward_text() -> String:
	if streak_time>0.0 and streak==1:return "下一段：+4零件 · 加速18秒"
	if streak_time>0.0 and streak==2:return "下一段：+18零件"
	return "同类会重置 · 废墟与动物不续段"

func collection_reward_text() -> String:
	return "四类合集已领 · 次日可重新收集" if full_set_claimed else "四类各一次：+52零件"

func affinity_text() -> String:
	if not affinity_active():return ""
	var names: Array[String] = []
	for kind in affinity_kinds:names.append(String(KIND_NAMES.get(kind,kind)))
	return "共鸣 %s · +8零件 · %.0f秒" % ["/".join(names),ceilf(affinity_time)]

func run_summary() -> String:
	return "本局探索 %d 次 · 最长连段 %d · 深处 %d · 夜行 %d" % [run_discoveries, best_streak, deep_discoveries, night_discoveries]

func route_summary() -> String:
	var names := {"ember_bloom":"余烬花", "memory_crystal":"余烬晶簇", "supply_cache":"补给箱", "waylight":"灯碑"}
	var completed: Array[String] = []
	var missing: Array[String] = []
	for kind: String in route_order:
		if run_kinds.has(kind): completed.append(String(names[kind]))
		else: missing.append(String(names[kind]))
	var text := "路线完成 %d/4 · 已发现：%s" % [completed.size(), "、".join(completed) if not completed.is_empty() else "暂无"]
	if not missing.is_empty(): text += " · 下局可追：%s" % "、".join(missing)
	return text
