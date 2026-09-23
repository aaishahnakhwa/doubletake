import os
import math
from PIL import Image, ImageDraw

SKINS_ROOT = "assets/skins"
ICONS_DIR = os.path.join(SKINS_ROOT, "icons")
os.makedirs(ICONS_DIR, exist_ok=True)

COLORS = ["orange", "blue", "green", "red", "purple", "yellow"]
LOOKS = ["classic", "ranger", "winter", "detective", "scout"]

for look in LOOKS:
    os.makedirs(os.path.join(SKINS_ROOT, look), exist_ok=True)

def draw_thick_polygon(draw, points, fill, outline="#111111", width=3):
    draw.polygon(points, fill=fill, outline=outline)
    for i in range(len(points)):
        p1 = points[i]
        p2 = points[(i + 1) % len(points)]
        draw.line([p1, p2], fill=outline, width=width)

# ====================================================
# LOOK ARTWORK COMPOSITORS
# ====================================================

def create_ranger_skin(base_img):
    """Camp Ranger / Cowboy: Wide-brim hat, ranger vest with gold star badge."""
    img = base_img.copy()
    d = ImageDraw.Draw(img)
    
    cx, cy = 60, 22
    
    # 1. Crown of Ranger Hat
    cw, ch = 25, 26
    crown_pts = [
        (cx - cw + 2, cy + ch),
        (cx - cw - 2, cy + 8),
        (cx - 12, cy),
        (cx, cy + 5),     # Crease in center
        (cx + 12, cy),
        (cx + cw + 2, cy + 8),
        (cx + cw - 2, cy + ch),
    ]
    draw_thick_polygon(d, crown_pts, fill="#7f4f24", outline="#111111", width=3)
    
    # Hat band (dark leather)
    band_pts = [
        (cx - cw + 1, cy + ch),
        (cx - cw, cy + ch - 7),
        (cx + cw, cy + ch - 7),
        (cx + cw - 1, cy + ch),
    ]
    draw_thick_polygon(d, band_pts, fill="#432818", outline="#111111", width=2)
    # Gold star badge on hat
    d.rectangle([cx - 4, cy + ch - 8, cx + 4, cy + ch + 1], fill="#ffd166", outline="#111111", width=2)

    # 2. Wide curved brim (completely covers old baseball cap)
    bw, bh = 46, 16
    brim_box = [cx - bw, cy + ch - 7, cx + bw, cy + ch + bh]
    d.ellipse(brim_box, fill="#936639", outline="#111111", width=3)
    # Brim contour highlight
    d.arc([cx - bw + 4, cy + ch - 5, cx + bw - 4, cy + ch + bh - 4], start=20, end=160, fill="#b08968", width=3)

    # 3. Ranger Utility Vest on Torso
    vx, vy = 60, 84
    vw, vh = 24, 28
    vest_pts = [
        (vx - 14, vy),
        (vx - vw, vy + 6),
        (vx - vw + 2, vy + vh),
        (vx + vw - 2, vy + vh),
        (vx + vw, vy + 6),
        (vx + 14, vy),
        (vx, vy + 8), # V-neck cutout
    ]
    draw_thick_polygon(d, vest_pts, fill="#58412b", outline="#111111", width=3)
    # Center seam
    d.line([(vx, vy + 8), (vx, vy + vh)], fill="#271b12", width=2)
    
    # Pockets on vest
    d.rounded_rectangle([vx - 20, vy + 14, vx - 6, vy + 24], radius=2, fill="#432818", outline="#111111", width=2)
    d.rounded_rectangle([vx + 6, vy + 14, vx + 20, vy + 24], radius=2, fill="#432818", outline="#111111", width=2)

    # Shiny Gold Ranger Badge on left chest
    d.polygon([(vx - 13, vy + 4), (vx - 10, vy + 10), (vx - 16, vy + 10)], fill="#ffd166", outline="#111111")
    
    return img


