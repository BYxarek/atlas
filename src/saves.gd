extends RefCounted

const L = preload("res://src/i18n.gd")

const Simulation = preload("res://src/game.gd")
var directory: String

func _init(path: String = "user://saves") -> void:
	directory = path

func autosave(game: RefCounted) -> Error:
	var error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	return game.save_game(directory.path_join("auto_" + game.campaign_id + ".json"))

func manual_save(game: RefCounted) -> Error:
	var error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	return game.save_game(directory.path_join("save_%d_%d.json" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]))

func list_saves() -> Array:
	var paths: Array = []
	var dir = DirAccess.open(directory)
	if dir != null:
		for file in dir.get_files():
			if file.ends_with(".json"):
				paths.append(directory.path_join(file))
	if directory == "user://saves" and FileAccess.file_exists(Simulation.SAVE_PATH):
		paths.append(Simulation.SAVE_PATH)
	var result: Array = []
	for path in paths:
		var saved = Simulation.new()
		var valid = saved.load_game(path)
		result.append({"path": path, "valid": valid, "modified": FileAccess.get_modified_time(path),
			"auto": path.get_file().begins_with("auto_"), "name": L.country(saved.atlas[saved.home]) if valid else L.text("Повреждённое сохранение"),
			"coins": int(saved.coins), "elapsed": saved.elapsed, "owned": saved.owned_count(), "color": saved.player_color,
			"defeated": valid and saved.finished and saved.owned_count() == 0})
	result.sort_custom(func(a, b):
		if a.modified == b.modified:
			return a.path > b.path
		return a.modified > b.modified)
	return result
