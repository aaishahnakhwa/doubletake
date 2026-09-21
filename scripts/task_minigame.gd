extends CanvasLayer

signal completed(task_id: String)
signal closed

const TaskCatalog = preload("res://scripts/task_catalog.gd")


class DraggableItemButton:
	extends Button
	signal drag_started(data: Dictionary)

	var drag_payload: Dictionary = {}
	var item_name := ""
	var caption_label: Label
	var active_drag_preview: TextureRect

	func set_caption(value: String) -> void:
		item_name = value
		if not is_instance_valid(caption_label):
			caption_label = Label.new()
			caption_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			caption_label.offset_left = 2.0
			caption_label.offset_top = -25.0
			caption_label.offset_right = -2.0
			caption_label.offset_bottom = -3.0
			caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			caption_label.add_theme_font_size_override("font_size", 12)
			caption_label.add_theme_color_override("font_color", Color("#fff3cf"))
			caption_label.add_theme_color_override("font_outline_color", Color("#061514"))
			caption_label.add_theme_constant_override("outline_size", 4)
			add_child(caption_label)
		caption_label.text = value

	func _ready() -> void:
		resized.connect(func() -> void: pivot_offset = size * 0.5)
		mouse_entered.connect(func() -> void:
			if not disabled:
				create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(self, "scale", Vector2(1.06, 1.06), 0.12)
		)
		mouse_exited.connect(func() -> void:
			create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).tween_property(self, "scale", Vector2.ONE, 0.1)
		)
		button_down.connect(func() -> void:
			if not disabled:
				create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(self, "scale", Vector2(0.91, 0.91), 0.07)
		)
		button_up.connect(func() -> void:
			if not disabled:
				create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(self, "scale", Vector2(1.06, 1.06) if get_global_rect().has_point(get_global_mouse_position()) else Vector2.ONE, 0.1)
		)

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if disabled or drag_payload.is_empty() or icon == null:
			return null
		var preview := TextureRect.new()
		preview.texture = icon
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.custom_minimum_size = Vector2(88, 88)
		preview.size = Vector2(88, 88)
		preview.modulate = Color(1.0, 1.0, 1.0, 0.92)
		active_drag_preview = preview
		set_drag_preview(preview)
		drag_started.emit(drag_payload)
		return drag_payload

	func set_drag_texture(texture: Texture2D) -> void:
		icon = texture
		if is_instance_valid(active_drag_preview):
			active_drag_preview.texture = texture


class ItemDropZone:
	extends PanelContainer

	signal item_dropped(data: Dictionary)
	signal item_dragged_over(data: Dictionary, at_position: Vector2)

	var accepted_task_id := ""
	var accepting := true

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		var accepted := accepting and data is Dictionary and str(data.get("task_id", "")) == accepted_task_id
		if accepted:
			item_dragged_over.emit(data, _at_position)
		return accepted

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if _can_drop_data(_at_position, data):
			item_dropped.emit(data)

var task_id := ""
var task: Dictionary = {}
var root: Control
var panel: PanelContainer
var content: VBoxContainer
var status_label: Label
var progress: ProgressBar
var task_icon: TextureRect
var action_buttons: Array[Button] = []
var drop_zone: ItemDropZone
var drop_label: Label
var primary_target_visual: TextureRect
var sequence_target_visual: TextureRect
var dock_plank_visual: TextureRect
var radio_visual: TextureRect
var radio_idle_tween: Tween
var remaining := 0
var next_sequence := 0
var hold_active := false
var hold_value := 0.0
var dial: HSlider
var dial_target := 0.0
var dial_tolerance := 4.0
var dial_lock_elapsed := 0.0
var signal_texture: TextureRect
var dial_knob_texture: TextureRect
var dial_needle_texture: TextureRect
var matching_order: Array[int] = []
var matching_zones: Array[ItemDropZone] = []
var matching_zone_labels: Array[Label] = []
var matching_zone_visuals: Array[TextureRect] = []
var matching_stage := 0
var matching_stage_busy := false
var rhythm_meter: HSlider
var rhythm_value := 0.0
var rhythm_direction := 1.0
var rhythm_hits := 0
var rhythm_ready := true
var rhythm_controls: Array[Control] = []
var lantern_work_panel: VBoxContainer
var lantern_work_instruction: Label
var lantern_fuel_button: DraggableItemButton
var lantern_pump_button: DraggableItemButton
var lantern_work_zone: ItemDropZone
var lantern_work_zone_label: Label
var lantern_work_visual: TextureRect
var lantern_pressure_cells: Array[PanelContainer] = []
var lantern_fueled := false
var fuel_idle_tween: Tween
var ignition_panel: VBoxContainer
var ignition_instruction: Label
var ignition_match: DraggableItemButton
var ignition_matchbox_zone: ItemDropZone
var ignition_lantern_zone: ItemDropZone
var ignition_lantern_visual: TextureRect
var ignition_stage := -1
var match_strike_last := Vector2.ZERO
var match_strike_distance := 0.0
var match_strike_tracking := false
var hammer_active_index := -1
var hammer_time_left := 0.0
var hammer_tool: DraggableItemButton
var hammer_nail_zones: Array[ItemDropZone] = []
var hammer_nail_labels: Array[Label] = []
var hammer_nail_hits: Array[int] = []
var hammer_hits_required := 3
var finished := false
var is_sabotage_task := false
var sabotage_step := 0
var sabotage_visual: TextureRect
var sabotage_buttons: Array[Button] = []


func _ready() -> void:
	layer = 40
	_build_shell()
	_build_task()
	get_viewport().size_changed.connect(_layout)
	_layout()
	call_deferred("_layout")


func setup(value: String, sabotage: bool = false) -> void:
	task_id = value
	is_sabotage_task = sabotage
	task = TaskCatalog.get_sabotage_task(task_id) if sabotage else TaskCatalog.get_task(task_id)


func _process(delta: float) -> void:
	if finished:
		return
	match str(task.get("mode", "")):
		"hold":
			if hold_active:
				hold_value = minf(100.0, hold_value + delta * 34.0)
				progress.value = hold_value
				status_label.text = "Pumping fuel... %d%%" % int(hold_value)
				if hold_value >= 100.0:
					_finish()
		"rhythm":
			_update_rhythm(delta)
		"hammer":
			_update_hammer(delta)
		"dial":
			_update_dial_lock(delta)


func _unhandled_input(event: InputEvent) -> void:
	if finished or task.is_empty():
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
		return
	if task.get("mode", "") == "hold" and event is InputEventKey and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER):
		hold_active = event.pressed
		get_viewport().set_input_as_handled()
		return
	if task.get("mode", "") == "dial":
		if event.is_action_pressed("ui_left"):
			dial.value -= 2.0
			_check_dial()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_right"):
			dial.value += 2.0
			_check_dial()
			get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		var number := int(event.keycode) - int(KEY_1)
		if number >= 0 and number < action_buttons.size():
			action_buttons[number].pressed.emit()
			get_viewport().set_input_as_handled()


func _build_shell() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.30)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(shade)
	panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.018, 0.02, 0.56)
	style.border_color = Color(0.92, 0.96, 0.92, 0.16)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 20
	style.content_margin_bottom = 18
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.48)
	style.shadow_size = 14
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)


