extends CanvasLayer

signal play_again_pressed
signal return_to_lobby_pressed
signal leave_room_pressed
signal rematch_ready_toggled(ready: bool)

const PORTRAIT_TEXTURES := [
	preload("res://assets/phase5/portraits/orange.png"),
	preload("res://assets/phase5/portraits/blue.png"),
	preload("res://assets/phase5/portraits/green.png"),
	preload("res://assets/phase5/portraits/red.png"),
	preload("res://assets/phase5/portraits/purple.png"),
	preload("res://assets/phase5/portraits/yellow.png")
]

const MEETING_BACKDROP := preload("res://assets/phase5/meeting_backdrop.png")
const ELIMINATED_STAMP := preload("res://assets/phase5/eliminated_stamp.png")
const GREYSCALE_SHADER := preload("res://shaders/greyscale.gdshader")
const CustomizationCatalog = preload("res://scripts/customization_catalog.gd")

const COLOR_VALUES: Array[Color] = [
	Color("#f4a261"), # 0: Orange
	Color("#4e95d9"), # 1: Blue
	Color("#52b788"), # 2: Green
	Color("#e63946"), # 3: Red
	Color("#a366e0"), # 4: Purple
	Color("#f4d03f")  # 5: Yellow
]

var outcome_data: Dictionary = {}
var local_player_id := ""
var is_host := false
var is_rematch_ready := false

var root: Control
var backdrop_tex: TextureRect
var color_overlay: ColorRect
var main_vbox: VBoxContainer
var title_label: Label
var subtitle_label: Label
var reason_badge: PanelContainer
var showcase_container: Control
var button_row: HBoxContainer
var play_again_btn: Button
var return_lobby_btn: Button
var leave_btn: Button
var rematch_ready_btn: Button
var host_waiting_label: Label


func setup(outcome: Dictionary, p_local_player_id: String, p_is_host: bool) -> void:
	outcome_data = outcome.duplicate(true)
	local_player_id = p_local_player_id
	is_host = p_is_host


func _ready() -> void:
	layer = 70
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_animate_entrance()


func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var winner := str(outcome_data.get("winner", "Campers"))
	var local_role := "Camper"
	for p: Dictionary in outcome_data.get("players", []):
		if str(p.get("player_id", "")) == local_player_id:
			local_role = str(p.get("role", "Camper"))
			break

	var is_camper_win := winner == "Campers"
	var is_victory := (local_role == "Killer" and not is_camper_win) or (local_role != "Killer" and is_camper_win)

	# Atmospheric Backdrop with Meeting Forest
	backdrop_tex = TextureRect.new()
	backdrop_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop_tex.texture = MEETING_BACKDROP
	backdrop_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	root.add_child(backdrop_tex)

	# Dynamic Color Vignette Overlay
	color_overlay = ColorRect.new()
	color_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if is_camper_win:
		color_overlay.color = Color(0.03, 0.08, 0.06, 0.88) # Deep emerald forest
	else:
		color_overlay.color = Color(0.14, 0.02, 0.04, 0.90) # Dark crimson dread
	color_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(color_overlay)

	# Main Vertical Layout
	main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 14)
	root.add_child(main_vbox)

	# Top Spacer
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 10)
	main_vbox.add_child(top_spacer)

	# Header Section
	_build_header(is_victory, is_camper_win, winner)

	# Center Stage Section
	if is_camper_win:
		_build_camper_win_stage()
	else:
		_build_killer_win_stage()

	# Mid Spacer
	var mid_spacer := Control.new()
	mid_spacer.custom_minimum_size = Vector2(0, 6)
	main_vbox.add_child(mid_spacer)

	# Action Buttons Row
	_build_action_buttons()


