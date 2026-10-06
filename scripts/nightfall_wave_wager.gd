class_name NightfallWaveWager
extends RefCounted
## One run-local ticket for a saved night-wave plan.
##
## The wager deliberately owns no game or wallet reference.  A caller passes
## the current wallet at lock time and applies the returned wallet_delta.  This
## keeps the single-resource ledger authoritative in the controller while the
## ticket retains the stake and pays a win at most once.
##
## Stable integration API:
##   setup(night, plan_signature, reward_id, count)
##   offer(night, plan_signature, reward_id, count)
##   target_options(plan), choose_target(index, day, plan)
##   risk_options(), place_risk(index, day, plan, available_scrap)
##   choose("steady" | "bold" | "reckless")
##   lock(plan_signature, reward_id, count, balance)
##   settle_wave(plan_signature, reward_id, count, defeated_count, eligible)
##   settle_loss(plan_signature, reward_id, count, reason)
##   snapshot(), plan_signature(), clear()

const STATE_IDLE := "idle"
const STATE_OFFERED := "offered"
const STATE_SELECTED := "selected"
const STATE_LOCKED := "locked"
const STATE_WON := "won"
const STATE_LOST := "lost"
const STATE_EXPIRED := "expired"

const TIERS: Array[Dictionary] = [
	{"id": "steady", "label": "稳押", "stake": 20, "reward": 50},
	{"id": "bold", "label": "加码", "stake": 40, "reward": 120},
	{"id": "reckless", "label": "梭哈", "stake": 60, "reward": 240},
]

var _state := STATE_IDLE
var _night_id := -1
var _plan_signature := ""
var _target_reward_id := -1
var _target_count := 0
var _selected_tier := ""
var _stake := 0
var _reward := 0
var _wallet_before := -1
var _wallet_after_lock := -1
var _last_result: Dictionary = {}
var _epoch := 0

## Initializes a fresh ticket. With no night arguments it only clears the
## module, which is useful for controller setup and retry paths.
func setup(night_id: int = -1, plan_signature_value: String = "", target_reward_id: int = -1, target_count: int = 0) -> bool:
	retry()
	if night_id < 0:
		return true
	return begin_night(night_id, plan_signature_value, target_reward_id, target_count)

## Starts the one-ticket offer for a night. Calling this again for the same
## night never creates a second ticket, even after a loss or expiry.
func begin_night(night_id: int, plan_signature: String, target_reward_id: int, target_count: int) -> bool:
	if night_id < 0 or plan_signature.is_empty() or target_reward_id < 0 or target_count <= 0:
		return false
	if _night_id >= 0:
		if night_id <= _night_id:
			return false
	_clear_ticket()
	_night_id = night_id
	_plan_signature = plan_signature
	_target_reward_id = target_reward_id
	_target_count = target_count
	_state = STATE_OFFERED
	return true

## Compatibility alias for callers that use offer terminology.
func offer(night_id: int, plan_signature: String, target_reward_id: int, target_count: int) -> bool:
	return begin_night(night_id, plan_signature, target_reward_id, target_count)

func tier_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tier: Dictionary in TIERS:
		result.append(tier.duplicate(true))
	return result

func options() -> Array[Dictionary]:
	return tier_options()

func risk_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in TIERS.size():
		var tier: Dictionary = TIERS[index]
		result.append({
			"index": index,
			"id": String(tier.id),
			"label": String(tier.label),
			"stake": int(tier.stake),
			"gross": int(tier.reward),
			"reward": int(tier.reward),
			"net": int(tier.reward) - int(tier.stake),
		})
	return result