func _build_task() -> void:
	if task.is_empty():
		_close()
		return
	var title := _label(str(task["name"]).to_upper(), 25, Color("#f2eee2"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	task_icon = TextureRect.new()
	task_icon.texture = load(str(task.get("icon", "")))
	task_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	task_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	task_icon.custom_minimum_size = Vector2(0, 64 if _uses_item_sprites() else 150)
	task_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(task_icon)
	var instructions := _label(str(task["instruction"]), 15, Color(0.9, 0.91, 0.88, 0.82))
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(instructions)
	status_label = _label("", 16, Color("#b8e663"))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(status_label)
	progress = ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, 30)
	progress.max_value = 100.0
	progress.show_percentage = false
	content.add_child(progress)
	match str(task["mode"]):
		"targets": _build_targets()
		"sequence": _build_sequence()
		"matching": _build_matching()
		"rhythm": _build_rhythm()
		"hammer": _build_hammer()
		"hold": _build_hold()
		"dial": _build_dial()
		"find": _build_find()
		"sabotage": _build_sabotage()
	var cancel := _button("CLOSE   [ESC]", 16)
	cancel.custom_minimum_size.y = 48
	_style_quiet_button(cancel)
	cancel.pressed.connect(_close)
	content.add_child(cancel)


func _build_sabotage() -> void:
	task_icon.visible = false
	progress.visible = true
	progress.value = 0.0
	var steps: Array = task.get("sabotage_steps", [])
	status_label.text = "Tap 1 on the machine: " + str(steps[0])

	var play_area := Control.new()
	play_area.custom_minimum_size = Vector2(0.0, 330.0)
	play_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(play_area)
	sabotage_visual = TextureRect.new()
	sabotage_visual.texture = _sabotage_state_texture(0)
	sabotage_visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sabotage_visual.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sabotage_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sabotage_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sabotage_visual.modulate = Color("#fff2ea")
	play_area.add_child(sabotage_visual)

	var hotspots := _sabotage_hotspots()
	for index in range(steps.size()):
		var button := _button(str(index + 1), 22)
		button.tooltip_text = str(steps[index])
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.disabled = index != 0
		_style_sabotage_button(button)
		var hotspot: Vector2 = hotspots[index]
		button.set_anchor(SIDE_LEFT, hotspot.x)
		button.set_anchor(SIDE_RIGHT, hotspot.x)
		button.set_anchor(SIDE_TOP, hotspot.y)
		button.set_anchor(SIDE_BOTTOM, hotspot.y)
		button.offset_left = -36.0
		button.offset_right = 36.0
		button.offset_top = -36.0
		button.offset_bottom = 36.0
		button.pressed.connect(_sabotage_step_pressed.bind(index))
		play_area.add_child(button)
		sabotage_buttons.append(button)
		action_buttons.append(button)


func _sabotage_step_pressed(index: int) -> void:
	if finished or index != sabotage_step or index < 0 or index >= sabotage_buttons.size():
		if index >= 0 and index < sabotage_buttons.size():
			_wiggle_control(sabotage_buttons[index], Color("#ff6b5f"))
		return
	var button := sabotage_buttons[index]
	button.disabled = true
	button.visible = false
	_pulse_control(sabotage_visual)
	_emit_action_burst(sabotage_visual, "!", Color("#ff4d4d"))
	sabotage_step += 1
	sabotage_visual.texture = _sabotage_state_texture(sabotage_step)
	sabotage_visual.modulate = Color("#ff9a87")
	create_tween().tween_property(sabotage_visual, "modulate", Color.WHITE, 0.20)
	progress.value = 100.0 * float(sabotage_step) / float(maxi(1, sabotage_buttons.size()))
	if sabotage_step < sabotage_buttons.size():
		sabotage_buttons[sabotage_step].disabled = false
		status_label.text = "Tap %d on the machine: %s" % [sabotage_step + 1, str(task.get("sabotage_steps", [])[sabotage_step])]
		return
	status_label.text = "SABOTAGE ARMED"
	await get_tree().create_timer(0.32).timeout
	_finish()


func _style_sabotage_button(button: Button) -> void:
	button.custom_minimum_size = Vector2.ZERO
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#9e2028", 0.92)
	normal.border_color = Color("#ff6464")
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(36)
	normal.shadow_color = Color(0, 0, 0, 0.65)
	normal.shadow_size = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#e34343")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#c33a3a")
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("#261e21", 0.78)
	disabled.border_color = Color("#8d676b")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color("#fff0df"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("#968184"))


func _sabotage_hotspots() -> Array[Vector2]:
	match task_id:
		"lanterns":
			return [Vector2(0.19, 0.68), Vector2(0.50, 0.55), Vector2(0.81, 0.68)]
		"supplies":
			return [Vector2(0.23, 0.57), Vector2(0.50, 0.57), Vector2(0.78, 0.57)]
		_:
			return [Vector2(0.23, 0.58), Vector2(0.50, 0.58), Vector2(0.77, 0.58)]


func _sabotage_state_texture(state_index: int) -> Texture2D:
	var atlas: Texture2D = load(str(task.get("sabotage_states", task.get("sabotage_panel", ""))))
	if atlas == null or not task.has("sabotage_states"):
		return atlas
	var frame := AtlasTexture.new()
	frame.atlas = atlas
	var cell_size := Vector2(float(atlas.get_width()) / 2.0, float(atlas.get_height()) / 2.0)
	var safe_index := clampi(state_index, 0, 3)
	var origin := Vector2(float(safe_index % 2) * cell_size.x, float(floori(float(safe_index) / 2.0)) * cell_size.y)
	frame.region = Rect2(origin + Vector2(6.0, 6.0), cell_size - Vector2(12.0, 12.0))
	frame.filter_clip = true
	return frame


func _build_targets() -> void:
	var items: Array = task["items"]
	var sprites: Array = task.get("item_sprites", [])
	remaining = items.size()
	progress.visible = false
	task_icon.visible = false
	status_label.text = "Pick up each object and throw it into the %s" % ("cleanup net" if task_id == "lake" else "camp pile")
	if not sprites.is_empty():
		var target_sprite := str(task.get("icon", ""))
		var task_assets: Array = task.get("task_assets", [])
		if not task_assets.is_empty():
			target_sprite = str(task_assets[0])
		drop_zone = _bare_image_drop_zone(
			target_sprite,
			"CLEANUP NET" if task_id == "lake" else "CAMPFIRE PILE",
			_target_dropped,
			138,
			Vector2(220, 142)
		)
		content.add_child(drop_zone)
		var target_stack := drop_zone.get_child(0) as VBoxContainer
		primary_target_visual = target_stack.get_child(0) as TextureRect
		drop_label = target_stack.get_child(1) as Label
		call_deferred("_start_primary_target_idle")
	var grid := _grid(3)
	for index in range(items.size()):
		var item = items[index]
		var button: Button
		if index < sprites.size():
			button = _item_button(str(item), str(sprites[index]), index, 14)
		else:
			button = _button(str(item), 17)
		button.custom_minimum_size = Vector2(150, 104 if not sprites.is_empty() else 70)
		if button is DraggableItemButton:
			button.add_theme_constant_override("icon_max_width", 82)
		button.pressed.connect(_target_pressed.bind(button))
		grid.add_child(button)
		action_buttons.append(button)
	content.add_child(grid)


func _target_pressed(button: Button) -> void:
	if button.disabled or finished:
		return
	_set_item_caption(button, "TOSSED!")
	_animate_item_transfer(button, primary_target_visual)
	_emit_action_burst(primary_target_visual, "✦", Color("#a7c957"))
	remaining -= 1
	progress.value = 100.0 * float(action_buttons.size() - remaining) / float(action_buttons.size())
	status_label.text = "%d object%s left — keep cleaning" % [remaining, "" if remaining == 1 else "s"]
	if is_instance_valid(drop_label):
		drop_label.text = "%d MORE" % remaining if remaining > 0 else "ALL CLEAR!"
	if remaining <= 0:
		_finish()


func _target_dropped(data: Dictionary) -> void:
	var button = data.get("button")
	if button is Button:
		_target_pressed(button)


func _build_sequence() -> void:
	var items: Array = task["items"]
	var sprites: Array = task.get("item_sprites", [])
	remaining = items.size()
	progress.visible = false
	task_icon.visible = false
	status_label.text = "Grab step 1 and use it on the %s" % _sequence_target_name()
	if not sprites.is_empty():
		var target_states: Array = task.get("target_states", [])
		var target_sprite := str(target_states[0]) if not target_states.is_empty() else str(task.get("icon", ""))
		drop_zone = _bare_image_drop_zone(
			target_sprite,
			_sequence_target_name().to_upper(),
			_sequence_dropped,
			172,
			Vector2(300, 190)
		)
		content.add_child(drop_zone)
		var target_stack := drop_zone.get_child(0) as VBoxContainer
		sequence_target_visual = target_stack.get_child(0) as TextureRect
		drop_label = target_stack.get_child(1) as Label
		call_deferred("_start_sequence_target_idle")
	var grid := _grid(3 if not sprites.is_empty() else 2)
	var shuffled_indices := range(items.size())
	shuffled_indices.shuffle()
	for order in shuffled_indices:
		var button: Button
		if order < sprites.size():
			button = _item_button(str(items[order]), str(sprites[order]), order, 13)
		else:
			button = _button(str(items[order]), 17)
		button.custom_minimum_size = Vector2(160 if not sprites.is_empty() else 210, 110 if not sprites.is_empty() else 66)
		if button is DraggableItemButton:
			button.add_theme_constant_override("icon_max_width", 86)
		button.pressed.connect(_sequence_pressed.bind(button, order))
		grid.add_child(button)
		action_buttons.append(button)
	content.add_child(grid)


func _sequence_pressed(button: Button, order: int) -> void:
	if finished:
		return
	if order != next_sequence:
		status_label.text = "Not yet — use step %d first" % (next_sequence + 1)
		_wiggle_control(button, Color("#ff8c74"))
		return
	_animate_sequence_action(button, order)
	next_sequence += 1
	progress.value = 100.0 * float(next_sequence) / float(remaining)
	status_label.text = "Nice! Now grab step %d" % (next_sequence + 1)
	if is_instance_valid(drop_label):
		drop_label.text = "STEP %d / %d" % [next_sequence, remaining]
	if next_sequence >= remaining:
		_finish()


func _sequence_dropped(data: Dictionary) -> void:
	var button = data.get("button")
	if button is Button:
		_sequence_pressed(button, int(data.get("order", -1)))


func _build_matching() -> void:
	var items: Array = task["items"]
	var sprites: Array = task.get("item_sprites", [])
	var destinations: Array = task.get("destinations", [])
	var destination_sprites: Array = task.get("destination_sprites", sprites)
	remaining = items.size()
	matching_stage = 0
	matching_stage_busy = false
	matching_order.clear()
	matching_zones.clear()
	matching_zone_labels.clear()
	matching_zone_visuals.clear()
	for index in range(items.size()):
		matching_order.append(index)
	progress.visible = false
	task_icon.visible = false
	var target_host := HBoxContainer.new()
	target_host.alignment = BoxContainer.ALIGNMENT_CENTER
	target_host.custom_minimum_size = Vector2(0, 230)
	target_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in range(destinations.size()):
		var zone := _bare_image_drop_zone(str(destination_sprites[index]), str(destinations[index]), _matching_dropped.bind(index), 210, Vector2(350, 230))
		zone.visible = index == matching_stage
		target_host.add_child(zone)
		matching_zones.append(zone)
		var zone_stack := zone.get_child(0) as VBoxContainer
		matching_zone_visuals.append(zone_stack.get_child(0) as TextureRect)
		matching_zone_labels.append(zone_stack.get_child(1) as Label)
	content.add_child(target_host)
	if not matching_zones.is_empty():
		drop_zone = matching_zones[0]
	var grid := _grid(3)
	var shuffled_indices: Array[int] = matching_order.duplicate()
	shuffled_indices.shuffle()
	for order in shuffled_indices:
		var button := _item_button(str(items[order]), str(sprites[order]), order, 14)
		button.custom_minimum_size = Vector2(145, 96)
		button.add_theme_constant_override("icon_max_width", 76)
		button.pressed.connect(_matching_item_tapped.bind(button.drag_payload))
		grid.add_child(button)
		action_buttons.append(button)
	content.add_child(grid)
	_show_matching_stage(0)


func _matching_item_tapped(data: Dictionary) -> void:
	_matching_dropped(data, matching_stage)


func _matching_dropped(data: Dictionary, destination: int = -1) -> void:
	if finished or matching_stage_busy:
		return
	var order := int(data.get("order", -1))
	var items: Array = task["items"]
	var destinations: Array = task.get("destinations", [])
	if destination < 0:
		destination = matching_stage
	if order < 0 or order >= items.size() or destination != order:
		var correct_destination := str(destinations[order]) if order >= 0 and order < destinations.size() else "another place"
		status_label.text = "That doesn't fit — %s belongs at %s" % [str(items[order]) if order >= 0 and order < items.size() else "that item", correct_destination]
		var wrong_button = data.get("button")
		if wrong_button is Control:
			_wiggle_control(wrong_button, Color("#ff8c74"))
		return
	matching_stage_busy = true
	var button = data.get("button")
	if button is Button and not button.disabled:
		_set_item_caption(button, "PUT AWAY!")
		_animate_item_transfer(button, matching_zone_visuals[destination])
		if destination < matching_zones.size():
			matching_zones[destination].accepting = false
			matching_zones[destination].modulate = Color.WHITE
			var filled_sprites: Array = task.get("destination_filled_sprites", [])
			if destination < filled_sprites.size():
				matching_zone_visuals[destination].texture = load(str(filled_sprites[destination]))
			matching_zone_visuals[destination].scale = Vector2(0.82, 0.82)
			matching_zone_visuals[destination].modulate = Color("#fff0ad")
			var reveal := create_tween()
			reveal.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			reveal.tween_property(matching_zone_visuals[destination], "scale", Vector2(1.12, 1.12), 0.18)
			reveal.tween_property(matching_zone_visuals[destination], "scale", Vector2.ONE, 0.18)
			reveal.parallel().tween_property(matching_zone_visuals[destination], "modulate", Color.WHITE, 0.18)
			matching_zone_labels[destination].text = "%s FILLED  ✓" % str(destinations[destination])
			_pulse_control(matching_zones[destination])
			_emit_action_burst(matching_zone_visuals[destination], "✦", Color("#ffd166"))
	next_sequence += 1
	remaining -= 1
	progress.value = 100.0 * float(items.size() - remaining) / float(items.size())
	status_label.text = "%s is packed!" % str(destinations[destination]).capitalize()
	_transition_matching_stage(destination)


func _transition_matching_stage(completed_index: int) -> void:
	await get_tree().create_timer(0.58).timeout
	if finished or not is_instance_valid(status_label):
		return
	if remaining <= 0:
		_finish()
		return
	if completed_index >= 0 and completed_index < matching_zones.size():
		matching_zones[completed_index].visible = false
	matching_stage = mini(completed_index + 1, matching_zones.size() - 1)
	matching_stage_busy = false
	_show_matching_stage(matching_stage)


func _show_matching_stage(index: int) -> void:
	if index < 0 or index >= matching_zones.size():
		return
	for zone_index in range(matching_zones.size()):
		matching_zones[zone_index].visible = zone_index == index
	drop_zone = matching_zones[index]
	var items: Array = task["items"]
	var destinations: Array = task.get("destinations", [])
	status_label.text = "Drag %s into the %s" % [str(items[index]), str(destinations[index])]
	matching_zone_visuals[index].pivot_offset = matching_zone_visuals[index].size * 0.5
	var entrance := create_tween()
	matching_zone_visuals[index].scale = Vector2(0.78, 0.78)
	matching_zone_visuals[index].modulate = Color(1.0, 0.91, 0.66, 0.55)
	entrance.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	entrance.tween_property(matching_zone_visuals[index], "scale", Vector2.ONE, 0.24)
	entrance.parallel().tween_property(matching_zone_visuals[index], "modulate", Color.WHITE, 0.24)


func _build_rhythm() -> void:
	var sprites: Array = task.get("item_sprites", [])
	progress.visible = false
	task_icon.visible = false
	status_label.text = "Step 1 — drag the fuel can onto the lantern"
	lantern_work_panel = VBoxContainer.new()
	lantern_work_panel.add_theme_constant_override("separation", 10)
	lantern_work_instruction = _label("FUEL CAN  →  LANTERN", 17, Color("#ffd166"))
	lantern_work_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lantern_work_panel.add_child(lantern_work_instruction)
	var work_row := HBoxContainer.new()
	work_row.alignment = BoxContainer.ALIGNMENT_CENTER
	work_row.add_theme_constant_override("separation", 20)
	lantern_work_panel.add_child(work_row)
	lantern_fuel_button = _item_button("FUEL CAN", str(sprites[2]), 0, 14)
	lantern_fuel_button.custom_minimum_size = Vector2(165, 154)
	lantern_fuel_button.add_theme_constant_override("icon_max_width", 118)
	lantern_fuel_button.drag_payload["kind"] = "fuel"
	lantern_fuel_button.pressed.connect(_lantern_prop_tapped.bind(lantern_fuel_button))
	work_row.add_child(lantern_fuel_button)
	action_buttons.append(lantern_fuel_button)
	lantern_pump_button = _item_button("HAND PUMP", str(sprites[1]), 1, 14)
	lantern_pump_button.custom_minimum_size = Vector2(165, 154)
	lantern_pump_button.add_theme_constant_override("icon_max_width", 118)
	lantern_pump_button.drag_payload["kind"] = "pump"
	lantern_pump_button.visible = false
	lantern_pump_button.pressed.connect(_lantern_prop_tapped.bind(lantern_pump_button))
	work_row.add_child(lantern_pump_button)
	action_buttons.append(lantern_pump_button)
	lantern_work_zone = _bare_image_drop_zone(str(sprites[0]), "FILL LANTERN", _lantern_work_dropped, 132, Vector2(180, 154))
	work_row.add_child(lantern_work_zone)
	var zone_stack := lantern_work_zone.get_child(0) as VBoxContainer
	lantern_work_visual = zone_stack.get_child(0) as TextureRect
	lantern_work_zone_label = zone_stack.get_child(1) as Label
	var pressure_title := _label("PRESSURE CHAMBERS", 13, Color("#f4d7a7"))
	pressure_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lantern_work_panel.add_child(pressure_title)
	var pressure_row := HBoxContainer.new()
	pressure_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pressure_row.add_theme_constant_override("separation", 8)
	for _index in range(5):
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(24, 24)
		var empty_style := StyleBoxFlat.new()
		empty_style.bg_color = Color("#173d35")
		empty_style.border_color = Color("#6e8e78")
		empty_style.set_border_width_all(2)
		empty_style.set_corner_radius_all(12)
		cell.add_theme_stylebox_override("panel", empty_style)
		pressure_row.add_child(cell)
		lantern_pressure_cells.append(cell)
	lantern_work_panel.add_child(pressure_row)
	content.add_child(lantern_work_panel)
	rhythm_controls.append(lantern_work_panel)
	call_deferred("_start_lantern_idle_animation")
	_build_lantern_ignition()


func _update_rhythm(delta: float) -> void:
	# Kept as a process hook for the task mode; the redesigned lantern task is
	# driven by direct prop manipulation rather than an abstract moving slider.
	if delta < 0.0:
		return


func _rhythm_pump() -> void:
	if finished or ignition_stage >= 0 or not lantern_fueled:
		return
	rhythm_hits += 1
	progress.value = 20.0 + 50.0 * float(rhythm_hits) / 5.0
	status_label.text = "Pressure built — %d / 5 pumps" % rhythm_hits
	if rhythm_hits <= lantern_pressure_cells.size():
		var filled_style := StyleBoxFlat.new()
		filled_style.bg_color = Color("#ffd166")
		filled_style.border_color = Color("#fff3cf")
		filled_style.set_border_width_all(2)
		filled_style.set_corner_radius_all(12)
		var filled_cell := lantern_pressure_cells[rhythm_hits - 1]
		filled_cell.add_theme_stylebox_override("panel", filled_style)
		_pulse_control(filled_cell)
	_animate_pump_stroke()
	_pulse_control(lantern_work_visual)
	if rhythm_hits >= 5:
		_begin_lantern_ignition()


func _lantern_prop_tapped(prop: DraggableItemButton) -> void:
	_lantern_work_dropped(prop.drag_payload)


func _lantern_work_dropped(data: Dictionary) -> void:
	if finished or ignition_stage >= 0:
		return
	var kind := str(data.get("kind", ""))
	if kind == "fuel" and not lantern_fueled:
		lantern_fueled = true
		progress.value = 20.0
		_set_item_caption(lantern_fuel_button, "POURED ✓")
		_animate_fuel_pour()
		lantern_pump_button.visible = true
		lantern_work_zone_label.text = "PUMP LANTERN"
		lantern_work_instruction.text = "PUMP  →  LANTERN  ×5"
		status_label.text = "Step 2 — drag the pump onto the lantern five times"
		_pulse_control(lantern_work_visual)
	elif kind == "pump" and lantern_fueled:
		_rhythm_pump()
	elif kind == "pump":
		status_label.text = "Add fuel before pumping"


func _build_lantern_ignition() -> void:
	var sprites: Array = task.get("item_sprites", [])
	var task_assets: Array = task.get("task_assets", [])
	if sprites.size() < 4 or task_assets.size() < 2:
		return
	ignition_panel = VBoxContainer.new()
	ignition_panel.visible = false
	ignition_panel.add_theme_constant_override("separation", 8)
	ignition_instruction = _label("Drag the matchstick across the matchbox", 15, Color("#f4d7a7"))
	ignition_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ignition_panel.add_child(ignition_instruction)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 34)
	ignition_panel.add_child(row)
	ignition_match = _item_button("MATCHSTICK", str(task_assets[0]), 0, 14)
	ignition_match.custom_minimum_size = Vector2(175, 166)
	ignition_match.add_theme_constant_override("icon_max_width", 122)
	ignition_match.drag_payload["kind"] = "matchstick"
	ignition_match.drag_payload["lit"] = false
	ignition_match.pressed.connect(_ignition_tapped)
	ignition_match.drag_started.connect(_reset_match_strike)
	row.add_child(ignition_match)
	action_buttons.append(ignition_match)
	ignition_matchbox_zone = _bare_image_drop_zone(str(sprites[3]), "SWIPE ACROSS", _ignition_drop.bind("matchbox"), 132, Vector2(185, 166))
	ignition_matchbox_zone.item_dragged_over.connect(_match_strike_motion)
	row.add_child(ignition_matchbox_zone)
	ignition_lantern_zone = _bare_image_drop_zone(str(sprites[0]), "LIGHT LANTERN", _ignition_drop.bind("lantern"), 138, Vector2(185, 166))
	var lantern_stack := ignition_lantern_zone.get_child(0) as VBoxContainer
	ignition_lantern_visual = lantern_stack.get_child(0) as TextureRect
	ignition_lantern_zone.visible = false
	row.add_child(ignition_lantern_zone)
	content.add_child(ignition_panel)


