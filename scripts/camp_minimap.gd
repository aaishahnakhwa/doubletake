extends Control

const WorldScript = preload("res://scripts/camp_world.gd")

var player_position := Vector2(1504, 1174)
var task_ids: Dictionary = {}
var task_mode := false
var killer_mode := false
var pulse_time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	if task_mode and not task_ids.is_empty():
		pulse_time = fmod(pulse_time + delta, 1.0)
		queue_redraw()


func _draw() -> void:
	var available := Rect2(Vector2(8, 8), size - Vector2(16, 16))
	var aspect: float = WorldScript.SOURCE_SIZE.x / WorldScript.SOURCE_SIZE.y
	var fitted := available.size
	if fitted.x / fitted.y > aspect:
		fitted.x = fitted.y * aspect
	else:
		fitted.y = fitted.x / aspect
	var bounds := Rect2(available.get_center() - fitted * 0.5, fitted)
	draw_texture_rect(WorldScript.MAP_ART, bounds, false, Color(1, 1, 1, 0.82))
	for station in WorldScript.STATION_PIXELS:
		var point: Vector2 = bounds.position + (station["at"] / WorldScript.SOURCE_SIZE) * bounds.size
		var station_task_id := str(station.get("task_id", ""))
		var is_exact_killer_station := str(station.get("name", "")) == str(WorldScript.SABOTAGE_STATIONS.get(station_task_id, ""))
		var is_task := task_ids.has(station_task_id) and (not killer_mode or is_exact_killer_station)
		if task_mode and not is_task:
			continue
		if is_task:
			var pulse := 1.5 + sin(pulse_time * TAU) * 1.2
			draw_circle(point, 6.5 + pulse, Color("#102b2b", 0.92))
			var marker_color := Color("#ff4050") if killer_mode else Color("#ffd166")
			draw_circle(point, 5.0 + pulse, Color(marker_color, 0.35))
			draw_circle(point, 4.6, marker_color)
			draw_circle(point, 1.8, Color("#fffbe7"))
		else:
			draw_circle(point, 2.7, Color("#a7c957"))
	var marker := bounds.position + (player_position / WorldScript.MAP_SIZE) * bounds.size
	draw_circle(marker, 6.0, Color("#102b2b"))
	draw_circle(marker, 3.7, Color("#fffbe7"))
	draw_rect(bounds, Color("#f4d7a7"), false, 2.0)


func update_player_position(at: Vector2) -> void:
	player_position = at
	queue_redraw()


func set_task_ids(ids: Array[String], killer_targets: bool = false) -> void:
	task_mode = true
	killer_mode = killer_targets
	task_ids.clear()
	for task_id in ids:
		task_ids[task_id] = true
	queue_redraw()
