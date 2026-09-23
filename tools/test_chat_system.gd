extends SceneTree

const NetworkSessionScript = preload("res://scripts/network_session.gd")
const ChatBoxScript = preload("res://scripts/chat_box.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("Starting Real-Time Chat automated test suite...")
	
	_test_lobby_chat()
	_test_meeting_living_chat()
	_test_meeting_ghost_chat_separation()
	_test_gameplay_chat_restrictions()
	_test_message_sanitization()
	await _test_chat_box_ui()
	
	print("ALL REAL-TIME CHAT TESTS PASSED!")
	quit(0)


func _setup_test_session() -> Node:
	var session = NetworkSessionScript.new()
	root.add_child(session)
	session.is_server = true
	session.room_code = "CHAT01"
	session.local_player_id = "host_id"
	session.minimum_players = 2
	session._create_server_world()
	
	session.players.clear()
	session.players["host_id"] = {
		"player_id": "host_id", "name": "HostCamper", "color": 0, "host": true,
		"ready": true, "connected": true, "peer_id": 1, "ghost": false
	}
	session.players["p2"] = {
		"player_id": "p2", "name": "PlayerTwo", "color": 1, "host": false,
		"ready": true, "connected": true, "peer_id": 102, "ghost": false
	}
	session.players["p3"] = {
		"player_id": "p3", "name": "PlayerThree", "color": 2, "host": false,
		"ready": true, "connected": true, "peer_id": 103, "ghost": false
	}
	session.peer_to_player[1] = "host_id"
	session.peer_to_player[102] = "p2"
	session.peer_to_player[103] = "p3"
	return session


func _test_lobby_chat() -> void:
	var session = _setup_test_session()
	session.match_running = false
	session.meeting_active = false
	
	var received_msgs: Array[Dictionary] = []
	session.chat_message_received.connect(func(msg: Dictionary) -> void: received_msgs.append(msg))
	
	# Host sends a message in lobby
	session.send_chat("Welcome to Camp Clear Lake!")
	
	assert(session.chat_history.size() == 1, "Chat history should contain 1 message")
	assert(session.chat_history[0]["sender_name"] == "HostCamper", "Sender name should be HostCamper")
	assert(session.chat_history[0]["text"] == "Welcome to Camp Clear Lake!", "Message text mismatch")
	assert(session.chat_history[0]["is_ghost"] == false, "Sender should not be ghost")
	assert(received_msgs.size() == 1, "Local host should have received the message via signal")
	
	session.queue_free()
	print("✓ Test 1 Passed: Lobby chat broadcast")


func _test_meeting_living_chat() -> void:
	var session = _setup_test_session()
	session.match_running = true
	session.meeting_active = true
	
	# Player 2 sends a message during meeting
	session._process_chat_message("p2", "I was doing lanterns at Lodge!")
	
	assert(session.chat_history.size() == 1, "Chat history should have 1 meeting message")
	var msg: Dictionary = session.chat_history[0]
	assert(msg["sender_name"] == "PlayerTwo", "Sender name should be PlayerTwo")
	assert(msg["sender_color"] == 1, "Sender color should be 1 (Blue)")
	assert(msg["in_meeting"] == true, "in_meeting should be true")
	assert(msg["is_ghost"] == false, "Living player should not be ghost")
	
	session.queue_free()
	print("✓ Test 2 Passed: Meeting living chat")


func _test_meeting_ghost_chat_separation() -> void:
	var session = _setup_test_session()
	session.match_running = true
	session.meeting_active = true
	
	# Mark Player 3 as ghost
	session.players["p3"]["ghost"] = true
	
	var host_received_msgs: Array[Dictionary] = []
	session.chat_message_received.connect(func(m: Dictionary) -> void: host_received_msgs.append(m))
	
	# Ghost player sends message
	session._process_chat_message("p3", "Red killed me at the dock!")
	
	# Check chat history
	assert(session.chat_history.size() == 1, "Chat history should contain ghost message")
	assert(session.chat_history[0]["is_ghost"] == true, "Message should be marked as ghost")
	
	# Host is living (not ghost), so host should NOT have received the ghost message!
	assert(host_received_msgs.is_empty(), "Living host must NOT receive ghost chat during match!")
	
	session.queue_free()
	print("✓ Test 3 Passed: Ghost chat separation (hidden from living campers)")


func _test_gameplay_chat_restrictions() -> void:
	var session = _setup_test_session()
	session.match_running = true
	session.meeting_active = false
	
	var failed_messages: Array[String] = []
	session.chat_action_failed.connect(func(msg: String) -> void: failed_messages.append(msg))
	
	# Living host tries to chat during gameplay
	session.send_chat("Hey guys!")
	assert(failed_messages.size() == 1, "Should have received 1 failure notification")
	assert(failed_messages[0].contains("only available during meetings"), "Living chat during gameplay should fail")
	assert(session.chat_history.is_empty(), "Failed message must not be in chat history")
	
	# Ghost tries to chat during gameplay -> allowed for ghosts
	session.players["p3"]["ghost"] = true
	session._process_chat_message("p3", "Ghost to ghost test")
	assert(session.chat_history.size() == 1, "Ghost chat during gameplay should be recorded")
	assert(session.chat_history[0]["text"] == "Ghost to ghost test", "Ghost text mismatch")
	
	session.queue_free()
	print("✓ Test 4 Passed: Gameplay chat restrictions (living blocked, ghosts allowed)")


func _test_message_sanitization() -> void:
	var session = _setup_test_session()
	session.match_running = false
	
	# 1. Empty message
	session.send_chat("   ")
	assert(session.chat_history.is_empty(), "Empty whitespace message should be ignored")
	
	# 2. Over-length message (> 120 chars)
	var long_text := "A".repeat(150)
	session.send_chat(long_text)
	assert(session.chat_history.size() == 1, "Over-length message should be stored")
	assert(session.chat_history[0]["text"].length() == 120, "Message should be truncated to 120 chars")
	
	session.queue_free()
	print("✓ Test 5 Passed: Message sanitization (empty ignored, capped at 120)")


func _test_chat_box_ui() -> void:
	var chat_box = ChatBoxScript.new()
	root.add_child(chat_box)
	await process_frame
	
	chat_box.setup(null, "p1", false)
	
	# Verify closed by default
	assert(chat_box.is_open == false, "Chat box should start closed")
	assert(chat_box.unread_count == 0, "Unread count should start at 0")
	
	# Add message while closed -> unread count should be 1
	chat_box.add_chat_message({
		"sender_name": "Orange", "sender_color": 0, "text": "Hello world!", "is_ghost": false
	})
	assert(chat_box.unread_count == 1, "Unread count should be 1 after receiving message while closed")
	assert(chat_box.unread_badge.visible == true, "Unread badge should be visible")
	assert(chat_box.unread_badge.text == "1", "Badge text should be 1")
	
	# Open chat box -> unread count resets to 0
	chat_box.set_chat_open(true)
	assert(chat_box.is_open == true, "Chat box should be open")
	assert(chat_box.unread_count == 0, "Unread count should reset to 0 on open")
	assert(chat_box.unread_badge.visible == false, "Unread badge should hide")
	
	# Test ghost mode
	chat_box.set_ghost_mode(true)
	assert(chat_box.header_title.text.contains("GHOST"), "Header title should reflect ghost mode")
	
	chat_box.queue_free()
	print("✓ Test 6 Passed: ChatBox UI component & unread notification system")
