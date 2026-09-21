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
signal match_ended(winner: String, reason: String)
signal phase4_state_received(state: Dictionary)
signal phase4_action_failed(message: String)
signal body_reported(body: Dictionary)
signal eos_membership_refresh_requested
signal color_change_failed(message: String)

const WorldScript = preload("res://scripts/camp_world.gd")
const ServerPlayerScript = preload("res://scripts/server_player.gd")
const TaskCatalog = preload("res://scripts/task_catalog.gd")
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
const EOS_CONNECT_TIMEOUT := 10.0
const EOS_CONNECT_MAX_ATTEMPTS := 4
const EOS_JOIN_RESPONSE_TIMEOUT := 45.0
const EOS_JOIN_RETRY_SECONDS := 3.0
const EOS_JOIN_MAX_ATTEMPTS := 8
const EOS_MEMBERSHIP_GRACE_SECONDS := 3.0
const TEST_BOT_PREFIX := "test-bot-"

var is_server := false
var room_code := ""
var room_secret := ""
var minimum_players := 4
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
var eos_allowed_player_ids: Dictionary = {}
var eos_connect_started_at := 0.0
var eos_join_request_started_at := 0.0
var eos_last_join_request_at := 0.0
var eos_join_attempts := 0
var eos_connect_attempts := 0
var eos_connect_retrying := false
var pending_eos_joins: Dictionary = {}
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


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func start_server(port: int, code: String, secret: String, required_players: int = 4) -> Error:
	is_server = true
	is_eos_p2p = false
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


func start_eos_host(code: String, player_id: String, display_name: String, color_index: int, allowed_player_ids: Array[String], required_players: int = 4):
	disconnect_session()
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


func start_lan_host(address_label: String, player_id: String, display_name: String, color_index: int, required_players: int = 4) -> Error:
	disconnect_session()
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
	disconnect_session()
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
	var peer := EOSGMultiplayerPeer.new()
	var error := peer.create_client(EOS_SOCKET_ID, server_address)
	if error != OK:
		join_failed.emit("Could not start EOS P2P connection: " + error_string(error))
		return int(error)
	multiplayer.multiplayer_peer = peer
	eos_connect_attempts += 1
	eos_connect_started_at = Time.get_unix_time_from_system()
	status_changed.emit("Connecting through internet P2P…")
	return int(OK)


func set_eos_allowed_player_ids(player_ids: Array[String]) -> void:
	eos_allowed_player_ids.clear()
	for player_id in player_ids:
		if not player_id.is_empty():
			eos_allowed_player_ids[player_id] = true
	if is_server and is_eos_p2p and not pending_eos_joins.is_empty():
		_process_pending_eos_joins(Time.get_unix_time_from_system())


func connect_to_server(address: String, port: int, token: String, display_name: String, color_index: int) -> Error:
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
	status_changed.emit("Connecting to %s:%d…" % [address, port])
	return OK


func disconnect_session() -> void:
	manual_disconnect = true
	reconnecting = false
	eos_connect_started_at = 0.0
	eos_join_request_started_at = 0.0
	eos_last_join_request_at = 0.0
	eos_join_attempts = 0
	eos_connect_attempts = 0
	eos_connect_retrying = false
	pending_eos_joins.clear()
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
	eos_allowed_player_ids.clear()
	if is_instance_valid(server_world):
		server_world.queue_free()
	server_world = null


func set_ready(ready: bool) -> void:
	if is_server and not local_player_id.is_empty():
		_set_ready_for_player(local_player_id, ready)
	elif multiplayer.multiplayer_peer != null:
		rpc_set_ready.rpc_id(1, ready)


func request_color(color_index: int) -> void:
	if is_server and not local_player_id.is_empty():
		_set_color_for_player(local_player_id, color_index)
	elif multiplayer.multiplayer_peer != null:
		request_color_change.rpc_id(1, color_index)


func update_settings(settings: Dictionary) -> void:
	if is_server and not local_player_id.is_empty():
		_update_settings_for_player(local_player_id, settings)
	elif multiplayer.multiplayer_peer != null:
		request_settings.rpc_id(1, settings)


func request_match_start() -> void:
	if is_server and not local_player_id.is_empty():
		_request_start_for_player(local_player_id)
	elif multiplayer.multiplayer_peer != null:
		request_start_match.rpc_id(1)


func set_test_bots(enabled: bool) -> void:
	if is_server and not local_player_id.is_empty():
		_set_test_bots_for_player(local_player_id, enabled)
	elif multiplayer.multiplayer_peer != null:
		request_test_bots.rpc_id(1, enabled)


func send_movement(direction: Vector2, sprinting: bool) -> void:
	if is_server and not local_player_id.is_empty():
		_apply_input(local_player_id, direction, sprinting)
	elif multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		submit_input.rpc_id(1, direction.limit_length(1.0), sprinting)


func begin_task(task_id: String) -> void:
	if is_server and not local_player_id.is_empty():
		_begin_task_for_player(local_player_id, task_id)
	elif multiplayer.multiplayer_peer != null:
		request_begin_task.rpc_id(1, task_id)


