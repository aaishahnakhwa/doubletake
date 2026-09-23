extends CanvasLayer

signal inspect_requested
signal player_count_delta(delta: int)
signal touch_direction_changed(direction: Vector2)
signal kill_requested
signal sabotage_requested(sabotage_id: String)
signal repair_requested(sabotage_id: String)
signal body_report_requested
signal emergency_meeting_requested
signal leave_match_requested
signal return_to_lobby_requested

const MiniMapScript = preload("res://scripts/camp_minimap.gd")
const JoystickScript = preload("res://scripts/touch_joystick.gd")
const TASK_ZONES := {
	"firewood": "Forest Trail",
	"generator": "Workshop",
	"dinner": "Dining Hall",
	"cabins": "Cabins",
	"tools": "Workshop",
	"supplies": "Storage",
	"lanterns": "Lodge",
	"lake": "Boathouse",
	"dock": "Lake & Dock",
	"radio": "Gate Office"
}

# Keep the Android controls visible when testing with a mouse on a laptop.
var mobile_mode := true
var is_host := false
var zone_names: Array[String] = []
var expanded := false
var visited: Dictionary = {}
var current_zone := "Campfire Square"
var player_count := 4
var nearby_station: Dictionary = {}
var toast_seconds := 0.0
var player_screen_position := Vector2(-10000, -10000)
var task_mode := false
var task_card_collapsed := false
var task_assignments: Array = []
var shared_completed := 0
var shared_total := 0
var phase4_state: Dictionary = {}
var nearby_body := false
var nearby_emergency_button := false
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
var task_toggle_btn: Button
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
var leave_button: Button
var blackout_overlay: ColorRect
var confirm_dialog: PanelContainer
var confirm_title: Label
var confirm_body: Label
var confirm_yes_btn: Button
var confirm_no_btn: Button
var confirm_bell_anim: AnimatedSprite2D
var confirm_btn_row: HBoxContainer
var leave_dialog: PanelContainer
var leave_title: Label
var leave_body: Label
var leave_return_lobby_btn: Button
var leave_quit_btn: Button
var leave_cancel_btn: Button


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
	_build_confirm_dialog()
	_build_leave_dialog()
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
		if is_instance_valid(confirm_dialog) and confirm_dialog.visible:
			if event.keycode == KEY_ESCAPE:
				_on_cancel_meeting()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				_on_confirm_meeting()
				get_viewport().set_input_as_handled()
				return
		if is_instance_valid(leave_dialog) and leave_dialog.visible:
			if event.keycode == KEY_ESCAPE:
				leave_dialog.visible = false
				get_viewport().set_input_as_handled()
				return
		elif event.keycode == KEY_ESCAPE:
			show_leave_dialog()
			get_viewport().set_input_as_handled()
			return
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

	leave_button = Button.new()
	leave_button.text = "✕ LEAVE"
	leave_button.custom_minimum_size = Vector2(74, 32)
	leave_button.add_theme_font_size_override("font_size", 13)
	var lb_style := StyleBoxFlat.new()
	lb_style.bg_color = Color("#3a1418")
	lb_style.border_color = Color("#e63946")
	lb_style.set_border_width_all(2)
	lb_style.set_corner_radius_all(6)
	lb_style.content_margin_left = 8
	lb_style.content_margin_right = 8
	lb_style.content_margin_top = 4
	lb_style.content_margin_bottom = 4
	leave_button.add_theme_stylebox_override("normal", lb_style)
	var lb_hover := lb_style.duplicate() as StyleBoxFlat
	lb_hover.bg_color = Color("#541a20")
	leave_button.add_theme_stylebox_override("hover", lb_hover)
	leave_button.add_theme_color_override("font_color", Color("#ffccd2"))
	leave_button.pressed.connect(show_leave_dialog)
	row.add_child(leave_button)


