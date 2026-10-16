extends RefCounted
## A separate optional trial never reverses the original completed generator.
const HOLD := 12.0
const RADIUS := 5.0
const REWARD := 50
const GUARDS := 3
const CONFIRM := 3.0
var game: Node3D
var expeditions: Node3D
var random := RandomNumberGenerator.new()
var day_used := -1
var pending: Dictionary = {}
var confirmation := 0.0
var pending_node: WeakRef
var trial: Dictionary = {}
var units: Dictionary = {}
var epoch := 0
func setup(controller: Node3D, owner_expeditions: Node3D) -> void:
 clear();game=controller;expeditions=owner_expeditions;day_used=-1
 random.seed=preload("res://scripts/run_session.gd").stream_seed(game.run.seed_value,"generator_overload")
func active() -> bool:
 return is_instance_valid(game) and is_instance_valid(expeditions) and game.expeditions==expeditions and not expeditions.is_queued_for_deletion() and not game.is_queued_for_deletion() and not game.quitting and not game.restart_pending and not game.shutting_down and game.phase=="day" and game.phase_time>0.0 and game.run_mode!="teaching" and is_instance_valid(game.hero) and game.hero.alive and game.hero.hp>0.0 and game.beacon_hp>0.0
func owned(site: Dictionary) -> bool:
 return active() and expeditions._site_owned(site) and site.state=="complete" and is_instance_valid(site.node) and site.node.is_inside_tree() and not site.node.is_queued_for_deletion() and site.node.position==site.position
func nearest() -> Dictionary:
 if not active():return {}
 var selected: Dictionary={}
 var distance:=3.4
 for site: Dictionary in expeditions.generators:
  if not owned(site):continue
  var candidate: float=game.hero.position.distance_to(site.position)
  if candidate<distance:selected=site;distance=candidate
 return selected
func prompt() -> String:
 var site:=nearest()
 if site.is_empty():return ""
 if not trial.is_empty() and is_same(trial.site,site) and trial.state=="active":return "过载 %d%% · 守圈并清除%d名守卫；无人守圈立即失败" % [roundi(float(trial.progress)/HOLD*100),GUARDS-int(trial.deaths.size())]
 if day_used==game.day_number:return "本日过载机会已使用 · 原能源芯保留"
 if not pending.is_empty() and is_same(pending,site) and confirmation>0:return "F 再确认过载 · 12秒＋3守卫，成功50光；无人守圈/日落失败"
 return "F 过载发电机 · 12秒＋3守卫，成功50光；无人守圈/日落失败"
func interact() -> bool:
 var site:=nearest()
 if site.is_empty() or day_used==game.day_number:return false
 if pending.is_empty() or not is_same(pending,site) or pending_node==null or pending_node.get_ref()!=site.node or confirmation<=0:
  pending=site;pending_node=weakref(site.node);confirmation=CONFIRM;game.notify(prompt(),3);return true
 var hero_point: Vector3=game.hero.position
 var anchor: Vector3=site.position
 if absf(hero_point.y-float(game.outpost_height(hero_point)))>.9 or not game.can_attack_line(hero_point,anchor) or not game.can_traverse(hero_point,anchor):return false
 if not owned(site) or game.hero.position!=hero_point or site.position!=anchor or day_used==game.day_number:return false
 var points:=_spawn_points(anchor)
 if points.size()!=GUARDS:
  game.notify("过载落点受阻 · 本日机会保留",3);return false
 if not owned(site) or game.hero.position!=hero_point or site.position!=anchor:return false
 day_used=game.day_number;pending={};confirmation=0.0;epoch+=1
 trial={"site":site,"node":weakref(site.node),"position":anchor,"day":game.day_number,"epoch":epoch,"state":"active","progress":0.0,"deaths":{},"guards":[],"tokens":[]}
 var generation:=epoch
 for slot in GUARDS:
  var point: Vector3=points[slot]
  if generation!=epoch or not owned(site) or trial.is_empty():return false
  var enemy: BattleUnit=game.spawn_creature(false,"",true,random)
  if generation!=epoch or not active() or trial.is_empty():
   if is_instance_valid(enemy):
    game.enemies.erase(enemy);enemy.queue_free()
   return false
  enemy.position=point;enemy.title="过载守卫";enemy.set_meta("day_hunter",true);enemy.set_meta("generator_overload",true);enemy.speed=3.4
  var token:=enemy.get_instance_id()
  units[token]={"unit":weakref(enemy),"epoch":generation,"before":-1.0,"lethal":false}
  enemy.damaged.connect(_before_damage)
  enemy.damage_confirmed.connect(_confirmed_damage)
  trial.guards.append(enemy)
  trial.tokens.append(token)
 site.ring.visible=true
 site.label.text="过载0% · 无人守圈立即失败"
 game.notify("过载已启动 · 守圈12秒并击杀3守卫，成功50光；原能源芯保留",5)
 return true
func _spawn_points(anchor: Vector3) -> Array[Vector3]:
 var occupied: Array[Vector3]=[]
 var actors: Array=[game.hero]
 actors.append_array(game.enemies)
 for squad: Dictionary in game.squads.squads:actors.append_array(squad.members)
 for actor: Variant in actors:
  if is_instance_valid(actor) and actor.alive and actor.hp>0.0 and actor.is_inside_tree() and not actor.is_queued_for_deletion():occupied.append(actor.position)
 var points: Array[Vector3]=[]
 for radius in [7.0,8.5,10.0]:
  for index in 24:
   var angle:=TAU*float(index)/24.0+.35
   var point:=anchor+Vector3(cos(angle)*radius,0,sin(angle)*radius)
   if not game.outpost_walkable(point):continue
   point.y=game.outpost_height(point)
   if not game.can_traverse(anchor,point):continue
   var clear_point:=true
   for position: Vector3 in occupied:
    if point.distance_to(position)<1.5:clear_point=false;break
   if not clear_point:continue
   points.append(point);occupied.append(point)
   if points.size()==GUARDS:return points
 return []
