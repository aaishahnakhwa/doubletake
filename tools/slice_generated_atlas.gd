extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 5:
		push_error("Usage: source output_dir columns rows name...")
		quit(1)
		return
	var source_path := str(args[0])
	var output_dir := str(args[1])
	var columns := int(args[2])
	var rows := int(args[3])
	var names := args.slice(4)
	var atlas := Image.load_from_file(source_path)
	if atlas == null or atlas.is_empty():
		push_error("Could not load atlas: " + source_path)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	for index in range(names.size()):
		var column := index % columns
		var row := index / columns
		if row >= rows:
			break
		var x0 := int(floor(float(atlas.get_width()) * float(column) / float(columns)))
		var x1 := int(floor(float(atlas.get_width()) * float(column + 1) / float(columns)))
		var y0 := int(floor(float(atlas.get_height()) * float(row) / float(rows)))
		var y1 := int(floor(float(atlas.get_height()) * float(row + 1) / float(rows)))
		var cell := atlas.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
		var used := _alpha_used_rect(cell)
		if used.size == Vector2i.ZERO:
			continue
		used = used.grow(8).intersection(Rect2i(Vector2i.ZERO, cell.get_size()))
		var sprite := cell.get_region(used)
		var max_edge := 224.0
		var scale_factor := minf(max_edge / float(sprite.get_width()), max_edge / float(sprite.get_height()))
		var target_size := Vector2i(
			maxi(1, int(round(float(sprite.get_width()) * scale_factor))),
			maxi(1, int(round(float(sprite.get_height()) * scale_factor)))
		)
		sprite.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
		var canvas := Image.create(256, 256, false, Image.FORMAT_RGBA8)
		canvas.fill(Color.TRANSPARENT)
		var destination := Vector2i((256 - target_size.x) / 2, (256 - target_size.y) / 2)
		canvas.blit_rect(sprite, Rect2i(Vector2i.ZERO, target_size), destination)
		var output_path := output_dir.path_join(str(names[index]) + ".png")
		var error := canvas.save_png(output_path)
		if error != OK:
			push_error("Could not save: " + output_path)
			quit(1)
			return
		print(output_path)
	quit(0)


func _alpha_used_rect(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.025:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
