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
signal customization_requested(color_index: int, hat: String, outfit: String)
signal leave_requested
signal quit_requested
signal offline_preview_requested

const CustomizationCatalog = preload("res://scripts/customization_catalog.gd")
const COLOR_NAMES := ["Orange", "Blue", "Green", "Red", "Purple", "Yellow"]
const ChatBoxScript = preload("res://scripts/chat_box.gd")

const KILL_COOLDOWN_OPTIONS: Array[float] = [10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 60.0]
const WALKING_PACE_OPTIONS: Array[float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
const DISCUSSION_TIME_OPTIONS: Array[float] = [0.0, 10.0, 15.0, 20.0, 30.0, 45.0, 60.0]
const VOTING_TIME_OPTIONS: Array[float] = [15.0, 30.0, 45.0, 60.0, 90.0, 120.0]

const PORTRAIT_TEXTURES := [
	preload("res://assets/phase5/portraits/orange.png"),
	preload("res://assets/phase5/portraits/blue.png"),
	preload("res://assets/phase5/portraits/green.png"),
	preload("res://assets/phase5/portraits/red.png"),
	preload("res://assets/phase5/portraits/purple.png"),
	preload("res://assets/phase5/portraits/yellow.png")
]
const GREYSCALE_SHADER := preload("res://shaders/greyscale.gdshader")

var local_player_id := ""
var current_state: Dictionary = {}
var ready_value := false
var chat_box: Control
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
var roster_container: HBoxContainer
var killer_row: HBoxContainer
var killer_picker: OptionButton
var ready_button: Button
var start_button: Button
var max_label: Label
var minus_button: Button
var plus_button: Button

# Match settings stepper controls
var kill_cd_minus: Button
var kill_cd_plus: Button
var kill_cd_label: Label
var pace_minus: Button
var pace_plus: Button
var pace_label: Label
var disc_minus: Button
var disc_plus: Button
var disc_label: Label
var vote_minus: Button
var vote_plus: Button
var vote_label: Label

var confirm_ejects: CheckButton
var player_names: CheckButton
var visual_tasks: CheckButton
var test_bots_button: Button
var lobby_color_picker: OptionButton

# Wardrobe / Customization Modal variables
var wardrobe_modal: Control = null
var wardrobe_preview_char: TextureRect = null
var wardrobe_preview_outfit: TextureRect = null
var wardrobe_preview_hat: TextureRect = null
var wardrobe_preview_name: Label = null
var wardrobe_item_title: Label = null
var wardrobe_grid: GridContainer = null
var wardrobe_tab_btns: Dictionary = {}
var selected_look_id := "classic"
var selected_hat_id := "classic"
var selected_outfit_id := "none"
var selected_color_idx := 0
var current_wardrobe_tab := "looks"
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
	chat_box = ChatBoxScript.new()
	root.add_child(chat_box)
	chat_box.visible = false
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
	var create_button := _button("CREATE GAME", 18)
	create_button.custom_minimum_size.y = 52
	create_button.pressed.connect(func() -> void: create_requested.emit(name_edit.text, color_picker.selected))
	column.add_child(create_button)
	
	var divider := HSeparator.new()
	column.add_child(divider)
	
	column.add_child(_label("ROOM CODE", 14, Color("#fffbe7")))
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "ENTER 6-LETTER CODE"
	code_edit.max_length = 32
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.custom_minimum_size.y = 50
	code_edit.text_changed.connect(func(value: String) -> void:
		var caret := code_edit.caret_column
		code_edit.text = value.to_upper().strip_edges()
		code_edit.caret_column = mini(caret, code_edit.text.length()))
	column.add_child(code_edit)
	
	var join_button := _button("JOIN GAME", 18)
	join_button.custom_minimum_size.y = 52
	join_button.pressed.connect(func() -> void:
		var raw_input := code_edit.text.to_upper().strip_edges()
		if raw_input.contains(".") or raw_input.begins_with("192.") or raw_input.begins_with("10.") or raw_input.begins_with("172.") or raw_input.begins_with("127."):
			lan_join_requested.emit(raw_input, name_edit.text, color_picker.selected)
		else:
			join_requested.emit(raw_input, name_edit.text, color_picker.selected))
	column.add_child(join_button)
	
	var preview_button := _button("OFFLINE MAP PREVIEW", 15)
	preview_button.custom_minimum_size.y = 44
	preview_button.pressed.connect(func() -> void: offline_preview_requested.emit())
	column.add_child(preview_button)
	var quit_button := _button("QUIT GAME", 15)
	quit_button.custom_minimum_size.y = 44
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	column.add_child(quit_button)
	endpoint_edit = LineEdit.new()
	endpoint_edit.visible = false
	status_label = _label("Enter the 6-letter room code from your host to join.", 13, Color("#f4d7a7"))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(status_label)


func _build_lobby() -> void:
	lobby_panel = _panel(Color("#183a2e"), Color("#a7c957"))
	lobby_panel.custom_minimum_size = Vector2(920, 560)
	center.add_child(lobby_panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(880, 524)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	lobby_panel.add_child(scroll)

	var main_row := HBoxContainer.new()
	main_row.custom_minimum_size = Vector2(860, 510)
	main_row.add_theme_constant_override("separation", 22)
	scroll.add_child(main_row)

	# ===== LEFT COLUMN: Room info, players, readiness & action buttons =====
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(410, 0)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 6)
	main_row.add_child(left_col)

	room_label = _label("ROOM ------", 28, Color("#f4d7a7"))
	room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_col.add_child(room_label)

	room_hint_label = _label("0/4 PLAYERS - Share this code with your friends", 13, Color("#a7c957"))
	room_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_col.add_child(room_hint_label)

	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 8)
	left_col.add_child(color_row)
	color_row.add_child(_label("YOUR COLOUR", 14, Color("#fffbe7")))
	var color_spacer := Control.new()
	color_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_row.add_child(color_spacer)
	lobby_color_picker = OptionButton.new()
	lobby_color_picker.custom_minimum_size = Vector2(130, 36)
	for color_name in COLOR_NAMES:
		lobby_color_picker.add_item(color_name)
	lobby_color_picker.item_selected.connect(func(index: int) -> void: color_requested.emit(index))
	color_row.add_child(lobby_color_picker)

	var wardrobe_btn := _button("👔 LOOK", 13)
	wardrobe_btn.custom_minimum_size = Vector2(90, 36)
	wardrobe_btn.pressed.connect(_open_wardrobe_modal)
	color_row.add_child(wardrobe_btn)

	color_hint = _label("", 12, Color("#f4d7a7"))
	color_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	color_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_col.add_child(color_hint)

	var roster_header := _label("CAMP ROSTER", 14, Color("#ffd166"))
	roster_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_col.add_child(roster_header)

	roster_container = HBoxContainer.new()
	roster_container.alignment = BoxContainer.ALIGNMENT_CENTER
	roster_container.custom_minimum_size = Vector2(410, 140)
	roster_container.add_theme_constant_override("separation", 6)
	left_col.add_child(roster_container)

	roster_label = RichTextLabel.new()
	roster_label.visible = false
	left_col.add_child(roster_label)

	var left_spacer := Control.new()
	left_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(left_spacer)

	ready_button = _button("READY", 18)
	ready_button.custom_minimum_size.y = 44
	ready_button.pressed.connect(_toggle_ready)
	left_col.add_child(ready_button)

	start_button = _button("START MATCH", 18)
	start_button.custom_minimum_size.y = 44
	start_button.pressed.connect(func() -> void: start_requested.emit())
	left_col.add_child(start_button)

	var leave_button := _button("LEAVE LOBBY", 14)
	leave_button.custom_minimum_size.y = 36
	leave_button.pressed.connect(func() -> void: leave_requested.emit())
	left_col.add_child(leave_button)

	# ===== VERTICAL SEPARATOR =====
	var sep := VSeparator.new()
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color("#2e684f")
	sep_style.thickness = 2
	sep_style.vertical = true
	sep.add_theme_stylebox_override("separator", sep_style)
	main_row.add_child(sep)

	# ===== RIGHT COLUMN: Camp rules, match settings & host tools =====
	var right_col := VBoxContainer.new()
	right_col.custom_minimum_size = Vector2(410, 0)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 5)
	main_row.add_child(right_col)

	var settings_header := _label("CAMP RULES & SETTINGS", 16, Color("#ffd166"))
	settings_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_col.add_child(settings_header)

	var max_row := HBoxContainer.new()
	max_row.add_theme_constant_override("separation", 8)
	right_col.add_child(max_row)
	max_row.add_child(_label("MAX PLAYERS", 14, Color("#fffbe7")))
	var max_spacer := Control.new()
	max_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	max_row.add_child(max_spacer)
	minus_button = _button("−", 18)
	minus_button.custom_minimum_size = Vector2(38, 36)
	minus_button.pressed.connect(func() -> void: _change_max(-1))
	max_row.add_child(minus_button)
	max_label = _label("4", 16, Color("#ffd166"))
	max_label.custom_minimum_size = Vector2(65, 36)
	max_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	max_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	max_row.add_child(max_label)
	plus_button = _button("+", 18)
	plus_button.custom_minimum_size = Vector2(38, 36)
	plus_button.pressed.connect(func() -> void: _change_max(1))
	max_row.add_child(plus_button)

	var cd_parts := _stepper_row("KILL COOLDOWN")
	right_col.add_child(cd_parts[0])
	kill_cd_minus = cd_parts[1]
	kill_cd_label = cd_parts[2]
	kill_cd_plus = cd_parts[3]
	kill_cd_minus.pressed.connect(func() -> void: _change_kill_cooldown(-1))
	kill_cd_plus.pressed.connect(func() -> void: _change_kill_cooldown(1))

	var pace_parts := _stepper_row("WALKING PACE")
	right_col.add_child(pace_parts[0])
	pace_minus = pace_parts[1]
	pace_label = pace_parts[2]
	pace_plus = pace_parts[3]
	pace_minus.pressed.connect(func() -> void: _change_walking_pace(-1))
	pace_plus.pressed.connect(func() -> void: _change_walking_pace(1))

	var disc_parts := _stepper_row("DISCUSSION TIME")
	right_col.add_child(disc_parts[0])
	disc_minus = disc_parts[1]
	disc_label = disc_parts[2]
	disc_plus = disc_parts[3]
	disc_minus.pressed.connect(func() -> void: _change_discussion_time(-1))
	disc_plus.pressed.connect(func() -> void: _change_discussion_time(1))

	var vote_parts := _stepper_row("VOTING TIME")
	right_col.add_child(vote_parts[0])
	vote_minus = vote_parts[1]
	vote_label = vote_parts[2]
	vote_plus = vote_parts[3]
	vote_minus.pressed.connect(func() -> void: _change_voting_time(-1))
	vote_plus.pressed.connect(func() -> void: _change_voting_time(1))

	var toggles_box := VBoxContainer.new()
	toggles_box.add_theme_constant_override("separation", 2)
	right_col.add_child(toggles_box)

	confirm_ejects = _check("Confirm Ejects")
	player_names = _check("Player Names")
	visual_tasks = _check("Visual Tasks")
	for toggle in [confirm_ejects, player_names, visual_tasks]:
		toggle.toggled.connect(func(_pressed: bool) -> void: _emit_settings())
		toggles_box.add_child(toggle)

	killer_row = HBoxContainer.new()
	killer_row.add_theme_constant_override("separation", 10)
	right_col.add_child(killer_row)
	killer_row.add_child(_label("KILLER (TEST)", 14, Color("#fffbe7")))
	var killer_spacer := Control.new()
	killer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	killer_row.add_child(killer_spacer)
	killer_picker = OptionButton.new()
	killer_picker.custom_minimum_size = Vector2(190, 36)
	killer_picker.item_selected.connect(_select_killer)
	killer_row.add_child(killer_picker)

	test_bots_button = _button("FILL WITH TEST BOTS", 13)
	test_bots_button.custom_minimum_size.y = 36
	test_bots_button.pressed.connect(func() -> void: test_bots_requested.emit(not test_bots_enabled))
	right_col.add_child(test_bots_button)

	lobby_panel.visible = false


