extends Node2D

const TaskCatalog = preload("res://scripts/task_catalog.gd")

# The supplied 1536 x 1024 camp_map_3 image is the actual visual layer. Geometry is kept
# separate so rooms, furniture, doors and stations remain playable in Godot.
const MAP_ART := preload("res://assets/camp_map_3.png")
const SOURCE_SIZE := Vector2(1536.0, 1024.0)
const ART_SCALE := 2.0
const MAP_SIZE := SOURCE_SIZE * ART_SCALE
const NAV_CELL := 8.0
const SABOTAGE_TEXTURES := {
	"generator": preload("res://assets/phase4/sabotage/generator.png"),
	"radio": preload("res://assets/phase4/sabotage/radio.png"),
	"supplies": preload("res://assets/phase4/sabotage/supplies.png"),
	"lanterns": preload("res://assets/phase4/sabotage/lanterns.png")
}
const SABOTAGE_STATIONS := {
	"generator": "Camp Generator",
	"radio": "Office Radio",
	"supplies": "Supply Shelves",
	"lanterns": "Lodge Lantern"
}

const ROOMS := [
	{"name": "Gate Office", "rect": Rect2(176, 170, 128, 134), "door_side": "bottom", "door_at": 234.0},
	{"name": "Cabin A", "rect": Rect2(307, 85, 123, 146), "door_side": "bottom", "door_at": 388.0},
	{"name": "Cabin B", "rect": Rect2(451, 85, 117, 146), "door_side": "bottom", "door_at": 513.0},
	{"name": "Cabin C", "rect": Rect2(589, 85, 119, 146), "door_side": "bottom", "door_at": 647.0},
	{"name": "Dining Hall", "rect": Rect2(775, 35, 281, 260), "door_side": "bottom", "door_at": 914.0},
	{"name": "Workshop", "rect": Rect2(1081, 112, 253, 201), "door_side": "bottom", "door_at": 1215.0},
	{"name": "Storage", "rect": Rect2(1334, 178, 123, 235), "door_side": "right", "door_at": 286.0},
	{"name": "Lodge", "rect": Rect2(89, 383, 314, 224), "door_side": "top", "door_at": 353.0},
	{"name": "Infirmary", "rect": Rect2(1115, 415, 305, 194), "door_side": "bottom", "door_at": 1295.0},
	{"name": "Boathouse", "rect": Rect2(49, 646, 250, 183), "door_side": "right", "door_at": 700.0},
	# The painted doorway is near x=870; the old x=823 opening left an invisible
	# wall across the real entrance.
	{"name": "South Lodge", "rect": Rect2(677, 650, 288, 202), "door_side": "bottom", "door_at": 870.0},
	{"name": "Cabin D", "rect": Rect2(1019, 701, 121, 155), "door_side": "bottom", "door_at": 1084.0},
	{"name": "Cabin E", "rect": Rect2(1143, 701, 125, 155), "door_side": "bottom", "door_at": 1201.0}
]

