extends Node3D
## Playable outpost survival slice: scavenge at dusk, protect the beacon at night.
const Layout = preload("res://scripts/outpost_layout.gd")
const Catalog = preload("res://scripts/outpost_catalog.gd")
const ConstructionScript = preload("res://scripts/tower_construction.gd")
const RallyScript = preload("res://scripts/outpost_rally.gd")
const ControlGroupsScript = preload("res://scripts/outpost_control_groups.gd")
const RepairsScript = preload("res://scripts/outpost_repairs.gd")
const DemolitionScript = preload("res://scripts/outpost_demolition.gd")
const UnitScript = preload("res://scripts/unit.gd")
const HudScript = preload("res://scripts/nightfall_hud.gd")
const SquadScript = preload("res://scripts/outpost_squads.gd")
const LogisticsScript = preload("res://scripts/outpost_logistics.gd")
const WaveRewardsScript = preload("res://scripts/wave_rewards.gd")
const WaveWagerScript = preload("res://scripts/nightfall_wave_wager.gd")
const BountyScript = preload("res://scripts/nightfall_bounty.gd")
const ExplorationMotivationScript = preload("res://scripts/exploration_motivation.gd")
const SalvageDrawScript = preload("res://scripts/salvage_draw.gd")
const GrowthGuidanceScript = preload("res://scripts/growth_guidance.gd")
const SiegeBossScript = preload("res://scripts/nightfall_siege_boss.gd")
const LobberScript = preload("res://scripts/nightfall_lobber.gd")
const SummonerScript = preload("res://scripts/nightfall_summoner.gd")
const WarderScript = preload("res://scripts/nightfall_warder.gd")
const ShellguardScript = preload("res://scripts/nightfall_shellguard.gd")
const RunSessionScript = preload("res://scripts/run_session.gd")
const RunArchiveScript = preload("res://scripts/run_archive.gd")
const DAY_LENGTH := 90.0
const NIGHT_LENGTH := 105.0
const HERO_MOVE_SPEED := 8.4
const HERO_MOVE_SUBSTEP := 0.08
const HERO_MOVE_RETRY_FACTORS := [1.0, 0.5, 0.25]
const DAY_SQUAD_ALERT_RADIUS := 8.0
# The hero mesh is wider than its selection ring. Keep its centre slightly
# inside the raised ramp side walls so the cape and shoulders do not scrape the
# retaining geometry while the input still slides at full speed.
const HERO_RAMP_SIDE_CLEARANCE := 0.42
const HERO_RAMP_SAFE_START_Z := 7.45 + Layout.EXPANSION_OFFSET
const HERO_RAMP_SAFE_FULL_Z := 8.35 + Layout.EXPANSION_OFFSET
# Include the imported ramp's vertical side-wall thickness when resolving a
# cursor ray. A ray through the outer 3.9 m edge can otherwise fall onto the
# low ground behind the ramp and send a right-click target several metres
# backwards along the map.
const HERO_RAMP_CLICK_OUTER_EDGE := 3.95
# Keep the hero's visual footprint away from the raised courtyard retaining
# walls as well as the south ramp walls. The gameplay wall follows the shared castle layout;
# this centre-only margin prevents the cape and shoulders from scraping it.
const HERO_FORT_WALL_CLEARANCE := 0.34
const HERO_FORT_SAFE_EDGE := Layout.FORT_INNER - HERO_FORT_WALL_CLEARANCE
const CAMERA_FLAT_FOLLOW_RATE := 6.0
const CAMERA_HIGH_GROUND_FOLLOW_RATE := 11.5
const CAMERA_HIGH_GROUND_THRESHOLD := 1.0
const WAVES_PER_NIGHT := 5
const BEACON_MAX := 1200.0
const TOWER_COSTS := [60,50,75]
const GATE_TRAP_COST := 45
const GATE_TRAP_MAX := 3
const BARRICADE_COST := 65
const BARRICADE_MAX := 520.0
const COUNTERMEASURE_OPTIONS := [
	{"id":"light_guard", "title":"灯火整备", "summary":"首35秒噬灯压制降低60%", "threat":"light_eater"},
	{"id":"gate_reinforce", "title":"南门工事", "summary":"免费部署+260耐久路障", "threat":"breaker"},
	{"id":"tower_barrage", "title":"塔火力整备", "summary":"首28秒防御塔伤害提高35%", "threat":"sapper"},
]
const COUNTERMEASURE_LIGHT_SECONDS := 35.0
const COUNTERMEASURE_TOWER_SECONDS := 28.0
const COUNTERMEASURE_TOWER_MULTIPLIER := 1.35
const COUNTERMEASURE_GATE_BONUS := 260.0
const FOCUS_DURATION := 8.0
const FOCUS_COOLDOWN := 22.0
const COSTS := [35.0,45.0,30.0,85.0,0.0]
const COOLDOWNS := [4.5,9.0,6.5,28.0,38.0]
var WALK_BLOCKS: Array[Rect2] = Layout.wall_blocks()

var world: NightfallWorld
var hero: BattleUnit
var camera: Camera3D
var hud: Control
var effects: Node3D
var construction: Node3D
var rally: RefCounted
var control_groups = ControlGroupsScript.new()
var repairs = RepairsScript.new()
var construction_blocks: Array[Rect2] = []
var building_approach_cache: Dictionary = {}
var selection_dragging := false
var selection_start := Vector2.ZERO
var selection_end := Vector2.ZERO
var selection_additive := false
var phase := "draft"
var day_number := 1
var phase_time := NIGHT_LENGTH
var beacon_hp := BEACON_MAX
var beacon_alarm_time := 0.0
var beacon_alarm_damage := 0.0
var scrap := 90
var kills := 0
var attack_count := 0
var day_start_pending: bool=false
var run_mode: String="teaching"
var run_mode_locked := false
var selected_blueprint := ""
var encounters=preload("res://scripts/nightfall_encounters.gd").new()
var night_plan: Array[Dictionary]=[]
var countermeasure_selected := -1
var countermeasure_active := ""
var countermeasure_consumed := false
var countermeasure_light_time := 0.0
var countermeasure_tower_time := 0.0
var wave_rewards=WaveRewardsScript.new()
var wave_wager=WaveWagerScript.new()
var bounty=BountyScript.new()
var contracts=preload("res://scripts/day_contracts.gd").new()
var contract_marker: Node3D
var motivation_marker: Node3D
var districts=preload("res://scripts/outpost_districts.gd").new()
var squads: Node3D
var logistics: Node3D
var cores=preload("res://scripts/combat_cores.gd").new()
var specializations=preload("res://scripts/tower_specializations.gd").new()
var siege_boss: Node
var lobbers: Array[Node3D] = []
var summoners: Array[Node3D] = []
var warders: Array[Node3D] = []
var mana := 300.0
var max_mana := 300.0
var cooldowns: Array[float] = [0,0,0,0,0]
var enemies: Array[BattleUnit] = []
var run := RunBuild.new()
var archive = RunArchiveScript.new()
var archive_result: Dictionary = {}
var rng := RandomNumberGenerator.new()
var spawn_rng := RandomNumberGenerator.new()
var spawn_timer := 4.0
var wave_index := 0
var wave_warning_issued := false
var active_wave_reward_id := -1
var final_clearance_active := false
var pulse_timer := 3.0
var guardian_timer := 12.0
var aim := Vector3(8,0,0)
var pending_aim_screen := Vector2(-INF,-INF)
var aim_sample_pending := false
var ground_point_queries := 0
var hero_move_retries := 0
var move_goal := Vector3.ZERO
var hero_navigation: AStarGrid2D
var hero_path := PackedVector3Array()
var hero_keyboard_active := false
var notice := ""
var notice_time := 0.0
var skill_notice_key := ""
var skill_notice_until := 0.0
var victory := false
var ending_key := ""
var return_phase := "night"
var opening_night_pending := true
var paused_from := "day"
var delayed_blasts: Array[Dictionary] = []
var gate_trap_charges := 0
var gate_trap_cooldown := 0.0
var gate_trap_marks: Array[Node3D] = []
var gate_trap_light: OmniLight3D
var gate_barricade: Node3D
var gate_barricade_hp := 0.0
var gate_barricade_ring: MeshInstance3D
var light_eater_warning_issued := false
var focus_target: BattleUnit
var focus_ring: MeshInstance3D
var focus_time := 0.0
var focus_cooldown := 0.0
var expeditions: DayExpeditions
var generator_cells := 0
var survivors_rescued := 0
var discoveries: Node3D
var wildlife: Node3D
var exploration: Node
var salvage_draw = SalvageDrawScript.new()
var exploration_count := 0
var exploration_milestones := 0
var reward_toasts: Array[Dictionary] = []
var pickup_sound: AudioStreamWAV
var draft_reroll_ready_at := 0.0
var music: Node
var music_credits_open := false
var combat: Node
var deaths: Node3D
var skill_lights: Node3D
var hero_attack_target: BattleUnit
var hero_attack_delay := 0.0
var hero_attack_step := 0
var player_attack_resolving := false
var attack_chain := 0
var attack_chain_time := 0.0
var kill_chain := 0
var kill_chain_time := 0.0
var combat_milestone_time := 0.0
var combat_milestone_title := ""
var combat_milestone_detail := ""
var hero_damage_flash_time := 0.0
var hero_damage_flash_text := ""
var camera_follow := Vector3.ZERO
var quitting := false
var restart_pending := false
var shutting_down := false
const SALVAGE_REFRESH := 55.0

func _ready() -> void:
	get_tree().auto_accept_quit=false
	# Headless production tests must never mutate the developer's profile. The
	# exported game and normal Godot play sessions keep persistence enabled; the
	# archive test injects its own temporary path explicitly.
	archive.enabled = DisplayServer.get_name() != "headless"
	var next_run: Dictionary=RunSessionScript.consume_request(get_tree())
	if not next_run.is_empty():
		run=RunBuild.new(int(next_run.seed))
		run_mode=String(next_run.mode)
	rng.seed=RunSessionScript.stream_seed(run.seed_value,"combat")
	spawn_rng.seed=RunSessionScript.stream_seed(run.seed_value,"spawns")
	world=NightfallWorld.new();add_child(world);world.build()
	build_hero_navigation()
	effects=Node3D.new();add_child(effects)
	create_gate_trap_visuals()
	create_gate_barricade()
	hero=UnitScript.new() as BattleUnit;add_child(hero)
	hero.position=Vector3(0,NightfallWorld.FORT_HEIGHT,3.1);hero.setup("hero",0)
	hero.speed=HERO_MOVE_SPEED
	hero.title="余烬守望者"
	hero.defeated.connect(_on_hero_defeated)
	hero.damaged.connect(_on_hero_damaged)
	hero.damage_confirmed.connect(_on_hero_damage_confirmed)
	cores.setup(self)
	hero.shield_absorbed.connect(cores.absorbed)
	move_goal=hero.position
	camera=Camera3D.new();add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=38
	# Gameplay never approaches this camera; avoid wasting depth precision at .05m.
	camera.near=.3
	camera.far=130
	camera.position=hero.position+Vector3(0,25,29)
	camera.look_at(hero.position)
	camera.current=true
	camera_follow=camera.position
	var layer:=CanvasLayer.new();add_child(layer)
	hud=HudScript.new();hud.game=self;layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	expeditions=DayExpeditions.new();add_child(expeditions);expeditions.setup(self)
	squads=SquadScript.new();add_child(squads);squads.setup(self,true)
	discoveries=load("res://scripts/wild_discoveries.gd").new();add_child(discoveries);discoveries.setup(self,run.seed_value)
	wildlife=load("res://scripts/neutral_wildlife.gd").new();add_child(wildlife);wildlife.setup(self,run.seed_value)
	exploration=ExplorationMotivationScript.new();add_child(exploration);exploration.setup(self,run.seed_value)
	salvage_draw.setup(self,run.seed_value)
	add_child(contracts);contracts.setup(self,run.seed_value)
	contracts.target_started.connect(trigger_contract_risk)
	districts.setup(self)
	construction=ConstructionScript.new();construction.setup(self)
	squads.set_health_multiplier(districts.squad_health_multiplier())
	for item in world.salvage:item.respawn=0.0
	prepare_opening_defenses()
	refresh_construction_navigation()
	logistics=LogisticsScript.new();logistics.setup(self)
	rally=RallyScript.new();rally.setup(self)
	control_groups.setup(self)
	repairs.setup(self)
	pickup_sound=make_pickup_sound()
	world.night_mix=1.0;world.set_night(true)
	run.grant("守夜者的第一段记忆")
	open_draft()
	notify("黑夜中的第一束灯火 · 选择能力，守住南门",6)
	music=load("res://scripts/music_director.gd").new()
	music.name="MusicDirector";add_child(music)
	music.update_game(self,0.0)
	combat=load("res://scripts/combat_feedback.gd").new()
	combat.name="CombatFeedback";add_child(combat);combat.setup(self)
	deaths=load("res://scripts/death_effects.gd").new()
	deaths.name="DeathEffects";add_child(deaths);deaths.setup(self)
	skill_lights=load("res://scripts/skill_lighting.gd").new()
	skill_lights.name="SkillLighting";add_child(skill_lights);skill_lights.setup(self)

func prepare_opening_defenses() -> void:
	for index in [0,1]:
		var pad: Dictionary=world.tower_pads[index]
		pad.turret=world.place("res://assets/models/auto_turret.glb",pad.position,1.0,0)
		pad.level=1;pad.max_hp=280.0;pad.hp=280.0
		pad["paid_investment"]=0
		pad["free_built"]=true
		pad.damage_ring=BattleVisuals.ring(world,pad.position+Vector3(0,.12,0),1.26,Color("d75f58"),.06)
		pad.damage_ring.visible=false
	gate_trap_charges=1
	show_gate_trap_charges()

func _process(delta: float) -> void:
	flush_pending_aim()
	if construction:construction.tick(delta)
	if phase=="day" or phase=="night":simulate(delta)
	if phase in ["day","night"]:
		update_beacon_alarm(delta)
		hero_damage_flash_time=maxf(0.0,hero_damage_flash_time-delta)
	for i in range(reward_toasts.size()-1,-1,-1):
		reward_toasts[i].time-=delta
		if reward_toasts[i].time<=0:reward_toasts.remove_at(i)
	if notice_time>0:notice_time=maxf(0,notice_time-delta)
	if is_instance_valid(hero):
		world.follow_ashfall(hero.position)
		var target:=hero.position+Vector3(0,25,29)
		# Keep the fixed camera direction and a deliberate glide on the outer
		# ground. Once the hero reaches the raised outpost, use a faster
		# horizontal response as well as the existing fast vertical response.
		# The old six-per-second horizontal response left the camera about 1.4 m
		# behind a moving hero on the high ground, which made smooth ramp travel
		# look like a terrain snag. The camera still eases rather than snapping.
		var follow_rate:=CAMERA_HIGH_GROUND_FOLLOW_RATE if hero.position.y>=CAMERA_HIGH_GROUND_THRESHOLD else CAMERA_FLAT_FOLLOW_RATE
		var horizontal_follow:=1.0-exp(-delta*follow_rate)
		var vertical_follow:=1.0-exp(-delta*18.0)
		camera_follow.x=lerpf(camera_follow.x,target.x,horizontal_follow)
		camera_follow.y=lerpf(camera_follow.y,target.y,vertical_follow)
		camera_follow.z=lerpf(camera_follow.z,target.z,horizontal_follow)
		if combat:combat.tick(delta)
		camera.position=camera_follow+(combat.camera_offset() if combat else Vector3.ZERO)
	if hud:hud.queue_redraw()
	if music:music.update_game(self,delta)
	if deaths:deaths.tick(delta,phase)
	if skill_lights:skill_lights.tick(delta,phase)
	if rally:rally.tick(delta)

func simulate(delta: float) -> void:
	if phase!="day" and phase!="night":return
	# Advance route timers once, before speed is read and before this frame
	# can grant a fresh bonus through a completed discovery interaction.
	if exploration:exploration.tick(delta)
	cores.advance(delta)
	specializations.advance(delta)
	phase_time-=delta
	if phase=="night":
		if phase_time<=0.0:bounty.expire()
		countermeasure_light_time=maxf(0.0,countermeasure_light_time-delta)
		countermeasure_tower_time=maxf(0.0,countermeasure_tower_time-delta)
	update_combat_chains(delta)
	update_focus(delta)
	for i in cooldowns.size():cooldowns[i]=maxf(0,cooldowns[i]-delta)
	mana=minf(max_mana,mana+delta*(8.0+float(run.stats.mana_regen)))
	hero.hp=minf(hero.max_hp,hero.hp+(2.0+float(run.stats.regen)+districts.guard_regen(hero.position))*delta)
	if run.school_count(2)>=6:
		guardian_timer-=delta
		if guardian_timer<=0:
			hero.shield=maxf(hero.shield,hero.max_hp*.12*float(run.stats.shield))
			hero.shield_time=5.0
			guardian_timer=12.0
	for i in range(delayed_blasts.size()-1,-1,-1):
		delayed_blasts[i].delay-=delta
		if delayed_blasts[i].delay<=0:
			var blast: Dictionary=delayed_blasts[i]
			hit_area(blast.position,blast.radius,blast.damage)
			BattleVisuals.burst(effects,blast.position,blast.radius,Color("efb179"),.42)
			if skill_lights:skill_lights.emit_skill(3,blast.position,Vector3.RIGHT,Vector3.INF,blast.radius)
			delayed_blasts.remove_at(i)
	hero.speed=HERO_MOVE_SPEED+float(run.stats.speed)+(exploration.speed_bonus_value() if exploration else 0.0)
	move_hero(delta)
	hero.tick(delta)
	update_hero_attack(delta)
	if phase!="day" and phase!="night":return
	if logistics:logistics.advance(delta)
	if squads:
		squads.set_health_multiplier(districts.squad_health_multiplier())
		squads.advance(delta)
	districts.tick(delta)
	repairs.tick(delta)
	var boss_action_handled:=false
	if phase=="night" and is_instance_valid(siege_boss):
		boss_action_handled=siege_boss.advance(delta)
		if phase!="day" and phase!="night":return
	if phase=="day" and not lobbers.is_empty():clear_lobbers()
	if phase=="day" and not summoners.is_empty():clear_summoners()
	if phase=="day" and not warders.is_empty():clear_warders()
	# A committed projectile outlives a defeated thrower. Advance controllers
	# once even when that host has already left the living enemy list.
	var lobber_actions: Dictionary={}
	for index in range(lobbers.size()-1,-1,-1):
		var lobber: Node3D=lobbers[index]
		if not is_instance_valid(lobber):
			lobbers.remove_at(index)
			continue
		var source_value: Variant=lobber.get("host")
		var source: BattleUnit=null
		if is_instance_valid(source_value):source=source_value as BattleUnit
		var source_id: int=source.get_instance_id() if is_instance_valid(source) else -1
		var handled: bool=lobber.advance(delta)
		if phase not in ["day","night"]:return
		if source_id>=0:lobber_actions[source_id]=handled
		var state: String=String(lobber.snapshot().get("phase","idle"))
		if (not is_instance_valid(source) or not source.alive) and state not in ["flight","impact"]:
			lobber.clear()
			lobber.queue_free()
			lobbers.remove_at(index)
	var summoner_actions: Dictionary={}
	for index in range(summoners.size()-1,-1,-1):
		var summoner: Node3D=summoners[index]
		if not is_instance_valid(summoner):
			summoners.remove_at(index)
			continue
		var source_value: Variant=summoner.get("host")
		var source: BattleUnit=null
		if is_instance_valid(source_value):source=source_value as BattleUnit
		if not is_instance_valid(source) or source.is_queued_for_deletion() or not source.alive:
			summoner.clear()
			summoner.queue_free()
			summoners.remove_at(index)
			continue
		summoner_actions[source.get_instance_id()]=summoner.advance(delta)
		if phase not in ["day","night"]:return
	var warder_actions:=pending_warder_actions()
	for i in world.gate_light_drain.size():world.gate_light_drain[i]=0.0
	for i in range(enemies.size()-1,-1,-1):
		var creature:=enemies[i]
		if not is_instance_valid(creature) or not creature.alive:
			enemies.remove_at(i)
			continue
		creature.tick(delta)
		if discoveries.cache_guards.owns(creature):
			discoveries.cache_guards.advance(creature,delta)
			continue
		if creature.get_meta("siege_boss",false) and boss_action_handled:
			continue
		if creature.get_meta("threat","")=="lobber" and bool(lobber_actions.get(creature.get_instance_id(),false)):
			continue
		if bool(summoner_actions.get(creature.get_instance_id(),false)):continue
		if bool(warder_actions.get(creature.get_instance_id(),false)):continue
		if squads and squads.intercept_enemy(creature,delta):
			continue
		update_creature(creature,delta)
		if creature.get_meta("threat","")=="light_eater":
			var eater:=creature.get_node_or_null("LightEater") as NightLightEater
			if eater:
				eater.tick(delta)
				for lamp_index in world.gate_lights.size():
					world.gate_light_drain[lamp_index]=maxf(world.gate_light_drain[lamp_index],eater.drain_at(world.gate_lights[lamp_index].global_position))
	# Every recipient has ticked before granting a new shield. Its four seconds
	# start here, independent of the source/recipient order in the enemy roster.
	advance_warders(delta)
	if phase not in ["day","night"]:return
	if countermeasure_light_time>0.0:
		for lamp_index in world.gate_light_drain.size():world.gate_light_drain[lamp_index]*=.4
	var gate_drain:=maxf(world.gate_light_drain[0],world.gate_light_drain[1])
	if gate_drain>.48 and not light_eater_warning_issued:
		light_eater_warning_issued=true
		notify("噬灯蛾正在吞噬南门灯光 · 击杀可恢复照明",4)
	elif gate_drain<.1:light_eater_warning_issued=false
	update_towers(delta)
	update_gate_trap(delta)
	auto_attack()
	expeditions.tick(delta)
	update_day_contracts(delta)
	discoveries.tick(delta)
	update_exploration_guidance()
	wildlife.tick(delta)
	update_salvage_refresh(delta)
	if phase=="night":
		if not final_clearance_active:
			if wave_index<WAVES_PER_NIGHT:
				spawn_timer=maxf(0,float(night_plan[wave_index].time)-(NIGHT_LENGTH-phase_time))
				if spawn_timer<=4.0 and not wave_warning_issued:
					wave_warning_issued=true
					world.wave_warning=true
					notify("南门警报 · 第 %d 波即将到达" % (wave_index+1),3)
				while wave_index<night_plan.size() and float(night_plan[wave_index].time)<=NIGHT_LENGTH-phase_time:
					spawn_night_wave()
		pulse_timer-=delta
		if pulse_timer<=0:
			beacon_pulse()
			pulse_timer=beacon_pulse_interval()
	if phase=="night" and final_clearance_active and not _has_living_night_enemies():
		finish_night()
		return
	if phase_time<=0 and (phase=="day" or phase=="night"):
		if phase=="day":start_night()
		elif day_number>=max_nights():
			begin_final_clearance()
			if not _has_living_night_enemies():finish_night()
		else:finish_night()