func show_menu(message := "") -> void:
	menu_panel.visible = true
	lobby_panel.visible = false
	if is_instance_valid(chat_box):
		chat_box.visible = false
		chat_box.set_chat_open(false)
	if not message.is_empty():
		set_status(message, true)


func show_lobby(player_id: String, state: Dictionary, desired_color := -1) -> void:
	local_player_id = player_id
	requested_color = desired_color
	menu_panel.visible = false
	lobby_panel.visible = true
	ready_value = false
	if is_instance_valid(chat_box):
		chat_box.visible = true
		chat_box.local_player_id = player_id
	update_lobby(state)


func setup_chat(session: Node) -> void:
	if is_instance_valid(chat_box):
		chat_box.setup(session, local_player_id, false)



func update_lobby(state: Dictionary) -> void:
	current_state = state
	var displayed_room := str(state.get("room_code", "------"))
	room_label.text = "ROOM  " + displayed_room
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
	room_hint_label.text = "%d/%d PLAYERS - Share this code with your friends" % [visible_player_count, int(settings.get("max_players", 4))]
	_update_killer_picker(state.get("players", []), str(settings.get("forced_killer_player_id", "")))
	killer_row.visible = is_host and allow_role_picker
	killer_picker.disabled = not is_host
	max_label.text = str(settings.get("max_players", 4))
	var kill_cd: float = float(settings.get("kill_cooldown", 25.0))
	var pace: float = float(settings.get("walking_pace", 1.0))
	var disc: float = float(settings.get("discussion_time", 15.0))
	var vote: float = float(settings.get("voting_time", 45.0))
	if is_instance_valid(kill_cd_label):
		kill_cd_label.text = "%.0fs" % kill_cd
	if is_instance_valid(pace_label):
		pace_label.text = "%.2fx" % pace
	if is_instance_valid(disc_label):
		disc_label.text = "0s (Off)" if disc <= 0.0 else "%.0fs" % disc
	if is_instance_valid(vote_label):
		vote_label.text = "%.0fs" % vote
	for btn: Button in [minus_button, plus_button, kill_cd_minus, kill_cd_plus, pace_minus, pace_plus, disc_minus, disc_plus, vote_minus, vote_plus]:
		if is_instance_valid(btn):
			btn.visible = is_host
			btn.disabled = not is_host
	confirm_ejects.set_pressed_no_signal(bool(settings.get("confirm_ejects", true)))
	player_names.set_pressed_no_signal(bool(settings.get("player_names", true)))
	visual_tasks.set_pressed_no_signal(bool(settings.get("visual_tasks", true)))
	for control in [confirm_ejects, player_names, visual_tasks]:
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
	_update_color_picker(local_record, state.get("players", []))
	_update_roster_characters(state.get("players", []))


