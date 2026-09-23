extends SceneTree

const HudScript = preload("res://scripts/camp_hud.gd")
const MeetingScreenScript = preload("res://scripts/meeting_screen.gd")
const NetworkSessionScript = preload("res://scripts/network_session.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("Starting Leave Match & Auto-Tasks automated test suite...")
	await _test_auto_tasks_visibility()
	await _test_hud_leave_dialog()
	await _test_meeting_leave_dialog()
	await _test_session_disconnect_signal()
	print("ALL LEAVE MATCH & AUTO-TASKS TESTS PASSED!")
	quit(0)

func _test_auto_tasks_visibility() -> void:
	var hud := HudScript.new()
	root.add_child(hud)
	await process_frame
	
	# Initial task state
	var sample_tasks := {
		"tasks": [
			{"id": "generator", "name": "Fix the generator", "completed": false},
			{"id": "radio", "name": "Realign radio antenna", "completed": false}
		],
		"completed": 0,
		"total": 2
	}
	hud.set_task_state(sample_tasks)
	
	# Verify zone card is visible automatically even in mobile_mode
	assert(hud.zone_card.visible, "Zone card should be visible automatically when tasks exist")
	assert(hud.task_list.visible, "Task list should be visible")
	assert(hud.task_progress.visible, "Task progress bar should be visible")
	assert(hud.task_toggle_btn.visible, "Task toggle collapse button should be visible")
	
	# Verify task list text includes location annotations
	var list_text: String = hud.task_list.text
	assert(list_text.contains("Workshop"), "Task text should mention Workshop")
	assert(list_text.contains("Gate Office"), "Task text should mention Gate Office")
	assert(list_text.contains("○"), "Incomplete task should have open circle")
	
	# Test collapse toggle
	assert(not hud.task_card_collapsed, "Task card initially not collapsed")
	hud.task_toggle_btn.pressed.emit()
	assert(hud.task_card_collapsed, "Task card should now be collapsed")
	assert(not hud.task_list.visible, "Task list should be hidden when collapsed")
	assert(hud.task_toggle_btn.text == "+", "Button text should be + when collapsed")
	
	hud.task_toggle_btn.pressed.emit()
	assert(not hud.task_card_collapsed, "Task card should now be expanded")
	assert(hud.task_list.visible, "Task list should be visible when expanded")
	assert(hud.task_toggle_btn.text == "−", "Button text should be − when expanded")
	
	hud.queue_free()
	print("✓ Test 1 Passed: Auto-tasks display, location tagging, and collapse toggle")

func _test_hud_leave_dialog() -> void:
	var hud := HudScript.new()
	root.add_child(hud)
	await process_frame
	
	assert(is_instance_valid(hud.leave_button), "Leave button should exist on HUD")
	assert(is_instance_valid(hud.leave_dialog), "Leave dialog should exist on HUD")
	assert(not hud.leave_dialog.visible, "Leave dialog should initially be hidden")
	
	# Test client mode
	hud.is_host = false
	hud.show_leave_dialog()
	assert(hud.leave_dialog.visible, "Leave dialog should be visible after show_leave_dialog()")
	assert(not hud.leave_return_lobby_btn.visible, "Return to lobby button should be hidden for client")
	
	# Test leave_match_requested signal using array for closure mutation
	var leave_emitted := [false]
	hud.leave_match_requested.connect(func() -> void: leave_emitted[0] = true)
	hud.leave_quit_btn.pressed.emit()
	assert(leave_emitted[0], "leave_match_requested signal should be emitted")
	assert(not hud.leave_dialog.visible, "Leave dialog should close after pressing leave")
	
	# Test host mode
	hud.is_host = true
	hud.show_leave_dialog()
	assert(hud.leave_dialog.visible, "Leave dialog should be visible after show_leave_dialog()")
	assert(hud.leave_return_lobby_btn.visible, "Return to lobby button should be visible for host")
	
	var return_lobby_emitted := [false]
	hud.return_to_lobby_requested.connect(func() -> void: return_lobby_emitted[0] = true)
	hud.leave_return_lobby_btn.pressed.emit()
	assert(return_lobby_emitted[0], "return_to_lobby_requested signal should be emitted")
	assert(not hud.leave_dialog.visible, "Leave dialog should close after pressing return to lobby")
	
	hud.queue_free()
	print("✓ Test 2 Passed: HUD leave dialog, host/client options, and signals")

func _test_meeting_leave_dialog() -> void:
	var meeting_screen := MeetingScreenScript.new()
	var sample_meeting := {
		"type": "emergency",
		"caller_name": "Player 1",
		"players": [
			{"player_id": "p1", "name": "Player 1", "ghost": false, "color_index": 0},
			{"player_id": "p2", "name": "Player 2", "ghost": false, "color_index": 1}
		]
	}
	meeting_screen.setup(sample_meeting, "p1", true, null)
	root.add_child(meeting_screen)
	await process_frame
	
	assert(is_instance_valid(meeting_screen.leave_btn), "Leave button should exist on Meeting screen")
	assert(is_instance_valid(meeting_screen.leave_dialog), "Leave dialog should exist on Meeting screen")
	assert(not meeting_screen.leave_dialog.visible, "Leave dialog should initially be hidden")
	
	meeting_screen.show_leave_dialog()
	assert(meeting_screen.leave_dialog.visible, "Leave dialog should be visible")
	assert(meeting_screen.leave_return_lobby_btn.visible, "Host should see return to lobby button")
	
	var return_lobby_emitted := [false]
	meeting_screen.return_to_lobby_requested.connect(func() -> void: return_lobby_emitted[0] = true)
	meeting_screen.leave_return_lobby_btn.pressed.emit()
	assert(return_lobby_emitted[0], "Meeting return_to_lobby_requested should be emitted")
	
	var leave_emitted := [false]
	meeting_screen.leave_match_requested.connect(func() -> void: leave_emitted[0] = true)
	meeting_screen.show_leave_dialog()
	meeting_screen.leave_quit_btn.pressed.emit()
	assert(leave_emitted[0], "Meeting leave_match_requested should be emitted")
	
	meeting_screen.queue_free()
	print("✓ Test 3 Passed: Meeting screen leave button, dialog, and signals")

func _test_session_disconnect_signal() -> void:
	var session := NetworkSessionScript.new()
	root.add_child(session)
	await process_frame
	
	var disconnect_count := [0]
	var join_failure_count := [0]
	session.session_disconnected.connect(func() -> void: disconnect_count[0] += 1)
	session.join_failed.connect(func(_message: String) -> void: join_failure_count[0] += 1)

	# Room creation/joining resets stale transport state internally. That reset
	# must never tell App to leave the EOS lobby that was just created or joined.
	session._reset_session_state()
	assert(disconnect_count[0] == 0, "Internal transport reset must not emit session_disconnected")

	session.disconnect_session()
	await process_frame
	assert(disconnect_count[0] == 1, "Explicit disconnect_session() must emit exactly one departure signal")
	assert(join_failure_count[0] == 0, "An intentional disconnect must not report a connection failure")

	# A drop before receive_join_success is an initial join failure, not an
	# in-game reconnect.
	session.manual_disconnect = false
	session.is_server = false
	session.is_eos_p2p = false
	session.transport_events_armed = true
	session.local_token = "dev:new-player:guest"
	session.has_joined_session = false
	session._on_server_disconnected()
	assert(not session.reconnecting, "A first-time join failure must not enter reconnect mode")
	assert(join_failure_count[0] == 1, "A first-time join failure must report one terminal error")

	# After admission, the same transport loss is a real reconnect.
	session.connection_failure_emitted = false
	session.manual_disconnect = false
	session.transport_events_armed = true
	session.local_token = "dev:joined-player:guest"
	session.has_joined_session = true
	session._on_server_disconnected()
	assert(session.reconnecting, "An admitted player should enter reconnect mode after a connection loss")

	session.disconnect_session()
	session.queue_free()
	print("✓ Test 4 Passed: room setup, departure, initial failure, and reconnect states stay separate")
