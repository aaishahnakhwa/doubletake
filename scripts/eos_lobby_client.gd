class_name EosLobbyClient
extends Node

## Internet lobby discovery and NAT-friendly P2P setup. EOS owns the public
## rendezvous/relay layer; gameplay still uses Godot's normal RPC API through
## EOSGMultiplayerPeer.

signal status_changed(message: String)
signal failed(message: String)
signal room_code_ready(code: String)

const BUCKET_ID := "double_take_v1"
const ROOM_CODE_ATTRIBUTE := "double_take_code"
const GAME_VERSION_ATTRIBUTE := "game_version"
const GAME_VERSION := "0.2.0"
const HOST_PUID_ATTRIBUTE := "host_puid"
const SOCKET_ID := "DoubleTakeP2PV1"
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const MAX_PLAYERS := 6
const MAX_JOIN_RETRIES := 3
const FAIL_SAFE_TIMEOUT_SECONDS := 24.0
const P2P_HANDSHAKE_GUARD_SECONDS := 12.0
const CREATED_AT_ATTRIBUTE := "created_at"
const STALE_LOBBY_SECONDS := 120.0

var current_lobby: HLobby
var session: Node
var eos_ready := false
var membership_refresh_active := false
var operation_active := false
var leaving_lobby := false

var _join_operation_id := 0
var _last_eos_setup_log := ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if current_lobby != null and current_lobby.is_valid():
			if current_lobby.is_owner():
				current_lobby.destroy_async()
			else:
				current_lobby.leave_async()


func create_room(network_session: Node, display_name: String, color_index: int) -> void:
	if operation_active or leaving_lobby:
		status_changed.emit("Multiplayer setup is already in progress.")
		return
	_join_operation_id += 1
	var op_id := _join_operation_id
	operation_active = true
	_attach_session(network_session)
	if not await _ensure_signed_in(display_name):
		return
	if op_id != _join_operation_id:
		return
	if current_lobby != null:
		await leave_room()
		operation_active = true
		if op_id != _join_operation_id:
			return
	_start_fail_safe_timeout(op_id, FAIL_SAFE_TIMEOUT_SECONDS)
	status_changed.emit("Creating private internet lobby…")
	var options := EOS.Lobby.CreateLobbyOptions.new()
	options.bucket_id = BUCKET_ID
	options.max_lobby_members = MAX_PLAYERS
	# The room owner is also the authoritative gameplay host. Do not leave a
	# discoverable but unusable room behind if that host exits or crashes.
	options.disable_host_migration = true
	options.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised
	options.presence_enabled = true
	options.allow_invites = false
	current_lobby = await HLobbies.create_lobby_async(options)
	if op_id != _join_operation_id:
		return
	if current_lobby == null:
		_failed("Could not create the internet lobby.")
		return

	# Pre-publish code collision check: only treat *live* lobbies (recently
	# created) as collisions. Stale lobbies left behind by crashed hosts must
	# not permanently block a fresh code.
	var code := _new_room_code()
	for collision_check in range(5):
		var existing = await HLobbies.search_by_attribute_async({"key": ROOM_CODE_ATTRIBUTE, "value": code})
		if op_id != _join_operation_id:
			return
		if _has_live_lobby(existing):
			code = _new_room_code()
		else:
			break

	current_lobby.add_attribute(ROOM_CODE_ATTRIBUTE, code)
	current_lobby.add_attribute(GAME_VERSION_ATTRIBUTE, GAME_VERSION)
	current_lobby.add_attribute(HOST_PUID_ATTRIBUTE, HAuth.product_user_id)
	current_lobby.add_attribute(CREATED_AT_ATTRIBUTE, str(Time.get_unix_time_from_system()))
	current_lobby.add_current_member_attribute("name", display_name)
	current_lobby.add_current_member_attribute("color", clampi(color_index, 0, 5))
	if not await current_lobby.update_async():
		if op_id == _join_operation_id:
			_failed("Could not publish the private room code.")
		return
	if op_id != _join_operation_id:
		return
	_watch_lobby()
	var connection_error: int = session.start_eos_host(code, HAuth.product_user_id, display_name, color_index, _member_ids(), 2)
	if connection_error != OK:
		_failed("Could not open the P2P game host: " + error_string(connection_error))
		return
	room_code_ready.emit(code)
	status_changed.emit("Room %s ready. Share the code; players can join from any network." % code)


