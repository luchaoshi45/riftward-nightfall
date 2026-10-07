extends RefCounted
## One-use, in-memory handoff when restarting the real production scene.
## Run-local growth is recreated by the scene; only its seed and mode survive.
const REQUEST_KEY := &"nightfall_next_run"
const MODES := ["teaching", "siege", "echo"]
const STREAM_SALTS := {
	"combat": 19453,
	"spawns": 29045,
	"discoveries": 71453,
	"wildlife": 97153,
}

static func stream_seed(run_seed: int, stream: String) -> int:
	# Fold both halves of the run identifier into a stable positive seed. Each
	# subsystem owns its RNG so card choices or combat cannot consume map rolls.
	var folded := run_seed ^ (run_seed >> 32)
	return ((folded ^ int(STREAM_SALTS.get(stream, 0))) & 0x7fffffff) + 1

static func fresh_seed(previous_seed: int) -> int:
	var random := RandomNumberGenerator.new()
	random.randomize()
	var next_seed := random.randi_range(1, 2147483647)
	# A new challenge must differ even if the generator happens to repeat.
	return next_seed if next_seed != previous_seed else next_seed % 2147483647 + 1

static func queue_request(tree: SceneTree, run_seed: int, mode: String, contract_id: String = "") -> bool:
	if not is_instance_valid(tree) or run_seed == 0 or mode not in MODES:
		return false
	if not contract_id.is_empty() and contract_id != "homecoming_pair":return false
	tree.set_meta(REQUEST_KEY, {"seed": run_seed, "mode": mode, "contract_id": contract_id})
	return true

static func consume_request(tree: SceneTree) -> Dictionary:
	if not tree.has_meta(REQUEST_KEY):
		return {}
	var value: Variant = tree.get_meta(REQUEST_KEY)
	tree.remove_meta(REQUEST_KEY)
	if not value is Dictionary:
		return {}
	if typeof(value.get("seed")) != TYPE_INT or int(value.seed) == 0:
		return {}
	if value.get("mode") not in MODES:
		return {}
	var contract_id:=String(value.get("contract_id", ""))
	if not contract_id.is_empty() and contract_id != "homecoming_pair":return {}
	return {"seed": int(value.seed), "mode": String(value.mode), "contract_id": contract_id}

static func clear_request(tree: SceneTree) -> void:
	if tree.has_meta(REQUEST_KEY):
		tree.remove_meta(REQUEST_KEY)
