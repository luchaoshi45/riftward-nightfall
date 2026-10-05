extends SceneTree
## Real Forward+ A/B: remove every skill mesh, then measure lit game surfaces.
var game: Node3D
var failures: Array[String] = []
var observations: Dictionary = {}
const ORIGIN := Vector3(35,0,30)

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.hide()
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size=Vector2i(1920,1200)
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message);push_error(message)

func frame() -> void:
	game.hud.queue_redraw()
	await process_frame;await RenderingServer.frame_post_draw

func photograph(name: String) -> Image:
	for i in 4:await frame()
	var picture:=root.get_texture().get_image()
	check(not picture.is_empty() and picture.get_size()==Vector2i(1920,1200),"Use the actual 1920 × 1200 gameplay-resolution renderer")
	check(picture.save_png("res://build/skill-light-"+name+".png")==OK,"Save real "+name+" frame")
	return picture

func brightness(picture: Image, point: Vector3, half_size: Vector2i=Vector2i(10,8)) -> float:
	var pixel:=Vector2i(game.camera.unproject_position(point))
	var total:=0.0
	var samples:=0
	for y in range(pixel.y-half_size.y,pixel.y+half_size.y):
		for x in range(pixel.x-half_size.x,pixel.x+half_size.x):
			if x<0 or y<0 or x>=picture.get_width() or y>=picture.get_height():continue
			var color:=picture.get_pixel(x,y)
			total+=color.r*.2126+color.g*.7152+color.b*.0722;samples+=1
	return total/maxf(samples,1)

func view(point: Vector3) -> void:
	game.camera.size=31
	game.camera.position=point+Vector3(0,25,29)
	game.camera.look_at(point)
	game.camera_follow=game.camera.position

func clean_effects() -> void:
	game.skill_lights.clear()
	for child in game.effects.get_children():
		if child is AudioStreamPlayer:child.stop();child.stream=null
		child.queue_free()
	await frame()

func set_lamps(enabled: bool) -> void:
	for item in game.skill_lights.lights:item.node.visible=enabled

func compare_skill(slot: int) -> void:
	await clean_effects()
	game.hero.position=ORIGIN;game.move_goal=ORIGIN
	game.hero.hero_action="";game.hero.shield=0;game.hero.shield_time=0
	game.aim=ORIGIN+Vector3.RIGHT*10
	game.mana=game.max_mana;game.cooldowns[slot]=0
	check(game.cast(slot),"The actual skill must release in the real night scene")
	# Effect planes and emissive geometry cannot contribute to the A/B result.
	game.effects.visible=false;game.hud.visible=false
	game.skill_lights.tick(.08,game.phase)
	view(ORIGIN+Vector3.RIGHT*2)
	var primary: OmniLight3D=game.skill_lights.lights[-1].node
	var floor_points: Array[Vector3]=[]
	for offset in [Vector3(-1.5,0,1.8),Vector3(1.6,0,1.8),Vector3(0,0,-2.4)]:
		var point: Vector3=primary.global_position+offset;point.y=game.outpost_height(point)+.025
		floor_points.append(point)
	set_lamps(false)
	var unlit:=await photograph("%s-off-no-fx" % ["q","w","e","r","x"][slot])
	set_lamps(true)
	var first_frames: Array[float]=[]
	for i in 8:
		var start:=Time.get_ticks_usec()
		await frame()
		first_frames.append(float(Time.get_ticks_usec()-start)/1000.0)
	var lit:=await photograph("%s-on-no-fx" % ["q","w","e","r","x"][slot])
	var differences: Array[float]=[]
	for point in floor_points:differences.append(brightness(lit,point)-brightness(unlit,point))
	var largest: float=differences.max()
	check(largest>.006,"Skill %d must illuminate actual ground with every effect mesh hidden: %s" % [slot,differences])
	var distant:=ORIGIN+Vector3(-15,0,5)
	var far_delta:=absf(brightness(lit,distant)-brightness(unlit,distant))
	check(far_delta<.015,"Skill %d must keep terrain outside its range dark" % slot)
	observations[str(slot)]={"floor_luminance_gain":differences,"distant_delta":far_delta,
		"lights":game.skill_lights.lights.size(),"shadow":primary.shadow_enabled,"first_visible_frames_ms":first_frames}
	if slot==3:
		var hero_gain:=brightness(lit,game.hero.position+Vector3.UP,Vector2i(18,22))-brightness(unlit,game.hero.position+Vector3.UP,Vector2i(18,22))
		observations[str(slot)]["hero_luminance_gain"]=hero_gain
		check(hero_gain>.006,"R must light the actual hero PBR model")
		# The same live skill with its authored effect meshes restored.
		game.effects.visible=true;game.hud.visible=true
		await photograph("r-gameplay")
		game.combat.reduced_effects=true
		game.skill_lights.tick(0,game.phase)
		game.effects.visible=false;game.hud.visible=false
		var reduced:=await photograph("r-reduced-no-fx")
		var point: Vector3=floor_points[differences.find(largest)]
		check(brightness(reduced,point)<brightness(lit,point),"Reduced feedback must soften actual illumination")
		game.combat.reduced_effects=false
	game.effects.visible=true;game.hud.visible=true

