import os
import math
from PIL import Image, ImageDraw

ICONS_DIR = "assets/customization/icons"
PORTRAIT_DIR = "assets/customization/portrait"
ACTOR_DIR = "assets/customization/actor"

os.makedirs(ICONS_DIR, exist_ok=True)
os.makedirs(PORTRAIT_DIR, exist_ok=True)
os.makedirs(ACTOR_DIR, exist_ok=True)

# ----------------------------------------------------
# Helper drawing functions
# ----------------------------------------------------

def draw_thick_ellipse(draw, bbox, fill, outline="#111111", width=3):
    draw.ellipse(bbox, fill=fill, outline=outline, width=width)

def draw_thick_polygon(draw, points, fill, outline="#111111", width=3):
    draw.polygon(points, fill=fill, outline=outline)
    # Extra outline stroke
    for i in range(len(points)):
        p1 = points[i]
        p2 = points[(i + 1) % len(points)]
        draw.line([p1, p2], fill=outline, width=width)

# ====================================================
# HAT DRAWINGS
# ====================================================

def draw_beanie(canvas_size=(120, 150), center_x=60, top_y=28, scale=1.0):
    """Knit red winter beanie with pompom and folded cuff."""
    img = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    w = int(38 * scale)
    h = int(32 * scale)
    cx = int(center_x)
    cy = int(top_y)
    
    # Dome of beanie
    dome_box = [cx - w, cy, cx + w, cy + h * 2]
    d.pieslice(dome_box, start=180, end=360, fill="#d90429", outline="#111111", width=3)
    
    # White decorative stripes
    d.arc([cx - w + 4, cy + int(10 * scale), cx + w - 4, cy + h * 2 - int(10 * scale)], start=190, end=350, fill="#ffffff", width=int(4 * scale))
    
    # Folded cuff
    cuff_h = int(14 * scale)
    cuff_box = [cx - w - 2, cy + h - int(4 * scale), cx + w + 2, cy + h + cuff_h]
    d.rounded_rectangle(cuff_box, radius=int(6 * scale), fill="#b00020", outline="#111111", width=3)
    # Cuff ribbing
    for rx in range(cx - w + 4, cx + w, int(7 * scale)):
        d.line([(rx, cy + h - int(2 * scale)), (rx, cy + h + cuff_h - 2)], fill="#800016", width=2)

    # Fluffy pompom on top
    pompom_r = int(10 * scale)
    p_box = [cx - pompom_r, cy - pompom_r, cx + pompom_r, cy + pompom_r]
    d.ellipse(p_box, fill="#ffffff", outline="#111111", width=3)
    
    return img

def draw_cowboy(canvas_size=(120, 150), center_x=60, top_y=30, scale=1.0):
    """Wild west / camp ranger cowboy hat."""
    img = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    cx = int(center_x)
    cy = int(top_y)
    
    # Crown of hat
    cw = int(24 * scale)
    ch = int(28 * scale)
    crown_pts = [
        (cx - cw + 2, cy + ch),
        (cx - cw - 2, cy + int(8 * scale)),
        (cx - int(12 * scale), cy),
        (cx, cy + int(5 * scale)), # Crease in middle
        (cx + int(12 * scale), cy),
        (cx + cw + 2, cy + int(8 * scale)),
        (cx + cw - 2, cy + ch),
    ]
    draw_thick_polygon(d, crown_pts, fill="#8c5835", outline="#111111", width=3)
    
    # Hat band (dark leather with gold buckle)
    band_pts = [
        (cx - cw + 2, cy + ch),
        (cx - cw, cy + ch - int(7 * scale)),
        (cx + cw, cy + ch - int(7 * scale)),
        (cx + cw - 2, cy + ch),
    ]
    draw_thick_polygon(d, band_pts, fill="#4a2810", outline="#111111", width=2)
    # Gold buckle
    d.rectangle([cx - int(4 * scale), cy + ch - int(8 * scale), cx + int(4 * scale), cy + ch + int(1 * scale)], fill="#ffd166", outline="#111111", width=2)

    # Wide curved brim
    bw = int(46 * scale)
    bh = int(14 * scale)
    brim_box = [cx - bw, cy + ch - int(6 * scale), cx + bw, cy + ch + bh]
    d.ellipse(brim_box, fill="#a0653d", outline="#111111", width=3)
    # Curved brim highlight
    d.arc([cx - bw + 4, cy + ch - int(4 * scale), cx + bw - 4, cy + ch + bh - 4], start=20, end=160, fill="#c48a5e", width=int(3 * scale))

    return img