func _begin_lantern_ignition() -> void:
	ignition_stage = 0
	for control in rhythm_controls:
		if is_instance_valid(control):
			control.visible = false
	if is_instance_valid(ignition_panel):
		ignition_panel.visible = true
	call_deferred("_start_ignition_idle_animation")
	progress.value = 70.0
	status_label.text = "Fuel ready — strike the match"


func _ignition_tapped() -> void:
	if not is_instance_valid(ignition_match):
		return
	if ignition_stage == 0:
		status_label.text = "Hold and swipe the matchstick across the matchbox"
	else:
		status_label.text = "Drag the burning match onto the lantern"


func _reset_match_strike(_data: Dictionary = {}) -> void:
	match_strike_tracking = false
	match_strike_distance = 0.0


func _match_strike_motion(data: Dictionary, at_position: Vector2) -> void:
	if finished or ignition_stage != 0 or str(data.get("kind", "")) != "matchstick":
		return
	if not match_strike_tracking:
		match_strike_tracking = true
		match_strike_last = at_position
		status_label.text = "Keep swiping across the rough strip..."
		return
	var movement := at_position - match_strike_last
	match_strike_last = at_position
	# A real strike must travel mostly sideways across the matchbox surface.
	if absf(movement.x) >= absf(movement.y) * 0.65:
		match_strike_distance += absf(movement.x)
		var strike_percent := clampi(int(100.0 * match_strike_distance / 42.0), 0, 100)
		status_label.text = "Striking match... %d%%" % strike_percent
	if match_strike_distance >= 42.0:
		_ignite_matchstick()


