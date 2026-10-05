class_name DayExpeditions
extends Node3D
## Daytime expeditions earn supplies and persistent help for the following nights.
const HOLD_SECONDS := 12.0
const HOLD_RADIUS := 5.0
const FOLLOW_SPEED := 5.4
const GENERATOR_REWARD := 100
const RESCUE_REWARD := 80
const HOME_LANTERN_SCENE: PackedScene = preload("res://assets/models/waylight.glb")
const HOME_LIGHT_RANGE := 3.6
const SCOUT_NAMES := ["沈禾", "周砚"]
const SCOUT_RECRUIT_LINES := ["沈禾：带我走南门，回去一起修灯。", "周砚：别让我落下，回到灯下我也能帮忙。"]

var game: Node3D
var generators: Array[Dictionary] = []
var camps: Array[Dictionary] = []

func setup(owner_game: Node3D) -> void:
	game=owner_game
	for point in [Vector3(-17,0,24),Vector3(18,0,25),Vector3(25,0,7)]:
		point.y=game.outpost_height(point)
		clear_expedition_space(point,3.4)
		var model: Node3D=game.world.place("res://assets/models/day_generator.glb",point,1.0,0)
		var ring:=BattleVisuals.ring(self,point+Vector3.UP*.1,HOLD_RADIUS,Color("647c7c"),.035)
		ring.visible=false
		var lamp:=OmniLight3D.new()
		add_child(lamp);lamp.position=point+Vector3.UP*1.6
		lamp.light_color=Color("8fd8cf");lamp.omni_range=7;lamp.light_energy=0
		var title:=make_label(point+Vector3.UP*2.4,"废墟发电机 · F 启动",Color("8fd8cf"))
		generators.append({"position":point,"node":model,"ring":ring,"lamp":lamp,"label":title,"state":"ready","progress":0.0,"guards":[],"inside_material":BattleVisuals.material(Color("8bd9ca"),.8),"outside_material":BattleVisuals.material(Color("c18864"),.8)})
	for point in [Vector3(-29,0,21),Vector3(28,0,32)]:
		var scout_index: int=camps.size()
		var scout_name: String=SCOUT_NAMES[scout_index]
		point.y=game.outpost_height(point)
		clear_expedition_space(point,4.0)
		var model: Node3D=game.world.place("res://assets/models/survivor_camp.glb",point,1.0,0)
		var scout:=BattleUnit.new()
		add_child(scout);scout.setup("hero",0)
		scout.title="失联哨兵 · "+scout_name;scout.visual.scale*=.87;scout.selection.visible=false
		scout.position=point+Vector3(-1.1,0,2.3);scout.position.y=game.outpost_height(scout.position)
		var label:=make_label(point+Vector3.UP*2.5,scout_name+" · F 护送回家",Color("e4b977"))
		camps.append({"position":point,"node":model,"npc":scout,"scout_name":scout_name,"recruit_line":SCOUT_RECRUIT_LINES[scout_index],"label":label,"state":"waiting","trail":[],"guards":[],"home_lantern":null,"home_light":null})

func clear_expedition_space(point: Vector3, radius: float) -> void:
	# Reserve readable activity space without deleting any objectives or resources.
	for prop in game.world.get_children():
		if not prop is Node3D:continue
		var path: String=prop.scene_file_path
		if path.ends_with("dead_tree.glb") or path.ends_with("ruined_house.glb") or path.ends_with("rock_v2.glb") or path.ends_with("truck_wreck.glb"):
			if Vector2(prop.position.x-point.x,prop.position.z-point.z).length()<radius:prop.queue_free()
	var shifted:=0
	for cache in game.world.salvage:
		if (cache.position as Vector3).distance_to(point)>=radius:continue
		var destination:=point+Vector3(radius+1.8,0,-2+shifted*2)
		destination.y=game.outpost_height(destination)
		cache.position=destination;cache.node.position=destination;shifted+=1