def draw_bandana(canvas_size=(120, 150), center_x=60, top_y=42, scale=1.0):
    """Red survivor bandana tied across forehead."""
    img = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    cx = int(center_x)
    cy = int(top_y)
    
    bw = int(34 * scale)
    bh = int(13 * scale)
    
    # Main forehead band
    band_box = [cx - bw, cy, cx + bw, cy + bh]
    d.rounded_rectangle(band_box, radius=int(5 * scale), fill="#e63946", outline="#111111", width=3)
    
    # White paisley dots
    for dot_x in range(cx - bw + int(7 * scale), cx + bw - int(4 * scale), int(9 * scale)):
        d.ellipse([dot_x - 1, cy + int(4 * scale), dot_x + 1, cy + int(6 * scale)], fill="#ffffff")
    
    # Side knot and tails
    knot_x = cx + bw - int(4 * scale)
    knot_y = cy + int(7 * scale)
    d.ellipse([knot_x - int(5 * scale), knot_y - int(5 * scale), knot_x + int(5 * scale), knot_y + int(5 * scale)], fill="#b00020", outline="#111111", width=2)
    # Hanging tails
    tail1 = [(knot_x, knot_y), (knot_x + int(12 * scale), knot_y + int(14 * scale)), (knot_x + int(4 * scale), knot_y + int(18 * scale))]
    tail2 = [(knot_x, knot_y), (knot_x + int(7 * scale), knot_y + int(20 * scale)), (knot_x - int(2 * scale), knot_y + int(16 * scale))]
    draw_thick_polygon(d, tail1, fill="#e63946", outline="#111111", width=2)
    draw_thick_polygon(d, tail2, fill="#b00020", outline="#111111", width=2)

    return img

def draw_flower_crown(canvas_size=(120, 150), center_x=60, top_y=38, scale=1.0):
    """Nature flower crown with daisies and leaves."""
    img = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    cx = int(center_x)
    cy = int(top_y)
    
    bw = int(32 * scale)
    
    # Green vine band
    d.arc([cx - bw, cy - int(4 * scale), cx + bw, cy + int(16 * scale)], start=200, end=340, fill="#2d6a4f", width=int(4 * scale))
    
    # Daisies across crown
    flower_positions = [
        (cx - int(24 * scale), cy + int(6 * scale)),
        (cx - int(12 * scale), cy + int(2 * scale)),
        (cx, cy),
        (cx + int(12 * scale), cy + int(2 * scale)),
        (cx + int(24 * scale), cy + int(6 * scale)),
    ]
    
    for fx, fy in flower_positions:
        # Green leaf behind
        d.ellipse([fx - int(7 * scale), fy - int(3 * scale), fx + int(7 * scale), fy + int(3 * scale)], fill="#52b788", outline="#111111", width=1)
        # 5 White petals
        for angle in range(0, 360, 72):
            rad = math.radians(angle)
            px = fx + math.cos(rad) * (5 * scale)
            py = fy + math.sin(rad) * (5 * scale)
            d.ellipse([px - int(3 * scale), py - int(3 * scale), px + int(3 * scale), py + int(3 * scale)], fill="#ffffff", outline="#111111", width=1)
        # Golden center
        d.ellipse([fx - int(3 * scale), fy - int(3 * scale), fx + int(3 * scale), fy + int(3 * scale)], fill="#ffd166", outline="#111111", width=2)

    return img