func start_night() -> void:
	salvage_draw.on_night()
	clear_lobbers()
	clear_summoners()
	clear_warders()
	cores.clear()
	specializations.reset_effects()
	cancel_hero_attack()
	attack_chain=0;attack_chain_time=0.0;kill_chain=0;kill_chain_time=0.0
	var withdrew_expedition:=expeditions.on_night()
	if squads:squads.on_night()
	if exploration:exploration.begin_night()
	contracts.on_night()
	settle_contract_reward()
	if is_instance_valid(contract_marker):contract_marker.queue_free()
	contract_marker=null
	phase="night";phase_time=NIGHT_LENGTH
	if logistics:logistics.on_night()
	districts.begin_night(day_number)
	if night_plan.is_empty() or int(night_plan[0].get("night",day_number))!=day_number:
		prepare_next_night_plan(false)
	_lock_wave_wager_for_night()
	if String(bounty.snapshot().state)=="selected":
		if not bounty.lock(night_plan,(day_number-1)*WAVES_PER_NIGHT+2):
			night_plan=encounters.make_plan(run_mode,day_number,run.seed_value,cleansed_nests())
			_settle_wave_wager_loss("plan_changed")
	activate_countermeasure()
	wave_rewards.reset()
	active_wave_reward_id=-1
	final_clearance_active=false
	if is_instance_valid(siege_boss):
		siege_boss.clear()
		siege_boss.queue_free()
		siege_boss=null
	spawn_timer=night_spawn_interval();pulse_timer=2.0
	wave_index=0;wave_warning_issued=false
	world.set_night(true)
	world.wave_warning=false
	discoveries.cache_guards.on_night()
	clear_contract_hunters()
	for creature in enemies:
		if is_instance_valid(creature):creature.queue_free()
	enemies.clear()
	BattleVisuals.burst(effects,Vector3(0,0,Layout.RAMP_END),4.5,Color("b85b4a"),.7)
	var night_lines:=["许弦：灯塔的回声太响了。夜行体正从南门涌来。",
		"林舟：快的先到，破城体跟在后面。通信塔会帮守塔锁敌。",
		"闻澈：守住最后一夜，我告诉你地下那座设施在哪。"]
	notify("黑夜降临 · 未完成远征撤离，明日可重试；立刻回防南门" if withdrew_expedition else night_lines[mini(day_number-1,2)],6)
	spawn_night_wave()

func spawn_night_wave() -> void:
	if phase!="night" or wave_index>=WAVES_PER_NIGHT:return
	var entry: Dictionary=night_plan[wave_index]
	var reward_id: int=(day_number-1)*WAVES_PER_NIGHT+wave_index
	var standard_rewards: bool=run_mode!="teaching"
	if standard_rewards:wave_rewards.begin_wave(reward_id,WaveRewardsScript.DEFAULT_BUDGET)
	active_wave_reward_id=reward_id if standard_rewards else -1
	wave_index+=1
	for role: String in entry.roles:
		var creature: BattleUnit=spawn_creature(true,role)
		if standard_rewards:wave_rewards.register_enemy(reward_id,creature)
	if bool(entry.get("boss_entry",false)):
		var boss: BattleUnit=spawn_creature(true,"breaker")
		siege_boss=SiegeBossScript.new()
		siege_boss.name="SiegeBossController"
		siege_boss.setup(self,boss)
		if standard_rewards:wave_rewards.register_enemy(reward_id,boss)
	if standard_rewards:wave_rewards.seal_wave(reward_id)
	spawn_timer=maxf(0,float(night_plan[wave_index].time)-(NIGHT_LENGTH-phase_time)) if wave_index<night_plan.size() else 0.0
	wave_warning_issued=false
	world.wave_warning=false
	BattleVisuals.burst(effects,Vector3(0,0,Layout.RAMP_END),3.2,Color("dc7957"),.5)
	if wave_index>1:notify("第 %d/%d 波 · %s · %d 只" % [wave_index,WAVES_PER_NIGHT,entry.title,entry.count],3)
	if bool(entry.get("boss_entry",false)):
		notify("末夜首领已抵达 · 先打断蓄力，再清理残敌",4)

