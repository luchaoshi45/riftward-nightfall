extends Node3D
## Owns the match lifecycle, player commands, AI and deterministic combat rules.
const UnitScene = preload("res://scripts/unit.gd")
const HudScript = preload("res://scripts/hud.gd")
const COOLDOWNS := [5.0, 9.0, 7.0, 28.0, 35.0]
const COSTS := [35.0, 45.0, 30.0, 85.0, 0.0]
const BLUE := Color("61def2")
const RED := Color("ff617c")

var units: Array[BattleUnit] = []
var player: BattleUnit
var enemy: BattleUnit
var camera: Camera3D
var hud: Control
var effects: Node3D
var mode: String = "menu"
var elapsed: float = 0.0
var wave_timer: float = 3.0
var wave_number: int = 0
var essence: float = 0.0
var experience: float = 0.0
var level: int = 1
var mana: float = 300.0
var max_mana: float = 300.0
var cooldowns: Array[float] = [0, 0, 0, 0, 0]
var kills: int = 0
var deaths: int = 0
var last_hits: int = 0
var player_respawn: float = 0.0
var enemy_respawn: float = 0.0
var enemy_skill: float = 7.0
var enemy_retreating: bool = false
var recall_time: float = 0.0
var recall_hp: float = 0.0
var build_open: bool = false
var help_open: bool = false
var notice: String = "跟随小兵推进，摧毁绯红核心"
var notice_time: float = 6.0
var winner: int = -1
var run := RunBuild.new()
var encounter_rng := RandomNumberGenerator.new()
var attack_count: int = 0
var next_evolution: float = 90.0
var evolution: int = 0
var resurrection_left: int = 3
var guardian_timer: float = 0.0
var draft_scheduled: bool = false
var aim := Vector3.ZERO
var projectiles: Array[Dictionary] = []
var warnings: Array[Dictionary] = []
var damage_numbers: Array[Dictionary] = []
var marker: MeshInstance3D
var aim_ring: MeshInstance3D
var audio_player: AudioStreamPlayer
var sounds: Array[AudioStreamWAV] = []
var muted: bool = false
var auto_test: bool = false
var navigation := BattleNavigation.new()
var heroes: Array[BattleUnit] = []
var cores: Array[BattleUnit] = []
var towers: Array[BattleUnit] = []
var jungle_kills: int = 0
var vigor_time: float = 0.0
var power_time: float = 0.0
var camera_locked: bool = true
var camera_focus := Vector3.ZERO
var danger_ring: MeshInstance3D
var team_scores: Array[int] = [0,0]
var interactables: Array[Dictionary] = []

func _ready() -> void:
	encounter_rng.seed=run.seed_value+913
	var world := BattleWorld.new()
	add_child(world)
	world.build()
	interactables = world.interactables
	effects = Node3D.new()
	add_child(effects)
	camera = Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 30.0
	camera.far = 150.0
	camera.position = Vector3(-9, 26, 22)
	camera.look_at(Vector3(-9, 0, 0))
	camera.current = true
	for team in [0, 1]:
		cores.append(spawn_unit("core", team, BattleMap.home(team)))
		for lane in range(3):
			for tier in range(2):
				var tower := spawn_unit("tower",team,BattleMap.tower_point(team,lane,tier))
				tower.lane=lane
				tower.tier=tier
	player = spawn_unit("hero", 0, Vector3(-35, 0, 1.8))
	enemy = spawn_unit("hero", 1, Vector3(35, 0, -1.8))
	enemy.damage = 43.0
	enemy.speed = 4.6
	for team in [0,1]:
		for lane in [0,2]:
			var ally := spawn_unit("hero",team,BattleMap.home(team)+Vector3(0,0,-2 if lane==0 else 2))
			ally.lane=lane
			ally.damage=43
			ally.speed=4.8
			ally.title=["青岚 · 巡林者","","白曜 · 守望者"][lane] if team==0 else ["赤棘 · 先锋","","暮影 · 裁决者"][lane]
	for i in BattleMap.CAMPS.size():
		var monster := spawn_unit("monster",2,BattleMap.CAMPS[i])
		monster.home_point=monster.position
		monster.camp_buff="vigor" if i%2==0 else "power"
		monster.title="苍翠守卫 · 恢复" if i%2==0 else "琥珀守卫 · 强攻"
	marker = BattleVisuals.ring(effects, Vector3.ZERO, 0.5, Color("dceac5"))
	marker.visible = false
	aim_ring = BattleVisuals.ring(effects, Vector3.ZERO, 0.24, BLUE, 0.03)
	danger_ring = BattleVisuals.ring(effects,Vector3.ZERO,8,Color("b76166"),.035)
	danger_ring.visible=false
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.game = self
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	audio_player.volume_db = -18
	for tone in [390.0, 620.0, 210.0]: sounds.append(make_tone(tone))
	apply_build()
	if "--showcase" in OS.get_cmdline_user_args():
		start_match()
		select_card(0)
		player.position = Vector3(-3, 0, 1.8)
		player.destination = player.position
		enemy.position = Vector3(5, 0, -0.5)
		for team in [0, 1]:
			for i in range(4): spawn_unit("minion", team, Vector3((-1 if team == 0 else 1) * (1.5 + i * 1.1), 0, (i % 2) * 1.5 - .7))
		camera.position = Vector3(0, 26, 22)
		camera.look_at(Vector3.ZERO)
		await get_tree().create_timer(1.0).timeout
		mode = "paused"
		hud.hide_pause = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://build/gameplay.png")
		print("SHOWCASE_SAVED")
		if "--capture-exit" in OS.get_cmdline_user_args(): get_tree().quit()
	elif "--draft-capture" in OS.get_cmdline_user_args():
		start_match()
		await get_tree().create_timer(.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://build/draft-v03.png")
		get_tree().quit()
	elif "--menu-capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://build/menu.png")
		get_tree().quit()
	elif "--smoke-test" in OS.get_cmdline_user_args():
		auto_test = true
		call_deferred("run_smoke_test")

