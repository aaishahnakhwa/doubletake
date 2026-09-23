extends CanvasLayer

signal meeting_dismissed
signal vote_cast(target_player_id: String)
signal leave_match_requested
signal return_to_lobby_requested

const BODY_TEXTURES := [
	preload("res://assets/phase4/bodies/orange.png"),
	preload("res://assets/phase4/bodies/blue.png"),
	preload("res://assets/phase4/bodies/green.png"),
	preload("res://assets/phase4/bodies/red.png"),
	preload("res://assets/phase4/bodies/purple.png"),
	preload("res://assets/phase4/bodies/yellow.png")
]

const PORTRAIT_TEXTURES := [
	preload("res://assets/phase5/portraits/orange.png"),
	preload("res://assets/phase5/portraits/blue.png"),
	preload("res://assets/phase5/portraits/green.png"),
	preload("res://assets/phase5/portraits/red.png"),
	preload("res://assets/phase5/portraits/purple.png"),
	preload("res://assets/phase5/portraits/yellow.png")
]

const CARD_FRAME := preload("res://assets/phase5/player_card_frame.png")
const EMERGENCY_BANNER := preload("res://assets/phase5/emergency_banner.png")
const BODY_REPORT_BANNER := preload("res://assets/phase5/body_report_banner.png")
const ELIMINATED_STAMP := preload("res://assets/phase5/eliminated_stamp.png")
const MEETING_BACKDROP := preload("res://assets/phase5/meeting_backdrop.png")
const ChatBoxScript = preload("res://scripts/chat_box.gd")
const CustomizationCatalog = preload("res://scripts/customization_catalog.gd")
const GREYSCALE_SHADER := preload("res://shaders/greyscale.gdshader")

var meeting_data: Dictionary = {}
var local_player_id := ""
var is_host := false
var local_is_ghost := false
var session: Node
var chat_box: Control

var root: Control
var backdrop_rect: TextureRect
var banner_rect: TextureRect
var subtitle_label: Label
var cards_grid: HFlowContainer
var reveal_box: Control
var reveal_cards_row: HBoxContainer

# Footer & Voting Controls
var footer_box: VBoxContainer
var timer_label: Label
var vote_progress_label: Label
var action_row: HBoxContainer
var skip_btn: Button
var skip_confirm_box: HBoxContainer
var skip_result_badge: Label
var dismiss_button: Button

# Outcome / Ejection Overlay
var outcome_overlay: Control
var outcome_panel: PanelContainer
var outcome_portrait: TextureRect
var outcome_title: Label
var outcome_subtitle: Label

# Leave Match Dialog
var leave_btn: Button
var leave_dialog: PanelContainer
var leave_title: Label
var leave_body: Label
var leave_return_lobby_btn: Button
var leave_quit_btn: Button
var leave_cancel_btn: Button

# State
var time_left := 45.0
var discussion_time := 15.0
var voting_time := 45.0
var in_discussion_phase := false
var can_dismiss := true
var in_reveal_phase := false
var reveal_timer := 2.6

var local_voted := false
var local_vote_target := ""
var selected_card_id := ""
var voted_player_ids: Dictionary = {}
var in_results_phase := false
var voting_results: Dictionary = {}
var results_timer := 3.8
var card_entries: Dictionary = {} # player_id -> Dictionary of nodes


func setup(data: Dictionary, current_player_id: String = "", host_mode: bool = false, network_session: Node = null) -> void:
	meeting_data = data
	local_player_id = current_player_id
	is_host = host_mode
	session = network_session
	in_reveal_phase = str(data.get("type", "")) == "body_report"
	discussion_time = float(data.get("discussion_time", 15.0))
	voting_time = float(data.get("voting_time", 45.0))
	time_left = voting_time
	in_discussion_phase = discussion_time > 0.0
	
	local_is_ghost = false
	for p: Dictionary in data.get("players", []):
		if str(p.get("player_id", "")) == local_player_id:
			local_is_ghost = bool(p.get("ghost", false))
			break


func _ready() -> void:
	layer = 70
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	
	_build_backdrop()
	_build_header()
	_build_cards()
	_build_reveal_box()
	_build_footer()
	_build_outcome_overlay()
	_build_chat()
	_build_leave_dialog()
	_refresh_display()
	
	get_viewport().size_changed.connect(_layout)
	_layout()
	call_deferred("_layout")


func _build_chat() -> void:
	chat_box = ChatBoxScript.new()
	root.add_child(chat_box)
	chat_box.setup(session, local_player_id, local_is_ghost)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if is_instance_valid(leave_dialog) and leave_dialog.visible:
			if event.keycode == KEY_ESCAPE:
				leave_dialog.visible = false
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			show_leave_dialog()
			get_viewport().set_input_as_handled()


func receive_chat_message(msg: Dictionary) -> void:
	if is_instance_valid(chat_box):
		chat_box.add_chat_message(msg)


func _process(delta: float) -> void:
	if in_reveal_phase:
		reveal_timer -= delta
		if reveal_timer <= 0.0:
			_end_reveal()
		return
	
	if in_results_phase:
		results_timer -= delta
		if results_timer <= 0.0 and can_dismiss:
			_on_dismiss()
		return

	if in_discussion_phase:
		discussion_time -= delta
		if is_instance_valid(timer_label):
			timer_label.text = "⏳ DISCUSSION: %ds" % maxi(0, int(ceilf(discussion_time)))
		if discussion_time <= 0.0:
			in_discussion_phase = false
			time_left = voting_time
			_update_voting_controls_state()
		return
	
	if time_left > 0.0:
		time_left -= delta
		if is_instance_valid(timer_label):
			timer_label.text = "VOTING TIME: %ds" % maxi(0, int(ceilf(time_left)))
		if time_left <= 0.0:
			# Auto-conclude locally if no server results arrived
			_local_tally_and_show()


