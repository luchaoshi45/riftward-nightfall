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
var _capture_orders: Array[Dictionary] = []
var _generator_guards: Dictionary = {}
var _epoch := 0

func _retire_node(value: Variant) -> void:
	if is_instance_valid(value) and value is Node and not value.is_queued_for_deletion(): value.queue_free()

func _retire_previous_expeditions() -> void:
	var enemy_list: Variant = game.get("enemies") if is_instance_valid(game) else null
	for site: Dictionary in generators:
		for guard: Variant in site.get("guards", []):
			if is_instance_valid(guard):
				if enemy_list is Array: enemy_list.erase(guard)
				_retire_node(guard)
		for key: String in ["node", "ring", "lamp", "label"]: _retire_node(site.get(key))
	for camp: Dictionary in camps:
		for guard: Variant in camp.get("guards", []):
			if is_instance_valid(guard):
				if enemy_list is Array: enemy_list.erase(guard)
				_retire_node(guard)
		for key: String in ["node", "npc", "label", "home_lantern"]: _retire_node(camp.get(key))

func setup(owner_game: Node3D) -> void:
	cancel_capture_orders()
	_retire_previous_expeditions()
	_epoch += 1
	_generator_guards.clear()
	generators.clear(); camps.clear()
	game=owner_game

	# The east site uses the outer flank, clear of the unchanged northeast
	# relay. Scaling its former z=7 would overlap that interactive relay.
	for original: Vector3 in [Vector3(-17,0,24),Vector3(18,0,25),Vector3(25,0,0)]:
		var point:=original*Vector3(OutpostLayout.CASTLE_HORIZONTAL_SCALE,1,OutpostLayout.CASTLE_HORIZONTAL_SCALE)
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

func _controller_current(controller: Node3D) -> bool:
	if not is_instance_valid(controller) or not is_same(controller, game) or controller.is_queued_for_deletion() or is_queued_for_deletion(): return false
	for property: Dictionary in controller.get_property_list():
		var key := String(property.name)
		if key == "expeditions" and not is_same(controller.get(key), self): return false
		if key in ["quitting", "restart_pending"] and bool(controller.get(key)): return false
	return String(controller.get("phase")) != "ended"

func _site_owned(site: Dictionary) -> bool:
	if not _controller_current(game): return false
	for current: Dictionary in generators:
		if not is_same(current, site): continue
		var model: Variant = site.get("node")
		return is_instance_valid(model) and model is Node3D and not model.is_queued_for_deletion() 			and (site.position as Vector3).is_finite()
	return false

func generator_at_point(point: Vector3) -> int:
	if not _controller_current(game) or String(game.get("phase")) != "day" or not point.is_finite(): return -1
	var selected := -1
	var distance := 3.4
	for index in generators.size():
		var site: Dictionary = generators[index]
		if not _site_owned(site) or String(site.state) not in ["ready", "active"]: continue
		var separation := Vector2(point.x, point.z).distance_to(Vector2(site.position.x, site.position.z))
		if separation <= distance: selected = index; distance = separation
	return selected

func _roster_current(roster: Node3D, generation: int) -> bool:
	if not _controller_current(game) or not is_instance_valid(roster) or roster.is_queued_for_deletion(): return false
	if not is_same(roster.get("game"), game) or int(roster.get("_epoch")) != generation: return false
	for property: Dictionary in game.get_property_list():
		if String(property.name) == "squads" and not is_same(game.get("squads"), roster): return false
	return true

func _original_squad(roster: Node3D, squad: Dictionary) -> bool:
	var rows: Array = roster.get("squads")
	var id := int(squad.get("id", -1))
	return id >= 0 and id < rows.size() and is_same(rows[id], squad) and String(squad.get("kind", "")) != "hauler"

func _living_capture_member(value: Variant) -> bool:
	return is_instance_valid(value) and value is BattleUnit and not value.is_queued_for_deletion() 		and value.alive and value.hp > 0.0 and value.kind == "minion" and value.team == 0

