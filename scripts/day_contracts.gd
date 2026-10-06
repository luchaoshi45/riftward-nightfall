extends Node
## Optional overlay on existing actions. Controller owns rewards and all visuals.
signal progress_changed(text: String)
signal target_started(position: Vector3)

const RouteBudget = preload("res://scripts/contract_route_budget.gd")
const TITLES := {"salvage":"废墟补给", "generator":"能源交接", "escort":"哨兵归队", "nest":"封巢报告"}
const REWARD_SCRAP := 38
const EARLY_RETURN_SECONDS := 15.0
const RETURN_HOME := Vector3(0, 5, 3.1)
const BUDGET_REFRESH_SECONDS := 0.28
const BUDGET_CELL_SIZE := 2.0
const OFFER_RISK_SECONDS := [0.0, 8.0, 16.0]
const OFFER_RISK_HUNTERS := [0, 1, 2]
const OFFER_NAMES := ["稳妥路线", "加码路线", "孤注路线"]
const AFFINITY_KINDS := {"salvage":["ember_bloom", "supply_cache"], "generator":["waylight"], "escort":["memory_crystal"], "nest":["waylight", "ember_bloom"]}
const BONUS_PAYOUTS := {
	"ember_bloom":{"scrap":21},
	"memory_crystal":{"scrap":16},
	"supply_cache":{"scrap":31},
	"waylight":{"scrap":16}
}
const BONUS_TITLES := {"ember_bloom":"余烬花", "memory_crystal":"余烬晶簇", "supply_cache":"遗落补给箱", "waylight":"引路灯碑"}
var game: Node3D
var run_seed := 0
var day_id := -1
var kind := ""
var status := "idle"
var targets: Array[Dictionary] = []
var offers: Array[Dictionary] = []
var selected_offer := 0
var progress_started := false
var offer_touched: Dictionary = {}
var start_notified := false
var offer_rejection_reason := ""
var selected_reward := {"scrap": REWARD_SCRAP, "risk": 0, "risk_hunters": 0, "risk_seconds": 0.0}
var risk_spawned := false
var risk_spawn_count := 0
var done: Dictionary = {}
var pending_reward: Dictionary = {}
var bonus_target: Dictionary = {}
var _bonus_selection: Dictionary = {}
var bonus_done := false
var bonus_choice := ""
var last_text := ""
var budget_route_queries := 0
var budget_refresh_time := 0.0
var budget_cache_revision := -1
var budget_route_cache: Dictionary = {}

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
	offer_touched.clear()
	start_notified=false
	offer_rejection_reason=""
	done.clear()
	pending_reward.clear()
	bonus_target.clear()
	_bonus_selection.clear()
	bonus_done=false
	bonus_choice=""
	selected_reward={"scrap":REWARD_SCRAP,"risk":0,"risk_hunters":0,"risk_seconds":0.0}
	risk_spawned=false
	risk_spawn_count=0
	last_text = ""
	budget_route_queries=0
	clear_budget_cache()

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
	clear_budget_cache()
	done.clear()
	targets.clear()
	offers.clear()
	selected_offer=0
	progress_started=false
	offer_touched.clear()
	start_notified=false
	offer_rejection_reason=""
	pending_reward.clear()
	bonus_target.clear()
	_bonus_selection.clear()
	bonus_done=false
	bonus_choice=""
	risk_spawned=false
	risk_spawn_count=0
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
			offer["risk_hunters"] = OFFER_RISK_HUNTERS[offer_index]
			offer["name"] = OFFER_NAMES[offer_index]
			offer["scrap"] = REWARD_SCRAP+offer_index*24
			offers.append(offer)
		_select_offer(0)
		status = "active"
	emit_progress()

func on_night() -> void:
	_bonus_selection.clear()
	risk_spawned=false
	risk_spawn_count=0
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
	offer_rejection_reason=""
	if not is_instance_valid(game) or game.phase!="day" or status!="active":
		offer_rejection_reason="当前没有可切换的委托方案"
		return false
	# Ordinary exploration can start a live target immediately before another
	# key event. Reconcile that action before allowing any reward-tier change.
	observe_offer_actions()
	if progress_started:
		offer_rejection_reason="委托已开始 · 方案已锁定"
		return false
	var choice:=offer_choice_state(index)
	if not bool(choice.available):
		offer_rejection_reason=String(choice.reason)
		return false
	_select_offer(index)
	emit_progress()
	return true