func _current() -> bool:
 return not trial.is_empty() and trial.state=="active" and owned(trial.site) and (trial.node as WeakRef).get_ref()==trial.site.node and trial.position==trial.site.position and int(trial.epoch)==epoch and int(trial.day)==game.day_number
func owns(enemy: Variant) -> bool:
 if not is_instance_valid(enemy):return false
 var row: Dictionary=units.get(enemy.get_instance_id(),{})
 return not row.is_empty() and (row.unit as WeakRef).get_ref()==enemy
func _before_damage(enemy: BattleUnit, _source: BattleUnit) -> void:
 if owns(enemy):units[enemy.get_instance_id()].before=enemy.hp
func _confirmed_damage(enemy: BattleUnit, _source: BattleUnit, loss: float, _shield: float) -> void:
 if not owns(enemy):return
 var row: Dictionary=units[enemy.get_instance_id()]
 if enemy.hp==0.0 and loss>0.0 and is_equal_approx(float(row.before)-enemy.hp,loss):row.lethal=true
 row.before=-1.0
func on_defeated(enemy: BattleUnit) -> bool:
 if not owns(enemy):return not bool(enemy.get_meta("generator_overload",false))
 var token:=enemy.get_instance_id()
 var row: Dictionary=units[token]
 if _current() and bool(row.lethal) and int(row.epoch)==epoch and enemy in game.enemies and not enemy.alive and enemy.hp==0.0 and not enemy.is_queued_for_deletion():
  if not trial.deaths.has(token):
   trial.deaths[token]=true
   game.squads.veterancy.on_enemy_defeated(enemy)
   game.specializations.forget_enemy(enemy)
   enemy.visible=false
   enemy.queue_free()
 return false
func _holding() -> bool:
 var candidates: Array=[game.hero]
 for squad: Dictionary in game.squads.squads:
  if String(squad.kind) in ["hauler","medic"]:continue
  candidates.append_array(squad.members)
 var anchor: Vector3=trial.position
 for unit: Variant in candidates:
  if not game._supply_opener_valid(unit) or unit.position.distance_to(anchor)>RADIUS:continue
  if absf(unit.position.y-float(game.outpost_height(unit.position)))>.9:continue
  var position_before: Vector3=unit.position
  var generation:=epoch
  var roster: Node3D=game.squads
  if game.can_attack_line(unit.position,anchor) and game.can_traverse(unit.position,anchor) and _current() and epoch==generation and game.squads==roster and game._supply_opener_valid(unit) and unit.position==position_before:return true
 return false
func tick(delta: float) -> void:
 if not is_instance_valid(game):return
 if game.phase in ["paused","draft"]:return
 if not active():
  if not trial.is_empty() or not pending.is_empty():clear()
  return
 if not is_finite(delta) or delta<=0:return
 if not pending.is_empty():
  confirmation=maxf(0.0,confirmation-delta)
  if confirmation<=0 or not owned(pending) or game.hero.position.distance_to(pending.position)>3.4:pending={}
 if trial.is_empty() or trial.state!="active":return
 if not _current():fail("过载源失效");return
 for token: Variant in trial.tokens:
  if trial.deaths.has(token):continue
  var row: Dictionary=units.get(token,{})
  var enemy: Variant=(row.unit as WeakRef).get_ref() if not row.is_empty() else null
  if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or enemy not in game.enemies or (not enemy.alive and not trial.deaths.has(token)):
   fail("过载守卫失联 · 未发放额外光");return
 if not _holding():fail("过载已撤退 · 无人守圈，原能源芯保留");return
 if not _current():return
 trial.progress=minf(HOLD,float(trial.progress)+delta)
 var site: Dictionary=trial.site
 site.label.text="过载%d%% · 清除%d/3守卫" % [roundi(float(trial.progress)/HOLD*100),int(trial.deaths.size())]
 if float(trial.progress)>=HOLD and trial.deaths.size()==GUARDS:
  trial.state="won";game.scrap+=REWARD
  site.ring.visible=false;site.label.text="过载完成 · +50光 · 原能源芯保留"
  game.notify("过载完成 · +50 光",4)
func fail(reason: String) -> void:
 if not trial.is_empty():
  if is_instance_valid(trial.site.get("ring")):trial.site.ring.visible=false
  if is_instance_valid(trial.site.get("label")):trial.site.label.text=reason
 clear()
 if active():game.notify(reason,3)
func clear() -> void:
 if not trial.is_empty() and is_instance_valid(trial.site.get("ring")): trial.site.ring.visible=false
 epoch+=1;pending={};pending_node=null;confirmation=0.0
 for row: Dictionary in units.values():
  var enemy: Variant=(row.unit as WeakRef).get_ref()
  if not is_instance_valid(enemy):continue
  if is_instance_valid(game):
   game.enemies.erase(enemy)
   if game.specializations:game.specializations.forget_enemy(enemy)
  if not enemy.is_queued_for_deletion():enemy.queue_free()
 units.clear();trial={}