def draw_bear_ears(canvas_size=(120, 150), center_x=60, top_y=32, scale=1.0):
    """Cute furry brown bear ears headband."""
    img = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    cx = int(center_x)
    cy = int(top_y)
    
    # Headband arc
    bw = int(28 * scale)
    d.arc([cx - bw, cy + int(4 * scale), cx + bw, cy + int(28 * scale)], start=190, end=350, fill="#222222", width=int(4 * scale))
    
    # Left Ear & Right Ear
    ear_r = int(12 * scale)
    left_ear_center = (cx - int(22 * scale), cy + int(4 * scale))
    right_ear_center = (cx + int(22 * scale), cy + int(4 * scale))
    
    for ex, ey in [left_ear_center, right_ear_center]:
        # Outer ear (brown)
        d.ellipse([ex - ear_r, ey - ear_r, ex + ear_r, ey + ear_r], fill="#7f4f24", outline="#111111", width=3)
        # Inner ear (soft tan/pink)
        inner_r = int(6 * scale)
        d.ellipse([ex - inner_r, ey - inner_r + int(1 * scale), ex + inner_r, ey + inner_r + int(1 * scale)], fill="#d4a373", outline="#111111", width=2)

    return img

def draw_detective(canvas_size=(120, 150), center_x=60, top_y=30, scale=1.0):
    """Classic detective fedora hat."""
    img = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    cx = int(center_x)
    cy = int(top_y)
    
    # Crown
    cw = int(23 * scale)
    ch = int(24 * scale)
    crown_pts = [
        (cx - cw + 2, cy + ch),
        (cx - cw - 1, cy + int(6 * scale)),
        (cx - int(8 * scale), cy),
        (cx, cy + int(4 * scale)),
        (cx + int(8 * scale), cy),
        (cx + cw + 1, cy + int(6 * scale)),
        (cx + cw - 2, cy + ch),
    ]
    draw_thick_polygon(d, crown_pts, fill="#495057", outline="#111111", width=3)
    
    # Black ribbon band
    band_box = [cx - cw + 1, cy + ch - int(7 * scale), cx + cw - 1, cy + ch]
    d.rectangle(band_box, fill="#1a1a1a", outline="#111111", width=2)

    # Snappy fedora brim (angled)
    bw = int(38 * scale)
    bh = int(12 * scale)
    brim_box = [cx - bw, cy + ch - int(5 * scale), cx + bw, cy + ch + bh]
    d.ellipse(brim_box, fill="#6c757d", outline="#111111", width=3)
    
    return img

# ====================================================
# OUTFIT DRAWINGS
# ====================================================

def draw_flannel(canvas_size=(120, 150), center_x=60, top_y=88, scale=1.0):
    """Lumberjack red & black plaid flannel vest."""
    img = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    cx = int(center_x)
    cy = int(top_y)
    
    w = int(24 * scale)
    h = int(30 * scale)
    
    # Vest base shape (covers chest/torso)
    vest_pts = [
        (cx - int(15 * scale), cy),
        (cx - w, cy + int(6 * scale)),
        (cx - w + 2, cy + h),
        (cx + w - 2, cy + h),
        (cx + w, cy + int(6 * scale)),
        (cx + int(15 * scale), cy),
        (cx, cy + int(8 * scale)), # V-neck cutout
    ]
    draw_thick_polygon(d, vest_pts, fill="#c1121f", outline="#111111", width=3)
    
    # Plaid grid lines (black/dark red)
    # Vertical plaid lines
    for vx in [cx - int(12 * scale), cx, cx + int(12 * scale)]:
        d.line([(vx, cy + int(8 * scale)), (vx, cy + h)], fill="#4a0404", width=int(3 * scale))
    # Horizontal plaid lines
    for vy in [cy + int(12 * scale), cy + int(21 * scale)]:
        d.line([(cx - w + 4, vy), (cx + w - 4, vy)], fill="#4a0404", width=int(3 * scale))
        
    # Center seam & buttons
    d.line([(cx, cy + int(8 * scale)), (cx, cy + h)], fill="#111111", width=2)
    for by in [cy + int(13 * scale), cy + int(20 * scale), cy + int(27 * scale)]:
        d.ellipse([cx - 2, by - 2, cx + 2, by + 2], fill="#ffd166", outline="#111111", width=1)

    return img