func source_started(offer_kind: String, source: Dictionary) -> bool:
	if source.is_empty():return false
	match offer_kind:
		"salvage":return bool(source.get("collected",false))
		"generator":return String(source.get("state","ready"))!="ready"
		"escort":return String(source.get("state","waiting"))!="waiting"
		"nest":return bool(source.get("cleansed",false))
	return false

func offer_has_started(index: int) -> bool:
	if index<0 or index>=offers.size():return false
	var offer: Dictionary=offers[index]
	for target: Dictionary in offer.get("targets",[]):
		if source_started(String(offer.kind),target.get("source",{})):return true
	return false

func selected_risk_seconds() -> float:
	var seconds:=float(selected_reward.get("risk_seconds",0.0))
	if seconds<=0.0 and selected_offer>=0 and selected_offer<offers.size():
		seconds=float(offers[selected_offer].get("risk_seconds",0.0))
	return maxf(0.0,seconds)

func observe_offer_actions() -> void:
	if not is_instance_valid(game) or game.phase!="day" or status!="active":return
	for index in offers.size():
		if offer_has_started(index):offer_touched[index]=true
	if not offer_touched.has(selected_offer):return
	progress_started=true
	if start_notified:return
	# Set both latches before the synchronous signal. A reward callback or
	# reentrant tick must never emit the same first-action risk twice.
	start_notified=true
	if game.phase_time<=selected_risk_seconds():return
	for target: Dictionary in targets:
		var source: Dictionary=target.get("source",{})
		if source_started(kind,source):
			target_started.emit(source.get("position",target.position))
			break

func offer_choice_state(index: int) -> Dictionary:
	# Presentation queries remain read-only: they cannot mark a target, lock
	# the current route, or spawn hunters. Live state covers the pre-tick frame.
	var selected:=index==selected_offer
	if index<0 or index>=offers.size():
		return {"available":false,"reason":"当前没有这个委托方案","tag":"不可用","selected":selected}
	if not is_instance_valid(game) or status!="active":
		return {"available":false,"reason":"当前没有可切换的委托方案","tag":"不可用","selected":selected}
	var day_context: bool=game.phase=="day" or (game.phase=="paused" and game.paused_from=="day") or (game.phase=="draft" and game.return_phase=="day")
	if not day_context:
		return {"available":false,"reason":"仅白昼可以选择委托方案","tag":"不可用","selected":selected}
	var touched:=offer_touched.has(index) or offer_has_started(index)
	if not selected and touched:
		return {"available":false,"reason":"目标已探索 · 请先选方案再行动","tag":"已探索","selected":false}
	if not selected and (progress_started or offer_touched.has(selected_offer) or offer_has_started(selected_offer)):
		return {"available":false,"reason":"委托已开始 · 方案已锁定","tag":"锁定","selected":false}
	if not (selected and (progress_started or touched)) and game.phase_time<=float(offers[index].get("risk_seconds",0.0)):
		return {"available":false,"reason":"该方案目标已截止 · 请选择其他未探索方案","tag":"已截止","selected":selected}
	return {"available":true,"reason":"当前方案" if selected else "可在行动前选择","tag":"已选" if selected else "可选","selected":selected}

func choice_hint() -> String:
	var parts: Array[String]=[]
	for index in offers.size():
		var choice:=offer_choice_state(index)
		parts.append("%d%s" % [4+index,String(choice.tag)])
	return " · ".join(parts)

func choose_bonus(index: int) -> bool:
	if not _bonus_operation_reason().is_empty():return false
	if index==0:
		bonus_choice="return"
		status="returning"
		emit_progress()
		return true
	if index!=1:return false
	# Confirm the current discovery and route when the player accepts, rather
	# than binding a presentation estimate that may have outlived a respawn.
	var candidate:=bonus_candidate(true)
	if candidate.is_empty():return false
	var budget:=_bonus_budget(candidate)
	if not bool(budget.available):return false
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
	var risk_count:=int(offer.get("risk_hunters", 0))
	var risk_label: String=["稳妥", "加码", "孤注"][clampi(int(offer.get("risk", index)),0,2)]
	var risk_text := "%s · 无额外追猎" % risk_label if risk_count <= 0 else "%s · 额外追猎%d" % [risk_label,risk_count]
	if risk_seconds > 0.0:risk_text += " · 提前%d秒截止" % risk_seconds
	return "%s · +%d零件 · %s" % [String(offer.get("name", "方案%d" % (index + 1))), int(offer.get("scrap", REWARD_SCRAP)), risk_text]

