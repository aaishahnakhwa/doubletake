class_name CustomizationCatalog
extends RefCounted

const SAVE_PATH := "user://customization.json"

const LOOKS: Dictionary = {
	"classic": {
		"id": "classic",
		"name": "Classic Camper",
		"desc": "Retro camp explorer with backwards cap & tee",
		"icon": "res://assets/skins/icons/classic.png"
	},
	"ranger": {
		"id": "ranger",
		"name": "Camp Ranger",
		"desc": "Wide-brim ranger hat & utility vest with star badge",
		"icon": "res://assets/skins/icons/ranger.png"
	},
	"winter": {
		"id": "winter",
		"name": "Winter Camper",
		"desc": "Warm knit pompom beanie & cozy winter scarf",
		"icon": "res://assets/skins/icons/winter.png"
	},
	"detective": {
		"id": "detective",
		"name": "Camp Detective",
		"desc": "Sleek fedora, collar, red tie & trenchcoat lapels",
		"icon": "res://assets/skins/icons/detective.png"
	},
	"scout": {
		"id": "scout",
		"name": "Wilderness Scout",
		"desc": "Scout beret, neckerchief & merit badge sash",
		"icon": "res://assets/skins/icons/scout.png"
	}
}

const COLOR_NAMES: Array[String] = [
	"orange", "blue", "green", "red", "purple", "yellow"
]

const COLOR_VALUES: Array[Color] = [
	Color("#f3722c"), # orange
	Color("#277da1"), # blue
	Color("#43aa8b"), # green
	Color("#e63946"), # red
	Color("#7209b7"), # purple
	Color("#f9c74f")  # yellow
]

static var _texture_cache: Dictionary = {}


static func get_look(id: String) -> Dictionary:
	return LOOKS.get(id, LOOKS["classic"])


static func get_all_look_ids() -> Array[String]:
	var list: Array[String] = []
	for k in ["classic", "ranger", "winter", "detective", "scout"]:
		list.append(str(k))
	return list


static func get_skin_texture_path(look_id: String, color_idx: int) -> String:
	var c_idx := clampi(color_idx, 0, COLOR_NAMES.size() - 1)
	var c_name := COLOR_NAMES[c_idx]
	var safe_look := look_id if LOOKS.has(look_id) else "classic"
	return "res://assets/skins/%s/%s.png" % [safe_look, c_name]


static func get_skin_portrait(look_id: String, color_idx: int) -> Texture2D:
	var path := get_skin_texture_path(look_id, color_idx)
	return get_texture(path)


static func get_icon_texture(path: String) -> Texture2D:
	return get_texture(path)


static func get_texture(res_path: String) -> Texture2D:
	if res_path.is_empty():
		return null
	if _texture_cache.has(res_path):
		return _texture_cache[res_path]
	if ResourceLoader.exists(res_path):
		var tex := load(res_path) as Texture2D
		if tex != null:
			_texture_cache[res_path] = tex
			return tex
	var global_path := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(global_path):
		var img := Image.load_from_file(global_path)
		if img != null and not img.is_empty():
			var tex := ImageTexture.create_from_image(img)
			_texture_cache[res_path] = tex
			return tex
	return null


# Backward-compatibility helpers
static func get_hat_portrait_texture(_id: String) -> Texture2D:
	return null

static func get_outfit_portrait_texture(_id: String) -> Texture2D:
	return null

static func get_hat_actor_texture(_id: String) -> Texture2D:
	return null

static func get_outfit_actor_texture(_id: String) -> Texture2D:
	return null

static func get_hat(_id: String) -> Dictionary:
	return {}

static func get_outfit(_id: String) -> Dictionary:
	return {}

static func get_all_hat_ids() -> Array[String]:
	return []

static func get_all_outfit_ids() -> Array[String]:
	return []


static func load_local_customization() -> Dictionary:
	var default_data := {
		"color": 0,
		"look": "classic"
	}
	if not FileAccess.file_exists(SAVE_PATH):
		return default_data
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return default_data
	var json_str := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_str) == OK and json.data is Dictionary:
		var loaded: Dictionary = json.data
		var c_idx := clampi(int(loaded.get("color", 0)), 0, 5)
		var look_str := str(loaded.get("look", loaded.get("hat", "classic")))
		if not LOOKS.has(look_str):
			look_str = "classic"
		return {
			"color": c_idx,
			"look": look_str
		}
	return default_data


static func save_local_customization(data: Dictionary) -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return
	var look_str := str(data.get("look", "classic"))
	if not LOOKS.has(look_str):
		look_str = "classic"
	var clean := {
		"color": clampi(int(data.get("color", 0)), 0, 5),
		"look": look_str
	}
	file.store_string(JSON.stringify(clean, "  "))
	file.close()