func _capture_context(binding: Dictionary) -> bool:
	if int(binding.get("epoch", -1)) != _epoch: return false
	var controller: Variant = (binding.controller as WeakRef).get_ref()
	var roster: Node3D = (binding.roster as WeakRef).get_ref() as Node3D
	if not _controller_current(controller as Node3D) or not _roster_current(roster, int(binding.generation)): return false
	var site: Dictionary = binding.site
	if not _site_owned(site) or String(site.state) not in ["ready", "active"]: return false
	var model: Variant = (binding.site_node as WeakRef).get_ref()
	if not is_same(site.node, model): return false
	var squad: Dictionary = binding.identity
	return _original_squad(roster, squad) and String(squad.get("order", "")) == "capture"

func _capture_members(binding: Dictionary) -> Array[BattleUnit]:
	var members: Array[BattleUnit] = []
	if not _capture_context(binding): return members
	var squad: Dictionary = binding.identity
	var originals: Array = binding.members
	for slot in mini(originals.size(), squad.members.size()):
		var reference: Variant = originals[slot]
		var member: Variant = reference.get_ref() if reference is WeakRef else null
		if _living_capture_member(member) and is_same(squad.members[slot], member): members.append(member as BattleUnit)
	return members

func _capture_binding(roster: Node3D, squad: Dictionary) -> Dictionary:
	for binding: Dictionary in _capture_orders:
		if not is_same((binding.roster as WeakRef).get_ref(), roster) or not is_same(binding.identity, squad): continue
		if _capture_context(binding) and not _capture_members(binding).is_empty(): return binding
	return {}

func capture_order_matches(roster: Node3D, squad: Dictionary, index: int) -> bool:
	var binding := _capture_binding(roster, squad)
	if binding.is_empty() or int(binding.site_index) != index: return false
	# An explicit fresh command can admit a newly paid replacement, while an
	# unchanged original selection leaves paths and weapon clocks untouched.
	var originals: Array = binding.members
	for slot in squad.members.size():
		var member: Variant = squad.members[slot]
		if not _living_capture_member(member): continue
		var reference: Variant = originals[slot] if slot < originals.size() else null
		if not reference is WeakRef or not is_same(reference.get_ref(), member): return false
	return true

func assign_capture(roster: Node3D, squad: Dictionary, index: int, generation: int) -> bool:
	if not _roster_current(roster, generation) or String(game.get("phase")) != "day" or not _original_squad(roster, squad): return false
	if index < 0 or index >= generators.size() or String(squad.get("order", "")) != "capture": return false
	var site: Dictionary = generators[index]
	if not _site_owned(site) or String(site.state) not in ["ready", "active"]: return false
	var originals: Array = []
	var stations: Array[Vector3] = []
	var alive := 0
	for slot in squad.members.size():
		var member: Variant = squad.members[slot]
		originals.append(weakref(member) if _living_capture_member(member) else null)
		if _living_capture_member(member): alive += 1
		# Capture formations stay inside the original five metre hold circle;
		# multiple teams do not acquire the ordinary march's expanding offsets.
		var point: Vector3 = roster.call("_resolve_destination", (site.position as Vector3) + Vector3((slot - 1) * 1.25, 0, 0))
		if not _roster_current(roster, generation) or not _original_squad(roster, squad) or not _site_owned(site) 			or not is_same(generators[index], site) or String(game.get("phase")) != "day" or String(squad.order) != "capture": return false
		if not point.is_finite() or point.distance_to(site.position) > HOLD_RADIUS 			or not bool(roster.call("_traversable", site.position, point)): point = site.position
		if not _roster_current(roster, generation) or not _original_squad(roster, squad) or String(squad.order) != "capture": return false
		if _living_capture_member(member) and game.has_method("build_day_hunter_route"):
			member.set_meta("capture_route", true)
			game.call("build_day_hunter_route", member, point)
			# A direct walkable segment legitimately has no grid corner. Keep the
			# real destination as a route marker so the first simulation step still
			# exposes an actual path; movement remains speed- and collision-limited.
			if member.path.is_empty() and member.position.distance_to(point) > .16:
				member.path.append(point)
		stations.append(point)
	if alive == 0: return false
	on_capture_order_changed(roster, squad)
	_capture_orders.append({"controller": weakref(game), "roster": weakref(roster), "generation": generation,
		"epoch": _epoch, "identity": squad, "site": site, "site_node": weakref(site.node),
		"site_index": index, "members": originals, "stations": stations})
	squad.destination = site.position
	squad.formation_index = 0
	return true

