extends Node2D

const INNER_RADIUS := 485.0
const OUTER_RADIUS := 665.0
const FAR_RADIUS := 4700.0
const SEGMENTS := 48


func _ready() -> void:
	z_index = 90
	queue_redraw()


func _draw() -> void:
	# A dusk vignette leaves nearby movement clear and makes distant paths uncertain.
	for i in range(SEGMENTS):
		var a := TAU * float(i) / float(SEGMENTS)
		var b := TAU * float(i + 1) / float(SEGMENTS)
		var inner_a := Vector2.RIGHT.rotated(a) * INNER_RADIUS
		var inner_b := Vector2.RIGHT.rotated(b) * INNER_RADIUS
		var outer_a := Vector2.RIGHT.rotated(a) * OUTER_RADIUS
		var outer_b := Vector2.RIGHT.rotated(b) * OUTER_RADIUS
		draw_polygon(PackedVector2Array([inner_a, inner_b, outer_b, outer_a]),
			PackedColorArray([
				Color(0.02, 0.07, 0.08, 0.0), Color(0.02, 0.07, 0.08, 0.0),
				Color(0.02, 0.07, 0.08, 0.62), Color(0.02, 0.07, 0.08, 0.62)
			]))
		draw_colored_polygon(PackedVector2Array([
			outer_a, outer_b, Vector2.RIGHT.rotated(b) * FAR_RADIUS,
			Vector2.RIGHT.rotated(a) * FAR_RADIUS
		]), Color(0.02, 0.07, 0.08, 0.62))
