extends Control

signal direction_changed(direction: Vector2)

var active_touch := -1
var mouse_active := false
var direction := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(true)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed and active_touch == -1 and _contains_viewport_point(event.position):
			active_touch = event.index
			_set_pointer(event.position)
		elif not event.pressed and event.index == active_touch:
			active_touch = -1
			_set_direction(Vector2.ZERO)
	elif event is InputEventScreenDrag and event.index == active_touch:
		_set_pointer(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and active_touch == -1:
		if event.pressed and _contains_viewport_point(event.position):
			mouse_active = true
			_set_pointer(event.position)
		elif not event.pressed and mouse_active:
			mouse_active = false
			_set_direction(Vector2.ZERO)
	elif event is InputEventMouseMotion and mouse_active and active_touch == -1:
		_set_pointer(event.position)


func _contains_viewport_point(viewport_point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(make_canvas_position_local(viewport_point))


func _set_pointer(viewport_point: Vector2) -> void:
	var local_point := make_canvas_position_local(viewport_point)
	var radius := minf(size.x, size.y) * 0.31
	_set_direction((local_point - size * 0.5) / radius)


func _set_direction(value: Vector2) -> void:
	direction = value.limit_length(1.0)
	direction_changed.emit(direction)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.37
	draw_circle(center, radius, Color("#102b2b", 0.62))
	draw_arc(center, radius, 0, TAU, 40, Color("#f4d7a7", 0.86), 3, true)
	draw_circle(center + direction * radius * 0.7, radius * 0.42, Color("#a7c957", 0.92))
	draw_circle(center + direction * radius * 0.7, radius * 0.42, Color("#fffbe7", 0.75), false, 2, true)
