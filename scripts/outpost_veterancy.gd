extends RefCounted
## Run-local experience belongs to the original member, group and slot.
## Confirmed enemy HP contributions are paid only by a genuine death receipt.
const Catalog := preload("res://scripts/outpost_catalog.gd")
const COMBAT_KINDS := ["shield", "ranged", "engineer", "ballista", "artillery", "hunter", "flamer", "netter"]
const VETERAN_XP := 300.0
const ELITE_XP := 900.0
const XP_CAP := ELITE_XP

var game: Node3D
var roster: Node3D
var _members: Dictionary = {}
var _enemies: Dictionary = {}
var _forgotten: Dictionary = {}
var _run_epoch := 0
var _has_roster := false
var _has_enemies := false
var _has_quitting := false
var _has_restart_pending := false
var _settled_enemies := 0

func setup(controller: Node3D, squad_roster: Node3D) -> void:
	clear()
	game = controller
	roster = squad_roster
	if not is_instance_valid(game): return
	for property: Dictionary in game.get_property_list():
		if String(property.name) == "squads": _has_roster = true
		if String(property.name) == "enemies": _has_enemies = true
		if String(property.name) == "quitting": _has_quitting = true
		if String(property.name) == "restart_pending": _has_restart_pending = true

func _roster_current() -> bool:
	return is_instance_valid(game) and not game.is_queued_for_deletion() \
		and is_instance_valid(roster) and not roster.is_queued_for_deletion() \
		and (not _has_roster or game.get("squads") == roster)

func _active() -> bool:
	return _roster_current() and String(game.get("phase")) in ["day", "night"] \
		and (not _has_quitting or not bool(game.get("quitting"))) \
		and (not _has_restart_pending or not bool(game.get("restart_pending")))

func _living_member(value: Variant) -> bool:
	return is_instance_valid(value) and value is BattleUnit and not value.is_queued_for_deletion() \
		and value.alive and value.hp > 0.0 and value.kind == "minion" and value.team == 0

func _group_owned(group: Dictionary) -> bool:
	if not _roster_current(): return false
	var groups: Array = roster.get("squads")
	var id := int(group.get("id", -1))
	return id >= 0 and id < groups.size() and is_same(groups[id], group)

func _member_owned(state: Dictionary) -> bool:
	if state.is_empty() or int(state.get("epoch", -1)) != _run_epoch: return false
	var value: Variant = (state.unit as WeakRef).get_ref()
	if not _living_member(value): return false
	var token: int = value.get_instance_id()
	if not _members.has(token) or not is_same(_members[token], state): return false
	var group: Dictionary = state.group
	if not _group_owned(group) or String(group.get("kind", "")) != String(state.kind): return false
	var members: Array = group.get("members", [])
	var slot := int(state.slot)
	return slot >= 0 and slot < members.size() and members[slot] == value \
		and bool(value.get_meta("outpost_squad", false)) and String(value.get_meta("squad_kind", "")) == String(state.kind)

func register_member(source: BattleUnit, group: Dictionary, slot: int) -> void:
	if not _living_member(source) or not _group_owned(group): return
	var kind := String(group.get("kind", ""))
	var members: Array = group.get("members", [])
	if kind not in COMBAT_KINDS or slot < 0 or slot >= members.size() or members[slot] != source: return
	if not bool(source.get_meta("outpost_squad", false)) or String(source.get_meta("squad_kind", "")) != kind: return
	var token := source.get_instance_id()
	# Registering again cannot reset experience, change its ownership identity
	# or turn a previous multiplier into the next member's base statistics.
	if _members.has(token) or _forgotten.has(token): return
	if not is_finite(source.damage) or source.damage < 0.0: return
	var base_hp := float(Catalog.troop(kind).get("hp", 0.0))
	if not is_finite(base_hp) or base_hp <= 0.0: return
	_members[token] = {"unit": weakref(source), "group": group, "slot": slot,
		"kind": kind, "epoch": _run_epoch, "xp": 0.0, "rank": 0,
		"base_damage": source.damage, "base_max_hp": base_hp}

func forget_member(source: BattleUnit) -> void:
	if not is_instance_valid(source): return
	var token := source.get_instance_id()
	if _members.has(token):
		_members.erase(token)
		_forgotten[token] = weakref(source)

func _enemy_owned(value: Variant) -> bool:
	return _roster_current() and _has_enemies and is_instance_valid(value) and value is BattleUnit \
		and not value.is_queued_for_deletion() and value.kind == "monster" and value.team == 2 \
		and not bool(value.get_meta("summoned_reinforcement", false)) and value in game.get("enemies")