func _build_header(is_victory: bool, is_camper_win: bool, winner: String) -> void:
	var header_box := VBoxContainer.new()
	header_box.alignment = BoxContainer.ALIGNMENT_CENTER
	header_box.add_theme_constant_override("separation", 6)
	main_vbox.add_child(header_box)

	title_label = Label.new()
	title_label.text = "VICTORY" if is_victory else "DEFEAT"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 46)

	var title_color := Color("#ffd166") if is_victory else Color("#e63946")
	var outline_color := Color("#10221c") if is_victory else Color("#260408")
	title_label.add_theme_color_override("font_color", title_color)
	title_label.add_theme_color_override("font_outline_color", outline_color)
	title_label.add_theme_constant_override("outline_size", 10)
	header_box.add_child(title_label)

	subtitle_label = Label.new()
	if is_camper_win:
		subtitle_label.text = "CAMPERS SURVIVED THE NIGHT"
		subtitle_label.add_theme_color_override("font_color", Color("#a7c957"))
	else:
		subtitle_label.text = "THE KILLER PREVAILED — CAMPERS ELIMINATED"
		subtitle_label.add_theme_color_override("font_color", Color("#ffb4be"))
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 19)
	subtitle_label.add_theme_color_override("font_outline_color", Color("#0a0e12"))
	subtitle_label.add_theme_constant_override("outline_size", 6)
	header_box.add_child(subtitle_label)

	# Reason Badge Pill
	var reason := str(outcome_data.get("reason", ""))
	if reason.is_empty():
		reason = "%s WON THE MATCH" % winner.to_upper()
	else:
		reason = "✓ " + reason if is_camper_win else "☠ " + reason

	reason_badge = PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	if is_camper_win:
		badge_style.bg_color = Color(0.06, 0.18, 0.12, 0.85)
		badge_style.border_color = Color("#2a9d8f")
	else:
		badge_style.bg_color = Color(0.20, 0.04, 0.06, 0.85)
		badge_style.border_color = Color("#e63946")
	badge_style.set_border_width_all(1)
	badge_style.set_corner_radius_all(14)
	badge_style.content_margin_left = 18
	badge_style.content_margin_right = 18
	badge_style.content_margin_top = 5
	badge_style.content_margin_bottom = 5
	reason_badge.add_theme_stylebox_override("panel", badge_style)

	var badge_label := Label.new()
	badge_label.text = reason
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_label.add_theme_font_size_override("font_size", 13)
	badge_label.add_theme_color_override("font_color", Color("#e6faf0") if is_camper_win else Color("#ffccd2"))
	reason_badge.add_child(badge_label)

	var badge_wrap := HBoxContainer.new()
	badge_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	badge_wrap.add_child(reason_badge)
	header_box.add_child(badge_wrap)


func _build_camper_win_stage() -> void:
	showcase_container = VBoxContainer.new()
	showcase_container.alignment = BoxContainer.ALIGNMENT_CENTER
	showcase_container.add_theme_constant_override("separation", 12)
	main_vbox.add_child(showcase_container)

	# Survivors Card Panel
	var survivors_panel := PanelContainer.new()
	var s_style := StyleBoxFlat.new()
	s_style.bg_color = Color(0.05, 0.11, 0.09, 0.90)
	s_style.border_color = Color("#2a9d8f")
	s_style.set_border_width_all(2)
	s_style.set_corner_radius_all(16)
	s_style.content_margin_left = 24
	s_style.content_margin_right = 24
	s_style.content_margin_top = 14
	s_style.content_margin_bottom = 14
	survivors_panel.add_theme_stylebox_override("panel", s_style)
	showcase_container.add_child(survivors_panel)

	var s_vbox := VBoxContainer.new()
	s_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	s_vbox.add_theme_constant_override("separation", 10)
	survivors_panel.add_child(s_vbox)

	var s_title := Label.new()
	s_title.text = "SURVIVING CAMPERS"
	s_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s_title.add_theme_font_size_override("font_size", 17)
	s_title.add_theme_color_override("font_color", Color("#ffe6a0"))
	s_vbox.add_child(s_title)

	# Campers Row
	var campers_row := HBoxContainer.new()
	campers_row.alignment = BoxContainer.ALIGNMENT_CENTER
	campers_row.add_theme_constant_override("separation", 16)
	s_vbox.add_child(campers_row)

	for p: Dictionary in outcome_data.get("players", []):
		if str(p.get("role", "")) == "Killer":
			continue
		var p_color := clampi(int(p.get("color", 0)), 0, 5)
		var p_name := str(p.get("name", "Camper"))
		var is_ghost := bool(p.get("ghost", false))
		var look_id := str(p.get("look", p.get("hat", "classic")))
		var card := _create_player_card(p_name, p_color, is_ghost, "Camper", look_id)
		campers_row.add_child(card)

	# Caught Killer Reveal Strip
	var killer_name := str(outcome_data.get("killer_name", "Unknown"))
	var killer_color := clampi(int(outcome_data.get("killer_color", 0)), 0, 5)

	var k_wrap := HBoxContainer.new()
	k_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	showcase_container.add_child(k_wrap)

	var k_panel := PanelContainer.new()
	var kp_style := StyleBoxFlat.new()
	kp_style.bg_color = Color(0.14, 0.05, 0.06, 0.90)
	kp_style.border_color = Color("#e63946")
	kp_style.set_border_width_all(2)
	kp_style.set_corner_radius_all(10)
	kp_style.content_margin_left = 16
	kp_style.content_margin_right = 18
	kp_style.content_margin_top = 6
	kp_style.content_margin_bottom = 6
	k_panel.add_theme_stylebox_override("panel", kp_style)
	k_wrap.add_child(k_panel)

	var k_hbox := HBoxContainer.new()
	k_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	k_hbox.add_theme_constant_override("separation", 12)
	k_panel.add_child(k_hbox)

	var k_img := TextureRect.new()
	k_img.custom_minimum_size = Vector2(44, 44)
	k_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	k_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	k_img.texture = PORTRAIT_TEXTURES[killer_color]
	k_hbox.add_child(k_img)

	var k_text_box := VBoxContainer.new()
	k_text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	k_text_box.add_theme_constant_override("separation", 2)
	k_hbox.add_child(k_text_box)

	var k_title_lbl := Label.new()
	k_title_lbl.text = "THE KILLER WAS: %s" % killer_name
	k_title_lbl.add_theme_font_size_override("font_size", 14)
	k_title_lbl.add_theme_color_override("font_color", Color("#ffb4be"))
	k_text_box.add_child(k_title_lbl)

	var k_role_lbl := Label.new()
	k_role_lbl.text = "Role: Impostor / Killer • Defeated"
	k_role_lbl.add_theme_font_size_override("font_size", 11)
	k_role_lbl.add_theme_color_override("font_color", Color("#e63946"))
	k_text_box.add_child(k_role_lbl)


