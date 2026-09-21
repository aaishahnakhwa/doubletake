extends Node2D

const BODY_TEXTURES := [
	# Same index order used by the lobby and authoritative player record.
	preload("res://assets/phase4/bodies/orange.png"),
	preload("res://assets/phase4/bodies/blue.png"),
	preload("res://assets/phase4/bodies/green.png"),
	preload("res://assets/phase4/bodies/red.png"),
	preload("res://assets/phase4/bodies/purple.png"),
	preload("res://assets/phase4/bodies/yellow.png")
]

var victim_name := "Camper"
var context_name := "Close-range"
var reported := false
var color_variant := 0
var body_sprite: Sprite2D


func _ready() -> void:
	body_sprite = Sprite2D.new()
	body_sprite.position = Vector2(0, 4)
	body_sprite.scale = Vector2(0.60, 0.60)
	add_child(body_sprite)
	_refresh_sprite()


func setup(body: Dictionary) -> void:
	victim_name = str(body.get("name", "Camper"))
	var context: Dictionary = body.get("context", {})
	context_name = str(context.get("name", "Close-range"))
	reported = bool(body.get("reported", false))
	color_variant = clampi(int(body.get("color", 0)), 0, BODY_TEXTURES.size() - 1)
	_refresh_sprite()
	queue_redraw()


func _refresh_sprite() -> void:
	if not is_instance_valid(body_sprite):
		return
	body_sprite.texture = BODY_TEXTURES[color_variant]
	body_sprite.modulate = Color("#84949b", 0.68) if reported else Color.WHITE


func _draw() -> void:
	var tint := Color("#6f8790", 0.82) if reported else Color("#e8a24d", 0.95)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-72, -72), "REPORTED" if reported else "BODY", HORIZONTAL_ALIGNMENT_CENTER, 144, 16, tint)
	draw_string(font, Vector2(-92, 78), victim_name + " - " + context_name, HORIZONTAL_ALIGNMENT_CENTER, 184, 13, Color("#fffbe7", 0.9))