func observe_enemy(actor: BattleUnit) -> void:
	if not _active() or not _enemy_owned(actor) or not actor.alive or actor.hp <= 0.0: return
	var token := actor.get_instance_id()
	if _enemies.has(token): return
	if not is_finite(actor.hp) or not is_finite(actor.max_hp) or actor.max_hp <= 0.0: return
	var budget := minf(actor.hp, actor.max_hp)
	if budget <= 0.0: return
	var before_damage := Callable(self, "_on_enemy_damaged").bind(_run_epoch, token)
	var confirmed_damage := Callable(self, "_on_enemy_damage_confirmed").bind(_run_epoch, token)
	_enemies[token] = {"unit": weakref(actor), "epoch": _run_epoch, "budget": budget,
		"used": 0.0, "confirmed_hp": 0.0, "contributions": {}, "transactions": [],
		"lethal_confirmed": false, "settled": false,
		"before_damage": before_damage, "confirmed_damage": confirmed_damage}
	actor.damaged.connect(before_damage)
	actor.damage_confirmed.connect(confirmed_damage)

func _disconnect_enemy(state: Dictionary) -> void:
	var value: Variant = (state.unit as WeakRef).get_ref()
	if not is_instance_valid(value) or not value is BattleUnit: return
	if value.damaged.is_connected(state.before_damage): value.damaged.disconnect(state.before_damage)
	if value.damage_confirmed.is_connected(state.confirmed_damage): value.damage_confirmed.disconnect(state.confirmed_damage)

func observe_enemies() -> void:
	if not _active() or not _has_enemies: return
	for token: Variant in _enemies.keys():
		var state: Dictionary = _enemies[token]
		var value: Variant = (state.unit as WeakRef).get_ref()
		if not is_instance_valid(value):
			_enemies.erase(token)
		elif not _enemy_owned(value):
			# Removing an actor never pays its pending contribution. Keep this
			# identity retired even if somebody later reinserts the same actor.
			_disconnect_enemy(state)
			state.settled = true
			(state.contributions as Dictionary).clear()
			(state.transactions as Array).clear()
		else:
			# hurt is synchronous. An unconfirmed zero-damage preparation from
			# an earlier frame is not permission for a later synthetic receipt.
			(state.transactions as Array).clear()
	for value: Variant in game.get("enemies"):
		if not _enemy_owned(value) or not value.alive or value.hp <= 0.0: continue
		observe_enemy(value as BattleUnit)

func _enemy_state(actor: Variant, generation: int, token: int) -> Dictionary:
	if generation != _run_epoch or not _active() or not _enemy_owned(actor): return {}
	var state: Dictionary = _enemies.get(token, {})
	if state.is_empty() or bool(state.settled) or int(state.epoch) != generation \
		or (state.unit as WeakRef).get_ref() != actor or actor.get_instance_id() != token: return {}
	return state

func _on_enemy_damaged(actor: BattleUnit, source: Variant, generation: int, token: int) -> void:
	var state := _enemy_state(actor, generation, token)
	if state.is_empty() or not actor.alive or not is_finite(actor.hp) or actor.hp <= 0.0: return
	(state.transactions as Array).append({"source": weakref(source) if is_instance_valid(source) else null,
		"source_token": source.get_instance_id() if is_instance_valid(source) else -1,
		"hp_before": actor.hp, "confirmed_before": float(state.confirmed_hp)})

func _on_enemy_damage_confirmed(actor: BattleUnit, source: Variant, hp_loss: float, _shield_loss: float,
		generation: int, token: int) -> void:
	var state := _enemy_state(actor, generation, token)
	if state.is_empty() or not actor.alive or not is_finite(actor.hp) or not is_finite(hp_loss) or hp_loss < 0.0: return
	var transactions: Array = state.transactions
	if transactions.is_empty(): return
	var source_token: int = source.get_instance_id() if is_instance_valid(source) else -1
	# Other synchronous hurt callbacks may have completed between this
	# preparation and receipt. Zero-loss nested hurts have no receipt at all;
	# skip their unmatched preparations instead of hiding the real outer hit.
	var matching := -1
	for index in range(transactions.size() - 1, -1, -1):
		var transaction: Dictionary = transactions[index]
		if int(transaction.source_token) != source_token: continue
		if transaction.source is WeakRef and (transaction.source as WeakRef).get_ref() != source: continue
		var actual_loss := maxf(0.0, float(transaction.hp_before) - actor.hp
			- (float(state.confirmed_hp) - float(transaction.confirmed_before)))
		if is_equal_approx(actual_loss, hp_loss):
			matching = index
			break
	if matching < 0: return
	# Confirming an outer hurt also closes the nested zero-loss calls above it.
	# Older outer preparations remain available for their own real receipts.
	transactions.resize(matching)
	if hp_loss <= 0.0: return # Shields and zero loss provide no experience.
	state.confirmed_hp = float(state.confirmed_hp) + hp_loss
	if actor.hp <= 0.0: state.lethal_confirmed = true
	var contribution := minf(hp_loss, maxf(0.0, float(state.budget) - float(state.used)))
	state.used = minf(float(state.budget), float(state.used) + contribution)
	if contribution <= 0.0 or not _living_member(source): return
	var member: Dictionary = _members.get(source.get_instance_id(), {})
	if not _member_owned(member): return
	var shares: Dictionary = state.contributions
	var member_token: int = source.get_instance_id()
	var share: Dictionary = shares.get(member_token, {})
	if share.is_empty():
		shares[member_token] = {"member": member, "hp": contribution}
	elif is_same(share.member, member):
		share.hp = float(share.hp) + contribution

