extends RefCounted
## A run-local, explicit permit. The existing logistics movement and finite
## stock transfer remain authoritative; this module never plans a route.
const COST := 20
const HAUL := "haul"

var logistics: Node3D
var _entries: Dictionary = {}
var _used: Dictionary = {}
var _markers: Dictionary = {}
var _night := -1
var _retired := false
var _spent := 0
var _night_spent := 0

func setup(owner_logistics: Node3D) -> void:
	clear()
	logistics = owner_logistics

func clear() -> void:
	_clear_visuals()
	_entries.clear(); _used.clear()
	_night = -1; _retired = false; _spent = 0; _night_spent = 0
	logistics = null

func _property(name: String) -> Variant:
	return logistics.call("_property", name) if is_instance_valid(logistics) else null

func _game() -> Node3D:
	return logistics.get("game") as Node3D if is_instance_valid(logistics) else null

func _teams() -> Dictionary:
	return logistics.get("_teams") if is_instance_valid(logistics) else {}

func _fields() -> Array:
	return logistics.get("fields") if is_instance_valid(logistics) else []

func _phase() -> String:
	return String(_property("phase"))

func _night_number() -> int:
	var value: Variant = _property("day_number")
	return int(value) if value != null else 1

func _command_allowed() -> bool:
	var controller := _game()
	if not is_instance_valid(logistics) or not is_instance_valid(controller) or controller.is_queued_for_deletion(): return false
	if _phase() not in ["day", "night"]: return false
	for property: String in ["quitting", "restart_pending", "shutting_down"]:
		if bool(_property(property)): return false
	return not (_phase() == "night" and _retired)

func _roster() -> Node:
	return logistics.call("_squads") as Node if is_instance_valid(logistics) else null

func _squad(id: int) -> Dictionary:
	var roster := _roster()
	if not is_instance_valid(roster) or roster.is_queued_for_deletion(): return {}
	var rows: Array = roster.get("squads")
	if id < 0 or id >= rows.size() or not rows[id] is Dictionary: return {}
	var row: Dictionary = rows[id]
	return row if int(row.get("id", -1)) == id and String(row.get("kind", "")) == "hauler" else {}

func _alive(squad: Dictionary) -> bool:
	for member: Variant in squad.get("members", []):
		if bool(logistics.call("_living", member)): return true
	return false

func _selected() -> Array[int]:
	var ids: Array[int] = []
	var roster := _roster()
	if not is_instance_valid(roster): return ids
	for value: Variant in roster.get("selected_ids"):
		var id := int(value)
		var squad := _squad(id)
		if not squad.is_empty() and _alive(squad) and id not in ids: ids.append(id)
	ids.sort()
	return ids

func _target_reason(id: int) -> String:
	var squad := _squad(id)
	if squad.is_empty() or not _alive(squad): return "请选择存活采运工队"
	if String(squad.get("order", "")) != HAUL: return "请先右键指定废料堆"
	var team: Dictionary = _teams().get(id, {})
	var index := int(team.get("preferred_field", -1))
	if not bool(team.get("automatic", false)) or index < 0: return "请先右键指定废料堆"
	if not bool(logistics.call("_field_live", index)): return "指定废料堆已失效"
	if int(_fields()[index].get("remaining", 0)) <= 0: return "指定废料堆已采尽"
	return ""

func _binding_reason(entry: Dictionary) -> String:
	var id := int(entry.get("id", -1))
	var squad := _squad(id)
	if squad.is_empty() or not is_same(squad, entry.get("squad", {})): return "原工队编组已失效"
	if not _alive(squad): return "工队已阵亡"
	if String(squad.get("order", "")) != HAUL: return "手动指挥已取消夜采"
	var team: Dictionary = _teams().get(id, {})
	var index := int(entry.get("field", -1))
	if not bool(team.get("automatic", false)) or int(team.get("preferred_field", -1)) != index: return "资源线已改变 · 夜采取消"
	if not bool(logistics.call("_field_live", index)): return "指定废料堆已失效"
	var field: Dictionary = _fields()[index]
	var reference: Variant = entry.get("field_node")
	var node: Variant = reference.get_ref() if reference is WeakRef else null
	if not is_same(field, entry.get("field_identity", {})) or not is_instance_valid(node) or field.get("node") != node: return "原废料堆身份已失效"
	if int(field.get("remaining", 0)) <= 0: return "指定废料堆已采尽 · 载货返站"
	return ""

