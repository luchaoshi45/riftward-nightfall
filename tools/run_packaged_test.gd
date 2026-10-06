extends SceneTree

# No game/test preloads: validate and mount the test-only pack first.
func _initialize() -> void:
	call_deferred("_run_test")

func _matches(value: String, pattern: String) -> bool:
	var expression := RegEx.new()
	if expression.compile(pattern) != OK:
		return false
	var found: RegExMatch = expression.search(value)
	return found != null and found.get_string() == value

func _physical(path: String) -> bool:
	var normalized := path.replace("\\", "/")
	if not normalized.is_absolute_path() or normalized.simplify_path() != normalized:
		return false
	var filesystem_root := "/"
	if normalized.length() >= 3 and normalized[1] == ":":
		filesystem_root = normalized.substr(0, 3)
	elif normalized.begins_with("//"):
		var parts := normalized.substr(2).split("/")
		if parts.size() < 2:
			return false
		filesystem_root = "//" + parts[0] + "/" + parts[1]
	var current := normalized
	while current != filesystem_root:
		var separator := current.rfind("/")
		if separator < 0:
			return false
		var parent := current.substr(0, separator)
		if parent.length() < filesystem_root.length():
			parent = filesystem_root
		if parent == current or not current.begins_with(parent):
			return false
		var directory: DirAccess = DirAccess.open(parent)
		if directory == null or directory.is_link(current.substr(separator + 1)):
			return false
		current = parent
	return DirAccess.dir_exists_absolute(filesystem_root)

func _arguments() -> Dictionary:
	var values: Dictionary = {}
	var arguments := OS.get_cmdline_user_args()
	var index := 0
	while index < arguments.size():
		var key := arguments[index]
		if ["--workspace", "--bundle", "--test"].has(key):
			if index + 1 >= arguments.size() or values.has(key):
				return {}
			values[key] = arguments[index + 1]
			index += 2
		else:
			# Test-specific --case/--output-dir arguments remain available to the test.
			index += 1
	return values

func _failed(message: String) -> void:
	push_error("PACKAGED_TEST_FAILED " + message)
	quit(1)

func _run_test() -> void:
	var arguments := _arguments()
	if arguments.size() != 3:
		_failed("Expected --workspace, --bundle and --test")
		return
	var workspace := String(arguments["--workspace"]).replace("\\", "/")
	var build := workspace.path_join("build")
	var bundle := String(arguments["--bundle"]).replace("\\", "/")
	var name := String(arguments["--test"])
	var manifest_path := bundle + ".manifest.json"
	if not _matches(name, "[a-z0-9_]+") or not _physical(workspace) or not DirAccess.dir_exists_absolute(workspace):
		_failed("Unexpected test name or workspace")
		return
	if not _matches(bundle.get_file(), "packaged-tests-Riftward_Nightfall_v[0-9]+\\.[0-9]+\\.[0-9]+\\.pck") or bundle.get_base_dir() != build:
		_failed("Unexpected verification bundle path")
		return
	if not _physical(bundle) or not _physical(manifest_path) or not FileAccess.file_exists(bundle) or not FileAccess.file_exists(manifest_path):
		_failed("Missing physical bundle or manifest")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		_failed("Invalid verification manifest")
		return
	var manifest: Dictionary = parsed
	if manifest.get("schema") != 1 or manifest.get("bundle_file") != bundle.get_file() or typeof(manifest.get("pack_sha256")) != TYPE_STRING:
		_failed("Unexpected verification manifest schema")
		return
	var pack_hash: String = manifest["pack_sha256"]
	if not _matches(pack_hash, "[a-f0-9]{64}") or FileAccess.get_sha256(bundle) != pack_hash:
		_failed("Verification pack hash mismatch")
		return
	if not manifest.get("entries") is Array or not manifest.get("requested_tests") is Array:
		_failed("Missing verification entry lists")
		return
	var requested: Array = manifest["requested_tests"]
	var names: Dictionary = {}
	for item in requested:
		if typeof(item) != TYPE_STRING or not _matches(item, "[a-z0-9_]+") or names.has(item):
			_failed("Unexpected requested test")
			return
		names[item] = true
	if not names.has(name):
		_failed("Test was not requested by this verification bundle")
		return
	var entries: Array = manifest["entries"]
	var hashes: Dictionary = {}
	for item in entries:
		if not item is Dictionary:
			_failed("Unexpected verification entry")
			return
		var entry: Dictionary = item
		if typeof(entry.get("path")) != TYPE_STRING or typeof(entry.get("sha256")) != TYPE_STRING:
			_failed("Malformed verification entry")
			return
		var path: String = entry["path"]
		var digest: String = entry["sha256"]
		if not _matches(path, "res://tests/[a-z0-9_]+\\.gd") or not _matches(digest, "[a-f0-9]{64}") or hashes.has(path):
			_failed("Only unique tests/*.gd entries are allowed")
			return
		if FileAccess.file_exists(path) or ResourceLoader.exists(path):
			_failed("Test entry already exists in the game pack or source fallback: " + path)
			return
		hashes[path] = digest
	for requested_name in names:
		if not hashes.has("res://tests/" + requested_name + ".gd"):
			_failed("Requested test is missing from the closure")
			return
	# The manifest binds a locally prepared artifact; it is not host authentication.
	if not _physical(bundle) or FileAccess.get_sha256(bundle) != pack_hash or not ProjectSettings.load_resource_pack(bundle, false):
		_failed("Cannot mount verified test-only pack")
		return
	for path in hashes:
		if FileAccess.get_sha256(path) != hashes[path]:
			_failed("Mounted test bytes disagree with the verification manifest")
			return
	var entry_path := "res://tests/" + name + ".gd"
	var test_script: Script = load(entry_path) as Script
	if test_script == null or not test_script.can_instantiate() or test_script.get_instance_base_type() != "SceneTree":
		_failed("Packaged entry must be an instantiable SceneTree script")
		return
	print("PACKAGED_TEST_READY name=" + name + " entry=" + entry_path + " closure=" + JSON.stringify(hashes.keys()))
	# Attach to this tree; constructing a second SceneTree leaves the wrong main loop.
	set_script(test_script)
	call_deferred("_initialize")
