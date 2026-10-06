extends SceneTree

# This pack contains raw test scripts only; game resources stay in the EXE.
var _workspace: String = ""
var _build: String = ""
var _partial: Array[String] = []

func _initialize() -> void:
	call_deferred("_prepare")

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

func _target(path: String) -> bool:
	return path.get_base_dir() == _build and _physical(path) and not DirAccess.dir_exists_absolute(path)

func _arguments() -> Dictionary:
	var values: Dictionary = {}
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 6:
		return {}
	for index in range(0, arguments.size(), 2):
		var key := arguments[index]
		if not ["--workspace", "--bundle", "--tests"].has(key) or values.has(key):
			return {}
		values[key] = arguments[index + 1]
	return values

func _failed(message: String) -> void:
	for path in _partial:
		if _target(path) and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	push_error("PACKAGED_TEST_BUNDLE_FAILED " + message)
	quit(1)

func _replace(temporary: String, destination: String) -> bool:
	if not _target(temporary) or not _target(destination):
		return false
	if FileAccess.file_exists(destination) and DirAccess.remove_absolute(destination) != OK:
		return false
	return DirAccess.rename_absolute(temporary, destination) == OK

func _prepare() -> void:
	var arguments := _arguments()
	if arguments.size() != 3:
		_failed("Expected --workspace, --bundle and --tests")
		return
	_workspace = String(arguments["--workspace"]).replace("\\", "/")
	_build = _workspace.path_join("build")
	var bundle := String(arguments["--bundle"]).replace("\\", "/")
	if not _physical(_workspace) or not DirAccess.dir_exists_absolute(_workspace) or not _physical(_build) or not DirAccess.dir_exists_absolute(_build):
		_failed("Workspace and build must be physical directories")
		return
	if not _matches(bundle.get_file(), "packaged-tests-Riftward_Nightfall_v[0-9]+\\.[0-9]+\\.[0-9]+\\.pck") or not _target(bundle):
		_failed("Unexpected bundle path")
		return
	var names: Array[String] = []
	var pending: Array[String] = []
	for name in String(arguments["--tests"]).split(","):
		if not _matches(name, "[a-z0-9_]+") or names.has(name):
			_failed("Unexpected or duplicate test name")
			return
		names.append(name)
		pending.append("res://tests/" + name + ".gd")
	var references := RegEx.new()
	if references.compile("([\"'])(res://tests/[^\"'\\r\\n]+)\\1") != OK:
		_failed("Cannot compile dependency matcher")
		return
	var sources: Dictionary = {}
	var hashes: Dictionary = {}
	while not pending.is_empty():
		var resource: String = pending.pop_front()
		if hashes.has(resource):
			continue
		if not _matches(resource, "res://tests/[a-z0-9_]+\\.gd"):
			_failed("Only flat ASCII tests/*.gd dependencies are allowed")
			return
		var source := _workspace.path_join(resource.trim_prefix("res://"))
		if not _physical(source) or not FileAccess.file_exists(source):
			_failed("Missing physical test source: " + resource)
			return
		var bytes := FileAccess.get_file_as_bytes(source)
		var digest := FileAccess.get_sha256(source)
		if bytes.is_empty() or digest.is_empty():
			_failed("Cannot read test source: " + resource)
			return
		sources[resource] = source
		hashes[resource] = digest
		for found in references.search_all(bytes.get_string_from_utf8()):
			var dependency: String = found.get_string(2)
			# Non-script paths (for example PNG evidence outputs) are not dependencies.
			# Every .gd reference still enters strict flat-path validation above.
			if dependency.to_lower().ends_with(".gd"):
				pending.append(dependency)
	var paths: Array = sources.keys()
	paths.sort()
	var entries: Array[Dictionary] = []
	for resource in paths:
		if not _physical(sources[resource]) or FileAccess.get_sha256(sources[resource]) != hashes[resource]:
			_failed("Source changed before packaging")
			return
		entries.append({"path": resource, "sha256": hashes[resource]})
	var manifest := bundle + ".manifest.json"
	var suffix := "." + str(OS.get_process_id()) + ".tmp"
	var temporary_pack := bundle + suffix
	var temporary_manifest := manifest + suffix
	if not _target(manifest) or not _target(temporary_pack) or not _target(temporary_manifest):
		_failed("Unsafe manifest or staging path")
		return
	_partial = [temporary_pack, temporary_manifest]
	var packer := PCKPacker.new()
	if packer.pck_start(temporary_pack) != OK:
		_failed("Cannot create verification pack")
		return
	for resource in paths:
		if packer.add_file(resource, sources[resource]) != OK:
			packer = null
			_failed("Cannot add test source")
			return
	if packer.flush() != OK:
		packer = null
		_failed("Cannot finish verification pack")
		return
	packer = null
	for resource in paths:
		if not _physical(sources[resource]) or FileAccess.get_sha256(sources[resource]) != hashes[resource]:
			_failed("Source changed during packaging")
			return
	var pack_hash := FileAccess.get_sha256(temporary_pack)
	if pack_hash.is_empty():
		_failed("Cannot hash verification pack")
		return
	var writer: FileAccess = FileAccess.open(temporary_manifest, FileAccess.WRITE)
	if writer == null:
		_failed("Cannot create verification manifest")
		return
	writer.store_string(JSON.stringify({"schema": 1, "bundle_file": bundle.get_file(),
		"pack_sha256": pack_hash, "requested_tests": names, "entries": entries}, "\t") + "\n")
	writer.flush()
	var write_error := writer.get_error()
	writer.close()
	if write_error != OK or not _replace(temporary_pack, bundle) or not _replace(temporary_manifest, manifest):
		_failed("Cannot publish verification pack and manifest")
		return
	print("PACKAGED_TEST_BUNDLE_READY " + bundle.get_file() + " closure=" + JSON.stringify(paths))
	quit(0)
