import math
import os
from PIL import Image, ImageDraw

ARTIFACT_DIR = r"C:\Users\saule\.gemini\antigravity\brain\17a13079-7005-4717-99fb-b563640774d7"
GAME_ASSET_DIR = r"c:\Users\saule\OneDrive\Documents\double-take\assets\phase5"
MOVING_BELL_DIR = r"c:\Users\saule\OneDrive\Documents\double-take\assets\phase5\moving_bell"

SS = 4
W = 640 * SS
H = 960 * SS

def get_bell_width_at_frac(frac):
    if frac < 0.32:
        df = frac / 0.32
        return 28 * SS + (72 * SS - 28 * SS) * math.sqrt(df)
    elif frac < 0.60:
        wf = (frac - 0.32) / 0.28
        return 72 * SS + (76 * SS - 72 * SS) * wf
    else:
        ff = (frac - 0.60) / 0.40
        return 76 * SS + (138 * SS - 76 * SS) * (ff ** 2.0)

def create_cartoon_bell(swing_deg=0.0, chime_level=0):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)

    dark_outline = (35, 21, 9, 255)       # #231509
    wood_base = (142, 89, 39, 255)         # #8e5927
    wood_hi = (184, 121, 60, 255)          # #b8793c
    wood_mid = (156, 99, 45, 255)          # #9c632d
    wood_shadow = (103, 61, 23, 255)       # #673d17
    wood_deep = (73, 41, 14, 255)          # #49290e

    iron_dark = (44, 39, 36, 255)          # #2c2724
    iron_mid = (66, 58, 53, 255)           # #423a35
    iron_hi = (101, 90, 83, 255)           # #655a53
    gold_rivet = (232, 176, 56, 255)       # #e8b038
    gold_rivet_hi = (255, 242, 168, 255)

    outline_w = int(7 * SS)

    # 1. LOWER POST (TRUNK)
    p_left = int(115 * SS)
    p_right = int(185 * SS)
    p_width = p_right - p_left
    p_collar_y = int(485 * SS)
    p_bottom = int(920 * SS)

    draw.rectangle([p_left, p_collar_y, p_right, p_bottom], fill=wood_base)
    draw.rectangle([p_left, p_collar_y, p_left + int(16 * SS), p_bottom], fill=wood_hi)
    draw.rectangle([p_left + int(16 * SS), p_collar_y, p_left + int(36 * SS), p_bottom], fill=wood_mid)
    draw.rectangle([p_right - int(18 * SS), p_collar_y, p_right, p_bottom], fill=wood_shadow)
    draw.rectangle([p_right - int(6 * SS), p_collar_y, p_right, p_bottom], fill=wood_deep)

    knot_x = p_left + int(28 * SS)
    knot_y = int(680 * SS)
    draw.ellipse([knot_x - int(10 * SS), knot_y - int(14 * SS), knot_x + int(10 * SS), knot_y + int(14 * SS)], fill=wood_shadow)
    draw.ellipse([knot_x - int(5 * SS), knot_y - int(7 * SS), knot_x + int(5 * SS), knot_y + int(7 * SS)], fill=wood_deep)
    draw.arc([knot_x - int(20 * SS), knot_y - int(26 * SS), knot_x + int(20 * SS), knot_y + int(26 * SS)],
             start=30, end=150, fill=wood_shadow, width=int(2.5 * SS))
    draw.arc([p_left + int(10 * SS), int(800 * SS), p_right - int(10 * SS), int(860 * SS)],
             start=200, end=340, fill=wood_shadow, width=int(2.5 * SS))

    draw.line([(p_left, p_collar_y), (p_left, p_bottom)], fill=dark_outline, width=outline_w)
    draw.line([(p_right, p_collar_y), (p_right, p_bottom)], fill=dark_outline, width=outline_w)
    draw.line([(p_left - int(3 * SS), p_bottom), (p_right + int(3 * SS), p_bottom)], fill=dark_outline, width=outline_w)

    # 2. COLLAR
    c_left = int(98 * SS)
    c_right = int(202 * SS)
    c_top = int(455 * SS)
    c_bot = int(515 * SS)
    c_rad = int(14 * SS)

    draw.rounded_rectangle([c_left, c_top, c_right, c_bot], radius=c_rad, fill=iron_dark)
    draw.rounded_rectangle([c_left + int(4 * SS), c_top + int(4 * SS), c_right - int(4 * SS), c_top + int(18 * SS)],
                           radius=int(6 * SS), fill=iron_hi)
    draw.rounded_rectangle([c_left + int(4 * SS), c_top + int(20 * SS), c_right - int(4 * SS), c_bot - int(6 * SS)],
                           radius=int(6 * SS), fill=iron_mid)

    for rx_pos in [c_left + int(20 * SS), (c_left + c_right) // 2, c_right - int(20 * SS)]:
        ry_pos = (c_top + c_bot) // 2
        r_sz = int(6 * SS)
        draw.ellipse([rx_pos - r_sz, ry_pos - r_sz, rx_pos + r_sz, ry_pos + r_sz], fill=gold_rivet)
        draw.ellipse([rx_pos - r_sz//2, ry_pos - r_sz//2, rx_pos, ry_pos], fill=gold_rivet_hi)
        draw.arc([rx_pos - r_sz, ry_pos - r_sz, rx_pos + r_sz, ry_pos + r_sz], start=0, end=360, fill=dark_outline, width=int(2 * SS))

    draw.rounded_rectangle([c_left, c_top, c_right, c_bot], radius=c_rad, outline=dark_outline, width=outline_w)

    # 3. UPPER POST
    u_left = int(124 * SS)
    u_right = int(176 * SS)
    u_top = int(95 * SS)
    u_bot = int(455 * SS)
    u_width = u_right - u_left

    draw.rectangle([u_left, u_top, u_right, u_bot], fill=wood_base)
    draw.rectangle([u_left, u_top, u_left + int(14 * SS), u_bot], fill=wood_hi)
    draw.rectangle([u_left + int(14 * SS), u_top, u_left + int(32 * SS), u_bot], fill=wood_mid)
    draw.rectangle([u_right - int(14 * SS), u_top, u_right, u_bot], fill=wood_shadow)

    cap_cx = (u_left + u_right) // 2
    cap_r = u_width // 2
    draw.pieslice([cap_cx - cap_r, u_top - cap_r, cap_cx + cap_r, u_top + cap_r], start=180, end=360, fill=wood_base)
    draw.pieslice([cap_cx - cap_r, u_top - cap_r, cap_cx + cap_r, u_top + cap_r], start=180, end=270, fill=wood_hi)

    draw.line([(u_left, u_bot), (u_left, u_top)], fill=dark_outline, width=outline_w)
    draw.line([(u_right, u_bot), (u_right, u_top)], fill=dark_outline, width=outline_w)
    draw.arc([cap_cx - cap_r, u_top - cap_r, cap_cx + cap_r, u_top + cap_r], start=180, end=360, fill=dark_outline, width=outline_w)

    # 4. DIAGONAL SUPPORT BRACE
    b_pts = [
        (int(150 * SS), int(255 * SS)),
        (int(172 * SS), int(272 * SS)),
        (int(275 * SS), int(182 * SS)),
        (int(253 * SS), int(165 * SS))
    ]
    draw.polygon(b_pts, fill=wood_mid)
    draw.line([b_pts[0], b_pts[3]], fill=dark_outline, width=int(6 * SS))
    draw.line([b_pts[1], b_pts[2]], fill=dark_outline, width=int(6 * SS))
    draw.ellipse([int(160 * SS) - int(5 * SS), int(258 * SS) - int(5 * SS), int(160 * SS) + int(5 * SS), int(258 * SS) + int(5 * SS)], fill=iron_dark)
    draw.ellipse([int(260 * SS) - int(5 * SS), int(178 * SS) - int(5 * SS), int(260 * SS) + int(5 * SS), int(178 * SS) + int(5 * SS)], fill=iron_dark)

    # 5. HORIZONTAL BEAM / ARM
    h_left = int(140 * SS)
    h_right = int(505 * SS)
    h_top = int(125 * SS)
    h_bot = int(175 * SS)
    h_rad = (h_bot - h_top) // 2

    draw.rectangle([h_left, h_top, h_right, h_bot], fill=wood_base)
    draw.rectangle([h_left, h_top, h_right, h_top + int(13 * SS)], fill=wood_hi)
    draw.rectangle([h_left, h_bot - int(15 * SS), h_right, h_bot], fill=wood_shadow)

    draw.pieslice([h_right - h_rad, h_top, h_right + h_rad, h_bot], start=270, end=450, fill=wood_base)
    draw.pieslice([h_right - h_rad, h_top, h_right + h_rad, h_bot], start=270, end=360, fill=wood_hi)

    draw.line([(h_left, h_top), (h_right, h_top)], fill=dark_outline, width=outline_w)
    draw.line([(h_left, h_bot), (h_right, h_bot)], fill=dark_outline, width=outline_w)
    draw.arc([h_right - h_rad, h_top, h_right + h_rad, h_bot], start=270, end=450, fill=dark_outline, width=outline_w)

    j_rect = [int(130 * SS), int(120 * SS), int(170 * SS), int(180 * SS)]
    draw.rounded_rectangle(j_rect, radius=int(6 * SS), fill=iron_dark, outline=dark_outline, width=int(5 * SS))
    draw.ellipse([int(150 * SS) - int(4 * SS), int(135 * SS) - int(4 * SS), int(150 * SS) + int(4 * SS), int(135 * SS) + int(4 * SS)], fill=gold_rivet)
    draw.ellipse([int(150 * SS) - int(4 * SS), int(165 * SS) - int(4 * SS), int(150 * SS) + int(4 * SS), int(165 * SS) + int(4 * SS)], fill=gold_rivet)

    # 6. HANGING MOUNT ON HORIZONTAL BEAM
    pivot_x = int(395 * SS)
    pivot_y = h_bot

    b_clamp = [pivot_x - int(16 * SS), h_top - int(3 * SS), pivot_x + int(16 * SS), h_bot + int(10 * SS)]
    draw.rounded_rectangle(b_clamp, radius=int(5 * SS), fill=iron_dark, outline=dark_outline, width=int(5 * SS))
    draw.ellipse([pivot_x - int(3 * SS), (h_top + h_bot)//2 - int(3 * SS), pivot_x + int(3 * SS), (h_top + h_bot)//2 + int(3 * SS)], fill=gold_rivet)

    link_top = h_bot + int(8 * SS)
    link_bot = link_top + int(45 * SS)
    draw.line([(pivot_x, link_top), (pivot_x, link_bot)], fill=dark_outline, width=int(14 * SS))
    draw.line([(pivot_x, link_top), (pivot_x, link_bot)], fill=iron_mid, width=int(8 * SS))

    # 7. THE CARTOON CAMP BELL (Rendered on dedicated layer)
    bell_im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(bell_im)

    loop_cx = pivot_x
    loop_cy = link_bot + int(24 * SS)
    loop_outer_r = int(24 * SS)
    loop_inner_r = int(11 * SS)

    bdraw.ellipse([loop_cx - loop_outer_r, loop_cy - loop_outer_r, loop_cx + loop_outer_r, loop_cy + loop_outer_r], fill=iron_dark)
    bdraw.ellipse([loop_cx - loop_inner_r, loop_cy - loop_inner_r, loop_cx + loop_inner_r, loop_cy + loop_inner_r], fill=(0, 0, 0, 0))
    bdraw.arc([loop_cx - loop_outer_r, loop_cy - loop_outer_r, loop_cx + loop_outer_r, loop_cy + loop_outer_r], start=0, end=360, fill=dark_outline, width=outline_w)
    bdraw.arc([loop_cx - loop_inner_r, loop_cy - loop_inner_r, loop_cx + loop_inner_r, loop_cy + loop_inner_r], start=0, end=360, fill=dark_outline, width=int(5 * SS))

    crown_cx = loop_cx
    crown_cy = loop_cy + int(24 * SS)
    crown_rx = int(32 * SS)
    crown_ry = int(14 * SS)
    bdraw.ellipse([crown_cx - crown_rx, crown_cy - crown_ry, crown_cx + crown_rx, crown_cy + crown_ry], fill=(212, 136, 18, 255))
    bdraw.ellipse([crown_cx - crown_rx + int(4*SS), crown_cy - crown_ry + int(2*SS), crown_cx + crown_rx - int(4*SS), crown_cy + crown_ry - int(2*SS)], fill=(245, 176, 42, 255))

    bell_top_y = crown_cy
    bell_rim_y = bell_top_y + int(250 * SS)
    bell_h = bell_rim_y - bell_top_y

    steps = 60
    pts_left = []
    pts_right = []

    for i in range(steps + 1):
        frac = i / float(steps)
        cur_y = bell_top_y + frac * bell_h
        w = get_bell_width_at_frac(frac)
        pts_left.append((loop_cx - w, cur_y))
        pts_right.append((loop_cx + w, cur_y))

    rim_cx = loop_cx
    rim_cy = bell_rim_y
    rim_rx = int(138 * SS)
    rim_ry = int(28 * SS)

    body_poly = list(pts_left)
    for j in range(steps + 1):
        ang = math.pi - (j / float(steps)) * math.pi
        body_poly.append((rim_cx + math.cos(ang) * rim_rx, rim_cy + math.sin(ang) * rim_ry))
    for pt in reversed(pts_right):
        body_poly.append(pt)

    # 1. Base bell color
    bdraw.polygon(body_poly, fill=(245, 165, 28, 255))

    # 2. Left side highlight polygon
    hi_poly = list(pts_left)
    for pt in reversed(pts_left):
        hx = pt[0] + (loop_cx - pt[0]) * 0.45
        hi_poly.append((hx, pt[1]))
    bdraw.polygon(hi_poly, fill=(255, 207, 77, 255))

    # 3. Specular shine streak on the left flank
    shine_pts = []
    for i in range(8, len(pts_left) - 8):
        pt = pts_left[i]
        sx = pt[0] + (loop_cx - pt[0]) * 0.22
        shine_pts.append((sx, pt[1]))
    if len(shine_pts) > 1:
        bdraw.line(shine_pts, fill=(255, 251, 238, 240), width=int(12 * SS))

    # 4. Right side shadow polygon
    sh_poly = list(pts_right)
    for pt in reversed(pts_right):
        sx = pt[0] - (pt[0] - loop_cx) * 0.42
        sh_poly.append((sx, pt[1]))
    bdraw.polygon(sh_poly, fill=(196, 115, 6, 255))

    # 5. Deep bronze edge on far right
    deep_poly = list(pts_right)
    for pt in reversed(pts_right):
        dx = pt[0] - (pt[0] - loop_cx) * 0.16
        deep_poly.append((dx, pt[1]))
    bdraw.polygon(deep_poly, fill=(138, 70, 0, 255))

    # 6. Grooves clipped inside the bell width!
    def draw_safe_groove(y_frac):
        gy = bell_top_y + y_frac * bell_h
        w_here = get_bell_width_at_frac(y_frac) - int(6 * SS)
        g_pts = []
        g_hi = []
        g_steps = 32
        for s in range(g_steps + 1):
            gf = s / float(g_steps)
            gx = (loop_cx - w_here) + gf * (2 * w_here)
            g_curve = math.sin(gf * math.pi) * (7 * SS)
            g_pts.append((gx, gy + g_curve))
            g_hi.append((gx, gy + g_curve + 3 * SS))
        bdraw.line(g_pts, fill=dark_outline, width=int(4 * SS))
        bdraw.line(g_hi, fill=(255, 230, 130, 220), width=int(2.5 * SS))

    draw_safe_groove(0.25)
    draw_safe_groove(0.50)
    draw_safe_groove(0.75)

    # 7. Interior Dark Cavity (Mouth Opening)
    # Background interior ellipse
    bdraw.ellipse([rim_cx - rim_rx + int(6*SS), rim_cy - rim_ry + int(4*SS),
                   rim_cx + rim_rx - int(6*SS), rim_cy + rim_ry - int(4*SS)], fill=(38, 19, 3, 255))
    bdraw.ellipse([rim_cx - rim_rx + int(24*SS), rim_cy - rim_ry - int(4*SS),
                   rim_cx + rim_rx - int(24*SS), rim_cy + rim_ry - int(12*SS)], fill=(20, 9, 1, 255))

    # 8. Clapper hanging in mouth
    clapper_y = rim_cy + int(12 * SS)
    clapper_r = int(22 * SS)
    bdraw.line([(rim_cx, rim_cy - int(30 * SS)), (rim_cx, clapper_y)], fill=dark_outline, width=int(10 * SS))
    bdraw.line([(rim_cx, rim_cy - int(30 * SS)), (rim_cx, clapper_y)], fill=(75, 42, 12, 255), width=int(5 * SS))

    bdraw.ellipse([rim_cx - clapper_r, clapper_y - clapper_r, rim_cx + clapper_r, clapper_y + clapper_r], fill=(217, 136, 24, 255))
    bdraw.ellipse([rim_cx - clapper_r + int(4*SS), clapper_y - clapper_r + int(3*SS),
                   rim_cx + int(4*SS), clapper_y], fill=(247, 191, 57, 255))
    bdraw.ellipse([rim_cx - int(8*SS), clapper_y - int(8*SS), rim_cx - int(2*SS), clapper_y - int(2*SS)], fill=(255, 244, 186, 255))
    bdraw.arc([rim_cx - clapper_r, clapper_y - clapper_r, rim_cx + clapper_r, clapper_y + clapper_r], start=0, end=360, fill=dark_outline, width=outline_w)

    # 9. Mouth Rim Lip & Highlights
    rim_front_pts = []
    for j in range(steps + 1):
        ang = (j / float(steps)) * math.pi
        rim_front_pts.append((rim_cx + math.cos(ang) * rim_rx, rim_cy + math.sin(ang) * rim_ry))
    bdraw.line(rim_front_pts, fill=dark_outline, width=outline_w)

    rim_hi_pts = []
    for j in range(6, steps - 5):
        ang = 0.15 * math.pi + (j / float(steps)) * 0.70 * math.pi
        rim_hi_pts.append((rim_cx + math.cos(ang) * (rim_rx - int(6 * SS)), rim_cy + math.sin(ang) * (rim_ry - int(5 * SS))))
    if len(rim_hi_pts) > 1:
        bdraw.line(rim_hi_pts, fill=(255, 235, 140, 240), width=int(8 * SS))

    # 10. Outer profile outlines
    bdraw.line(pts_left, fill=dark_outline, width=outline_w)
    bdraw.line(pts_right, fill=dark_outline, width=outline_w)

    # Bell swinging
    if abs(swing_deg) > 0.001:
        bell_im = bell_im.rotate(swing_deg, resample=Image.Resampling.BICUBIC, center=(loop_cx, loop_cy))

    # Composite bell onto main image
    im = Image.alpha_composite(im, bell_im)

    # 11. Chime sound waves (if ringing)
    if chime_level > 0:
        chime_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        cdraw = ImageDraw.Draw(chime_layer)
        # Chime waves radiating out from bell mouth
        # If swing_deg < 0, wave on left; if swing_deg > 0, wave on right
        side = -1 if swing_deg < 0 else 1
        wave_cx = loop_cx + side * int(160 * SS)
        wave_cy = rim_cy
        chime_color = (255, 214, 90, 240)
        chime_color_glow = (255, 180, 40, 140)

        for w_idx in range(chime_level):
            r_dist = int((40 + w_idx * 30) * SS)
            ang_start = 120 if side == -1 else -60
            ang_end = 240 if side == -1 else 60
            cdraw.arc([wave_cx - r_dist, wave_cy - r_dist, wave_cx + r_dist, wave_cy + r_dist],
                      start=ang_start, end=ang_end, fill=chime_color_glow, width=int(14 * SS))
            cdraw.arc([wave_cx - r_dist, wave_cy - r_dist, wave_cx + r_dist, wave_cy + r_dist],
                      start=ang_start, end=ang_end, fill=chime_color, width=int(7 * SS))

        # Star impact burst at clapper impact point
        impact_x = rim_cx + side * int(115 * SS)
        impact_y = rim_cy
        for rot in [0, 45, 90, 135]:
            rad = math.radians(rot)
            dx = math.cos(rad) * int(22 * SS)
            dy = math.sin(rad) * int(22 * SS)
            cdraw.line([(impact_x - dx, impact_y - dy), (impact_x + dx, impact_y + dy)], fill=(255, 255, 220, 255), width=int(6 * SS))
            cdraw.line([(impact_x - dx*0.6, impact_y - dy*0.6), (impact_x + dx*0.6, impact_y + dy*0.6)], fill=(255, 210, 60, 255), width=int(10 * SS))

        im = Image.alpha_composite(im, chime_layer)

    # Downsample with Lanczos
    final_w = W // SS
    final_h = H // SS
    return im.resize((final_w, final_h), resample=Image.Resampling.LANCZOS)

def main():
    os.makedirs(ARTIFACT_DIR, exist_ok=True)
    os.makedirs(GAME_ASSET_DIR, exist_ok=True)
    os.makedirs(MOVING_BELL_DIR, exist_ok=True)

    print("1. Rendering idle cartoon camp bell...")
    bell_img = create_cartoon_bell(swing_deg=0.0, chime_level=0)

    # Save isolated game asset
    game_path = os.path.join(GAME_ASSET_DIR, "cartoon_camp_bell_asset.png")
    bell_img.save(game_path, "PNG")
    print("Saved game asset:", game_path)

    # Also update camp_bell_post.png so in-game world bell uses this exact asset!
    post_game_path = os.path.join(GAME_ASSET_DIR, "camp_bell_post.png")
    bell_img.save(post_game_path, "PNG")
    print("Saved camp_bell_post.png:", post_game_path)

    # Save artifact
    art_path = os.path.join(ARTIFACT_DIR, "cartoon_camp_bell_asset.png")
    bell_img.save(art_path, "PNG")
    print("Saved artifact asset:", art_path)

    # 2. Create presentation card for user review
    card_w = 700
    card_h = 1020
    card = Image.new("RGBA", (card_w, card_h), (20, 16, 12, 255))
    cdraw = ImageDraw.Draw(card)

    glow_cx = 410
    glow_cy = 460
    for r in range(260, 0, -10):
        alpha = int(30 * (1.0 - r / 260.0))
        cdraw.ellipse([glow_cx - r, glow_cy - r, glow_cx + r, glow_cy + r], fill=(255, 190, 80, alpha))

    offset_x = (card_w - bell_img.width) // 2
    offset_y = (card_h - bell_img.height) // 2 + 10
    card.alpha_composite(bell_img, (offset_x, offset_y))

    card_path = os.path.join(ARTIFACT_DIR, "cartoon_camp_bell_preview.png")
    card.save(card_path, "PNG")
    print("Saved presentation card:", card_path)

    # 3. Render 7-frame swinging animation frames matching this exact gallows bell!
    # Frames:
    # 0: idle (0 deg)
    # 1: swing left (-24 deg) with 3 chime waves
    # 2: swing right (+22 deg) with 3 chime waves
    # 3: swing left (-15 deg) with 2 chime waves
    # 4: swing right (+10 deg) with 1 chime wave
    # 5: swing left (-4 deg) settling
    # 6: rest (0 deg)
    anim_configs = [
        (0.0, 0),
        (-24.0, 3),
        (22.0, 3),
        (-15.0, 2),
        (10.0, 1),
        (-4.0, 0),
        (0.0, 0)
    ]

    print("3. Rendering 7 animation frames for moving bell...")
    frame_imgs = []
    for idx, (deg, chime) in enumerate(anim_configs):
        f_img = create_cartoon_bell(swing_deg=deg, chime_level=chime)
        f_path = os.path.join(MOVING_BELL_DIR, f"frame_{idx}.png")
        f_img.save(f_path, "PNG")
        frame_imgs.append(f_img)
        print(f"Saved animation frame {idx}: {f_path}")

    # Create sprite sheet
    sheet_w = bell_img.width * len(frame_imgs)
    sheet_h = bell_img.height
    sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
    for idx, f_img in enumerate(frame_imgs):
        sheet.alpha_composite(f_img, (idx * bell_img.width, 0))

    sheet_game_path = os.path.join(GAME_ASSET_DIR, "moving_bell_ring_sheet.png")
    sheet.save(sheet_game_path, "PNG")
    print("Saved moving bell sprite sheet:", sheet_game_path)

    sheet_art_path = os.path.join(ARTIFACT_DIR, "moving_bell_ring_sheet.png")
    sheet.save(sheet_art_path, "PNG")
    print("Saved artifact sprite sheet:", sheet_art_path)

    print("ALL_ASSETS_SUCCESSFULLY_RENDERED")

if __name__ == "__main__":
    main()
