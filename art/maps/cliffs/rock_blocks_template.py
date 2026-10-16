#!/usr/bin/env python3
"""Pose template for the sheet of natural rock blocks (Codex Image 1): one block = one cliff cell.

Canvas 1536x1024 = 4 x 2 cells of 384x512, 3 texels per map px. In each cell one block on its foot:
  top face   (light grey) 32x24 map px = the cell seen at 30 deg
  front face (dark grey)  the block height in map px (HEIGHTS: peak 96, tall 72, mid 44, low 20)
  peak       extra spire outline above the top face (the rock may rise into a crag there)
  dashed frame            how far rock may bulge past the box (10 map px each side, 10 up): neighbours
                          overlap there and join into one cliff
Foot line = bottom of the front face = the south edge of the cell. The game picks the height per cell:
low near the ends of a ridge (a gentle slope), higher further in, peaks here and there.
Writes rock_blocks_template.png and rock_blocks_template.json (per block: kind, height, box, foot,
bulge frame). Exit 0.

Example: python3 rock_blocks_template.py
"""
import argparse
import json
import os

from PIL import Image, ImageDraw

W, H = 1536, 1024
CW, CH = 384, 512
TEX = 3
BOX_W, TOP_H = 32 * TEX, 24 * TEX
BULGE_X, BULGE_UP = 10 * TEX, 10 * TEX
FOOT_Y = 470
BLOCKS = [("peak", 96), ("tall", 72), ("tall", 72), ("mid", 44),
          ("mid", 44), ("mid", 44), ("low", 20), ("low", 20)]


def dashed_rect(d, x0, y0, x1, y1, col, dash=10):
    for x in range(x0, x1, dash * 2):
        d.line((x, y0, min(x + dash, x1), y0), fill=col, width=2)
        d.line((x, y1, min(x + dash, x1), y1), fill=col, width=2)
    for y in range(y0, y1, dash * 2):
        d.line((x0, y, x0, min(y + dash, y1)), fill=col, width=2)
        d.line((x1, y, x1, min(y + dash, y1)), fill=col, width=2)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--out-dir", default=os.path.dirname(os.path.abspath(__file__)),
                    help="where to write the template (default: next to this script)")
    a = ap.parse_args()
    im = Image.new("RGB", (W, H), (255, 255, 255))
    d = ImageDraw.Draw(im)
    blocks = []
    for i, (kind, h_map) in enumerate(BLOCKS):
        cx = (i % 4) * CW + CW // 2
        foot = (i // 4) * CH + FOOT_Y
        x0, x1 = cx - BOX_W // 2, cx + BOX_W // 2
        face_top = foot - h_map * TEX
        top_top = face_top - TOP_H
        if kind == "peak":
            # Spire: the rock may rise above the top face here.
            d.polygon([(x0 + 10, top_top + 10), (cx - 6, top_top - 70), (cx + 14, top_top - 40), (x1 - 8, top_top + 10)],
                      fill=(170, 170, 170), outline=(60, 60, 60))
        d.rectangle((x0, top_top, x1, face_top), fill=(200, 200, 200), outline=(60, 60, 60), width=2)
        d.rectangle((x0, face_top, x1, foot), fill=(105, 105, 105), outline=(40, 40, 40), width=3)
        d.line((x0 - 40, foot, x1 + 40, foot), fill=(40, 40, 40), width=3)
        up = 70 if kind == "peak" else 0
        fr = (x0 - BULGE_X, top_top - BULGE_UP - up, x1 + BULGE_X, foot)
        dashed_rect(d, *fr, col=(150, 150, 150))
        blocks.append({"kind": kind, "height": h_map, "box": [x0, top_top, x1, foot], "face_top": face_top,
                       "foot": [cx, foot], "bulge": list(fr)})
    im.save(os.path.join(a.out_dir, "rock_blocks_template.png"))
    with open(os.path.join(a.out_dir, "rock_blocks_template.json"), "w") as f:
        json.dump({"size": [W, H], "cell": [CW, CH], "texels_per_map_px": TEX,
                   "map_cell": [32, 24], "blocks": blocks}, f, indent=1)
        f.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
