extends RefCounted
## Fixed run-local wave budgets. The controller adds only returned real income.
## Register the initial pack, seal it, then call defeat from the death signal.
## Adds reopen registration until seal_wave is called again; sealing never pays.
const DEFAULT_BUDGET: int = 24
var _waves: Dictionary = {}
var _enemy_waves: Dictionary = {}

func begin_wave(id: int, budget: int = DEFAULT_BUDGET) -> bool:
	if id < 0 or budget < 0 or _waves.has(id): return false
	_waves[id] = {"budget": budget, "count": 0, "kills": 0, "paid": 0,
		"sealed": false, "cleared": false, "units": {}, "defeated": {}}
	return true

func register_enemy(id: int, enemy: Variant) -> bool:
	if not _waves.has(id) or typeof(enemy) != TYPE_OBJECT or not is_instance_valid(enemy) or not enemy is BattleUnit:
		return false
	if not enemy.alive or enemy.kind != "monster" or enemy.team != 2:
		return false
	var wave: Dictionary = _waves[id]
	var instance_id: int = enemy.get_instance_id()
	if wave.cleared or _enemy_waves.has(instance_id): return false
	wave.units[instance_id] = weakref(enemy)
	wave.count += 1
	wave.sealed = false
	_enemy_waves[instance_id] = id
	enemy.set_meta("wave_reward_id", id)
	return true

func seal_wave(id: int) -> bool:
	if not _waves.has(id): return false
	var wave: Dictionary = _waves[id]
	if wave.cleared: return false
	wave.sealed = true
	# Empty waves and deaths before sealing never create a free completion payout.
	# Production registration occurs synchronously before any combat simulation.
	if wave.count == 0 or wave.kills == wave.count:
		wave.cleared = true
	return true

func defeat(enemy: Variant) -> int:
	if typeof(enemy) != TYPE_OBJECT or not is_instance_valid(enemy) or not enemy is BattleUnit or enemy.alive:
		return 0
	var instance_id: int = enemy.get_instance_id()
	if not _enemy_waves.has(instance_id): return 0
	var id: int = _enemy_waves[instance_id]
	if not _waves.has(id): return 0
	var wave: Dictionary = _waves[id]
	if wave.cleared or wave.defeated.has(instance_id): return 0
	var registered: Variant = wave.units[instance_id].get_ref()
	if not is_instance_valid(registered) or registered != enemy: return 0
	wave.defeated[instance_id] = true
	wave.kills += 1
	var target_paid: int = int(floor(float(int(wave.kills) * int(wave.budget) * 7) / float(int(wave.count) * 10)))
	if wave.sealed and wave.kills == wave.count:
		target_paid = int(wave.budget)
		wave.cleared = true
	var income: int = maxi(0, mini(int(wave.budget), target_paid) - int(wave.paid))
	wave.paid += income
	return income

func snapshot(id: int) -> Dictionary:
	if not _waves.has(id): return {}
	var wave: Dictionary = _waves[id]
	return {"id": id, "budget": int(wave.budget), "count": int(wave.count),
		"kills": int(wave.kills), "paid": int(wave.paid),
		"remaining": int(wave.budget) - int(wave.paid),
		"sealed": bool(wave.sealed), "cleared": bool(wave.cleared)}

func reset() -> void:
	for id in _waves:
		var wave: Dictionary = _waves[id]
		for instance_id in wave.units:
			var enemy: Variant = wave.units[instance_id].get_ref()
			if is_instance_valid(enemy) and enemy.get_meta("wave_reward_id", -1) == id:
				enemy.remove_meta("wave_reward_id")
	_waves.clear()
	_enemy_waves.clear()
