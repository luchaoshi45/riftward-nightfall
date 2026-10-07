extends SceneTree
## Real saved-plan births, one-wallet deaths, nest reductions and scene retries.
const Encounters := preload("res://scripts/nightfall_encounters.gd")
const Session := preload("res://scripts/run_session.gd")
const SCENE := "res://scenes/nightfall.tscn"
const SEED := 20261006
const LOBBERS_PER_WAVE := {1: [0, 0, 0, 0, 0], 2: [0, 0, 1, 0, 1], 3: [0, 1, 2, 1, 2], 4: [0, 2, 3, 2, 3]}
var game: Node3D
var checks := 0
var failures: Array[String] = []
var lobber_deaths := 0
var burstling_deaths := 0

func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.hide()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 30: push_error(message)

func clear_enemies() -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	game.enemies.clear()

func counts(roles: Array) -> Dictionary:
	var result: Dictionary = {}
	for role in roles: result[String(role)] = int(result.get(String(role), 0)) + 1
	return result

func verify_plan_rules() -> void:
	var encounters := Encounters.new()
	for seed_value in [SEED, 73571]:
		for mode in ["teaching", "standard", "siege", "echo"]:
			for night in range(1, 5):
				var plan: Array[Dictionary] = encounters.make_plan(mode, night, seed_value, 0)
				check(plan == encounters.make_plan(mode, night, seed_value, 0), "Same seed and mode must reproduce the entire saved plan")
				var original_rng := RandomNumberGenerator.new()
				original_rng.seed = seed_value + night * 104729
				original_rng.randi_range(0, 2)
				for wave in 5:
					# Unchanged legacy helpers provide the pre-replacement composition
					# with the original number and order of random draws.
					var original: Dictionary = encounters._first_night(wave, original_rng) if night == 1 else encounters._later_night(wave, night, String(plan[wave].theme), original_rng)
					var entry: Dictionary = plan[wave]
					var original_counts := counts(original.roles)
					var actual_counts := counts(entry.roles)
					var population := 8 + night * 3 if wave == 0 else 8 + night * 2 + wave * 2
					check(int(entry.role_count) == population and entry.roles.size() == population, "Replacing specialists must keep every original wave population")
					check(int(actual_counts.get("lobber", 0)) == int(LOBBERS_PER_WAVE[night][wave]), "Every mode must use the declared progressive lobber wave counts")
					var summoner_count := 1 if night >= 3 and wave == 2 else 0
					check(int(actual_counts.get("summoner", 0)) == summoner_count and int(entry.get("reinforcement_cap",0)) == summoner_count * 2, "Only later third waves may advertise one source and two finite potential reinforcements")
					var warder_count := 1 if (night == 2 and wave == 3) or (night >= 3 and wave in [1,3]) else 0
					var shellguard_count := 1 if (night == 2 and wave == 2) or (night >= 3 and wave in [0,4]) else 0
					var burstling_count := 1 if mode != "teaching" and ((night == 2 and wave == 1) or (night >= 3 and wave in [1,3])) else 0
					check(int(actual_counts.get("warder",0)) == warder_count and int(entry.get("warder_count",0)) == warder_count and int(entry.get("shield_cast_cap",0)) == warder_count*3, "Saved finite shielding remains in its declared waves")
					check(int(actual_counts.get("shellguard",0)) == shellguard_count and int(entry.get("shellguard_count",0)) == shellguard_count, "One armored ordinary replacement appears only in its declared waves")
					check(int(actual_counts.get("burstling",0)) == burstling_count and int(entry.get("burstling_count",0)) == burstling_count, "Only declared four-night-mode waves replace exactly one ordinary follower with a burstling")
					check(int(actual_counts.get("basic", 0)) == population - original.roles.size() - summoner_count - warder_count - shellguard_count - burstling_count, "Finite sources, armored actors and burstlings replace ordinary population while preserving every original specialist")
					for role in original_counts:
						check(int(actual_counts.get(role, 0)) >= 1 and int(actual_counts[role]) <= int(original_counts[role]), "Every original specialist identity must retain at least one member")
					for role in entry.roles: check(Encounters.KNOWN_ROLES.has(String(role)), "Every saved role must have a known production identity")
					if night == 1:
						var original_pack: Dictionary = original_counts.duplicate()
						original_pack["basic"] = population - original.roles.size()
						check(actual_counts == original_pack, "First-night role counts must exactly match the untouched legacy composition")
						check(entry.title == original.title and entry.threat == original.threat and entry.advice == original.advice and not entry.roles.has("lobber"), "First-night threat labels and guidance must stay unchanged")
					elif wave == 2 and night == 2:
						check(entry.threat == "lobber" and String(entry.advice).contains("2米") and String(entry.advice).contains("集火") and String(entry.advice).contains("11.2") and String(entry.advice).contains("1.15") and String(entry.advice).contains("0.75"), "Lobber preview must expose actionable real timing, range and dodge guidance")
					if summoner_count > 0:
						check(entry.threat == "summoner" and String(entry.advice).contains("2.4") and String(entry.advice).contains("10") and String(entry.advice).contains("2") and String(entry.advice).contains("南门") and String(entry.advice).contains("集火"), "Finite-summoner preview must describe genuine limits, timing, entry and counterplay")
					if burstling_count > 0:
						check(String(entry.title).ends_with(" · 爆裂逼近") and String(entry.advice).ends_with(" " + Encounters.BURSTLING_ADVICE), "Actual burstling waves append their exact preparation, fixed-circle and interruption counterplay")
					else:
						check(not String(entry.title).contains("爆裂逼近") and not String(entry.advice).contains("爆裂体"), "Teaching, first night and all unselected waves cannot advertise absent burstlings")
					var boss_expected := night == (3 if mode == "teaching" else 4) and wave == 4
					check(bool(entry.boss_entry) == boss_expected and int(entry.boss_count) == (1 if boss_expected else 0) and int(entry.count) == population + (1 if boss_expected else 0), "Replacement must preserve original boss and total counts")
					for nest_count in [1, 2, 3]:
						var reduced: Dictionary = encounters.make_plan(mode, night, seed_value, nest_count)[wave]
						var reduced_counts := counts(reduced.roles)
						for role in actual_counts:
							if role != "basic": check(int(reduced_counts.get(role, 0)) == int(actual_counts[role]), "Nest clearing must retain every saved specialist, including lobbers")
						check(reduced.threat == entry.threat and reduced.title == entry.title and reduced.advice == entry.advice and reduced.boss_count == entry.boss_count, "Nest clearing must not reroll threats, guidance or boss entries")

