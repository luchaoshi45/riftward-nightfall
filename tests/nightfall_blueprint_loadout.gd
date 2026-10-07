extends SceneTree
## Production smoke test for the permanent blueprint loadout and its first
## playable building. The profile uses an isolated user path and the test never
## writes the developer's real archive.

const Catalog := preload("res://scripts/outpost_catalog.gd")
const RunArchive := preload("res://scripts/run_archive.gd")
const RunSession := preload("res://scripts/run_session.gd")
const SEED := 20261007
const WORKSHOP := Vector3(-7.5, 5, -8.5)
const SIGNAL_BEACON := Vector3(-7.5, 5, -3.5)

var checks := 0
var failures: Array[String] = []
var game: Node3D
var profile_path := "user://riftward-blueprint-loadout-%d.json" % Time.get_ticks_usec()

func check(condition: bool, message: String) -> void:
 checks += 1
 if condition: return
 failures.append(message)
 push_error(message)

func cleanup_profile() -> void:
 for suffix in ["", ".tmp", ".bak"]:
  var candidate: String = profile_path + suffix
  if FileAccess.file_exists(candidate):
   DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))

func wait_frames(count: int = 3) -> void:
 for _frame in count: await process_frame

func close_game() -> void:
 if not is_instance_valid(game): return
 await game.prepare_shutdown()
 if current_scene == game: current_scene = null
 game.queue_free()
 game = null
 await wait_frames(4)
 await create_timer(.2, true, false, true).timeout

func _initialize() -> void:
 root.size = Vector2i(1440, 900)
 root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
 root.content_scale_size = root.size
 call_deferred("run")

func run() -> void:
 cleanup_profile()
 check(RunSession.queue_request(self, SEED, "teaching"), "Blueprint fixture queues a real teaching run")
 game = load("res://scenes/nightfall.tscn").instantiate()
 root.add_child(game)
 current_scene = game
 await wait_frames(6)
 check(game.phase == "draft" and game.opening_night_pending, "Blueprint fixture starts at the real opening draft")

 var archive := RunArchive.new(profile_path, true)
 game.archive = archive
 check(game.available_blueprints().size() == 1 and not game.select_blueprint("signal_beacon"),
  "Locked profile cannot select the signal blueprint")
 archive.record_victory({"victory": true, "ending_key": "signal", "seed": SEED, "mode": "teaching", "day_number": 3})
 check(archive.has_blueprint("signal_beacon"), "A recorded signal victory unlocks the real blueprint")
 check(game.available_blueprints().size() == 2, "The draft exposes no-blueprint and unlocked blueprint choices")
 check(game.select_blueprint("signal_beacon") and game.selected_blueprint == "signal_beacon",
  "The draft accepts the unlocked blueprint before the core card")
 check(game.select_run_mode(0), "The opening mode remains selectable alongside the blueprint")
 check(game.choose_card(0), "Choosing the opening core card starts the real night")
 check(game.phase == "night" and game.run_mode_locked and not game.opening_night_pending,
  "The core card locks the blueprint loadout for the active run")
 check(not game.select_blueprint(""), "The active run rejects blueprint changes after core selection")

 game.scrap = 1000
 var missing_workshop: Dictionary = game.districts.build_eligibility("signal_beacon")
 check(not bool(missing_workshop.available), "The signal beacon keeps its live workshop prerequisite")
 var workshop_result: Dictionary = game.districts.build_at(WORKSHOP, "workshop")
 check(bool(workshop_result.ok), "The real workshop can be paid before the blueprint building")
 var eligible: Dictionary = game.districts.build_eligibility("signal_beacon")
 check(bool(eligible.available), "An unlocked and selected blueprint becomes buildable after its prerequisite")
 var before := int(game.scrap)
 var beacon_result: Dictionary = game.districts.build_at(SIGNAL_BEACON, "signal_beacon")
 check(bool(beacon_result.ok) and int(game.scrap) == before - 110,
  "The signal beacon uses its real 110-part payment exactly once")
 check(Catalog.building("signal_beacon").size == Vector2i(3, 2), "The signal beacon reserves a 3x2 construction footprint")
 check(game.districts.live_level("signal_beacon") == 1 and is_equal_approx(game.focus_duration_seconds(), 12.0)
  and is_equal_approx(game.focus_cooldown_seconds(), 18.0),
  "A live level-one beacon changes the actual focus duration and cooldown")
 game.districts.damage(int(beacon_result.index), 100000.0)
 check(game.districts.live_level("signal_beacon") == 0 and is_equal_approx(game.focus_duration_seconds(), 8.0)
  and is_equal_approx(game.focus_cooldown_seconds(), 22.0),
  "Beacon destruction immediately removes its focus bonus")
 var rebuild: Dictionary = game.districts.build_at(SIGNAL_BEACON, "signal_beacon")
 check(bool(rebuild.ok) and game.districts.live_level("signal_beacon") == 1,
  "The same 3x2 plot can be paid to rebuild the beacon and restore its bonus")

 await close_game()
 cleanup_profile()
 print("NIGHTFALL_BLUEPRINT_LOADOUT_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
 quit(0 if failures.is_empty() else 1)
