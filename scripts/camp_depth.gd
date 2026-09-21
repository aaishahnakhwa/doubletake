extends Node2D

const WorldScript = preload("res://scripts/camp_world.gd")


func _ready() -> void:
	z_index = 5
	queue_redraw()


func _draw() -> void:
	# Repaint only front-facing wall strips over actors. The source map is flat,
	# but this gives feet a real foreground wall when crossing into a room.
	for room in WorldScript.ROOMS:
		var rect: Rect2 = room["rect"]
		var top := rect.end.y - 9.0
		var width := rect.size.x
		var left := rect.position.x
		var door_side: String = room["door_side"]
		if door_side == "bottom":
			var gap_left: float = room["door_at"] - 24.0
			var gap_right: float = room["door_at"] + 24.0
			_draw_strip(Rect2(left, top, gap_left - left, 18.0))
			_draw_strip(Rect2(gap_right, top, rect.end.x - gap_right, 18.0))
		elif room["name"] == "Boathouse":
			_draw_strip(Rect2(left, top, 248.0 - left, 18.0))
			_draw_strip(Rect2(294.0, top, rect.end.x - 294.0, 18.0))
		else:
			_draw_strip(Rect2(left, top, width, 18.0))


func _draw_strip(source: Rect2) -> void:
	var world_rect := Rect2(source.position * WorldScript.ART_SCALE, source.size * WorldScript.ART_SCALE)
	draw_texture_rect_region(WorldScript.MAP_ART, world_rect, source)
