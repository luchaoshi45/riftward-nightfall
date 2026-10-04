class_name WildDiscoveries
extends Node3D
## Short excursions: choose recovery, memory, supplies, or a temporary safe light.
const ITEM_COUNT := 18
const USE_RADIUS := 3.2
const CHANNEL_RADIUS := 4.0
const CHANNEL_SECONDS := 3.0
const WAYLIGHT_SECONDS := 30.0
const WAYLIGHT_RADIUS := 7.0
const LIGHT_BUDGET := 6
const LIGHT_VIEW_DISTANCE := 40.0
const MIN_SPACING := 4.8
const KINDS := ["ember_bloom", "memory_crystal", "supply_cache", "waylight"]
const TITLES := {"ember_bloom":"余烬花", "memory_crystal":"记忆晶簇", "supply_cache":"遗落补给箱", "waylight":"引路灯碑"}
const COLORS := {"ember_bloom":Color("ffb26b"), "memory_crystal":Color("82c8ff"), "supply_cache":Color("e4b47a"), "waylight":Color("94ead3")}

var game: Node3D
var rng := RandomNumberGenerator.new()
var items: Array[Dictionary] = []
var scenes: Dictionary = {}
var elapsed := 0.0

func _init() -> void:
	rng.randomize()

func setup(owner_game: Node3D) -> void:
	game = owner_game
	for kind: String in KINDS:
		scenes[kind] = load("res://assets/models/"+kind+".glb") as PackedScene
	for index in ITEM_COUNT:
		var kind: String = KINDS[index%KINDS.size()]
		var point := choose_position(index, Vector3.INF)
		var node := Node3D.new()
		node.name = "Discovery%d" % index
		add_child(node)
		node.position = point
		var lamp := OmniLight3D.new()
		node.add_child(lamp)
		lamp.position = Vector3(0,1.35,0)
		lamp.shadow_enabled = false
		lamp.light_energy = 0.0
		var label := Label3D.new()
		node.add_child(label)
		label.position = Vector3(0,2.8,0)
		label.font_size = 28
		label.pixel_size = .008
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 5
		label.visible = false
		var ring := BattleVisuals.ring(node,Vector3.UP*.09,1.2,COLORS[kind],.024)
		ring.visible = false
		var field := BattleVisuals.ring(node,Vector3.UP*.11,WAYLIGHT_RADIUS,COLORS.waylight,.025)
		field.visible = false
		var item := {"position":point,"node":node,"kind":kind,"state":"ready","respawn":0.0,"lamp":lamp,"label":label,"ring":ring,"field":field,"progress":0.0,"remaining":0.0,"visual":null,"serial":0,"feedback_time":0.0}
		items.append(item)
		replace_model(item)
		clear_visual_space(point)
	update_lights()

func gameplay_active() -> bool:
	return is_instance_valid(game) and (game.phase == "day" or game.phase == "night")

func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()

func position_available(point: Vector3, ignore_index: int = -1) -> bool:
	if not game.outpost_walkable(point):return false
	for block: Rect2 in game.WALK_BLOCKS:
		if block.grow(MIN_SPACING).has_point(Vector2(point.x,point.z)):return false
	for collection: Array in [game.world.salvage,game.world.tower_pads,game.world.relays,game.world.nests]:
		for old: Dictionary in collection:
			if flat_distance(point,old.position)<MIN_SPACING:return false
	if game.expeditions:
		for old: Dictionary in game.expeditions.generators+game.expeditions.camps:
			if flat_distance(point,old.position)<MIN_SPACING:return false
	var wildlife: Node3D=game.get("wildlife")
	if is_instance_valid(wildlife):
		for animal: Dictionary in wildlife.animals:
			if flat_distance(point,animal.position)<5.0:return false
	for index in items.size():
		if index == ignore_index:continue
		if flat_distance(point,items[index].position)<MIN_SPACING:return false
	return true

