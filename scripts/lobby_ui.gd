extends CanvasLayer

signal create_requested(name: String, color_index: int)
signal create_lan_requested(name: String, color_index: int)
signal join_requested(code: String, name: String, color_index: int)
signal lan_join_requested(address: String, name: String, color_index: int)
signal ready_requested(ready: bool)
signal start_requested
signal settings_requested(settings: Dictionary)
signal test_bots_requested(enabled: bool)
signal color_requested(color_index: int)
signal leave_requested
signal quit_requested
signal offline_preview_requested

const COLOR_NAMES := ["Orange", "Blue", "Green", "Red", "Purple", "Yellow"]

var local_player_id := ""
var current_state: Dictionary = {}
var ready_value := false
var root: Control
var backdrop: ColorRect
var center: CenterContainer
var menu_panel: PanelContainer
var lobby_panel: PanelContainer
var status_label: Label
var name_edit: LineEdit
var code_edit: LineEdit
var color_picker: OptionButton
var endpoint_edit: LineEdit
var room_label: Label
var room_hint_label: Label
var roster_label: RichTextLabel
var killer_row: HBoxContainer
var killer_picker: OptionButton
var ready_button: Button
var start_button: Button
var max_label: Label
var minus_button: Button
var plus_button: Button
var confirm_ejects: CheckButton
var player_names: CheckButton
var visual_tasks: CheckButton
var test_bots_button: Button
var lobby_color_picker: OptionButton
var color_hint: Label
var allow_test_bots := OS.is_debug_build()
var allow_lan_test := OS.is_debug_build()
var allow_role_picker := OS.is_debug_build()
var test_bots_enabled := false
var requested_color := -1
var killer_option_player_ids: Array[String] = []
var updating_killer_picker := false