func make_label(point: Vector3, value: String, color: Color) -> Label3D:
	var label:=Label3D.new()
	add_child(label);label.position=point;label.text=value
	label.font_size=32;label.pixel_size=.008;label.modulate=color
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test=false
	label.outline_size=5
	return label

func nearest_generator() -> int:
	if game.phase!="day":return -1
	var selected:=-1
	var distance:=3.4
	for i in generators.size():
		if generators[i].state!="ready":continue
		var candidate: float=game.hero.position.distance_to(generators[i].position)
		if candidate<distance:selected=i;distance=candidate
	return selected

func nearest_camp() -> int:
	if game.phase!="day":return -1
	var selected:=-1
	var distance:=3.4
	for i in camps.size():
		if camps[i].state!="waiting":continue
		var candidate: float=game.hero.position.distance_to(camps[i].position)
		if candidate<distance:selected=i;distance=candidate
	return selected

func interaction_prompt() -> String:
	if nearest_generator()>=0:return "F 启动发电机 · 守住灯区，获得能源芯"
	var camp_index:=nearest_camp()
	if camp_index>=0:return "F 接回%s · 日落前经南门返家" % camps[camp_index].scout_name
	return ""

func start_generator(index: int) -> bool:
	if game.phase!="day" or index<0 or index>=generators.size():return false
	var site: Dictionary=generators[index]
	if site.state!="ready":return false
	site.state="active";site.progress=0.0
	site.ring.visible=true;site.lamp.light_energy=1.6
	site.guards=spawn_ambush(site.position,3)
	game.notify("发电机声响惊醒潜伏体 · 守住灯圈 12 秒并清除袭击",5)
	return true

func start_camp(index: int) -> bool:
	if game.phase!="day" or index<0 or index>=camps.size():return false
	var camp: Dictionary=camps[index]
	if camp.state!="waiting":return false
	camp.state="escort";camp.trail=[game.hero.position]
	camp.guards=spawn_ambush(camp.position,2)
	camp.label.text=camp.scout_name+"跟随中 · 返回灯塔"
	game.notify(camp.recruit_line,5)
	return true

func interact() -> bool:
	var index:=nearest_generator()
	if index>=0:return start_generator(index)
	index=nearest_camp()
	if index>=0:return start_camp(index)
	return false

func spawn_ambush(center: Vector3, count: int) -> Array[BattleUnit]:
	var guards: Array[BattleUnit]=[]
	for i in count:
		var angle:=TAU*float(i)/float(count)+.35
		var point:=center+Vector3(cos(angle)*7,0,sin(angle)*7)
		if not game.outpost_walkable(point):point=center+Vector3(0,0,7+i)
		point.y=game.outpost_height(point)
		var creature: BattleUnit=game.spawn_creature(false)
		creature.position=point;creature.title="惊醒的潜伏体"
		creature.set_meta("day_hunter",true)
		creature.speed=3.4
		guards.append(creature)
		BattleVisuals.burst(game.effects,point,1.4,Color("ba795d"),.4)
	return guards

func guards_alive(site: Dictionary) -> bool:
	for creature in site.guards:
		if is_instance_valid(creature) and creature.alive:return true
	return false

func tick(delta: float) -> void:
	if game.phase!="day":
		if game.phase=="night":
			for camp in camps:
				var resting_scout: BattleUnit=camp.npc
				resting_scout.moving=false;resting_scout.set_locomotion_velocity(Vector3.ZERO);resting_scout.tick(delta)
		return
	for site in generators:
		if site.state!="active":continue
		var in_circle: bool=game.hero.position.distance_to(site.position)<=HOLD_RADIUS
		if in_circle:site.progress=minf(HOLD_SECONDS,float(site.progress)+delta)
		var ratio: float=site.progress/HOLD_SECONDS
		site.ring.material_override=site.inside_material if in_circle else site.outside_material
		site.label.text="充能 %d%% · %s" % [roundi(ratio*100),"清除潜伏体" if ratio>=1 and guards_alive(site) else ("守住灯圈" if in_circle else "返回灯圈继续")]
		if ratio>=1 and not guards_alive(site):complete_generator(site)
	for i in camps.size():
		var camp: Dictionary=camps[i]
		var npc: BattleUnit=camp.npc
		if camp.state=="escort":
			follow_hero(camp,delta)
			if npc.position.y>4.8 and Vector2(npc.position.x,npc.position.z).length()<6.2:deliver_scout(camp,i)
		else:
			npc.moving=false;npc.set_locomotion_velocity(Vector3.ZERO)
		npc.tick(delta)

