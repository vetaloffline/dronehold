#!/usr/bin/env python3
"""Pose template for the sheet of cliff blocks (Codex Image 1): one block = one cliff cell.

Canvas 1536x1024 = 4 x 2 cells of 384x512, 4 texels per map px. In each cell one block on its foot:
  top face   (light grey) 32x24 map px = the cell seen at 30 deg      -> 128x96 px
  front face (dark grey)  48 map px tall = the cliff height            -> 128x192 px
  dashed frame            how far rocks may bulge past the box (6 map px each side, 8 up): neighbours
                          overlap there and the blocks join into one cliff
Foot line = bottom of the front face = the south edge of the cell.
Writes cliff_blocks_template.png and cliff_blocks_template.json (per block: box, foot, bulge frame). Exit 0.

Example: python3 cliff_blocks_template.py
"""
import argparse
import json
import os

from PIL import Image, ImageDraw

W, H = 1536, 1024
CW, CH = 384, 512
TEX = 4
BOX_W, TOP_H, FACE_H = 32 * TEX, 24 * TEX, 48 * TEX
BULGE_X, BULGE_UP = 6 * TEX, 8 * TEX
FOOT_Y = 440


def dashed_rect(d, x0, y0, x1, y1, col, dash=12):
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
    for i in range(8):
        cx = (i % 4) * CW + CW // 2
        foot = (i // 4) * CH + FOOT_Y
        x0, x1 = cx - BOX_W // 2, cx + BOX_W // 2
        face_top = foot - FACE_H
        top_top = face_top - TOP_H
        d.rectangle((x0, top_top, x1, face_top), fill=(200, 200, 200), outline=(60, 60, 60), width=2)
        d.rectangle((x0, face_top, x1, foot), fill=(105, 105, 105), outline=(40, 40, 40), width=3)
        d.line((x0 - 30, foot, x1 + 30, foot), fill=(40, 40, 40), width=3)
        fr = (x0 - BULGE_X, top_top - BULGE_UP, x1 + BULGE_X, foot)
        dashed_rect(d, *fr, col=(150, 150, 150))
        blocks.append({"box": [x0, top_top, x1, foot], "face_top": face_top, "foot": [cx, foot], "bulge": list(fr)})
    im.save(os.path.join(a.out_dir, "cliff_blocks_template.png"))
    with open(os.path.join(a.out_dir, "cliff_blocks_template.json"), "w") as f:
        json.dump({"size": [W, H], "cell": [CW, CH], "texels_per_map_px": TEX,
                   "map_cell": [32, 24], "map_height": 48, "blocks": blocks}, f, indent=1)
        f.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
