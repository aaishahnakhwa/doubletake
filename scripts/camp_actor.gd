extends CharacterBody2D

const WorldScript = preload("res://scripts/camp_world.gd")
const CustomizationCatalog = preload("res://scripts/customization_catalog.gd")
const SPRITE_SHEET := preload("res://assets/character_sprite_keyed.png")
const SPRITE_SHADER := preload("res://shaders/sprite_background_key.gdshader")
const GHOST_TEXTURES := [
	preload("res://assets/phase4/ghosts/ghost_orange.png"),
	preload("res://assets/phase4/ghosts/ghost_blue.png"),
	preload("res://assets/phase4/ghosts/ghost_green.png"),
	preload("res://assets/phase4/ghosts/ghost_red.png"),
	preload("res://assets/phase4/ghosts/ghost_purple.png"),
	preload("res://assets/phase4/ghosts/ghost_yellow.png")
]
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
@export var look_id := "classic"
@export var hat_id := "none"
@export var outfit_id := "none"

var touch_direction := Vector2.ZERO
var route_path := PackedVector2Array()
var route_index := 0
var speed := 155.0
var stuck_time := 0.0
var last_position := Vector2.ZERO
var sprite: Sprite2D
var hat_sprite: Sprite2D = null
var outfit_sprite: Sprite2D = null
var ghost_sprite: Sprite2D
var animation_time := 0.0
var animation_state := "idle"
var active_frame := -1
var input_locked := false
var is_ghost := false
var is_performing_action := false


func _ready() -> void:
	add_to_group("campers")
	collision_layer = 2
	collision_mask = 1
	var collider := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	collider.position = Vector2(0.0, 14.0)
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

	_update_customization_textures()
	
	ghost_sprite = Sprite2D.new()
	ghost_sprite.name = "GhostSprite"
	ghost_sprite.visible = false
	ghost_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(ghost_sprite)
	
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
		sprite.visible = not value
	if is_instance_valid(hat_sprite):
		hat_sprite.visible = not value and hat_sprite.texture != null
	if is_instance_valid(outfit_sprite):
		outfit_sprite.visible = not value and outfit_sprite.texture != null
	if is_instance_valid(ghost_sprite):
		ghost_sprite.visible = value
		if value:
			var color_index := clampi(sprite_variant, 0, GHOST_TEXTURES.size() - 1)
			ghost_sprite.texture = GHOST_TEXTURES[color_index]
			ghost_sprite.scale = Vector2.ONE * (110.0 / float(ghost_sprite.texture.get_height()))
			ghost_sprite.modulate = Color(1.0, 1.0, 1.0, 0.85)
	if value:
		collision_mask = 0
	else:
		collision_mask = 1
	queue_redraw()


func set_customization(p_look_id: String, p_outfit_id: String = "") -> void:
	look_id = p_look_id if CustomizationCatalog.LOOKS.has(p_look_id) else "classic"
	hat_id = look_id
	outfit_id = p_outfit_id
	_update_customization_textures()


