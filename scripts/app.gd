extends Node

const NetworkSessionScript = preload("res://scripts/network_session.gd")
const LobbyUIScript = preload("res://scripts/lobby_ui.gd")
const MultiplayerGameScript = preload("res://scripts/multiplayer_game.gd")
const CampPreviewScript = preload("res://scripts/camp_game.gd")
const EosLobbyClientScript = preload("res://scripts/eos_lobby_client.gd")

var session: Node
var lobby_ui: CanvasLayer
var eos_lobby: Node
var pending_name := "Camper"
var pending_color := 0
var cli: Dictionary = {}
var auto_start_sent := false
var test_movement_active := false
var test_start_position := Vector2.INF
var eos_profile_port_guard: TCPServer
var eos_profile_slot := 1


func _ready() -> void:
	cli = _parse_cli(OS.get_cmdline_user_args())
	_claim_eos_instance_profile()
	HAuth.rotate_device_id_before_anonymous_login = eos_profile_slot > 1
	session = NetworkSessionScript.new()
	session.name = "NetworkSession"
	session.force_killer_for_testing = OS.is_debug_build() and (
		cli.has("force-killer") or OS.get_executable_path().get_file().begins_with("DoubleTake_Killer_Test")
	)
	# The shareable playtest exports use this feature so their room host can
	# inspect the Camper experience without being randomly assigned the Killer.
	session.force_camper_for_testing = OS.has_feature("camper_test") or cli.has("force-camper")
	add_child(session)
	session.status_changed.connect(_on_status)
	session.join_succeeded.connect(_on_join_succeeded)
	session.join_failed.connect(_on_join_failed)
	session.lobby_state_changed.connect(_on_lobby_state)
	session.match_started.connect(_on_match_started)
	session.snapshot_received.connect(_on_test_snapshot)
	session.color_change_failed.connect(_on_color_change_failed)
	session.match_returned_to_lobby.connect(_on_match_returned_to_lobby)
	session.session_disconnected.connect(_on_session_disconnected)
	if cli.has("server"):
		_start_dedicated_server()
		return
	if cli.has("lan-host"):
		_start_cli_lan_host()
		return
	if cli.has("address") and cli.has("token"):
		_start_cli_client()
		return
	_build_client_ui()
	if cli.has("eos-create"):
		call_deferred("_create_room", str(cli.get("name", "Host")), int(cli.get("color", "0")))
	elif cli.has("eos-join"):
		call_deferred("_join_room", str(cli.get("eos-join", "")), str(cli.get("name", "Camper")), int(cli.get("color", "0")))


func _exit_tree() -> void:
	if eos_profile_port_guard != null:
		eos_profile_port_guard.stop()