func choose_position(index: int, previous: Vector3) -> Vector3:
	# Keep early discoveries close, but reserve the gate, towers and old objectives.
	var minimum := 10.0 if index<4 else 18.0
	var maximum := 24.0 if index<4 else 65.0
	for attempt in 900:
		var angle := rng.randf_range(0,TAU)
		var radius := sqrt(rng.randf_range(minimum*minimum,maximum*maximum))
		var point := Vector3(cos(angle)*radius,0,sin(angle)*radius)
		if index==0 and attempt==0 and previous==Vector3.INF:point=Vector3(-13,0,22)
		if previous!=Vector3.INF and flat_distance(point,previous)<7.0:continue
		if not position_available(point,index):continue
		point.y=game.outpost_height(point)
		return point
	# Deterministic fallback also obeys all clearances; do not silently overlap a wall.
	for radius in range(int(minimum)+1,int(maximum),2):
		for step in 120:
			var angle := TAU*float(step)/120.0
			var point := Vector3(cos(angle)*radius,0,sin(angle)*radius)
			if previous!=Vector3.INF and flat_distance(point,previous)<7.0:continue
			if position_available(point,index):
				point.y=game.outpost_height(point)
				return point
	push_error("Cannot reserve a reachable wilderness discovery position")
	return previous if previous!=Vector3.INF else Vector3(-18,0,-18)

func clear_visual_space(point: Vector3) -> void:
	for prop in game.world.get_children():
		if not prop is Node3D:continue
		var path: String=prop.scene_file_path
		var clearance:=0.0
		if path.ends_with("dead_tree.glb"):clearance=4.5
		elif path.ends_with("ruined_house.glb"):clearance=6.5
		elif path.ends_with("truck_wreck.glb"):clearance=5.5
		elif path.ends_with("rock_v2.glb"):clearance=2.6
		if clearance>0 and flat_distance(prop.position,point)<clearance:prop.queue_free()

func replace_model(item: Dictionary) -> void:
	if is_instance_valid(item.visual):item.visual.queue_free()
	var scene: PackedScene=scenes[item.kind]
	assert(scene!=null,"Blender wilderness discovery asset is required: "+str(item.kind))
	var model:=scene.instantiate() as Node3D
	(item.node as Node3D).add_child(model)
	model.rotation.y=rng.randf_range(0,TAU)
	item.visual=model
	item.lamp.light_color=COLORS[item.kind]
	item.label.modulate=COLORS[item.kind]
	item.ring.material_override=BattleVisuals.material(COLORS[item.kind],.6)
	item.node.visible=true

func nearest_item() -> int:
	if not gameplay_active():return -1
	var selected := -1
	var distance := USE_RADIUS
	for index in items.size():
		if items[index].state!="ready" and items[index].state!="channel":continue
		var candidate: float=game.hero.position.distance_to(items[index].position)
		if candidate<distance:selected=index;distance=candidate
	return selected

func interaction_prompt() -> String:
	if not gameplay_active():return ""
	for item: Dictionary in items:
		if item.state=="channel":return "开启补给箱 %d%% · 留在 4 米内" % roundi(float(item.progress)/CHANNEL_SECONDS*100)
	var index:=nearest_item()
	if index<0:return ""
	match items[index].kind:
		"ember_bloom":return "F 采集余烬花 · +12 零件，恢复 70 生命"
		"memory_crystal":return "F 吸收记忆晶簇 · +12 记忆，恢复 45 法力"
		"supply_cache":return "F 开启补给箱 · 守住 3 秒，+40 零件、+6 记忆"
		"waylight":return "F 点亮引路灯碑 · 30 秒护盾灯区"
	return ""

func interact() -> bool:
	if not gameplay_active():return false
	for item: Dictionary in items:
		if item.state=="channel":return true
	var index:=nearest_item()
	if index<0:return false
	return interact_index(index)

func interact_index(index: int) -> bool:
	if not gameplay_active() or index<0 or index>=items.size():return false
	for item: Dictionary in items:
		if item.state=="channel":return item == items[index]
	var item: Dictionary=items[index]
	if item.state!="ready":return false
	if game.hero.position.distance_to(item.position)>USE_RADIUS and item.kind!="supply_cache":return false
	if game.hero.position.distance_to(item.position)>CHANNEL_RADIUS and item.kind=="supply_cache":return false
	match item.kind:
		"supply_cache":
			item.state="channel";item.progress=0.0
			game.notify("正在开启补给箱 · 守住周围 3 秒，离开会中断",3)
		"waylight":
			item.state="active";item.remaining=WAYLIGHT_SECONDS;item.feedback_time=1.6
			item.field.visible=true
			_refresh_motivation_lights()
			game.grant_exploration_reward("引路灯碑点亮",item.position,0,0,0.0,0.0,"waylight")
			apply_waylight(item)
			update_lights()
		"ember_bloom":
			begin_cooling(item,rng.randf_range(45,65))
			game.grant_exploration_reward("余烬花",item.position,12,0,70.0,0.0,"ember_bloom")
		"memory_crystal":
			begin_cooling(item,rng.randf_range(45,65))
			game.grant_exploration_reward("记忆晶簇",item.position,0,12,0.0,45.0,"memory_crystal")
	return true

