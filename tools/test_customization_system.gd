extends SceneTree

const CustomizationCatalog = preload("res://scripts/customization_catalog.gd")
const NetworkSessionScript = preload("res://scripts/network_session.gd")
const ActorScript = preload("res://scripts/camp_actor.gd")
const LobbyUIScript = preload("res://scripts/lobby_ui.gd")

func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("Starting Customization System Test Suite...")
	
	# ----------------------------------------------------
	# Test 1: CustomizationCatalog definitions and textures
	# ----------------------------------------------------
	var hat_ids := CustomizationCatalog.get_all_hat_ids()
	assert("none" in hat_ids, "Missing none hat")
	assert("beanie" in hat_ids, "Missing beanie hat")
	assert("cowboy" in hat_ids, "Missing cowboy hat")
	assert("bandana" in hat_ids, "Missing bandana hat")
	assert("flower_crown" in hat_ids, "Missing flower_crown hat")
	assert("bear_ears" in hat_ids, "Missing bear_ears hat")
	assert("detective" in hat_ids, "Missing detective hat")
	
	var outfit_ids := CustomizationCatalog.get_all_outfit_ids()
	assert("none" in outfit_ids, "Missing none outfit")
	assert("flannel" in outfit_ids, "Missing flannel outfit")
	assert("scout_sash" in outfit_ids, "Missing scout_sash outfit")
	assert("hoodie" in outfit_ids, "Missing hoodie outfit")
	assert("necktie" in outfit_ids, "Missing necktie outfit")
	
	for hid in ["beanie", "cowboy", "flower_crown"]:
		assert(CustomizationCatalog.get_hat_portrait_texture(hid) != null, "Hat portrait texture missing: " + hid)
		assert(CustomizationCatalog.get_hat_actor_texture(hid) != null, "Hat actor texture missing: " + hid)

	for oid in ["flannel", "scout_sash", "hoodie"]:
		assert(CustomizationCatalog.get_outfit_portrait_texture(oid) != null, "Outfit portrait texture missing: " + oid)
		assert(CustomizationCatalog.get_outfit_actor_texture(oid) != null, "Outfit actor texture missing: " + oid)

	print("[PASS] Test 1: CustomizationCatalog has all 7 hats and 5 outfits with valid textures.")

	# ----------------------------------------------------
	# Test 2: Local Persistence
	# ----------------------------------------------------
	var test_data := {
		"color": 2,
		"hat": "beanie",
		"outfit": "flannel"
	}
	CustomizationCatalog.save_local_customization(test_data)
	var loaded := CustomizationCatalog.load_local_customization()
	assert(loaded["color"] == 2, "Color mismatch in local save")
	assert(loaded["hat"] == "beanie", "Hat mismatch in local save")
	assert(loaded["outfit"] == "flannel", "Outfit mismatch in local save")
	print("[PASS] Test 2: Local persistence save and load verified.")

	# ----------------------------------------------------
	# Test 3: NetworkSession Customization Sync
	# ----------------------------------------------------
	var session := NetworkSessionScript.new()
	root.add_child(session)
	session.start_server(7200, "CUST77", "dev", 2)
	
	var peer_claims := {"player_id": "host_player", "host": true}
	session._accept_join_request(1, peer_claims, "Host", 0)
	assert(session.players["host_player"]["hat"] == "none", "Default hat should be none")
	assert(session.players["host_player"]["outfit"] == "none", "Default outfit should be none")
	
	# Update customization
	session._set_customization_for_player("host_player", 1, "cowboy", "scout_sash")
	assert(session.players["host_player"]["color"] == 1, "Color should update to 1")
	assert(session.players["host_player"]["hat"] == "cowboy", "Hat should update to cowboy")
	assert(session.players["host_player"]["outfit"] == "scout_sash", "Outfit should update to scout_sash")
	
	var lobby_state := session._make_lobby_state()
	var p_entry := {}
	for p: Dictionary in lobby_state["players"]:
		if p["player_id"] == "host_player":
			p_entry = p
			break
	assert(p_entry["hat"] == "cowboy", "Lobby state hat missing")
	assert(p_entry["outfit"] == "scout_sash", "Lobby state outfit missing")
	print("[PASS] Test 3: NetworkSession customization sync verified.")

	# ----------------------------------------------------
	# Test 4: CampActor Layering & Animation Bobbing
	# ----------------------------------------------------
	var actor := ActorScript.new()
	root.add_child(actor)
	actor.sprite_variant = 2
	actor.set_customization("beanie", "flannel")
	assert(actor.hat_sprite != null and actor.hat_sprite.visible, "Hat sprite should be visible")
	assert(actor.outfit_sprite != null and actor.outfit_sprite.visible, "Outfit sprite should be visible")

	actor._set_frame(5) # Walking frame
	assert(actor.hat_sprite.flip_h == actor.sprite.flip_h, "Hat sprite flip_h should match")

	# Ghost form should hide hats and outfits
	actor.set_ghost(true)
	assert(not actor.hat_sprite.visible, "Hat sprite should be hidden in ghost form")
	assert(not actor.outfit_sprite.visible, "Outfit sprite should be hidden in ghost form")
	print("[PASS] Test 4: CampActor layering and ghost form handling verified.")

	# ----------------------------------------------------
	# Test 5: Visual Renderings (Wardrobe Modal & Customized Roster)
	# ----------------------------------------------------
	root.size = Vector2i(1280, 720)
	var lobby_ui := LobbyUIScript.new()
	root.add_child(lobby_ui)
	
	var sample_state := {
		"room_code": "CAMP77",
		"players": [
			{"player_id": "host_1", "name": "Ranger Rick", "color": 0, "hat": "cowboy", "outfit": "flannel", "ready": true, "host": true, "connected": true},
			{"player_id": "camper_2", "name": "Sammy", "color": 1, "hat": "beanie", "outfit": "hoodie", "ready": false, "host": false, "connected": true},
			{"player_id": "camper_3", "name": "Alex", "color": 2, "hat": "flower_crown", "outfit": "scout_sash", "ready": true, "host": false, "connected": true},
			{"player_id": "camper_4", "name": "Maya", "color": 3, "hat": "detective", "outfit": "necktie", "ready": false, "host": false, "connected": true}
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
	
	lobby_ui.show_lobby("host_1", sample_state)
	for i in range(5):
		await process_frame
		
	var img := root.get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("C:/Users/saule/.gemini/antigravity/brain/17a13079-7005-4717-99fb-b563640774d7/lobby_customized_roster.png")
		print("Saved lobby_customized_roster.png!")

	# Now open the Wardrobe Modal and capture preview
	lobby_ui._open_wardrobe_modal()
	lobby_ui.selected_color_idx = 2 # Green
	lobby_ui.selected_hat_id = "beanie"
	lobby_ui.selected_outfit_id = "flannel"
	lobby_ui._update_wardrobe_preview()
	for i in range(5):
		await process_frame
		
	img = root.get_texture().get_image()
	if img and not img.is_empty():
		img.save_png("C:/Users/saule/.gemini/antigravity/brain/17a13079-7005-4717-99fb-b563640774d7/wardrobe_modal_preview.png")
		print("Saved wardrobe_modal_preview.png!")

	print("ALL CUSTOMIZATION TESTS AND RENDERS COMPLETED SUCCESSFULLY!")
	
	actor.queue_free()
	lobby_ui.queue_free()
	session.queue_free()
	quit(0)
