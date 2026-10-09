"""Cut map_03_ground.png into <=2048 px WebP chunks for the game (phones may not take a 5K texture).

Run: python map_03_chunks.py  (needs Pillow). Output: game/maps/map_03/ground/ground_<row>_<col>.webp
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "map_03_ground.png")
OUT = os.path.join(HERE, "..", "..", "..", "game", "maps", "map_03", "ground")
CHUNK = 2048
QUALITY = 90

im = Image.open(SRC).convert("RGB")
W, H = im.size
os.makedirs(OUT, exist_ok=True)
for r, y in enumerate(range(0, H, CHUNK)):
    for c, x in enumerate(range(0, W, CHUNK)):
        box = (x, y, min(x + CHUNK, W), min(y + CHUNK, H))
        im.crop(box).save(os.path.join(OUT, f"ground_{r}_{c}.webp"), "WEBP", quality=QUALITY, method=6)
        print(f"ground_{r}_{c}.webp", box)
