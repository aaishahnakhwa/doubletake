extends Node2D

const WorldScript = preload("res://scripts/camp_world.gd")


func _ready() -> void:
	z_index = 5
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# Repaint front-facing wall strips only when a camper is positioned behind
	# the wall strip inside the room. If campers are outside in front of the wall,
	# the wall strip is skipped so it does not peek through the player's body.
	for room in WorldScript.ROOMS:
		var rect: Rect2 = room["rect"]
		var top := rect.end.y - 9.0
		var width := rect.size.x
		var left := rect.position.x
		var door_side: String = room["door_side"]
		if door_side == "bottom":
			var gap_left: float = room["door_at"] - 24.0
			var gap_right: float = room["door_at"] + 24.0
			_draw_strip_conditional(Rect2(left, top, gap_left - left, 18.0))
			_draw_strip_conditional(Rect2(gap_right, top, rect.end.x - gap_right, 18.0))
		elif room["name"] == "Boathouse":
			_draw_strip_conditional(Rect2(left, top, 248.0 - left, 18.0))
			_draw_strip_conditional(Rect2(294.0, top, rect.end.x - 294.0, 18.0))
		else:
			_draw_strip_conditional(Rect2(left, top, width, 18.0))


func _draw_strip_conditional(source: Rect2) -> void:
	if not _is_camper_behind_strip(source):
		return
	var world_rect := Rect2(source.position * WorldScript.ART_SCALE, source.size * WorldScript.ART_SCALE)
	draw_texture_rect_region(WorldScript.MAP_ART, world_rect, source)


func _is_camper_behind_strip(source: Rect2) -> bool:
	var left_world := source.position.x * WorldScript.ART_SCALE - 16.0
	var right_world := (source.position.x + source.size.x) * WorldScript.ART_SCALE + 16.0
	var bottom_world := (source.position.y + source.size.y) * WorldScript.ART_SCALE
	var campers := get_tree().get_nodes_in_group("campers")
	for node in campers:
		if is_instance_valid(node) and node is Node2D:
			var n2d := node as Node2D
			if n2d.visible:
				var pos := n2d.global_position
				if pos.x >= left_world and pos.x <= right_world:
					if pos.y < bottom_world - 4.0:
						return true
	return false
