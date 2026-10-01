extends Node

## Lightweight, local-only sound effects for Double Take.
##
## The sounds are synthesized once at startup instead of shipping large audio
## files. This keeps mobile builds small and lets gameplay code trigger effects
## without involving any network/session state.

const SAMPLE_RATE := 32000
const VOICE_COUNT := 10
const SFX_BUS := &"SFX"
const AMBIENCE_BUS := &"Ambience"
const AMBIENCE_DURATION := 16.0
const AMBIENCE_VOLUME_DB := -15.0
const AMBIENCE_DUCK_DB := -80.0
const AMBIENCE_FADE_OUT_SECONDS := 0.08
const AMBIENCE_FADE_IN_SECONDS := 0.85

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _voice_cursor := 0
var _ambience_player: AudioStreamPlayer
var _ambience_linear := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_buses()
	_build_streams()
	for index in VOICE_COUNT:
		var player := AudioStreamPlayer.new()
		player.name = "SfxVoice%d" % index
		player.bus = SFX_BUS
		add_child(player)
		_players.append(player)
	_start_ambience()


func _process(delta: float) -> void:
	if _ambience_player == null:
		return
	var sfx_playing := false
	for player in _players:
		if player.playing:
			sfx_playing = true
			break
	var target_linear := db_to_linear(AMBIENCE_DUCK_DB if sfx_playing else AMBIENCE_VOLUME_DB)
	var fade_seconds := AMBIENCE_FADE_OUT_SECONDS if sfx_playing else AMBIENCE_FADE_IN_SECONDS
	var fade_speed := db_to_linear(AMBIENCE_VOLUME_DB) / maxf(fade_seconds, 0.001)
	_ambience_linear = move_toward(_ambience_linear, target_linear, delta * fade_speed)
	_ambience_player.volume_db = linear_to_db(maxf(_ambience_linear, 0.0001))


func play_sfx(effect_name: StringName, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	var stream: AudioStreamWAV = _streams.get(effect_name)
	if stream == null or _players.is_empty():
		return
	var player := _next_player()
	player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch_scale, 0.5, 2.0)
	player.play()


func set_sfx_volume(linear_volume: float) -> void:
	var bus_index := AudioServer.get_bus_index(SFX_BUS)
	if bus_index < 0:
		return
	var safe_volume := clampf(linear_volume, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, safe_volume <= 0.001)
	if safe_volume > 0.001:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(safe_volume))


func _next_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	var player := _players[_voice_cursor]
	_voice_cursor = (_voice_cursor + 1) % _players.size()
	return player


func _ensure_audio_buses() -> void:
	_ensure_bus(SFX_BUS)
	_ensure_bus(AMBIENCE_BUS)


func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, bus_name)
	AudioServer.set_bus_send(bus_index, &"Master")


func _start_ambience() -> void:
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.name = "CampAmbience"
	_ambience_player.bus = AMBIENCE_BUS
	_ambience_player.stream = _build_ambience_stream()
	_ambience_player.volume_db = AMBIENCE_DUCK_DB
	add_child(_ambience_player)
	_ambience_player.play()