func _build_backdrop() -> void:
	var dark_dim := ColorRect.new()
	dark_dim.color = Color("#060e14", 0.90)
	dark_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dark_dim)
	
	backdrop_rect = TextureRect.new()
	backdrop_rect.texture = MEETING_BACKDROP
	backdrop_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop_rect.modulate = Color(1.0, 1.0, 1.0, 0.40)
	backdrop_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop_rect)


func _build_header() -> void:
	banner_rect = TextureRect.new()
	banner_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(banner_rect)
	
	subtitle_label = Label.new()
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 20)
	subtitle_label.add_theme_color_override("font_color", Color("#fffbe7"))
	subtitle_label.add_theme_color_override("font_outline_color", Color("#102b2b"))
	subtitle_label.add_theme_constant_override("outline_size", 4)
	root.add_child(subtitle_label)

	leave_btn = Button.new()
	leave_btn.text = "✕ LEAVE"
	leave_btn.custom_minimum_size = Vector2(74, 32)
	leave_btn.add_theme_font_size_override("font_size", 13)
	var lb_style := StyleBoxFlat.new()
	lb_style.bg_color = Color("#3a1418")
	lb_style.border_color = Color("#e63946")
	lb_style.set_border_width_all(2)
	lb_style.set_corner_radius_all(6)
	lb_style.content_margin_left = 8
	lb_style.content_margin_right = 8
	lb_style.content_margin_top = 4
	lb_style.content_margin_bottom = 4
	leave_btn.add_theme_stylebox_override("normal", lb_style)
	var lb_hover := lb_style.duplicate() as StyleBoxFlat
	lb_hover.bg_color = Color("#541a20")
	leave_btn.add_theme_stylebox_override("hover", lb_hover)
	leave_btn.add_theme_color_override("font_color", Color("#ffccd2"))
	leave_btn.pressed.connect(show_leave_dialog)
	root.add_child(leave_btn)