func capture_station(roster: Node3D, squad: Dictionary, slot: int) -> Vector3:
	var binding := _capture_binding(roster, squad)
	if not binding.is_empty() and slot >= 0 and slot < (binding.stations as Array).size():
		var reference: Variant = binding.members[slot]
		var original: Variant = reference.get_ref() if reference is WeakRef else null
		if _living_capture_member(original) and is_same(squad.members[slot], original): return binding.stations[slot]
	var current: Variant = squad.members[slot] if slot >= 0 and slot < squad.members.size() else null
	return current.position if _living_capture_member(current) else squad.destination

func on_capture_order_changed(roster: Node3D, squad: Dictionary) -> void:
	for index in range(_capture_orders.size() - 1, -1, -1):
		var binding: Dictionary = _capture_orders[index]
		if is_same((binding.roster as WeakRef).get_ref(), roster) and is_same(binding.identity, squad): _capture_orders.remove_at(index)

func _retire_capture(binding: Dictionary, completed: bool = false) -> void:
	# Detach before calling the roster: synchronous callbacks cannot inherit it.
	for index in range(_capture_orders.size() - 1, -1, -1):
		if is_same(_capture_orders[index], binding): _capture_orders.remove_at(index)
	var roster: Node3D = (binding.roster as WeakRef).get_ref() as Node3D
	if not _roster_current(roster, int(binding.generation)) or not _original_squad(roster, binding.identity): return
	if String((binding.identity as Dictionary).get("order", "")) != "capture": return
	roster.call("_cancel_generator_order", binding.identity, completed, binding.stations)

func prepare_capture_squad(roster: Node3D, squad: Dictionary) -> void:
	for binding: Dictionary in _capture_orders.duplicate():
		if not is_same((binding.roster as WeakRef).get_ref(), roster) or not is_same(binding.identity, squad): continue
		if not _capture_context(binding) or _capture_members(binding).is_empty(): _retire_capture(binding)

func on_capture_member_defeated(roster: Node3D, member: BattleUnit) -> void:
	for binding: Dictionary in _capture_orders.duplicate():
		if not is_same((binding.roster as WeakRef).get_ref(), roster): continue
		var original := false
		for reference: Variant in binding.members:
			if reference is WeakRef and is_same(reference.get_ref(), member): original = true; break
		if original and _capture_members(binding).is_empty(): _retire_capture(binding)

func forget_capture_roster(roster: Node3D) -> void:
	for index in range(_capture_orders.size() - 1, -1, -1):
		if is_same((_capture_orders[index].roster as WeakRef).get_ref(), roster): _capture_orders.remove_at(index)

func _retire_generator_guards(site: Dictionary) -> void:
	for guard: Variant in site.get("guards", []):
		if not is_instance_valid(guard): continue
		var token: int = int(guard.get_instance_id())
		_generator_guards.erase(token)
		if guard.defeated.is_connected(_on_generator_guard_defeated): guard.defeated.disconnect(_on_generator_guard_defeated)
		var enemy_list: Variant = game.get("enemies") if is_instance_valid(game) else null
		if enemy_list is Array: enemy_list.erase(guard)
		guard.visible = false
		_retire_node(guard)
	site.guards=[];site.guard_tokens=[];site.guard_deaths={}

func cancel_capture_orders() -> void:
	for binding: Dictionary in _capture_orders.duplicate(): _retire_capture(binding)
	_capture_orders.clear()
	for site: Dictionary in generators:
		_retire_generator_guards(site)
	_generator_guards.clear()

func _guard_binding(creature: Variant) -> Dictionary:
	if not _controller_current(game) or not is_instance_valid(creature) or not creature is BattleUnit 		or creature.is_queued_for_deletion() or not creature.alive or creature.hp <= 0.0 or creature not in game.get("enemies"): return {}
	var row: Dictionary = _generator_guards.get(creature.get_instance_id(), {})
	if row.is_empty() or int(row.epoch) != _epoch or not is_same((row.unit as WeakRef).get_ref(), creature): return {}
	var site: Dictionary = row.site
	if not _site_owned(site) or String(site.state) != "active" or creature not in site.guards: return {}
	return row

