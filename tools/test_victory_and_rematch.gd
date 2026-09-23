extends SceneTree

const NetworkSessionScript = preload("res://scripts/network_session.gd")
const EndGameScreenScript = preload("res://scripts/end_game_screen.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("Starting Victory & Rematch automated test suite...")
	
	# Test 1: Task completion victory
	_test_task_victory()
	
	# Test 2: Killer ejection victory
	_test_killer_ejection_victory()
	
	# Test 3: 2-player 1v1 elimination victory
	_test_two_player_elimination_victory()
	
	# Test 4: 4-player parity elimination victory
	_test_four_player_parity_victory()
	
	# Test 5: Return to lobby flow
	_test_return_to_lobby_flow()
	
	# Test 6: Rematch flow
	_test_rematch_flow()

	# Test 7: EndGameScreen visual instantiation
	await _test_end_game_screen_ui()
	
	print("ALL VICTORY, WIN/LOSE SCREEN & REMATCH TESTS PASSED!")
	quit(0)


func _setup_test_session(player_count: int = 4) -> Node:
	var session = NetworkSessionScript.new()
	root.add_child(session)
	session.is_server = true
	session.room_code = "TEST01"
	session.local_player_id = "host_id"
	session.minimum_players = 2
	session._create_server_world()
	
	session.players.clear()
	session.players["host_id"] = {
		"player_id": "host_id", "name": "Host", "color": 0, "host": true,
		"connected": true, "ready": true, "peer_id": 1, "role": "Camper", "ghost": false,
		"tasks": ["lanterns", "generator"], "completed_tasks": []
	}
	
	for i in range(1, player_count):
		var pid := "player_%d" % i
		session.players[pid] = {
			"player_id": pid, "name": "Player%d" % i, "color": i, "host": false,
			"connected": true, "ready": true, "peer_id": 100 + i, "role": "Camper", "ghost": false,
			"tasks": ["lanterns"], "completed_tasks": []
		}
	
	return session


func _test_task_victory() -> void:
	var session = _setup_test_session(2)
	session.match_running = true
	session.shared_tasks_total = 2
	session.shared_tasks_completed = 1
	
	var res := {"winner": "", "reason": "", "outcome": {}}
	session.match_ended.connect(func(w: String, r: String, o: Dictionary) -> void:
		res["winner"] = w
		res["reason"] = r
		res["outcome"] = o
	)
	
	session.shared_tasks_completed = 2
	var won = session._check_victory_conditions()
	
	assert(won == true, "Task victory should trigger when all tasks completed")
	assert(res["winner"] == "Campers", "Winner should be Campers")
	assert(res["outcome"].has("players"), "Outcome must contain player summaries")
	assert(session.match_running == false, "Match running must be false after finish")
	print("✓ Test 1 Passed: Task completion victory")
	session.queue_free()


func _test_killer_ejection_victory() -> void:
	var session = _setup_test_session(3)
	session.match_running = true
	var killer_rec: Dictionary = session.players["player_1"]
	killer_rec["role"] = "Killer"
	session.players["player_1"] = killer_rec
	
	var res := {"winner": ""}
	session.match_ended.connect(func(w: String, _r: String, _o: Dictionary) -> void:
		res["winner"] = w
	)
	
	session.set_player_ghost("player_1", true)
	var won = session._check_victory_conditions()
	
	assert(won == true, "Campers should win when killer is ejected/eliminated")
	assert(res["winner"] == "Campers", "Winner should be Campers")
	print("✓ Test 2 Passed: Killer ejection victory")
	session.queue_free()


func _test_two_player_elimination_victory() -> void:
	var session = _setup_test_session(2)
	session.match_running = true
	var killer_rec: Dictionary = session.players["player_1"]
	killer_rec["role"] = "Killer"
	session.players["player_1"] = killer_rec
	
	var res := {"winner": ""}
	session.match_ended.connect(func(w: String, _r: String, _o: Dictionary) -> void:
		res["winner"] = w
	)
	
	var premature_win = session._check_victory_conditions()
	assert(premature_win == false, "1v1 starting state must NOT trigger premature victory")
	
	session.set_player_ghost("host_id", true)
	var won = session._check_victory_conditions()
	assert(won == true, "Killer should win when last camper is eliminated in 1v1")
	assert(res["winner"] == "Killer", "Winner must be Killer")
	print("✓ Test 3 Passed: 2-player 1v1 elimination victory")
	session.queue_free()


func _test_four_player_parity_victory() -> void:
	var session = _setup_test_session(4)
	session.match_running = true
	var killer_rec: Dictionary = session.players["player_3"]
	killer_rec["role"] = "Killer"
	session.players["player_3"] = killer_rec
	
	var res := {"winner": ""}
	session.match_ended.connect(func(w: String, _r: String, _o: Dictionary) -> void:
		res["winner"] = w
	)
	
	# 1 camper eliminated: 2 campers left vs 1 killer. Game must continue!
	session.set_player_ghost("player_1", true)
	var win1 = session._check_victory_conditions()
	assert(win1 == false, "Game must continue when 2 campers remain vs 1 killer")
	
	# 2nd camper eliminated: 1 camper left vs 1 killer (1 <= 1). Parity reached! Killer wins!
	session.set_player_ghost("player_2", true)
	var win2 = session._check_victory_conditions()
	assert(win2 == true, "Killer should win when parity (1 camper <= 1 killer) is reached in 3+ player match")
	assert(res["winner"] == "Killer", "Winner must be Killer")
	print("✓ Test 4 Passed: 4-player parity victory")
	session.queue_free()


func _test_return_to_lobby_flow() -> void:
	var session = _setup_test_session(3)
	session.match_running = true
	session.shared_tasks_completed = 2
	session.set_player_ghost("player_1", true)
	
	var res := {"returned": false}
	session.match_returned_to_lobby.connect(func() -> void:
		res["returned"] = true
	)
	
	session.request_return_to_lobby()
	
	assert(res["returned"] == true, "match_returned_to_lobby signal must fire")
	assert(session.match_running == false, "match_running must be false")
	assert(session.shared_tasks_completed == 0, "shared_tasks_completed must reset to 0")
	for pid: String in session.players:
		assert(session.players[pid]["ghost"] == false, "Player ghost flag must reset")
		assert(session.players[pid]["role"] == "", "Player role must reset to empty")
	print("✓ Test 5 Passed: Return to lobby flow")
	session.queue_free()


func _test_rematch_flow() -> void:
	var session = _setup_test_session(2)
	session.match_running = false
	
	var res := {"started": false}
	session.match_started.connect(func(_role: String, _state: Dictionary) -> void:
		res["started"] = true
	)
	
	session.request_rematch()
	
	assert(res["started"] == true, "match_started signal must fire on rematch")
	assert(session.match_running == true, "match_running must be true on rematch")
	var killer_found := false
	for pid: String in session.players:
		if session.players[pid].get("role", "") == "Killer":
			killer_found = true
	assert(killer_found == true, "New match must have an assigned killer")
	print("✓ Test 6 Passed: Rematch flow")
	session.queue_free()


func _test_end_game_screen_ui() -> void:
	var outcome := {
		"winner": "Campers",
		"reason": "All camp tasks were completed.",
		"killer_id": "player_1",
		"killer_name": "Slasher",
		"killer_color": 3,
		"players": [
			{"player_id": "host_id", "name": "Host", "color": 0, "role": "Camper", "ghost": false},
			{"player_id": "player_1", "name": "Slasher", "color": 3, "role": "Killer", "ghost": false},
			{"player_id": "player_2", "name": "Victim", "color": 1, "role": "Camper", "ghost": true}
		]
	}
	
	var screen = EndGameScreenScript.new()
	screen.setup(outcome, "host_id", true)
	root.add_child(screen)
	await process_frame
	
	assert(screen.title_label.text == "VICTORY", "Host camper should see VICTORY when Campers win")
	assert(is_instance_valid(screen.play_again_btn), "Host must have play again button")
	assert(is_instance_valid(screen.return_lobby_btn), "Host must have return to lobby button")
	
	var click_res := {"clicked": false}
	screen.play_again_pressed.connect(func() -> void: click_res["clicked"] = true)
	screen.play_again_btn.pressed.emit()
	assert(click_res["clicked"] == true, "Play again signal must emit when button pressed")
	
	screen.queue_free()
	await process_frame
	print("✓ Test 7 Passed: EndGameScreen visual instantiation & button signals")