func complete_task(task_id: String) -> void:
	if is_server and not local_player_id.is_empty():
		_complete_task_for_player(local_player_id, task_id)
	elif multiplayer.multiplayer_peer != null:
		request_complete_task.rpc_id(1, task_id)


func request_kill() -> void:
	if is_server and not local_player_id.is_empty():
		_kill_nearest_for_player(local_player_id)
	elif multiplayer.multiplayer_peer != null:
		request_kill_nearby.rpc_id(1)


func request_sabotage(sabotage_id: String) -> void:
	if is_server and not local_player_id.is_empty():
		_start_sabotage_for_player(local_player_id, sabotage_id)
	elif multiplayer.multiplayer_peer != null:
		request_start_sabotage.rpc_id(1, sabotage_id)


func request_repair(sabotage_id: String) -> void:
	if is_server and not local_player_id.is_empty():
		_repair_sabotage_for_player(local_player_id, sabotage_id)
	elif multiplayer.multiplayer_peer != null:
		request_repair_sabotage.rpc_id(1, sabotage_id)


func report_nearby_body() -> void:
	if is_server and not local_player_id.is_empty():
		_report_nearby_body_for_player(local_player_id)
	elif multiplayer.multiplayer_peer != null:
		request_report_nearby_body.rpc_id(1)


func _emit_local_eos_join() -> void:
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


func _on_connected_to_server() -> void:
	reconnecting = false
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
	if eos_connect_retrying:
		return
	if reconnecting:
		next_reconnect_attempt = Time.get_unix_time_from_system() + 2.0
		status_changed.emit("Reconnect attempt failed; retrying…")
	elif is_eos_p2p and eos_connect_attempts < EOS_CONNECT_MAX_ATTEMPTS:
		_schedule_eos_connect_retry()
	else:
		eos_connect_started_at = 0.0
		join_failed.emit("Connection failed after %d attempts. Ask the host to keep the lobby open, then try again." % maxi(eos_connect_attempts, 1))


func _on_server_disconnected() -> void:
	if eos_connect_retrying:
		return
	if manual_disconnect or local_token.is_empty():
		join_failed.emit("Disconnected from the room server.")
		return
	reconnecting = true
	reconnect_deadline = Time.get_unix_time_from_system() + RECONNECT_SECONDS
	next_reconnect_attempt = Time.get_unix_time_from_system() + 1.0
	status_changed.emit("Connection lost. Reconnecting for up to 60 seconds…")


func _on_peer_connected(_peer_id: int) -> void:
	if is_server and is_eos_p2p:
		eos_membership_refresh_requested.emit()


func _on_peer_disconnected(peer_id: int) -> void:
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
	record["reconnect_deadline"] = Time.get_unix_time_from_system() + RECONNECT_SECONDS
	players[player_id] = record
	if server_bodies.has(player_id):
		server_bodies[player_id].move_input = Vector2.ZERO
		server_bodies[player_id].sprinting = false
	_assign_host_if_needed()
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
		pending_eos_joins[peer_id] = {
			"claims": claims,
			"display_name": display_name,
			"color_index": color_index,
			"accept_after": Time.get_unix_time_from_system() + EOS_MEMBERSHIP_GRACE_SECONDS
		}
		status_changed.emit("An EOS player is joining; refreshing lobby membership…")
		eos_membership_refresh_requested.emit()
		return
	_accept_join_request(peer_id, claims, display_name, color_index)


func _accept_join_request(peer_id: int, claims: Dictionary, display_name: String, color_index: int) -> void:
	pending_eos_joins.erase(peer_id)
	var player_id: String = str(claims.get("player_id", ""))
	if match_running and not players.has(player_id):
		_reject_join(peer_id, "This match has already started.")
		return
	if players.has(player_id):
		var existing: Dictionary = players[player_id]
		if existing["connected"]:
			# The client may retry if the first EOS success response was lost.
			# Re-send the current authoritative state to that same peer.
			if int(existing.get("peer_id", 0)) == peer_id:
				var retry_packet := _encode_state_packet(_make_lobby_state())
				receive_join_success.rpc_id(peer_id, player_id, int(retry_packet[0]), retry_packet[1])
				return
			_reject_join(peer_id, "This player is already connected.")
			return
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
	local_player_id = player_id
	var state := _decode_state_packet(raw_size, payload)
	current_lobby_state = state
	join_succeeded.emit(state)


@rpc("authority", "call_remote", "reliable")
func receive_join_failure(message: String) -> void:
	eos_join_request_started_at = 0.0
	eos_last_join_request_at = 0.0
	eos_join_attempts = 0
	join_failed.emit(message)


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
	if peer_id > 0:
		receive_color_change_failure.rpc_id(peer_id, message)