func join_room(network_session: Node, code: String, display_name: String, color_index: int) -> void:
	if operation_active or leaving_lobby:
		status_changed.emit("A room connection is already in progress.")
		return
	_join_operation_id += 1
	var op_id := _join_operation_id
	operation_active = true
	_attach_session(network_session)
	var clean_code := code.strip_edges().to_upper()
	if clean_code.length() != 6:
		_failed("Enter the complete six-character room code.")
		return
	if not await _ensure_signed_in(display_name):
		return
	if op_id != _join_operation_id:
		return
	if current_lobby != null:
		await leave_room()
		operation_active = true
		if op_id != _join_operation_id:
			return
	_start_fail_safe_timeout(op_id, FAIL_SAFE_TIMEOUT_SECONDS)
	_execute_join_with_retry(op_id, clean_code, display_name, color_index, 1)


func _execute_join_with_retry(op_id: int, clean_code: String, display_name: String, color_index: int, attempt: int) -> void:
	if op_id != _join_operation_id or not operation_active:
		return
	if attempt > MAX_JOIN_RETRIES:
		_failed("Could not join room %s after %d retries. Room may be full or closed." % [clean_code, MAX_JOIN_RETRIES])
		return
	if attempt > 1:
		status_changed.emit("Retrying matchmaking (%d/%d)…" % [attempt, MAX_JOIN_RETRIES])
		if current_lobby != null:
			await leave_room()
			operation_active = true
			if op_id != _join_operation_id:
				return

	status_changed.emit("Finding room %s…" % clean_code)
	var matches = []
	for search_attempt in range(1, 6):
		if op_id != _join_operation_id or not operation_active:
			return
		matches = await HLobbies.search_by_attribute_async({"key": ROOM_CODE_ATTRIBUTE, "value": clean_code})
		if matches != null and not matches.is_empty():
			break
		if search_attempt % 2 == 0:
			var bucket_lobbies = await HLobbies.search_by_bucket_id_async(BUCKET_ID)
			if bucket_lobbies != null:
				for candidate in bucket_lobbies:
					var code_attr = candidate.get_attribute(ROOM_CODE_ATTRIBUTE)
					var candidate_code := str(code_attr.get("value", "")).to_upper()
					if candidate_code == clean_code:
						matches = [candidate]
						break
			if not matches.is_empty():
				break
		if search_attempt < 5:
			await get_tree().create_timer(0.4).timeout

	# Several lobbies can carry the same code (a stale lobby from a crashed host
	# and the current room). Prefer the newest so players join the live room.
	matches = _newest_first(matches)

	if op_id != _join_operation_id or not operation_active:
		return

	if matches == null or matches.is_empty():
		if attempt < MAX_JOIN_RETRIES:
			status_changed.emit("Room not found yet. Retrying matchmaking (%d/%d)…" % [attempt + 1, MAX_JOIN_RETRIES])
			await get_tree().create_timer(0.8).timeout
			_execute_join_with_retry(op_id, clean_code, display_name, color_index, attempt + 1)
			return
		else:
			_failed("Room not found. Check the code or ask the host to create a new room.")
			return

	var joined_lobby: HLobby = null
	for candidate in matches:
		if op_id != _join_operation_id or not operation_active:
			return
		if candidate == null:
			continue
		joined_lobby = await HLobbies.join_async(candidate)
		if joined_lobby != null and joined_lobby.is_valid():
			break
		joined_lobby = null
	if op_id != _join_operation_id or not operation_active:
		if joined_lobby != null:
			joined_lobby.leave_async()
		return

	if joined_lobby == null:
		if attempt < MAX_JOIN_RETRIES:
			status_changed.emit("Room slot busy. Retrying matchmaking (%d/%d)…" % [attempt + 1, MAX_JOIN_RETRIES])
			await get_tree().create_timer(0.8).timeout
			_execute_join_with_retry(op_id, clean_code, display_name, color_index, attempt + 1)
			return
		else:
			_failed("Could not join that room. It may be full or closed.")
			return

	current_lobby = joined_lobby
	current_lobby.add_current_member_attribute("name", display_name)
	current_lobby.add_current_member_attribute("color", clampi(color_index, 0, 5))
	if not await current_lobby.update_async():
		if attempt < MAX_JOIN_RETRIES:
			_execute_join_with_retry(op_id, clean_code, display_name, color_index, attempt + 1)
			return
		else:
			_failed("Joined the room but could not update the player profile.")
			return

	if op_id != _join_operation_id or not operation_active:
		return

	_watch_lobby()
	status_changed.emit("Joining room %s… syncing player list…" % clean_code)
	await get_tree().create_timer(0.15).timeout

	if op_id != _join_operation_id or not operation_active:
		return

	if current_lobby == null or not current_lobby.is_valid():
		if attempt < MAX_JOIN_RETRIES:
			_execute_join_with_retry(op_id, clean_code, display_name, color_index, attempt + 1)
			return
		else:
			_failed("The room closed before the connection could be opened.")
			return

	var host_id := current_lobby.owner_product_user_id
	if host_id.is_empty():
		_failed("Room has no active host.")
		return

	_start_p2p_handshake_guard(op_id, clean_code, display_name, color_index, attempt)

	var connection_error: int = session.connect_to_eos_host(host_id, HAuth.product_user_id, display_name, color_index)
	if connection_error != OK:
		if attempt < MAX_JOIN_RETRIES:
			status_changed.emit("P2P connection error. Retrying matchmaking (%d/%d)…" % [attempt + 1, MAX_JOIN_RETRIES])
			_execute_join_with_retry(op_id, clean_code, display_name, color_index, attempt + 1)
			return
		else:
			_failed("Could not connect to the P2P host: " + error_string(connection_error))
			return

	status_changed.emit("Connecting to room %s…" % clean_code)


