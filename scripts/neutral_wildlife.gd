class_name NeutralWildlife
extends Node3D
## Peaceful, renewable wildlife. No BattleUnit and no combat target membership.
const REFRESH_SECONDS := 60.0
const INTERACT_RADIUS := 3.2
const BEETLE_COST := 20
var game: Node3D
var animals: Array[Dictionary] = []
var scenery: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var seeded := false

func setup(owner_game: Node3D) -> void:
	game=owner_game
	if not seeded:rng.randomize()
	for prop in game.world.get_children():
		if not prop is Node3D:continue
		var path: String=prop.scene_file_path
		var radius:=0.0
		if path.ends_with("dead_tree.glb"):radius=2.0
		elif path.ends_with("ruined_house.glb"):radius=4.2
		elif path.ends_with("truck_wreck.glb"):radius=3.8
		elif path.ends_with("rock_v2.glb"):radius=1.6
		if radius>0:scenery.append({"position":prop.position,"radius":radius*absf(prop.scale.x)})
	var kinds: Array[String]=["stag","beetle",("stag" if rng.randf()<.5 else "beetle"),("stag" if rng.randf()<.5 else "beetle")]
	for i in kinds.size():
		var point:=Vector3(-17,0,15) if i==0 else random_point()
		if i==0 and occupied(point):point=random_point()
		point.y=game.outpost_height(point)
		create_animal(kinds[i],point)

func create_animal(kind: String, point: Vector3) -> void:
	var animal:=Node3D.new()
	add_child(animal);animal.position=point
	var path: String="res://assets/models/lantern_stag.glb" if kind=="stag" else "res://assets/models/mossback_beetle.glb"
	var packed: PackedScene=load(path)
	var model: Node3D=packed.instantiate()
	animal.add_child(model)
	animal.rotation.y=rng.randf_range(-PI,PI)
	var lamp:=OmniLight3D.new()
	animal.add_child(lamp);lamp.position=Vector3(0,1.9 if kind=="stag" else 1.0,0)
	lamp.light_color=Color("73d5f0") if kind=="stag" else Color("edc66a")
	lamp.omni_range=5.2 if kind=="stag" else 4.4
	lamp.light_energy=.85;lamp.shadow_enabled=false
	lamp.visible=point.distance_to(game.hero.position)<35.0
	var label:=Label3D.new()
	animal.add_child(label);label.position=Vector3(0,3.45 if kind=="stag" else 1.55,0)
	label.text="荧角鹿 · F 抚触" if kind=="stag" else "苔背甲虫 · F 交换"
	label.font_size=29;label.pixel_size=.006;label.outline_size=5
	label.modulate=lamp.light_color;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.visible=false
	var limbs: Array[Dictionary]=[]
	for side in ["L","R"]:
		for limb in (["F","B"] if kind=="stag" else ["0","1","2"]):
			var prefix: String="Stag" if kind=="stag" else "Beetle"
			var hip: Node3D=model.find_child(prefix+"Hip"+side+limb,true,false)
			var knee: Node3D=model.find_child(prefix+"Knee"+side+limb,true,false)
			limbs.append({"hip":hip,"knee":knee,"phase":(PI if (side=="R")!=(limb in ["B","1"]) else 0.0),"hip_rest":hip.rotation if hip else Vector3.ZERO,"knee_rest":knee.rotation if knee else Vector3.ZERO})
	animals.append({"node":animal,"position":point,"kind":kind,"state":"idle","model":model,"lamp":lamp,"label":label,"anchor":point,"target":point,"timer":rng.randf_range(2,5),"refresh":0.0,"age":rng.randf_range(0,TAU),"stride":0.0,"moving_weight":0.0,"limbs":limbs,"body":model.find_child("BodyPivot",true,false),"head":model.find_child("HeadPivot",true,false),"ear_l":model.find_child("EarL",true,false),"ear_r":model.find_child("EarR",true,false),"tail":model.find_child("TailPivot",true,false)})

