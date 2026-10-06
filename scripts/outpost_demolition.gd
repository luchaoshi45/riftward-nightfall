extends RefCounted
## Quotes are read-only; commit resolves the live world again instead of trusting
## a cached price or index. Removed identities remain stable and cannot rebuild.
const Grid := preload("res://scripts/construction_grid.gd")
const Catalog := preload("res://scripts/outpost_catalog.gd")

static func quote_at(game: Node3D, point: Vector3) -> Dictionary:
	var result := Grid.placement(point, "tower")
	result.merge({"valid": false, "space_valid": false, "tech_valid": true, "cost": 0,
		"kind": "tower", "title": "拆卖", "reason": "请指向城内建筑或残基 · 灯塔不能拆除",
		"refund": 0, "investment": 0, "queue_refund": 0, "pending_loss": 0, "live": false,
		"target_type": "", "target_index": -1, "cell_states": []})
	if not is_instance_valid(game) or not point.is_finite(): return result
	if game.phase not in ["day", "night"]:
		result.reason = "暂停或选卡时不能拆卖"
		return result
	# A live building takes precedence over an overlapping, traversable old ruin.
	for live_pass in [true, false]:
		for index in game.world.tower_pads.size():
			var pad: Dictionary = game.world.tower_pads[index]
			if bool(pad.get("removed", false)) or not is_instance_valid(pad.get("node")): continue
			var live := int(pad.level) > 0 and float(pad.hp) > 0.0
			if live != live_pass or not _contains(game, point, pad.position, "tower"): continue
			var investment := maxi(0, int(pad.get("paid_investment", 0))) if live else 0
			return _target(result, pad.position, "tower", "tower", index, live, investment, 0)
		for index in game.districts.plots.size():
			var plot: Dictionary = game.districts.plots[index]
			if bool(plot.get("removed", false)) or not is_instance_valid(plot.get("node")): continue
			var live := int(plot.level) > 0 and float(plot.hp) > 0.0
			if live != live_pass or not _contains(game, point, plot.position, String(plot.kind)): continue
			var quote: Dictionary = game.districts.demolition_quote(index)
			if bool(quote.ok):
				var target := _target(result, plot.position, String(plot.kind), "district", index, live,
					int(quote.investment), int(quote.queue_refund))
				if live and String(plot.kind) == "recycler" and int(plot.pending) > 0:
					target.pending_loss = int(plot.pending)
					target.reason = "实付折价50%% · 未加工%d零件作废 · 维修不退" % int(plot.pending)
				elif live and String(plot.kind) == "depot":
					target.reason = "实付折价50% · 工队保货，改找存活中转站"
				return target
	return result

static func _contains(game: Node3D, point: Vector3, center: Vector3, kind: String) -> bool:
	var half: Vector2 = game.construction.footprint(kind)
	return absf(point.y - center.y) <= 1.0 and Rect2(Vector2(center.x, center.z) - half, half * 2.0).has_point(Vector2(point.x, point.z))

static func _target(result: Dictionary, center: Vector3, kind: String, target_type: String,
	index: int, live: bool, investment: int, queue_refund: int) -> Dictionary:
	result.merge(Grid.placement(center, kind), true)
	var title := String(Catalog.building(kind).get("title", "建筑"))
	var refund := floori(float(investment) * .5)
	var reason := "实付折价50% · 维修不退" if live else "残基免费清除 · 不返还零件"
	if queue_refund > 0: reason = "未完成训练另全退%d零件 · 已出部队保留" % queue_refund
	result.merge({"valid": true, "space_valid": true, "kind": kind, "title": title,
		"target_type": target_type, "target_index": index, "live": live,
		"refund": refund, "investment": investment, "queue_refund": queue_refund,
		"reason": reason}, true)
	return result

static func sell_at(game: Node3D, point: Vector3) -> bool:
	var quote := quote_at(game, point)
	if not bool(quote.valid): return false
	var index := int(quote.target_index)
	var target_type := String(quote.target_type)
	var refund := int(quote.refund)
	var queue_refund := int(quote.queue_refund)
	if target_type == "district":
		var result: Dictionary = game.districts.demolish(index)
		if not bool(result.ok): return false
		refund = int(result.refund)
		queue_refund = int(result.queue_refund)
	else:
		var pad: Dictionary = game.world.tower_pads[index]
		# Terminate before payment/callbacks; repeat and old-index build requests
		# cannot resurrect this foundation or consume its receipt a second time.
		pad["removed"] = true
		pad["paid_investment"] = 0
		pad["free_built"] = false
		pad.level = 0
		pad.hp = 0.0
		pad.max_hp = 0.0
		pad.cooldown = 0.0
		pad.mode = "nearest"
		game.specializations.on_destroyed(pad)
		for reference: String in ["turret", "node", "damage_ring", "light"]:
			var node: Variant = pad.get(reference)
			pad[reference] = null
			if is_instance_valid(node): (node as Node).queue_free()
		game.scrap += refund
		game.refresh_construction_navigation()
	for creature: BattleUnit in game.enemies:
		if not is_instance_valid(creature): continue
		if String(creature.get_meta("attack_target_kind", "")) != target_type or int(creature.get_meta("attack_target_index", -1)) != index: continue
		creature.attack_queued = false
		creature.attack_windup = 0.0
		creature.set_meta("attack_target_kind", "")
		creature.set_meta("attack_target_index", -1)
	var message := "%s已拆除 · +%d零件" % [String(quote.title), refund]
	if queue_refund > 0: message += " · 训练全退%d" % queue_refund
	if int(quote.pending_loss) > 0: message += " · 未加工%d作废" % int(quote.pending_loss)
	game.notify(message, 3)
	return true