## Normalizes either an Array of wave rows, a Dictionary containing `waves` or
## `targets`, or one target Dictionary.  The original row is never mutated.
func target_options(plan: Variant) -> Array[Dictionary]:
	var rows: Array = []
	var plan_signature_value := ""
	if plan is Array:
		rows = plan
	elif plan is Dictionary:
		var plan_dict: Dictionary = plan
		plan_signature_value = String(plan_dict.get("plan_signature", plan_dict.get("signature", "")))
		var nested: Variant = plan_dict.get("waves", plan_dict.get("targets", []))
		if nested is Array:
			rows = nested
		elif plan_dict.has("reward_id") or plan_dict.has("target_reward_id"):
			rows = [plan_dict]
	var result: Array[Dictionary] = []
	for row_index in rows.size():
		var row_value: Variant = rows[row_index]
		if not row_value is Dictionary:
			continue
		var row: Dictionary = row_value
		var reward_id := int(row.get("target_reward_id", row.get("reward_id", row.get("id", -1))))
		var target_count := int(row.get("target_count", row.get("count", row.get("enemy_count", 0))))
		if reward_id < 0 or target_count <= 0:
			continue
		var row_signature := String(row.get("plan_signature", row.get("signature", plan_signature_value)))
		if row_signature.is_empty():
			row_signature = "night-plan:%d:%d:%d" % [row_index, reward_id, target_count]
		result.append({
			"index": row_index,
			"day": int(row.get("day", row.get("night", -1))),
			"plan_signature": row_signature,
			"target_reward_id": reward_id,
			"reward_id": reward_id,
			"target_count": target_count,
			"count": target_count,
			"title": String(row.get("title", row.get("name", ""))),
		})
	return result

## Binds only a target. It intentionally does not choose or charge a risk tier.
func choose_target(index: int, day: int, plan: Variant) -> bool:
	var targets := target_options(plan)
	if index < 0 or index >= targets.size():
		return false
	var target: Dictionary = targets[index]
	var target_day := int(target.get("day", -1))
	if target_day >= 0 and target_day != day:
		return false
	return offer(day, String(target.plan_signature), int(target.target_reward_id), int(target.target_count))

## Quotes risk_options()[index] against the currently bound target.  The wallet
## remains untouched; `remaining` is the caller's available balance after the
## quote.  Call choose_target first when `plan` contains multiple targets.
func place_risk(index: int, day: int, plan: Variant, available_scrap: int) -> Dictionary:
	var result := {"ok": false, "state": _state, "reason": "", "index": index,
		"day": day, "stake": 0, "gross": 0, "reward": 0, "remaining": available_scrap,
		"cost": 0, "quoted_delta": 0, "wallet_delta": 0, "plan_signature": _plan_signature}
	if _state not in [STATE_OFFERED, STATE_SELECTED]:
		result.reason = "not_offered"
		return result
	var targets := target_options(plan)
	var target: Dictionary = {}
	for candidate: Dictionary in targets:
		if _matches_target(String(candidate.plan_signature), int(candidate.target_reward_id), int(candidate.target_count)):
			target = candidate
			break
	if target.is_empty() and targets.size() == 1 and _state == STATE_OFFERED:
		# A single-target dictionary is convenient for a compact HUD quote; the
		# target still has to be bound explicitly through choose_target first.
		target = targets[0]
	if target.is_empty():
		return _expire("plan_changed")
	if int(target.get("day", -1)) >= 0 and int(target.day) != day:
		return _expire("wrong_day")
	if not _matches_target(String(target.plan_signature), int(target.target_reward_id), int(target.target_count)):
		return _expire("plan_changed")
	var risk_index := int(result.index)
	if risk_index < 0 or risk_index >= TIERS.size():
		result.reason = "invalid_risk"
		return result
	var tier: Dictionary = TIERS[risk_index]
	var stake := int(tier.stake)
	var gross := int(tier.reward)
	result.stake = stake
	result.gross = gross
	result.reward = gross
	if available_scrap < stake:
		result.reason = "insufficient_scrap"
		return result
	select_tier(String(tier.id))
	result.ok = true
	result.state = STATE_SELECTED
	result.reason = ""
	result.remaining = available_scrap - stake
	result.cost = stake
	result.quoted_delta = -stake
	# A quote is not a ledger mutation. The controller applies the actual
	# wallet deduction returned by lock(), once the player confirms.
	result.wallet_delta = 0
	result.net = gross - stake
	result.tier_id = String(tier.id)
	return result