def draw_scout_sash(canvas_size=(120, 150), center_x=60, top_y=84, scale=1.0):
    """Wilderness scout sash with merit badges."""
    img = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    cx = int(center_x)
    cy = int(top_y)
    
    # Diagonal sash from right shoulder (cx + 18) to left hip (cx - 22)
    sash_pts = [
        (cx + int(14 * scale), cy),
        (cx + int(22 * scale), cy + int(4 * scale)),
        (cx - int(14 * scale), cy + int(36 * scale)),
        (cx - int(22 * scale), cy + int(32 * scale)),
    ]
    draw_thick_polygon(d, sash_pts, fill="#c7b198", outline="#111111", width=3)
    
    # Merit Badges (colorful little embroidered circles)
    badge_data = [
        (cx + int(14 * scale), cy + int(8 * scale), "#52b788"),   # Green
        (cx + int(6 * scale), cy + int(15 * scale), "#ffd166"),   # Gold
        (cx - int(2 * scale), cy + int(22 * scale), "#e63946"),   # Red
        (cx - int(10 * scale), cy + int(29 * scale), "#118ab2"),  # Blue
    ]
    for bx, by, col in badge_data:
        d.ellipse([bx - int(3 * scale), by - int(3 * scale), bx + int(3 * scale), by + int(3 * scale)], fill=col, outline="#111111", width=2)

    return img

def draw_hoodie(canvas_size=(120, 150), center_x=60, top_y=85, scale=1.0):
    """Forest green cozy winter hoodie with drawstrings."""
    img = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    cx = int(center_x)
    cy = int(top_y)
    
    w = int(24 * scale)
    h = int(32 * scale)
    
    # Hoodie body
    hoodie_pts = [
        (cx - int(14 * scale), cy),
        (cx - w, cy + int(6 * scale)),
        (cx - w + 2, cy + h),
        (cx + w - 2, cy + h),
        (cx + w, cy + int(6 * scale)),
        (cx + int(14 * scale), cy),
        (cx, cy + int(4 * scale)),
    ]
    draw_thick_polygon(d, hoodie_pts, fill="#2d6a4f", outline="#111111", width=3)
    
    # Kangaroo pocket
    pocket_w = int(14 * scale)
    pocket_h = int(11 * scale)
    pocket_box = [cx - pocket_w, cy + h - pocket_h - int(2 * scale), cx + pocket_w, cy + h - int(2 * scale)]
    d.rounded_rectangle(pocket_box, radius=int(3 * scale), fill="#1b4332", outline="#111111", width=2)

    # White drawstrings
    d.line([(cx - int(5 * scale), cy + int(4 * scale)), (cx - int(5 * scale), cy + int(18 * scale))], fill="#ffffff", width=int(2 * scale))
    d.line([(cx + int(5 * scale), cy + int(4 * scale)), (cx + int(5 * scale), cy + int(18 * scale))], fill="#ffffff", width=int(2 * scale))
    d.ellipse([cx - int(6 * scale), cy + int(17 * scale), cx - int(4 * scale), cy + int(19 * scale)], fill="#ffd166")
    d.ellipse([cx + int(4 * scale), cy + int(17 * scale), cx + int(6 * scale), cy + int(19 * scale)], fill="#ffd166")

    return img

