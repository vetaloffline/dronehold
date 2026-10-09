"""Build the slime skin atlas for the game: slime_a.png, slime_b.png → slime_skins.png.

Each skin is cropped to its alpha box, scaled to the same body width (BODY_W px) and placed in its
own frame so that all skins share one pivot (the ground point). Frames are padded so mipmaps do not
bleed into the neighbour. Prints the values for game/objects/slime/slime_rig.tres.
Run: python slime_skins.py  (needs Pillow and numpy).
"""
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
BODY_W = 1000
PAD = 32
# Ground point inside the cropped sprite, as a share of its box (eyeballed on the art).
PIVOT_K = (0.5, 0.88)
# Eyes in raw PNG px: x, y, rx, ry — measured on a zoomed grid. Order: left, middle, right
# (blink order in the rig: 0 → 2 → 1).
SKINS = [
    ("slime_a.png", [(915, 535, 85, 75), (1051, 395, 94, 85), (1221, 515, 51, 45)]),
    ("slime_b.png", [(970, 490, 70, 45), (1115, 396, 85, 69), (1215, 509, 45, 39)]),
]

prepared = []
for name, eyes in SKINS:
    im = Image.open(os.path.join(HERE, name)).convert("RGBA")
    a = np.array(im)[..., 3]
    box = Image.fromarray(((a > 8) * 255).astype(np.uint8)).getbbox()
    crop = im.crop(box)
    s = BODY_W / crop.width
    crop = crop.resize((BODY_W, round(crop.height * s)), Image.LANCZOS)
    piv = (crop.width * PIVOT_K[0], crop.height * PIVOT_K[1])
    eyes_s = [((x - box[0]) * s, (y - box[1]) * s, rx * s, ry * s) for x, y, rx, ry in eyes]
    prepared.append((name, crop, piv, eyes_s))

above = max(p[2][1] for p in prepared)
below = max(p[1].height - p[2][1] for p in prepared)
frame_w = BODY_W + 2 * PAD
frame_h = int(round(above + below)) + 2 * PAD
pivot = (PAD + BODY_W / 2, PAD + above)
atlas = Image.new("RGBA", (frame_w * len(prepared), frame_h), (0, 0, 0, 0))
print("frame", frame_w, frame_h, "pivot", pivot, "atlas", atlas.size)
for k, (name, crop, piv, eyes_s) in enumerate(prepared):
    ox = k * frame_w + pivot[0] - piv[0]
    oy = pivot[1] - piv[1]
    atlas.alpha_composite(crop, (int(round(ox)), int(round(oy))))
    # Eyes relative to the frame origin (the shader adds the frame offset).
    for x, y, rx, ry in eyes_s:
        print(f"  {name} eye Vector4({x + ox - k * frame_w:.0f}, {y + oy:.0f}, {rx:.0f}, {ry:.0f})")
atlas.save(os.path.join(HERE, "slime_skins.png"))
