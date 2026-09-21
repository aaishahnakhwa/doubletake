extends Node2D

const WorldScript = preload("res://scripts/camp_world.gd")
const ActorScript = preload("res://scripts/camp_actor.gd")
const HudScript = preload("res://scripts/camp_hud.gd")
const VisibilityScript = preload("res://scripts/visibility_overlay.gd")
const AtmosphereScript = preload("res://scripts/camp_atmosphere.gd")
const DepthScript = preload("res://scripts/camp_depth.gd")
const TaskMinigameScript = preload("res://scripts/task_minigame.gd")
const BodyScript = preload("res://scripts/camp_body.gd")
const KillEffectScript = preload("res://scripts/kill_effect.gd")
const KillCinematicScript = preload("res://scripts/kill_cinematic.gd")

var session: Node
var initial_state: Dictionary = {}
var world: Node2D
var actors: Node2D
var player: CharacterBody2D
var hud: CanvasLayer
var visibility: Node2D
var actor_by_id: Dictionary = {}
var target_positions: Dictionary = {}
var send_elapsed := 0.0
var last_station_name := ""
var current_minigame: CanvasLayer
var current_sabotage_id := ""
var active_kill_cinematic: CanvasLayer
var task_state: Dictionary = {}
var phase4_state: Dictionary = {}
var bodies_by_id: Dictionary = {}


func _ready() -> void:
	_bind_controls()
	world = WorldScript.new()
	add_child(world)
	add_child(AtmosphereScript.new())
	actors = Node2D.new()
	actors.name = "NetworkCampers"
	add_child(actors)
	add_child(DepthScript.new())
	visibility = VisibilityScript.new()
	visibility.name = "DuskVisibility"
	add_child(visibility)
	hud = HudScript.new()
	add_child(hud)
	hud.set_zone_names(world.get_zone_names())
	hud.inspect_requested.connect(_inspect_station)
	_spawn_players()
	hud.touch_direction_changed.connect(func(direction: Vector2) -> void:
		if is_instance_valid(player):
			player.touch_direction = direction)
	hud.update_player_count(actor_by_id.size())
	task_state = initial_state.get("task_state", {}).duplicate(true)
	hud.set_task_state(task_state)
	phase4_state = initial_state.get("phase4_state", {}).duplicate(true)
	hud.set_phase4_state(phase4_state)
	_refresh_task_markers()
	_refresh_sabotage_markers()
	hud.show_toast("Role: %s • Room %s" % [session.local_role, str(initial_state.get("room_code", ""))])
	session.snapshot_received.connect(_on_snapshot)
	session.task_begin_approved.connect(_on_task_begin_approved)
	session.task_state_received.connect(_on_task_state)
	session.task_action_failed.connect(func(message: String) -> void: hud.show_toast(message))
	session.phase4_state_received.connect(_on_phase4_state)
	session.phase4_action_failed.connect(func(message: String) -> void: hud.show_toast(message))
	session.body_reported.connect(func(_body: Dictionary) -> void: hud.show_toast("Body report confirmed. Meetings begin in Phase 5."))
	hud.kill_requested.connect(session.request_kill)
	hud.sabotage_requested.connect(_begin_sabotage_minigame)
	hud.repair_requested.connect(session.request_repair)
	hud.body_report_requested.connect(session.report_nearby_body)
	session.match_ended.connect(_on_match_ended)
	_apply_phase4_visuals(false)


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	visibility.global_position = player.global_position
	hud.update_player_position(player.global_position)
	hud.update_player_screen_position(player.get_global_transform_with_canvas().origin)
	var zone: String = world.get_zone_at(player.global_position)
	hud.update_zone(zone)
	hud.mark_zone(zone)
	var station: Dictionary = world.get_nearest_station(player.global_position)
	var station_name: String = station.get("name", "")
	if station_name != last_station_name:
		last_station_name = station_name
		hud.update_station(station)
	hud.set_nearby_body(_nearby_unreported_body())
	for player_id: String in actor_by_id:
		if player_id == session.local_player_id or not target_positions.has(player_id):
			continue
		var actor: CharacterBody2D = actor_by_id[player_id]
		actor.global_position = actor.global_position.lerp(target_positions[player_id], minf(1.0, delta * 12.0))


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	send_elapsed += delta
	if send_elapsed < 0.05:
		return
	send_elapsed = 0.0
	var direction := Vector2.ZERO if is_instance_valid(current_minigame) else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if not is_instance_valid(current_minigame) and player.touch_direction.length_squared() > 0.01:
		direction = player.touch_direction
	var sprinting: bool = Input.is_action_pressed("sprint") or player.touch_direction.length() > 0.72
	session.send_movement(direction, sprinting)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.is_action_pressed("interact"):
		_inspect_station()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_K:
		session.request_kill()
		get_viewport().set_input_as_handled()


