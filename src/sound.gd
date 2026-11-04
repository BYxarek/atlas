extends Node

const L = preload("res://src/i18n.gd")
## Audio is driven by semantic game events, not by translated journal text.

const CUES = ["click", "select", "open", "cancel", "confirm", "error", "save", "coins", "upgrade", "unlock",
	"warning", "all_clear", "invasion", "report", "rocket_launch", "rocket_loop", "start", "victory", "defeat",
	"campaign_win", "campaign_lose", "spy_send", "spy_loop", "naval_loop", "army_loop", "march", "march_naval",
	"battle", "battle_naval", "nuke", "notification"]
const UI_CUES = ["click", "select", "open", "cancel", "confirm", "error", "save", "notification"]
const RESULT_CUES = ["start", "victory", "defeat", "campaign_win", "campaign_lose"]
var game: RefCounted
var streams: Dictionary = {}
var players: Array = []
var loops: Dictionary = {}
var next_player = 0
var master_volume = 0.8
var effects_volume = 0.75

func _ready() -> void:
	if AudioServer.get_bus_index("Effects") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Effects")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	if AudioServer.get_bus_index("Interface") < 0:
		AudioServer.add_bus()
		var ui_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(ui_bus, "Interface")
		AudioServer.set_bus_send(ui_bus, "Effects")
		AudioServer.set_bus_volume_db(ui_bus, -13)
	var limiter_exists = false
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter: limiter_exists = true
	if not limiter_exists:
		var limiter = AudioEffectHardLimiter.new()
		limiter.ceiling_db = -1
		AudioServer.add_bus_effect(0, limiter)
	for cue in CUES:
		streams[cue] = load("res://assets/audio/%s.ogg" % cue)
	for i in 12:
		var player = AudioStreamPlayer.new()
		add_child(player)
		players.append(player)
	for cue in ["army_loop", "naval_loop", "spy_loop", "rocket_loop"]:
		var player = AudioStreamPlayer.new()
		player.bus = "Effects"
		player.stream = streams[cue].duplicate()
		player.stream.loop = true
		player.volume_db = -29 if cue == "spy_loop" else -25
		add_child(player)
		loops[cue] = player
	set_mix(master_volume, effects_volume)

func set_mix(master: float, effects: float) -> void:
	master_volume = clampf(master, 0, 1)
	effects_volume = clampf(effects, 0, 1)
	for entry in [["Master", master_volume], ["Effects", effects_volume]]:
		var index = AudioServer.get_bus_index(entry[0])
		AudioServer.set_bus_mute(index, entry[1] <= 0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, entry[1])))

func play(cue: String) -> void:
	if not streams.has(cue):
		push_error("Unknown audio cue: " + cue)
		return
	var player: AudioStreamPlayer = players[next_player]
	next_player = (next_player + 1) % players.size()
	player.stop()
	player.stream = streams[cue]
	player.set_meta("gameplay", not cue in UI_CUES and not cue in RESULT_CUES)
	player.bus = "Master" if cue in RESULT_CUES else "Effects"
	player.volume_db = -13
	if cue in ["nuke", "invasion"]: player.volume_db = -9
	if cue in ["march", "march_naval", "coins"]: player.volume_db = -16
	if cue == "spy_send": player.volume_db = -24
	if cue == "notification": player.volume_db = -17
	player.play()
	player.stream_paused = game != null and game.paused and player.get_meta("gameplay")

func stop_gameplay() -> void:
	for player in players:
		if player.get_meta("gameplay", false) or player.bus == "Master": player.stop()
	for player in loops.values(): player.stop()

func sync() -> void:
	if game == null: return
	for player in players:
		if player.get_meta("gameplay", false): player.stream_paused = game.paused
	var wanted = {"army_loop": false, "naval_loop": false, "spy_loop": not game.mission.is_empty(), "rocket_loop": false}
	for op in game.operations + game.remote_operations:
		if op.kind == "enemy" and op.get("surprise", false): continue
		if op.kind == "nuke": wanted.rocket_loop = true
		elif op.kind in ["attack", "enemy"]:
			wanted["naval_loop" if op.overseas else "army_loop"] = true
	for cue in loops:
		var player: AudioStreamPlayer = loops[cue]
		if wanted[cue] and not game.finished:
			if not player.has_stream_playback(): player.play()
			player.stream_paused = game.paused
		else:
			player.stop()

func _process(_delta: float) -> void:
	sync()

func _exit_tree() -> void:
	for player in players + loops.values():
		player.stop()
		player.stream = null
	streams.clear()
