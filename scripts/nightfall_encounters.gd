extends RefCounted
## 保存实际敌群计划；预告读取同一份计划，不另行随机生成文案。

const WAVE_TIMES: Array[float] = [0.0, 20.0, 40.0, 65.0, 85.0]
const KNOWN_ROLES: Array[String] = ["basic", "runner", "breaker", "sapper", "light_eater", "lobber", "summoner", "warder"]
const MAX_NEST_REDUCTION: int = 6
const MIN_WAVE_COUNT: int = 4
const LOBBER_ADVICE := "移出2米落点，弩手/重弩集火；射程11.2米，蓄力1.15秒＋飞行0.75秒。"
const SUMMONER_ADVICE := "2.4秒引导可打断；冷却10秒，最多2援军从南门外进入；集火召潮者。"
const WARDER_ADVICE := "织壳者1秒引导，可击杀或牵制打断；32护盾持续4秒，成功后间隔6秒，每源最多3次。"

func make_plan(mode: String, night_index: int, run_seed: int, nest_count: int) -> Array[Dictionary]:
	var night: int = clampi(night_index, 1, 4)
	var selected_mode: String = mode if mode in ["teaching", "standard", "siege", "echo"] else "teaching"
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = run_seed + night * 104729
	var variant: int = random.randi_range(0, 2)
	var theme: String = selected_mode
	if selected_mode in ["teaching", "standard"]:
		theme = ["breach", "siege", "echo"][variant]
	var plan: Array[Dictionary] = []
	for index in range(WAVE_TIMES.size()):
		var composition: Dictionary = _first_night(index, random) if night == 1 else _later_night(index, night, theme, random)
		if night >= 2:
			var lobber_count := night - 1 if index in [2, 4] else (night - 2 if index in [1, 3] else 0)
			composition = _with_lobbers(composition, lobber_count, index == 2)
		var roles: Array[String] = []
		var specialists: Array = composition.roles
		for role in specialists:
			roles.append(String(role))
		var base_count: int = 8 + night * 3 if index == 0 else 8 + night * 2 + index * 2
		# 巢穴只削减普通随从，不能暗中更换已经预告的主要威胁。
		var reduction: int = mini(clampi(nest_count, 0, 3) * 2, MAX_NEST_REDUCTION)
		var count: int = maxi(maxi(MIN_WAVE_COUNT, roles.size()), base_count - reduction)
		while roles.size() < count:
			roles.append("basic")
		# Replace one already-budgeted ordinary follower after padding. This
		# preserves specialists, initial population and the original shuffle RNG.
		if night >= 3 and index == 2:
			var ordinary_index := roles.rfind("basic")
			if ordinary_index >= 0:
				roles[ordinary_index] = "summoner"
				composition.title = "召潮增援"
				composition.threat = "summoner"
				composition.advice = SUMMONER_ADVICE
		var summoner_count := roles.count("summoner")
		# Keep the saved primary threat and its guidance. One ordinary follower
		# becomes a finite shield source before the original deterministic shuffle.
		if (night == 2 and index == 3) or (night >= 3 and index in [1, 3]):
			var ordinary_index := roles.rfind("basic")
			if ordinary_index >= 0:
				roles[ordinary_index] = "warder"
				composition.title = String(composition.title) + " · 织壳护卫"
				composition.advice = String(composition.advice) + " " + WARDER_ADVICE
		var warder_count := roles.count("warder")
		# 排列也属于保存的计划，出怪时不能再次抽取角色。
		var order_random: RandomNumberGenerator = RandomNumberGenerator.new()
		order_random.seed = run_seed + night * 104729 + (index + 1) * 9719
		_shuffle_roles(roles, order_random)
		var final_night: int = 3 if selected_mode == "teaching" else 4
		var boss_entry: bool = night == final_night and index == WAVE_TIMES.size() - 1
		if boss_entry:
			# The boss is spawned beside the saved role list by the production
			# controller. Keep it in the same preview count so the warning cannot
			# under-report the real final-wave population.
			count += 1
		plan.append({
			"index": index,
			"wave_number": index + 1,
			"time": WAVE_TIMES[index],
			"title": String(composition.title),
			"threat": String(composition.threat),
			"advice": String(composition.advice),
			"roles": roles,
			"count": count,
			"role_count": roles.size(),
			"reinforcement_cap": 2 * summoner_count,
			"warder_count": warder_count,
			"shield_cast_cap": 3 * warder_count,
			"night": night,
			"mode": selected_mode,
			"theme": theme,
			"nest_reduction": base_count - roles.size(),
			"boss_entry": boss_entry,
			"boss_count": 1 if boss_entry else 0,
			"boss_role": "breaker" if boss_entry else "",
		})
		if boss_entry:
			plan[plan.size() - 1].title = "末夜首领 · 灯噬巨兽 · %s" % String(composition.title)
			plan[plan.size() - 1].advice = "打断首领蓄力，移出2米投蚀落点后远程集火。" if composition.roles.has("lobber") else "灯噬巨兽将在本波压门 · 打断蓄力后清理增援与残敌"
	return plan