func _update_settings_for_player(player_id: String, settings: Dictionary) -> void:
	if not is_server or match_running or not players.has(player_id) or not bool(players[player_id].get("host", false)):
		return
	var requested_max := clampi(int(settings.get("max_players", _server_settings["max_players"])), 4, MAX_PLAYERS)
	_server_settings["max_players"] = maxi(requested_max, _connected_players().size())
	_server_settings["confirm_ejects"] = bool(settings.get("confirm_ejects", true))
	_server_settings["player_names"] = bool(settings.get("player_names", true))
	_server_settings["visual_tasks"] = bool(settings.get("visual_tasks", true))
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
func receive_match_ended(winner: String, reason: String) -> void:
	match_running = false
	match_ended.emit(winner, reason)


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


var _server_settings := {
	"max_players": 6,
	"confirm_ejects": true,
	"player_names": true,
	"visual_tasks": true,
	"forced_killer_player_id": ""
}


func _start_match() -> void:
	match_running = true
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
		server_world.add_child(body)
		server_bodies[player_id] = body
		public_players.append({
			"player_id": player_id,
			"name": record["name"],
			"color": record["color"],
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
		else:
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
		elif peer_id > 0:
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
	kill_cooldown_until = Time.get_unix_time_from_system() + KILL_COOLDOWN_SECONDS
	_broadcast_task_state()
	_broadcast_phase4_state()


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


func _emit_body_report(player_id: String, body: Dictionary) -> void:
	var record: Dictionary = players.get(player_id, {})
	var peer_id := int(record.get("peer_id", 0))
	if _is_local_server_player(player_id):
		body_reported.emit(body)
	elif peer_id > 0:
		receive_body_reported.rpc_id(peer_id, body)


func _send_phase4_failure(player_id: String, message: String) -> void:
	var record: Dictionary = players.get(player_id, {})
	var peer_id := int(record.get("peer_id", 0))
	if _is_local_server_player(player_id):
		phase4_action_failed.emit(message)
	elif peer_id > 0:
		receive_phase4_action_failed.rpc_id(peer_id, message)


func _begin_task_for_player(player_id: String, task_id: String) -> void:
	var error := _task_validation_error(player_id, task_id)
	if not error.is_empty():
		_send_task_failure(player_id, error)
		return
	var peer_id := int(players[player_id].get("peer_id", 0))
	if _is_local_server_player(player_id):
		task_begin_approved.emit(task_id)
	elif peer_id > 0:
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
	if shared_tasks_total > 0 and shared_tasks_completed >= shared_tasks_total:
		_finish_match("Campers", "All camp tasks were completed.")


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
		else:
			var task_packet := _encode_state_packet(state)
			receive_task_state.rpc_id(peer_id, int(task_packet[0]), task_packet[1])


func _send_task_failure(player_id: String, message: String) -> void:
	var record: Dictionary = players.get(player_id, {})
	var peer_id := int(record.get("peer_id", 0))
	if _is_local_server_player(player_id):
		task_action_failed.emit(message)
	elif peer_id > 0:
		receive_task_action_failed.rpc_id(peer_id, message)


func _finish_match(winner: String, reason: String) -> void:
	match_running = false
	for record: Dictionary in _connected_players():
		if bool(record.get("bot", false)):
			continue
		var peer_id := int(record["peer_id"])
		if _is_local_server_player(str(record.get("player_id", ""))):
			match_ended.emit(winner, reason)
		else:
			receive_match_ended.rpc_id(peer_id, winner, reason)


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
		else:
			receive_lobby_state.rpc_id(peer_id, int(lobby_packet[0]), lobby_packet[1])


func _emit_start_failure(player_id: String, message: String) -> void:
	if _is_local_server_player(player_id):
		join_failed.emit(message)
		return
	var record: Dictionary = players.get(player_id, {})
	if not record.is_empty():
		receive_join_failure.rpc_id(int(record.get("peer_id", 0)), message)


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
		if shared_tasks_total > 0 and shared_tasks_completed >= shared_tasks_total:
			_finish_match("Campers", "All remaining camp tasks were completed.")


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
		reconnecting = false
		join_failed.emit("Could not reconnect within 60 seconds.")
		return
	if now < next_reconnect_attempt:
		return
	next_reconnect_attempt = now + 2.0
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
		status_changed.emit("Reconnecting…")


func _process_eos_connection() -> void:
	if is_server or not is_eos_p2p or reconnecting or eos_connect_retrying:
		return
	var now := Time.get_unix_time_from_system()
	if eos_join_request_started_at > 0.0 and now - eos_join_request_started_at >= EOS_JOIN_RESPONSE_TIMEOUT:
		eos_join_request_started_at = 0.0
		join_failed.emit("The host did not respond after several join attempts. Keep the host lobby open and try once more.")
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
		eos_connect_started_at = 0.0
		join_failed.emit("Could not reach the host after %d attempts. Please try joining again." % EOS_CONNECT_MAX_ATTEMPTS)
		return
	_schedule_eos_connect_retry()


func _schedule_eos_connect_retry() -> void:
	if eos_connect_retrying or is_server or not is_eos_p2p:
		return
	eos_connect_retrying = true
	_retry_eos_connect_after_backoff()


func _retry_eos_connect_after_backoff() -> void:
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
		eos_connect_started_at = 0.0


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
