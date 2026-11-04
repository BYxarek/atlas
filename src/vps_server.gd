extends Node

var session: Node
var stop_path = ""

func _ready() -> void:
	var port_value = OS.get_environment("ATLAS_PORT")
	var limit_value = OS.get_environment("ATLAS_MAX_ROOMS")
	var data_path = OS.get_environment("ATLAS_DATA_DIR")
	if data_path.is_empty(): data_path = "user://server"
	stop_path = data_path.path_join(".stop")
	if (not port_value.is_empty() and not port_value.is_valid_int()) or (not limit_value.is_empty() and not limit_value.is_valid_int()):
		push_error("ATLAS_PORT and ATLAS_MAX_ROOMS must be integers")
		get_tree().quit(1)
		return
	session = load("res://src/network_session.gd").new()
	session.identity_token = "0".repeat(48)
	get_parent().add_child(session)
	var port = int(port_value) if not port_value.is_empty() else 24760
	var limit = int(limit_value) if not limit_value.is_empty() else 8
	var error = session.host_directory(port, data_path, limit)
	if error != OK:
		push_error("ATLAS VPS startup failed: " + error_string(error))
		get_tree().quit(1)
		return
	print("ATLAS VPS ready: port=%d rooms=%d data=%s" % [port, limit, data_path])

func _process(_delta: float) -> void:
	if session != null and session.active and FileAccess.file_exists(stop_path):
		session.directory.stop()
		get_tree().quit()