func _ignition_drop(data: Dictionary, target: String) -> void:
	if finished or str(data.get("kind", "")) != "matchstick":
		return
	if target == "matchbox" and ignition_stage == 0:
		status_label.text = "Swipe farther across the rough strip to ignite it"
	elif target == "lantern" and ignition_stage == 1 and bool(data.get("lit", false)):
		ignition_stage = 2
		ignition_match.disabled = true
		ignition_lantern_zone.modulate = Color("#ffd166")
		status_label.text = "Lantern flame caught!"
		_finish()
	elif target == "lantern":
		status_label.text = "Strike the match on the box first"


func _ignite_matchstick() -> void:
	if ignition_stage != 0:
		return
	var task_assets: Array = task.get("task_assets", [])
	ignition_stage = 1
	var lit_texture: Texture2D = load(str(task_assets[1]))
	ignition_match.set_drag_texture(lit_texture)
	ignition_match.set_caption("LIT MATCH")
	ignition_match.drag_payload["lit"] = true
	ignition_match.modulate = Color("#ffd166")
	ignition_matchbox_zone.visible = false
	ignition_lantern_zone.visible = true
	ignition_instruction.text = "Flame lit! Keep dragging it onto the lantern"
	status_label.text = "Match is burning — light the lantern"
	progress.value = 85.0
	_pulse_control(ignition_match)
	_emit_match_sparks()
	call_deferred("_start_flame_flicker")