func _claim_eos_instance_profile() -> void:
	var profiles_root := ProjectSettings.globalize_path("user://eos-instance-profiles")
	DirAccess.make_dir_recursive_absolute(profiles_root)
	for slot in range(1, 33):
		# Holding a loopback TCP port is an OS-level, crash-safe, cross-process
		# lock. It prevents two game windows from ever selecting the same cache.
		var guard := TCPServer.new()
		if guard.listen(43100 + slot, "127.0.0.1") != OK:
			continue
		eos_profile_port_guard = guard
		eos_profile_slot = slot
		HPlatform.cache_directory = profiles_root.path_join("slot_%02d" % slot)
		DirAccess.make_dir_recursive_absolute(HPlatform.cache_directory)
		print("EOS_INSTANCE_PROFILE slot=%d pid=%d" % [slot, OS.get_process_id()])
		return
	# This is only a safety fallback if more than 32 copies are opened at once.
	HPlatform.cache_directory = profiles_root.path_join("pid_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(HPlatform.cache_directory)


func _start_dedicated_server() -> void:
	var port := int(cli.get("port", "7200"))
	var code := str(cli.get("code", "LOCAL1")).to_upper()
	var secret := str(cli.get("room-secret", OS.get_environment("DOUBLE_TAKE_ROOM_SECRET")))
	if secret.is_empty():
		secret = "dev"
	var required := int(cli.get("minimum-players", "4"))
	session.preferred_camper_player_id = str(cli.get("prefer-camper", "")).strip_edges()
	session.shutdown_when_empty = cli.has("shutdown-when-empty")
	var error: int = session.start_server(port, code, secret, required)
	if error != OK:
		get_tree().quit(error)
	else:
		print("PHASE2_SERVER_READY code=%s port=%d" % [code, port])


func _start_cli_client() -> void:
	pending_name = str(cli.get("name", "Camper"))
	pending_color = int(cli.get("color", "0"))
	var error: int = session.connect_to_server(
		str(cli.get("address", "127.0.0.1")),
		int(cli.get("port", "7200")),
		str(cli.get("token", "")),
		pending_name,
		pending_color
	)
	if error != OK:
		get_tree().quit(error)


func _start_cli_lan_host() -> void:
	pending_name = str(cli.get("name", "Local Host"))
	pending_color = int(cli.get("color", "0"))
	var player_id := str(cli.get("player-id", "local-host"))
	var required := int(cli.get("minimum-players", "4"))
	var error: int = session.start_lan_host("127.0.0.1", player_id, pending_name, pending_color, required)
	if error != OK:
		get_tree().quit(error)


func _build_client_ui() -> void:
	lobby_ui = LobbyUIScript.new()
	lobby_ui.allow_test_bots = true
	lobby_ui.allow_role_picker = true
	lobby_ui.allow_lan_test = true
	add_child(lobby_ui)
	lobby_ui.setup_chat(session)
	lobby_ui.create_requested.connect(_create_room)
	lobby_ui.create_lan_requested.connect(_create_lan_room)
	lobby_ui.join_requested.connect(_join_room)
	lobby_ui.lan_join_requested.connect(_join_lan_test)
	lobby_ui.ready_requested.connect(session.set_ready)
	lobby_ui.start_requested.connect(session.request_match_start)
	lobby_ui.settings_requested.connect(session.update_settings)
	lobby_ui.test_bots_requested.connect(session.set_test_bots)
	lobby_ui.color_requested.connect(session.request_color)
	lobby_ui.customization_requested.connect(session.set_customization)
	lobby_ui.leave_requested.connect(_leave_lobby)
	lobby_ui.quit_requested.connect(_quit_game)
	lobby_ui.offline_preview_requested.connect(_open_offline_preview)
	eos_lobby = EosLobbyClientScript.new()
	add_child(eos_lobby)
	eos_lobby.status_changed.connect(_on_status)
	eos_lobby.failed.connect(_on_eos_lobby_failed)
	eos_lobby.room_code_ready.connect(func(code: String) -> void: _on_status("Room %s created. Share this code." % code))


func _create_room(display_name: String, color_index: int) -> void:
	pending_name = _clean_name(display_name)
	pending_color = color_index
	ProjectSettings.set_setting("double_take/player_name", pending_name)
	eos_lobby.create_room(session, pending_name, pending_color)


func _create_lan_room(display_name: String, color_index: int) -> void:
	pending_name = _clean_name(display_name)
	pending_color = color_index
	ProjectSettings.set_setting("double_take/player_name", pending_name)
	var address := _best_lan_address()
	var player_id := "lan-host-" + str(Time.get_ticks_msec()) + "-" + str(randi_range(1000, 9999))
	var error: int = session.start_lan_host(address, player_id, pending_name, pending_color, 2)
	if error != OK:
		_on_eos_lobby_failed("Could not create the Local Wi-Fi lobby. Close other hosts and try again.")


func _join_room(code: String, display_name: String, color_index: int) -> void:
	pending_name = _clean_name(display_name)
	pending_color = color_index
	ProjectSettings.set_setting("double_take/player_name", pending_name)
	eos_lobby.join_room(session, code, pending_name, pending_color)


func _join_lan_test(address: String, display_name: String, color_index: int) -> void:
	var host := address.strip_edges().trim_prefix("http://").trim_prefix("https://").trim_suffix("/")
	if host.is_empty() or host.length() > 64:
		_on_eos_lobby_failed("Enter the PC's Wi-Fi IPv4 address, for example 192.168.1.25.")
		return
	pending_name = _clean_name(display_name)
	pending_color = color_index
	var player_id := "lan-" + str(Time.get_unix_time_from_system()) + "-" + str(randi_range(1000, 9999))
	var error: int = session.connect_to_server(host, 7200, "dev:%s:guest" % player_id, pending_name, pending_color)
	if error != OK:
		_on_eos_lobby_failed("Could not reach the PC LAN host. Check that both devices are on the same Wi-Fi.")


func _best_lan_address() -> String:
	var ipv4_fallback := "127.0.0.1"
	for address: String in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127."):
			continue
		ipv4_fallback = address
		if address.begins_with("192.168.") or address.begins_with("10."):
			return address
		var parts := address.split(".")
		if parts.size() == 4 and parts[0] == "172" and int(parts[1]) >= 16 and int(parts[1]) <= 31:
			return address
	return ipv4_fallback


func _on_join_succeeded(state: Dictionary) -> void:
	print("PHASE2_JOINED player=%s room=%s" % [pending_name, state.get("room_code", "")])
	if is_instance_valid(lobby_ui):
		lobby_ui.show_lobby(session.local_player_id, state, pending_color)
	if cli.has("auto-ready"):
		session.set_ready(true)
	if cli.has("test-exit-after-lobby-delay"):
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)


func _on_join_failed(message: String) -> void:
	push_error(message)
	if session.connection_failure_emitted:
		# A terminal transport failure (during first join or after reconnects are
		# exhausted) returns to the same simple code-entry screen and releases EOS.
		session.disconnect_session()
		if is_instance_valid(lobby_ui):
			lobby_ui.show_menu(message)
		else:
			get_tree().quit(2)
		return
	if is_instance_valid(lobby_ui):
		lobby_ui.set_status(message, true)
	else:
		get_tree().quit(2)


