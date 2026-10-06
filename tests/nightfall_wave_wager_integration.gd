extends SceneTree
## Production integration for the controller-owned wave wager. The isolated
## module test covers pure state transitions; this file checks the actual saved
## plan, controller wallet, wave birth/death ledger, retry cleanup and the F3
## defense-page hit rectangles without adding a second reward account.

const SCENE := "res://scenes/nightfall.tscn"
const CleanHud = preload("res://scripts/nightfall_clean_hud.gd")
const VIEWPORT := Vector2i(1440, 900)

var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	root.size = VIEWPORT
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failures.append(message)
	if failures.size() <= 20:
		push_error(message)

func clear_enemies() -> void:
	game.clear_lobbers()
	game.clear_summoners()
	game.clear_warders()
	for value: Variant in game.enemies:
		if is_instance_valid(value):
			(value as BattleUnit).queue_free()
	game.enemies.clear()

func new_game() -> Node3D:
	var instance: Node3D = load(SCENE).instantiate()
	root.add_child(instance)
	current_scene = instance
	await process_frame
	return instance

func close_game(instance: Node3D) -> void:
	if not is_instance_valid(instance):
		return
	await instance.prepare_shutdown()
	instance.queue_free()
	await process_frame

func prepare_standard_day() -> void:
	game.run_mode = "siege"
	check(game.choose_card(0), "Standard run must enter the first night after choosing a core")
	clear_enemies()
	game.phase = "day"
	game.phase_time = game.DAY_LENGTH
	game.begin_day()
	check(game.phase == "day" and game.day_number == 1, "Controller day setup must expose the wager before the first standard night")

func run() -> void:
	game = await new_game()
	await prepare_standard_day()
	var first: Dictionary = game.wave_wager_snapshot()
	check(bool(first.get("enabled", false)) and bool(first.get("available", false)), "Standard day must expose one available wager in the F3 defense page")
	var targets: Array = game.wave_wager_target_options()
	check(targets.size() == game.WAVES_PER_NIGHT, "Wager target cards must mirror every saved wave")
	game.hud.detail_tab = "defense"
	check(game.hud.wave_wager_visible(), "The wager must stay inside the existing F3 defense drawer")
	for index in targets.size():
		check(CleanHud.DRAWER_RECT.encloses(game.hud.wave_wager_target_rect(index)), "Target card %d must remain inside the drawer" % index)
	for index in game.wave_wager.risk_options().size():
		check(CleanHud.DRAWER_RECT.encloses(game.hud.wave_wager_risk_rect(index)), "Risk card %d must remain inside the drawer" % index)
	var signature: String = String(targets[2].get("plan_signature", ""))
	check(not signature.is_empty() and signature.contains("night-plan"), "The wager must bind a stable saved-plan signature")
	check(game.select_wave_wager_target(2), "A target wave must be selectable before choosing a risk tier")
	var before_parts := int(game.scrap)
	var quote: Dictionary = game.place_wave_wager(1)
	check(bool(quote.get("ok", false)) and int(quote.get("stake", -1)) == 40, "The bold tier must quote its real 40-part stake")
	check(int(game.scrap) == before_parts, "Risk quotation must not deduct parts before night lock")
	check(String(game.wave_wager_snapshot().get("state", "")) == "selected", "A quoted tier must remain selected until night starts")
	game.start_night()
	var locked: Dictionary = game.wave_wager_snapshot()
	check(String(locked.get("state", "")) == "locked", "Starting the night must lock the selected ticket")
	check(int(game.scrap) == before_parts - 40, "Night lock must deduct the stake exactly once")
	check(int(locked.get("target_reward_id", -1)) == 2 and int(locked.get("target_count", 0)) == int(targets[2].count), "Lock must retain the exact target reward id and count")

	# Skip the automatically spawned first wave and birth the actual saved target
	# wave. Every death below goes through BattleUnit's production signal.
	clear_enemies()
	game.wave_index = 2
	game.spawn_night_wave()
	var target_victims: Array = game.enemies.duplicate()
	var target_count := target_victims.size()
	check(target_count == int(targets[2].count), "Target card count must equal actual production births")
	for value: Variant in target_victims:
		var enemy: BattleUnit = value as BattleUnit
		if is_instance_valid(enemy) and enemy.alive:
			enemy.hurt(100000.0, game.hero)
	var won: Dictionary = game.wave_wager_snapshot()
	check(String(won.get("state", "")) == "won", "A fully cleared real target wave must win the wager")
	check(int(game.scrap) == before_parts - 40 + 24 + 120, "A bold win must preserve the base 24-part wave budget and pay the gross 120 once")
	var duplicate_before := int(game.scrap)
	if not target_victims.is_empty() and is_instance_valid(target_victims[0]):
		(target_victims[0] as BattleUnit).hurt(100000.0, game.hero)
	check(int(game.scrap) == duplicate_before, "A repeated production death callback must not duplicate wager payout")

	# Plan replacement before lock invalidates the old offer without refunding a
	# nonexistent stake and exposes a fresh target identity for the same day.
	clear_enemies()
	game.phase = "day"
	game.phase_time = game.DAY_LENGTH
	game.prepare_next_night_plan(false)
	var replacement: Dictionary = game.wave_wager_snapshot()
	check(String(replacement.get("state", "")) in ["offered", "selected", "won"], "Plan refresh must leave a visible terminal or fresh ticket state")
	check(String(replacement.get("plan_signature", "")) != signature or String(replacement.get("state", "")) == "won", "A changed saved plan must not keep the stale ticket identity")

	await close_game(game)
	game = await new_game()
	await prepare_standard_day()
	check(game.select_wave_wager_target(0), "Failure path must select a target")
	check(bool(game.place_wave_wager(0).get("ok", false)), "Failure path must quote the steady tier")
	var failed_parts := int(game.scrap)
	game.start_night()
	check(String(game.wave_wager_snapshot().get("state", "")) == "locked", "Failure path must lock before defeat")
	game.end_defeat("押注集成失败路径")
	var lost: Dictionary = game.wave_wager_snapshot()
	check(String(lost.get("state", "")) == "lost", "Defeat must forfeit an active wager")
	check(int(game.scrap) == failed_parts - 20, "Defeat must keep the already-paid stake forfeited")
	await game.prepare_shutdown()
	check(String(game.wave_wager_snapshot().get("state", "idle")) == "idle", "Shutdown/retry cleanup must clear the run-local wager")
	await close_game(game)
	print("NIGHTFALL_WAVE_WAGER_INTEGRATION_", "OK" if failures.is_empty() else "FAILED", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
