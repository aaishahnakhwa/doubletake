extends SceneTree

const NetworkSessionScript = preload("res://scripts/network_session.gd")
const ServerPlayerScript = preload("res://scripts/server_player.gd")
const TaskCatalog = preload("res://scripts/task_catalog.gd")
const TaskMinigameScript = preload("res://scripts/task_minigame.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(TaskCatalog.TASKS.size() == 10, "Catalog contains all ten Phase 3 task types")
	var ids := TaskCatalog.all_ids()
	_check(ids.size() == 10 and _unique(ids).size() == 10, "Task identifiers are unique")
	await _test_minigames(ids)
	await _test_colour_exclusivity()
	await _test_solo_test_bots()
	await _test_authoritative_progress(ids)
	print("Phase 3 task checks: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)


func _test_minigames(ids: Array[String]) -> void:
	var original_size := root.size
	root.size = Vector2i(1280, 720)
	await process_frame
	var modes := {}
	for task_id in ids:
		var task: Dictionary = TaskCatalog.get_task(task_id)
		modes[str(task["mode"])] = true
		var icon: Texture2D = load(str(task.get("icon", "")))
		_check(icon != null and icon.get_width() <= 512 and icon.get_height() <= 512, "Optimized task artwork loads for " + task_id)
		var item_sprites: Array = task.get("item_sprites", [])
		_check(not item_sprites.is_empty(), "Every Phase 3 task has dedicated gameplay artwork: " + task_id)
		if not item_sprites.is_empty():
			_check(item_sprites.size() == task["items"].size(), "Draggable artwork matches every item in " + task_id)
			for sprite_path in item_sprites:
				var sprite: Texture2D = load(str(sprite_path))
				_check(sprite != null and sprite.get_width() == 256 and sprite.get_height() == 256, "Drag-ready 256px sprite loads for " + str(sprite_path))
		for asset_path in task.get("task_assets", []):
			var extra_asset: Texture2D = load(str(asset_path))
			_check(extra_asset != null and extra_asset.get_width() == 256 and extra_asset.get_height() == 256, "Task prop loads for " + str(asset_path))
		for generated_key in ["destination_sprites", "destination_filled_sprites", "target_states"]:
			for asset_path in task.get(generated_key, []):
				var generated_asset: Texture2D = load(str(asset_path))
				_check(generated_asset != null and generated_asset.get_width() == 256 and generated_asset.get_height() == 256, "Generated task state loads for " + str(asset_path))
		if task.has("destination_sprites"):
			_check(task["destination_sprites"].size() == task["destinations"].size(), "Cabin furniture matches every destination")
			_check(task["destination_filled_sprites"].size() == task["destinations"].size(), "Every cabin destination has a visibly filled state")
		if task.has("target_states"):
			_check(task["target_states"].size() == task["items"].size() + 1, "Animated work states cover every step in " + task_id)
		var game = TaskMinigameScript.new()
		game.setup(task_id)
		var completion := {"done": false}
		game.completed.connect(func(_completed_id: String) -> void: completion["done"] = true)
		root.add_child(game)
		await process_frame
		await process_frame
		_check(not task.is_empty() and is_instance_valid(game.panel), "Minigame opens for " + str(task["name"]))
		_check(Rect2(Vector2.ZERO, root.size).encloses(Rect2(game.panel.position, game.panel.size)), "Minigame panel fits the viewport for %s (viewport=%s panel=%s/%s)" % [task_id, root.size, game.panel.position, game.panel.size])
		if str(task["mode"]) in ["targets", "sequence", "matching", "rhythm", "hammer", "find"]:
			_check(not game.action_buttons.is_empty(), "Touch targets are built for " + task_id)
			for button: Button in game.action_buttons:
				_check(button.custom_minimum_size.y >= 58.0, "Touch target is large enough in " + task_id)
		if not item_sprites.is_empty() and str(task["mode"]) in ["targets", "sequence", "matching", "find"]:
			_check(is_instance_valid(game.drop_zone), "Drag-and-drop target is built for " + task_id)
			for button: Button in game.action_buttons:
				_check(button.icon != null and not button.get("drag_payload").is_empty(), "Visual item is draggable in " + task_id)
		if str(task["mode"]) == "matching":
			_check(game.matching_zones.size() == task["destinations"].size(), "Every cabin destination is a playable drop slot")
		if str(task["mode"]) == "hammer":
			_check(is_instance_valid(game.hammer_tool) and game.hammer_nail_zones.size() == task["items"].size(), "Hammer and every nail are directly playable")
		match str(task["mode"]):
			"targets":
				for button: Button in game.action_buttons.duplicate():
					if item_sprites.is_empty():
						button.pressed.emit()
					else:
						game._target_dropped(button.get("drag_payload"))
			"sequence":
				for item in task["items"]:
					for button: Button in game.action_buttons:
						if str(button.get("item_name")) == str(item):
							if item_sprites.is_empty():
								button.pressed.emit()
							else:
								game._sequence_dropped(button.get("drag_payload"))
							break
				if task.has("target_states"):
					_check(game.sequence_target_visual.texture == load(str(task["target_states"][-1])), "Work prop reaches its final visual state in " + task_id)
			"matching":
				for expected_order: int in game.matching_order:
					for button: Button in game.action_buttons:
						var payload: Dictionary = button.get("drag_payload")
						if int(payload.get("order", -1)) == expected_order:
							game._matching_dropped(payload)
							await create_timer(0.62).timeout
							break
			"rhythm":
				game._lantern_work_dropped(game.lantern_fuel_button.drag_payload)
				_check(game.lantern_fueled and game.lantern_pump_button.visible, "Fuel can is poured into the lantern before pumping")
				for _hit in range(5):
					game._lantern_work_dropped(game.lantern_pump_button.drag_payload)
				_check(game.rhythm_hits == 5, "Direct pump interaction fills all five pressure chambers")
				_check(game.ignition_stage == 0, "Lantern ignition starts after pumping")
				var unlit_texture: Texture2D = game.ignition_match.icon
				game._reset_match_strike(game.ignition_match.drag_payload)
				game._match_strike_motion(game.ignition_match.drag_payload, Vector2(12, 42))
				game._match_strike_motion(game.ignition_match.drag_payload, Vector2(30, 43))
				_check(game.ignition_stage == 0, "A short touch on the matchbox does not ignite the match")
				game._match_strike_motion(game.ignition_match.drag_payload, Vector2(72, 44))
				_check(game.ignition_stage == 1, "Matchstick ignites only after a sideways strike across the matchbox")
				_check(game.ignition_match.icon != unlit_texture, "Lit matchstick sprite replaces the unlit sprite")
				_check(bool(game.ignition_match.drag_payload.get("lit", false)), "Ignited matchstick carries lit state")
				game._ignition_drop(game.ignition_match.drag_payload, "lantern")
			"hammer":
				if game.hammer_active_index < 0:
					game._select_next_nail()
				while game.remaining > 0:
					game._hammer_drop(game.hammer_tool.drag_payload, game.hammer_active_index)
			"hold":
				game.hold_value = 99.0
				game.hold_active = true
				game._process(0.1)
			"dial":
				game.dial.value = game.dial_target
				game._process(1.0)
			"find":
				var target_items := [task["items"][1], task["items"][4], task["items"][5]]
				for button: Button in game.action_buttons:
					if str(button.get("item_name")) in target_items:
						button.pressed.emit()
		await create_timer(0.55).timeout
		_check(bool(completion["done"]), "Minigame can be completed for " + task_id)
		if is_instance_valid(game):
			game.queue_free()
		await process_frame
	_check(modes.size() == 7, "Ten tasks cover seven keyboard/touch minigame mechanics")
	root.size = original_size
	await process_frame


func _test_colour_exclusivity() -> void:
	var session = NetworkSessionScript.new()
	root.add_child(session)
	await process_frame
	session.is_server = true
	session.is_eos_p2p = true
	session.local_player_id = "host"
	session.players["host"] = _lobby_record("host", 0, true)
	session.players["guest"] = _lobby_record("guest", 1, true)
	var rejected := {"value": false}
	session.color_change_failed.connect(func(_message: String) -> void: rejected["value"] = true)
	session._set_color_for_player("host", 1)
	_check(bool(rejected["value"]) and int(session.players["host"]["color"]) == 0, "Host rejects duplicate player colours")
	_check(session._available_color(0) == 2, "Duplicate join colour is reassigned to the next free colour")
	root.remove_child(session)
	session.free()
	await process_frame


func _test_solo_test_bots() -> void:
	var session = NetworkSessionScript.new()
	root.add_child(session)
	await process_frame
	session.is_server = true
	session.is_eos_p2p = true
	session.room_code = "SOLO4"
	session.local_player_id = "solo-host"
	session.minimum_players = 4
	session._create_server_world()
	session.players["solo-host"] = {
		"player_id": "solo-host",
		"peer_id": 1,
		"name": "Solo Tester",
		"color": 0,
		"ready": false,
		"host": true,
		"connected": true,
		"reconnect_deadline": 0.0,
		"role": "Camper",
		"bot": false
	}
	session._set_test_bots_for_player("solo-host", true)
	var bot_count := 0
	for record: Dictionary in session._connected_players():
		if bool(record.get("bot", false)):
			bot_count += 1
			_check(bool(record.get("ready", false)), "Test bots enter the lobby ready")
	_check(session._connected_players().size() == 4 and bot_count == 3, "One click fills a solo lobby to four players")
	session._set_ready_for_player("solo-host", true)
	session._request_start_for_player("solo-host")
	_check(session.match_running and session.server_bodies.size() == 4, "Solo test lobby starts a four-character match")
	_check(str(session.players["solo-host"].get("role", "")) == "Camper", "Solo tester remains a Camper")
	var bot_killers := 0
	for player_id: String in session.players:
		var record: Dictionary = session.players[player_id]
		if bool(record.get("bot", false)) and str(record.get("role", "")) == "Killer":
			bot_killers += 1
	_check(bot_killers == 1, "A test bot takes the Killer role")
	_check(session.shared_tasks_total == 5, "Only the solo tester's five tasks count toward completion")
	session.queue_free()
	await process_frame


func _test_authoritative_progress(ids: Array[String]) -> void:
	var session = NetworkSessionScript.new()
	root.add_child(session)
	await process_frame
	session.is_server = true
	session.match_running = true
	session.room_code = "TASK03"
	session._create_server_world()
	await physics_frame
	var marker_ids: Array[String] = ["radio", "dock"]
	session.server_world.set_active_task_ids(marker_ids)
	_check(session.server_world.task_markers_enabled and session.server_world.active_task_ids.size() == 2, "World map shows only assigned incomplete task markers")
	var camper_ids := ["camper-a", "camper-b", "camper-c"]
	session.players["killer"] = _record("killer", "Killer", [])
	for index in range(camper_ids.size()):
		var player_id: String = camper_ids[index]
		var tasks: Array[String] = session._assign_tasks(player_id, index)
		_check(tasks.size() == 5 and _unique(tasks).size() == 5, "Each Camper receives five unique objectives")
		_check("lanterns" in tasks, "Each Camper always receives the matchstick lantern task")
		session.players[player_id] = _record(player_id, "Camper", tasks)
		var body = ServerPlayerScript.new()
		body.global_position = Vector2(10, 10)
		session.server_world.add_child(body)
		session.server_bodies[player_id] = body
	session.shared_tasks_total = camper_ids.size() * 5
	var sample_id: String = camper_ids[0]
	var sample_task: String = session.players[sample_id]["tasks"][0]
	_check(not session._task_validation_error(sample_id, sample_task).is_empty(), "Host rejects task completion away from its station")
	var ghost_record: Dictionary = session.players[sample_id]
	ghost_record["ghost"] = true
	session.players[sample_id] = ghost_record
	var ghost_station := _station_for(session.server_world, sample_task)
	session.server_bodies[sample_id].global_position = ghost_station["at"]
	_check(session._task_validation_error(sample_id, sample_task).is_empty(), "Ghost can continue an assigned task")
	session._complete_task_for_player(sample_id, sample_task)
	_check(session.shared_tasks_completed == 1, "Ghost completion contributes to shared progress")
	ghost_record = session.players[sample_id]
	ghost_record["ghost"] = false
	session.players[sample_id] = ghost_record
	var unassigned := ""
	for task_id in ids:
		if task_id not in session.players[sample_id]["tasks"]:
			unassigned = task_id
			break
	_check(not session._task_validation_error(sample_id, unassigned).is_empty(), "Host rejects unassigned objectives")
	_check(not session._task_validation_error("killer", ids[0]).is_empty(), "Host rejects Killer task claims")
	for player_id in camper_ids:
		var task_ids: Array = session.players[player_id]["tasks"]
		for task_id: String in task_ids:
			if task_id in session.players[player_id]["completed_tasks"]:
				continue
			var station := _station_for(session.server_world, task_id)
			_check(not station.is_empty(), "A reachable camp station exists for " + task_id)
			session.server_bodies[player_id].global_position = station["at"]
			_check(session._task_validation_error(player_id, task_id).is_empty(), "Host accepts nearby assigned task " + task_id)
			session._complete_task_for_player(player_id, task_id)
	_check(session.shared_tasks_completed == session.shared_tasks_total, "Shared progress reaches every assigned objective")
	_check(not session.match_running, "100 percent shared progress ends the match")
	var state: Dictionary = session._task_state_for(sample_id)
	_check(state["tasks"].size() == 5 and int(state["completed"]) == int(state["total"]), "Private checklist and final shared state are restorable")
	session.queue_free()


func _record(player_id: String, role: String, tasks: Array) -> Dictionary:
	return {
		"player_id": player_id,
		"peer_id": 0,
		"name": player_id,
		"color": 0,
		"ready": true,
		"host": false,
		"connected": false,
		"role": role,
		"ghost": false,
		"tasks": tasks,
		"completed_tasks": []
	}


func _lobby_record(player_id: String, color: int, host: bool) -> Dictionary:
	return {
		"player_id": player_id,
		"peer_id": 1 if host else 0,
		"name": player_id,
		"color": color,
		"ready": false,
		"host": host,
		"connected": true,
		"reconnect_deadline": 0.0,
		"role": "Camper"
	}


func _station_for(world: Node, task_id: String) -> Dictionary:
	for station: Dictionary in world.stations:
		if str(station.get("task_id", "")) == task_id:
			return station
	return {}


func _unique(values: Array) -> Dictionary:
	var result := {}
	for value in values:
		result[value] = true
	return result


func _check(success: bool, description: String) -> void:
	if not success:
		failures += 1
		push_error("FAIL: " + description)