func _build_leave_dialog() -> void:
	leave_dialog = PanelContainer.new()
	leave_dialog.name = "LeaveMeetingConfirmDialog"
	leave_dialog.custom_minimum_size = Vector2(460, 220)

	var dlg_style := StyleBoxFlat.new()
	dlg_style.bg_color = Color("#1c140e")
	dlg_style.border_color = Color("#e63946")
	dlg_style.set_border_width_all(3)
	dlg_style.set_corner_radius_all(12)
	dlg_style.shadow_color = Color(0, 0, 0, 0.7)
	dlg_style.shadow_size = 18
	dlg_style.content_margin_left = 24
	dlg_style.content_margin_right = 24
	dlg_style.content_margin_top = 20
	dlg_style.content_margin_bottom = 20
	leave_dialog.add_theme_stylebox_override("panel", dlg_style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	leave_dialog.add_child(column)

	leave_title = Label.new()
	leave_title.text = "✕ LEAVE MATCH?"
	leave_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leave_title.add_theme_font_size_override("font_size", 22)
	leave_title.add_theme_color_override("font_color", Color("#e63946"))
	column.add_child(leave_title)

	leave_body = Label.new()
	leave_body.text = "Are you sure you want to leave the match?"
	leave_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leave_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	leave_body.add_theme_font_size_override("font_size", 14)
	leave_body.add_theme_color_override("font_color", Color("#e0d4c8"))
	column.add_child(leave_body)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	column.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	column.add_child(btn_row)

	leave_return_lobby_btn = Button.new()
	leave_return_lobby_btn.text = "🏕 RETURN TO LOBBY"
	leave_return_lobby_btn.custom_minimum_size = Vector2(170, 42)
	leave_return_lobby_btn.add_theme_font_size_override("font_size", 14)
	var rl_style := StyleBoxFlat.new()
	rl_style.bg_color = Color("#8b5e3c")
	rl_style.border_color = Color("#f4a261")
	rl_style.set_border_width_all(2)
	rl_style.set_corner_radius_all(8)
	leave_return_lobby_btn.add_theme_stylebox_override("normal", rl_style)
	leave_return_lobby_btn.add_theme_color_override("font_color", Color("#fffbe7"))
	leave_return_lobby_btn.pressed.connect(func() -> void:
		leave_dialog.visible = false
		return_to_lobby_requested.emit()
	)
	btn_row.add_child(leave_return_lobby_btn)

	leave_quit_btn = Button.new()
	leave_quit_btn.text = "✕ LEAVE MATCH"
	leave_quit_btn.custom_minimum_size = Vector2(150, 42)
	leave_quit_btn.add_theme_font_size_override("font_size", 14)
	var q_style := StyleBoxFlat.new()
	q_style.bg_color = Color("#4a1a1c")
	q_style.border_color = Color("#e63946")
	q_style.set_border_width_all(2)
	q_style.set_corner_radius_all(8)
	leave_quit_btn.add_theme_stylebox_override("normal", q_style)
	leave_quit_btn.add_theme_color_override("font_color", Color("#ffffff"))
	leave_quit_btn.pressed.connect(func() -> void:
		leave_dialog.visible = false
		leave_match_requested.emit()
	)
	btn_row.add_child(leave_quit_btn)

	leave_cancel_btn = Button.new()
	leave_cancel_btn.text = "RESUME"
	leave_cancel_btn.custom_minimum_size = Vector2(110, 42)
	leave_cancel_btn.add_theme_font_size_override("font_size", 14)
	var c_style := StyleBoxFlat.new()
	c_style.bg_color = Color("#2d6a4f")
	c_style.border_color = Color("#52b788")
	c_style.set_border_width_all(2)
	c_style.set_corner_radius_all(8)
	leave_cancel_btn.add_theme_stylebox_override("normal", c_style)
	leave_cancel_btn.add_theme_color_override("font_color", Color("#ffffff"))
	leave_cancel_btn.pressed.connect(func() -> void:
		leave_dialog.visible = false
	)
	btn_row.add_child(leave_cancel_btn)

	root.add_child(leave_dialog)
	leave_dialog.visible = false


func show_leave_dialog() -> void:
	if not is_instance_valid(leave_dialog):
		return
	if is_host:
		leave_body.text = "You are the host. You can return all campers to the lobby, or leave the match."
		leave_return_lobby_btn.visible = true
	else:
		leave_body.text = "Are you sure you want to leave the match and return to the main menu?"
		leave_return_lobby_btn.visible = false
	leave_dialog.visible = true
	_layout()


func _build_cards() -> void:
	cards_grid = HFlowContainer.new()
	cards_grid.alignment = FlowContainer.ALIGNMENT_CENTER
	cards_grid.add_theme_constant_override("h_separation", 16)
	cards_grid.add_theme_constant_override("v_separation", 16)
	root.add_child(cards_grid)


func _build_reveal_box() -> void:
	reveal_box = Control.new()
	root.add_child(reveal_box)
	reveal_cards_row = HBoxContainer.new()
	reveal_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	reveal_cards_row.add_theme_constant_override("separation", 24)
	reveal_box.add_child(reveal_cards_row)


func _build_footer() -> void:
	footer_box = VBoxContainer.new()
	footer_box.alignment = BoxContainer.ALIGNMENT_CENTER
	footer_box.add_theme_constant_override("separation", 6)
	root.add_child(footer_box)
	
	# Top line: Timer and Vote Progress
	var top_line := HBoxContainer.new()
	top_line.alignment = BoxContainer.ALIGNMENT_CENTER
	top_line.add_theme_constant_override("separation", 28)
	footer_box.add_child(top_line)
	
	timer_label = Label.new()
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 16)
	timer_label.add_theme_color_override("font_color", Color("#ffd166"))
	if in_discussion_phase:
		timer_label.text = "⏳ DISCUSSION: %ds" % maxi(0, int(ceilf(discussion_time)))
	else:
		timer_label.text = "VOTING TIME: %ds" % maxi(0, int(ceilf(time_left)))
	top_line.add_child(timer_label)
	
	vote_progress_label = Label.new()
	vote_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vote_progress_label.add_theme_font_size_override("font_size", 15)
	vote_progress_label.add_theme_color_override("font_color", Color("#a7c957"))
	vote_progress_label.text = "VOTING: 0 VOTED"
	top_line.add_child(vote_progress_label)
	
	# Action row: Skip button & Dismiss button
	action_row = HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 16)
	footer_box.add_child(action_row)
	
	# Skip vote button
	skip_btn = Button.new()
	skip_btn.text = "⏭ SKIP VOTE"
	skip_btn.custom_minimum_size = Vector2(145, 38)
	skip_btn.add_theme_font_size_override("font_size", 15)
	var skip_style := StyleBoxFlat.new()
	skip_style.bg_color = Color("#3d3024")
	skip_style.border_color = Color("#d4a373")
	skip_style.set_border_width_all(2)
	skip_style.set_corner_radius_all(8)
	var skip_hover := skip_style.duplicate() as StyleBoxFlat
	skip_hover.bg_color = Color("#554332")
	skip_btn.add_theme_stylebox_override("normal", skip_style)
	skip_btn.add_theme_stylebox_override("hover", skip_hover)
	skip_btn.add_theme_stylebox_override("pressed", skip_style)
	skip_btn.add_theme_color_override("font_color", Color("#fffbe7"))
	skip_btn.disabled = in_discussion_phase
	skip_btn.pressed.connect(_on_skip_clicked)
	action_row.add_child(skip_btn)
	
	# Skip confirmation sub-row
	skip_confirm_box = HBoxContainer.new()
	skip_confirm_box.visible = false
	skip_confirm_box.add_theme_constant_override("separation", 6)
	action_row.add_child(skip_confirm_box)
	
	var skip_yes := Button.new()
	skip_yes.text = "✓ SKIP"
	skip_yes.add_theme_font_size_override("font_size", 14)
	var sy_style := StyleBoxFlat.new()
	sy_style.bg_color = Color("#c85a17")
	sy_style.border_color = Color("#ffd166")
	sy_style.set_border_width_all(2)
	sy_style.set_corner_radius_all(6)
	skip_yes.add_theme_stylebox_override("normal", sy_style)
	skip_yes.add_theme_color_override("font_color", Color("#fffbe7"))
	skip_yes.pressed.connect(_on_skip_confirmed)
	skip_confirm_box.add_child(skip_yes)
	
	var skip_no := Button.new()
	skip_no.text = "✕"
	skip_no.add_theme_font_size_override("font_size", 14)
	var sn_style := StyleBoxFlat.new()
	sn_style.bg_color = Color("#4a3525")
	sn_style.set_corner_radius_all(6)
	skip_no.add_theme_stylebox_override("normal", sn_style)
	skip_no.add_theme_color_override("font_color", Color("#fffbe7"))
	skip_no.pressed.connect(func() -> void: skip_confirm_box.visible = false)
	skip_confirm_box.add_child(skip_no)
	
	# Skip results badge (shown during results phase)
	skip_result_badge = Label.new()
	skip_result_badge.visible = false
	skip_result_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skip_result_badge.add_theme_font_size_override("font_size", 15)
	skip_result_badge.add_theme_color_override("font_color", Color("#ffd166"))
	action_row.add_child(skip_result_badge)
	
	# Dismiss / Return button (for host / local testing)
	dismiss_button = Button.new()
	dismiss_button.text = "RETURN TO CAMP"
	dismiss_button.custom_minimum_size = Vector2(165, 38)
	dismiss_button.add_theme_font_size_override("font_size", 15)
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color("#8b5e3c")
	normal_style.border_color = Color("#f4d7a7")
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(8)
	dismiss_button.add_theme_stylebox_override("normal", normal_style)
	dismiss_button.add_theme_color_override("font_color", Color("#fffbe7"))
	dismiss_button.pressed.connect(_on_dismiss)
	action_row.add_child(dismiss_button)


