extends Node

func _ready() -> void:
	var mods = load("res://src/mods.gd").new()
	if not mods.activate():
		var message = Label.new()
		message.text = str(Engine.get_meta("atlas_mod_error")) + "\nRestart with -- --no-mods"
		add_child(message)
		return
	# Resolve the game only after mounting packs, before any static data or preloads.
	var scene = load("res://main.tscn")
	if scene == null:
		var message = Label.new()
		message.text = "Cannot load game. Restart with -- --no-mods"
		add_child(message)
		return
	get_tree().change_scene_to_packed.call_deferred(scene)