func _wave_wager_signature(plan: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for entry: Dictionary in plan:
		var roles: Array = entry.get("roles", [])
		parts.append("%d@%.2f:%s:%d:%s:%d" % [
			int(entry.get("index", -1)), float(entry.get("time", 0.0)),
			"|".join(roles), int(entry.get("count", 0)),
			"1" if bool(entry.get("boss_entry", false)) else "0",
			int(entry.get("night", day_number)),
		])
	return "night-plan:%d:%s" % [day_number, ";".join(parts)]

func wave_wager_target_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if run_mode == "teaching" or night_plan.is_empty():
		return result
	var signature := _wave_wager_signature(night_plan)
	for index in night_plan.size():
		var entry: Dictionary = night_plan[index]
		var reward_id: int = (day_number - 1) * WAVES_PER_NIGHT + index
		result.append({
			"index": index,
			"day": day_number,
			"night": day_number,
			"title": String(entry.get("title", "第%d波" % (index + 1))),
			"time": float(entry.get("time", 0.0)),
			"target_reward_id": reward_id,
			"reward_id": reward_id,
			"target_count": int(entry.get("count", 0)),
			"count": int(entry.get("count", 0)),
			"plan_signature": signature,
		})
	return result

func _refresh_wave_wager_offer() -> void:
	if run_mode == "teaching" or night_plan.is_empty():
		wave_wager.clear()
		return
	var options := wave_wager_target_options()
	if options.is_empty():
		wave_wager.clear()
		return
	var signature := String(options[0].plan_signature)
	var current: Dictionary = wave_wager.snapshot()
	var current_state := String(current.get("state", "idle"))
	if int(current.get("night_id", -1)) == day_number:
		if String(current.get("plan_signature", "")) == signature:
			return
		if current_state == "locked":
			wave_wager.expire("plan_changed")
			return
		if current_state in ["won", "lost", "expired"]:
			return
		wave_wager.clear()
	elif int(current.get("night_id", -1)) > day_number:
		return
	var first: Dictionary = options[0]
	wave_wager.begin_night(day_number, signature, int(first.target_reward_id), int(first.target_count))

func wave_wager_snapshot() -> Dictionary:
	var result: Dictionary = wave_wager.snapshot()
	var enabled := run_mode != "teaching" and not night_plan.is_empty()
	result["enabled"] = enabled
	result["available"] = enabled and phase == "day" and String(result.get("state", "")) in ["offered", "selected"] and not quitting and not restart_pending
	result["target_index"] = int(result.get("target_reward_id", -1)) - (day_number - 1) * WAVES_PER_NIGHT
	result["targets"] = wave_wager_target_options()
	return result

func select_wave_wager_target(index: int) -> bool:
	if phase != "day" or run_mode == "teaching" or quitting or restart_pending:
		return false
	var options := wave_wager_target_options()
	if index < 0 or index >= options.size():
		return false
	var state := String(wave_wager.snapshot().get("state", "idle"))
	if state not in ["offered", "selected"]:
		return false
	if state == "selected":
		notify("风险档已选 · 天黑前不能更换目标", 2)
		return false
	var target: Dictionary = options[index]
	var current: Dictionary = wave_wager.snapshot()
	if int(current.get("target_reward_id", -1)) == int(target.target_reward_id):
		return true
	wave_wager.clear()
	return wave_wager.begin_night(day_number, String(target.plan_signature), int(target.target_reward_id), int(target.target_count))

func place_wave_wager(index: int) -> Dictionary:
	if phase != "day" or run_mode == "teaching" or quitting or restart_pending:
		return {"ok": false, "reason": "not_available", "wallet_delta": 0}
	var result: Dictionary = wave_wager.place_risk(index, day_number, wave_wager_target_options(), scrap)
	if bool(result.get("ok", false)):
		notify("夜战押注 · %s档已锁定目标 · 天黑时扣除%d零件" % [String(result.get("tier_id", "")), int(result.get("stake", 0))], 3)
	else:
		notify("夜战押注 · " + String(result.get("reason", "不可用")), 2)
	return result

func _lock_wave_wager_for_night() -> void:
	var state: Dictionary = wave_wager.snapshot()
	var wager_state := String(state.get("state", ""))
	if wager_state == "offered":
		wave_wager.expire("not_selected")
		return
	if wager_state != "selected":
		return
	var result: Dictionary = wave_wager.lock(String(state.get("plan_signature", "")), int(state.get("target_reward_id", -1)), int(state.get("target_count", 0)), scrap)
	if bool(result.get("ok", false)):
		scrap += int(result.get("wallet_delta", 0))
		notify("夜战押注已入场 · 风险档投入%d零件 · 清波派彩%d" % [int(result.get("stake", 0)), int(result.get("reward", 0))], 4)
	else:
		wave_wager.expire(String(result.get("reason", "lock_failed")))
		notify("夜战押注未能入场 · " + String(result.get("reason", "不可用")), 3)

func _settle_wave_wager_loss(reason: String) -> void:
	var state: Dictionary = wave_wager.snapshot()
	if String(state.get("state", "")) != "locked":
		return
	wave_wager.settle_loss(String(state.get("plan_signature", "")), int(state.get("target_reward_id", -1)), int(state.get("target_count", 0)), reason)

func register_active_wave_enemy(enemy: Variant) -> bool:
	if run_mode=="teaching" or active_wave_reward_id<0 or not is_instance_valid(enemy):return false
	if enemy.get_meta("summoned_reinforcement",false):return false
	var registered:=wave_rewards.register_enemy(active_wave_reward_id,enemy)
	if registered:wave_rewards.seal_wave(active_wave_reward_id)
	return registered

func _has_living_night_enemies() -> bool:
	for lobber: Node3D in lobbers:
		if is_instance_valid(lobber) and String(lobber.snapshot().get("phase",""))=="flight":return true
	for creature in enemies:
		if is_instance_valid(creature) and not creature.is_queued_for_deletion() and creature.alive:return true
	return false

func lobber_warning_snapshot() -> Array[Dictionary]:
	var warnings: Array[Dictionary]=[]
	for lobber: Node3D in lobbers:
		if not is_instance_valid(lobber):continue
		var warning: Dictionary=lobber.snapshot()
		if String(warning.get("phase","")) in ["windup","flight"]:warnings.append(warning)
	return warnings

func clear_lobbers() -> void:
	for lobber: Node3D in lobbers:
		if not is_instance_valid(lobber):continue
		lobber.clear()
		lobber.queue_free()
	lobbers.clear()

func summoner_warning_snapshot() -> Array[Dictionary]:
	var warnings: Array[Dictionary]=[]
	for summoner: Node3D in summoners:
		if not is_instance_valid(summoner) or summoner.is_queued_for_deletion():continue
		var warning: Dictionary=summoner.snapshot()
		var source: Variant=warning.get("source")
		if is_instance_valid(source) and source.alive and not source.is_queued_for_deletion() and String(warning.get("phase",""))=="windup":warnings.append(warning)
	return warnings

func clear_summoners() -> void:
	for summoner: Node3D in summoners:
		if not is_instance_valid(summoner):continue
		summoner.clear()
		summoner.queue_free()
	summoners.clear()

func warder_warning_snapshot() -> Array[Dictionary]:
	var warnings: Array[Dictionary]=[]
	for value: Variant in warders:
		if not is_instance_valid(value) or value.is_queued_for_deletion():continue
		var warning: Dictionary=value.snapshot()
		var source: Variant=warning.get("source")
		if is_instance_valid(source) and not source.is_queued_for_deletion() and source.alive and source in enemies and String(warning.get("phase",""))=="windup":warnings.append(warning)
	return warnings

func pending_warder_actions() -> Dictionary:
	var handled: Dictionary={}
	for value: Variant in warders:
		if not is_instance_valid(value) or value.is_queued_for_deletion():continue
		var state: Dictionary=value.snapshot()
		var source: Variant=state.get("source")
		if not is_instance_valid(source) or source.is_queued_for_deletion() or not source.alive or source not in enemies:continue
		handled[source.get_instance_id()]=String(state.phase) in ["windup","committing"] or (bool(source.get_meta("warder_active",false)) and specializations.movement_multiplier(source)<.9999)
	return handled

func advance_warders(delta: float) -> void:
	for value: Variant in warders.duplicate():
		if not is_instance_valid(value):
			warders.erase(value)
			continue
		if value.is_queued_for_deletion() or value not in warders:continue
		var source: Variant=value.get("host")
		if not is_instance_valid(source) or source.is_queued_for_deletion() or not source.alive or source not in enemies:
			value.clear();value.queue_free();warders.erase(value)
			continue
		value.advance(delta)
		# A world callback may synchronously clear/setup the module or end a run.
		if phase not in ["day","night"]:return

func clear_warders() -> void:
	for value: Variant in warders.duplicate():
		if not is_instance_valid(value):continue
		value.clear()
		if not value.is_queued_for_deletion():value.queue_free()
	warders.clear()

func spawn_summoned_reinforcement(source: BattleUnit, point: Vector3) -> BattleUnit:
	# The cast controller owns timing; the original source instance owns its
	# lifetime budget. Recreating a controller cannot replenish that budget.
	if phase!="night" or not is_instance_valid(source) or not source.alive or source.is_queued_for_deletion():return null
	if not enemies.has(source) or source.get_meta("threat","")!="summoner" or source.get_meta("summoned_reinforcement",false):return null
	if int(source.get_meta("summoner_spawned",0))>=2 or specializations.movement_multiplier(source)<.9999:return null
	var controller: Node3D=null
	for candidate: Node3D in summoners:
		if is_instance_valid(candidate) and not candidate.is_queued_for_deletion() and candidate.get("host")==source:
			controller=candidate
			break
	if controller==null:return null
	var cast: Dictionary=controller.snapshot()
	if String(cast.get("phase",""))!="committing" or float(cast.get("remaining",1.0))>0.0:return null
	var entry:=Vector3(clampf(float(source.get_meta("gate_lane",0.0)),-1.15,1.15),0,Layout.RAMP_END+3.0)
	entry.y=outpost_height(entry)
	if not point.is_finite() or point.distance_to(entry)>.001 or source.position.z<Layout.RAMP_END+.5:return null
	if Vector2(source.position.x-entry.x,source.position.z-entry.z).length()>14.0:return null
	var approach:=Vector3(entry.x,0,Layout.RAMP_END+.25)
	approach.y=outpost_height(approach)
	if not outpost_walkable(entry) or not can_traverse(entry,approach):return null
	var reinforcement: BattleUnit=spawn_creature(true,"runner")
	reinforcement.position=entry
	reinforcement.title="应召疾行体"
	reinforcement.set_meta("summoned_reinforcement",true)
	reinforcement.set_meta("summoner_token",source.get_instance_id())
	source.set_meta("summoner_spawned",int(source.get_meta("summoner_spawned",0))+1)
	return reinforcement

func begin_final_clearance() -> void:
	if final_clearance_active or phase!="night":return
	final_clearance_active=true
	phase_time=0.0
	wave_index=WAVES_PER_NIGHT
	wave_warning_issued=false
	spawn_timer=0.0
	world.wave_warning=false
	notify("末夜清场 · 首领与残敌仍在，清除全部威胁后才能迎来日出",5)

func wave_preview() -> Dictionary:
	return encounters.next_preview(night_plan,wave_index,NIGHT_LENGTH-phase_time)

func boss_snapshot() -> Dictionary:
	if not is_instance_valid(siege_boss) or not siege_boss.has_method("snapshot"):
		return {}
	return siege_boss.snapshot()

func initial_night_pack() -> int:
	return maxi(5,8+day_number*3-cleansed_nests()*2)

func night_spawn_interval() -> float:
	return 19.0-float(day_number)*.5+float(cleansed_nests())*1.4

func beacon_pulse_interval() -> float:
	return maxf(2.5,3.1-float(generator_cells)*.2)

func beacon_repair_cost() -> int:
	return maxi(14,20-survivors_rescued*3)

func finish_night() -> void:
	if phase=="ended":return
	var was_final_clearance: bool=final_clearance_active
	_settle_wave_wager_loss("night_end")
	bounty.expire()
	clear_lobbers()
	clear_summoners()
	clear_warders()
	clear_exploration_marker()
	cores.clear()
	specializations.reset_effects()
	cancel_hero_attack()
	attack_chain=0;attack_chain_time=0.0;kill_chain=0;kill_chain_time=0.0
	world.wave_warning=false
	clear_gate_barricade()
	clear_contract_hunters()
	final_clearance_active=false
	if is_instance_valid(siege_boss):
		siege_boss.clear()
		siege_boss.queue_free()
		siege_boss=null
	if squads:squads.on_day()
	if day_number>=max_nights():
		discoveries.cache_guards.clear()
		salvage_draw.clear()
		control_groups.clear()
		repairs.clear()
		if rally:rally.clear()
		if logistics:logistics.clear()
		if squads:squads.clear()
		for creature in enemies:
			if is_instance_valid(creature):creature.queue_free()
		enemies.clear()
		victory=true;phase="ended";world.set_night(false)
		ending_key="signal" if remaining_nests()==0 else "hold"
		if was_final_clearance:
			archive_result=archive.record_victory({
				"victory": true,
				"seed": run.seed_value,
				"mode": run_mode,
				"ending_key": ending_key,
				"day_number": day_number,
				"kills": kills,
				"cleansed_nests": cleansed_nests(),
				"survivors_rescued": survivors_rescued,
			})
		if ending_key=="signal":
			world.beacon_light.light_color=Color("96d9d6")
			BattleVisuals.burst(effects,Vector3(0,NightfallWorld.FORT_HEIGHT,0),11.0,Color("8bd9d5"),.9)
			notify(("第四次日出" if max_nights()==3 else "第五次日出")+" · 三处夜巢封印，地下阵列坐标已显现",8)
		else:
			BattleVisuals.burst(effects,Vector3(0,NightfallWorld.FORT_HEIGHT,0),8.0,Color("e9aa65"),.8)
			notify(("灯火未灭 · " + ("三夜" if max_nights()==3 else "四夜") + "守望完成，荒原的夜巢仍在呼吸"),8)
		return
	day_number+=1
	phase="draft"
	return_phase="day"
	phase_time=DAY_LENGTH
	world.set_night(false)
	for item in world.salvage:
		item.collected=false
		item.respawn=0.0
		(item.node as Node3D).visible=true
	for creature in enemies:
		if is_instance_valid(creature):creature.queue_free()
	enemies.clear()
	for i in range(5+day_number):spawn_creature(false)
	spawn_nest_guards()
	run.grant("熬过第 %d 夜 · 选择新的守望能力" % (day_number-1))
	day_start_pending=true
	open_draft()

func begin_day() -> void:
	day_start_pending=false
	phase="day";phase_time=DAY_LENGTH
	if logistics:logistics.on_day()
	world.set_night(false)
	expeditions.on_day()
	if squads:squads.on_day()
	if exploration:exploration.begin_day(day_number)
	salvage_draw.begin_day()
	discoveries.cache_guards.begin_day()
	contracts.on_day()
	prepare_next_night_plan(true)
	_refresh_wave_wager_offer()
	spawn_timer=4
	var day_lines:=["许弦：废墟里还有能源芯和失联哨兵。带他们回家。",
		"林舟：启动发电机会惊醒潜伏体，先准备好再接通。",
		"许弦：最后一夜。救回哨兵，他们会协助修复灯塔。"]
	notify("白昼只有 90 秒 · " + day_lines[mini(day_number-1,2)],6)

func prepare_next_night_plan(reset_countermeasure: bool = false) -> bool:
	# The day forecast and the next night share this exact saved plan. Rebuilding
	# it after a nest is sealed only changes the public count reduction; the seed,
	# theme and specialist roles remain deterministic and visible to the player.
	night_plan=encounters.make_plan(run_mode,day_number,run.seed_value,cleansed_nests())
	if reset_countermeasure:
		bounty.offer(run_mode,day_number)
		countermeasure_selected=-1
		countermeasure_active=""
		countermeasure_consumed=false
		countermeasure_light_time=0.0
		countermeasure_tower_time=0.0
	if String(bounty.snapshot().state)=="selected":
		var selected_plan: Array[Dictionary]=encounters.with_bounty(night_plan)
		if selected_plan.is_empty():
			bounty.deselect()
			_refresh_wave_wager_offer()
			return true
		night_plan=selected_plan
	_refresh_wave_wager_offer()
	return false

func bounty_snapshot() -> Dictionary:
	var state: Dictionary=bounty.snapshot()
	var selectable: bool=String(state.state) in ["offered","selected"] and run_mode in ["standard","siege","echo"] and day_number==2
	var eligible: bool=phase=="day" and phase_time>0.0 and not quitting and not restart_pending and is_instance_valid(hero) and hero.alive and hero.hp>0.0 and beacon_hp>0.0
	# The saved plan already refreshes on nest changes. Reading the drawer must
	# not regenerate and deep-copy five waves every rendered frame.
	var capacity:=false
	if selectable and night_plan.size()>2:
		var entry: Dictionary=night_plan[2]
		capacity=String(entry.get("bounty_id",""))=="shellguard_pack" or (entry.roles as Array).count("basic")>=2
	state["available"]=selectable and eligible and capacity
	state["reason"]="第三波需有两名普通随从可替换" if selectable and not capacity else "仅第二夜白昼可选"
	if phase=="paused" and selectable:state.reason="暂停中，恢复后可选择"
	elif bool(state.available):state.reason="放弃免费反制 · 第三波增加两名甲壳卫"
	state["paid"]=BountyScript.REWARD if String(state.state)=="won" else 0
	var ledger: Dictionary=wave_rewards.snapshot((2-1)*WAVES_PER_NIGHT+2)
	state["kills"]=int(ledger.get("kills",0)) if String(state.state) in ["active","won","expired"] else 0
	state["count"]=int(ledger.get("count",0)) if String(state.state) in ["active","won","expired"] else 0
	return state

func select_bounty() -> bool:
	if not bool(bounty_snapshot().available):return false
	var baseline: Array[Dictionary]=encounters.make_plan(run_mode,day_number,run.seed_value,cleansed_nests())
	var selected_plan: Array[Dictionary]=encounters.with_bounty(baseline)
	if selected_plan.is_empty() or not bounty.select(baseline):return false
	night_plan=selected_plan
	_refresh_wave_wager_offer()
	countermeasure_selected=-1
	notify("已选甲壳悬赏 · 放弃免费反制，第三波清完额外+48零件",3)
	return true

func countermeasure_count() -> int:
	return COUNTERMEASURE_OPTIONS.size()

func countermeasure_title(index: int) -> String:
	if index<0 or index>=COUNTERMEASURE_OPTIONS.size():return "未选择"
	return String(COUNTERMEASURE_OPTIONS[index].title)

func countermeasure_summary(index: int) -> String:
	if index<0 or index>=COUNTERMEASURE_OPTIONS.size():return "白昼不选择则不获得额外加成"
	return String(COUNTERMEASURE_OPTIONS[index].summary)

func forecast_primary_threat_id() -> String:
	var counts: Dictionary={}
	for entry: Dictionary in night_plan:
		for role in entry.roles:
			var role_name:=String(role)
			if role_name=="basic":continue
			counts[role_name]=int(counts.get(role_name,0))+1
		if bool(entry.get("boss_entry",false)):
			counts["breaker"]=int(counts.get("breaker",0))+1
	var selected: String=""
	var best:=0
	for role in ["summoner","warder","light_eater","lobber","sapper","breaker","shellguard","runner"]:
		var amount:=int(counts.get(role,0))
		if amount>best:
			best=amount;selected=role
	return selected

func forecast_primary_threat() -> String:
	return {"summoner":"召潮者", "warder":"织壳者", "light_eater":"噬灯蛾", "lobber":"投蚀体", "sapper":"蚀塔体", "breaker":"破城体", "shellguard":"甲壳卫", "runner":"疾行体"}.get(forecast_primary_threat_id(),"基础夜行体")

func forecast_specialist_count() -> int:
	var total:=0
	for entry: Dictionary in night_plan:
		for role in entry.roles:
			if String(role)!="basic":total+=1
		if bool(entry.get("boss_entry",false)):total+=1
	return total

func countermeasure_recommended(index: int) -> bool:
	if index<0 or index>=COUNTERMEASURE_OPTIONS.size():return false
	var primary:=forecast_primary_threat_id()
	# The three orders cover all public specialist identities. Fast enemies use
	# the gate order because its free buffer buys the same recovery window as a
	# direct speed counter; a basic-only plan recommends tower fire by default.
	var recommended_index:=2
	match primary:
		"light_eater":recommended_index=0
		"breaker","runner":recommended_index=1
		"sapper","lobber","summoner","warder","shellguard":recommended_index=2
	return index==recommended_index

func select_countermeasure(index: int) -> bool:
	if phase!="day" or phase_time<=0.0 or quitting or restart_pending or index<0 or index>=COUNTERMEASURE_OPTIONS.size() or night_plan.is_empty():return false
	if String(bounty.snapshot().state)=="selected":
		bounty.deselect()
		night_plan=encounters.make_plan(run_mode,day_number,run.seed_value,cleansed_nests())
		_refresh_wave_wager_offer()
	countermeasure_selected=index
	notify("已选战前反制：%s · 天黑前可更换" % countermeasure_title(index),3)
	return true

func activate_countermeasure() -> void:
	if countermeasure_consumed:return
	countermeasure_consumed=true
	countermeasure_active=""
	countermeasure_light_time=0.0
	countermeasure_tower_time=0.0
	if countermeasure_selected<0 or countermeasure_selected>=COUNTERMEASURE_OPTIONS.size():return
	var id:=String(COUNTERMEASURE_OPTIONS[countermeasure_selected].id)
	countermeasure_active=id
	match id:
		"light_guard":
			countermeasure_light_time=COUNTERMEASURE_LIGHT_SECONDS
		"gate_reinforce":
			if gate_barricade_hp<=0.0:
				gate_barricade_hp=BARRICADE_MAX+COUNTERMEASURE_GATE_BONUS
				gate_barricade.visible=true;gate_barricade_ring.visible=true
				gate_barricade_ring.material_override.albedo_color=Color("e2a665")
				BattleVisuals.burst(effects,gate_barricade.position,2.7,Color("e2a665"),.45)
		"tower_barrage":
			countermeasure_tower_time=COUNTERMEASURE_TOWER_SECONDS
	notify("战前反制生效 · %s" % countermeasure_title(countermeasure_selected),4)

func max_nights() -> int:
	return 3 if run_mode=="teaching" else 4

func run_mode_title() -> String:
	return {"teaching":"三夜教学","siege":"四夜·铁潮","echo":"四夜·暗翼"}.get(run_mode,"三夜教学")

func run_mode_description() -> String:
	return {
		"teaching":"三夜入门 · 保留基础击杀奖励",
		"siege":"四夜标准 · 破城体与蚀塔体更集中",
		"echo":"四夜标准 · 噬灯蛾与疾行体交错"
	}.get(run_mode,"三夜入门 · 保留基础击杀奖励")

func select_run_mode(index: int) -> bool:
	if phase!="draft" or not opening_night_pending or run_mode_locked:return false
	var options: Array[String]=["teaching","siege","echo"]
	if index<0 or index>=options.size():return false
	run_mode=options[index]
	notify("本局模式：%s · 选择核心后锁定" % run_mode_title(),3)
	return true

func available_blueprints() -> Array[Dictionary]:
	var options: Array[Dictionary] = [{"id": "", "title": "无蓝图", "detail": "基础开局 · 不解锁额外建筑许可"}]
	if not is_instance_valid(archive) or not archive.has_method("unlocked_blueprints"): return options
	var catalog: Dictionary = archive.blueprint_catalog()
	for blueprint_id: String in archive.unlocked_blueprints():
		var definition: Dictionary = catalog.get(blueprint_id, {})
		if definition.is_empty(): continue
		options.append({"id": blueprint_id, "title": String(definition.get("title", blueprint_id)), "detail": String(definition.get("detail", "永久许可 · 需本局选择后可用"))})
	return options

func _blueprint_title(blueprint_id: String) -> String:
	if blueprint_id.is_empty(): return "无"
	for option: Dictionary in available_blueprints():
		if String(option.get("id", "")) == blueprint_id: return String(option.get("title", blueprint_id))
	return blueprint_id

func select_blueprint(blueprint_id: String) -> bool:
	if phase!="draft" or not opening_night_pending or run_mode_locked:return false
	var allowed := false
	for option: Dictionary in available_blueprints():
		if String(option.get("id", "")) == blueprint_id:
			allowed=true
			break
	if not allowed:return false
	selected_blueprint=blueprint_id
	notify("本局蓝图：%s · 只解锁付费建筑许可" % _blueprint_title(blueprint_id),3)
	if is_instance_valid(hud):hud.queue_redraw()
	return true

func select_bonus_route(index: int, serial: int, expected: Dictionary = {}) -> bool:
	if quitting or restart_pending or phase!="day" or phase_time<=0.0:return false
	# A displayed card must still refer to the same discovery when clicked.
	# Index/serial alone cannot detect a replaced dictionary with copied fields.
	if not expected.is_empty():
		if int(expected.get("index",-1))!=index or int(expected.get("serial",-1))!=serial:return false
		if not is_instance_valid(discoveries) or index<0 or index>=discoveries.items.size():return false
		var source: Dictionary=discoveries.items[index]
		if not is_same(source,expected.get("source",{})) or String(source.get("kind",""))!=String(expected.get("kind","")):return false
	if not is_instance_valid(contracts) or not contracts.select_bonus_route(index,serial):return false
	if is_instance_valid(hud):
		hud.refresh_contract_budgets()
		hud.queue_redraw()
	notify("已选择追加路线 · 5确认后锁定目标",2)
	return true

func choose_bonus_route(action: int) -> bool:
	if quitting or restart_pending or phase!="day" or phase_time<=0.0:return false
	var accepted: bool=is_instance_valid(contracts) and contracts.choose_bonus(action)
	if is_instance_valid(hud):
		hud.refresh_contract_budgets()
		hud.queue_redraw()
	if accepted:
		notify("立即返家领取主委托保底" if action==0 else "追加目标已锁定 · 完成后回灯塔领额外奖励",3)
	else:
		notify("所选追加路线不可用 · 请在F3重选或4返家" if action==1 else "追加选择不可用",2)
	return accepted

func contract_goal() -> Vector3:
	if contracts.status in ["bonus_offer", "returning"]:
		return Vector3(0,NightfallWorld.FORT_HEIGHT,3.1)
	if contracts.status=="bonus_active":
		var bonus_source:=contracts.bonus_source()
		return bonus_source.position if not bonus_source.is_empty() else Vector3(0,NightfallWorld.FORT_HEIGHT,3.1)
	if contracts.status!="active":return Vector3.INF
	if contracts.done.size()==contracts.targets.size():return Vector3(0,NightfallWorld.FORT_HEIGHT,3.1)
	for target: Dictionary in contracts.targets:
		if contracts.done.has(int(target.index)):continue
		if contracts.kind=="escort" and target.source.state=="escort":return Vector3(0,NightfallWorld.FORT_HEIGHT,3.1)
		return target.position
	return Vector3.INF

func follow_exploration() -> bool:
	if phase not in ["day","night"] or not is_instance_valid(discoveries):return false
	var target: Dictionary=discoveries.motivation_target()
	if target.is_empty():return false
	plan_hero_path(target.position)
	if hero_path.is_empty():return false
	var route_name: String="沿共鸣路线" if target.get("reason","")=="affinity" else "沿路线"
	notify("%s寻找%s · 约%.0f米" % [route_name,discoveries.TITLES.get(String(target.kind),"下一种发现"),float(target.distance)],2)
	return true

func follow_route() -> bool:
	if phase=="day" and contract_goal()!=Vector3.INF:
		return follow_contract()
	return follow_exploration()

func follow_contract() -> bool:
	if phase!="day":return false
	var target:=contract_goal()
	if target==Vector3.INF:return false
	plan_hero_path(target)
	return not hero_path.is_empty()

func update_day_contracts(delta: float) -> void:
	if phase!="day":return
	contracts.tick(delta)
	settle_contract_reward()
	var goal:=contract_goal() if phase=="day" else Vector3.INF
	if goal==Vector3.INF:
		if is_instance_valid(contract_marker):contract_marker.queue_free()
		contract_marker=null
	else:
		if not is_instance_valid(contract_marker):contract_marker=BattleVisuals.ring(effects,goal,1.4,Color("a2d5bb"),.075)
		contract_marker.position=goal+Vector3(0,.14,0)

func trigger_contract_risk(center: Vector3) -> void:
	if phase!="day" or contracts.status not in ["active", "bonus_offer"] or contracts.risk_spawned:return
	var count:=int(contracts.selected_reward.get("risk_hunters",0))
	contracts.mark_risk_spawned(count)
	if count<=0:return
	var hunters:=expeditions.spawn_ambush(center,count)
	for hunter: BattleUnit in hunters:
		hunter.set_meta("contract_hunter",true)
		hunter.title="委托追猎者"
	notify("委托风险触发 · 额外追猎%d · 先保住自己再完成目标" % count,4)

func clear_contract_hunters() -> void:
	for i in range(enemies.size()-1,-1,-1):
		var creature:=enemies[i]
		if not is_instance_valid(creature):
			enemies.remove_at(i)
			continue
		if not creature.get_meta("contract_hunter",false):continue
		creature.queue_free()
		enemies.remove_at(i)

func clear_exploration_marker() -> void:
	if is_instance_valid(motivation_marker):motivation_marker.queue_free()
	motivation_marker=null

func update_exploration_guidance() -> void:
	if phase not in ["day","night"] or not is_instance_valid(discoveries):
		clear_exploration_marker()
		return
	var target: Dictionary=discoveries.motivation_target()
	if target.is_empty():
		clear_exploration_marker()
		return
	if not is_instance_valid(motivation_marker):
		motivation_marker=BattleVisuals.ring(effects,target.position,1.3,Color("e8bc70"),.055)
	motivation_marker.position=target.position+Vector3(0,.16,0)

func settle_contract_reward() -> void:
	var reward: Dictionary=contracts.take_reward_request()
	if not reward.is_empty():
		scrap+=int(reward.scrap)
		if exploration and reward.has("affinity"):
			exploration.arm_contract_affinity(reward.affinity)
		var reward_detail: String="+%d零件" % int(reward.scrap)
		if bool(reward.get("bonus",false)):reward_detail+=" · 追加补给已兑现"
		elif bool(reward.get("early_return",false)):reward_detail+=" · 提前返家奖励"
		reward_toasts.append({"title":"委托交付 · 同伴接回物资","detail":reward_detail,"time":3.5,"color":Color("e8bc76")})
		while reward_toasts.size()>4:reward_toasts.remove_at(0)
		notify("委托已交回 · +%d零件" % int(reward.scrap),3)

func spawn_creature(night: bool, role: String="") -> BattleUnit:
	var is_lobber: bool=night and role=="lobber"
	var is_summoner: bool=night and role=="summoner"
	var is_warder: bool=night and role=="warder"
	var is_shellguard: bool=night and role=="shellguard"
	var creature:=UnitScript.new() as BattleUnit
	add_child(creature)
	var angle:=spawn_rng.randf_range(0,TAU)
	var radius:=spawn_rng.randf_range(29,98)
	creature.position=Vector3(spawn_rng.randf_range(-10,10),0,spawn_rng.randf_range(34,54)) if night else Vector3(cos(angle)*radius,0,sin(angle)*radius)
	creature.set_meta("gate_lane",spawn_rng.randf_range(-1.15,1.15))
	var roll:=spawn_rng.randf() if night else 1.0
	if night and not role.is_empty():
		roll={"basic":1.0,"breaker":0.0,"runner":.061+day_number*.025,"sapper":.231+day_number*.035,"light_eater":.341+day_number*.035}.get(role,1.0)
	var is_light_eater: bool=night and roll>=.34+day_number*.035 and roll<.43+day_number*.035
	creature.setup("monster",2)
	creature.title="夜行体" if night else "潜伏体"
	creature.visual.queue_free()
	var model_path: String="res://assets/models/night_breaker_v2.glb" if night and roll<.06+day_number*.025 else ("res://assets/models/night_light_eater.glb" if is_light_eater else "res://assets/models/night_stalker_v2.glb")
	creature.visual=(load(model_path) as PackedScene).instantiate() as Node3D
	creature.add_child(creature.visual)
	# setup() painted the temporary golem, which is replaced above. Apply the
	# production material to the actual night creature rather than that stub.
	BattleVisuals.paint_model(creature.visual)
	creature.bind_stalker_rig()
	creature.visual_yaw_offset=PI
	creature.visual.scale=Vector3.ONE*(1.12 if night else 1.0)
	creature.max_hp=(155.0+day_number*28) if night else (105.0+day_number*16)
	creature.hp=creature.max_hp
	creature.damage=20.0 if night else 13.0
	creature.speed=3.8 if night else 2.3
	creature.attack_range=1.6
	creature.attack_interval=1.1
	if night:
		if is_shellguard:
			ShellguardScript.configure(creature)
		elif is_warder:
			creature.set_meta("threat","warder")
			creature.title="织壳者"
			creature.max_hp*=.82
			creature.hp=creature.max_hp
			creature.armor=0.0
			creature.damage=12.0
			creature.speed=3.0
			creature.attack_interval=1.4
			creature.visual.scale=Vector3.ONE*1.08
			var warder: Node3D=WarderScript.new()
			warder.name="WarderController"
			add_child(warder)
			warder.setup(self,creature)
			warders.append(warder)
		elif is_summoner:
			creature.set_meta("threat","summoner")
			creature.title="召潮者"
			creature.max_hp*=.84
			creature.hp=creature.max_hp
			creature.damage=16.0
			creature.speed=3.0
			creature.visual.scale=Vector3.ONE*1.08
			var summoner: Node3D=SummonerScript.new()
			summoner.name="SummonerController"
			add_child(summoner)
			summoner.setup(self,creature)
			summoners.append(summoner)
		elif is_lobber:
			creature.set_meta("threat","lobber")
			creature.title="投蚀体"
			creature.max_hp*=.92
			creature.hp=creature.max_hp
			creature.damage=22.0
			creature.speed=3.15
			creature.attack_range=LobberScript.RANGE
			creature.attack_interval=LobberScript.ATTACK_INTERVAL
			creature.visual.scale=Vector3.ONE*1.08
			var lobber: Node3D=LobberScript.new()
			lobber.name="LobberController"
			add_child(lobber)
			lobber.setup(self,creature)
			lobbers.append(lobber)
		elif roll<.06+day_number*.025:
			creature.set_meta("threat","breaker")
			creature.title="破城体"
			creature.max_hp*=2.35
			creature.hp=creature.max_hp
			creature.damage*=2.6
			creature.speed=2.45
			creature.visual.scale=Vector3.ONE*1.5
			BattleVisuals.ring(creature,Vector3(0,.08,0),.95,Color("df7854"),.045)
		elif roll<.23+day_number*.035:
			creature.set_meta("threat","runner")
			creature.title="疾行体"
			creature.max_hp*=.64
			creature.hp=creature.max_hp
			creature.damage*=.75
			creature.speed=5.4
			creature.visual.scale=Vector3.ONE*.94
			BattleVisuals.ring(creature,Vector3(0,.08,0),.56,Color("75ced1"),.035)
		elif roll<.34+day_number*.035:
			creature.set_meta("threat","sapper")
			creature.title="蚀塔体"
			creature.max_hp*=1.28
			creature.hp=creature.max_hp
			creature.damage*=1.35
			creature.speed=4.3
			creature.visual.scale=Vector3.ONE*1.1
			BattleVisuals.ring(creature,Vector3(0,.08,0),.72,Color("b4d66d"),.05)
		elif is_light_eater:
			creature.set_meta("threat","light_eater")
			creature.title="噬灯蛾"
			creature.max_hp*=.82
			creature.hp=creature.max_hp
			creature.damage*=.7
			creature.speed=4.1
			creature.visual.scale=Vector3.ONE*1.2
			var eater:=NightLightEater.new()
			eater.name="LightEater"
			creature.add_child(eater)
			eater.setup(creature)
			BattleVisuals.ring(creature,Vector3(0,.08,0),.63,Color("70c9c9"),.045)
		else:creature.set_meta("threat","stalker")
	creature.defeated.connect(_on_creature_defeated)
	enemies.append(creature)
	return creature

func spawn_nest_guards() -> void:
	for nest in world.nests:
		if nest.cleansed:continue
		for side in [-1,1]:
			var guard:=spawn_creature(false)
			guard.position=nest.position+Vector3(float(side)*2.8,0,1.5)
			guard.title="夜巢守卫"

func update_creature(creature: BattleUnit, delta: float) -> void:
	var move_speed: float=creature.speed*specializations.movement_multiplier(creature)
	var threat: String=creature.get_meta("threat","")
	var day_hunter: bool=phase=="day" and creature.get_meta("day_hunter",false)
	var selected: Dictionary=choose_enemy_target(creature)
	if selected.is_empty():
		creature.moving=false;creature.attack_queued=false;creature.attack_windup=0.0
		return
	if day_hunter and hero.alive:
		selected={"kind":"hero","index":-1,"position":hero.position}
	var target_kind: String=String(selected.get("kind","beacon"))
	var target_pad: int=int(selected.get("index",-1)) if target_kind in ["tower","district"] else -1
	var target_token: int=int(selected.get("token",-1))
	var pursuing_hero: bool=target_kind=="hero"
	var attacking_barricade: bool=target_kind=="barricade"
	var selected_position: Vector3=selected.position
	if creature.attack_queued and (String(creature.get_meta("attack_target_kind",""))!=target_kind or int(creature.get_meta("attack_target_index",-1))!=target_pad or int(creature.get_meta("attack_target_token",-1))!=target_token):
		creature.attack_queued=false
		creature.attack_windup=0
	if phase=="day" and target_kind not in ["hero","squad"]:
		creature.moving=false;creature.attack_queued=false;creature.attack_windup=0.0
		return
	var destination:=selected_position
	if target_kind=="tower":destination=building_approach_position(creature.position,selected_position,"tower")
	elif target_kind=="district":destination=building_approach_position(creature.position,selected_position,String(districts.plots[target_pad].kind))
	elif target_kind=="beacon":destination=building_approach_position(creature.position,selected_position,"core")
	if not destination.is_finite():
		creature.moving=false;creature.attack_queued=false;creature.attack_windup=0.0
		return
	var target: Vector3=day_hunter_waypoint(creature,destination)
	var final_target: bool=target.distance_to(destination)<.2
	var distance:=creature.position.distance_to(target)
	var attacking_tower: bool=target_kind=="tower" and final_target
	var attacking_district: bool=target_kind=="district" and final_target
	var attacking_unit: bool=target_kind=="squad" and final_target
	var hero_attackable: bool=pursuing_hero and final_target
	var reach:=creature.attack_range if hero_attackable or attacking_tower or attacking_district or attacking_barricade or attacking_unit or (target_kind=="beacon" and final_target) else (0.05 if pursuing_hero else .2)
	var unreachable_target:=not final_target or not can_attack_line(creature.position,selected_position)
	if threat=="lobber" and final_target:
		# Stop relative to the target centre, not its nearer approach surface.
		# The latter can otherwise leave a thrower stalled beyond launch range.
		distance=Vector2(creature.position.x-selected_position.x,creature.position.z-selected_position.z).length()
		unreachable_target=unreachable_target or absf(creature.position.y-selected_position.y)>LobberScript.HEIGHT_TOLERANCE
	if distance>reach or unreachable_target:
		creature.attack_queued=false
		creature.attack_windup=0
		var direction:=target-creature.position;direction.y=0
		var previous:=creature.position
		if direction.length()>.05:
			var next:=previous+direction.normalized()*minf(direction.length(),move_speed*delta)
			if can_traverse(previous,next):
				next.y=outpost_height(next)
				creature.position=next
			else:
				creature.path.clear();creature.path_timer=0
		creature.face(target,delta)
		creature.moving=creature.position.distance_squared_to(previous)>.000001
	else:
		creature.moving=false
		creature.face(target,delta)
		# Cooldown/cancelled casts must never fall through to instant melee.
		if threat=="lobber":return
		if creature.attack_queued and creature.attack_windup<=0:
			creature.attack_queued=false
			creature.attack_timer=creature.attack_interval
			creature.attack_pose=1.0
			if threat=="breaker":BattleVisuals.breaker_slam(effects,creature.position)
			if attacking_tower:
				damage_tower(target_pad,creature.damage)
			elif attacking_district:
				districts.damage(target_pad,creature.damage)
			elif attacking_barricade:
				damage_gate_barricade(creature.damage)
			elif attacking_unit:
				var victim:=selected.get("unit") as BattleUnit
				if is_instance_valid(victim) and victim.alive:
					victim.hurt(creature.damage,creature)
					BattleVisuals.sparks(effects,victim.position+Vector3.UP,Color("ef9d76"),5)
					BattleVisuals.burst(effects,creature.position,.85,Color("d77962"),.2)
			elif target_kind=="beacon" and final_target:
				apply_beacon_damage(creature.damage)
				BattleVisuals.burst(effects,Vector3(0,NightfallWorld.FORT_HEIGHT,0),1.15,Color("ff9a4d"),.28)
			elif target_kind=="hero" and hero_attackable:
				hero.hurt(creature.damage,creature)
				BattleVisuals.sparks(effects,hero.position+Vector3.UP,Color("ef9d76"),5)
				BattleVisuals.burst(effects,creature.position,.85,Color("d77962"),.2)
		elif not creature.attack_queued and creature.attack_timer<=0 and (target_kind!="hero" or hero_attackable):
			creature.attack_queued=true
			creature.attack_target_hero=hero_attackable
			creature.attack_target_pad=target_pad
			creature.attack_target_barricade=attacking_barricade
			creature.set_meta("attack_target_kind",target_kind)
			creature.set_meta("attack_target_index",target_pad)
			creature.set_meta("attack_target_token",target_token)
			creature.windup_duration=.22 if creature.get_meta("threat","")=="runner" else (.55 if creature.get_meta("threat","")=="breaker" else .34)
			creature.attack_windup=creature.windup_duration

func choose_enemy_target(creature: BattleUnit) -> Dictionary:
	if is_instance_valid(discoveries) and discoveries.cache_guards.owns(creature):
		return discoveries.cache_guards.target_for(creature)
	# Day scavengers defend against nearby troops outside the walls. They do
	# not inherit the night assault's beacon/building fallback or unlimited chase.
	if phase=="day":
		if creature.get_meta("day_hunter",false) and hero.alive:
			return {"kind":"hero","index":-1,"position":hero.position}
		return nearby_day_squad_target(creature)
	# Night defenders share one target selector: the closest living hero,
	# squad member, constructed tower, barricade, or beacon. Shield squads
	# intercept before this function runs, so they remain the first line when
	# ordered to hold; ranged members remain valid targets when exposed.
	var beacon_position:=Vector3(0,NightfallWorld.FORT_HEIGHT,0)
	var selected: Dictionary={"kind":"beacon","index":-1,"position":beacon_position}
	var best:=Vector2(creature.position.x,creature.position.z).distance_to(Vector2(beacon_position.x,beacon_position.z))
	if creature.get_meta("threat","")=="breaker" and gate_barricade_hp>0.0 and creature.position.z<=Layout.RAMP_END+.5:
		var gate_distance:=Vector2(creature.position.x,creature.position.z).distance_to(Vector2(gate_barricade.position.x,gate_barricade.position.z))
		if gate_distance<6.0:
			return {"kind":"barricade","index":-1,"position":gate_barricade.position}
	if phase=="night" and hero.alive:
		var hero_distance:=Vector2(creature.position.x,creature.position.z).distance_to(Vector2(hero.position.x,hero.position.z))
		if hero_distance<best:
			best=hero_distance;selected={"kind":"hero","index":-1,"position":hero.position}
	if is_instance_valid(squads):
		for squad: Dictionary in squads.squads:
			for member: BattleUnit in squad.members:
				if not is_instance_valid(member) or not member.alive:continue
				var member_distance:=Vector2(creature.position.x,creature.position.z).distance_to(Vector2(member.position.x,member.position.z))
				if member_distance<best:
					best=member_distance
					selected={"kind":"squad","index":-1,"token":member.get_instance_id(),"unit":member,"position":member.position}
	for i in world.tower_pads.size():
		var pad: Dictionary=world.tower_pads[i]
		if int(pad.level)<=0 or float(pad.hp)<=0.0:continue
		var pad_distance:=Vector2(creature.position.x,creature.position.z).distance_to(Vector2(pad.position.x,pad.position.z))
		if pad_distance<best:
			best=pad_distance;selected={"kind":"tower","index":i,"position":pad.position}
	for index in districts.plots.size():
		var plot: Dictionary=districts.plots[index]
		if int(plot.level)<=0 or float(plot.get("hp",0))<=0:continue
		var separation:=Vector2(creature.position.x,creature.position.z).distance_to(Vector2(plot.position.x,plot.position.z))
		if separation<best:
			best=separation;selected={"kind":"district","index":index,"position":plot.position}
	if gate_barricade_hp>0.0:
		var barricade_distance:=Vector2(creature.position.x,creature.position.z).distance_to(Vector2(gate_barricade.position.x,gate_barricade.position.z))
		if barricade_distance<best:
			best=barricade_distance;selected={"kind":"barricade","index":-1,"position":gate_barricade.position}
	if threat_is_tower_hunter(creature):
		var tower_index:=south_tower_target(creature.position)
		if tower_index>=0:
			selected={"kind":"tower","index":tower_index,"position":world.tower_pads[tower_index].position}
	if phase=="night" and not enemy_target_reachable(creature.position,selected):
		return nearest_reachable_structure(creature.position)
	return selected

func nearby_day_squad_target(creature: BattleUnit) -> Dictionary:
	var selected: Dictionary={}
	var best:=DAY_SQUAD_ALERT_RADIUS
	if not is_instance_valid(squads):return selected
	for squad: Dictionary in squads.squads:
		for member: BattleUnit in squad.members:
			if not is_instance_valid(member) or not member.alive or Layout.contains_castle(member.position):continue
			var separation:=Vector2(creature.position.x,creature.position.z).distance_to(Vector2(member.position.x,member.position.z))
			if separation>best:continue
			var target: Dictionary={"kind":"squad","index":-1,"token":member.get_instance_id(),"unit":member,"position":member.position}
			if not enemy_target_reachable(creature.position,target):continue
			best=separation;selected=target
	return selected

func enemy_target_reachable(origin: Vector3, target: Dictionary) -> bool:
	var kind: String=String(target.kind)
	if kind in ["tower","district","beacon"]:
		var structure_kind: String="core" if kind=="beacon" else (String(districts.plots[int(target.index)].kind) if kind=="district" else "tower")
		return building_approach_position(origin,target.position,structure_kind).is_finite()
	if can_traverse(origin,target.position):return true
	var start_cell:=nearest_navigation_cell(origin,true)
	var end_cell:=nearest_navigation_cell(target.position,true)
	if start_cell.x==999 or end_cell.x==999:return false
	var key: String="route:%s" % Vector4i(start_cell.x,start_cell.y,end_cell.x,end_cell.y)
	if building_approach_cache.has(key):return bool(building_approach_cache[key])
	var reachable:=not hero_navigation.get_id_path(start_cell,end_cell).is_empty()
	if building_approach_cache.size()>=2048:building_approach_cache.clear()
	building_approach_cache[key]=reachable
	return reachable

func nearest_reachable_structure(origin: Vector3) -> Dictionary:
	# A sealed nearest target must not stop the assault or receive distant hits.
	# Enemies first break an exposed building, opening the route for later ticks.
	var candidates: Array[Dictionary]=[{"kind":"beacon","index":-1,"position":Vector3(0,Layout.FORT_HEIGHT,0)}]
	for index in world.tower_pads.size():
		var pad: Dictionary=world.tower_pads[index]
		if int(pad.level)>0 and float(pad.hp)>0:candidates.append({"kind":"tower","index":index,"position":pad.position})
	for index in districts.plots.size():
		var plot: Dictionary=districts.plots[index]
		if int(plot.level)>0 and float(plot.hp)>0:candidates.append({"kind":"district","index":index,"position":plot.position})
	candidates.sort_custom(func(left: Dictionary,right: Dictionary)->bool:return (left.position as Vector3).distance_squared_to(origin)<(right.position as Vector3).distance_squared_to(origin))
	for candidate: Dictionary in candidates:
		if enemy_target_reachable(origin,candidate):return candidate
	return {}

func target_warning_snapshot() -> Array[Dictionary]:
	# Read the live attack windups instead of running a second timer. This keeps
	# target-side warnings frozen with the simulation during pause and selection
	# screens, and automatically follows a moving hero or squad member.
	var warnings: Array[Dictionary]=[]
	if phase not in ["day","night","paused"]:return warnings
	var casting_sources: Dictionary={}
	for summoner: Node3D in summoners:
		if not is_instance_valid(summoner):continue
		var cast: Dictionary=summoner.snapshot()
		if String(cast.get("phase","")) not in ["windup","committing"]:continue
		var source: Variant=cast.get("source")
		if is_instance_valid(source):casting_sources[source.get_instance_id()]=true
	for cast: Dictionary in warder_warning_snapshot():
		var source: Variant=cast.get("source")
		if is_instance_valid(source):casting_sources[source.get_instance_id()]=true
	for creature: BattleUnit in enemies:
		if not is_instance_valid(creature) or not creature.alive or creature.get_meta("siege_boss",false) or creature.get_meta("threat","")=="lobber" or casting_sources.has(creature.get_instance_id()):continue
		if not creature.attack_queued or creature.attack_windup<=0.0:continue
		var target:=attack_target_node(creature)
		var target_kind:=String(creature.get_meta("attack_target_kind",""))
		if not is_instance_valid(target) and is_instance_valid(squads) and squads.has_method("intercept_target_for"):
			target=squads.intercept_target_for(creature)
			if is_instance_valid(target):target_kind="squad"
		if not is_instance_valid(target):continue
		warnings.append({"source":creature,"target":target,"target_kind":target_kind,
			"threat":String(creature.get_meta("threat","stalker")),"title":creature.title,
			"remaining":creature.attack_windup,"duration":maxf(.01,creature.windup_duration),
			"progress":1.0-clampf(creature.attack_windup/maxf(.01,creature.windup_duration),0.0,1.0)})
	if is_instance_valid(squads):
		for squad: Dictionary in squads.squads:
			for soldier: BattleUnit in squad.members:
				if not is_instance_valid(soldier) or not soldier.alive or not soldier.attack_queued or soldier.attack_windup<=0.0:continue
				if not is_instance_valid(soldier.target):continue
				warnings.append({"source":soldier,"target":soldier.target,"target_kind":"enemy",
					"threat":"defender","title":soldier.title,"remaining":soldier.attack_windup,
					"duration":maxf(.01,soldier.windup_duration),
					"progress":1.0-clampf(soldier.attack_windup/maxf(.01,soldier.windup_duration),0.0,1.0)})
	return warnings

func attack_target_node(creature: BattleUnit) -> Node3D:
	var target_kind:=String(creature.get_meta("attack_target_kind",""))
	match target_kind:
		"hero":return hero
		"squad":return squad_member_by_token(int(creature.get_meta("attack_target_token",-1)))
		"tower":
			var index:=int(creature.get_meta("attack_target_index",-1))
			if index>=0 and index<world.tower_pads.size():return world.tower_pads[index].node as Node3D
		"district":
			var index:=int(creature.get_meta("attack_target_index",-1))
			if index>=0 and index<districts.plots.size():return districts.plots[index].node as Node3D
		"barricade":return gate_barricade
		"beacon":return world.beacon
	return null

func squad_member_by_token(token: int) -> BattleUnit:
	if token<0 or not is_instance_valid(squads):return null
	for squad: Dictionary in squads.squads:
		for member: BattleUnit in squad.members:
			if is_instance_valid(member) and member.get_instance_id()==token:return member
	return null

func threat_is_tower_hunter(creature: BattleUnit) -> bool:
	return creature.get_meta("threat","")=="sapper"

func day_hunter_waypoint(creature: BattleUnit, destination: Vector3) -> Vector3:
	# All attack targets share the gate-aware cached route, including freely
	# placed castle towers. Refresh moving targets without rebuilding each frame.
	if can_traverse(creature.position,destination):
		creature.path.clear();creature.path_goal=destination
		return destination
	while not creature.path.is_empty() and Vector2(creature.position.x,creature.position.z).distance_to(Vector2(creature.path[0].x,creature.path[0].z))<.18:
		creature.path.remove_at(0)
	if creature.path_timer<=0 and (creature.path.is_empty() or creature.path_goal.distance_to(destination)>.8):
		build_day_hunter_route(creature,destination)
	if creature.path.is_empty():return creature.position
	return creature.path[0]

func build_day_hunter_route(creature: BattleUnit, destination: Vector3) -> void:
	creature.path.clear();creature.path_goal=destination;creature.path_timer=.45
	var start_cell:=nearest_navigation_cell(creature.position,true)
	var end_cell:=nearest_navigation_cell(destination,false)
	if start_cell.x==999 or end_cell.x==999:return
	var grid_path:=hero_navigation.get_point_path(start_cell,end_cell)
	var cursor:=creature.position
	var index:=0
	while index<grid_path.size():
		var furthest:=index
		for i in range(index,grid_path.size()):
			var point:=Vector3(grid_path[i].x,0,grid_path[i].y)
			if can_traverse(cursor,point):furthest=i
			else:break
		var waypoint:=Vector3(grid_path[furthest].x,0,grid_path[furthest].y)
		if not can_traverse(cursor,waypoint):
			creature.path.clear()
			return
		waypoint.y=outpost_height(waypoint)
		creature.path.append(waypoint)
		cursor=waypoint;index=furthest+1
	if can_traverse(cursor,destination):creature.path.append(destination)

func south_tower_target(from: Vector3) -> int:
	var selected:=-1
	var nearest:=INF
	for i in world.tower_pads.size():
		var pad: Dictionary=world.tower_pads[i]
		if pad.level<=0 or pad.hp<=0:continue
		var distance: float=from.distance_squared_to(pad.position)
		if distance<nearest:selected=i;nearest=distance
	return selected

func damage_tower(index: int, amount: float) -> void:
	var pad: Dictionary=world.tower_pads[index]
	if pad.level<=0:return
	pad.hp=maxf(0.0,float(pad.hp)-amount)
	BattleVisuals.sparks(effects,pad.position+Vector3(0,1.4,0),Color("cbdd82"),5)
	if is_instance_valid(pad.damage_ring):pad.damage_ring.visible=pad.hp<pad.max_hp*.6
	if pad.hp>0:return
	repairs.stop("tower",index)
	(pad.turret as Node3D).queue_free()
	pad.turret=null
	pad.level=0
	pad.max_hp=0.0
	pad.cooldown=0.0
	pad.mode="nearest"
	specializations.on_destroyed(pad)
	BattleVisuals.burst(effects,pad.position,2.5,Color("db8757"),.45)
	notify("城内防御塔被摧毁 · 到残基旁按F重建",3)
	refresh_construction_navigation()

func apply_beacon_damage(amount: float, defeat_message: String="灯塔熄灭 · 哨站失守") -> float:
	if phase not in ["day","night"] or quitting or restart_pending or shutting_down or beacon_hp<=0.0 or not is_finite(amount) or amount<=0.0:return 0.0
	var multiplier: float=districts.holdfast_damage_multiplier() if is_instance_valid(districts) else 1.0
	var before:=beacon_hp
	beacon_hp=maxf(0.0,beacon_hp-amount*multiplier)
	var actual:=before-beacon_hp
	record_beacon_hit(actual)
	if beacon_hp<=0.0:end_defeat(defeat_message)
	return actual

func record_beacon_hit(amount: float) -> void:
	if amount<=0:return
	if beacon_alarm_time>0:beacon_alarm_damage+=amount
	else:beacon_alarm_damage=amount
	beacon_alarm_time=3.0

func update_beacon_alarm(delta: float) -> void:
	beacon_alarm_time=maxf(0.0,beacon_alarm_time-delta)
	if beacon_alarm_time<=0:beacon_alarm_damage=0.0

func move_hero(delta: float) -> void:
	var old_position:=hero.position
	var input:=Vector3.ZERO
	if Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_UP):input.z-=1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):input.z+=1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):input.x-=1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):input.x+=1
	if input.length_squared()>0:
		hero_keyboard_active=true
		hero_path.clear()
		move_goal=hero.position+input.normalized()*2
	elif hero_keyboard_active:
		hero_keyboard_active=false
		hero_path.clear()
		move_goal=hero.position
	# Waypoint completion is planar. A raised-ramp waypoint can differ in Y by
	# over a metre while its ground position is already reached; using 3D
	# distance there leaves the route waiting on a vertical gap and feels like
	# the hero is stuck at the high-ground edge.
	while not hero_path.is_empty() and Vector2(hero.position.x,hero.position.z).distance_to(Vector2(hero_path[0].x,hero_path[0].z))<.18:
		hero_path.remove_at(0)
	var target: Vector3=hero_path[0] if not hero_path.is_empty() else move_goal
	var to_goal:=target-hero.position
	to_goal.y=0
	if to_goal.length()>.11:
		var direction:=to_goal.normalized()
		var remaining:=minf(to_goal.length(),hero.speed*delta)
		var moved_any:=false
		var substeps:=0
		var max_substeps:=maxi(4,ceili(remaining/HERO_MOVE_SUBSTEP)*4)
		# Split a long frame into short terrain steps. At a low or uneven
		# render cadence one large step could cross the raised ramp's wall
		# corner, making the controller reject the whole frame and feel sticky.
		# The substeps keep the same total distance while preserving the
		# existing wall-slide projection in move_hero_position().
		# A nearly blocked corner can return millimetres of progress. Bound the
		# contact work by the requested distance instead of spending a whole
		# render frame consuming the budget through tiny accepted corrections.
		while remaining>.0001 and substeps<max_substeps:
			substeps+=1
			var step_distance:=minf(remaining,HERO_MOVE_SUBSTEP)
			var before:=hero.position
			var accepted:=false
			for factor: float in HERO_MOVE_RETRY_FACTORS:
				var requested_step:=step_distance*factor
				if not move_hero_position(before+direction*requested_step):continue
				var travelled: float=Vector2(before.x-hero.position.x,before.z-hero.position.z).length()
				if travelled<.000001:continue
				accepted=true
				if factor<.999:hero_move_retries+=1
				moved_any=true
				remaining=maxf(0.0,remaining-travelled)
				break
			if not accepted:break
		if moved_any:
			hero.moving=true
			# A wall-slide can resolve a diagonal request onto the free tangent.
			# Facing the original blocked vector makes the hero run into the
			# retaining wall while the feet move sideways, which reads as terrain
			# snagging even though the controller is still advancing. Follow the
			# actual planar displacement whenever the resolver produced one.
			var travelled_direction:=hero.position-old_position
			travelled_direction.y=0.0
			if travelled_direction.length_squared()>.000001:
				hero.face(hero.position+travelled_direction.normalized(),delta)
			else:
				hero.face(hero.position+to_goal.normalized(),delta)
		else:
			hero.moving=false
			hero_path.clear()
			move_goal=hero.position
	else:hero.moving=false
	hero.set_locomotion_velocity((hero.position-old_position)/maxf(delta,.001))

