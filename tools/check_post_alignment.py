from PIL import Image

img_path = r'C:\Users\saule\.gemini\antigravity\brain\17a13079-7005-4717-99fb-b563640774d7\.user_uploaded\media_1790001255845.png'
im = Image.open(img_path)

# Let's inspect where the top cap of the wooden post is in each frame
# The top cap of the post is around Y = 150-180, on the left side of each frame
# Let's find the left-most pixel of the post and top-most pixel of the post for each frame
frames_bounds = [
    (15, 240),
    (266, 486),
    (524, 771),
    (778, 998)
]

for idx, (sx, ex) in enumerate(frames_bounds):
    # Find the top cap of the post (near y=148 to 170)
    top_pixels = []
    for y in range(148, 175):
        for x in range(sx, sx + 70): # post width is around 50px
            if im.getpixel((x, y))[3] > 100:
                top_pixels.append((x, y))
    
    # Left-most pixel of the post
    min_x = min(p[0] for p in top_pixels)
    min_y = min(p[1] for p in top_pixels)
    max_x = max(p[0] for p in top_pixels)
    print(f"Frame {idx}: Post cap top-left = ({min_x}, {min_y}), width={max_x - min_x + 1}")