func _build_outcome_overlay() -> void:
	outcome_overlay = Control.new()
	outcome_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outcome_overlay.visible = false
	root.add_child(outcome_overlay)
	
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.70)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outcome_overlay.add_child(dim)
	
	outcome_panel = PanelContainer.new()
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color("#18100a")
	p_style.border_color = Color("#e63946")
	p_style.set_border_width_all(3)
	p_style.set_corner_radius_all(14)
	p_style.content_margin_left = 32
	p_style.content_margin_right = 32
	p_style.content_margin_top = 24
	p_style.content_margin_bottom = 24
	outcome_panel.add_theme_stylebox_override("panel", p_style)
	outcome_overlay.add_child(outcome_panel)
	
	var o_col := VBoxContainer.new()
	o_col.alignment = BoxContainer.ALIGNMENT_CENTER
	o_col.add_theme_constant_override("separation", 12)
	outcome_panel.add_child(o_col)
	
	outcome_portrait = TextureRect.new()
	outcome_portrait.custom_minimum_size = Vector2(96, 96)
	outcome_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	outcome_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	outcome_portrait.visible = false
	o_col.add_child(outcome_portrait)
	
	outcome_title = Label.new()
	outcome_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_title.add_theme_font_size_override("font_size", 24)
	outcome_title.add_theme_color_override("font_color", Color("#ffd166"))
	o_col.add_child(outcome_title)
	
	outcome_subtitle = Label.new()
	outcome_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_subtitle.add_theme_font_size_override("font_size", 17)
	outcome_subtitle.add_theme_color_override("font_color", Color("#fffbe7"))
	o_col.add_child(outcome_subtitle)


func _refresh_display() -> void:
	var mtype: String = str(meeting_data.get("type", "emergency"))
	var caller_name: String = str(meeting_data.get("caller_name", "Camper"))
	var victim_name: String = str(meeting_data.get("victim_name", ""))
	
	if mtype == "body_report":
		banner_rect.texture = BODY_REPORT_BANNER
		subtitle_label.text = "%s reported the dead body of %s!" % [caller_name, victim_name]
	else:
		banner_rect.texture = EMERGENCY_BANNER
		subtitle_label.text = "%s rang the Camp Bell for an Emergency Meeting!" % caller_name
	
	for child in cards_grid.get_children():
		child.queue_free()
	for child in reveal_cards_row.get_children():
		child.queue_free()
	card_entries.clear()
	
	var players_list: Array = meeting_data.get("players", [])
	var caller_id: String = str(meeting_data.get("caller_id", ""))
	var victim_id: String = str(meeting_data.get("victim_id", ""))
	
	for pdata: Dictionary in players_list:
		var card := _create_player_card(pdata, caller_id)
		cards_grid.add_child(card)
		
		# If this camper is the victim, add to the reveal row
		var pid: String = str(pdata.get("player_id", ""))
		var is_dead: bool = bool(pdata.get("ghost", false)) or pid == victim_id
		if is_dead:
			var reveal_card := _create_player_card(pdata, caller_id, true)
			reveal_cards_row.add_child(reveal_card)
	
	_update_vote_progress_label()
	
	if in_reveal_phase:
		cards_grid.visible = false
		footer_box.visible = false
		reveal_box.visible = true
	else:
		reveal_box.visible = false
		cards_grid.visible = true
		footer_box.visible = true


func _end_reveal() -> void:
	in_reveal_phase = false
	if is_instance_valid(reveal_box):
		reveal_box.visible = false
	if is_instance_valid(cards_grid):
		cards_grid.visible = true
	if is_instance_valid(footer_box):
		footer_box.visible = true
	_update_voting_controls_state()
	_layout()


func _update_voting_controls_state() -> void:
	var can_vote := not in_discussion_phase and not in_reveal_phase and not in_results_phase and not local_voted and not local_is_ghost
	if is_instance_valid(skip_btn):
		skip_btn.disabled = not can_vote
	for pid: String in card_entries:
		var entry: Dictionary = card_entries[pid]
		if entry.has("vote_action_btn") and is_instance_valid(entry["vote_action_btn"]):
			entry["vote_action_btn"].disabled = not can_vote or bool(entry.get("is_dead", false))