func spawn_unit(kind: String, team: int, pos: Vector3) -> BattleUnit:
	var unit := UnitScene.new() as BattleUnit
	add_child(unit)
	unit.position = pos
	unit.setup(kind, team)
	unit.destination = pos
	unit.defeated.connect(_on_defeated)
	unit.damaged.connect(_on_damaged)
	units.append(unit)
	if kind=="hero": heroes.append(unit)
	if kind=="tower": towers.append(unit)
	return unit

func start_match() -> void:
	mode = "playing"
	run.grant("启程赐福 · 选择首张命运卡")
	open_draft()
	notify("三路战场开启 · 推通任意一路，击破敌方核心", 6)

func _process(delta: float) -> void:
	if mode == "playing":
		if camera_locked: camera_focus=Vector3(clampf(player.position.x+2,-34,34),0,clampf(player.position.z,-23,23))
		camera.position = camera.position.lerp(camera_focus + Vector3(0, 26, 22), 1.0 - exp(-delta * 5))
		camera.look_at(camera.position - Vector3(0, 26, 22))
		aim = ground_point(get_viewport().get_mouse_position())
		aim_ring.position = aim + Vector3.UP * 0.13
		aim_ring.visible = player.alive and not build_open and not help_open
	else:
		aim_ring.visible = false
	danger_ring.visible=false
	if mode=="playing" and player.alive:
		for unit in units:
			if unit.alive and unit.team==1 and unit.kind=="tower" and player.position.distance_to(unit.position)<11:
				danger_ring.position=unit.position+Vector3.UP*.13
				danger_ring.visible=true
				break
	hud.queue_redraw()

func _physics_process(delta: float) -> void:
	if mode != "playing" or auto_test or help_open or build_open: return
	simulate(delta)

