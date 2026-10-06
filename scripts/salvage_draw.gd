class_name SalvageDraw
extends RefCounted
## An optional, run-local draw against the existing parts wallet.
const RunSessionScript = preload("res://scripts/run_session.gd")
const COST := 30
const SAFE_MODE := "safe"
const JACKPOT_MODE := "jackpot"
const JACKPOT_STAKE := 60
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
const JACKPOT_RESULTS := [
	{"probability": 70, "payout": 0, "net": -60},
	{"probability": 25, "payout": 120, "net": 60},
	{"probability": 5, "payout": 600, "net": 540},
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
## Public risk controls.  `safe` is the legacy path; `jackpot` is available
## only for the second draw of a daylight and never changes the RNG stream.
var modes: Array = [SAFE_MODE, JACKPOT_MODE]
var selected_mode := SAFE_MODE
var stake := COST

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
	selected_mode = SAFE_MODE
	stake = COST
	# The local salt separates this stream without changing the four old streams.
	_rng.seed = RunSessionScript.stream_seed(_run_seed ^ STREAM_SALT ^ (_day_id * DAY_SALT), "salvage_draw")

func on_night() -> void:
	_day_open = false
	selected_mode = SAFE_MODE
	stake = COST

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
	selected_mode = SAFE_MODE
	stake = COST

func snapshot() -> Dictionary:
	var reason: String = _availability_reason()
	return {
		"available": reason.is_empty(),
		"reason": reason,
		"day_id": _day_id,
		"used": _used,
		"remaining": maxi(0, DAILY_LIMIT - _used) if _day_open else 0,
		"cost": mode_stake(selected_mode),
		"stake": stake,
		"modes": modes.duplicate(),
		"selected_mode": selected_mode,
		"mode_options": mode_options(),
		"results_by_mode": {
			SAFE_MODE: RESULTS.duplicate(true),
			JACKPOT_MODE: JACKPOT_RESULTS.duplicate(true),
		},
		"last": _last.duplicate(true),
		"results": mode_results(selected_mode),
		"rng_state": _rng.state,
	}

## Selects the receipt mode without consuming randomness or wallet.  A jackpot
## selection is intentionally locked until the legacy first draw is committed.
func select_mode(mode: String) -> bool:
	if not _mode_reason(mode).is_empty(): return false
	selected_mode = mode
	stake = mode_stake(mode)
	return true

func set_mode(mode: String) -> bool:
	return select_mode(mode)

func mode_reason(mode: String) -> String:
	return _mode_reason(mode)

func mode_stake(mode: String) -> int:
	return JACKPOT_STAKE if mode == JACKPOT_MODE else COST

func mode_results(mode: String) -> Array:
	return (JACKPOT_RESULTS if mode == JACKPOT_MODE else RESULTS).duplicate(true)

func mode_options() -> Array:
	return [
		{"mode": SAFE_MODE, "stake": COST, "results": RESULTS.duplicate(true)},
		{"mode": JACKPOT_MODE, "stake": JACKPOT_STAKE, "results": JACKPOT_RESULTS.duplicate(true)},
	]

## `draw()` keeps the original safe call-site contract.  New callers pass an
## explicit mode; all validation completes before the sole wallet assignment.
func draw(mode: String = SAFE_MODE) -> Dictionary:
	var requested_mode: String = selected_mode if mode.is_empty() else mode
	var reason: String = _availability_reason(requested_mode)
	if not reason.is_empty(): return {"ok": false, "reason": reason}
	var owner_game: Node3D = _game
	var epoch: int = _epoch
	_settling = true
	var wallet_before: int = int(owner_game.scrap)
	var roll: int = _rng.randi_range(0, 99)
	var payout: int = 10
	if requested_mode == JACKPOT_MODE:
		payout = 600 if roll >= 95 else (120 if roll >= 70 else 0)
	else:
		if roll >= 90:
			payout = 120
		elif roll >= 60:
			payout = 40
	var draw_stake: int = mode_stake(requested_mode)
	var wallet_after: int = wallet_before - draw_stake + payout
	_used += 1
	var result: Dictionary = {
		"ok": true,
		"reason": "",
		"mode": requested_mode,
		"day_id": _day_id,
		"draw_number": _used,
		"cost": draw_stake,
		"stake": draw_stake,
		"roll": roll,
		"payout": payout,
		"net": payout - draw_stake,
		"wallet_before": wallet_before,
		"wallet_after": wallet_after,
	}
	# Commit the quota and record before the single wallet assignment. There are
	# no signals, nodes or yields in settlement; repeat calls see the new quota.
	_last = result.duplicate(true)
	selected_mode = requested_mode
	stake = draw_stake
	owner_game.scrap = wallet_after
	if _epoch == epoch: _settling = false
	return result

func _mode_reason(mode: String) -> String:
	if not modes.has(mode): return "invalid_mode"
	if mode == JACKPOT_MODE and _used < 1: return "jackpot_requires_first"
	return ""

func _availability_reason(mode: String = selected_mode) -> String:
	var mode_error: String = _mode_reason(mode)
	if not mode_error.is_empty(): return mode_error
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
	if int(_game.scrap) < mode_stake(mode):
		return "insufficient_scrap_jackpot" if mode == JACKPOT_MODE else "insufficient_scrap"
	return ""
