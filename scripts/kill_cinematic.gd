extends CanvasLayer

signal finished

const KILLER_ATTACK_ATLAS := preload("res://assets/phase4/kill/killer_attack_atlas.png")
const VICTIM_DEFEAT_ATLAS := preload("res://assets/phase4/kill/victim_defeat_atlas.png")
const CHARACTER_SHEET := preload("res://assets/character_sprite_keyed.png")
const CHARACTER_SHADER := preload("res://shaders/sprite_background_key.gdshader")
const FLAT_FX_FRAMES := [
	preload("res://assets/phase4/kill/impact_flat_v3.svg"),
	preload("res://assets/phase4/kill/impact_flat_v3.svg"),
	preload("res://assets/phase4/kill/splat_flat_v3.svg"),
	preload("res://assets/phase4/kill/ghost_flat_v2.png")
]
const CONTEXT_TEXTURES := {
	"campfire": preload("res://assets/phase4/kill/contexts/campfire_flat_v2.png"),
	"lake": preload("res://assets/phase4/kill/contexts/lake_splash_flat_v2.png"),
	"weak_tree": preload("res://assets/phase4/kill/contexts/falling_tree_flat_v2.png"),
	"workshop": preload("res://assets/phase4/kill/contexts/workshop_cart_flat_v3.svg")
}
const CHARACTER_FRAME_LEFT := [43, 190, 335, 485, 694, 830, 965, 1096, 1228, 1363]
const CHARACTER_ROW_TOP := [30, 225, 402, 569, 726, 871]
const CHARACTER_ROW_HEIGHT := [164, 154, 150, 149, 142, 137]
# Lobby order is Orange, Blue, Green, Red, Purple, Yellow. The source sheet
# rows are Orange, Red, Yellow, Green, Blue, Purple.
const COLOR_TO_SHEET_ROW := [0, 4, 3, 1, 5, 2]

var body_state: Dictionary = {}
var root: Control
var screen_tint: ColorRect
var band: Panel
var attacker: TextureRect
var victim: TextureRect
var context_prop: TextureRect
var effect: TextureRect
var flash: ColorRect
var title: Label
var victim_label: Label
var attacker_target := Vector2.ZERO
var victim_target := Vector2.ZERO
var killer_color := 0
var victim_color := 0
var context_id := "normal"
var has_finished := false


func setup(body: Dictionary) -> void:
	body_state = body.duplicate(true)


