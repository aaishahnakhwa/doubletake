extends SceneTree

const TaskMinigameScript = preload("res://scripts/task_minigame.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game = TaskMinigameScript.new()
	game.setup("generator", true)
	root.add_child(game)
	await create_timer(0.45).timeout
	var image := root.get_texture().get_image()
	var error := image.save_png("res://builds/sabotage_minigame_preview.png")
	if error != OK:
		push_error("Could not save sabotage minigame preview")
		quit(1)
		return
	print("Sabotage minigame visual check: PASS")
	quit(0)