def create_winter_skin(base_img):
    """Winter Camper: Cozy knit pompom beanie, warm scarf, puffer jacket."""
    img = base_img.copy()
    d = ImageDraw.Draw(img)
    
    cx, cy = 60, 18
    w, h = 36, 32
    
    # 1. Beanie Dome (covers head and old cap)
    dome_box = [cx - w, cy, cx + w, cy + h * 2]
    d.pieslice(dome_box, start=180, end=360, fill="#c1121f", outline="#111111", width=3)
    
    # White knit pattern band
    d.arc([cx - w + 4, cy + 10, cx + w - 4, cy + h * 2 - 10], start=190, end=350, fill="#ffffff", width=4)
    
    # Folded ribbed cuff (over forehead, just above eyes)
    cuff_box = [cx - w - 2, cy + h - 4, cx + w + 2, cy + h + 13]
    d.rounded_rectangle(cuff_box, radius=6, fill="#780000", outline="#111111", width=3)
    # Ribbing lines
    for rx in range(cx - w + 4, cx + w, 7):
        d.line([(rx, cy + h - 2), (rx, cy + h + 11)], fill="#500000", width=2)

    # Fluffy pompom on top
    p_box = [cx - 10, cy - 10, cx + 10, cy + 10]
    d.ellipse(p_box, fill="#ffffff", outline="#111111", width=3)

    # 2. Cozy Winter Scarf around neck
    sx, sy = 60, 78
    # Scarf wrap loop
    d.rounded_rectangle([sx - 24, sy, sx + 24, sy + 15], radius=7, fill="#003049", outline="#111111", width=3)
    # White striped pattern on scarf
    d.line([(sx - 12, sy + 2), (sx - 12, sy + 13)], fill="#fdf0d5", width=3)
    d.line([(sx + 12, sy + 2), (sx + 12, sy + 13)], fill="#fdf0d5", width=3)
    
    # Hanging scarf tail
    tail_pts = [
        (sx - 18, sy + 12),
        (sx - 6, sy + 12),
        (sx - 8, sy + 36),
        (sx - 20, sy + 36),
    ]
    draw_thick_polygon(d, tail_pts, fill="#003049", outline="#111111", width=2)
    # Fringe on scarf end
    for fx in range(sx - 19, sx - 7, 3):
        d.line([(fx, sy + 36), (fx, sy + 40)], fill="#fdf0d5", width=2)

    # Puffer jacket zipper
    d.line([(sx + 6, sy + 15), (sx + 6, sy + 38)], fill="#111111", width=2)

    return img


def create_detective_skin(base_img):
    """Camp Detective: Sleek fedora hat, detective coat, white collar & red tie."""
    img = base_img.copy()
    d = ImageDraw.Draw(img)
    
    cx, cy = 60, 22
    
    # 1. Fedora Crown
    cw, ch = 24, 24
    crown_pts = [
        (cx - cw + 2, cy + ch),
        (cx - cw - 1, cy + 6),
        (cx - 8, cy),
        (cx, cy + 4),
        (cx + 8, cy),
        (cx + cw + 1, cy + 6),
        (cx + cw - 2, cy + ch),
    ]
    draw_thick_polygon(d, crown_pts, fill="#343a40", outline="#111111", width=3)
    
    # Black satin ribbon band
    d.rectangle([cx - cw + 1, cy + ch - 7, cx + cw - 1, cy + ch], fill="#111111", outline="#111111", width=1)

    # Fedora Brim
    bw, bh = 40, 14
    brim_box = [cx - bw, cy + ch - 6, cx + bw, cy + ch + bh]
    d.ellipse(brim_box, fill="#495057", outline="#111111", width=3)

    # 2. Detective Coat Lapels & Collar on Torso
    vx, vy = 60, 80
    
    # White shirt collar
    left_col = [(vx - 12, vy), (vx - 2, vy + 7), (vx - 9, vy + 9)]
    right_col = [(vx + 12, vy), (vx + 2, vy + 7), (vx + 9, vy + 9)]
    draw_thick_polygon(d, left_col, fill="#ffffff", outline="#111111", width=2)
    draw_thick_polygon(d, right_col, fill="#ffffff", outline="#111111", width=2)

    # Red Detective Necktie
    knot = [(vx - 4, vy + 6), (vx + 4, vy + 6), (vx + 3, vy + 11), (vx - 3, vy + 11)]
    draw_thick_polygon(d, knot, fill="#9b2226", outline="#111111", width=2)
    tie = [
        (vx - 3, vy + 11),
        (vx + 3, vy + 11),
        (vx + 5, vy + 28),
        (vx, vy + 34),
        (vx - 5, vy + 28),
    ]
    draw_thick_polygon(d, tie, fill="#ae2012", outline="#111111", width=2)
    # Gold tie clip
    d.line([(vx - 4, vy + 18), (vx + 4, vy + 18)], fill="#ffd166", width=2)

    # Detective Coat Lapels (framing tie)
    lapel_l = [(vx - 22, vy + 2), (vx - 10, vy + 16), (vx - 18, vy + 32), (vx - 24, vy + 20)]
    lapel_r = [(vx + 22, vy + 2), (vx + 10, vy + 16), (vx + 18, vy + 32), (vx + 24, vy + 20)]
    draw_thick_polygon(d, lapel_l, fill="#343a40", outline="#111111", width=2)
    draw_thick_polygon(d, lapel_r, fill="#343a40", outline="#111111", width=2)

    return img


