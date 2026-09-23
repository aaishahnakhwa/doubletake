from PIL import Image

img_path = r'C:\Users\saule\.gemini\antigravity\brain\17a13079-7005-4717-99fb-b563640774d7\.user_uploaded\media_1790001255845.png'
im = Image.open(img_path)
w, h = im.size

col_has_content = []
for x in range(w):
    has_c = False
    for y in range(h):
        r, g, b, a = im.getpixel((x, y))
        if a > 10:
            has_c = True
            break
    col_has_content.append(has_c)

# Find segments where a > 10
segments = []
in_seg = False
start_x = 0
for x in range(w):
    if col_has_content[x] and not in_seg:
        in_seg = True
        start_x = x
    elif not col_has_content[x] and in_seg:
        in_seg = False
        segments.append((start_x, x - 1))
if in_seg:
    segments.append((start_x, w - 1))

print(f"Total width: {w}, height: {h}")
print("Found segments:", len(segments))
for i, (sx, ex) in enumerate(segments):
    # Also find y bounds for this segment
    min_y = h
    max_y = 0
    for x in range(sx, ex + 1):
        for y in range(h):
            if im.getpixel((x, y))[3] > 10:
                if y < min_y: min_y = y
                if y > max_y: max_y = y
    print(f"Frame {i}: X [{sx:4d} .. {ex:4d}] (w={ex-sx+1}), Y [{min_y:4d} .. {max_y:4d}] (h={max_y-min_y+1})")
