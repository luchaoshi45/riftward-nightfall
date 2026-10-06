class_name SalvageDraw
extends RefCounted
## An optional, run-local draw against the existing parts wallet.
const RunSessionScript = preload("res://scripts/run_session.gd")
const COST := 30
const DAILY_LIMIT := 2
const HOME_RADIUS := 6.0
const MIN_HOME_HEIGHT: float = Vector3(0, 4.8, 0).y
const STREAM_SALT := 0x5a17c9
const DAY_SALT := 104729
const RESULTS := [
	{"probability": 60, "payout": 10, "net": -20},
	{"probability": 30, "payout": 40, "net": 10},
	{"probability": 10, "payout": 120, "net": 90},
]

var _game: Node3D
var _run_seed := 0
var _day_id := 0
var _used := 0
var _day_open := false
var _last: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _settling := false
var _epoch := 0

func setup(owner_game: Node3D, run_seed: int) -> void:
	clear()
	_game = owner_game
	_run_seed = run_seed

func begin_day() -> void:
	if not is_instance_valid(_game) or _game.is_queued_for_deletion(): return
	if _game.quitting or _game.restart_pending or _game.phase != "day": return
	var time_left: float = float(_game.phase_time)
	if not is_finite(time_left) or time_left <= 0.0: return
	var day_id: int = int(_game.day_number)
	if day_id < 2 or day_id <= _day_id: return
	var exploration: Variant = _game.exploration
	if not is_instance_valid(exploration) or int(exploration.route_day) != day_id: return
	_day_id = day_id
	_used = 0
	_day_open = true
	# The local salt separates this stream without changing the four old streams.
	_rng.seed = RunSessionScript.stream_seed(_run_seed ^ STREAM_SALT ^ (_day_id * DAY_SALT), "salvage_draw")

func on_night() -> void:
	_day_open = false

func clear() -> void:
	_epoch += 1
	_game = null
	_run_seed = 0
	_day_id = 0
	_used = 0
	_day_open = false
	_last.clear()
	_rng.seed = 1
	_settling = false

func snapshot() -> Dictionary:
	var reason: String = _availability_reason()
	return {
		"available": reason.is_empty(),
		"reason": reason,
		"day_id": _day_id,
		"used": _used,
		"remaining": maxi(0, DAILY_LIMIT - _used) if _day_open else 0,
		"cost": COST,
		"last": _last.duplicate(true),
		"results": RESULTS.duplicate(true),
		"rng_state": _rng.state,
	}

func draw() -> Dictionary:
	var reason: String = _availability_reason()
	if not reason.is_empty(): return {"ok": false, "reason": reason}
	var owner_game: Node3D = _game
	var epoch: int = _epoch
	_settling = true
	var wallet_before: int = int(owner_game.scrap)
	var roll: int = _rng.randi_range(0, 99)
	var payout: int = 10
	if roll >= 90:
		payout = 120
	elif roll >= 60:
		payout = 40
	var wallet_after: int = wallet_before - COST + payout
	_used += 1
	var result: Dictionary = {
		"ok": true,
		"reason": "",
		"day_id": _day_id,
		"draw_number": _used,
		"cost": COST,
		"roll": roll,
		"payout": payout,
		"net": payout - COST,
		"wallet_before": wallet_before,
		"wallet_after": wallet_after,
	}
	# Commit the quota and record before the single wallet assignment. There are
	# no signals, nodes or yields in settlement; repeat calls see the new quota.
	_last = result.duplicate(true)
	owner_game.scrap = wallet_after
	if _epoch == epoch: _settling = false
	return result

func _availability_reason() -> String:
	if not is_instance_valid(_game) or _game.is_queued_for_deletion(): return "closed"
	if _game.quitting or _game.restart_pending: return "closed"
	if _settling: return "settling"
	var time_left: float = float(_game.phase_time)
	if _game.phase != "day" or not is_finite(time_left) or time_left <= 0.0: return "not_day"
	var day_id: int = int(_game.day_number)
	if not _day_open or day_id < 2 or day_id != _day_id: return "day_unavailable"
	var actor: Variant = _game.hero
	if not is_instance_valid(actor) or not actor is Node3D: return "hero_unavailable"
	if actor.is_queued_for_deletion() or not actor.alive or not (float(actor.hp) > 0.0): return "hero_unavailable"
	if not (float(_game.beacon_hp) > 0.0): return "beacon_unavailable"
	if _used >= DAILY_LIMIT: return "daily_limit"
	var exploration: Variant = _game.exploration
	if not is_instance_valid(exploration): return "exploration_required"
	if int(exploration.route_day) != day_id or int(exploration.day_discoveries) < 1: return "exploration_required"
	var actor_position: Vector3 = actor.position
	if not actor_position.is_finite() or actor_position.y <= MIN_HOME_HEIGHT: return "return_home"
	if Vector2(actor_position.x, actor_position.z).length_squared() > HOME_RADIUS * HOME_RADIUS: return "return_home"
	if int(_game.scrap) < COST: return "insufficient_scrap"
	return ""