func _build_zones() -> void:
	zone_card = _panel(Color("#102b2b", 0.94), Color("#8b5e3c"))
	root.add_child(zone_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	zone_card.add_child(column)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	column.add_child(title_row)

	section_title = _label("SCOUT THE CAMP", 18, Color("#f4d7a7"))
	section_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(section_title)

	task_toggle_btn = Button.new()
	task_toggle_btn.text = "−"
	task_toggle_btn.custom_minimum_size = Vector2(28, 28)
	task_toggle_btn.add_theme_font_size_override("font_size", 16)
	var tb_style := StyleBoxFlat.new()
	tb_style.bg_color = Color("#183d37")
	tb_style.border_color = Color("#52b788")
	tb_style.set_border_width_all(1)
	tb_style.set_corner_radius_all(4)
	task_toggle_btn.add_theme_stylebox_override("normal", tb_style)
	task_toggle_btn.add_theme_color_override("font_color", Color("#fffbe7"))
	task_toggle_btn.pressed.connect(_toggle_task_card_collapsed)
	task_toggle_btn.visible = false
	title_row.add_child(task_toggle_btn)
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


func _build_confirm_dialog() -> void:
	# Camp Signboard Style Panel
	confirm_dialog = PanelContainer.new()
	confirm_dialog.name = "CampBellConfirmDialog"
	confirm_dialog.custom_minimum_size = Vector2(480, 420)
	
	var board_style := StyleBoxFlat.new()
	board_style.bg_color = Color("#1c140e")
	board_style.border_color = Color("#d4a373")
	board_style.set_border_width_all(4)
	board_style.set_corner_radius_all(14)
	board_style.shadow_color = Color(0, 0, 0, 0.65)
	board_style.shadow_size = 18
	board_style.content_margin_left = 22
	board_style.content_margin_right = 22
	board_style.content_margin_top = 18
	board_style.content_margin_bottom = 18
	confirm_dialog.add_theme_stylebox_override("panel", board_style)
	
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	confirm_dialog.add_child(col)
	
	# Top Plaque Banner
	var plaque := PanelContainer.new()
	var plaque_style := StyleBoxFlat.new()
	plaque_style.bg_color = Color("#3d2817")
	plaque_style.border_color = Color("#f4d7a7")
	plaque_style.set_border_width_all(2)
	plaque_style.set_corner_radius_all(8)
	plaque_style.content_margin_top = 8
	plaque_style.content_margin_bottom = 8
	plaque.add_theme_stylebox_override("panel", plaque_style)
	col.add_child(plaque)
	
	confirm_title = _label("CAMP DINNER BELL", 22, Color("#ffd166"))
	confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plaque.add_child(confirm_title)
	
	# Moving Bell Sprite Display Area
	var bell_holder := Control.new()
	bell_holder.custom_minimum_size = Vector2(430, 190)
	col.add_child(bell_holder)
	
	confirm_bell_anim = AnimatedSprite2D.new()
	confirm_bell_anim.name = "ConfirmBellAnim"
	
	var frames := SpriteFrames.new()
	var f0 := load("res://assets/phase5/moving_bell/frame_0.png") as Texture2D
	var f1 := load("res://assets/phase5/moving_bell/frame_1.png") as Texture2D
	var f2 := load("res://assets/phase5/moving_bell/frame_2.png") as Texture2D
	var f3 := load("res://assets/phase5/moving_bell/frame_3.png") as Texture2D
	var f4 := load("res://assets/phase5/moving_bell/frame_4.png") as Texture2D
	var f5 := load("res://assets/phase5/moving_bell/frame_5.png") as Texture2D
	var f6 := load("res://assets/phase5/moving_bell/frame_6.png") as Texture2D
	var f7 := load("res://assets/phase5/moving_bell/frame_7.png") as Texture2D
	
	frames.add_animation("idle")
	frames.set_animation_loop("idle", false)
	if f0:
		frames.add_frame("idle", f0)
	
	frames.add_animation("ring")
	frames.set_animation_loop("ring", true)
	frames.set_animation_speed("ring", 8.0)
	for f in [f1, f2, f3, f2, f5, f2, f6, f4, f7, f0]:
		if f:
			frames.add_frame("ring", f)
	
	confirm_bell_anim.sprite_frames = frames
	confirm_bell_anim.animation = "idle"
	confirm_bell_anim.frame = 0
	confirm_bell_anim.position = Vector2(215, 95)
	confirm_bell_anim.scale = Vector2(0.48, 0.48)
	bell_holder.add_child(confirm_bell_anim)
	
	# Notice Parchment Box
	var notice_box := PanelContainer.new()
	var notice_style := StyleBoxFlat.new()
	notice_style.bg_color = Color("#2a1f18")
	notice_style.border_color = Color("#5a3d27")
	notice_style.set_border_width_all(2)
	notice_style.set_corner_radius_all(8)
	notice_style.content_margin_left = 14
	notice_style.content_margin_right = 14
	notice_style.content_margin_top = 10
	notice_style.content_margin_bottom = 10
	notice_box.add_theme_stylebox_override("panel", notice_style)
	col.add_child(notice_box)
	
	confirm_body = _label("Ring the camp dinner bell to halt all activities and summon every camper to the campfire for an Emergency Meeting.", 15, Color("#fffbe7"))
	confirm_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_box.add_child(confirm_body)
	
	# Themed Buttons Row
	confirm_btn_row = HBoxContainer.new()
	confirm_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	confirm_btn_row.add_theme_constant_override("separation", 18)
	col.add_child(confirm_btn_row)
	
	confirm_yes_btn = Button.new()
	confirm_yes_btn.text = "🔔 RING THE BELL"
	confirm_yes_btn.custom_minimum_size = Vector2(175, 46)
	confirm_yes_btn.add_theme_font_size_override("font_size", 16)
	var yes_style := StyleBoxFlat.new()
	yes_style.bg_color = Color("#c85a17")
	yes_style.border_color = Color("#ffd166")
	yes_style.set_border_width_all(3)
	yes_style.set_corner_radius_all(10)
	var yes_hover := yes_style.duplicate() as StyleBoxFlat
	yes_hover.bg_color = Color("#e06d20")
	var yes_pressed := yes_style.duplicate() as StyleBoxFlat
	yes_pressed.bg_color = Color("#9e3f08")
	confirm_yes_btn.add_theme_stylebox_override("normal", yes_style)
	confirm_yes_btn.add_theme_stylebox_override("hover", yes_hover)
	confirm_yes_btn.add_theme_stylebox_override("pressed", yes_pressed)
	confirm_yes_btn.add_theme_color_override("font_color", Color("#fffbe7"))
	confirm_yes_btn.pressed.connect(_on_confirm_meeting)
	confirm_btn_row.add_child(confirm_yes_btn)
	
	confirm_no_btn = Button.new()
	confirm_no_btn.text = "✕ CANCEL"
	confirm_no_btn.custom_minimum_size = Vector2(125, 46)
	confirm_no_btn.add_theme_font_size_override("font_size", 16)
	var no_style := StyleBoxFlat.new()
	no_style.bg_color = Color("#4a3525")
	no_style.border_color = Color("#a67c52")
	no_style.set_border_width_all(2)
	no_style.set_corner_radius_all(10)
	var no_hover := no_style.duplicate() as StyleBoxFlat
	no_hover.bg_color = Color("#634732")
	var no_pressed := no_style.duplicate() as StyleBoxFlat
	no_pressed.bg_color = Color("#332419")
	confirm_no_btn.add_theme_stylebox_override("normal", no_style)
	confirm_no_btn.add_theme_stylebox_override("hover", no_hover)
	confirm_no_btn.add_theme_stylebox_override("pressed", no_pressed)
	confirm_no_btn.add_theme_color_override("font_color", Color("#e0d4c8"))
	confirm_no_btn.pressed.connect(_on_cancel_meeting)
	confirm_btn_row.add_child(confirm_no_btn)
	
	root.add_child(confirm_dialog)
	confirm_dialog.visible = false


func show_emergency_confirm_dialog() -> void:
	if is_instance_valid(confirm_dialog):
		confirm_title.text = "CAMP DINNER BELL"
		confirm_body.text = "Ring the camp dinner bell to halt all activities and summon every camper to the campfire for an Emergency Meeting."
		if is_instance_valid(confirm_btn_row):
			confirm_btn_row.visible = true
		if is_instance_valid(confirm_bell_anim):
			confirm_bell_anim.play("idle")
			confirm_bell_anim.frame = 0
		confirm_dialog.visible = true
		_layout()


func _on_confirm_meeting() -> void:
	if is_instance_valid(confirm_bell_anim):
		confirm_title.text = "🔔 THE BELL CHIMES!"
		confirm_body.text = "The camp bell rings loudly across the woods... Calling all campers!"
		if is_instance_valid(confirm_btn_row):
			confirm_btn_row.visible = false
		confirm_bell_anim.play("ring")
		
		# Dramatic ringing sequence before meeting opens
		var tween := create_tween()
		tween.tween_interval(1.3)
		tween.tween_callback(func() -> void:
			if is_instance_valid(confirm_dialog):
				confirm_dialog.visible = false
			emergency_meeting_requested.emit()
		)
	else:
		if is_instance_valid(confirm_dialog):
			confirm_dialog.visible = false
		emergency_meeting_requested.emit()


func _on_cancel_meeting() -> void:
	if is_instance_valid(confirm_dialog):
		confirm_dialog.visible = false


func _build_leave_dialog() -> void:
	leave_dialog = PanelContainer.new()
	leave_dialog.name = "LeaveMatchConfirmDialog"
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


func _toggle_task_card_collapsed() -> void:
	task_card_collapsed = not task_card_collapsed
	if is_instance_valid(task_toggle_btn):
		task_toggle_btn.text = "+" if task_card_collapsed else "−"
	if is_instance_valid(task_list):
		task_list.visible = not task_card_collapsed
	_layout()


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
	header_title.add_theme_font_size_override("font_size", 16 if mobile_mode else 22)
	header.size = Vector2(350, 60) if mobile_mode else Vector2(390, 60)
	header_status.text = "TASKS %d%%" % _task_percent() if task_mode else "AREAS %d/%d" % [visited.size(), zone_names.size()]
	map_card.scale = factor
	map_card.size = Vector2(410, 318) if expanded else Vector2(230, 184)
	map_card.position = Vector2(viewport_size.x - safe.z - 16 * scale_factor - map_card.size.x * scale_factor,
		safe.y + 14 * scale_factor)
	zone_card.scale = factor
	if task_mode:
		zone_card.visible = true
		zone_card.size = Vector2(280, 72 if task_card_collapsed else 210)
	else:
		zone_card.visible = not mobile_mode or expanded
		zone_card.size = Vector2(280, 360)
	zone_card.position = Vector2(safe.x + 16 * scale_factor, safe.y + (76 if mobile_mode else 82) * scale_factor)
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
	if is_instance_valid(confirm_dialog) and confirm_dialog.visible:
		var dlg_w := minf(viewport_size.x * 0.94, 480.0 * scale_factor)
		var dlg_h := minf(viewport_size.y * 0.94, 430.0 * scale_factor)
		confirm_dialog.size = Vector2(dlg_w, dlg_h)
		confirm_dialog.position = (viewport_size - Vector2(dlg_w, dlg_h)) * 0.5
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
	elif nearby_emergency_button:
		prompt_card.visible = true
		prompt_label.text = "Tap RING BELL" if mobile_mode else "E  RING CAMP BELL"
		action_button.text = "RING BELL"
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
			prompt_label.text = ("Tap REPAIR" if mobile_mode else "E  REPAIR") + "  •  " + str(sabotage.get("effect", "Sabotage"))
			action_button.text = "REPAIR"
			action_button.disabled = false
		elif not sabotage.is_empty() and _is_living_killer() and _is_killer_objective(str(sabotage.get("id", ""))):
			prompt_label.text = ("Tap SABOTAGE" if mobile_mode else "E  SABOTAGE") + "  •  " + str(station["name"])
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
	if nearby_emergency_button:
		show_emergency_confirm_dialog()
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
	task_list.visible = not task_card_collapsed
	if is_instance_valid(task_toggle_btn):
		task_toggle_btn.visible = true
	zone_scroll.visible = false
	camper_row.visible = false
	task_progress.value = _task_percent()
	task_progress_label.text = "SHARED TASKS  %d%%  (%d/%d)" % [_task_percent(), shared_completed, shared_total]
	var lines := PackedStringArray()
	for assignment: Dictionary in task_assignments:
		var task_id := str(assignment.get("id", ""))
		var t_name := str(assignment.get("name", "Task"))
		var t_zone: String = TASK_ZONES.get(task_id, "")
		var done := bool(assignment.get("completed", false))
		var prefix := "✓  " if done else "○  "
		var line := prefix + t_name
		if not t_zone.is_empty() and not done:
			line += "  [📍 %s]" % t_zone
		lines.append(line)
	if lines.is_empty():
		lines.append("• Sabotage Camp Stations\n• Eliminate campers without being caught")
	task_list.text = "\n".join(lines)
	var incomplete_ids: Array[String] = []
	for assignment: Dictionary in task_assignments:
		if not bool(assignment.get("completed", false)):
			incomplete_ids.append(str(assignment.get("id", "")))
	minimap.set_task_ids(incomplete_ids)
	header_status.text = "TASKS %d%%" % _task_percent()
	_layout()
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
		if is_instance_valid(task_toggle_btn):
			task_toggle_btn.visible = true
		task_list.visible = not task_card_collapsed
		var lines := PackedStringArray()
		for objective: Dictionary in task_assignments:
			var obj_id := str(objective.get("id", ""))
			var obj_name := str(objective.get("name", "Sabotage"))
			var obj_zone: String = TASK_ZONES.get(obj_id, "")
			var done := bool(objective.get("completed", false))
			var prefix := "✓  " if done else "○  "
			var line := prefix + obj_name
			if not obj_zone.is_empty() and not done:
				line += "  [📍 %s]" % obj_zone
			lines.append(line)
		lines.append("○  Eliminate Campers (K key)")
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
		_layout()
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


func set_nearby_emergency_button(value: bool) -> void:
	if nearby_emergency_button == value:
		return
	nearby_emergency_button = value
	if not value and is_instance_valid(confirm_dialog):
		confirm_dialog.visible = false
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


func show_ringing_bell_cinematic(duration: float = 1.2) -> void:
	var cinematic := Control.new()
	cinematic.name = "RingingBellCinematic"
	cinematic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cinematic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cinematic)
	
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cinematic.add_child(dim)
	
	var center_box := VBoxContainer.new()
	center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center_box.add_theme_constant_override("separation", 16)
	center_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	cinematic.add_child(center_box)
	
	var sprite_holder := Control.new()
	sprite_holder.custom_minimum_size = Vector2(200, 220)
	center_box.add_child(sprite_holder)
	
	var bell_anim := CampBell.new()
	bell_anim.scale = Vector2(0.55, 0.55)
	bell_anim.position = Vector2(100, 110)
	sprite_holder.add_child(bell_anim)
	bell_anim.ring(duration)
	
	var banner := _label("🔔 RINGING CAMP BELL!", 28, Color("#ffd166"))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_box.add_child(banner)
	
	var subtitle := _label("EMERGENCY MEETING CALLED • GATHERING ALL CAMPERS", 16, Color("#fffbe7"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_box.add_child(subtitle)
	
	var tween := create_tween()
	tween.tween_interval(duration)
	tween.tween_property(cinematic, "modulate:a", 0.0, 0.2)
	tween.tween_callback(cinematic.queue_free)