func _rank(experience: float) -> int:
	return 2 if experience >= ELITE_XP else (1 if experience >= VETERAN_XP else 0)

func _multiplier(rank: int) -> float:
	return [1.0, 1.1, 1.2][clampi(rank, 0, 2)]

func _apply_rank(member: Dictionary, rank: int) -> void:
	if not _member_owned(member): return
	var source: BattleUnit = (member.unit as WeakRef).get_ref() as BattleUnit
	var multiplier := _multiplier(rank)
	var current_hp := source.hp
	source.damage = float(member.base_damage) * multiplier
	source.max_hp = float(member.base_max_hp) * float(roster.get("health_multiplier")) * multiplier
	# Promotion increases capacity only; it cannot provide free treatment.
	source.hp = minf(current_hp, source.max_hp)
	member.rank = rank

func on_enemy_defeated(actor: BattleUnit) -> void:
	if not _active() or not _enemy_owned(actor) or actor.alive or not is_finite(actor.hp) or actor.hp != 0.0: return
	var token := actor.get_instance_id()
	var state := _enemy_state(actor, _run_epoch, token)
	if state.is_empty() or not bool(state.lethal_confirmed): return
	var generation := _run_epoch
	state.settled = true # Retire before any member can receive a promotion.
	_disconnect_enemy(state)
	_settled_enemies += 1
	var shares: Dictionary = state.contributions
	for share: Dictionary in shares.values():
		if generation != _run_epoch or not _active(): return
		var member: Dictionary = share.member
		if not _member_owned(member): continue
		member.xp = minf(XP_CAP, float(member.xp) + float(share.hp))
		var rank := _rank(float(member.xp))
		if rank != int(member.rank): _apply_rank(member, rank)
	shares.clear()
	(state.transactions as Array).clear()

func member_snapshot(actor: Variant) -> Dictionary:
	if not is_instance_valid(actor) or not actor is BattleUnit: return {}
	var member: Dictionary = _members.get(actor.get_instance_id(), {})
	if not _member_owned(member): return {}
	var rank := int(member.rank)
	var threshold := VETERAN_XP if rank == 0 else ELITE_XP
	return {"source_token": actor.get_instance_id(), "squad_id": int(member.group.id),
		"slot": int(member.slot), "kind": String(member.kind), "xp": float(member.xp),
		"rank": rank, "rank_label": ["新兵", "老兵", "精锐"][rank],
		"damage_multiplier": _multiplier(rank), "health_multiplier": _multiplier(rank),
		"next_threshold": threshold, "xp_to_next": maxf(0.0, threshold - float(member.xp)),
		"base_damage": float(member.base_damage), "base_max_hp": float(member.base_max_hp)}

func snapshot() -> Dictionary:
	var rows: Array[Dictionary] = []
	var enemy_rows: Array[Dictionary] = []
	var rookies := 0
	var veterans := 0
	var elite := 0
	var experience := 0.0
	for member: Dictionary in _members.values():
		var value: Variant = (member.unit as WeakRef).get_ref()
		var row := member_snapshot(value)
		if row.is_empty(): continue
		rows.append(row)
		experience += float(row.xp)
		if int(row.rank) == 0: rookies += 1
		if int(row.rank) >= 1: veterans += 1
		if int(row.rank) == 2: elite += 1
	for token: Variant in _enemies.keys():
		var state: Dictionary = _enemies[token]
		var value: Variant = (state.unit as WeakRef).get_ref()
		if not _enemy_owned(value) or bool(state.settled): continue
		var contribution := 0.0
		for share: Dictionary in (state.contributions as Dictionary).values(): contribution += float(share.hp)
		enemy_rows.append({"enemy_token": int(token), "budget": float(state.budget),
			"used": float(state.used), "contribution_hp": contribution,
			"lethal_confirmed": bool(state.lethal_confirmed)})
	return {"members": rows, "alive": rows.size(), "rookies": rookies, "veterans": veterans,
		"elite": elite, "xp_total": experience, "pending_enemies": enemy_rows.size(),
		"enemies": enemy_rows, "settled_enemies": _settled_enemies}

func clear() -> void:
	for member: Dictionary in _members.values():
		if _member_owned(member): _apply_rank(member, 0)
	_run_epoch += 1
	for state: Dictionary in _enemies.values(): _disconnect_enemy(state)
	_members.clear()
	_enemies.clear()
	_forgotten.clear()
	_settled_enemies = 0
	_has_roster = false
	_has_enemies = false
	_has_quitting = false
	_has_restart_pending = false
	game = null
	roster = null