func verify_wave(entry: Dictionary) -> void:
	check(game.enemies.size() == int(entry.count), "Preview population must equal the real production wave")
	var expected: Dictionary = {}
	var actual: Dictionary = {}
	for role in entry.roles:
		var kind := "stalker" if String(role) == "basic" else String(role)
		expected[kind] = int(expected.get(kind, 0)) + 1
	if bool(entry.get("boss_entry", false)): expected["breaker"] = int(expected.get("breaker", 0)) + 1
	for enemy: BattleUnit in game.enemies:
		var kind := String(enemy.get_meta("threat", ""))
		actual[kind] = int(actual.get(kind, 0)) + 1
	check(actual == expected, "Saved preview composition must equal actual spawned identities")

func defeat_wave(entry: Dictionary) -> void:
	var before := int(game.scrap)
	var reward_id: int = (game.day_number - 1) * 5 + int(entry.index)
	var standard: bool = game.run_mode != "teaching"
	if standard:
		var ledger: Dictionary = game.wave_rewards.snapshot(reward_id)
		check(not ledger.is_empty() and int(ledger.budget) == 24 and int(ledger.count) == int(entry.count) and bool(ledger.sealed), "Each actual wave must register its count against the original 24-part budget")
	var victims: Array = game.enemies.duplicate()
	for enemy: BattleUnit in victims:
		var lobber := String(enemy.get_meta("threat", "")) == "lobber"
		var burstling := String(enemy.get_meta("threat", "")) == "burstling"
		if lobber and standard: check(int(enemy.get_meta("wave_reward_id", -1)) == reward_id, "A real born lobber must belong to its actual wave ledger")
		if burstling and standard: check(int(enemy.get_meta("wave_reward_id", -1)) == reward_id, "A real born burstling must belong to the unchanged original wave ledger")
		enemy.hurt(100000.0, game.hero)
		check(not enemy.alive, "Wave accounting must receive a real production death")
		if lobber: lobber_deaths += 1
		if burstling: burstling_deaths += 1
		if lobber or burstling:
			var paid := int(game.scrap)
			var kills := int(game.kills)
			enemy.hurt(100000.0, game.hero)
			check(game.wave_rewards.defeat(enemy) == 0 and game.scrap == paid and game.kills == kills, "Duplicate lobber or burstling deaths must not pay again or increase kill totals")
	if standard:
		var complete: Dictionary = game.wave_rewards.snapshot(reward_id)
		check(bool(complete.cleared) and int(complete.paid) == 24 and int(complete.kills) == int(entry.count) and game.scrap == before + 24, "Lobber-containing deaths must preserve exactly 24 parts per standard wave")
	else: check(game.scrap == before + int(entry.count) * 8, "Teaching must retain its original per-death reward for every identity")
	await process_frame
	game.enemies.clear()