func primary_budget(offer_index: int = -1) -> Dictionary:
	return RouteBudget.evaluate(self, offer_index)

func primary_travel_text(budget: Dictionary) -> String:
	return RouteBudget.travel_text(budget)

func primary_timing_text(budget: Dictionary) -> String:
	return RouteBudget.timing_text(budget)

func primary_condition_text(budget: Dictionary) -> String:
	return RouteBudget.condition_text(budget)

func _select_offer(index: int) -> void:
	selected_offer=index
	var offer: Dictionary=offers[index]
	kind=String(offer.kind)
	targets.clear()
	for target: Dictionary in offer.targets:targets.append(target)
	selected_reward={"scrap":int(offer.scrap),"risk":int(offer.get("risk", index)),"risk_hunters":int(offer.get("risk_hunters", 0)),"risk_seconds":float(offer.get("risk_seconds", 0.0))}

func bonus_source() -> Dictionary:
	return _bonus_source_for(bonus_target)

func bonus_finished() -> bool:
	var source:=bonus_source()
	if source.is_empty():return false
	var state:=String(source.get("state",""))
	return state in ["active", "cooling"]

func bonus_interaction_range(source: Dictionary) -> float:
	return 4.0 if String(source.get("kind",""))=="supply_cache" else 3.2

func route_distance(from: Vector3, to: Vector3) -> float:
	if game.can_traverse(from,to):return flat_distance(from,to)
	var discoveries: Node=game.get("discoveries")
	var revision:=int(discoveries.motivation_revision) if is_instance_valid(discoveries) else -1
	if budget_refresh_time<=0.0 or revision!=budget_cache_revision:
		clear_budget_cache()
		budget_cache_revision=revision
		budget_refresh_time=BUDGET_REFRESH_SECONDS
	var cell:=Vector2i(floori(from.x/BUDGET_CELL_SIZE),floori(from.z/BUDGET_CELL_SIZE))
	var key:=str(cell)+":"+str(to)
	if budget_route_cache.has(key):
		var previous: Dictionary=budget_route_cache[key]
		if previous.is_empty():return INF
		var first: Vector2=previous.first
		# A coarse cell can straddle a wall. Never reuse its cached approach
		# from the other side of that wall, even during the short stale window.
		if game.can_traverse(from,Vector3(first.x,0,first.y)):
			return cached_route_distance(from,previous)
	budget_route_queries+=1
	var start: Vector2i=game.nearest_navigation_cell(from,true)
	var finish: Vector2i=game.nearest_navigation_cell(to,false)
	if start.x==999 or finish.x==999:
		budget_route_cache[key]={}
		return INF
	# The nearest free cell can sit outside a sealed pocket. Its final
	# approach still has to reach the actual source instead of crossing a wall.
	if not game.can_traverse(Vector3(finish.x,0,finish.y),to):
		budget_route_cache[key]={}
		return INF
	var route: PackedVector2Array=game.hero_navigation.get_point_path(start,finish)
	if route.is_empty():
		budget_route_cache[key]={}
		return INF
	var previous:=route[0]
	var distance:=0.0
	for point in route:
		distance+=previous.distance_to(point)
		previous=point
	var cached: Dictionary={"first":route[0],"tail":distance+previous.distance_to(Vector2(to.x,to.z))}
	budget_route_cache[key]=cached
	return cached_route_distance(from,cached)

func clear_budget_cache() -> void:
	budget_route_cache.clear()
	budget_refresh_time=0.0
	budget_cache_revision=-1

func cached_route_distance(from: Vector3, cached: Dictionary) -> float:
	if cached.is_empty():return INF
	return Vector2(from.x,from.z).distance_to(cached.first)+float(cached.tail)

func bonus_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not is_instance_valid(game):return result
	var discoveries: Node=game.get("discoveries")
	if not is_instance_valid(discoveries) or not _bonus_actor_valid():return result
	for index in discoveries.items.size():
		var item: Dictionary=discoveries.items[index]
		if String(item.get("state",""))!="ready":continue
		if not _bonus_discovery_valid(item):continue
		var distance:=route_distance(game.hero.position,item.position)
		if not is_finite(distance) or distance>58.0:continue
		var payout: Dictionary=BONUS_PAYOUTS.get(String(item.kind),{"scrap":15})
		result.append({"index":index,"serial":int(item.get("serial",0)),"kind":String(item.kind),"position":item.position,"distance":distance,"scrap":int(payout.scrap),"source":item})
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		if not is_equal_approx(float(a.distance),float(b.distance)):return float(a.distance)<float(b.distance)
		return int(a.index)<int(b.index)
	)
	return result

