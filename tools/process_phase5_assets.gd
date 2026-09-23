extends SceneTree

const SOURCE_DIR := "C:/Users/saule/.gemini/antigravity/brain/17a13079-7005-4717-99fb-b563640774d7/"
const TARGET_DIR := "res://assets/phase5/"

func _initialize() -> void:
	var dir := DirAccess.open("res://assets")
	if not dir.dir_exists("phase5"):
		dir.make_dir("phase5")
	
	_process_asset("emergency_button_stump_1789985067633.jpg", "meeting_button_stump.png", true)
	_process_asset("player_card_frame_1789985306337.jpg", "player_card_frame.png", true)
	_process_asset("emergency_banner_1789985322401.jpg", "emergency_banner.png", true)
	_process_asset("body_report_banner_1789985415097.jpg", "body_report_banner.png", true)
	_process_asset("eliminated_stamp_1789985397143.jpg", "eliminated_stamp.png", true)
	_process_asset("meeting_backdrop_1789985446467.jpg", "meeting_backdrop.png", false)
	
	print("ASSETS_PROCESSED_SUCCESSFULLY")
	quit(0)

func _process_asset(source_name: String, target_name: String, remove_bg: bool) -> void:
	var src_path := SOURCE_DIR + source_name
	var img := Image.load_from_file(src_path)
	if img == null or img.is_empty():
		push_error("Failed to load: " + src_path)
		return
	
	img.convert(Image.FORMAT_RGBA8)
	
	if remove_bg:
		_flood_fill_transparent(img)
	
	var dst_path := ProjectSettings.globalize_path(TARGET_DIR + target_name)
	img.save_png(dst_path)
	print("Saved %s -> %s (%dx%d)" % [source_name, target_name, img.get_width(), img.get_height()])

func _flood_fill_transparent(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var visited := []
	visited.resize(w * h)
	visited.fill(false)
	
	var queue: Array[Vector2i] = []
	# Seed borders
	for x in range(w):
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, h - 1))
	for y in range(h):
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(w - 1, y))
	
	var head := 0
	while head < queue.size():
		var pt: Vector2i = queue[head]
		head += 1
		var idx := pt.y * w + pt.x
		if visited[idx]:
			continue
		visited[idx] = true
		
		var col: Color = img.get_pixel(pt.x, pt.y)
		# Check if neutral grey/white (checkerboard)
		var max_diff := maxf(absf(col.r - col.g), maxf(absf(col.g - col.b), absf(col.r - col.b)))
		var is_neutral := max_diff < 0.09
		# Also ensure it's not a dark outline (outline is typically < 0.15)
		var is_not_dark_outline := (col.r + col.g + col.b) / 3.0 > 0.22
		
		if is_neutral and is_not_dark_outline:
			img.set_pixel(pt.x, pt.y, Color(0, 0, 0, 0))
			if pt.x > 0: queue.append(Vector2i(pt.x - 1, pt.y))
			if pt.x < w - 1: queue.append(Vector2i(pt.x + 1, pt.y))
			if pt.y > 0: queue.append(Vector2i(pt.x, pt.y - 1))
			if pt.y < h - 1: queue.append(Vector2i(pt.x, pt.y + 1))
