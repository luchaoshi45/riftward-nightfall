extends SceneTree

const Encounters = preload("res://scripts/nightfall_encounters.gd")
var encounters: RefCounted = Encounters.new()

# Frozen from actual production plans at main e83a414 before summoner changes.
# Restoring summoner to basic must reproduce the exact original order/counts.
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
	print("NIGHTFALL_ENCOUNTERS_FIXTURE_%s checks=%d failures=%d exact_baseline_order finite_source_caps initial_population seed_variants nest_reductions" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
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
					if restored[index] == "summoner": restored[index] = "basic"
				role_rows.append([restored, wave.count, wave.role_count, wave.boss_count])
				early_rows.append([wave.title, wave.threat, wave.advice, wave.roles, wave.count, wave.role_count, wave.boss_count, wave.theme])
			check(JSON.stringify(role_rows).sha256_text() == BASELINE_ROLE_DIGESTS[key], key + ": restoring the replaced basic must reproduce exact original role order and initial population")
			if night <= 2:
				check(JSON.stringify(early_rows).sha256_text() == EARLY_METADATA_DIGESTS[key], key + ": first/second-night labels, guidance, roles, counts and random theme must stay unchanged")

func finite_source_matrix() -> void:
	for mode: String in MODES:
		for night in range(1, 5):
			for seed_value: int in [-55, 17, 45, 29045, 2147483647]:
				var plan: Array[Dictionary] = encounters.make_plan(mode, night, seed_value, 0)
				var reduced: Array[Dictionary] = encounters.make_plan(mode, night, seed_value, 3)
				var context := "%s night%d seed%d" % [mode, night, seed_value]
				check(plan == encounters.make_plan(mode, night, seed_value, 0), context + ": saved roles and finite ceilings must reproduce")
				var sources := 0
				for index in plan.size():
					var wave: Dictionary = plan[index]
					var less: Dictionary = reduced[index]
					var count: int = wave.roles.count("summoner")
					sources += count
					check(count == (1 if night >= 3 and index == 2 else 0), context + ": only later-night wave three may contain one source")
					check(int(wave.reinforcement_cap) == count * 2 and int(less.reinforcement_cap) == count * 2, context + ": source lifetime cap must stay separate from initial population")
					check(int(wave.count) == wave.roles.size() + int(wave.boss_count) and int(wave.role_count) == wave.roles.size(), context + ": unborn reinforcements must not inflate initial counts")
					check(wave.roles.count("lobber") == int(LOBBERS[night][index]), context + ": all original lobber counts must stay intact")
					check(int(wave.count) - int(less.count) == 6 and wave.title == less.title and wave.advice == less.advice and wave.threat == less.threat, context + ": nest clearing must only reduce ordinary followers")
					for role: String in Encounters.KNOWN_ROLES:
						if role != "basic": check(wave.roles.count(role) == less.roles.count(role), context + ": nest clearing must retain every specialist and source")
					if count > 0:
						check(wave.threat == "summoner" and wave.title == "召潮增援", context + ": primary warning must identify the actual source")
						for text: String in ["2.4秒", "可打断", "冷却10秒", "最多2援军", "南门外", "集火召潮者"]:
							check(String(wave.advice).contains(text), context + ": counterplay must disclose " + text)
					elif night == 2 and index == 2:
						check(wave.threat == "lobber" and String(wave.advice).contains("2米") and String(wave.advice).contains("1.15秒"), context + ": second-night lobber guidance must stay unchanged")
				check(sources == (1 if night >= 3 else 0), context + ": one whole night may have at most one finite source")
				check(not plan[4].roles.has("summoner") and int(plan[4].reinforcement_cap) == 0, context + ": original last-wave boss must not gain a summoner ceiling")
	var stored: Array[Dictionary] = encounters.make_plan("siege", 3, 17, 0)
	var preview: Dictionary = encounters.next_preview(stored, 2, 12.5)
	check(preview.remaining == 27.5 and preview.roles.count("summoner") == 1 and preview.reinforcement_cap == 2, "Preview must separately expose one actual initial source and two potential future births")
	preview.roles.clear(); preview.reinforcement_cap = 99; preview.advice = "测试修改"
	check(stored[2].roles.count("summoner") == 1 and stored[2].reinforcement_cap == 2 and stored[2].advice == Encounters.SUMMONER_ADVICE, "Preview edits must not mutate the saved source, ceiling or guidance")
