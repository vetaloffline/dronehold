"""Pose template for the wall pieces (Codex reference): 3 blocks in the game's 3/4 view, exact size.
Map cell 32×24 px, art ×8 → cell 256×192. A box = top face (footprint, lifted by its height) + front face.
Pieces: pillar (on every wall cell), span along x (to the right neighbour), span in depth (to the lower one).
Prints each piece's ground point (cell centre) in sheet px — used to cut and place the pieces."""
from PIL import Image, ImageDraw
import json, sys

S = 8
CELL = (32 * S, 24 * S)
PILLAR = dict(w=136, d=104, h=150)
SPAN_H = 110
ALONG = dict(x0=PILLAR["w"] / 2, x1=CELL[0] - PILLAR["w"] / 2, d=64)
DEPTH = dict(w=72, y0=PILLAR["d"] / 2, y1=CELL[1] - PILLAR["d"] / 2)

W, H = 1536, 1024
img = Image.new("RGB", (W, H), (255, 255, 255))
dr = ImageDraw.Draw(img)


def box(gx, gy, x0, x1, y0, y1, h):
    """Box over ground rect [x0,x1]×[y0,y1] (relative to ground point gx, gy), height h."""
    top = [gx + x0, gy + y0 - h, gx + x1, gy + y1 - h]
    front = [gx + x0, gy + y1 - h, gx + x1, gy + y1]
    dr.rectangle(front, fill=(120, 124, 132), outline=(30, 30, 34), width=3)
    dr.rectangle(top, fill=(196, 200, 206), outline=(30, 30, 34), width=3)


def ground(gx, gy):
    # Faint cell outline on the ground for scale.
    dr.rectangle([gx - CELL[0] / 2, gy - CELL[1] / 2, gx + CELL[0] / 2, gy + CELL[1] / 2], outline=(215, 215, 215), width=2)


pts = {}
# 1) pillar
gx, gy = 256, 640
ground(gx, gy)
p = PILLAR
box(gx, gy, -p["w"] / 2, p["w"] / 2, -p["d"] / 2, p["d"] / 2, p["h"])
pts["pillar"] = (gx, gy)
# 2) span along x: from the pillar's right face to the next pillar's left face (cell centre = left pillar)
gx, gy = 640, 640
ground(gx, gy)
ground(gx + CELL[0], gy)
a = ALONG
box(gx, gy, a["x0"], a["x1"], -a["d"] / 2, a["d"] / 2, SPAN_H)
pts["along"] = (gx, gy)
# 3) span in depth: from the pillar's front face to the lower pillar's back face
gx, gy = 1280, 520
ground(gx, gy)
ground(gx, gy + CELL[1])
d = DEPTH
box(gx, gy, -d["w"] / 2, d["w"] / 2, d["y0"], d["y1"], SPAN_H)
pts["depth"] = (gx, gy)

out = sys.argv[1]
img.save(out)
json.dump(dict(scale=S, cell=CELL, pillar=PILLAR, span_h=SPAN_H, along=ALONG, depth=DEPTH, ground=pts),
          open(out.replace(".png", ".json"), "w"), indent=1)
print(out)