func simulate(delta: float) -> void:
	if mode!="playing": return
	elapsed += delta
	vigor_time=maxf(0,vigor_time-delta)
	power_time=maxf(0,power_time-delta)
	for item in interactables:
		item.cooldown = maxf(0.0, float(item.cooldown) - delta)
	if elapsed>=next_evolution:
		evolution+=1
		next_evolution+=90
		for hero in heroes:
			if hero==player: continue
			hero.damage+=9
			hero.max_hp+=90
			hero.hp=minf(hero.max_hp,hero.hp+90)
		run.grant("第 %d 次裂隙异变 · 战场英雄与兵线强化" % evolution)
		schedule_draft()
	guardian_timer=maxf(0,guardian_timer-delta)
	if run.school_count(2)>=6 and guardian_timer<=0 and player.alive:
		player.shield=maxf(player.shield,player.max_hp*.12*run.stats.shield)
		player.shield_time=5
		guardian_timer=12
	experience += delta * 0.55
	check_level()
	notice_time = maxf(0, notice_time - delta)
	for i in cooldowns.size(): cooldowns[i] = maxf(0, cooldowns[i] - delta)
	mana = minf(max_mana, mana + delta * ((13 if vigor_time>0 else 7)+run.stats.mana_regen))
	wave_timer -= delta
	if wave_timer <= 0:
		spawn_wave()
		wave_timer = 16.0
	update_respawns(delta)
	for unit in units:
		if not unit.alive: continue
		unit.tick(delta)
		unit.moving = false
		if unit == player:
			update_player(delta)
		elif unit.kind=="hero":
			update_bot(unit,delta)
		elif unit.kind=="monster":
			update_monster(unit,delta)
		elif unit.kind == "minion":
			update_minion(unit, delta)
		else:
			update_structure(unit)
		if mode != "playing": break
	if mode != "playing": return
	update_projectiles(delta)
	if mode != "playing": return
	update_warnings(delta)
	for i in range(damage_numbers.size() - 1, -1, -1):
		damage_numbers[i]["ttl"] -= delta
		if damage_numbers[i]["ttl"] <= 0: damage_numbers.remove_at(i)
	if player.alive:
		if player.position.distance_to(BattleMap.home(0)) < 5:
			player.hp = minf(player.max_hp, player.hp + 120 * delta)
			mana = minf(max_mana, mana + 70 * delta)
		else: player.hp = minf(player.max_hp, player.hp + (2.0 + run.stats.regen + (7 if vigor_time>0 else 0)) * delta)
	if recall_time > 0:
		if player.hp < recall_hp or not player.alive:
			recall_time = 0
			notify("回城被伤害打断")
		else:
			recall_time -= delta
			if recall_time <= 0:
				player.position = BattleMap.home(0)+Vector3(2,0,2)
				player.destination = player.position
				player.path.clear()
				BattleVisuals.burst(effects, player.position, 2.5, BLUE)
				notify("已回到泉水 · 生命与能量快速恢复")

func spawn_wave() -> void:
	wave_number += 1
	for team in [0, 1]:
		for lane in range(3):
			for i in range(3):
				var pos := BattleMap.home(team)+Vector3((-1 if team==0 else 1)*i*.9,0,(lane-1)*1.5)
				var unit := spawn_unit("minion", team, pos)
				unit.lane=lane
				unit.max_hp += minf(200, wave_number * 5)+evolution*35
				unit.hp = unit.max_hp
				unit.damage += minf(35, wave_number * .8)+evolution*3
				if wave_number%4==0 and i==2:
					unit.max_hp*=1.8
					unit.hp=unit.max_hp
					unit.damage*=1.45
					unit.visual.scale*=1.35

func update_player(delta: float) -> void:
	var arrows := Vector3(float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)), 0, float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP)))
	if arrows.length_squared() > 0:
		recall_time=0
		player.target = null
		player.destination = clamp_point(player.position + arrows.normalized() * 2)
	if recall_time > 0: return
	if valid_target(player.target, player.team):
		if player.position.distance_to(player.target.position) > player.attack_range:
			move_unit(player, player.target.position, delta)
		else:
			player.destination = player.position
			attack(player, player.target)
	elif player.position.distance_to(player.destination) > 0.18:
		player.target = null
		move_unit(player, player.destination, delta)
	else:
		var target := find_target(player, player.attack_range)
		if target: attack(player, target)

func update_bot(bot: BattleUnit, delta: float) -> void:
	if bot.hp/bot.max_hp<.25: bot.retreating=true
	if bot.retreating:
		move_unit(bot,BattleMap.home(bot.team),delta)
		if bot.position.distance_to(BattleMap.home(bot.team))<4:
			bot.hp=minf(bot.max_hp,bot.hp+120*delta)
			if bot.hp>bot.max_hp*.9:
				bot.retreating=false
				bot.route_index=1
		return
	bot.skill_timer-=delta
	var target := find_target(bot,8.0)
	if target:
		if bot.position.distance_to(target.position)<=bot.attack_range:
			attack(bot,target)
		elif not unsafe_tower(bot,target.position): move_unit(bot,target.position,delta)
		if bot.skill_timer<=0 and target.kind=="hero":
			telegraph(bot,target.position,2.5,90+level*7,1.2)
			bot.skill_timer=10
	else:
		follow_lane(bot,delta,true)

func unsafe_tower(bot: BattleUnit, point: Vector3) -> bool:
	for tower in units:
		if not tower.alive or tower.team==bot.team or tower.kind!="tower": continue
		if tower.position.distance_to(point)>tower.attack_range+1: continue
		for ally in units:
			if ally.alive and ally.team==bot.team and ally.kind=="minion" and ally.position.distance_to(tower.position)<7.5: return false
		return true
	return false