func random_point(previous: Vector3=Vector3.ZERO) -> Vector3:
	for attempt in 160:
		var angle:=rng.randf_range(0,TAU)
		var distance:=rng.randf_range(20,55)
		var point:=Vector3(cos(angle)*distance,0,sin(angle)*distance)
		if not game.outpost_walkable(point) or Vector2(point.x,point.z).length()<20:continue
		if previous!=Vector3.ZERO and point.distance_to(previous)<12:continue
		if occupied(point):continue
		point.y=game.outpost_height(point)
		return point
	# A known open section west of the southern road is a safe bounded fallback.
	var fallback:=Vector3(-37,0,42)
	fallback.y=game.outpost_height(fallback)
	return fallback

func occupied(point: Vector3, skip: Node3D=null) -> bool:
	for obstacle in scenery:
		if Vector2(point.x-obstacle.position.x,point.z-obstacle.position.z).length()<float(obstacle.radius)+.8:return true
	for animal in animals:
		if animal.node==skip:continue
		if (animal.position as Vector3).distance_to(point)<6:return true
	for list in [game.world.salvage,game.world.relays,game.world.nests,game.world.tower_pads]:
		for item in list:
			if (item.position as Vector3).distance_to(point)<5:return true
	if game.get("expeditions"):
		for list in [game.expeditions.generators,game.expeditions.camps]:
			for item in list:
				if (item.position as Vector3).distance_to(point)<5:return true
	if game.get("discoveries"):
		for item in game.discoveries.items:
			if (item.position as Vector3).distance_to(point)<5:return true
	return false

func nearest() -> int:
	if game.phase!="day" and game.phase!="night":return -1
	if not game.hero.alive:return -1
	var distance:=INTERACT_RADIUS
	var selected:=-1
	for i in animals.size():
		if animals[i].state!="idle" and animals[i].state!="walk":continue
		var current: float=game.hero.position.distance_to(animals[i].position)
		if current<distance:selected=i;distance=current
	return selected

func interaction_prompt() -> String:
	var index:=nearest()
	if index<0:return ""
	return "F 抚触荧角鹿 · 恢复生命，获得 90 护盾与记忆" if animals[index].kind=="stag" else "F 与苔背甲虫交换 · 20 零件换法力、生命与记忆"

func interact() -> bool:
	var index:=nearest()
	if index<0:return false
	var animal: Dictionary=animals[index]
	if animal.kind=="beetle" and game.scrap<BEETLE_COST:
		game.notify("甲虫需要 20 零件 · 当前材料不足",2)
		return true
	# Consume the encounter before reward callbacks can open a draft.
	animal.state="leaving";animal.timer=3.0;animal.refresh=REFRESH_SECONDS
	animal.label.visible=false
	if animal.kind=="stag":
		game.hero.shield=maxf(game.hero.shield,90.0)
		game.hero.shield_time=maxf(game.hero.shield_time,10.0)
		game.grant_exploration_reward("荧角鹿的祝福 · 90 护盾",animal.position,0,6,60,0)
		BattleVisuals.burst(game.effects,animal.position,2.8,Color("75d4eb"),.65)
	else:
		game.scrap-=BEETLE_COST
		game.grant_exploration_reward("苔背甲虫交换",animal.position,0,8,40,80)
		BattleVisuals.burst(game.effects,animal.position,2.3,Color("d2d083"),.65)
	return true