func verify_actual_later_nights() -> void:
	for mode in ["teaching", "standard", "siege", "echo"]:
		for night in range(2, 4 if mode == "teaching" else 5):
			clear_enemies(); await process_frame
			# Isolate modes/nights through real plan/start/spawn APIs without
			# supplying fake creatures, ledger entries or resource income.
			game.run_mode = mode; game.day_number = night; game.night_plan.clear()
			for nest in game.world.nests: nest.cleansed = false
			game.start_night()
			var saved: Array[Dictionary] = game.night_plan.duplicate(true)
			var before := int(game.scrap)
			for wave in 5:
				if wave > 0: game.spawn_night_wave()
				verify_wave(saved[wave])
				await defeat_wave(saved[wave])
			check(game.wave_preview().is_empty(), "A fully spawned night must have no invented sixth wave")
			if mode != "teaching": check(game.scrap == before + 120, "Lobbers must not expand the standard five-wave 120-part budget")
			for nest in game.world.nests: nest.cleansed = true
			game.prepare_next_night_plan(false)
			for wave in 5:
				var original_counts := counts(saved[wave].roles)
				var reduced_counts := counts(game.night_plan[wave].roles)
				for role in original_counts:
					if role != "basic": check(reduced_counts.get(role, 0) == original_counts[role], "Production nest-plan refresh must keep all non-basic roles")
			game.wave_index = 0; game.spawn_night_wave(); verify_wave(game.night_plan[0])
	check(lobber_deaths > 0, "All four modes must create and actually defeat planned lobbers")
	check(burstling_deaths == 15, "Explicit standard/siege/echo fixtures must each create and really defeat the exact one/two/two planned burstlings across nights two through four")

func verify_same_challenge_retry() -> void:
	clear_enemies(); await process_frame
	var mode := String(game.run_mode)
	var run_seed := int(game.run.seed_value)
	var plans: Array = []
	for night in range(1, game.max_nights() + 1): plans.append(game.encounters.make_plan(mode, night, run_seed, 0))
	var previous: WeakRef = weakref(game)
	game.end_defeat("波次回归 · 同一守望")
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER; event.physical_keycode = KEY_ENTER; event.pressed = true
	root.push_input(event, true)
	event.pressed = false; root.push_input(event, true)
	for frame in 240:
		await create_timer(0.02).timeout
		if is_instance_valid(current_scene) and current_scene != previous.get_ref() and current_scene.scene_file_path == SCENE:
			game = current_scene
			game.set_process(false); game.world.set_process(false)
			break
	check(is_instance_valid(game) and previous.get_ref() != game and not is_instance_valid(previous.get_ref()), "Real Enter retry must replace and free the previous production scene")
	if not is_instance_valid(game) or previous.get_ref() == game: return
	check(game.run.seed_value == run_seed and game.run_mode == mode and game.phase == "draft", "Real same-challenge retry must retain seed and mode")
	for night in range(1, game.max_nights() + 1): check(game.encounters.make_plan(mode, night, game.run.seed_value, 0) == plans[night - 1], "Scene retry must reproduce each night including lobber counts and ordering")
	check(game.choose_card(0), "Retried challenge must choose its real opening core")
	clear_enemies(); await process_frame
	game.day_number = 2; game.night_plan.clear(); game.start_night()
	check(game.night_plan == plans[1], "Retried second night must consume the original full lobber plan")
	for wave in 3:
		if wave > 0: game.spawn_night_wave()
		verify_wave(game.night_plan[wave])
		clear_enemies(); await process_frame

func run() -> void:
	verify_plan_rules()
	check(Session.queue_request(self, SEED, "siege"), "Production session must accept the fixed standard challenge")
	game = load(SCENE).instantiate(); root.add_child(game); current_scene = game
	for frame in 4: await process_frame
	game.set_process(false); game.world.set_process(false)
	check(game.choose_card(0) and game.night_plan.size() == 5 and game.spawn_timer == 20, "Opening core must enter the unchanged first night")
	check(game.wave_preview().threat == "runner", "First-night next-wave threat must remain the original runner")
	var preview: Dictionary = game.wave_preview(); preview.roles.clear()
	check(not game.night_plan[1].roles.is_empty(), "Preview mutation must not change the saved source plan")
	game.phase = "paused"; game.simulate(21)
	check(game.phase_time == 105, "Paused simulation must not consume wave time")
	game.phase = "night"
	var before := int(game.scrap)
	var first_deaths := 0
	for wave in 5:
		if wave > 0:
			game.phase_time = 105 - float(game.night_plan[wave].time) + .1
			game.simulate(.11)
		check(game.wave_index == wave + 1, "Simulation must spawn each scheduled wave exactly once")
		verify_wave(game.night_plan[wave])
		first_deaths += game.enemies.size()
		await defeat_wave(game.night_plan[wave])
	check(first_deaths == 71 and game.kills == 71 and game.scrap == before + 120, "Actual first night must keep 71 deaths and 120 standard income")
	await verify_actual_later_nights()
	await verify_same_challenge_retry()
	await game.prepare_shutdown(); game.queue_free()
	for frame in 4: await process_frame
	print("NIGHTFALL_PLANNED_WAVES_", "OK" if failures.is_empty() else "FAILED", " checks=", checks, " lobber_deaths=", lobber_deaths, " burstling_deaths=", burstling_deaths)
	quit(0 if failures.is_empty() else 1)