func _create_player_card(pdata: Dictionary, caller_id: String, is_spotlight: bool = false) -> Control:
	var pid: String = str(pdata.get("player_id", ""))
	var pname: String = str(pdata.get("name", "Camper"))
	var color_idx: int = clampi(int(pdata.get("color", 0)), 0, 5)
	var is_dead: bool = bool(pdata.get("ghost", false)) or pid == str(meeting_data.get("victim_id", ""))
	var is_caller: bool = pid == caller_id
	var is_local: bool = pid == local_player_id
	
	var card_w := 150.0
	var card_h := 200.0
	if is_spotlight:
		card_w = 210.0
		card_h = 280.0
	
	var card := Control.new()
	card.custom_minimum_size = Vector2(card_w, card_h)
	card.size = Vector2(card_w, card_h)
	
	# Background frame
	var frame := TextureRect.new()
	frame.texture = CARD_FRAME
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(frame)
	
	# Selection border (highlight when clicked to vote)
	var sel_border := Panel.new()
	sel_border.visible = false
	sel_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb_style := StyleBoxFlat.new()
	sb_style.bg_color = Color(1.0, 0.82, 0.4, 0.18)
	sb_style.border_color = Color("#ffd166")
	sb_style.set_border_width_all(3)
	sb_style.set_corner_radius_all(10)
	sel_border.add_theme_stylebox_override("panel", sb_style)
	card.add_child(sel_border)
	
	# Paper region inside CARD_FRAME (clip is at y 0..0.24, paper is 0.24..0.92)
	var paper_x := card_w * 0.18
	var paper_y := card_h * 0.24
	var paper_w := card_w * 0.64
	var paper_h := card_h * 0.68
	
	# Avatar container
	var avatar_box := Control.new()
	avatar_box.position = Vector2(paper_x, paper_y)
	avatar_box.size = Vector2(paper_w, paper_h * 0.56)
	card.add_child(avatar_box)
	
	var look_id := str(pdata.get("look", pdata.get("hat", "classic")))
	var char_rect := TextureRect.new()
	char_rect.texture = CustomizationCatalog.get_skin_portrait(look_id, color_idx)
	char_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	char_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	char_rect.position = Vector2.ZERO
	char_rect.size = avatar_box.size
	
	if is_dead:
		var mat := ShaderMaterial.new()
		mat.shader = GREYSCALE_SHADER
		char_rect.material = mat
	avatar_box.add_child(char_rect)

	if is_dead:
		# Chotu sa (small) eliminated stamp on the top-left corner, slanted
		var stamp := TextureRect.new()
		stamp.texture = ELIMINATED_STAMP
		stamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stamp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var stamp_w := paper_w * 0.48
		var stamp_h := stamp_w * (672.0 / 918.0)
		stamp.size = Vector2(stamp_w, stamp_h)
		stamp.pivot_offset = stamp.size * 0.5
		stamp.rotation = deg_to_rad(-6.0)
		stamp.position = Vector2(paper_x - paper_w * 0.04, paper_y + paper_h * 0.01)
		card.add_child(stamp)
	
	# Status tag (CALLER / YOU / DEAD / ALIVE)
	var tag_label := Label.new()
	tag_label.position = Vector2(paper_x, paper_y + paper_h * 0.58)
	tag_label.size = Vector2(paper_w, paper_h * 0.16)
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag_label.add_theme_font_size_override("font_size", int(paper_h * 0.12))
	
	if is_dead:
		tag_label.text = "ELIMINATED"
		tag_label.add_theme_color_override("font_color", Color("#c1121f"))
	elif is_caller:
		tag_label.text = "REPORTER" if str(meeting_data.get("type", "")) == "body_report" else "CALLER"
		tag_label.add_theme_color_override("font_color", Color("#b07d12"))
	elif is_local:
		tag_label.text = "YOU"
		tag_label.add_theme_color_override("font_color", Color("#2d6a4f"))
	else:
		tag_label.text = "ALIVE"
		tag_label.add_theme_color_override("font_color", Color("#1b4965"))
	card.add_child(tag_label)
	
	# Name label on the card
	var name_label := Label.new()
	name_label.position = Vector2(paper_x, paper_y + paper_h * 0.74)
	name_label.size = Vector2(paper_w, paper_h * 0.22)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.text = pname
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", int(paper_h * 0.15))
	name_label.add_theme_color_override("font_color", Color("#26170d") if not is_dead else Color("#6b141a"))
	card.add_child(name_label)
	
	# Voted badge (shown when this player has cast their vote)
	var voted_badge := Label.new()
	voted_badge.text = "✓ VOTED"
	voted_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	voted_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	voted_badge.position = Vector2(card_w * 0.12, 4)
	voted_badge.size = Vector2(card_w * 0.76, 20)
	voted_badge.add_theme_font_size_override("font_size", 11)
	voted_badge.add_theme_color_override("font_color", Color("#a7c957"))
	voted_badge.visible = voted_player_ids.has(pid)
	card.add_child(voted_badge)
	
	if is_spotlight:
		return card
	
	# Interactive click button over the card (allows clicking profile card directly to select)
	if not is_dead:
		var click_btn := Button.new()
		click_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		click_btn.flat = true
		var empty_style := StyleBoxEmpty.new()
		click_btn.add_theme_stylebox_override("normal", empty_style)
		click_btn.add_theme_stylebox_override("hover", empty_style)
		click_btn.add_theme_stylebox_override("pressed", empty_style)
		click_btn.pressed.connect(func() -> void: _on_card_clicked(pid))
		card.add_child(click_btn)
		card.move_child(click_btn, 0)
	
	# Container wrapping the profile card on top and voting button directly below
	var item_container := VBoxContainer.new()
	var btn_h := 34.0
	item_container.custom_minimum_size = Vector2(card_w, card_h + btn_h + 6.0)
	item_container.size = Vector2(card_w, card_h + btn_h + 6.0)
	item_container.add_theme_constant_override("separation", 6)
	item_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	item_container.add_child(card)
	
	# Voting Bar directly below the profile card
	var vote_bar := Control.new()
	vote_bar.custom_minimum_size = Vector2(card_w, btn_h)
	vote_bar.size = Vector2(card_w, btn_h)
	item_container.add_child(vote_bar)
	
	# 1. Main Vote Button
	var vote_action_btn := Button.new()
	vote_action_btn.text = "🗳️ VOTE"
	vote_action_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vote_action_btn.add_theme_font_size_override("font_size", 13)
	var va_style := StyleBoxFlat.new()
	va_style.bg_color = Color("#3d2f23")
	va_style.border_color = Color("#d4a373")
	va_style.set_border_width_all(2)
	va_style.set_corner_radius_all(6)
	var va_hover := va_style.duplicate() as StyleBoxFlat
	va_hover.bg_color = Color("#554131")
	va_hover.border_color = Color("#ffd166")
	var va_disabled := va_style.duplicate() as StyleBoxFlat
	va_disabled.bg_color = Color("#221b15")
	va_disabled.border_color = Color("#443528")
	vote_action_btn.add_theme_stylebox_override("normal", va_style)
	vote_action_btn.add_theme_stylebox_override("hover", va_hover)
	vote_action_btn.add_theme_stylebox_override("disabled", va_disabled)
	vote_action_btn.add_theme_color_override("font_color", Color("#fffbe7"))
	vote_action_btn.add_theme_color_override("font_disabled_color", Color("#776a5e"))
	vote_action_btn.pressed.connect(func() -> void: _on_card_clicked(pid))
	vote_bar.add_child(vote_action_btn)
	
	var eliminated_btn: Button = null
	if is_dead:
		vote_action_btn.visible = false
		eliminated_btn = Button.new()
		eliminated_btn.text = "✕ ELIMINATED"
		eliminated_btn.disabled = true
		eliminated_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		eliminated_btn.add_theme_font_size_override("font_size", 12)
		var el_style := StyleBoxFlat.new()
		el_style.bg_color = Color("#1d1410")
		el_style.border_color = Color("#592424")
		el_style.set_border_width_all(1)
		el_style.set_corner_radius_all(6)
		eliminated_btn.add_theme_stylebox_override("disabled", el_style)
		eliminated_btn.add_theme_color_override("font_disabled_color", Color("#9e4b4b"))
		vote_bar.add_child(eliminated_btn)
	elif local_voted or local_is_ghost or in_discussion_phase:
		vote_action_btn.disabled = true
	
	# 2. Voting Confirmation Sub-row (appears below card when selected)
	var vote_confirm_row := HBoxContainer.new()
	vote_confirm_row.visible = false
	vote_confirm_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vote_confirm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vote_confirm_row.add_theme_constant_override("separation", 4)
	vote_bar.add_child(vote_confirm_row)
	
	var vote_btn := Button.new()
	vote_btn.text = "✓ VOTE"
	vote_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vote_btn.add_theme_font_size_override("font_size", 12)
	var vb_style := StyleBoxFlat.new()
	vb_style.bg_color = Color("#2d6a4f")
	vb_style.border_color = Color("#74c69d")
	vb_style.set_border_width_all(2)
	vb_style.set_corner_radius_all(6)
	vote_btn.add_theme_stylebox_override("normal", vb_style)
	vote_btn.add_theme_color_override("font_color", Color("#fffbe7"))
	vote_btn.pressed.connect(func() -> void: _confirm_vote(pid))
	vote_confirm_row.add_child(vote_btn)
	
	var cancel_btn := Button.new()
	cancel_btn.text = "✕"
	cancel_btn.custom_minimum_size = Vector2(32, 0)
	cancel_btn.add_theme_font_size_override("font_size", 12)
	var cb_style := StyleBoxFlat.new()
	cb_style.bg_color = Color("#4a3525")
	cb_style.border_color = Color("#8c533e")
	cb_style.set_border_width_all(2)
	cb_style.set_corner_radius_all(6)
	cancel_btn.add_theme_stylebox_override("normal", cb_style)
	cancel_btn.add_theme_color_override("font_color", Color("#fffbe7"))
	cancel_btn.pressed.connect(func() -> void: _deselect_card())
	vote_confirm_row.add_child(cancel_btn)
	
	# 3. Results row: shows vote count & voter icons during results phase
	var results_row := HBoxContainer.new()
	results_row.visible = false
	results_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results_row.alignment = BoxContainer.ALIGNMENT_CENTER
	results_row.add_theme_constant_override("separation", 4)
	vote_bar.add_child(results_row)
	
	var results_badge := Label.new()
	results_badge.name = "ResultsBadge"
	results_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	results_badge.add_theme_font_size_override("font_size", 13)
	results_badge.add_theme_color_override("font_color", Color("#ffd166"))
	results_row.add_child(results_badge)
	
	card_entries[pid] = {
		"card": card,
		"item_container": item_container,
		"vote_bar": vote_bar,
		"sel_border": sel_border,
		"vote_action_btn": vote_action_btn,
		"vote_confirm_row": vote_confirm_row,
		"voted_badge": voted_badge,
		"results_row": results_row,
		"results_badge": results_badge,
		"name_label": name_label,
		"tag_label": tag_label,
		"eliminated_btn": eliminated_btn,
		"is_dead": is_dead,
		"color": color_idx
	}
	
	return item_container


