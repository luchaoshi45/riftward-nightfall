class_name RunBuild
extends RefCounted
## Run-local deterministic drafting. Upgrades share the construction scrap budget.
const SCHOOLS := ["强袭", "秘术", "守御"]
const COLORS := [Color("e4ac67"),Color("79c9ef"),Color("7ac7ad")]
const RARITIES := ["基础", "稀有", "传奇"]
const OPENING_SOURCE := "守夜者的第一段记忆"
const MEMORY_COSTS := [120, 180, 260, 360, 500, 680]
const CORE_CARDS := [
	{"id":"core_storm","name":"雷斩 · 第三剑","school":0,"rarity":0,"cap":1,"desc":"第三次有效普攻向附近最多两敌跳电，\n造成 30% 攻击伤害。\n保持走位普攻，清理南门杂兵。","stat":"core_storm","value":1.0,"core":true},
	{"id":"core_flame","name":"灯焰 · 灼印","school":1,"rarity":0,"cap":1,"desc":"Q 留下持续 4 秒的灼印；\nR 消耗灼印，额外造成 60 伤害。\n先斩光标记，再灯焰引爆。","stat":"core_flame","value":1.0,"core":true},
	{"id":"core_guard","name":"守灯 · 反震","school":2,"rarity":0,"cap":1,"desc":"W 屏障吸收攻击后反震一次，\n对近身敌人造成 50 伤害。\n挡住进攻，为防线创造反击。","stat":"core_guard","value":1.0,"core":true}
]
const CARDS := [
	{"id":"edge","name":"锐锋意志","school":0,"rarity":0,"cap":3,"desc":"攻击 +16。\n普攻与强袭效果的基础伤害提高。","stat":"attack","value":16.0},
	{"id":"tempo","name":"疾风脉搏","school":0,"rarity":0,"cap":3,"desc":"攻速 +18%。\n更快触发暴击与连锁效果。","stat":"attack_speed","value":.18},
	{"id":"critical","name":"命运之眼","school":0,"rarity":1,"cap":3,"desc":"暴击率 +12%。\n普攻暴击造成 175% 伤害。","stat":"crit","value":.12},
	{"id":"drain","name":"猩红契约","school":0,"rarity":1,"cap":2,"desc":"普攻汲取 +8%。\n对夜行体造成的伤害转为治疗。","stat":"lifesteal","value":.08},
	{"id":"reach","name":"猎星视界","school":0,"rarity":0,"cap":2,"desc":"普攻射程 +0.65 米。\n移速 +0.25。","stat":"range","value":.65},
	{"id":"chain","name":"雷霆回路","school":0,"rarity":2,"cap":1,"desc":"每第三次普攻，闪电跳向附近\n最多两名敌人，造成 55% 攻击伤害。","stat":"chain","value":1.0},
	{"id":"arcana","name":"星辉共鸣","school":1,"rarity":0,"cap":3,"desc":"法术强度 +30。\n提高 Q、W、R 的伤害及护盾。","stat":"spell","value":30.0},
	{"id":"haste","name":"时砂回响","school":1,"rarity":0,"cap":3,"desc":"技能急速 +18。\n冷却 = 原冷却 / (1 + 急速/100)。","stat":"haste","value":18.0},
	{"id":"reservoir","name":"灵泉之心","school":1,"rarity":0,"cap":3,"desc":"能量上限 +70，能量恢复 +2/秒。\n获得时恢复 70 能量。","stat":"mana","value":70.0},
	{"id":"nova","name":"扩散星域","school":1,"rarity":1,"cap":2,"desc":"W 与 R 范围 +18%。\n范围倍率最高 1.6 倍。","stat":"area","value":.18},
	{"id":"split","name":"三重裂光","school":1,"rarity":2,"cap":1,"desc":"Q 改为扇形三发光刃。\n每发 70% 伤害，可分别命中同一目标。","stat":"split","value":1.0},
	{"id":"echo","name":"坠星余响","school":1,"rarity":2,"cap":1,"desc":"R 在首次落点追加一次爆发。\n延迟 0.55 秒，造成 50% 伤害。","stat":"echo","value":1.0},
	{"id":"vitality","name":"古树血脉","school":2,"rarity":0,"cap":3,"desc":"最大生命 +160。\n获得时同时恢复 160 生命。","stat":"health","value":160.0},
	{"id":"armor","name":"玄岩誓约","school":2,"rarity":0,"cap":3,"desc":"护甲 +20。\n承伤倍率 = 100 / (100 + 护甲)。","stat":"armor","value":20.0},
	{"id":"renew","name":"不息生长","school":2,"rarity":0,"cap":3,"desc":"生命恢复 +4/秒。\n脱离泉水也能持续恢复。","stat":"regen","value":4.0},
	{"id":"stride","name":"踏风者","school":2,"rarity":1,"cap":2,"desc":"移速 +0.65。\nE 距离 +0.8 米，仍受树林阻挡。","stat":"speed","value":.65},
	{"id":"ward","name":"棱镜屏障","school":2,"rarity":1,"cap":2,"desc":"护盾强度 +30%。\nW 屏障与守御联动护盾受益。","stat":"shield","value":.30},
	{"id":"thorns","name":"荆棘王冠","school":2,"rarity":2,"cap":1,"desc":"被普攻时反击施暴者，造成\n18 + 25% 护甲伤害；不触发连锁。","stat":"thorns","value":1.0}
]
var rng := RandomNumberGenerator.new()
var seed_value: int
var owned: Dictionary = {}
var offer: Array[Dictionary] = []
var queue: Array[String] = []
var pending: int = 0
var rerolls: int = 3
var selections: int = 0
var memory_level: int = 0
var pity: int = 0
var reason: String = ""
var focus: int = 1
var stats: Dictionary = {}
var _opening_source: String = OPENING_SOURCE