const STATION_PIXELS := [
	{"name": "Noticeboard", "task": "Find missing supplies", "task_id": "supplies", "zone": "Campfire Square", "at": Vector2(615, 420)},
	{"name": "Office Radio", "task": "Tune camp radio", "task_id": "radio", "zone": "Gate Office", "at": Vector2(232, 245)},
	{"name": "Cabin A Bunks", "task": "Tidy the cabins", "task_id": "cabins", "zone": "Cabin A", "at": Vector2(367, 177)},
	{"name": "Cabin B Bunks", "task": "Tidy the cabins", "task_id": "cabins", "zone": "Cabin B", "at": Vector2(510, 204)},
	{"name": "Cabin C Bunks", "task": "Tidy the cabins", "task_id": "cabins", "zone": "Cabin C", "at": Vector2(647, 178)},
	{"name": "Dining Counter", "task": "Prepare dinner", "task_id": "dinner", "zone": "Dining Hall", "at": Vector2(916, 92)},
	{"name": "Tool Bench", "task": "Sort workshop tools", "task_id": "tools", "zone": "Workshop", "at": Vector2(1245, 178)},
	{"name": "Camp Generator", "task": "Fix the generator", "task_id": "generator", "zone": "Workshop", "at": Vector2(1215, 286)},
	{"name": "Supply Shelves", "task": "Find missing supplies", "task_id": "supplies", "zone": "Storage", "at": Vector2(1360, 245)},
	{"name": "Lodge Lantern", "task": "Refill lanterns", "task_id": "lanterns", "zone": "Lodge", "at": Vector2(336, 447)},
	{"name": "First-Aid Cabinet", "task": "Find missing supplies", "task_id": "supplies", "zone": "Infirmary", "at": Vector2(1270, 462)},
	{"name": "Lake Cleanup Bin", "task": "Clear lake debris", "task_id": "lake", "zone": "Boathouse", "at": Vector2(140, 740)},
	{"name": "Dock Boards", "task": "Repair dock boards", "task_id": "dock", "zone": "Lake & Dock", "at": Vector2(352, 760)},
	{"name": "Lounge Table", "task": "Find missing supplies", "task_id": "supplies", "zone": "South Lodge", "at": Vector2(820, 770)},
	{"name": "Cabin D Bunks", "task": "Tidy the cabins", "task_id": "cabins", "zone": "Cabin D", "at": Vector2(1053, 781)},
	{"name": "Cabin E Bunks", "task": "Tidy the cabins", "task_id": "cabins", "zone": "Cabin E", "at": Vector2(1165, 781)},
	{"name": "Weak Tree", "task": "Collect firewood", "task_id": "firewood", "zone": "Forest Trail", "at": Vector2(1147, 635)}
]

# These are deliberately non-graphic cartoon set pieces. The host selects the
# context from both players' authoritative positions, never from a client hint.
const ELIMINATION_CONTEXTS := [
	{"id": "campfire", "name": "Campfire", "at": Vector2(758, 503), "radius": 185.0},
	{"id": "weak_tree", "name": "Weak Tree", "at": Vector2(1147, 635), "radius": 180.0},
	# Multiple shoreline anchors share one Lake cinematic. This makes the
	# contextual kill available around the playable dock instead of at one
	# single pixel in the middle of it.
	{"id": "lake", "name": "Lake", "at": Vector2(352, 760), "radius": 250.0},
	{"id": "lake", "name": "Lake", "at": Vector2(255, 790), "radius": 210.0},
	{"id": "lake", "name": "Lake", "at": Vector2(430, 845), "radius": 210.0},
	{"id": "workshop", "name": "Workshop", "at": Vector2(1245, 178), "radius": 190.0}
]

# Local preview campers use outdoor paths; the real multiplayer phase will
# replace these dummy routes with server-authoritative player positions.
const ROUTE_PIXELS := [
	Vector2(760, 606), Vector2(745, 345), Vector2(522, 427), Vector2(997, 426),
	Vector2(536, 265), Vector2(743, 272), Vector2(1075, 284), Vector2(240, 333),
	Vector2(388, 252), Vector2(513, 252), Vector2(647, 252), Vector2(914, 320),
	Vector2(1215, 332), Vector2(1380, 435), Vector2(1295, 625), Vector2(353, 625),
	Vector2(317, 699), Vector2(352, 760), Vector2(544, 855), Vector2(821, 878),
	Vector2(1084, 881), Vector2(1397, 678), Vector2(579, 628), Vector2(1117, 517),
	Vector2(1452, 266)
]

