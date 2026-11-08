extends SceneTree
## Build source-only packs; imported art/audio should use Godot's Export PCK.

const Package = preload("res://src/mod_package.gd")
var problem = ""
var paths: Array = []

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("Usage: godot --headless --path . --script tools/build_mod.gd -- SOURCE OUTPUT.atlasmod [DEPENDENCY.atlasmod ...]")
		quit(1)
		return
	var source = ProjectSettings.globalize_path(args[0]).simplify_path()
	var output = ProjectSettings.globalize_path(args[1]).simplify_path()
	if output.get_extension() != "atlasmod" or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output):
		printerr("OUTPUT must be a new .atlasmod file")
		quit(1)
		return
	var manifest = source.path_join("mod.json")
	if not FileAccess.file_exists(manifest):
		printerr("Missing mod.json")
		quit(1)
		return
	var document = Package.Rules.numbers(JSON.parse_string(FileAccess.get_file_as_string(manifest)))
	if not Package.manifest_valid(document):
		printerr("Invalid manifest")
		quit(1)
		return
	if document.api == 2:
		var documents = []
		var seen = []
		for path in args.slice(2):
			var dependency = Package.read(path)
			if dependency.is_empty() or dependency.id in seen:
				printerr("Invalid dependency: ", path)
				quit(1)
				return
			documents.append(dependency)
			seen.append(dependency.id)
		documents.append(document)
		for item in documents:
			for required in item.get("requires", []):
				if not required in seen or documents.find(item) <= seen.find(required):
					printerr("Missing earlier dependency: ", required)
					quit(1)
					return
		var compiled = Package.Rules.compose(documents, JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json")))
		if not compiled.error.is_empty():
			printerr(compiled.error)
			quit(1)
			return
	var error = DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var pck_path = source.path_join("content.pck")
	var generated = not FileAccess.file_exists(pck_path)
	if generated:
		pck_path = output + ".pck.tmp"
		var pack = PCKPacker.new()
		if error == OK: error = pack.pck_start(pck_path)
		if error == OK and (document.api == 1 or DirAccess.dir_exists_absolute(source.path_join("files"))): add_files(pack, source.path_join("files"), "res://")
		if error == OK and problem.is_empty(): error = pack.flush()
	var balance: Variant = null
	if paths == ["res://assets/balance.json"]:
		balance = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("files/assets/balance.json")))
		if not Package.balance_valid(balance, JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json"))): problem = "Invalid shared balance rules"
	if error == OK and problem.is_empty(): error = Package.create(manifest, pck_path, output, balance)
	if generated: DirAccess.remove_absolute(pck_path)
	if error != OK or not problem.is_empty():
		printerr(problem if not problem.is_empty() else error_string(error))
		quit(1)
	else:
		print("PASS: built ", output)
		quit()

func add_files(pack: PCKPacker, source: String, target: String) -> void:
	var dir = DirAccess.open(source)
	if dir == null:
		problem = "Cannot read " + source
		return
	for file in dir.get_files():
		if not file.get_extension() in ["json", "gd", "tscn", "tres", "gdshader", "txt", "csv"]:
			problem = "Use Godot Export PCK for imported resources: " + file
			return
		paths.append(target.path_join(file))
		var error = pack.add_file(target.path_join(file), source.path_join(file))
		# Exported games remap scripts/scenes to compiled resources; prefer the mod source.
		if error == OK and file.get_extension() in ["gd", "tscn", "tres"]:
			error = pack.add_file_removal(target.path_join(file) + ".remap")
		if error != OK:
			problem = error_string(error)
			return
	for folder in dir.get_directories():
		if folder.begins_with("."): continue
		add_files(pack, source.path_join(folder), target.path_join(folder))