func _update_roster_characters(players_list: Array) -> void:
	if not is_instance_valid(roster_container):
		return
	for child in roster_container.get_children():
		child.queue_free()

	for player: Dictionary in players_list:
		if not bool(player.get("connected", true)):
			continue
		var player_id := str(player.get("player_id", ""))
		var pname := str(player.get("name", "Camper"))
		var color_idx := clampi(int(player.get("color", 0)), 0, 5)
		var is_ready := bool(player.get("ready", false))
		var is_player_host := bool(player.get("host", false))
		var is_local := player_id == local_player_id

		# Camper character card without button borders
		var card_vbox := VBoxContainer.new()
		card_vbox.custom_minimum_size = Vector2(66, 130)
		card_vbox.add_theme_constant_override("separation", 3)
		card_vbox.alignment = BoxContainer.ALIGNMENT_CENTER

		# Sprite Container
		var sprite_frame := Control.new()
		sprite_frame.custom_minimum_size = Vector2(60, 75)
		sprite_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card_vbox.add_child(sprite_frame)

		var look_id := str(player.get("look", player.get("hat", "classic")))
		var char_rect := TextureRect.new()
		char_rect.texture = CustomizationCatalog.get_skin_portrait(look_id, color_idx)
		char_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		char_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		char_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		
		# B/W shader if unready, full color if ready!
		if not is_ready:
			var mat := ShaderMaterial.new()
			mat.shader = GREYSCALE_SHADER
			char_rect.material = mat
			char_rect.modulate = Color(0.85, 0.85, 0.85, 0.85)
		else:
			char_rect.material = null
			char_rect.modulate = Color(1.0, 1.0, 1.0, 1.0)
		sprite_frame.add_child(char_rect)

		# Player Name label
		var name_lbl := Label.new()
		name_lbl.text = pname
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", Color("#a7c957") if is_local else (Color("#ffd166") if is_player_host else Color("#fffbe7")))
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_lbl.custom_minimum_size = Vector2(62, 15)
		card_vbox.add_child(name_lbl)

		# Status Badge
		var badge_lbl := Label.new()
		badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge_lbl.add_theme_font_size_override("font_size", 10)
		if is_player_host:
			badge_lbl.text = "★ HOST" if not is_ready else "★ READY"
			badge_lbl.add_theme_color_override("font_color", Color("#ffd166") if not is_ready else Color("#52b788"))
		elif is_ready:
			badge_lbl.text = "✓ READY"
			badge_lbl.add_theme_color_override("font_color", Color("#52b788"))
		else:
			badge_lbl.text = "WAITING"
			badge_lbl.add_theme_color_override("font_color", Color("#9e9e9e"))
		badge_lbl.custom_minimum_size = Vector2(62, 14)
		card_vbox.add_child(badge_lbl)

		roster_container.add_child(card_vbox)


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