func select_tier(tier_id: String) -> bool:
	if _state not in [STATE_OFFERED, STATE_SELECTED]:
		return false
	var tier := _tier(tier_id)
	if tier.is_empty():
		return false
	_selected_tier = tier_id
	_stake = int(tier.stake)
	_reward = int(tier.reward)
	_state = STATE_SELECTED
	return true

func choose_tier(tier_id: String) -> bool:
	return select_tier(tier_id)

func choose(tier_id: String) -> bool:
	return select_tier(tier_id)

## Locks a selected ticket against the exact plan identity and deducts only the
## stake.  The caller applies wallet_delta; no hidden wallet reference exists.
func lock(plan_signature: String, target_reward_id: int, target_count: int, balance: int) -> Dictionary:
	if _state != STATE_SELECTED:
		return _failure("not_selected")
	if not _matches_target(plan_signature, target_reward_id, target_count):
		return _expire("plan_changed")
	if balance < _stake:
		return _failure("insufficient_balance")
	_wallet_before = balance
	_wallet_after_lock = balance - _stake
	_state = STATE_LOCKED
	_last_result = {
		"ok": true,
		"state": STATE_LOCKED,
		"reason": "",
		"night_id": _night_id,
		"plan_signature": _plan_signature,
		"target_reward_id": _target_reward_id,
		"target_count": _target_count,
		"tier_id": _selected_tier,
		"stake": _stake,
		"reward": _reward,
		"wallet_before": _wallet_before,
		"wallet_after": _wallet_after_lock,
		"wallet_delta": -_stake,
		"net": -_stake,
	}
	return _last_result.duplicate(true)

## Alternate argument order for a controller that already has the wallet value.
func lock_with_balance(balance: int, plan_signature: String, target_reward_id: int, target_count: int) -> Dictionary:
	return lock(plan_signature, target_reward_id, target_count, balance)

func lock_ticket(plan_signature: String, target_reward_id: int, target_count: int, balance: int) -> Dictionary:
	return lock(plan_signature, target_reward_id, target_count, balance)

## Resolves a locked ticket once. A valid exact target with all units defeated
## wins; any other eligible result loses the paid stake. A changed plan or
## target expires the ticket and can never pay a later result.
func settle(plan_signature: String, target_reward_id: int, target_count: int, defeated_count: int, eligible: bool = true) -> Dictionary:
	if _state != STATE_LOCKED:
		return _repeat_result("already_settled" if _state in [STATE_WON, STATE_LOST, STATE_EXPIRED] else "not_locked")
	if not _matches_target(plan_signature, target_reward_id, target_count):
		return _expire("plan_changed")
	if not eligible:
		return _lose("ineligible")
	if defeated_count != _target_count:
		return _lose("target_not_cleared")
	_state = STATE_WON
	_last_result = _settled_result(STATE_WON, "cleared", _reward, _reward)
	return _last_result.duplicate(true)

func resolve(plan_signature: String, target_reward_id: int, target_count: int, defeated_count: int, eligible: bool = true) -> Dictionary:
	return settle(plan_signature, target_reward_id, target_count, defeated_count, eligible)

func settle_ticket(plan_signature: String, target_reward_id: int, target_count: int, defeated_count: int, eligible: bool = true) -> Dictionary:
	return settle(plan_signature, target_reward_id, target_count, defeated_count, eligible)

func settle_wave(plan_signature: String, target_reward_id: int, target_count: int, defeated_count: int, eligible: bool = true) -> Dictionary:
	return settle(plan_signature, target_reward_id, target_count, defeated_count, eligible)

