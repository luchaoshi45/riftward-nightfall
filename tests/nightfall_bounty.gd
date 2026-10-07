extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
## Real scene/GUI/saved waves/death ledgers. Precision cases use 5000 parts,
## disabled unrelated offense, stationary enemies and explicit 100000-damage
## lifecycle boundaries. Economy separately retains original clocks and stats.

const RunSession = preload("res://scripts/run_session.gd")
const Encounters = preload("res://scripts/nightfall_encounters.gd")
const HistoricPlans = preload("res://tests/nightfall_encounters_fixture.gd")
const CleanHud = preload("res://scripts/nightfall_clean_hud.gd")
const SEED := 20261006
const STEP := .1
const HOME := Vector3(0,5,3.1)
const VIEWPORTS := [Vector2i(1920,1200),Vector2i(1920,1080),Vector2i(1440,900)]
const BOUNTY_RECT := Rect2(46,352,496,30)
const OBJECTIVE_TITLE_POINT := Vector2(444,43)
const OBJECTIVE_DETAIL_POINT := Vector2(444,66)
const TARGET_REWARD_ID := 7
const HUD_OBSERVER := """extends 'res://scripts/nightfall_hud.gd'
var drawn_rects: Array[Rect2] = []
var drawn_labels: Array[Dictionary] = []
var drawing_drawer := false
func _draw() -> void:
\tdrawn_rects.clear(); drawn_labels.clear(); drawing_drawer = false
\tsuper._draw()
func box(rect: Rect2, fill: Color = Color(.022,.035,.045,.88), outline: Color = Color('435455')) -> void:
\tdrawn_rects.append(rect)
\tif rect == Rect2(24,112,540,622): drawing_drawer = true
\tif rect == Rect2(428,692,112,30): drawing_drawer = false
\tsuper.box(rect,fill,outline)
func label(value: String, point: Vector2, size_px: int, color: Color = Color('e7e1d3'), latin: bool = false) -> void:
\tvar actual: Font = display_font if latin else font
\tdrawn_labels.append({'text':value,'point':point,'size':size_px,'width':actual.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x,'ascent':actual.get_ascent(size_px),'descent':actual.get_descent(size_px),'drawer':drawing_drawer})
\tsuper.label(value,point,size_px,color,latin)
"""

# An explicit capacity boundary: ordinary production plans are tested above.
# This synthetic composition leaves two basic after the original shellguard,
# then a real F seal removes them through the existing public nest rules.
class ScarceFollowers extends "res://scripts/nightfall_encounters.gd":
	func _later_night(index: int, night: int, theme: String, random: RandomNumberGenerator) -> Dictionary:
		if night==2 and index==2:
			return _composition("人工容量边界","runner","人工十三疾行容量边界",_repeat("runner",13))
		return super._later_night(index,night,theme,random)

var game: Node3D
var checks := 0
var failures: Array[String] = []
var output_dir := "res://build/nightfall-bounty"
var render_test := false
var active_stage := "initialization"
var finished := false
var stage_returned := false
var births: Dictionary = {}
var natural_deaths: Array[Dictionary] = []
var natural_tokens: Dictionary = {}
var natural_damage: Array[Dictionary] = []
var evidence: Dictionary = {}

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args(); render_test="--render-test" in args
	var index:=args.find("--output-dir")
	if index>=0 and index+1<args.size():
		var candidate:=ProjectSettings.globalize_path(args[index+1]).simplify_path()
		var allowed:=ProjectSettings.globalize_path("res://build").simplify_path()
		if candidate.begins_with(allowed+"/"):output_dir=candidate
		else:check(false,"Bounty evidence must stay below the local project build directory")
	root.size=VIEWPORTS[0]; root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT; root.content_scale_size=VIEWPORTS[0]
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.position=Vector2i(10000,10000); root.hide()
	evidence={"seed":SEED,"scope":"precision5000/disabled unrelated offense/stationary actors/direct positions/lethal100000 boundaries; economy original90 wallet and105/90/105 clocks, actual paid purchases and original enemy stats; controlled capture lighting; no human or all-build balance claim","completed":[],"captures":[],"plans":[],"ledgers":[],"boundaries":[],"hud":[],"economy":[]}
	create_timer(300.0,true,false,true).timeout.connect(watchdog)
	call_deferred("run")

func watchdog() -> void:
	if finished:return
	check(false,"Bounty acceptance stalled in "+active_stage)
	await close_game(); finished=true; quit(1)

func check(condition: bool, message: String) -> void:
	checks+=1
	if condition:return
	failures.append(message)
	if failures.size()<=30:push_error(message)

func press(code: int) -> void:
	var event:=InputEventKey.new(); event.keycode=code; event.physical_keycode=code; event.pressed=true
	root.push_input(event,true); event.pressed=false; root.push_input(event,true)
	await process_frame

func mouse(point: Vector2, button: int = 0) -> void:
	var motion:=InputEventMouseMotion.new(); motion.position=point; motion.global_position=point
	root.push_input(motion,true); await process_frame
	if button==0:return
	var event:=InputEventMouseButton.new(); event.position=point; event.global_position=point; event.button_index=button
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if button==MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	event.pressed=true; root.push_input(event,true); await process_frame
	event.pressed=false; event.button_mask=0; root.push_input(event,true); await process_frame

func click_ui(rect: Rect2, button: int = MOUSE_BUTTON_LEFT) -> void:
	await mouse(rect.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900),button)

func redraw() -> void:
	game.hud.queue_redraw()
	for _frame in 3:await process_frame

func camera_at(point: Vector3) -> void:
	game.camera.size=38.0; game.camera.position=point+Vector3(0,25,29)
	game.camera.look_at(point); game.camera_follow=game.camera.position

func stand(point: Vector3) -> void:
	point.y=game.outpost_height(point); game.hero.position=point; game.move_goal=point
	game.hero_path.clear(); game.hero_keyboard_active=false; game.hero.moving=false
	game.hero.set_locomotion_velocity(Vector3.ZERO)

func clear_enemies() -> void:
	game.clear_warders(); game.clear_summoners(); game.clear_lobbers(); game.clear_focus(); game.cancel_hero_attack()
	for value: Variant in game.enemies:
		if not is_instance_valid(value) or value.is_queued_for_deletion():continue
		var unit: BattleUnit=value as BattleUnit
		unit.queue_free()
	game.enemies.clear()

