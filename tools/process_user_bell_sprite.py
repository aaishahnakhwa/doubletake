from PIL import Image
import os

ARTIFACT_DIR = r"C:\Users\saule\.gemini\antigravity\brain\17a13079-7005-4717-99fb-b563640774d7"
GAME_ASSET_DIR = r"c:\Users\saule\OneDrive\Documents\double-take\assets\phase5"
MOVING_BELL_DIR = r"c:\Users\saule\OneDrive\Documents\double-take\assets\phase5\moving_bell"

img_path = os.path.join(ARTIFACT_DIR, r".user_uploaded\media_1790001255845.png")
im = Image.open(img_path).convert("RGBA")
w, h = im.size

# The 4 frames in the user's sprite sheet:
# Frame 0: Swing Left
# Frame 1: Center (Rest)
# Frame 2: Swing Right
# Frame 3: Center (Slight settle)
frame_x_ranges = [
    (15, 245),   # Frame 0: Swing left
    (266, 490),  # Frame 1: Center
    (524, 775),  # Frame 2: Swing right
    (778, 1000)  # Frame 3: Center
]

# Find post cap anchor (top-left of the post cap) in each frame
post_anchors = []
for idx, (sx, ex) in enumerate(frame_x_ranges):
    top_pixels = []
    for y in range(148, 175):
        for x in range(sx, sx + 70):
            if im.getpixel((x, y))[3] > 100:
                top_pixels.append((x, y))
    min_x = min(p[0] for p in top_pixels)
    min_y = min(p[1] for p in top_pixels)
    post_anchors.append((min_x, min_y))
    print(f"Frame {idx}: Post anchor at ({min_x}, {min_y})")

# Determine required canvas size
# Max offset to right from post anchor:
max_right_offset = 0
max_down_offset = 0
for idx, (min_x, min_y) in enumerate(post_anchors):
    sx, ex = frame_x_ranges[idx]
    for x in range(sx, ex + 1):
        for y in range(148, h):
            if im.getpixel((x, y))[3] > 10:
                dx = x - min_x
                dy = y - min_y
                if dx > max_right_offset: max_right_offset = dx
                if dy > max_down_offset: max_down_offset = dy

print(f"Max right offset: {max_right_offset}, max down offset: {max_down_offset}")

# Set unified canvas size with padding
pad_x = 20
pad_y = 15
CANVAS_W = max_right_offset + pad_x + 25
CANVAS_H = max_down_offset + pad_y + 20
print(f"Unified Canvas size: {CANVAS_W} x {CANVAS_H}")

# Extract and align the 4 raw frames
raw_frames = []
for idx, (min_x, min_y) in enumerate(post_anchors):
    frame_canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    sx, ex = frame_x_ranges[idx]
    
    # Copy pixels with anchor mapped to (pad_x, pad_y)
    for x in range(sx, ex + 1):
        for y in range(140, h):
            px = im.getpixel((x, y))
            if px[3] > 5:
                dst_x = pad_x + (x - min_x)
                dst_y = pad_y + (y - min_y)
                if 0 <= dst_x < CANVAS_W and 0 <= dst_y < CANVAS_H:
                    frame_canvas.putpixel((dst_x, dst_y), px)
    raw_frames.append(frame_canvas)

# Let's verify:
# raw_frames[0]: Swing Left
# raw_frames[1]: Center (Idle)
# raw_frames[2]: Swing Right
# raw_frames[3]: Center (Slight settle)

os.makedirs(MOVING_BELL_DIR, exist_ok=True)
os.makedirs(GAME_ASSET_DIR, exist_ok=True)
os.makedirs(ARTIFACT_DIR, exist_ok=True)

# Save the primary idle asset (Center frame)
idle_asset = raw_frames[1]
idle_path = os.path.join(GAME_ASSET_DIR, "camp_bell_post.png")
idle_asset.save(idle_path, "PNG")
idle_asset.save(os.path.join(ARTIFACT_DIR, "camp_bell_post.png"), "PNG")
print("Saved camp_bell_post.png (Idle):", idle_path)

# Build the swinging sequence:
# Frame 0: Center (Idle at rest)
# Frame 1: Swing Left
# Frame 2: Center
# Frame 3: Swing Right
# Frame 4: Center
# Frame 5: Swing Left
# Frame 6: Swing Right
# Frame 7: Center (Settle to rest)
anim_sequence = [
    raw_frames[1], # Frame 0: Center (idle)
    raw_frames[0], # Frame 1: Swing left
    raw_frames[1], # Frame 2: Center
    raw_frames[2], # Frame 3: Swing right
    raw_frames[3], # Frame 4: Center settle
    raw_frames[0], # Frame 5: Swing left
    raw_frames[2], # Frame 6: Swing right
    raw_frames[1], # Frame 7: Center rest
]

for i, f_img in enumerate(anim_sequence):
    f_path = os.path.join(MOVING_BELL_DIR, f"frame_{i}.png")
    f_img.save(f_path, "PNG")
    print(f"Saved moving_bell frame_{i}.png")

# Also save the full animation sprite sheet
sheet_w = CANVAS_W * len(anim_sequence)
sheet_h = CANVAS_H
sheet = Image.new("RGBA", (sheet_w, sheet_h), (0, 0, 0, 0))
for i, f_img in enumerate(anim_sequence):
    sheet.paste(f_img, (i * CANVAS_W, 0), f_img)

sheet_game_path = os.path.join(GAME_ASSET_DIR, "moving_bell_ring_sheet.png")
sheet.save(sheet_game_path, "PNG")
sheet.save(os.path.join(ARTIFACT_DIR, "moving_bell_ring_sheet.png"), "PNG")
print("Saved moving_bell_ring_sheet.png:", sheet_game_path)

# Create a presentation preview card
card_w = 600
card_h = 700
card = Image.new("RGBA", (card_w, card_h), (22, 17, 13, 255))
cdraw = Image.new("RGBA", (card_w, card_h), (0, 0, 0, 0))

# Composite idle asset centered
offset_x = (card_w - CANVAS_W) // 2
offset_y = (card_h - CANVAS_H) // 2
card.paste(idle_asset, (offset_x, offset_y), idle_asset)
card_path = os.path.join(ARTIFACT_DIR, "user_bell_preview.png")
card.save(card_path, "PNG")
print("Saved user_bell_preview.png:", card_path)

print("PROCESSING_COMPLETE")
