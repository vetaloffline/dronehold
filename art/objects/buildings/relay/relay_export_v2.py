"""Export the approved relay art (tower with spire + 16 dish views) for the game; prints the rig numbers.

In (drafts): spire/relay_base_spire.png (tower with spire, approved 2026-10-12), relay_base_shadow.png
(relay_cut.py), dish_v2/export/relay_dish_*.png (16 views at tower px, hinge at 320, 412.5) and
dish_v2/export/relay_dish_views.json.
Out (argv[1], default ../../../objects/buildings/relay): relay_base.png, relay_base_shadow.png (BASE_BOX),
relay_dish_<az>.png (DISH_BOX, the same box for all 16), relay_dish_views.json.
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "..", "objects", "buildings", "relay")
# relay_export.py box, but the top raised from 317 to 240 so the spire (top at y 264.5) is kept.
BASE_BOX = (123, 240, 1019, 1163)
GROUND = (631, 972)          # footprint centre on the tower PNG (relay_export.py)
HOUSING = (635.0, 264.5)     # spire top = dish hinge (spire/relay_base_spire_placeholder.png)
FOOT_W = 762                 # slab width px = 2 cells = 64 map px
EXP = os.path.join(HERE, "dish_v2", "export")
meta = json.load(open(os.path.join(EXP, "relay_dish_views.json")))
PIVOT = tuple(meta["housing"])   # hinge in every 640x640 dish view

os.makedirs(OUT, exist_ok=True)
Image.open(os.path.join(HERE, "spire", "relay_base_spire.png")).crop(BASE_BOX).save(os.path.join(OUT, "relay_base.png"))
Image.open(os.path.join(HERE, "relay_base_shadow.png")).crop(BASE_BOX).save(os.path.join(OUT, "relay_base_shadow.png"))

frames = [(v, Image.open(os.path.join(EXP, v["file"])).convert("RGBA")) for v in meta["views"]]
boxes = [im.getchannel("A").getbbox() for _, im in frames]
m = 8
DISH_BOX = (min(b[0] for b in boxes) - m, min(b[1] for b in boxes) - m,
            max(b[2] for b in boxes) + m, max(b[3] for b in boxes) + m)
for v, im in frames:
    im.crop(DISH_BOX).save(os.path.join(OUT, v["file"]))
out_meta = dict(meta, canvas=[DISH_BOX[2] - DISH_BOX[0], DISH_BOX[3] - DISH_BOX[1]],
                housing=[PIVOT[0] - DISH_BOX[0], PIVOT[1] - DISH_BOX[1]])
json.dump(out_meta, open(os.path.join(OUT, "relay_dish_views.json"), "w"), indent=1)
print(json.dumps(dict(
    ground=[GROUND[0] - BASE_BOX[0], GROUND[1] - BASE_BOX[1]],
    housing=[HOUSING[0] - BASE_BOX[0], HOUSING[1] - BASE_BOX[1]],
    dish_pivot=out_meta["housing"], dish_size=out_meta["canvas"],
    map_scale=round(64.0 / FOOT_W, 4),
    base_size=[BASE_BOX[2] - BASE_BOX[0], BASE_BOX[3] - BASE_BOX[1]],
    files=[v["file"] for v, _ in frames], azimuths=[v["azimuth"] for v, _ in frames])))
