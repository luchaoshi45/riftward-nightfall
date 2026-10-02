extends SceneTree
## Reproducible, staged footage of v0.1. It does not alter shipped gameplay.
## Run with --write-movie tmp/devlog/ID.avi --fixed-fps 30 --script this_file -- --clip=ID
const DURATIONS := {"01_menu":8.0,"02_map":12.0,"03_movement":10.0,"04_skills":20.0,"05_battle":20.0,"06_shop":10.0,"07_recall":16.0,"08_victory":12.0,"09_models":12.0}
var game: Node3D
var clip := "01_menu"
var clock_time := 0.0
var ready_to_record := false
var fired: Dictionary = {}
var orbit: Node3D
var snapshot_times: Dictionary = {}
var output_dir := "res://devlog/v0.1/screenshots"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--clip="): clip = arg.trim_prefix("--clip=")
		if arg.begins_with("--out="): output_dir = arg.trim_prefix("--out=")
	call_deferred("setup")

func setup() -> void:
	root.content_scale_size = Vector2i(1920,1080)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.auto_test = true
	game.set_process(false)
	game.set_process_unhandled_input(false)
	game.wave_timer = 999
	game.notice_time = 0
	game.aim_ring.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	game.player.position = Vector3(-4,0,1.5)
	game.player.destination = game.player.position
	game.enemy.position = Vector3(5,0,-1)
	game.enemy.destination = game.enemy.position
	game.mode = "playing"
	game.elapsed = 90
	game.wave_number = 5
	game.camera.size = 26
	pose_camera(Vector3.ZERO)
	match clip:
		"01_menu":
			game.mode = "menu"
			game.camera.size = 30
			pose_camera(Vector3(-9,0,0))
			snapshot_times = {2.0:"01_menu"}
		"02_map":
			game.hud.visible = false
			game.player.visible = false
			game.enemy.visible = false
			game.camera.size = 34
			snapshot_times = {2.0:"02_blue_base",6.0:"03_river",10.0:"04_red_base"}
		"03_movement":
			game.enemy.position = Vector3(30,0,-3)
			snapshot_times = {2.0:"05_hero_movement",7.0:"06_hero_close"}
		"04_skills":
			game.level = 4
			game.max_mana = 500
			game.mana = 500
			game.player.hp = 470
			game.enemy.max_hp = 3000
			game.enemy.hp = 3000
			game.enemy.position = Vector3(3,0,1.5)
			snapshot_times = {2.2:"07_q_blade",5.15:"08_w_shield",8.1:"09_e_dash",11.78:"10_r_impact",15.3:"11_d_heal"}
		"05_battle":
			game.level = 4
			game.player.max_hp = 1200
			game.player.hp = 1200
			game.max_mana = 600
			game.mana = 600
			game.gold = 720
			for team in [0,1]:
				for i in range(6): game.spawn_unit("minion",team,Vector3((-1 if team==0 else 1)*(2+i*.75),0,(i%3)*1.15-1))
			game.player.destination = Vector3(-1,0,2)
			snapshot_times = {3.0:"12_lane_battle",9.0:"13_battle_push"}
		"06_shop":
			game.gold = 1400
			snapshot_times = {2.0:"14_shop",7.0:"15_equipment"}
		"07_recall":
			game.player.hp = 350
			game.enemy.position = Vector3(28,0,0)
			snapshot_times = {3.0:"16_recall",7.0:"17_fountain",10.0:"18_respawn"}
		"08_victory":
			for unit in game.units:
				if unit.team==1 and unit.kind=="tower": unit.alive=false; unit.visible=false
			game.player.position = Vector3(27.5,0,2)
			game.player.destination = game.player.position
			game.enemy.alive=false
			game.enemy.visible=false
			game.units[3].hp = 190
			game.units[3].attack_timer=99
			pose_camera(Vector3(28,0,0))
			snapshot_times = {2.0:"19_core_siege",8.0:"20_victory"}
		"09_models":
			game.hud.visible=false
			for unit in game.units: unit.visible=false
			orbit = Node3D.new()
			game.add_child(orbit)
			for spec in [["hero_blue",-6,1.65],["hero_red",-3,1.65],["minion_blue",0,1.8],["tower_blue",3.5,1.1],["core_red",7,1.0]]:
				var model: Node3D = load("res://assets/models/%s.glb" % spec[0]).instantiate()
				orbit.add_child(model)
				model.position = Vector3(spec[1],0,0)
				model.scale = Vector3.ONE * spec[2]
			game.camera.size=15
			game.camera.position=Vector3(1,11,17)
			game.camera.look_at(Vector3(1,1,0))
			snapshot_times = {3.0:"21_model_lineup",7.0:"22_model_turnaround"}
	await process_frame
	ready_to_record = true
	print("RECORDING_CLIP: ",clip)