func suspend_defense() -> void:
	game.hero.attack_timer=100000.0; game.pulse_timer=100000.0
	game.gate_trap_charges=0; game.show_gate_trap_charges()
	for pad: Dictionary in game.world.tower_pads:pad.cooldown=100000.0

func hold_enemies() -> void:
	for value: Variant in game.enemies:
		if not is_instance_valid(value) or value.is_queued_for_deletion():continue
		var unit: BattleUnit=value as BattleUnit
		if not unit.alive:continue
		var token:=unit.get_instance_id()
		if not births.has(token):
			births[token]={"token":token,"wave":int(unit.get_meta("wave_reward_id",-1)),"role":String(unit.get_meta("threat","")),"max_hp":unit.max_hp,"armor":unit.armor,"speed":unit.speed,"damage":unit.damage,"position":unit.position}
		unit.speed=0.0; unit.attack_timer=100000.0

func advance(seconds: float, precision: bool = true) -> void:
	for frame in ceili(seconds/STEP):
		if precision:hold_enemies(); suspend_defense()
		game.simulate(minf(STEP,seconds-float(frame)*STEP))
		if frame%80==79:await process_frame
	if precision:hold_enemies()

func snapshot() -> Dictionary:
	var units: Array[Dictionary]=[]
	for value: Variant in game.enemies:
		if not is_instance_valid(value) or value.is_queued_for_deletion():continue
		var unit: BattleUnit=value as BattleUnit
		units.append({"token":unit.get_instance_id(),"alive":unit.alive,"hp":unit.hp,"position":unit.position,"queued":false})
	return {"bounty":game.bounty_snapshot(),"parts":int(game.scrap),"phase":String(game.phase),"time":float(game.phase_time),"day":int(game.day_number),"rng":game.run.rng.state,"spawn_rng":game.spawn_rng.state,"plan":game.night_plan.duplicate(true),"selected":int(game.countermeasure_selected),"countermeasure":String(game.countermeasure_active),"counter_light":float(game.countermeasure_light_time),"counter_tower":float(game.countermeasure_tower_time),"goal":game.move_goal,"path":game.hero_path.duplicate(),"units":units}

func close_game() -> void:
	if not is_instance_valid(game):return
	var bounty: RefCounted=game.get("bounty")
	var old_root:=game.get_instance_id()
	await game.prepare_shutdown()
	var cleared: Dictionary=bounty.call("snapshot")
	check(String(cleared.state)=="idle" and int(cleared.expected_count)==0,"Actual shutdown clears captured run-local bounty and committed wave capacity")
	bounty=null
	if current_scene==game:current_scene=null
	game.queue_free(); game=null
	for _frame in 4:await process_frame
	check(not is_instance_id_valid(old_root),"Actual shutdown releases the old real game root")

func fresh(precision: bool = true, mode: String = "siege") -> void:
	await close_game()
	check(RunSession.queue_request(self,SEED,mode),"Actual new run accepts the fixed seed and production mode "+mode)
	game=load("res://scenes/nightfall.tscn").instantiate(); root.add_child(game); current_scene=game
	for _frame in 5:await process_frame
	game.set_process(false); game.world.set_process(false)
	var script:=GDScript.new(); script.source_code=HUD_OBSERVER
	check(script.reload()==OK,"Read-only bounty observer forwards actual production drawing and input")
	var original: Control=game.hud; var layer: Node=original.get_parent(); layer.remove_child(original); original.queue_free()
	var observed: Control=script.new(); observed.game=game; game.hud=observed; layer.add_child(observed)
	observed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await press(KEY_1)
	check(game.phase=="night" and game.phase_time==105.0 and game.run.seed_value==SEED and game.scrap==90 and game.tower_count()==2,"Real opening key keeps the original105-second night, ninety parts and two gifted towers")
	check(not bool(game.bounty_snapshot().available) and not game.select_bounty(),"Real first night never offers a second-night-only bounty")
	births.clear()
	if precision:
		game.scrap=5000; clear_enemies(); game.wave_index=game.WAVES_PER_NIGHT; suspend_defense(); stand(HOME)

func day_fixture(mode: String = "siege", day: int = 2) -> void:
	await fresh(true,mode)
	game.day_number=day-1; TransitionFixture.finish_for_fixture(game); await press(KEY_1)
	clear_enemies(); suspend_defense(); stand(HOME); camera_at(HOME)
	check(game.phase=="day" and game.day_number==day and game.phase_time==90.0,"Precision setup enters the actual dawn/card/day hooks with the original90-second day")

func open_defense() -> void:
	if game.construction.active:await press(KEY_ESCAPE)
	if game.hud.detail_tab.is_empty():await press(KEY_F3)
	if game.hud.detail_tab!="defense":await click_ui(game.hud.details_tab_rect(3))
	await redraw()
	check(game.hud.detail_tab=="defense","Actual F3 tab GUI opens the existing defense drawer")

func close_drawer() -> void:
	if not game.hud.detail_tab.is_empty():await press(KEY_F3)
	await redraw()

func select_gui() -> void:
	await open_defense()
	check(game.hud.bounty_rect()==BOUNTY_RECT,"Actual bounty control uses its declared existing-drawer hitbox")
	var before_parts: int=game.scrap; var before_goal: Vector3=game.move_goal
	await click_ui(game.hud.bounty_rect())
	check(String(game.bounty_snapshot().state)=="selected" and game.countermeasure_selected==-1 and game.scrap==before_parts and game.move_goal==before_goal,"Actual bounty GUI selects the live plan, cancels free countermeasure and consumes its click without payment or movement")

func target_units() -> Array[BattleUnit]:
	var result: Array[BattleUnit]=[]
	for value: Variant in game.enemies:
		if not is_instance_valid(value) or value.is_queued_for_deletion():continue
		var unit: BattleUnit=value as BattleUnit
		if int(unit.get_meta("wave_reward_id",-1))==TARGET_REWARD_ID:result.append(unit)
	return result

