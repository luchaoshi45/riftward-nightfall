class_name NightfallBounty
extends RefCounted
## One optional run-local reward, committed against the real sealed wave ledger.
const EncountersScript = preload("res://scripts/nightfall_encounters.gd")
const REWARD := 48
const ID := "shellguard_pack"
const NIGHT := 2
const WAVE_INDEX := 2
const WAVE := WAVE_INDEX + 1
const REWARD_ID := 7 # Five waves per night: (2 - 1) * 5 + 2.

var _state := "idle"
var _mode := ""
var _selected_shellguard_count := -1
var _expected_count := 0
var _reward_id := -1
var _locked_roles: Array[String] = []

func offer(mode: String, night: int) -> void:
	if _state in ["won", "expired"]: return
	if mode not in ["standard", "siege", "echo"] or night != NIGHT:
		if _state in ["selected", "active"]:
			expire()
		elif _state == "offered":
			_state = "idle"
			_mode = ""
		return
	if _state == "active": return
	if _mode != mode:
		_clear_commit()
		_state = "offered"
	_mode = mode
	if _state == "idle": _state = "offered"

## Select from an unmodified baseline; a later nest change may rebuild that plan.
func select(plan: Array[Dictionary]) -> bool:
	if _state not in ["offered", "selected"]: return false
	var candidate: Array[Dictionary] = EncountersScript.new().with_bounty(plan)
	if candidate.is_empty() or String(candidate[WAVE_INDEX].get("mode", "")) != _mode: return false
	_selected_shellguard_count = int(plan[WAVE_INDEX].shellguard_count)
	_state = "selected"
	return true

func deselect() -> void:
	if _state != "selected": return
	_clear_commit()
	_state = "offered"

## Lock only the transformed saved plan. An unsuccessful lock cannot stay active.
func lock(plan: Array[Dictionary], reward_id: int) -> bool:
	if _state not in ["selected", "active"]: return false
	var entry := _locked_entry(plan)
	if reward_id != REWARD_ID or entry.is_empty():
		_clear_commit()
		_state = "expired"
		return false
	var roles: Array = entry.roles
	if _state == "active":
		if _reward_id == reward_id and _expected_count == int(entry.count) and _locked_roles == roles: return true
		_clear_commit()
		_state = "expired"
		return false
	_expected_count = int(entry.count)
	_reward_id = reward_id
	_locked_roles.assign(roles)
	_state = "active"
	return true

func _locked_entry(plan: Array[Dictionary]) -> Dictionary:
	if plan.size() != EncountersScript.WAVE_TIMES.size(): return {}
	for index in plan.size():
		var row: Dictionary = plan[index]
		if int(row.get("night", -1)) != NIGHT or String(row.get("mode", "")) != _mode: return {}
		if int(row.get("index", -1)) != index or int(row.get("wave_number", -1)) != index + 1: return {}
		if index != WAVE_INDEX and (row.has("bounty_id") or row.has("bounty_reward")): return {}
	var entry: Dictionary = plan[WAVE_INDEX]
	if String(entry.get("bounty_id", "")) != ID or int(entry.get("bounty_reward", 0)) != REWARD: return {}
	if bool(entry.get("boss_entry", false)) or not entry.get("roles") is Array: return {}
	var roles: Array = entry.roles
	if roles.is_empty() or int(entry.get("count", 0)) != roles.size() or int(entry.get("role_count", 0)) != roles.size(): return {}
	if _selected_shellguard_count < 0 or roles.count("shellguard") != _selected_shellguard_count + 2: return {}
	if int(entry.get("shellguard_count", -1)) != roles.count("shellguard"): return {}
	for role: Variant in roles:
		if not role is String or role not in EncountersScript.KNOWN_ROLES: return {}
	return entry

func completion(reward_id: int, ledger: Dictionary, time_left: float, eligible: bool) -> int:
	if _state != "active" or reward_id != _reward_id or _expected_count <= 0: return 0
	if not eligible or not is_finite(time_left) or time_left <= 0.0: return 0
	if int(ledger.get("id", -1)) != _reward_id: return 0
	if ledger.get("sealed", false) != true or ledger.get("cleared", false) != true: return 0
	if int(ledger.get("count", 0)) != _expected_count or int(ledger.get("kills", 0)) != _expected_count: return 0
	# Commit before returning income so repeated death callbacks cannot pay again.
	_state = "won"
	return REWARD

func expire() -> void:
	if _state in ["selected", "active"]: _state = "expired"

func _clear_commit() -> void:
	_selected_shellguard_count = -1
	_expected_count = 0
	_reward_id = -1
	_locked_roles.clear()

func reset() -> void:
	_clear_commit()
	_state = "idle"
	_mode = ""

func snapshot() -> Dictionary:
	return {"state": _state, "reward": REWARD, "wave": WAVE, "expected_count": _expected_count, "bounty_id": ID}
