extends SceneTree
## Small persistence regression for the cross-run profile. The test uses an
## isolated user:// path and never touches the developer's real archive.

const RunArchive = preload("res://scripts/run_archive.gd")

var checks := 0
var failures: Array[String] = []
var test_path := "user://riftward-profile-regression-%d.json" % Time.get_ticks_usec()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _paths() -> Array[String]:
	return [test_path, test_path + ".tmp", test_path + ".bak"]

func _cleanup() -> void:
	for candidate in _paths():
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))

func _write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Open isolated profile fixture")
	if file != null:
		file.store_string(value)
		file.flush()
		file.close()

func _victory(ending_key: String, seed: int = 20261007, day: int = 3) -> Dictionary:
	return {
		"victory": true,
		"ending_key": ending_key,
		"seed": seed,
		"mode": "standard",
		"day_number": day,
		"kills": 19,
		"cleansed_nests": 2,
		"survivors_rescued": 1,
	}

func _challenge_victory(ending_key: String, seed: int, day: int, completed: bool) -> Dictionary:
	var result := _victory(ending_key,seed,day)
	result["contract_id"]="homecoming_pair"
	result["contract_completed"]=completed
	return result

func _round_trip_and_idempotence() -> void:
	_cleanup()
	var archive = RunArchive.new(test_path, true)
	check(archive.snapshot().schema_version == 2, "New profiles use the current schema")
	var first: Dictionary = archive.record_victory(_victory("signal"))
	check(bool(first.ok) and first.reason == "recorded", "A real victory is written")
	check(archive.has_blueprint("signal_beacon"), "Signal victory unlocks its blueprint")
	check(archive.completed_objectives().has("victory_signal"), "Signal victory records its objective")
	check(archive.snapshot().run_history.size() == 1, "A victory creates one history entry")
	check(archive.snapshot().completed_challenges.is_empty(), "Ordinary victories do not unlock a challenge")
	var loaded = RunArchive.new(test_path, true)
	check(loaded.has_blueprint("signal_beacon"), "Profile round-trips through disk")
	check(loaded.snapshot().run_history.size() == 1, "History round-trips through disk")
	var duplicate: Dictionary = loaded.record_victory(_victory("signal"))
	check(duplicate.reason == "already_recorded" and duplicate.unlocked.is_empty(), "Duplicate victory is idempotent")
	check(loaded.snapshot().run_history.size() == 1, "Duplicate victory does not grow history")

func _atomic_and_backup_recovery() -> void:
	var archive = RunArchive.new(test_path, true)
	archive.record_victory(_victory("hold", 20261008, 4))
	check(not FileAccess.file_exists(test_path + ".tmp"), "Atomic save removes the temporary file")
	check(FileAccess.file_exists(test_path + ".bak"), "A replacement keeps a backup copy")
	_write(test_path, "")
	var recovered = RunArchive.new(test_path, true)
	check(recovered.loaded_from_backup, "A corrupt primary profile restores its backup")
	check(recovered.has_blueprint("signal_beacon"), "Backup recovery keeps existing unlocks")
	check(not recovered.has_blueprint("holdfast_beacon"), "Backup recovery uses the last known good profile")

func _schema_migration_and_whitelist() -> void:
	_cleanup()
	_write(test_path, JSON.stringify({
		"schema_version": 0,
		"unlocked_blueprints": ["signal_beacon", "signal_beacon", "unknown"],
		"completed_objectives": ["victory_hold", "bad"],
		"run_history": [{"run_id": "legacy", "outcome": "victory"}, "bad"],
		"scrap": 99999,
	}))
	var migrated = RunArchive.new(test_path, true)
	check(migrated.snapshot().schema_version == 2, "Legacy profiles migrate to schema 2")
	check(migrated.unlocked_blueprints().size() == 1 and migrated.has_blueprint("signal_beacon"), "Legacy blueprints are unique and allowlisted")
	check(migrated.completed_objectives().size() == 1 and migrated.completed_objectives().has("victory_hold"), "Legacy objectives are allowlisted")
	check(migrated.snapshot().run_history.size() == 1, "Legacy history drops malformed entries")
	check(not migrated.snapshot().has("scrap"), "Run-local economy is never imported into the profile")
	check(migrated.completed_challenges().is_empty(), "Legacy profiles migrate with no fabricated challenges")
	_write(test_path, JSON.stringify({"schema_version": 999, "unlocked_blueprints": ["holdfast_beacon"]}))
	var future = RunArchive.new(test_path, true)
	check(future.unlocked_blueprints().is_empty(), "Unknown future schemas fail closed")

func _rejection_and_no_inheritance() -> void:
	_cleanup()
	var archive = RunArchive.new(test_path, true)
	var failure: Dictionary = archive.record_victory({"victory": false, "ending_key": "signal"})
	check(not bool(failure.ok) and failure.reason == "not_victory", "Failed runs do not unlock blueprints")
	check(not FileAccess.file_exists(test_path), "Failed runs do not create a profile")
	var unknown: Dictionary = archive.record_victory({"victory": true, "ending_key": "other"})
	check(not bool(unknown.ok) and unknown.reason == "unknown_ending", "Unknown endings are rejected")
	var unknown_challenge: Dictionary = archive.record_victory({"victory": true, "ending_key": "signal", "contract_id": "not_allowed"})
	check(not bool(unknown_challenge.ok) and unknown_challenge.reason == "unknown_challenge", "Unknown challenge ids are rejected")
	var disabled = RunArchive.new(test_path, false)
	var blocked: Dictionary = disabled.record_victory(_victory("signal"))
	check(not bool(blocked.ok) and blocked.reason == "disabled", "Disabled persistence never writes")
	check(not FileAccess.file_exists(test_path), "Disabled persistence leaves no file")
	var fresh = RunArchive.new(test_path, true)
	check(fresh.snapshot().run_history.is_empty() and fresh.unlocked_blueprints().is_empty(), "A new run reads only unlocks and no run-local state")
	check(not fresh.snapshot().has("cards") and not fresh.snapshot().has("buildings") and not fresh.snapshot().has("squads"), "Profile excludes cards, buildings and squads")
	var challenge := RunArchive.new(test_path, true)
	var completed: Dictionary = challenge.record_victory(_challenge_victory("signal",20261009,3,true))
	check(bool(completed.ok) and challenge.has_challenge("homecoming_pair"), "A completed allowed challenge is persisted")
	var challenge_duplicate: Dictionary = challenge.record_victory(_challenge_victory("signal",20261009,3,true))
	check(challenge_duplicate.reason == "already_recorded" and challenge.completed_challenges().size() == 1, "Challenge victory history is idempotent")
	var incomplete := RunArchive.new(test_path + ".incomplete", true)
	var incomplete_result: Dictionary = incomplete.record_victory(_challenge_victory("hold",20261010,4,false))
	check(bool(incomplete_result.ok) and incomplete.completed_challenges().is_empty(), "An incomplete challenge does not unlock the archive")

func _initialize() -> void:
	_round_trip_and_idempotence()
	_atomic_and_backup_recovery()
	_schema_migration_and_whitelist()
	_rejection_and_no_inheritance()
	_cleanup()
	print("NIGHTFALL_RUN_ARCHIVE_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