func _bind(id: int) -> Dictionary:
	var reason := _target_reason(id)
	if not reason.is_empty(): return {}
	var index := int(_teams()[id].preferred_field)
	var field: Dictionary = _fields()[index]
	return {"id": id, "squad": _squad(id), "field": index, "field_identity": field,
		"field_node": weakref(field.node), "planned": false, "active": false,
		"night": _night_number(), "reason": ""}

func _technology_reason() -> String:
	var districts: Variant = _property("districts")
	if not is_instance_valid(districts) or not districts.has_method("has_live"): return "需要存活研究所与中转站"
	if not bool(districts.call("has_live", "laboratory")): return "需要存活研究所"
	if (logistics.call("_depots") as Array).is_empty(): return "需要存活中转站"
	return ""

func _activate(entry: Dictionary) -> Dictionary:
	var id := int(entry.id)
	if can_haul(id): return {"ok": true, "charged": false, "reason": "夜采装配已生效"}
	var reason := ""
	if not _command_allowed() or _phase() != "night" or _night != _night_number(): reason = "当前不能装配夜采"
	elif _used.has(id): reason = "本队当夜已装配 · 停止后不可重启"
	else:
		reason = _binding_reason(entry)
		if reason.is_empty(): reason = _technology_reason()
		if reason.is_empty() and int(_property("scrap")) < COST: reason = "夜采装配需要20零件"
	entry.planned = false
	if not reason.is_empty():
		entry.active = false; entry.reason = reason
		_entries[id] = entry
		return {"ok": false, "charged": false, "reason": reason}
	# This synchronous commit precedes visuals and navigation. No stock is
	# created, reserved or paid by an observation or a repeated permit request.
	_game().set("scrap", int(_property("scrap")) - COST)
	_used[id] = true; _spent += COST; _night_spent += COST
	entry.active = true; entry.night = _night; entry.reason = "指定堆%d夜采 · 停止不退款" % (int(entry.field) + 1)
	_entries[id] = entry
	var team: Dictionary = _teams()[id]
	# A prepared team keeps its real outbound/loading reservation, timer and
	# destinations across sunset. Only a newly equipped waiting team restarts.
	if int(logistics.call("_team_cargo", id)) <= 0 and int(team.field) < 0:
		team.retry = 0.0
		team.destinations.clear()
		logistics.call("_set_state", team, "idle", entry.reason)
	_refresh_visuals()
	return {"ok": true, "charged": true, "reason": String(entry.reason)}

func _permit_current(id: int) -> bool:
	if _retired or _night < 0 or _night != _night_number() or _phase() not in ["night", "paused", "draft"]: return false
	for property: String in ["quitting", "restart_pending", "shutting_down"]:
		if bool(_property(property)): return false
	var entry: Dictionary = _entries.get(id, {})
	return bool(entry.get("active", false)) and _used.has(id) and _binding_reason(entry).is_empty()

func can_haul(id: int) -> bool:
	return _command_allowed() and _phase() == "night" and _permit_current(id)

func on_night() -> void:
	if not _command_allowed() or _phase() != "night": return
	var number := _night_number()
	if _night == number: return
	_night = number; _night_spent = 0; _used.clear(); _retired = false
	var ids: Array = _entries.keys()
	ids.sort()
	for value: Variant in ids:
		var entry: Dictionary = _entries[int(value)]
		if not bool(entry.get("planned", false)): continue
		_activate(entry)
	_refresh_visuals()

func on_night_end() -> void:
	# Keep the paid ledger until day starts: finish_night initially still has
	# phase=night, and a repeated night hook must not open a second permit.
	for value: Variant in _entries.keys(): cancel(int(value), "夜采结束 · 载货保留")
	_retired = true
	_clear_visuals()

func on_day() -> void:
	# Only the real begin_day transition can renew next-night eligibility.
	# An incorrect night/paused hook cannot erase this night's paid ledger.
	if not _command_allowed() or _phase() != "day": return
	on_night_end()
	_entries.clear(); _used.clear()
	_night = -1; _night_spent = 0; _retired = false

func cancel(id: int, reason: String = "夜采停止 · 已付款不退款") -> void:
	var entry: Dictionary = _entries.get(id, {})
	if entry.is_empty(): return
	var was_active := bool(entry.get("active", false))
	entry.active = false; entry.planned = false; entry.reason = reason
	# Do not clear a replacement same-ID roster's route while retiring the old
	# dictionary's permit. The normal logistics pass owns that new roster.
	if was_active and is_instance_valid(logistics) and is_same(_squad(id), entry.get("squad", {})):
		logistics.call("_stop_night_hauling", id, reason)
	_refresh_visuals()

