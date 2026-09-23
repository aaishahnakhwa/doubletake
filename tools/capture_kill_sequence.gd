extends SceneTree

const KillCinematicScript = preload("res://scripts/kill_cinematic.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var background := ColorRect.new()
	background.color = Color("#658f60")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var path := ColorRect.new()
	path.color = Color("#b39a69")
	path.position = Vector2(0, 235)
	path.size = Vector2(1280, 250)
	background.add_child(path)
	var captures := {
		"approach": 0.84,
		"contact": 1.28,
		"blood_streak": 1.72,
		"blood_burst": 1.88,
		"blood_droplets": 2.08,
		"final": 2.22,
	}
	for capture_name: String in captures:
		var cinematic = KillCinematicScript.new()
		cinematic.setup({
			"name": "Blue Camper", "color": 1, "killer_color": 3,
			"context": {"id": "normal", "name": "Normal"}
		})
		root.add_child(cinematic)
		await create_timer(float(captures[capture_name])).timeout
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var error := image.save_png("res://builds/kill_sequence_%s.png" % capture_name)
		if error != OK:
			push_error("Could not save kill preview " + capture_name)
		if is_instance_valid(cinematic):
			cinematic._finish_cinematic()
		await process_frame
	print("Kill sequence previews captured")
	quit(0)
