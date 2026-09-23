extends Node2D

# A short, non-graphic five-frame burst which plays at the authoritative body
# position on every client that receives the new body state.
const FRAMES := [
	preload("res://assets/phase4/kill/impact_flat_v3.svg"),
	preload("res://assets/phase4/kill/blood_streak_v4.png"),
	preload("res://assets/phase4/kill/blood_burst_v4.png"),
	preload("res://assets/phase4/kill/blood_droplets_v4.png"),
	preload("res://assets/phase4/kill/ghost_flat_v2.png")
]

var elapsed := 0.0
var sprite: Sprite2D


func _ready() -> void:
	z_index = 20
	sprite = Sprite2D.new()
	sprite.texture = FRAMES[0]
	sprite.scale = _frame_scale(sprite.texture, 0.92)
	var effect_material := CanvasItemMaterial.new()
	effect_material.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	sprite.material = effect_material
	add_child(sprite)


func _process(delta: float) -> void:
	elapsed += delta
	var frame_index := mini(int(elapsed / 0.14), FRAMES.size() - 1)
	sprite.texture = FRAMES[frame_index]
	sprite.scale = _frame_scale(sprite.texture, 0.92 + elapsed * 0.18)
	if elapsed > 0.48:
		sprite.modulate.a = clampf(1.0 - (elapsed - 0.48) / 0.34, 0.0, 1.0)
	if elapsed >= 0.82:
		queue_free()
	queue_redraw()


func _draw() -> void:
	if elapsed < 0.24:
		var alpha := clampf(1.0 - elapsed / 0.24, 0.0, 1.0)
		var slash_color := Color(0.95, 0.12, 0.18, alpha * 0.95)
		var white_core := Color(1.0, 1.0, 1.0, alpha)
		var p1 := Vector2(-42, -36)
		var p2 := Vector2(42, 32)
		draw_line(p1, p2, slash_color, 8.0, true)
		draw_line(p1, p2, white_core, 3.0, true)


func _frame_scale(texture: Texture2D, pulse: float) -> Vector2:
	# Generated effect sheets have different source resolutions. Normalize their
	# on-map footprint so the burst never balloons over nearby campers.
	var longest_edge := maxf(float(texture.get_width()), float(texture.get_height()))
	return Vector2.ONE * (160.0 / longest_edge) * pulse