func complete_generator(site: Dictionary) -> void:
	site.state="complete";site.ring.visible=false
	site.label.text="能源芯已取回 · 灯塔脉冲强化"
	site.label.modulate=Color("7eaea5");site.lamp.light_energy=.5
	game.scrap+=GENERATOR_REWARD;game.generator_cells+=1
	BattleVisuals.burst(game.effects,site.position,4.2,Color("9cddd1"),.7)
	game.notify("能源芯取回 · +100 零件，灯塔攻击脉冲加快",5)

func follow_hero(camp: Dictionary, delta: float) -> void:
	var npc: BattleUnit=camp.npc
	var trail: Array=camp.trail
	if trail.is_empty() or (trail.back() as Vector3).distance_to(game.hero.position)>.65:trail.append(game.hero.position)
	var target: Vector3=npc.position
	var direct: bool=game.can_traverse(npc.position,game.hero.position)
	if direct:
		npc.path.clear()
		trail.clear();trail.append(game.hero.position)
		if npc.position.distance_to(game.hero.position)>2.3:target=game.hero.position
	else:
		while not trail.is_empty() and npc.position.distance_to(trail[0])<.3:trail.pop_front()
		if not trail.is_empty():target=trail[0]
		# A follower may approach a corner at a different angle from the hero.
		# Re-route that segment instead of cutting the corner into a wall.
		if npc.path.is_empty() and not game.can_traverse(npc.position,target):build_scout_route(npc,target)
		while not npc.path.is_empty() and npc.position.distance_to(npc.path[0])<.08:npc.path.remove_at(0)
		if not npc.path.is_empty():target=npc.path[0]
	var before:=npc.position
	var direction:=target-before;direction.y=0
	if direction.length()>.04:
		var next:=before+direction.normalized()*minf(direction.length(),FOLLOW_SPEED*delta)
		if game.can_traverse(before,next):
			next.y=game.outpost_height(next);npc.position=next
			npc.face(target,delta)
	npc.moving=npc.position.distance_squared_to(before)>.000001
	npc.set_locomotion_velocity((npc.position-before)/maxf(delta,.001))

func build_scout_route(npc: BattleUnit, destination: Vector3) -> void:
	var start_cell: Vector2i=game.nearest_navigation_cell(npc.position,true)
	var end_cell: Vector2i=game.nearest_navigation_cell(destination,false)
	if start_cell.x==999 or end_cell.x==999:return
	var grid_path: PackedVector2Array=game.hero_navigation.get_point_path(start_cell,end_cell)
	for cell in grid_path:
		var point:=Vector3(cell.x,0,cell.y)
		point.y=game.outpost_height(point);npc.path.append(point)
	if not npc.path.is_empty() and game.can_traverse(npc.path[-1],destination):npc.path.append(destination)