func target_fixture() -> Array[BattleUnit]:
	await day_fixture(); await select_gui(); await close_drawer()
	var plan: Array[Dictionary]=game.night_plan.duplicate(true)
	game.start_night()
	var state: Dictionary=game.bounty_snapshot()
	check(state.state=="active" and state.wave==3 and state.expected_count==int(plan[2].count) and state.paid==0 and game.phase_time==105.0,"Actual sunset locks the saved third-wave count with a fresh original105-second deadline")
	check(game.night_plan==plan and game.countermeasure_active.is_empty(),"Actual sunset retains the chosen saved roles and forfeits all free countermeasure effects")
	await advance(40.001)
	var units:=target_units()
	check(units.size()==int(plan[2].count) and game.wave_rewards.snapshot(TARGET_REWARD_ID).count==units.size(),"Actual timed third-wave spawning registers every promised actor in the real sealed ledger")
	return units

func kill_all_but_last(units: Array[BattleUnit]) -> BattleUnit:
	check(units.size()>1,"Real bounty target wave has multiple distinct members")
	if units.is_empty():return null
	for index in units.size()-1:units[index].hurt(100000.0,null)
	return units[-1]

func clear_transient_hud() -> void:
	game.notice_time=0.0; game.reward_toasts.clear(); game.beacon_alarm_time=0.0
	game.hero_damage_flash_time=0.0; game.combat_milestone_time=0.0
	if game.combat:game.combat.clear_transients()

func actual_hud(tag: String) -> void:
	var before:=snapshot(); var previous_viewport: Vector2i=root.size
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport; await redraw()
		var bounty_labels: Array[Dictionary]=[]
		for row: Dictionary in game.hud.drawn_labels:
			check(row.point.x>=0 and row.point.x+float(row.width)<=1440 and row.point.y-float(row.ascent)>=0 and row.point.y+float(row.descent)<=900,"Actual bounty HUD font bounds fit "+tag+" "+str(viewport)+": "+String(row.text))
			for character: String in String(row.text):
				var code:=character.unicode_at(0)
				if code>=0x4e00 and code<=0x9fff:check(game.hud.font.has_char(code),"Actual production font supplies bounty Chinese glyph "+character)
			if bool(row.drawer):
				check(row.point.x>=32 and row.point.x+float(row.width)<=552 and row.point.y+float(row.descent)<692,"Actual bounty drawer text fits its content area above the real close button")
			if String(row.text).contains("悬赏"):bounty_labels.append(row.duplicate())
		if game.hud.detail_tab=="defense":check(not bounty_labels.is_empty(),"Actual existing defense drawer visibly describes bounty state "+tag)
		if tag=="third-wave-preview":
			var preview: Dictionary=game.wave_preview()
			check(not preview.is_empty() and int(preview.get("wave_number",0))==3 and String(preview.get("bounty_id",""))=="shellguard_pack","Actual compact forecast reads the real selected third-wave bounty preview in "+str(viewport))
			if not preview.is_empty():
				var expected_title: String="下一波 · 甲壳悬赏 · %d只 · %.0f秒" % [int(preview.count),float(preview.remaining)]
				var expected_detail: String="全清+48 · 甲壳60甲/J破甲 · 投蚀落点2米 · F3 防线"
				var objective: Rect2=CleanHud.objective_rect(game.hud,game)
				check(CleanHud.OBJECTIVE_RECT.encloses(objective) and game.hud.drawn_rects.has(objective)
					and game.hud.visible_hud_rects().has(objective),"The painted bounty objective and its actual input region share the current compact rectangle in "+str(viewport))
				var title_rows: Array[Dictionary]=[]; var detail_rows: Array[Dictionary]=[]
				for row: Dictionary in game.hud.drawn_labels:
					if row.point==OBJECTIVE_TITLE_POINT:title_rows.append(row)
					if row.point==OBJECTIVE_DETAIL_POINT:detail_rows.append(row)
				check(title_rows.size()==1 and String(title_rows[0].text)==expected_title and int(title_rows[0].size)==16 and float(title_rows[0].width)<=552.0,"Actual compact third-wave title includes the complete real population and rounded deadline within552px in "+str(viewport))
				check(detail_rows.size()==1 and String(detail_rows[0].text)==expected_detail and int(detail_rows[0].size)==12 and float(detail_rows[0].width)<=552.0,"Actual compact third-wave detail includes the complete reward, armor counter and two-meter warning within552px in "+str(viewport))
				for row: Dictionary in title_rows+detail_rows:
					var glyphs:=Rect2(Vector2(row.point.x,row.point.y-float(row.ascent)),Vector2(float(row.width),float(row.ascent)+float(row.descent)))
					check(objective.encloses(glyphs),"The complete actual bounty title/detail glyph bounds fit the painted compact objective in "+str(viewport)+": "+String(row.text))
		(evidence.hud as Array).append({"tag":tag,"viewport":viewport,"bounty_labels":bounty_labels})
	check(snapshot()==before,"Three-viewport bounty drawing does not spend, advance clocks, roll plans or move actors")
	root.size=previous_viewport; root.content_scale_size=previous_viewport; await redraw()

func capture(tag: String) -> void:
	if not render_test:return
	check(DisplayServer.get_name()!="headless","Bounty screenshots require an actual graphical renderer")
	if DisplayServer.get_name()=="headless":return
	var before:=snapshot(); var previous_viewport: Vector2i=root.size
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport
		game.world.night_mix=1.0 if game.phase=="night" else 0.0; game.world.apply_lighting(); await redraw()
		for _frame in 2:await RenderingServer.frame_post_draw
		var image: Image=root.get_texture().get_image()
		check(image.get_size()==viewport,"Actual bounty capture matches the requested viewport")
		var folder:=ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
		var name:="%s-%dx%d" % [tag,viewport.x,viewport.y]
		check(image.save_png(folder.path_join(name+".png"))==OK,"Actual bounty PNG saves below local build")
		(evidence.captures as Array).append(name)
	check(snapshot()==before,"Controlled capture lighting never changes the actual bounty/economic/plan state")
	root.size=previous_viewport; root.content_scale_size=previous_viewport; await redraw()