func _init(run_seed: int = 0) -> void:
	seed_value=run_seed if run_seed!=0 else int(Time.get_unix_time_from_system()) ^ Time.get_ticks_usec()
	rng.seed=seed_value
	recalculate()

func grant(source: String) -> void:
	pending+=1
	queue.append(source)

func grant_opening(source: String = OPENING_SOURCE) -> void:
	# Explicit entry for an opening whose player-facing wording changes.
	_opening_source = source
	grant(source)

func count(id: String) -> int:
	return int(owned.get(id,0))

func core_id() -> String:
	for card: Dictionary in CORE_CARDS:
		if count(card.id) > 0:
			return card.id
	return ""

func core_school() -> int:
	for card: Dictionary in CORE_CARDS:
		if count(card.id) > 0:
			return int(card.school)
	return -1

func has_core(id: String) -> bool:
	return core_id() == id

func memory_cost(level: int = -1) -> int:
	var requested_level: int = memory_level if level < 0 else level
	if requested_level < MEMORY_COSTS.size():
		return int(MEMORY_COSTS[requested_level])
	var cost: int = int(MEMORY_COSTS.back())
	for _step in range(MEMORY_COSTS.size(), requested_level + 1):
		cost = int(ceil(float(cost) * 1.3))
	return cost

func register_memory_upgrade() -> int:
	# The controller subtracts this cost and grants one queued choice.
	# Choosing opening/dawn cards never changes the memory progression.
	var paid_cost: int = memory_cost()
	memory_level += 1
	return paid_cost

func has_available_upgrade() -> bool:
	# Affordability and previews must not draw cards or consume the seeded stream.
	for card: Dictionary in CARDS:
		if count(card.id) < int(card.cap):return true
	return false

func school_count(school: int) -> int:
	var total:=0
	for card in CARDS:
		if card.school==school: total+=count(card.id)
	for card: Dictionary in CORE_CARDS:
		if card.school == school:
			total += count(card.id)
	return total

func draft() -> bool:
	if pending<=0: return false
	if not offer.is_empty(): return true
	reason=queue[0]
	if selections == 0 and core_id().is_empty() and reason == _opening_source:
		# Rerolls deliberately retain all three mutually exclusive starting paths.
		for card: Dictionary in CORE_CARDS:
			offer.append(card)
		return true
	var pool: Array[Dictionary]=[]
	for card in CARDS:
		if count(card.id)<card.cap: pool.append(card)
	if pool.is_empty():
		pending=0; queue.clear()
		return false
	var guaranteed := 2 if (selections+1)%5==0 else (1 if pity>=3 else 0)
	var compatible_school: int = core_school()
	var compatible_offered := false
	for slot in range(mini(3,pool.size())):
		var candidates: Array[Dictionary]=[]
		for card in pool:
			if slot == 0 and card.rarity < guaranteed:
				continue
			if slot == 1 and compatible_school >= 0 and not compatible_offered and card.school != compatible_school:
				continue
			candidates.append(card)
		if candidates.is_empty(): candidates=pool.duplicate()
		var total:=0.0
		for card in candidates: total+=weight(card)
		var roll:=rng.randf()*total
		var chosen: Dictionary=candidates.back()
		for card in candidates:
			roll-=weight(card)
			if roll<=0:
				chosen=card
				break
		offer.append(chosen)
		if chosen.school == compatible_school:
			compatible_offered = true
		pool.erase(chosen)
	return true

func weight(card: Dictionary) -> float:
	return [7.0,3.0,1.0][card.rarity] * (1.6 if card.school==focus else 1.0)

func redraw() -> bool:
	if rerolls<=0 or offer.is_empty(): return false
	rerolls-=1
	offer.clear()
	return draft()

func choose(index: int) -> Dictionary:
	if index<0 or index>=offer.size() or pending<=0: return {}
	var chosen: Dictionary=offer[index]
	if count(chosen.id) >= int(chosen.cap): return {}
	if bool(chosen.get("core", false)) and not core_id().is_empty(): return {}
	owned[chosen.id]=count(chosen.id)+1
	if bool(chosen.get("core", false)):
		focus = int(chosen.school)
	selections+=1
	pity=0 if chosen.rarity>=1 else pity+1
	pending-=1
	queue.pop_front()
	offer.clear()
	recalculate()
	return chosen

func recalculate() -> void:
	stats={"attack":0.0,"attack_speed":0.0,"crit":0.05,"lifesteal":0.0,"range":0.0,"spell":0.0,"haste":0.0,"mana":0.0,"mana_regen":0.0,"area":1.0,"health":0.0,"armor":0.0,"regen":0.0,"speed":0.0,"shield":1.0,"chain":0.0,"split":0.0,"echo":0.0,"thorns":0.0,"core_storm":0.0,"core_flame":0.0,"core_guard":0.0}
	for card in CARDS:
		stats[card.stat]+=card.value*count(card.id)
	for card: Dictionary in CORE_CARDS:
		stats[card.stat] += card.value * count(card.id)
	stats.speed+=count("reach")*.25
	stats.mana_regen=count("reservoir")*2.0
	if school_count(0)>=3: stats.crit+=.10
	if school_count(0)>=6: stats.lifesteal+=.10
	if school_count(1)>=3: stats.haste+=15
	if school_count(1)>=6: stats.spell+=45
	if school_count(2)>=3: stats.armor+=15
	if school_count(2)>=6: stats.regen+=5
	stats.crit=minf(.75,stats.crit)
	stats.attack_speed=minf(1.2,stats.attack_speed)
	stats.haste=minf(120,stats.haste)
	stats.area=minf(1.6,stats.area)

func cooldown_factor() -> float:
	return 100.0/(100.0+stats.haste)