# Only solid furniture receives collision. Small decorative art stays visual.
const FURNITURE := [
	Rect2(332, 130, 23, 54), Rect2(383, 124, 30, 60),
	Rect2(468, 125, 29, 60), Rect2(524, 125, 28, 60),
	Rect2(605, 125, 29, 60), Rect2(662, 125, 29, 60),
	Rect2(823, 134, 76, 51), Rect2(929, 134, 76, 51),
	Rect2(823, 199, 76, 48), Rect2(929, 199, 76, 48),
	Rect2(1169, 209, 73, 42), Rect2(1388, 293, 54, 91),
	Rect2(160, 443, 61, 40), Rect2(204, 539, 75, 31),
	Rect2(1187, 453, 42, 54), Rect2(1325, 453, 45, 60),
	Rect2(750, 696, 63, 41), Rect2(845, 740, 50, 47)
]

const FOREST_BLOCKS := [
	Rect2(0, 0, 1536, 58), Rect2(0, 955, 1536, 69),
	Rect2(0, 385, 60, 265), Rect2(465, 923, 140, 75)
]

# Each circle follows a visible tree crown or dense grove on camp_map_3.
# The older broad rectangles hid walkable dirt paths between these trees.
const TREE_CROWNS := [
	[Vector2(109, 44), 35.0], [Vector2(215, 61), 32.0], [Vector2(300, 54), 28.0],
	[Vector2(541, 40), 33.0], [Vector2(681, 48), 28.0], [Vector2(1120, 48), 34.0],
	[Vector2(1238, 58), 31.0], [Vector2(1361, 92), 31.0],
	[Vector2(270, 143), 26.0], [Vector2(736, 246), 27.0],
	[Vector2(461, 294), 27.0], [Vector2(578, 309), 24.0],
	[Vector2(431, 421), 27.0], [Vector2(539, 394), 20.0],
	[Vector2(948, 411), 28.0], [Vector2(1081, 411), 29.0],
	[Vector2(1153, 399), 25.0],
	[Vector2(1278, 402), 26.0],
	[Vector2(424, 540), 27.0], [Vector2(491, 540), 28.0],
	[Vector2(568, 548), 24.0],
	[Vector2(456, 633), 28.0], [Vector2(545, 639), 27.0],
	[Vector2(667, 636), 27.0], [Vector2(856, 630), 28.0],
	[Vector2(910, 576), 21.0],
	[Vector2(966, 587), 27.0], [Vector2(1000, 559), 27.0],
	[Vector2(1080, 625), 25.0], [Vector2(1190, 641), 26.0],
	[Vector2(1344, 701), 28.0], [Vector2(493, 773), 28.0],
	[Vector2(1297, 860), 25.0],
	[Vector2(1005, 879), 25.0], [Vector2(1260, 882), 24.0],
	[Vector2(737, 929), 26.0], [Vector2(858, 934), 25.0],
	[Vector2(1279, 916), 28.0],
	[Vector2(1378, 922), 29.0], [Vector2(1452, 965), 31.0]
]

const LOG_SEGMENTS := [
	[Vector2(689, 455), Vector2(726, 430), 19.0],
	[Vector2(799, 431), Vector2(837, 458), 19.0],
	[Vector2(662, 499), Vector2(673, 547), 19.0],
	[Vector2(853, 499), Vector2(843, 548), 19.0],
	[Vector2(695, 564), Vector2(729, 583), 19.0],
	[Vector2(788, 583), Vector2(823, 564), 19.0],
	[Vector2(507, 324), Vector2(560, 349), 20.0],
	[Vector2(970, 589), Vector2(1028, 615), 20.0]
]

# Wooden dock boards and bridges override the blue-water pixel mask.
const PLATFORM_RECTS := [
	Rect2(31, 674, 341, 109), Rect2(250, 773, 38, 118),
	Rect2(133, 868, 210, 75), Rect2(380, 887, 220, 55),
	Rect2(548, 767, 56, 158), Rect2(1470, 248, 53, 92),
	Rect2(1467, 394, 57, 167)
]

const PLATFORM_SEGMENTS := [
	[Vector2(1389, 655), Vector2(1459, 662), 46.0],
	[Vector2(1326, 832), Vector2(1400, 886), 49.0]
]

