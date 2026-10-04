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
const BONUS_PAYOUTS := {
	"ember_bloom":{"scrap":18, "memory":3},
	"memory_crystal":{"scrap":8, "memory":8},
	"supply_cache":{"scrap":26, "memory":5},
	"waylight":{"scrap":12, "memory":4}
}
const BONUS_TITLES := {"ember_bloom":"余烬花", "memory_crystal":"记忆晶簇", "supply_cache":"遗落补给箱", "waylight":"引路灯碑"}
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
var bonus_target: Dictionary = {}
var bonus_done := false
var bonus_choice := ""
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
	bonus_target.clear()
	bonus_done=false
	bonus_choice=""
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
	bonus_target.clear()
	bonus_done=false
	bonus_choice=""
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
	if status == "active":
		status = "expired"
	elif status in ["bonus_offer", "returning", "bonus_active"]:
		# The field work is already complete, so dusk preserves the primary
		# contract payout even when the optional detour was abandoned.
		status="completed"
		pending_reward=build_reward(false,false)
		if is_instance_valid(game):game.notify("日落收尾 · 主委托保底奖励到账，追加补给已放弃",3)
	emit_progress()

func choose_offer(index: int) -> bool:
	if game.phase!="day" or status!="active" or progress_started:return false
	if index<0 or index>=offers.size():return false
	_select_offer(index)
	emit_progress()
	return true

func choose_bonus(index: int) -> bool:
	if game.phase!="day" or status!="bonus_offer":return false
	if index==0:
		bonus_choice="return"
		status="returning"
		emit_progress()
		return true
	if index!=1:return false
	var candidate:=bonus_candidate()
	if candidate.is_empty():return false
	bonus_target=candidate
	bonus_done=false
	bonus_choice="scavenge"
	status="bonus_active"
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

func bonus_source() -> Dictionary:
	if bonus_target.is_empty() or not is_instance_valid(game):return {}
	var discoveries: Node=game.get("discoveries")
	if not is_instance_valid(discoveries):return {}
	var index:=int(bonus_target.get("index",-1))
	if index<0 or index>=discoveries.items.size():return {}
	var source: Dictionary=discoveries.items[index]
	if int(source.get("serial",-1))!=int(bonus_target.get("serial",-2)):return {}
	return source

func bonus_finished() -> bool:
	var source:=bonus_source()
	if source.is_empty():return false
	var state:=String(source.get("state",""))
	return state in ["active", "cooling"]

func bonus_interaction_range(source: Dictionary) -> float:
	return 4.0 if String(source.get("kind",""))=="supply_cache" else 3.2

func route_distance(from: Vector3, to: Vector3) -> float:
	if game.can_traverse(from,to):return flat_distance(from,to)
	var start: Vector2i=game.nearest_navigation_cell(from,true)
	var finish: Vector2i=game.nearest_navigation_cell(to,false)
	if start.x==999 or finish.x==999:return INF
	var route: PackedVector2Array=game.hero_navigation.get_point_path(start,finish)
	if route.is_empty():return INF
	var previous:=Vector2(from.x,from.z)
	var distance:=0.0
	for point in route:
		distance+=previous.distance_to(point)
		previous=point
	return distance+previous.distance_to(Vector2(to.x,to.z))

func bonus_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not is_instance_valid(game):return result
	var discoveries: Node=game.get("discoveries")
	if not is_instance_valid(discoveries):return result
	for index in discoveries.items.size():
		var item: Dictionary=discoveries.items[index]
		if String(item.get("state",""))!="ready":continue
		var distance:=route_distance(game.hero.position,item.position)
		if not is_finite(distance) or distance>58.0:continue
		var payout: Dictionary=BONUS_PAYOUTS.get(String(item.kind),{"scrap":12,"memory":3})
		result.append({"index":index,"serial":int(item.get("serial",0)),"kind":String(item.kind),"position":item.position,"distance":distance,"scrap":int(payout.scrap),"memory":int(payout.memory)})
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		if not is_equal_approx(float(a.distance),float(b.distance)):return float(a.distance)<float(b.distance)
		return int(a.index)<int(b.index)
	)
	return result

func bonus_candidate() -> Dictionary:
	var candidates:=bonus_candidates()
	return candidates[0] if not candidates.is_empty() else {}

