extends RefCounted
## Paid, finite shielding belongs to one actual lamp incarnation and troop identity.
const COST := 12
const RADIUS := 4.8
const SHIELD := 20.0
const SHIELD_SECONDS := 4.0
const DURATION := 30.0
var game: Node3D
var discoveries: Node3D
var bindings: Dictionary = {}
func setup(controller: Node3D, owner_discoveries: Node3D) -> void:
 bindings.clear()
 game = controller
 discoveries = owner_discoveries
func _active() -> bool:
 return is_instance_valid(game) and is_instance_valid(discoveries) and game.discoveries == discoveries and not game.is_queued_for_deletion() and not discoveries.is_queued_for_deletion() and not game.quitting and not game.shutting_down and not game.restart_pending and game.phase in ["day","night"] and game.phase_time > 0.0 and is_instance_valid(game.hero) and game.hero.alive and game.hero.hp > 0.0 and game.beacon_hp > 0.0
func _owned(item: Dictionary) -> bool:
 if not is_instance_valid(discoveries): return false
 var found := false
 for candidate: Dictionary in discoveries.items:
  if is_same(candidate,item): found = true; break
 var node: Variant = item.get("node")
 return found and item.get("kind","") == "waylight" and item.get("state","") == "active" and float(item.get("remaining",0.0)) > 0.0 and is_instance_valid(node) and node is Node3D and node.is_inside_tree() and not node.is_queued_for_deletion() and node.get_parent() == discoveries and node.position == item.position
func _key(item: Dictionary) -> String:
 return "%d:%d" % [item.node.get_instance_id(),int(item.serial)]
func _same(binding: Dictionary, item: Dictionary) -> bool:
 return is_same(binding.source,item) and (binding.node as WeakRef).get_ref() == item.node and int(binding.serial) == int(item.serial)
func snapshot(item: Dictionary) -> Dictionary:
 if not is_instance_valid(game) or not _owned(item): return {}
 var binding: Dictionary = bindings.get(_key(item),{})
 if binding.is_empty() or not _same(binding,item): return {"paid":false,"remaining":0.0,"granted":0}
 var live: bool = not bool(binding.retired)
 return {"paid":true,"remaining":minf(float(binding.remaining),float(item.remaining)) if live else 0.0,"granted":int(binding.granted)}
func purchase(item: Dictionary) -> Dictionary:
 if not _active() or not _owned(item): return {"ok":false,"reason":"灯碑改装暂不可用"}
 if not snapshot(item).get("paid",false):
  if game.hero.position.distance_to(item.position) > discoveries.USE_RADIUS: return {"ok":false,"reason":"靠近灯碑再改装"}
  var hero_point: Vector3 = game.hero.position
  var lamp_point: Vector3 = item.position
  if absf(game.hero.position.y-float(game.outpost_height(game.hero.position))) > .9 or not game.can_attack_line(game.hero.position,item.position) or not game.can_traverse(game.hero.position,item.position): return {"ok":false,"reason":"灯碑不可达"}
  if not _active() or not _owned(item) or game.hero.position != hero_point or item.position != lamp_point or snapshot(item).get("paid",false): return {"ok":false,"reason":"灯碑身份已变化"}
  if not game.districts.has_live("workshop"): return {"ok":false,"reason":"需存活工坊 · 远征掩护12光"}
  if game.scrap < COST: return {"ok":false,"reason":"光不足 · 远征掩护需12光"}
  var live_workshop := false
  for plot: Dictionary in game.districts.plots:
   var model: Variant = plot.get("model")
   if plot.kind == "workshop" and game.districts._living(plot) and is_instance_valid(model) and model.is_inside_tree() and not model.is_queued_for_deletion(): live_workshop = true
  if not live_workshop: return {"ok":false,"reason":"需存活工坊 · 远征掩护12光"}
  # No callbacks between the incarnation debit and publishing its finite state.
  game.scrap -= COST
  bindings[_key(item)] = {"source":item,"node":weakref(item.node),"serial":int(item.serial),"phase":game.phase,"day":game.day_number,"remaining":minf(DURATION,float(item.remaining)),"seen":{},"granted":0,"retired":false}
  return {"ok":true,"reason":"远征掩护已启用 · 每员一次20盾/4秒"}
 return {"ok":false,"reason":"该灯碑已改装 · 不重复收费"}
func _member(unit: Variant, roster: Node3D) -> bool:
 return is_instance_valid(unit) and unit is BattleUnit and unit.is_inside_tree() and not unit.is_queued_for_deletion() and unit.alive and unit.hp > 0.0 and unit.kind == "minion" and unit.team == 0 and unit.get_parent() == roster and bool(unit.get_meta("outpost_squad",false)) and game._supply_opener_valid(unit)
func retire(item: Dictionary) -> void:
 for key: Variant in bindings.keys():
  if is_same(bindings[key].source,item): bindings.erase(key)
func clear() -> void:
 bindings.clear()
func tick(delta: float) -> void:
 if not _active() or not is_finite(delta) or delta <= 0.0: return
 for key: Variant in bindings.keys():
  if not bindings.has(key): continue
  var binding: Dictionary = bindings[key]
  var item: Dictionary = binding.source
  if not _owned(item) or not _same(binding,item): bindings.erase(key); continue
  if binding.retired: continue
  binding.remaining = minf(float(item.remaining),maxf(0.0,float(binding.remaining)-delta))
  if float(binding.remaining) <= 0.0: binding.retired = true; continue
  var roster: Node3D = game.squads
  for squad: Dictionary in roster.squads:
   for unit: Variant in squad.members:
    if not _member(unit,roster) or game.squads != roster: continue
    var token: int = unit.get_instance_id()
    if (binding.seen as Dictionary).has(token): continue
    if not unit.position.is_finite() or Vector2(unit.position.x-item.position.x,unit.position.z-item.position.z).length() > RADIUS: continue
    if absf(unit.position.y-float(game.outpost_height(unit.position))) > .9 or absf(item.position.y-float(game.outpost_height(item.position))) > .9: continue
    var unit_point: Vector3 = unit.position
    var lamp_point: Vector3 = item.position
    if not game.can_attack_line(unit.position,item.position) or not game.can_traverse(unit.position,item.position): continue
    if not _active() or not _owned(item) or not _same(binding,item) or not _member(unit,roster) or unit.position != unit_point or item.position != lamp_point or not bindings.has(key) or not is_same(bindings[key],binding): continue
    # Existing shields, even smaller ones, retain their original size and clock.
    if unit.shield > 0.0 or unit.shield_time > 0.0: continue
    binding.seen[token] = weakref(unit)
    binding.granted = int(binding.granted)+1
    unit.shield = SHIELD
    unit.shield_time = SHIELD_SECONDS
