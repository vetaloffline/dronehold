"""Pose template for the relay (Codex reference): a 2x2-cell building in the game's 3/4 view, exact size.
Map cell 32x24 px, art x8 -> cell 256x192, footprint 2x2 = 512x384 art px.
Grey boxes only, no text: base slab over the footprint, a mast in the middle, an antenna on a swivel
on top (the part that will spin in code), two small round drone pads on the base (left / right).
Writes relay_template.png + relay_template.json (ground point, footprint rect, parts) next to it."""
from PIL import Image, ImageDraw
import json, os, sys

S = 8
CELL = (32 * S, 24 * S)
FOOT = (2 * CELL[0], 2 * CELL[1])  # 512 x 384
W, H = 1024, 1024
G = (W // 2, 760)  # ground point = footprint centre
BASE_H = 70
MAST = dict(w=96, h=330)
SWIVEL = dict(w=150, h=40)
ANT = dict(w=300, h=46)

img = Image.new("RGB", (W, H), (255, 255, 255))
dr = ImageDraw.Draw(img)
LINE = (30, 30, 34)


def box(x0, x1, y0, y1, h, top=(196, 200, 206), front=(120, 124, 132)):
    """Box over ground rect [x0,x1]x[y0,y1] (absolute art px), height h."""
    dr.rectangle([x0, y1 - h, x1, y1], fill=front, outline=LINE, width=3)
    dr.rectangle([x0, y0 - h, x1, y1 - h], fill=top, outline=LINE, width=3)


def ellipse_col(cx, gy, w, h, fill_top=(196, 200, 206), fill_side=(120, 124, 132)):
    """Vertical cylinder of width w standing on ground y gy (ellipse squash 0.75), height h."""
    ry = w * 0.375 * 0.5
    dr.rectangle([cx - w / 2, gy - h, cx + w / 2, gy], fill=fill_side)
    dr.ellipse([cx - w / 2, gy - ry, cx + w / 2, gy + ry], fill=fill_side, outline=LINE, width=3)
    dr.line([cx - w / 2, gy - h, cx - w / 2, gy], fill=LINE, width=3)
    dr.line([cx + w / 2, gy - h, cx + w / 2, gy], fill=LINE, width=3)
    dr.ellipse([cx - w / 2, gy - h - ry, cx + w / 2, gy - h + ry], fill=fill_top, outline=LINE, width=3)


# Faint 2x2 cell grid on the ground for scale.
fx0, fy0 = G[0] - FOOT[0] / 2, G[1] - FOOT[1] / 2
for i in range(3):
    dr.line([fx0 + i * CELL[0], fy0, fx0 + i * CELL[0], fy0 + FOOT[1]], fill=(215, 215, 215), width=2)
    dr.line([fx0, fy0 + i * CELL[1], fx0 + FOOT[0], fy0 + i * CELL[1]], fill=(215, 215, 215), width=2)

# Base slab: the whole footprint, inset a little.
inset = 20
box(fx0 + inset, fx0 + FOOT[0] - inset, fy0 + inset, fy0 + FOOT[1] - inset, BASE_H)
base_top_y = G[1] - BASE_H  # ground point lifted onto the slab top
# Drone pads: flat discs on the slab, left and right of the mast, towards the front.
pads = []
for sx in (-1, 1):
    cx, cy = G[0] + sx * 165, base_top_y + 70
    dr.ellipse([cx - 62, cy - 30, cx + 62, cy + 30], fill=(160, 166, 176), outline=LINE, width=3)
    dr.ellipse([cx - 34, cy - 16, cx + 34, cy + 16], outline=LINE, width=3)
    pads.append((cx, cy))
# Mast: a cylinder from the slab centre (a bit back).
mast_gy = base_top_y - 10
ellipse_col(G[0], mast_gy, MAST["w"], MAST["h"])
top_y = mast_gy - MAST["h"]
# Swivel joint (blue mark = the part that turns), antenna bar on it.
ellipse_col(G[0], top_y, SWIVEL["w"], SWIVEL["h"], fill_top=(90, 150, 255), fill_side=(60, 110, 220))
sw_top = top_y - SWIVEL["h"]
ant = [G[0] - ANT["w"] / 2, sw_top - ANT["h"] - 20, G[0] + ANT["w"] / 2, sw_top - 20]
dr.rectangle([G[0] - 14, sw_top - 30, G[0] + 14, sw_top + 4], fill=(120, 124, 132), outline=LINE, width=3)
dr.rectangle(ant, fill=(196, 200, 206), outline=LINE, width=3)

out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "relay_template.png")
img.save(out)
json.dump(dict(scale=S, cell=CELL, footprint_px=FOOT, ground=G,
               footprint_rect=[fx0, fy0, fx0 + FOOT[0], fy0 + FOOT[1]], base_h=BASE_H,
               mast=dict(MAST, ground_y=mast_gy), swivel_center=[G[0], top_y], antenna_rect=ant,
               drone_pads=pads), open(out.replace(".png", ".json"), "w"), indent=1)
print(out)
