extends SceneTree

const WorldScript = preload("res://scripts/camp_world.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/camp_preview.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	for i in range(3):
		await physics_frame
	_check(WorldScript.MAP_ART.resource_path == "res://assets/camp_map_3.png" and WorldScript.MAP_ART.get_size() == Vector2(1536, 1024), "Updated Pinewood Camp image loads")
	_check(scene.hud.joystick.visible, "Android joystick is visible for laptop testing")
	_check(scene.world.get_zone_names().size() == WorldScript.ROOMS.size() + 3, "Every room has a map zone")
	_check(scene.bots.size() == 3, "Four-player preview starts with three moving dummies")
	scene._set_player_count(10)
	_check(scene.bots.size() == 9, "Preview supports ten campers")
	var bot_starts: Array[Vector2] = []
	for bot in scene.bots:
		bot_starts.append(bot.global_position)
	for i in range(75):
		await physics_frame
	for i in range(scene.bots.size()):
		_check(scene.bots[i].global_position.distance_to(bot_starts[i]) > 20, "Dummy camper %d patrols" % (i + 1))
	scene._set_player_count(4)
	_test_route_graph(scene.world)
	_test_collision_layout(scene.world)
	_test_stations(scene.world)
	await _test_room_entry(scene)
	await _test_dock_walk(scene)
	await _test_tree_block(scene)
	await _test_keyboard(scene)
	await _test_touch(scene)
	await _test_mouse(scene)
	await _test_responsive_hud(scene)
	print("Pinewood map checks: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)


func _test_route_graph(world: Node2D) -> void:
	_check(world.navigation != null, "Walkable-grid navigation is built")
	var targets: Array[Vector2] = []
	for point in world.route_nodes:
		targets.append(point)
	for station in world.stations:
		targets.append(station["at"])
	var space := world.get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = 17.0
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = circle
	params.collision_mask = 1
	for index in range(targets.size()):
		var path: PackedVector2Array = world.find_path(world.get_spawn_point(), targets[index])
		_check(path.size() > 1, "Navigation reaches destination %d" % index)
		var blocked := false
		for point in path:
			params.transform = Transform2D(0.0, point)
			if not space.intersect_shape(params, 1).is_empty():
				blocked = true
				break
		_check(not blocked, "Navigation path %d avoids solid obstacles" % index)


func _test_collision_layout(world: Node2D) -> void:
	var space := world.get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = 17.0
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = circle
	params.collision_mask = 1
	for room in WorldScript.ROOMS:
		var rect: Rect2 = room["rect"]
		_check(world.get_zone_at(rect.get_center() * WorldScript.ART_SCALE) == room["name"], "Zone identifies " + room["name"])
		var door := Vector2(room["door_at"], rect.end.y) if room["door_side"] == "bottom" else Vector2(room["door_at"], rect.position.y)
		if room["door_side"] == "right":
			door = Vector2(rect.end.x, room["door_at"])
		elif room["door_side"] == "left":
			door = Vector2(rect.position.x, room["door_at"])
		params.transform = Transform2D(0.0, door * WorldScript.ART_SCALE)
		_check(space.intersect_shape(params, 1).is_empty(), "Door is open: " + room["name"])
	params.transform = Transform2D(0.0, Vector2(758, 503) * WorldScript.ART_SCALE)
	_check(not space.intersect_shape(params, 1).is_empty(), "Campfire blocks walking through flames")
	params.transform = Transform2D(0.0, Vector2(848, 139) * WorldScript.ART_SCALE)
	_check(not space.intersect_shape(params, 1).is_empty(), "Dining furniture has collision")
	params.transform = Transform2D(0.0, Vector2(350, 900) * WorldScript.ART_SCALE)
	_check(not space.intersect_shape(params, 1).is_empty(), "Deep lake water blocks walking")
	_check(world.find_path(Vector2(140, 740) * WorldScript.ART_SCALE, Vector2(352, 760) * WorldScript.ART_SCALE).size() > 1, "Boathouse connects to dock")
	for point in [Vector2(461, 294), Vector2(948, 411), Vector2(667, 636), Vector2(1344, 701)]:
		params.transform = Transform2D(0.0, point * WorldScript.ART_SCALE)
		_check(not space.intersect_shape(params, 1).is_empty(), "Tree crown blocks walking at %s" % point)
	for point in [Vector2(760, 606), Vector2(275, 900), Vector2(1493, 475), Vector2(1420, 660), Vector2(1362, 861)]:
		params.transform = Transform2D(0.0, point * WorldScript.ART_SCALE)
		_check(space.intersect_shape(params, 1).is_empty(), "Open path or platform permits walking at %s" % point)
	for point in [Vector2(300, 840), Vector2(1450, 750)]:
		params.transform = Transform2D(0.0, point * WorldScript.ART_SCALE)
		_check(not space.intersect_shape(params, 1).is_empty(), "Water next to platform blocks walking at %s" % point)
	_check(world.find_path(Vector2(352, 760) * WorldScript.ART_SCALE, Vector2(275, 900) * WorldScript.ART_SCALE).size() > 1, "Lower dock connects to boathouse platform")


func _test_stations(world: Node2D) -> void:
	var space := world.get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = 17.0
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = circle
	params.collision_mask = 1
	for station in world.stations:
		params.transform = Transform2D(0.0, station["at"])
		_check(space.intersect_shape(params, 1).is_empty(), "Station is reachable: " + station["name"])
		_check(world.get_zone_at(station["at"]) == station["zone"], "Station belongs to its mapped area: " + station["name"])


func _test_room_entry(scene: Node) -> void:
	for room in WorldScript.ROOMS:
		var rect: Rect2 = room["rect"]
		var door_side: String = room["door_side"]
		var door_at: float = room["door_at"]
		var start := Vector2.ZERO
		var direction := Vector2.ZERO
		match door_side:
			"top":
				start = Vector2(door_at, rect.position.y - 24.0)
				direction = Vector2.DOWN
			"bottom":
				start = Vector2(door_at, rect.end.y + 24.0)
				direction = Vector2.UP
			"left":
				start = Vector2(rect.position.x - 24.0, door_at)
				direction = Vector2.RIGHT
			"right":
				start = Vector2(rect.end.x + 24.0, door_at)
				direction = Vector2.LEFT
		scene.player.global_position = start * WorldScript.ART_SCALE
		scene.player.touch_direction = direction
		for i in range(36):
			await physics_frame
		scene.player.touch_direction = Vector2.ZERO
		_check(scene.world.get_zone_at(scene.player.global_position) == room["name"], "Player can walk through %s door" % room["name"])
	scene.player.global_position = scene.world.get_spawn_point()
	await physics_frame


func _test_dock_walk(scene: Node) -> void:
	scene.player.global_position = Vector2(269, 790) * WorldScript.ART_SCALE
	scene.player.touch_direction = Vector2.DOWN
	for i in range(90):
		await physics_frame
	scene.player.touch_direction = Vector2.ZERO
	_check(scene.player.global_position.y > 870 * WorldScript.ART_SCALE, "Player can walk from boathouse onto lower dock")
	scene.player.global_position = scene.world.get_spawn_point()
	await physics_frame


func _test_tree_block(scene: Node) -> void:
	scene.player.global_position = Vector2(948, 465) * WorldScript.ART_SCALE
	scene.player.touch_direction = Vector2.UP
	for i in range(60):
		await physics_frame
	scene.player.touch_direction = Vector2.ZERO
	_check(scene.player.global_position.y > 440 * WorldScript.ART_SCALE, "Player cannot walk through pine tree")
	scene.player.global_position = scene.world.get_spawn_point()
	await physics_frame


func _test_keyboard(scene: Node) -> void:
	var before: Vector2 = scene.player.global_position
	Input.action_press("move_right")
	for i in range(15):
		await physics_frame
	Input.action_release("move_right")
	_check(scene.player.global_position.x > before.x + 20, "Keyboard moves local camper")
	var walking_distance: float = scene.player.global_position.x - before.x
	_check(scene.player.active_frame >= 4, "Walking uses the supplied walk frames")
	scene.player.global_position = before
	Input.action_press("move_right")
	Input.action_press("sprint")
	for i in range(15):
		await physics_frame
	Input.action_release("sprint")
	Input.action_release("move_right")
	_check(scene.player.global_position.x - before.x > walking_distance * 1.2, "Shift runs faster than walking")
	_check(scene.player.animation_state == "run", "Running plays the faster walk-frame cycle")
	scene.player.global_position = before
	Input.action_press("move_left")
	for i in range(4):
		await physics_frame
	Input.action_release("move_left")
	_check(scene.player.sprite.flip_h, "Sprite mirrors when moving left")


func _test_touch(scene: Node) -> void:
	scene.player.global_position = scene.world.get_spawn_point()
	scene.hud.transform = Transform2D(0.0, Vector2(1.2, 1.2), 0.0, Vector2(210, 25))
	var start: Vector2 = scene.player.global_position
	var center: Vector2 = scene.hud.joystick.get_global_transform_with_canvas() * (scene.hud.joystick.size * 0.5)
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = center
	root.push_input(press, true)
	_check(scene.hud.joystick.active_touch == 0, "Viewport touch reaches shifted joystick")
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = center + Vector2(110, 0)
	root.push_input(drag, true)
	for i in range(15):
		await physics_frame
	_check(scene.player.animation_state == "run", "Full joystick deflection runs on touch")
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = drag.position
	root.push_input(release, true)
	_check(scene.player.global_position.x > start.x + 20, "Touch drag moves local camper")
	_check(scene.hud.joystick.direction == Vector2.ZERO, "Touch release resets joystick")
	scene.hud.transform = Transform2D.IDENTITY


func _test_mouse(scene: Node) -> void:
	scene.player.global_position = scene.world.get_spawn_point()
	var start: Vector2 = scene.player.global_position
	var center: Vector2 = scene.hud.joystick.get_global_transform_with_canvas() * (scene.hud.joystick.size * 0.5)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = center
	root.push_input(press, true)
	var drag := InputEventMouseMotion.new()
	drag.position = center + Vector2(65, 0)
	root.push_input(drag, true)
	for i in range(15):
		await physics_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = drag.position
	root.push_input(release, true)
	_check(scene.player.global_position.x > start.x + 20, "Laptop mouse drag moves local camper")
	_check(scene.hud.joystick.direction == Vector2.ZERO, "Mouse release resets joystick")


func _test_responsive_hud(scene: Node) -> void:
	var original_size := root.size
	var viewport_cases := [Vector2i(1280, 720), Vector2i(1600, 720)]
	for viewport_size in viewport_cases:
		root.size = viewport_size
		await process_frame
		scene.hud.mobile_mode = true
		scene.hud.expanded = false
		scene.hud._layout()
		var bounds := Rect2(Vector2.ZERO, Vector2(viewport_size))
		_check(bounds.encloses(_scaled_rect(scene.hud.header)), "Header fits %s mobile layout" % viewport_size)
		_check(bounds.encloses(_scaled_rect(scene.hud.map_card)), "Minimap fits %s mobile layout" % viewport_size)
		_check(bounds.encloses(_scaled_rect(scene.hud.joystick)), "Joystick fits %s mobile layout" % viewport_size)
		_check(bounds.encloses(_scaled_rect(scene.hud.action_button)), "Inspect button fits %s mobile layout" % viewport_size)
		_check(bounds.encloses(_scaled_rect(scene.hud.map_button)), "Map button fits %s mobile layout" % viewport_size)
		_check(not _scaled_rect(scene.hud.joystick).intersects(_scaled_rect(scene.hud.action_button)), "Touch controls do not overlap at %s" % viewport_size)
		scene.hud.expanded = true
		scene.hud._layout()
		_check(bounds.encloses(_scaled_rect(scene.hud.zone_card)), "Expanded task panel fits %s mobile layout" % viewport_size)
		_check(not _scaled_rect(scene.hud.zone_card).intersects(_scaled_rect(scene.hud.map_card)), "Expanded panels do not overlap at %s" % viewport_size)
	root.size = Vector2i(1920, 1080)
	await process_frame
	scene.hud.mobile_mode = false
	scene.hud.expanded = false
	scene.hud._layout()
	var desktop_bounds := Rect2(Vector2.ZERO, Vector2(root.size))
	_check(desktop_bounds.encloses(_scaled_rect(scene.hud.zone_card)), "Task panel fits 1920x1080 desktop layout")
	_check(desktop_bounds.encloses(_scaled_rect(scene.hud.map_card)), "Minimap fits 1920x1080 desktop layout")
	_check(not scene.hud.joystick.visible and not scene.hud.action_button.visible, "Touch controls hide in desktop layout")
	root.size = original_size
	scene.hud.mobile_mode = true
	scene.hud.expanded = false
	await process_frame
	scene.hud._layout()


func _scaled_rect(control: Control) -> Rect2:
	return Rect2(control.position, control.size * control.scale)


func _check(success: bool, description: String) -> void:
	if not success:
		failures += 1
		push_error("FAIL: " + description)