func _on_generator_guard_defeated(creature: BattleUnit, _source: BattleUnit) -> void:
	# The ordinary death callback may already have queued this actor for
	# deletion. Its terminal HP/alive state, original trial and weak identity
	# still authorize the one real death before it leaves the production list.
	if not _controller_current(game) or String(game.get("phase")) != "day" or not is_instance_valid(creature) 		or creature.alive or creature.hp > 0.0 or creature not in game.get("enemies"): return
	var token: int = int(creature.get_instance_id())
	var row: Dictionary = _generator_guards.get(token, {})
	if row.is_empty() or int(row.epoch) != _epoch or not is_same((row.unit as WeakRef).get_ref(), creature): return
	var site: Dictionary = row.site
	if not _site_owned(site) or String(site.state) != "active" or token not in site.get("guard_tokens", []) or creature not in site.guards: return
	(site.guard_deaths as Dictionary)[token] = true

func _generator_guards_defeated(site: Dictionary) -> bool:
	var tokens: Array = site.get("guard_tokens", [])
	var deaths: Dictionary = site.get("guard_deaths", {})
	if tokens.size() != 3: return false
	for token: Variant in tokens:
		if not bool(deaths.get(token, false)): return false
	return true

func _generator_guards_lost(site: Dictionary) -> bool:
	var tokens: Array = site.get("guard_tokens", [])
	var deaths: Dictionary = site.get("guard_deaths", {})
	if tokens.size() != 3: return true
	for token: Variant in tokens:
		if bool(deaths.get(token, false)): continue
		var row: Dictionary = _generator_guards.get(token, {})
		if row.is_empty() or not is_same(row.site, site): return true
		var guard: Variant = (row.unit as WeakRef).get_ref()
		if not is_instance_valid(guard) or not guard is BattleUnit or guard.is_queued_for_deletion() 			or not guard.alive or guard.hp <= 0.0 or guard not in game.get("enemies") or guard not in site.guards: return true
	return false

func is_generator_guard(creature: Variant) -> bool:
	return not _guard_binding(creature).is_empty()

func generator_guard_target(creature: BattleUnit) -> Dictionary:
	var row := _guard_binding(creature)
	if row.is_empty() or String(game.get("phase")) != "day": return {}
	# A generator fight belongs to the expedition squad. Prefer any live member
	# bound to this site before considering the hero, even when the hero happens
	# to be closer. This keeps a hero who stays in the fort from absorbing the
	# station guards' damage while the real capture party is approaching.
	var selected_squad: Dictionary = {}
	var squad_best := INF
	var has_site_binding := false
	if not is_same(_guard_binding(creature), row): return {}
	for binding: Dictionary in _capture_orders:
		if not is_same(binding.site, row.site): continue
		has_site_binding = true
		for member: BattleUnit in _capture_members(binding):
			var separation := Vector2(creature.position.x, creature.position.z).distance_to(Vector2(member.position.x, member.position.z))
			if separation > squad_best: continue
			var target := {"kind": "squad", "index": -1, "token": member.get_instance_id(), "unit": member, "position": member.position}
			var reachable := bool(game.call("enemy_target_reachable", creature.position, target))
			if not is_same(_guard_binding(creature), row) or member not in _capture_members(binding): return {}
			if not reachable: continue
			selected_squad = target; squad_best = separation
	if not selected_squad.is_empty():
		return selected_squad if is_same(_guard_binding(creature), row) and String(game.get("phase")) == "day" else {}
	# A bound capture party owns this encounter. If the hero is safely inside
	# the fort, do not let a temporarily unreachable/dead party redirect guard
	# damage through the walls to the player; the site will remain unresolved.
	if has_site_binding and game.has_method("near_squad_controls") and bool(game.call("near_squad_controls")):
		return {}
	var hero: Variant = game.get("hero")
	if is_instance_valid(hero) and hero is BattleUnit and not hero.is_queued_for_deletion() and hero.alive and hero.hp > 0.0:
		var target := {"kind": "hero", "index": -1, "position": hero.position}
		if bool(game.call("enemy_target_reachable", creature.position, target)):
			return target if is_same(_guard_binding(creature), row) and String(game.get("phase")) == "day" else {}
	return {}

