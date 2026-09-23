extends SceneTree

const ARTIFACT_DIR := "C:/Users/saule/.gemini/antigravity/brain/17a13079-7005-4717-99fb-b563640774d7/"
const GAME_ASSET_PATH := "res://assets/phase5/cartoon_camp_bell_asset.png"

class BellDrawer extends Node2D:
	var swing_angle := 0.0 # in radians
	var bell_offset_x := 0.0

	func _draw() -> void:
		# Draw the gallows post structure first (behind the bell)
		_draw_post()
		# Draw the hanging bell with optional swing angle
		_draw_bell()

	func _draw_post() -> void:
		var dark_outline := Color("#231509")
		var wood_base := Color("#8a5526")
		var wood_hi := Color("#b3743b")
		var wood_mid := Color("#9a602e")
		var wood_shadow := Color("#653c16")
		var wood_deep := Color("#48280d")

		var iron_dark := Color("#2c2724")
		var iron_mid := Color("#423a35")
		var iron_hi := Color("#655a53")
		var gold_rivet := Color("#e8b038")

		# --- 1. LOWER POST (TRUNK) ---
		# X: 108 to 172 (width 64), Y: 500 to 1020
		var p_left := 108.0
		var p_right := 172.0
		var p_width := p_right - p_left
		var p_bottom := 1020.0
		var p_collar_y := 500.0

		# Shadow & body
		draw_rect(Rect2(p_left, p_collar_y, p_width, p_bottom - p_collar_y), wood_base)
		# Vertical wood tone strips (highlight left, shadow right)
		draw_rect(Rect2(p_left, p_collar_y, 14, p_bottom - p_collar_y), wood_hi)
		draw_rect(Rect2(p_left + 14, p_collar_y, 22, p_bottom - p_collar_y), wood_mid)
		draw_rect(Rect2(p_right - 18, p_collar_y, 18, p_bottom - p_collar_y), wood_shadow)
		draw_rect(Rect2(p_right - 6, p_collar_y, 6, p_bottom - p_collar_y), wood_deep)

		# Wood grain knots / accents
		draw_circle(Vector2(p_left + 26, 680), 9, wood_shadow)
		draw_circle(Vector2(p_left + 26, 680), 5, wood_deep)
		draw_arc(Vector2(p_left + 26, 680), 15, -1.0, 1.2, 16, wood_shadow, 3.0)
		draw_arc(Vector2(p_left + 35, 860), 18, -2.2, -0.4, 16, wood_shadow, 3.0)

		# Outline for lower post
		draw_line(Vector2(p_left, p_collar_y), Vector2(p_left, p_bottom), dark_outline, 8.0, true)
		draw_line(Vector2(p_right, p_collar_y), Vector2(p_right, p_bottom), dark_outline, 8.0, true)
		draw_line(Vector2(p_left - 4, p_bottom), Vector2(p_right + 4, p_bottom), dark_outline, 8.0, true)

		# --- 2. COLLAR (CUFF BETWEEN LOWER AND UPPER POST) ---
		# Rounded band wrapping around post at Y: 460 to 520
		var c_left := 92.0
		var c_right := 188.0
		var c_top := 465.0
		var c_bot := 525.0
		var c_rect := Rect2(c_left, c_top, c_right - c_left, c_bot - c_top)
		var c_radius := 14.0

		# Draw collar filled rounded rect
		_draw_rounded_rect(c_rect, c_radius, iron_dark)
		_draw_rounded_rect(Rect2(c_left + 4, c_top + 4, c_right - c_left - 8, 16), 8.0, iron_hi)
		_draw_rounded_rect(Rect2(c_left + 4, c_top + 20, c_right - c_left - 8, c_bot - c_top - 24), 8.0, iron_mid)
		# Golden rivets
		draw_circle(Vector2(c_left + 18, (c_top + c_bot) * 0.5), 6.0, gold_rivet)
		draw_circle(Vector2(c_left + 18, (c_top + c_bot) * 0.5), 3.0, Color("#fff2a8"))
		draw_circle(Vector2(c_right - 18, (c_top + c_bot) * 0.5), 6.0, gold_rivet)
		draw_circle(Vector2(c_right - 18, (c_top + c_bot) * 0.5), 3.0, Color("#fff2a8"))
		draw_circle(Vector2((c_left + c_right) * 0.5, (c_top + c_bot) * 0.5), 6.0, gold_rivet)
		draw_circle(Vector2((c_left + c_right) * 0.5, (c_top + c_bot) * 0.5), 3.0, Color("#fff2a8"))
		# Collar outline
		_draw_rounded_rect_outline(c_rect, c_radius, dark_outline, 8.0)

		# --- 3. UPPER POST ---
		# X: 116 to 164 (width 48), Y: 110 to 465
		var u_left := 116.0
		var u_right := 164.0
		var u_width := u_right - u_left
		var u_top := 110.0
		var u_bot := 465.0

		# Upper post body
		draw_rect(Rect2(u_left, u_top, u_width, u_bot - u_top), wood_base)
		draw_rect(Rect2(u_left, u_top, 12, u_bot - u_top), wood_hi)
		draw_rect(Rect2(u_left + 12, u_top, 18, u_bot - u_top), wood_mid)
		draw_rect(Rect2(u_right - 12, u_top, 12, u_bot - u_top), wood_shadow)

		# Rounded cap at the very top
		var cap_center := Vector2((u_left + u_right) * 0.5, u_top)
		var cap_radius := u_width * 0.5
		_draw_half_circle(cap_center, cap_radius, true, wood_base)
		_draw_half_circle(cap_center, cap_radius, true, wood_hi, 0.4) # left highlight

		# Outlines for upper post
		draw_line(Vector2(u_left, u_bot), Vector2(u_left, u_top), dark_outline, 8.0, true)
		draw_line(Vector2(u_right, u_bot), Vector2(u_right, u_top), dark_outline, 8.0, true)
		draw_arc(cap_center, cap_radius, PI, TAU, 32, dark_outline, 8.0, true)

		# --- 4. DIAGONAL SUPPORT BRACE ---
		# Strengthens the gallows arm joint: from (140, 270) to (240, 185)
		var b_poly := PackedVector2Array([
			Vector2(140, 260),
			Vector2(160, 275),
			Vector2(265, 185),
			Vector2(245, 170)
		])
		draw_colored_polygon(b_poly, wood_mid)
		draw_line(Vector2(140, 260), Vector2(245, 170), dark_outline, 7.0, true)
		draw_line(Vector2(160, 275), Vector2(265, 185), dark_outline, 7.0, true)
		draw_circle(Vector2(152, 262), 5.0, iron_dark)
		draw_circle(Vector2(250, 180), 5.0, iron_dark)

		# --- 5. HORIZONTAL BEAM / ARM ---
		# Y: 135 to 185 (height 50), from X: 140 to X: 520
		var h_top := 135.0
		var h_bot := 185.0
		var h_height := h_bot - h_top
		var h_left := 140.0
		var h_right := 500.0
		var h_cap_x := h_right
		var h_cap_center := Vector2(h_cap_x, (h_top + h_bot) * 0.5)
		var h_cap_radius := h_height * 0.5

		# Arm body
		draw_rect(Rect2(h_left, h_top, h_right - h_left, h_height), wood_base)
		draw_rect(Rect2(h_left, h_top, h_right - h_left, 12), wood_hi)
		draw_rect(Rect2(h_left, h_bot - 14, h_right - h_left, 14), wood_shadow)
		# Rounded right end cap
		_draw_half_circle(h_cap_center, h_cap_radius, false, wood_base, 1.0, 0.5 * PI)
		_draw_half_circle(h_cap_center, h_cap_radius, false, wood_hi, 0.4, 0.5 * PI)

		# Arm outlines
		draw_line(Vector2(h_left, h_top), Vector2(h_right, h_top), dark_outline, 8.0, true)
		draw_line(Vector2(h_left, h_bot), Vector2(h_right, h_bot), dark_outline, 8.0, true)
		draw_arc(h_cap_center, h_cap_radius, -0.5 * PI, 0.5 * PI, 32, dark_outline, 8.0, true)

		# Joint bracket at post-to-arm connection
		var j_rect := Rect2(120, 130, 48, 60)
		_draw_rounded_rect(j_rect, 8.0, iron_dark)
		_draw_rounded_rect_outline(j_rect, 8.0, dark_outline, 6.0)
		draw_circle(Vector2(144, 145), 5.0, gold_rivet)
		draw_circle(Vector2(144, 175), 5.0, gold_rivet)

	func _draw_bell() -> void:
		var dark_outline := Color("#231509")
		var iron_dark := Color("#2c2724")
		var iron_mid := Color("#4a413c")

		# Bell attachment point on horizontal arm
		var pivot := Vector2(380.0, 185.0)

		# Push transform for swinging animation
		var t := Transform2D().translated(-pivot)
		t = Transform2D(swing_angle, Vector2.ZERO) * t
		t = Transform2D().translated(pivot) * t

		# Transform helper
		# --- 1. SUSPENSION MOUNT & LOOP ---
		# Vertical link hanging from arm
		var hanger_top := pivot
		var hanger_bot := pivot + Vector2(0, 45)
		draw_line(hanger_top, hanger_bot, iron_dark, 14.0, true)
		draw_line(hanger_top, hanger_bot, iron_mid, 6.0, true)
		draw_line(hanger_top - Vector2(10, 0), hanger_top + Vector2(10, 0), dark_outline, 8.0, true)

		# Top arch / loop on bell
		var loop_center := pivot + Vector2(0, 70)
		# Outer loop
		draw_circle(loop_center, 26.0, iron_dark)
		draw_circle(loop_center, 12.0, Color(0, 0, 0, 0)) # hollow
		# Clapper / bell crown cap
		var crown_center := pivot + Vector2(0, 95)
		draw_circle(crown_center, 22.0, Color("#d48812"))
		draw_circle(crown_center, 14.0, Color("#f5b02a"))

		# --- 2. BELL BODY GEOMETRY ---
		# Let's create smooth cartoon curved points for the bell body
		# Top of bell: Y: 95
		# Waist: Y: 210
		# Flare/Rim: Y: 330
		# Mouth ellipse: Center Y: 330, Width: 260 (radius 130), Height: 60 (radius 30)

		var bell_points_left := PackedVector2Array()
		var bell_points_right := PackedVector2Array()

		# Generate bell profile curve
		var steps := 24
		for i in range(steps + 1):
			var frac := float(i) / float(steps)
			var cur_y := lerpf(95.0, 330.0, frac)
			# Profile equation: rounded top, narrow waist, dramatic flare at bottom
			var w := 0.0
			if frac < 0.35:
				# Top dome curving out from 22 to 70
				var dome_f := frac / 0.35
				w = lerpf(22.0, 72.0, sqrt(dome_f))
			elif frac < 0.65:
				# Waist: gently holding / slightly tapering
				var waist_f := (frac - 0.35) / 0.30
				w = lerpf(72.0, 78.0, waist_f)
			else:
				# Dramatic trumpet flare towards bottom rim
				var flare_f := (frac - 0.65) / 0.35
				w = lerpf(78.0, 138.0, flare_f * flare_f)

			bell_points_left.append(pivot + Vector2(-w, cur_y))
			bell_points_right.append(pivot + Vector2(w, cur_y))

		# Construct outer polygon
		var bell_poly := PackedVector2Array()
		for pt in bell_points_left:
			bell_poly.append(pt)
		# Bottom arc across the rim (front lip)
		var rim_center := pivot + Vector2(0, 330)
		for j in range(steps + 1):
			var angle := lerpf(PI, 0.0, float(j) / float(steps))
			var rx := 138.0
			var ry := 24.0
			bell_poly.append(rim_center + Vector2(cos(angle) * rx, sin(angle) * ry))
		for k in range(bell_points_right.size() - 1, -1, -1):
			bell_poly.append(bell_points_right[k])

		# Fill bell exterior with warm vibrant gold/brass
		draw_colored_polygon(bell_poly, Color("#f5a51c"))

		# Highlight layers (left side sunny yellow/gold)
		var hi_poly := PackedVector2Array()
		for i in range(bell_points_left.size()):
			var pt: Vector2 = bell_points_left[i]
			hi_poly.append(pt)
		# Inner boundary of highlight
		for i in range(bell_points_left.size() - 1, -1, -1):
			var pt: Vector2 = bell_points_left[i]
			var center_x := pivot.x
			var hi_x := lerpf(pt.x, center_x, 0.45)
			hi_poly.append(Vector2(hi_x, pt.y))
		draw_colored_polygon(hi_poly, Color("#ffcf4d", 0.85))

		# Specular cartoon shine stripe on left flank
		var shine_points := PackedVector2Array()
		for i in range(4, bell_points_left.size() - 4):
			var pt: Vector2 = bell_points_left[i]
			var sx := lerpf(pt.x, pivot.x, 0.22)
			shine_points.append(Vector2(sx, pt.y))
		draw_polyline(shine_points, Color("#fffbee", 0.90), 10.0, true)

		# Shadow layers (right side warm amber bronze)
		var shadow_poly := PackedVector2Array()
		for i in range(bell_points_right.size()):
			var pt: Vector2 = bell_points_right[i]
			shadow_poly.append(pt)
		for i in range(bell_points_right.size() - 1, -1, -1):
			var pt: Vector2 = bell_points_right[i]
			var center_x := pivot.x
			var sh_x := lerpf(pt.x, center_x, 0.40)
			shadow_poly.append(Vector2(sh_x, pt.y))
		draw_colored_polygon(shadow_poly, Color("#c47306", 0.75))

		# Deep rim shadow on the far right edge
		var deep_shadow := PackedVector2Array()
		for i in range(bell_points_right.size()):
			var pt: Vector2 = bell_points_right[i]
			deep_shadow.append(pt)
		for i in range(bell_points_right.size() - 1, -1, -1):
			var pt: Vector2 = bell_points_right[i]
			var center_x := pivot.x
			var sh_x := lerpf(pt.x, center_x, 0.15)
			deep_shadow.append(Vector2(sh_x, pt.y))
		draw_colored_polygon(deep_shadow, Color("#824300", 0.70))

		# Horizontal decorative accent ridges on the bell body (classic church/camp bell grooves)
		_draw_bell_groove(pivot, 155.0, 74.0, dark_outline, Color("#ffe07a"))
		_draw_bell_groove(pivot, 220.0, 78.0, dark_outline, Color("#ffe07a"))
		_draw_bell_groove(pivot, 285.0, 105.0, dark_outline, Color("#ffe07a"))

		# --- 3. BELL MOUTH / INTERIOR CAVITY & CLAPPER ---
		# Draw the dark hollow inside opening of the bell
		var mouth_center := rim_center
		var rx := 138.0
		var ry := 26.0

		# Dark interior cavity ellipse
		_draw_ellipse(mouth_center, rx - 6, ry - 3, Color("#261202"))
		_draw_ellipse(mouth_center + Vector2(0, -6), rx - 24, ry - 10, Color("#150800"))

		# Clapper hanging inside
		# Clapper stem
		draw_line(mouth_center + Vector2(0, -25), mouth_center + Vector2(0, 15), Color("#3d2208"), 10.0, true)
		# Clapper ball
		var clapper_center := mouth_center + Vector2(0, 14)
		draw_circle(clapper_center, 24.0, Color("#1f0e02")) # dark shadow ring
		draw_circle(clapper_center, 20.0, Color("#d98818")) # clapper body
		draw_circle(clapper_center + Vector2(-5, -5), 13.0, Color("#f7bf39")) # clapper highlight
		draw_circle(clapper_center + Vector2(-6, -6), 5.0, Color("#fff4ba")) # specular point
		draw_arc(clapper_center, 20.0, 0.0, TAU, 32, dark_outline, 5.0, true)

		# --- 4. BELL MOUTH THICK RIM LIP & OUTLINES ---
		# Outer rim lip (front bottom flare)
		var rim_front := PackedVector2Array()
		for j in range(steps + 1):
			var angle := lerpf(0.0, PI, float(j) / float(steps))
			rim_front.append(mouth_center + Vector2(cos(angle) * rx, sin(angle) * ry))
		draw_polyline(rim_front, dark_outline, 8.0, true)
		# Rim highlight along bottom lip
		var rim_hi := PackedVector2Array()
		for j in range(4, steps - 3):
			var angle := lerpf(0.15 * PI, 0.85 * PI, float(j) / float(steps))
			rim_hi.append(mouth_center + Vector2(cos(angle) * (rx - 5), sin(angle) * (ry - 4)))
		draw_polyline(rim_hi, Color("#ffea85", 0.90), 6.0, true)

		# Left profile outline
		draw_polyline(bell_points_left, dark_outline, 8.0, true)
		# Right profile outline
		draw_polyline(bell_points_right, dark_outline, 8.0, true)
		# Crown loop outline
		draw_arc(loop_center, 26.0, PI * 0.9, TAU * 1.05, 32, dark_outline, 8.0, true)
		draw_arc(loop_center, 12.0, PI * 0.8, TAU * 1.1, 32, dark_outline, 6.0, true)

	func _draw_bell_groove(pivot: Vector2, y_pos: float, width: float, dark_col: Color, hi_col: Color) -> void:
		var p_left := pivot + Vector2(-width, y_pos)
		var p_right := pivot + Vector2(width, y_pos)
		var curve_drop := 6.0
		var pts := PackedVector2Array()
		var hi_pts := PackedVector2Array()
		var steps := 16
		for i in range(steps + 1):
			var f := float(i) / float(steps)
			var x := lerpf(p_left.x, p_right.x, f)
			var y := y_pos + sin(f * PI) * curve_drop
			pts.append(Vector2(x, y))
			hi_pts.append(Vector2(x, y + 3.0))
		draw_polyline(pts, dark_col, 4.0, true)
		draw_polyline(hi_pts, hi_col, 2.5, true)

	func _draw_rounded_rect(rect: Rect2, radius: float, color: Color) -> void:
		var pts := PackedVector2Array()
		var steps := 8
		# Top-right
		for i in range(steps + 1):
			var a := lerpf(-0.5 * PI, 0.0, float(i) / steps)
			pts.append(Vector2(rect.end.x - radius + cos(a) * radius, rect.position.y + radius + sin(a) * radius))
		# Bottom-right
		for i in range(steps + 1):
			var a := lerpf(0.0, 0.5 * PI, float(i) / steps)
			pts.append(Vector2(rect.end.x - radius + cos(a) * radius, rect.end.y - radius + sin(a) * radius))
		# Bottom-left
		for i in range(steps + 1):
			var a := lerpf(0.5 * PI, PI, float(i) / steps)
			pts.append(Vector2(rect.position.x + radius + cos(a) * radius, rect.end.y - radius + sin(a) * radius))
		# Top-left
		for i in range(steps + 1):
			var a := lerpf(PI, 1.5 * PI, float(i) / steps)
			pts.append(Vector2(rect.position.x + radius + cos(a) * radius, rect.position.y + radius + sin(a) * radius))
		draw_colored_polygon(pts, color)

	func _draw_rounded_rect_outline(rect: Rect2, radius: float, color: Color, width: float) -> void:
		var pts := PackedVector2Array()
		var steps := 8
		for i in range(steps + 1):
			var a := lerpf(-0.5 * PI, 0.0, float(i) / steps)
			pts.append(Vector2(rect.end.x - radius + cos(a) * radius, rect.position.y + radius + sin(a) * radius))
		for i in range(steps + 1):
			var a := lerpf(0.0, 0.5 * PI, float(i) / steps)
			pts.append(Vector2(rect.end.x - radius + cos(a) * radius, rect.end.y - radius + sin(a) * radius))
		for i in range(steps + 1):
			var a := lerpf(0.5 * PI, PI, float(i) / steps)
			pts.append(Vector2(rect.position.x + radius + cos(a) * radius, rect.end.y - radius + sin(a) * radius))
		for i in range(steps + 1):
			var a := lerpf(PI, 1.5 * PI, float(i) / steps)
			pts.append(Vector2(rect.position.x + radius + cos(a) * radius, rect.position.y + radius + sin(a) * radius))
		pts.append(pts[0]) # close loop
		draw_polyline(pts, color, width, true)

	func _draw_half_circle(center: Vector2, radius: float, is_top: bool, color: Color, x_scale: float = 1.0, rot_offset: float = 0.0) -> void:
		var pts := PackedVector2Array()
		pts.append(center)
		var start_a := PI if is_top else 0.0
		var end_a := TAU if is_top else PI
		if rot_offset != 0.0:
			start_a -= rot_offset
			end_a -= rot_offset
		var steps := 16
		for i in range(steps + 1):
			var a := lerpf(start_a, end_a, float(i) / steps)
			pts.append(center + Vector2(cos(a) * radius * x_scale, sin(a) * radius))
		pts.append(center)
		draw_colored_polygon(pts, color)

	func _draw_ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
		var pts := PackedVector2Array()
		var steps := 32
		for i in range(steps):
			var a := (float(i) / float(steps)) * TAU
			pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts, color)

