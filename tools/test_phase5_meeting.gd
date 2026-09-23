extends SceneTree

const NetworkSessionScript = preload("res://scripts/network_session.gd")
const ServerPlayerScript = preload("res://scripts/server_player.gd")
const MeetingScreenScript = preload("res://scripts/meeting_screen.gd")
const WorldScript = preload("res://scripts/camp_world.gd")
const HudScript = preload("res://scripts/camp_hud.gd")
const BodyScript = preload("res://scripts/camp_body.gd")
const CampBellScript = preload("res://scripts/camp_bell.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_camp_bell_presence()
	await _test_hud_confirmation_dialog()
	await _test_dead_body_scaling_and_cleanup()
	await _test_emergency_meeting_trigger()
	await _test_body_report_meeting()
	await _test_meeting_screen_ui()
	await _test_network_voting()
	print("Phase 5 meeting checks: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)


func _test_camp_bell_presence() -> void:
	var world = WorldScript.new()
	root.add_child(world)
	await process_frame
	
	var btn_stump := world.get_node_or_null("EmergencyMeetingStump")
	_check(btn_stump != null, "World contains EmergencyMeetingStump node near campfire")
	if btn_stump != null:
		_check(btn_stump is Node2D, "Emergency meeting stump is a Node2D")
		_check(btn_stump is AnimatedSprite2D, "Emergency meeting stump is an AnimatedSprite2D")
		_check(btn_stump.get_script() == CampBellScript, "Emergency meeting stump is a CampBell instance")
		_check(btn_stump.texture != null, "Emergency meeting stump has a texture")
		_check(btn_stump.texture.resource_path.contains("bell_") or btn_stump.texture.resource_path.contains("camp_bell") or btn_stump.texture.resource_path.contains("moving_bell"), "Camp bell texture is assigned")
		if btn_stump.has_method("ring"):
			btn_stump.ring(0.5)
			_check(btn_stump.is_ringing, "CampBell begins ringing when ring() is called")
	
	_check(world.is_near_emergency_button(WorldScript.EMERGENCY_BUTTON_POS), "Player at bell position is within proximity")
	_check(world.is_near_emergency_button(WorldScript.EMERGENCY_BUTTON_POS + Vector2(50, 0)), "Player 50px away is within proximity")
	_check(not world.is_near_emergency_button(Vector2.ZERO), "Player at origin is not within proximity of bell")
	
	world.queue_free()
	await process_frame


func _test_hud_confirmation_dialog() -> void:
	var hud := HudScript.new()
	root.add_child(hud)
	await process_frame
	
	_check(hud.confirm_dialog != null, "HUD creates confirmation dialog")
	_check(not hud.confirm_dialog.visible, "Confirmation dialog is initially hidden")
	
	hud.set_nearby_emergency_button(true)
	_check(hud.action_button.text == "RING BELL", "HUD prompts 'RING BELL' when near campfire bell")
	
	# Action button opens dialog
	hud.show_emergency_confirm_dialog()
	_check(hud.confirm_dialog.visible, "Confirmation dialog opens on request")
	
	# Cancel closes dialog
	hud._on_cancel_meeting()
	_check(not hud.confirm_dialog.visible, "Cancel closes confirmation dialog")
	
	# Confirm plays bell ringing animation on dialog, then emits emergency_meeting_requested
	var meeting_requested := {"fired": false}
	hud.emergency_meeting_requested.connect(func() -> void: meeting_requested["fired"] = true)
	hud.show_emergency_confirm_dialog()
	hud._on_confirm_meeting()
	_check(hud.confirm_bell_anim != null and hud.confirm_bell_anim.animation == "ring", "Confirm starts ringing animation on confirmation bell")
	
	# Wait for ringing animation to finish
	var wait_tree := root.create_tween()
	wait_tree.tween_interval(1.3)
	await wait_tree.finished
	
	_check(not hud.confirm_dialog.visible, "Confirm closes confirmation dialog after ringing completes")
	_check(meeting_requested["fired"], "Confirm button emits emergency_meeting_requested signal after ringing")
	
	# Moving away automatically dismisses dialog
	hud.show_emergency_confirm_dialog()
	hud.set_nearby_emergency_button(false)
	_check(not hud.confirm_dialog.visible, "Walking away automatically closes confirmation dialog")
	
	hud.queue_free()
	await process_frame


func _test_dead_body_scaling_and_cleanup() -> void:
	var body_node := BodyScript.new()
	root.add_child(body_node)
	await process_frame
	
	_check(body_node.body_sprite.scale.x >= 0.45 and body_node.body_sprite.scale.x <= 0.55, "Dead body sprite scale is properly proportioned (0.48)")
	
	body_node.setup({"name": "Victim", "reported": true, "color": 0})
	_check(not body_node.visible, "Dead body hides itself when reported")
	
	await process_frame


func _test_emergency_meeting_trigger() -> void:
	var session = await _session()
	var btn_pos := WorldScript.EMERGENCY_BUTTON_POS
	
	_add_player(session, "camper-1", "Camper", btn_pos, 0)
	_add_player(session, "camper-2", "Camper", Vector2(1000, 1000), 1)
	_add_player(session, "ghost-1", "Camper", btn_pos, 2)
	session.players["ghost-1"]["ghost"] = true
	
	# Ghost cannot call meeting
	session._start_emergency_meeting_for_player("ghost-1")
	_check(not session.meeting_active, "Ghost player cannot call an emergency meeting")
	
	# Distant player cannot call meeting
	session._start_emergency_meeting_for_player("camper-2")
	_check(not session.meeting_active, "Player far from campfire button cannot call emergency meeting")
	
	# Living player near button calls meeting
	var capture_emer := {"data": {}, "ended": false}
	session.meeting_started.connect(func(data: Dictionary) -> void: capture_emer["data"] = data)
	session._start_emergency_meeting_for_player("camper-1")
	
	_check(session.meeting_active, "Living player near campfire bell triggers emergency meeting")
	_check(str(session.current_meeting_data.get("type", "")) == "emergency", "Meeting type is emergency")
	_check(str(session.current_meeting_data.get("caller_id", "")) == "camper-1", "Caller ID is recorded correctly")
	_check(capture_emer["data"].has("players"), "Meeting broadcast contains player roster")
	
	var roster: Array = session.current_meeting_data.get("players", [])
	_check(roster.size() == 3, "All 3 players are included in meeting roster")
	
	# End meeting
	session.meeting_ended.connect(func() -> void: capture_emer["ended"] = true)
	session._end_meeting()
	_check(not session.meeting_active, "Meeting ends cleanly")
	_check(capture_emer["ended"], "meeting_ended signal emitted")
	
	session.queue_free()
	await process_frame


func _test_body_report_meeting() -> void:
	var session = await _session()
	var camp_pos := Vector2(1516, 1006)
	
	_add_player(session, "killer", "Killer", camp_pos, 3)
	_add_player(session, "victim", "Camper", camp_pos, 4)
	_add_player(session, "reporter", "Camper", camp_pos + Vector2(20, 0), 1)
	
	# Killer eliminates victim
	session._kill_nearest_for_player("killer")
	_check(session.bodies.has("victim"), "Victim body exists")
	
	# Verify body is in public_bodies before report
	var state_before: Dictionary = session._phase4_state_for("reporter")
	var has_body := false
	for b in state_before.get("bodies", []):
		if str(b.get("player_id", "")) == "victim":
			has_body = true
	_check(has_body, "Victim body is active in public_bodies before report")
	
	var capture_rep := {"data": {}}
	session.meeting_started.connect(func(data: Dictionary) -> void: capture_rep["data"] = data)
	
	# Reporter reports the body
	session._report_nearby_body_for_player("reporter")
	var meeting_data: Dictionary = capture_rep["data"]
	_check(session.meeting_active, "Reporting body starts a meeting")
	_check(str(meeting_data.get("type", "")) == "body_report", "Meeting type is body_report")
	_check(str(meeting_data.get("caller_id", "")) == "reporter", "Reporter ID is set")
	_check(str(meeting_data.get("victim_id", "")) == "victim", "Victim ID is set")
	
	# Verify reported body is removed from public_bodies
	var state_after: Dictionary = session._phase4_state_for("reporter")
	var body_remains := false
	for b in state_after.get("bodies", []):
		if str(b.get("player_id", "")) == "victim":
			body_remains = true
	_check(not body_remains, "Reported body disappears from public_bodies upon report")
	
	# Verify victim is ghost in roster
	var victim_in_roster := false
	for p: Dictionary in meeting_data.get("players", []):
		if str(p.get("player_id", "")) == "victim":
			victim_in_roster = true
			_check(bool(p.get("ghost", false)), "Victim is marked as ghost in meeting roster")
	_check(victim_in_roster, "Victim is present in meeting roster")
	
	session._end_meeting()
	session.queue_free()
	await process_frame


func _test_meeting_screen_ui() -> void:
	var screen := MeetingScreenScript.new()
	var test_data := {
		"type": "body_report",
		"caller_id": "p1",
		"caller_name": "Ayaan",
		"caller_color": 0,
		"victim_id": "p2",
		"victim_name": "Riya",
		"victim_color": 1,
		"players": [
			{"player_id": "p1", "name": "Ayaan", "color": 0, "ghost": false, "connected": true},
			{"player_id": "p2", "name": "Riya", "color": 1, "ghost": true, "connected": true},
			{"player_id": "p3", "name": "Kabir", "color": 2, "ghost": false, "connected": true}
		]
	}
	screen.setup(test_data, "p1", true)
	root.add_child(screen)
	await process_frame
	
	_check(screen.PORTRAIT_TEXTURES.size() == 6, "All 6 camper portrait textures are loaded")
	_check(screen.in_reveal_phase, "Body report meeting starts in reveal phase")
	_check(screen.reveal_box != null and screen.reveal_box.visible, "Reveal box is visible during reveal phase")
	_check(screen.reveal_cards_row.get_child_count() == 1, "Only eliminated victim card is spotlighted during reveal phase")
	_check(not screen.cards_grid.visible, "Full cards grid is hidden during reveal phase")
	
	# End reveal phase
	screen._end_reveal()
	_check(not screen.in_reveal_phase, "Reveal phase ends cleanly")
	_check(screen.cards_grid.visible, "Full cards grid becomes visible after reveal phase")
	_check(screen.cards_grid.get_child_count() == 3, "All three player cards are displayed")
	_check(screen.banner_rect != null and screen.banner_rect.texture != null, "Banner texture is displayed")
	_check(screen.dismiss_button != null and screen.dismiss_button.visible, "Dismiss button is present")
	
	# Test voting UI interactions
	_check(screen.skip_btn != null and screen.skip_btn.visible, "Skip Vote button is present in meeting footer")
	_check(screen.card_entries["p3"]["vote_action_btn"] != null, "Vote action button exists below living player profile")
	_check(screen.card_entries["p3"]["vote_action_btn"].visible, "Vote action button is visible below player profile before selection")
	_check(screen.card_entries["p2"]["eliminated_btn"] != null, "Eliminated button exists below dead player profile")
	_check(screen.card_entries["p2"]["eliminated_btn"].disabled, "Eliminated button below dead player profile is disabled")
	
	var vote_cast_capture := {"target": ""}
	screen.vote_cast.connect(func(tgt: String) -> void: vote_cast_capture["target"] = tgt)
	
	# Clicking living player card or its vote button selects it
	screen._on_card_clicked("p3")
	_check(screen.selected_card_id == "p3", "Clicking living player card selects it for voting")
	_check(screen.card_entries["p3"]["sel_border"].visible, "Selected card shows highlight border")
	_check(not screen.card_entries["p3"]["vote_action_btn"].visible, "Vote action button is replaced by confirmation row when selected")
	_check(screen.card_entries["p3"]["vote_confirm_row"].visible, "Selected card shows vote confirmation buttons below profile")
	
	# Deselect restores the vote action button
	screen._deselect_card()
	_check(screen.card_entries["p3"]["vote_action_btn"].visible, "Vote action button is restored when deselected")
	_check(not screen.card_entries["p3"]["vote_confirm_row"].visible, "Vote confirmation row hidden when deselected")
	
	# Select and confirm vote
	screen._select_card("p3")
	screen._confirm_vote("p3")
	_check(screen.local_voted, "Local player marked as voted")
	_check(vote_cast_capture["target"] == "p3", "vote_cast signal emitted with selected player ID")
	_check(screen.card_entries["p1"]["voted_badge"].visible, "Voted badge is displayed on local card")
	_check(screen.card_entries["p3"]["vote_action_btn"].disabled, "Vote buttons become disabled after voting")
	
	# Test skip vote flow on a separate screen
	var skip_screen := MeetingScreenScript.new()
	skip_screen.setup(test_data, "p1", true)
	root.add_child(skip_screen)
	await process_frame
	skip_screen._end_reveal()
	
	var skip_capture := {"target": ""}
	skip_screen.vote_cast.connect(func(tgt: String) -> void: skip_capture["target"] = tgt)
	skip_screen._on_skip_clicked()
	_check(skip_screen.skip_confirm_box.visible, "Skip button displays confirmation sub-row")
	skip_screen._on_skip_confirmed()
	_check(skip_screen.local_voted, "Local player marked as voted on skip")
	_check(skip_capture["target"] == "skip", "vote_cast signal emitted with 'skip'")
	
	# Test results display and ejection overlay
	var test_results := {
		"outcome_type": "ejected",
		"ejected_id": "p3",
		"ejected_name": "Kabir",
		"ejected_role": "Camper",
		"votes": {"p1": "p3", "p2": "p3"},
		"tally": {"p3": 2}
	}
	skip_screen.show_voting_results(test_results)
	_check(skip_screen.in_results_phase, "Screen enters results phase")
	_check(skip_screen.outcome_overlay.visible, "Outcome overlay becomes visible on voting results")
	_check(skip_screen.outcome_title.text.contains("Kabir was ejected"), "Outcome title displays ejected camper name")
	_check(skip_screen.outcome_subtitle.text.contains("Camper"), "Outcome subtitle displays ejected role")
	
	skip_screen.queue_free()
	
	var capture_ui := {"dismissed": false}
	screen.meeting_dismissed.connect(func() -> void: capture_ui["dismissed"] = true)
	screen._on_dismiss()
	_check(capture_ui["dismissed"], "Meeting screen emits meeting_dismissed on dismiss")
	
	# Test emergency meeting starts directly without reveal phase
	var emer_screen := MeetingScreenScript.new()
	var emer_data := {
		"type": "emergency", "caller_id": "p1", "caller_name": "Ayaan", "caller_color": 0,
		"victim_id": "", "victim_name": "", "victim_color": 0,
		"players": [{"player_id": "p1", "name": "Ayaan", "color": 0, "ghost": false, "connected": true}]
	}
	emer_screen.setup(emer_data, "p1", true)
	root.add_child(emer_screen)
	await process_frame
	_check(not emer_screen.in_reveal_phase, "Emergency meeting skips reveal phase and opens directly")
	_check(emer_screen.cards_grid.visible, "Emergency meeting displays cards grid immediately")
	emer_screen.queue_free()
	
	await process_frame


func _test_network_voting() -> void:
	var session = await _session()
	var btn_pos := WorldScript.EMERGENCY_BUTTON_POS
	
	_add_player(session, "camper-1", "Camper", btn_pos, 0)
	_add_player(session, "camper-2", "Camper", Vector2(1000, 1000), 1)
	_add_player(session, "camper-3", "Camper", Vector2(1000, 1050), 2)
	
	# Start emergency meeting
	session._start_emergency_meeting_for_player("camper-1")
	_check(session.meeting_active, "Meeting is active for voting test")
	_check(session.votes.is_empty(), "Votes are empty at meeting start")
	
	var capture_voted := {"voters": []}
	session.player_voted.connect(func(vid: String) -> void: capture_voted["voters"].append(vid))
	
	var capture_results := {"data": {}}
	session.voting_results_received.connect(func(res: Dictionary) -> void: capture_results["data"] = res)
	
	# Camper 1 votes for camper 3
	session._record_vote("camper-1", "camper-3")
	_check(session.votes["camper-1"] == "camper-3", "Camper 1 vote recorded for camper 3")
	_check(capture_voted["voters"].has("camper-1"), "player_voted signal emitted for camper-1")
	
	# Duplicate vote is ignored
	session._record_vote("camper-1", "camper-2")
	_check(session.votes["camper-1"] == "camper-3", "Duplicate vote is rejected")
	
	# Camper 2 votes for camper 3
	session._record_vote("camper-2", "camper-3")
	_check(session.votes["camper-2"] == "camper-3", "Camper 2 vote recorded for camper 3")
	
	# Camper 3 skips vote
	session._record_vote("camper-3", "skip")
	_check(session.votes["camper-3"] == "skip", "Camper 3 vote recorded as skip")
	
	# All 3 living players have voted -> auto tally!
	var res: Dictionary = session.voting_results
	_check(not res.is_empty(), "Voting results produced after all living players vote")
	_check(str(res.get("outcome_type", "")) == "ejected", "Outcome is ejected when majority votes for camper 3")
	_check(str(res.get("ejected_id", "")) == "camper-3", "Camper 3 is ejected")
	_check(bool(session.players["camper-3"]["ghost"]), "Ejected player is marked as ghost")
	
	# Test skip vote outcome: reset and run skip vote test
	session._end_meeting()
	session.players["camper-3"]["ghost"] = false
	session._start_emergency_meeting_for_player("camper-1")
	
	session._record_vote("camper-1", "skip")
	session._record_vote("camper-2", "skip")
	session._record_vote("camper-3", "camper-1")
	
	var skip_res: Dictionary = session.voting_results
	_check(str(skip_res.get("outcome_type", "")) == "skip", "Outcome is skip when skip receives majority")
	_check(str(skip_res.get("ejected_id", "")).is_empty(), "No player is ejected when skip wins")
	_check(not bool(session.players["camper-1"]["ghost"]), "Camper 1 remains alive")
	
	# Test tie vote outcome: reset and run tie vote test
	session._end_meeting()
	session._start_emergency_meeting_for_player("camper-1")
	session._record_vote("camper-1", "camper-2")
	session._record_vote("camper-2", "camper-3")
	session._record_vote("camper-3", "skip")
	
	var tie_res: Dictionary = session.voting_results
	_check(str(tie_res.get("outcome_type", "")) == "tie", "Outcome is tie when votes are tied")
	_check(str(tie_res.get("ejected_id", "")).is_empty(), "No player is ejected on tie")
	
	session._end_meeting()
	session.queue_free()
	await process_frame


func _session():
	var session = NetworkSessionScript.new()
	root.add_child(session)
	await process_frame
	session.is_server = true
	session.is_eos_p2p = true
	session.match_running = true
	session.room_code = "PHASE5"
	session._create_server_world()
	await physics_frame
	return session


func _add_player(session, player_id: String, role: String, at: Vector2, color: int = 0) -> void:
	session.players[player_id] = {
		"player_id": player_id, "peer_id": 1 if player_id == "killer" or player_id == "camper-1" else 0,
		"name": player_id, "color": color, "ready": true, "host": player_id == "killer" or player_id == "camper-1",
		"connected": true, "role": role, "ghost": false, "tasks": [], "completed_tasks": [],
		"sabotage_objectives": [], "completed_sabotages": []
	}
	var body = ServerPlayerScript.new()
	body.global_position = at
	session.server_world.add_child(body)
	session.server_bodies[player_id] = body


func _check(success: bool, description: String) -> void:
	if not success:
		failures += 1
		push_error("FAIL: " + description)
