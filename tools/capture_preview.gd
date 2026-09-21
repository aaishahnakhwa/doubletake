extends SceneTree


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed: PackedScene = load("res://scenes/camp_preview.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	var area := "clearing"
	var preview_spawns := {
		"north": Vector2(160, 50) * 2.0,
		"cabins": Vector2(366, 165) * 2.0,
		"dining": Vector2(925, 94) * 2.0,
		"workshop": Vector2(1251, 172) * 2.0,
		"infirmary": Vector2(1262, 480) * 2.0,
		"lake": Vector2(352, 760) * 2.0,
		"lowerdock": Vector2(275, 900) * 2.0,
		"forest": Vector2(1111, 626) * 2.0
	}
	for choice in preview_spawns:
		if choice in OS.get_cmdline_user_args():
			area = choice
			scene.player.global_position = preview_spawns[choice]
			break
	var camera: Camera2D = root.get_camera_2d()
	if camera != null:
		camera.reset_smoothing()
		if "closeup" in OS.get_cmdline_user_args():
			camera.zoom = Vector2(1.8, 1.8)
	var mobile_preview := not ("desktop" in OS.get_cmdline_user_args())
	scene.hud.mobile_mode = mobile_preview
	scene.hud._layout()
	var expanded_preview := "expanded" in OS.get_cmdline_user_args()
	if expanded_preview:
		scene.hud._toggle_map()
	for i in range(8):
		await process_frame
	var late_preview := "late" in OS.get_cmdline_user_args()
	if late_preview:
		await create_timer(3.0).timeout
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("Preview capture requires a graphical display driver")
		quit(1)
		return
	var target := "user://phase1_%s_%s%s%s%s.png" % ["mobile" if mobile_preview else "desktop", area, "_expanded" if expanded_preview else "", "_late" if late_preview else "", "_closeup" if "closeup" in OS.get_cmdline_user_args() else ""]
	var error := image.save_png(target)
	if error != OK:
		push_error("Could not save preview image: %s" % error)
	else:
		print("Preview: " + ProjectSettings.globalize_path(target))
	quit()