func follow_lane(unit: BattleUnit, delta: float, careful: bool=false) -> void:
	var route := BattleMap.route(unit.lane,unit.team)
	unit.route_index=mini(unit.route_index,route.size()-1)
	while unit.route_index<route.size()-1 and unit.position.distance_to(route[unit.route_index])<1.8:
		unit.route_index+=1
	var goal := route[unit.route_index]
	# Stop outside tower range until allied minions enter first.
	if careful:
		var step := unit.position+(goal-unit.position).normalized()*2
		if unsafe_tower(unit,step): return
	move_unit(unit,goal,delta)

func update_monster(monster: BattleUnit, delta: float) -> void:
	if monster.resetting:
		monster.hp=minf(monster.max_hp,monster.hp+monster.max_hp*delta)
		move_unit(monster,monster.home_point,delta)
		if monster.position.distance_to(monster.home_point)<.3:
			monster.resetting=false
			monster.hp=monster.max_hp
		return
	if not is_instance_valid(monster.target) or not monster.target.alive: monster.target=null
	if monster.target:
		if monster.position.distance_to(monster.home_point)>7 or monster.target.position.distance_to(monster.home_point)>9:
			monster.target=null
			monster.resetting=true
		elif monster.position.distance_to(monster.target.position)<=monster.attack_range:
			attack(monster,monster.target)
		else: move_unit(monster,monster.target.position,delta)

func update_minion(unit: BattleUnit, delta: float) -> void:
	var target := find_target(unit, 7.5)
	if target:
		if unit.position.distance_to(target.position) <= unit.attack_range + (0.7 if target.is_structure() else 0.0):
			attack(unit, target)
		else: move_unit(unit, target.position, delta)
	else:
		follow_lane(unit,delta)

func update_structure(unit: BattleUnit) -> void:
	if not valid_target(unit.target, unit.team) or unit.position.distance_to(unit.target.position) > unit.attack_range:
		unit.target = find_target(unit, unit.attack_range, true)
	if unit.target: attack(unit, unit.target)

func move_unit(unit: BattleUnit, point: Vector3, delta: float) -> void:
	var goal := navigation.destination(point)
	if BattleMap.segment_clear(unit.position,goal):
		unit.path=PackedVector3Array([goal])
	elif unit.path.is_empty() or (unit.path_timer<=0 and unit.path_goal.distance_to(goal)>1.5):
		unit.path=navigation.path(unit.position,goal)
		unit.path_goal=goal
		unit.path_timer=.45
	while unit.path.size()>1 and unit.position.distance_to(unit.path[0])<.4: unit.path.remove_at(0)
	if unit.path.is_empty(): return
	var direction := unit.path[0] - unit.position
	direction.y = 0
	if direction.length() < 0.15: return
	var step := direction.normalized() * minf(unit.speed * delta, direction.length())
	# Soft separation keeps waves readable without blocking the player's route.
	for other in units:
		if other == unit or not other.alive or other.is_structure(): continue
		var offset := unit.position - other.position
		var distance := offset.length()
		if distance < 0.65 and distance > 0.01:
			step += offset.normalized() * (0.65 - distance) * delta * 3.0
	if not BattleMap.walkable(unit.position+step): step=direction.normalized()*minf(unit.speed*delta,direction.length())
	if BattleMap.walkable(unit.position+step): unit.position=BattleMap.bounded(unit.position+step)
	unit.face(unit.position + direction, delta)
	unit.moving = true

func clamp_point(point: Vector3) -> Vector3:
	return navigation.destination(point)

func protected_structure(unit: BattleUnit) -> bool:
	if not unit.is_structure(): return false
	if unit.kind=="core":
		for lane in range(3):
			var lane_open := true
			for tower in towers:
				if tower.alive and tower.team==unit.team and tower.kind=="tower" and tower.lane==lane: lane_open=false
			if lane_open: return false
		return true
	for other in towers:
		if other.alive and other.team == unit.team and other.lane==unit.lane and other.tier<unit.tier:
			return true
	return false

func valid_target(unit: Variant, team: int) -> bool:
	return is_instance_valid(unit) and unit.alive and unit.team != team and not unit.resetting and not protected_structure(unit)

func find_target(unit: BattleUnit, radius: float, prefer_minions: bool = false) -> BattleUnit:
	var best: BattleUnit
	var best_score := INF
	for other in units:
		if not other.alive or other.team==unit.team: continue
		var distance := unit.position.distance_to(other.position)
		if distance > radius: continue
		if not valid_target(other, unit.team): continue
		if other.kind=="monster" and (unit!=player or other.target!=player): continue
		var score := distance
		if prefer_minions and other.kind == "minion": score -= 20
		if other.is_structure(): score += 8
		if score < best_score:
			best_score = score
			best = other
	return best