func _build_killer_win_stage() -> void:
	showcase_container = HBoxContainer.new()
	showcase_container.alignment = BoxContainer.ALIGNMENT_CENTER
	showcase_container.add_theme_constant_override("separation", 24)
	main_vbox.add_child(showcase_container)

	var killer_name := str(outcome_data.get("killer_name", "Unknown"))
	var killer_color := clampi(int(outcome_data.get("killer_color", 0)), 0, 5)

	# Left Column: The Killer Spotlight Card
	var killer_card_panel := PanelContainer.new()
	killer_card_panel.custom_minimum_size = Vector2(240, 240)
	var kc_style := StyleBoxFlat.new()
	kc_style.bg_color = Color(0.18, 0.04, 0.06, 0.95)
	kc_style.border_color = Color("#e63946")
	kc_style.set_border_width_all(3)
	kc_style.set_corner_radius_all(16)
	kc_style.content_margin_left = 18
	kc_style.content_margin_right = 18
	kc_style.content_margin_top = 12
	kc_style.content_margin_bottom = 12
	killer_card_panel.add_theme_stylebox_override("panel", kc_style)
	showcase_container.add_child(killer_card_panel)

	var kc_vbox := VBoxContainer.new()
	kc_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	kc_vbox.add_theme_constant_override("separation", 6)
	killer_card_panel.add_child(kc_vbox)

	var kc_header := Label.new()
	kc_header.text = "THE KILLER"
	kc_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kc_header.add_theme_font_size_override("font_size", 16)
	kc_header.add_theme_color_override("font_color", Color("#ff646e"))
	kc_vbox.add_child(kc_header)

	var kp_img := TextureRect.new()
	kp_img.custom_minimum_size = Vector2(95, 95)
	kp_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	kp_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	kp_img.texture = PORTRAIT_TEXTURES[killer_color]
	kc_vbox.add_child(kp_img)

	var kn_lbl := Label.new()
	kn_lbl.text = killer_name
	kn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kn_lbl.add_theme_font_size_override("font_size", 16)
	kn_lbl.add_theme_color_override("font_color", Color("#ffffff"))
	kc_vbox.add_child(kn_lbl)

	var k_pill := PanelContainer.new()
	var kp_pill_style := StyleBoxFlat.new()
	kp_pill_style.bg_color = Color("#b4141e")
	kp_pill_style.set_corner_radius_all(6)
	kp_pill_style.content_margin_left = 12
	kp_pill_style.content_margin_right = 12
	kp_pill_style.content_margin_top = 3
	kp_pill_style.content_margin_bottom = 3
	k_pill.add_theme_stylebox_override("panel", kp_pill_style)

	var kp_pill_lbl := Label.new()
	kp_pill_lbl.text = "🔪 KILLER"
	kp_pill_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kp_pill_lbl.add_theme_font_size_override("font_size", 12)
	kp_pill_lbl.add_theme_color_override("font_color", Color("#ffffff"))
	k_pill.add_child(kp_pill_lbl)

	var kp_pill_wrap := HBoxContainer.new()
	kp_pill_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	kp_pill_wrap.add_child(k_pill)
	kc_vbox.add_child(kp_pill_wrap)

	# Right Column: Fallen Campers Panel
	var fallen_panel := PanelContainer.new()
	var f_style := StyleBoxFlat.new()
	f_style.bg_color = Color(0.08, 0.06, 0.07, 0.90)
	f_style.border_color = Color("#642832")
	f_style.set_border_width_all(2)
	f_style.set_corner_radius_all(16)
	f_style.content_margin_left = 20
	f_style.content_margin_right = 20
	f_style.content_margin_top = 12
	f_style.content_margin_bottom = 12
	fallen_panel.add_theme_stylebox_override("panel", f_style)
	showcase_container.add_child(fallen_panel)

	var f_vbox := VBoxContainer.new()
	f_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	f_vbox.add_theme_constant_override("separation", 10)
	fallen_panel.add_child(f_vbox)

	var f_title := Label.new()
	f_title.text = "FALLEN CAMPERS"
	f_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	f_title.add_theme_font_size_override("font_size", 16)
	f_title.add_theme_color_override("font_color", Color("#c8b4be"))
	f_vbox.add_child(f_title)

	var fallen_row := HBoxContainer.new()
	fallen_row.alignment = BoxContainer.ALIGNMENT_CENTER
	fallen_row.add_theme_constant_override("separation", 14)
	f_vbox.add_child(fallen_row)

	for p: Dictionary in outcome_data.get("players", []):
		if str(p.get("role", "")) == "Killer":
			continue
		var p_color := clampi(int(p.get("color", 0)), 0, 5)
		var p_name := str(p.get("name", "Camper"))
		var look_id := str(p.get("look", p.get("hat", "classic")))
		var card := _create_player_card(p_name, p_color, true, "Camper", look_id)
		fallen_row.add_child(card)