func capture_snapshot() -> Dictionary:
	var sites: Array[Dictionary] = []
	var rows: Array[Dictionary] = []
	for binding: Dictionary in _capture_orders:
		var members := _capture_members(binding)
		if members.is_empty(): continue
		var arrived := 0
		var tokens: Array[int] = []
		for member: BattleUnit in members:
			tokens.append(member.get_instance_id())
			if member.position.distance_to((binding.site as Dictionary).position) <= HOLD_RADIUS: arrived += 1
		rows.append({"id": int((binding.identity as Dictionary).id), "site_index": int(binding.site_index),
			"alive": members.size(), "arrived": arrived, "holding": arrived > 0, "member_tokens": tokens})
	for index in generators.size():
		var site: Dictionary = generators[index]
		var ids: Array[int] = []
		var alive := 0
		var arrived := 0
		for row: Dictionary in rows:
			if int(row.site_index) != index: continue
			ids.append(int(row.id)); alive += int(row.alive); arrived += int(row.arrived)
		var hero: Variant = game.get("hero") if _controller_current(game) else null
		var hero_inside: bool = is_instance_valid(hero) and hero is BattleUnit and not hero.is_queued_for_deletion() 			and hero.alive and hero.hp > 0.0 and hero.position.distance_to(site.position) <= HOLD_RADIUS
		var guard_count := 0
		for guard: Variant in site.guards:
			if is_instance_valid(guard) and guard is BattleUnit and not guard.is_queued_for_deletion() and guard.alive and guard.hp > 0.0: guard_count += 1
		sites.append({"index": index, "state": String(site.state), "position": site.position,
			"progress": float(site.progress), "ratio": float(site.progress) / HOLD_SECONDS,
			"assigned_ids": ids, "alive": alive, "arrived": arrived, "holders": arrived,
			"hero_inside": hero_inside, "guards_alive": guard_count,
			"guards_defeated": (site.get("guard_deaths", {}) as Dictionary).size(),
			"guards_lost": _generator_guards_lost(site) if String(site.state) == "active" else false})
	return {"count": rows.size(), "sites": sites, "squads": rows}

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
	if not _controller_current(game) or game.phase!="day" or index<0 or index>=generators.size():return false
	var site: Dictionary=generators[index]
	var controller := game
	var generation := _epoch
	if not _site_owned(site) or site.state!="ready":return false
	site.state="active";site.progress=0.0
	site.guard_tokens=[];site.guard_deaths={};site.guards_lost=false
	site.ring.visible=true;site.lamp.light_energy=1.6
	var guards := spawn_ambush(site.position,3)
	if generation != _epoch or not _controller_current(controller) or game.phase != "day" 		or not _site_owned(site) or site.state != "active": return false
	site.guards=guards
	for guard: BattleUnit in guards:
		if not is_instance_valid(guard) or guard.is_queued_for_deletion() or not guard.alive or guard not in game.enemies: continue
		var token: int = int(guard.get_instance_id())
		site.guard_tokens.append(token)
		_generator_guards[token] = {"unit": weakref(guard), "site": site, "epoch": generation}
		if not guard.defeated.is_connected(_on_generator_guard_defeated): guard.defeated.connect(_on_generator_guard_defeated)
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
	var controller := game
	var generation := _epoch
	for i in count:
		if generation != _epoch or not _controller_current(controller): return guards
		var angle:=TAU*float(i)/float(count)+.35
		var point:=center+Vector3(cos(angle)*7,0,sin(angle)*7)
		if not game.outpost_walkable(point):point=center+Vector3(0,0,7+i)
		point.y=game.outpost_height(point)
		var creature: BattleUnit=game.spawn_creature(false)
		if generation != _epoch or not _controller_current(controller) or not is_instance_valid(creature) 			or creature.is_queued_for_deletion() or creature not in controller.enemies: return guards
		creature.position=point;creature.title="惊醒的潜伏体"
		creature.set_meta("day_hunter",true)
		creature.speed=3.4
		guards.append(creature)
		BattleVisuals.burst(game.effects,point,1.4,Color("ba795d"),.4)
	return guards

func guards_alive(site: Dictionary) -> bool:
	for creature in site.guards:
		if is_instance_valid(creature) and not creature.is_queued_for_deletion() and creature.alive and creature.hp>0.0:return true
	return false