func bonus_summary() -> String:
	var candidate: Dictionary=bonus_target if not bonus_target.is_empty() else bonus_candidate()
	if candidate.is_empty():return "4 立即返家保底 · 暂无可达追加补给"
	var title: String=BONUS_TITLES.get(String(candidate.kind),"追加补给")
	var seconds:=float(candidate.distance)/maxf(1.0,float(game.hero.speed))+3.0
	return "5 贪一笔：%s · +%d零件/+%d记忆 · 往返约%.0f秒" % [title,int(candidate.scrap),int(candidate.memory),seconds*2.0]

func active_target_interaction() -> Dictionary:
	# The controller uses this read-only view before ordinary F actions. Keep
	# the authoritative source dictionary so a nearby discovery or animal
	# cannot steal the interaction for the marked contract target.
	if not is_instance_valid(game) or game.phase!="day":return {}
	if status=="bonus_active":
		if bonus_done or bonus_finished():return {}
		var bonus:=bonus_source()
		if bonus.is_empty():return {}
		var bonus_distance:=flat_distance(game.hero.position,bonus.position)
		if bonus_distance<=bonus_interaction_range(bonus):
			return {"kind":"bonus_discovery","index":int(bonus_target.index),"source":bonus,"position":bonus.position,"state":String(bonus.state),"distance":bonus_distance}
		return {}
	if status!="active":return {}
	if targets.is_empty() or done.size()>=targets.size():return {}
	for target: Dictionary in targets:
		var index:=int(target.get("index",-1))
		if done.has(index):continue
		var source: Dictionary=target.source
		if target_finished(source):continue
		var distance:=flat_distance(game.hero.position,target.position)
		var range:=target_interaction_range(source)
		if distance>range:continue
		return {"kind":kind,"index":index,"source":source,"position":target.position,"state":String(source.get("state","")),"distance":distance}
	return {}

func target_finished(source: Dictionary) -> bool:
	match kind:
		"salvage":return bool(source.get("collected",false))
		"generator","escort":return String(source.get("state","")) in ["complete","delivered"]
		"nest":return bool(source.get("cleansed",false))
	return false

func target_interaction_range(source: Dictionary) -> float:
	match kind:
		"salvage":return 2.4
		"generator":return 5.0 if String(source.get("state",""))=="active" else 3.4
		"escort":return 3.4
		"nest":return 3.6
	return 0.0

func mark_target_started() -> void:
	if status!="active":return
	progress_started=true
	emit_progress()

func tick(_delta: float) -> void:
	if not is_instance_valid(game): return
	if game.phase in ["paused", "draft"]: return
	if game.phase != "day" or game.phase_time <= 0.0:
		on_night()
		return
	if status == "bonus_active":
		if bonus_finished():
			bonus_done=true
			status="returning"
			if is_instance_valid(game):game.notify("追加补给已带走 · 返回灯塔领取额外奖励",3)
			emit_progress()
		return
	elif status != "active":
		if status=="returning" and returned_home():
			status="completed"
			var early: bool = game.phase_time >= EARLY_RETURN_SECONDS
			pending_reward=build_reward(early,bonus_done)
			emit_progress()
		return
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
	if done.size() == targets.size():
		status="bonus_offer"
	emit_progress()

func build_reward(early: bool, include_bonus: bool) -> Dictionary:
	var reward_scrap:=int(selected_reward.scrap)+(10 if early else 0)
	var reward_memory:=int(selected_reward.memory)
	if include_bonus:
		reward_scrap+=int(bonus_target.get("scrap",0))
		reward_memory+=int(bonus_target.get("memory",0))
	return {"id":"day_contract_%d" % day_id,"day":day_id,"kind":kind,"scrap":reward_scrap,"memory":reward_memory,"early_return":early,"bonus":include_bonus,"affinity":AFFINITY_KINDS.get(kind, []).duplicate()}

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
		"bonus_offer": return "主委托已完成 · 4 立即返家保底 / 5 贪一笔追加补给"
		"bonus_active": return "追加 %s · 完成后返回灯塔" % BONUS_TITLES.get(String(bonus_target.get("kind","")),"补给")
		"returning": return "委托目标已完成 · 返回灯塔领取奖励"
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