func _build_hammer() -> void:
	var items: Array = task["items"]
	var sprites: Array = task.get("item_sprites", [])
	var task_assets: Array = task.get("task_assets", [])
	remaining = items.size()
	progress.visible = false
	task_icon.visible = false
	status_label.text = "Drag the hammer onto a nail — each one needs 3 solid hits"
	var workbench := HBoxContainer.new()
	workbench.alignment = BoxContainer.ALIGNMENT_CENTER
	workbench.add_theme_constant_override("separation", 20)
	var board_area := Control.new()
	board_area.custom_minimum_size = Vector2(390, 245)
	board_area.mouse_filter = Control.MOUSE_FILTER_PASS
	workbench.add_child(board_area)
	if task_assets.size() >= 2:
		dock_plank_visual = TextureRect.new()
		dock_plank_visual.texture = load(str(task_assets[1]))
		dock_plank_visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		dock_plank_visual.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		dock_plank_visual.position = Vector2(30, 20)
		dock_plank_visual.size = Vector2(330, 205)
		dock_plank_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board_area.add_child(dock_plank_visual)
	var nail_positions := [Vector2(38, 67), Vector2(145, 61), Vector2(252, 67)]
	for index in range(items.size()):
		var zone := _bare_image_drop_zone(str(sprites[index]), "3 HITS", _hammer_drop.bind(index), 76, Vector2(100, 120))
		zone.position = nail_positions[index]
		zone.size = Vector2(100, 120)
		board_area.add_child(zone)
		hammer_nail_zones.append(zone)
		hammer_nail_hits.append(0)
		var stack := zone.get_child(0) as VBoxContainer
		hammer_nail_labels.append(stack.get_child(1) as Label)
	if task_assets.size() >= 1:
		hammer_tool = _item_button("HAMMER", str(task_assets[0]), 0, 14)
		hammer_tool.custom_minimum_size = Vector2(155, 210)
		hammer_tool.add_theme_constant_override("icon_max_width", 128)
		hammer_tool.drag_payload["kind"] = "hammer"
		hammer_tool.pressed.connect(_hammer_tapped)
		workbench.add_child(hammer_tool)
		action_buttons.append(hammer_tool)
	content.add_child(workbench)
	call_deferred("_select_next_nail")


func _select_next_nail() -> void:
	if finished or remaining <= 0:
		return
	hammer_active_index = -1
	for index in range(hammer_nail_zones.size()):
		var zone := hammer_nail_zones[index]
		if zone.accepting:
			zone.modulate = Color.WHITE
			if hammer_active_index < 0:
				hammer_active_index = index
	if hammer_active_index >= 0:
		_animate_raised_nail(hammer_nail_zones[hammer_active_index])


func _update_hammer(delta: float) -> void:
	# Dock repair is now direct manipulation; there is no arbitrary timer.
	if delta < 0.0:
		return


func _hammer_tapped() -> void:
	if hammer_active_index >= 0:
		_hammer_hit(hammer_active_index)


func _hammer_drop(data: Dictionary, index: int) -> void:
	if str(data.get("kind", "")) == "hammer":
		_hammer_hit(index)


func _hammer_hit(index: int) -> void:
	if finished or index < 0 or index >= hammer_nail_zones.size() or not hammer_nail_zones[index].accepting:
		return
	hammer_nail_hits[index] += 1
	var hits_left := hammer_hits_required - hammer_nail_hits[index]
	_animate_hammer_impact(hammer_nail_zones[index])
	_sink_nail_visual(index)
	if hits_left > 0:
		hammer_nail_labels[index].text = "%d HIT%s LEFT" % [hits_left, "" if hits_left == 1 else "S"]
		status_label.text = "Good hit! %s needs %d more" % [str(task["items"][index]).capitalize(), hits_left]
		return
	hammer_nail_zones[index].accepting = false
	hammer_nail_zones[index].modulate = Color("#a7c957")
	hammer_nail_labels[index].text = "FLUSH  ✓"
	remaining -= 1
	progress.value = 100.0 * float(hammer_nail_zones.size() - remaining) / float(hammer_nail_zones.size())
	if remaining <= 0:
		_complete_dock_repair()
		_finish()
	else:
		status_label.text = "%d nail%s left — choose either one" % [remaining, "" if remaining == 1 else "s"]
		_select_next_nail()


func _hammer_pressed(_button: Button, index: int) -> void:
	_hammer_hit(index)


func _build_hold() -> void:
	status_label.text = "Hold to pump - releasing pauses the fill"
	var pump := _button("HOLD TO PUMP", 23)
	pump.custom_minimum_size = Vector2(360, 110)
	pump.button_down.connect(func() -> void: hold_active = true)
	pump.button_up.connect(func() -> void: hold_active = false)
	content.add_child(pump)
	action_buttons.append(pump)


func _build_dial() -> void:
	dial_target = float(abs(task_id.hash()) % 51 + 25)
	progress.visible = false
	task_icon.visible = false
	var sprites: Array = task.get("item_sprites", [])
	if sprites.size() >= 4:
		var radio_strip := HBoxContainer.new()
		radio_strip.alignment = BoxContainer.ALIGNMENT_CENTER
		radio_strip.add_theme_constant_override("separation", 32)
		radio_visual = _asset_texture(str(sprites[0]), 168)
		radio_strip.add_child(radio_visual)
		dial_needle_texture = _asset_texture(str(sprites[2]), 112)
		radio_strip.add_child(dial_needle_texture)
		signal_texture = _asset_texture(str(sprites[3]), 126)
		signal_texture.modulate = Color(1.0, 1.0, 1.0, 0.22)
		radio_strip.add_child(signal_texture)
		content.add_child(radio_strip)
	dial = HSlider.new()
	dial.min_value = 0.0
	dial.max_value = 100.0
	dial.step = 1.0
	dial.value = 8.0
	dial.custom_minimum_size = Vector2(460, 92)
	if sprites.size() >= 2:
		var knob_texture: Texture2D = _scaled_texture(str(sprites[1]), 78)
		dial.add_theme_icon_override("grabber", knob_texture)
		dial.add_theme_icon_override("grabber_highlight", knob_texture)
	_style_playable_slider(dial)
	dial.value_changed.connect(func(_value: float) -> void: _check_dial())
	content.add_child(dial)
	status_label.text = "Turn the large knob to channel %.0f and hold it steady" % dial_target
	var frequency_hint := _label("◀  STATIC     CHANNEL %.0f     STATIC  ▶" % dial_target, 14, Color("#ffd166"))
	frequency_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(frequency_hint)
	call_deferred("_start_radio_idle_animation")
	call_deferred("_check_dial")


func _check_dial() -> void:
	var offset := absf(dial.value - dial_target)
	if is_instance_valid(dial_knob_texture):
		dial_knob_texture.pivot_offset = dial_knob_texture.size * 0.5
		dial_knob_texture.rotation = deg_to_rad(lerpf(-125.0, 125.0, float(dial.value) / 100.0))
	if is_instance_valid(dial_needle_texture):
		dial_needle_texture.pivot_offset = dial_needle_texture.size * 0.5
		dial_needle_texture.rotation = deg_to_rad(lerpf(-42.0, 42.0, float(dial.value) / 100.0))
	if offset <= dial_tolerance:
		status_label.text = "STRONG SIGNAL — hold steady"
		if is_instance_valid(radio_visual):
			_pulse_control(radio_visual)
	else:
		dial_lock_elapsed = 0.0
		progress.value = clampf(55.0 - offset * 2.0, 0.0, 55.0)
		status_label.text = "SEARCHING... target %.0f" % dial_target
		if is_instance_valid(signal_texture):
			signal_texture.modulate = Color(1.0, 1.0, 1.0, 0.22)


func _update_dial_lock(delta: float) -> void:
	if not is_instance_valid(dial):
		return
	var offset := absf(dial.value - dial_target)
	if offset > dial_tolerance:
		_check_dial()
		return
	dial_lock_elapsed += delta
	progress.value = clampf(100.0 * dial_lock_elapsed / 0.85, 0.0, 100.0)
	status_label.text = "SIGNAL LOCK %.0f%% — keep steady" % progress.value
	if is_instance_valid(signal_texture):
		signal_texture.modulate = Color(1.0, 1.0, 1.0, 0.45 + 0.55 * progress.value / 100.0)
		signal_texture.pivot_offset = signal_texture.size * 0.5
		signal_texture.scale = Vector2.ONE * (0.88 + 0.12 * progress.value / 100.0)
	if dial_lock_elapsed >= 0.85:
		_finish()