func _stepper_row(title_text: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_label(title_text, 14, Color("#fffbe7")))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var minus_btn := _button("−", 18)
	minus_btn.custom_minimum_size = Vector2(38, 38)
	row.add_child(minus_btn)
	var val_label := _label("---", 16, Color("#ffd166"))
	val_label.custom_minimum_size = Vector2(65, 38)
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(val_label)
	var plus_btn := _button("+", 18)
	plus_btn.custom_minimum_size = Vector2(38, 38)
	row.add_child(plus_btn)
	return [row, minus_btn, val_label, plus_btn]


func _find_closest_option(options: Array[float], val: float) -> int:
	var best_idx := 0
	var best_diff := 999999.0
	for i in range(options.size()):
		var diff := absf(options[i] - val)
		if diff < best_diff:
			best_diff = diff
			best_idx = i
	return best_idx


func _change_kill_cooldown(delta: int) -> void:
	var settings: Dictionary = current_state.get("settings", {}).duplicate(true)
	var current_val: float = float(settings.get("kill_cooldown", 25.0))
	var idx := _find_closest_option(KILL_COOLDOWN_OPTIONS, current_val)
	var new_idx := clampi(idx + delta, 0, KILL_COOLDOWN_OPTIONS.size() - 1)
	settings["kill_cooldown"] = KILL_COOLDOWN_OPTIONS[new_idx]
	settings_requested.emit(settings)