func nearest_objective(unit: BattleUnit) -> BattleUnit:
	var best: BattleUnit
	var distance := INF
	for other in units:
		if other.is_structure() and valid_target(other, unit.team) and (other.kind=="core" or other.lane==unit.lane):
			var d := unit.position.distance_to(other.position)
			if d<distance: best=other; distance=d
	return best

func attack(attacker: BattleUnit, victim: BattleUnit) -> void:
	if attacker.attack_timer > 0 or not valid_target(victim, attacker.team): return
	attacker.attack_timer = attacker.attack_interval
	attacker.attack_pose = 1
	attacker.face(victim.position)
	var height := 2.8 if attacker.is_structure() else 1.2
	BattleVisuals.beam(effects, attacker.position + Vector3.UP * height, victim.position + Vector3.UP, attacker.faction_color(), 0.09 if attacker.is_structure() else 0.045)
	var amount := attacker.damage * (0.62 if victim.is_structure() and attacker.kind == "hero" else 1.0)
	if attacker==player and encounter_rng.randf()<run.stats.crit:
		amount*=1.75
		BattleVisuals.sparks(effects,victim.position+Vector3.UP,Color("ffd784"),7)
	var dealt := deal_damage(victim,amount,attacker)
	if attacker==player:
		attack_count+=1
		if not victim.is_structure(): player.hp=minf(player.max_hp,player.hp+dealt*run.stats.lifesteal)
		if run.count("chain")>0 and attack_count%3==0:
			var hit:=0
			for other in units:
				if other==victim or not valid_target(other,0) or other.is_structure(): continue
				if other.position.distance_to(victim.position)>5: continue
				BattleVisuals.beam(effects,victim.position+Vector3.UP,other.position+Vector3.UP,Color("e5c778"),.07)
				deal_damage(other,player.damage*.55,player)
				hit+=1
				if hit>=2: break
	if victim==player and player.alive and run.count("thorns")>0 and attacker.alive:
		deal_damage(attacker,18+player.armor*.25,player)
	if attacker == player: sound(0)
	# Damaging a hero beneath their tower draws that tower's attention.
	if attacker.kind == "hero" and victim.kind == "hero":
		for unit in units:
			if unit.alive and unit.kind == "tower" and unit.team == victim.team and unit.position.distance_to(attacker.position) < unit.attack_range:
				unit.target = attacker

func deal_damage(victim: BattleUnit, amount: float, source: BattleUnit) -> float:
	if not valid_target(victim, source.team): return 0.0
	if source==player and power_time>0: amount*=1.25
	damage_numbers.append({"point": victim.position + Vector3.UP * 2.1, "value": int(amount), "ttl": 0.85, "team": source.team})
	var before := victim.hp
	victim.hurt(amount, source)
	if source.kind=="hero" and victim.kind=="hero":
		for tower in units:
			if tower.alive and tower.kind=="tower" and tower.team==victim.team and tower.position.distance_to(source.position)<tower.attack_range: tower.target=source
	return before-victim.hp

func _on_damaged(unit: BattleUnit, source: BattleUnit) -> void:
	if unit==player and recall_time>0:
		recall_time=0
		notify("回城被攻击打断")
	if unit.kind=="monster" and not unit.resetting and is_instance_valid(source): unit.target=source

func _on_defeated(unit: BattleUnit, source: BattleUnit) -> void:
	BattleVisuals.burst(effects, unit.position, 2.0 if unit.is_structure() else 1.1, unit.faction_color())
	unit.visible = false
	if unit.kind=="monster":
		unit.respawn_timer=45
		if source==player:
			add_essence(70)
			experience+=85
			jungle_kills+=1
			if unit.camp_buff=="vigor": vigor_time=45
			else: power_time=45
			notify("野怪击败 +70 星尘 · %s持续 45 秒" % ("生命能量恢复" if unit.camp_buff=="vigor" else "伤害提升 25%"),4)
			check_level()
		return
	if unit.kind=="hero": team_scores[1-unit.team]+=1
	if unit.team == 1 and (unit.is_structure() or source == player or player.position.distance_to(unit.position) < 15):
		add_essence(8 if unit.kind=="minion" else 45)
		experience += 22 if unit.kind == "minion" else 110
		if unit.kind == "minion": last_hits += 1
		check_level()
	if unit == player:
		deaths += 1
		if resurrection_left<=0:
			winner=1
			mode="ended"
			run.offer.clear()
			build_open=false
			return
		resurrection_left-=1
		player_respawn = 8.0 + level
		vigor_time=0
		power_time=0
		recall_time = 0
		notify("你已倒下 · 即将于泉水重生", 5)
	elif unit.kind=="hero":
		unit.respawn_timer=13
		if unit.team==1:
			if source==player: kills+=1
			notify("敌方英雄已倒下："+unit.title,4)
	elif unit.kind == "tower":
		if unit.team==1:
			run.grant("破塔赐福 · 战场目标奖励")
			schedule_draft()
		notify("敌方守塔已摧毁 · 获得命运选卡" if unit.team==1 else "我方防御塔被摧毁！",5)
	elif unit.kind == "core":
		winner = 1 - unit.team
		mode = "ended"
		build_open = false
		sound(1 if winner == 0 else 2)
	if unit.kind == "minion":
		# Removal is deferred because defeat signals arrive during iteration.
		call_deferred("remove_minion", unit)

