extends SceneTree

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const HudScript = preload("res://scripts/camp_hud.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager = AudioManagerScript.new()
	manager.name = "AudioManager"
	root.add_child(manager)
	await process_frame

	if AudioServer.get_bus_index(&"SFX") < 0:
		_fail("SFX audio bus was not created")
		return
	if AudioServer.get_bus_index(&"Ambience") < 0:
		_fail("Ambience audio bus was not created")
		return
	var players: Array = manager.get("_players")
	var streams: Dictionary = manager.get("_streams")
	var ambience_player: AudioStreamPlayer = manager.get("_ambience_player")
	if players.size() != AudioManagerScript.VOICE_COUNT:
		_fail("SFX voice pool was not initialized")
		return
	if streams.size() != 17:
		_fail("Expected 17 synthesized sound effects")
		return
	if ambience_player == null or not ambience_player.playing:
		_fail("Background ambience did not start")
		return
	var ambience_stream := ambience_player.stream as AudioStreamWAV
	if ambience_stream == null or ambience_stream.loop_mode != AudioStreamWAV.LOOP_FORWARD:
		_fail("Background ambience is not a looping PCM stream")
		return
	var audible_motion := 0.0
	var motion_samples := 0
	var previous_sample := float(ambience_stream.data.decode_s16(0)) / 32768.0
	for byte_offset in range(32, ambience_stream.data.size(), 32):
		var current_sample := float(ambience_stream.data.decode_s16(byte_offset)) / 32768.0
		audible_motion += absf(current_sample - previous_sample)
		previous_sample = current_sample
		motion_samples += 1
	if audible_motion / float(maxi(motion_samples, 1)) < 0.004:
		_fail("Background ambience has too little audible-frequency energy")
		return
	await create_timer(0.95).timeout
	if ambience_player.volume_db < AudioManagerScript.AMBIENCE_VOLUME_DB - 1.0:
		_fail("Background ambience did not fade in")
		return
	manager.call("play_sfx", &"bell", -12.0)
	await create_timer(0.12).timeout
	if ambience_player.volume_db > -60.0:
		_fail("Background ambience did not duck while an effect played")
		return
	await create_timer(2.35).timeout
	if ambience_player.volume_db < AudioManagerScript.AMBIENCE_VOLUME_DB - 2.0:
		_fail("Background ambience did not return after the effect")
		return

	for effect_name: StringName in streams:
		var stream: AudioStreamWAV = streams[effect_name]
		if stream == null or stream.data.is_empty():
			_fail("Sound effect has no PCM data: %s" % effect_name)
			return
		if stream.mix_rate != AudioManagerScript.SAMPLE_RATE:
			_fail("Unexpected sample rate for: %s" % effect_name)
			return
		manager.call("play_sfx", effect_name, -12.0)

	await create_timer(1.4).timeout
	var hud = HudScript.new()
	root.add_child(hud)
	await process_frame
	var killer_state := {
		"role": "Killer", "ghost": false, "kill_cooldown": 0.0,
		"bodies": [], "objectives": [], "sabotages": []
	}
	hud.set_phase4_state(killer_state)
	killer_state["kill_cooldown"] = 25.0
	killer_state["bodies"] = [{"victim_id": "test_victim"}]
	hud.set_phase4_state(killer_state)
	var killer_feedback_playing := false
	for player: AudioStreamPlayer in players:
		if player.playing and player.stream == streams[&"killer_confirm"]:
			killer_feedback_playing = true
			break
	if not killer_feedback_playing:
		_fail("Killer did not receive confirmed-kill audio feedback")
		return
	await create_timer(0.80).timeout
	root.remove_child(hud)
	hud.free()
	print("Audio effects checks: PASS (17 effects, looping ambience, %d pooled voices)" % players.size())
	ambience_player.stop()
	ambience_player.stream = null
	for player: AudioStreamPlayer in players:
		player.stop()
		player.stream = null
	streams.clear()
	root.remove_child(manager)
	manager.free()
	await create_timer(0.10).timeout
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