func _build_find() -> void:
	var items: Array = task["items"]
	var sprites: Array = task.get("item_sprites", [])
	var targets := [items[1], items[4], items[5]]
	var target_names := PackedStringArray()
	for target in targets:
		target_names.append(str(target))
	remaining = targets.size()
	progress.visible = false
	task_icon.visible = false
	status_label.text = "Pack only: %s" % ", ".join(target_names)
	drop_zone = _bare_image_drop_zone(str(task.get("icon", "")), "SUPPLY PACK", _find_dropped.bind(targets), 132, Vector2(220, 140))
	content.add_child(drop_zone)
	var pack_stack := drop_zone.get_child(0) as VBoxContainer
	primary_target_visual = pack_stack.get_child(0) as TextureRect
	drop_label = pack_stack.get_child(1) as Label
	call_deferred("_start_primary_target_idle")
	var grid := _grid(3)
	var shuffled_indices := range(items.size())
	shuffled_indices.shuffle()
	for index in shuffled_indices:
		var button: Button
		if index < sprites.size():
			button = _item_button(str(items[index]), str(sprites[index]), index, 14)
		else:
			button = _button(str(items[index]), 16)
		button.custom_minimum_size = Vector2(150, 102 if not sprites.is_empty() else 68)
		if button is DraggableItemButton:
			button.add_theme_constant_override("icon_max_width", 80)
		button.pressed.connect(_find_pressed.bind(button, str(items[index]), targets))
		grid.add_child(button)
		action_buttons.append(button)
	content.add_child(grid)


func _find_dropped(data: Dictionary, targets: Array) -> void:
	var index := int(data.get("order", -1))
	var items: Array = task["items"]
	if index >= 0 and index < items.size():
		var button = data.get("button")
		if button is Button:
			_find_pressed(button, str(items[index]), targets)


func _find_pressed(button: Button, item: String, targets: Array) -> void:
	if button.disabled or finished:
		return
	if item not in targets:
		status_label.text = "%s isn't on the list — leave it on the shelf" % item
		_wiggle_control(button, Color("#ff8c74"))
		return
	_set_item_caption(button, "PACKED!")
	_animate_item_transfer(button, primary_target_visual)
	_emit_action_burst(primary_target_visual, "+", Color("#a7c957"))
	remaining -= 1
	progress.value = 100.0 * float(targets.size() - remaining) / float(targets.size())
	status_label.text = "%d requested suppl%s left" % [remaining, "y" if remaining == 1 else "ies"]
	if is_instance_valid(drop_label):
		drop_label.text = "%d / %d PACKED" % [targets.size() - remaining, targets.size()]
	if remaining <= 0:
		_finish()


func _finish() -> void:
	if finished:
		return
	finished = true
	hold_active = false
	progress.value = 100.0
	status_label.text = "SABOTAGE COMPLETE" if is_sabotage_task else "TASK COMPLETE"
	if task_id == "dock":
		var dock_assets: Array = task.get("task_assets", [])
		if dock_assets.size() >= 3 and is_instance_valid(task_icon):
			task_icon.texture = load(str(dock_assets[2]))
	if is_instance_valid(drop_label):
		drop_label.text = "SABOTAGE COMPLETE" if is_sabotage_task else "TASK COMPLETE"
	for button in action_buttons:
		button.disabled = true
	await get_tree().create_timer(0.45).timeout
	completed.emit(task_id)
	queue_free()


func _close() -> void:
	if finished:
		return
	closed.emit()
	queue_free()


func _layout() -> void:
	if not is_instance_valid(panel):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if is_instance_valid(task_icon):
		if _uses_item_sprites():
			task_icon.custom_minimum_size.y = 46.0 if viewport_size.y < 700.0 else 64.0
		else:
			task_icon.custom_minimum_size.y = 110.0 if viewport_size.y < 700.0 else 150.0
	var panel_size := Vector2(minf(720.0, viewport_size.x - 28.0), minf(680.0, viewport_size.y - 28.0))
	panel.size = panel_size
	panel.position = (viewport_size - panel_size) * 0.5


func _grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	return grid


func _build_drop_zone(label_text: String, callback: Callable, sprite_path: String = "") -> void:
	drop_zone = ItemDropZone.new()
	drop_zone.accepted_task_id = task_id
	drop_zone.custom_minimum_size = Vector2(0, 78 if not sprite_path.is_empty() else 52)
	drop_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#102b2b")
	style.border_color = Color("#f4d7a7")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(8)
	drop_zone.add_theme_stylebox_override("panel", style)
	drop_label = _label(label_text, 15, Color("#f4d7a7"))
	drop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if sprite_path.is_empty():
		drop_zone.add_child(drop_label)
	else:
		var target_row := HBoxContainer.new()
		target_row.alignment = BoxContainer.ALIGNMENT_CENTER
		target_row.add_theme_constant_override("separation", 12)
		target_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		target_row.add_child(_asset_texture(sprite_path, 58))
		target_row.add_child(drop_label)
		drop_zone.add_child(target_row)
	drop_zone.item_dropped.connect(callback)
	content.add_child(drop_zone)


func _asset_strip(paths: Array, item_size: int) -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 18)
	for path in paths:
		strip.add_child(_asset_texture(str(path), item_size))
	return strip


func _asset_texture(path: String, item_size: int) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.texture = load(path)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_rect.custom_minimum_size = Vector2(item_size, item_size)
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return texture_rect


func _image_drop_zone(sprite_path: String, label_text: String, callback: Callable, visual_size: int = 68) -> ItemDropZone:
	var zone := ItemDropZone.new()
	zone.accepted_task_id = task_id
	zone.custom_minimum_size = Vector2(150, 104)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#102b2b")
	style.border_color = Color("#f4d7a7")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(5)
	zone.add_theme_stylebox_override("panel", style)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var visual := _asset_texture(sprite_path, visual_size)
	stack.add_child(visual)
	var caption := _label(label_text, 12, Color("#f4d7a7"))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(caption)
	zone.add_child(stack)
	zone.item_dropped.connect(callback)
	return zone


func _bare_image_drop_zone(sprite_path: String, label_text: String, callback: Callable, visual_size: int, minimum_size: Vector2) -> ItemDropZone:
	var zone := ItemDropZone.new()
	zone.accepted_task_id = task_id
	zone.custom_minimum_size = minimum_size
	zone.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var transparent := StyleBoxFlat.new()
	transparent.bg_color = Color.TRANSPARENT
	transparent.border_color = Color.TRANSPARENT
	transparent.set_border_width_all(0)
	transparent.set_content_margin_all(0)
	zone.add_theme_stylebox_override("panel", transparent)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var visual := _asset_texture(sprite_path, visual_size)
	stack.add_child(visual)
	var caption := _label(label_text, 13, Color("#fff3cf"))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_color_override("font_outline_color", Color("#061514"))
	caption.add_theme_constant_override("outline_size", 4)
	stack.add_child(caption)
	zone.add_child(stack)
	zone.item_dropped.connect(callback)
	return zone


func _style_quiet_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color.TRANSPARENT
	normal.border_color = Color.TRANSPARENT
	normal.set_border_width_all(0)
	normal.set_corner_radius_all(12)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#255244", 0.72)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#35705a", 0.82)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", Color("#cde3c3"))
	button.add_theme_color_override("font_hover_color", Color("#fff3cf"))


func _sequence_target_name() -> String:
	match task_id:
		"generator": return "generator"
		"dinner": return "cooking pot"
		"tools": return "tool rack"
	return "work area"


func _start_primary_target_idle() -> void:
	if not is_instance_valid(primary_target_visual):
		return
	primary_target_visual.pivot_offset = primary_target_visual.size * 0.5
	var tween := create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(primary_target_visual, "rotation", deg_to_rad(2.4), 0.8)
	tween.parallel().tween_property(primary_target_visual, "scale", Vector2(1.045, 1.045), 0.8)
	tween.tween_property(primary_target_visual, "rotation", deg_to_rad(-2.4), 0.8)
	tween.parallel().tween_property(primary_target_visual, "scale", Vector2.ONE, 0.8)


func _start_sequence_target_idle() -> void:
	if not is_instance_valid(sequence_target_visual):
		return
	sequence_target_visual.pivot_offset = sequence_target_visual.size * 0.5
	var tween := create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sequence_target_visual, "modulate", Color("#ffe1a2"), 0.9)
	tween.parallel().tween_property(sequence_target_visual, "scale", Vector2(1.035, 1.035), 0.9)
	tween.tween_property(sequence_target_visual, "modulate", Color.WHITE, 0.9)
	tween.parallel().tween_property(sequence_target_visual, "scale", Vector2.ONE, 0.9)


