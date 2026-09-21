extends SceneTree

const TaskCatalog = preload("res://scripts/task_catalog.gd")
const MAX_ICON_SIZE := 512


func _initialize() -> void:
	var failures := 0
	for task_id in TaskCatalog.all_ids():
		var task := TaskCatalog.get_task(task_id)
		var resource_path := str(task.get("icon", ""))
		var disk_path := ProjectSettings.globalize_path(resource_path)
		var image := Image.load_from_file(disk_path)
		if image == null or image.is_empty():
			push_error("Could not load task icon: " + resource_path)
			failures += 1
			continue
		var longest := maxi(image.get_width(), image.get_height())
		if longest > MAX_ICON_SIZE:
			var factor := float(MAX_ICON_SIZE) / float(longest)
			image.resize(roundi(image.get_width() * factor), roundi(image.get_height() * factor), Image.INTERPOLATE_LANCZOS)
			var error := image.save_png(disk_path)
			if error != OK:
				push_error("Could not save task icon: " + resource_path)
				failures += 1
				continue
		print("TASK_ICON %s %dx%d" % [task_id, image.get_width(), image.get_height()])
	quit(0 if failures == 0 else 1)