func _update_customization_textures() -> void:
	if not is_instance_valid(sprite):
		return
	if look_id != "classic" and CustomizationCatalog.LOOKS.has(look_id):
		var skin_tex := CustomizationCatalog.get_skin_portrait(look_id, sprite_variant)
		if skin_tex != null:
			sprite.texture = skin_tex
			sprite.region_enabled = false
			sprite.material = null
			var art_scale := TARGET_SPRITE_HEIGHT / 136.0
			sprite.scale = Vector2.ONE * art_scale
			sprite.position = Vector2(0.0, 17.0 - 136.0 * art_scale * 0.5)
			return
	# Classic look uses base sprite sheet
	sprite.texture = SPRITE_SHEET
	sprite.region_enabled = true
	var key_material := ShaderMaterial.new()
	key_material.shader = SPRITE_SHADER
	sprite.material = key_material
	_set_frame(0)


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
	if is_performing_action:
		return
	var moving := direction.length_squared() > 0.02
	var next_state := "run" if moving and running else ("walk" if moving else "idle")
	if next_state != animation_state:
		animation_state = next_state
		animation_time = 0.0
	else:
		animation_time += delta
	if is_ghost:
		if is_instance_valid(ghost_sprite):
			var bob_speed := 5.0 if moving else 2.5
			var bob_offset := sin(animation_time * bob_speed) * 4.0
			ghost_sprite.position = Vector2(0.0, -32.0 + bob_offset)
			if direction.x < -0.15:
				ghost_sprite.flip_h = true
			elif direction.x > 0.15:
				ghost_sprite.flip_h = false
		return
	if look_id != "classic":
		var bob := sin(animation_time * (14.0 if running else 9.0)) * (2.2 if moving else 0.6)
		var art_scale := TARGET_SPRITE_HEIGHT / 136.0
		sprite.position = Vector2(0.0, 17.0 - 136.0 * art_scale * 0.5 + (bob if moving else 0.0))
		sprite.rotation = sin(animation_time * (14.0 if running else 9.0)) * 0.04 if moving else 0.0
	else:
		var frame := int(animation_time * (14.0 if running else 9.0)) % 6 + 4 if moving else int(animation_time * 4.0) % 4
		_set_frame(frame)
	if direction.x < -0.15:
		sprite.flip_h = true
	elif direction.x > 0.15:
		sprite.flip_h = false


func _set_frame(frame: int) -> void:
	if look_id != "classic":
		return
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
		draw_arc(Vector2(0, 13), 34, 0, TAU, 28, Color("#9fc4d1", 0.4), 2.5, true)
		draw_circle(Vector2(0, 17), 16, Color("#122b2b", 0.25))
	else:
		draw_circle(Vector2(0, 17), 24, Color("#122b2b", 0.55))
	if is_local:
		draw_arc(Vector2(0, 13), 31, 0, TAU, 32, Color("#fffbe7") if not is_ghost else Color("#9fc4d1", 0.8), 2.5, true)
		return
	var font := ThemeDB.fallback_font
	var label_width := maxf(110.0, font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x + 28.0)
	var label_bg := Color("#102b2b", 0.55) if is_ghost else Color("#102b2b", 0.9)
	var text_col := Color("#9fc4d1", 0.8) if is_ghost else Color("#fffbe7")
	draw_rect(Rect2(-label_width * 0.5, -122, label_width, 27), label_bg)
	draw_string(font, Vector2(-label_width * 0.5 + 8, -102), display_name, HORIZONTAL_ALIGNMENT_CENTER, label_width - 16, 19, text_col)