func _on_card_clicked(pid: String) -> void:
	if in_discussion_phase or local_voted or local_is_ghost or in_reveal_phase or in_results_phase:
		return
	if not card_entries.has(pid) or bool(card_entries[pid].get("is_dead", false)):
		return
	_select_card(pid)


func _select_card(pid: String) -> void:
	if selected_card_id == pid:
		_deselect_card()
		return
	_deselect_card()
	selected_card_id = pid
	if card_entries.has(pid):
		card_entries[pid]["sel_border"].visible = true
		if card_entries[pid].has("vote_action_btn") and is_instance_valid(card_entries[pid]["vote_action_btn"]):
			card_entries[pid]["vote_action_btn"].visible = false
		card_entries[pid]["vote_confirm_row"].visible = true
	if is_instance_valid(skip_confirm_box):
		skip_confirm_box.visible = false


func _deselect_card() -> void:
	if not selected_card_id.is_empty() and card_entries.has(selected_card_id):
		card_entries[selected_card_id]["sel_border"].visible = false
		card_entries[selected_card_id]["vote_confirm_row"].visible = false
		if card_entries[selected_card_id].has("vote_action_btn") and is_instance_valid(card_entries[selected_card_id]["vote_action_btn"]):
			card_entries[selected_card_id]["vote_action_btn"].visible = not bool(card_entries[selected_card_id].get("is_dead", false)) and not in_results_phase
	selected_card_id = ""


func _confirm_vote(pid: String) -> void:
	if local_voted or local_is_ghost:
		return
	local_voted = true
	local_vote_target = pid
	_deselect_card()
	
	for cid in card_entries:
		if card_entries[cid].has("vote_action_btn") and is_instance_valid(card_entries[cid]["vote_action_btn"]):
			card_entries[cid]["vote_action_btn"].disabled = true
	
	if card_entries.has(local_player_id):
		card_entries[local_player_id]["tag_label"].text = "VOTED"
	if is_instance_valid(skip_btn):
		skip_btn.disabled = true
	if is_instance_valid(skip_confirm_box):
		skip_confirm_box.visible = false
		
	set_player_voted(local_player_id)
	vote_cast.emit(pid)