func move_hero_position(next: Vector3) -> bool:
	# Keep movement responsive when the desired diagonal step clips a ramp
	# wall. Resolve onto a continuously reachable component or free tangent.
	var origin:=hero.position
	var requested:=Vector2(next.x-origin.x,next.z-origin.z)
	var requested_distance:=requested.length()
	var unclamped_next:=next
	next=hero_safe_destination(next,origin)
	var ramp_motion:=hero_ramp_motion(origin,unclamped_next)
	var platform_x_clamped:=not is_equal_approx(next.x,unclamped_next.x)
	var platform_z_clamped:=not is_equal_approx(next.z,unclamped_next.z)
	# hero_safe_destination() can move a point to the far side of a retaining
	# wall so the final destination is walkable. That correction must never be
	# mistaken for requested movement: keep the candidate inside this frame's
	# original substep and let the component/corner fallback resolve the wall.
	var safe_delta:=Vector2(next.x-origin.x,next.z-origin.z)
	if requested_distance>.0001 and safe_delta.length()>requested_distance+.0001:
		# Preserve the direction of the safety correction (for example, easing
		# inward from the ramp side wall) while limiting its length to this
		# frame. Replacing it with the raw input vector would undo the visual
		# clearance and push the mesh back into the retaining wall.
		var safe_direction:=safe_delta.normalized()
		next=Vector3(origin.x+safe_direction.x*requested_distance,origin.y,origin.z+safe_direction.y*requested_distance)
		platform_x_clamped=not is_equal_approx(next.x,unclamped_next.x)
		platform_z_clamped=not is_equal_approx(next.z,unclamped_next.z)
	if not ramp_motion:
		# A platform-wall clamp must never pull the hero backwards when the
		# current frame is already at the safe edge. Keep that axis at the
		# current position and let the other component slide along the wall.
		# Without this guard, entering the south/north wall band alternates
		# between 6.16 and 6.5 m and feels like a terrain snag.
		# Once the centre has entered the small visual-clearance band, however,
		# the correction is intentional: it moves the centre back into the safe
		# corridor so the cape can clear the retaining wall. Without this
		# exception the north wall leaves the hero parked at z=-6.495 forever.
		var x_clearance_correction:=not is_equal_approx(next.x,unclamped_next.x) and absf(origin.x)>HERO_FORT_SAFE_EDGE
		var z_clearance_correction:=not is_equal_approx(next.z,unclamped_next.z) and absf(origin.z)>HERO_FORT_SAFE_EDGE
		if requested.x*(next.x-origin.x)<-.0001 and not x_clearance_correction:next.x=origin.x
		if requested.y*(next.z-origin.z)<-.0001 and not z_clearance_correction:next.z=origin.z
		# Preserve the full normalized input step on the free tangent. Without
		# this projection, the clamped diagonal vector is shorter by sqrt(1/2)
		# and the hero visibly slows while sliding beside a high-ground wall.
		if requested_distance>.0001 and platform_x_clamped and absf(requested.y)>.0001 and not platform_z_clamped:
			var tangent_z:=Vector3(origin.x,origin.y,origin.z+signf(requested.y)*requested_distance)
			if can_traverse(origin,tangent_z):next=tangent_z
		elif requested_distance>.0001 and platform_z_clamped and absf(requested.x)>.0001 and not platform_x_clamped:
			var tangent_x:=Vector3(origin.x+signf(requested.x)*requested_distance,origin.y,origin.z)
			if can_traverse(origin,tangent_x):next=tangent_x
	if ramp_motion and requested_distance>.0001 and not is_equal_approx(next.x,unclamped_next.x):
		# Keep the clamped edge position instead of projecting the whole frame
		# back to the old centre. The old projection made a lateral input beside
		# the ramp wall lose its entire step, which felt like terrain snagging.
		# Preserve the requested step length on the downhill tangent after the
		# visual clearance correction, so diagonal motion remains responsive.
		var limit:=minf(hero_ramp_side_limit(origin.z),hero_ramp_side_limit(unclamped_next.z))
		var corrected_x:=clampf(next.x,-limit,limit)
		# A test or a low-FPS frame can begin just outside the visual corridor.
		# Move back into it over at most this frame's requested distance instead
		# of teleporting the centre across the ramp width.
		var corrected_x_delta:=clampf(corrected_x-origin.x,-requested_distance,requested_distance)
		corrected_x=origin.x+corrected_x_delta
		var downhill_distance:=sqrt(maxf(0.0,requested_distance*requested_distance-corrected_x_delta*corrected_x_delta))
		var projected:=Vector3(corrected_x,origin.y,
			origin.z+signf(requested.y)*downhill_distance)
		if can_traverse(origin,projected):next=projected
	if can_traverse(origin,next):
		next.y=outpost_height(next)
		hero.position=next
		return true
	var delta:=next-origin
	delta.y=0.0
	var step_distance:=Vector2(delta.x,delta.z).length()
	var candidates: Array[Vector3]=[]
	var x_step:=Vector3(next.x,origin.y,origin.z)
	var x_reachable:=absf(delta.x)>.0001 and can_traverse(origin,x_step)
	var z_step:=Vector3(origin.x,origin.y,next.z)
	var z_reachable:=absf(delta.z)>.0001 and can_traverse(origin,z_step)
	if x_reachable:
		candidates.append(x_step)
	if z_reachable:
		candidates.append(z_step)
	# Two individually clear axis legs must not reintroduce the diagonal
	# endpoint that was rejected above. The hero moves directly to the selected
	# candidate, so that diagonal would still clip the solid wall's outer corner.
	# A diagonal input has a normalized step. If one component is blocked,
	# retain that step length along the free tangent instead of slowing to the
	# smaller component length at the wall.
	if step_distance>.0001:
		if absf(delta.x)>.0001:
			var x_slide:=Vector3(origin.x+signf(delta.x)*step_distance,origin.y,origin.z)
			if can_traverse(origin,x_slide):candidates.append(x_slide)
		if absf(delta.z)>.0001:
			var z_slide:=Vector3(origin.x,origin.y,origin.z+signf(delta.z)*step_distance)
			if can_traverse(origin,z_slide):candidates.append(z_slide)
	if candidates.is_empty():
		# At the raised platform's south lip the top retaining wall and the
		# ramp side wall meet at an L-shaped corner. A diagonal input aimed
		# toward that corner can legitimately block both component steps even
		# though the ramp is immediately beyond it. Move inward first, then
		# continue downhill as one short step so the player does not have to
		# release the sideways key to enter the ramp.
		# `next` has already passed through hero_safe_destination(), which may
		# move a point across the whole retaining-wall clearance band.  That
		# correction is only a safety boundary, not a request to travel that
		# distance in one frame.  Keep the corner escape bounded by the original
		# substep so entering the courtyard cannot produce a visible jump.
		var corner_escape:=raised_ramp_corner_escape(origin,delta,requested_distance)
		if corner_escape.x<INF:
			corner_escape.y=outpost_height(corner_escape)
			hero.position=corner_escape
			return true
		return false
	var desired:=Vector2(delta.x,delta.z).normalized()
	var best:=origin
	var best_progress: float=-INF
	var best_distance: float=-INF
	for candidate in candidates:
		var offset:=Vector2(candidate.x-origin.x,candidate.z-origin.z)
		var progress:=offset.dot(desired)
		var travelled:=offset.length_squared()
		if progress>best_progress+.000001 or (is_equal_approx(progress,best_progress) and travelled>best_distance):
			best=candidate
			best_progress=progress
			best_distance=travelled
	if best==origin:return false
	best.y=outpost_height(best)
	hero.position=best
	return true