func play_kill_strike(target_position: Vector2) -> void:
	if not is_instance_valid(sprite):
		return
	is_performing_action = true
	var dir := (target_position - global_position).normalized()
	if dir.length_squared() > 0.01:
		if dir.x < -0.15:
			sprite.flip_h = true
		elif dir.x > 0.15:
			sprite.flip_h = false

	# Set strike action frame (running forward strike frame)
	_set_frame(5)

	var orig_pos := sprite.position
	var orig_scale := sprite.scale
	var lunge_offset := dir * 26.0

	var tween := create_tween()
	# Fast forward thrust towards victim
	tween.tween_property(sprite, "position", orig_pos + lunge_offset, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sprite, "scale", orig_scale * Vector2(1.25, 0.85), 0.07)
	if is_instance_valid(hat_sprite) and hat_sprite.visible:
		tween.parallel().tween_property(hat_sprite, "position", orig_pos + lunge_offset, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(hat_sprite, "scale", orig_scale * Vector2(1.25, 0.85), 0.07)
	if is_instance_valid(outfit_sprite) and outfit_sprite.visible:
		tween.parallel().tween_property(outfit_sprite, "position", orig_pos + lunge_offset, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(outfit_sprite, "scale", orig_scale * Vector2(1.25, 0.85), 0.07)

	# Snap back to normal stance
	tween.tween_property(sprite, "position", orig_pos, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(sprite, "scale", orig_scale, 0.14)
	if is_instance_valid(hat_sprite) and hat_sprite.visible:
		tween.parallel().tween_property(hat_sprite, "position", orig_pos, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(hat_sprite, "scale", orig_scale, 0.14)
	if is_instance_valid(outfit_sprite) and outfit_sprite.visible:
		tween.parallel().tween_property(outfit_sprite, "position", orig_pos, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(outfit_sprite, "scale", orig_scale, 0.14)
	tween.tween_callback(func() -> void:
		is_performing_action = false
	)


func play_death_reaction(from_position: Vector2) -> void:
	if not is_instance_valid(sprite):
		return
	is_performing_action = true
	visible = true
	var dir := (global_position - from_position).normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2.DOWN
	var orig_pos := sprite.position
	var orig_scale := sprite.scale

	# Flash red and knockback
	sprite.modulate = Color(2.5, 0.3, 0.3)
	if is_instance_valid(hat_sprite): hat_sprite.modulate = Color(2.5, 0.3, 0.3)
	if is_instance_valid(outfit_sprite): outfit_sprite.modulate = Color(2.5, 0.3, 0.3)
	var rot_target := deg_to_rad(-25.0 if dir.x >= 0 else 25.0)
	var tween := create_tween()
	tween.tween_property(sprite, "position", orig_pos + dir * 20.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(sprite, "rotation", rot_target, 0.12)
	if is_instance_valid(hat_sprite) and hat_sprite.visible:
		tween.parallel().tween_property(hat_sprite, "position", orig_pos + dir * 20.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(hat_sprite, "rotation", rot_target, 0.12)
	if is_instance_valid(outfit_sprite) and outfit_sprite.visible:
		tween.parallel().tween_property(outfit_sprite, "position", orig_pos + dir * 20.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(outfit_sprite, "rotation", rot_target, 0.12)

	# Collapse & fade out
	tween.tween_property(sprite, "modulate:a", 0.0, 0.22)
	tween.parallel().tween_property(sprite, "scale", orig_scale * 0.60, 0.22)
	if is_instance_valid(hat_sprite) and hat_sprite.visible:
		tween.parallel().tween_property(hat_sprite, "modulate:a", 0.0, 0.22)
		tween.parallel().tween_property(hat_sprite, "scale", orig_scale * 0.60, 0.22)
	if is_instance_valid(outfit_sprite) and outfit_sprite.visible:
		tween.parallel().tween_property(outfit_sprite, "modulate:a", 0.0, 0.22)
		tween.parallel().tween_property(outfit_sprite, "scale", orig_scale * 0.60, 0.22)

	tween.tween_callback(func() -> void:
		visible = false
		is_performing_action = false
		if is_instance_valid(sprite):
			sprite.position = orig_pos
			sprite.scale = orig_scale
			sprite.rotation = 0.0
			sprite.modulate = Color.WHITE
		if is_instance_valid(hat_sprite):
			hat_sprite.position = orig_pos
			hat_sprite.scale = orig_scale
			hat_sprite.rotation = 0.0
			hat_sprite.modulate = Color.WHITE
		if is_instance_valid(outfit_sprite):
			outfit_sprite.position = orig_pos
			outfit_sprite.scale = orig_scale
			outfit_sprite.rotation = 0.0
			outfit_sprite.modulate = Color.WHITE
	)


func shake_camera(intensity: float = 6.0, duration: float = 0.22) -> void:
	var cam: Camera2D = null
	for child in get_children():
		if child is Camera2D:
			cam = child
			break
	if not is_instance_valid(cam):
		return
	var tween := create_tween()
	var step_time := 0.04
	var count := int(duration / step_time)
	var cur_intensity := intensity
	for i in range(count):
		var offset := Vector2(randf_range(-cur_intensity, cur_intensity), randf_range(-cur_intensity, cur_intensity))
		tween.tween_property(cam, "offset", offset, step_time)
		cur_intensity *= 0.72
	tween.tween_property(cam, "offset", Vector2.ZERO, step_time)