func _on_skip_clicked() -> void:
	if in_discussion_phase or local_voted or local_is_ghost or in_reveal_phase or in_results_phase:
		return
	_deselect_card()
	skip_confirm_box.visible = not skip_confirm_box.visible


func _on_skip_confirmed() -> void:
	if local_voted or local_is_ghost:
		return
	local_voted = true
	local_vote_target = "skip"
	_deselect_card()
	
	for cid in card_entries:
		if card_entries[cid].has("vote_action_btn") and is_instance_valid(card_entries[cid]["vote_action_btn"]):
			card_entries[cid]["vote_action_btn"].disabled = true
	
	skip_confirm_box.visible = false
	skip_btn.text = "✓ SKIPPED"
	skip_btn.disabled = true
	
	if card_entries.has(local_player_id):
		card_entries[local_player_id]["tag_label"].text = "SKIPPED"
		
	set_player_voted(local_player_id)
	vote_cast.emit("skip")


func set_player_voted(voter_id: String) -> void:
	voted_player_ids[voter_id] = true
	if card_entries.has(voter_id):
		card_entries[voter_id]["voted_badge"].visible = true
	_update_vote_progress_label()


func _update_vote_progress_label() -> void:
	if not is_instance_valid(vote_progress_label):
		return
	var living_count := 0
	for p: Dictionary in meeting_data.get("players", []):
		if not bool(p.get("ghost", false)):
			living_count += 1
	var voted_count := voted_player_ids.size()
	vote_progress_label.text = "VOTING: %d / %d VOTED" % [voted_count, living_count]


func show_voting_results(results: Dictionary) -> void:
	in_results_phase = true
	voting_results = results
	time_left = 0.0
	_deselect_card()
	
	if is_instance_valid(skip_confirm_box):
		skip_confirm_box.visible = false
	if is_instance_valid(skip_btn):
		skip_btn.visible = false
	
	var votes_dict: Dictionary = results.get("votes", {})
	var tally: Dictionary = results.get("tally", {})
	
	# Reveal votes on each camper's card
	for pid: String in card_entries:
		var entry: Dictionary = card_entries[pid]
		var count: int = int(tally.get(pid, 0))
		entry["vote_confirm_row"].visible = false
		entry["sel_border"].visible = false
		entry["name_label"].visible = true
		if entry.has("vote_action_btn") and is_instance_valid(entry["vote_action_btn"]):
			entry["vote_action_btn"].visible = false
		if entry.has("eliminated_btn") and is_instance_valid(entry["eliminated_btn"]):
			entry["eliminated_btn"].visible = false
		
		var r_row: HBoxContainer = entry["results_row"]
		var r_badge: Label = entry["results_badge"]
		r_row.visible = true
		r_badge.text = "%d %s" % [count, "VOTE" if count == 1 else "VOTES"]
		
		# Add voter portrait tokens
		for vid: String in votes_dict:
			if str(votes_dict[vid]) == pid:
				var v_color: int = 0
				for p: Dictionary in meeting_data.get("players", []):
					if str(p.get("player_id", "")) == vid:
						v_color = int(p.get("color", 0))
				var token := TextureRect.new()
				token.texture = PORTRAIT_TEXTURES[clampi(v_color, 0, 5)]
				token.custom_minimum_size = Vector2(20, 20)
				token.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				token.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				r_row.add_child(token)
	
	# Reveal skip votes
	var skip_count: int = int(tally.get("skip", 0))
	if is_instance_valid(skip_result_badge):
		skip_result_badge.text = "SKIPPED: %d %s" % [skip_count, "VOTE" if skip_count == 1 else "VOTES"]
		skip_result_badge.visible = true
	
	# Show dramatic outcome overlay
	_show_outcome_overlay(results)
	results_timer = 3.8


func _show_outcome_overlay(results: Dictionary) -> void:
	if not is_instance_valid(outcome_overlay):
		return
	outcome_overlay.visible = true
	
	var o_type: String = str(results.get("outcome_type", "none"))
	var ename: String = str(results.get("ejected_name", "Camper"))
	var erole: String = str(results.get("ejected_role", "Camper"))
	var eid: String = str(results.get("ejected_id", ""))
	
	if o_type == "ejected":
		var e_color := 0
		for p: Dictionary in meeting_data.get("players", []):
			if str(p.get("player_id", "")) == eid:
				e_color = int(p.get("color", 0))
		outcome_portrait.texture = PORTRAIT_TEXTURES[clampi(e_color, 0, 5)]
		outcome_portrait.visible = true
		outcome_title.text = "%s was ejected." % ename
		outcome_title.add_theme_color_override("font_color", Color("#e63946"))
		outcome_subtitle.text = "%s was %s %s." % [ename, "a" if erole == "Camper" else "the", erole]
	elif o_type == "skip":
		outcome_portrait.visible = false
		outcome_title.text = "No one was ejected."
		outcome_title.add_theme_color_override("font_color", Color("#ffd166"))
		outcome_subtitle.text = "(Skipped by popular vote)"
	elif o_type == "tie":
		outcome_portrait.visible = false
		outcome_title.text = "No one was ejected."
		outcome_title.add_theme_color_override("font_color", Color("#ffd166"))
		outcome_subtitle.text = "(Tie vote)"
	else:
		outcome_portrait.visible = false
		outcome_title.text = "No one was ejected."
		outcome_title.add_theme_color_override("font_color", Color("#ffd166"))
		outcome_subtitle.text = "(No votes cast)"


