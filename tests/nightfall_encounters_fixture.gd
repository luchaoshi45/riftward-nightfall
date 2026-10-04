extends SceneTree

const Encounters = preload("res://scripts/nightfall_encounters.gd")
var encounters: RefCounted = Encounters.new()

func _initialize() -> void:
	var first: Array[Dictionary] = encounters.make_plan("teaching", 1, 45, 0)
	assert(first == encounters.make_plan("teaching", 1, 45, 0))
	assert(first.size() == 5)
	assert(first[0].roles.size() == 11 and first[4].roles.size() == 18)
	for index in range(first.size()):
		assert(first[index].time == [0.0, 20.0, 40.0, 65.0, 85.0][index])
		assert(not "light_eater" in first[index].roles)
		assert(not first[index].boss_entry)
		if index < 3:
			assert(not "sapper" in first[index].roles and not "breaker" in first[index].roles)
	assert(first[0].roles.count("basic") == 11)
	assert(first[1].roles.count("runner") >= 3)
	assert(first[2].roles.count("runner") == 2)
	assert(first[3].roles.count("sapper") == 2)
	assert(first[4].roles.count("breaker") == 2)
	var night_two: Array[Dictionary] = encounters.make_plan("standard", 2, 29045, 0)
	assert(night_two == encounters.make_plan("standard", 2, 29045, 0))
	var distinct: bool = false
	for seed in range(29046, 29056):
		if encounters.make_plan("standard", 2, seed, 0) != night_two:
			distinct = true
	assert(distinct)
	assert(night_two[0].roles.count("light_eater") == 2)
	for mode in ["teaching", "standard", "siege", "echo"]:
		for night in range(1, 5):
			var original: Array[Dictionary] = encounters.make_plan(mode, night, 17, 0)
			var reduced: Array[Dictionary] = encounters.make_plan(mode, night, 17, 3)
			assert(reduced == encounters.make_plan(mode, night, 17, 100))
			assert(original == encounters.make_plan(mode, night, 17, -10))
			for index in range(original.size()):
				var wave: Dictionary = original[index]
				var less: Dictionary = reduced[index]
				assert(wave.count <= 25 and wave.count >= 4)
				assert(wave.count == wave.roles.size() + int(wave.get("boss_count",0)) and less.count == less.roles.size() + int(less.get("boss_count",0)))
				assert(less.count >= 4 and wave.count - less.count == 6)
				assert(wave.title == less.title and wave.advice == less.advice)
				assert(wave.threat == less.threat and wave.time == less.time)
				assert(wave.mode == less.mode and wave.theme == less.theme)
				for role in wave.roles:
					assert(role in Encounters.KNOWN_ROLES)
				for role in Encounters.KNOWN_ROLES:
					if role != "basic":
						assert(wave.roles.count(role) == less.roles.count(role))
			var final_night: int = 3 if mode == "teaching" else 4
			assert(original[4].boss_entry == (night == final_night))
	var siege: Array[Dictionary] = encounters.make_plan("siege", 3, 17, 0)
	var echo: Array[Dictionary] = encounters.make_plan("echo", 3, 17, 0)
	assert(siege[1].threat == "breaker" and echo[1].threat == "runner")
	assert(siege[2].threat == "sapper" and echo[2].threat == "light_eater")
	var preview: Dictionary = encounters.next_preview(first, 1, 12.5)
	assert(preview.remaining == 7.5 and preview.roles == first[1].roles)
	preview.roles.clear()
	preview.title = "测试修改"
	assert(first[1].roles.size() == 12 and first[1].title == "疾行突破")
	assert(encounters.next_preview(first, 1, 25.0).remaining == 0.0)
	assert(encounters.next_preview(first, 0, -5.0).remaining == 0.0)
	assert(encounters.next_preview(first, -1, 0.0).is_empty())
	assert(encounters.next_preview(first, 5, 105.0).is_empty())
	assert(encounters.make_plan("unknown", 0, 17, 0) == encounters.make_plan("teaching", 1, 17, 0))
	assert(encounters.make_plan("standard", 99, 17, 0) == encounters.make_plan("standard", 4, 17, 0))
	print("NIGHTFALL_ENCOUNTERS_FIXTURE_OK 5 waves, saved previews, seed variants, three nest reductions, 4-night bounds")
	quit()