func _build_ambience_stream() -> AudioStreamWAV:
	var sample_count := ceili(AMBIENCE_DURATION * SAMPLE_RATE)
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	for index in sample_count:
		var progress := float(index) / float(sample_count)
		# Integer-cycle partials make an audible, seamless bed of soft wind.
		var wind := (
			sin(TAU * 1328.0 * progress + 0.4) * 0.34
			+ sin(TAU * 1712.0 * progress + 2.1) * 0.25
			+ sin(TAU * 2224.0 * progress + 4.0) * 0.19
			+ sin(TAU * 2928.0 * progress + 1.3) * 0.14
			+ sin(TAU * 3744.0 * progress + 5.2) * 0.10
			+ sin(TAU * 4912.0 * progress + 3.1) * 0.07
		)
		var breeze_motion := 0.70 + _cyclic_noise(progress, 9, 17.0) * 0.18
		var forest_air := wind * breeze_motion * 0.24
		var low_camp_tone := (
			sin(TAU * 880.0 * progress + 0.8) * 0.022
			+ sin(TAU * 1320.0 * progress + 2.6) * 0.014
		)
		var ember := 0.0
		for ember_at in [0.12, 0.34, 0.57, 0.81]:
			var distance := absf(progress - float(ember_at))
			distance = minf(distance, 1.0 - distance)
			var ember_envelope := exp(-distance * 260.0)
			ember += (_raw_noise(index * 5) * 0.10 + sin(TAU * 6208.0 * progress) * 0.045) * ember_envelope
		var sample := clampf(forest_air + low_camp_tone + ember, -0.55, 0.55)
		pcm.encode_s16(index * 2, int(round(sample * 32767.0)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	stream.data = pcm
	return stream


func _build_streams() -> void:
	_streams[&"ui_select"] = _synthesize(&"ui_select", 0.09)
	_streams[&"ui_confirm"] = _synthesize(&"ui_confirm", 0.24)
	_streams[&"ui_cancel"] = _synthesize(&"ui_cancel", 0.14)
	_streams[&"vote_tally"] = _synthesize(&"vote_tally", 0.42)
	_streams[&"vote_outcome"] = _synthesize(&"vote_outcome", 0.68)
	_streams[&"bell"] = _synthesize(&"bell", 1.45)
	_streams[&"task_action"] = _synthesize(&"task_action", 0.12)
	_streams[&"task_error"] = _synthesize(&"task_error", 0.24)
	_streams[&"task_success"] = _synthesize(&"task_success", 0.62)
	_streams[&"kill_sting"] = _synthesize(&"kill_sting", 0.52)
	_streams[&"killer_confirm"] = _synthesize(&"killer_confirm", 0.48)
	_streams[&"shove"] = _synthesize(&"shove", 0.34)
	_streams[&"impact"] = _synthesize(&"impact", 0.48)
	_streams[&"fire"] = _synthesize(&"fire", 0.90)
	_streams[&"splash"] = _synthesize(&"splash", 0.90)
	_streams[&"tree_crack"] = _synthesize(&"tree_crack", 0.72)
	_streams[&"cart_roll"] = _synthesize(&"cart_roll", 0.72)


func _synthesize(effect_name: StringName, duration: float) -> AudioStreamWAV:
	var sample_count := ceili(duration * SAMPLE_RATE)
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	for index in sample_count:
		var time := float(index) / float(SAMPLE_RATE)
		var progress := float(index) / float(maxi(sample_count - 1, 1))
		var sample := clampf(_sample_effect(effect_name, time, progress, index), -1.0, 1.0)
		pcm.encode_s16(index * 2, int(round(sample * 32767.0)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = pcm
	return stream


func _sample_effect(effect_name: StringName, time: float, progress: float, index: int) -> float:
	var noise := _smooth_noise(index)
	var dry_noise := _raw_noise(index)
	var air_noise := dry_noise - noise
	match effect_name:
		&"ui_select":
			var select_tap := sin(TAU * 245.0 * time) * exp(-38.0 * time) * 0.30
			return select_tap + air_noise * exp(-72.0 * time) * 0.07
		&"ui_confirm":
			var first_tap := sin(TAU * 290.0 * time) * _transient(time, 0.0, 0.004, 30.0)
			var second_time := maxf(0.0, time - 0.105)
			var second_tap := sin(TAU * 390.0 * second_time) * _transient(time, 0.105, 0.004, 28.0)
			return (first_tap + second_tap * 0.88) * 0.20 + air_noise * (_transient(time, 0.0, 0.002, 70.0) + _transient(time, 0.105, 0.002, 70.0)) * 0.04
		&"ui_cancel":
			return (sin(TAU * 175.0 * time) * 0.26 + noise * 0.09) * exp(-28.0 * time)
		&"vote_tally":
			var tally := 0.0
			for beat in [0.0, 0.105, 0.210, 0.315]:
				var local_time := maxf(0.0, time - float(beat))
				tally += (sin(TAU * 310.0 * local_time) * 0.16 + air_noise * 0.035) * _transient(time, float(beat), 0.003, 42.0)
			return tally
		&"vote_outcome":
			var outcome_thump := sin(TAU * lerpf(92.0, 58.0, progress) * time) * exp(-5.2 * time)
			var outcome_air := noise * _envelope(progress, 0.12, 0.35) * 0.11
			return outcome_thump * 0.34 + outcome_air
		&"bell":
			var decay := exp(-2.7 * time)
			var metal := sin(TAU * 612.0 * time) + sin(TAU * 963.0 * time + 0.3) * 0.48 + sin(TAU * 1417.0 * time + 0.8) * 0.23
			var strike := air_noise * _transient(time, 0.0, 0.002, 48.0) * 0.13
			return metal * decay * 0.16 + strike
		&"task_action":
			return (sin(TAU * 330.0 * time) * 0.20 + air_noise * 0.06) * exp(-32.0 * time)
		&"task_error":
			var error_first := sin(TAU * 145.0 * time) * _transient(time, 0.0, 0.004, 24.0)
			var error_time := maxf(0.0, time - 0.11)
			var error_second := sin(TAU * 122.0 * error_time) * _transient(time, 0.11, 0.004, 24.0)
			return (error_first + error_second * 0.82) * 0.22
		&"task_success":
			var success := 0.0
			var notes := [523.25, 659.25, 783.99]
			for note_index in notes.size():
				var note_at: float = float(note_index) * 0.14
				var note_time := maxf(0.0, time - note_at)
				success += sin(TAU * float(notes[note_index]) * note_time) * _transient(time, note_at, 0.012, 8.0)
			return success * 0.12
		&"kill_sting":
			var sting_body := sin(TAU * lerpf(78.0, 46.0, progress) * time) * exp(-3.8 * time)
			var sting_air := noise * _envelope(progress, 0.16, 0.40)
			return sting_body * 0.34 + sting_air * 0.15
		&"killer_confirm":
			var confirm_thump := sin(TAU * lerpf(82.0, 48.0, progress) * time) * exp(-7.0 * time)
			var confirm_sweep := noise * _envelope(progress, 0.10, 0.42)
			return confirm_thump * 0.48 + confirm_sweep * 0.17
		&"shove":
			var shove_body := sin(TAU * lerpf(118.0, 62.0, progress) * time) * exp(-6.0 * time)
			return shove_body * 0.34 + noise * _envelope(progress, 0.08, 0.44) * 0.20
		&"impact":
			var thump := sin(TAU * lerpf(72.0, 42.0, progress) * time) * exp(-8.0 * time)
			var impact_texture := noise * _transient(time, 0.0, 0.003, 18.0)
			return thump * 0.55 + impact_texture * 0.24
		&"fire":
			var crackle := 0.0
			if _raw_noise(index * 7) > 0.90:
				crackle = air_noise * 0.38
			var flame_motion := 0.56 + sin(TAU * 6.0 * time) * 0.16 + sin(TAU * 11.0 * time) * 0.08
			return (noise * flame_motion * 0.31 + crackle) * _envelope(progress, 0.10, 0.34)
		&"splash":
			var water_body := noise * _envelope(progress, 0.025, 0.58)
			var water_drop := sin(TAU * lerpf(180.0, 68.0, progress) * time) * exp(-4.4 * time)
			return water_body * 0.36 + water_drop * 0.16
		&"tree_crack":
			var burst := 0.0
			for beat in [0.01, 0.14, 0.29, 0.43]:
				var distance: float = absf(time - float(beat))
				burst += air_noise * clampf(1.0 - distance / 0.038, 0.0, 1.0)
			var creak := sin(TAU * lerpf(92.0, 47.0, progress) * time) * exp(-2.2 * time)
			return burst * 0.28 + creak * 0.14
		&"cart_roll":
			var wheel_phase := fposmod(time, 0.115) / 0.115
			var wheel_hit := sin(TAU * 78.0 * time) * _envelope(wheel_phase, 0.035, 0.62)
			return (wheel_hit * 0.22 + noise * 0.10) * _envelope(progress, 0.07, 0.22)
	return 0.0


func _envelope(progress: float, attack: float, release: float) -> float:
	var fade_in := clampf(progress / maxf(attack, 0.001), 0.0, 1.0)
	var fade_out := clampf((1.0 - progress) / maxf(release, 0.001), 0.0, 1.0)
	return fade_in * fade_out


func _transient(time: float, at_time: float, attack: float, decay: float) -> float:
	var local_time := time - at_time
	if local_time < 0.0:
		return 0.0
	return clampf(local_time / maxf(attack, 0.0001), 0.0, 1.0) * exp(-local_time * decay)


func _raw_noise(index: int) -> float:
	return fposmod(sin(float(index) * 12.9898) * 43758.5453, 1.0) * 2.0 - 1.0


func _smooth_noise(index: int) -> float:
	return (_raw_noise(index) + _raw_noise(index - 1) + _raw_noise(index - 2) + _raw_noise(index - 3)) * 0.25


func _cyclic_noise(progress: float, cells: int, seed: float) -> float:
	var position := progress * float(cells)
	var cell := floori(position)
	var blend := position - float(cell)
	blend = blend * blend * (3.0 - 2.0 * blend)
	var first_index := posmod(cell, cells)
	var second_index := posmod(cell + 1, cells)
	var first := fposmod(sin((float(first_index) + seed) * 12.9898) * 43758.5453, 1.0) * 2.0 - 1.0
	var second := fposmod(sin((float(second_index) + seed) * 12.9898) * 43758.5453, 1.0) * 2.0 - 1.0
	return lerpf(first, second, blend)