func _on_lobby_state(state: Dictionary) -> void:
	if is_instance_valid(lobby_ui):
		lobby_ui.update_lobby(state)
	if cli.has("auto-start") and not auto_start_sent and _local_is_host(state) and _all_ready(state):
		auto_start_sent = true
		session.request_match_start()
	if cli.has("test-host-transfer") and _local_is_host(state):
		print("PHASE2_HOST_TRANSFERRED player=%s" % pending_name)
		get_tree().quit(0)


func _on_color_change_failed(message: String) -> void:
	if is_instance_valid(lobby_ui):
		lobby_ui.set_color_notice(message, true)


func _on_match_started(role: String, state: Dictionary) -> void:
	print("PHASE2_MATCH_STARTED player=%s role=%s players=%d" % [pending_name, role, state.get("players", []).size()])
	if cli.has("test-exit-on-match"):
		await get_tree().process_frame
		get_tree().quit(0)
		return
	if cli.has("test-movement"):
		test_movement_active = true
		return
	if is_instance_valid(lobby_ui):
		lobby_ui.visible = false
	var old_game := get_node_or_null("MultiplayerCamp")
	if is_instance_valid(old_game):
		old_game.queue_free()
	await _show_role_reveal(role)
	var game := MultiplayerGameScript.new()
	game.name = "MultiplayerCamp"
	game.session = session
	game.initial_state = state
	add_child(game)


func _on_match_returned_to_lobby() -> void:
	var old_game := get_node_or_null("MultiplayerCamp")
	if is_instance_valid(old_game):
		old_game.queue_free()
	if is_instance_valid(lobby_ui):
		lobby_ui.visible = true
		lobby_ui.update_lobby(session.current_lobby_state)
		lobby_ui.set_status("Returned to lobby.")


func _on_session_disconnected() -> void:
	var old_game := get_node_or_null("MultiplayerCamp")
	if is_instance_valid(old_game):
		old_game.queue_free()
	if is_instance_valid(eos_lobby):
		eos_lobby.leave_room()
	if is_instance_valid(lobby_ui):
		lobby_ui.visible = true
		lobby_ui.show_menu("Left the room.")


func _physics_process(_delta: float) -> void:
	if test_movement_active:
		session.send_movement(Vector2.RIGHT, false)


func _on_test_snapshot(snapshot: Dictionary) -> void:
	if not test_movement_active:
		return
	var positions: Dictionary = snapshot.get("positions", {})
	if not positions.has(session.local_player_id):
		return
	var current: Vector2 = positions[session.local_player_id]
	if test_start_position == Vector2.INF:
		test_start_position = current
	elif current.x > test_start_position.x + 20.0:
		print("PHASE2_MOVEMENT_SYNCED player=%s distance=%.1f" % [pending_name, current.x - test_start_position.x])
		test_movement_active = false
		get_tree().quit(0)


func _show_role_reveal(role: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var backdrop := ColorRect.new()
	backdrop.color = Color("#081918", 0.96)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)
	var label := Label.new()
	label.text = "YOU ARE THE\n" + role.to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 42)
	label.add_theme_color_override("font_color", Color("#e63946") if role == "Killer" else Color("#a7c957"))
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(label)
	await get_tree().create_timer(2.4).timeout
	layer.queue_free()


func _leave_lobby() -> void:
	# disconnect_session emits the one player-departure event that owns both EOS
	# lobby cleanup and the return to the menu. Keeping this single path prevents
	# duplicate asynchronous leave calls.
	session.disconnect_session()


func _quit_game() -> void:
	session.disconnect_session()
	get_tree().quit(0)


func _open_offline_preview() -> void:
	if is_instance_valid(lobby_ui):
		lobby_ui.queue_free()
	var preview := CampPreviewScript.new()
	preview.name = "OfflineCampPreview"
	add_child(preview)


func _on_status(message: String) -> void:
	print(message)
	if is_instance_valid(lobby_ui):
		lobby_ui.set_status(message)


func _on_eos_lobby_failed(message: String) -> void:
	if is_instance_valid(lobby_ui):
		lobby_ui.set_status(message, true)


func _local_is_host(state: Dictionary) -> bool:
	for player: Dictionary in state.get("players", []):
		if player.get("player_id", "") == session.local_player_id:
			return bool(player.get("host", false))
	return false


func _all_ready(state: Dictionary) -> bool:
	var connected := 0
	for player: Dictionary in state.get("players", []):
		if player.get("connected", false):
			connected += 1
			if not player.get("ready", false):
				return false
	return connected >= int(state.get("minimum_players", 4))


func _parse_cli(arguments: PackedStringArray) -> Dictionary:
	var parsed := {}
	for argument in arguments:
		if not argument.begins_with("--"):
			continue
		var item := argument.trim_prefix("--")
		var separator := item.find("=")
		if separator == -1:
			parsed[item] = true
		else:
			parsed[item.left(separator)] = item.substr(separator + 1)
	return parsed


func _clean_name(value: String) -> String:
	var cleaned := value.strip_edges()
	return ("Camper" if cleaned.is_empty() else cleaned).left(18)
