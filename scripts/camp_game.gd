extends Node2D

const WorldScript = preload("res://scripts/camp_world.gd")
const ActorScript = preload("res://scripts/camp_actor.gd")
const HudScript = preload("res://scripts/camp_hud.gd")
const VisibilityScript = preload("res://scripts/visibility_overlay.gd")
const AtmosphereScript = preload("res://scripts/camp_atmosphere.gd")
const DepthScript = preload("res://scripts/camp_depth.gd")
const MeetingScreenScript = preload("res://scripts/meeting_screen.gd")

const CAMPER_NAMES := ["Ayaan", "Riya", "Kabir", "Zoya", "Armaan", "Mira", "Dev", "Tara", "Noor"]
const SPAWN_NODES := [8, 9, 10, 11, 12, 14, 15, 18, 20]
const SPRITE_VARIANTS := [1, 2, 3, 4, 5, 0, 1, 3, 4]

var world: Node2D
var actors: Node2D
var player: CharacterBody2D
var bots: Array[CharacterBody2D] = []
var hud: CanvasLayer
var visibility: Node2D
var atmosphere: Node2D
var depth: Node2D
var active_meeting: CanvasLayer
var last_station_name := ""
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 532916
	_bind_controls()
	world = WorldScript.new()
	add_child(world)
	atmosphere = AtmosphereScript.new()
	add_child(atmosphere)
	actors = Node2D.new()
	actors.name = "Campers"
	add_child(actors)
	_spawn_player()
	depth = DepthScript.new()
	add_child(depth)
	visibility = VisibilityScript.new()
	visibility.name = "DuskVisibility"
	add_child(visibility)
	hud = HudScript.new()
	add_child(hud)
	hud.set_zone_names(world.get_zone_names())
	hud.inspect_requested.connect(_inspect_station)
	hud.emergency_meeting_requested.connect(_start_emergency_sequence)
	hud.player_count_delta.connect(_change_player_count)
	hud.touch_direction_changed.connect(func(direction: Vector2) -> void: player.touch_direction = direction)
	if is_instance_valid(world) and is_instance_valid(world.bell):
		world.bell.bell_clicked.connect(_on_bell_clicked)
	_set_player_count(4)
	hud.show_toast("Explore camp. Inspect green markers!")


func _process(_delta: float) -> void:
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
	var near_emergency: bool = bool(world.is_near_emergency_button(player.global_position)) and not is_instance_valid(active_meeting)
	hud.set_nearby_emergency_button(near_emergency)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("interact"):
			_inspect_station()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F3:
			_change_player_count(1)
			get_viewport().set_input_as_handled()


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


func _spawn_player() -> void:
	player = ActorScript.new()
	player.name = "LocalCamper"
	player.display_name = "You"
	player.is_local = true
	player.global_position = world.get_spawn_point()
	actors.add_child(player)


func _set_player_count(total: int) -> void:
	var target := clampi(total, 4, 10) - 1
	while bots.size() < target:
		_spawn_bot(bots.size())
	while bots.size() > target:
		var bot: CharacterBody2D = bots.pop_back()
		bot.queue_free()
	hud.update_player_count(bots.size() + 1)


func _change_player_count(delta: int) -> void:
	var next := bots.size() + 1 + delta
	if next > 10:
		next = 4
	elif next < 4:
		next = 10
	_set_player_count(next)
	hud.show_toast("%d campers in local map preview" % next)


func _spawn_bot(index: int) -> void:
	var bot: CharacterBody2D = ActorScript.new()
	bot.name = "DummyCamper%d" % (index + 1)
	bot.display_name = CAMPER_NAMES[index]
	bot.sprite_variant = SPRITE_VARIANTS[index]
	bot.is_local = false
	bot.global_position = world.route_nodes[SPAWN_NODES[index]]
	bot.route_point_reached.connect(_advance_bot)
	actors.add_child(bot)
	bots.append(bot)
	_advance_bot(bot)


func _advance_bot(bot: CharacterBody2D) -> void:
	for attempt in range(24):
		var destination: Vector2
		if attempt % 3 == 0:
			destination = world.stations[rng.randi_range(0, world.stations.size() - 1)]["at"]
		else:
			destination = world.route_nodes[rng.randi_range(0, world.route_nodes.size() - 1)]
		if bot.global_position.distance_to(destination) < 100.0:
			continue
		var path: PackedVector2Array = world.find_path(bot.global_position, destination)
		if path.size() > 2:
			bot.route_path = path
			bot.route_index = 1
			return
	bot.route_path = PackedVector2Array()


func _inspect_station() -> void:
	if is_instance_valid(active_meeting):
		return
	if world.is_near_emergency_button(player.global_position):
		hud.show_emergency_confirm_dialog()
		return
	var station: Dictionary = world.get_nearest_station(player.global_position)
	if station.is_empty():
		return
	hud.mark_zone(station["zone"])
	hud.show_toast("Inspected %s • %s" % [station["name"], station["task"]])


func _on_bell_clicked() -> void:
	if is_instance_valid(active_meeting):
		return
	if world.is_near_emergency_button(player.global_position):
		hud.show_emergency_confirm_dialog()
	else:
		hud.show_toast("Walk closer to the Camp Bell to ring it!")


func _start_emergency_sequence() -> void:
	if is_instance_valid(active_meeting):
		return
	if is_instance_valid(player):
		player.input_locked = true
		player.velocity = Vector2.ZERO
	hud.show_ringing_bell_cinematic(1.2)
	if is_instance_valid(world) and is_instance_valid(world.bell):
		world.bell.ring(1.2)
		world.bell.ring_finished.connect(_open_emergency_meeting, CONNECT_ONE_SHOT)
	else:
		get_tree().create_timer(1.2).timeout.connect(_open_emergency_meeting)


func _open_emergency_meeting() -> void:
	if is_instance_valid(active_meeting):
		return
	if is_instance_valid(player):
		player.input_locked = true
		player.velocity = Vector2.ZERO
	var meeting_players: Array = []
	meeting_players.append({
		"player_id": "local",
		"name": "You",
		"color": 0,
		"ghost": false,
		"connected": true
	})
	for i in range(bots.size()):
		var bot: CharacterBody2D = bots[i]
		meeting_players.append({
			"player_id": "bot_%d" % i,
			"name": bot.display_name,
			"color": bot.sprite_variant,
			"ghost": false,
			"connected": true
		})
	var meeting_data := {
		"type": "emergency",
		"caller_id": "local",
		"caller_name": "You",
		"caller_color": 0,
		"victim_id": "",
		"victim_name": "",
		"players": meeting_players
	}
	active_meeting = MeetingScreenScript.new()
	active_meeting.setup(meeting_data, "local", true)
	active_meeting.meeting_dismissed.connect(func() -> void:
		active_meeting = null
		if is_instance_valid(player):
			player.input_locked = false
		hud.show_toast("Meeting dismissed. Returning to camp.")
	)
	add_child(active_meeting)

