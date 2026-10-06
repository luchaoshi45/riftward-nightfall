class_name OutpostControlGroups
extends RefCounted
## Run-local shortcuts for selection, independent of every squad's orders.
const SLOT_COUNT := 3

var _game: Node3D
var _squads: Node3D
var _groups: Dictionary = {}
var _epoch := 0

func setup(owner_game: Node3D) -> void:
	clear()
	if not is_instance_valid(owner_game) or owner_game.is_queued_for_deletion(): return
	_game = owner_game
	var manager: Variant = owner_game.get("squads")
	if is_instance_valid(manager) and manager is Node3D:
		_squads = manager

func clear() -> void:
	_epoch += 1
	_groups.clear()
	_game = null
	_squads = null

func save(slot: int) -> Dictionary:
	var reason: String = _operation_reason(slot)
	if not reason.is_empty(): return _result(false, reason, slot)
	var selected: Variant = _squads.get("selected_ids")
	if not selected is Array: return _result(false, "squads_unavailable", slot)
	var roster: Array = _roster()
	var entries: Array[Dictionary] = []
	var ids: Array[int] = []
	for value: Variant in selected:
		if typeof(value) != TYPE_INT: continue
		var id: int = int(value)
		if id in ids: continue
		var squad: Dictionary = _squad_for_id(roster, id)
		if squad.is_empty() or not _squad_alive(squad): continue
		# IDs are stable within a run but reused after clear. Retain the original
		# dictionary identity so a new same-numbered squad cannot inherit a group.
		entries.append({"id": id, "identity": squad})
		ids.append(id)
	_groups[slot] = entries
	_game.selection_dragging = false
	return _result(true, "", slot, ids)

func select(slot: int, additive: bool = false) -> Dictionary:
	var reason: String = _operation_reason(slot)
	if not reason.is_empty(): return _result(false, reason, slot)
	var ids: Array[int] = _group_ids(slot, true)
	if ids.is_empty(): return _result(false, "empty_group", slot)
	var manager: Node3D = _squads
	var epoch: int = _epoch
	var selected: Array[int] = manager.select_ids(ids, additive)
	# Selection-circle changes are synchronous. A lifecycle callback must not
	# let an old invocation cancel a new run's drag or report a stale selection.
	if epoch != _epoch: return _result(false, "closed", slot)
	if not _manager_valid(): return _result(false, "squads_unavailable", slot)
	if _group_ids(slot, false).is_empty(): return _result(false, "closed", slot)
	# Selection was committed before any circle notification. A phase-only
	# change afterwards cannot turn that accepted action into a refusal.
	_game.selection_dragging = false
	return _result(true, "", slot, selected)

func snapshot() -> Dictionary:
	var groups: Array[Dictionary] = []
	for slot in range(1, SLOT_COUNT + 1):
		var ids: Array[int] = _group_ids(slot, false)
		var alive_ids: Array[int] = _group_ids(slot, true)
		groups.append({"slot": slot, "ids": ids, "alive_ids": alive_ids, "count": alive_ids.size()})
	var reason: String = _availability_reason()
	return {"groups": groups, "available": reason.is_empty(), "reason": reason}

func _result(ok: bool, reason: String, slot: int, ids: Array[int] = []) -> Dictionary:
	return {"ok": ok, "reason": reason, "slot": slot, "ids": ids.duplicate(), "count": ids.size()}

func _operation_reason(slot: int) -> String:
	if slot < 1 or slot > SLOT_COUNT: return "invalid_slot"
	return _availability_reason()

func _availability_reason() -> String:
	if not is_instance_valid(_game) or _game.is_queued_for_deletion(): return "closed"
	if _game.quitting or _game.restart_pending: return "closed"
	if _game.phase not in ["day", "night"]: return "not_active"
	if _game.music_credits_open: return "source_open"
	var construction: Variant = _game.get("construction")
	if is_instance_valid(construction) and bool(construction.get("active")): return "construction_active"
	var rally: Variant = _game.get("rally")
	if is_instance_valid(rally) and bool(rally.get("active")): return "rally_active"
	var actor: Variant = _game.get("hero")
	if not is_instance_valid(actor) or not actor is BattleUnit: return "hero_unavailable"
	if actor.is_queued_for_deletion() or not actor.alive or not (float(actor.hp) > 0.0): return "hero_unavailable"
	if not (float(_game.beacon_hp) > 0.0): return "beacon_unavailable"
	if not _manager_valid() or not _squads.has_method("select_ids"): return "squads_unavailable"
	return ""

func _manager_valid() -> bool:
	if not is_instance_valid(_game) or _game.is_queued_for_deletion(): return false
	if not is_instance_valid(_squads) or _squads.is_queued_for_deletion(): return false
	var current: Variant = _game.get("squads")
	return is_instance_valid(current) and current == _squads

func _roster() -> Array:
	if not _manager_valid(): return []
	var value: Variant = _squads.get("squads")
	return value if value is Array else []

func _squad_for_id(roster: Array, id: int) -> Dictionary:
	if id < 0 or id >= roster.size(): return {}
	var squad: Variant = roster[id]
	if not squad is Dictionary or int(squad.get("id", -1)) != id: return {}
	return squad

func _squad_alive(squad: Dictionary) -> bool:
	var members: Variant = squad.get("members", [])
	if not members is Array: return false
	for member: Variant in members:
		if not is_instance_valid(member) or not member is BattleUnit: continue
		if not member.is_queued_for_deletion() and member.alive: return true
	return false

func _group_ids(slot: int, alive_only: bool) -> Array[int]:
	var ids: Array[int] = []
	var roster: Array = _roster()
	var entries: Array = _groups.get(slot, [])
	for entry: Dictionary in entries:
		var id: int = int(entry.id)
		var squad: Dictionary = _squad_for_id(roster, id)
		if squad.is_empty() or not is_same(squad, entry.identity): continue
		if alive_only and not _squad_alive(squad): continue
		if id not in ids: ids.append(id)
	return ids
