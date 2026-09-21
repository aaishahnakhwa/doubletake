extends SceneTree


func _initialize() -> void:
	for source_path in OS.get_cmdline_user_args():
		var image := Image.load_from_file(ProjectSettings.globalize_path(source_path))
		if image == null or image.is_empty():
			push_error("Could not load " + source_path)
			continue
		print(source_path, " size=", image.get_size(), " corner_alpha=", image.get_pixel(0, 0).a, " used_rect=", image.get_used_rect())
	quit()