func _spawn_players() -> void:
	for record: Dictionary in initial_state.get("players", []):
		var actor: CharacterBody2D = ActorScript.new()
		var player_id: String = str(record["player_id"])
		actor.name = "Camper_" + player_id
		actor.display_name = str(record["name"])
		actor.sprite_variant = clampi(int(record["color"]), 0, 5)
		actor.is_local = player_id == session.local_player_id
		actor.global_position = record["position"]
		actors.add_child(actor)
		actor_by_id[player_id] = actor
		target_positions[player_id] = actor.global_position
		if actor.is_local:
			player = actor


func _on_snapshot(snapshot: Dictionary) -> void:
	var positions: Dictionary = snapshot.get("positions", {})
	for player_id: String in positions:
		if not actor_by_id.has(player_id):
			continue
		var server_position: Vector2 = positions[player_id]
		target_positions[player_id] = server_position
		if player_id == session.local_player_id:
			var actor: CharacterBody2D = actor_by_id[player_id]
			var distance := actor.global_position.distance_to(server_position)
			if distance > 100.0:
				actor.global_position = server_position
			elif distance > 5.0:
				actor.global_position = actor.global_position.lerp(server_position, 0.18)


func _inspect_station() -> void:
	if not is_instance_valid(player) or is_instance_valid(current_minigame):
		return
	if _nearby_unreported_body():
		session.report_nearby_body()
		return
	var station: Dictionary = world.get_nearest_station(player.global_position)
	if station.is_empty():
		return
	var sabotage := _sabotage_at_station(station)
	if not sabotage.is_empty() and bool(sabotage.get("active", false)) and _is_living_camper():
		session.request_repair(str(sabotage["id"]))
		return
	if not sabotage.is_empty() and _is_living_killer() and _is_killer_objective(str(sabotage["id"])):
		_begin_sabotage_minigame(str(sabotage["id"]))
		return
	hud.mark_zone(station["zone"])
	var task_id := str(station.get("task_id", ""))
	if not _has_open_task(task_id):
		hud.show_toast("No unfinished task assigned here.")
		return
	hud.show_toast("Host is checking task access...")
	session.begin_task(task_id)


func _has_open_task(task_id: String) -> bool:
	for assignment: Dictionary in task_state.get("tasks", []):
		if str(assignment.get("id", "")) == task_id:
			return not bool(assignment.get("completed", false))
	return false


func _on_task_begin_approved(task_id: String) -> void:
	if is_instance_valid(current_minigame):
		return
	current_sabotage_id = ""
	current_minigame = TaskMinigameScript.new()
	current_minigame.setup(task_id)
	current_minigame.completed.connect(_on_minigame_completed)
	current_minigame.closed.connect(_on_minigame_closed)
	add_child(current_minigame)
	player.input_locked = true
	player.touch_direction = Vector2.ZERO


func _on_minigame_completed(task_id: String) -> void:
	player.input_locked = false
	current_minigame = null
	session.complete_task(task_id)


func _begin_sabotage_minigame(sabotage_id: String) -> void:
	if is_instance_valid(current_minigame) or not _is_living_killer() or not _is_killer_objective(sabotage_id):
		return
	current_sabotage_id = sabotage_id
	current_minigame = TaskMinigameScript.new()
	current_minigame.setup(sabotage_id, true)
	current_minigame.completed.connect(_on_sabotage_minigame_completed)
	current_minigame.closed.connect(_on_minigame_closed)
	add_child(current_minigame)
	player.input_locked = true
	player.touch_direction = Vector2.ZERO
	hud.show_toast("Complete the sabotage sequence.")


func _on_sabotage_minigame_completed(sabotage_id: String) -> void:
	if is_instance_valid(player):
		player.input_locked = false
	current_minigame = null
	current_sabotage_id = ""
	session.request_sabotage(sabotage_id)


func _on_minigame_closed() -> void:
	if is_instance_valid(player):
		player.input_locked = false
	current_minigame = null
	current_sabotage_id = ""


func _on_task_state(state: Dictionary) -> void:
	task_state = state.duplicate(true)
	hud.set_task_state(task_state)
	if session.local_role == "Killer":
		hud.set_phase4_state(phase4_state)
	_refresh_task_markers()
	if bool(state.get("ghost", false)):
		hud.show_toast("Ghost tasks remain active.")


func _on_phase4_state(state: Dictionary) -> void:
	phase4_state = state.duplicate(true)
	hud.set_phase4_state(phase4_state)
	_refresh_task_markers()
	_refresh_sabotage_markers()
	_apply_phase4_visuals(true)


