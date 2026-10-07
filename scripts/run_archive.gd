extends RefCounted
## Small, explicit profile for cross-run replay motivation.
## It never stores run-local economy, cards, buildings, squads or rescue state.

const SCHEMA_VERSION := 2
const PROFILE_PATH := "user://riftward_profile.json"
const MAX_BLUEPRINTS := 32
const MAX_OBJECTIVES := 64
const MAX_HISTORY := 50
const BLUEPRINT_IDS := ["signal_beacon", "holdfast_beacon"]
const OBJECTIVE_IDS := ["victory_signal", "victory_hold"]
const CHALLENGE_IDS := ["homecoming_pair"]
const BLUEPRINT_CATALOG := {
	"signal_beacon": {"title": "曙光阵列蓝图", "detail": "完成信号结局后记录的远征蓝图"},
	"holdfast_beacon": {"title": "坚守灯塔蓝图", "detail": "需工坊 · 减伤10%/18%"},
}

var path := PROFILE_PATH
var enabled := true
var profile: Dictionary = {}
var last_unlocks: Array[String] = []
var last_objectives: Array[String] = []
var last_challenges: Array[String] = []
var loaded_from_backup := false

func _init(profile_path: String = PROFILE_PATH, write_enabled: bool = true) -> void:
	path = profile_path
	enabled = write_enabled
	profile = _default_profile()
	_load()

func _default_profile() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"unlocked_blueprints": [],
		"completed_objectives": [],
		"completed_challenges": [],
		"run_history": [],
		"settings": {},
	}

func _load() -> void:
	loaded_from_backup = false
	var primary := _read_document(path)
	if bool(primary.get("ok", false)):
		profile = _normalise(primary.get("value", {}))
		return
	var backup := _read_document(path + ".bak")
	if bool(backup.get("ok", false)):
		loaded_from_backup = true
		profile = _normalise(backup.get("value", {}))
		return
	profile = _default_profile()

func reload() -> Dictionary:
	_load()
	return snapshot()

func snapshot() -> Dictionary:
	return profile.duplicate(true)

func unlocked_blueprints() -> Array[String]:
	var result: Array[String] = []
	for value: Variant in profile.get("unlocked_blueprints", []):
		result.append(String(value))
	return result

func completed_objectives() -> Array[String]:
	var result: Array[String] = []
	for value: Variant in profile.get("completed_objectives", []):
		result.append(String(value))
	return result

func completed_challenges() -> Array[String]:
	var result: Array[String] = []
	for value: Variant in profile.get("completed_challenges", []):
		result.append(String(value))
	return result

func has_challenge(challenge_id: String) -> bool:
	return challenge_id in completed_challenges()

func has_blueprint(blueprint_id: String) -> bool:
	return blueprint_id in unlocked_blueprints()

func blueprint_catalog() -> Dictionary:
	return BLUEPRINT_CATALOG.duplicate(true)

func record_victory(result: Dictionary) -> Dictionary:
	last_unlocks.clear()
	last_objectives.clear()
	last_challenges.clear()
	if not enabled:
		return {"ok": false, "reason": "disabled", "unlocked": [], "objective": ""}
	if not bool(result.get("victory", false)):
		return {"ok": false, "reason": "not_victory", "unlocked": [], "objective": ""}
	var ending_key := String(result.get("ending_key", ""))
	var challenge_id := String(result.get("contract_id", ""))
	if not challenge_id.is_empty() and challenge_id not in CHALLENGE_IDS:
		return {"ok": false, "reason": "unknown_challenge", "unlocked": [], "objective": "", "challenge": ""}
	var blueprint_id := ""
	var objective_id := ""
	match ending_key:
		"signal":
			blueprint_id = "signal_beacon"
			objective_id = "victory_signal"
		"hold":
			blueprint_id = "holdfast_beacon"
			objective_id = "victory_hold"
		_:
			return {"ok": false, "reason": "unknown_ending", "unlocked": [], "objective": ""}
	var changed := false
	var blueprints: Array = profile.get("unlocked_blueprints", [])
	if blueprint_id not in blueprints:
		blueprints.append(blueprint_id)
		last_unlocks.append(blueprint_id)
		changed = true
	profile["unlocked_blueprints"] = blueprints
	var objectives: Array = profile.get("completed_objectives", [])
	if objective_id not in objectives:
		objectives.append(objective_id)
		last_objectives.append(objective_id)
		changed = true
	profile["completed_objectives"] = objectives
	var challenge_completed := not challenge_id.is_empty() and bool(result.get("contract_completed", false))
	var challenges: Array = profile.get("completed_challenges", [])
	if challenge_completed and challenge_id not in challenges:
		challenges.append(challenge_id)
		last_challenges.append(challenge_id)
		changed = true
	profile["completed_challenges"] = challenges
	var run_id := _run_id(result, ending_key)
	var history: Array = profile.get("run_history", [])
	var duplicate := false
	for entry: Variant in history:
		if entry is Dictionary and String(entry.get("run_id", "")) == run_id:
			duplicate = true
			break
	if not duplicate:
		history.append(_history_entry(result, run_id, ending_key))
		changed = true
	profile["run_history"] = history
	_trim()
	if changed and not _save():
		return {"ok": false, "reason": "write_failed", "unlocked": last_unlocks.duplicate(), "objective": objective_id, "challenge": last_challenges.duplicate()}
	return {"ok": true, "reason": "recorded" if changed else "already_recorded", "unlocked": last_unlocks.duplicate(), "objective": objective_id, "challenge": last_challenges.duplicate()}