func advance() -> void:
	if not _command_allowed(): return
	for value: Variant in _entries.keys():
		var entry: Dictionary = _entries[int(value)]
		if not bool(entry.get("active", false)) and not bool(entry.get("planned", false)): continue
		var reason := _binding_reason(entry)
		if not reason.is_empty(): cancel(int(value), reason)
	_refresh_visuals()

func on_member_defeated(token: int) -> void:
	_remove_marker(token)
	for value: Variant in _entries.keys():
		var entry: Dictionary = _entries[int(value)]
		if not bool(entry.get("active", false)) and not bool(entry.get("planned", false)): continue
		if not _alive(_squad(int(value))): cancel(int(value), "工队已阵亡")

func _row(id: int) -> Dictionary:
	var entry: Dictionary = _entries.get(id, {})
	var invalid := _binding_reason(entry) if not entry.is_empty() else ""
	var planned := bool(entry.get("planned", false)) and invalid.is_empty() and _phase() in ["day", "paused", "draft"] and not _retired
	var active := _permit_current(id)
	var reason := invalid if not invalid.is_empty() else String(entry.get("reason", ""))
	return {"id": id, "planned": planned, "used": _used.has(id), "active": active,
		"field": int(entry.get("field", (_teams().get(id, {}) as Dictionary).get("preferred_field", -1))),
		"night": int(entry.get("night", _night_number())), "reason": reason}

func snapshot() -> Dictionary:
	var rows: Array[Dictionary] = []
	var counts := {"planned": 0, "used": 0, "active": 0}
	var roster := _roster()
	if is_instance_valid(roster):
		for squad: Dictionary in roster.get("squads"):
			if String(squad.get("kind", "")) != "hauler": continue
			var row := _row(int(squad.id))
			rows.append(row)
			for state: String in ["planned", "used", "active"]:
				if bool(row[state]): counts[state] = int(counts[state]) + 1
	return {"night": _night, "current_night": _night_number(), "cost": COST, "spent": _spent,
		"night_spent": _night_spent, "retired": _retired, "planned": counts.planned,
		"used": counts.used, "active": counts.active, "teams": rows}

func selection() -> Dictionary:
	var ids := _selected()
	var rows: Array[Dictionary] = []
	var planned := 0; var active := 0; var used := 0; var payable := 0
	var all_enabled := not ids.is_empty()
	for id: int in ids:
		var row := _row(id)
		if bool(row.planned): planned += 1
		if bool(row.active): active += 1
		if bool(row.used): used += 1
		if not bool(row.planned) and not bool(row.active): all_enabled = false
		rows.append(row)
	var action := "stop" if all_enabled else ("prepare" if _phase() == "day" else "enable")
	var available := false
	var first_reason := "请先选择存活采运工队" if ids.is_empty() else ""
	var budget := int(_property("scrap"))
	for row: Dictionary in rows:
		var reason := ""
		if not _command_allowed(): reason = "夜采已结束" if _retired else "暂停或选卡时不能修改夜采"
		elif action != "stop" and not bool(row.active) and not bool(row.planned):
			reason = "本队当夜已装配 · 停止后不可重启" if _phase() == "night" and bool(row.used) else _target_reason(int(row.id))
			if reason.is_empty() and _phase() == "night":
				reason = _technology_reason()
				if reason.is_empty() and budget < COST: reason = "夜采装配需要20零件"
				if reason.is_empty(): budget -= COST; payable += 1
		row.available = reason.is_empty()
		row.reason = reason if not reason.is_empty() else String(row.reason)
		available = available or bool(row.available)
		if first_reason.is_empty() and not reason.is_empty(): first_reason = reason
	var title := "取消准备 / 停止夜采" if action == "stop" else ("准备夜采 · 日落每队20零件" if action == "prepare" else "装配夜采 · 每队20零件")
	return {"count": ids.size(), "cost": COST, "total_cost": (ids.size() - active - planned) * COST if action != "stop" else 0,
		"payable_count": payable, "planned_count": planned, "active_count": active, "used_count": used,
		"all_enabled": all_enabled, "available": available, "action": action, "reason": title if available else first_reason, "teams": rows}