func tick(delta: float) -> void:
	if game.phase!="day":
		if game.phase=="night":
			for camp in camps:
				var resting_scout: BattleUnit=camp.npc
				resting_scout.moving=false;resting_scout.set_locomotion_velocity(Vector3.ZERO);resting_scout.tick(delta)
		return
	if not _controller_current(game): return
	for binding: Dictionary in _capture_orders.duplicate():
		if not _capture_context(binding) or _capture_members(binding).is_empty():
			_retire_capture(binding)
			continue
		var site: Dictionary = binding.site
		if site.state != "ready": continue
		for member: BattleUnit in _capture_members(binding):
			if member.position.distance_to(site.position) > HOLD_RADIUS: continue
			start_generator(int(binding.site_index))
			break
		if not _controller_current(game) or String(game.phase) != "day": return
	for site in generators:
		if site.state!="active":continue
		var in_circle: bool=is_instance_valid(game.hero) and not game.hero.is_queued_for_deletion() and game.hero.alive 			and game.hero.hp>0.0 and game.hero.position.distance_to(site.position)<=HOLD_RADIUS
		if not in_circle:
			for binding: Dictionary in _capture_orders:
				if not is_same(binding.site, site): continue
				for member: BattleUnit in _capture_members(binding):
					if member.position.distance_to(site.position) <= HOLD_RADIUS: in_circle = true; break
				if in_circle: break
		var guards_lost := _generator_guards_lost(site)
		site.guards_lost = guards_lost
		if in_circle and not guards_lost:site.progress=minf(HOLD_SECONDS,float(site.progress)+maxf(0.0,delta))
		var ratio: float=site.progress/HOLD_SECONDS
		site.ring.material_override=site.inside_material if in_circle and not guards_lost else site.outside_material
		site.label.text="守卫失联 · 充能中断，次日重试" if guards_lost else ("充能 %d%% · %s" % [roundi(ratio*100),"清除潜伏体" if ratio>=1 and guards_alive(site) else ("守住灯圈" if in_circle else "返回灯圈继续")])
		if ratio>=1 and _generator_guards_defeated(site):complete_generator(site)
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
	if not _controller_current(game) or game.phase != "day" or not _site_owned(site) 		or site.state != "active" or float(site.progress) < HOLD_SECONDS or guards_alive(site) or not _generator_guards_defeated(site): return
	site.state="complete";site.ring.visible=false
	site.label.text="能源芯已取回 · 灯塔脉冲强化"
	site.label.modulate=Color("7eaea5");site.lamp.light_energy=.5
	game.scrap+=GENERATOR_REWARD;game.generator_cells+=1
	BattleVisuals.burst(game.effects,site.position,4.2,Color("9cddd1"),.7)
	game.notify("能源芯取回 · +100 零件，灯塔攻击脉冲加快",5)
	for binding: Dictionary in _capture_orders.duplicate():
		if is_same(binding.site, site): _retire_capture(binding, true)
	for token in _generator_guards.keys():
		if is_same((_generator_guards[token] as Dictionary).site, site): _generator_guards.erase(token)

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
	cancel_capture_orders()
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
		if site.state == "active" and _generator_guards_lost(site): return "发电机守卫失联 · 充能中断，次日重试"
		if site.state=="active" and game.hero.position.distance_to(site.position)<=HOLD_RADIUS:return "发电机 %d%% · %s" % [roundi(float(site.progress)/HOLD_SECONDS*100),"清除来袭" if guards_alive(site) else "守住灯圈"]
	for binding: Dictionary in _capture_orders:
		var members := _capture_members(binding)
		if members.is_empty(): continue
		var site: Dictionary = binding.site
		var holding := false
		for member: BattleUnit in members:
			if member.position.distance_to(site.position) <= HOLD_RADIUS: holding = true; break
		if site.state == "active" and holding:return "部队夺取发电机 %d%% · %s" % [roundi(float(site.progress)/HOLD_SECONDS*100), "清除来袭" if guards_alive(site) else "守住灯圈"]
	for camp in camps:
		if camp.state=="escort":return "%s跟随中 · 日落前带回家" % camp.scout_name
	for site in generators:
		if site.state=="active":return "发电机 %d%% · 返回灯圈继续充能" % roundi(float(site.progress)/HOLD_SECONDS*100)
	return "远征 · 能源芯 %d/3 · 救援 %d/2" % [game.generator_cells,game.survivors_rescued]
