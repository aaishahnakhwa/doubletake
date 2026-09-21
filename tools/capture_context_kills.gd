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
	for context_id: String in ["campfire", "lake", "weak_tree", "workshop"]:
		var cinematic = KillCinematicScript.new()
		cinematic.setup({
			"name": "Blue Camper", "color": 1, "killer_color": 3,
			"context": {"id": context_id, "name": context_id.capitalize()}
		})
		root.add_child(cinematic)
		await create_timer(0.76).timeout
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var error := image.save_png("res://builds/context_kill_%s.png" % context_id)
		if error != OK:
			push_error("Could not save contextual kill preview for " + context_id)
		if is_instance_valid(cinematic):
			cinematic._finish_cinematic()
		await process_frame
	print("Context kill previews captured")
	quit(0)