func _create_player_card(p_name: String, color_idx: int, is_ghost: bool, role: String, look_id: String = "classic", _outfit_id: String = "") -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(115, 175)

	var style := StyleBoxFlat.new()
	if not is_ghost:
		style.bg_color = Color(0.07, 0.16, 0.12, 0.94)
		style.border_color = Color("#52b788")
		style.set_border_width_all(2)
	else:
		style.bg_color = Color(0.08, 0.09, 0.11, 0.94)
		style.border_color = Color("#506469")
		style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 5)
	card.add_child(vbox)

	# Avatar container
	var portrait_wrap := Control.new()
	portrait_wrap.custom_minimum_size = Vector2(72, 72)
	vbox.add_child(portrait_wrap)

	var p_img := TextureRect.new()
	p_img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	p_img.texture = CustomizationCatalog.get_skin_portrait(look_id, color_idx)

	if is_ghost:
		var mat := ShaderMaterial.new()
		mat.shader = GREYSCALE_SHADER
		p_img.material = mat
	portrait_wrap.add_child(p_img)

	if is_ghost:
		# Top-Left slanted eliminated stamp (leaving face completely clear!)
		var stamp := TextureRect.new()
		stamp.texture = ELIMINATED_STAMP
		stamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stamp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var stamp_w := 42.0
		var stamp_h := stamp_w * (672.0 / 918.0)
		stamp.size = Vector2(stamp_w, stamp_h)
		stamp.pivot_offset = stamp.size * 0.5
		stamp.rotation = deg_to_rad(-6.0)
		stamp.position = Vector2(0, 0)
		portrait_wrap.add_child(stamp)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = p_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.clip_text = true
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color("#ffffff") if not is_ghost else Color("#c8d0d4"))
	vbox.add_child(name_lbl)

	# Status Pill
	var status_pill := PanelContainer.new()
	var pill_style := StyleBoxFlat.new()
	if not is_ghost:
		pill_style.bg_color = Color(0.18, 0.42, 0.31, 0.90)
	else:
		pill_style.bg_color = Color(0.28, 0.10, 0.12, 0.90)
	pill_style.set_corner_radius_all(6)
	pill_style.content_margin_left = 6
	pill_style.content_margin_right = 6
	pill_style.content_margin_top = 2
	pill_style.content_margin_bottom = 2
	status_pill.add_theme_stylebox_override("panel", pill_style)

	var status_lbl := Label.new()
	status_lbl.text = "★ SURVIVED" if not is_ghost else "☠ ELIMINATED"
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 10)
	status_lbl.add_theme_color_override("font_color", Color("#d8f3dc") if not is_ghost else Color("#ffb4be"))
	status_pill.add_child(status_lbl)

	var pill_wrap := HBoxContainer.new()
	pill_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	pill_wrap.add_child(status_pill)
	vbox.add_child(pill_wrap)

	# Role label
	var role_lbl := Label.new()
	role_lbl.text = role
	role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_lbl.add_theme_font_size_override("font_size", 10)
	role_lbl.add_theme_color_override("font_color", Color("#a7c957") if not is_ghost else Color("#8d99ae"))
	vbox.add_child(role_lbl)

	return card


