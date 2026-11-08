extends SceneTree
## Validate a source/package profile, inspect provenance, or compare a saved profile.

const Package = preload("res://src/mod_package.gd")

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() < 2 or not args[0] in ["validate", "inspect", "save-check"]:
		printerr("Usage: godot --headless --path . --script tools/mod_tool.gd -- validate|inspect|save-check MOD [MOD...] [SAVE.json]")
		quit(1)
		return
	var mode = args[0]
	var paths = Array(args.slice(1))
	var save_path = str(paths.pop_back()) if mode == "save-check" else ""
	var documents = []
	var profile = []
	var seen = []
	for path in paths:
		var data = Package.read(path) if str(path).ends_with(".atlasmod") else Package.Rules.numbers(JSON.parse_string(FileAccess.get_file_as_string(str(path).path_join("mod.json"))))
		if not Package.manifest_valid(data) or data.id in seen or data.game_version != ProjectSettings.get_setting("application/config/version"):
			printerr("Invalid manifest or duplicate ID: ", path)
			quit(1)
			return
		for required in data.get("requires", []):
			if not required in seen:
				printerr("Missing earlier dependency: ", required)
				quit(1)
				return
		documents.append(data)
		seen.append(data.id)
		if data.has("sha256"): profile.append(Package.descriptor(data))
	for doc in documents:
		for conflict in doc.get("conflicts", []):
			if conflict in seen:
				printerr("Conflicting mods: ", doc.id, " / ", conflict)
				quit(1)
				return
	var compiled = Package.Rules.compose(documents, JSON.parse_string(FileAccess.get_file_as_string("res://assets/balance.json")))
	if not compiled.error.is_empty():
		printerr(compiled.error)
		quit(1)
		return
	if mode == "save-check":
		var saved = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if profile.size() != documents.size() or not saved is Dictionary or saved.get("mods", "") != Package.fingerprint(profile):
			printerr("Save requires a different exact package profile; no migration was performed")
			quit(1)
			return
	if mode == "inspect": print(JSON.stringify({"balance": compiled.balance, "content": compiled.content, "sources": compiled.sources, "conflicts": compiled.conflicts}, "  "))
	print("PASS: valid profile, ", documents.size(), " mods; ", compiled.conflicts.size(), " overlapping balance changes")
	quit()
