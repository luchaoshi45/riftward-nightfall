extends Node
## 单首领的局部蓄力攻势。普通移动、普攻与末夜清场由主控制器处理。

const MAX_HEALTH: float = 2600.0
const NORMAL_ARMOR: float = 18.0
const SLAM_DAMAGE: float = 70.0
const ATTACK_INTERVAL: float = 8.0
const WINDUP_SECONDS: float = 2.4
const SLAM_RADIUS: float = 3.2
const INTERRUPT_DAMAGE: float = 220.0
const EXPOSE_SECONDS: float = 4.0
const REINFORCEMENT_BATCH_SIZE: int = 3
const REINFORCEMENT_BATCH_COUNT: int = 2
const REINFORCEMENT_ROLE: String = "runner"

var game: Node3D
var boss: BattleUnit
var _state: String = "approach"
var _cooldown: float = ATTACK_INTERVAL
var _windup: float = 0.0
var _exposed: float = 0.0
var _loss: float = 0.0
var _last_hp: float = MAX_HEALTH
var _locked_point: Vector3 = Vector3.ZERO
var _reinforcement_batches_spawned: int = 0
var _visual_root: Node3D
var _ring: MeshInstance3D
var _lamp: OmniLight3D

func setup(owner_game: Node3D, owner_boss: BattleUnit) -> void:
	clear()
	game = owner_game
	boss = owner_boss
	if get_parent() == null:
		game.add_child(self)
	_state = "approach"
	_cooldown = ATTACK_INTERVAL
	_windup = 0.0
	_exposed = 0.0
	_loss = 0.0
	_reinforcement_batches_spawned = 0
	if not _living(boss):
		_state = "dead"
		return
	boss.title = "灯噬巨兽"
	boss.max_hp = MAX_HEALTH
	boss.hp = MAX_HEALTH
	boss.armor = NORMAL_ARMOR
	boss.damage = SLAM_DAMAGE
	boss.speed = 2.1
	boss.set_meta("threat", "breaker")
	boss.set_meta("siege_boss", true)
	if is_instance_valid(boss.visual):
		boss.visual.scale = Vector3.ONE * 1.85
	_last_hp = boss.hp
	boss.defeated.connect(_on_boss_defeated)
	_visual_root = Node3D.new()
	_visual_root.name = "SiegeBossWarnings"
	add_child(_visual_root)
	_lamp = OmniLight3D.new()
	_visual_root.add_child(_lamp)
	_lamp.light_color = Color("e66d41")
	_lamp.omni_range = SLAM_RADIUS
	_lamp.light_energy = 0.0
	_lamp.shadow_enabled = false

## 蓄力及释放帧返回true，主控制器此帧不得再执行普通敌人攻击。
func advance(delta: float) -> bool:
	if not _living(boss):
		_state = "dead"
		_clear_warning()
		return false
	if not is_instance_valid(game) or game.get("phase") != "night" or delta <= 0.0:
		return _state == "windup"
	_spawn_reinforcements()
	_cooldown = maxf(0.0, _cooldown - delta)
	if _state == "windup":
		# damaged信号在扣血前发出；这里只采样真实扣除的HP，护盾不算。
		_loss += maxf(0.0, _last_hp - boss.hp)
		_last_hp = boss.hp
		boss.moving = false
		boss.attack_queued = false
		boss.attack_windup = 0.0
		if _loss + 0.0001 >= INTERRUPT_DAMAGE:
			_interrupt()
			return true
		_windup = maxf(0.0, _windup - delta)
		_update_warning()
		if _windup <= 0.0:
			# 先提交状态再hurt；反伤或死亡回调不能重入同一次伤害。
			_state = "approach"
			_cooldown = ATTACK_INTERVAL
			_clear_warning()
			_apply_slam()
		return true
	if _state == "exposed":
		_exposed = maxf(0.0, _exposed - delta)
		if _exposed <= 0.0:
			boss.armor = NORMAL_ARMOR
			_state = "approach"
	if boss.position.z > 16.0 or _cooldown > 0.0:
		return false
	var target: Dictionary = _local_target()
	if target.is_empty():
		return false
	_begin_windup(target.position)
	return true

func snapshot() -> Dictionary:
	return {"phase": _state, "windup": _windup, "interrupt_progress": minf(1.0, _loss / INTERRUPT_DAMAGE), "interrupt_damage": _loss, "interrupt_threshold": INTERRUPT_DAMAGE, "exposed": _exposed, "cooldown": _cooldown, "adds": _reinforcement_batches_spawned * REINFORCEMENT_BATCH_SIZE, "reinforcement_batches": _reinforcement_batches_spawned, "reinforcement_total": REINFORCEMENT_BATCH_COUNT * REINFORCEMENT_BATCH_SIZE, "position": _locked_point, "radius": SLAM_RADIUS, "hp": boss.hp if is_instance_valid(boss) else 0.0, "max_hp": MAX_HEALTH}

func clear() -> void:
	if is_instance_valid(boss):
		if boss.defeated.is_connected(_on_boss_defeated):
			boss.defeated.disconnect(_on_boss_defeated)
		if _state == "exposed" and boss.alive:
			boss.armor = NORMAL_ARMOR
	_clear_warning()
	if is_instance_valid(_visual_root):
		_visual_root.queue_free()
	_visual_root = null
	_lamp = null
	boss = null
	_state = "dead"

