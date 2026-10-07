extends SceneTree

const Encounters = preload("res://scripts/nightfall_encounters.gd")
var encounters: RefCounted = Encounters.new()

# Frozen from actual production plans at main e83a414 before summoner changes.
# Restoring summoner, warder, shellguard and burstling to basic must reproduce the same
# frozen original order/counts; adding a role must not replace the baselines.
const BASELINE_ROLE_DIGESTS := {
	"echo:1": "b0bfdfd82c64fc796454c5e2c57315e640777ad9fd8afbcdc3bbe2feb4ee6486",
	"echo:2": "4d28a37bc7398a86024e17a51dc0364022f2b505729efd4edc397395bb8a85f3",
	"echo:3": "0f1d7e01bffacd63df794074bcd3ce08457c4402df3cc90aa14ad4c41ae8b3f3",
	"echo:4": "1c4a67f469fe35cf43db2e39e341df6cd5aa7436c00c51b30e6caf6549a03798",
	"siege:1": "b0bfdfd82c64fc796454c5e2c57315e640777ad9fd8afbcdc3bbe2feb4ee6486",
	"siege:2": "ce0dfb731dd9b236447fdd61d836680e029cfa8262e28a2660d7117f2c39947c",
	"siege:3": "fdacfc6fb1a879511713035b16d127f9e9a255479e048680f8f970f9404b69f4",
	"siege:4": "a2bb4ea4ada0ca4008c19d19a4bf861d73a63933657ee072442e83798fefb8c7",
	"standard:1": "b0bfdfd82c64fc796454c5e2c57315e640777ad9fd8afbcdc3bbe2feb4ee6486",
	"standard:2": "1f91a17435d14ab29bfe55d9faaea49488e8292bc1cf4b55b5ca4c6b5f8f7352",
	"standard:3": "d07fd2d2aeb95d99c40cc68cec396de4edc7a23597287efe781b940e56af2a32",
	"standard:4": "1c4a67f469fe35cf43db2e39e341df6cd5aa7436c00c51b30e6caf6549a03798",
	"teaching:1": "b0bfdfd82c64fc796454c5e2c57315e640777ad9fd8afbcdc3bbe2feb4ee6486",
	"teaching:2": "1f91a17435d14ab29bfe55d9faaea49488e8292bc1cf4b55b5ca4c6b5f8f7352",
	"teaching:3": "578b02e0b0acb654c8a4e3de111713f2da4be072dc307e813c1c73e50e07e569",
	"teaching:4": "152c28af869affed4d8f8d3065561fd2850b38dad282a1c9473a6c5e8ff56e9f"
}
const EARLY_METADATA_DIGESTS := {
	"echo:1": "b21b759310ad379e59d4bdd63f755f4448f8b396b9d5c6b04effdb8d4fef2b7b",
	"echo:2": "34cc816010c4e8ed48745b9631a89e2ce88676bc3567a3a05eeb643ed9cea25e",
	"siege:1": "80b5419d8ceb9111d2c4851c164a9236cd6ce1913f5aa321aa67ef29c6c84603",
	"siege:2": "7ccb90daba6565c0ad72580358fe7393aa5593514434c660a6befc05029f8ace",
	"standard:1": "80b5419d8ceb9111d2c4851c164a9236cd6ce1913f5aa321aa67ef29c6c84603",
	"standard:2": "70cc1d07344b4c6c0b70efbda5ea31beb448e1351e0d49dd110070cd0db09777",
	"teaching:1": "80b5419d8ceb9111d2c4851c164a9236cd6ce1913f5aa321aa67ef29c6c84603",
	"teaching:2": "70cc1d07344b4c6c0b70efbda5ea31beb448e1351e0d49dd110070cd0db09777"
}
const MODES := ["teaching", "standard", "siege", "echo"]
const LOBBERS := {1: [0,0,0,0,0], 2: [0,0,1,0,1], 3: [0,1,2,1,2], 4: [0,2,3,2,3]}
const WARDERS := {1: [0,0,0,0,0], 2: [0,0,0,1,0], 3: [0,1,0,1,0], 4: [0,1,0,1,0]}
const SHELLGUARDS := {1: [0,0,0,0,0], 2: [0,0,1,0,0], 3: [1,0,0,0,1], 4: [1,0,0,0,1]}
const BURSTLINGS := {1: [0,0,0,0,0], 2: [0,1,0,0,0], 3: [0,1,0,1,0], 4: [0,1,0,1,0]}