func _start_fail_safe_timeout(op_id: int, timeout_seconds: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(timeout_seconds).timeout.connect(func():
		if op_id == _join_operation_id and operation_active:
			status_changed.emit("Matchmaking timed out (%ds limit). Cleaning up..." % int(timeout_seconds))
			_failed("Matchmaking timed out. Please check your network connection and try again.")
	, CONNECT_ONE_SHOT)


func _start_p2p_handshake_guard(op_id: int, clean_code: String, display_name: String, color_index: int, attempt: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(P2P_HANDSHAKE_GUARD_SECONDS).timeout.connect(func():
		if op_id == _join_operation_id and operation_active:
			status_changed.emit("Connection to host timed out. Retrying matchmaking…")
			if attempt < MAX_JOIN_RETRIES:
				_execute_join_with_retry(op_id, clean_code, display_name, color_index, attempt + 1)
			else:
				_failed("Connection to host timed out. Check firewalls or host availability.")
	, CONNECT_ONE_SHOT)


func leave_room() -> void:
	# Cleanup must never invalidate the in-flight operation that requested it.
	# Only create_room/join_room/_failed advance _join_operation_id, otherwise a
	# retry that leaves a lobby first would disarm its own timers and lock up.
	operation_active = false
	if leaving_lobby:
		return
	var lobby_to_leave := current_lobby
	current_lobby = null
	if lobby_to_leave == null or not lobby_to_leave.is_valid():
		return
	leaving_lobby = true
	if lobby_to_leave.is_owner():
		await lobby_to_leave.destroy_async()
	else:
		await lobby_to_leave.leave_async()
	leaving_lobby = false


func _attach_session(network_session: Node) -> void:
	if is_instance_valid(session) and session != network_session:
		if session.join_succeeded.is_connected(_on_session_join_succeeded):
			session.join_succeeded.disconnect(_on_session_join_succeeded)
		if session.join_failed.is_connected(_on_session_join_failed):
			session.join_failed.disconnect(_on_session_join_failed)
	session = network_session
	if not session.join_succeeded.is_connected(_on_session_join_succeeded):
		session.join_succeeded.connect(_on_session_join_succeeded)
	if not session.join_failed.is_connected(_on_session_join_failed):
		session.join_failed.connect(_on_session_join_failed)


func _on_session_join_succeeded(_state: Dictionary) -> void:
	_join_operation_id += 1
	operation_active = false


func _on_session_join_failed(_message: String) -> void:
	if not operation_active:
		return
	_join_operation_id += 1
	operation_active = false
	leave_room()


func _ensure_signed_in(display_name: String) -> bool:
	if eos_ready and not HAuth.product_user_id.is_empty():
		return true
	var credentials := HCredentials.new()
	credentials.product_name = "Double Take"
	credentials.product_version = "0.2.0"
	credentials.product_id = _credential("product_id")
	credentials.sandbox_id = _credential("sandbox_id")
	credentials.deployment_id = _credential("deployment_id")
	credentials.client_id = _credential("client_id")
	credentials.client_secret = _credential("client_secret")
	credentials.encryption_key = _credential("encryption_key")
	for value in [credentials.product_id, credentials.sandbox_id, credentials.deployment_id, credentials.client_id, credentials.client_secret]:
		if value.strip_edges().is_empty():
			_failed("EOS is not configured yet. Add the Epic Product, Sandbox, Deployment, Client ID and Client Secret in Project Settings.")
			return false
	status_changed.emit("Signing in to multiplayer…")
	if not eos_ready:
		_last_eos_setup_log = ""
		if not HPlatform.log_msg.is_connected(_on_eos_setup_log):
			HPlatform.log_msg.connect(_on_eos_setup_log)
		if not await HPlatform.setup_eos_async(credentials):
			var reason := HPlatform.last_setup_error
			if reason.is_empty():
				reason = "Android EOS setup returned without creating a platform."
			if not _last_eos_setup_log.is_empty():
				reason += " Native: " + _last_eos_setup_log
			_failed("Could not initialize Epic Online Services. " + reason)
			return false
		eos_ready = true
		HP2P.set_relay_control(EOS.P2P.RelayControl.AllowRelays)
	if HAuth.product_user_id.is_empty():
		var signed_in := false
		for attempt in range(1, 4):
			# Most failures here are short EOS/network races. Attempt 2+ repairs stale
			# Device IDs immediately so the player never has to clear app data manually.
			var repair_device_id := attempt >= 2
			if await HAuth.login_anonymous_async(display_name, repair_device_id):
				signed_in = true
				break
			if attempt < 3:
				status_changed.emit("Multiplayer sign-in is taking longer than expected… retrying automatically (%d/3)…" % (attempt + 1))
				await get_tree().create_timer(0.4 * attempt).timeout
		if not signed_in:
			clear_eos_cache()
			_failed("Could not sign in to multiplayer after automatic recovery. Check the internet connection and try again.")
			return false
	return true


func _on_eos_setup_log(message: EOS.Logging.LogMessage) -> void:
	var text := message.message.strip_edges()
	if text.is_empty():
		return
	print("EOS [%s]: %s" % [message.category, text])
	# Retain the latest native explanation without overflowing the lobby UI.
	_last_eos_setup_log = text.left(220)


static func clear_eos_cache() -> void:
	var profiles_root := ProjectSettings.globalize_path("user://eos-instance-profiles")
	if DirAccess.dir_exists_absolute(profiles_root):
		DirAccess.remove_absolute(profiles_root)
	var eosg_cache := ProjectSettings.globalize_path("user://eosg-cache")
	if DirAccess.dir_exists_absolute(eosg_cache):
		DirAccess.remove_absolute(eosg_cache)


const DEFAULT_CREDENTIALS := {
	"product_id": "e4918c75285240b68ef3171959c2054b",
	"sandbox_id": "3884cd90dfb847e9b8e515dce0395370",
	"deployment_id": "378bb80a63e743d7a4eb5d2e9b50804d",
	"client_id": "xyza78916zYVZYOAlqCi5G7TaXA8Vhq2",
	"client_secret": "UCqoGQmZU64w0bTKqJt10IWyCOXrtCTwmTz3ZZZDFoI",
	"encryption_key": "1111111111111111111111111111111111111111111111111111111111111111"
}


func _credential(key: String) -> String:
	var config := ConfigFile.new()
	if config.load("res://eos_credentials.cfg") == OK:
		var from_file := str(config.get_value("eos", key, "")).strip_edges()
		if not from_file.is_empty():
			return from_file
	var from_settings := str(ProjectSettings.get_setting("double_take/eos_" + key, "")).strip_edges()
	if not from_settings.is_empty():
		return from_settings
	return str(DEFAULT_CREDENTIALS.get(key, "")).strip_edges()


func _watch_lobby() -> void:
	if current_lobby == null:
		return
	if not current_lobby.lobby_updated.is_connected(_sync_members):
		current_lobby.lobby_updated.connect(_sync_members)
	if not current_lobby.kicked_from_lobby.is_connected(_on_lobby_closed):
		current_lobby.kicked_from_lobby.connect(_on_lobby_closed)
	if not current_lobby.lobby_owner_changed.is_connected(_on_lobby_owner_changed):
		current_lobby.lobby_owner_changed.connect(_on_lobby_owner_changed)
	if is_instance_valid(session) and session.has_signal("eos_membership_refresh_requested") and not session.eos_membership_refresh_requested.is_connected(_refresh_membership_burst):
		session.eos_membership_refresh_requested.connect(_refresh_membership_burst)
	_sync_members()


func _sync_members() -> void:
	if is_instance_valid(session):
		session.set_eos_allowed_player_ids(_member_ids())


func _refresh_membership_burst() -> void:
	if membership_refresh_active:
		return
	membership_refresh_active = true
	for delay in [0.0, 0.3, 0.8, 1.5, 2.5]:
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
		if current_lobby == null or not current_lobby.is_valid():
			break
		# EOS notifications can arrive out of order when several people join at
		# once. Re-copying the cached lobby details makes every member visible to
		# the gameplay host instead of rejecting the later connections.
		current_lobby._copy_lobby_data()
		_sync_members()
	membership_refresh_active = false


func _member_ids() -> Array[String]:
	var ids: Array[String] = []
	if current_lobby == null:
		return ids
	for member in current_lobby.members:
		if not member.product_user_id.is_empty():
			ids.append(member.product_user_id)
	return ids


func _on_lobby_owner_changed() -> void:
	# EOS transfers lobby ownership automatically. Moving a live authoritative
	# simulation requires state handoff, so the current match intentionally stays
	# with its original host rather than silently corrupting game state.
	if current_lobby != null and current_lobby.owner_product_user_id != HAuth.product_user_id:
		status_changed.emit("Lobby host changed. Recreate the room before starting a new match.")


func _on_lobby_closed() -> void:
	if leaving_lobby:
		return
	current_lobby = null
	_join_operation_id += 1
	operation_active = false
	if is_instance_valid(session):
		session.disconnect_session()
	_failed("The host closed the room. Ask them for a new code.")


func _lobby_created_at(lobby) -> float:
	if lobby == null:
		return 0.0
	var attr = lobby.get_attribute(CREATED_AT_ATTRIBUTE)
	var value := str(attr.get("value", "")).strip_edges()
	return value.to_float() if not value.is_empty() else 0.0


func _has_live_lobby(lobbies) -> bool:
	if lobbies == null or lobbies.is_empty():
		return false
	var now := Time.get_unix_time_from_system()
	for candidate in lobbies:
		var created_at := _lobby_created_at(candidate)
		if created_at > 0.0 and now - created_at < STALE_LOBBY_SECONDS:
			return true
	return false


func _newest_first(lobbies) -> Array:
	if lobbies == null or lobbies.size() <= 1:
		return lobbies
	var sorted: Array = lobbies.duplicate()
	sorted.sort_custom(func(a, b) -> bool: return _lobby_created_at(a) > _lobby_created_at(b))
	return sorted


func _new_room_code() -> String:
	var code := ""
	for _index in 6:
		code += CODE_ALPHABET[randi_range(0, CODE_ALPHABET.length() - 1)]
	return code


func _failed(message: String) -> void:
	_join_operation_id += 1
	operation_active = false
	if current_lobby != null:
		leave_room()
	failed.emit(message)
