extends CanvasLayer

signal inspect_requested
signal player_count_delta(delta: int)
signal touch_direction_changed(direction: Vector2)
signal kill_requested
signal sabotage_requested(sabotage_id: String)
signal repair_requested(sabotage_id: String)
signal body_report_requested

const MiniMapScript = preload("res://scripts/camp_minimap.gd")
const JoystickScript = preload("res://scripts/touch_joystick.gd")
# Keep the Android controls visible when testing with a mouse on a laptop.
var mobile_mode := true
var zone_names: Array[String] = []
var expanded := false
var visited: Dictionary = {}
var current_zone := "Campfire Square"
var player_count := 4
var nearby_station: Dictionary = {}
var toast_seconds := 0.0
var player_screen_position := Vector2(-10000, -10000)
var task_mode := false
var task_assignments: Array = []
var shared_completed := 0
var shared_total := 0
var phase4_state: Dictionary = {}
var nearby_body := false
var kill_cooldown_remaining := 0.0

var root: Control
var header: PanelContainer
var zone_card: PanelContainer
var map_card: PanelContainer
var prompt_card: PanelContainer
var toast_card: PanelContainer
var header_title: Label
var header_status: Label
var count_label: Label
var zone_list: Label
var section_title: Label
var task_progress: ProgressBar
var task_progress_label: Label
var task_list: Label
var zone_scroll: ScrollContainer
var camper_row: HBoxContainer
var prompt_label: Label
var toast_label: Label
var kill_cooldown_card: PanelContainer
var kill_cooldown_label: Label
var minimap: Control
var joystick: Control
var action_button: Button
var map_button: Button
var kill_button: Button
var blackout_overlay: ColorRect


func _ready() -> void:
	blackout_overlay = ColorRect.new()
	blackout_overlay.color = Color("#02070d", 0.52)
	blackout_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blackout_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blackout_overlay.visible = false
	add_child(blackout_overlay)
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_build_header()
	_build_zones()
	_build_map()
	_build_prompt()
	_build_toast()
	_build_kill_cooldown()
	_build_touch_controls()
	get_viewport().size_changed.connect(_layout)
	_refresh_zones()
	_layout()
	call_deferred("_layout")