func saved_plan_matrix() -> void:
	var encounters: RefCounted=Encounters.new()
	for mode: String in ["teaching","standard","siege","echo"]:
		for night in range(1,5):
			var historical: Array[Dictionary]=encounters.make_plan(mode,night,17,0)
			var restored_rows: Array=[]
			for row: Dictionary in historical:
				var restored: Array=row.roles.duplicate()
				for slot in restored.size():
					if restored[slot] in ["summoner","warder","shellguard","burstling"]:restored[slot]="basic"
				restored_rows.append([restored,row.count,row.role_count,row.boss_count])
			check(JSON.stringify(restored_rows).sha256_text()==HistoricPlans.BASELINE_ROLE_DIGESTS["%s:%d" % [mode,night]],"Original make_plan keeps the frozen pre-support role order/population for "+mode+str(night))
			for seed_value: int in [-55,17,45,29045,2147483647]:
				for nests in range(4):
					var original: Array[Dictionary]=encounters.make_plan(mode,night,seed_value,nests)
					var baseline: Array[Dictionary]=original.duplicate(true)
					var converted: Array[Dictionary]=encounters.with_bounty(original)
					var eligible:=mode!="teaching" and night==2 and (original[2].roles as Array).count("basic")>=2
					check(original==baseline and original==encounters.make_plan(mode,night,seed_value,nests),"Pure bounty conversion cannot alter the original deterministic seed/mode/night/nest plan")
					check(converted.is_empty()!=eligible,"Bounty conversion only accepts real standard second-night plans with two ordinary followers")
					if not eligible:continue
					for wave in range(5):
						if wave!=2:check(converted[wave]==baseline[wave],"Every other wave keeps exact roles/order/labels/counts and boss metadata")
						else:
							var expected: Array=baseline[wave].roles.duplicate()
							for _replacement in 2:expected[expected.rfind("basic")]="shellguard"
							check(converted[wave].roles==expected,"Bounty replaces exactly two final basic entries without reshuffling or another RNG draw")
							check(converted[wave].count==baseline[wave].count and converted[wave].role_count==baseline[wave].role_count and converted[wave].time==baseline[wave].time and converted[wave].threat==baseline[wave].threat,"Bounty preserves target population, forty-second time and original primary threat")
							check(converted[wave].shellguard_count==3 and converted[wave].bounty_id=="shellguard_pack" and converted[wave].bounty_reward==48,"Saved target metadata truthfully records three real shellguards and the separate48 reward")
							for role: String in Encounters.KNOWN_ROLES:
								if role not in ["basic","shellguard"]:check(converted[wave].roles.count(role)==baseline[wave].roles.count(role),"Bounty cannot replace any original specialist "+role)
					check(encounters.with_bounty(converted).is_empty(),"A marked bounty plan cannot receive a second two-enemy conversion")
					converted[0].roles.clear(); converted[2].roles.clear()
					check(original==baseline,"All returned nested role arrays are independent deep copies")
					(evidence.plans as Array).append({"mode":mode,"night":night,"seed":seed_value,"nests":nests,"original_count":int(baseline[2].count),"original_roles":baseline[2].roles})
	var valid: Array[Dictionary]=encounters.make_plan("siege",2,SEED,0)
	var one_follower: Array[Dictionary]=valid.duplicate(true)
	var roles: Array=one_follower[2].roles
	while roles.count("basic")>1:roles[roles.find("basic")]="runner"
	check(encounters.with_bounty(one_follower).is_empty(),"Explicit synthetic one-follower capacity refuses a partial bounty conversion")
	var malformed: Array[Dictionary]=valid.duplicate(true); malformed[2].count+=1
	check(encounters.with_bounty(malformed).is_empty(),"Malformed target population cannot be committed to a bounty ledger")
	malformed=valid.duplicate(true); malformed[2].roles.append("unknown"); malformed[2].count+=1; malformed[2].role_count+=1
	check(encounters.with_bounty(malformed).is_empty(),"Unknown real role identity cannot enter a locked bounty roster")
	var empty: Array[Dictionary]=[]; check(encounters.with_bounty(empty).is_empty(),"Empty plans cannot create free bounty income")
	stage_returned=true

func physical_selection_and_lock() -> void:
	await day_fixture()
	check(game.bounty_snapshot().state=="offered" and bool(game.bounty_snapshot().available),"The actual standard second dawn offers the one optional bounty")
	var baseline: Array[Dictionary]=game.night_plan.duplicate(true)
	for viewport: Vector2i in VIEWPORTS:
		root.size=viewport; root.content_scale_size=viewport
		for key: int in [KEY_7,KEY_8,KEY_9]:
			await press(key); var counter: int=key-KEY_7
			check(game.countermeasure_selected==counter and game.bounty_snapshot().state=="offered" and game.night_plan==baseline,"Actual free-countermeasure key selects its original plan before bounty")
			await select_gui(); var selected:=snapshot()
			check(game.select_bounty() and snapshot()==selected,"Repeating the chosen bounty is economically and geometrically idempotent")
			await press(key)
			check(game.countermeasure_selected==counter and game.bounty_snapshot().state=="offered" and game.night_plan==baseline,"Actual7/8/9 cancels bounty and restores the exact original saved plan")
			await select_gui(); await click_ui(game.hud.countermeasure_rect(counter))
			check(game.countermeasure_selected==counter and game.bounty_snapshot().state=="offered" and game.night_plan==baseline,"Actual original countermeasure GUI also cancels bounty without a leftover marked plan")
		await close_drawer()
	root.size=VIEWPORTS[0]; root.content_scale_size=VIEWPORTS[0]
	await select_gui(); await close_drawer(); game.phase_time=.001; await advance(.002)
	check(game.phase=="night" and game.phase_time==105.0 and game.bounty_snapshot().state=="active","Actual day-clock expiration locks the selected bounty and starts the original night clock")
	var locked:=snapshot()
	for key: int in [KEY_7,KEY_8,KEY_9]:await press(key)
	check(not game.select_bounty() and snapshot()==locked,"Nighttime keys/API cannot change the promised locked roles or restore a free countermeasure")
	for mode: String in ["teaching","siege","echo"]:
		await day_fixture(mode,3 if mode!="teaching" else 2)
		var unavailable:=snapshot()
		check(not bool(game.bounty_snapshot().available) and not game.select_bounty() and snapshot()==unavailable,"Teaching and later dawns refuse the one second-night bounty without any state/payment mutation")
	await day_fixture("echo")
	check(game.select_bounty() and game.bounty_snapshot().state=="selected","The real alternate standard mode also accepts its saved second-night bounty")
	await day_fixture()
	game.encounters=ScarceFollowers.new(); game.prepare_next_night_plan()
	check(game.night_plan[2].roles.count("basic")==2 and game.select_bounty(),"Synthetic13-specialist boundary initially has precisely two ordinary followers to commit")
	var nest: Dictionary=game.world.nests[0]; stand(nest.position); camera_at(nest.position); await press(KEY_F)
	check(bool(nest.cleansed) and game.bounty_snapshot().state=="offered" and not bool(game.bounty_snapshot().available),"Actual F sealing withdraws the selected bounty when the explicit capacity boundary loses both ordinary followers")
	var scarce: Array[Dictionary]=game.encounters.make_plan(game.run_mode,2,SEED,game.cleansed_nests())
	check(game.night_plan==scarce and not game.night_plan[2].has("bounty_id") and not game.notice.is_empty(),"Capacity withdrawal leaves the exact unmarked reduced plan and a visible reason instead of partially replacing specialists")
	stage_returned=true

