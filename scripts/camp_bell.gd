class_name CampBell
extends AnimatedSprite2D

signal bell_clicked
signal ring_started
signal ring_finished

const CLICK_RADIUS := 65.0

var is_ringing := false
var ring_timer := 0.0
var ring_duration := 1.2

var texture: Texture2D:
	get:
		if sprite_frames and sprite_frames.has_animation("idle") and sprite_frames.get_frame_count("idle") > 0:
			return sprite_frames.get_frame_texture("idle", 0)
		return null


func _init() -> void:
	_setup_frames()


func _setup_frames() -> void:
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
	frames.set_animation_speed("idle", 1.0)
	if f0:
		frames.add_frame("idle", f0)
	
	frames.add_animation("ring")
	frames.set_animation_loop("ring", false)
	frames.set_animation_speed("ring", 8.0)
	# Full 1.25s pendulum sequence: swing left -> center -> swing right -> center -> swing left -> center -> swing right -> settle -> rest
	for f in [f1, f2, f3, f2, f5, f2, f6, f4, f7, f0]:
		if f:
			frames.add_frame("ring", f)
	
	sprite_frames = frames
	animation = "idle"
	frame = 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_click: Vector2 = to_local(get_global_mouse_position())
		if local_click.length() <= CLICK_RADIUS / maxf(scale.x, 0.01):
			bell_clicked.emit()
			get_viewport().set_input_as_handled()


func ring(duration: float = 1.2) -> void:
	is_ringing = true
	ring_duration = duration
	ring_timer = duration
	play("ring")
	ring_started.emit()


func _process(delta: float) -> void:
	if is_ringing:
		ring_timer -= delta
		if ring_timer <= 0.0:
			stop_ringing()


func stop_ringing() -> void:
	if not is_ringing:
		return
	is_ringing = false
	play("idle")
	frame = 0
	ring_finished.emit()
