extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func measure_travel(hero: BattleUnit, velocity: float) -> Dictionary:
	hero.speed = 8.4
	hero.moving = true
	hero.set_locomotion_velocity(Vector3(0, 0, velocity))
	hero.face(hero.position + hero.locomotion_velocity, 1.0)
	for i in 18:
		hero.position.z += velocity / 60.0
		hero.tick(1.0 / 60.0)
	var lowest_boot := INF
	var clearance := 0.0
	var max_knee := 0.0
	var max_knee_delta := 0.0
	var root_delta := 0.0
	var last_knee := hero.knees[0].rotation.x
	var last_root := hero.visual.position.y
	var cycles := 0.0
	var support_drift := 0.0
	var support_samples := 0
	var last_ankle := hero.feet[0].global_position
	var last_phase := fposmod(hero.gait_phase / TAU, 1.0)
	var blade := hero.visual.find_child("Diamond_forged_sword", true, false) as MeshInstance3D
	if not blade: blade = hero.visual.find_child("Diamond forged sword", true, false) as MeshInstance3D
	assert(blade != null and hero.hero_sword_wrist != null)
	var blade_lowest := INF
	for i in 180:
		var before := hero.gait_phase
		hero.position.z += velocity / 60.0
		hero.tick(1.0 / 60.0)
		cycles += fposmod(hero.gait_phase - before, TAU) / TAU
		var expected_phase := fposmod(before + velocity / 60.0 / hero.hero_stride_distance * TAU, TAU)
		assert(absf(wrapf(hero.gait_phase - expected_phase, -PI, PI)) < .0001, "Run phase must advance by real metres travelled")
		lowest_boot = minf(lowest_boot, minf(hero.hero_boot_lowest(0), hero.hero_boot_lowest(1)))
		clearance = maxf(clearance, maxf(hero.hero_boot_lowest(0), hero.hero_boot_lowest(1)))
		max_knee = maxf(max_knee, hero.knees[0].rotation.x)
		max_knee_delta = maxf(max_knee_delta, absf(hero.knees[0].rotation.x - last_knee))
		root_delta = maxf(root_delta, absf(hero.visual.position.y - last_root))
		last_knee = hero.knees[0].rotation.x
		last_root = hero.visual.position.y
		var phase := fposmod(hero.gait_phase / TAU, 1.0)
		var ankle := hero.feet[0].global_position
		if phase > .02 and phase < hero.hero_contact_fraction - .015 and last_phase > .02 and last_phase < phase:
			support_drift += Vector2(ankle.x - last_ankle.x, ankle.z - last_ankle.z).length()
			support_samples += 1
		last_ankle = ankle
		last_phase = phase
		var blade_box := blade.get_aabb()
		for x in [blade_box.position.x, blade_box.end.x]:
			for y in [blade_box.position.y, blade_box.end.y]:
				for z in [blade_box.position.z, blade_box.end.z]:
					blade_lowest = minf(blade_lowest, blade.to_global(Vector3(x, y, z)).y - hero.position.y)
	var drift := support_drift / maxi(support_samples, 1)
	print("HERO_TRAVEL_METRICS speed=", velocity, " footfalls/s=", cycles / 3.0 * 2.0, " knee=", max_knee, " sole=", lowest_boot, " swing=", clearance, " root_frame=", root_delta, " knee_frame=", max_knee_delta, " contact_drift=", drift, " sword_clearance=", blade_lowest)
	assert(lowest_boot >= .024, "No broad-toe mesh corner may penetrate the floor")
	assert(clearance > .10 and clearance < .60, "Recovery foot must lift visibly without kicking waist-high")
	assert(max_knee > .70 and max_knee < 1.65, "Recovery must fold the knee while the support leg stays extended")
	assert(max_knee_delta < .25 and root_delta < .055, "Consecutive real-travel frames must not pop")
	assert(support_samples > 15 and drift < .035, "Contact ankle must stay planted during full-speed travel")
	assert(blade_lowest > .15, "The running sword must stay above the floor instead of dragging behind the boot")
	return {"cadence": cycles / 3.0 * 2.0, "phase": hero.gait_phase}

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var hero := BattleUnit.new()
	stage.add_child(hero)
	hero.setup("hero", 0)
	assert(hero.legs.size() == 2 and hero.knees.size() == 2 and hero.feet.size() == 2)
	assert(hero.elbows.size() == 2 and hero.hero_pelvis != null)
	assert(hero.boot_sole_points[0].size() == 4 and hero.boot_sole_points[1].size() == 4)
	var run_fast := measure_travel(hero, 8.4)
	assert(run_fast.cadence > 3.8 and run_fast.cadence < 4.3, "Fast guardian must run with a readable brisk stride")
	assert(hero.elbows[1].rotation.x < -.40 and hero.hero_upper_body.rotation.x > .12, "Running must bend the sword elbow and lean the chest")
	var run_normal := measure_travel(hero, 6.0)
	var jog := measure_travel(hero, 3.0)
	assert(jog.cadence < run_normal.cadence and run_normal.cadence < run_fast.cadence, "Cadence must follow actual velocity, including escort jogs")
	# A larger speed stat with unchanged actual velocity cannot advance pose.
	hero.speed = 20.0
	hero.set_locomotion_velocity(Vector3(0, 0, 3.0))
	var phase_before := hero.gait_phase
	hero.tick(1.0 / 60.0)
	assert(absf(fposmod(hero.gait_phase - phase_before, TAU) - TAU / hero.hero_stride_duration / 60.0) < .0001)
	hero.moving = false
	hero.set_locomotion_velocity(Vector3.ZERO)
	var stopped_phase := hero.gait_phase
	for i in 6: hero.tick(1.0 / 60.0)
	assert(hero.gait_blend < .001, "The moving pose must settle within 100 ms of stopping")
	assert(is_equal_approx(hero.gait_phase, stopped_phase), "A stopped hero must not take another in-place step")
	assert(absf(hero.legs[0].rotation.x) < .001 and absf(hero.knees[0].rotation.x) < .001)
	assert(absf(hero.hero_pelvis.rotation.y) < .001 and absf(hero.hero_upper_body.rotation.y) < .001)
	hero.moving = true
	hero.set_locomotion_velocity(Vector3(0, 0, 8.4))
	for i in 5: hero.tick(1.0 / 60.0)
	assert(hero.gait_blend > .99, "The first running stride must appear within 85 ms")
	print("NIGHTFALL_HERO_GAIT_OK actual_speed_cadence=pass planted_contact=pass immediate_start_stop=pass articulated_run=pass")
	quit()