func hero_safe_destination(point: Vector3, origin: Vector3=Vector3.INF) -> Vector3:
	# Visual clearance belongs to the side of the wall that the hero occupies.
	# Applying the courtyard's inner clamp to the outer south slope pulled an
	# exterior hero towards the inner wall edge through the wall. The bounded correction then
	# reversed its free-axis slide, producing alternating steps and tiny retries.
	# Standalone route goals use their own region; movement and dashes also
	# check their origin so a blocked request cannot change sides of a wall.
	var reference:=point if origin==Vector3.INF else origin
	var ramp_clearance: bool=absf(reference.x)<=2.65 and reference.z>Layout.FORT_INNER and reference.z<Layout.RAMP_WALL_END
	var courtyard_clearance: bool=absf(reference.x)<=Layout.FORT_INNER and absf(reference.z)<=Layout.FORT_INNER
	if absf(point.x)<=Layout.FORT_INNER and absf(point.z)<=Layout.FORT_INNER:courtyard_clearance=true
	# The raised south ramp is only 5.2 m wide between its side walls. The
	# imported hero has a broader visual footprint than the gameplay ring, so a
	# centre position at x=±2.6 visibly intersects the wall and feels sticky.
	# Apply a small centre-only margin while crossing the sloped section; the
	# physical walkable map remains unchanged for enemies, escorts and clicks.
	# Only the walkable ramp corridor needs a side-clearance clamp. The ground
	# beside the ramp is intentionally open; applying this to every point in
	# the ramp's z range pulled an outer-ground hero across the retaining wall
	# or left it unable to move along that side.
	if ramp_clearance and point.z>HERO_RAMP_SAFE_START_Z and point.z<Layout.RAMP_WALL_END and absf(point.x)<3.9:
		var limit:=hero_ramp_side_limit(point.z)
		point.x=clampf(point.x,-limit,limit)
	# The raised courtyard has three solid retaining walls. Apply the same
	# centre-only clearance there, but leave the central south gate open so the
	# player can transition onto the ramp without a second hard stop. The two
	# passes handle a diagonal step that first enters the south wall band and
	# then reaches an east/west wall corner in the same frame.
	if not courtyard_clearance:return point
	for _pass in 2:
		if absf(point.z)<=Layout.FORT_INNER and absf(point.x)<=Layout.FORT_INNER:
			point.x=clampf(point.x,-HERO_FORT_SAFE_EDGE,HERO_FORT_SAFE_EDGE)
		if absf(point.x)<2.65 and point.z>HERO_FORT_SAFE_EDGE and point.z<Layout.FORT_OUTER:
			continue
		if absf(point.x)<=Layout.FORT_INNER and point.z>=HERO_FORT_SAFE_EDGE and point.z<Layout.FORT_OUTER:
			point.z=minf(point.z,HERO_FORT_SAFE_EDGE)
		if absf(point.x)<=Layout.FORT_INNER and point.z>=-Layout.FORT_OUTER and point.z<=-HERO_FORT_SAFE_EDGE:
			point.z=maxf(point.z,-HERO_FORT_SAFE_EDGE)
	return point

func hero_ramp_motion(origin: Vector3, target: Vector3) -> bool:
	# The same z band also contains the outer ground beside the ramp.  Treating
	# every point in that band as ramp motion makes a diagonal approach to the
	# raised courtyard wall skip the normal tangent slide and lose most of a
	# frame.  Only the walkable ramp corridor needs ramp-specific projection.
	return ((origin.z>HERO_RAMP_SAFE_START_Z-.75 and origin.z<Layout.RAMP_WALL_END) or (target.z>HERO_RAMP_SAFE_START_Z-.75 and target.z<Layout.RAMP_WALL_END)) and (absf(origin.x)<3.9 or absf(target.x)<3.9)

func hero_ramp_side_limit(z: float) -> float:
	# Bring the visual clearance in over the raised platform lip. A hard
	# threshold at the ramp lip made the first frame on the ramp pull the hero sideways.
	# Smoothstep keeps the correction below one visible movement step while
	# retaining the full 0.42 m margin on the actual sloped section.
	if z<=HERO_RAMP_SAFE_START_Z or z>=Layout.RAMP_WALL_END:return 2.65
	var blend:=clampf((z-HERO_RAMP_SAFE_START_Z)/(HERO_RAMP_SAFE_FULL_Z-HERO_RAMP_SAFE_START_Z),0.0,1.0)
	blend=blend*blend*(3.0-2.0*blend)
	return lerpf(2.65,2.65-HERO_RAMP_SIDE_CLEARANCE,blend)

func raised_ramp_corner_escape(origin: Vector3, delta: Vector3, step_distance: float) -> Vector3:
	if step_distance<=.0001 or delta.z<=.0001:return Vector3.INF
	if origin.z<Layout.FORT_INNER-.05 or origin.z>Layout.RAMP_WALL_START+.05:return Vector3.INF
	var side:=signf(origin.x)
	if absf(origin.x)<2.52 or side==0.0 or signf(delta.x)!=side:return Vector3.INF
	# Keep the whole corrective step inside the 2.6 m walkable ramp width.
	var inward_limit:=maxf(0.0,absf(origin.x)-2.54)
	var inward:=minf(step_distance*.75,inward_limit)
	if inward<.0001:return Vector3.INF
	var downhill:=sqrt(maxf(0.0,step_distance*step_distance-inward*inward))
	var inner:=Vector3(origin.x-side*inward,origin.y,origin.z)
	var exit:=Vector3(inner.x,origin.y,origin.z+downhill)
	if not can_traverse(origin,inner) or not can_traverse(inner,exit):return Vector3.INF
	return exit

func build_hero_navigation() -> void:
	hero_navigation=AStarGrid2D.new()
	hero_navigation.region=Rect2i(-123,-107,247,215)
	hero_navigation.cell_size=Vector2.ONE
	hero_navigation.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_NEVER
	hero_navigation.update()
	for z in range(-107,108):
		for x in range(-123,124):
			if not outpost_walkable(Vector3(x,0,z)):
				hero_navigation.set_point_solid(Vector2i(x,z))

func refresh_construction_navigation() -> void:
	if not is_instance_valid(construction):return
	construction_blocks=construction.navigation_blocks()
	building_approach_cache.clear()
	build_hero_navigation()
	# Route estimates must observe a placed, destroyed or rebuilt building
	# in the same frame rather than retaining its previous open approach.
	if is_instance_valid(contracts):contracts.clear_budget_cache()
	for creature in enemies:
		if is_instance_valid(creature) and creature is BattleUnit:creature.path.clear();creature.path_timer=0.0
	if is_instance_valid(squads):
		for squad: Dictionary in squads.squads:
			for member in squad.members:
				if is_instance_valid(member) and member is BattleUnit:member.path.clear();member.path_timer=0.0
	if is_instance_valid(hero) and not hero_path.is_empty():plan_hero_path(move_goal)

func nearest_navigation_cell(point: Vector3, require_reachable: bool) -> Vector2i:
	var center:=Vector2i(clampi(roundi(point.x),-123,123),clampi(roundi(point.z),-107,107))
	for radius in range(0,7):
		var best:=Vector2i(999,999)
		var best_distance:=INF
		for z in range(center.y-radius,center.y+radius+1):
			for x in range(center.x-radius,center.x+radius+1):
				var cell:=Vector2i(x,z)
				if not hero_navigation.is_in_boundsv(cell) or hero_navigation.is_point_solid(cell):continue
				var waypoint:=Vector3(x,0,z)
				if require_reachable and not can_traverse(point,waypoint):continue
				var distance:=Vector2(point.x-x,point.z-z).length_squared()
				if distance<best_distance:best=cell;best_distance=distance
		if best.x!=999:return best
	return Vector2i(999,999)

func plan_hero_path(destination: Vector3) -> void:
	hero_keyboard_active=false
	hero_path.clear()
	var goal:=Vector3(clampf(destination.x,-122.5,122.5),0,clampf(destination.z,-106.5,106.5))
	var end_cell:=nearest_navigation_cell(goal,false)
	if end_cell.x==999:
		move_goal=hero.position
		return
	if not outpost_walkable(goal):goal=Vector3(end_cell.x,0,end_cell.y)
	# Clicks can land inside the gameplay clearance band of a raised wall. The
	# visual controller will clamp those frames while moving, but a fixed click
	# goal then keeps asking for the unreachable point and makes the hero slide
	# back and forth along the wall forever. Resolve the goal once up front so
	# the route has a reachable endpoint on the same walkable terrain.
	goal=hero_safe_destination(goal)
	goal.y=outpost_height(goal)
	move_goal=goal
	if can_traverse(hero.position,goal):
		hero_path.append(goal)
		return
	var start_cell:=nearest_navigation_cell(hero.position,true)
	if start_cell.x==999:
		move_goal=hero.position
		return
	var grid_path:=hero_navigation.get_point_path(start_cell,end_cell)
	if grid_path.is_empty():
		move_goal=hero.position
		return
	var cursor:=hero.position
	var index:=0
	while index<grid_path.size():
		var furthest:=index
		for i in range(index,grid_path.size()):
			var point:=hero_safe_destination(Vector3(grid_path[i].x,0,grid_path[i].y))
			if can_traverse(cursor,point):furthest=i
			else:break
		var waypoint:=hero_safe_destination(Vector3(grid_path[furthest].x,0,grid_path[furthest].y))
		if not can_traverse(cursor,waypoint):
			hero_path.clear()
			move_goal=hero.position
			return
		waypoint.y=outpost_height(waypoint)
		hero_path.append(waypoint)
		cursor=waypoint
		index=furthest+1
	if can_traverse(cursor,goal):hero_path.append(goal)
	else:move_goal=cursor

func outpost_walkable(point: Vector3) -> bool:
	if not point.is_finite() or absf(point.x)>Layout.MAP_HALF_X or absf(point.z)>Layout.MAP_HALF_Z:return false
	var flat:=Vector2(point.x,point.z)
	for block: Rect2 in WALK_BLOCKS:
		if flat.x>block.position.x and flat.x<block.end.x and flat.y>block.position.y and flat.y<block.end.y:return false
	for block: Rect2 in construction_blocks:
		if flat.x>block.position.x and flat.x<block.end.x and flat.y>block.position.y and flat.y<block.end.y:return false
	return true

func outpost_height(point: Vector3) -> float:
	return world.terrain_height(point)

func can_traverse(start: Vector3, end: Vector3) -> bool:
	if not outpost_walkable(end):return false
	var origin:=Vector2(start.x,start.z)
	var direction:=Vector2(end.x-start.x,end.z-start.z)
	for block: Rect2 in WALK_BLOCKS:
		if segment_crosses_wall(origin,direction,block):return false
	for block: Rect2 in construction_blocks:
		if segment_crosses_wall(origin,direction,block):return false
	return true

func can_attack_line(start: Vector3, end: Vector3) -> bool:
	# Projectiles and repair tools reach the target's surface. Its own building
	# footprint blocks movement, but must not prevent attacks or repairs.
	if not start.is_finite() or not end.is_finite():return false
	var origin:=Vector2(start.x,start.z)
	var direction:=Vector2(end.x-start.x,end.z-start.z)
	for block: Rect2 in WALK_BLOCKS:
		if segment_crosses_wall(origin,direction,block):return false
	return true

func building_approach_position(origin: Vector3, center: Vector3, kind: String) -> Vector3:
	# Free placement can cover the nearest face with a wall or another building.
	# Choose a reachable exposed surface rather than routing into that footprint.
	var key:=Vector4i(roundi(origin.x),roundi(origin.z),roundi(center.x*100),roundi(center.z*100))
	var cache_key: String="%s:%s" % [key,kind]
	if building_approach_cache.has(cache_key):
		var cached: Vector3=building_approach_cache[cache_key]
		if not cached.is_finite() or outpost_walkable(cached):return cached
	var half: Vector2=construction.footprint(kind) if is_instance_valid(construction) else Vector2(1.3,1.3)
	var flat:=Vector2(origin.x,origin.z)
	var anchor:=Vector2(center.x,center.z)
	var nearest:=Vector2(clampf(flat.x,anchor.x-half.x,anchor.x+half.x),clampf(flat.y,anchor.y-half.y,anchor.y+half.y))
	var outward:=flat-nearest
	if outward.length_squared()<.0001:outward=Vector2.DOWN
	var candidates: Array[Vector2]=[nearest+outward.normalized()*.35]
	for ratio in [-.85,0.0,.85]:
		candidates.append(anchor+Vector2(half.x+.35,half.y*ratio))
		candidates.append(anchor+Vector2(-half.x-.35,half.y*ratio))
		candidates.append(anchor+Vector2(half.x*ratio,half.y+.35))
		candidates.append(anchor+Vector2(half.x*ratio,-half.y-.35))
	candidates.sort_custom(func(left: Vector2,right: Vector2)->bool:return left.distance_squared_to(flat)<right.distance_squared_to(flat))
	var start_cell:=Vector2i(999,999)
	var selected:=Vector3.INF
	for candidate: Vector2 in candidates:
		var point:=Vector3(candidate.x,0,candidate.y)
		point.y=outpost_height(point)
		if not outpost_walkable(point) or not can_attack_line(point,center):continue
		if can_traverse(origin,point):selected=point;break
		if start_cell.x==999:start_cell=nearest_navigation_cell(origin,true)
		if start_cell.x==999:continue
		var end_cell:=nearest_navigation_cell(point,true)
		if end_cell.x!=999 and not hero_navigation.get_id_path(start_cell,end_cell).is_empty():selected=point;break
	if building_approach_cache.size()>=2048:building_approach_cache.clear()
	building_approach_cache[cache_key]=selected
	return selected

func segment_crosses_wall(origin: Vector2, direction: Vector2, block: Rect2) -> bool:
	# Continuous collision prevents short corner cuts that fixed samples can miss.
	var enter:=0.0
	var leave:=1.0
	for axis in 2:
		var low: float=block.position[axis]
		var high: float=block.end[axis]
		if absf(direction[axis])<.000001:
			if origin[axis]<=low or origin[axis]>=high:return false
		else:
			var first: float=(low-origin[axis])/direction[axis]
			var last: float=(high-origin[axis])/direction[axis]
			enter=maxf(enter,minf(first,last));leave=minf(leave,maxf(first,last))
			# Reject an intersection interval that lies entirely before or after
			# this movement segment. The previous check only compared the two
			# slab values, so a diagonal step beside the south gate could be
			# mistaken for crossing a side wall and freeze at the raised lip.
			if enter>=leave or leave<=0.0 or enter>=1.0:return false
	return leave>0 and enter<1

func update_towers(delta: float) -> void:
	var relay_bonus:=relay_count()
	for pad in world.tower_pads:
		if pad.level<=0:continue
		pad.cooldown=maxf(0.0,float(pad.cooldown)-delta)
		if pad.cooldown>0:continue
		var selected: BattleUnit
		var range_limit:=14.0+float(pad.level)*1.5+float(relay_bonus)*.55
		var nearest:=range_limit
		var breaker: BattleUnit
		var breaker_distance:=nearest
		var threat_target: BattleUnit
		var threat_rank:=99
		var threat_distance:=nearest
		for creature in enemies:
			if not is_instance_valid(creature) or not creature.alive:continue
			var distance: float=pad.position.distance_to(creature.position)
			# Priority changes the target, never the tower's strict attack radius.
			if distance>=range_limit:continue
			if distance<nearest:selected=creature;nearest=distance
			if pad.mode=="breaker" and creature.get_meta("threat","")=="breaker" and distance<breaker_distance:
				breaker=creature;breaker_distance=distance
			if pad.mode=="threat":
				var rank:=tower_threat_rank(String(creature.get_meta("threat","")))
				if creature.get_meta("threat","")=="summoner" and not creature.get_meta("summoner_active",false):rank=99
				if creature.get_meta("threat","")=="warder" and not creature.get_meta("warder_active",false):rank=99
				if rank<99 and (rank<threat_rank or (rank==threat_rank and distance<threat_distance)):
					threat_target=creature;threat_rank=rank;threat_distance=distance
		if breaker!=null:selected=breaker
		if pad.mode=="threat" and threat_target!=null:selected=threat_target
		if is_instance_valid(focus_target) and focus_target.alive and focus_time>0 and pad.position.distance_to(focus_target.position)<range_limit:
			selected=focus_target
		if selected==null:continue
		pad.cooldown=maxf(.38,1.05-float(pad.level)*.18)*specializations.cooldown_multiplier(pad)
		var tower: Node3D=pad.turret
		tower.look_at(Vector3(selected.position.x,tower.position.y,selected.position.z),Vector3.UP)
		var impact:=selected.position
		var damage:=42.0+float(pad.level)*17.0+float(relay_bonus)*2.5
		if countermeasure_tower_time>0.0:damage*=COUNTERMEASURE_TOWER_MULTIPLIER
		BattleVisuals.tower_shot(effects,pad.position+Vector3(0,2.1,0),impact+Vector3(0,1,0),pad.level)
		specializations.resolve_shot(pad,selected,enemies,damage,hero)
		if specializations.branch(pad)=="control":BattleVisuals.burst(effects,impact,3.2,Color("8bbfcf"),.25)
		elif specializations.branch(pad)=="piercing":BattleVisuals.sparks(effects,impact+Vector3.UP,Color("f5b271"),8)
	# A real control shot must cancel preparation before this frame is drawn.
	for summoner: Node3D in summoners:
		if is_instance_valid(summoner):summoner.revalidate_cast()
	for value: Variant in warders.duplicate():
		if is_instance_valid(value) and not value.is_queued_for_deletion() and value in warders:value.revalidate_cast()

func update_focus(delta: float) -> void:
	focus_cooldown=maxf(0.0,focus_cooldown-delta)
	if focus_time<=0:return
	focus_time=maxf(0.0,focus_time-delta)
	if not is_instance_valid(focus_target) or not focus_target.alive or focus_time<=0:
		clear_focus()
	elif is_instance_valid(focus_ring):
		var pulse:=0.0 if combat and combat.reduced_effects else sin(world.light_time*2.4)*.025
		focus_ring.scale=Vector3.ONE*(1.0+pulse)

func clear_focus() -> void:
	if is_instance_valid(focus_ring):focus_ring.queue_free()
	focus_ring=null
	focus_target=null
	focus_time=0.0

func focus_duration_seconds() -> float:
	var level := int(districts.live_level("signal_beacon")) if is_instance_valid(districts) else 0
	return FOCUS_DURATION + float(level) * 4.0

func focus_cooldown_seconds() -> float:
	var level := int(districts.live_level("signal_beacon")) if is_instance_valid(districts) else 0
	return maxf(12.0, FOCUS_COOLDOWN - float(level) * 4.0)

func refresh_focus_bonus() -> void:
	if focus_time>0.0:focus_time=minf(focus_time,focus_duration_seconds())
	if focus_cooldown>0.0:focus_cooldown=minf(focus_cooldown,focus_cooldown_seconds())