# Synthetic no-follower composition checks only the defensive replacement
# branch. It is not evidence that natural production waves use this roster.
class NoFollowerEncounters:
	extends "res://scripts/nightfall_encounters.gd"
	func _later_night(_index: int, _night: int, _theme: String, _random: RandomNumberGenerator) -> Dictionary:
		return _composition("专职守卫", "runner", "原专职提示", _repeat("runner", 24))

var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String = "Saved encounter invariant failed") -> void:
	checks += 1
	if condition: return
	failures.append(message)
	if failures.size() <= 30: push_error(message)

func _initialize() -> void:
	frozen_baselines()
	finite_source_matrix()
	shellguard_previews_and_nests()
	shellguard_without_followers()
	var first: Array[Dictionary] = encounters.make_plan("teaching", 1, 45, 0)
	check(first == encounters.make_plan("teaching", 1, 45, 0))
	check(first.size() == 5)
	check(first[0].roles.size() == 11 and first[4].roles.size() == 18)
	for index in range(first.size()):
		check(first[index].time == [0.0, 20.0, 40.0, 65.0, 85.0][index])
		check(not "light_eater" in first[index].roles)
		check(not first[index].boss_entry)
		if index < 3:
			check(not "sapper" in first[index].roles and not "breaker" in first[index].roles)
	check(first[0].roles.count("basic") == 11)
	check(first[1].roles.count("runner") >= 3)
	check(first[2].roles.count("runner") == 2)
	check(first[3].roles.count("sapper") == 2)
	check(first[4].roles.count("breaker") == 2)
	var night_two: Array[Dictionary] = encounters.make_plan("standard", 2, 29045, 0)
	check(night_two == encounters.make_plan("standard", 2, 29045, 0))
	var distinct: bool = false
	for seed in range(29046, 29056):
		if encounters.make_plan("standard", 2, seed, 0) != night_two:
			distinct = true
	check(distinct)
	check(night_two[0].roles.count("light_eater") == 2)
	for mode in ["teaching", "standard", "siege", "echo"]:
		for night in range(1, 5):
			var original: Array[Dictionary] = encounters.make_plan(mode, night, 17, 0)
			var reduced: Array[Dictionary] = encounters.make_plan(mode, night, 17, 3)
			check(reduced == encounters.make_plan(mode, night, 17, 100))
			check(original == encounters.make_plan(mode, night, 17, -10))
			for index in range(original.size()):
				var wave: Dictionary = original[index]
				var less: Dictionary = reduced[index]
				check(wave.count <= 25 and wave.count >= 4)
				check(wave.count == wave.roles.size() + int(wave.get("boss_count",0)) and less.count == less.roles.size() + int(less.get("boss_count",0)))
				check(less.count >= 4 and wave.count - less.count == 6)
				check(wave.title == less.title and wave.advice == less.advice)
				check(wave.threat == less.threat and wave.time == less.time)
				check(wave.mode == less.mode and wave.theme == less.theme)
				for role in wave.roles:
					check(role in Encounters.KNOWN_ROLES)
				for role in Encounters.KNOWN_ROLES:
					if role != "basic":
						check(wave.roles.count(role) == less.roles.count(role))
			var final_night: int = 3 if mode == "teaching" else 4
			check(original[4].boss_entry == (night == final_night))
	var siege: Array[Dictionary] = encounters.make_plan("siege", 3, 17, 0)
	var echo: Array[Dictionary] = encounters.make_plan("echo", 3, 17, 0)
	check(siege[1].threat == "breaker" and echo[1].threat == "runner")
	check(siege[2].threat == "summoner" and echo[2].threat == "summoner", "Third-night wave three must announce the actual finite source in both themes")
	var preview: Dictionary = encounters.next_preview(first, 1, 12.5)
	check(preview.remaining == 7.5 and preview.roles == first[1].roles)
	preview.roles.clear()
	preview.title = "测试修改"
	check(first[1].roles.size() == 12 and first[1].title == "疾行突破")
	check(encounters.next_preview(first, 1, 25.0).remaining == 0.0)
	check(encounters.next_preview(first, 0, -5.0).remaining == 0.0)
	check(encounters.next_preview(first, -1, 0.0).is_empty())
	check(encounters.next_preview(first, 5, 105.0).is_empty())
	check(encounters.make_plan("unknown", 0, 17, 0) == encounters.make_plan("teaching", 1, 17, 0))
	check(encounters.make_plan("standard", 99, 17, 0) == encounters.make_plan("standard", 4, 17, 0))
	print("NIGHTFALL_ENCOUNTERS_FIXTURE_%s checks=%d failures=%d exact_baseline_order finite_source_caps finite_shield_caps shellguard_schedule boss_guidance preview_isolation initial_population seed_variants nest_reductions" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func frozen_baselines() -> void:
	for mode: String in MODES:
		for night in range(1, 5):
			var key := "%s:%d" % [mode, night]
			var plan: Array[Dictionary] = encounters.make_plan(mode, night, 17, 0)
			var role_rows: Array = []
			var early_rows: Array = []
			for wave: Dictionary in plan:
				var restored: Array = wave.roles.duplicate()
				for index in restored.size():
					if restored[index] in ["summoner", "warder", "shellguard", "burstling"]: restored[index] = "basic"
				role_rows.append([restored, wave.count, wave.role_count, wave.boss_count])
				var restored_title := String(wave.title).trim_suffix(" · 爆裂逼近").trim_suffix(" · 甲壳护卫").trim_suffix(" · 织壳护卫")
				var restored_advice := String(wave.advice).trim_suffix(" " + Encounters.BURSTLING_ADVICE).trim_suffix(" " + Encounters.SHELLGUARD_ADVICE).trim_suffix(" " + Encounters.WARDER_ADVICE)
				early_rows.append([restored_title, wave.threat, restored_advice, restored, wave.count, wave.role_count, wave.boss_count, wave.theme])
			check(JSON.stringify(role_rows).sha256_text() == BASELINE_ROLE_DIGESTS[key], key + ": restoring the replaced basic must reproduce exact original role order and initial population")
			if night <= 2:
				check(JSON.stringify(early_rows).sha256_text() == EARLY_METADATA_DIGESTS[key], key + ": removing only shield-source, shellguard and burstling additions must preserve exact first/second-night labels, guidance, roles, counts and random theme")

func finite_source_matrix() -> void:
	for mode: String in MODES:
		for night in range(1, 5):
			for seed_value: int in [-55, 17, 45, 29045, 2147483647]:
				var plan: Array[Dictionary] = encounters.make_plan(mode, night, seed_value, 0)
				var reduced: Array[Dictionary] = encounters.make_plan(mode, night, seed_value, 3)
				var context := "%s night%d seed%d" % [mode, night, seed_value]
				check(plan == encounters.make_plan(mode, night, seed_value, 0), context + ": saved roles and finite ceilings must reproduce")
				var sources := 0
				var shield_sources := 0
				var shellguards := 0
				var burstlings := 0
				for index in plan.size():
					var wave: Dictionary = plan[index]
					var less: Dictionary = reduced[index]
					var count: int = wave.roles.count("summoner")
					var warder_count: int = wave.roles.count("warder")
					var shellguard_count: int = wave.roles.count("shellguard")
					var burstling_count: int = wave.roles.count("burstling")
					var burstling_expected: int = int(BURSTLINGS[night][index]) if mode != "teaching" else 0
					var before_burst_title := String(wave.title).trim_suffix(" · 爆裂逼近")
					var before_burst_advice := String(wave.advice).trim_suffix(" " + Encounters.BURSTLING_ADVICE)
					sources += count
					shield_sources += warder_count
					shellguards += shellguard_count
					burstlings += burstling_count
					check(count == (1 if night >= 3 and index == 2 else 0), context + ": only later-night wave three may contain one source")
					check(int(wave.reinforcement_cap) == count * 2 and int(less.reinforcement_cap) == count * 2, context + ": source lifetime cap must stay separate from initial population")
					check(int(wave.count) == wave.roles.size() + int(wave.boss_count) and int(wave.role_count) == wave.roles.size(), context + ": unborn reinforcements must not inflate initial counts")
					check(wave.roles.count("lobber") == int(LOBBERS[night][index]), context + ": all original lobber counts must stay intact")
					check(warder_count == int(WARDERS[night][index]), context + ": finite shield sources replace one basic only in the declared later-night waves")
					check(int(wave.warder_count) == warder_count and int(less.warder_count) == warder_count,
						context + ": stored shield-source counts match actual saved roles before and after nest clearing")
					check(int(wave.shield_cast_cap) == warder_count * 3 and int(less.shield_cast_cap) == warder_count * 3,
						context + ": potential three-cast shield quota is separate from population and summoner births")
					check(shellguard_count == int(SHELLGUARDS[night][index]), context + ": armor replaces one basic only in the declared later-night waves")
					check(int(wave.shellguard_count) == shellguard_count and int(less.shellguard_count) == shellguard_count,
						context + ": stored armored counts match actual saved roles before and after nest clearing")
					check(shellguard_count == 0 or (count == 0 and warder_count == 0), context + ": armor does not replace either finite support source")
					check(burstling_count == burstling_expected and int(wave.burstling_count) == burstling_expected
						and int(less.burstling_count) == burstling_expected,
						context + ": exactly one ordinary follower becomes a burstling only in the declared four-night-mode waves")
					check(int(wave.count) - int(less.count) == 6 and wave.title == less.title and wave.advice == less.advice and wave.threat == less.threat, context + ": nest clearing must only reduce ordinary followers")
					for role: String in Encounters.KNOWN_ROLES:
						if role != "basic": check(wave.roles.count(role) == less.roles.count(role), context + ": nest clearing must retain every specialist and source")
					if count > 0:
						check(wave.threat == "summoner" and wave.title == "召潮增援", context + ": primary warning must identify the actual source")
						for text: String in ["2.4秒", "可打断", "冷却10秒", "最多2援军", "南门外", "集火召潮者"]:
							check(String(wave.advice).contains(text), context + ": counterplay must disclose " + text)
					elif night == 2 and index == 2:
						check(wave.threat == "lobber" and String(wave.advice).contains("2米") and String(wave.advice).contains("1.15秒"), context + ": second-night lobber guidance must stay unchanged")
					if warder_count > 0:
						var original_threat := "breaker" if index == 1 and String(wave.theme) == "siege" else ("runner" if index == 1 else "sapper")
						check(wave.threat == original_threat and before_burst_title.ends_with(" · 织壳护卫"), context + ": shield warning supplements the original wave identity rather than replacing its primary threat")
						check(before_burst_advice.ends_with(" " + Encounters.WARDER_ADVICE)
							and before_burst_advice.length() > Encounters.WARDER_ADVICE.length() + 1,
							context + ": shield guidance retains the original advice before its appended disclosure")
						for text: String in ["1秒引导", "击杀", "牵制打断", "32护盾", "4秒", "间隔6秒", "每源最多3次"]:
							check(String(wave.advice).contains(text), context + ": finite shield counterplay discloses " + text)
					else:
						check(not String(wave.title).contains("织壳护卫") and not String(wave.advice).contains("织壳者"), context + ": waves without a shield source must not advertise one")
					if shellguard_count > 0:
						var original_threat := "lobber" if night == 2 else ("light_eater" if index == 0 else "breaker")
						check(wave.threat == original_threat and String(wave.title).ends_with(" · 甲壳护卫"), context + ": armor supplements the original primary threat and title")
						check(String(wave.advice).ends_with(" " + Encounters.SHELLGUARD_ADVICE)
							and String(wave.advice).length() > Encounters.SHELLGUARD_ADVICE.length() + 1,
							context + ": armor counterplay follows the preserved original guidance")
						for text: String in ["60护甲", "二级塔J", "破甲", "×1.65", "忽略一半护甲", "C集火", "盾卫挡线"]:
							check(String(wave.advice).contains(text), context + ": armor counterplay discloses " + text)
					else:
						check(not String(wave.title).contains("甲壳护卫") and not String(wave.advice).contains("甲壳卫"), context + ": waves without armor must not advertise it")
					if burstling_count > 0:
						var original_threat := "breaker" if index == 1 and String(wave.theme) == "siege" else ("runner" if index == 1 else "sapper")
						check(wave.threat == original_threat and String(wave.title) == before_burst_title + " · 爆裂逼近"
							and String(wave.advice) == before_burst_advice + " " + Encounters.BURSTLING_ADVICE
							and before_burst_advice.length() > 0,
							context + ": burst warning appends exact counterplay without replacing the primary identity or original guidance")
					else:
						check(not String(wave.title).contains("爆裂逼近") and not String(wave.advice).contains("爆裂体"), context + ": waves without burstlings must not advertise their danger")
					if bool(wave.boss_entry):
						check(shellguard_count == 1 and int(wave.boss_count) == 1 and wave.boss_role == "breaker", context + ": the final armor follower leaves the unique original boss intact")
						check(String(wave.title).begins_with("末夜首领 · 灯噬巨兽 · "), context + ": boss keeps its primary public identity")
						check(String(wave.advice).trim_suffix(" " + Encounters.SHELLGUARD_ADVICE) == "打断首领蓄力，移出2米投蚀落点后远程集火。", context + ": final-wave guidance preserves the exact original boss and thrower advice before armor counterplay")
				check(sources == (1 if night >= 3 else 0), context + ": one whole night may have at most one finite source")
				check(shield_sources == (0 if night == 1 else (1 if night == 2 else 2)), context + ": whole-night shield-source count stays zero/one/two across all seeds and modes")
				check(shellguards == (0 if night == 1 else (1 if night == 2 else 2)), context + ": whole-night armored count stays zero/one/two across all seeds and modes")
				check(burstlings == ((0 if night == 1 else (1 if night == 2 else 2)) if mode != "teaching" else 0), context + ": only four-night modes gain the declared zero/one/two burstling replacements")
				check(not plan[4].roles.has("summoner") and int(plan[4].reinforcement_cap) == 0, context + ": original last-wave boss must not gain a summoner ceiling")
				check(not plan[4].roles.has("warder") and int(plan[4].shield_cast_cap) == 0, context + ": original last-wave boss and specialists are not replaced by a shield source")
	var stored: Array[Dictionary] = encounters.make_plan("siege", 3, 17, 0)
	var preview: Dictionary = encounters.next_preview(stored, 2, 12.5)
	check(preview.remaining == 27.5 and preview.roles.count("summoner") == 1 and preview.reinforcement_cap == 2, "Preview must separately expose one actual initial source and two potential future births")
	preview.roles.clear(); preview.reinforcement_cap = 99; preview.advice = "测试修改"
	check(stored[2].roles.count("summoner") == 1 and stored[2].reinforcement_cap == 2 and stored[2].advice == Encounters.SUMMONER_ADVICE, "Preview edits must not mutate the saved source, ceiling or guidance")
	var shield_preview: Dictionary = encounters.next_preview(stored, 1, 12.5)
	check(shield_preview.remaining == 7.5 and shield_preview.roles.count("warder") == 1
		and shield_preview.warder_count == 1 and shield_preview.shield_cast_cap == 3
		and shield_preview.reinforcement_cap == 0 and shield_preview.threat == "breaker",
		"Preview separately exposes one initial shield source and its three finite casts while preserving the actual primary threat")
	shield_preview.roles.clear(); shield_preview.warder_count = 99; shield_preview.shield_cast_cap = 99; shield_preview.advice = "测试修改"
	check(stored[1].roles.count("warder") == 1 and stored[1].warder_count == 1 and stored[1].shield_cast_cap == 3
		and stored[1].reinforcement_cap == 0
		and String(stored[1].advice).trim_suffix(" " + Encounters.BURSTLING_ADVICE).ends_with(Encounters.WARDER_ADVICE),
		"Preview edits must not mutate saved shield source, finite cast ceiling, original births or appended guidance")

func shellguard_previews_and_nests() -> void:
	for mode: String in MODES:
		for night in range(1, 5):
			for seed_value: int in [-55, 17, 45, 29045, 2147483647]:
				var stored: Array[Dictionary] = encounters.make_plan(mode, night, seed_value, 0)
				for nests in [1, 2, 3]:
					var reduced: Array[Dictionary] = encounters.make_plan(mode, night, seed_value, nests)
					for index in stored.size():
						var original: Dictionary = stored[index]
						var less: Dictionary = reduced[index]
						var context := "%s night%d seed%d nests%d wave%d" % [mode, night, seed_value, nests, index + 1]
						check(int(original.count) - int(less.count) == nests * 2
							and original.roles.count("basic") - less.roles.count("basic") == nests * 2,
							context + ": all three individual nest reductions remove only ordinary followers")
						check(original.shellguard_count == less.shellguard_count
							and less.roles.count("shellguard") == int(SHELLGUARDS[night][index])
							and original.boss_entry == less.boss_entry and original.boss_count == less.boss_count
							and original.reinforcement_cap == less.reinforcement_cap and original.shield_cast_cap == less.shield_cast_cap,
							context + ": nests cannot remove armor or alter bosses and finite support caps")
						check(original.title == less.title and original.threat == less.threat and original.advice == less.advice,
							context + ": each nest leaves both primary and supplemental counterplay unchanged")
				var saved_before: Array[Dictionary] = stored.duplicate(true)
				for index in stored.size():
					var preview: Dictionary = encounters.next_preview(stored, index, 12.5)
					check(int(preview.shellguard_count) == int(SHELLGUARDS[night][index])
						and preview.roles.count("shellguard") == int(preview.shellguard_count),
						"Actual armor preview matches the saved count at every night, seed and wave")
					preview.roles.clear(); preview.shellguard_count = 99; preview.advice = "测试修改"; preview.title = "测试修改"
					check(stored == saved_before, "Armor preview edits cannot mutate saved role order, labels, advice, counts or support caps")

func shellguard_without_followers() -> void:
	var no_followers := NoFollowerEncounters.new()
	for mode: String in MODES:
		for night in range(2, 5):
			for nests in [0, 3]:
				var plan: Array[Dictionary] = no_followers.make_plan(mode, night, 17, nests)
				for entry: Dictionary in plan:
					check(not entry.roles.has("basic") and int(entry.role_count) == 24, "Synthetic all-specialist fixture has no padded ordinary follower to replace")
					check(int(entry.shellguard_count) == 0 and not entry.roles.has("shellguard"), "Without a real basic slot armor cannot displace an original specialist")
					check(not String(entry.title).contains("甲壳护卫") and not String(entry.advice).contains("甲壳卫"), "Skipped armor replacement cannot add false public guidance")
					check(int(entry.burstling_count) == 0 and not entry.roles.has("burstling"), "Without a real basic slot a burstling cannot displace an original specialist")
					check(not String(entry.title).contains("爆裂逼近") and not String(entry.advice).contains("爆裂体"), "Skipped burstling replacement cannot add false public guidance")
