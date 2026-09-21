extends SceneTree

const LobbyUIScript = preload("res://scripts/lobby_ui.gd")


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var ui: CanvasLayer = LobbyUIScript.new()
	root.add_child(ui)
	var lobby_mode := "lobby" in OS.get_cmdline_user_args()
	if lobby_mode:
		ui.show_lobby("player-host", {
			"room_code": "PINE42",
			"minimum_players": 4,
			"settings": {"max_players": 10, "confirm_ejects": true, "player_names": true, "visual_tasks": true},
			"players": [
				{"player_id": "player-host", "name": "Ayaan", "color": 0, "ready": true, "host": true, "connected": true},
				{"player_id": "player-2", "name": "Riya", "color": 1, "ready": true, "host": false, "connected": true},
				{"player_id": "player-3", "name": "Kabir", "color": 2, "ready": false, "host": false, "connected": true},
				{"player_id": "player-4", "name": "Zoya", "color": 3, "ready": false, "host": false, "connected": true}
			]
		})
	for _frame in range(5):
		await process_frame
	print("UI panel size=%s minimum=%s position=%s" % [ui.lobby_panel.size if lobby_mode else ui.menu_panel.size, ui.lobby_panel.get_combined_minimum_size() if lobby_mode else ui.menu_panel.get_combined_minimum_size(), ui.lobby_panel.position if lobby_mode else ui.menu_panel.position])
	var image := root.get_texture().get_image()
	if image == null:
		push_error("Phase 2 UI capture requires a graphical display driver")
		quit(1)
		return
	var target := "user://phase2_%s.png" % ("lobby" if lobby_mode else "menu")
	var error := image.save_png(target)
	if error != OK:
		push_error("Could not save Phase 2 UI preview: %s" % error)
		quit(1)
		return
	print("Preview: " + ProjectSettings.globalize_path(target))
	quit(0)