func remove_minion(unit: BattleUnit) -> void:
	if is_instance_valid(unit):
		for other in units:
			if other.target==unit: other.target=null
		units.erase(unit)
		unit.queue_free()

func check_level() -> void:
	while level < 12 and experience >= level * 65:
		experience -= level * 65
		level += 1
		apply_build()
		player.hp=minf(player.max_hp,player.hp+80)
		mana=max_mana
		run.grant("升至 %d 级 · 选择命运卡" % level)
		schedule_draft()
		BattleVisuals.burst(effects, player.position, 2.0, Color("ffe4a3"))
		notify("升至 %d 级%s" % [level, " · 终极技能已解锁！" if level == 4 else " · 生命与攻击提升"], 4)

func update_respawns(delta: float) -> void:
	if not player.alive:
		player_respawn -= delta
		if player_respawn <= 0:
			player.revive(BattleMap.home(0)+Vector3(2,0,2))
			mana = max_mana
			notify("重返战场")
			if run.pending>0: schedule_draft()
	for unit in units:
		if unit==player or unit.alive or unit.kind not in ["hero","monster"]: continue
		unit.respawn_timer-=delta
		if unit.respawn_timer<=0:
			if unit.kind=="monster": unit.revive(unit.home_point)
			else:
				unit.max_hp=850+(level-1)*45+evolution*90
				unit.damage=43+(level-1)*4+evolution*9
				unit.revive(BattleMap.home(unit.team)+Vector3(0,0,(unit.lane-1)*2))

func ground_point(screen: Vector2) -> Vector3:
	var result: Variant = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	return clamp_point(result) if result != null else player.position

func command_move(point: Vector3) -> void:
	if not player.alive: return
	recall_time = 0
	player.target = null
	player.path.clear()
	player.destination = clamp_point(point)
	marker.position = player.destination + Vector3.UP * 0.16
	marker.visible = true
	marker.scale = Vector3.ONE
	var tween := marker.create_tween()
	tween.tween_property(marker, "scale", Vector3(0.02, 1, 0.02), 0.6)

func nearest_interactable() -> int:
	if not player.alive: return -1
	var best := 3.0
	var index := -1
	for i in interactables.size():
		var distance := player.position.distance_to(interactables[i].position)
		if distance < best:
			best = distance
			index = i
	return index

func interaction_prompt() -> String:
	var index := nearest_interactable()
	if index < 0: return ""
	var item := interactables[index]
	var label := "月泉 · 恢复生命与能量" if item.kind=="well" else ("星碑 · 短时强化" if item.kind=="obelisk" else "遗珍匣 · 星尘")
	if item.used: return label + " · 已开启"
	if item.cooldown > 0: return "%s · 冷却 %ds" % [label, ceili(item.cooldown)]
	return "F 交互  ·  " + label