func pose_camera(center: Vector3) -> void:
	game.camera.position = center + Vector3(0,26,22)
	game.camera.look_at(center)

func at(time: float, id: String) -> bool:
	if clock_time >= time and not fired.has(id):
		fired[id] = true
		return true
	return false

func _process(delta: float) -> bool:
	if not ready_to_record: return false
	clock_time += delta
	match clip:
		"02_map":
			pose_camera(Vector3(lerpf(-30,30,smoothstep(0,12,clock_time)),0,0))
		"03_movement":
			if at(.6,"move1"): game.command_move(Vector3(3,0,2.5))
			if at(3,"move2"): game.command_move(Vector3(-1,0,-2))
			if at(5.5,"move3"): game.command_move(Vector3(-4,0,1))
			game.player.tick(delta)
			game.player.moving=false
			game.update_player(delta)
			game.camera.size=lerpf(26,20,smoothstep(5,9,clock_time))
		"04_skills":
			game.player.tick(delta)
			game.enemy.tick(delta)
			for i in range(5): game.cooldowns[i]=maxf(0,game.cooldowns[i]-delta)
			if at(2,"q"): game.aim=game.enemy.position; game.cast(0)
			if at(5,"w"): game.cast(1)
			if at(8,"e"): game.aim=Vector3(1,0,3); game.cast(2)
			if at(11,"r"): game.aim=game.enemy.position; game.cast(3)
			if at(15,"d"): game.cast(4)
			game.update_projectiles(delta)
			game.update_warnings(delta)
			age_numbers(delta)
		"05_battle":
			if at(1.5,"q"): game.aim=game.enemy.position; game.cast(0)
			if at(3.5,"w"): game.cast(1)
			if at(5,"r"): game.aim=game.enemy.position; game.cast(3)
			if at(7.5,"advance"): game.command_move(Vector3(7,0,2))
			if at(10,"heal"): game.cast(4)
			if at(12,"q2"): game.aim=game.enemy.position; game.cast(0)
			if at(15,"push"): game.command_move(Vector3(9,0,1))
			game.simulate(delta)
			pose_camera(Vector3(clampf(game.player.position.x+2,-8,12),0,0))
		"06_shop":
			if at(1,"shop"): game.shop_open=true
			if at(3,"buyblade"): game.buy(0)
			if at(4.5,"buyarmor"): game.buy(1)
			if at(6,"buyboots"): game.buy(2)
			if at(8,"close"): game.shop_open=false
		"07_recall":
			if at(1,"recall"): game.recall()
			game.simulate(delta)
			pose_camera(Vector3(clampf(game.player.position.x+3,-27,0),0,0))
			if at(8,"death"): game.player.hurt(9999,game.enemy); game.player_respawn=5
		"08_victory":
			game.player.tick(delta)
			if clock_time>1.5 and game.mode=="playing": game.attack(game.player,game.units[3])
			age_numbers(delta)
		"09_models":
			for model in orbit.get_children(): model.rotation.y=clock_time*.42+PI
	game.hud.queue_redraw()
	for time in snapshot_times:
		if at(time,"shot_"+str(time)): save_shot(snapshot_times[time])
	if clock_time >= DURATIONS.get(clip,8):
		print("RECORDING_DONE: ",clip," frames=",Engine.get_process_frames())
		quit()
	return false

func age_numbers(delta: float) -> void:
	for i in range(game.damage_numbers.size()-1,-1,-1):
		game.damage_numbers[i].ttl -= delta
		if game.damage_numbers[i].ttl<=0: game.damage_numbers.remove_at(i)

func save_shot(id: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output_dir.path_join(id+".png"))
	print("SCREENSHOT: ",id," result=",error)
