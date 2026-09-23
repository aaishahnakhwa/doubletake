extends Control

signal message_sent(text: String)
signal chat_toggled(is_open: bool)
signal unread_count_changed(count: int)

const COLOR_NAMES := ["Orange", "Blue", "Green", "Red", "Purple", "Yellow"]
const COLOR_VALUES: Array[Color] = [
	Color("#f4a261"), # 0: Orange
	Color("#4ea8de"), # 1: Blue
	Color("#70e000"), # 2: Green
	Color("#e63946"), # 3: Red
	Color("#b5179e"), # 4: Purple
	Color("#ffd166")  # 5: Yellow
]

var session: Node
var local_player_id := ""
var is_ghost := false
var unread_count := 0
var is_open := false

# UI Nodes
var toggle_button: Button
var chat_panel: PanelContainer
var header_title: Label
var close_button: Button
var scroll_container: ScrollContainer
var messages_box: VBoxContainer
var input_field: LineEdit
var send_button: Button
var unread_badge: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func setup(network_session: Node, current_player_id: String, ghost: bool = false) -> void:
	session = network_session
	local_player_id = current_player_id
	set_ghost_mode(ghost)
	if session != null and session.has_signal("chat_message_received"):
		if not session.chat_message_received.is_connected(add_chat_message):
			session.chat_message_received.connect(add_chat_message)
	if session != null and "chat_history" in session:
		load_history(session.chat_history)


func set_ghost_mode(ghost: bool) -> void:
	is_ghost = ghost
	if is_instance_valid(header_title):
		if is_ghost:
			header_title.text = "👻 GHOST CHAT"
			header_title.add_theme_color_override("font_color", Color("#c77dff"))
		else:
			header_title.text = "CAMP CHAT"
			header_title.add_theme_color_override("font_color", Color("#f4d7a7"))
	if is_instance_valid(input_field):
		if is_ghost:
			input_field.placeholder_text = "Ghost chat (only dead see)..."
		else:
			input_field.placeholder_text = "Type a message..."


func _build_ui() -> void:
	# 1. Toggle Button
	toggle_button = Button.new()
	toggle_button.text = "💬 CHAT"
	toggle_button.custom_minimum_size = Vector2(96, 36)
	toggle_button.focus_mode = Control.FOCUS_NONE
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color("#183a2e", 0.92)
	btn_style.border_color = Color("#a7c957")
	btn_style.set_border_width_all(2)
	btn_style.set_corner_radius_all(6)
	btn_style.set_content_margin_all(6)
	toggle_button.add_theme_stylebox_override("normal", btn_style)
	var btn_hover := btn_style.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color("#244b3c")
	toggle_button.add_theme_stylebox_override("hover", btn_hover)
	var btn_pressed := btn_style.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color("#0f241d")
	toggle_button.add_theme_stylebox_override("pressed", btn_pressed)
	toggle_button.add_theme_color_override("font_color", Color("#fffbe7"))
	toggle_button.add_theme_font_size_override("font_size", 14)
	toggle_button.pressed.connect(toggle_chat)
	add_child(toggle_button)

	# Unread Badge on Toggle Button
	unread_badge = Label.new()
	unread_badge.visible = false
	unread_badge.text = "0"
	unread_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unread_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	unread_badge.custom_minimum_size = Vector2(20, 20)
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color("#e63946")
	badge_style.set_corner_radius_all(10)
	badge_style.set_content_margin_all(2)
	unread_badge.add_theme_stylebox_override("normal", badge_style)
	unread_badge.add_theme_font_size_override("font_size", 11)
	unread_badge.add_theme_color_override("font_color", Color.WHITE)
	toggle_button.add_child(unread_badge)
	unread_badge.position = Vector2(toggle_button.custom_minimum_size.x - 14, -8)

	# 2. Chat Panel
	chat_panel = PanelContainer.new()
	chat_panel.visible = false
	chat_panel.custom_minimum_size = Vector2(320, 420)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#10221c", 0.96)
	panel_style.border_color = Color("#a7c957", 0.85)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(10)
	panel_style.shadow_color = Color(0, 0, 0, 0.6)
	panel_style.shadow_size = 8
	chat_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(chat_panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	chat_panel.add_child(main_vbox)

	# Header: Title + Close Button
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(header)

	header_title = Label.new()
	header_title.text = "CAMP CHAT"
	header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_title.add_theme_font_size_override("font_size", 15)
	header_title.add_theme_color_override("font_color", Color("#f4d7a7"))
	header.add_child(header_title)

	close_button = Button.new()
	close_button.text = "✕"
	close_button.custom_minimum_size = Vector2(28, 28)
	close_button.focus_mode = Control.FOCUS_NONE
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color("#e63946", 0.7)
	close_style.set_corner_radius_all(4)
	close_button.add_theme_stylebox_override("normal", close_style)
	close_button.add_theme_font_size_override("font_size", 13)
	close_button.pressed.connect(func() -> void: set_chat_open(false))
	header.add_child(close_button)

	# Messages Feed
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll_container)

	messages_box = VBoxContainer.new()
	messages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	messages_box.add_theme_constant_override("separation", 6)
	scroll_container.add_child(messages_box)

	# Input Bar: LineEdit + Send Button
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	main_vbox.add_child(input_row)

	input_field = LineEdit.new()
	input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_field.placeholder_text = "Type a message..."
	input_field.max_length = 120
	input_field.custom_minimum_size.y = 36
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color("#183a2e")
	input_style.border_color = Color("#244b3c")
	input_style.set_border_width_all(1)
	input_style.set_corner_radius_all(4)
	input_style.set_content_margin_all(6)
	input_field.add_theme_stylebox_override("normal", input_style)
	input_field.add_theme_color_override("font_color", Color("#fffbe7"))
	input_field.text_submitted.connect(_on_text_submitted)
	input_row.add_child(input_field)

	send_button = Button.new()
	send_button.text = "SEND"
	send_button.custom_minimum_size = Vector2(58, 36)
	send_button.focus_mode = Control.FOCUS_NONE
	var send_style := StyleBoxFlat.new()
	send_style.bg_color = Color("#2a9d8f")
	send_style.set_corner_radius_all(4)
	send_style.set_content_margin_all(4)
	send_button.add_theme_stylebox_override("normal", send_style)
	send_button.add_theme_color_override("font_color", Color.WHITE)
	send_button.add_theme_font_size_override("font_size", 12)
	send_button.pressed.connect(_on_send_pressed)
	input_row.add_child(send_button)