func tick(delta: float) -> void:
	if game.phase!="day" and game.phase!="night":return
	for animal in animals:
		animal.lamp.visible=animal.node.visible and (animal.position as Vector3).distance_to(game.hero.position)<35.0
		animal.age+=delta
		animal.timer-=delta
		if animal.state=="leaving" or animal.state=="cooldown":
			animal.refresh-=delta
			if animal.state=="leaving":
				animate(animal,delta,false)
				animal.node.scale=Vector3.ONE*clampf(float(animal.timer),.02,1.0)
				animal.lamp.light_energy=.85*clampf(float(animal.timer),0,1)
				if animal.timer<=0:animal.state="cooldown";animal.node.visible=false;animal.lamp.visible=false
			if animal.refresh<=0:respawn(animal)
			continue
		animal.label.visible=(animal.position as Vector3).distance_to(game.hero.position)<9
		if animal.timer<=0:
			if animal.state=="walk":
				animal.state="idle";animal.timer=rng.randf_range(2.0,5.2)
			else:choose_walk(animal)
		var moved:=false
		if animal.state=="walk":
			var node: Node3D=animal.node
			var direction: Vector3=animal.target-node.position;direction.y=0
			if direction.length()<.18:
				animal.state="idle";animal.timer=rng.randf_range(2,4)
			else:
				var desired:=atan2(-direction.x,-direction.z)
				node.rotation.y=lerp_angle(node.rotation.y,desired,1-exp(-delta*3.2))
				# Settle the heading before moving, rather than sliding sideways.
				var facing: Vector3=-node.basis.z
				if facing.dot(direction.normalized())>.72:
					var speed:=1.15 if animal.kind=="stag" else .68
					var next:=node.position+direction.normalized()*minf(speed*delta,direction.length())
					if game.can_traverse(node.position,next):
						next.y=game.outpost_height(next);node.position=next;animal.position=next;moved=true
					else:animal.state="idle";animal.timer=2.0
		animate(animal,delta,moved)

func choose_walk(animal: Dictionary) -> void:
	for attempt in 20:
		var angle:=rng.randf_range(0,TAU)
		var radius:=rng.randf_range(1.5,6.5)
		var target: Vector3=animal.anchor+Vector3(cos(angle)*radius,0,sin(angle)*radius)
		if not game.outpost_walkable(target) or not game.can_traverse(animal.position,target):continue
		# Keep roaming creatures clear of interactive landmarks.
		if occupied(target,animal.node):continue
		target.y=game.outpost_height(target)
		animal.target=target;animal.state="walk";animal.timer=rng.randf_range(7,11)
		return
	animal.timer=2.5

func respawn(animal: Dictionary) -> void:
	var point:=random_point(animal.position)
	animal.position=point;animal.anchor=point;animal.target=point
	animal.node.position=point;animal.node.scale=Vector3.ONE;animal.node.visible=true
	animal.node.rotation.y=rng.randf_range(-PI,PI)
	animal.lamp.visible=point.distance_to(game.hero.position)<35.0;animal.lamp.light_energy=.85
	animal.state="idle";animal.timer=rng.randf_range(2,5);animal.refresh=0.0
	animal.moving_weight=0.0

func animate(animal: Dictionary, delta: float, moving: bool) -> void:
	var weight: float=move_toward(animal.moving_weight,1.0 if moving else 0.0,delta*4)
	animal.moving_weight=weight
	if moving:animal.stride+=delta*(5.0 if animal.kind=="stag" else 6.2)
	var age: float=animal.age
	var body: Node3D=animal.body
	if body:
		body.rotation.x=sin(age*1.2)*.012+sin(animal.stride*2)*.012*weight
		body.position.y=(1.36 if animal.kind=="stag" else .68)+sin(age*1.7)*.011+absf(sin(animal.stride))*.025*weight
	var head: Node3D=animal.head
	if head:
		head.rotation.x=sin(age*.8)*.045+sin(animal.stride)*.02*weight
		head.rotation.y=sin(age*.51)*.075*(1-weight*.5)
	for limb in animal.limbs:
		var step: float=animal.stride+float(limb.phase)
		if limb.hip:
			limb.hip.rotation=limb.hip_rest+Vector3(sin(step)*(.28 if animal.kind=="stag" else .16)*weight,0,0)
		if limb.knee:
			limb.knee.rotation=limb.knee_rest+Vector3(maxf(0,-sin(step))*(.33 if animal.kind=="stag" else .22)*weight,0,0)
	if animal.ear_l:animal.ear_l.rotation.y=sin(age*2.1)*.07
	if animal.ear_r:animal.ear_r.rotation.y=sin(age*1.6+1.2)*.09
	if animal.tail:animal.tail.rotation.y=sin(age*2.0)*.16
	animal.lamp.light_energy=.80+sin(age*2.2)*.07
