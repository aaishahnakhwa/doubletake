extends SceneTree

const LobbyUIScript = preload("res://scripts/lobby_ui.gd")
const MeetingScreenScript = preload("res://scripts/meeting_screen.gd")
const NetworkSessionScript = preload("res://scripts/network_session.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("Starting Match Settings automated test suite...")
	await _test_server_settings_defaults_and_host_update()
	await _test_non_host_cannot_update_settings()
	await _test_lobby_ui_host_vs_non_host()
	await _test_meeting_discussion_phase()
	print("ALL MATCH SETTINGS TESTS PASSED!")
	quit(0)

func _test_server_settings_defaults_and_host_update() -> void:
	var session := NetworkSessionScript.new()
	root.add_child(session)
	await process_frame

	session.start_lan_host("127.0.0.1", "host_1", "HostPlayer", 0)
	await process_frame

	var state: Dictionary = session.current_lobby_state
	var settings: Dictionary = state.get("settings", {})
	assert(settings.get("kill_cooldown") == 25.0, "Default kill cooldown should be 25.0s")
	assert(settings.get("walking_pace") == 1.0, "Default walking pace should be 1.0x")
	assert(settings.get("discussion_time") == 15.0, "Default discussion time should be 15.0s")
	assert(settings.get("voting_time") == 45.0, "Default voting time should be 45.0s")

	# Host updates settings
	session.update_settings({
		"kill_cooldown": 35.0,
		"walking_pace": 1.5,
		"discussion_time": 30.0,
		"voting_time": 60.0
	})
	await process_frame

	state = session.current_lobby_state
	settings = state.get("settings", {})
	assert(settings.get("kill_cooldown") == 35.0, "Updated kill cooldown should be 35.0s")
	assert(settings.get("walking_pace") == 1.5, "Updated walking pace should be 1.5x")
	assert(settings.get("discussion_time") == 30.0, "Updated discussion time should be 30.0s")
	assert(settings.get("voting_time") == 60.0, "Updated voting time should be 60.0s")

	# Clamping check
	session.update_settings({
		"kill_cooldown": 999.0,
		"walking_pace": 0.1,
		"discussion_time": -10.0,
		"voting_time": 500.0
	})
	await process_frame

	settings = session.current_lobby_state.get("settings", {})
	assert(settings.get("kill_cooldown") == 60.0, "Kill cooldown should clamp to 60.0s")
	assert(settings.get("walking_pace") == 0.75, "Walking pace should clamp to 0.75x")
	assert(settings.get("discussion_time") == 0.0, "Discussion time should clamp to 0.0s")
	assert(settings.get("voting_time") == 120.0, "Voting time should clamp to 120.0s")

	session.disconnect_session()
	session.queue_free()
	print("✓ Test 1 Passed: Server settings defaults, host update, and value clamping")

func _test_non_host_cannot_update_settings() -> void:
	var session := NetworkSessionScript.new()
	root.add_child(session)
	await process_frame

	session.start_lan_host("127.0.0.1", "host_1", "HostPlayer", 0)
	await process_frame

	# Simulate a client player entry
	session.players["client_2"] = {
		"player_id": "client_2",
		"peer_id": 2,
		"name": "CamperTwo",
		"color": 1,
		"ready": false,
		"host": false,
		"connected": true,
		"role": "Camper"
	}

	var original_settings: Dictionary = session.current_lobby_state.get("settings", {}).duplicate(true)

	# Client attempts to update settings directly
	session._update_settings_for_player("client_2", {
		"kill_cooldown": 10.0,
		"walking_pace": 2.0,
		"discussion_time": 0.0,
		"voting_time": 15.0
	})
	await process_frame

	var current_settings: Dictionary = session.current_lobby_state.get("settings", {})
	assert(current_settings.get("kill_cooldown") == original_settings.get("kill_cooldown"), "Non-host cannot change kill cooldown")
	assert(current_settings.get("walking_pace") == original_settings.get("walking_pace"), "Non-host cannot change walking pace")
	assert(current_settings.get("discussion_time") == original_settings.get("discussion_time"), "Non-host cannot change discussion time")
	assert(current_settings.get("voting_time") == original_settings.get("voting_time"), "Non-host cannot change voting time")

	session.disconnect_session()
	session.queue_free()
	print("✓ Test 2 Passed: Server authoritatively rejects settings changes from non-host")

func _test_lobby_ui_host_vs_non_host() -> void:
	var lobby := LobbyUIScript.new()
	root.add_child(lobby)
	await process_frame

	var sample_state := {
		"room_code": "ABCD12",
		"players": [
			{"player_id": "host_1", "name": "HostPlayer", "color": 0, "ready": false, "host": true, "connected": true},
			{"player_id": "camper_2", "name": "CamperTwo", "color": 1, "ready": false, "host": false, "connected": true}
		],
		"settings": {
			"max_players": 4,
			"confirm_ejects": true,
			"player_names": true,
			"visual_tasks": true,
			"kill_cooldown": 25.0,
			"walking_pace": 1.0,
			"discussion_time": 15.0,
			"voting_time": 45.0
		},
		"minimum_players": 2
	}

	# 1. As Host
	lobby.show_lobby("host_1", sample_state)
	await process_frame

	assert(lobby.kill_cd_label.text == "25s", "Kill cooldown label should show 25s")
	assert(lobby.pace_label.text == "1.00x", "Walking pace label should show 1.00x")
	assert(lobby.disc_label.text == "15s", "Discussion time label should show 15s")
	assert(lobby.vote_label.text == "45s", "Voting time label should show 45s")

	assert(lobby.kill_cd_minus.visible == true, "Host can see kill cd minus button")
	assert(lobby.kill_cd_minus.disabled == false, "Host can use kill cd minus button")
	assert(lobby.pace_plus.visible == true, "Host can see pace plus button")
	assert(lobby.disc_plus.visible == true, "Host can see disc plus button")
	assert(lobby.vote_plus.visible == true, "Host can see vote plus button")

	# Test signal emission on stepper click
	var received_settings := [{}]
	lobby.settings_requested.connect(func(s: Dictionary) -> void: received_settings[0] = s)
	lobby._change_kill_cooldown(1)
	assert(received_settings[0].get("kill_cooldown") == 30.0, "Stepping kill cooldown should advance to 30.0s")

	lobby._change_walking_pace(1)
	assert(received_settings[0].get("walking_pace") == 1.25, "Stepping walking pace should advance to 1.25x")

	lobby._change_discussion_time(-1)
	assert(received_settings[0].get("discussion_time") == 10.0, "Stepping discussion time should step down to 10.0s")

	lobby._change_voting_time(1)
	assert(received_settings[0].get("voting_time") == 60.0, "Stepping voting time should advance to 60.0s")

	# 2. As Non-Host
	lobby.local_player_id = "camper_2"
	lobby.update_lobby(sample_state)
	await process_frame

	assert(lobby.kill_cd_label.text == "25s", "Non-host still sees 25s")
	assert(lobby.kill_cd_minus.visible == false, "Non-host cannot see minus button")
	assert(lobby.kill_cd_minus.disabled == true, "Non-host minus button disabled")
	assert(lobby.kill_cd_plus.visible == false, "Non-host cannot see plus button")
	assert(lobby.pace_minus.visible == false, "Non-host cannot see pace minus button")
	assert(lobby.disc_minus.visible == false, "Non-host cannot see disc minus button")
	assert(lobby.vote_minus.visible == false, "Non-host cannot see vote minus button")

	lobby.queue_free()
	print("✓ Test 3 Passed: Lobby UI displays values and restricts controls to host only")

func _test_meeting_discussion_phase() -> void:
	var meeting := MeetingScreenScript.new()
	var meeting_data := {
		"type": "emergency",
		"caller_id": "p1",
		"caller_name": "HostPlayer",
		"caller_color": 0,
		"victim_id": "",
		"victim_name": "",
		"victim_color": 0,
		"discussion_time": 10.0,
		"voting_time": 30.0,
		"players": [
			{"player_id": "p1", "name": "HostPlayer", "color": 0, "ghost": false, "connected": true},
			{"player_id": "p2", "name": "CamperTwo", "color": 1, "ghost": false, "connected": true}
		]
	}
	meeting.setup(meeting_data, "p1", true, null)
	root.add_child(meeting)
	await process_frame

	# Check discussion phase active
	assert(meeting.in_discussion_phase == true, "Meeting should start in discussion phase when discussion_time > 0")
	assert(meeting.timer_label.text.contains("DISCUSSION"), "Timer label should display DISCUSSION")
	assert(meeting.skip_btn.disabled == true, "Skip button must be disabled during discussion phase")

	# Card vote button should be disabled during discussion phase
	var p2_entry: Dictionary = meeting.card_entries["p2"]
	assert(p2_entry["vote_action_btn"].disabled == true, "Vote button must be disabled during discussion phase")

	# Attempting to click card during discussion phase should not select it
	meeting._on_card_clicked("p2")
	assert(meeting.selected_card_id == "", "Card selection must be ignored during discussion phase")

	# Simulate discussion timer completing
	meeting._process(10.5)
	await process_frame

	assert(meeting.in_discussion_phase == false, "Discussion phase should end after timer expires")
	assert(meeting.timer_label.text.contains("VOTING TIME"), "Timer label should now display VOTING TIME")
	assert(meeting.skip_btn.disabled == false, "Skip button should unlock after discussion phase")
	assert(p2_entry["vote_action_btn"].disabled == false, "Vote button should unlock after discussion phase")

	# Now card clicking should work
	meeting._on_card_clicked("p2")
	assert(meeting.selected_card_id == "p2", "Card can now be selected in voting phase")

	meeting.queue_free()
	print("✓ Test 4 Passed: Meeting screen discussion phase locks controls and transitions to voting")