func real_births_and_ledgers() -> void:
	var units: Array[BattleUnit]=await target_fixture()
	var shellguards:=0; var tokens: Dictionary={}
	for value: Variant in units:
		check(is_instance_valid(value) and not value.is_queued_for_deletion(),"The real freshly spawned target roster contains valid unretired actors")
		if not is_instance_valid(value) or value.is_queued_for_deletion():continue
		var unit: BattleUnit=value as BattleUnit
		check(not tokens.has(unit.get_instance_id()),"Actual third-wave actors have distinct stable identities")
		tokens[unit.get_instance_id()]=true
		if String(unit.get_meta("threat",""))=="shellguard":
			shellguards+=1; var actual: Dictionary=births[unit.get_instance_id()]
			check(unit.armor==60.0 and is_equal_approx(unit.max_hp,(155.0+2*28)*1.15) and actual.speed==2.7 and actual.damage==22.0,"All three actual shellguard births retain original60 armor/health/2.7 speed/22 damage before the stationary fixture")
	check(shellguards==3 and game.wave_rewards.snapshot(TARGET_REWARD_ID).budget==24,"Actual bounty wave has three甲壳 and only the original24-part base budget")
	var balance: int=game.scrap; var last:=kill_all_but_last(units)
	if not is_instance_valid(last):return
	var partial: Dictionary=game.wave_rewards.snapshot(TARGET_REWARD_ID)
	check(last.alive and partial.kills==units.size()-1 and not bool(partial.cleared) and game.bounty_snapshot().state=="active" and game.bounty_snapshot().paid==0,"The genuine final living enemy blocks the bounty even after every other actor truly dies")
	check(game.scrap-balance==int(partial.paid) and int(partial.paid)<=16,"Before clear, the single wallet contains only budgeted partial base income")
	last.hurt(100000.0,null)
	var completed: Dictionary=game.wave_rewards.snapshot(TARGET_REWARD_ID)
	check(completed.kills==units.size() and completed.cleared and completed.paid==24 and game.bounty_snapshot().state=="won" and game.bounty_snapshot().paid==48,"The last true death commits the sealed24 ledger and one separate48 bounty")
	check(game.scrap==balance+24+48,"Real third-wave deaths add exactly72 parts to the sole wallet, with no second currency")
	var paid: int=game.scrap; last.hurt(100000.0,null)
	check(game.wave_rewards.defeat(last)==0,"The real already-defeated identity cannot repeat base ledger income")
	last.defeated.emit(last,null)
	check(game.scrap==paid and game.bounty_snapshot().paid==48,"An explicit repeated actual death callback cannot repay either base income or bounty")
	(evidence.ledgers as Array).append({"wave":3,"actors":units.size(),"shellguards":shellguards,"partial":partial,"completed":completed,"base":24,"bonus":48,"actual_delta":game.scrap-balance})
	TransitionFixture.finish_for_fixture(game)
	check(game.bounty_snapshot().state=="won" and game.bounty_snapshot().paid==48,"The earned one-time result survives dawn without becoming another offer")
	await press(KEY_1)
	check(not game.select_bounty() and game.bounty_snapshot().paid==48,"A later dawn cannot repeat the already won run-local bounty")
	stage_returned=true

func rejection_boundaries() -> void:
	for failure_kind: String in ["alive-signal","released-member","zero-time","negative-time","hero-death","beacon-death"]:
		var units: Array[BattleUnit]=await target_fixture(); var last:=kill_all_but_last(units)
		if not is_instance_valid(last):continue
		var before_paid: int=int(game.bounty_snapshot().paid)
		match failure_kind:
			"alive-signal":
				check(last.alive and last.hp>0.0,"Fake-death boundary begins with a genuinely living registered actor")
				last.defeated.emit(last,null)
				await process_frame; await process_frame
				check(not game.wave_rewards.snapshot(TARGET_REWARD_ID).cleared,"An emitted signal without actual hurt/death cannot clear the registered real ledger")
			"released-member":
				var token:=last.get_instance_id(); last.queue_free(); await process_frame; await process_frame
				check(not is_instance_id_valid(token) and not game.wave_rewards.snapshot(TARGET_REWARD_ID).cleared,"Actually releasing the last living actor cannot stand in for a registered death")
			"zero-time","negative-time":
				game.phase_time=0.0 if failure_kind=="zero-time" else -.001
				last.hurt(100000.0,null)
				check(game.wave_rewards.snapshot(TARGET_REWARD_ID).cleared,"The explicit nonpositive-time boundary still uses a genuine final death")
			"hero-death":
				game.hero.hurt(100000.0,null)
				check(game.phase=="ended" and not game.hero.alive,"Real lethal hero hurt reaches production defeat before the final enemy dies")
				last.hurt(100000.0,null)
			"beacon-death":
				# Controlled low-health boundary, then actual reachable enemy AI
				# completes its unmodified damage callback against the real core.
				game.beacon_hp=1.0; stand(Vector3(30,0,40))
				var attacker: BattleUnit=game.spawn_creature(true,"basic")
				attacker.position=Vector3(0,5,4.5); attacker.attack_timer=0.0
				check(game.outpost_walkable(attacker.position) and game.choose_enemy_target(attacker).kind=="beacon" and game.can_attack_line(attacker.position,Vector3(0,5,0)),"Controlled core attacker stands on a real walkable courtyard cell and legally selects the reachable core")
				for _frame in 30:
					if game.phase=="ended":break
					attacker.tick(.1)
					game.update_creature(attacker,.1)
				check(game.phase=="ended" and game.beacon_hp==0.0,"Actual enemy attack at the reachable core reaches real beacon defeat")
				last.hurt(100000.0,null)
		var result: Dictionary=game.bounty_snapshot()
		check(before_paid==0 and result.paid==0 and result.state!="won","Actual "+failure_kind+" boundary cannot create bounty income")
		if game.phase=="night":game.phase_time=.001; await advance(.002)
		check(game.bounty_snapshot().state=="expired" and game.bounty_snapshot().paid==0,"Failure/time expiry records a terminal unpaid bounty for "+failure_kind)
		(evidence.boundaries as Array).append({"kind":failure_kind,"ledger":game.wave_rewards.snapshot(TARGET_REWARD_ID),"bounty":game.bounty_snapshot(),"phase":game.phase})
	var units: Array[BattleUnit]=await target_fixture(); var last:=kill_all_but_last(units)
	game.phase_time=.000001
	if is_instance_valid(last):last.hurt(100000.0,null)
	check(game.bounty_snapshot().state=="won" and game.bounty_snapshot().paid==48,"A genuine last death with strictly positive remaining original time can claim exactly once")
	stage_returned=true