func _animate_item_transfer(item: Control, target: Control) -> void:
	if not is_instance_valid(item):
		return
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if item is BaseButton:
		(item as BaseButton).disabled = true
	item.pivot_offset = item.size * 0.5
	var target_point := item.position
	if is_instance_valid(target):
		target_point += (target.global_position + target.size * 0.5) - (item.global_position + item.size * 0.5)
	var faded := Color("#ffd166")
	faded.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(item, "position", target_point, 0.34)
	tween.tween_property(item, "scale", Vector2(0.22, 0.22), 0.34)
	tween.tween_property(item, "rotation", item.rotation + deg_to_rad(34.0), 0.34)
	tween.tween_property(item, "modulate", faded, 0.34)
	if is_instance_valid(target):
		_pulse_control(target)


func _animate_sequence_action(button: Button, order: int) -> void:
	button.disabled = true
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_item_caption(button, "USED!")
	button.pivot_offset = button.size * 0.5
	_advance_sequence_target(order)
	var tween := create_tween()
	match task_id:
		"generator":
			if order == 1:
				tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
				tween.tween_property(button, "rotation", button.rotation + TAU, 0.42)
			elif order == 2:
				tween.tween_property(button, "rotation", deg_to_rad(54.0), 0.2)
				tween.tween_interval(0.12)
			else:
				tween.tween_property(button, "scale", Vector2(1.16, 0.84), 0.12)
		"dinner":
			if order == 0:
				tween.tween_property(button, "rotation", deg_to_rad(58.0), 0.22)
			elif order == 2:
				for angle in [-10.0, 10.0, -8.0, 0.0]:
					tween.tween_property(button, "rotation", deg_to_rad(angle), 0.07)
			elif order == 3 and is_instance_valid(sequence_target_visual):
				var pot_tween := create_tween()
				for angle in [-7.0, 7.0, -5.0, 0.0]:
					pot_tween.tween_property(sequence_target_visual, "rotation", deg_to_rad(angle), 0.09)
			else:
				tween.tween_property(button, "position:y", button.position.y - 18.0, 0.14)
		_:
			tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(button, "scale", Vector2(1.14, 1.14), 0.12)
	var faded := button.modulate
	faded.a = 0.0
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(button, "scale", Vector2(0.25, 0.25), 0.24)
	tween.tween_property(button, "modulate", faded, 0.24)
	if is_instance_valid(sequence_target_visual):
		_pulse_control(sequence_target_visual)
		_emit_action_burst(sequence_target_visual, "⚡" if task_id == "generator" else "✦", Color("#ffd166"))


func _advance_sequence_target(order: int) -> void:
	if not is_instance_valid(sequence_target_visual):
		return
	var target_states: Array = task.get("target_states", [])
	var next_state := order + 1
	if next_state < 0 or next_state >= target_states.size():
		return
	sequence_target_visual.texture = load(str(target_states[next_state]))
	sequence_target_visual.pivot_offset = sequence_target_visual.size * 0.5
	sequence_target_visual.scale = Vector2(0.86, 0.86)
	sequence_target_visual.modulate = Color("#fff0b2")
	var reveal := create_tween()
	reveal.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_property(sequence_target_visual, "scale", Vector2(1.08, 1.08), 0.16)
	reveal.tween_property(sequence_target_visual, "scale", Vector2.ONE, 0.15)
	reveal.parallel().tween_property(sequence_target_visual, "modulate", Color.WHITE, 0.15)
	if next_state == target_states.size() - 1:
		_emit_action_burst(sequence_target_visual, "⚡" if task_id == "generator" else "✦", Color("#ffd166"))
		if task_id == "generator":
			var running := create_tween().set_loops(3)
			running.tween_property(sequence_target_visual, "rotation", deg_to_rad(1.8), 0.06)
			running.tween_property(sequence_target_visual, "rotation", deg_to_rad(-1.8), 0.06)
			running.tween_property(sequence_target_visual, "rotation", 0.0, 0.06)


func _wiggle_control(control: Control, flash: Color) -> void:
	if not is_instance_valid(control):
		return
	control.pivot_offset = control.size * 0.5
	var base_rotation := float(control.get_meta("home_rotation", control.rotation))
	var tween := create_tween()
	tween.tween_property(control, "modulate", flash, 0.06)
	for angle in [-7.0, 7.0, -5.0, 5.0, 0.0]:
		tween.tween_property(control, "rotation", base_rotation + deg_to_rad(angle), 0.045)
	tween.tween_property(control, "modulate", Color.WHITE, 0.1)


func _emit_action_burst(target: Control, glyph: String, color: Color) -> void:
	if not is_instance_valid(target) or not is_instance_valid(root):
		return
	var origin := target.global_position + target.size * 0.5 - root.global_position
	var directions := [Vector2(-42, -22), Vector2(-22, -45), Vector2(4, -52), Vector2(32, -39), Vector2(46, -10)]
	for direction in directions:
		var particle := _label(glyph, 20, color)
		particle.position = origin - Vector2(10, 10)
		particle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(particle)
		var faded := particle.modulate
		faded.a = 0.0
		var tween := create_tween().set_parallel(true)
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(particle, "position", particle.position + direction, 0.42)
		tween.tween_property(particle, "scale", Vector2(0.3, 0.3), 0.42)
		tween.tween_property(particle, "modulate", faded, 0.42)
		tween.chain().tween_callback(particle.queue_free)


func _animate_raised_nail(zone: Control) -> void:
	if not is_instance_valid(zone):
		return
	zone.pivot_offset = zone.size * 0.5
	var tween := create_tween().set_loops(3)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(zone, "scale", Vector2(1.13, 1.13), 0.16)
	tween.tween_property(zone, "scale", Vector2.ONE, 0.18)


func _animate_hammer_impact(nail_zone: Control) -> void:
	if is_instance_valid(hammer_tool):
		hammer_tool.pivot_offset = hammer_tool.size * Vector2(0.25, 0.82)
		var home_rotation := float(hammer_tool.get_meta("home_rotation", 0.0))
		var swing := create_tween()
		swing.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		swing.tween_property(hammer_tool, "rotation", home_rotation - deg_to_rad(34.0), 0.08)
		swing.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		swing.tween_property(hammer_tool, "rotation", home_rotation + deg_to_rad(18.0), 0.1)
		swing.tween_property(hammer_tool, "rotation", home_rotation, 0.13)
	if is_instance_valid(nail_zone):
		nail_zone.pivot_offset = nail_zone.size * 0.5
		var impact := create_tween()
		impact.tween_property(nail_zone, "scale", Vector2(1.18, 0.58), 0.08)
		impact.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		impact.tween_property(nail_zone, "scale", Vector2.ONE, 0.18)
		_emit_action_burst(nail_zone, "✦", Color("#ffd166"))
	if is_instance_valid(dock_plank_visual):
		_pulse_control(dock_plank_visual)


func _sink_nail_visual(index: int) -> void:
	if index < 0 or index >= hammer_nail_zones.size():
		return
	var stack := hammer_nail_zones[index].get_child(0) as VBoxContainer
	var nail_visual := stack.get_child(0) as TextureRect
	nail_visual.pivot_offset = Vector2(nail_visual.size.x * 0.5, nail_visual.size.y)
	var depth := clampf(float(hammer_nail_hits[index]) / float(hammer_hits_required), 0.0, 1.0)
	var target_scale := Vector2(1.0 - depth * 0.12, 1.0 - depth * 0.52)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(nail_visual, "scale", target_scale, 0.16)
	tween.parallel().tween_property(nail_visual, "modulate", Color("#fff0ad") if depth < 1.0 else Color("#b7d67b"), 0.16)


func _complete_dock_repair() -> void:
	var task_assets: Array = task.get("task_assets", [])
	if task_assets.size() < 3 or not is_instance_valid(dock_plank_visual):
		return
	dock_plank_visual.texture = load(str(task_assets[2]))
	dock_plank_visual.pivot_offset = dock_plank_visual.size * 0.5
	var reveal := create_tween()
	dock_plank_visual.scale = Vector2(0.84, 0.84)
	dock_plank_visual.modulate = Color("#ffd166")
	reveal.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_property(dock_plank_visual, "scale", Vector2(1.12, 1.12), 0.18)
	reveal.tween_property(dock_plank_visual, "scale", Vector2.ONE, 0.2)
	reveal.parallel().tween_property(dock_plank_visual, "modulate", Color.WHITE, 0.2)
	_emit_action_burst(dock_plank_visual, "✦", Color("#ffd166"))


func _style_playable_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#0b2725")
	track.border_color = Color("#6e8e78")
	track.set_border_width_all(2)
	track.set_corner_radius_all(8)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color = Color("#a7c957")
	filled.border_color = Color("#e7f7a9")
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", filled)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled)