func _local_tally_and_show() -> void:
	if in_results_phase:
		return
	var tally: Dictionary = {}
	var votes_dict: Dictionary = {}
	if local_voted and not local_vote_target.is_empty():
		votes_dict[local_player_id] = local_vote_target
		tally[local_vote_target] = 1
	var outcome_type := "none"
	var ejected_id := ""
	var ejected_name := ""
	var ejected_role := ""
	if not tally.is_empty():
		var max_c := 0
		var top_candidates: Array[String] = []
		for tid in tally:
			var c: int = tally[tid]
			if c > max_c:
				max_c = c
				top_candidates = [tid]
			elif c == max_c:
				top_candidates.append(tid)
		if top_candidates.size() > 1:
			outcome_type = "tie"
		elif top_candidates[0] == "skip":
			outcome_type = "skip"
		else:
			outcome_type = "ejected"
			ejected_id = top_candidates[0]
			for p: Dictionary in meeting_data.get("players", []):
				if str(p.get("player_id", "")) == ejected_id:
					ejected_name = str(p.get("name", "Camper"))
					ejected_role = str(p.get("role", "Camper"))
	show_voting_results({
		"votes": votes_dict,
		"tally": tally,
		"outcome_type": outcome_type,
		"ejected_id": ejected_id,
		"ejected_name": ejected_name,
		"ejected_role": ejected_role
	})


func _on_dismiss() -> void:
	if not can_dismiss:
		return
	can_dismiss = false
	meeting_dismissed.emit()
	queue_free()


func _layout() -> void:
	if not is_instance_valid(root):
		return
	var vp_size := get_viewport().get_visible_rect().size
	var scale_factor := clampf(vp_size.y / 720.0, 0.65, 1.3)
	
	# Banner
	var banner_max_w := minf(vp_size.x * 0.70, 420.0 * scale_factor)
	var banner_w := banner_max_w
	var banner_h := banner_w * (768.0 / 1376.0)
	banner_rect.size = Vector2(banner_w, banner_h)
	banner_rect.position = Vector2((vp_size.x - banner_w) * 0.5, 10.0 * scale_factor)
	
	# Subtitle
	var sub_font_size := int(clampf(18.0 * scale_factor, 13.0, 22.0))
	subtitle_label.position = Vector2(16, banner_rect.position.y + banner_h + 4.0 * scale_factor)
	subtitle_label.size = Vector2(vp_size.x - 32, 28.0 * scale_factor)
	subtitle_label.add_theme_font_size_override("font_size", sub_font_size)
	
	var content_top := subtitle_label.position.y + subtitle_label.size.y + 12.0 * scale_factor
	
	# Spotlight reveal box for dead body report
	if is_instance_valid(reveal_box) and reveal_box.visible:
		var avail_h := vp_size.y - content_top - 20.0 * scale_factor
		var card_h := minf(avail_h * 0.86, 280.0 * scale_factor)
		var card_w := card_h * (896.0 / 1200.0)
		reveal_box.position = Vector2((vp_size.x - card_w) * 0.5, content_top + (avail_h - card_h) * 0.5)
		reveal_box.size = Vector2(card_w, card_h)
		if is_instance_valid(reveal_cards_row):
			reveal_cards_row.position = Vector2.ZERO
			reveal_cards_row.size = Vector2(card_w, card_h)
			for child: Control in reveal_cards_row.get_children():
				child.custom_minimum_size = Vector2(card_w, card_h)
				child.size = Vector2(card_w, card_h)
	
	# Normal cards grid
	var footer_h := 88.0 * scale_factor
	var cards_h := vp_size.y - content_top - footer_h
	cards_grid.position = Vector2(32, content_top)
	cards_grid.size = Vector2(vp_size.x - 64, maxf(100.0, cards_h))
	
	# Footer box
	footer_box.position = Vector2(24, vp_size.y - footer_h - 6.0 * scale_factor)
	footer_box.size = Vector2(vp_size.x - 48, footer_h)
	
	# Center outcome panel
	if is_instance_valid(outcome_panel):
		var op_w := minf(vp_size.x * 0.86, 420.0 * scale_factor)
		var op_h := minf(vp_size.y * 0.55, 240.0 * scale_factor)
		outcome_panel.size = Vector2(op_w, op_h)
		outcome_panel.position = Vector2((vp_size.x - op_w) * 0.5, (vp_size.y - op_h) * 0.5)

	# Chat Box
	if is_instance_valid(chat_box):
		var btn_w := 96.0 * scale_factor
		var btn_h := 36.0 * scale_factor
		chat_box.toggle_button.size = Vector2(btn_w, btn_h)
		chat_box.toggle_button.position = Vector2(vp_size.x - btn_w - 16.0 * scale_factor, 12.0 * scale_factor)
		var panel_w := clampf(vp_size.x * 0.38, 290.0, 380.0)
		var panel_h := clampf(vp_size.y * 0.72, 320.0, 520.0)
		chat_box.chat_panel.size = Vector2(panel_w, panel_h)
		chat_box.chat_panel.position = Vector2(vp_size.x - panel_w - 16.0 * scale_factor, chat_box.toggle_button.position.y + btn_h + 8.0)

	# Leave Button (Top Left)
	if is_instance_valid(leave_btn):
		var lb_w := 84.0 * scale_factor
		var lb_h := 36.0 * scale_factor
		leave_btn.size = Vector2(lb_w, lb_h)
		leave_btn.position = Vector2(16.0 * scale_factor, 12.0 * scale_factor)

	# Leave Dialog
	if is_instance_valid(leave_dialog) and leave_dialog.visible:
		var ld_w := minf(vp_size.x * 0.9, 460.0 * scale_factor)
		var ld_h := minf(vp_size.y * 0.45, 230.0 * scale_factor)
		leave_dialog.size = Vector2(ld_w, ld_h)
		leave_dialog.position = Vector2((vp_size.x - ld_w) * 0.5, (vp_size.y - ld_h) * 0.5)