func frozen_phases_and_retry() -> void:
	await day_fixture(); await select_gui()
	await press(KEY_F1); await press(KEY_ESCAPE)
	check(game.phase=="paused","Actual F1 then source-close pauses the live offered defense page")
	var before:=snapshot(); game.simulate(4.0); await click_ui(game.hud.bounty_rect())
	check(not game.select_bounty() and snapshot()==before,"Paused actual GUI/API and simulate cannot pay, change roles or advance the selected bounty")
	for _escape in 3:
		if game.phase!="paused":break
		await press(KEY_ESCAPE)
	check(game.phase=="day","Actual Escape closes the defense drawer and resumes the original paused day")
	await close_drawer()
	var parts: int=game.scrap; var price: int=game.run.memory_cost(); await press(KEY_V)
	check(game.phase=="draft" and game.scrap==parts-price,"Actual V pays the sole wallet to open a genuine freezing card choice")
	before=snapshot(); game.simulate(4.0)
	check(not game.select_bounty() and snapshot()==before,"Actual paid-card phase freezes the selected plan/deadline and rejects another bounty selection")
	await press(KEY_1)
	check(game.phase=="day" and game.bounty_snapshot().state=="selected","Actual choice resumes the same selected second-day bounty")
	var units: Array[BattleUnit]=await target_fixture(); var last:=kill_all_but_last(units)
	await press(KEY_F1); await press(KEY_ESCAPE); before=snapshot(); game.simulate(4)
	check(snapshot()==before,"A paused actual final-enemy situation preserves actors, wallet, deadline and ledger progress")
	if is_instance_valid(last):last.hurt(100000.0,null)
	check(game.bounty_snapshot().paid==0 and game.bounty_snapshot().state!="won","An explicit death while paused cannot use an otherwise clear ledger to claim bounty")
	for _escape in 3:
		if game.phase!="paused":break
		await press(KEY_ESCAPE)
	check(game.phase=="night","Actual Escape resumes the original final-enemy night")
	game.phase_time=.001; await advance(.002)
	check(game.bounty_snapshot().paid==0,"Resuming/dawn cannot retroactively cash a last death that occurred while paused")
	await day_fixture(); await select_gui(); await close_drawer()
	var captured: RefCounted=game.get("bounty"); var old_root:=game.get_instance_id()
	game.end_defeat("悬赏重试生命周期边界"); await press(KEY_ENTER)
	for _frame in 240:
		await create_timer(.02,true,false,true).timeout
		if is_instance_valid(current_scene) and current_scene.get_instance_id()!=old_root:
			game=current_scene as Node3D; game.set_process(false); game.world.set_process(false); break
	check(is_instance_valid(game) and game.get_instance_id()!=old_root and not is_instance_id_valid(old_root),"Actual same-seed Enter really releases the prior game root")
	if not is_instance_valid(game) or game.get_instance_id()==old_root:return
	check(game.run.seed_value==SEED and game.phase=="draft" and game.scrap==90 and game.bounty_snapshot().state=="idle" and game.bounty_snapshot().paid==0,"Real retry starts the same seed with original wallet, free opening card and no inherited bounty")
	check(String(captured.call("snapshot").state)=="idle","Captured old bounty reference is actually cleared during production shutdown/retry")
	captured=null
	await fresh(); game.day_number=2; TransitionFixture.finish_for_fixture(game); await press(KEY_1)
	check(game.bounty_snapshot().state=="idle" and not game.select_bounty(),"An unchosen skipped second-night offer cannot appear at a later dawn")
	stage_returned=true