func _build_action_buttons() -> void:
	button_row = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 16)
	main_vbox.add_child(button_row)

	if is_host:
		play_again_btn = _create_styled_button("↻ PLAY AGAIN", Color("#2a9d8f"), Color("#52b788"))
		play_again_btn.pressed.connect(func() -> void: play_again_pressed.emit())
		button_row.add_child(play_again_btn)

		return_lobby_btn = _create_styled_button("🏕 RETURN TO LOBBY", Color("#8b5e3c"), Color("#f4a261"))
		return_lobby_btn.pressed.connect(func() -> void: return_to_lobby_pressed.emit())
		button_row.add_child(return_lobby_btn)
	else:
		rematch_ready_btn = _create_styled_button("✓ READY FOR REMATCH", Color("#2a9d8f"), Color("#52b788"))
		rematch_ready_btn.pressed.connect(_on_rematch_ready_pressed)
		button_row.add_child(rematch_ready_btn)

		host_waiting_label = Label.new()
		host_waiting_label.text = "Waiting for host to restart or return to lobby..."
		host_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		host_waiting_label.add_theme_font_size_override("font_size", 14)
		host_waiting_label.add_theme_color_override("font_color", Color("#ffd166"))
		main_vbox.add_child(host_waiting_label)

	leave_btn = _create_styled_button("✕ LEAVE ROOM", Color("#4a1a1c"), Color("#e63946"))
	leave_btn.pressed.connect(func() -> void: leave_room_pressed.emit())
	button_row.add_child(leave_btn)


func _create_styled_button(btn_text: String, bg_col: Color, border_col: Color) -> Button:
	var btn := Button.new()
	btn.text = btn_text
	btn.custom_minimum_size = Vector2(175, 46)
	btn.add_theme_font_size_override("font_size", 15)

	var style := StyleBoxFlat.new()
	style.bg_color = bg_col
	style.border_color = border_col
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", style)

	var hover_style := style.duplicate() as StyleBoxFlat
	hover_style.bg_color = bg_col.lightened(0.12)
	hover_style.border_color = border_col.lightened(0.2)
	btn.add_theme_stylebox_override("hover", hover_style)

	var press_style := style.duplicate() as StyleBoxFlat
	press_style.bg_color = bg_col.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", press_style)

	btn.add_theme_color_override("font_color", Color("#ffffff"))
	return btn


func _on_rematch_ready_pressed() -> void:
	is_rematch_ready = not is_rematch_ready
	if is_rematch_ready:
		rematch_ready_btn.text = "✓ READY! (WAITING)"
		var style: StyleBoxFlat = rematch_ready_btn.get_theme_stylebox("normal")
		if style:
			style.bg_color = Color("#1e6b5c")
	else:
		rematch_ready_btn.text = "✓ READY FOR REMATCH"
		var style: StyleBoxFlat = rematch_ready_btn.get_theme_stylebox("normal")
		if style:
			style.bg_color = Color("#2a9d8f")
	rematch_ready_toggled.emit(is_rematch_ready)


func _animate_entrance() -> void:
	root.modulate.a = 0.0
	title_label.scale = Vector2(0.7, 0.7)
	title_label.pivot_offset = title_label.size * 0.5

	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(root, "modulate:a", 1.0, 0.35)
	tween.tween_property(title_label, "scale", Vector2.ONE, 0.45)


func _layout() -> void:
	if not is_instance_valid(root):
		return
	var vp_size := get_viewport().get_visible_rect().size
	var scale_factor := clampf(vp_size.y / 720.0, 0.75, 1.25)
	if is_instance_valid(title_label):
		title_label.add_theme_font_size_override("font_size", int(46.0 * scale_factor))
	if is_instance_valid(subtitle_label):
		subtitle_label.add_theme_font_size_override("font_size", int(19.0 * scale_factor))