func toggle_chat() -> void:
	set_chat_open(not is_open)


func set_chat_open(open: bool) -> void:
	is_open = open
	if is_instance_valid(chat_panel):
		chat_panel.visible = is_open
	if is_open:
		unread_count = 0
		_update_badge()
		call_deferred("_scroll_to_bottom")
		if is_instance_valid(input_field):
			input_field.grab_focus()
	chat_toggled.emit(is_open)


func add_chat_message(msg: Dictionary) -> void:
	if not is_instance_valid(messages_box):
		return
	
	var sender_name := str(msg.get("sender_name", "Camper"))
	var sender_color := clampi(int(msg.get("sender_color", 0)), 0, 5)
	var text := str(msg.get("text", ""))
	var msg_is_ghost := bool(msg.get("is_ghost", false))

	# Container for this message
	var msg_panel := PanelContainer.new()
	var msg_style := StyleBoxFlat.new()
	if msg_is_ghost:
		msg_style.bg_color = Color("#2b1b3d", 0.75)
		msg_style.border_color = Color("#9d4edd", 0.6)
	else:
		msg_style.bg_color = Color("#183a2e", 0.65)
		msg_style.border_color = Color("#244b3c", 0.5)
	msg_style.set_border_width_all(1)
	msg_style.set_corner_radius_all(6)
	msg_style.set_content_margin_all(6)
	msg_panel.add_theme_stylebox_override("panel", msg_style)

	var v_box := VBoxContainer.new()
	v_box.add_theme_constant_override("separation", 2)
	msg_panel.add_child(v_box)

	# Sender Label
	var sender_label := Label.new()
	var color_val: Color = COLOR_VALUES[sender_color]
	if msg_is_ghost:
		sender_label.text = "👻 [GHOST] " + sender_name
		sender_label.add_theme_color_override("font_color", Color("#c77dff"))
	else:
		sender_label.text = sender_name
		sender_label.add_theme_color_override("font_color", color_val)
	sender_label.add_theme_font_size_override("font_size", 12)
	v_box.add_child(sender_label)

	# Text Label
	var text_label := Label.new()
	text_label.text = text
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_color_override("font_color", Color("#fffbe7"))
	text_label.add_theme_font_size_override("font_size", 13)
	v_box.add_child(text_label)

	messages_box.add_child(msg_panel)

	# Keep message box from growing indefinitely
	if messages_box.get_child_count() > 60:
		var oldest: Node = messages_box.get_child(0)
		oldest.queue_free()

	if not is_open:
		unread_count += 1
		_update_badge()
	else:
		call_deferred("_scroll_to_bottom")


func load_history(history: Array[Dictionary]) -> void:
	clear_messages()
	for msg in history:
		# If we are alive and the message was from a ghost, don't show it!
		if not is_ghost and bool(msg.get("is_ghost", false)):
			continue
		add_chat_message(msg)
	if not is_open:
		unread_count = 0
		_update_badge()


func clear_messages() -> void:
	if not is_instance_valid(messages_box):
		return
	for child: Node in messages_box.get_children():
		child.queue_free()
	unread_count = 0
	_update_badge()


func set_input_enabled(enabled: bool, placeholder: String = "") -> void:
	if is_instance_valid(input_field):
		input_field.editable = enabled
		if not placeholder.is_empty():
			input_field.placeholder_text = placeholder
	if is_instance_valid(send_button):
		send_button.disabled = not enabled


func _on_send_pressed() -> void:
	if not is_instance_valid(input_field):
		return
	var text := input_field.text.strip_edges()
	if text.is_empty():
		return
	input_field.text = ""
	message_sent.emit(text)
	if session != null and session.has_method("send_chat"):
		session.send_chat(text)


func _on_text_submitted(_text: String) -> void:
	_on_send_pressed()


func _scroll_to_bottom() -> void:
	if is_instance_valid(scroll_container):
		var v_bar := scroll_container.get_v_scroll_bar()
		if is_instance_valid(v_bar):
			scroll_container.scroll_vertical = int(v_bar.max_value)


func _update_badge() -> void:
	if not is_instance_valid(unread_badge):
		return
	if unread_count > 0:
		unread_badge.text = str(mini(unread_count, 99))
		unread_badge.visible = true
	else:
		unread_badge.visible = false
	unread_count_changed.emit(unread_count)
