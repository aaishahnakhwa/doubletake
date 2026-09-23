extends SceneTree

const LobbyUIScript = preload("res://scripts/lobby_ui.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var lobby := LobbyUIScript.new()
	root.add_child(lobby)
	
	var sample_state := {
		"room_code": "CAMP77",
		"players": [
			{"player_id": "host_1", "name": "Ranger Rick", "color": 0, "ready": true, "host": true, "connected": true},
			{"player_id": "camper_2", "name": "Sammy", "color": 1, "ready": false, "host": false, "connected": true},
			{"player_id": "camper_3", "name": "Alex", "color": 2, "ready": true, "host": false, "connected": true},
			{"player_id": "camper_4", "name": "Maya", "color": 3, "ready": false, "host": false, "connected": true}
		],
		"settings": {
			"max_players": 6,
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
	
	# 1. Host Mode
	lobby.show_lobby("host_1", sample_state)
	for i in range(5):
		await process_frame
		
	var img := root.get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("C:/Users/saule/.gemini/antigravity/brain/17a13079-7005-4717-99fb-b563640774d7/lobby_characters_host.png")
		print("Saved host characters preview!")

	# 2. Camper View-Only Mode
	lobby.local_player_id = "camper_2"
	lobby.update_lobby(sample_state)
	for i in range(5):
		await process_frame
		
	img = root.get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("C:/Users/saule/.gemini/antigravity/brain/17a13079-7005-4717-99fb-b563640774d7/lobby_characters_camper.png")
		print("Saved camper characters preview!")

	lobby.queue_free()
	quit(0)
