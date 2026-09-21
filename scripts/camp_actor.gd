extends CharacterBody2D

const WorldScript = preload("res://scripts/camp_world.gd")
const SPRITE_SHEET := preload("res://assets/character_sprite_keyed.png")
const SPRITE_SHADER := preload("res://shaders/sprite_background_key.gdshader")
const FRAME_LEFT := [43, 190, 335, 485, 694, 830, 965, 1096, 1228, 1363]
const ROW_TOP := [30, 225, 402, 569, 726, 871]
const ROW_HEIGHT := [164, 154, 150, 149, 142, 137]
# Lobby colours are Orange, Blue, Green, Red, Purple, Yellow, while the
# source sheet rows are Orange, Red, Yellow, Green, Blue, Purple.
const COLOR_TO_SHEET_ROW := [0, 4, 3, 1, 5, 2]
const FRAME_WIDTH := 120
const TARGET_SPRITE_HEIGHT := 94.0

signal route_point_reached(actor)

@export var display_name := "Camper"
@export var is_local := false
@export_range(0, 5) var sprite_variant := 0

var touch_direction := Vector2.ZERO
var route_path := PackedVector2Array()
var route_index := 0
var speed := 155.0
var stuck_time := 0.0
var last_position := Vector2.ZERO
var sprite: Sprite2D
var animation_time := 0.0
var animation_state := "idle"
var active_frame := -1
var input_locked := false
var is_ghost := false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var collider := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 18.0
	collider.shape = circle
	add_child(collider)
	sprite = Sprite2D.new()
	sprite.name = "CamperSprite"
	sprite.texture = SPRITE_SHEET
	sprite.region_enabled = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var key_material := ShaderMaterial.new()
	key_material.shader = SPRITE_SHADER
	sprite.material = key_material
	add_child(sprite)
	_set_frame(0)
	last_position = global_position
	if is_local:
		var camera := Camera2D.new()
		camera.zoom = Vector2(0.8, 0.8)
		camera.position_smoothing_enabled = true
		camera.position_smoothing_speed = 6.0
		camera.limit_left = 0
		camera.limit_top = 0
		camera.limit_right = int(WorldScript.MAP_SIZE.x)
		camera.limit_bottom = int(WorldScript.MAP_SIZE.y)
		add_child(camera)
		camera.make_current()
	queue_redraw()


func set_ghost(value: bool) -> void:
	is_ghost = value
	if is_instance_valid(sprite):
		sprite.modulate = Color("#9fc4d1", 0.58) if value else Color.WHITE
	queue_redraw()


func _physics_process(delta: float) -> void:
	var direction := Vector2.ZERO
	if is_local:
		if not input_locked:
			direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
			if touch_direction.length_squared() > 0.01:
				direction = touch_direction
	else:
		if route_path.is_empty() or route_index >= route_path.size():
			route_point_reached.emit(self)
		else:
			if global_position.distance_to(route_path[route_index]) < 19.0:
				route_index += 1
			if route_index >= route_path.size():
					route_point_reached.emit(self)
			if route_index < route_path.size():
				direction = global_position.direction_to(route_path[route_index])
	var running := is_local and not input_locked and (Input.is_action_pressed("sprint") or touch_direction.length() > 0.72)
	velocity = direction * speed * (1.38 if running else 1.0)
	move_and_slide()
	if not is_local and direction.length_squared() > 0.1:
		if global_position.distance_to(last_position) < 0.8:
			stuck_time += delta
			if stuck_time > 0.8:
				stuck_time = 0.0
				route_point_reached.emit(self)
		else:
			stuck_time = 0.0
	last_position = global_position
	_update_animation(delta, direction, running)
	queue_redraw()


func _update_animation(delta: float, direction: Vector2, running: bool) -> void:
	var moving := direction.length_squared() > 0.02
	var next_state := "run" if moving and running else ("walk" if moving else "idle")
	if next_state != animation_state:
		animation_state = next_state
		animation_time = 0.0
	else:
		animation_time += delta
	var frame := int(animation_time * (14.0 if running else 9.0)) % 6 + 4 if moving else int(animation_time * 4.0) % 4
	_set_frame(frame)
	if direction.x < -0.15:
		sprite.flip_h = true
	elif direction.x > 0.15:
		sprite.flip_h = false


func _set_frame(frame: int) -> void:
	if frame == active_frame:
		return
	active_frame = frame
	var color_index := clampi(sprite_variant, 0, COLOR_TO_SHEET_ROW.size() - 1)
	var row: int = COLOR_TO_SHEET_ROW[color_index]
	var height: int = ROW_HEIGHT[row]
	sprite.region_rect = Rect2(FRAME_LEFT[frame], ROW_TOP[row], FRAME_WIDTH, height)
	var art_scale := TARGET_SPRITE_HEIGHT / float(height - 12)
	sprite.scale = Vector2.ONE * art_scale
	sprite.position = Vector2(0.0, 17.0 - float(height) * art_scale * 0.5)


func _draw() -> void:
	if is_ghost:
		draw_arc(Vector2(0, 13), 34, 0, TAU, 28, Color("#9fc4d1", 0.82), 2.5, true)
	draw_circle(Vector2(0, 17), 24, Color("#122b2b", 0.55))
	if is_local:
		draw_arc(Vector2(0, 13), 31, 0, TAU, 32, Color("#fffbe7"), 2.5, true)
		return
	var font := ThemeDB.fallback_font
	var label_width := maxf(110.0, font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 28.0)
	draw_rect(Rect2(-label_width * 0.5, -122, label_width, 27), Color("#102b2b", 0.9))
	draw_string(font, Vector2(-label_width * 0.5 + 8, -102), display_name, HORIZONTAL_ALIGNMENT_CENTER, label_width - 16, 19, Color("#fffbe7"))