# Shore segments leave gaps for the docks and the two bridges.
const SHORE_SEGMENTS := [
	[Vector2(347, 783), Vector2(424, 829)],
	[Vector2(424, 829), Vector2(537, 927)],
	[Vector2(1508, 0), Vector2(1510, 360)],
	[Vector2(1510, 440), Vector2(1512, 608)],
	[Vector2(1512, 710), Vector2(1515, 1024)]
]

var route_nodes: Array[Vector2] = []
var stations: Array[Dictionary] = []
var solid_rects: Array[Rect2] = []
var solid_segments: Array[Dictionary] = []
var solid_circles: Array[Dictionary] = []
var navigation: AStarGrid2D
var active_task_ids: Dictionary = {}
var active_task_icons: Dictionary = {}
var active_sabotage_ids: Dictionary = {}
var killer_sabotage_ids: Dictionary = {}
var task_markers_enabled := false
var task_marker_time := 0.0


func _ready() -> void:
	var art := Sprite2D.new()
	art.name = "PinewoodCampArt"
	art.texture = MAP_ART
	art.centered = false
	art.scale = Vector2.ONE * ART_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var surface := ShaderMaterial.new()
	surface.shader = preload("res://shaders/camp_surface.gdshader")
	art.material = surface
	art.z_index = -5
	add_child(art)
	for pixel in ROUTE_PIXELS:
		route_nodes.append(pixel * ART_SCALE)
	for source in STATION_PIXELS:
		var station: Dictionary = source.duplicate()
		station["at"] = source["at"] * ART_SCALE
		stations.append(station)
	_build_collisions()
	_build_navigation()
	queue_redraw()


func _process(delta: float) -> void:
	if task_markers_enabled and (not active_task_ids.is_empty() or not active_sabotage_ids.is_empty() or not killer_sabotage_ids.is_empty()):
		task_marker_time = fmod(task_marker_time + delta, 1.0)
		queue_redraw()


func _build_collisions() -> void:
	_add_rect_collider(Rect2(-20, -20, SOURCE_SIZE.x + 40, 20))
	_add_rect_collider(Rect2(-20, SOURCE_SIZE.y, SOURCE_SIZE.x + 40, 20))
	_add_rect_collider(Rect2(-20, 0, 20, SOURCE_SIZE.y))
	_add_rect_collider(Rect2(SOURCE_SIZE.x, 0, 20, SOURCE_SIZE.y))
	for room in ROOMS:
		_add_room_walls(room)
	for rect in FURNITURE:
		_add_rect_collider(rect)
	for rect in FOREST_BLOCKS:
		_add_rect_collider(rect)
	for crown in TREE_CROWNS:
		_add_circle_collider(crown[0], crown[1])
	for log in LOG_SEGMENTS:
		_add_segment_collider(log[0], log[1], log[2])
	for segment in SHORE_SEGMENTS:
		_add_segment_collider(segment[0], segment[1], 13.0)
	_add_water_collisions()
	_add_circle_collider(Vector2(758, 503), 32.0)


func _add_water_collisions() -> void:
	# The image is the only source asset, so sample its lake/river pixels and
	# create narrow collision strips. Wooden docks remain walkable.
	var image: Image = MAP_ART.get_image()
	var cells_x := int(SOURCE_SIZE.x / NAV_CELL)
	var cells_y := int(SOURCE_SIZE.y / NAV_CELL)
	for y in range(cells_y):
		var run_start := -1
		for x in range(cells_x + 1):
			var water := false
			if x < cells_x:
				var point := Vector2(x + 0.5, y + 0.5) * NAV_CELL
				var lake_or_river := (point.x < 570.0 and point.y > 630.0) or (point.x > 1400.0 and point.y > 345.0) or (point.x > 1290.0 and point.y > 800.0)
				if lake_or_river:
					var inside_room := false
					for room in ROOMS:
						if (room["rect"] as Rect2).grow(7.0).has_point(point):
							inside_room = true
							break
					if not inside_room and not _on_platform(point):
						var color := image.get_pixelv(Vector2i(point))
						water = color.b > 0.2 and color.b > color.g * 1.4 and color.b > color.r * 1.5
			if water and run_start < 0:
				run_start = x
			elif not water and run_start >= 0:
				_add_rect_collider(Rect2(run_start * NAV_CELL, y * NAV_CELL, (x - run_start) * NAV_CELL, NAV_CELL))
				run_start = -1