func _run_id(result: Dictionary, ending_key: String) -> String:
	return "%d:%s:%s:%d:%s" % [int(result.get("seed", 0)),String(result.get("mode", "teaching")),ending_key,int(result.get("day_number", 0)),String(result.get("contract_id", ""))]

func _history_entry(result: Dictionary, run_id: String, ending_key: String) -> Dictionary:
	return {
		"run_id": run_id,
		"seed": int(result.get("seed", 0)),
		"mode": String(result.get("mode", "teaching")),
		"outcome": "victory",
		"ending_key": ending_key,
		"day_number": int(result.get("day_number", 0)),
		"kills": int(result.get("kills", 0)),
		"cleansed_nests": int(result.get("cleansed_nests", 0)),
		"survivors_rescued": int(result.get("survivors_rescued", 0)),
		"contract_id": String(result.get("contract_id", "")),
		"contract_completed": bool(result.get("contract_completed", false)),
		"at_ms": int(Time.get_unix_time_from_system() * 1000.0),
	}

func _trim() -> void:
	var blueprints: Array = profile.get("unlocked_blueprints", [])
	blueprints = _unique_allowed(blueprints, BLUEPRINT_IDS, MAX_BLUEPRINTS)
	blueprints.sort()
	profile["unlocked_blueprints"] = blueprints
	var objectives: Array = profile.get("completed_objectives", [])
	objectives = _unique_allowed(objectives, OBJECTIVE_IDS, MAX_OBJECTIVES)
	objectives.sort()
	profile["completed_objectives"] = objectives
	var challenges: Array = profile.get("completed_challenges", [])
	challenges = _unique_allowed(challenges, CHALLENGE_IDS, MAX_OBJECTIVES)
	challenges.sort()
	profile["completed_challenges"] = challenges
	var history: Array = profile.get("run_history", [])
	var bounded: Array = []
	for entry: Variant in history:
		if entry is Dictionary and not String(entry.get("run_id", "")).is_empty():bounded.append(entry)
	if bounded.size() > MAX_HISTORY:bounded = bounded.slice(bounded.size() - MAX_HISTORY)
	profile["run_history"] = bounded
	profile["schema_version"] = SCHEMA_VERSION

func _unique_allowed(values: Array, allowed: Array, limit: int) -> Array:
	var result: Array = []
	for value: Variant in values:
		var item := String(value)
		if item in allowed and item not in result and result.size() < limit:result.append(item)
	return result

func _normalise(raw: Variant) -> Dictionary:
	if not raw is Dictionary:return _default_profile()
	var source: Dictionary = raw
	var schema := int(source.get("schema_version", 0))
	if schema > SCHEMA_VERSION:return _default_profile()
	var result := _default_profile()
	var blueprints: Variant = source.get("unlocked_blueprints", [])
	var objectives: Variant = source.get("completed_objectives", [])
	var challenges: Variant = source.get("completed_challenges", [])
	var history: Variant = source.get("run_history", [])
	if blueprints is Array:result["unlocked_blueprints"] = blueprints.duplicate()
	if objectives is Array:result["completed_objectives"] = objectives.duplicate()
	if challenges is Array:result["completed_challenges"] = challenges.duplicate()
	if history is Array:result["run_history"] = history.duplicate(true)
	var settings: Variant = source.get("settings", {})
	if settings is Dictionary:result["settings"] = settings.duplicate(true)
	_trim_profile(result)
	return result

func _trim_profile(target: Dictionary) -> void:
	var blueprints: Array = target.get("unlocked_blueprints", [])
	target["unlocked_blueprints"] = _unique_allowed(blueprints, BLUEPRINT_IDS, MAX_BLUEPRINTS)
	var objectives: Array = target.get("completed_objectives", [])
	target["completed_objectives"] = _unique_allowed(objectives, OBJECTIVE_IDS, MAX_OBJECTIVES)
	var challenges: Array = target.get("completed_challenges", [])
	target["completed_challenges"] = _unique_allowed(challenges, CHALLENGE_IDS, MAX_OBJECTIVES)
	var history: Array = target.get("run_history", [])
	var bounded: Array = []
	for entry: Variant in history:
		if entry is Dictionary and not String(entry.get("run_id", "")).is_empty():bounded.append(entry.duplicate(true))
	if bounded.size() > MAX_HISTORY:bounded = bounded.slice(bounded.size() - MAX_HISTORY)
	target["run_history"] = bounded
	target["schema_version"] = SCHEMA_VERSION

func _read_document(candidate: String) -> Dictionary:
	if not FileAccess.file_exists(candidate):return {"ok": false, "reason": "missing"}
	var text := FileAccess.get_file_as_string(candidate)
	if text.is_empty():return {"ok": false, "reason": "empty"}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:return {"ok": false, "reason": "invalid_json"}
	return {"ok": true, "value": parsed}

func _save() -> bool:
	var encoded := JSON.stringify(profile, "\t")
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:return false
	file.store_string(encoded)
	file.flush()
	file.close()
	var absolute := ProjectSettings.globalize_path(path)
	var temp_absolute := ProjectSettings.globalize_path(temp_path)
	var backup_absolute := ProjectSettings.globalize_path(path + ".bak")
	var moved_main := false
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(backup_absolute)
		if DirAccess.rename_absolute(absolute, backup_absolute) != OK:
			DirAccess.remove_absolute(temp_absolute)
			return false
		moved_main = true
	if DirAccess.rename_absolute(temp_absolute, absolute) != OK:
		if moved_main:DirAccess.rename_absolute(backup_absolute, absolute)
		DirAccess.remove_absolute(temp_absolute)
		return false
	return true