def create_scout_skin(base_img):
    """Wilderness Scout: Scout beret with emblem, neckerchief, merit badge sash."""
    img = base_img.copy()
    d = ImageDraw.Draw(img)
    
    cx, cy = 60, 24
    
    # 1. Scout Beret (angled slightly to the right)
    beret_box = [cx - 30, cy, cx + 34, cy + 26]
    d.ellipse(beret_box, fill="#2d6a4f", outline="#111111", width=3)
    # Beret headband band
    d.arc([cx - 28, cy + 4, cx + 32, cy + 28], start=20, end=160, fill="#1b4332", width=4)
    # Gold Scout Emblem on beret
    d.ellipse([cx - 16, cy + 8, cx - 8, cy + 16], fill="#ffd166", outline="#111111", width=2)

    # 2. Scout Neckerchief around neck
    vx, vy = 60, 80
    # Neckerchief triangle
    neck_pts = [
        (vx - 16, vy),
        (vx + 16, vy),
        (vx, vy + 14),
    ]
    draw_thick_polygon(d, neck_pts, fill="#d4a373", outline="#111111", width=2)
    # Gold slide ring (woggle)
    d.rectangle([vx - 3, vy + 8, vx + 3, vy + 13], fill="#ffd166", outline="#111111", width=2)
    # Neckerchief tips hanging down
    d.polygon([(vx - 4, vy + 13), (vx - 1, vy + 22), (vx - 6, vy + 20)], fill="#bc6c25", outline="#111111")
    d.polygon([(vx + 4, vy + 13), (vx + 1, vy + 22), (vx + 6, vy + 20)], fill="#bc6c25", outline="#111111")

    # 3. Merit Badge Sash (diagonal across chest from right shoulder to left hip)
    sash_pts = [
        (vx + 14, vy + 2),
        (vx + 23, vy + 6),
        (vx - 13, vy + 36),
        (vx - 22, vy + 32),
    ]
    draw_thick_polygon(d, sash_pts, fill="#c7b198", outline="#111111", width=3)
    
    # Colorful embroidered merit badges
    badges = [
        (vx + 14, vy + 9, "#52b788"),   # Green (Campcraft)
        (vx + 6, vy + 16, "#ffd166"),   # Gold (First Aid)
        (vx - 2, vy + 23, "#e63946"),   # Red (Fire Building)
        (vx - 10, vy + 30, "#118ab2"),  # Blue (Navigation)
    ]
    for bx, by, col in badges:
        d.ellipse([bx - 3, by - 3, bx + 3, by + 3], fill=col, outline="#111111", width=2)

    return img


def clear_cap(base_img):
    img = base_img.copy()
    w, h = img.size
    cpix = img.load()
    for y in range(h):
        for x in range(w):
            # 1. Cap dome on top of head
            if y < 46 and x < 92:
                cpix[x, y] = (0, 0, 0, 0)
            # 2. Backwards visor sticking out to the left
            if x <= 34 and 25 <= y <= 64:
                cpix[x, y] = (0, 0, 0, 0)
            # 3. Upward horn curl sticking out above hats
            if y < 38 and x >= 85:
                cpix[x, y] = (0, 0, 0, 0)
    return img

LOOK_PROCESSORS = {
    "classic": lambda img: img.copy(),
    "ranger": lambda img: create_ranger_skin(clear_cap(img)),
    "winter": lambda img: create_winter_skin(clear_cap(img)),
    "detective": lambda img: create_detective_skin(clear_cap(img)),
    "scout": lambda img: create_scout_skin(clear_cap(img)),
}

print("Generating cohesive character skin sprites...")

for color in COLORS:
    src_portrait = f"assets/phase5/portraits/{color}.png"
    if not os.path.exists(src_portrait):
        print(f"  Warning: Missing {src_portrait}")
        continue
    base_img = Image.open(src_portrait).convert("RGBA")
    
    for look_id, func in LOOK_PROCESSORS.items():
        skin_img = func(base_img)
        dst_path = os.path.join(SKINS_ROOT, look_id, f"{color}.png")
        skin_img.save(dst_path)
        print(f"  [OK] {look_id}/{color}.png")

# Generate 64x64 Icons for each look (using orange as showcase)
orange_base = Image.open("assets/phase5/portraits/orange.png").convert("RGBA")
for look_id, func in LOOK_PROCESSORS.items():
    full_skin = func(orange_base)
    # Crop head and upper torso for icon
    crop_box = (20, 10, 100, 90) # (left, top, right, bottom)
    cropped = full_skin.crop(crop_box)
    icon_img = cropped.resize((64, 64), Image.Resampling.LANCZOS)
    icon_path = os.path.join(ICONS_DIR, f"{look_id}.png")
    icon_img.save(icon_path)
    print(f"  [OK] icon: {look_id}.png")

print("All skin assets successfully generated!")