func _change_walking_pace(delta: int) -> void:
	var settings: Dictionary = current_state.get("settings", {}).duplicate(true)
	var current_val: float = float(settings.get("walking_pace", 1.0))
	var idx := _find_closest_option(WALKING_PACE_OPTIONS, current_val)
	var new_idx := clampi(idx + delta, 0, WALKING_PACE_OPTIONS.size() - 1)
	settings["walking_pace"] = WALKING_PACE_OPTIONS[new_idx]
	settings_requested.emit(settings)


func _change_discussion_time(delta: int) -> void:
	var settings: Dictionary = current_state.get("settings", {}).duplicate(true)
	var current_val: float = float(settings.get("discussion_time", 15.0))
	var idx := _find_closest_option(DISCUSSION_TIME_OPTIONS, current_val)
	var new_idx := clampi(idx + delta, 0, DISCUSSION_TIME_OPTIONS.size() - 1)
	settings["discussion_time"] = DISCUSSION_TIME_OPTIONS[new_idx]
	settings_requested.emit(settings)


func _change_voting_time(delta: int) -> void:
	var settings: Dictionary = current_state.get("settings", {}).duplicate(true)
	var current_val: float = float(settings.get("voting_time", 45.0))
	var idx := _find_closest_option(VOTING_TIME_OPTIONS, current_val)
	var new_idx := clampi(idx + delta, 0, VOTING_TIME_OPTIONS.size() - 1)
	settings["voting_time"] = VOTING_TIME_OPTIONS[new_idx]
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
	if is_instance_valid(chat_box):
		var vp_size := get_viewport().get_visible_rect().size
		var btn_w := 96.0
		var btn_h := 36.0
		chat_box.toggle_button.size = Vector2(btn_w, btn_h)
		chat_box.toggle_button.position = Vector2(vp_size.x - btn_w - 20.0, 20.0)
		var panel_w := clampf(vp_size.x * 0.36, 300.0, 380.0)
		var panel_h := clampf(vp_size.y * 0.72, 340.0, 560.0)
		chat_box.chat_panel.size = Vector2(panel_w, panel_h)
		chat_box.chat_panel.position = Vector2(vp_size.x - panel_w - 20.0, chat_box.toggle_button.position.y + btn_h + 10.0)



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