func _initialize() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(620, 1060)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var drawer := BellDrawer.new()
	vp.add_child(drawer)
	root.add_child(vp)

	# Render frames
	for i in range(3):
		await process_frame

	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		# Save isolated transparent game asset
		var dst_game := ProjectSettings.globalize_path(GAME_ASSET_PATH)
		img.save_png(dst_game)
		print("Saved game asset to: ", dst_game)

		# Save to artifact directory
		var dst_artifact := ARTIFACT_DIR + "cartoon_camp_bell_asset.png"
		img.save_png(dst_artifact)
		print("Saved artifact to: ", dst_artifact)

		# Also generate a warm presentation preview card with dark camp backdrop
		_create_preview_card(img)

	print("BELL_ASSET_GENERATION_COMPLETE")
	quit(0)

func _create_preview_card(asset_img: Image) -> void:
	var w := 800
	var h := 1150
	var card := Image.create(w, h, false, Image.FORMAT_RGBA8)
	card.fill(Color("#14100c")) # dark camp night backdrop

	# Add subtle warm camp gradient
	for y in range(h):
		var f := float(y) / float(h)
		var bg_col := Color("#16120d").lerp(Color("#241c14"), f)
		for x in range(w):
			card.set_pixel(x, y, bg_col)

	# Composite the asset in the center
	var offset_x := int((w - asset_img.get_width()) * 0.5)
	var offset_y := int((h - asset_img.get_height()) * 0.5) + 30

	for y in range(asset_img.get_height()):
		for x in range(asset_img.get_width()):
			var px := asset_img.get_pixel(x, y)
			if px.a > 0.001:
				var target_x := offset_x + x
				var target_y := offset_y + y
				if target_x >= 0 and target_x < w and target_y >= 0 and target_y < h:
					var bg: Color = card.get_pixel(target_x, target_y)
					card.set_pixel(target_x, target_y, bg.blend(px))

	var card_path := ARTIFACT_DIR + "cartoon_camp_bell_preview.png"
	card.save_png(card_path)
	print("Saved preview card to: ", card_path)
