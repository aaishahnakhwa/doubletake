extends Node

signal status_changed(message: String)
signal join_succeeded(state: Dictionary)
signal join_failed(message: String)
signal lobby_state_changed(state: Dictionary)
signal match_started(role: String, state: Dictionary)
signal snapshot_received(snapshot: Dictionary)
signal server_started(port: int, code: String)
signal task_begin_approved(task_id: String)
signal task_state_received(state: Dictionary)
signal task_action_failed(message: String)
signal match_ended(winner: String, reason: String, outcome: Dictionary)
signal match_returned_to_lobby
signal player_rematch_ready(player_id: String, ready: bool)
signal phase4_state_received(state: Dictionary)
signal phase4_action_failed(message: String)
signal body_reported(body: Dictionary)
signal meeting_started(meeting: Dictionary)
signal meeting_ended
signal player_voted(voter_id: String)
signal voting_results_received(results: Dictionary)
signal eos_membership_refresh_requested
signal color_change_failed(message: String)
signal chat_message_received(message: Dictionary)
signal chat_action_failed(message: String)
signal session_disconnected

const WorldScript = preload("res://scripts/camp_world.gd")
const ServerPlayerScript = preload("res://scripts/server_player.gd")
const TaskCatalog = preload("res://scripts/task_catalog.gd")
const CustomizationCatalog = preload("res://scripts/customization_catalog.gd")
const MAX_PLAYERS := 6
const RECONNECT_SECONDS := 60.0
const SNAPSHOT_INTERVAL := 0.05
const SPAWN_NODES := [0, 1, 2, 3, 4, 5, 6, 7, 13, 14]
const EOS_SOCKET_ID := "DoubleTakeP2PV1"
const TASKS_PER_CAMPER := 5
const GUARANTEED_TASK_ID := "lanterns"
const TASK_RADIUS := 125.0
const KILL_RADIUS := 118.0
const KILL_COOLDOWN_SECONDS := 8.0
const SABOTAGE_RADIUS := 130.0
const SABOTAGE_DURATION_SECONDS := 42.0
const SABOTAGE_OBJECTIVES_PER_KILLER := 2
const SABOTAGES := [
	{"id": "generator", "name": "Generator blackout", "station": "Camp Generator", "effect": "Camp lights are out"},
	{"id": "radio", "name": "Radio jam", "station": "Office Radio", "effect": "Radio signal is jammed"},
	{"id": "supplies", "name": "Hide supplies", "station": "Supply Shelves", "effect": "Supplies are hidden"},
	{"id": "lanterns", "name": "Douse lanterns", "station": "Lodge Lantern", "effect": "Lanterns are out"}
]
const EOS_CONNECT_TIMEOUT := 8.0
const EOS_CONNECT_MAX_ATTEMPTS := 3
const EOS_JOIN_RESPONSE_TIMEOUT := 30.0
const EOS_JOIN_RETRY_SECONDS := 1.0
const EOS_JOIN_MAX_ATTEMPTS := 8
const EOS_MEMBERSHIP_GRACE_SECONDS := 0.5
const TEST_BOT_PREFIX := "test-bot-"

var is_server := false
var room_code := ""
var room_secret := ""
var minimum_players := 2
var local_token := ""
var local_name := ""
var local_color := 0
var local_player_id := ""
var local_role := ""
var current_lobby_state: Dictionary = {}
var players: Dictionary = {}
var peer_to_player: Dictionary = {}
var match_running := false
var server_world: Node2D
var server_bodies: Dictionary = {}
var snapshot_elapsed := 0.0
var server_address := ""
var server_port := 0
var reconnecting := false
var reconnect_deadline := 0.0
var next_reconnect_attempt := 0.0
var manual_disconnect := false
var current_match_state: Dictionary = {}
var is_eos_p2p := false
var meeting_active := false
var current_meeting_data: Dictionary = {}
var votes: Dictionary = {}
var voting_results: Dictionary = {}
var eos_allowed_player_ids: Dictionary = {}
var eos_connect_started_at := 0.0
var eos_join_request_started_at := 0.0
var eos_last_join_request_at := 0.0
var eos_join_attempts := 0
var eos_connect_attempts := 0
var eos_connect_retrying := false
var pending_eos_joins: Dictionary = {}
var has_joined_session := false
var transport_events_armed := false
var connection_failure_emitted := false
var shared_tasks_completed := 0
var shared_tasks_total := 0
var kill_cooldown_until := 0.0
var sabotage_state: Dictionary = {}
var bodies: Dictionary = {}
# Debug-only launch option used for offline/solo Phase 4 verification.
var force_killer_for_testing := false
# Playtest option: keep the room host on the Camper side when another player
# (including a test bot) is available to take the Killer role.
var force_camper_for_testing := false
# Used only by the local same-PC test launcher. A normal EOS room leaves this
# empty and still assigns roles randomly.
var preferred_camper_player_id := ""
var shutdown_when_empty := false
var server_had_connected_player := false
var last_match_outcome: Dictionary = {}
var chat_history: Array[Dictionary] = []


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func start_server(port: int, code: String, secret: String, required_players: int = 4) -> Error:
	_reset_session_state()
	is_server = true
	is_eos_p2p = false
	manual_disconnect = false
	room_code = code.to_upper()
	room_secret = secret
	minimum_players = clampi(required_players, 1, MAX_PLAYERS)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		status_changed.emit("Could not start server on UDP %d: %s" % [port, error_string(error)])
		return error
	multiplayer.multiplayer_peer = peer
	_create_server_world()
	status_changed.emit("Authoritative server ready for room %s on UDP %d" % [room_code, port])
	server_started.emit(port, room_code)
	return OK


