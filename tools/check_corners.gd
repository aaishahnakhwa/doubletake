extends SceneTree

const SOURCE_DIR := "C:/Users/saule/.gemini/antigravity/brain/17a13079-7005-4717-99fb-b563640774d7/"
const TARGET_DIR := "res://assets/phase5/"

func _initialize() -> void:
	for banner in ["emergency_banner_1789985322401.jpg", "body_report_banner_1789985415097.jpg", "eliminated_stamp_1789985397143.jpg"]:
		var img := Image.load_from_file(SOURCE_DIR + banner)
		print(banner, " corner 0,0: ", img.get_pixel(0, 0), " corner 16,16: ", img.get_pixel(16, 16))
	quit(0)
