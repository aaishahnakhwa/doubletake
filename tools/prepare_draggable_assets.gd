extends SceneTree

const OUTPUT_SIZE := 256
const INNER_SIZE := 220
const ALPHA_CUTOFF := 0.02

const ATLASES := [
	{
		"path": "res://assets/task_draggables/atlases/generator.png",
		"columns": 2,
		"rows": 2,
		"group": "generator",
		"items": ["fuse", "belt", "fuel", "start"]
	},
	{
		"path": "res://assets/task_draggables/atlases/dinner.png",
		"columns": 2,
		"rows": 2,
		"group": "dinner",
		"items": ["water", "vegetables", "spices", "stir"]
	},
	{
		"path": "res://assets/task_draggables/atlases/cabins.png",
		"columns": 3,
		"rows": 2,
		"group": "cabins",
		"items": ["blanket", "boots", "pillow", "bag", "book"]
	},
	{
		"path": "res://assets/task_draggables/atlases/tools.png",
		"columns": 3,
		"rows": 2,
		"group": "tools",
		"items": ["hammer", "saw", "wrench", "pliers", "tape"]
	},
	{
		"path": "res://assets/task_draggables/atlases/lake.png",
		"columns": 3,
		"rows": 2,
		"group": "lake",
		"items": ["bottle", "can", "rope", "bag", "net"]
	},
	{
		"path": "res://assets/task_draggables/atlases/firewood.png",
		"columns": 3,
		"rows": 2,
		"group": "firewood",
		"items": ["log", "twigs", "branch", "kindling", "bark"]
	},
	{
		"path": "res://assets/task_draggables/atlases/lanterns.png",
		"columns": 2,
		"rows": 2,
		"group": "lanterns",
		"items": ["lantern", "pump", "fuel", "matches"]
	},
	{
		"path": "res://assets/task_draggables/atlases/dock.png",
		"columns": 2,
		"rows": 2,
		"group": "dock",
		"items": ["hammer", "nail", "cracked_plank", "repaired_plank"]
	},
	{
		"path": "res://assets/task_draggables/atlases/radio.png",
		"columns": 2,
		"rows": 2,
		"group": "radio",
		"items": ["radio", "knob", "needle", "signal"]
	},
	{
		"path": "res://assets/task_draggables/atlases/supplies.png",
		"columns": 3,
		"rows": 2,
		"group": "supplies",
		"items": ["first_aid", "batteries", "matches", "canteen", "compass", "soap"]
	},
	{
		"path": "res://assets/task_draggables/atlases/match_states.png",
		"columns": 2,
		"rows": 1,
		"group": "lanterns",
		"items": ["match_unlit", "match_lit"]
	}
]


func _initialize() -> void:
	var failures := 0
	for atlas: Dictionary in ATLASES:
		failures += _process_atlas(atlas)
	quit(0 if failures == 0 else 1)


func _process_atlas(spec: Dictionary) -> int:
	var source_path := str(spec["path"])
	var image := Image.load_from_file(ProjectSettings.globalize_path(source_path))
	if image == null or image.is_empty():
		push_error("Could not load draggable atlas: " + source_path)
		return 1
	image.convert(Image.FORMAT_RGBA8)

	var columns := int(spec["columns"])
	var rows := int(spec["rows"])
	var cell_width := image.get_width() / columns
	var cell_height := image.get_height() / rows
	var output_dir := "res://assets/task_draggables/%s" % str(spec["group"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))

	var failures := 0
	var names: Array = spec["items"]
	for index in range(names.size()):
		var column := index % columns
		var row := index / columns
		var cell := image.get_region(Rect2i(column * cell_width, row * cell_height, cell_width, cell_height))
		var bounds := _opaque_bounds(cell)
		if bounds.size.x <= 0 or bounds.size.y <= 0:
			push_error("Empty atlas cell for %s/%s" % [spec["group"], names[index]])
			failures += 1
			continue

		var sprite := cell.get_region(bounds)
		var scale_factor := minf(float(INNER_SIZE) / float(sprite.get_width()), float(INNER_SIZE) / float(sprite.get_height()))
		var target_width := maxi(1, roundi(sprite.get_width() * scale_factor))
		var target_height := maxi(1, roundi(sprite.get_height() * scale_factor))
		sprite.resize(target_width, target_height, Image.INTERPOLATE_LANCZOS)

		var canvas := Image.create(OUTPUT_SIZE, OUTPUT_SIZE, false, Image.FORMAT_RGBA8)
		canvas.fill(Color(0.0, 0.0, 0.0, 0.0))
		var destination := Vector2i((OUTPUT_SIZE - target_width) / 2, (OUTPUT_SIZE - target_height) / 2)
		canvas.blend_rect(sprite, Rect2i(Vector2i.ZERO, sprite.get_size()), destination)

		var output_path := "%s/%s.png" % [output_dir, str(names[index])]
		var error := canvas.save_png(ProjectSettings.globalize_path(output_path))
		if error != OK:
			push_error("Could not save draggable sprite: " + output_path)
			failures += 1
			continue
		print("DRAGGABLE %s %dx%d" % [output_path, OUTPUT_SIZE, OUTPUT_SIZE])
	return failures


func _opaque_bounds(image: Image) -> Rect2i:
	var minimum := Vector2i(image.get_width(), image.get_height())
	var maximum := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= ALPHA_CUTOFF:
				continue
			minimum.x = mini(minimum.x, x)
			minimum.y = mini(minimum.y, y)
			maximum.x = maxi(maximum.x, x)
			maximum.y = maxi(maximum.y, y)
	if maximum.x < minimum.x or maximum.y < minimum.y:
		return Rect2i()
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)
