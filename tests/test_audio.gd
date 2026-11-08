extends SceneTree

const Game = preload("res://src/game.gd")
const Sound = preload("res://src/sound.gd")
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + text)

func run() -> void:
	var game = Game.new()
	var sound = Sound.new()
	sound.game = game
	root.add_child(sound)
	check(sound.streams.size() == 31, "Thirty-one downloaded and prepared sounds load")
	for cue in Sound.CUES:
		check(sound.streams[cue] is AudioStreamOggVorbis and sound.streams[cue].get_length() > 0 and sound.streams[cue].get_length() < 8, "Cue decodes and has bounded duration: " + cue)
		sound.play(cue)
		var player: AudioStreamPlayer = sound.players[(sound.next_player - 1 + sound.players.size()) % sound.players.size()]
		check(player.stream == sound.streams[cue] and player.has_stream_playback(), "Cue reaches playback: " + cue)
	check(sound.players.size() == 12, "Concurrent effects use a bounded player pool")
	check(AudioServer.get_bus_effect(0, 0) is AudioEffectHardLimiter, "Master limiter prevents clipping")
	sound.set_mix(0, 1)
	check(AudioServer.is_bus_mute(0), "Zero master volume fully mutes output")
	sound.set_mix(1, 0)
	check(not AudioServer.is_bus_mute(0) and AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects")), "Effects can be muted without muting results")
	sound.set_mix(0.8, 0.75)
	game.start(0)
	game.coins = 10000
	game.spy(1)
	sound.sync()
	check(sound.loops.spy_loop.has_stream_playback(), "Spy mission starts radio ambience")
	game.paused = true
	sound.sync()
	check(sound.loops.spy_loop.stream_paused, "Pause freezes mission ambience")
	sound.play("click")
	check(not sound.players[(sound.next_player - 1 + 12) % 12].stream_paused, "Menu remains audible during pause")
	game.paused = false
	sound.sync()
	check(not sound.loops.spy_loop.stream_paused, "Resuming campaign resumes mission ambience")
	game.mission = {}
	sound.sync()
	check(not sound.loops.spy_loop.has_stream_playback(), "Completed mission stops ambience")
	game.units[2] = 4
	game.dispatch_attack(1)
	sound.sync()
	check(sound.loops.naval_loop.has_stream_playback(), "Naval march starts ship ambience")
	game.operations = [{"kind": "attack", "overseas": false}, {"kind": "nuke"}]
	sound.sync()
	check(sound.loops.army_loop.has_stream_playback() and sound.loops.rocket_loop.has_stream_playback(), "Land march and rocket flight have independent ambience")
	game.paused = true
	sound.sync()
	check(sound.loops.army_loop.stream_paused and sound.loops.rocket_loop.stream_paused, "Pause freezes every active operation")
	sound.stop_gameplay()
	check(sound.loops.values().all(func(player): return not player.has_stream_playback()), "Changing campaign clears old operation audio")
	var cues: Array = []
	var g = Game.new()
	g.sound_requested.connect(func(cue): cues.append(cue))
	g.start(0)
	g.coins = 100000
	g.recruit(0)
	g.upgrade_army(0)
	g.upgrade_business(0, 0)
	g.spy(1)
	for i in 6: g.tick()
	g.countries[1].units = [1, 0, 0]
	g.units = [500, 50, 4]
	g.dispatch_attack(1)
	for i in 4: g.tick()
	for id in range(2, 11):
		g.units = [10000, 10000, 10000]
		g.attack(id)
	g.nuclear_strike(11)
	for i in 3: g.tick()
	g.schedule_warning()
	var warning = g.pending_warning()
	g.elapsed = int(warning.deadline)
	g.launch_enemy_attack(int(warning.attacker), g.origin_for(int(warning.attacker)))
	for i in 5: g.tick()
	g.units = [1, 0, 4]
	g.countries[12].units = [10000, 1000, 1000]
	g.attack(12)
	for cue in ["start", "coins", "upgrade", "spy_send", "report", "march_naval", "battle_naval", "victory", "unlock", "rocket_launch", "nuke", "warning", "invasion", "defeat"]:
		check(cue in cues, "Simulation emits sound for event: " + cue)
	var count = cues.size()
	g.paused = true
	g.tick()
	check(cues.size() == count, "Paused simulation generates no repeated event audio")
	if DisplayServer.get_name() != "headless":
		game.operations = []
		game.mission = {}
		game.paused = false
		sound.stop_gameplay()
		sound.sync()
		var capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(0, capture)
		sound.play("coins")
		await create_timer(0.15).timeout
		var buffer = capture.get_buffer(mini(1024, capture.get_frames_available()))
		var audible = false
		for frame in buffer:
			if absf(frame.x) + absf(frame.y) > 0.00001: audible = true
		check(buffer.size() > 0 and audible, "Native audio mixer produces non-silent output")
		AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	for player in sound.players + sound.loops.values(): player.stop()
	await create_timer(0.2).timeout
	sound.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	print("%s: %d audio checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