func _scaled_texture(path: String, edge: int) -> Texture2D:
	var source: Texture2D = load(path)
	if source == null:
		return null
	var image := source.get_image()
	image.resize(edge, edge, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


func _start_radio_idle_animation() -> void:
	if not is_instance_valid(radio_visual):
		return
	radio_visual.pivot_offset = radio_visual.size * 0.5
	radio_idle_tween = create_tween().set_loops()
	radio_idle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	radio_idle_tween.tween_property(radio_visual, "rotation", deg_to_rad(1.6), 0.32)
	radio_idle_tween.tween_property(radio_visual, "rotation", deg_to_rad(-1.6), 0.32)


func _start_lantern_idle_animation() -> void:
	if is_instance_valid(lantern_work_visual):
		lantern_work_visual.pivot_offset = lantern_work_visual.size * 0.5
		var lantern_tween := create_tween().set_loops()
		lantern_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		lantern_tween.tween_property(lantern_work_visual, "scale", Vector2(1.055, 1.055), 0.85)
		lantern_tween.tween_property(lantern_work_visual, "scale", Vector2.ONE, 0.85)
	if is_instance_valid(lantern_fuel_button):
		lantern_fuel_button.pivot_offset = lantern_fuel_button.size * 0.5
		var base_rotation := float(lantern_fuel_button.get_meta("home_rotation", 0.0))
		fuel_idle_tween = create_tween().set_loops()
		fuel_idle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		fuel_idle_tween.tween_property(lantern_fuel_button, "rotation", base_rotation + deg_to_rad(2.5), 0.7)
		fuel_idle_tween.tween_property(lantern_fuel_button, "rotation", base_rotation - deg_to_rad(2.5), 0.7)


func _start_ignition_idle_animation() -> void:
	var target_visual: TextureRect = ignition_lantern_visual
	if not is_instance_valid(target_visual):
		return
	target_visual.pivot_offset = target_visual.size * 0.5
	var tween := create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(target_visual, "modulate", Color("#ffd982"), 0.75)
	tween.parallel().tween_property(target_visual, "scale", Vector2(1.045, 1.045), 0.75)
	tween.tween_property(target_visual, "modulate", Color.WHITE, 0.75)
	tween.parallel().tween_property(target_visual, "scale", Vector2.ONE, 0.75)


func _animate_fuel_pour() -> void:
	if not is_instance_valid(lantern_fuel_button):
		return
	if is_instance_valid(fuel_idle_tween):
		fuel_idle_tween.kill()
	lantern_fuel_button.disabled = true
	lantern_fuel_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lantern_fuel_button.pivot_offset = lantern_fuel_button.size * 0.5
	var faded := Color("#ffd166")
	faded.a = 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(lantern_fuel_button, "rotation", deg_to_rad(52.0), 0.18)
	tween.parallel().tween_property(lantern_fuel_button, "scale", Vector2(1.12, 1.12), 0.18)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(lantern_fuel_button, "scale", Vector2(0.35, 0.35), 0.2)
	tween.parallel().tween_property(lantern_fuel_button, "modulate", faded, 0.2)
	tween.tween_callback(func() -> void: lantern_fuel_button.visible = false)


func _animate_pump_stroke() -> void:
	if not is_instance_valid(lantern_pump_button):
		return
	lantern_pump_button.pivot_offset = lantern_pump_button.size * 0.5
	var base_rotation := float(lantern_pump_button.get_meta("home_rotation", 0.0))
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(lantern_pump_button, "scale", Vector2(1.08, 0.72), 0.1)
	tween.parallel().tween_property(lantern_pump_button, "rotation", base_rotation - deg_to_rad(6.0), 0.1)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(lantern_pump_button, "scale", Vector2.ONE, 0.16)
	tween.parallel().tween_property(lantern_pump_button, "rotation", base_rotation, 0.16)


func _emit_match_sparks() -> void:
	if not is_instance_valid(ignition_matchbox_zone):
		return
	var origin := ignition_matchbox_zone.global_position + ignition_matchbox_zone.size * 0.5 - root.global_position
	var directions := [Vector2(-30, -34), Vector2(-12, -48), Vector2(18, -42), Vector2(34, -24), Vector2(5, -58)]
	for index in range(directions.size()):
		var spark := _label("✦", 17 + index % 2 * 5, Color("#ffd166"))
		spark.position = origin - Vector2(8, 8)
		spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(spark)
		var faded := spark.modulate
		faded.a = 0.0
		var tween := create_tween().set_parallel(true)
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(spark, "position", spark.position + directions[index], 0.38)
		tween.tween_property(spark, "scale", Vector2(0.25, 0.25), 0.38)
		tween.tween_property(spark, "modulate", faded, 0.38)
		tween.chain().tween_callback(spark.queue_free)


func _start_flame_flicker() -> void:
	if not is_instance_valid(ignition_match):
		return
	ignition_match.pivot_offset = ignition_match.size * 0.5
	var base_rotation := float(ignition_match.get_meta("home_rotation", 0.0))
	var tween := create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(ignition_match, "scale", Vector2(1.055, 0.97), 0.12)
	tween.parallel().tween_property(ignition_match, "rotation", base_rotation + deg_to_rad(1.5), 0.12)
	tween.tween_property(ignition_match, "scale", Vector2(0.98, 1.055), 0.14)
	tween.parallel().tween_property(ignition_match, "rotation", base_rotation - deg_to_rad(1.0), 0.14)


func _icon_button(value: String, sprite_path: String, font_size: int) -> Button:
	var button := _button(value, font_size)
	button.icon = load(sprite_path)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width", 58)
	return button


func _item_button(value: String, sprite_path: String, order: int, font_size: int) -> DraggableItemButton:
	var button := DraggableItemButton.new()
	_style_asset_button(button, font_size)
	button.set_caption(value)
	button.icon = load(sprite_path)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 68)
	button.tooltip_text = "Drag or tap " + value
	var tilts := [-3.0, 2.0, -1.5, 3.0, 0.0]
	button.rotation = deg_to_rad(tilts[posmod(order + task_id.hash(), tilts.size())])
	button.set_meta("home_rotation", button.rotation)
	button.drag_payload = {
		"task_id": task_id,
		"order": order,
		"button": button
	}
	return button


func _style_asset_button(button: Button, _font_size: int) -> void:
	button.text = ""
	button.custom_minimum_size = Vector2(145, 88)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color.TRANSPARENT
	normal.border_color = Color.TRANSPARENT
	normal.set_border_width_all(0)
	normal.content_margin_bottom = 24.0
	var hover := normal.duplicate() as StyleBoxFlat
	var pressed := normal.duplicate() as StyleBoxFlat
	var focus := normal.duplicate() as StyleBoxFlat
	var disabled := normal.duplicate() as StyleBoxFlat
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("icon_normal_color", Color.WHITE)
	button.add_theme_color_override("icon_hover_color", Color("#fff2b8"))
	button.add_theme_color_override("icon_pressed_color", Color("#ffd166"))
	button.add_theme_color_override("icon_focus_color", Color.WHITE)
	button.add_theme_color_override("icon_disabled_color", Color.WHITE)


func _set_item_caption(button: Button, value: String) -> void:
	if button is DraggableItemButton:
		(button as DraggableItemButton).set_caption(value)
	else:
		button.text = value


func _consume_item(button: Button) -> void:
	button.disabled = true
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var target_rotation := button.rotation + deg_to_rad(10.0)
	var faded := button.modulate
	faded.a = 0.12
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(button, "scale", Vector2(0.42, 0.42), 0.2)
	tween.tween_property(button, "rotation", target_rotation, 0.2)
	tween.tween_property(button, "modulate", faded, 0.2)


func _pulse_control(control: Control) -> void:
	if not is_instance_valid(control):
		return
	control.pivot_offset = control.size * 0.5
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2(1.045, 1.045), 0.09)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.12)


func _button(value: String, font_size: int) -> Button:
	var button := Button.new()
	_style_button(button, value, font_size)
	return button


func _style_button(button: Button, value: String, font_size: int) -> void:
	button.text = value
	button.custom_minimum_size.y = 58
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	disabled.bg_color = Color("#315348")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color("#fffbe7"))
	button.add_theme_color_override("font_hover_color", Color("#102b2b"))
	button.add_theme_color_override("font_disabled_color", Color("#cde3c3"))


func _uses_item_sprites() -> bool:
	return not task.get("item_sprites", []).is_empty()


func _label(value: String, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	return label