func start_eos_host(code: String, player_id: String, display_name: String, color_index: int, allowed_player_ids: Array[String], required_players: int = 2):
	_reset_session_state()
	is_server = true
	is_eos_p2p = true
	manual_disconnect = false
	room_code = code.to_upper()
	room_secret = ""
	minimum_players = clampi(required_players, 1, MAX_PLAYERS)
	local_player_id = player_id
	local_name = _clean_name(display_name)
	local_color = clampi(color_index, 0, 5)
	set_eos_allowed_player_ids(allowed_player_ids)
	var peer := EOSGMultiplayerPeer.new()
	var error := peer.create_server(EOS_SOCKET_ID)
	if error != OK:
		status_changed.emit("Could not start the EOS P2P host: " + error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	_create_server_world()
	players[player_id] = {
		"player_id": player_id,
		"peer_id": 1,
		"name": local_name,
		"color": local_color,
		"hat": "none",
		"outfit": "none",
		"ready": false,
		"host": true,
		"connected": true,
		"reconnect_deadline": 0.0,
		"role": "Camper"
	}
	peer_to_player[1] = player_id
	status_changed.emit("Internet host ready for room %s." % room_code)
	call_deferred("_emit_local_eos_join")
	return OK


func start_lan_host(address_label: String, player_id: String, display_name: String, color_index: int, required_players: int = 2) -> Error:
	_reset_session_state()
	is_server = true
	is_eos_p2p = false
	manual_disconnect = false
	room_code = address_label
	room_secret = "dev"
	minimum_players = clampi(required_players, 1, MAX_PLAYERS)
	local_player_id = player_id
	local_name = _clean_name(display_name)
	local_color = clampi(color_index, 0, 5)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(7200, MAX_PLAYERS)
	if error != OK:
		status_changed.emit("Could not create the Local Wi-Fi lobby on UDP 7200: " + error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	_create_server_world()
	players[player_id] = {
		"player_id": player_id,
		"peer_id": 1,
		"name": local_name,
		"color": local_color,
		"look": "classic",
		"hat": "classic",
		"outfit": "none",
		"ready": false,
		"host": true,
		"connected": true,
		"reconnect_deadline": 0.0,
		"role": "Camper"
	}
	peer_to_player[1] = player_id
	status_changed.emit("Local Wi-Fi host ready at %s:7200." % address_label)
	call_deferred("_emit_local_eos_join")
	return OK


func connect_to_eos_host(host_product_user_id: String, player_id: String, display_name: String, color_index: int):
	_reset_session_state()
	is_server = false
	is_eos_p2p = true
	manual_disconnect = false
	server_address = host_product_user_id
	server_port = 0
	local_token = "eos:" + player_id
	local_player_id = player_id
	local_name = _clean_name(display_name)
	local_color = clampi(color_index, 0, 5)
	eos_connect_attempts = 0
	return _open_eos_client_connection()


func _open_eos_client_connection() -> int:
	transport_events_armed = false
	var peer := EOSGMultiplayerPeer.new()
	var error := peer.create_client(EOS_SOCKET_ID, server_address)
	if error != OK:
		return int(error)
	multiplayer.multiplayer_peer = peer
	eos_connect_attempts += 1
	eos_connect_started_at = Time.get_unix_time_from_system()
	_arm_transport_events()
	status_changed.emit("Connecting through internet P2P…")
	return int(OK)


func set_eos_allowed_player_ids(player_ids: Array[String]) -> void:
	for player_id in player_ids:
		if not player_id.is_empty():
			eos_allowed_player_ids[player_id] = true
	if is_server and is_eos_p2p:
		var now := Time.get_unix_time_from_system()
		var to_purge: Array[String] = []
		for p_id: String in players:
			if p_id == local_player_id or bool(players[p_id].get("bot", false)):
				continue
			var record: Dictionary = players[p_id]
			# Only purge players who are marked disconnected AND past their reconnect deadline
			if not bool(record.get("connected", false)) and not match_running:
				var deadline := float(record.get("reconnect_deadline", 0.0))
				if deadline > 0.0 and now >= deadline and not eos_allowed_player_ids.has(p_id):
					to_purge.append(p_id)
		for p_id in to_purge:
			_remove_player(p_id)
		if not to_purge.is_empty() and not match_running:
			_assign_host_if_needed()
			_broadcast_lobby_state()
		if not pending_eos_joins.is_empty():
			_process_pending_eos_joins(now)


func connect_to_server(address: String, port: int, token: String, display_name: String, color_index: int) -> Error:
	_reset_session_state()
	is_server = false
	is_eos_p2p = false
	manual_disconnect = false
	server_address = address
	server_port = port
	local_token = token
	local_name = _clean_name(display_name)
	local_color = clampi(color_index, 0, 5)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		join_failed.emit("Could not connect: " + error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	_arm_transport_events()
	status_changed.emit("Connecting to %s:%d…" % [address, port])
	return OK


func disconnect_session() -> void:
	_reset_session_state()
	session_disconnected.emit()


## Clears only gameplay transport/state. Starting a host or client must not emit
## session_disconnected: App treats that signal as an explicit request to leave
## the EOS lobby, which would invalidate a room during its own setup.
func _reset_session_state() -> void:
	manual_disconnect = true
	transport_events_armed = false
	reconnecting = false
	has_joined_session = false
	connection_failure_emitted = false
	eos_connect_started_at = 0.0
	eos_join_request_started_at = 0.0
	eos_last_join_request_at = 0.0
	eos_join_attempts = 0
	eos_connect_attempts = 0
	eos_connect_retrying = false
	pending_eos_joins.clear()
	if multiplayer != null:
		if multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	peer_to_player.clear()
	server_bodies.clear()
	match_running = false
	shared_tasks_completed = 0
	shared_tasks_total = 0
	kill_cooldown_until = 0.0
	sabotage_state.clear()
	bodies.clear()
	current_match_state.clear()
	current_lobby_state.clear()
	eos_allowed_player_ids.clear()
	if is_instance_valid(server_world):
		server_world.queue_free()
	server_world = null
	local_player_id = ""
	local_role = ""
	local_token = ""
	server_address = ""
	server_port = 0
	is_server = false
	is_eos_p2p = false


func _arm_transport_events() -> void:
	if not manual_disconnect and not is_server and multiplayer.multiplayer_peer != null:
		transport_events_armed = true


func set_ready(ready: bool) -> void:
	if is_server and not local_player_id.is_empty():
		_set_ready_for_player(local_player_id, ready)
	elif _is_client_connected():
		rpc_set_ready.rpc_id(1, ready)


func request_color(color_index: int) -> void:
	if is_server and not local_player_id.is_empty():
		_set_color_for_player(local_player_id, color_index)
	elif _is_client_connected():
		request_color_change.rpc_id(1, color_index)


func update_settings(settings: Dictionary) -> void:
	if is_server and not local_player_id.is_empty():
		_update_settings_for_player(local_player_id, settings)
	elif _is_client_connected():
		request_settings.rpc_id(1, settings)


func request_match_start() -> void:
	if is_server and not local_player_id.is_empty():
		_request_start_for_player(local_player_id)
	elif _is_client_connected():
		request_start_match.rpc_id(1)


func request_rematch() -> void:
	if is_server and not local_player_id.is_empty():
		_rematch_for_player(local_player_id)
	elif _is_client_connected():
		rpc_request_rematch.rpc_id(1)


func request_return_to_lobby() -> void:
	if is_server and not local_player_id.is_empty():
		_return_to_lobby_for_player(local_player_id)
	elif _is_client_connected():
		rpc_request_return_to_lobby.rpc_id(1)


func set_rematch_ready(ready: bool) -> void:
	if is_server:
		player_rematch_ready.emit(local_player_id, ready)
	elif _is_client_connected():
		rpc_set_rematch_ready.rpc_id(1, ready)


func set_test_bots(enabled: bool) -> void:
	if is_server and not local_player_id.is_empty():
		_set_test_bots_for_player(local_player_id, enabled)
	elif _is_client_connected():
		request_test_bots.rpc_id(1, enabled)


func send_movement(direction: Vector2, sprinting: bool) -> void:
	if is_server and not local_player_id.is_empty():
		_apply_input(local_player_id, direction, sprinting)
	elif _is_client_connected():
		submit_input.rpc_id(1, direction.limit_length(1.0), sprinting)


func begin_task(task_id: String) -> void:
	if is_server and not local_player_id.is_empty():
		_begin_task_for_player(local_player_id, task_id)
	elif _is_client_connected():
		request_begin_task.rpc_id(1, task_id)


func complete_task(task_id: String) -> void:
	if is_server and not local_player_id.is_empty():
		_complete_task_for_player(local_player_id, task_id)
	elif _is_client_connected():
		request_complete_task.rpc_id(1, task_id)


func request_kill() -> void:
	if is_server and not local_player_id.is_empty():
		_kill_nearest_for_player(local_player_id)
	elif _is_client_connected():
		request_kill_nearby.rpc_id(1)


func request_sabotage(sabotage_id: String) -> void:
	if is_server and not local_player_id.is_empty():
		_start_sabotage_for_player(local_player_id, sabotage_id)
	elif _is_client_connected():
		request_start_sabotage.rpc_id(1, sabotage_id)


func request_repair(sabotage_id: String) -> void:
	if is_server and not local_player_id.is_empty():
		_repair_sabotage_for_player(local_player_id, sabotage_id)
	elif _is_client_connected():
		request_repair_sabotage.rpc_id(1, sabotage_id)


func report_nearby_body() -> void:
	if is_server and not local_player_id.is_empty():
		_report_nearby_body_for_player(local_player_id)
	elif _is_client_connected():
		request_report_nearby_body.rpc_id(1)


func request_emergency_meeting() -> void:
	if is_server and not local_player_id.is_empty():
		_start_emergency_meeting_for_player(local_player_id)
	elif _is_client_connected():
		rpc_request_emergency_meeting.rpc_id(1)


func request_end_meeting() -> void:
	if is_server:
		_end_meeting()
	elif _is_client_connected():
		rpc_request_end_meeting.rpc_id(1)


func cast_vote(target_id: String) -> void:
	if is_server:
		_record_vote(local_player_id, target_id)
	elif _is_client_connected():
		rpc_cast_vote.rpc_id(1, target_id)


func send_chat(text: String) -> void:
	if is_server:
		_process_chat_message(local_player_id, text)
	elif _is_client_connected():
		rpc_send_chat.rpc_id(1, text)



func _emit_local_eos_join() -> void:
	has_joined_session = true
	current_lobby_state = _make_lobby_state()
	join_succeeded.emit(current_lobby_state)


func _process(_delta: float) -> void:
	if not is_server:
		_process_reconnect()
		_process_eos_connection()
		return
	var now := Time.get_unix_time_from_system()
	_process_sabotage_expiry(now)
	_process_pending_eos_joins(now)
	var expired: Array[String] = []
	for player_id: String in players:
		var record: Dictionary = players[player_id]
		if not record["connected"] and float(record.get("reconnect_deadline", now + 1.0)) <= now:
			expired.append(player_id)
	for player_id in expired:
		_remove_player(player_id)
	if not expired.is_empty() and not match_running:
		_assign_host_if_needed()
		_broadcast_lobby_state()
	if shutdown_when_empty and server_had_connected_player and _connected_players().is_empty():
		get_tree().quit()


func _physics_process(delta: float) -> void:
	if not is_server or not match_running:
		return
	snapshot_elapsed += delta
	if snapshot_elapsed < SNAPSHOT_INTERVAL:
		return
	snapshot_elapsed = 0.0
	var positions := {}
	for player_id: String in server_bodies:
		var body: CharacterBody2D = server_bodies[player_id]
		positions[player_id] = body.global_position
	var snapshot := {"positions": positions, "server_time": Time.get_ticks_msec()}
	if not local_player_id.is_empty():
		snapshot_received.emit(snapshot)
	var connected_peers := multiplayer.get_peers()
	for record: Dictionary in _connected_players():
		var peer_id := int(record["peer_id"])
		if peer_id == 1:
			continue
		if peer_id in connected_peers:
			receive_snapshot.rpc_id(peer_id, snapshot)


static func log_network_event(event_text: String) -> void:
	var msg := "[NET_DEBUG %s] %s" % [Time.get_datetime_string_from_system(), event_text]
	print(msg)
	var file := FileAccess.open("user://network_debug.log", FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open("user://network_debug.log", FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(msg)
		file.close()


func _on_connected_to_server() -> void:
	log_network_event("CONNECTED_TO_SERVER player=" + local_player_id)
	if is_server or manual_disconnect or not transport_events_armed:
		return
	reconnecting = false
	connection_failure_emitted = false
	eos_connect_started_at = 0.0
	eos_connect_attempts = 0
	eos_join_request_started_at = Time.get_unix_time_from_system() if is_eos_p2p else 0.0
	status_changed.emit("Connected. Joining room…")
	if is_eos_p2p:
		eos_join_attempts = 0
		eos_last_join_request_at = 0.0
		_send_eos_join_request()
	else:
		join_request.rpc_id(1, local_token, local_name, local_color)


func _send_eos_join_request() -> void:
	if not is_eos_p2p or multiplayer.multiplayer_peer == null:
		return
	eos_join_attempts += 1
	eos_last_join_request_at = Time.get_unix_time_from_system()
	join_request.rpc_id(1, local_token, local_name, local_color)


func _on_connection_failed() -> void:
	log_network_event("CONNECTION_FAILED")
	if is_server or manual_disconnect or not transport_events_armed:
		return
	transport_events_armed = false
	if eos_connect_retrying:
		return
	if reconnecting:
		next_reconnect_attempt = Time.get_unix_time_from_system() + 2.0
		status_changed.emit("Reconnect attempt failed; retrying…")
	elif is_eos_p2p and eos_connect_attempts < EOS_CONNECT_MAX_ATTEMPTS:
		_schedule_eos_connect_retry()
	else:
		_fail_connection("Connection failed after %d attempts. Ask the host to keep the lobby open, then try again." % maxi(eos_connect_attempts, 1))


func _on_server_disconnected() -> void:
	log_network_event("SERVER_DISCONNECTED player=" + local_player_id)
	if is_server or manual_disconnect or not transport_events_armed:
		return
	transport_events_armed = false
	if eos_connect_retrying:
		return
	if local_token.is_empty():
		_fail_connection("Disconnected from the room server.")
		return
	if not has_joined_session:
		if is_eos_p2p and eos_connect_attempts < EOS_CONNECT_MAX_ATTEMPTS:
			_schedule_eos_connect_retry()
		else:
			_fail_connection("Could not reach the room host. Keep the host lobby open and try the code again.")
		return
	reconnecting = true
	reconnect_deadline = Time.get_unix_time_from_system() + RECONNECT_SECONDS
	next_reconnect_attempt = Time.get_unix_time_from_system() + 1.0
	status_changed.emit("Connection lost. Reconnecting for up to 60 seconds…")


func _on_peer_connected(peer_id: int) -> void:
	log_network_event("PEER_CONNECTED peer=" + str(peer_id))
	if is_server and is_eos_p2p:
		eos_membership_refresh_requested.emit()


func _on_peer_disconnected(peer_id: int) -> void:
	log_network_event("PEER_DISCONNECTED peer=" + str(peer_id))
	pending_eos_joins.erase(peer_id)
	if not is_server or not peer_to_player.has(peer_id):
		return
	var player_id: String = peer_to_player[peer_id]
	peer_to_player.erase(peer_id)
	if not players.has(player_id):
		return
	var record: Dictionary = players[player_id]
	record["connected"] = false
	record["peer_id"] = 0
	record["ready"] = false
	if is_eos_p2p and not match_running:
		record["reconnect_deadline"] = Time.get_unix_time_from_system() + EOS_MEMBERSHIP_GRACE_SECONDS
	else:
		record["reconnect_deadline"] = Time.get_unix_time_from_system() + RECONNECT_SECONDS
	players[player_id] = record
	if server_bodies.has(player_id):
		server_bodies[player_id].move_input = Vector2.ZERO
		server_bodies[player_id].sprinting = false
	_assign_host_if_needed()
	if is_eos_p2p:
		eos_membership_refresh_requested.emit()
	if not match_running:
		_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable")
func join_request(token: String, display_name: String, color_index: int) -> void:
	if not is_server:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var claims := _validate_token(token)
	if claims.is_empty():
		_reject_join(peer_id, "Invalid or expired room token.")
		return
	var player_id: String = str(claims.get("player_id", ""))
	if player_id.is_empty():
		_reject_join(peer_id, "Token has no player identity.")
		return
	if is_eos_p2p and not eos_allowed_player_ids.has(player_id):
		# _validate_token matched the claimed Product User ID against the identity
		# authenticated by the EOS P2P peer. Lobby membership notifications are
		# eventually consistent, so they must not reject that authenticated peer.
		eos_allowed_player_ids[player_id] = true
	_accept_join_request(peer_id, claims, display_name, color_index)


func _accept_join_request(peer_id: int, claims: Dictionary, display_name: String, color_index: int) -> void:
	pending_eos_joins.erase(peer_id)
	var player_id: String = str(claims.get("player_id", ""))
	if match_running and not players.has(player_id):
		_reject_join(peer_id, "This match has already started.")
		return
	if players.has(player_id):
		var existing: Dictionary = players[player_id]
		var active_peers: Array = multiplayer.get_peers() if multiplayer.multiplayer_peer != null else []
		var old_peer_id := int(existing.get("peer_id", 0))
		var old_peer_active: bool = old_peer_id in active_peers
		if existing["connected"] and old_peer_active and old_peer_id != peer_id:
			_reject_join(peer_id, "This player is already connected.")
			return
		if old_peer_active and old_peer_id != peer_id and multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.disconnect_peer(old_peer_id)
		existing["peer_id"] = peer_id
		existing["connected"] = true
		existing["reconnect_deadline"] = 0.0
		existing["name"] = _clean_name(display_name)
		existing["color"] = _available_color(color_index, player_id)
		players[player_id] = existing
	else:
		if players.size() >= int(_server_settings["max_players"]):
			_reject_join(peer_id, "Lobby is full.")
			return
		if bool(claims.get("host", false)):
			for existing_id: String in players:
				var other: Dictionary = players[existing_id]
				other["host"] = false
				players[existing_id] = other
		players[player_id] = {
			"player_id": player_id,
			"peer_id": peer_id,
			"name": _clean_name(display_name),
			"color": _available_color(color_index),
			"look": "classic",
			"hat": "classic",
			"outfit": "none",
			"ready": false,
			"host": bool(claims.get("host", false)),
			"connected": true,
			"reconnect_deadline": 0.0,
			"role": "Camper"
		}
	peer_to_player[peer_id] = player_id
	server_had_connected_player = true
	_assign_host_if_needed()
	var state := _make_lobby_state()
	var join_packet := _encode_state_packet(state)
	receive_join_success.rpc_id(peer_id, player_id, int(join_packet[0]), join_packet[1])
	if match_running:
		var reconnect_packet := _encode_state_packet(_match_state_for(player_id))
		receive_match_started.rpc_id(peer_id, str(players[player_id]["role"]), int(reconnect_packet[0]), reconnect_packet[1])
		return
	_broadcast_lobby_state()


func _process_pending_eos_joins(now: float) -> void:
	if pending_eos_joins.is_empty() or multiplayer.multiplayer_peer == null:
		return
	var connected_peers := multiplayer.get_peers()
	for peer_key: Variant in pending_eos_joins.keys():
		var peer_id := int(peer_key)
		if peer_id not in connected_peers:
			pending_eos_joins.erase(peer_id)
			continue
		var request: Dictionary = pending_eos_joins[peer_id]
		var claims: Dictionary = request.get("claims", {})
		var player_id := str(claims.get("player_id", ""))
		if eos_allowed_player_ids.has(player_id) or now >= float(request.get("accept_after", now)):
			_accept_join_request(peer_id, claims, str(request.get("display_name", "Camper")), int(request.get("color_index", 0)))


func _reject_join(peer_id: int, message: String) -> void:
	pending_eos_joins.erase(peer_id)
	receive_join_failure.rpc_id(peer_id, message)
	_disconnect_peer_after_notice(peer_id)


func _disconnect_peer_after_notice(peer_id: int) -> void:
	await get_tree().create_timer(0.25).timeout
	if multiplayer.multiplayer_peer != null and peer_id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


@rpc("authority", "call_remote", "reliable")
func receive_join_success(player_id: String, raw_size: int, payload: PackedByteArray) -> void:
	eos_join_request_started_at = 0.0
	eos_last_join_request_at = 0.0
	eos_join_attempts = 0
	has_joined_session = true
	connection_failure_emitted = false
	local_player_id = player_id
	var state := _decode_state_packet(raw_size, payload)
	current_lobby_state = state
	join_succeeded.emit(state)


@rpc("authority", "call_remote", "reliable")
func receive_join_failure(message: String) -> void:
	eos_join_request_started_at = 0.0
	eos_last_join_request_at = 0.0
	eos_join_attempts = 0
	_fail_connection(message)


@rpc("authority", "call_remote", "reliable")
func receive_lobby_state(raw_size: int, payload: PackedByteArray) -> void:
	var state := _decode_state_packet(raw_size, payload)
	current_lobby_state = state
	lobby_state_changed.emit(state)


@rpc("any_peer", "call_remote", "reliable")
func rpc_set_ready(ready: bool) -> void:
	if not is_server or match_running:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not peer_to_player.has(peer_id):
		return
	_set_ready_for_player(str(peer_to_player[peer_id]), ready)


@rpc("any_peer", "call_remote", "reliable")
func request_color_change(color_index: int) -> void:
	if not is_server or match_running:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not peer_to_player.has(peer_id):
		return
	_set_color_for_player(str(peer_to_player[peer_id]), color_index)


@rpc("any_peer", "call_remote", "reliable")
func request_customization(color_index: int, hat: String, outfit: String) -> void:
	if not is_server or match_running:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not peer_to_player.has(peer_id):
		return
	_set_customization_for_player(str(peer_to_player[peer_id]), color_index, hat, outfit)


func set_customization(color_index: int, hat: String, outfit: String) -> void:
	if is_server:
		_set_customization_for_player(local_player_id, color_index, hat, outfit)
	elif _is_client_connected():
		request_customization.rpc_id(1, color_index, hat, outfit)


func _set_customization_for_player(player_id: String, color_index: int, hat: String, outfit: String) -> void:
	if not is_server or match_running or not players.has(player_id):
		return
	var requested := clampi(color_index, 0, 5)
	var record: Dictionary = players[player_id]
	if requested != int(record.get("color", -1)):
		if _is_color_taken(requested, player_id):
			_send_color_change_failure(player_id, "%s is already taken. Pick one of the available colours." % _color_name(requested))
		else:
			record["color"] = requested
	var look_id := hat if CustomizationCatalog.LOOKS.has(hat) else "classic"
	record["look"] = look_id
	record["hat"] = look_id
	record["outfit"] = outfit
	players[player_id] = record
	_broadcast_lobby_state()


@rpc("any_peer", "call_remote", "reliable")
func request_settings(settings: Dictionary) -> void:
	if not is_server or match_running:
		return
	var record := _record_for_peer(multiplayer.get_remote_sender_id())
	if record.is_empty() or not record["host"]:
		return
	_update_settings_for_player(str(record["player_id"]), settings)


@rpc("any_peer", "call_remote", "reliable")
func request_start_match() -> void:
	if not is_server or match_running:
		return
	var record := _record_for_peer(multiplayer.get_remote_sender_id())
	if record.is_empty() or not record["host"]:
		return
	_request_start_for_player(str(record["player_id"]))


@rpc("any_peer", "call_remote", "reliable")
func request_test_bots(enabled: bool) -> void:
	if not is_server or match_running:
		return
	var record := _record_for_peer(multiplayer.get_remote_sender_id())
	if record.is_empty() or not record["host"]:
		return
	_set_test_bots_for_player(str(record["player_id"]), enabled)


func _set_ready_for_player(player_id: String, ready: bool) -> void:
	if not is_server or match_running or not players.has(player_id):
		return
	var record: Dictionary = players[player_id]
	record["ready"] = ready
	players[player_id] = record
	_broadcast_lobby_state()


func _set_color_for_player(player_id: String, color_index: int) -> void:
	if not is_server or match_running or not players.has(player_id):
		return
	var requested := clampi(color_index, 0, 5)
	if _is_color_taken(requested, player_id):
		_send_color_change_failure(player_id, "%s is already taken. Pick one of the available colours." % _color_name(requested))
		return
	var record: Dictionary = players[player_id]
	record["color"] = requested
	players[player_id] = record
	_broadcast_lobby_state()


@rpc("authority", "call_remote", "reliable")
func receive_color_change_failure(message: String) -> void:
	color_change_failed.emit(message)


func _send_color_change_failure(player_id: String, message: String) -> void:
	if _is_local_server_player(player_id):
		color_change_failed.emit(message)
		return
	var record: Dictionary = players.get(player_id, {})
	var peer_id := int(record.get("peer_id", 0))
	if _is_peer_connected(peer_id):
		receive_color_change_failure.rpc_id(peer_id, message)


func _update_settings_for_player(player_id: String, settings: Dictionary) -> void:
	if not is_server or match_running or not players.has(player_id) or not bool(players[player_id].get("host", false)):
		return
	var requested_max := clampi(int(settings.get("max_players", _server_settings["max_players"])), 4, MAX_PLAYERS)
	_server_settings["max_players"] = maxi(requested_max, _connected_players().size())
	_server_settings["confirm_ejects"] = bool(settings.get("confirm_ejects", true))
	_server_settings["player_names"] = bool(settings.get("player_names", true))
	_server_settings["visual_tasks"] = bool(settings.get("visual_tasks", true))
	_server_settings["kill_cooldown"] = clampf(float(settings.get("kill_cooldown", _server_settings.get("kill_cooldown", 25.0))), 10.0, 60.0)
	_server_settings["walking_pace"] = clampf(float(settings.get("walking_pace", _server_settings.get("walking_pace", 1.0))), 0.75, 2.0)
	_server_settings["discussion_time"] = clampf(float(settings.get("discussion_time", _server_settings.get("discussion_time", 15.0))), 0.0, 60.0)
	_server_settings["voting_time"] = clampf(float(settings.get("voting_time", _server_settings.get("voting_time", 45.0))), 15.0, 120.0)
	var selected_killer := str(settings.get("forced_killer_player_id", "")).strip_edges()
	if selected_killer.is_empty() or (players.has(selected_killer) and bool(players[selected_killer].get("connected", false))):
		_server_settings["forced_killer_player_id"] = selected_killer
	_broadcast_lobby_state()


func _set_test_bots_for_player(player_id: String, enabled: bool) -> void:
	if not is_server or match_running or not players.has(player_id) or not bool(players[player_id].get("host", false)):
		return
	_remove_test_bots()
	if enabled:
		var target_players := mini(maxi(minimum_players, 4), int(_server_settings["max_players"]))
		var bot_number := 1
		while _connected_players().size() < target_players:
			var bot_id := TEST_BOT_PREFIX + str(bot_number)
			bot_number += 1
			if players.has(bot_id):
				continue
			players[bot_id] = {
				"player_id": bot_id,
				"peer_id": 0,
				"name": "Test Bot %d" % (bot_number - 1),
				"color": _available_color(bot_number - 1),
				"ready": true,
				"host": false,
				"connected": true,
				"reconnect_deadline": 0.0,
				"role": "Camper",
				"bot": true
			}
	_broadcast_lobby_state()


func _remove_test_bots() -> void:
	var bot_ids: Array[String] = []
	for player_id: String in players:
		if bool(players[player_id].get("bot", false)):
			bot_ids.append(player_id)
	for bot_id in bot_ids:
		players.erase(bot_id)


func _request_start_for_player(player_id: String) -> void:
	if not is_server or match_running or not players.has(player_id) or not bool(players[player_id].get("host", false)):
		return
	var connected := _connected_players()
	if connected.size() < minimum_players:
		_emit_start_failure(player_id, "Need %d connected players to start." % minimum_players)
		return
	for player: Dictionary in connected:
		if not player["ready"]:
			_emit_start_failure(player_id, "Every player must be ready.")
			return
	_start_match()


@rpc("authority", "call_remote", "reliable")
func receive_match_started(role: String, raw_size: int, payload: PackedByteArray) -> void:
	local_role = role
	match_running = true
	var state := _decode_state_packet(raw_size, payload)
	match_started.emit(role, state)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_input(direction: Vector2, sprinting: bool) -> void:
	if not is_server or not match_running:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not peer_to_player.has(peer_id):
		return
	_apply_input(str(peer_to_player[peer_id]), direction, sprinting)


func _apply_input(player_id: String, direction: Vector2, sprinting: bool) -> void:
	if not is_server or not match_running:
		return
	if not server_bodies.has(player_id):
		return
	var body = server_bodies[player_id]
	body.move_input = direction.limit_length(1.0)
	body.sprinting = sprinting


@rpc("authority", "call_remote", "unreliable_ordered")
func receive_snapshot(snapshot: Dictionary) -> void:
	snapshot_received.emit(snapshot)


@rpc("any_peer", "call_remote", "reliable")
func request_begin_task(task_id: String) -> void:
	if not is_server or not match_running:
		return
	var player_id := _player_id_for_peer(multiplayer.get_remote_sender_id())
	if not player_id.is_empty():
		_begin_task_for_player(player_id, task_id)


@rpc("any_peer", "call_remote", "reliable")
func request_complete_task(task_id: String) -> void:
	if not is_server or not match_running:
		return
	var player_id := _player_id_for_peer(multiplayer.get_remote_sender_id())
	if not player_id.is_empty():
		_complete_task_for_player(player_id, task_id)


@rpc("authority", "call_remote", "reliable")
func receive_task_begin_approved(task_id: String) -> void:
	task_begin_approved.emit(task_id)


@rpc("authority", "call_remote", "reliable")
func receive_task_state(raw_size: int, payload: PackedByteArray) -> void:
	var state := _decode_state_packet(raw_size, payload)
	task_state_received.emit(state)


@rpc("authority", "call_remote", "reliable")
func receive_task_action_failed(message: String) -> void:
	task_action_failed.emit(message)


@rpc("authority", "call_remote", "reliable")
func receive_match_ended(winner: String, reason: String, raw_size: int = 0, payload: PackedByteArray = PackedByteArray()) -> void:
	match_running = false
	var outcome := {}
	if raw_size > 0 and not payload.is_empty():
		outcome = _decode_state_packet(raw_size, payload)
	last_match_outcome = outcome
	match_ended.emit(winner, reason, outcome)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_rematch() -> void:
	if not is_server:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not peer_to_player.has(peer_id):
		return
	var player_id := str(peer_to_player[peer_id])
	_rematch_for_player(player_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_return_to_lobby() -> void:
	if not is_server:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not peer_to_player.has(peer_id):
		return
	var player_id := str(peer_to_player[peer_id])
	_return_to_lobby_for_player(player_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_set_rematch_ready(ready: bool) -> void:
	if not is_server:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not peer_to_player.has(peer_id):
		return
	var player_id := str(peer_to_player[peer_id])
	player_rematch_ready.emit(player_id, ready)


@rpc("authority", "call_remote", "reliable")
func receive_return_to_lobby() -> void:
	match_running = false
	meeting_active = false
	match_returned_to_lobby.emit()


@rpc("any_peer", "call_remote", "reliable")
func request_kill_nearby() -> void:
	if not is_server or not match_running:
		return
	var player_id := _player_id_for_peer(multiplayer.get_remote_sender_id())
	if not player_id.is_empty():
		_kill_nearest_for_player(player_id)


@rpc("any_peer", "call_remote", "reliable")
func request_start_sabotage(sabotage_id: String) -> void:
	if not is_server or not match_running:
		return
	var player_id := _player_id_for_peer(multiplayer.get_remote_sender_id())
	if not player_id.is_empty():
		_start_sabotage_for_player(player_id, sabotage_id)


@rpc("any_peer", "call_remote", "reliable")
func request_repair_sabotage(sabotage_id: String) -> void:
	if not is_server or not match_running:
		return
	var player_id := _player_id_for_peer(multiplayer.get_remote_sender_id())
	if not player_id.is_empty():
		_repair_sabotage_for_player(player_id, sabotage_id)


@rpc("any_peer", "call_remote", "reliable")
func request_report_nearby_body() -> void:
	if not is_server or not match_running:
		return
	var player_id := _player_id_for_peer(multiplayer.get_remote_sender_id())
	if not player_id.is_empty():
		_report_nearby_body_for_player(player_id)


@rpc("authority", "call_remote", "reliable")
func receive_phase4_state(raw_size: int, payload: PackedByteArray) -> void:
	var state := _decode_state_packet(raw_size, payload)
	phase4_state_received.emit(state)


@rpc("authority", "call_remote", "reliable")
func receive_phase4_action_failed(message: String) -> void:
	phase4_action_failed.emit(message)


@rpc("authority", "call_remote", "reliable")
func receive_body_reported(body: Dictionary) -> void:
	body_reported.emit(body)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_emergency_meeting() -> void:
	if not is_server or not match_running:
		return
	var player_id := _player_id_for_peer(multiplayer.get_remote_sender_id())
	if not player_id.is_empty():
		_start_emergency_meeting_for_player(player_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_end_meeting() -> void:
	if not is_server or not match_running:
		return
	var player_id := _player_id_for_peer(multiplayer.get_remote_sender_id())
	if not player_id.is_empty():
		_end_meeting()


@rpc("any_peer", "call_remote", "reliable")
func rpc_cast_vote(target_id: String) -> void:
	if not is_server or not match_running or not meeting_active:
		return
	var player_id := _player_id_for_peer(multiplayer.get_remote_sender_id())
	if not player_id.is_empty():
		_record_vote(player_id, target_id)


@rpc("authority", "call_remote", "reliable")
func receive_player_voted(voter_id: String) -> void:
	player_voted.emit(voter_id)


@rpc("authority", "call_remote", "reliable")
func receive_voting_results(raw_size: int, payload: PackedByteArray) -> void:
	var res := _decode_state_packet(raw_size, payload)
	voting_results = res
	voting_results_received.emit(res)


@rpc("authority", "call_remote", "reliable")
func receive_meeting_started(raw_size: int, payload: PackedByteArray) -> void:
	var state := _decode_state_packet(raw_size, payload)
	meeting_active = true
	current_meeting_data = state
	meeting_started.emit(state)


@rpc("authority", "call_remote", "reliable")
func receive_meeting_ended() -> void:
	meeting_active = false
	current_meeting_data.clear()
	meeting_ended.emit()


@rpc("any_peer", "call_remote", "reliable")
func rpc_send_chat(text: String) -> void:
	if not is_server:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var player_id := _player_id_for_peer(peer_id)
	if player_id.is_empty():
		return
	_process_chat_message(player_id, text)


@rpc("authority", "call_remote", "reliable")
func receive_chat_message(raw_size: int, payload: PackedByteArray) -> void:
	var msg := _decode_state_packet(raw_size, payload)
	chat_history.append(msg)
	if chat_history.size() > 60:
		chat_history.pop_front()
	chat_message_received.emit(msg)


@rpc("authority", "call_remote", "reliable")
func receive_chat_action_failed(message: String) -> void:
	chat_action_failed.emit(message)



var _server_settings := {
	"max_players": 6,
	"confirm_ejects": true,
	"player_names": true,
	"visual_tasks": true,
	"forced_killer_player_id": "",
	"kill_cooldown": 25.0,
	"walking_pace": 1.0,
	"discussion_time": 15.0,
	"voting_time": 45.0
}


func _start_match() -> void:
	for pid: String in server_bodies:
		if is_instance_valid(server_bodies[pid]):
			server_bodies[pid].queue_free()
	server_bodies.clear()
	match_running = true
	meeting_active = false
	current_meeting_data.clear()
	shared_tasks_completed = 0
	shared_tasks_total = 0
	kill_cooldown_until = 0.0
	bodies.clear()
	sabotage_state.clear()
	for sabotage: Dictionary in SABOTAGES:
		sabotage_state[str(sabotage["id"])] = {
			"id": sabotage["id"], "name": sabotage["name"], "station": sabotage["station"],
			"effect": sabotage["effect"], "active": false, "until": 0.0
		}
	var connected := _connected_players()
	var killer_index := randi_range(0, connected.size() - 1)
	var selected_killer_id := str(_server_settings.get("forced_killer_player_id", ""))
	var has_selected_killer := false
	if not selected_killer_id.is_empty():
		for index in range(connected.size()):
			if str(connected[index].get("player_id", "")) == selected_killer_id:
				killer_index = index
				has_selected_killer = true
				break
	if has_selected_killer:
		pass
	elif force_killer_for_testing and not local_player_id.is_empty():
		for index in range(connected.size()):
			if str(connected[index].get("player_id", "")) == local_player_id:
				killer_index = index
				break
	elif force_camper_for_testing and not local_player_id.is_empty() and connected.size() > 1:
		for index in range(connected.size()):
			if str(connected[index].get("player_id", "")) != local_player_id:
				killer_index = index
				break
	elif not preferred_camper_player_id.is_empty() and connected.size() > 1:
		for index in range(connected.size()):
			if str(connected[index].get("player_id", "")) != preferred_camper_player_id:
				killer_index = index
				break
	else:
		for index in range(connected.size()):
			if bool(connected[index].get("bot", false)):
				killer_index = index
				break
	var public_players: Array[Dictionary] = []
	for index in range(connected.size()):
		var record: Dictionary = connected[index]
		var player_id: String = record["player_id"]
		record["role"] = "Killer" if index == killer_index else "Camper"
		record["ghost"] = false
		record["completed_tasks"] = []
		record["sabotage_objectives"] = _assign_sabotage_objectives(player_id) if record["role"] == "Killer" else []
		record["completed_sabotages"] = []
		var is_test_bot := bool(record.get("bot", false))
		record["tasks"] = [] if record["role"] == "Killer" or is_test_bot else _assign_tasks(player_id, index)
		if record["role"] == "Camper" and not is_test_bot:
			shared_tasks_total += TASKS_PER_CAMPER
		players[player_id] = record
		var spawn_index: int = SPAWN_NODES[index % SPAWN_NODES.size()]
		var spawn_at: Vector2 = server_world.route_nodes[spawn_index]
		var body: CharacterBody2D = ServerPlayerScript.new()
		body.name = "ServerPlayer_" + player_id
		body.global_position = spawn_at
		var pace_mult := float(_server_settings.get("walking_pace", 1.0))
		body.walk_speed = 155.0 * pace_mult
		server_world.add_child(body)
		server_bodies[player_id] = body
		public_players.append({
			"player_id": player_id,
			"name": record["name"],
			"color": record["color"],
			"look": record.get("look", record.get("hat", "classic")),
			"hat": record.get("hat", "classic"),
			"outfit": record.get("outfit", "none"),
			"position": spawn_at
		})
	current_match_state = {"room_code": room_code, "players": public_players, "settings": _server_settings.duplicate(true)}
	for player: Dictionary in connected:
		if bool(player.get("bot", false)):
			continue
		var peer_id := int(player["peer_id"])
		var player_id := str(player["player_id"])
		var state := _match_state_for(player_id)
		var match_packet := _encode_state_packet(state)
		if _is_local_server_player(player_id):
			receive_match_started(str(player["role"]), int(match_packet[0]), match_packet[1])
		elif _is_peer_connected(peer_id):
			receive_match_started.rpc_id(peer_id, str(player["role"]), int(match_packet[0]), match_packet[1])
	_broadcast_phase4_state()


func _assign_tasks(player_id: String, player_index: int) -> Array[String]:
	var pool := TaskCatalog.all_ids()
	pool.erase(GUARANTEED_TASK_ID)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(room_code + ":" + player_id + ":" + str(player_index))
	for index in range(pool.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var value := pool[index]
		pool[index] = pool[swap_index]
		pool[swap_index] = value
	var result: Array[String] = [GUARANTEED_TASK_ID]
	for index in range(mini(TASKS_PER_CAMPER - result.size(), pool.size())):
		result.append(pool[index])
	return result


func _assign_sabotage_objectives(player_id: String) -> Array[String]:
	var pool: Array[String] = []
	for sabotage: Dictionary in SABOTAGES:
		pool.append(str(sabotage["id"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("sabotage:" + room_code + ":" + player_id)
	# Keep assignment deterministic for reconnect and regression checks.
	for index in range(pool.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var value := pool[index]
		pool[index] = pool[swap_index]
		pool[swap_index] = value
	return pool.slice(0, SABOTAGE_OBJECTIVES_PER_KILLER)


func _match_state_for(player_id: String) -> Dictionary:
	var state := current_match_state.duplicate(true)
	state["task_state"] = _task_state_for(player_id)
	state["phase4_state"] = _phase4_state_for(player_id)
	return state


func _task_state_for(player_id: String) -> Dictionary:
	var assignments: Array[Dictionary] = []
	var record: Dictionary = players.get(player_id, {})
	var completed: Array = record.get("completed_tasks", [])
	for task_id: String in record.get("tasks", []):
		var assignment := TaskCatalog.make_assignment(task_id)
		assignment["completed"] = task_id in completed
		assignments.append(assignment)
	return {
		"tasks": assignments,
		"completed": shared_tasks_completed,
		"total": shared_tasks_total,
		"ghost": bool(record.get("ghost", false))
	}


func _phase4_state_for(player_id: String) -> Dictionary:
	var record: Dictionary = players.get(player_id, {})
	var now := Time.get_unix_time_from_system()
	var public_sabotages: Array[Dictionary] = []
	for sabotage_id: String in sabotage_state:
		var sabotage: Dictionary = sabotage_state[sabotage_id].duplicate(true)
		sabotage["remaining"] = maxf(0.0, float(sabotage.get("until", 0.0)) - now) if bool(sabotage.get("active", false)) else 0.0
		public_sabotages.append(sabotage)
	public_sabotages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	var public_bodies: Array[Dictionary] = []
	for victim_id: String in bodies:
		if not bool(bodies[victim_id].get("reported", false)):
			public_bodies.append(bodies[victim_id].duplicate(true))
	var player_states := {}
	for state_player_id: String in players:
		var state_record: Dictionary = players[state_player_id]
		player_states[state_player_id] = {"ghost": bool(state_record.get("ghost", false))}
	var objectives: Array[Dictionary] = []
	if str(record.get("role", "")) == "Killer":
		for sabotage_id: String in record.get("sabotage_objectives", []):
			var sabotage: Dictionary = sabotage_state.get(sabotage_id, {})
			objectives.append({
				"id": sabotage_id,
				"name": str(sabotage.get("name", sabotage_id)),
				"completed": sabotage_id in record.get("completed_sabotages", [])
			})
	return {
		"role": str(record.get("role", "Camper")),
		"ghost": bool(record.get("ghost", false)),
		"kill_cooldown": maxf(0.0, kill_cooldown_until - now) if str(record.get("role", "")) == "Killer" else 0.0,
		"objectives": objectives,
		"sabotages": public_sabotages,
		"bodies": public_bodies,
		"player_states": player_states
	}


func _broadcast_phase4_state() -> void:
	if not match_running:
		return
	for record: Dictionary in _connected_players():
		if bool(record.get("bot", false)):
			continue
		var player_id := str(record["player_id"])
		var peer_id := int(record.get("peer_id", 0))
		var state := _phase4_state_for(player_id)
		if _is_local_server_player(player_id):
			phase4_state_received.emit(state)
		elif _is_peer_connected(peer_id):
			var phase4_packet := _encode_state_packet(state)
			receive_phase4_state.rpc_id(peer_id, int(phase4_packet[0]), phase4_packet[1])


func _phase4_actor_error(player_id: String) -> String:
	if not match_running or not players.has(player_id):
		return "The match is not accepting that action."
	if bool(players[player_id].get("ghost", false)):
		return "Ghosts cannot use this action."
	if not server_bodies.has(player_id):
		return "Your position is unavailable."
	return ""


func _kill_nearest_for_player(killer_id: String) -> void:
	var error := _phase4_actor_error(killer_id)
	if error.is_empty() and str(players[killer_id].get("role", "")) != "Killer":
		error = "Only the Killer can eliminate campers."
	if error.is_empty() and Time.get_unix_time_from_system() < kill_cooldown_until:
		error = "Elimination is cooling down."
	if not error.is_empty():
		_send_phase4_failure(killer_id, error)
		return
	var killer_body: CharacterBody2D = server_bodies[killer_id]
	var victim_id := ""
	var nearest := KILL_RADIUS
	for candidate_id: String in players:
		if candidate_id == killer_id or not server_bodies.has(candidate_id):
			continue
		var candidate: Dictionary = players[candidate_id]
		if str(candidate.get("role", "")) != "Camper" or bool(candidate.get("ghost", false)):
			continue
		var distance := killer_body.global_position.distance_to(server_bodies[candidate_id].global_position)
		if distance <= nearest:
			nearest = distance
			victim_id = candidate_id
	if victim_id.is_empty():
		_send_phase4_failure(killer_id, "Move closer to a living Camper.")
		return
	var victim_body: CharacterBody2D = server_bodies[victim_id]
	var context: Dictionary = server_world.get_contextual_elimination(killer_body.global_position, victim_body.global_position)
	var victim: Dictionary = players[victim_id]
	victim["ghost"] = true
	players[victim_id] = victim
	bodies[victim_id] = {
		"player_id": victim_id, "name": str(victim.get("name", "Camper")), "at": victim_body.global_position,
		"context": context, "color": clampi(int(victim.get("color", 0)), 0, 5),
		"killer_id": killer_id, "killer_color": clampi(int(players[killer_id].get("color", 0)), 0, 5),
		"reported": false
	}
	kill_cooldown_until = Time.get_unix_time_from_system() + float(_server_settings.get("kill_cooldown", 25.0))
	_broadcast_task_state()
	_broadcast_phase4_state()
	get_tree().create_timer(1.8).timeout.connect(func() -> void:
		if match_running:
			_check_victory_conditions()
	)


func _start_sabotage_for_player(player_id: String, sabotage_id: String) -> void:
	var error := _phase4_actor_error(player_id)
	if error.is_empty() and str(players[player_id].get("role", "")) != "Killer":
		error = "Only the Killer can sabotage camp systems."
	var record: Dictionary = players.get(player_id, {})
	if error.is_empty() and sabotage_id not in record.get("sabotage_objectives", []):
		error = "That sabotage is not one of your objectives."
	var sabotage: Dictionary = sabotage_state.get(sabotage_id, {})
	if error.is_empty() and sabotage.is_empty():
		error = "Unknown sabotage."
	if error.is_empty() and bool(sabotage.get("active", false)):
		error = "That system is already sabotaged."
	if error.is_empty() and sabotage_id in record.get("completed_sabotages", []):
		error = "That sabotage objective is already complete."
	if error.is_empty() and not _near_sabotage_station(player_id, sabotage):
		error = "Move closer to %s." % str(sabotage.get("station", "the sabotage point"))
	if not error.is_empty():
		_send_phase4_failure(player_id, error)
		return
	sabotage["active"] = true
	sabotage["until"] = Time.get_unix_time_from_system() + SABOTAGE_DURATION_SECONDS
	sabotage_state[sabotage_id] = sabotage
	var completed: Array = record.get("completed_sabotages", [])
	completed.append(sabotage_id)
	record["completed_sabotages"] = completed
	players[player_id] = record
	_broadcast_phase4_state()


func _repair_sabotage_for_player(player_id: String, sabotage_id: String) -> void:
	var error := _phase4_actor_error(player_id)
	if error.is_empty() and str(players[player_id].get("role", "")) != "Camper":
		error = "Only living Campers can repair sabotages."
	var sabotage: Dictionary = sabotage_state.get(sabotage_id, {})
	if error.is_empty() and (sabotage.is_empty() or not bool(sabotage.get("active", false))):
		error = "That camp system does not need repair."
	if error.is_empty() and not _near_sabotage_station(player_id, sabotage):
		error = "Move closer to %s." % str(sabotage.get("station", "the damaged system"))
	if not error.is_empty():
		_send_phase4_failure(player_id, error)
		return
	sabotage["active"] = false
	sabotage["until"] = 0.0
	sabotage_state[sabotage_id] = sabotage
	_broadcast_phase4_state()


func _near_sabotage_station(player_id: String, sabotage: Dictionary) -> bool:
	var station_name := str(sabotage.get("station", ""))
	for station: Dictionary in server_world.stations:
		if str(station.get("name", "")) == station_name:
			return server_bodies[player_id].global_position.distance_to(station["at"]) <= SABOTAGE_RADIUS
	return false


func _process_sabotage_expiry(now: float) -> void:
	if not match_running:
		return
	var changed := false
	for sabotage_id: String in sabotage_state:
		var sabotage: Dictionary = sabotage_state[sabotage_id]
		if bool(sabotage.get("active", false)) and now >= float(sabotage.get("until", 0.0)):
			sabotage["active"] = false
			sabotage["until"] = 0.0
			sabotage_state[sabotage_id] = sabotage
			changed = true
	if changed:
		_broadcast_phase4_state()


func _report_nearby_body_for_player(player_id: String) -> void:
	if not match_running or meeting_active:
		return
	var error := _phase4_actor_error(player_id)
	if not error.is_empty():
		_send_phase4_failure(player_id, error)
		return
	var reporter: CharacterBody2D = server_bodies[player_id]
	var nearest := KILL_RADIUS
	var reported_id := ""
	for victim_id: String in bodies:
		var body: Dictionary = bodies[victim_id]
		if bool(body.get("reported", false)):
			continue
		var distance := reporter.global_position.distance_to(body.get("at", Vector2.ZERO))
		if distance <= nearest:
			nearest = distance
			reported_id = victim_id
	if reported_id.is_empty():
		_send_phase4_failure(player_id, "Move closer to a reportable body.")
		return
	var body: Dictionary = bodies[reported_id]
	body["reported"] = true
	bodies[reported_id] = body
	_broadcast_phase4_state()
	_emit_body_report(player_id, body)
	var caller_rec: Dictionary = players.get(player_id, {})
	var meeting := {
		"type": "body_report",
		"caller_id": player_id,
		"caller_name": str(caller_rec.get("name", "Camper")),
		"caller_color": int(caller_rec.get("color", 0)),
		"victim_id": reported_id,
		"victim_name": str(body.get("name", "Camper")),
		"victim_color": int(body.get("color", 0)),
		"discussion_time": float(_server_settings.get("discussion_time", 15.0)),
		"voting_time": float(_server_settings.get("voting_time", 45.0)),
		"players": _build_meeting_players_roster()
	}
	_broadcast_meeting_start(meeting)


func _start_emergency_meeting_for_player(player_id: String) -> void:
	if not match_running or meeting_active:
		return
	var error := _phase4_actor_error(player_id)
	if not error.is_empty():
		_send_phase4_failure(player_id, error)
		return
	var caller: CharacterBody2D = server_bodies[player_id]
	if not server_world.is_near_emergency_button(caller.global_position):
		_send_phase4_failure(player_id, "Move closer to the Campfire Emergency Button.")
		return
	var caller_rec: Dictionary = players.get(player_id, {})
	var meeting := {
		"type": "emergency",
		"caller_id": player_id,
		"caller_name": str(caller_rec.get("name", "Camper")),
		"caller_color": int(caller_rec.get("color", 0)),
		"victim_id": "",
		"victim_name": "",
		"victim_color": 0,
		"discussion_time": float(_server_settings.get("discussion_time", 15.0)),
		"voting_time": float(_server_settings.get("voting_time", 45.0)),
		"players": _build_meeting_players_roster()
	}
	_broadcast_meeting_start(meeting)


func _build_meeting_players_roster() -> Array:
	var roster: Array = []
	for pid: String in players:
		var rec: Dictionary = players[pid]
		roster.append({
			"player_id": pid,
			"name": str(rec.get("name", "Camper")),
			"color": int(rec.get("color", 0)),
			"ghost": bool(rec.get("ghost", false)),
			"connected": bool(rec.get("connected", true))
		})
	roster.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["player_id"]) < str(b["player_id"]))
	return roster


func _broadcast_meeting_start(meeting: Dictionary) -> void:
	meeting_active = true
	current_meeting_data = meeting
	votes.clear()
	voting_results.clear()
	for pid: String in server_bodies:
		var sb: CharacterBody2D = server_bodies[pid]
		sb.move_input = Vector2.ZERO
		sb.velocity = Vector2.ZERO
	var packet := _encode_state_packet(meeting)
	for record: Dictionary in _connected_players():
		if bool(record.get("bot", false)):
			continue
		var pid := str(record["player_id"])
		var peer_id := int(record["peer_id"])
		if _is_local_server_player(pid):
			meeting_started.emit(meeting)
		elif _is_peer_connected(peer_id):
			receive_meeting_started.rpc_id(peer_id, int(packet[0]), packet[1])
	var total_time := float(meeting.get("discussion_time", 15.0)) + float(meeting.get("voting_time", 45.0))
	get_tree().create_timer(total_time + 1.2).timeout.connect(func() -> void:
		if meeting_active and match_running:
			_tally_votes_and_conclude()
	)


func _record_vote(voter_id: String, target_id: String) -> void:
	if not meeting_active or not is_server:
		return
	if not players.has(voter_id):
		return
	var v_rec: Dictionary = players[voter_id]
	if bool(v_rec.get("ghost", false)) or not bool(v_rec.get("connected", false)):
		return
	if votes.has(voter_id):
		return
	if target_id != "skip" and not players.has(target_id):
		return
	
	votes[voter_id] = target_id
	
	for record: Dictionary in _connected_players():
		if bool(record.get("bot", false)):
			continue
		var pid := str(record["player_id"])
		var peer_id := int(record["peer_id"])
		if _is_local_server_player(pid):
			player_voted.emit(voter_id)
		elif _is_peer_connected(peer_id):
			receive_player_voted.rpc_id(peer_id, voter_id)
	
	var living_count := 0
	for pid: String in players:
		var rec: Dictionary = players[pid]
		if bool(rec.get("connected", false)) and not bool(rec.get("ghost", false)):
			living_count += 1
	
	if votes.size() >= living_count:
		_tally_votes_and_conclude()


func _tally_votes_and_conclude() -> void:
	if not is_server or not meeting_active:
		return
	var tally: Dictionary = {}
	for vid: String in votes:
		var tid := str(votes[vid])
		tally[tid] = int(tally.get(tid, 0)) + 1
	
	var max_count := 0
	var top_candidates: Array[String] = []
	for tid: String in tally:
		var c: int = tally[tid]
		if c > max_count:
			max_count = c
			top_candidates = [tid]
		elif c == max_count:
			top_candidates.append(tid)
	
	var outcome_type := "none"
	var ejected_id := ""
	var ejected_name := ""
	var ejected_role := ""
	
	if top_candidates.size() == 0:
		outcome_type = "none"
	elif top_candidates.size() > 1:
		outcome_type = "tie"
	else:
		var winner: String = top_candidates[0]
		if winner == "skip":
			outcome_type = "skip"
		else:
			outcome_type = "ejected"
			ejected_id = winner
			var e_rec: Dictionary = players.get(ejected_id, {})
			ejected_name = str(e_rec.get("name", "Camper"))
			ejected_role = str(e_rec.get("role", "Camper"))
			set_player_ghost(ejected_id, true)
	
	var results := {
		"votes": votes.duplicate(),
		"tally": tally.duplicate(),
		"outcome_type": outcome_type,
		"ejected_id": ejected_id,
		"ejected_name": ejected_name,
		"ejected_role": ejected_role
	}
	voting_results = results
	
	var packet := _encode_state_packet(results)
	for record: Dictionary in _connected_players():
		if bool(record.get("bot", false)):
			continue
		var pid := str(record["player_id"])
		var peer_id := int(record["peer_id"])
		if _is_local_server_player(pid):
			voting_results_received.emit(results)
		elif _is_peer_connected(peer_id):
			receive_voting_results.rpc_id(peer_id, int(packet[0]), packet[1])


func _end_meeting() -> void:
	if not meeting_active:
		return
	meeting_active = false
	current_meeting_data.clear()
	votes.clear()
	voting_results.clear()
	for record: Dictionary in _connected_players():
		if bool(record.get("bot", false)):
			continue
		var pid := str(record["player_id"])
		var peer_id := int(record["peer_id"])
		if _is_local_server_player(pid):
			meeting_ended.emit()
		elif _is_peer_connected(peer_id):
			receive_meeting_ended.rpc_id(peer_id)
	_check_victory_conditions()


func _process_chat_message(player_id: String, raw_text: String) -> void:
	if not is_server or not players.has(player_id):
		return
	var clean_text := raw_text.strip_edges()
	if clean_text.is_empty():
		return
	if clean_text.length() > 120:
		clean_text = clean_text.substr(0, 120)
	
	var record: Dictionary = players[player_id]
	var is_ghost := bool(record.get("ghost", false))
	
	# If match is running and no meeting is active:
	# living players cannot chat to preserve social deduction mechanics.
	if match_running and not meeting_active and not is_ghost:
		_send_chat_failure(player_id, "Chat is only available during meetings.")
		return

	var msg := {
		"sender_id": player_id,
		"sender_name": str(record.get("name", "Camper")),
		"sender_color": int(record.get("color", 0)),
		"text": clean_text,
		"is_ghost": is_ghost,
		"timestamp": Time.get_unix_time_from_system(),
		"in_meeting": meeting_active
	}
	_broadcast_chat_message(msg, is_ghost)


func _broadcast_chat_message(msg: Dictionary, is_ghost_sender: bool) -> void:
	chat_history.append(msg)
	if chat_history.size() > 60:
		chat_history.pop_front()
	var packet := _encode_state_packet(msg)
	for record: Dictionary in _connected_players():
		if bool(record.get("bot", false)):
			continue
		var pid := str(record.get("player_id", ""))
		var peer_id := int(record.get("peer_id", 0))
		
		# If sender is ghost during a match, living players must NOT receive it!
		if match_running and is_ghost_sender:
			var is_recipient_ghost := bool(record.get("ghost", false))
			if not is_recipient_ghost:
				continue

		if _is_local_server_player(pid):
			chat_message_received.emit(msg)
		elif _is_peer_connected(peer_id):
			receive_chat_message.rpc_id(peer_id, int(packet[0]), packet[1])


func _send_chat_failure(player_id: String, message: String) -> void:
	var record: Dictionary = players.get(player_id, {})
	var peer_id := int(record.get("peer_id", 0))
	if _is_local_server_player(player_id):
		chat_action_failed.emit(message)
	elif _is_peer_connected(peer_id):
		receive_chat_action_failed.rpc_id(peer_id, message)


func _emit_body_report(player_id: String, body: Dictionary) -> void:
	for record: Dictionary in _connected_players():
		if bool(record.get("bot", false)):
			continue
		var pid := str(record["player_id"])
		var peer_id := int(record.get("peer_id", 0))
		if _is_local_server_player(pid):
			body_reported.emit(body)
		elif _is_peer_connected(peer_id):
			receive_body_reported.rpc_id(peer_id, body)


func _send_phase4_failure(player_id: String, message: String) -> void:
	var record: Dictionary = players.get(player_id, {})
	var peer_id := int(record.get("peer_id", 0))
	if _is_local_server_player(player_id):
		phase4_action_failed.emit(message)
	elif _is_peer_connected(peer_id):
		receive_phase4_action_failed.rpc_id(peer_id, message)


func _begin_task_for_player(player_id: String, task_id: String) -> void:
	var error := _task_validation_error(player_id, task_id)
	if not error.is_empty():
		_send_task_failure(player_id, error)
		return
	var peer_id := int(players[player_id].get("peer_id", 0))
	if _is_local_server_player(player_id):
		task_begin_approved.emit(task_id)
	elif _is_peer_connected(peer_id):
		receive_task_begin_approved.rpc_id(peer_id, task_id)


func _complete_task_for_player(player_id: String, task_id: String) -> void:
	var error := _task_validation_error(player_id, task_id)
	if not error.is_empty():
		_send_task_failure(player_id, error)
		return
	var record: Dictionary = players[player_id]
	var completed: Array = record.get("completed_tasks", [])
	completed.append(task_id)
	record["completed_tasks"] = completed
	players[player_id] = record
	shared_tasks_completed += 1
	_broadcast_task_state()
	_check_victory_conditions()


func _task_validation_error(player_id: String, task_id: String) -> String:
	if not match_running or not players.has(player_id):
		return "The match is not accepting tasks."
	if TaskCatalog.get_task(task_id).is_empty():
		return "Unknown camp task."
	var record: Dictionary = players[player_id]
	if str(record.get("role", "")) != "Camper":
		return "Only Campers can complete camp tasks."
	if task_id not in record.get("tasks", []):
		return "That task is not on your checklist."
	if task_id in record.get("completed_tasks", []):
		return "That task is already complete."
	if not server_bodies.has(player_id):
		return "Your position is unavailable."
	var station: Dictionary = server_world.get_nearest_station(server_bodies[player_id].global_position, TASK_RADIUS)
	if station.is_empty() or str(station.get("task_id", "")) != task_id:
		return "Move closer to the correct task station."
	return ""


func _broadcast_task_state() -> void:
	for record: Dictionary in _connected_players():
		if bool(record.get("bot", false)):
			continue
		var player_id := str(record["player_id"])
		var peer_id := int(record["peer_id"])
		var state := _task_state_for(player_id)
		if _is_local_server_player(player_id):
			task_state_received.emit(state)
		elif _is_peer_connected(peer_id):
			var task_packet := _encode_state_packet(state)
			receive_task_state.rpc_id(peer_id, int(task_packet[0]), task_packet[1])


func _send_task_failure(player_id: String, message: String) -> void:
	var record: Dictionary = players.get(player_id, {})
	var peer_id := int(record.get("peer_id", 0))
	if _is_local_server_player(player_id):
		task_action_failed.emit(message)
	elif _is_peer_connected(peer_id):
		receive_task_action_failed.rpc_id(peer_id, message)


func _check_victory_conditions() -> bool:
	if not match_running:
		return false

	# 1. Task Victory (Campers)
	if shared_tasks_total > 0 and shared_tasks_completed >= shared_tasks_total:
		_finish_match("Campers", "All camp tasks were completed.")
		return true

	# Count living and connected players
	var living_campers := 0
	var living_killers := 0
	var total_initial_campers := 0
	var total_initial_killers := 0
	for pid: String in players:
		var p: Dictionary = players[pid]
		if str(p.get("role", "")) == "Camper":
			total_initial_campers += 1
		elif str(p.get("role", "")) == "Killer":
			total_initial_killers += 1
		if not bool(p.get("connected", false)) and not bool(p.get("bot", false)):
			continue
		if bool(p.get("ghost", false)):
			continue
		if str(p.get("role", "")) == "Killer":
			living_killers += 1
		elif str(p.get("role", "")) == "Camper":
			living_campers += 1

	# 2. Killer Discovered / Eliminated (Campers Victory)
	if total_initial_killers > 0 and living_killers == 0:
		_finish_match("Campers", "The Killer was discovered and ejected.")
		return true

	# 3. Campers Parity / Outnumbered (Killer Victory)
	# In a 2-player match (1v1), killer wins when all campers are eliminated (0 living campers).
	# In a 3+ player match, parity (living_campers <= living_killers) secures killer victory.
	var killer_parity_met := false
	if total_initial_campers <= 1:
		killer_parity_met = (living_campers == 0)
	else:
		killer_parity_met = (living_campers <= living_killers)

	if total_initial_killers > 0 and living_killers > 0 and killer_parity_met:
		_finish_match("Killer", "The Killer eliminated the Campers.")
		return true

	return false


func _finish_match(winner: String, reason: String) -> void:
	if not match_running:
		return
	match_running = false

	var killer_id := ""
	var killer_name := ""
	var killer_color := 0
	var player_summaries: Array[Dictionary] = []
	for pid: String in players:
		var p: Dictionary = players[pid]
		var r := str(p.get("role", "Camper"))
		var col := int(p.get("color", 0))
		var pname := str(p.get("name", "Camper"))
		var is_ghost := bool(p.get("ghost", false))
		if r == "Killer":
			killer_id = pid
			killer_name = pname
			killer_color = col
		player_summaries.append({
			"player_id": pid,
			"name": pname,
			"color": col,
			"role": r,
			"ghost": is_ghost
		})

	var outcome := {
		"winner": winner,
		"reason": reason,
		"killer_id": killer_id,
		"killer_name": killer_name,
		"killer_color": killer_color,
		"players": player_summaries
	}
	last_match_outcome = outcome

	var packet := _encode_state_packet(outcome)
	for record: Dictionary in _connected_players():
		if bool(record.get("bot", false)):
			continue
		var peer_id := int(record["peer_id"])
		var pid := str(record.get("player_id", ""))
		if _is_local_server_player(pid):
			match_ended.emit(winner, reason, outcome)
		elif _is_peer_connected(peer_id):
			receive_match_ended.rpc_id(peer_id, winner, reason, int(packet[0]), packet[1])


func _rematch_for_player(player_id: String) -> void:
	if not is_server or not players.has(player_id) or not bool(players[player_id].get("host", false)):
		return
	for pid: String in server_bodies:
		if is_instance_valid(server_bodies[pid]):
			server_bodies[pid].queue_free()
	server_bodies.clear()
	_start_match()


func _return_to_lobby_for_player(player_id: String) -> void:
	if not is_server or not players.has(player_id) or not bool(players[player_id].get("host", false)):
		return
	_return_to_lobby()


func _return_to_lobby() -> void:
	match_running = false
	meeting_active = false
	current_meeting_data.clear()
	votes.clear()
	voting_results.clear()
	bodies.clear()
	sabotage_state.clear()
	shared_tasks_completed = 0
	shared_tasks_total = 0
	kill_cooldown_until = 0.0

	for pid: String in server_bodies:
		if is_instance_valid(server_bodies[pid]):
			server_bodies[pid].queue_free()
	server_bodies.clear()

	for pid: String in players:
		var p: Dictionary = players[pid]
		p["role"] = ""
		p["ghost"] = false
		p["ready"] = false
		p["completed_tasks"] = []
		p["tasks"] = []
		p["completed_sabotages"] = []
		p["sabotage_objectives"] = []
		players[pid] = p

	_broadcast_lobby_state()
	for record: Dictionary in _connected_players():
		if bool(record.get("bot", false)):
			continue
		var peer_id := int(record["peer_id"])
		var pid := str(record.get("player_id", ""))
		if _is_local_server_player(pid):
			match_returned_to_lobby.emit()
		elif _is_peer_connected(peer_id):
			receive_return_to_lobby.rpc_id(peer_id)


func set_player_ghost(player_id: String, ghost: bool = true) -> void:
	if not is_server or not players.has(player_id):
		return
	var record: Dictionary = players[player_id]
	record["ghost"] = ghost
	players[player_id] = record
	_broadcast_task_state()
	_broadcast_phase4_state()


func _player_id_for_peer(peer_id: int) -> String:
	return str(peer_to_player.get(peer_id, ""))


func _is_local_server_player(player_id: String) -> bool:
	if not is_server or not players.has(player_id):
		return false
	var peer_id := int((players[player_id] as Dictionary).get("peer_id", 0))
	return peer_id == 1 and (local_player_id.is_empty() or player_id == local_player_id)


func _is_peer_connected(peer_id: int) -> bool:
	return peer_id > 1 and multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and peer_id in multiplayer.get_peers()


func _is_client_connected() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED



func _create_server_world() -> void:
	server_world = WorldScript.new()
	server_world.name = "AuthoritativeCamp"
	add_child(server_world)
	server_world.visible = false


func _broadcast_lobby_state() -> void:
	var state := _make_lobby_state()
	current_lobby_state = state
	var lobby_packet := _encode_state_packet(state)
	for record: Dictionary in _connected_players():
		if bool(record.get("bot", false)):
			continue
		var peer_id := int(record["peer_id"])
		if _is_local_server_player(str(record.get("player_id", ""))):
			lobby_state_changed.emit(state)
		elif _is_peer_connected(peer_id):
			receive_lobby_state.rpc_id(peer_id, int(lobby_packet[0]), lobby_packet[1])


func _emit_start_failure(player_id: String, message: String) -> void:
	if _is_local_server_player(player_id):
		join_failed.emit(message)
		return
	var record: Dictionary = players.get(player_id, {})
	var peer_id := int(record.get("peer_id", 0))
	if _is_peer_connected(peer_id):
		receive_join_failure.rpc_id(peer_id, message)


func _encode_state_packet(state: Dictionary) -> Array:
	var raw := var_to_bytes(state)
	var compressed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	return [raw.size(), compressed]


func _decode_state_packet(raw_size: int, payload: PackedByteArray) -> Dictionary:
	if raw_size <= 0 or payload.is_empty():
		return {}
	var raw := payload.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.is_empty():
		return {}
	var decoded = bytes_to_var(raw)
	return decoded if decoded is Dictionary else {}


func _make_lobby_state() -> Dictionary:
	var public_players: Array[Dictionary] = []
	for player_id: String in players:
		var record: Dictionary = players[player_id]
		public_players.append({
			"player_id": player_id,
			"name": record["name"],
			"color": record["color"],
			"look": record.get("look", record.get("hat", "classic")),
			"hat": record.get("hat", "classic"),
			"outfit": record.get("outfit", "none"),
			"ready": record["ready"],
			"host": record["host"],
			"connected": record["connected"],
			"bot": bool(record.get("bot", false))
		})
	public_players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["player_id"]) < str(b["player_id"]))
	return {
		"room_code": room_code,
		"players": public_players,
		"settings": _server_settings.duplicate(true),
		"minimum_players": minimum_players
	}


func _connected_players() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for player_id: String in players:
		var record: Dictionary = players[player_id]
		if record["connected"]:
			result.append(record)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["player_id"]) < str(b["player_id"]))
	return result


func _record_for_peer(peer_id: int) -> Dictionary:
	if not peer_to_player.has(peer_id):
		return {}
	return players.get(peer_to_player[peer_id], {})


func _assign_host_if_needed() -> void:
	var has_connected_host := false
	for player_id: String in players:
		var record: Dictionary = players[player_id]
		if record["host"] and record["connected"] and not bool(record.get("bot", false)):
			has_connected_host = true
			break
	if has_connected_host:
		return
	var connected: Array[Dictionary] = []
	for record: Dictionary in _connected_players():
		if not bool(record.get("bot", false)):
			connected.append(record)
	if connected.is_empty():
		return
	for player_id: String in players:
		var record: Dictionary = players[player_id]
		record["host"] = record["player_id"] == connected[0]["player_id"]
		players[player_id] = record


func _remove_player(player_id: String) -> void:
	if not players.has(player_id):
		return
	var removed: Dictionary = players[player_id]
	var peer_id := int(removed.get("peer_id", 0))
	if match_running and str(removed.get("role", "")) == "Camper":
		shared_tasks_total = maxi(0, shared_tasks_total - removed.get("tasks", []).size())
		shared_tasks_completed = maxi(0, shared_tasks_completed - removed.get("completed_tasks", []).size())
	peer_to_player.erase(peer_id)
	players.erase(player_id)
	if server_bodies.has(player_id):
		server_bodies[player_id].queue_free()
		server_bodies.erase(player_id)
	if match_running:
		_broadcast_task_state()
		_check_victory_conditions()


func _available_color(requested: int, except_player_id := "") -> int:
	var preferred := clampi(requested, 0, 5)
	if not _is_color_taken(preferred, except_player_id):
		return preferred
	for candidate in range(6):
		if not _is_color_taken(candidate, except_player_id):
			return candidate
	return preferred


func _is_color_taken(color_index: int, except_player_id := "") -> bool:
	for player_id: String in players:
		if player_id == except_player_id:
			continue
		var record: Dictionary = players[player_id]
		if bool(record.get("connected", false)) and int(record.get("color", -1)) == color_index:
			return true
	return false


func _color_name(color_index: int) -> String:
	return ["Orange", "Blue", "Green", "Red", "Purple", "Yellow"][clampi(color_index, 0, 5)]


func _process_reconnect() -> void:
	if not reconnecting:
		return
	var now := Time.get_unix_time_from_system()
	if now >= reconnect_deadline:
		_fail_connection("Could not reconnect within 60 seconds.")
		return
	if now < next_reconnect_attempt:
		return
	next_reconnect_attempt = now + 2.0
	transport_events_armed = false
	var previous_peer := multiplayer.multiplayer_peer
	if previous_peer != null:
		previous_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var peer: MultiplayerPeer
	var error: Error
	if is_eos_p2p:
		peer = EOSGMultiplayerPeer.new()
		error = peer.create_client(EOS_SOCKET_ID, server_address)
	else:
		peer = ENetMultiplayerPeer.new()
		error = peer.create_client(server_address, server_port)
	if error == OK:
		multiplayer.multiplayer_peer = peer
		_arm_transport_events()
		status_changed.emit("Reconnecting…")


func _process_eos_connection() -> void:
	if is_server or not is_eos_p2p or reconnecting or eos_connect_retrying:
		return
	var now := Time.get_unix_time_from_system()
	if eos_join_request_started_at > 0.0 and now - eos_join_request_started_at >= EOS_JOIN_RESPONSE_TIMEOUT:
		_fail_connection("The host did not respond after several join attempts. Keep the host lobby open and try once more.")
		return
	if eos_join_request_started_at > 0.0 and eos_join_attempts < EOS_JOIN_MAX_ATTEMPTS and now - eos_last_join_request_at >= EOS_JOIN_RETRY_SECONDS:
		status_changed.emit("Waiting for host confirmation… retrying (%d/%d)…" % [eos_join_attempts + 1, EOS_JOIN_MAX_ATTEMPTS])
		_send_eos_join_request()
	if eos_connect_started_at <= 0.0:
		return
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTING:
		return
	if now - eos_connect_started_at < EOS_CONNECT_TIMEOUT:
		return
	if eos_connect_attempts >= EOS_CONNECT_MAX_ATTEMPTS:
		_fail_connection("Could not reach the host after %d attempts. Please try joining again." % EOS_CONNECT_MAX_ATTEMPTS)
		return
	_schedule_eos_connect_retry()


func _schedule_eos_connect_retry() -> void:
	if eos_connect_retrying or manual_disconnect or is_server or not is_eos_p2p:
		return
	eos_connect_retrying = true
	_retry_eos_connect_after_backoff()


func _retry_eos_connect_after_backoff() -> void:
	transport_events_armed = false
	var peer := multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	status_changed.emit("Host is taking longer than expected. Retrying connection (%d/%d)…" % [eos_connect_attempts + 1, EOS_CONNECT_MAX_ATTEMPTS])
	await get_tree().create_timer(0.65).timeout
	eos_connect_retrying = false
	if manual_disconnect or is_server or not is_eos_p2p:
		return
	var error := _open_eos_client_connection()
	if error != OK:
		_fail_connection("Could not open the internet connection: " + error_string(error))


func _fail_connection(message: String) -> void:
	if connection_failure_emitted:
		return
	connection_failure_emitted = true
	transport_events_armed = false
	reconnecting = false
	eos_connect_retrying = false
	eos_connect_started_at = 0.0
	eos_join_request_started_at = 0.0
	eos_last_join_request_at = 0.0
	var peer := multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	join_failed.emit(message)


func _validate_token(token: String) -> Dictionary:
	if is_eos_p2p and token.begins_with("eos:"):
		var claimed_player_id := token.trim_prefix("eos:")
		var peer_id := multiplayer.get_remote_sender_id()
		var peer := multiplayer.multiplayer_peer
		if not peer is EOSGMultiplayerPeer:
			return {}
		var actual_player_id: String = peer.get_peer_user_id(peer_id)
		if actual_player_id.is_empty() or actual_player_id != claimed_player_id:
			return {}
		return {"room": room_code, "player_id": actual_player_id, "host": false, "exp": Time.get_unix_time_from_system() + 3600}
	if room_secret == "dev" and token.begins_with("dev:"):
		var dev_parts := token.split(":")
		if dev_parts.size() >= 3:
			return {"room": room_code, "player_id": dev_parts[1], "host": dev_parts[2] == "host", "exp": Time.get_unix_time_from_system() + 3600}
		return {}
	var parts := token.split(".")
	if parts.size() != 2:
		return {}
	var payload_bytes := Marshalls.base64_to_raw(parts[0])
	var signature := Marshalls.base64_to_raw(parts[1])
	if payload_bytes.is_empty() or signature.is_empty():
		return {}
	var crypto := Crypto.new()
	var expected := crypto.hmac_digest(HashingContext.HASH_SHA256, room_secret.to_utf8_buffer(), payload_bytes)
	if expected != signature:
		return {}
	var parsed = JSON.parse_string(payload_bytes.get_string_from_utf8())
	if not parsed is Dictionary:
		return {}
	var claims: Dictionary = parsed
	if str(claims.get("room", "")).to_upper() != room_code:
		return {}
	if float(claims.get("exp", 0.0)) <= Time.get_unix_time_from_system():
		return {}
	return claims


func _clean_name(value: String) -> String:
	var cleaned := value.strip_edges()
	if cleaned.is_empty():
		cleaned = "Camper"
	return cleaned.left(18)
