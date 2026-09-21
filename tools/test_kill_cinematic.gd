extends SceneTree

const KillCinematicScript = preload("res://scripts/kill_cinematic.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# A simple map-like background makes it obvious that the kill presentation
	# is an overlay and not a replacement screen.
	var map_background := ColorRect.new()
	map_background.color = Color("#6f9b68")
	map_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(map_background)
	var trail := ColorRect.new()
	trail.color = Color("#b59a68")
	trail.position = Vector2(0, 240)
	trail.size = Vector2(1280, 240)
	map_background.add_child(trail)
	var contexts := ["normal", "campfire", "lake", "weak_tree", "workshop"]
	for context_id: String in contexts:
		var cinematic = KillCinematicScript.new()
		cinematic.setup({
			"name": "Test Bot", "color": 1, "killer_color": 3,
			"context": {"id": context_id, "name": context_id.capitalize()}
		})
		root.add_child(cinematic)
		await process_frame
		if context_id == "normal":
			if cinematic.context_prop.visible:
				push_error("Normal kill unexpectedly shows a contextual prop")
				quit(1)
				return
		else:
			if not cinematic.context_prop.visible or cinematic.context_prop.texture == null:
				push_error("Contextual prop did not load for " + context_id)
				quit(1)
				return
		await create_timer(2.65).timeout
		if is_instance_valid(cinematic):
			push_error("Kill cinematic did not release the gameplay overlay for " + context_id)
			quit(1)
			return
	print("Kill cinematic runtime checks: PASS (normal + 4 contextual sequences)")
	quit(0)
