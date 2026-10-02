extends SceneTree
## Background-only rendered movement benchmark. No recording, no desktop interaction.
var game: Node3D
var samples: Array[Dictionary] = []
var lamps: Array[Light3D] = []
var stage := 0
var stage_started := 0.0
var previous_tick := 0
var travel_right := true
var sampling := false
var stable_lights := false
var section_seconds := 8.0
var gate_mode := false
var all_lamps: Array[Light3D] = []
var light_visibility: Dictionary = {}
var enemy_positions: Array[Vector3] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	assert(DisplayServer.get_name() != "headless", "This probe must use the real renderer")
	game=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await create_timer(1.0).timeout
	assert(game.choose_card(0))
	game.spawn_timer=999.0
	game.wave_index=game.WAVES_PER_NIGHT
	game.hero.hp=100000.0
	game.hero.max_hp=100000.0
	stable_lights="--stable-light-test" in OS.get_cmdline_user_args()
	gate_mode="--visibility-gate-test" in OS.get_cmdline_user_args()
	stable_lights=stable_lights or gate_mode
	if stable_lights:
		section_seconds=6.0
		for enemy in game.enemies:
			enemy.max_hp=1000000.0
			enemy.hp=1000000.0
			enemy.damage=0.0
			var p:=Vector3(-5.0+float(enemy_positions.size())*.95,0,13.5)
			p.y=game.outpost_height(p)
			enemy_positions.append(p)
			enemy.position=p
	for parent in [game.discoveries,game.wildlife]:
		for lamp in parent.find_children("*","Light3D",true,false):lamps.append(lamp)
	for lamp in game.find_children("*","Light3D",true,false):
		all_lamps.append(lamp)
		light_visibility[lamp]=lamp.visible
	game.hero.position=Vector3(-3.0,5.0,3.5)
	game.move_goal=Vector3(3.0,5.0,3.5)
	game.hero_path.clear()
	await create_timer(5.0 if stable_lights else 1.5).timeout
	print("MOVEMENT_PROFILE_RENDERER ",RenderingServer.get_video_adapter_name()," vsync=",DisplayServer.window_get_vsync_mode()," viewport=",root.size," new_lights=",lamps.size())
	stage_started=float(Time.get_ticks_usec())/1000000.0
	previous_tick=Time.get_ticks_usec()
	sampling=true
	process_frame.connect(frame)
	RenderingServer.frame_pre_draw.connect(apply_visibility)

func frame() -> void:
	if not sampling:return
	var ticks:=Time.get_ticks_usec()
	var delta:=float(ticks-previous_tick)/1000.0
	previous_tick=ticks
	var now:=float(ticks)/1000000.0
	if stable_lights:
		for i in game.enemies.size():game.enemies[i].position=enemy_positions[i]
	if game.hero.position.x>2.7:travel_right=false
	elif game.hero.position.x< -2.7:travel_right=true
	game.move_goal=Vector3(3.0 if travel_right else -3.0,5.0,3.5)
	game.hero_path.clear()
	if stage==1 and not gate_mode:
		for lamp in lamps:lamp.visible=false
	samples.append({"delta":delta,"cpu":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"draw":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"triangles":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
	if now-stage_started<section_seconds:return
	report("all_lights_before" if stage==0 else (("zero_energy_and_far_wildlife_hidden" if gate_mode else "new_lights_disabled") if stage==1 else "all_lights_after"),now-stage_started)
	samples.clear()
	stage+=1
	if stage>=3:
		sampling=false
		print("MOVEMENT_PROFILE_OK")
		quit(0)
		return
	for lamp in lamps:lamp.visible=stage!=1
	game.hero.position=Vector3(-3.0,5.0,3.5)
	game.move_goal=Vector3(3.0,5.0,3.5)
	travel_right=true
	stage_started=now

func apply_visibility() -> void:
	if not sampling or not gate_mode:return
	for lamp in all_lamps:
		lamp.visible=bool(light_visibility[lamp])
		if stage==1 and lamp.light_energy<.001:lamp.visible=false
	if stage==1:
		for animal in game.wildlife.animals:
			if game.hero.position.distance_to(animal.position)>35.0:animal.lamp.visible=false

func report(name_: String, seconds: float) -> void:
	var deltas: Array[float]=[]
	var cpus: Array[float]=[]
	var draws:=0.0
	var triangles:=0.0
	for item in samples:
		deltas.append(item.delta)
		cpus.append(item.cpu)
		draws+=float(item.draw)
		triangles+=float(item.triangles)
	deltas.sort()
	cpus.sort()
	print("MOVEMENT_PROFILE ",JSON.stringify({"phase":name_,"seconds":seconds,"frames":samples.size(),"fps":float(samples.size())/seconds,"delta_p50_ms":deltas[int(deltas.size()*.5)],"delta_p95_ms":deltas[mini(deltas.size()-1,int(deltas.size()*.95))],"process_cpu_p50_ms":cpus[int(cpus.size()*.5)],"process_cpu_p95_ms":cpus[mini(cpus.size()-1,int(cpus.size()*.95))],"draw_calls_mean":draws/samples.size(),"primitives_mean":triangles/samples.size(),"enemies":game.enemies.size()}))