func issue_focus_order() -> bool:
	if phase!="day" and phase!="night":return false
	if focus_cooldown>0:return false
	var selected: BattleUnit
	var best:=3.0
	for creature in enemies:
		if not is_instance_valid(creature) or not creature.alive:continue
		if Vector2(creature.position.x,creature.position.z).distance_to(Vector2(hero.position.x,hero.position.z))>27:continue
		var distance:=Vector2(creature.position.x,creature.position.z).distance_to(Vector2(aim.x,aim.z))
		if distance<best:selected=creature;best=distance
	if selected==null:
		notify("将准星移到射程内的夜行体，再按 C 集火",2)
		return false
	var reachable:=false
	for pad in world.tower_pads:
		if pad.level<=0:continue
		var range_limit:=14.0+float(pad.level)*1.5+float(relay_count())*.55
		if pad.position.distance_to(selected.position)<range_limit:reachable=true;break
	if not reachable:
		notify("目标尚未进入防御塔射程",2)
		return false
	clear_focus()
	focus_target=selected
	focus_time=focus_duration_seconds()
	focus_cooldown=focus_cooldown_seconds()
	focus_ring=BattleVisuals.ring(selected,Vector3(0,.16,0),.95,Color("f0c66f"),.1)
	BattleVisuals.sparks(effects,selected.position+Vector3.UP,Color("f0c66f"),9)
	notify("塔群集火：%s · 持续 %.0f 秒 · 冷却 %.0f 秒" % [selected.title,focus_time,focus_cooldown],2)
	return true

func auto_attack() -> void:
	if phase not in ["day","night"] or not hero.alive:return
	if hero.attack_timer>0 or is_instance_valid(hero_attack_target):return
	if hero.hero_action=="inferno":return
	var closest: BattleUnit
	var best:=hero.attack_range+float(run.stats.range)
	for creature in enemies:
		if not is_instance_valid(creature) or not creature.alive:continue
		var distance:=creature.position.distance_to(hero.position)
		if distance<best:closest=creature;best=distance
	if closest==null:return
	hero_attack_step=attack_chain if attack_chain_time>0 else 0
	hero.hero_attack_variant=hero_attack_step
	hero.attack_timer=hero.attack_interval
	hero.attack_pose=1
	hero.play_action("attack",closest.position-hero.position)
	hero_attack_target=closest
	hero.hero_action_duration=minf(.70,hero.attack_interval*.90)
	hero_attack_delay=hero.hero_action_duration*.20
	if combat:combat.swing(hero.position,closest.position-hero.position,hero_attack_step,hero_attack_delay)

func update_combat_chains(delta: float) -> void:
	attack_chain_time=maxf(0.0,attack_chain_time-delta)
	if attack_chain_time<=0:attack_chain=0
	kill_chain_time=maxf(0.0,kill_chain_time-delta)
	if kill_chain_time<=0:kill_chain=0
	combat_milestone_time=maxf(0.0,combat_milestone_time-delta)

func cancel_hero_attack() -> void:
	hero_attack_target=null
	hero_attack_delay=0.0

func update_hero_attack(delta: float) -> void:
	if phase not in ["day","night"]:return
	if not is_instance_valid(hero_attack_target):
		cancel_hero_attack()
		return
	if not hero.alive or not hero_attack_target.alive:
		cancel_hero_attack()
		return
	hero_attack_delay=maxf(0.0,hero_attack_delay-delta)
	if hero_attack_delay>0:return
	var closest:=hero_attack_target
	cancel_hero_attack()
	# Contact resolves against the original target; leaving reach is a miss,
	# never an invisible hit on another creature during the draw-back.
	if closest.position.distance_to(hero.position)>hero.attack_range+float(run.stats.range)+.35:return
	attack_count+=1
	if attack_chain_time<=0:hero_attack_step=0
	var finisher:=hero_attack_step==2
	attack_chain=0 if finisher else hero_attack_step+1
	attack_chain_time=2.8
	var critical:=rng.randf()<float(run.stats.crit)
	var amount:=hero.damage
	if finisher:amount*=1.30
	if critical:amount*=1.75
	var old_hp:=closest.hp
	var impact_point:=closest.position
	var hit_direction:=(closest.position-hero.position).normalized()
	player_attack_resolving=true
	closest.hurt(amount,hero)
	player_attack_resolving=false
	var dealt:=maxf(0.0,old_hp-closest.hp)
	if combat:combat.impact(impact_point,hit_direction,dealt,critical,finisher)
	if not combat or not combat.reduced_effects:
		hero.visual_hit_stop=.055 if finisher or critical else .028
		if closest.alive:closest.visual_hit_stop=.055 if finisher or critical else .028
	if closest.alive:
		var push:=.30 if finisher else .12
		if closest.get_meta("threat","")=="breaker":push*=.30
		var pushed:=closest.position+Vector3(hit_direction.x,0,hit_direction.z)*push
		if can_traverse(closest.position,pushed):
			pushed.y=outpost_height(pushed);closest.position=pushed
	if (attack_count%3==0 if run.count("chain")>0 else run.count("core_storm")>0 and finisher):
		var chained:=0
		for other in enemies:
			if other==closest or not is_instance_valid(other) or not other.alive:continue
			if other.position.distance_to(closest.position)<5.0:
				player_attack_resolving=true
				other.hurt(amount*(.55 if run.count("chain")>0 else .30),hero)
				player_attack_resolving=false
				BattleVisuals.beam(effects,closest.position+Vector3.UP,other.position+Vector3.UP,Color("95d6e1"),.12)
				chained+=1
				if chained>=2:break
	if float(run.stats.lifesteal)>0:
		hero.hp=minf(hero.max_hp,hero.hp+maxf(0,old_hp-closest.hp)*float(run.stats.lifesteal))

func beacon_pulse() -> void:
	var hits:=0
	for creature in enemies:
		if not is_instance_valid(creature) or not creature.alive:continue
		if Vector2(creature.position.x,creature.position.z).length()<10.5:
			creature.hurt(34+day_number*9,hero)
			hits+=1
			if hits>=5:break
	if hits>0:BattleVisuals.burst(effects,Vector3(0,NightfallWorld.FORT_HEIGHT,0),10.5,Color("ffaa58"),.28)

func _on_creature_defeated(creature: BattleUnit, _source: BattleUnit) -> void:
	if is_instance_valid(discoveries) and not discoveries.cache_guards.on_defeated(creature):
		return
	specializations.forget_enemy(creature)
	kills+=1
	var combat_phase: String=return_phase if phase=="draft" else phase
	var reward_id: int=int(creature.get_meta("wave_reward_id",-1))
	var previous_kills: int=int(wave_rewards.snapshot(reward_id).get("kills",0))
	var scrap_gain: int=5
	if combat_phase=="night":
		scrap_gain=8 if run_mode=="teaching" else wave_rewards.defeat(creature)
		if phase=="night":districts.register_wreck(creature.get_instance_id(),creature.position)
	if creature.get_meta("summoned_reinforcement",false):scrap_gain=0
	scrap+=scrap_gain
	var ledger: Dictionary=wave_rewards.snapshot(reward_id)
	var bonus:=0
	# Only a newly accepted real ledger death can settle the challenge. A stale
	# callback after pause, actor removal or shutdown cannot replay a cleared row.
	if int(ledger.get("kills",0))==previous_kills+1:
		bonus=bounty.completion(reward_id,ledger,phase_time,
			phase=="night" and not quitting and not restart_pending and is_instance_valid(hero) and hero.alive and hero.hp>0.0 and beacon_hp>0.0)
	if bonus>0:
		scrap+=bonus
		notify("甲壳悬赏完成 · 额外 +%d 零件" % bonus,4)
	var wager_state: Dictionary=wave_wager.snapshot()
	if String(wager_state.get("state", "")) == "locked" and reward_id == int(wager_state.get("target_reward_id", -1)) and int(ledger.get("kills", 0)) == int(wager_state.get("target_count", 0)) and int(ledger.get("kills", 0)) == previous_kills + 1:
		var wager_result: Dictionary=wave_wager.settle_wave(String(wager_state.get("plan_signature", "")), reward_id, int(wager_state.get("target_count", 0)), int(ledger.get("kills", 0)), phase == "night" and not quitting and not restart_pending and is_instance_valid(hero) and hero.alive and hero.hp > 0.0 and beacon_hp > 0.0)
		if bool(wager_result.get("ok", false)):
			scrap += int(wager_result.get("wallet_delta", 0))
			notify("夜战押注派彩 · +%d零件" % int(wager_result.get("payout", 0)), 4)
	if player_attack_resolving and _source==hero:
		kill_chain=(kill_chain+1) if kill_chain_time>0 else 1
		kill_chain_time=6.0
		if combat:combat.kill(creature.position,scrap_gain)
		var thresholds: Array[int]=[3,6,10]
		var milestone_index:=thresholds.find(kill_chain)
		if milestone_index>=0:
			var extra_scrap: int=[9,14,22][milestone_index]
			scrap+=extra_scrap
			combat_milestone_title="%d 连斩 · %s" % [kill_chain,["余烬初燃","灯火燎原","长夜破晓"][milestone_index]]
			combat_milestone_detail="额外 +%d 零件" % extra_scrap
			combat_milestone_time=2.2
			if combat:combat.milestone(kill_chain,extra_scrap)
	if deaths:
		var source_position:=_source.global_position if is_instance_valid(_source) else creature.global_position-Vector3.FORWARD
		deaths.spawn(creature,source_position)
	else:BattleVisuals.burst(effects,creature.position,.9,Color("b37661"),.38)
	creature.visible=false
	creature.queue_free()

func growth_snapshot() -> Dictionary:
	return GrowthGuidanceScript.snapshot(self)

func request_upgrade() -> bool:
	if phase not in ["day","night"]:return false
	if run.pending<=0:
		if not run.has_available_upgrade():
			notify("当前强化已全部铭刻",2)
			return false
		var cost: int=run.memory_cost()
		if scrap<cost:
			notify("铭刻需要%d零件 · 还差%d" % [cost,cost-scrap],2)
			return false
		run.grant("零件铭刻 · 第%d次强化" % (run.memory_level+1))
		# Only commit the shared payment after a real legal offer exists.
		if not run.draft():return false
		scrap-=run.register_memory_upgrade()
	open_draft()
	return phase=="draft"

func _on_hero_defeated(_unit: BattleUnit, _source: BattleUnit) -> void:
	end_defeat("守望者倒下 · 灯塔无人防守")

func _on_hero_damaged(_unit: BattleUnit, source: BattleUnit) -> void:
	if run.count("thorns")>0 and is_instance_valid(source) and source.alive:
		source.hurt(18+hero.armor*.25,hero)

func _on_hero_damage_confirmed(_unit: BattleUnit, source: BattleUnit, hp_loss: float, shield_loss: float) -> void:
	var source_title: String=source.title if is_instance_valid(source) else String(_unit.get_meta("delayed_enemy_hit_title","未知攻击"))
	var losses: Array[String]=[]
	if shield_loss>0.0:losses.append("护盾 -%d" % maxi(1,roundi(shield_loss)))
	if hp_loss>0.0:losses.append("生命 -%d" % maxi(1,roundi(hp_loss)))
	hero_damage_flash_time=.62
	hero_damage_flash_text="受到%s · %s" % [source_title," · ".join(losses)]
	if combat:combat.damage_confirmed(hero.position,hp_loss,shield_loss,source_title)

func end_defeat(message: String) -> void:
	if phase=="ended":return
	_settle_wave_wager_loss("defeat")
	if is_instance_valid(discoveries):discoveries.cache_guards.clear()
	salvage_draw.clear()
	control_groups.clear()
	repairs.clear()
	bounty.expire()
	clear_lobbers()
	clear_summoners()
	clear_warders()
	cores.clear()
	specializations.reset_effects()
	if rally:rally.clear()
	if logistics:logistics.clear()
	if squads:squads.clear()
	if is_instance_valid(siege_boss):
		siege_boss.clear()
		siege_boss.queue_free()
		siege_boss=null
	phase="ended";victory=false;ending_key="defeat";notify(message,8)

func open_draft() -> void:
	if phase=="ended":return
	if phase=="day" or phase=="night":
		return_phase=phase
		# A second gathering tap must not spend a reroll on the newly opened card UI.
		draft_reroll_ready_at=float(Time.get_ticks_msec())*.001+.6
	if run.draft():
		selection_dragging=false
		if rally:rally.cancel_setting()
		phase="draft"

func choose_card(index: int) -> bool:
	if phase!="draft":return false
	var card:=run.choose(index)
	if card.is_empty():return false
	if opening_night_pending:run_mode_locked=true
	var old_max:=hero.max_hp
	hero.max_hp=850+float(run.stats.health)
	hero.hp=minf(hero.max_hp,hero.hp+maxf(0,hero.max_hp-old_max))
	hero.damage=58+float(run.stats.attack)
	hero.armor=10+float(run.stats.armor)
	hero.speed=HERO_MOVE_SPEED+float(run.stats.speed)
	hero.attack_interval=.8/(1.0+float(run.stats.attack_speed))
	max_mana=300+float(run.stats.mana)
	mana=minf(max_mana,mana+maxf(0,float(run.stats.mana)))
	notify("铭刻："+str(card.name),3)
	if run.pending>0:
		open_draft()
	elif opening_night_pending:
		opening_night_pending=false
		start_night()
		notify("第 1 夜 · 两座守门塔已就位，B 布障 / R 灯焰；守住南门",6)
	elif day_start_pending:begin_day()
	else:phase=return_phase
	return true

func nearest_salvage() -> int:
	var selected:=-1
	var best:=2.4
	for i in world.salvage.size():
		var item:=world.salvage[i]
		if item.collected:continue
		var distance:=hero.position.distance_to(item.position)
		if distance<best:selected=i;best=distance
	return selected

func nearest_tower_pad() -> int:
	var selected:=-1
	var best:=2.6
	for i in world.tower_pads.size():
		if bool(world.tower_pads[i].get("removed",false)):continue
		var distance: float=hero.position.distance_to(world.tower_pads[i].position)
		if distance<best:selected=i;best=distance
	return selected

func toggle_tower_mode() -> bool:
	if phase!="day" and phase!="night":return false
	var index:=nearest_tower_pad()
	if index<0 or world.tower_pads[index].level<=0:return false
	var pad: Dictionary=world.tower_pads[index]
	pad.mode={"nearest":"breaker","breaker":"threat","threat":"nearest"}.get(String(pad.mode),"nearest")
	notify("防御塔目标：%s" % tower_mode_label(String(pad.mode)),2)
	return true

func tower_threat_rank(threat: String) -> int:
	return {"summoner":0,"warder":1,"light_eater":2,"lobber":3,"sapper":4,"breaker":5,"shellguard":6}.get(threat,99)

func tower_mode_label(mode: String) -> String:
	return {"nearest":"最近目标","breaker":"破城优先","threat":"威胁优先"}.get(mode,"最近目标")

func choose_tower_specialization(kind: String) -> bool:
	var index:=nearest_tower_pad()
	if index<0:return false
	var result: Dictionary=specializations.choose(world.tower_pads[index],kind,scrap,phase)
	if not result.ok:notify(result.reason,2);return false
	scrap=result.scrap
	BattleVisuals.burst(effects,world.tower_pads[index].position,2.2,Color("80bfd3") if kind=="control" else Color("efae67"),.4)
	notify("已改装：牵制群敌" if kind=="control" else "已改装：重敌破甲",2)
	return true

func repair_tower() -> bool:
	if phase!="day" and phase!="night":return false
	var index:=nearest_tower_pad()
	if index<0:return false
	var pad: Dictionary=world.tower_pads[index]
	if pad.level<=0 or pad.hp>=pad.max_hp:return false
	var cost: int=districts.repair_cost(20)
	if scrap<cost:
		notify("修复防御塔需要 %d 零件" % cost,2)
		return false
	scrap-=cost
	pad.hp=minf(pad.max_hp,float(pad.hp)+100.0)
	if pad.hp>=pad.max_hp:repairs.stop("tower",index)
	if is_instance_valid(pad.damage_ring):pad.damage_ring.visible=pad.hp<pad.max_hp*.6
	BattleVisuals.burst(effects,pad.position+Vector3(0,1.0,0),1.8,Color("82d4b9"),.35)
	notify("防御塔已修复 · 耐久 %d/%d" % [ceili(pad.hp),ceili(pad.max_hp)],2)
	return true

func build_district(kind: String) -> bool:
	return construction.begin(kind) if is_instance_valid(construction) else false

func upgrade_district() -> bool:
	var result: Dictionary=districts.upgrade(districts.nearest())
	if not result.ok:notify(result.reason,2);return false
	if squads:squads.set_health_multiplier(districts.squad_health_multiplier())
	notify("%s升至二级 · 耐久恢复" % String(Catalog.building(String(result.kind)).title),3)
	return true

func near_squad_controls() -> bool:
	if not is_instance_valid(hero):return false
	return Layout.contains_castle(hero.position,.1) and hero.position.y >= 4.8

func hire_shield_squad() -> bool:
	return train_troop("shield")

func hire_ranged_squad() -> bool:
	return train_troop("ranged")

func train_troop(kind: String) -> bool:
	if phase not in ["day","night"]:return false
	var barracks_id: int=rally.selection_id() if rally else -1
	var result: Dictionary=squads.enqueue(kind,barracks_id)
	if not result.ok:notify(String(result.reason),2);return false
	notify("%s加入营%d训练队列 · -%d零件" % [String(Catalog.troop(kind).get("title","部队")),int(result.barracks_id)+1,int(result.cost)],3)
	return true

func cancel_troop_training(barracks_id: int, queue_index: int) -> bool:
	var result: Dictionary=squads.cancel_training(barracks_id,queue_index)
	if not result.ok:notify(String(result.reason),2);return false
	notify("已取消训练 · 退回%d零件" % int(result.get("refund",result.get("cost",0))),2)
	return true

func toggle_squad_order() -> bool:
	if phase!="day" and phase!="night":return false
	if squads.selected_count()>0:
		var guard: Dictionary=squads.command_guard(aim)
		notify(String(guard.reason),2)
		return bool(guard.ok)
	var snapshot: Dictionary=squads.snapshot()
	if int(snapshot.count)<=0:
		notify("先建兵营，再用U/I/N训练部队",2)
		return false
	var hold := true
	for row: Dictionary in snapshot.squads:
		if String(row.order)!="hold":hold=false;break
	var order := "recall" if hold else "hold"
	var result: Dictionary=squads.set_order(order)
	if not result.ok:
		notify(result.reason,2)
		return false
	notify("全军%s" % ("驻守南门" if order=="hold" else "撤回灯塔"),2)
	return true

func refill_squads() -> bool:
	if phase!="day":
		notify("只能在白昼付费补员休整",2)
		return false
	var result: Dictionary=squads.refill()
	if not result.ok:
		notify(result.reason,2)
		return false
	notify("小队补员休整完成 · -%d零件" % result.cost,3)
	return true

func near_gate_controls() -> bool:
	return Vector2(hero.position.x,hero.position.z).distance_to(Vector2(0,Layout.RAMP_TOP))<3.4

func create_gate_barricade() -> void:
	var point:=Vector3(0,0,12.5+Layout.EXPANSION_OFFSET)
	point.y=world.terrain_height(point)
	gate_barricade=world.place("res://assets/models/barricade.glb",point,1.55,0)
	gate_barricade.visible=false
	gate_barricade_ring=BattleVisuals.ring(world,point+Vector3(0,.12,0),2.3,Color("e2a665"),.07)
	gate_barricade_ring.visible=false

func build_gate_barricade() -> bool:
	if phase!="day" and phase!="night":return false
	if not near_gate_controls():return false
	if gate_barricade_hp>0:
		notify("南门路障仍可抵挡夜行体",2)
		return false
	if scrap<BARRICADE_COST:
		notify("部署路障需要 %d 零件" % BARRICADE_COST,2)
		return false
	scrap-=BARRICADE_COST
	gate_barricade_hp=BARRICADE_MAX
	gate_barricade.visible=true
	gate_barricade_ring.visible=true
	gate_barricade_ring.material_override.albedo_color=Color("e2a665")
	BattleVisuals.burst(effects,gate_barricade.position,2.7,Color("e2a665"),.45)
	notify("南门路障已部署 · 耐久 %d" % int(BARRICADE_MAX),2)
	return true

func damage_gate_barricade(amount: float) -> void:
	if phase not in ["day","night"] or quitting or restart_pending or shutting_down or gate_barricade_hp<=0.0 or not is_finite(amount) or amount<=0.0:return
	var multiplier: float=districts.holdfast_damage_multiplier() if is_instance_valid(districts) else 1.0
	gate_barricade_hp=maxf(0.0,gate_barricade_hp-amount*multiplier)
	BattleVisuals.sparks(effects,gate_barricade.position+Vector3(0,1.0,0),Color("e5ad73"),5)
	gate_barricade_ring.material_override.albedo_color=Color("d35f54") if gate_barricade_hp<BARRICADE_MAX*.4 else Color("e2a665")
	if gate_barricade_hp>0:return
	clear_gate_barricade()
	BattleVisuals.burst(effects,gate_barricade.position,3.5,Color("d97855"),.5)
	notify("南门路障被击碎 · 入口暴露",3)

func clear_gate_barricade() -> void:
	gate_barricade_hp=0.0
	gate_barricade.visible=false
	gate_barricade_ring.visible=false

func create_gate_trap_visuals() -> void:
	for i in GATE_TRAP_MAX:
		var point:=Vector3(0,0,8.7+Layout.EXPANSION_OFFSET+float(i)*.8)
		point.y=world.terrain_height(point)+.12
		var mark:=BattleVisuals.ring(effects,point,.46,Color("e99552"),.07)
		mark.visible=false
		gate_trap_marks.append(mark)
	gate_trap_light=OmniLight3D.new()
	gate_trap_light.position=Vector3(0,world.terrain_height(Vector3(0,0,9.5+Layout.EXPANSION_OFFSET))+.5,9.5+Layout.EXPANSION_OFFSET)
	gate_trap_light.light_color=Color("ff9b50")
	gate_trap_light.omni_range=6.0
	gate_trap_light.light_energy=0
	gate_trap_light.shadow_enabled=false
	effects.add_child(gate_trap_light)

func show_gate_trap_charges() -> void:
	for i in gate_trap_marks.size():gate_trap_marks[i].visible=i<gate_trap_charges
	gate_trap_light.light_energy=.65 if gate_trap_charges>0 else 0.0

func arm_gate_trap() -> bool:
	if phase!="day" and phase!="night":return false
	if not near_gate_controls():return false
	if gate_trap_charges>=GATE_TRAP_MAX:
		notify("南门火焰机关已装满",2)
		return false
	if scrap<GATE_TRAP_COST:
		notify("零件不足 · 装填机关需要 %d" % GATE_TRAP_COST,2)
		return false
	scrap-=GATE_TRAP_COST
	gate_trap_charges+=1
	show_gate_trap_charges()
	BattleVisuals.sparks(effects,Vector3(0,world.terrain_height(Vector3(0,0,9.5+Layout.EXPANSION_OFFSET))+1,9.5+Layout.EXPANSION_OFFSET),Color("f4ae63"),9)
	notify("南门火焰机关已装填 · %d/%d" % [gate_trap_charges,GATE_TRAP_MAX],2)
	return true