func _on_platform(point: Vector2) -> bool:
	for rect in PLATFORM_RECTS:
		if rect.has_point(point):
			return true
	for segment in PLATFORM_SEGMENTS:
		var a: Vector2 = segment[0]
		var b: Vector2 = segment[1]
		var along := b - a
		var t := clampf((point - a).dot(along) / along.length_squared(), 0.0, 1.0)
		if point.distance_to(a + along * t) < segment[2] * 0.5:
			return true
	return false


func _add_room_walls(room: Dictionary) -> void:
	var rect: Rect2 = room["rect"]
	var door_side: String = room["door_side"]
	var door_at: float = room["door_at"]
	# Keep entrances wider than the camper collision shape so diagonal movement
	# and touch controls do not snag on invisible wall corners.
	var half_gap := 34.0
	var wall := 9.0
	var left := rect.position.x
	var right := rect.end.x
	var top := rect.position.y
	var bottom := rect.end.y
	if door_side == "top":
		_add_rect_collider(Rect2(left, top - wall * 0.5, door_at - half_gap - left, wall))
		_add_rect_collider(Rect2(door_at + half_gap, top - wall * 0.5, right - door_at - half_gap, wall))
	else:
		_add_rect_collider(Rect2(left, top - wall * 0.5, rect.size.x, wall))
	if door_side == "bottom":
		_add_rect_collider(Rect2(left, bottom - wall * 0.5, door_at - half_gap - left, wall))
		_add_rect_collider(Rect2(door_at + half_gap, bottom - wall * 0.5, right - door_at - half_gap, wall))
	elif room["name"] == "Boathouse":
		# The boathouse opens onto the narrow south dock near x=270.
		_add_rect_collider(Rect2(left, bottom - wall * 0.5, 248.0 - left, wall))
		_add_rect_collider(Rect2(294.0, bottom - wall * 0.5, right - 294.0, wall))
	else:
		_add_rect_collider(Rect2(left, bottom - wall * 0.5, rect.size.x, wall))
	if door_side == "left":
		_add_rect_collider(Rect2(left - wall * 0.5, top, wall, door_at - half_gap - top))
		_add_rect_collider(Rect2(left - wall * 0.5, door_at + half_gap, wall, bottom - door_at - half_gap))
	else:
		_add_rect_collider(Rect2(left - wall * 0.5, top, wall, rect.size.y))
	if door_side == "right":
		_add_rect_collider(Rect2(right - wall * 0.5, top, wall, door_at - half_gap - top))
		_add_rect_collider(Rect2(right - wall * 0.5, door_at + half_gap, wall, bottom - door_at - half_gap))
	else:
		_add_rect_collider(Rect2(right - wall * 0.5, top, wall, rect.size.y))


func _add_rect_collider(source_rect: Rect2) -> void:
	solid_rects.append(source_rect)
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = source_rect.get_center() * ART_SCALE
	var shape := RectangleShape2D.new()
	shape.size = source_rect.size * ART_SCALE
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


func _add_segment_collider(a: Vector2, b: Vector2, width: float) -> void:
	solid_segments.append({"a": a, "b": b, "width": width})
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = (a + b) * 0.5 * ART_SCALE
	body.rotation = (b - a).angle()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(a.distance_to(b), width) * ART_SCALE
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


func _add_circle_collider(source_at: Vector2, radius: float) -> void:
	solid_circles.append({"at": source_at, "radius": radius})
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = source_at * ART_SCALE
	var shape := CircleShape2D.new()
	shape.radius = radius * ART_SCALE
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