func hud_and_default_coverage() -> void:
	await day_fixture(); await close_drawer(); clear_transient_hud(); await redraw()
	var ordinary: Array=game.hud.visible_hud_rects().duplicate(); var default_area:=0.0
	var ordinary_objective: Rect2=CleanHud.objective_rect(game.hud,game)
	check(ordinary.has(ordinary_objective),"The quiet daytime baseline includes its actual compact objective input region")
	for rect: Rect2 in ordinary:default_area+=rect.get_area()
	check(default_area/(1440.0*900.0)<.15,"Actual default bounty-day conservative HUD area retains the prior compact under15-percent budget")
	await open_defense(); await actual_hud("offered"); await capture("bounty-offered-existing-defense")
	await select_gui(); await actual_hud("selected"); await capture("bounty-selected-existing-defense")
	await close_drawer(); clear_transient_hud(); await redraw()
	check(game.hud.visible_hud_rects()==ordinary,"Selecting bounty adds no default permanent rectangle or input region")
	stand(Vector3(0,0,33)); camera_at(game.hero.position)
	var before:=snapshot(); await click_ui(BOUNTY_RECT,MOUSE_BUTTON_RIGHT)
	check(game.move_goal!=before.goal and game.bounty_snapshot().state=="selected","The hidden drawer bounty area releases real normal right-click world movement")
	stand(HOME); game.start_night(); await advance(36.0); clear_transient_hud(); camera_at(HOME)
	await actual_hud("third-wave-preview"); await capture("bounty-real-third-wave-forecast")
	var live_areas: Array=game.hud.visible_hud_rects().duplicate()
	var live_objective: Rect2=CleanHud.objective_rect(game.hud,game)
	var ordinary_other: Array=ordinary.duplicate(); ordinary_other.erase(ordinary_objective)
	var live_other: Array=live_areas.duplicate(); live_other.erase(live_objective)
	check(not game.hud.drawn_rects.has(BOUNTY_RECT) and live_areas.has(live_objective)
		and game.hud.drawn_rects.has(live_objective) and live_areas.size()==ordinary.size()
		and live_other==ordinary_other and live_objective.position==ordinary_objective.position
		and CleanHud.OBJECTIVE_RECT.encloses(live_objective),"Actual live bounty forecast only resizes the existing compact objective; every other permanent rectangle and input region stays exact")
	await advance(4.001); var units:=target_units(); var last:=kill_all_but_last(units)
	await open_defense(); await actual_hud("active-last-enemy"); await capture("bounty-active-last-enemy")
	if is_instance_valid(last):last.hurt(100000.0,null)
	await redraw(); await actual_hud("won"); await capture("bounty-won-existing-defense")
	# Artificial saved-plan corruption exercises the real fail-closed sunset
	# fallback and keeps the terminal state in the genuine second-night drawer.
	await day_fixture(); await select_gui(); await close_drawer()
	var baseline: Array[Dictionary]=game.encounters.make_plan(game.run_mode,2,SEED,game.cleansed_nests())
	game.night_plan[2].bounty_reward=0; game.start_night()
	check(game.phase=="night" and game.day_number==2 and game.bounty_snapshot().state=="expired" and game.night_plan==baseline,"An explicitly malformed bounty reward fails sunset lock and restores the exact ordinary second-night plan")
	await open_defense(); await actual_hud("expired-invalid-lock-boundary"); await capture("bounty-expired-invalid-lock-boundary")
	stage_returned=true

func on_natural_death(unit: BattleUnit, _source: BattleUnit) -> void:
	natural_deaths.append({"token":unit.get_instance_id(),"wave":int(unit.get_meta("wave_reward_id",-1)),"role":String(unit.get_meta("threat","")),"alive":unit.alive,"hp":unit.hp,"night":int(game.day_number),"time_left":float(game.phase_time)})

func on_natural_damage(unit: BattleUnit, source: BattleUnit, hp_loss: float, shield_loss: float) -> void:
	natural_damage.append({"token":unit.get_instance_id(),"source":source.get_instance_id() if is_instance_valid(source) else -1,"hp":hp_loss,"shield":shield_loss,"night":int(game.day_number),"time_left":float(game.phase_time)})

func observe_natural_actors() -> void:
	for value: Variant in game.enemies:
		if not is_instance_valid(value) or value.is_queued_for_deletion():continue
		var unit: BattleUnit=value as BattleUnit
		if natural_tokens.has(unit.get_instance_id()):continue
		natural_tokens[unit.get_instance_id()]=true; unit.defeated.connect(on_natural_death)

func natural_policy_frame() -> void:
	observe_natural_actors()
	game.aim=game.hero.position+Vector3(0,0,8)
	if game.gate_pressure()>0:game.cast(0)
	if game.hero.hp<game.hero.max_hp*.6:game.cast(1); game.cast(4)
	if game.gate_pressure()>=6:game.cast(3)
	game.simulate(STEP)