# ====================================================
# WARDROBE & CUSTOMIZATION MODAL
# ====================================================

func _open_wardrobe_modal() -> void:
	if not is_instance_valid(wardrobe_modal):
		_build_wardrobe_modal()

	var local_rec := {}
	for p: Dictionary in current_state.get("players", []):
		if str(p.get("player_id", "")) == local_player_id:
			local_rec = p
			break
	if not local_rec.is_empty():
		selected_color_idx = clampi(int(local_rec.get("color", 0)), 0, 5)
		selected_look_id = str(local_rec.get("look", local_rec.get("hat", "classic")))
		if not CustomizationCatalog.LOOKS.has(selected_look_id):
			selected_look_id = "classic"
		if is_instance_valid(wardrobe_preview_name):
			wardrobe_preview_name.text = str(local_rec.get("name", "Camper"))
	else:
		var saved := CustomizationCatalog.load_local_customization()
		selected_color_idx = clampi(int(saved.get("color", 0)), 0, 5)
		selected_look_id = str(saved.get("look", "classic"))

	_switch_wardrobe_tab("looks")
	_update_wardrobe_preview()
	wardrobe_modal.visible = true


func _build_wardrobe_modal() -> void:
	wardrobe_modal = Control.new()
	wardrobe_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wardrobe_modal.visible = false
	root.add_child(wardrobe_modal)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.09, 0.07, 0.85)
	wardrobe_modal.add_child(bg)

	var center_box := CenterContainer.new()
	center_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wardrobe_modal.add_child(center_box)

	var dialog_panel := PanelContainer.new()
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color("#0b1c15")
	p_style.border_color = Color("#52b788")
	p_style.set_border_width_all(3)
	p_style.set_corner_radius_all(14)
	p_style.content_margin_left = 20
	p_style.content_margin_right = 20
	p_style.content_margin_top = 16
	p_style.content_margin_bottom = 16
	dialog_panel.add_theme_stylebox_override("panel", p_style)
	dialog_panel.custom_minimum_size = Vector2(720, 500)
	center_box.add_child(dialog_panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	dialog_panel.add_child(main_vbox)

	# Header: Title + Close [X]
	var header_row := HBoxContainer.new()
	main_vbox.add_child(header_row)

	var title := _label("👔 WARDROBE & CUSTOMIZATION", 20, Color("#ffd166"))
	header_row.add_child(title)

	var h_spacer := Control.new()
	h_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(h_spacer)

	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.pressed.connect(_close_wardrobe_modal)
	header_row.add_child(close_btn)

	# Body: Left Preview, Right Selectors
	var body_row := HBoxContainer.new()
	body_row.add_theme_constant_override("separation", 20)
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(body_row)

	# --- LEFT: PREVIEW COLUMN ---
	var preview_panel := PanelContainer.new()
	var prev_style := StyleBoxFlat.new()
	prev_style.bg_color = Color("#07140e")
	prev_style.border_color = Color("#2e684f")
	prev_style.set_border_width_all(2)
	prev_style.set_corner_radius_all(10)
	prev_style.content_margin_left = 14
	prev_style.content_margin_right = 14
	prev_style.content_margin_top = 14
	prev_style.content_margin_bottom = 14
	preview_panel.add_theme_stylebox_override("panel", prev_style)
	preview_panel.custom_minimum_size = Vector2(230, 360)
	body_row.add_child(preview_panel)

	var prev_vbox := VBoxContainer.new()
	prev_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	prev_vbox.add_theme_constant_override("separation", 10)
	preview_panel.add_child(prev_vbox)

	var prev_title := _label("CAMPER PREVIEW", 13, Color("#a7c957"))
	prev_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prev_vbox.add_child(prev_title)

	var sprite_box := Control.new()
	sprite_box.custom_minimum_size = Vector2(140, 175)
	sprite_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	prev_vbox.add_child(sprite_box)

	wardrobe_preview_char = TextureRect.new()
	wardrobe_preview_char.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wardrobe_preview_char.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wardrobe_preview_char.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sprite_box.add_child(wardrobe_preview_char)

	wardrobe_preview_name = _label("Camper", 14, Color("#fffbe7"))
	wardrobe_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prev_vbox.add_child(wardrobe_preview_name)

	wardrobe_item_title = _label("", 11, Color("#f4d7a7"))
	wardrobe_item_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wardrobe_item_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prev_vbox.add_child(wardrobe_item_title)

	# --- RIGHT: TABS & ITEMS GRID ---
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 10)
	body_row.add_child(right_vbox)

	var tabs_row := HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 10)
	right_vbox.add_child(tabs_row)

	var btn_looks := _button("🎭 LOOKS", 13)
	btn_looks.custom_minimum_size = Vector2(140, 36)
	btn_looks.pressed.connect(func() -> void: _switch_wardrobe_tab("looks"))
	tabs_row.add_child(btn_looks)
	wardrobe_tab_btns["looks"] = btn_looks

	var btn_colors := _button("🎨 COLOUR", 13)
	btn_colors.custom_minimum_size = Vector2(140, 36)
	btn_colors.pressed.connect(func() -> void: _switch_wardrobe_tab("colors"))
	tabs_row.add_child(btn_colors)
	wardrobe_tab_btns["colors"] = btn_colors

	var grid_scroll := ScrollContainer.new()
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	right_vbox.add_child(grid_scroll)

	wardrobe_grid = GridContainer.new()
	wardrobe_grid.columns = 3
	wardrobe_grid.add_theme_constant_override("h_separation", 12)
	wardrobe_grid.add_theme_constant_override("v_separation", 12)
	wardrobe_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.add_child(wardrobe_grid)

	# Footer: Action Buttons
	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 12)
	main_vbox.add_child(footer_row)

	var f_spacer := Control.new()
	f_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(f_spacer)

	var cancel_btn := _button("CANCEL", 14)
	cancel_btn.custom_minimum_size = Vector2(110, 40)
	cancel_btn.pressed.connect(_close_wardrobe_modal)
	footer_row.add_child(cancel_btn)

	var save_btn := _button("✓ EQUIP & SAVE", 15)
	save_btn.custom_minimum_size = Vector2(160, 40)
	save_btn.pressed.connect(_save_wardrobe)
	footer_row.add_child(save_btn)