func _build_navigation() -> void:
	navigation = AStarGrid2D.new()
	navigation.region = Rect2i(0, 0, int(SOURCE_SIZE.x / NAV_CELL), int(SOURCE_SIZE.y / NAV_CELL))
	navigation.cell_size = Vector2.ONE * NAV_CELL * ART_SCALE
	navigation.offset = navigation.cell_size * 0.5
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	navigation.update()
	for y in range(navigation.region.size.y):
		for x in range(navigation.region.size.x):
			var source_point := Vector2(x + 0.5, y + 0.5) * NAV_CELL
			if _blocked_for_camper(source_point):
				navigation.set_point_solid(Vector2i(x, y))


func _blocked_for_camper(source_point: Vector2) -> bool:
	const CLEARANCE := 10.0
	for rect in solid_rects:
		if rect.grow(CLEARANCE).has_point(source_point):
			return true
	for segment in solid_segments:
		var a: Vector2 = segment["a"]
		var b: Vector2 = segment["b"]
		var along := b - a
		var t := clampf((source_point - a).dot(along) / along.length_squared(), 0.0, 1.0)
		if source_point.distance_to(a + along * t) < segment["width"] * 0.5 + CLEARANCE:
			return true
	for circle in solid_circles:
		if source_point.distance_to(circle["at"]) < circle["radius"] + CLEARANCE:
			return true
	return false


func _cell_near(world_point: Vector2) -> Vector2i:
	var source_point := world_point / ART_SCALE
	var requested := Vector2i(floori(source_point.x / NAV_CELL), floori(source_point.y / NAV_CELL))
	for radius in range(6):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var candidate := requested + Vector2i(dx, dy)
				if navigation.is_in_boundsv(candidate) and not navigation.is_point_solid(candidate):
					return candidate
	return Vector2i(-1, -1)


func find_path(from_world: Vector2, to_world: Vector2) -> PackedVector2Array:
	var from_id := _cell_near(from_world)
	var to_id := _cell_near(to_world)
	if from_id.x < 0 or to_id.x < 0:
		return PackedVector2Array()
	var points := navigation.get_point_path(from_id, to_id)
	if points.is_empty():
		return points
	points.insert(0, from_world)
	return points


func _draw() -> void:
	for station in stations:
		var at: Vector2 = station["at"]
		var is_task := active_task_ids.has(str(station.get("task_id", "")))
		var sabotage_id := str(station.get("task_id", ""))
		var correct_sabotage_station := str(station.get("name", "")) == str(SABOTAGE_STATIONS.get(sabotage_id, ""))
		var is_sabotaged := active_sabotage_ids.has(sabotage_id) and correct_sabotage_station
		var is_killer_target := killer_sabotage_ids.has(sabotage_id) and correct_sabotage_station
		if task_markers_enabled and not is_task and not is_sabotaged and not is_killer_target:
			continue
		if is_task:
			var pulse := 5.0 + sin(task_marker_time * TAU) * 4.0
			draw_circle(at, 29.0 + pulse, Color("#ffd166", 0.18))
			draw_arc(at, 25.0 + pulse, 0.0, TAU, 32, Color("#ffd166", 0.9), 4.0, true)
			draw_circle(at, 27.0, Color("#102b2b", 0.92))
			var task_id := str(station.get("task_id", ""))
			if active_task_icons.has(task_id):
				draw_texture_rect(active_task_icons[task_id], Rect2(at - Vector2(25, 25), Vector2(50, 50)), false)
			var font := ThemeDB.fallback_font
			draw_string(font, at + Vector2(-31, -34 - pulse), "TASK", HORIZONTAL_ALIGNMENT_CENTER, 62, 17, Color("#fffbe7"))
		elif is_killer_target:
			var target_pulse := 6.0 + sin(task_marker_time * TAU) * 4.0
			draw_circle(at, 34.0 + target_pulse, Color("#e63946", 0.22))
			draw_arc(at, 29.0 + target_pulse, 0.0, TAU, 32, Color("#ff4d5a", 0.96), 4.0, true)
			draw_circle(at, 29.0, Color("#26090d", 0.94))
			if SABOTAGE_TEXTURES.has(sabotage_id):
				draw_texture_rect(SABOTAGE_TEXTURES[sabotage_id], Rect2(at - Vector2(27, 27), Vector2(54, 54)), false)
			var target_font := ThemeDB.fallback_font
			draw_string(target_font, at + Vector2(-48, -39 - target_pulse), "TARGET", HORIZONTAL_ALIGNMENT_CENTER, 96, 16, Color("#ffe0a6"))
		else:
			draw_circle(at, 17, Color("#102b2b", 0.83))
			draw_circle(at, 12, Color("#a7c957", 0.95))
			draw_circle(at, 5, Color("#fffbe7"))
		if is_sabotaged and SABOTAGE_TEXTURES.has(sabotage_id):
			var pulse := 4.0 + sin(task_marker_time * TAU) * 3.0
			draw_circle(at, 43.0 + pulse, Color("#e63946", 0.20))
			draw_texture_rect(SABOTAGE_TEXTURES[sabotage_id], Rect2(at - Vector2(38, 38), Vector2(76, 76)), false)
			var warning_font := ThemeDB.fallback_font
			draw_string(warning_font, at + Vector2(-52, -48 - pulse), "SABOTAGE", HORIZONTAL_ALIGNMENT_CENTER, 104, 15, Color("#ffcf70"))


