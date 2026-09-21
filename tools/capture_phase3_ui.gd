extends SceneTree

const TaskMinigameScript = preload("res://scripts/task_minigame.gd")
const TaskCatalog = preload("res://scripts/task_catalog.gd")


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var requested := "firewood"
	for task_id in TaskCatalog.all_ids():
		if task_id in OS.get_cmdline_user_args():
			requested = task_id
			break
	var game = TaskMinigameScript.new()
	game.setup(requested)
	root.add_child(game)
	for _frame in range(10):
		await process_frame
	var capture_suffix := ""
	if requested == "cabins" and "filled" in OS.get_cmdline_user_args():
		for button: Button in game.action_buttons:
			if int(button.drag_payload.get("order", -1)) == 0:
				game._matching_dropped(button.drag_payload)
				break
		capture_suffix = "_filled"
		await create_timer(0.28).timeout
	elif requested == "lanterns" and "fueled" in OS.get_cmdline_user_args():
		game._lantern_work_dropped(game.lantern_fuel_button.drag_payload)
		capture_suffix = "_fueled"
		await process_frame
	elif requested == "lanterns" and "pumped" in OS.get_cmdline_user_args():
		game._lantern_work_dropped(game.lantern_fuel_button.drag_payload)
		for _hit in range(5):
			game._lantern_work_dropped(game.lantern_pump_button.drag_payload)
		capture_suffix = "_pumped"
		await process_frame
	elif requested == "lanterns" and "struck" in OS.get_cmdline_user_args():
		game._lantern_work_dropped(game.lantern_fuel_button.drag_payload)
		for _hit in range(5):
			game._lantern_work_dropped(game.lantern_pump_button.drag_payload)
		game._reset_match_strike(game.ignition_match.drag_payload)
		game._match_strike_motion(game.ignition_match.drag_payload, Vector2(10, 42))
		game._match_strike_motion(game.ignition_match.drag_payload, Vector2(70, 43))
		capture_suffix = "_struck"
		await process_frame
	print("Task panel size=%s minimum=%s position=%s viewport=%s" % [game.panel.size, game.panel.get_combined_minimum_size(), game.panel.position, root.size])
	print("Panel anchors=%s,%s,%s,%s offsets=%s,%s,%s,%s root_control=%s" % [game.panel.anchor_left, game.panel.anchor_top, game.panel.anchor_right, game.panel.anchor_bottom, game.panel.offset_left, game.panel.offset_top, game.panel.offset_right, game.panel.offset_bottom, game.root.size])
	for child in game.content.get_children():
		print("  %s size=%s min=%s flags=%d" % [child.get_class(), child.size, child.get_combined_minimum_size(), child.size_flags_vertical])
	var image := root.get_texture().get_image()
	if image == null:
		push_error("Phase 3 UI capture requires a graphical display driver")
		quit(1)
		return
	var target := "user://phase3_%s%s.png" % [requested, capture_suffix]
	var error := image.save_png(target)
	if error != OK:
		push_error("Could not save Phase 3 preview: %s" % error)
		quit(1)
		return
	print("Preview: " + ProjectSettings.globalize_path(target))
	quit(0)