func update_gate_trap(delta: float) -> void:
	gate_trap_cooldown=maxf(0.0,gate_trap_cooldown-delta)
	if phase!="night" or gate_trap_charges<=0 or gate_trap_cooldown>0:return
	for creature in enemies:
		if not is_instance_valid(creature) or not creature.alive:continue
		if absf(creature.position.x)>2.2 or creature.position.z<8.5+Layout.EXPANSION_OFFSET or creature.position.z>10.8+Layout.EXPANSION_OFFSET:continue
		gate_trap_charges-=1
		gate_trap_cooldown=.8
		show_gate_trap_charges()
		var point:=Vector3(0,world.terrain_height(Vector3(0,0,9.5+Layout.EXPANSION_OFFSET)),9.5+Layout.EXPANSION_OFFSET)
		BattleVisuals.burst(effects,point,4.6,Color("ff9d51"),.55)
		for target in enemies:
			if is_instance_valid(target) and target.alive and Vector2(target.position.x,target.position.z).distance_to(Vector2(0,9.5+Layout.EXPANSION_OFFSET))<4.6:
				target.hurt(190.0,hero)
		notify("南门机关引爆 · 剩余 %d 发" % gate_trap_charges,2)
		return

func nearest_relay() -> int:
	var selected:=-1
	var best:=3.2
	for i in world.relays.size():
		if world.relays[i].activated:continue
		var distance: float=hero.position.distance_to(world.relays[i].position)
		if distance<best:selected=i;best=distance
	return selected

func tower_count() -> int:
	var count:=0
	for pad in world.tower_pads:
		if pad.level>0:count+=1
	return count

func relay_count() -> int:
	var count:=0
	for relay in world.relays:
		if relay.activated:count+=1
	return count

func remaining_nests() -> int:
	var count:=0
	for nest in world.nests:
		if not nest.cleansed:count+=1
	return count

func cleansed_nests() -> int:
	return world.nests.size()-remaining_nests()

func nearest_nest() -> int:
	if phase!="day":return -1
	var selected:=-1
	var best:=3.6
	for i in world.nests.size():
		if world.nests[i].cleansed:continue
		var distance: float=hero.position.distance_to(world.nests[i].position)
		if distance<best:selected=i;best=distance
	return selected

func nest_guarded(point: Vector3) -> bool:
	for creature in enemies:
		if is_instance_valid(creature) and creature.alive and creature.position.distance_to(point)<6.5:return true
	return false

func gate_pressure() -> int:
	var count:=0
	for creature in enemies:
		if is_instance_valid(creature) and creature.alive and creature.position.z<Layout.RAMP_END+3.5 and creature.position.z>0:count+=1
	return count

func contract_interaction_prompt(action: Dictionary) -> String:
	var source: Dictionary=action.source
	if String(action.get("kind",""))=="bonus_discovery":
		return "F 带回追加%s · 返回灯塔领取 +%d 零件" % [contracts.BONUS_TITLES.get(String(source.get("kind","")),"补给"),int(contracts.bonus_target.get("scrap",0))]
	match contracts.kind:
		"salvage":return "F 采集委托废料 · +%d 零件" % (int(source.amount)+3)
		"generator":
			if String(source.state)=="ready":return "F 启动指定发电机 · 守住灯区 12 秒"
			var ratio:=clampf(float(source.progress)/12.0,0.0,1.0)
			return "委托能源交接 · 充能 %d%% · %s" % [roundi(ratio*100.0),"清除来袭" if expeditions.guards_alive(source) else "守住灯区"]
		"escort":
			if String(source.state)=="waiting":return "F 接回指定哨兵 · 日落前经南门返家"
			return "委托护送 · %s跟随中 · 返回灯塔" % String(source.scout_name)
		"nest":
			return "委托封巢 · 先清除夜巢守卫" if nest_guarded(source.position) else "F 封闭指定夜巢 · +90 零件"
	return ""

func interaction_prompt() -> String:
	if construction and construction.active and phase in ["day","night"]:
		var placement: Dictionary=construction.snapshot()
		return "Y 选址 · %s · 左键/F确认 · 右键/Esc取消" % String(placement.reason)
	if phase!="day" and phase!="night":return ""
	var contract_action:=contracts.active_target_interaction()
	if not contract_action.is_empty():return contract_interaction_prompt(contract_action)
	var expedition_prompt:=expeditions.interaction_prompt()
	if expedition_prompt!="":return expedition_prompt
	var discovery_prompt: String=discoveries.interaction_prompt()
	if discovery_prompt!="":return discovery_prompt
	var wildlife_prompt: String=wildlife.interaction_prompt()
	if wildlife_prompt!="":return wildlife_prompt
	var cache:=nearest_salvage()
	if cache>=0:return "F  搜集废墟零件 · +%d 零件" % (int(world.salvage[cache].amount)+3)
	var nest_index:=nearest_nest()
	if nest_index>=0:
		return "清除夜巢附近的守卫" if nest_guarded(world.nests[nest_index].position) else "F  封闭夜巢 · +90 零件，减轻夜袭"
	if Vector2(hero.position.x,hero.position.z).length()<4.2 and beacon_hp<BEACON_MAX and scrap>=beacon_repair_cost():
		return "F  消耗 %d 零件修复灯塔" % beacon_repair_cost()
	if nearest_relay()>=0:return "F  修复旧通信塔 · +85 零件"
	var pad_index:=nearest_tower_pad()
	if pad_index>=0:
		var level: int=world.tower_pads[pad_index].level
		var zone_label: String="核心防线 · " if String(world.tower_pads[pad_index].get("zone","outer"))=="core" else ""
		if level==0:return "F  %s建造自动防御塔 · 消耗 %d 零件" % [zone_label,districts.tower_cost(TOWER_COSTS[0])]
		var mode_label: String=tower_mode_label(String(world.tower_pads[pad_index].mode))
		var durability: String="%d/%d" % [ceili(world.tower_pads[pad_index].hp),ceili(world.tower_pads[pad_index].max_hp)]
		var repair_hint: String=" · H 修复%d" % districts.repair_cost(20) if world.tower_pads[pad_index].hp<world.tower_pads[pad_index].max_hp else ""
		if level>=3:return "%s塔耐久 %s%s · G %s · 满级" % [zone_label,durability,repair_hint,mode_label]
		return "%s塔耐久 %s · F 升级%d%s · G %s" % [zone_label,durability,districts.tower_cost(TOWER_COSTS[level]),repair_hint,mode_label]
	if near_gate_controls() and gate_trap_charges<GATE_TRAP_MAX:
		return "B 路障%s · T 火焰机关 %d/%d" % [" %d/%d" % [ceili(gate_barricade_hp),int(BARRICADE_MAX)] if gate_barricade_hp>0 else " 65零件",gate_trap_charges,GATE_TRAP_MAX]
	if near_gate_controls():return "B  南门路障 %d/%d" % [ceili(gate_barricade_hp),int(BARRICADE_MAX)] if gate_barricade_hp>0 else "B  部署南门路障 · 65 零件"
	var district_index: int=districts.nearest()
	if district_index>=0:
		var plot: Dictionary=districts.plots[district_index]
		var definition:=Catalog.building(String(plot.kind))
		var title:=String(definition.title)
		if int(plot.level)==0:return "F 重建%s · %d零件" % [title,int(definition.cost)]
		return "%s %d/%d · %s" % [title,ceili(plot.hp),ceili(plot.max_hp),"F升级80" if int(plot.level)<2 else "已满级"]
	return ""

func _squads_all_holding(snapshot: Dictionary) -> bool:
	if int(snapshot.count)<=0:return false
	for row: Dictionary in snapshot.squads:
		if String(row.order)!="hold":return false
	return true

func interact_contract_target(action: Dictionary) -> bool:
	var index:=int(action.index)
	if String(action.get("kind",""))=="bonus_discovery":
		return discoveries.interact_index(index)
	match contracts.kind:
		"salvage":
			return collect_salvage(index)
		"generator":
			if String(action.state)=="ready":
				var started:=expeditions.start_generator(index)
				if started:contracts.on_action()
				return started
			# Consume F while the marked site is charging; never start a nearby
			# unrelated action or restart the same generator.
			contracts.on_action()
			return true
		"escort":
			if String(action.state)=="waiting":
				var started:=expeditions.start_camp(index)
				if started:contracts.on_action()
				return started
			contracts.on_action()
			return true
		"nest":
			return interact_nest(index)
	return false

func collect_salvage(index: int=-1) -> bool:
	if index<0:index=nearest_salvage()
	if index<0 or index>=world.salvage.size() or world.salvage[index].collected:return false
	world.salvage[index].collected=true
	world.salvage[index].respawn=SALVAGE_REFRESH
	(world.salvage[index].node as Node3D).visible=false
	var amount: int=world.salvage[index].amount
	grant_exploration_reward("废墟搜集",world.salvage[index].position,amount+3,0.0,0.0,"salvage")
	return true