func natural_economic_comparison() -> void:
	for route: String in ["free-countermeasure","bounty"]:
		await fresh(false); natural_deaths.clear(); natural_tokens.clear(); natural_damage.clear()
		game.hero.damage_confirmed.connect(on_natural_damage)
		camera_at(Vector3(0,5,10)); await mouse(game.camera.unproject_position(Vector3(0,5,10)),MOUSE_BUTTON_RIGHT)
		var first_night_elapsed := 0.0
		var first_night_cutoff: Dictionary = {}
		# Bound actual residual combat; the production assault deadline is unchanged.
		for frame in ceili(240.0 / STEP):
			if game.phase!="night":break
			natural_policy_frame()
			first_night_elapsed += STEP
			if first_night_cutoff.is_empty() and first_night_elapsed >= game.NIGHT_LENGTH:
				first_night_cutoff = TransitionFixture.deadline_evidence(game, first_night_elapsed)
			if frame%100==99:await process_frame
		TransitionFixture.record_natural_receipt(game, evidence, "opening", first_night_elapsed, first_night_cutoff)
		check(game.phase=="draft" and game.hero.alive and game.beacon_hp>0.0,"Original fixed-seed105-second first-night policy survives before natural route "+route)
		if game.phase!="draft":return
		var first_deaths:=natural_deaths.duplicate(true); await press(KEY_1)
		var dawn_parts: int=game.scrap
		check(game.phase=="day" and game.phase_time==90.0 and dawn_parts>=95,"Natural first-night income reaches the untouched90-second day and can afford one95-part pierce tower")
		var tower: Dictionary=game.world.tower_pads[1]; var destination: Vector3=tower.position+Vector3(2,0,0)
		camera_at(tower.position); await mouse(game.camera.unproject_position(destination),MOUSE_BUTTON_RIGHT); await advance(4.0,false)
		check(Vector2(game.hero.position.x-destination.x,game.hero.position.z-destination.z).length()<.25,"Actual natural right click walks to the original tower interaction edge")
		await press(KEY_F); await press(KEY_J)
		check(tower.level==2 and game.specializations.branch(tower)=="piercing" and game.scrap==dawn_parts-95,"Actual natural F/J purchases50 upgrade and45 pierce using only the real earned balance")
		if route=="bounty":await select_gui(); await close_drawer()
		else:await press(KEY_9)
		var purchased_parts: int=game.scrap; var day_remaining: float=game.phase_time
		await advance(day_remaining+.001,false)
		check(game.phase=="night" and game.day_number==2 and game.phase_time==105.0,"The actual remaining original90-second day reaches a fresh105-second second night without clock extension")
		var promised_shellguards: int=int(game.night_plan[2].shellguard_count)
		check(promised_shellguards==(3 if route=="bounty" else 1),"Both natural routes enter their exact saved promised third-wave composition")
		var second_births: Array[Dictionary]=[]; var second_seen: Dictionary={}; var last_ledger: Dictionary={}
		var second_night_elapsed := 0.0
		var second_night_cutoff: Dictionary = {}
		# Bound actual residual combat; the production assault deadline is unchanged.
		for frame in ceili(240.0 / STEP):
			if game.phase!="night":break
			for value: Variant in game.enemies:
				if not is_instance_valid(value) or value.is_queued_for_deletion():continue
				var unit: BattleUnit=value as BattleUnit
				if second_seen.has(unit.get_instance_id()):continue
				second_seen[unit.get_instance_id()]=true
				second_births.append({"token":unit.get_instance_id(),"wave":int(unit.get_meta("wave_reward_id",-1)),"role":String(unit.get_meta("threat","")),"max_hp":unit.max_hp,"armor":unit.armor,"speed":unit.speed,"damage":unit.damage})
			natural_policy_frame()
			second_night_elapsed += STEP
			if second_night_cutoff.is_empty() and second_night_elapsed >= game.NIGHT_LENGTH:
				second_night_cutoff = TransitionFixture.deadline_evidence(game, second_night_elapsed)
			if not game.wave_rewards.snapshot(TARGET_REWARD_ID).is_empty():last_ledger=game.wave_rewards.snapshot(TARGET_REWARD_ID)
			if frame%100==99:await process_frame
		TransitionFixture.record_natural_receipt(game, evidence, "second", second_night_elapsed, second_night_cutoff)
		check(game.phase in ["draft","ended"],"Natural second-night route reaches real dawn or defeat through original waves and actual residual combat within240 simulated seconds")
		var bounty: Dictionary=game.bounty_snapshot(); var actual_shellguards:=0
		for row: Dictionary in second_births:
			if int(row.wave)==TARGET_REWARD_ID and String(row.role)=="shellguard":
				actual_shellguards+=1
				check(row.armor==60.0 and is_equal_approx(float(row.max_hp),(155.0+2*28)*1.15) and row.speed==2.7 and row.damage==22.0,"Natural route records unmodified actual甲壳 stats without stationary precision controls")
		if not last_ledger.is_empty():
			check(actual_shellguards==promised_shellguards,"A genuinely reached natural third wave produces every promised甲壳 actor")
		else:
			check(game.phase=="ended" and actual_shellguards==0,"A real earlier natural defeat is recorded without inventing target-wave births or requiring a bounty win")
		check(int(bounty.paid)==(48 if bounty.state=="won" else 0),"Natural route reports real completed or unpaid bounty without requiring scripted victory")
		if route=="free-countermeasure":check(int(bounty.paid)==0,"The conservative original free-countermeasure route cannot earn bounty")
		var record: Dictionary={"route":route,"seed":SEED,"opening_parts":90,"night1_seconds":105,"day_seconds":90,"night2_seconds":105,"night1_deaths":first_deaths,"dawn_parts":dawn_parts,"purchases":[{"kind":"tower-upgrade","cost":50},{"kind":"pierce-specialization","cost":45}],"after_purchases":purchased_parts,"free_countermeasure":"tower_barrage" if route=="free-countermeasure" else "","promised_third_wave_shellguards":promised_shellguards,"third_wave_shellguards":actual_shellguards,"second_births":second_births,"deaths":natural_deaths.duplicate(true),"hero_damage":natural_damage.duplicate(true),"final_phase":game.phase,"final_parts":game.scrap,"hero_hp":game.hero.hp,"hero_max_hp":game.hero.max_hp,"beacon_hp":game.beacon_hp,"beacon_loss":game.BEACON_MAX-game.beacon_hp,"target_ledger":last_ledger.duplicate(true),"bounty":bounty,"scope":"one fixed-seed scripted policy; no wallet supplementation, damage/HP/speed changes, clock extension or guaranteed completion; final wallet also includes ordinary/chain income and real spending"}
		(evidence.economy as Array).append(record)
		print("BOUNTY_NATURAL ",route," dawn_parts=",dawn_parts," after95=",purchased_parts," final_parts=",game.scrap," hero=",game.hero.hp," beacon=",game.beacon_hp," shellguards=",actual_shellguards," state=",bounty.state," bonus=",bounty.paid)
		if game.phase=="draft":await press(KEY_1)
		camera_at(Vector3(0,5,10)); await capture("bounty-natural-"+route)
	stage_returned=true

func run() -> void:
	var cases: Dictionary={"plan":saved_plan_matrix,"input":physical_selection_and_lock,"ledger":real_births_and_ledgers,"boundary":rejection_boundaries,"lifecycle":frozen_phases_and_retry,"hud":hud_and_default_coverage,"economy":natural_economic_comparison}
	var args:=OS.get_cmdline_user_args(); var selected: Array=cases.keys(); var index:=args.find("--case")
	if index>=0:
		if index+1<args.size():selected=[args[index+1]]
		else:check(false,"Missing bounty stage after --case"); selected=[]
	for name: String in selected:
		if not cases.has(name):check(false,"Unknown bounty stage "+name); break
		active_stage=name; stage_returned=false; print("BOUNTY_STAGE_BEGIN ",name)
		await (cases[name] as Callable).call()
		check(stage_returned,"Bounty stage "+name+" reaches its explicit full-body completion marker")
		print("BOUNTY_STAGE_END ",name," checks=",checks," failures=",failures.size())
		(evidence.completed as Array).append(name)
		if not failures.is_empty():break
	if index<0:check((evidence.completed as Array)==cases.keys(),"The complete bounty suite finishes every expected stage")
	await close_game()
	check(not is_instance_valid(game) and current_scene==null,"Final bounty scene cleanup completes before the suite result")
	var folder:=ProjectSettings.globalize_path(output_dir); DirAccess.make_dir_recursive_absolute(folder)
	var file:=FileAccess.open(folder.path_join("nightfall-bounty.json"),FileAccess.WRITE)
	check(file!=null,"Bounty structured evidence opens below local build")
	evidence.checks=checks; evidence.failures=failures
	if file!=null:file.store_string(JSON.stringify(evidence,"\t")); file.close()
	finished=true; print("BOUNTY_RESULT checks=",checks," failures=",failures.size())
	if index<0 and (evidence.completed as Array)==cases.keys() and failures.is_empty():print("NIGHTFALL_BOUNTY_OK checks=",checks)
	quit(0 if failures.is_empty() else 1)
