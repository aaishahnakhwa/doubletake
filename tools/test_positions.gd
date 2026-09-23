@tool
extends SceneTree

func _init() -> void:
	var map := Image.load_from_file("res://assets/camp_map_3.png")
	map.convert(Image.FORMAT_RGBA8)
	
	# Let's crop from x=550 to 850, y=400 to 620
	# and mark candidate positions:
	# Candidate A: (630, 515) - west of campfire
	# Candidate B: (650, 420) - north-west of campfire near noticeboard
	# Candidate C: (865, 490) - east of campfire
	# Candidate D: (758, 380) - north of campfire near flag
	
	var crop_rect := Rect2i(550, 360, 350, 260)
	var preview := Image.create(crop_rect.size.x, crop_rect.size.y, false, Image.FORMAT_RGBA8)
	preview.blit_rect(map, crop_rect, Vector2i.ZERO)
	
	# Mark candidates with bright colored circles
	_mark(preview, Vector2i(630 - 550, 515 - 360), Color.RED) # West
	_mark(preview, Vector2i(650 - 550, 420 - 360), Color.YELLOW) # NW
	_mark(preview, Vector2i(865 - 550, 490 - 360), Color.CYAN) # East
	_mark(preview, Vector2i(715 - 550, 503 - 360), Color.MAGENTA) # Old position
	
	var out_path := "C:/Users/saule/.gemini/antigravity/brain/17a13079-7005-4717-99fb-b563640774d7/candidate_positions.png"
	preview.save_png(out_path)
	print("Saved candidate preview to: ", out_path)
	quit(0)


func _mark(img: Image, at: Vector2i, col: Color) -> void:
	for dx in range(-6, 7):
		for dy in range(-6, 7):
			if dx*dx + dy*dy <= 36:
				img.set_pixel(at.x + dx, at.y + dy, col)
