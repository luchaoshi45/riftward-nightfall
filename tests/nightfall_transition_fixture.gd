extends RefCounted
## finish_for_fixture is artificial setup, never natural clearance proof.
## It removes hostile actors without rewards, retains friendly orders/effects for
## the production transition, and never records a fabricated archive unlock.

static func finish_for_fixture(game: Node3D) -> bool:
	if not is_instance_valid(game) or game.is_queued_for_deletion(): return false
	if game.phase == "ended" or game.quitting or game.restart_pending or game.shutting_down: return false
	if not is_instance_valid(game.hero) or game.hero.is_queued_for_deletion(): return false
	if not game.hero.alive or game.hero.hp <= 0.0 or game.beacon_hp <= 0.0: return false
	for enemy: Variant in game.enemies:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion(): enemy.queue_free()
	game.enemies.clear()
	# A committed hostile flight is a real clearance threat. Retire it only in
	# this artificial setup; natural projectile-clearance tests must wait for it.
	for controller: Variant in game.lobbers.duplicate():
		if is_instance_valid(controller) and String(controller.snapshot().get("phase", "")) == "flight":
			controller.clear()
	game.phase = "night"
	game.phase_time = 0.0
	game.wave_index = game.WAVES_PER_NIGHT
	game.begin_night_clearance()
	var archive_enabled: bool = game.archive.enabled
	game.archive.enabled = false
	game.finish_night()
	game.archive.enabled = archive_enabled
	return game.phase in ["draft", "ended"]

## These two observational helpers never change a production actor or clock.
static func deadline_evidence(game: Node3D, elapsed: float) -> Dictionary:
	var result: Dictionary = game.night_clearance_snapshot().duplicate(true)
	var deadline: float = game.NIGHT_LENGTH
	var sample_phase: String = game.phase
	var direct_dawn: bool = sample_phase == "draft" and game.return_phase == "day" and elapsed >= deadline
	if direct_dawn:
		# The production completion gate has cleared the original night. Its new
		# daytime actors are unrelated to that night's remaining-threat receipt.
		result.merge({"active":false,"final":false,"remaining":0,"projectiles":0,
			"elapsed":maxf(0.0,elapsed-deadline)},true)
	result.merge({"sample_elapsed":elapsed,"phase":sample_phase,"sample_phase":sample_phase,
		"reached":elapsed >= deadline,"direct_dawn":direct_dawn,
		"clearance_elapsed_source":"sample_elapsed_minus_deadline" if direct_dawn else "production_snapshot",
		"parts":int(game.scrap),"kills":int(game.kills)})
	return result

static func record_natural_receipt(game: Node3D, evidence: Dictionary, label: String,
		elapsed: float, cutoff: Dictionary) -> void:
	var observed_cutoff: Dictionary = cutoff.duplicate(true)
	if observed_cutoff.is_empty() and elapsed < game.NIGHT_LENGTH and game.phase == "ended":
		observed_cutoff = {"reached":false,"direct_dawn":false,"before_deadline_termination":true,
			"sample_elapsed":elapsed,"phase":String(game.phase),"sample_phase":String(game.phase),
			"phase_time":float(game.phase_time),"victory":bool(game.victory)}
	if not evidence.has("natural_clearance"): evidence["natural_clearance"] = []
	(evidence["natural_clearance"] as Array).append({"label":label,"seed":int(game.run.seed_value),
		"deadline_seconds":float(game.NIGHT_LENGTH),"actual_elapsed":elapsed,"cutoff":observed_cutoff,
		"phase":String(game.phase),"parts":int(game.scrap),"kills":int(game.kills),
		"hero_hp":float(game.hero.hp),"beacon_hp":float(game.beacon_hp)})