func bonus_candidate(force_refresh: bool = false) -> Dictionary:
	if force_refresh:clear_budget_cache()
	if not _bonus_selection.is_empty():
		var source:=_bonus_source_for(_bonus_selection)
		if source.is_empty() or String(source.get("state",""))!="ready" or not _bonus_actor_valid():return {}
		var distance:=route_distance(game.hero.position,source.position)
		if not is_finite(distance) or distance>58.0:return {}
		var selected:=_bonus_selection.duplicate(false)
		selected.position=source.position
		selected.distance=distance
		selected.scrap=int(BONUS_PAYOUTS.get(String(source.kind),{"scrap":15}).scrap)
		return selected
	var candidates:=bonus_candidates()
	return candidates[0] if not candidates.is_empty() else {}

func bonus_route_options() -> Array[Dictionary]:
	# A presentation query never creates a selection. The nearest route stays
	# first; offer category variety before filling any remaining nearest slots.
	var result: Array[Dictionary]=[]
	if status!="bonus_offer" or not _bonus_day_context():return result
	var candidates:=bonus_candidates()
	var picked: Array[Dictionary]=[]
	var kinds: Dictionary={}
	if not candidates.is_empty():
		picked.append(candidates[0])
		kinds[String(candidates[0].kind)]=true
	for candidate: Dictionary in candidates:
		if picked.size()>=3:break
		if kinds.has(String(candidate.kind)):continue
		picked.append(candidate)
		kinds[String(candidate.kind)]=true
	for candidate: Dictionary in candidates:
		if picked.size()>=3:break
		if _bonus_picked(picked,candidate):continue
		picked.append(candidate)
	var selection_included:=false
	for candidate: Dictionary in picked:
		var selected:=_bonus_matches_selection(candidate) if not _bonus_selection.is_empty() else result.is_empty()
		selection_included=selection_included or selected
		result.append(_bonus_option(candidate,selected))
	if not _bonus_selection.is_empty() and not selection_included:
		var selected_candidate:=bonus_candidate()
		if selected_candidate.is_empty():selected_candidate=_bonus_selection.duplicate(false)
		if result.size()>=3:result.pop_back()
		result.append(_bonus_option(selected_candidate,true))
	return result

func select_bonus_route(index: int, serial: int) -> bool:
	if not _bonus_operation_reason().is_empty():return false
	var discoveries: Node=game.get("discoveries")
	if not is_instance_valid(discoveries) or index<0 or index>=discoveries.items.size():return false
	var source: Dictionary=discoveries.items[index]
	if int(source.get("serial",-1))!=serial or String(source.get("state",""))!="ready" or not _bonus_discovery_valid(source):return false
	# Revalidate the actual route instead of trusting a cached HUD estimate.
	clear_budget_cache()
	var distance:=route_distance(game.hero.position,source.position)
	if not is_finite(distance) or distance>58.0:return false
	var candidate: Dictionary={"index":index,"serial":serial,"kind":String(source.kind),
		"position":source.position,"distance":distance,
		"scrap":int(BONUS_PAYOUTS.get(String(source.kind),{"scrap":15}).scrap),"source":source}
	if not bool(_bonus_budget(candidate).available):return false
	_bonus_selection=candidate
	return true

func _bonus_option(candidate: Dictionary, selected: bool) -> Dictionary:
	var result:=candidate.duplicate(false)
	var source:=_bonus_source_for(candidate)
	var budget:=_bonus_budget(candidate)
	var reason:=_bonus_operation_reason()
	if source.is_empty():reason="原追加目标已失效 · 请选其他路线或返家"
	elif String(source.get("state",""))!="ready":reason="目标已开始或已探索 · 请选其他路线或返家"
	elif not bool(budget.available) or float(budget.outbound_distance)>58.0:reason="目标或返家路线不可达"
	var route_valid:=not source.is_empty() and String(source.get("state",""))=="ready" \
		and bool(budget.available) and float(budget.outbound_distance)<=58.0
	# A stale source must not display a feasible budget. Pausing only blocks
	# submitting the choice; its unchanged, valid geometry remains visible.
	if not route_valid:
		budget.available=false
		budget.total_seconds=INF
		budget.spare_seconds=-INF
		budget.risk="unreachable"
	result.selected=selected
	result.available=reason.is_empty()
	result.reason=reason if not reason.is_empty() else ("已选路线" if selected else "可选择追加路线")
	result.budget=budget
	return result