func _process(delta: float) -> void:
	if toast_seconds > 0.0:
		toast_seconds -= delta
		if toast_seconds <= 0.0:
			toast_card.visible = false
	if kill_cooldown_remaining > 0.0:
		kill_cooldown_remaining = maxf(0.0, kill_cooldown_remaining - delta)
		_refresh_kill_cooldown()
	var actor_bounds := Rect2(player_screen_position - Vector2(34, 72), Vector2(68, 108))
	for panel in [header, zone_card, map_card, prompt_card]:
		if not panel.visible:
			continue
		var panel_bounds := Rect2(panel.position, panel.size * panel.scale)
		var target_alpha := 0.25 if panel_bounds.intersects(actor_bounds) else 1.0
		panel.modulate.a = move_toward(panel.modulate.a, target_alpha, delta * 5.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F2:
			mobile_mode = not mobile_mode
			expanded = false
			_layout()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB:
			_toggle_map()
			get_viewport().set_input_as_handled()


func _build_header() -> void:
	header = _panel(Color("#0e2929"), Color("#a7c957"))
	root.add_child(header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	header.add_child(row)
	header_title = _label("DOUBLE TAKE", 23, Color("#f4d7a7"))
	header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(header_title)
	header_status = _label("AREAS 0/0", 15, Color("#a7c957"))
	row.add_child(header_status)


func _build_zones() -> void:
	zone_card = _panel(Color("#102b2b", 0.94), Color("#8b5e3c"))
	root.add_child(zone_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	zone_card.add_child(column)
	section_title = _label("SCOUT THE CAMP", 20, Color("#f4d7a7"))
	column.add_child(section_title)
	task_progress_label = _label("SHARED TASKS  0%", 14, Color("#a7c957"))
	task_progress_label.visible = false
	column.add_child(task_progress_label)
	task_progress = ProgressBar.new()
	task_progress.custom_minimum_size = Vector2(254, 20)
	task_progress.show_percentage = false
	task_progress.visible = false
	column.add_child(task_progress)
	task_list = _label("", 14, Color("#fffbe7"))
	task_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task_list.visible = false
	column.add_child(task_list)
	zone_scroll = ScrollContainer.new()
	zone_scroll.custom_minimum_size = Vector2(254, 140)
	zone_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(zone_scroll)
	zone_list = _label("", 15, Color("#fffbe7"))
	zone_scroll.add_child(zone_list)
	camper_row = HBoxContainer.new()
	camper_row.add_theme_constant_override("separation", 6)
	column.add_child(camper_row)
	camper_row.add_child(_label("CAMPERS", 14, Color("#f4d7a7")))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camper_row.add_child(spacer)
	var minus := _button("-", 18)
	minus.custom_minimum_size = Vector2(34, 34)
	minus.pressed.connect(func() -> void: player_count_delta.emit(-1))
	camper_row.add_child(minus)
	count_label = _label("4", 18, Color("#fffbe7"))
	camper_row.add_child(count_label)
	var plus := _button("+", 18)
	plus.custom_minimum_size = Vector2(34, 34)
	plus.pressed.connect(func() -> void: player_count_delta.emit(1))
	camper_row.add_child(plus)


func _build_map() -> void:
	map_card = _panel(Color("#102b2b", 0.96), Color("#8b5e3c"))
	root.add_child(map_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	map_card.add_child(column)
	column.add_child(_label("THE CAMP", 18, Color("#f4d7a7")))
	column.add_child(_label("● YOUR TASK     ◉ YOU", 12, Color("#ffd166")))
	minimap = MiniMapScript.new()
	minimap.custom_minimum_size = Vector2(205, 118)
	minimap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	minimap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(minimap)


func _build_prompt() -> void:
	prompt_card = _panel(Color("#102b2b", 0.94), Color("#a7c957"))
	root.add_child(prompt_card)
	prompt_label = _label("Explore the camp • E to inspect", 18, Color("#fffbe7"))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.clip_text = true
	prompt_card.add_child(prompt_label)
	prompt_card.visible = false


func _build_toast() -> void:
	toast_card = _panel(Color("#204d3f", 0.97), Color("#a7c957"))
	root.add_child(toast_card)
	toast_label = _label("", 20, Color("#fffbe7"))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.clip_text = true
	toast_card.add_child(toast_label)
	toast_card.visible = false


func _build_kill_cooldown() -> void:
	kill_cooldown_card = _panel(Color("#4b1f28", 0.96), Color("#ffb703"))
	root.add_child(kill_cooldown_card)
	kill_cooldown_label = _label("ELIMINATE READY  •  K", 18, Color("#fffbe7"))
	kill_cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kill_cooldown_card.add_child(kill_cooldown_label)
	kill_cooldown_card.visible = false


func _build_touch_controls() -> void:
	joystick = JoystickScript.new()
	joystick.custom_minimum_size = Vector2(180, 180)
	joystick.direction_changed.connect(func(direction: Vector2) -> void: touch_direction_changed.emit(direction))
	root.add_child(joystick)
	action_button = _button("INSPECT", 21)
	action_button.pressed.connect(_action_button_pressed)
	root.add_child(action_button)
	kill_button = _button("ELIMINATE", 18)
	kill_button.pressed.connect(func() -> void: kill_requested.emit())
	root.add_child(kill_button)
	map_button = _button("MAP / TASKS", 16)
	map_button.pressed.connect(_toggle_map)
	root.add_child(map_button)


func _panel(fill: Color, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _button(value: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = value
	button.add_theme_font_size_override("font_size", font_size)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#8b5e3c")
	normal.border_color = Color("#f4d7a7")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(9)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#a7c957")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#2e684f")
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("#3b4540")
	disabled.border_color = Color("#819082")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color("#fffbe7"))
	button.add_theme_color_override("font_hover_color", Color("#102b2b"))
	button.add_theme_color_override("font_pressed_color", Color("#fffbe7"))
	button.add_theme_color_override("font_disabled_color", Color("#c5d0c2"))
	return button


func _label(value: String, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	return label


func _safe_insets(viewport_size: Vector2) -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var screen := Vector2(DisplayServer.screen_get_size())
	if screen.x <= 0 or screen.y <= 0:
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var factor := viewport_size / screen
	return Vector4(
		maxf(0, safe.position.x * factor.x),
		maxf(0, safe.position.y * factor.y),
		maxf(0, (screen.x - safe.end.x) * factor.x),
		maxf(0, (screen.y - safe.end.y) * factor.y)
	)


func _layout() -> void:
	if not is_instance_valid(root):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var safe := _safe_insets(viewport_size)
	var scale_factor := clampf(viewport_size.y / 720.0, 0.78, 1.65)
	var touch_scale := scale_factor * 1.3
	var factor := Vector2.ONE * scale_factor
	header.scale = factor
	header.position = Vector2(safe.x + 16 * scale_factor, safe.y + 14 * scale_factor)
	header_title.text = "DOUBLE TAKE"
	header_title.add_theme_font_size_override("font_size", 17 if mobile_mode else 23)
	header.size = Vector2(282, 60) if mobile_mode else Vector2(360, 60)
	header_status.text = "TASKS %d%%" % _task_percent() if task_mode else "AREAS %d/%d" % [visited.size(), zone_names.size()]
	map_card.scale = factor
	map_card.size = Vector2(410, 318) if expanded else Vector2(230, 184)
	map_card.position = Vector2(viewport_size.x - safe.z - 16 * scale_factor - map_card.size.x * scale_factor,
		safe.y + 14 * scale_factor)
	zone_card.scale = factor
	zone_card.size = Vector2(280, 360)
	zone_card.position = Vector2(safe.x + 16 * scale_factor, safe.y + 84 * scale_factor)
	zone_card.visible = not mobile_mode or expanded
	prompt_card.scale = factor
	prompt_card.size = Vector2(380, 62)
	prompt_card.position = Vector2((viewport_size.x - 380 * scale_factor) * 0.5,
		viewport_size.y - safe.w - 78 * scale_factor if mobile_mode else viewport_size.y - safe.w - 82 * scale_factor)
	toast_card.scale = factor
	toast_card.size = Vector2(360, 54)
	toast_card.position = Vector2((viewport_size.x - 360 * scale_factor) * 0.5,
		viewport_size.y - safe.w - 160 * scale_factor)
	kill_cooldown_card.scale = factor
	kill_cooldown_card.size = Vector2(280, 48)
	kill_cooldown_card.position = Vector2((viewport_size.x - 280 * scale_factor) * 0.5,
		safe.y + 18 * scale_factor)
	joystick.visible = mobile_mode
	action_button.visible = mobile_mode
	map_button.visible = mobile_mode
	if mobile_mode:
		var touch_factor := Vector2.ONE * touch_scale
		joystick.scale = touch_factor
		joystick.size = Vector2(180, 180)
		joystick.position = Vector2(safe.x + 24 * touch_scale,
			viewport_size.y - safe.w - 194 * touch_scale)
		action_button.scale = touch_factor
		action_button.size = Vector2(128, 78)
		action_button.position = Vector2(viewport_size.x - safe.z - 154 * touch_scale,
			viewport_size.y - safe.w - 102 * touch_scale)
		map_button.scale = touch_factor
		map_button.size = Vector2(128, 62)
		map_button.position = Vector2(viewport_size.x - safe.z - 154 * touch_scale,
			viewport_size.y - safe.w - 180 * touch_scale)
		kill_button.scale = touch_factor
		kill_button.size = Vector2(128, 58)
		kill_button.position = Vector2(viewport_size.x - safe.z - 154 * touch_scale,
			viewport_size.y - safe.w - 250 * touch_scale)
	else:
		joystick.direction = Vector2.ZERO
		touch_direction_changed.emit(Vector2.ZERO)
	kill_button.visible = mobile_mode and _is_living_killer()
	_refresh_kill_cooldown()
	update_station(nearby_station)


func _toggle_map() -> void:
	expanded = not expanded
	_layout()


func _refresh_zones() -> void:
	if not is_instance_valid(zone_list):
		return
	var lines := PackedStringArray()
	for name in zone_names:
		lines.append(("✓  " if visited.has(name) else "○  ") + name)
	zone_list.text = "\n".join(lines)
	header_status.text = "TASKS %d%%" % _task_percent() if task_mode else "AREAS %d/%d" % [visited.size(), zone_names.size()]


func set_zone_names(names: Array[String]) -> void:
	zone_names = names
	_refresh_zones()


func mark_zone(name: String) -> bool:
	if visited.has(name):
		return false
	visited[name] = true
	_refresh_zones()
	show_toast("Discovered: " + name)
	return true


func update_zone(name: String) -> void:
	if name != current_zone:
		current_zone = name
		_refresh_zones()
		update_station(nearby_station)


func update_player_count(count: int) -> void:
	player_count = count
	count_label.text = str(count)


func update_station(station: Dictionary) -> void:
	nearby_station = station
	if nearby_body:
		prompt_card.visible = true
		prompt_label.text = "Tap REPORT BODY" if mobile_mode else "E  REPORT BODY"
		action_button.text = "REPORT BODY"
		action_button.disabled = false
	elif station.is_empty():
		prompt_card.visible = false
		action_button.disabled = true
	else:
		prompt_card.visible = true
		var sabotage := _sabotage_at_station(station)
		var task_id := str(station.get("task_id", ""))
		var assigned := _assignment_for(task_id)
		if not sabotage.is_empty() and bool(sabotage.get("active", false)) and _is_living_camper():
			prompt_label.text = ("Tap REPAIR" if mobile_mode else "E  REPAIR") + "  â€¢  " + str(sabotage.get("effect", "Sabotage"))
			action_button.text = "REPAIR"
			action_button.disabled = false
		elif not sabotage.is_empty() and _is_living_killer() and _is_killer_objective(str(sabotage.get("id", ""))):
			prompt_label.text = ("Tap SABOTAGE" if mobile_mode else "E  SABOTAGE") + "  â€¢  " + str(station["name"])
			action_button.text = "SABOTAGE"
			action_button.disabled = bool(sabotage.get("active", false)) or _objective_complete(str(sabotage.get("id", "")))
		elif task_mode and not assigned.is_empty():
			var done := bool(assigned.get("completed", false))
			prompt_label.text = ("COMPLETED" if done else ("Tap DO TASK" if mobile_mode else "E  DO TASK")) + "  •  " + str(station["name"])
			action_button.text = "DONE" if done else "DO TASK"
			action_button.disabled = done
		elif task_mode:
			prompt_label.text = "No assigned task here  •  " + str(station["name"])
			action_button.text = "NO TASK"
			action_button.disabled = true
		else:
			prompt_label.text = ("Tap INSPECT" if mobile_mode else "E  INSPECT") + "  •  " + str(station["name"])
			action_button.text = "INSPECT"
			action_button.disabled = false


func _action_button_pressed() -> void:
	if nearby_body:
		body_report_requested.emit()
		return
	var sabotage := _sabotage_at_station(nearby_station)
	if not sabotage.is_empty() and bool(sabotage.get("active", false)) and _is_living_camper():
		repair_requested.emit(str(sabotage["id"]))
		return
	if not sabotage.is_empty() and _is_living_killer() and _is_killer_objective(str(sabotage.get("id", ""))):
		sabotage_requested.emit(str(sabotage["id"]))
		return
	inspect_requested.emit()


func set_task_state(state: Dictionary) -> void:
	task_mode = true
	task_assignments = state.get("tasks", []).duplicate(true)
	shared_completed = int(state.get("completed", 0))
	shared_total = int(state.get("total", 0))
	section_title.text = "YOUR TASKS" if not task_assignments.is_empty() else "KILLER OBJECTIVES"
	task_progress.visible = true
	task_progress_label.visible = true
	task_list.visible = true
	zone_scroll.visible = false
	camper_row.visible = false
	task_progress.value = _task_percent()
	task_progress_label.text = "SHARED TASKS  %d%%  (%d/%d)" % [_task_percent(), shared_completed, shared_total]
	var lines := PackedStringArray()
	for assignment: Dictionary in task_assignments:
		lines.append(("✓  " if assignment.get("completed", false) else "○  ") + str(assignment.get("name", "Task")))
	if lines.is_empty():
		lines.append("Complete your killer objectives in Phase 4.")
	task_list.text = "\n".join(lines)
	var incomplete_ids: Array[String] = []
	for assignment: Dictionary in task_assignments:
		if not bool(assignment.get("completed", false)):
			incomplete_ids.append(str(assignment.get("id", "")))
	minimap.set_task_ids(incomplete_ids)
	header_status.text = "TASKS %d%%" % _task_percent()
	update_station(nearby_station)


func set_phase4_state(state: Dictionary) -> void:
	phase4_state = state.duplicate(true)
	if _is_living_killer():
		kill_cooldown_remaining = maxf(0.0, float(phase4_state.get("kill_cooldown", 0.0)))
	else:
		kill_cooldown_remaining = 0.0
	_refresh_kill_cooldown()
	if str(phase4_state.get("role", "")) == "Killer":
		task_assignments = phase4_state.get("objectives", []).duplicate(true)
		section_title.text = "KILLER OBJECTIVES"
		var lines := PackedStringArray()
		for objective: Dictionary in task_assignments:
			lines.append(("âœ“  " if objective.get("completed", false) else "â—‹  ") + str(objective.get("name", "Sabotage")))
		task_list.text = "\n".join(lines)
		var completed := 0
		for objective: Dictionary in task_assignments:
			if bool(objective.get("completed", false)):
				completed += 1
		var incomplete_ids: Array[String] = []
		for objective: Dictionary in task_assignments:
			if not bool(objective.get("completed", false)):
				incomplete_ids.append(str(objective.get("id", "")))
		minimap.set_task_ids(incomplete_ids, true)
		task_progress.value = 0 if task_assignments.is_empty() else 100.0 * completed / task_assignments.size()
		task_progress_label.text = "SABOTAGES  %d/%d" % [completed, task_assignments.size()]
	var blackout := false
	var active_effects := PackedStringArray()
	for sabotage: Dictionary in phase4_state.get("sabotages", []):
		if bool(sabotage.get("active", false)):
			active_effects.append(str(sabotage.get("effect", "Sabotage active")))
			blackout = blackout or str(sabotage.get("id", "")) == "generator"
	blackout_overlay.visible = blackout
	if not active_effects.is_empty():
		show_toast("SABOTAGE: " + " • ".join(active_effects))
	_layout()
	update_station(nearby_station)


func _refresh_kill_cooldown() -> void:
	if not is_instance_valid(kill_cooldown_card):
		return
	var killer := _is_living_killer()
	var cooling_down := killer and kill_cooldown_remaining > 0.0
	kill_cooldown_card.visible = killer
	if killer:
		kill_cooldown_label.text = "ELIMINATE IN %.1fs" % kill_cooldown_remaining if cooling_down else "ELIMINATE READY  •  K"
	if is_instance_valid(kill_button):
		kill_button.disabled = not killer or cooling_down


func set_nearby_body(value: bool) -> void:
	if nearby_body == value:
		return
	nearby_body = value
	update_station(nearby_station)


func _sabotage_at_station(station: Dictionary) -> Dictionary:
	if station.is_empty():
		return {}
	for sabotage: Dictionary in phase4_state.get("sabotages", []):
		if str(sabotage.get("station", "")) == str(station.get("name", "")):
			return sabotage
	return {}


func _is_living_killer() -> bool:
	return str(phase4_state.get("role", "")) == "Killer" and not bool(phase4_state.get("ghost", false))


func _is_living_camper() -> bool:
	return str(phase4_state.get("role", "")) == "Camper" and not bool(phase4_state.get("ghost", false))


func _is_killer_objective(sabotage_id: String) -> bool:
	for objective: Dictionary in phase4_state.get("objectives", []):
		if str(objective.get("id", "")) == sabotage_id:
			return true
	return false


func _objective_complete(sabotage_id: String) -> bool:
	for objective: Dictionary in phase4_state.get("objectives", []):
		if str(objective.get("id", "")) == sabotage_id:
			return bool(objective.get("completed", false))
	return false


func _assignment_for(task_id: String) -> Dictionary:
	for assignment: Dictionary in task_assignments:
		if str(assignment.get("id", "")) == task_id:
			return assignment
	return {}


func _task_percent() -> int:
	return 0 if shared_total <= 0 else clampi(roundi(100.0 * float(shared_completed) / float(shared_total)), 0, 100)


func update_player_position(at: Vector2) -> void:
	minimap.update_player_position(at)


func update_player_screen_position(at: Vector2) -> void:
	player_screen_position = at


func show_toast(message: String) -> void:
	toast_label.text = message
	toast_card.visible = true
	toast_seconds = 2.6
