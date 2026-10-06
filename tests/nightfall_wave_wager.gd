extends SceneTree
## Isolated state/ledger coverage for the one-ticket night-wave wager.
## No production controller, HUD, wallet node, or project configuration is
## changed by this test; wallet arithmetic is checked through returned deltas.

const Wager = preload("res://scripts/nightfall_wave_wager.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		return
	failures.append(message)
	push_error(message)

func state(wager: RefCounted, expected: String, message: String) -> Dictionary:
	var snapshot: Dictionary = wager.snapshot()
	check(String(snapshot.get("state", "")) == expected, message)
	return snapshot

func run() -> void:
	var wager: RefCounted = Wager.new()
	var snapshot: Dictionary = state(wager, "idle", "A new wager must start idle")
	check(int(snapshot.get("night_id", -1)) == -1, "Idle wager must not claim a night")
	check(String(wager.plan_signature()) == "", "Idle wager must expose an empty plan signature")
	check(wager.tier_options().size() == 3, "Exactly three wager tiers must be offered")
	var tiers: Array = wager.tier_options()
	check(String(tiers[0].get("id", "")) == "steady" and int(tiers[0].get("stake", -1)) == 20 and int(tiers[0].get("reward", -1)) == 50, "Steady tier must be 20 stake for 50 reward")
	check(String(tiers[1].get("id", "")) == "bold" and int(tiers[1].get("stake", -1)) == 40 and int(tiers[1].get("reward", -1)) == 120, "Bold tier must be 40 stake for 120 reward")
	check(String(tiers[2].get("id", "")) == "reckless" and int(tiers[2].get("stake", -1)) == 60 and int(tiers[2].get("reward", -1)) == 240, "Reckless tier must be 60 stake for 240 reward")
	var risks: Array = wager.risk_options()
	check(risks.size() == 3 and int(risks[2].get("index", -1)) == 2, "risk_options must expose indexed risk choices")
	check(int(risks[2].get("stake", -1)) == 60 and int(risks[2].get("gross", -1)) == 240 and int(risks[2].get("net", 0)) == 180, "risk_options must expose stake/gross/net for the high tier")
	var plan_rows: Array = [
		{"signature": "shared-plan", "day": 10, "reward_id": 100, "count": 2, "title": "南门试探"},
		{"signature": "shared-plan", "day": 10, "reward_id": 101, "count": 3, "title": "裂隙增援"},
	]
	check(wager.target_options(plan_rows).size() == 2, "target_options must normalize every valid plan row")
	check(wager.choose_target(1, 10, plan_rows), "choose_target must bind only the requested plan row")
	check(String(wager.plan_signature()) == "shared-plan" and int(wager.snapshot().get("target_reward_id", -1)) == 101 and int(wager.snapshot().get("target_count", -1)) == 3, "choose_target must bind signature/reward/count without selecting a risk")
	var quote: Dictionary = wager.place_risk(2, 10, plan_rows, 59)
	check(not bool(quote.get("ok", true)) and String(quote.get("reason", "")) == "insufficient_scrap", "place_risk must enforce the selected stake threshold")
	check(String(wager.snapshot().get("state", "")) == "offered", "A failed risk quote must leave the target offered")
	quote = wager.place_risk(2, 10, plan_rows, 70)
	check(bool(quote.get("ok", false)) and String(quote.get("state", "")) == "selected", "place_risk must enter selected without touching the wallet")
	check(int(quote.get("stake", -1)) == 60 and int(quote.get("gross", -1)) == 240 and int(quote.get("remaining", -1)) == 10 and int(quote.get("cost", -1)) == 60 and int(quote.get("quoted_delta", 0)) == -60 and int(quote.get("wallet_delta", 1)) == 0, "place_risk must return verifiable stake/gross/remaining accounting without mutating the wallet")
	check(int(wager.snapshot().get("wallet_before", -1)) == -1, "place_risk must not mutate the module wallet ledger")
	check(bool(wager.lock("shared-plan", 101, 3, 70).get("ok", false)), "A quoted risk must still require the exact bound target at lock")
	check(String(wager.settle_wave("shared-plan", 101, 3, 3, true).get("state", "")) == "won", "A quoted high-risk target must settle through the normal win path")
	wager.clear()

	# Invalid offers never consume the one-ticket slot.
	check(not wager.offer(-1, "plan-invalid", 3, 2), "Negative night must be rejected")
	check(not wager.offer(1, "", 3, 2), "Empty plan signature must be rejected")
	check(not wager.offer(1, "plan-invalid", -1, 2), "Negative reward id must be rejected")
	check(not wager.offer(1, "plan-invalid", 3, 0), "Non-positive target count must be rejected")
	check(String(wager.snapshot().get("state", "")) == "idle", "Invalid offers must leave the wager idle")

	# Selection and one-ticket-per-night boundary.
	check(wager.setup(2, "plan-A", 17, 4), "setup must open a valid night ticket")
	snapshot = state(wager, "offered", "A valid setup must enter offered state")
	check(int(snapshot.get("night_id", -1)) == 2 and String(wager.plan_signature()) == "plan-A", "Offer must bind night and plan signature")
	check(int(snapshot.get("target_reward_id", -1)) == 17 and int(snapshot.get("target_count", -1)) == 4, "Offer must bind reward id and target count")
	check(not wager.offer(2, "plan-A-replaced", 17, 4), "The same night cannot open a second ticket")
	check(not wager.offer(1, "old-night", 17, 4), "An older night cannot replace the active ticket")
	check(not wager.choose("unknown"), "Unknown tier must be rejected")
	check(wager.choose("steady"), "A valid tier must be selectable")
	snapshot = state(wager, "selected", "Tier selection must enter selected state")
	check(String(snapshot.get("selected_tier", "")) == "steady" and int(snapshot.get("stake", -1)) == 20 and int(snapshot.get("reward", -1)) == 50, "Steady selection must expose its stake and reward")
	check(wager.choose("bold"), "A selected ticket may change tier before lock")
	snapshot = state(wager, "selected", "Changing a pre-lock tier must stay selected")
	check(String(snapshot.get("selected_tier", "")) == "bold" and int(snapshot.get("stake", -1)) == 40 and int(snapshot.get("reward", -1)) == 120, "Bold selection must replace the pre-lock quote")

	# Balance threshold and immutable lock.
	var result: Dictionary = wager.lock("plan-A", 17, 4, 39)
	check(not bool(result.get("ok", true)) and String(result.get("reason", "")) == "insufficient_balance", "Balance below the selected stake must be rejected")
	check(String(wager.snapshot().get("state", "")) == "selected", "Insufficient balance must preserve the selectable ticket")
	check(int(result.get("wallet_delta", 1)) == 0, "Rejected lock must not change the wallet")
	result = wager.lock("plan-A", 17, 4, 100)
	check(bool(result.get("ok", false)) and String(result.get("state", "")) == "locked", "A funded matching lock must activate the ticket")
	check(int(result.get("wallet_before", -1)) == 100 and int(result.get("wallet_after", -1)) == 60 and int(result.get("wallet_delta", 0)) == -40, "Lock must deduct exactly the bold stake")
	snapshot = state(wager, "locked", "A funded lock must remain locked")
	check(bool(snapshot.get("locked", false)) and not bool(snapshot.get("settled", true)), "Locked snapshot must expose lifecycle flags")
	check(not wager.choose("reckless"), "A locked ticket cannot change tier")
	result = wager.lock("plan-A", 17, 4, 100)
	check(not bool(result.get("ok", true)) and String(result.get("reason", "")) == "not_selected", "A locked ticket cannot be locked a second time")

	# A partial clear loses the paid stake and cannot be paid by a later callback.
	result = wager.settle_wave("plan-A", 17, 4, 3, true)
	check(not bool(result.get("ok", true)) and String(result.get("state", "")) == "lost", "An uncleared target wave must lose")
	check(int(result.get("payout", -1)) == 0 and int(result.get("wallet_delta", 1)) == 0 and int(result.get("net", 0)) == -40, "A loss must forfeit the stake without a payout")
	snapshot = state(wager, "lost", "A loss must be terminal")
	check(bool(snapshot.get("settled", false)) and not bool(snapshot.get("locked", true)), "A loss snapshot must mark the ticket settled")
	result = wager.settle_wave("plan-A", 17, 4, 4, true)
	check(not bool(result.get("ok", true)) and bool(result.get("duplicate", false)), "A repeated win callback after a loss must be ignored")
	check(int(result.get("wallet_delta", 1)) == 0, "A repeated terminal callback must not change the wallet")
	check(not wager.choose("steady"), "A lost one-ticket wager cannot be selected again")
	check(not wager.offer(2, "plan-A", 17, 4), "A lost ticket still occupies its night slot")

	# Retry cleanup permits the same numerical night only after an explicit run reset.
	wager.on_retry()
	state(wager, "idle", "Retry must clear the old terminal ticket")
	check(wager.plan_signature().is_empty(), "Retry must clear the old plan identity")
	check(wager.setup(2, "plan-B", 21, 2), "Retry must permit a fresh ticket for the same numerical night")
	check(wager.choose("steady"), "Fresh retry ticket must be selectable")
	result = wager.lock("plan-A", 21, 2, 100)
	check(not bool(result.get("ok", true)) and String(result.get("state", "")) == "expired" and String(result.get("reason", "")) == "plan_changed", "A stale plan must expire before stake is locked")
	check(int(result.get("wallet_delta", 1)) == 0, "A stale pre-lock plan must not deduct a stake")

	# Target reward/count are part of the identity, not merely display data.
	wager.clear()
	check(wager.offer(3, "plan-C", 31, 5), "Target identity case must open")
	check(wager.choose("bold"), "Target identity case must select")
	result = wager.lock("plan-C", 30, 5, 100)
	check(String(result.get("state", "")) == "expired" and String(result.get("reason", "")) == "plan_changed", "A changed reward id must expire the ticket")
	wager.clear()
	check(wager.offer(3, "plan-C", 31, 5), "Count identity case must reopen after clear")
	check(wager.choose("bold"), "Count identity case must select")
	result = wager.lock("plan-C", 31, 4, 100)
	check(String(result.get("state", "")) == "expired" and String(result.get("reason", "")) == "plan_changed", "A changed target count must expire the ticket")
	wager.clear()
	var bound_plan: Array = [{"signature": "plan-stale", "day": 12, "reward_id": 120, "count": 2}]
	var replaced_plan: Array = [{"signature": "plan-replaced", "day": 12, "reward_id": 120, "count": 2}]
	check(wager.choose_target(0, 12, bound_plan), "Pre-lock stale-plan case must bind the original target")
	check(String(wager.place_risk(0, 12, replaced_plan, 100).get("state", "")) == "expired", "A replaced plan must expire during pre-lock risk placement")
	check(int(wager.snapshot().get("stake", -1)) == 0 and int(wager.snapshot().get("wallet_before", -1)) == -1, "Pre-lock plan expiry must not charge a stake")

	# Winning path: each tier's stake/reward is settled once against the exact plan.
	wager.reset()
	check(wager.offer(4, "plan-W", 44, 2), "Winning case must open")
	check(wager.choose("bold"), "Winning case must select bold")
	result = wager.lock_with_balance(100, "plan-W", 44, 2)
	check(bool(result.get("ok", false)) and int(result.get("wallet_after", -1)) == 60, "Winning case must deduct the selected stake")
	result = wager.settle_wave("plan-W", 44, 2, 2, true)
	check(bool(result.get("ok", false)) and String(result.get("state", "")) == "won", "An exact cleared target must win")
	check(int(result.get("payout", -1)) == 120 and int(result.get("wallet_delta", -1)) == 120 and int(result.get("net", -1)) == 80, "Bold win must pay 120 for an 80 net")
	snapshot = state(wager, "won", "Winning ticket must be terminal")
	check(bool(snapshot.get("settled", false)) and int(snapshot.get("last_result", {}).get("payout", -1)) == 120, "Winning snapshot must retain its one payout")
	result = wager.settle_wave("plan-W", 44, 2, 2, true)
	check(not bool(result.get("ok", true)) and bool(result.get("duplicate", false)) and int(result.get("wallet_delta", 1)) == 0, "Repeated winning callbacks must not duplicate the payout")

	# Extra kills are not allowed to satisfy a different saved target count.
	wager.clear()
	check(wager.offer(5, "plan-exact", 55, 2), "Exact-count case must open")
	check(wager.choose("steady"), "Exact-count case must select")
	check(bool(wager.lock("plan-exact", 55, 2, 100).get("ok", false)), "Exact-count case must lock")
	result = wager.settle_wave("plan-exact", 55, 2, 3, true)
	check(String(result.get("state", "")) == "lost" and int(result.get("payout", -1)) == 0, "A mismatched defeated count must not overpay")

	# Eligibility failure and explicit loss both forfeit the already-paid stake.
	wager.clear()
	check(wager.offer(6, "plan-loss", 66, 3), "Eligibility case must open")
	check(wager.choose("reckless"), "Eligibility case must select")
	check(bool(wager.lock("plan-loss", 66, 3, 100).get("ok", false)), "Eligibility case must lock")
	result = wager.settle_wave("plan-loss", 66, 3, 3, false)
	check(String(result.get("state", "")) == "lost" and String(result.get("reason", "")) == "ineligible", "An ineligible clear must lose")
	check(int(result.get("net", 0)) == -60 and int(result.get("wallet_delta", 1)) == 0, "An ineligible clear must forfeit the reckless stake")
	wager.clear()
	check(wager.offer(7, "plan-expire", 77, 1), "Expiry case must open")
	check(wager.choose("steady"), "Expiry case must select")
	check(bool(wager.lock("plan-expire", 77, 1, 100).get("ok", false)), "Expiry case must lock")
	result = wager.expire("dusk")
	check(String(result.get("state", "")) == "expired" and String(result.get("reason", "")) == "dusk", "Dusk must expire an active wager")
	check(int(result.get("payout", -1)) == 0 and int(result.get("net", 0)) == -20, "Expired wager must not refund or pay")
	result = wager.expire("second-call")
	check(not bool(result.get("ok", true)) and bool(result.get("duplicate", false)) and int(result.get("wallet_delta", 1)) == 0, "Repeated expiry must be idempotent")

	# A fresh higher night is allowed only after the previous ticket is terminal.
	wager.clear()
	check(wager.offer(8, "plan-next", 88, 2), "Night transition case must open")
	check(wager.choose("steady"), "Night transition case must select")
	check(bool(wager.lock("plan-next", 88, 2, 100).get("ok", false)), "Night transition case must lock")
	check(not wager.offer(8, "plan-next-2", 88, 2), "Same night replacement must remain forbidden while locked")
	check(String(wager.expire("night_end").get("state", "")) == "expired", "Night transition must explicitly expire the ticket")
	check(wager.offer(9, "plan-new-night", 99, 1), "A higher night must open after explicit expiry")
	snapshot = state(wager, "offered", "Higher night must expose a fresh offer")
	check(int(snapshot.get("night_id", -1)) == 9 and String(snapshot.get("plan_signature", "")) == "plan-new-night", "Higher night must replace the old target identity")

	print("NIGHTFALL_WAVE_WAGER_", "OK" if failures.is_empty() else "FAILED", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