func interact_nearby() -> bool:
	if mode!="playing" or not player.alive or build_open or help_open: return false
	var index := nearest_interactable()
	if index < 0: return false
	var item := interactables[index]
	if item.used or item.cooldown > 0: return false
	match item.kind:
		"well":
			player.hp = minf(player.max_hp,player.hp + player.max_hp*.35)
			mana = minf(max_mana,mana + max_mana*.38)
			item.cooldown = 55.0
			notify("月泉苏醒 · 恢复生命与能量")
		"obelisk":
			power_time = maxf(power_time,18.0)
			item.cooldown = 80.0
			notify("星碑共鸣 · 18 秒内伤害提升")
		"relic":
			add_essence(45.0)
			item.used = true
			notify("遗珍匣开启 · 获得 45 星尘")
	var visual := item.node as Node3D
	var tween := create_tween()
	tween.tween_property(visual,"scale",Vector3.ONE*1.18,.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual,"scale",Vector3.ONE,.22).set_trans(Tween.TRANS_SINE)
	BattleVisuals.burst(effects,item.position,1.2,Color("b2e9d6"),.42)
	sound(1)
	return true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if mode=="draft":
			if event.physical_keycode in [KEY_1,KEY_2,KEY_3]: select_card(event.physical_keycode-KEY_1)
			elif event.physical_keycode==KEY_F: run.redraw()
			return
		if event.physical_keycode == KEY_ESCAPE:
			if build_open: build_open = false
			elif help_open: help_open = false
			elif mode == "playing": mode = "paused"
			elif mode == "paused":
				mode = "playing"
				if run.pending>0: schedule_draft()
			return
		if event.physical_keycode == KEY_M:
			muted = not muted
			return
		if mode != "playing": return
		match event.physical_keycode:
			KEY_Y:
				camera_locked=not camera_locked
				notify("镜头跟随" if camera_locked else "镜头自由 · 左键小地图观察，空格返回")
			KEY_SPACE: camera_locked=true
			KEY_TAB: build_open = not build_open
			KEY_F1: help_open = not help_open
			KEY_Q: cast(0)
			KEY_W: cast(1)
			KEY_E: cast(2)
			KEY_R: cast(3)
			KEY_D: cast(4)
			KEY_B: recall()
			KEY_F: interact_nearby()
			KEY_S:
				player.destination = player.position
				player.target = null
				recall_time = 0
	if mode != "playing" or build_open or help_open: return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			command_move(ground_point(event.position))
			for unit in units:
				if unit.team != 0 and unit.alive and camera.unproject_position(unit.position + Vector3.UP).distance_to(event.position) < (34 if unit.is_structure() else 25):
					if protected_structure(unit): notify("先摧毁前方防御塔，解除建筑护盾")
					else: player.target = unit
					break
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP: camera.size = maxf(23, camera.size - 1.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera.size = minf(48, camera.size + 1.5)

func cast(slot: int) -> bool:
	if mode != "playing" or not player.alive or build_open or help_open: return false
	if slot == 3 and level < 4:
		notify("星陨将在 4 级解锁")
		return false
	if cooldowns[slot] > 0:
		notify("技能冷却中")
		return false
	if mana < COSTS[slot]:
		notify("能量不足 · 回泉水或等待恢复")
		return false
	cooldowns[slot] = COOLDOWNS[slot] * run.cooldown_factor()
	mana -= COSTS[slot]
	recall_time = 0
	var direction := (aim - player.position).normalized()
	if direction.length() < 0.1: direction = Vector3.RIGHT
	player.face(player.position + direction)
	player.attack_pose = 1
	match slot:
		0:
			var spread := [-.20,0.0,.20] if run.count("split")>0 else [0.0]
			for angle in spread:
				var dir := direction.rotated(Vector3.UP,angle)
				var orb := BattleVisuals.ring(effects, player.position + Vector3.UP * 0.75, 0.35, BLUE, 0.12)
				var amount: float=(115.0+level*12+run.stats.spell*.85)*(.7 if spread.size()==3 else 1.0)
				projectiles.append({"node":orb,"direction":dir,"distance":0.0,"hits":[],"damage":amount})
		1:
			player.shield = (140 + level * 18 + run.stats.spell*.5)*run.stats.shield
			player.shield_time = 4.0
			BattleVisuals.burst(effects, player.position, 4.2*run.stats.area, BLUE, .5)
			for unit in units:
				if valid_target(unit, 0) and unit.position.distance_to(player.position) < 4.2*run.stats.area:
					deal_damage(unit, 75 + level * 12 + run.stats.spell*.65, player)
		2:
			var from := player.position
			player.position = navigation.dash(player.position,player.position + direction * minf(6.2+run.count("stride")*.8, player.position.distance_to(aim)))
			player.destination = player.position
			player.target = null
			player.path.clear()
			BattleVisuals.beam(effects, from + Vector3.UP, player.position + Vector3.UP, BLUE, 0.24)
			BattleVisuals.burst(effects, player.position, 1.2, BLUE)
		3:
			var point := player.position + direction * minf(11, player.position.distance_to(aim))
			telegraph(player, point, 4.0*run.stats.area, 290 + level * 22+run.stats.spell*1.25, 0.7)
			if run.count("echo")>0: telegraph(player,point,4.0*run.stats.area,(290+level*22+run.stats.spell*1.25)*.5,1.25)
		4:
			player.hp = minf(player.max_hp, player.hp + player.max_hp * .35)
			BattleVisuals.burst(effects, player.position, 1.5, Color("8af1b7"), .7)
	sound(1)
	return true

func update_projectiles(delta: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		var node: Node3D = p.node
		var before := node.position
		node.position += p.direction * delta * 23
		p.distance += delta * 23
		for unit in units:
			if not valid_target(unit, 0) or unit in p.hits: continue
			var closest := Geometry3D.get_closest_point_to_segment(unit.position + Vector3.UP * .75, before, node.position)
			if closest.distance_to(unit.position + Vector3.UP * .75) < (1.25 if unit.is_structure() else .8):
				p.hits.append(unit)
				deal_damage(unit, p.damage * (0.5 if unit.is_structure() else 1), player)
		if p.distance > 13:
			node.queue_free()
			projectiles.remove_at(i)

func telegraph(source: BattleUnit, point: Vector3, radius: float, amount: float, delay: float) -> void:
	var ring := BattleVisuals.ring(effects, point + Vector3.UP * .17, radius, source.faction_color(), .09)
	warnings.append({"node": ring, "point": point, "radius": radius, "damage": amount, "delay": delay, "source": source})

func update_warnings(delta: float) -> void:
	for i in range(warnings.size() - 1, -1, -1):
		var warning: Dictionary = warnings[i]
		warning.delay -= delta
		var node: Node3D = warning.node
		node.rotation.y += delta
		if warning.delay <= 0:
			var source: BattleUnit = warning.source
			BattleVisuals.burst(effects, warning.point, warning.radius, source.faction_color(), .5)
			BattleVisuals.beam(effects, warning.point + Vector3.UP * 12, warning.point, source.faction_color(), .45)
			for unit in units:
				if valid_target(unit, source.team) and unit.position.distance_to(warning.point) <= warning.radius:
					deal_damage(unit, warning.damage * (.5 if unit.is_structure() else 1), source)
			node.queue_free()
			warnings.remove_at(i)

func recall() -> void:
	if not player.alive or build_open: return
	recall_time = 4
	recall_hp = player.hp
	player.target = null
	player.destination = player.position
	BattleVisuals.burst(effects, player.position, 1.7, BLUE, 1.5)
	notify("正在回城 · 移动、施法或受伤会打断", 4)

func apply_build() -> void:
	var old_max := player.max_hp
	player.max_hp=850+(level-1)*65+run.stats.health
	player.hp=minf(player.max_hp,player.hp+maxf(0,player.max_hp-old_max))
	player.damage=58+(level-1)*6+run.stats.attack
	player.attack_interval=.8/(1+run.stats.attack_speed)
	player.attack_range=5.2+run.stats.range
	player.speed=minf(9,6+run.stats.speed)
	player.armor=10+run.stats.armor
	var previous_mana := max_mana
	max_mana=300+(level-1)*20+run.stats.mana
	mana=minf(max_mana,mana+maxf(0,max_mana-previous_mana))

func add_essence(amount: float) -> void:
	essence+=amount
	while essence>=100:
		essence-=100
		run.grant("100 星尘共鸣 · 选择命运卡")
		schedule_draft()

func schedule_draft() -> void:
	if draft_scheduled: return
	draft_scheduled=true
	call_deferred("open_draft")

func open_draft() -> void:
	draft_scheduled=false
	if mode!="playing" or not player.alive: return
	if run.draft():
		mode="draft"
		build_open=false
		help_open=false

func select_card(index: int) -> bool:
	if mode!="draft": return false
	var selected := run.choose(index)
	if selected.is_empty(): return false
	apply_build()
	sound(1)
	BattleVisuals.burst(effects,player.position,2.0,RunBuild.COLORS[selected.school],.6)
	mode="playing"
	notify("命运已铭刻："+selected.name,3)
	if run.pending>0: open_draft()
	return true

func notify(message: String, duration: float = 2.5) -> void:
	notice = message
	notice_time = duration

func sound(index: int) -> void:
	if muted: return
	audio_player.stream = sounds[index]
	audio_player.play()

func make_tone(frequency: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var bytes := PackedByteArray()
	var count := 3307
	bytes.resize(count * 2)
	for i in count:
		var t := float(i) / 22050
		var envelope := pow(1.0 - float(i) / count, 2.0)
		var sample := int(sin(t * frequency * TAU * (1.0 - t * 1.5)) * envelope * 18000)
		bytes.encode_s16(i * 2, sample)
	stream.data = bytes
	return stream

func run_smoke_test() -> void:
	var suite=load("res://tests/rogue_smoke.gd").new()
	add_child(suite)
	await suite.run(self)