func _bonus_picked(picked: Array[Dictionary], candidate: Dictionary) -> bool:
	for previous: Dictionary in picked:
		if int(previous.index)==int(candidate.index) and int(previous.serial)==int(candidate.serial) and is_same(previous.source,candidate.source):return true
	return false

func _bonus_matches_selection(candidate: Dictionary) -> bool:
	return int(candidate.index)==int(_bonus_selection.get("index",-1)) \
		and int(candidate.serial)==int(_bonus_selection.get("serial",-1)) \
		and String(candidate.kind)==String(_bonus_selection.get("kind","")) \
		and is_same(candidate.get("source",{}),_bonus_selection.get("source",{}))

func _bonus_source_for(candidate: Dictionary) -> Dictionary:
	if candidate.is_empty() or not is_instance_valid(game):return {}
	var discoveries: Node=game.get("discoveries")
	if not is_instance_valid(discoveries):return {}
	var index:=int(candidate.get("index",-1))
	if index<0 or index>=discoveries.items.size():return {}
	var source: Dictionary=discoveries.items[index]
	if int(source.get("serial",-1))!=int(candidate.get("serial",-2)) or String(source.get("kind",""))!=String(candidate.get("kind","")):return {}
	# Legacy isolated fixtures can supply index/serial metadata; every new
	# route created by this module also binds the original dictionary identity.
	if candidate.has("source") and not is_same(source,candidate.source):return {}
	return source if _bonus_discovery_valid(source) else {}

func _bonus_discovery_valid(source: Dictionary) -> bool:
	var node: Variant=source.get("node")
	var point: Variant=source.get("position")
	return is_instance_valid(node) and node is Node3D and not node.is_queued_for_deletion() \
		and point is Vector3 and point.is_finite() and bool(game.outpost_walkable(point))

func _bonus_actor_valid() -> bool:
	if not is_instance_valid(game):return false
	var hero: Variant=game.get("hero")
	return is_instance_valid(hero) and hero is Node3D and not hero.is_queued_for_deletion() \
		and bool(hero.get("alive")) and float(hero.get("hp"))>0.0 and hero.position.is_finite()

func _bonus_day_context() -> bool:
	if not is_instance_valid(game):return false
	return game.phase=="day" or (game.phase=="paused" and game.paused_from=="day") or (game.phase=="draft" and game.return_phase=="day")

func _bonus_operation_reason() -> String:
	if not is_instance_valid(game) or game.is_queued_for_deletion() or bool(game.get("quitting")) or bool(game.get("restart_pending")):return "当前守望已结束"
	if game.phase!="day" or status!="bonus_offer" or float(game.phase_time)<=0.0:return "仅白昼追加待选时可切换路线"
	if not _bonus_actor_valid() or not (float(game.get("beacon_hp"))>0.0):return "守望者或灯塔已失守"
	return ""

func bonus_summary() -> String:
	var candidate: Dictionary=bonus_target if not bonus_target.is_empty() else bonus_candidate()
	if candidate.is_empty():
		if status=="bonus_offer" and not _bonus_selection.is_empty():return "所选%s已失效 · 重选路线或4返家" % BONUS_TITLES.get(String(_bonus_selection.kind),"追加目标")
		return "4 立即返家保底 · 暂无可达追加补给"
	var title: String=BONUS_TITLES.get(String(candidate.kind),"追加补给")
	return "%s%s · +%d零件" % ["5 贪一笔：" if status=="bonus_offer" else "追加 ",title,int(candidate.scrap)]

func return_budget() -> Dictionary:
	# Cache only route geometry. Time left, actual movement speed and the
	# remaining cache-opening channel stay live, including during a detour.
	var candidate: Dictionary=bonus_candidate() if status=="bonus_offer" else bonus_target if status=="bonus_active" else {}
	return _bonus_budget(candidate,status in ["bonus_offer","bonus_active"])

