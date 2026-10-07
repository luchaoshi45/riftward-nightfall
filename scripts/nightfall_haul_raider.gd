class_name NightfallHaulRaider
extends RefCounted
## 夜采/采运存在载货时才会出现的劫运威胁。
## 它只负责出现门槛与真实目标快照；伤害、死亡和货物丢失仍走原战斗/物流链。

const MIN_NIGHT: int = 2
const SPAWN_AFTER_SECONDS: float = 22.0

var game: Node3D
var night: int = -1
var elapsed: float = 0.0
var spawned: bool = false
var source_token: int = -1

func setup(owner_game: Node3D) -> void:
	clear()
	game = owner_game

func begin_night(night_index: int) -> void:
	night = night_index
	elapsed = 0.0
	spawned = false
	source_token = -1

func advance(delta: float) -> void:
	if not _active() or not is_finite(delta) or delta <= 0.0:
		return
	elapsed += delta

func eligible() -> bool:
	return _active() and not spawned and night >= MIN_NIGHT and String(game.get("run_mode")) != "teaching" \
		and elapsed >= SPAWN_AFTER_SECONDS and has_loaded_target()

func has_loaded_target() -> bool:
	var logistics: Variant = game.get("logistics")
	return is_instance_valid(logistics) and logistics.has_method("haul_raider_targets") \
		and not (logistics.haul_raider_targets() as Array).is_empty()

func target_for(origin: Vector3) -> Dictionary:
	if not is_instance_valid(game):
		return {}
	var logistics: Variant = game.get("logistics")
	if not is_instance_valid(logistics) or not logistics.has_method("haul_raider_target"):
		return {}
	return logistics.haul_raider_target(origin)

func mark_spawned(source: BattleUnit) -> void:
	spawned = true
	source_token = source.get_instance_id() if is_instance_valid(source) else -1

func snapshot() -> Dictionary:
	var target := target_for(Vector3.ZERO)
	return {"night": night, "elapsed": elapsed, "spawned": spawned,
		"source_token": source_token, "possible": _possible(),
		"eligible": eligible(), "target_token": int(target.get("token", -1)),
		"cargo": int(target.get("haul_cargo", 0)),
		"target_position": target.get("position", Vector3.INF)}

func clear() -> void:
	game = null
	night = -1
	elapsed = 0.0
	spawned = false
	source_token = -1

func _possible() -> bool:
	return _active() and night >= MIN_NIGHT and String(game.get("run_mode")) != "teaching"

func _active() -> bool:
	return is_instance_valid(game) and not game.is_queued_for_deletion() \
		and String(game.get("phase")) == "night" and not bool(game.get("quitting")) \
		and not bool(game.get("restart_pending")) and not bool(game.get("shutting_down"))