func _exit_tree() -> void:
	clear()

func _living(unit: Variant) -> bool:
	return is_instance_valid(unit) and unit is BattleUnit and not unit.is_queued_for_deletion() and unit.alive

func _core_point() -> Vector3:
	var point: Vector3 = Vector3.ZERO
	point.y = float(game.call("outpost_height", point)) if game.has_method("outpost_height") else 5.0
	return point

func _reachable(point: Vector3) -> bool:
	return absf(boss.position.y - point.y) <= 1.2 and boss.position.distance_to(point) <= SLAM_RADIUS and (not game.has_method("can_traverse") or bool(game.call("can_traverse", boss.position, point)))

func _local_target() -> Dictionary:
	var candidates: Array[Vector3] = [_core_point()]
	var hero: BattleUnit = game.get("hero") as BattleUnit
	if _living(hero):
		candidates.append(hero.position)
	for soldier in _squad_fighters():
		candidates.append(soldier.position)
	var selected: Dictionary = {}
	var distance: float = INF
	for point in candidates:
		var separation: float = boss.position.distance_to(point)
		if _reachable(point) and separation < distance:
			selected = {"position": point}
			distance = separation
	if not selected.is_empty():
		return selected
	# 在坡道外不把远处灯塔当作无限射程目标；继续走正常南门路线。
	return {}

func _begin_windup(point: Vector3) -> void:
	_state = "windup"
	_locked_point = point
	_windup = WINDUP_SECONDS
	_loss = 0.0
	_last_hp = boss.hp
	boss.moving = false
	boss.attack_queued = false
	boss.attack_windup = 0.0
	_clear_warning()
	_ring = BattleVisuals.ring(_visual_root, point + Vector3.UP * 0.12, SLAM_RADIUS, Color("ed694f"), 0.095)
	_lamp.position = point + Vector3.UP * 1.2
	_lamp.light_energy = 1.1
	if game.has_method("notify"):
		game.call("notify", "灯噬巨兽蓄力 · 移出红圈，或造成220实际伤害打断", 2.4)

func _update_warning() -> void:
	if is_instance_valid(_ring):
		var progress: float = 1.0 - _windup / WINDUP_SECONDS
		(_ring.material_override as StandardMaterial3D).emission_energy_multiplier = 0.45 + progress * 0.8

func _interrupt() -> void:
	_state = "exposed"
	_exposed = EXPOSE_SECONDS
	_windup = 0.0
	_cooldown = ATTACK_INTERVAL
	boss.armor = 0.0
	boss.attack_queued = false
	boss.attack_windup = 0.0
	_clear_warning()
	BattleVisuals.burst(_visual_root, boss.position, 1.8, Color("85d5dc"), 0.28)
	if game.has_method("notify"):
		game.call("notify", "蓄力已打断 · 巨兽护甲破绽持续4秒", 3.0)

func _apply_slam() -> void:
	var source: BattleUnit = boss
	var fighters: Array[BattleUnit] = []
	var hero: BattleUnit = game.get("hero") as BattleUnit
	if _living(hero):
		fighters.append(hero)
	for soldier in _squad_fighters():
		if not soldier in fighters:
			fighters.append(soldier)
	BattleVisuals.burst(_visual_root, _locked_point, SLAM_RADIUS, Color("ed8256"), 0.32)
	for fighter in fighters:
		if _living(fighter) and fighter.position.distance_to(_locked_point) <= SLAM_RADIUS:
			fighter.hurt(SLAM_DAMAGE, source)
	# 核心只在实际锁定区域内受伤，不因首领在地图别处蓄力而掉血。
	if _core_point().distance_to(_locked_point) <= SLAM_RADIUS:
		game.call("apply_beacon_damage", SLAM_DAMAGE, "灯噬巨兽击碎灯塔 · 哨站失守")

func _squad_fighters() -> Array[BattleUnit]:
	var fighters: Array[BattleUnit] = []
	var squad_controller: Node = game.get("squads") as Node
	if not is_instance_valid(squad_controller):
		return fighters
	var groups: Variant = squad_controller.get("squads")
	if not groups is Array:
		return fighters
	for group: Dictionary in groups:
		for soldier: BattleUnit in group.members:
			if _living(soldier):
				fighters.append(soldier)
	return fighters

func _spawn_reinforcements() -> void:
	if not game.has_method("spawn_creature"):
		return
	for threshold in [2.0 / 3.0, 1.0 / 3.0]:
		var step: int = 1 if threshold > 0.5 else 2
		if _reinforcement_batches_spawned >= step or boss.hp / boss.max_hp > threshold:
			continue
		_reinforcement_batches_spawned = step
		for index in range(REINFORCEMENT_BATCH_SIZE):
			var reinforcement: Variant = game.call("spawn_creature", true, REINFORCEMENT_ROLE)
			# Reinforcements belong to the same live wave as the boss. Register
			# each real unit immediately so standard-wave rewards cannot use the
			# old unregistered eight-part fallback.
			if game.has_method("register_active_wave_enemy"):
				game.call("register_active_wave_enemy", reinforcement)

func _clear_warning() -> void:
	if is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null
	if is_instance_valid(_lamp):
		_lamp.light_energy = 0.0

func _on_boss_defeated(_unit: BattleUnit, _source: BattleUnit) -> void:
	_state = "dead"
	_windup = 0.0
	_exposed = 0.0
	_clear_warning()