func _apply_phase4_visuals(play_new_cinematics: bool = true) -> void:
	for player_id: String in actor_by_id:
		var actor = actor_by_id[player_id]
		var player_states: Dictionary = phase4_state.get("player_states", {})
		var player_state: Dictionary = player_states.get(player_id, {})
		var ghost := bool(player_state.get("ghost", false))
		actor.set_ghost(ghost)
		# Only the eliminated player sees their own movable ghost. Everyone else
		# sees the body marker instead of a standing duplicate.
		actor.visible = not ghost or player_id == session.local_player_id
	var wanted := {}
	for body: Dictionary in phase4_state.get("bodies", []):
		var victim_id := str(body.get("player_id", ""))
		if victim_id.is_empty():
			continue
		wanted[victim_id] = true
		if not bodies_by_id.has(victim_id):
			var marker := BodyScript.new()
			marker.name = "Body_" + victim_id
			marker.global_position = body.get("at", Vector2.ZERO)
			actors.add_child(marker)
			bodies_by_id[victim_id] = marker
			var effect := KillEffectScript.new()
			effect.global_position = marker.global_position
			actors.add_child(effect)
			if play_new_cinematics:
				_start_kill_cinematic(body)
		var marker = bodies_by_id[victim_id]
		marker.setup(body)
	for victim_id: String in bodies_by_id.keys():
		if not wanted.has(victim_id):
			bodies_by_id[victim_id].queue_free()
			bodies_by_id.erase(victim_id)


func _start_kill_cinematic(body: Dictionary) -> void:
	var victim_id := str(body.get("player_id", ""))
	var killer_id := str(body.get("killer_id", ""))
	if session.local_player_id != killer_id and session.local_player_id != victim_id:
		return
	if is_instance_valid(active_kill_cinematic):
		return
	if is_instance_valid(current_minigame):
		current_minigame.queue_free()
		current_minigame = null
		current_sabotage_id = ""
	if is_instance_valid(player):
		player.input_locked = true
		player.touch_direction = Vector2.ZERO
	active_kill_cinematic = KillCinematicScript.new()
	active_kill_cinematic.setup(body)
	active_kill_cinematic.finished.connect(_on_kill_cinematic_finished)
	add_child(active_kill_cinematic)


func _on_kill_cinematic_finished() -> void:
	active_kill_cinematic = null
	if is_instance_valid(player) and not is_instance_valid(current_minigame):
		player.input_locked = false


func _nearby_unreported_body() -> bool:
	if not is_instance_valid(player):
		return false
	for body: Dictionary in phase4_state.get("bodies", []):
		if not bool(body.get("reported", false)) and player.global_position.distance_to(body.get("at", Vector2.ZERO)) <= 118.0:
			return true
	return false


func _sabotage_at_station(station: Dictionary) -> Dictionary:
	for sabotage: Dictionary in phase4_state.get("sabotages", []):
		if str(sabotage.get("station", "")) == str(station.get("name", "")):
			return sabotage
	return {}


func _is_living_killer() -> bool:
	return session.local_role == "Killer" and not bool(phase4_state.get("ghost", false))


func _is_living_camper() -> bool:
	return session.local_role == "Camper" and not bool(phase4_state.get("ghost", false))


func _is_killer_objective(sabotage_id: String) -> bool:
	for objective: Dictionary in phase4_state.get("objectives", []):
		if str(objective.get("id", "")) == sabotage_id and not bool(objective.get("completed", false)):
			return true
	return false


func _refresh_task_markers() -> void:
	var incomplete_ids: Array[String] = []
	if session.local_role == "Killer":
		for objective: Dictionary in phase4_state.get("objectives", []):
			if not bool(objective.get("completed", false)):
				incomplete_ids.append(str(objective.get("id", "")))
		world.set_active_task_ids([])
		world.set_killer_sabotage_ids(incomplete_ids)
		return
	world.set_killer_sabotage_ids([])
	for assignment: Dictionary in task_state.get("tasks", []):
		if not bool(assignment.get("completed", false)):
			incomplete_ids.append(str(assignment.get("id", "")))
	world.set_active_task_ids(incomplete_ids)


func _refresh_sabotage_markers() -> void:
	var active_ids: Array[String] = []
	for sabotage: Dictionary in phase4_state.get("sabotages", []):
		if bool(sabotage.get("active", false)):
			active_ids.append(str(sabotage.get("id", "")))
	world.set_active_sabotage_ids(active_ids)


func _on_match_ended(winner: String, reason: String) -> void:
	if is_instance_valid(player):
		player.input_locked = true
	var result := CanvasLayer.new()
	result.layer = 60
	add_child(result)
	var backdrop := ColorRect.new()
	backdrop.color = Color("#081918", 0.93)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result.add_child(backdrop)
	var label := Label.new()
	label.text = "%s WIN\n\n%s" % [winner.to_upper(), reason]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 38)
	label.add_theme_color_override("font_color", Color("#a7c957") if winner == "Campers" else Color("#e63946"))
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result.add_child(label)


func _bind_controls() -> void:
	_bind_action("move_left", [KEY_A, KEY_LEFT])
	_bind_action("move_right", [KEY_D, KEY_RIGHT])
	_bind_action("move_up", [KEY_W, KEY_UP])
	_bind_action("move_down", [KEY_S, KEY_DOWN])
	_bind_action("interact", [KEY_E])
	_bind_action("sprint", [KEY_SHIFT])


func _bind_action(action: StringName, codes: Array[int]) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for code in codes:
		var key := InputEventKey.new()
		key.physical_keycode = code
		if not InputMap.action_has_event(action, key):
			InputMap.action_add_event(action, key)