func _bonus_budget(candidate: Dictionary, requires_target: bool = true) -> Dictionary:
	var outbound:=0.0
	var action_seconds:=0.0
	var guard_state: Dictionary={}
	var actor_valid:=_bonus_actor_valid()
	var hero: Variant=game.get("hero") if is_instance_valid(game) else null
	var speed: float=maxf(1.0,float(hero.get("speed"))) if is_instance_valid(hero) else 1.0
	var return_from: Vector3=game.hero.position if actor_valid else RETURN_HOME
	var available:=actor_valid
	if requires_target:
		var source:=_bonus_source_for(candidate)
		available=available and not source.is_empty() and String(source.get("state","")) in ["ready","channel"]
		if available:
			outbound=route_distance(game.hero.position,source.position)
			return_from=source.position
			if String(source.kind)=="supply_cache":
				action_seconds=maxf(0.0,game.discoveries.CHANNEL_SECONDS-float(source.progress)) if String(source.state)=="channel" else game.discoveries.CHANNEL_SECONDS
				guard_state=game.discoveries.cache_guards.snapshot(int(candidate.get("index",-1)))
	var returning_distance:=route_distance(return_from,RETURN_HOME) if actor_valid else INF
	if not requires_target and status=="returning" and actor_valid and returned_home():returning_distance=0.0
	available=available and is_finite(outbound) and is_finite(returning_distance)
	var total_seconds: float=(outbound+returning_distance)/speed+action_seconds if available else INF
	var spare_seconds: float=float(game.phase_time)-total_seconds if is_instance_valid(game) else -INF
	var risk: String="unreachable" if not available else ("late" if spare_seconds<0.0 else ("tight" if spare_seconds<EARLY_RETURN_SECONDS else "ready"))
	return {"available":available,"candidate":candidate.duplicate(),"outbound_distance":outbound,"return_distance":returning_distance,"action_seconds":action_seconds,"total_seconds":total_seconds,"spare_seconds":spare_seconds,"risk":risk,"speed":speed,
		"guarded":bool(guard_state.get("guarded",false)),"guard_blocked":bool(guard_state.get("blocked",false)),"guard_remaining":int(guard_state.get("remaining",0)),"guard_lost":int(guard_state.get("lost",0))}

func return_budget_text(budget: Dictionary) -> String:
	var guard_text:=""
	if bool(budget.get("guard_blocked",false)):
		guard_text="守卫离场，箱仍锁 · " if int(budget.get("guard_lost",0))>0 else "守卫%d未清，战斗另计 · " % int(budget.get("guard_remaining",0))
	if not budget.available:return guard_text+"追加目标不可达 · 主委托保底保留"
	if String(budget.risk)=="late":return guard_text+"预计回灯塔 %.0f秒 · 日落前难返家，主委托保底保留" % ceili(float(budget.total_seconds))
	var spare:=maxi(0,floori(float(budget.spare_seconds)))
	return guard_text+"预计回灯塔 %.0f秒 · 余%d秒整备%s" % [ceili(float(budget.total_seconds)),spare," · 时间紧" if String(budget.risk)=="tight" else ""]

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

func mark_risk_spawned(count: int) -> void:
	risk_spawned=true
	risk_spawn_count=maxi(0,count)

func tick(delta: float) -> void:
	if not is_instance_valid(game): return
	if game.phase in ["paused", "draft"]: return
	budget_refresh_time=maxf(0.0,budget_refresh_time-delta)
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
	var risk_seconds := selected_risk_seconds()
	if done.size() < targets.size() and risk_seconds > 0.0 and game.phase_time <= risk_seconds:
		status = "expired"
		emit_progress()
		return
	observe_offer_actions()
	if status!="active":return
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
	if include_bonus:
		reward_scrap+=int(bonus_target.get("scrap",0))
	return {"id":"day_contract_%d" % day_id,"day":day_id,"kind":kind,"scrap":reward_scrap,"risk":int(selected_reward.get("risk",selected_offer)),"risk_hunters":int(selected_reward.get("risk_hunters",0)),"early_return":early,"bonus":include_bonus,"affinity":AFFINITY_KINDS.get(kind, []).duplicate()}

func returned_home() -> bool:
	return game.hero.alive and in_home_area(game.hero.position)

func in_home_area(point: Vector3) -> bool:
	return point.y > 4.8 and flat_distance(point, Vector3.ZERO) < 6.2

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
	var switch_hint := " · "+choice_hint() if offers.size()>1 else (" · 方案已锁定" if progress_started else "")
	return "可选 · 方案%d/%d · %s %d/%d · %s · %s · 日落前交回，提前15秒再+10零件%s" % [selected_offer+1,offers.size(),TITLES[kind], done.size(), targets.size(), instruction, reward_text, switch_hint]

func emit_progress() -> void:
	var value := progress_text()
	if value != last_text:
		last_text = value
		progress_changed.emit(value)
