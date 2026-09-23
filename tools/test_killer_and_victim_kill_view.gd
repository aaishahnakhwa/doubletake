extends SceneTree

const MultiplayerGameScript = preload("res://scripts/multiplayer_game.gd")
const NetworkSessionScript = preload("res://scripts/network_session.gd")
const ActorScript = preload("res://scripts/camp_actor.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("Starting Killer vs Victim Kill View automated test suite...")
	await _test_killer_view()
	await _test_victim_view()
	await _test_bystander_view()
	print("ALL KILLER & VICTIM VIEW TESTS PASSED!")
	quit(0)

func _test_killer_view() -> void:
	var session: Node = NetworkSessionScript.new()
	session.local_player_id = "killer_p1"
	session.local_role = "Killer"
	root.add_child(session)

	var game: Node2D = MultiplayerGameScript.new()
	game.session = session
	root.add_child(game)
	await process_frame
	
	# Create actors for killer and victim
	var killer_actor: CharacterBody2D = ActorScript.new()
	killer_actor.is_local = true
	game.actors.add_child(killer_actor)
	game.actor_by_id["killer_p1"] = killer_actor
	game.player = killer_actor
	
	var victim_actor: CharacterBody2D = ActorScript.new()
	victim_actor.is_local = false
	game.actors.add_child(victim_actor)
	game.actor_by_id["victim_p2"] = victim_actor
	
	var kill_body := {
		"player_id": "victim_p2",
		"name": "VictimCamper",
		"killer_id": "killer_p1",
		"at": Vector2(200, 200),
		"color": 1,
		"killer_color": 3,
		"context": {"id": "normal", "name": "Normal"}
	}
	
	# Trigger kill cinematic logic
	game._start_kill_cinematic(kill_body)
	await process_frame
	
	# Verify killer does NOT have active_kill_cinematic
	assert(game.active_kill_cinematic == null, "Killer must NOT have a separate kill screen/cinematic overlay!")
	assert(not game.player.input_locked, "Killer input must NOT be locked during a kill!")
	
	# Trigger in-world presentation
	game.phase4_state = {
		"bodies": [kill_body],
		"player_states": {
			"killer_p1": {"ghost": false},
			"victim_p2": {"ghost": true}
		}
	}
	game._apply_phase4_visuals(false)
	await process_frame
	
	# Verify body marker is created on the map
	assert(game.bodies_by_id.has("victim_p2"), "Dead body marker must be spawned on the map")
	
	game.queue_free()
	session.queue_free()
	await process_frame
	print("✓ Test 1 Passed: Killer stays on map without any separate screen, input unlocked")

func _test_victim_view() -> void:
	var session: Node = NetworkSessionScript.new()
	session.local_player_id = "victim_p2"
	session.local_role = "Camper"
	root.add_child(session)

	var game: Node2D = MultiplayerGameScript.new()
	game.session = session
	root.add_child(game)
	await process_frame
	
	var victim_actor: CharacterBody2D = ActorScript.new()
	victim_actor.is_local = true
	game.actors.add_child(victim_actor)
	game.actor_by_id["victim_p2"] = victim_actor
	game.player = victim_actor
	
	var kill_body := {
		"player_id": "victim_p2",
		"name": "VictimCamper",
		"killer_id": "killer_p1",
		"at": Vector2(200, 200),
		"color": 1,
		"killer_color": 3,
		"context": {"id": "normal", "name": "Normal"}
	}
	
	# Trigger kill cinematic logic for victim
	game._start_kill_cinematic(kill_body)
	await process_frame
	
	# Verify victim DOES have active_kill_cinematic
	assert(game.active_kill_cinematic != null, "Victim camper MUST receive the kill cinematic overlay screen!")
	assert(game.player.input_locked, "Victim camper input must be locked during the elimination sequence!")
	
	game.queue_free()
	session.queue_free()
	await process_frame
	print("✓ Test 2 Passed: Victim receives dramatic elimination cinematic screen")

func _test_bystander_view() -> void:
	var session: Node = NetworkSessionScript.new()
	session.local_player_id = "bystander_p3"
	session.local_role = "Camper"
	root.add_child(session)

	var game: Node2D = MultiplayerGameScript.new()
	game.session = session
	root.add_child(game)
	await process_frame
	
	var bystander_actor: CharacterBody2D = ActorScript.new()
	bystander_actor.is_local = true
	game.actors.add_child(bystander_actor)
	game.actor_by_id["bystander_p3"] = bystander_actor
	game.player = bystander_actor
	
	var kill_body := {
		"player_id": "victim_p2",
		"name": "VictimCamper",
		"killer_id": "killer_p1",
		"at": Vector2(200, 200),
		"color": 1,
		"killer_color": 3,
		"context": {"id": "normal", "name": "Normal"}
	}
	
	# Trigger kill cinematic logic for bystander
	game._start_kill_cinematic(kill_body)
	await process_frame
	
	# Verify bystander does NOT have active_kill_cinematic
	assert(game.active_kill_cinematic == null, "Bystander must NOT have a kill cinematic overlay screen!")
	assert(not game.player.input_locked, "Bystander input must NOT be locked!")
	
	game.queue_free()
	session.queue_free()
	await process_frame
	print("✓ Test 3 Passed: Bystanders do not get any screen takeover and see kill in-world")