## Forces a loss for a matching target. This is the explicit failure path for
## an uncleared wave; the already-paid stake remains forfeited.
func settle_loss(plan_signature: String, target_reward_id: int, target_count: int, reason: String = "failed") -> Dictionary:
	if _state != STATE_LOCKED:
		return _repeat_result("already_settled" if _state in [STATE_WON, STATE_LOST, STATE_EXPIRED] else "not_locked")
	if not _matches_target(plan_signature, target_reward_id, target_count):
		return _expire("plan_changed")
	return _lose(reason)

## Invalidates an active ticket without a payout. This is used for dusk,
## restart, or a plan identity that no longer exists.
func expire(reason: String = "expired") -> Dictionary:
	if _state != STATE_LOCKED:
		return _repeat_result("already_settled" if _state in [STATE_WON, STATE_LOST, STATE_EXPIRED] else "not_locked")
	return _expire(reason)

## Retry starts a fresh run-local ticket. It intentionally clears the night so
## the same numerical night may be played again after a real game restart.
func retry() -> void:
	_clear_ticket()

func on_retry() -> void:
	retry()

func reset() -> void:
	retry()

func clear() -> void:
	retry()

func plan_signature() -> String:
	return _plan_signature

func snapshot() -> Dictionary:
	return {
		"state": _state,
		"night_id": _night_id,
		"plan_signature": _plan_signature,
		"target_reward_id": _target_reward_id,
		"target_count": _target_count,
		"selected_tier": _selected_tier,
		"stake": _stake,
		"reward": _reward,
		"wallet_before": _wallet_before,
		"wallet_after_lock": _wallet_after_lock,
		"ticket_used": _night_id >= 0,
		"locked": _state == STATE_LOCKED,
		"settled": _state in [STATE_WON, STATE_LOST, STATE_EXPIRED],
		"last_result": _last_result.duplicate(true),
		"epoch": _epoch,
	}

func _tier(tier_id: String) -> Dictionary:
	for tier: Dictionary in TIERS:
		if String(tier.id) == tier_id:
			return tier
	return {}

func _matches_target(plan_signature: String, target_reward_id: int, target_count: int) -> bool:
	return plan_signature == _plan_signature and target_reward_id == _target_reward_id and target_count == _target_count

func _failure(reason: String) -> Dictionary:
	return {
		"ok": false,
		"state": _state,
		"reason": reason,
		"stake": _stake,
		"reward": _reward,
		"wallet_delta": 0,
	}

func _expire(reason: String) -> Dictionary:
	_state = STATE_EXPIRED
	_last_result = _settled_result(STATE_EXPIRED, reason, 0, 0)
	return _last_result.duplicate(true)

func _lose(reason: String) -> Dictionary:
	_state = STATE_LOST
	_last_result = _settled_result(STATE_LOST, reason, 0, 0)
	return _last_result.duplicate(true)

func _settled_result(state: String, reason: String, payout: int, delta: int) -> Dictionary:
	return {
		"ok": state == STATE_WON,
		"state": state,
		"reason": reason,
		"night_id": _night_id,
		"plan_signature": _plan_signature,
		"target_reward_id": _target_reward_id,
		"target_count": _target_count,
		"tier_id": _selected_tier,
		"stake": _stake,
		"reward": payout,
		"payout": payout,
		"wallet_delta": delta,
		"net": -_stake + payout,
	}

func _repeat_result(reason: String) -> Dictionary:
	var result := _last_result.duplicate(true)
	if result.is_empty():
		return _failure(reason)
	result["ok"] = false
	result["reason"] = reason
	result["duplicate"] = true
	result["wallet_delta"] = 0
	return result

func _clear_ticket() -> void:
	_epoch += 1
	_state = STATE_IDLE
	_night_id = -1
	_plan_signature = ""
	_target_reward_id = -1
	_target_count = 0
	_selected_tier = ""
	_stake = 0
	_reward = 0
	_wallet_before = -1
	_wallet_after_lock = -1
	_last_result.clear()
