extends SceneTree

const CustomizationCatalog = preload("res://scripts/customization_catalog.gd")
const NetworkSessionScript = preload("res://scripts/network_session.gd")
const ActorScript = preload("res://scripts/camp_actor.gd")
const LobbyUIScript = preload("res://scripts/lobby_ui.gd")

func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("Starting Dedicated Skins System Test Suite...")
	
	# ----------------------------------------------------
	# Test 1: CustomizationCatalog looks & skin portraits
	# ----------------------------------------------------
	var look_ids := CustomizationCatalog.get_all_look_ids()
	assert("classic" in look_ids, "Missing classic look")
	assert("ranger" in look_ids, "Missing ranger look")
	assert("winter" in look_ids, "Missing winter look")
	assert("detective" in look_ids, "Missing detective look")
	assert("scout" in look_ids, "Missing scout look")
	
	for lid in look_ids:
		var look: Dictionary = CustomizationCatalog.get_look(lid)
		assert(not look.is_empty(), "Look dict empty for: " + lid)
		assert(CustomizationCatalog.get_icon_texture(look["icon"]) != null, "Missing icon for: " + lid)
		for c_idx in range(6):
			var tex := CustomizationCatalog.get_skin_portrait(lid, c_idx)
			assert(tex != null, "Missing skin portrait: %s color %d" % [lid, c_idx])

	print("[PASS] Test 1: CustomizationCatalog verified for all 5 looks across all 6 colors.")

	# ----------------------------------------------------
	# Test 2: Local Persistence
	# ----------------------------------------------------
	var test_data := {
		"color": 3,
		"look": "ranger"
	}
	CustomizationCatalog.save_local_customization(test_data)
	var loaded := CustomizationCatalog.load_local_customization()
	assert(loaded["color"] == 3, "Color mismatch in local save")
	assert(loaded["look"] == "ranger", "Look mismatch in local save")
	print("[PASS] Test 2: Local persistence save and load verified.")

	# ----------------------------------------------------
	# Test 3: NetworkSession Customization Sync
	# ----------------------------------------------------
	var session := NetworkSessionScript.new()
	root.add_child(session)
	session.start_server(7200, "SKIN77", "dev", 2)
	
	var peer_claims := {"player_id": "host_player", "host": true}
	session._accept_join_request(1, peer_claims, "Host", 0)
	assert(session.players["host_player"]["look"] == "classic", "Default look should be classic")
	
	# Update customization
	session._set_customization_for_player("host_player", 1, "winter", "")
	assert(session.players["host_player"]["color"] == 1, "Color should update to 1")
	assert(session.players["host_player"]["look"] == "winter", "Look should update to winter")
	
	var lobby_state := session._make_lobby_state()
	var p_entry := {}
	for p: Dictionary in lobby_state["players"]:
		if p["player_id"] == "host_player":
			p_entry = p
			break
	assert(p_entry["look"] == "winter", "Lobby state look missing")
	print("[PASS] Test 3: NetworkSession customization sync verified.")

	# ----------------------------------------------------
	# Test 4: CampActor Dedicated Skin
	# ----------------------------------------------------
	var actor := ActorScript.new()
	root.add_child(actor)
	actor.sprite_variant = 2
	actor.set_customization("detective")
	assert(actor.look_id == "detective", "Actor look_id should be detective")
	assert(actor.sprite.texture != null, "Actor sprite texture should not be null")
	print("[PASS] Test 4: CampActor dedicated skin verified.")

	# ----------------------------------------------------
	# Test 5: Render Visual Artifacts
	# ----------------------------------------------------
	var lobby_ui := LobbyUIScript.new()
	root.add_child(lobby_ui)
	
	# Populate lobby state with players showing all 5 looks
	var test_lobby_state := {
		"room_code": "SKINS5",
		"settings": {
			"kill_cooldown": 25.0,
			"walking_pace": 1.0,
			"discussion_time": 15.0,
			"voting_time": 30.0,
			"max_players": 6,
			"confirm_ejects": true,
			"player_names": true,
			"visual_tasks": true
		},
		"players": [
			{"player_id": "p1", "name": "Host Ranger", "color": 0, "look": "ranger", "hat": "ranger", "ready": true, "host": true, "connected": true},
			{"player_id": "p2", "name": "Winter Boy", "color": 1, "look": "winter", "hat": "winter", "ready": true, "host": false, "connected": true},
			{"player_id": "p3", "name": "Detective Q", "color": 2, "look": "detective", "hat": "detective", "ready": false, "host": false, "connected": true},
			{"player_id": "p4", "name": "Scout Sam", "color": 3, "look": "scout", "hat": "scout", "ready": true, "host": false, "connected": true},
			{"player_id": "p5", "name": "Retro Dan", "color": 4, "look": "classic", "hat": "classic", "ready": false, "host": false, "connected": true},
		]
	}
	
	lobby_ui.set_local_player("p1", true)
	lobby_ui.update_lobby(test_lobby_state)
	
	# Wait 2 frames to layout
	await process_frame
	await process_frame
	
	# Capture Roster
	var img_roster := root.get_texture().get_image()
	img_roster.save_png("C:/Users/saule/.gemini/antigravity/brain/17a13079-7005-4717-99fb-b563640774d7/lobby_skins_roster.png")
	print("Saved lobby_skins_roster.png")
	
	# Open Wardrobe Modal and capture
	lobby_ui._open_wardrobe_modal()
	await process_frame
	await process_frame
	
	var img_wardrobe := root.get_texture().get_image()
	img_wardrobe.save_png("C:/Users/saule/.gemini/antigravity/brain/17a13079-7005-4717-99fb-b563640774d7/wardrobe_skins_preview.png")
	print("Saved wardrobe_skins_preview.png")
	
	print("ALL TESTS PASSED SUCCESSFULLY!")
	quit(0)