func _switch_wardrobe_tab(tab: String) -> void:
	current_wardrobe_tab = tab
	for t in wardrobe_tab_btns:
		var btn: Button = wardrobe_tab_btns[t]
		if t == tab:
			btn.modulate = Color(1.2, 1.2, 1.2)
		else:
			btn.modulate = Color(0.75, 0.75, 0.75)
	_populate_wardrobe_grid()


func _populate_wardrobe_grid() -> void:
	if not is_instance_valid(wardrobe_grid):
		return
	for c in wardrobe_grid.get_children():
		c.queue_free()

	if current_wardrobe_tab == "looks":
		for look_id in CustomizationCatalog.get_all_look_ids():
			var look: Dictionary = CustomizationCatalog.get_look(look_id)
			var item_card := _create_wardrobe_item_card(
				str(look.get("name", "Classic")),
				str(look.get("icon", "")),
				look_id == selected_look_id,
				func() -> void:
					selected_look_id = look_id
					_update_wardrobe_preview()
					_populate_wardrobe_grid()
			)
			wardrobe_grid.add_child(item_card)
	elif current_wardrobe_tab == "colors":
		for i in range(COLOR_NAMES.size()):
			var c_name: String = COLOR_NAMES[i]
			var is_selected := i == selected_color_idx
			var item_card := _create_wardrobe_color_card(
				c_name,
				i,
				is_selected,
				func() -> void:
					selected_color_idx = i
					_update_wardrobe_preview()
					_populate_wardrobe_grid()
			)
			wardrobe_grid.add_child(item_card)