func set_active_task_ids(ids: Array[String]) -> void:
	task_markers_enabled = true
	active_task_ids.clear()
	active_task_icons.clear()
	for task_id in ids:
		active_task_ids[task_id] = true
		var task := TaskCatalog.get_task(task_id)
		var icon_path := str(task.get("icon", ""))
		if not icon_path.is_empty():
			active_task_icons[task_id] = load(icon_path)
	queue_redraw()


func set_active_sabotage_ids(ids: Array[String]) -> void:
	active_sabotage_ids.clear()
	for sabotage_id in ids:
		active_sabotage_ids[sabotage_id] = true
	queue_redraw()


func set_killer_sabotage_ids(ids: Array[String]) -> void:
	task_markers_enabled = true
	killer_sabotage_ids.clear()
	for sabotage_id in ids:
		killer_sabotage_ids[sabotage_id] = true
	queue_redraw()


func get_zone_names() -> Array[String]:
	var names: Array[String] = ["Campfire Square", "Lake & Dock", "Forest Trail"]
	for room in ROOMS:
		names.append(room["name"])
	return names


func get_zone_at(at: Vector2) -> String:
	var source := at / ART_SCALE
	for room in ROOMS:
		if (room["rect"] as Rect2).has_point(source):
			return room["name"]
	if source.x < 570 and source.y > 602:
		return "Lake & Dock"
	if source.distance_to(Vector2(758, 503)) < 270:
		return "Campfire Square"
	return "Forest Trail"


func get_nearest_station(at: Vector2, radius: float = 95.0) -> Dictionary:
	var nearest: Dictionary = {}
	var distance := radius
	for station in stations:
		var current: float = at.distance_to(station["at"])
		if current < distance:
			nearest = station
			distance = current
	return nearest


func get_contextual_elimination(killer_at: Vector2, victim_at: Vector2, radius: float = 145.0) -> Dictionary:
	var nearest: Dictionary = {"id": "normal", "name": "Close-range"}
	var best_score := 1.0
	for source: Dictionary in ELIMINATION_CONTEXTS:
		var at: Vector2 = source["at"] * ART_SCALE
		var combined_distance := maxf(killer_at.distance_to(at), victim_at.distance_to(at))
		var context_radius := float(source.get("radius", radius))
		var score := combined_distance / context_radius
		if score <= best_score:
			best_score = score
			nearest = {"id": source["id"], "name": source["name"]}
	return nearest


func get_spawn_point() -> Vector2:
	return Vector2(760, 606) * ART_SCALE