func prepare_selected() -> Dictionary:
	if not _command_allowed() or _phase() != "day": return _result(0, 0, "prepare", [{"id": -1, "reason": "只能在白昼准备夜采"}])
	var count := 0
	var rejected: Array[Dictionary] = []
	for id: int in _selected():
		var old: Dictionary = _entries.get(id, {})
		if bool(old.get("planned", false)) and _binding_reason(old).is_empty(): count += 1; continue
		var entry := _bind(id)
		if entry.is_empty(): rejected.append({"id": id, "reason": _target_reason(id)}); continue
		entry.planned = true; entry.reason = "已准备 · 日落检查科技和20零件"
		_entries[id] = entry; count += 1
	return _result(count, 0, "prepare", rejected)

func toggle_selected() -> Dictionary:
	if not _command_allowed(): return _result(0, 0, "enable", [{"id": -1, "reason": "夜采已结束" if _retired else "暂停或选卡时不能修改夜采"}])
	if bool(selection().all_enabled): return stop_selected()
	if _phase() == "day": return prepare_selected()
	on_night()
	var count := 0; var charged := 0
	var rejected: Array[Dictionary] = []
	for id: int in _selected():
		if can_haul(id): count += 1; continue
		if _used.has(id):
			rejected.append({"id": id, "reason": "本队当夜已装配 · 停止后不可重启"})
			continue
		var entry := _bind(id)
		if entry.is_empty(): rejected.append({"id": id, "reason": _target_reason(id)}); continue
		var result := _activate(entry)
		if bool(result.ok):
			count += 1
			if bool(result.charged): charged += 1
		else: rejected.append({"id": id, "reason": String(result.reason)})
	return _result(count, charged, "enable", rejected)

func stop_selected() -> Dictionary:
	if not _command_allowed(): return _result(0, 0, "stop", [{"id": -1, "reason": "暂停或选卡时不能修改夜采"}])
	var count := 0
	for id: int in _selected():
		var entry: Dictionary = _entries.get(id, {})
		if not bool(entry.get("active", false)) and not bool(entry.get("planned", false)): continue
		cancel(id, "已取消准备" if _phase() == "day" else "夜采停止 · 当夜不可重启，已付款不退款")
		count += 1
	return _result(count, 0, "stop", [])

func _result(count: int, charged: int, action: String, rejected: Array[Dictionary]) -> Dictionary:
	var reason := "请选择存活采运工队"
	if count > 0: reason = "%d队%s" % [count, "准备夜采 · 日落检查20零件" if action == "prepare" else ("停止夜采 · 载货保留" if action == "stop" else "夜采装配生效")]
	elif not rejected.is_empty(): reason = String(rejected[0].reason)
	if count > 0 and not rejected.is_empty(): reason += " · 部分工队未启用"
	return {"ok": count > 0, "count": count, "charged_count": charged, "spent": charged * COST,
		"action": action, "reason": reason, "rejected": rejected}

func _refresh_visuals() -> void:
	var keep: Dictionary = {}
	for value: Variant in _entries.keys():
		var id := int(value)
		if not _permit_current(id): continue
		for member: Variant in _squad(id).get("members", []):
			if not bool(logistics.call("_living", member)): continue
			var token: int = member.get_instance_id()
			keep[token] = true
			member.set_meta("night_haul_active", true)
			if _markers.has(token): continue
			var marker := Node3D.new(); marker.name = "NightHaulPermit"
			(member as BattleUnit).visual.add_child(marker)
			var pole := BattleVisuals.box(marker, Vector3(.30, 1.46, .31), Vector3(.035, .54, .035), BattleVisuals.material(Color("758b81")))
			pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := BattleVisuals.material(Color("f2c879"), .45)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var lamp := BattleVisuals.box(marker, Vector3(.30, 1.74, .31), Vector3(.14, .16, .14), mat)
			lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_markers[token] = {"node": weakref(marker), "member": weakref(member)}
	for value: Variant in _markers.keys():
		if not keep.has(value): _remove_marker(int(value))

func _remove_marker(token: int) -> void:
	var row: Dictionary = _markers.get(token, {})
	var member_ref: Variant = row.get("member")
	var member: Variant = member_ref.get_ref() if member_ref is WeakRef else null
	if is_instance_valid(member): member.set_meta("night_haul_active", false)
	var reference: Variant = row.get("node")
	var marker: Variant = reference.get_ref() if reference is WeakRef else null
	if is_instance_valid(marker):
		if marker.get_parent() != null: marker.get_parent().remove_child(marker)
		marker.queue_free()
	_markers.erase(token)

func _clear_visuals() -> void:
	for value: Variant in _markers.keys(): _remove_marker(int(value))