func deliver_scout(camp: Dictionary, index: int) -> void:
	# A return is committed only once, after the escort actually reaches the fort.
	if camp.state!="escort" or game.phase!="day":return
	var arriving_scout: BattleUnit=camp.npc
	if arriving_scout.position.y<=4.8 or Vector2(arriving_scout.position.x,arriving_scout.position.z).length()>=6.2:return
	camp.state="delivered";camp.trail.clear()
	var npc: BattleUnit=camp.npc
	npc.position=Vector3(-2-float(index)*1.6,NightfallWorld.FORT_HEIGHT,1.2)
	npc.path.clear()
	npc.moving=false;npc.set_locomotion_velocity(Vector3.ZERO)
	camp.label.position=npc.position+Vector3.UP*2.5
	camp.label.text=camp.scout_name+" · 已归队"
	camp.label.font_size=26;camp.label.pixel_size=.006
	camp.label.modulate=Color("e4b977")
	light_home_lantern(camp,index)
	game.scrap+=RESCUE_REWARD;game.survivors_rescued+=1
	game.beacon_hp=minf(game.BEACON_MAX,game.beacon_hp+120)
	game.hero.hp=minf(game.hero.max_hp,game.hero.hp+100)
	BattleVisuals.burst(game.effects,npc.position,3,Color("e2bc79"),.6)
	game.notify("%s回家了 · +80零件，灯塔+120，协作修灯%d零件" % [camp.scout_name,game.beacon_repair_cost()],6)

func light_home_lantern(camp: Dictionary, index: int) -> void:
	if camp.state!="delivered":return
	if is_instance_valid(camp.home_lantern):return
	var npc: BattleUnit=camp.npc
	var lantern:=Node3D.new()
	lantern.name="HomecomingLantern%d" % index
	add_child(lantern)
	lantern.position=npc.position+Vector3(-.65,0,.65)
	var model: Node3D=HOME_LANTERN_SCENE.instantiate() as Node3D
	lantern.add_child(model);model.scale=Vector3.ONE*.55
	var light:=OmniLight3D.new()
	light.name="HomeLight"
	lantern.add_child(light);light.position=Vector3.UP*.80
	light.light_color=Color("ffc27b")
	light.omni_range=HOME_LIGHT_RANGE;light.omni_attenuation=1.6
	light.light_energy=1.05;light.light_size=.12;light.shadow_enabled=false
	camp.home_lantern=lantern;camp.home_light=light

func on_night() -> bool:
	var interrupted:=false
	for site in generators:
		site.label.visible=false
		if site.state!="active":continue
		site.state="ready";site.progress=0.0;site.guards=[]
		site.ring.visible=false;site.lamp.light_energy=0
		site.label.text="充能中断 · 次日可重试";interrupted=true
	for camp in camps:
		camp.label.visible=camp.state=="delivered"
		if camp.state!="escort":continue
		camp.state="waiting";camp.trail.clear();camp.guards=[]
		var npc: BattleUnit=camp.npc
		npc.position=camp.position+Vector3(-1.1,0,2.3);npc.position.y=game.outpost_height(npc.position)
		npc.path.clear()
		npc.moving=false;npc.set_locomotion_velocity(Vector3.ZERO)
		camp.label.position=camp.position+Vector3.UP*2.5
		camp.label.text=camp.scout_name+"撤回营地 · 次日救援";interrupted=true
	return interrupted

func on_day() -> void:
	for site in generators:
		site.label.visible=true
		if site.state=="ready":site.label.text="废墟发电机 · F 启动"
	for camp in camps:
		camp.label.visible=true
		if camp.state=="waiting":camp.label.text=camp.scout_name+" · F 护送回家"

func objective_text() -> String:
	for site in generators:
		if site.state=="active" and game.hero.position.distance_to(site.position)<=HOLD_RADIUS:return "发电机 %d%% · %s" % [roundi(float(site.progress)/HOLD_SECONDS*100),"清除来袭" if guards_alive(site) else "守住灯圈"]
	for camp in camps:
		if camp.state=="escort":return "%s跟随中 · 日落前带回家" % camp.scout_name
	for site in generators:
		if site.state=="active":return "发电机 %d%% · 返回灯圈继续充能" % roundi(float(site.progress)/HOLD_SECONDS*100)
	return "远征 · 能源芯 %d/3 · 救援 %d/2" % [game.generator_cells,game.survivors_rescued]
