extends Node2D

# A short, non-graphic four-frame burst which plays at the authoritative body
# position on every client that receives the new body state.
const FRAMES := [
	preload("res://assets/phase4/kill/impact_flat_v3.svg"),
	preload("res://assets/phase4/kill/splat_flat_v3.svg"),
	preload("res://assets/phase4/kill/splat_flat_v3.svg"),
	preload("res://assets/phase4/kill/ghost_flat_v2.png")
]

var elapsed := 0.0
var sprite: Sprite2D


func _ready() -> void:
	z_index = 20
	sprite = Sprite2D.new()
	sprite.texture = FRAMES[0]
	sprite.scale = Vector2(0.62, 0.62)
	var effect_material := CanvasItemMaterial.new()
	effect_material.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	sprite.material = effect_material
	add_child(sprite)


func _process(delta: float) -> void:
	elapsed += delta
	var frame_index := mini(int(elapsed / 0.17), FRAMES.size() - 1)
	sprite.texture = FRAMES[frame_index]
	sprite.scale = Vector2.ONE * (0.54 + elapsed * 0.2)
	if elapsed > 0.48:
		sprite.modulate.a = clampf(1.0 - (elapsed - 0.48) / 0.34, 0.0, 1.0)
	if elapsed >= 0.82:
		queue_free()