func _create_wardrobe_item_card(title_text: String, icon_path: String, is_selected: bool, on_click: Callable) -> Control:
	var card := Button.new()
	card.custom_minimum_size = Vector2(125, 95)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0f291e") if not is_selected else Color("#1b4d38")
	style.border_color = Color("#ffd166") if is_selected else Color("#2e684f")
	style.set_border_width_all(3 if is_selected else 1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("normal", style)
	card.add_theme_stylebox_override("hover", style)
	card.add_theme_stylebox_override("pressed", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(48, 48)
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = CustomizationCatalog.get_icon_texture(icon_path)
	vbox.add_child(icon_rect)

	var lbl := Label.new()
	lbl.text = title_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("#ffd166") if is_selected else Color("#fffbe7"))
	vbox.add_child(lbl)

	card.pressed.connect(on_click)
	return card


func _create_wardrobe_color_card(color_name: String, color_idx: int, is_selected: bool, on_click: Callable) -> Control:
	var card := Button.new()
	card.custom_minimum_size = Vector2(125, 95)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0f291e") if not is_selected else Color("#1b4d38")
	style.border_color = Color("#ffd166") if is_selected else Color("#2e684f")
	style.set_border_width_all(3 if is_selected else 1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	card.add_theme_stylebox_override("normal", style)
	card.add_theme_stylebox_override("hover", style)
	card.add_theme_stylebox_override("pressed", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(48, 48)
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = PORTRAIT_TEXTURES[color_idx]
	vbox.add_child(icon_rect)

	var lbl := Label.new()
	lbl.text = color_name
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("#ffd166") if is_selected else Color("#fffbe7"))
	vbox.add_child(lbl)

	card.pressed.connect(on_click)
	return card


func _update_wardrobe_preview() -> void:
	if not is_instance_valid(wardrobe_preview_char):
		return
	wardrobe_preview_char.texture = CustomizationCatalog.get_skin_portrait(selected_look_id, selected_color_idx)
	
	var look_entry := CustomizationCatalog.get_look(selected_look_id)
	var look_name: String = str(look_entry.get("name", "Classic Camper"))
	var look_desc: String = str(look_entry.get("desc", ""))
	wardrobe_item_title.text = "%s\n%s" % [look_name, look_desc]


func _save_wardrobe() -> void:
	CustomizationCatalog.save_local_customization({
		"color": selected_color_idx,
		"look": selected_look_id
	})
	customization_requested.emit(selected_color_idx, selected_look_id, "")
	color_requested.emit(selected_color_idx)
	_close_wardrobe_modal()


func _close_wardrobe_modal() -> void:
	if is_instance_valid(wardrobe_modal):
		wardrobe_modal.visible = false