func interact_nest(index: int=-1) -> bool:
	if index<0:index=nearest_nest()
	if index<0 or index>=world.nests.size():return false
	var nest: Dictionary=world.nests[index]
	if nest.cleansed:return false
	if nest_guarded(nest.position):
		notify("先清除夜巢周围的守卫",2)
		return false
	nest.cleansed=true
	contracts.on_action()
	var active_nest: Node3D=nest.node
	var seal: Node3D=nest.sealed_node
	seal.visible=true
	var collapse:=create_tween()
	collapse.tween_property(active_nest,"scale",Vector3.ONE*.02,.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	collapse.tween_callback(active_nest.hide)
	var reveal:=create_tween()
	reveal.tween_property(seal,"scale",Vector3.ONE,.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	create_tween().tween_property(nest.light,"light_energy",0.0,.4)
	create_tween().tween_property(nest.sealed_light,"light_energy",.8,.6)
	scrap+=90
	var bounty_removed:=false
	if phase=="day":
		bounty_removed=prepare_next_night_plan(false)
	BattleVisuals.burst(effects,nest.position,3.2,Color("79c7bb"),.6)
	var result_text:="夜巢已封闭 · +90 零件，下一夜预告已按公开规则减少普通随从" if phase=="day" else "夜巢已封闭 · +90 零件，今夜来袭减弱"
	if bounty_removed:result_text+="；悬赏取消：普通随从不足两名，请重新选择反制"
	notify(result_text,4)
	return true

func interact() -> bool:
	if construction and construction.active:return construction.confirm()
	if phase!="day" and phase!="night":return false
	var contract_action:=contracts.active_target_interaction()
	if not contract_action.is_empty():return interact_contract_target(contract_action)
	if expeditions.interaction_prompt()!="":
		var acted:=expeditions.interact()
		if acted:contracts.on_action()
		return acted
	if discoveries.interaction_prompt()!="":return discoveries.interact()
	if wildlife.interaction_prompt()!="":return wildlife.interact()
	var index:=nearest_salvage()
	if index>=0:return collect_salvage(index)
	var nest_index:=nearest_nest()
	if nest_index>=0:return interact_nest(nest_index)
	if Vector2(hero.position.x,hero.position.z).length()<4.2 and beacon_hp<BEACON_MAX and scrap>=beacon_repair_cost():
		scrap-=beacon_repair_cost()
		beacon_hp=minf(BEACON_MAX,beacon_hp+150)
		BattleVisuals.burst(effects,Vector3(0,NightfallWorld.FORT_HEIGHT,0),3.5,Color("ffb861"),.45)
		notify("灯塔外壳已修复 · +150 耐久")
		return true
	var relay_index:=nearest_relay()
	if relay_index>=0:
		world.relays[relay_index].activated=true
		scrap+=85
		BattleVisuals.burst(effects,world.relays[relay_index].position,3.0,Color("78cbd0"),.55)
		notify("通信塔重新亮起 · +85 零件，防御塔射程与火力提升",4)
		return true
	var pad_index:=nearest_tower_pad()
	if pad_index>=0:return build_or_upgrade_tower(pad_index)
	var district_index: int=districts.nearest()
	if district_index<0:return false
	var plot: Dictionary=districts.plots[district_index]
	if int(plot.level)==0:return build_structure_at(plot.position,String(plot.kind))
	return upgrade_district()

func toggle_tower_construction() -> bool:
	if not construction:return false
	if rally:rally.cancel_setting()
	if construction.active:
		construction.cancel()
		return true
	if not construction.begin():return false
	hud.dismiss_details()
	selection_dragging=false
	notify("格子建设 · 1/2/3选择当前页 · PgUp/PgDn翻页 · 左键/F建造",3)
	return true

func build_structure_at(point: Vector3, kind: String) -> bool:
	if phase not in ["day","night"] or not is_instance_valid(construction):return false
	if kind=="tower":return build_tower_at(point)
	var placement: Dictionary=construction.validity(point,-1,kind)
	if not bool(placement.valid):notify(String(placement.reason),2);return false
	var result: Dictionary=districts.build_at(placement.point,kind)
	if not bool(result.ok):notify(String(result.reason),2);return false
	notify("%s建成 · -%d零件 · 可继续放置" % [String(placement.title),int(result.cost)],3)
	return true

func demolition_at(point: Vector3) -> Dictionary:
	return DemolitionScript.quote_at(self,point)

func sell_structure_at(point: Vector3) -> bool:
	return DemolitionScript.sell_at(self,point)

func build_tower_at(point: Vector3) -> bool:
	if not construction:return false
	var placement: Dictionary=construction.validity(point,-1,"tower")
	if not bool(placement.valid):
		notify(String(placement.reason),2)
		return false
	var index: int=-1
	for i in world.tower_pads.size():
		var candidate: Dictionary=world.tower_pads[i]
		if bool(candidate.get("removed",false)):continue
		# Reuse only an effectively identical, still-valid suggestion. Snapping
		# a free point to a nearby foundation can violate spacing after a green
		# preview and would otherwise move the tower away from the chosen point.
		if int(candidate.level)==0 and not bool(candidate.get("free_built",false)) and (candidate.position as Vector3).distance_to(placement.point)<=.01 and bool(construction.validity(candidate.position,i,"tower").valid):
			index=i
			break
	if index<0:index=world.add_tower_pad(placement.point,"castle")
	if index<0:return false
	if not build_or_upgrade_tower(index):return false
	world.tower_pads[index]["free_built"]=true
	return true

func build_or_upgrade_tower(index: int) -> bool:
	if phase not in ["day","night"] or index<0 or index>=world.tower_pads.size():return false
	var pad: Dictionary=world.tower_pads[index]
	if bool(pad.get("removed",false)):return false
	var level: int=int(pad.level)
	if level>=3:return false
	if level==0:
		var placement: Dictionary=construction.validity(pad.position,index,"tower")
		if not bool(placement.valid):
			notify(String(placement.reason),2)
			return false
	var tower_cost: int=districts.tower_cost(TOWER_COSTS[level])
	if scrap<tower_cost:
		notify("零件不足 · 需要 %d" % tower_cost,2)
		return false
	if level==0:
		pad.turret=world.place("res://assets/models/auto_turret.glb",pad.position,1.0,0)
		if not is_instance_valid(pad.damage_ring):pad.damage_ring=BattleVisuals.ring(world,pad.position+Vector3(0,.12,0),1.26,Color("d75f58"),.06)
	scrap-=tower_cost
	pad["paid_investment"]=tower_cost if level==0 else maxi(0,int(pad.get("paid_investment",0)))+tower_cost
	pad.level=level+1
	pad.max_hp=280.0+float(level)*110.0
	pad.hp=pad.max_hp
	repairs.stop("tower",index)
	if is_instance_valid(pad.damage_ring):pad.damage_ring.visible=false
	(pad.turret as Node3D).scale=Vector3.ONE*(1.0+float(level)*.12)
	pad["free_built"]=true
	if level==0:refresh_construction_navigation()
	BattleVisuals.burst(effects,pad.position,2.3,Color("e3ac62"),.35)
	notify("自动防御塔 %s · 等级 %d" % ["建成" if level==0 else "升级",pad.level])
	return true

func skill_status(slot: int) -> String:
	if cooldowns[slot]>0:return "%.1f s" % cooldowns[slot]
	if mana<COSTS[slot]:return "法力不足"
	return "就绪"

func skill_rejection(slot: int, reason: String) -> void:
	var key: String="%d:%s" % [slot,reason]
	var now:=float(Time.get_ticks_msec())*.001
	if key==skill_notice_key and now<skill_notice_until:return
	skill_notice_key=key;skill_notice_until=now+1.2
	var names: Array[String]=["Q 斩光","W 屏障","E 突进","R 灯焰","X 治疗"]
	if reason=="cooldown":notify("%s · 冷却还剩 %.1f 秒" % [names[slot],cooldowns[slot]],1.8)
	else:notify("%s · 法力不足（%d / 需要 %d）" % [names[slot],floori(mana),int(COSTS[slot])],2.0)

func cast(slot: int, feedback: bool = false) -> bool:
	if slot<0 or slot>=COSTS.size():return false
	if phase!="day" and phase!="night":return false
	if cooldowns[slot]>0:
		if feedback:skill_rejection(slot,"cooldown")
		return false
	if mana<COSTS[slot]:
		if feedback:skill_rejection(slot,"mana")
		return false
	# Sword and ultimate actions override their own pending basic wind-up;
	# movement, the shield and healing remain usable during a normal strike.
	if slot in [0,2,3]:cancel_hero_attack()
	cooldowns[slot]=COOLDOWNS[slot]*run.cooldown_factor()
	mana-=COSTS[slot]
	var direction:=(aim-hero.position).normalized()
	if direction.length()<.01:direction=Vector3.RIGHT
	match slot:
		0:
			hero.hero_attack_variant=0
			hero.play_action("attack",direction)
			var split_blades:=run.count("split")>0
			var blade_directions: Array[Vector3]=[direction]
			if split_blades:
				blade_directions=[direction.rotated(Vector3.UP,-.22),direction,direction.rotated(Vector3.UP,.22)]
			for blade_direction: Vector3 in blade_directions:
				BattleVisuals.slash_arc(effects,hero.position,blade_direction)
				skill_lights.emit_skill(0,hero.position,blade_direction)
				for creature in enemies:
					if not is_instance_valid(creature) or not creature.alive:continue
					var to_creature:=creature.position-hero.position
					var distance:=to_creature.length()
					if distance>=11.0:continue
					var alignment:=blade_direction.dot(to_creature.normalized())
					# The three blades overlap slightly at the centre, so a close
					# target can receive all three independent 70% hits while targets
					# on either side can be split across the fan.
					var in_blade: bool=alignment>.965 if split_blades else direction.dot(to_creature.normalized())>.78
					if not in_blade:continue
					var burst_damage: float=110+float(run.stats.spell)*.85
					creature.hurt(burst_damage*(.70 if split_blades else 1.0),hero)
					cores.mark(creature)
		1:
			hero.shield=(150+float(run.stats.spell)*.5)*float(run.stats.shield)
			hero.shield_time=4
			cores.arm_guard()
			var shield_radius: float=4.2*float(run.stats.area)
			BattleVisuals.burst(effects,hero.position,shield_radius,Color("70cbd5"),.45)
			skill_lights.emit_skill(1,hero.position,direction,Vector3.INF,shield_radius)
			for creature in enemies:
				if is_instance_valid(creature) and creature.alive and creature.position.distance_to(hero.position)<shield_radius:
					creature.hurt(78+float(run.stats.spell)*.65,hero)
		2:
			var origin:=hero.position
			var requested_target:=hero.position+direction*dash_distance()
			# Dash uses the same visual clearance corridor as keyboard/click
			# movement. Without this resolution, a diagonal E from the raised
			# ramp or courtyard can place the hero's cape inside a retaining wall,
			# which makes the next ordinary frame look like terrain snagging.
			var target:=hero_safe_destination(requested_target,origin)
			if can_traverse(origin,target):
				target.y=outpost_height(target)
				hero.position=target;move_goal=target;hero_path.clear()
				BattleVisuals.beam(effects,origin+Vector3.UP,target+Vector3.UP,Color("79dce0"),.25)
				skill_lights.emit_skill(2,origin,direction,target)
		3:
			var fire_radius: float=8.0*float(run.stats.area)
			var fire_damage: float=260+float(run.stats.spell)*1.2
			hero.play_action("inferno",direction)
			BattleVisuals.lantern_inferno(effects,hero.position,fire_radius,false)
			skill_lights.emit_skill(3,hero.position,direction,Vector3.INF,fire_radius)
			for creature in enemies:
				if is_instance_valid(creature) and creature.alive and creature.position.distance_to(hero.position)<fire_radius:
					creature.hurt(fire_damage+cores.consume(creature),hero)
			if run.count("echo")>0:
				delayed_blasts.append({"position":hero.position,"radius":fire_radius,"damage":fire_damage*.5,"delay":.55})
		4:
			hero.hp=minf(hero.max_hp,hero.hp+hero.max_hp*.32)
			BattleVisuals.burst(effects,hero.position,2.0,Color("7acfae"),.6)
			skill_lights.emit_skill(4,hero.position,direction)
	return true

func dash_distance() -> float:
	return 6.0+float(run.count("stride"))*.8

func homecoming_summary() -> Dictionary:
	var people := clampi(survivors_rescued,0,2)
	var names: Array[String]=[]
	if expeditions:
		for camp in expeditions.camps:
			if camp.state=="delivered":names.append(camp.scout_name)
	var name_record: String=" · "+"、".join(names) if not names.is_empty() else ""
	var response: String
	if phase=="ended" and not victory:
		response="返家的 %d 人曾与你并肩；这一夜没守住，还可以重新出发。" % people if people>0 else "荒原的求救声还在。下一次守望，也为他们留一条回家的路。"
	else:
		response=["荒原里还有人在等待。第四次日出，也是再次出发的机会。",
			"庭院多了一盏灯。下一次修灯，有人为你递来零件。",
			"两个人都回到灯下。守住这个家，已经不再是你一个人的事。"][people]
	return {"people":people,"names":names,"record":"返家记录 %d / 2%s · 协作修灯 %d 零件" % [people,name_record,beacon_repair_cost()],
		"response":response,"repair_cost":beacon_repair_cost()}

func hit_area(point: Vector3,radius: float,amount: float) -> void:
	for creature in enemies:
		if is_instance_valid(creature) and creature.alive and creature.position.distance_to(point)<radius:
			creature.hurt(amount,hero)

func ground_point(screen: Vector2) -> Vector3:
	ground_point_queries+=1
	var origin:=camera.project_ray_origin(screen)
	var direction:=camera.project_ray_normal(screen)
	var flat_result: Variant=Plane(Vector3.UP,0).intersects_ray(origin,direction)
	if flat_result is Vector3:
		var flat_seed: Vector3=flat_result
		var terrain_result:=ray_terrain_intersection(origin,direction,flat_seed)
		var ramp_click: Vector3=resolve_ramp_click(flat_seed,terrain_result)
		if ramp_click!=Vector3.INF:return ramp_click
		return terrain_result
	return hero.position

func ray_terrain_intersection(origin: Vector3, direction: Vector3, flat_seed: Vector3) -> Vector3:
	# Fixed-point plane updates oscillate on the steep outer slope: the ray can
	# alternate between y=0 and y=5 instead of converging. Find the first
	# surface crossing along the actual camera ray, then refine it by bisection.
	# The y=0 hit bounds the raised terrain because every authored surface is at
	# or above the outer ground.
	var flat_t:=origin.distance_to(flat_seed)
	if flat_t<=.001:return flat_seed
	var previous_t:=0.0
	var previous_value:=origin.y-outpost_height(origin)
	var lower:=0.0
	var upper:=flat_t
	var bracketed:=false
	const SAMPLES:=40
	for index in range(1,SAMPLES+1):
		var current_t:=flat_t*float(index)/float(SAMPLES)
		var point:=origin+direction*current_t
		var current_value:=point.y-outpost_height(point)
		if current_value<=0.0 or previous_value>=0.0 and current_value<=0.0:
			lower=previous_t;upper=current_t;bracketed=true;break
		previous_t=current_t;previous_value=current_value
	if not bracketed:return flat_seed
	for _iteration in 14:
		var middle:=(lower+upper)*.5
		var point:=origin+direction*middle
		var value:=point.y-outpost_height(point)
		if value>0.0:lower=middle
		else:upper=middle
	return origin+direction*((lower+upper)*.5)

func resolve_ramp_click(flat_seed: Vector3, sampled: Variant) -> Vector3:
	# The imported ramp meets the outer ground at x=±3.2. A cursor placed on
	# that vertical side wall can make the fixed-point sampler alternate between
	# the raised surface and y=0, producing a target several metres away from
	# the visible terrain. Treat a near-side-wall click as a request for the
	# nearest walkable ramp edge while leaving clicks on the outer ground alone.
	if sampled is Vector3 and (sampled as Vector3).z<Layout.FORT_INNER:return Vector3.INF
	if sampled is Vector3 and (sampled as Vector3).z>Layout.RAMP_END+1.0:return Vector3.INF
	if absf(flat_seed.x)<2.77 or absf(flat_seed.x)>HERO_RAMP_CLICK_OUTER_EDGE:return Vector3.INF
	if sampled is Vector3 and outpost_walkable(sampled) and absf((sampled as Vector3).x)<2.77:return Vector3.INF
	var side: float=signf(flat_seed.x)
	# Preserve the cursor's forward position whenever possible. The y=0 ray
	# can land well before the ramp at the steep lower lip, so clamp only that
	# ambiguous part to the entrance instead of searching the whole ramp and
	# accidentally sending a click several metres uphill.
	var z: float=clampf(flat_seed.z,7.5+Layout.EXPANSION_OFFSET,Layout.RAMP_WALL_END-.05)
	var candidate_x: float=side*hero_ramp_side_limit(z)
	var candidate: Vector3=Vector3(candidate_x,outpost_height(Vector3(candidate_x,0,z)),z)
	return candidate if not camera.is_position_behind(candidate) else Vector3.INF

func flush_pending_aim() -> void:
	if not aim_sample_pending or not is_instance_valid(camera):return
	aim=ground_point(pending_aim_screen)
	aim_sample_pending=false

func hauler_under_cursor(screen: Vector2) -> BattleUnit:
	if not is_instance_valid(camera) or not is_instance_valid(squads):return null
	var chosen: BattleUnit
	var distance:=14.0*get_viewport().get_visible_rect().size.x/1440.0
	for squad: Dictionary in squads.squads:
		if String(squad.kind)!="hauler":continue
		for member: BattleUnit in squad.members:
			if not is_instance_valid(member) or member.is_queued_for_deletion() or not member.alive or member.hp<=0.0 or camera.is_position_behind(member.position):continue
			var feet:=camera.unproject_position(member.position)
			var head:=camera.unproject_position(member.position+Vector3(0,1.7,0))
			var candidate:=Geometry2D.get_closest_point_to_segment(screen,feet,head).distance_to(screen)
			if candidate<distance:chosen=member;distance=candidate
	return chosen

func handle_strategy_mouse(event: InputEvent) -> bool:
	if quitting or restart_pending or phase not in ["day","night"] or music_credits_open:return false
	if event is InputEventMouseMotion:
		pending_aim_screen=event.position
		aim_sample_pending=true
		if selection_dragging:selection_end=event.position
		return false
	if not event is InputEventMouseButton:return false
	if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed:
		camera.size=maxf(21,camera.size-1.5);return true
	if event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		camera.size=minf(52,camera.size+1.5);return true
	if event.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:return false
	if rally and rally.active:
		selection_dragging=false
		if not event.pressed:return true
		if event.button_index==MOUSE_BUTTON_RIGHT:rally.cancel_setting()
		else:
			aim=ground_point(event.position);aim_sample_pending=false
			var result: Dictionary=rally.commit(aim)
			hud.rally_feedback="" if bool(result.ok) else String(result.reason)
			notify(String(result.reason),3)
		return true
	if construction.active:
		if not event.pressed:return true
		selection_dragging=false
		if event.button_index==MOUSE_BUTTON_RIGHT:construction.cancel()
		else:
			aim=ground_point(event.position);aim_sample_pending=false
			construction.confirm()
		return true
	if event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			selection_dragging=true
			selection_start=event.position;selection_end=event.position
			selection_additive=event.shift_pressed
		elif selection_dragging:
			selection_dragging=false
			selection_end=event.position
			if selection_start.distance_to(selection_end)<8.0:
				squads.select_at(ground_point(event.position),selection_additive)
			else:
				squads.select_rect(camera,Rect2(selection_start,selection_end-selection_start).abs(),selection_additive)
		return true
	if not event.pressed:return true
	if event.alt_pressed:
		var escort_result: Dictionary=squads.command_escort(hauler_under_cursor(event.position))
		if bool(escort_result.ok):selection_dragging=false
		notify(String(escort_result.reason),2)
		return true
	selection_dragging=false
	var click_point:=ground_point(event.position)
	aim=click_point;aim_sample_pending=false
	if squads.selected_count()>0:
		if event.shift_pressed:
			var advance_result: Dictionary=squads.command_attack_move(click_point)
			notify(String(advance_result.reason),2)
			return true
		var target: BattleUnit
		var distance:=14.0*get_viewport().get_visible_rect().size.x/1440.0
		for enemy: BattleUnit in enemies:
			if not is_instance_valid(enemy) or enemy.hp<=0 or camera.is_position_behind(enemy.position):continue
			var feet:=camera.unproject_position(enemy.position)
			var head:=camera.unproject_position(enemy.position+Vector3(0,1.7,0))
			var candidate:=Geometry2D.get_closest_point_to_segment(event.position,feet,head).distance_to(event.position)
			if candidate<distance:target=enemy;distance=candidate
		var result: Dictionary
		if is_instance_valid(target):result=squads.command_attack(target)
		elif is_instance_valid(logistics) and logistics.selected_hauler_count()>0:
			var field_index: int=logistics.field_at_point(click_point)
			if field_index>=0:
				result=logistics.command_selected_field(field_index)
				if bool(result.ok):squads.command_move_non_haulers(click_point)
			else:result=squads.command_move(click_point)
		else:result=squads.command_move(click_point)
		notify(String(result.reason),2)
	else:plan_hero_path(click_point)
	return true

func _unhandled_input(event: InputEvent) -> void:
	if restart_pending or quitting:return
	if handle_strategy_mouse(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		flush_pending_aim()
		if event.keycode==KEY_M and music:
			music.toggle_mute()
			notify("配乐已静音" if music.muted else "配乐已开启",2)
			return
		if event.keycode in [KEY_BRACKETLEFT,KEY_BRACKETRIGHT] and music:
			music.set_volume(music.get_volume()+(-.1 if event.keycode==KEY_BRACKETLEFT else .1))
			notify("配乐音量 %d%%" % roundi(music.get_volume()*100),2)
			return
		if event.keycode==KEY_F1:
			selection_dragging=false
			if phase=="day" or phase=="night":paused_from=phase;phase="paused"
			music_credits_open=not music_credits_open
			return
		if event.keycode==KEY_ESCAPE and music_credits_open:
			music_credits_open=false
			return
		if event.keycode==KEY_ESCAPE and rally and rally.active and phase in ["day","night","paused"]:
			rally.cancel_setting();selection_dragging=false
			return
		if event.keycode==KEY_F3 and not music_credits_open:
			hud.toggle_details()
			return
		if event.keycode==KEY_ESCAPE and not music_credits_open and phase in ["day","night","paused"] and (not hud.detail_tab.is_empty() or hud.map_expanded):
			hud.dismiss_details()
			return
		if event.keycode==KEY_ESCAPE and construction and construction.active and phase in ["day","night"]:
			construction.cancel()
			return
		if event.keycode==KEY_ESCAPE and phase in ["day","night"] and (selection_dragging or squads.selected_count()>0):
			selection_dragging=false;squads.cancel_selection()
			return
		if music_credits_open:return
		if event.keycode==KEY_F2 and combat:
			combat.reduced_effects=not combat.reduced_effects
			if combat.reduced_effects:
				hero.visual_hit_stop=0.0
				for creature in enemies:
					if is_instance_valid(creature):creature.visual_hit_stop=0.0
			notify("已减弱震动与闪光" if combat.reduced_effects else "完整打击反馈已开启",2)
			return
		if phase=="ended" and event.keycode in [KEY_ENTER,KEY_R]:
			request_run_restart(event.keycode==KEY_ENTER)
			return
		if phase=="draft":
			if opening_night_pending and event.keycode in [KEY_7,KEY_8,KEY_9]:
				select_run_mode(event.keycode-KEY_7)
			elif event.keycode in [KEY_1,KEY_2,KEY_3]:choose_card(event.keycode-KEY_1)
			elif event.keycode==KEY_F and float(Time.get_ticks_msec())*.001>=draft_reroll_ready_at and run.redraw():notify("重新搜索战斗记忆",2)
			return
		# A temporary rally click is an exclusive world tool. Do not train,
		# upgrade a nearby building or issue a squad order while choosing it.
		if rally and rally.active and phase in ["day","night"]:
			if event.keycode==KEY_Y:toggle_tower_construction()
			return
		if event.keycode in [KEY_1,KEY_2,KEY_3]:
			if phase not in ["day","night"]:return
			if construction.active:
				hud.select_construction_slot(int(event.keycode)-KEY_1)
				return
			var slot:=int(event.keycode)-KEY_1+1
			var saving: bool=event.ctrl_pressed
			var result: Dictionary=control_groups.save(slot) if saving else control_groups.select(slot,event.shift_pressed)
			if bool(result.ok):
				var verb: String="已保存" if saving else ("追加选择" if event.shift_pressed else "已选中")
				notify("编组%d · 已清空" % slot if saving and int(result.count)==0 else "编组%d · %s%d队" % [slot,verb,int(result.count)],2)
			elif String(result.reason)=="empty_group":
				notify("编组%d暂无存活部队 · 选队后Ctrl+%d保存" % [slot,slot],2)
			hud.queue_redraw()
			get_viewport().set_input_as_handled()
			return
		if phase=="day" and event.keycode in [KEY_4,KEY_5,KEY_6]:
			if contracts.status=="bonus_offer" and event.keycode in [KEY_4,KEY_5]:
				var bonus_index: int=int(event.keycode)-KEY_4
				choose_bonus_route(bonus_index)
				return
			var offer_index: int = int(event.keycode)-KEY_4
			if contracts.choose_offer(offer_index):
				notify("已切换委托方案%d · 首次行动即锁定" % (offer_index+1),2)
			else:
				notify(contracts.offer_rejection_reason if not contracts.offer_rejection_reason.is_empty() else "当前没有可切换的委托方案",2)
			return
		if phase=="day" and event.keycode in [KEY_7,KEY_8,KEY_9]:
			var countermeasure_index: int=int(event.keycode)-KEY_7
			if not select_countermeasure(countermeasure_index):
				notify("当前没有可用的下一夜反制选择",2)
			return
		if event.keycode in [KEY_PAGEUP,KEY_PAGEDOWN] and phase in ["day","night","paused"]:
			var direction:= -1 if event.keycode==KEY_PAGEUP else 1
			if construction.active:hud.change_construction_page(direction)
			elif hud.detail_tab=="army":hud.change_troop_page(direction)
			return
		match event.keycode:
			KEY_DELETE,KEY_BACKSPACE:
				if construction.active:construction.toggle_sell()
			KEY_U:hire_shield_squad()
			KEY_I:hire_ranged_squad()
			KEY_N:train_troop("engineer")
			KEY_TAB:
				if phase in ["day","night"]:squads.select_all()
			KEY_O:toggle_squad_order()
			KEY_L:refill_squads()
			KEY_P:follow_route()
			KEY_V:request_upgrade()
			KEY_J:choose_tower_specialization("piercing")
			KEY_K:choose_tower_specialization("control")
			KEY_Y:toggle_tower_construction()
			KEY_F:interact()
			KEY_G:toggle_tower_mode()
			KEY_H:
				if construction.active:construction.toggle_repair()
				else:repair_tower()
			KEY_T:arm_gate_trap()
			KEY_B:build_gate_barricade()
			KEY_C:issue_focus_order()
			KEY_Q:cast(0,true)
			KEY_W:cast(1,true)
			KEY_E:cast(2,true)
			KEY_R:cast(3,true)
			KEY_X:cast(4,true)
			KEY_SPACE:camera.size=38
			KEY_ESCAPE:
				if phase=="paused":phase=paused_from
				elif phase=="day" or phase=="night":selection_dragging=false;paused_from=phase;phase="paused"

func notify(message: String, duration: float=3.0) -> void:
	notice=message;notice_time=duration

func update_salvage_refresh(delta: float) -> void:
	if phase!="day" and phase!="night":return
	for item in world.salvage:
		if not item.collected:continue
		item.respawn=maxf(0.0,float(item.respawn)-delta)
		if item.respawn>0:continue
		item.collected=false;item.node.visible=true

func salvage_draw_snapshot() -> Dictionary:
	return salvage_draw.snapshot()

func select_salvage_draw_mode(mode: String) -> bool:
	var selected: bool=salvage_draw.select_mode(mode)
	if not selected:
		notify(salvage_draw_reason(salvage_draw.mode_reason(mode)),2)
	else:
		notify("废墟补给 · %s档已选 · 不消耗随机" % ("押大" if mode=="jackpot" else "稳妥"),2)
	hud.queue_redraw()
	return selected

func salvage_draw_reason(reason: String) -> String:
	match reason:
		"":return "已解锁 · 可自愿抽取"
		"invalid_mode":return "未知抽取档位"
		"jackpot_requires_first":return "押大档需先完成一次稳妥抽取"
		"not_day":return "仅剩余白昼时间内可抽取"
		"day_unavailable":return "首夜结束后的白昼开放"
		"hero_unavailable":return "守望者需要存活"
		"beacon_unavailable":return "灯塔需要存活"
		"exploration_required":return "今天先完成一次探索"
		"return_home":return "返回灯塔旁的高台（6米内）"
		"daily_limit":return "今日两次已用完 · 下个白昼再开放"
		"insufficient_scrap":return "至少保留30零件才能抽取"
		"insufficient_scrap_jackpot":return "押大档需要至少60零件"
		"settling":return "补给正在结算"
		_:return "本次守望已结束"

func draw_salvage_supply(mode: String="safe") -> Dictionary:
	var result: Dictionary=salvage_draw.draw(mode)
	if not bool(result.ok):
		notify(salvage_draw_reason(String(result.reason)),2)
		return result
	var net: int=int(result.net)
	var net_text: String="+%d" % net if net>=0 else str(net)
	var mode_text: String="押大" if String(result.get("mode","safe"))=="jackpot" else "稳妥"
	var detail: String="%s档 · 支付%d · 回款%d · 净%s零件" % [mode_text,int(result.cost),int(result.payout),net_text]
	var color:=Color("a3d7bd") if net>=0 else Color("e2a960")
	# The draw has already settled the one wallet. This is a receipt, not a
	# gathering event: no exploration count, route bonus or milestone is granted.
	reward_toasts.append({"title":"废墟补给","detail":detail,"time":3.5,"color":color})
	while reward_toasts.size()>4:reward_toasts.pop_front()
	notify("废墟补给 · "+detail,3)
	hud.queue_redraw()
	return result

func grant_exploration_reward(title: String, point: Vector3, scrap_gain: int, hp_gain: float=0.0, mana_gain: float=0.0, category: String="") -> void:
	contracts.on_action()
	if phase!="day" and phase!="night":return
	var route: Dictionary={"scrap":0,"event":""}
	if exploration:
		route=exploration.record(category if not category.is_empty() else title,point,phase)
		scrap_gain+=int(route.scrap)
	exploration_count+=1
	var milestone:=exploration_count%5==0
	if milestone:
		exploration_milestones+=1
		scrap_gain+=55
	scrap+=maxi(0,scrap_gain)
	var actual_hp:=minf(maxf(0.0,hp_gain),hero.max_hp-hero.hp)
	var actual_mana:=minf(maxf(0.0,mana_gain),max_mana-mana)
	hero.hp+=actual_hp
	mana+=actual_mana
	var gains: Array[String]=[]
	if scrap_gain>0:gains.append("零件 +%d" % scrap_gain)
	if actual_hp>0:gains.append("生命 +%d" % int(actual_hp))
	if actual_mana>0:gains.append("法力 +%d" % int(actual_mana))
	var detail: String="探索进度 +1" if gains.is_empty() else "  ·  ".join(gains)
	var color:=Color("f4ca7c") if milestone else Color("86d8c6")
	reward_toasts.append({"title":"探索里程碑 · " + title if milestone else title,"detail":detail,"time":3.2,"color":color})
	if reward_toasts.size()>3:reward_toasts.pop_front()
	if not String(route.event).is_empty():
		var route_detail: String="路线加成：+%d零件" % int(route.scrap)
		if float(route.get("speed_seconds",0.0))>0.0:route_detail+=" · 加速%.0f秒" % float(route.speed_seconds)
		reward_toasts.append({"title":String(route.event),"detail":route_detail,"time":3.8,"color":Color("a6d9c6")})
		while reward_toasts.size()>4:reward_toasts.pop_front()
	var floating:=Label3D.new()
	effects.add_child(floating);floating.position=point+Vector3.UP*2.4
	floating.text=detail;floating.font_size=30;floating.pixel_size=.009
	floating.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	floating.modulate=color;floating.outline_size=5
	var tw:=floating.create_tween().set_parallel(true)
	tw.tween_property(floating,"position",floating.position+Vector3.UP*1.3,1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(floating,"modulate:a",0.0,.7).set_delay(.7)
	tw.chain().tween_callback(floating.queue_free)
	BattleVisuals.burst(effects,point,2.6 if milestone else 1.15,color,.4)
	if pickup_sound:
		if music:music.duck(.65)
		var sound:=AudioStreamPlayer.new()
		effects.add_child(sound);sound.stream=pickup_sound;sound.volume_db=-15
		sound.pitch_scale=1.15 if milestone else 1.0
		sound.finished.connect(sound.queue_free);sound.play()
	if milestone:notify("探索 %d 次 · 额外 +55 零件" % exploration_count,3)

func make_pickup_sound() -> AudioStreamWAV:
	var stream:=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=16000
	var samples:=PackedByteArray();samples.resize(4800*2)
	for i in 4800:
		var t:=float(i)/16000.0
		var envelope:=minf(1.0,t/.012)*exp(-t*14.0)
		var note:=660.0 if t<.1 else 880.0
		var value:=int((sin(TAU*note*t)+.25*sin(TAU*note*2*t))*envelope*9000.0)
		samples.encode_s16(i*2,value)
	stream.data=samples
	return stream

func _exit_tree() -> void:
	if is_instance_valid(discoveries):discoveries.cache_guards.clear()
	salvage_draw.clear()
	control_groups.clear()
	repairs.clear()
	bounty.reset()
	wave_wager.reset()
	clear_lobbers()
	clear_summoners()
	clear_warders()
	if is_instance_valid(effects):
		for child in effects.get_children():
			if child is AudioStreamPlayer:child.stop()

func request_run_restart(same_seed: bool) -> void:
	if phase!="ended" or restart_pending or quitting:return
	var next_seed: int=run.seed_value if same_seed else RunSessionScript.fresh_seed(run.seed_value)
	if not RunSessionScript.queue_request(get_tree(),next_seed,run_mode):return
	restart_pending=true
	_settle_wave_wager_loss("retry")
	wave_wager.reset()
	salvage_draw.clear()
	control_groups.clear()
	repairs.clear()
	hud.queue_redraw()
	# Keep music/playback cleanup in the tree before replacing the entire run.
	await prepare_shutdown()
	if quitting:
		RunSessionScript.clear_request(get_tree())
		return
	var error:=get_tree().reload_current_scene()
	if error!=OK:
		RunSessionScript.clear_request(get_tree())
		restart_pending=false
		set_process(true)
		notify("无法重新打开守望场景，请重试",4)

func prepare_shutdown() -> void:
	# Retire audio while its players and music bus still belong to the tree.
	# Removing the bus first can strand pending playback handles during teardown.
	shutting_down=true
	set_process(false)
	if is_instance_valid(discoveries):discoveries.cache_guards.clear()
	salvage_draw.clear()
	control_groups.clear()
	repairs.clear()
	bounty.reset()
	wave_wager.reset()
	clear_lobbers()
	clear_summoners()
	clear_warders()
	cores.clear()
	selection_dragging=false
	if construction:construction.clear()
	if rally:rally.clear()
	if logistics:logistics.clear()
	if squads:squads.clear()
	if districts:districts.clear()
	if skill_lights:skill_lights.clear()
	if combat:combat.clear_transients()
	if music:
		for player in music.players:
			player.stop();player.stream=null
	if is_instance_valid(effects):
		for child in effects.get_children():
			if child is AudioStreamPlayer:child.stop();child.stream=null
	# Allow the audio mix thread to retire its playback handles before the
	# application shuts down. This also keeps Windows close requests idempotent.
	await get_tree().create_timer(.15,true,false,true).timeout

func _notification(what: int) -> void:
	if what!=NOTIFICATION_WM_CLOSE_REQUEST or quitting:return
	quitting=true
	await prepare_shutdown()
	get_tree().quit()