func timing() -> Dictionary:
	for i in 12:await frame()
	var samples: Array[float]=[]
	for i in 40:
		var start:=Time.get_ticks_usec()
		await frame()
		samples.append(float(Time.get_ticks_usec()-start)/1000.0)
	var raw:=samples.duplicate();samples.sort()
	return {"median_ms":samples[20],"max_ms":samples[-1],"frames_ms":raw}

func homecoming_views() -> void:
	await clean_effects()
	game.phase="day";game.beacon_hp=game.BEACON_MAX;game.victory=false
	game.world.night_mix=1;game.world.night_active=true;game.world.apply_lighting()
	game.hero.position=Vector3(0,5,3.1);game.move_goal=game.hero.position
	view(game.hero.position)
	game.world.follow_ashfall(game.hero.position)
	for index in game.expeditions.camps.size():
		var camp: Dictionary=game.expeditions.camps[index]
		camp.state="escort";camp.npc.position=Vector3(0,5,3)
		game.expeditions.deliver_scout(camp,index)
	game.phase="night";game.expeditions.on_night();game.notice_time=0
	await photograph("two-home-lanterns")
	# Recruitment celebration meshes are animated and cannot enter this A/B.
	game.effects.visible=false
	for camp in game.expeditions.camps:camp.home_light.visible=false
	var no_home:=await photograph("home-lamps-off")
	for camp in game.expeditions.camps:camp.home_light.visible=true
	var with_home:=await photograph("home-lamps-on")
	var npc: BattleUnit=game.expeditions.camps[1].npc
	var home_gain:=brightness(with_home,npc.position+Vector3(-1,0,1.3))-brightness(no_home,npc.position+Vector3(-1,0,1.3))
	check(home_gain>.001,"Returned people must leave actual local illumination, not an emissive prop only")
	observations["home_gain"]=home_gain
	game.effects.visible=true
	game.phase="ended";game.victory=true;game.ending_key="hold";game.day_number=3
	await photograph("two-returnees-result")
	game.victory=false;game.hero.hp=0;game.beacon_hp=800
	await photograph("hero-fallen-result")

func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("This test requires actual Forward+ rendering");quit(1);return
	game=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.set_process(false);game.world.set_process(false)
	await photograph("opening-story")
	check(game.choose_card(0),"Start the actual night via a card choice")
	game.world.night_mix=1;game.world.night_active=true;game.world.apply_lighting()
	game.world.ashfall.emitting=false
	for enemy in game.enemies:enemy.queue_free()
	game.enemies.clear()
	game.hero.position=ORIGIN;game.move_goal=ORIGIN
	game.world.follow_ashfall(ORIGIN)
	game.world.hero_lantern.position=ORIGIN+Vector3.UP*1.3
	view(ORIGIN+Vector3.RIGHT*2)
	game.notice_time=0
	var enemy: BattleUnit=game.spawn_creature(false)
	enemy.position=ORIGIN+Vector3(3,0,-2);enemy.max_hp=10000;enemy.hp=10000
	for slot in 5:await compare_skill(slot)
	await clean_effects();game.effects.visible=false;game.hud.visible=false
	observations["no_skill_timing"]=await timing()
	for i in 6:game.skill_lights.emit_skill(3,ORIGIN+Vector3(float(i%3)*3,0,float(i/3)*3),Vector3.RIGHT,Vector3.INF,8)
	game.skill_lights.tick(.08,"night")
	check(game.skill_lights.lights.size()==6,"Worst case must respect the six-light budget")
	observations["six_light_timing"]=await timing()
	await photograph("six-lights")
	# Pause freezes the light, then gameplay expiration returns to the dark scene.
	var entry: Dictionary=game.skill_lights.lights[-1]
	var energy: float=entry.node.light_energy
	game.skill_lights.tick(3,"paused")
	check(is_equal_approx(entry.time,.08) and is_equal_approx(entry.node.light_energy,energy),"Paused lights must not animate behind the pause UI")
	game.skill_lights.tick(1.1,"night")
	await frame();check(game.skill_lights.lights.is_empty(),"All six lights must expire")
	game.effects.visible=true;game.hud.visible=true
	await homecoming_views()
	var output:=FileAccess.open("res://build/skill-light-observations.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(observations,"  "));output.close()
	print("SKILL_LIGHT_OBSERVATIONS ",JSON.stringify(observations))
	await game.prepare_shutdown();game.queue_free();await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_SKILL_LIGHTING_VISUAL_","OK" if failures.is_empty() else "FAILED")
	quit(0 if failures.is_empty() else 1)