func begin_cooling(item: Dictionary, seconds: float) -> void:
	item.state="cooling";item.respawn=seconds;item.progress=0.0;item.remaining=0.0
	item.node.visible=false;item.lamp.light_energy=0.0
	item.field.visible=false;item.label.visible=false;item.ring.visible=false

func apply_waylight(item: Dictionary) -> void:
	if game.hero.alive and flat_distance(game.hero.position,item.position)<=WAYLIGHT_RADIUS:
		# Larger W or wildlife shields keep their own expiry even inside a lamp field.
		if game.hero.shield<=50.0:
			game.hero.shield=50.0
			game.hero.shield_time=2.0

func respawn_item(index: int) -> void:
	var item: Dictionary=items[index]
	var point:=choose_position(index,item.position)
	var old_kind: int=KINDS.find(item.kind)
	item.kind=KINDS[(old_kind+rng.randi_range(1,3))%KINDS.size()]
	item.position=point;item.node.position=point;item.serial+=1
	item.state="ready";item.respawn=0.0
	replace_model(item)
	clear_visual_space(point)

func tick(delta: float) -> void:
	if not gameplay_active():return
	elapsed+=delta
	for index in items.size():
		if not gameplay_active():break
		var item: Dictionary=items[index]
		item.feedback_time=maxf(0.0,float(item.feedback_time)-delta)
		match item.state:
			"channel":
				if game.hero.position.distance_to(item.position)>CHANNEL_RADIUS:
					item.state="ready";item.progress=0.0
					game.notify("补给箱开启中断 · 回到附近可重新尝试",2)
				else:
					item.progress=minf(CHANNEL_SECONDS,float(item.progress)+delta)
					if item.progress>=CHANNEL_SECONDS:
						begin_cooling(item,rng.randf_range(45,65))
						game.grant_exploration_reward("遗落补给箱",item.position,40,6,0.0,0.0,"supply_cache")
			"active":
				item.remaining=maxf(0.0,float(item.remaining)-delta)
				if item.remaining<=0:begin_cooling(item,50.0)
				else:apply_waylight(item)
			"cooling":
				item.respawn=maxf(0.0,float(item.respawn)-delta)
				if item.respawn<=0:respawn_item(index)
		var distance: float=game.hero.position.distance_to(item.position)
		item.label.visible=item.state!="cooling" and distance<11.0 and item.feedback_time<=0.0
		item.ring.visible=(item.state=="ready" or item.state=="channel") and distance<5.5
		item.field.visible=item.state=="active" and distance<18.0
		if item.state=="channel":item.label.text="补给箱 %d%%" % roundi(float(item.progress)/CHANNEL_SECONDS*100)
		elif item.state=="active":item.label.text="护盾灯区 · %d秒" % ceili(item.remaining)
		else:item.label.text=TITLES[item.kind]+" · F"
	_refresh_motivation_lights()
	update_lights()

func _refresh_motivation_lights() -> void:
	if not game or not game.get("exploration"):return
	var active := 0
	for item: Dictionary in items:
		if item.kind=="waylight" and item.state=="active":active+=1
	game.exploration.set_waylight_count(active)

func motivation_target() -> Dictionary:
	if not game or not game.get("exploration"):return {}
	var kind: String=game.exploration.next_kind()
	if kind.is_empty():return {}
	var selected: Dictionary={}
	var distance:=INF
	for item: Dictionary in items:
		if item.kind!=kind or item.state!="ready":continue
		var candidate: float=game.hero.position.distance_to(item.position)
		if candidate<distance:
			distance=candidate;selected=item
	if selected.is_empty():return {}
	return {"kind":kind,"distance":distance,"position":selected.position}

func update_lights() -> void:
	var nearby: Array[Dictionary]=[]
	for item: Dictionary in items:
		item.lamp.light_energy=0.0
		item.lamp.visible=false
		if item.state=="cooling":continue
		var distance: float=game.hero.position.distance_to(item.position)
		if distance<=LIGHT_VIEW_DISTANCE:nearby.append({"item":item,"distance":distance})
	nearby.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.distance<b.distance)
	for index in mini(LIGHT_BUDGET,nearby.size()):
		var item: Dictionary=nearby[index].item
		item.lamp.visible=true
		var active: bool=item.state=="active"
		item.lamp.omni_range=9.0 if active else 5.0
		item.lamp.light_energy=(2.3 if active else 1.05)*(1.0+.045*sin(elapsed*2.1+float(index)))
