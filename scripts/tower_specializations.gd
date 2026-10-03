extends RefCounted
## 独立塔分支：控制器保留选敌、集火、耐久、卡牌/通信塔基础数值及射击表现。
## 接入：resolve_shot 替换原 hurt 和三级溅射；advance 在活跃战斗帧调用一次，
## 移动使用 creature.speed * movement_multiplier(creature)，禁止回写 speed。
## 昼夜/结局/新局调用 reset_effects；死亡调用 forget_enemy；毁塔调用 on_destroyed。
## 选择入口将 choose 返回的 scrap 写回；同一次建造只可选一次，无退款。

const STANDARD := "standard"
const PIERCING := "piercing"
const CONTROL := "control"
const COST := 45
const RADIUS := 3.2
const TARGET_CAP := 5
const SLOW_DURATION := 1.2
const SLOW := .30
const HEAVY_SLOW := .15
var _slows: Dictionary = {}

func branch(pad: Dictionary) -> String:
	return str(pad.get("specialization", STANDARD))

func choose(pad: Dictionary, requested: String, scrap: int, phase: String, frozen: bool = false) -> Dictionary:
	var reason := ""
	if frozen or phase not in ["day", "night"]: reason = "当前不能改装"
	elif requested not in [PIERCING, CONTROL]: reason = "未知分支"
	elif int(pad.get("level", 0)) < 2 or float(pad.get("hp", 0)) <= 0: reason = "需要存活的二级塔"
	elif branch(pad) != STANDARD: reason = "本次建造已选择分支"
	elif scrap < COST: reason = "需要45零件"
	if not reason.is_empty(): return {"ok": false, "scrap": scrap, "reason": reason}
	pad["specialization"] = requested
	return {"ok": true, "scrap": scrap - COST, "reason": ""}

func on_destroyed(pad: Dictionary) -> void:
	# 改装随塔体报废。原建造费用/等级逻辑不变，重建后二级可重新付费选择。
	pad["specialization"] = STANDARD
	# 已射出的短时牵制仍自然到期，不因毁塔永久残留。

func heavy(enemy: BattleUnit) -> bool:
	return str(enemy.get_meta("threat", "")) in ["breaker", "sapper"]

func eligible(enemy: BattleUnit) -> bool:
	return is_instance_valid(enemy) and enemy.alive and enemy.kind == "monster" and enemy.team == 2

func cooldown_multiplier(pad: Dictionary) -> float:
	return 1.25 if branch(pad) == CONTROL else 1.0

func resolve_shot(pad: Dictionary, selected: BattleUnit, enemies: Array, base_damage: float, source: BattleUnit) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	if int(pad.get("level", 0)) <= 0 or float(pad.get("hp", 0)) <= 0 or not eligible(selected): return hits
	var kind := branch(pad)
	var impact := selected.position
	if kind == PIERCING:
		# 重敌1.65倍，其他0.75倍；仅此弹忽略50%正护甲，不给其他伤害破甲增益。
		var amount := base_damage * (1.65 if heavy(selected) else .75)
		var armor := maxf(0.0, selected.armor)
		amount *= (100.0 + armor) / (100.0 + armor * .5)
		_hit(selected, amount, source, hits, false)
		return hits # 破甲三级也放弃原溅射。
	if kind == CONTROL:
		# 主目标计入5个上限；范围按地面距离，最近优先，保留原集火目标。
		var nearby: Array[BattleUnit] = []
		for candidate in enemies:
			if candidate != selected and eligible(candidate) and _distance(candidate.position, impact) <= RADIUS:
				if not nearby.has(candidate): nearby.append(candidate)
		nearby.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
			var da := _distance(a.position, impact)
			var db := _distance(b.position, impact)
			return da < db if not is_equal_approx(da, db) else a.get_instance_id() < b.get_instance_id())
		_hit(selected, base_damage * .55, source, hits, true)
		for i in mini(TARGET_CAP - 1, nearby.size()):
			_hit(nearby[i], base_damage * .22, source, hits, true)
		return hits # 替代而非叠加原三级溅射。
	_hit(selected, base_damage, source, hits, false)
	if int(pad.level) >= 3:
		for candidate in enemies:
			if candidate != selected and eligible(candidate) and candidate.position.distance_to(impact) < 2.7:
				_hit(candidate, base_damage * .36, source, hits, false)
	return hits

func _distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _hit(enemy: BattleUnit, amount: float, source: BattleUnit, hits: Array[Dictionary], slow: bool) -> void:
	if not eligible(enemy): return
	enemy.hurt(amount, source)
	if slow and enemy.alive:
		if not enemy.defeated.is_connected(_on_defeated): enemy.defeated.connect(_on_defeated)
		# 同类减速仅取最强并刷新到1.2秒：最多一层，不能相加或延长累积。
		var strength := HEAVY_SLOW if heavy(enemy) else SLOW
		var id := enemy.get_instance_id()
		var previous: Dictionary = _slows.get(id, {})
		_slows[id] = {"unit": weakref(enemy), "remaining": SLOW_DURATION,
			"strength": maxf(strength, float(previous.get("strength", 0.0)))}
	elif not enemy.alive: forget_enemy(enemy)
	hits.append({"target": enemy, "raw_damage": amount, "slowed": slow and enemy.alive})

func advance(delta: float, active: bool = true) -> void:
	# 暂停、选卡不走秒；清理死亡/释放引用仍可执行。
	for id in _slows.keys():
		var effect: Dictionary = _slows[id]
		var enemy: BattleUnit = effect.unit.get_ref() as BattleUnit
		if not eligible(enemy):
			_slows.erase(id)
			continue
		if active: effect.remaining = maxf(0.0, float(effect.remaining) - maxf(delta, 0.0))
		if effect.remaining <= 0: _slows.erase(id)

func movement_multiplier(enemy: BattleUnit) -> float:
	if not eligible(enemy): return 1.0
	var effect: Dictionary = _slows.get(enemy.get_instance_id(), {})
	return 1.0 - float(effect.get("strength", 0.0))

func forget_enemy(enemy: BattleUnit) -> void:
	if is_instance_valid(enemy): _slows.erase(enemy.get_instance_id())

func _on_defeated(enemy: BattleUnit, _source: BattleUnit) -> void:
	forget_enemy(enemy) # 当帧清除，死亡后同帧复活也不能继承旧减速。

func reset_effects() -> void:
	_slows.clear()

func description(pad: Dictionary) -> String:
	match branch(pad):
		PIERCING: return "破甲：重敌×1.65 / 其余×0.75，忽略50%护甲，无溅射"
		CONTROL: return "牵制：主伤×0.55 / 群伤×0.22，3.2米最多5敌，减速30%（重敌15%）1.2秒，间隔×1.25"
	return "通用：保留原伤害与三级溅射；二级可花45零件选一次分支"
