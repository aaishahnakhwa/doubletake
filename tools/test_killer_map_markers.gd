extends SceneTree

const MiniMapScript = preload("res://scripts/camp_minimap.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(900, 560)
	var background := ColorRect.new()
	background.color = Color("#102b2b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var map = MiniMapScript.new()
	map.position = Vector2(60, 60)
	map.size = Vector2(780, 440)
	map.set_task_ids(["generator", "supplies"], true)
	background.add_child(map)
	await create_timer(0.35).timeout
	var image := root.get_texture().get_image()
	var error := image.save_png("res://builds/killer_map_markers_preview.png")
	if error != OK:
		push_error("Could not save Killer map marker preview")
		quit(1)
		return
	print("Killer map marker visual check: PASS")
	quit(0)
