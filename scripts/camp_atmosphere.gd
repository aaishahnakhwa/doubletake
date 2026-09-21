extends Node2D

const MAP_SCALE := 2.0
const LANTERNS := [
	Vector2(226, 204), Vector2(336, 125), Vector2(553, 126), Vector2(629, 126),
	Vector2(816, 64), Vector2(985, 64), Vector2(1127, 204), Vector2(1306, 204),
	Vector2(138, 420), Vector2(351, 428), Vector2(1183, 438), Vector2(62, 746),
	Vector2(695, 737), Vector2(1081, 711), Vector2(1208, 711),
	Vector2(244, 148), Vector2(617, 350), Vector2(1095, 502), Vector2(1400, 650)
]

var elapsed := 0.0


func _ready() -> void:
	z_index = -3
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = glow_material


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


func _draw() -> void:
	for i in range(LANTERNS.size()):
		var position: Vector2 = LANTERNS[i] * MAP_SCALE
		var pulse := 1.0 + 0.07 * sin(elapsed * (3.1 + float(i % 4) * 0.3) + float(i) * 1.9)
		_draw_glow(position, 52.0 * pulse, 0.42)
	var fire := Vector2(752, 480) * MAP_SCALE
	var fire_pulse := 1.0 + 0.1 * sin(elapsed * 8.0) + 0.04 * sin(elapsed * 13.0)
	_draw_glow(fire, 170.0 * fire_pulse, 0.62)
	for i in range(14):
		var lifetime := fposmod(elapsed * (0.42 + float(i % 3) * 0.09) + float(i) * 0.173, 1.0)
		var drift := sin(elapsed * 2.3 + float(i) * 4.1) * 12.0
		var spark := fire + Vector2(sin(float(i) * 12.7) * 24.0 + drift, -25.0 - lifetime * 100.0)
		draw_circle(spark, 1.5 + (1.0 - lifetime) * 2.0, Color(1.0, 0.46 + lifetime * 0.3, 0.08, (1.0 - lifetime) * 0.42))


func _draw_glow(at: Vector2, radius: float, strength: float) -> void:
	draw_circle(at, radius, Color(1.0, 0.4, 0.08, strength * 0.07))
	draw_circle(at, radius * 0.66, Color(1.0, 0.5, 0.12, strength * 0.11))
	draw_circle(at, radius * 0.36, Color(1.0, 0.67, 0.25, strength * 0.16))
