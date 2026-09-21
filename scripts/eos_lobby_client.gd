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
const SOCKET_ID := "DoubleTakeP2PV1"
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const MAX_PLAYERS := 6

var current_lobby: HLobby
var session: Node
var eos_ready := false
var membership_refresh_active := false


func create_room(network_session: Node, display_name: String, color_index: int) -> void:
	session = network_session
	if not await _ensure_signed_in(display_name):
		return
	status_changed.emit("Creating private internet lobby…")
	var options := EOS.Lobby.CreateLobbyOptions.new()
	options.bucket_id = BUCKET_ID
	options.max_lobby_members = MAX_PLAYERS
	options.disable_host_migration = false
	options.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised
	options.presence_enabled = false
	options.allow_invites = false
	current_lobby = await HLobbies.create_lobby_async(options)
	if current_lobby == null:
		_failed("Could not create the internet lobby.")
		return
	var code := _new_room_code()
	current_lobby.add_attribute(ROOM_CODE_ATTRIBUTE, code)
	current_lobby.add_current_member_attribute("name", display_name)
	current_lobby.add_current_member_attribute("color", clampi(color_index, 0, 5))
	if not await current_lobby.update_async():
		_failed("Could not publish the private room code.")
		return
	_watch_lobby()
	var connection_error: int = session.start_eos_host(code, HAuth.product_user_id, display_name, color_index, _member_ids())
	if connection_error != OK:
		_failed("Could not open the P2P game host: " + error_string(connection_error))
		return
	room_code_ready.emit(code)
	status_changed.emit("Room %s ready. Share the code; players can join from any network." % code)


func join_room(network_session: Node, code: String, display_name: String, color_index: int) -> void:
	session = network_session
	var clean_code := code.strip_edges().to_upper()
	if clean_code.length() != 6:
		_failed("Enter the complete six-character room code.")
		return
	if not await _ensure_signed_in(display_name):
		return
	status_changed.emit("Finding room %s…" % clean_code)
	var matches = []
	for attempt in range(1, 9):
		matches = await HLobbies.search_by_attribute_async({"key": ROOM_CODE_ATTRIBUTE, "value": clean_code})
		if matches != null and not matches.is_empty():
			break
		if attempt < 8:
			status_changed.emit("Room is still publishing… retrying automatically (%d/8)…" % (attempt + 1))
			await get_tree().create_timer(0.9).timeout
	if matches == null or matches.is_empty():
		_failed("Room not found. Check the code or ask the host to create a new room.")
		return
	current_lobby = await HLobbies.join_async(matches[0])
	if current_lobby == null:
		_failed("Could not join that room. It may be full or closed.")
		return
	current_lobby.add_current_member_attribute("name", display_name)
	current_lobby.add_current_member_attribute("color", clampi(color_index, 0, 5))
	if not await current_lobby.update_async():
		_failed("Joined the room but could not update the player profile.")
		return
	_watch_lobby()
	# The host validates a P2P player against its live EOS lobby member list.
	# Give EOS a brief moment to deliver this membership update before opening
	# the gameplay socket. This matters when several players join at once.
	status_changed.emit("Joining room %s… syncing player list…" % clean_code)
	await get_tree().create_timer(0.75).timeout
	if current_lobby == null or not current_lobby.is_valid():
		_failed("The room closed before the connection could be opened.")
		return
	var host_id := current_lobby.owner_product_user_id
	if host_id.is_empty():
		_failed("Room has no active host.")
		return
	var connection_error: int = session.connect_to_eos_host(host_id, HAuth.product_user_id, display_name, color_index)
	if connection_error != OK:
		_failed("Could not connect to the P2P host: " + error_string(connection_error))
		return
	status_changed.emit("Connecting to room %s…" % clean_code)


func leave_room() -> void:
	if current_lobby != null and current_lobby.is_valid():
		await current_lobby.leave_async()
	current_lobby = null


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
		if not await HPlatform.setup_eos_async(credentials):
			_failed("Could not initialize Epic Online Services. Check the configured IDs.")
			return false
		eos_ready = true
	if HAuth.product_user_id.is_empty():
		var signed_in := false
		for attempt in range(1, 4):
			# Most failures here are short EOS/network races. Retry silently, then
			# repair a stale Device ID on the final attempt so the player never has
			# to clear app data or edit a cache folder manually.
			var repair_device_id := attempt == 3
			if await HAuth.login_anonymous_async(display_name, repair_device_id):
				signed_in = true
				break
			if attempt < 3:
				status_changed.emit("Multiplayer sign-in is taking longer than expectedâ€¦ retrying automatically (%d/3)â€¦" % (attempt + 1))
				await get_tree().create_timer(0.75 * attempt).timeout
		if not signed_in:
			_failed("Could not sign in to multiplayer after automatic recovery. Check the internet connection and try again.")
			return false
	return true


func _credential(key: String) -> String:
	var config := ConfigFile.new()
	if config.load("res://eos_credentials.cfg") == OK:
		var from_file := str(config.get_value("eos", key, "")).strip_edges()
		if not from_file.is_empty():
			return from_file
	return str(ProjectSettings.get_setting("double_take/eos_" + key, "")).strip_edges()


func _watch_lobby() -> void:
	if current_lobby == null:
		return
	if not current_lobby.lobby_updated.is_connected(_sync_members):
		current_lobby.lobby_updated.connect(_sync_members)
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


func _new_room_code() -> String:
	var code := ""
	for _index in 6:
		code += CODE_ALPHABET[randi_range(0, CODE_ALPHABET.length() - 1)]
	return code


func _failed(message: String) -> void:
	failed.emit(message)
	status_changed.emit(message)