def draw_necktie(canvas_size=(120, 150), center_x=60, top_y=82, scale=1.0):
    """Detective necktie with crisp white collar."""
    img = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    
    cx = int(center_x)
    cy = int(top_y)
    
    # White collar
    left_collar = [(cx - int(12 * scale), cy), (cx - 2, cy + int(6 * scale)), (cx - int(8 * scale), cy + int(8 * scale))]
    right_collar = [(cx + int(12 * scale), cy), (cx + 2, cy + int(6 * scale)), (cx + int(8 * scale), cy + int(8 * scale))]
    draw_thick_polygon(d, left_collar, fill="#ffffff", outline="#111111", width=2)
    draw_thick_polygon(d, right_collar, fill="#ffffff", outline="#111111", width=2)
    
    # Tie knot
    knot = [
        (cx - int(4 * scale), cy + int(5 * scale)),
        (cx + int(4 * scale), cy + int(5 * scale)),
        (cx + int(3 * scale), cy + int(10 * scale)),
        (cx - int(3 * scale), cy + int(10 * scale)),
    ]
    draw_thick_polygon(d, knot, fill="#9b2226", outline="#111111", width=2)

    # Tie body & point
    tie = [
        (cx - int(3 * scale), cy + int(10 * scale)),
        (cx + int(3 * scale), cy + int(10 * scale)),
        (cx + int(5 * scale), cy + int(28 * scale)),
        (cx, cy + int(34 * scale)), # Pointed bottom
        (cx - int(5 * scale), cy + int(28 * scale)),
    ]
    draw_thick_polygon(d, tie, fill="#ae2012", outline="#111111", width=2)
    
    # Diagonal gold stripes on tie
    for sy in [cy + int(14 * scale), cy + int(20 * scale), cy + int(26 * scale)]:
        d.line([(cx - int(4 * scale), sy), (cx + int(4 * scale), sy - int(3 * scale))], fill="#ffd166", width=2)

    return img

# ====================================================
# GENERATE ALL ASSETS
# ====================================================

HATS = {
    "beanie": draw_beanie,
    "cowboy": draw_cowboy,
    "bandana": draw_bandana,
    "flower_crown": draw_flower_crown,
    "bear_ears": draw_bear_ears,
    "detective": draw_detective,
}

OUTFITS = {
    "flannel": draw_flannel,
    "scout_sash": draw_scout_sash,
    "hoodie": draw_hoodie,
    "necktie": draw_necktie,
}

def create_item_icon(draw_func, is_hat=True):
    """Render a clean 64x64 item icon centered."""
    icon_img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    # Render with custom center/scale to fit 64x64
    if is_hat:
        rendered = draw_func(canvas_size=(64, 64), center_x=32, top_y=14, scale=0.85)
    else:
        rendered = draw_func(canvas_size=(64, 64), center_x=32, top_y=16, scale=0.85)
    return rendered

print("Generating Hat assets...")
for hat_id, func in HATS.items():
    # 1. Portrait overlay (120x150)
    p_img = func(canvas_size=(120, 150), center_x=60, top_y=30, scale=1.0)
    p_path = os.path.join(PORTRAIT_DIR, f"{hat_id}.png")
    p_img.save(p_path)
    
    # 2. In-game Actor sprite (120x150)
    a_img = func(canvas_size=(120, 150), center_x=60, top_y=28, scale=0.95)
    a_path = os.path.join(ACTOR_DIR, f"{hat_id}.png")
    a_img.save(a_path)
    
    # 3. Icon (64x64)
    i_img = create_item_icon(func, is_hat=True)
    i_path = os.path.join(ICONS_DIR, f"{hat_id}.png")
    i_img.save(i_path)
    print(f"  [OK] {hat_id}")

print("Generating Outfit assets...")
for outfit_id, func in OUTFITS.items():
    # 1. Portrait overlay (120x150)
    p_img = func(canvas_size=(120, 150), center_x=60, top_y=84, scale=1.0)
    p_path = os.path.join(PORTRAIT_DIR, f"{outfit_id}.png")
    p_img.save(p_path)
    
    # 2. In-game Actor sprite (120x150)
    a_img = func(canvas_size=(120, 150), center_x=60, top_y=82, scale=0.95)
    a_path = os.path.join(ACTOR_DIR, f"{outfit_id}.png")
    a_img.save(a_path)
    
    # 3. Icon (64x64)
    i_img = create_item_icon(func, is_hat=False)
    i_path = os.path.join(ICONS_DIR, f"{outfit_id}.png")
    i_img.save(i_path)
    print(f"  [OK] {outfit_id}")

# Also generate "none" icons (simple red slash / clear symbol)
none_icon = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
d = ImageDraw.Draw(none_icon)
d.ellipse([14, 14, 50, 50], outline="#e63946", width=4)
d.line([(22, 22), (42, 42)], fill="#e63946", width=4)
none_icon.save(os.path.join(ICONS_DIR, "none.png"))
print("  [OK] none.png icon")

print("All wardrobe assets successfully generated!")
