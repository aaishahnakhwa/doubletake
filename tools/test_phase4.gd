extends SceneTree

const NetworkSessionScript = preload("res://scripts/network_session.gd")
const ServerPlayerScript = preload("res://scripts/server_player.gd")
const ActorScript = preload("res://scripts/camp_actor.gd")
const BodyScript = preload("res://scripts/camp_body.gd")
const TaskCatalog = preload("res://scripts/task_catalog.gd")
const TaskMinigameScript = preload("res://scripts/task_minigame.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_host_selected_killer()
	await _test_authoritative_kills_and_bodies()
	await _test_visual_color_mapping()
	await _test_sabotage_minigames()
	await _test_sabotage_objectives_and_repairs()
	print("Phase 4 kill/sabotage checks: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)


func _test_host_selected_killer() -> void:
	var session = await _session()
	session.match_running = false
	session.local_player_id = "host"
	_add_player(session, "host", "Camper", Vector2.ZERO)
	_add_player(session, "chosen", "Camper", Vector2.ZERO)
	var chosen: Dictionary = session.players["chosen"]
	chosen["bot"] = true # Avoids an RPC target in this isolated role-assignment test.
	session.players["chosen"] = chosen
	session.force_camper_for_testing = true
	session._server_settings["forced_killer_player_id"] = "chosen"
	session._start_match()
	_check(str(session.players["chosen"].get("role", "")) == "Killer", "Host-selected Killer overrides the Camper playtest default")
	_check(str(session.players["host"].get("role", "")) == "Camper", "Host remains Camper when another player is selected as Killer")
	session.queue_free()
	await process_frame


func _test_authoritative_kills_and_bodies() -> void:
	var session = await _session()
	_add_player(session, "killer", "Killer", Vector2(1516, 1006))
	_add_player(session, "camper-a", "Camper", Vector2(1516, 1006), 4)
	_add_player(session, "camper-b", "Camper", Vector2(1560, 1006))
	session._kill_nearest_for_player("camper-a")
	_check(not bool(session.players["killer"].get("ghost", false)), "Host rejects a Camper elimination request")
	session._kill_nearest_for_player("killer")
	_check(bool(session.players["camper-a"].get("ghost", false)), "Host marks the nearest Camper as a ghost")
	_check(session.bodies.has("camper-a"), "Host creates a reportable body")
	var body: Dictionary = session.bodies["camper-a"]
	_check(int(body.get("color", -1)) == 4, "Body keeps the eliminated Camper's color variant")
	_check(str(body.get("killer_id", "")) == "killer", "Body event identifies the authoritative Killer for the cinematic")
	_check(int(body.get("killer_color", -1)) == 0, "Kill cinematic keeps the Killer's authoritative colour")
	_check(str((body.get("context", {}) as Dictionary).get("id", "")) == "campfire", "Campfire contextual elimination is selected from authoritative positions")
	var lake_context: Dictionary = session.server_world.get_contextual_elimination(Vector2(704, 1520), Vector2(704, 1520))
	var tree_context: Dictionary = session.server_world.get_contextual_elimination(Vector2(2294, 1270), Vector2(2294, 1270))
	var workshop_context: Dictionary = session.server_world.get_contextual_elimination(Vector2(2490, 356), Vector2(2490, 356))
	_check(str(lake_context.get("id", "")) == "lake", "Lake shoreline selects the splash contextual elimination")
	_check(str(tree_context.get("id", "")) == "weak_tree", "Weak tree selects the falling-tree contextual elimination")
	_check(str(workshop_context.get("id", "")) == "workshop", "Workshop selects the cart contextual elimination")
	_check(float(session.kill_cooldown_until) > Time.get_unix_time_from_system(), "Elimination starts a server-owned cooldown")
	session._kill_nearest_for_player("killer")
	_check(not bool(session.players["camper-b"].get("ghost", false)), "Cooldown blocks another elimination")
	session.server_bodies["camper-b"].global_position = body["at"]
	session._report_nearby_body_for_player("camper-b")
	_check(bool(session.bodies["camper-a"].get("reported", false)), "Nearby living Camper can report a body through the host")
	session.queue_free()
	await process_frame


func _test_visual_color_mapping() -> void:
	var expected_rows := [30, 726, 569, 225, 871, 402]
	var expected_bodies := ["orange.png", "blue.png", "green.png", "red.png", "purple.png", "yellow.png"]
	for color_index in range(6):
		var actor = ActorScript.new()
		actor.sprite_variant = color_index
		root.add_child(actor)
		await process_frame
		_check(int(actor.sprite.region_rect.position.y) == expected_rows[color_index], "Playable character uses lobby colour index %d" % color_index)
		var marker = BodyScript.new()
		root.add_child(marker)
		marker.setup({"color": color_index})
		_check(marker.body_sprite.texture.resource_path.ends_with(expected_bodies[color_index]), "Dead body uses the same colour index %d" % color_index)
		actor.queue_free()
		marker.queue_free()
		await process_frame


func _test_sabotage_minigames() -> void:
	var original_size := root.size
	root.size = Vector2i(1280, 720)
	await process_frame
	for sabotage_id in ["generator", "radio", "supplies", "lanterns"]:
		var task: Dictionary = TaskCatalog.get_sabotage_task(sabotage_id)
		var panel_texture: Texture2D = load(str(task.get("sabotage_states", "")))
		_check(not task.is_empty() and str(task.get("mode", "")) == "sabotage", "Dedicated Killer minigame exists for " + sabotage_id)
		_check(panel_texture != null and panel_texture.get_width() >= 1024 and panel_texture.get_width() == panel_texture.get_height(), "Four-state sabotage sprite atlas loads for " + sabotage_id)
		var game = TaskMinigameScript.new()
		game.setup(sabotage_id, true)
		var completion := {"done": false}
		game.completed.connect(func(_id: String) -> void: completion["done"] = true)
		root.add_child(game)
		await process_frame
		await process_frame
		_check(game.sabotage_buttons.size() == 3 and is_instance_valid(game.sabotage_visual), "Sabotage controls are playable for " + sabotage_id)
		for index in range(game.sabotage_buttons.size()):
			game._sabotage_step_pressed(index)
			_check((game.sabotage_visual.texture as AtlasTexture).region.position != Vector2.ZERO or index == 0, "Sabotage artwork advances after step %d in %s" % [index + 1, sabotage_id])
		await create_timer(0.9).timeout
		_check(bool(completion["done"]), "Sabotage sequence completes for " + sabotage_id)
		if is_instance_valid(game):
			game.queue_free()
		await process_frame
	root.size = original_size
	await process_frame


func _test_sabotage_objectives_and_repairs() -> void:
	var session = await _session()
	_add_player(session, "killer", "Killer", Vector2.ZERO)
	_add_player(session, "camper", "Camper", Vector2.ZERO)
	for sabotage: Dictionary in session.SABOTAGES:
		session.sabotage_state[str(sabotage["id"])] = {
			"id": sabotage["id"], "name": sabotage["name"], "station": sabotage["station"],
			"effect": sabotage["effect"], "active": false, "until": 0.0
		}
	var objectives: Array[String] = session._assign_sabotage_objectives("killer")
	session.players["killer"]["sabotage_objectives"] = objectives
	session.players["killer"]["completed_sabotages"] = []
	_check(objectives.size() == 2 and objectives[0] != objectives[1], "Killer receives two distinct sabotage objectives")
	session.server_world.set_killer_sabotage_ids(objectives)
	_check(session.server_world.killer_sabotage_ids.size() == objectives.size(), "Killer objectives appear as dedicated red map targets")
	var chosen := str(objectives[0])
	var sabotage: Dictionary = session.sabotage_state[chosen]
	var station := _station_by_name(session.server_world, str(sabotage["station"]))
	session.server_bodies["killer"].global_position = station["at"]
	session._start_sabotage_for_player("killer", chosen)
	_check(bool(session.sabotage_state[chosen].get("active", false)), "Host accepts an assigned Killer sabotage at its station")
	_check(chosen in session.players["killer"].get("completed_sabotages", []), "Sabotage objective remains completed after activation")
	var forbidden := "radio" if chosen != "radio" else "generator"
	session._start_sabotage_for_player("killer", forbidden)
	_check(not bool(session.sabotage_state[forbidden].get("active", false)), "Host rejects sabotage outside Killer's private objectives")
	session.server_bodies["camper"].global_position = station["at"]
	session._repair_sabotage_for_player("camper", chosen)
	_check(not bool(session.sabotage_state[chosen].get("active", true)), "Living Camper can repair an active sabotage")
	session.sabotage_state[chosen]["active"] = true
	session.sabotage_state[chosen]["until"] = Time.get_unix_time_from_system() - 1.0
	session._process_sabotage_expiry(Time.get_unix_time_from_system())
	_check(not bool(session.sabotage_state[chosen].get("active", true)), "Sabotage effects expire at their capped duration")
	session.queue_free()
	await process_frame


func _session():
	var session = NetworkSessionScript.new()
	root.add_child(session)
	await process_frame
	session.is_server = true
	session.is_eos_p2p = true
	session.match_running = true
	session.room_code = "PHASE4"
	session._create_server_world()
	await physics_frame
	return session


func _add_player(session, player_id: String, role: String, at: Vector2, color: int = 0) -> void:
	session.players[player_id] = {
		"player_id": player_id, "peer_id": 1 if player_id == "killer" else 0, "name": player_id,
		"color": color, "ready": true, "host": player_id == "killer", "connected": true,
		"role": role, "ghost": false, "tasks": [], "completed_tasks": [],
		"sabotage_objectives": [], "completed_sabotages": []
	}
	var body = ServerPlayerScript.new()
	body.global_position = at
	session.server_world.add_child(body)
	session.server_bodies[player_id] = body


func _station_by_name(world: Node, station_name: String) -> Dictionary:
	for station: Dictionary in world.stations:
		if str(station.get("name", "")) == station_name:
			return station
	return {}


func _check(success: bool, description: String) -> void:
	if not success:
		failures += 1
		push_error("FAIL: " + description)
