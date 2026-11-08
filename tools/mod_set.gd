extends SceneTree

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 3 or args[0] != "unpack":
		printerr("Usage: godot --headless --path . --script tools/mod_set.gd -- unpack SET.atlaspack NEW_DIRECTORY")
		quit(1)
		return
	var result = preload("res://src/mod_set.gd").unpack(ProjectSettings.globalize_path(args[1]), ProjectSettings.globalize_path(args[2]))
	if not result.error.is_empty():
		printerr(result.error)
		quit(1)
		return
	print("PASS: verified and unpacked ", result.paths.size(), " ordered mods")
	quit()