func _ready() -> void:
	layer = 90
	killer_color = clampi(int(body_state.get("killer_color", 0)), 0, 5)
	victim_color = clampi(int(body_state.get("color", 0)), 0, 5)
	var context: Dictionary = body_state.get("context", {})
	context_id = str(context.get("id", "normal"))
	if context_id == "dock":
		context_id = "lake"

	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# The game remains visible. This tint separates the short combat beat from
	# the live map without turning it into a different screen.
	screen_tint = ColorRect.new()
	screen_tint.color = Color(0.035, 0.005, 0.01, 0.46)
	screen_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen_tint)

	band = Panel.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var band_style := StyleBoxFlat.new()
	band_style.bg_color = Color(0.10, 0.012, 0.022, 0.90)
	band_style.border_color = Color(0.96, 0.10, 0.18, 1.0)
	band_style.border_width_top = 5
	band_style.border_width_bottom = 5
	band_style.shadow_color = Color(0, 0, 0, 0.62)
	band_style.shadow_size = 20
	band.add_theme_stylebox_override("panel", band_style)
	band.clip_contents = true
	root.add_child(band)

	attacker = _action_view(KILLER_ATTACK_ATLAS, killer_color, 0)
	victim = _action_view(VICTIM_DEFEAT_ATLAS, victim_color, 0)
	band.add_child(attacker)
	band.add_child(victim)

	context_prop = TextureRect.new()
	context_prop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	context_prop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	context_prop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	context_prop.texture = CONTEXT_TEXTURES.get(context_id)
	context_prop.visible = context_id in CONTEXT_TEXTURES
	context_prop.modulate.a = 0.0
	band.add_child(context_prop)

	effect = TextureRect.new()
	effect.texture = _fx_frame(0)
	effect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	effect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect.modulate.a = 0.0
	band.add_child(effect)

	title = _label(_context_title(), 38, Color("#fff4e5"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color("#260408"))
	title.add_theme_constant_override("outline_size", 8)
	band.add_child(title)

	victim_label = _label(_context_result_text(), 22, Color("#ffd5ce"))
	victim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victim_label.add_theme_color_override("font_outline_color", Color("#190306"))
	victim_label.add_theme_constant_override("outline_size", 6)
	victim_label.modulate.a = 0.0
	band.add_child(victim_label)

	flash = ColorRect.new()
	flash.color = Color(1.0, 0.08, 0.14, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(flash)

	get_viewport().size_changed.connect(_layout)
	_layout()
	root.modulate.a = 0.0
	# Safety net: the gameplay input lock must never survive a cinematic,
	# even if rendering is interrupted or a tween is cancelled.
	get_tree().create_timer(3.2).timeout.connect(_finish_cinematic)
	call_deferred("_play")


func _action_view(atlas: Texture2D, color_index: int, frame_index: int) -> TextureRect:
	var view := TextureRect.new()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_action_frame(view, atlas, color_index, frame_index)
	return view


func _set_action_frame(view: TextureRect, atlas: Texture2D, color_index: int, frame_index: int) -> void:
	var row: int = COLOR_TO_SHEET_ROW[clampi(color_index, 0, COLOR_TO_SHEET_ROW.size() - 1)]
	var frame := AtlasTexture.new()
	frame.atlas = atlas
	var cell_size := Vector2(float(atlas.get_width()) / 4.0, float(atlas.get_height()) / 6.0)
	# Generated poses have a little artwork overspill at some cell edges. Keep a
	# safe inset so a neighbouring colour/frame can never leak into this sprite.
	var inset_origin := Vector2(20.0, 12.0)
	var inset_size := cell_size - Vector2(40.0, 50.0)
	frame.region = Rect2(Vector2(cell_size.x * clampi(frame_index, 0, 3), cell_size.y * row) + inset_origin, inset_size)
	frame.filter_clip = true
	view.texture = frame


func _fx_frame(frame_index: int) -> Texture2D:
	return FLAT_FX_FRAMES[clampi(frame_index, 0, FLAT_FX_FRAMES.size() - 1)]


func _set_playing_frame(view: TextureRect, color_index: int, frame_index: int) -> void:
	var row: int = COLOR_TO_SHEET_ROW[clampi(color_index, 0, COLOR_TO_SHEET_ROW.size() - 1)]
	var frame := AtlasTexture.new()
	frame.atlas = CHARACTER_SHEET
	frame.region = Rect2(
		CHARACTER_FRAME_LEFT[clampi(frame_index, 0, CHARACTER_FRAME_LEFT.size() - 1)],
		CHARACTER_ROW_TOP[row], 120, CHARACTER_ROW_HEIGHT[row]
	)
	frame.filter_clip = true
	view.texture = frame
	var key_material := ShaderMaterial.new()
	key_material.shader = CHARACTER_SHADER
	view.material = key_material


func _context_title() -> String:
	match context_id:
		"campfire": return "FIRE PIT!"
		"lake": return "SPLASH!"
		"weak_tree": return "TIMBER!"
		"workshop": return "WORKSHOP WIPEOUT!"
	return "AMBUSH!"


func _context_result_text() -> String:
	var camper_name := str(body_state.get("name", "Camper"))
	match context_id:
		"campfire": return camper_name + " took a flaming shortcut"
		"lake": return camper_name + " went over the dock"
		"weak_tree": return camper_name + " was caught under the pine"
		"workshop": return camper_name + " met a runaway cart"
	return camper_name + " was eliminated"


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _layout() -> void:
	if not is_instance_valid(root):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	# A wide dramatic cut-in keeps the live map visible above/below it while
	# giving the two characters enough space for a readable multi-beat action.
	var band_width := viewport_size.x + 4.0
	var band_height := minf(maxf(viewport_size.y * 0.68, 300.0), viewport_size.y - 12.0)
	var band_size := Vector2(band_width, band_height)
	band.size = band_size
	band.position = (viewport_size - band_size) * 0.5
	band.pivot_offset = band_size * 0.5
	flash.position = Vector2.ZERO
	flash.size = band_size

	var ui_scale := clampf(minf(band_width / 1100.0, band_height / 500.0), 0.55, 1.16)
	var character_size := Vector2(330.0, 330.0) * ui_scale
	attacker.size = character_size
	victim.size = character_size
	attacker_target = Vector2(band_width * 0.18, band_height - character_size.y - 42.0 * ui_scale)
	# Both characters begin within visible reach; contextual motion then carries
	# the victim into the nearby set piece.
	victim_target = Vector2(band_width * 0.45, band_height - character_size.y - 42.0 * ui_scale)
	attacker.position = attacker_target
	victim.position = victim_target
	attacker.pivot_offset = attacker.size * 0.5
	victim.pivot_offset = victim.size * 0.5

	var effect_size := Vector2.ONE * minf(360.0 * ui_scale, band_height * 0.78)
	effect.size = effect_size
	effect.position = Vector2(band_width * 0.53, band_height * 0.54) - effect_size * 0.5
	effect.pivot_offset = effect.size * 0.5
	var prop_size := Vector2(390.0, 315.0) * ui_scale
	if context_id == "lake":
		prop_size = Vector2(480.0, 310.0) * ui_scale
	elif context_id == "weak_tree":
		prop_size = Vector2(490.0, 340.0) * ui_scale
	elif context_id == "workshop":
		prop_size = Vector2(470.0, 325.0) * ui_scale
	context_prop.size = prop_size
	context_prop.position = Vector2(band_width * 0.70, band_height * 0.61) - prop_size * 0.5
	context_prop.pivot_offset = prop_size * 0.5
	title.position = Vector2(0.0, 10.0 * ui_scale)
	title.size = Vector2(band_width, 56.0 * ui_scale)
	title.add_theme_font_size_override("font_size", int(38.0 * ui_scale))
	victim_label.position = Vector2(0.0, band_height - 52.0 * ui_scale)
	victim_label.size = Vector2(band_width, 42.0 * ui_scale)
	victim_label.add_theme_font_size_override("font_size", int(22.0 * ui_scale))


func _play() -> void:
	attacker.position = attacker_target + Vector2(-attacker.size.x * 0.55, 0.0)
	victim.position = victim_target + Vector2(victim.size.x * 0.20, 0.0)
	band.scale = Vector2(1.0, 0.88)
	var entrance := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	entrance.tween_property(root, "modulate:a", 1.0, 0.14)
	entrance.tween_property(band, "scale", Vector2.ONE, 0.20)
	entrance.tween_property(attacker, "position", attacker_target, 0.28)
	entrance.tween_property(victim, "position", victim_target, 0.28)
	await entrance.finished
	if context_id in CONTEXT_TEXTURES:
		await _play_contextual()
	else:
		await _play_close_range()
	await _play_exit()


func _play_contextual() -> void:
	# Context kills are physical pushes/accidents. Use the normal playable
	# character art for the Killer so no weapon appears in these sequences.
	_set_playing_frame(attacker, killer_color, 4)
	match context_id:
		"campfire": await _play_campfire()
		"lake": await _play_lake()
		"weak_tree": await _play_tree()
		"workshop": await _play_workshop()


func _play_campfire() -> void:
	context_prop.scale = Vector2(0.72, 0.72)
	var reveal := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_property(context_prop, "modulate:a", 1.0, 0.16)
	reveal.tween_property(context_prop, "scale", Vector2.ONE, 0.22)
	await reveal.finished
	_set_playing_frame(attacker, killer_color, 5)
	_set_action_frame(victim, VICTIM_DEFEAT_ATLAS, victim_color, 1)
	var shove := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	shove.tween_property(attacker, "position:x", victim_target.x - attacker.size.x * 0.58, 0.24)
	shove.tween_property(victim, "position", context_prop.position + context_prop.size * Vector2(0.33, 0.30), 0.34)
	shove.tween_property(victim, "rotation", 0.35, 0.34)
	await shove.finished
	await _play_context_impact(Color(1.0, 0.34, 0.03, 0.46))
	var sink := create_tween().set_parallel(true)
	sink.tween_property(victim, "scale", Vector2(0.55, 0.55), 0.24)
	sink.tween_property(victim, "modulate:a", 0.0, 0.24)
	sink.tween_property(context_prop, "scale", Vector2(1.08, 1.08), 0.14)
	await sink.finished
	await _context_hold()


func _play_lake() -> void:
	context_prop.scale = Vector2(0.35, 0.18)
	_set_playing_frame(attacker, killer_color, 5)
	_set_action_frame(victim, VICTIM_DEFEAT_ATLAS, victim_color, 1)
	var push := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	push.tween_property(attacker, "position:x", victim_target.x - attacker.size.x * 0.60, 0.22)
	push.tween_property(victim, "position", context_prop.position + context_prop.size * Vector2(0.26, 0.15), 0.38)
	push.tween_property(victim, "rotation", -0.45, 0.38)
	await push.finished
	await _play_context_impact(Color(0.05, 0.55, 1.0, 0.36))
	context_prop.modulate.a = 1.0
	var splash := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	splash.tween_property(context_prop, "scale", Vector2.ONE, 0.20)
	splash.tween_property(victim, "position:y", victim.position.y + victim.size.y * 0.46, 0.24)
	splash.tween_property(victim, "modulate:a", 0.0, 0.22)
	await splash.finished
	await _context_hold()


func _play_tree() -> void:
	context_prop.position.y -= context_prop.size.y * 0.42
	context_prop.rotation = -0.16
	context_prop.scale = Vector2(0.92, 0.92)
	context_prop.modulate.a = 1.0
	_set_playing_frame(attacker, killer_color, 5)
	_set_action_frame(victim, VICTIM_DEFEAT_ATLAS, victim_color, 1)
	var bump := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	bump.tween_property(attacker, "position:x", victim_target.x - attacker.size.x * 0.62, 0.22)
	bump.tween_property(victim, "position:x", victim.position.x + victim.size.x * 0.28, 0.25)
	await bump.finished
	var timber := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	timber.tween_property(context_prop, "position:y", context_prop.position.y + context_prop.size.y * 0.38, 0.30)
	timber.tween_property(context_prop, "rotation", 0.05, 0.30)
	timber.tween_property(victim, "position:y", victim.position.y + victim.size.y * 0.20, 0.30)
	await timber.finished
	await _play_context_impact(Color(0.62, 0.44, 0.18, 0.38))
	_set_action_frame(victim, VICTIM_DEFEAT_ATLAS, victim_color, 3)
	victim.modulate.a = 0.18
	await _context_hold()


func _play_workshop() -> void:
	context_prop.position.x += context_prop.size.x * 0.58
	context_prop.rotation = 0.16
	context_prop.modulate.a = 1.0
	_set_playing_frame(attacker, killer_color, 5)
	_set_action_frame(victim, VICTIM_DEFEAT_ATLAS, victim_color, 0)
	var cart := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	cart.tween_property(context_prop, "position:x", context_prop.position.x - context_prop.size.x * 0.58, 0.34)
	cart.tween_property(context_prop, "rotation", -0.05, 0.34)
	cart.tween_property(victim, "position:x", victim.position.x - victim.size.x * 0.08, 0.30)
	await cart.finished
	await _play_context_impact(Color(1.0, 0.75, 0.20, 0.38))
	_set_action_frame(victim, VICTIM_DEFEAT_ATLAS, victim_color, 2)
	var knock := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	knock.tween_property(victim, "position:y", victim.position.y + victim.size.y * 0.22, 0.22)
	knock.tween_property(victim, "rotation", -0.42, 0.22)
	knock.tween_property(victim, "modulate:a", 0.12, 0.25)
	await knock.finished
	await _context_hold()


func _play_context_impact(flash_color: Color) -> void:
	effect.texture = _fx_frame(0)
	effect.modulate = Color.WHITE
	effect.modulate.a = 1.0
	effect.scale = Vector2(0.30, 0.30)
	flash.color = flash_color
	var pop := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(effect, "scale", Vector2.ONE, 0.12)
	pop.tween_property(flash, "color:a", 0.0, 0.15)
	await pop.finished
	var fade := create_tween().set_parallel(true)
	fade.tween_property(effect, "modulate:a", 0.0, 0.12)
	fade.tween_property(effect, "scale", Vector2(1.14, 1.14), 0.12)
	await fade.finished


func _context_hold() -> void:
	_set_playing_frame(attacker, killer_color, 0)
	victim_label.modulate.a = 1.0
	await get_tree().create_timer(0.48).timeout


func _play_close_range() -> void:

	# The killer visibly charges across the live-game overlay.
	effect.texture = _fx_frame(0)
	effect.modulate.a = 0.92
	effect.scale = Vector2(0.62, 0.62)
	_set_action_frame(attacker, KILLER_ATTACK_ATLAS, killer_color, 1)
	var trail := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	trail.tween_property(attacker, "position:x", attacker_target.x + attacker.size.x * 0.92, 0.16)
	trail.tween_property(effect, "scale", Vector2.ONE, 0.16)
	await get_tree().create_timer(0.08).timeout
	_set_action_frame(attacker, KILLER_ATTACK_ATLAS, killer_color, 2)
	await get_tree().create_timer(0.10).timeout

	effect.texture = _fx_frame(1)
	effect.modulate.a = 1.0
	flash.color.a = 0.48
	create_tween().tween_property(flash, "color:a", 0.0, 0.14)
	_set_action_frame(victim, VICTIM_DEFEAT_ATLAS, victim_color, 1)
	await get_tree().create_timer(0.13).timeout

	effect.texture = _fx_frame(2)
	effect.scale = Vector2(0.92, 0.92)
	_set_action_frame(victim, VICTIM_DEFEAT_ATLAS, victim_color, 2)
	var fall := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(victim, "position:y", victim.position.y + victim.size.y * 0.16, 0.28)
	fall.tween_property(victim, "modulate:a", 0.82, 0.28)
	fall.tween_property(attacker, "position:x", attacker_target.x + attacker.size.x * 0.54, 0.32)
	await fall.finished

	_set_action_frame(attacker, KILLER_ATTACK_ATLAS, killer_color, 3)
	_set_action_frame(victim, VICTIM_DEFEAT_ATLAS, victim_color, 3)
	effect.texture = _fx_frame(3)
	effect.scale = Vector2(0.82, 0.82)
	victim_label.modulate.a = 1.0
	await get_tree().create_timer(0.52).timeout


func _play_exit() -> void:

	var exit := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	exit.tween_property(root, "modulate:a", 0.0, 0.20)
	exit.tween_property(band, "scale", Vector2(0.98, 0.98), 0.20)
	exit.tween_property(effect, "position:y", effect.position.y - 36.0, 0.20)
	await exit.finished
	_finish_cinematic()


func _finish_cinematic() -> void:
	if has_finished:
		return
	has_finished = true
	finished.emit()
	queue_free()