func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	backdrop = ColorRect.new()
	backdrop.color = Color("#102b2b")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)
	center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	_build_menu()
	_build_lobby()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _build_menu() -> void:
	menu_panel = _panel(Color("#183a2e"), Color("#a7c957"))
	menu_panel.custom_minimum_size = Vector2(430, 700)
	center.add_child(menu_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	menu_panel.add_child(column)
	var title := _label("DOUBLE TAKE", 34, Color("#f4d7a7"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var subtitle := _label("PRIVATE CAMP LOBBY", 16, Color("#a7c957"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)
	column.add_child(_label("CAMPER NAME", 14, Color("#fffbe7")))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Enter your name"
	name_edit.text = _default_name()
	name_edit.max_length = 18
	name_edit.custom_minimum_size.y = 50
	column.add_child(name_edit)
	column.add_child(_label("PREFERRED COLOUR", 14, Color("#fffbe7")))
	color_picker = OptionButton.new()
	color_picker.custom_minimum_size.y = 50
	for color_name in COLOR_NAMES:
		color_picker.add_item(color_name)
	column.add_child(color_picker)
	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 8)
	column.add_child(create_row)
	var create_button := _button("CREATE ONLINE" if allow_lan_test else "CREATE PRIVATE LOBBY", 16)
	create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_button.pressed.connect(func() -> void: create_requested.emit(name_edit.text, color_picker.selected))
	create_row.add_child(create_button)
	var create_lan_button := _button("CREATE LOCAL", 16)
	create_lan_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_lan_button.visible = allow_lan_test
	create_lan_button.pressed.connect(func() -> void: create_lan_requested.emit(name_edit.text, color_picker.selected))
	create_row.add_child(create_lan_button)
	var divider := HSeparator.new()
	column.add_child(divider)
	column.add_child(_label("JOIN CODE / PC LAN IP" if allow_lan_test else "JOIN CODE", 14, Color("#fffbe7")))
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "ABC123 or 192.168.1.25" if allow_lan_test else "ABC123"
	code_edit.max_length = 64 if allow_lan_test else 6
	code_edit.custom_minimum_size.y = 50
	code_edit.text_changed.connect(func(value: String) -> void:
		if value.contains(".") or value.contains(":"):
			return
		var caret := code_edit.caret_column
		code_edit.text = value.to_upper()
		code_edit.caret_column = mini(caret, code_edit.text.length()))
	column.add_child(code_edit)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	column.add_child(join_row)
	var join_button := _button("JOIN EOS", 16)
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.pressed.connect(func() -> void: join_requested.emit(code_edit.text.to_upper(), name_edit.text, color_picker.selected))
	join_row.add_child(join_button)
	var lan_join_button := _button("JOIN LOCAL", 16)
	lan_join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lan_join_button.visible = allow_lan_test
	lan_join_button.pressed.connect(func() -> void: lan_join_requested.emit(code_edit.text, name_edit.text, color_picker.selected))
	join_row.add_child(lan_join_button)
	var preview_button := _button("OFFLINE MAP PREVIEW", 16)
	preview_button.pressed.connect(func() -> void: offline_preview_requested.emit())
	column.add_child(preview_button)
	var quit_button := _button("QUIT GAME", 16)
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	column.add_child(quit_button)
	endpoint_edit = LineEdit.new()
	endpoint_edit.visible = false
	status_label = _label("Private rooms work across networks through P2P.", 13, Color("#f4d7a7"))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(status_label)


func _build_lobby() -> void:
	lobby_panel = _panel(Color("#183a2e"), Color("#a7c957"))
	lobby_panel.custom_minimum_size = Vector2(500, 720)
	center.add_child(lobby_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	lobby_panel.add_child(column)
	room_label = _label("ROOM ------", 28, Color("#f4d7a7"))
	room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(room_label)
	room_hint_label = _label("0/4 PLAYERS - Share this code with your friends", 14, Color("#a7c957"))
	room_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(room_hint_label)
	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 10)
	column.add_child(color_row)
	color_row.add_child(_label("YOUR COLOUR", 15, Color("#fffbe7")))
	var color_spacer := Control.new()
	color_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_row.add_child(color_spacer)
	lobby_color_picker = OptionButton.new()
	lobby_color_picker.custom_minimum_size = Vector2(150, 42)
	for color_name in COLOR_NAMES:
		lobby_color_picker.add_item(color_name)
	lobby_color_picker.item_selected.connect(func(index: int) -> void: color_requested.emit(index))
	color_row.add_child(lobby_color_picker)
	color_hint = _label("", 13, Color("#f4d7a7"))
	color_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	color_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(color_hint)
	roster_label = RichTextLabel.new()
	roster_label.bbcode_enabled = true
	roster_label.fit_content = false
	roster_label.scroll_active = false
	roster_label.custom_minimum_size = Vector2(430, 78)
	roster_label.add_theme_font_size_override("normal_font_size", 16)
	column.add_child(roster_label)
	killer_row = HBoxContainer.new()
	killer_row.add_theme_constant_override("separation", 10)
	column.add_child(killer_row)
	killer_row.add_child(_label("KILLER (TEST)", 15, Color("#fffbe7")))
	var killer_spacer := Control.new()
	killer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	killer_row.add_child(killer_spacer)
	killer_picker = OptionButton.new()
	killer_picker.custom_minimum_size = Vector2(205, 38)
	killer_picker.item_selected.connect(_select_killer)
	killer_row.add_child(killer_picker)
	var max_row := HBoxContainer.new()
	max_row.add_theme_constant_override("separation", 8)
	column.add_child(max_row)
	max_row.add_child(_label("MAX PLAYERS", 15, Color("#fffbe7")))
	var max_spacer := Control.new()
	max_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	max_row.add_child(max_spacer)
	minus_button = _button("−", 20)
	minus_button.custom_minimum_size = Vector2(44, 44)
	minus_button.pressed.connect(func() -> void: _change_max(-1))
	max_row.add_child(minus_button)
	max_label = _label("4", 20, Color("#fffbe7"))
	max_row.add_child(max_label)
	plus_button = _button("+", 20)
	plus_button.custom_minimum_size = Vector2(44, 44)
	plus_button.pressed.connect(func() -> void: _change_max(1))
	max_row.add_child(plus_button)
	confirm_ejects = _check("Confirm Ejects")
	player_names = _check("Player Names")
	visual_tasks = _check("Visual Tasks")
	for toggle in [confirm_ejects, player_names, visual_tasks]:
		toggle.toggled.connect(func(_pressed: bool) -> void: _emit_settings())
		column.add_child(toggle)
	test_bots_button = _button("FILL WITH TEST BOTS", 14)
	test_bots_button.custom_minimum_size.y = 40
	test_bots_button.pressed.connect(func() -> void: test_bots_requested.emit(not test_bots_enabled))
	column.add_child(test_bots_button)
	ready_button = _button("READY", 19)
	ready_button.pressed.connect(_toggle_ready)
	column.add_child(ready_button)
	start_button = _button("START MATCH", 19)
	start_button.pressed.connect(func() -> void: start_requested.emit())
	column.add_child(start_button)
	var leave_button := _button("LEAVE LOBBY", 15)
	leave_button.pressed.connect(func() -> void: leave_requested.emit())
	column.add_child(leave_button)
	lobby_panel.visible = false


func show_menu(message := "") -> void:
	menu_panel.visible = true
	lobby_panel.visible = false
	if not message.is_empty():
		set_status(message, true)


func show_lobby(player_id: String, state: Dictionary, desired_color := -1) -> void:
	local_player_id = player_id
	requested_color = desired_color
	menu_panel.visible = false
	lobby_panel.visible = true
	ready_value = false
	update_lobby(state)


func update_lobby(state: Dictionary) -> void:
	current_state = state
	var displayed_room := str(state.get("room_code", "------"))
	room_label.text = ("LOCAL HOST  " if displayed_room.contains(".") else "ROOM  ") + displayed_room
	var cells := PackedStringArray()
	var is_host := false
	var local_record: Dictionary = {}
	var visible_player_count := 0
	for player: Dictionary in state.get("players", []):
		var badges := PackedStringArray()
		if player.get("host", false):
			badges.append("HOST")
		if player.get("ready", false):
			badges.append("READY")
		if not player.get("connected", true):
			badges.append("RECONNECTING")
		var suffix := "  [color=#a7c957]%s[/color]" % " / ".join(badges) if not badges.is_empty() else ""
		cells.append("[cell][color=#fffbe7]%s[/color]%s[/cell]" % [str(player.get("name", "Camper")), suffix])
		if bool(player.get("connected", false)):
			visible_player_count += 1
		if player.get("player_id", "") == local_player_id:
			is_host = bool(player.get("host", false))
			local_record = player
	roster_label.text = "[table=2]%s[/table]" % "".join(cells)
	ready_value = bool(local_record.get("ready", false))
	ready_button.text = "NOT READY" if ready_value else "READY"
	var settings: Dictionary = state.get("settings", {})
	if displayed_room.contains("."):
		room_hint_label.text = "%d/%d PLAYERS - Others enter this HOST IP" % [visible_player_count, int(settings.get("max_players", 4))]
	else:
		room_hint_label.text = "%d/%d PLAYERS - Share this code with your friends" % [visible_player_count, int(settings.get("max_players", 4))]
	_update_killer_picker(state.get("players", []), str(settings.get("forced_killer_player_id", "")))
	killer_row.visible = is_host and allow_role_picker
	killer_picker.disabled = not is_host
	max_label.text = str(settings.get("max_players", 4))
	confirm_ejects.set_pressed_no_signal(bool(settings.get("confirm_ejects", true)))
	player_names.set_pressed_no_signal(bool(settings.get("player_names", true)))
	visual_tasks.set_pressed_no_signal(bool(settings.get("visual_tasks", true)))
	for control in [minus_button, plus_button, confirm_ejects, player_names, visual_tasks]:
		control.disabled = not is_host
	test_bots_enabled = false
	for player: Dictionary in state.get("players", []):
		if player.get("bot", false):
			test_bots_enabled = true
			break
	test_bots_button.visible = is_host and allow_test_bots
	test_bots_button.disabled = not is_host
	test_bots_button.text = "REMOVE TEST BOTS" if test_bots_enabled else "FILL WITH TEST BOTS"
	start_button.visible = is_host
	var connected_count := 0
	var all_ready := true
	for player: Dictionary in state.get("players", []):
		if player.get("connected", false):
			connected_count += 1
			all_ready = all_ready and bool(player.get("ready", false))
	start_button.disabled = connected_count < int(state.get("minimum_players", 4)) or not all_ready
	_update_color_picker(local_record, state.get("players", []))


func _update_color_picker(local_record: Dictionary, lobby_players: Array) -> void:
	if not is_instance_valid(lobby_color_picker) or local_record.is_empty():
		return
	var current_color := clampi(int(local_record.get("color", 0)), 0, COLOR_NAMES.size() - 1)
	var used := {}
	for player: Dictionary in lobby_players:
		if player.get("connected", false) and str(player.get("player_id", "")) != local_player_id:
			used[int(player.get("color", -1))] = true
	for index in range(COLOR_NAMES.size()):
		lobby_color_picker.set_item_disabled(index, used.has(index))
	lobby_color_picker.select(current_color)
	if requested_color >= 0 and requested_color != current_color:
		color_hint.text = "%s was taken — you joined as %s. Pick any available colour." % [COLOR_NAMES[requested_color], COLOR_NAMES[current_color]]
		requested_color = current_color
	else:
		color_hint.text = "Unavailable colours are disabled."


func _update_killer_picker(lobby_players: Array, selected_player_id: String) -> void:
	if not is_instance_valid(killer_picker):
		return
	updating_killer_picker = true
	killer_picker.clear()
	killer_option_player_ids.clear()
	killer_picker.add_item("RANDOM")
	killer_option_player_ids.append("")
	var selected_index := 0
	for player: Dictionary in lobby_players:
		if not bool(player.get("connected", false)):
			continue
		var player_id := str(player.get("player_id", ""))
		if player_id.is_empty():
			continue
		var label := str(player.get("name", "Camper"))
		if player_id == local_player_id:
			label += " (YOU)"
		killer_picker.add_item(label)
		killer_option_player_ids.append(player_id)
		if player_id == selected_player_id:
			selected_index = killer_option_player_ids.size() - 1
	killer_picker.select(selected_index)
	updating_killer_picker = false


func _select_killer(index: int) -> void:
	if updating_killer_picker or index < 0 or index >= killer_option_player_ids.size():
		return
	var settings: Dictionary = current_state.get("settings", {}).duplicate(true)
	settings["forced_killer_player_id"] = killer_option_player_ids[index]
	settings_requested.emit(settings)


func set_status(message: String, is_error := false) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color("#ff9b8f") if is_error else Color("#f4d7a7"))


func set_color_notice(message: String, is_error := false) -> void:
	if not is_instance_valid(color_hint):
		return
	color_hint.text = message
	color_hint.add_theme_color_override("font_color", Color("#ff9b8f") if is_error else Color("#f4d7a7"))


func set_endpoint(url: String) -> void:
	endpoint_edit.text = url


func get_endpoint() -> String:
	var value := endpoint_edit.text.strip_edges().trim_suffix("/")
	if not value.begins_with("http://") and not value.begins_with("https://"):
		value = "http://" + value
	return value


func _toggle_ready() -> void:
	ready_requested.emit(not ready_value)


func _change_max(delta: int) -> void:
	var settings: Dictionary = current_state.get("settings", {}).duplicate(true)
	settings["max_players"] = clampi(int(settings.get("max_players", 4)) + delta, 4, 6)
	settings_requested.emit(settings)


func _emit_settings() -> void:
	var settings: Dictionary = current_state.get("settings", {}).duplicate(true)
	settings["max_players"] = int(max_label.text)
	settings["confirm_ejects"] = confirm_ejects.button_pressed
	settings["player_names"] = player_names.button_pressed
	settings["visual_tasks"] = visual_tasks.button_pressed
	settings_requested.emit(settings)


func _layout() -> void:
	if not is_instance_valid(root):
		return
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _panel(fill: Color, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _button(value: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 52
	button.add_theme_font_size_override("font_size", font_size)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#8b5e3c")
	normal.border_color = Color("#f4d7a7")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(9)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#a7c957")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#2e684f")
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("#3f4b45")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color("#fffbe7"))
	button.add_theme_color_override("font_hover_color", Color("#102b2b"))
	return button


func _check(value: String) -> CheckButton:
	var check := CheckButton.new()
	check.text = value
	check.button_pressed = true
	check.custom_minimum_size.y = 36
	check.add_theme_font_size_override("font_size", 16)
	check.add_theme_color_override("font_color", Color("#fffbe7"))
	return check


func _label(value: String, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	return label


func _default_name() -> String:
	var saved := str(ProjectSettings.get_setting("double_take/player_name", "Camper"))
	return saved.left(18)