## index 是已经生成的波数（0表示尚未生成）；返回值可供HUD自由修改。
func next_preview(plan: Array[Dictionary], index: int, elapsed: float) -> Dictionary:
	if index < 0 or index >= plan.size():
		return {}
	var preview: Dictionary = plan[index].duplicate(true)
	preview["remaining"] = maxf(0.0, float(preview.time) - maxf(0.0, elapsed))
	return preview

func _first_night(index: int, random: RandomNumberGenerator) -> Dictionary:
	match index:
		0:
			return _composition("暗潮初袭", "basic", "用普攻与Q试试核心，守住南门。", [])
		1:
			return _composition("疾行突破", "runner", "疾行体容易漏过防线，留E回位拦截。", _repeat("runner", 3 + random.randi_range(0, 1)))
		2:
			return _composition("暗潮追击", "runner", "先清聚集的夜行体，再拦截少量疾行。", _repeat("runner", 2))
		3:
			return _composition("蚀塔侧翼", "sapper", "蚀塔体优先拆塔，出门保护受压的防御塔。", _repeat("sapper", 2))
		_:
			return _composition("破城压门", "breaker", "用R与C集火破城体，塔继续处理随从。", _repeat("breaker", 2))

func _later_night(index: int, night: int, theme: String, random: RandomNumberGenerator) -> Dictionary:
	var pressure: int = night - 2
	var variant: int = random.randi_range(0, 1)
	match index:
		0:
			return _composition("噬灯先遣", "light_eater", "先击退噬灯蛾，保持南门灯光可见。", _repeat("light_eater", 2 + pressure))
		1:
			if theme == "siege":
				return _composition("重甲推进", "breaker", "集中火力解决破城体，不要让它压住坡道。", _repeat("breaker", 2 + pressure))
			return _composition("疾行夜潮", "runner", "守住通道纵深，留突进拦截漏怪。", _repeat("runner", 4 + pressure + variant))
		2:
			if theme == "echo":
				return _composition("掩灯突围", "light_eater", "清除噬灯蛾后再拦截疾行体，别在黑暗中追远。", _repeat("light_eater", 2 + pressure) + _repeat("runner", 3 + variant))
			return _composition("蚀塔包围", "sapper", "保护两侧塔，清群能力留给正门随从。", _repeat("sapper", 3 + pressure) + _repeat("runner", 2))
		3:
			if theme == "echo":
				return _composition("暗翼蚀塔", "sapper", "拆塔者受噬灯掩护，优先清灯下的特殊敌人。", _repeat("sapper", 3 + pressure) + _repeat("light_eater", 2))
			if theme == "siege":
				return _composition("重甲侧翼", "sapper", "分配英雄与塔的目标，侧翼蚀塔者不能放任。", _repeat("sapper", 3 + pressure) + _repeat("breaker", 2))
			return _composition("疾行拆塔", "sapper", "拦截快敌并保护受压塔，尽量在南门交战。", _repeat("sapper", 3 + pressure) + _repeat("runner", 4 + variant))
		_:
			if theme == "echo":
				return _composition("回声压门", "breaker", "先恢复光照，再用R与集火击穿重敌。", _repeat("breaker", 2 + pressure) + _repeat("light_eater", 3 + pressure))
			if theme == "siege":
				return _composition("重甲围城", "breaker", "破城体数量较多，集中重敌火力并清理随从。", _repeat("breaker", 3 + pressure) + _repeat("sapper", 2))
			return _composition("突破终潮", "breaker", "留住爆发击败重敌，同时阻止疾行体越过防线。", _repeat("breaker", 2 + pressure) + _repeat("runner", 4 + variant))

func _composition(title: String, threat: String, advice: String, roles: Array) -> Dictionary:
	return {"title": title, "threat": threat, "advice": advice, "roles": roles}

func _with_lobbers(composition: Dictionary, requested_count: int, primary: bool) -> Dictionary:
	if requested_count <= 0: return composition
	var roles: Array = composition.roles
	var counts: Dictionary = {}
	for role: String in roles: counts[role] = int(counts.get(role, 0)) + 1
	var replaced := 0
	# Replace specialists without changing population or consuming extra RNG.
	# Keep at least one of every original identity, including mixed-role themes.
	for index in range(roles.size() - 1, -1, -1):
		if replaced >= requested_count: break
		var role := String(roles[index])
		if role == "basic" or int(counts[role]) <= 1: continue
		counts[role] = int(counts[role]) - 1
		roles[index] = "lobber"
		replaced += 1
	if replaced > 0:
		composition.title = String(composition.title) + " · 投蚀落点"
		composition.advice = LOBBER_ADVICE
		if primary: composition.threat = "lobber"
	return composition

func _repeat(role: String, count: int) -> Array[String]:
	var roles: Array[String] = []
	for index in range(count):
		roles.append(role)
	return roles

func _shuffle_roles(roles: Array[String], random: RandomNumberGenerator) -> void:
	for index in range(roles.size() - 1, 0, -1):
		var replacement: int = random.randi_range(0, index)
		var role: String = roles[index]
		roles[index] = roles[replacement]
		roles[replacement] = role
