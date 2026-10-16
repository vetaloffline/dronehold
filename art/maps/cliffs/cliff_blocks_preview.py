#!/usr/bin/env python3
"""Preview: cliff blocks placed one per cliff cell of the cliff_sandbox demo maze, on the ground tile.

Blocks are drawn bottom-last (Y-sort by the cell's south edge), the block's ground point on the middle of
the cell's south edge, scaled from texels to map px. Variant per cell = hash of the cell (no neighbour twins
along a row). Writes <out>_full.png (half size) and crops <out>_ring.png, <out>_u.png, <out>_diag.png.
Exit 0.

Example (after cliff_sheet_cut.py): python3 cliff_blocks_preview.py $TMPDIR/cut/cliff_wall.json -o $TMPDIR/cliff_wall_preview
"""
import argparse
import json
import os

from PIL import Image

COLS, ROWS, CW, CH = 96, 64, 32, 24


def demo_cells():
    s = set()
    for r in range(ROWS):
        for c in range(COLS):
            if c < 2 or r < 2 or c >= COLS - 2 or r >= ROWS - 2:
                s.add((c, r))
    for c in range(10, 40):
        s |= {(c, 12), (c, 13)}
    for r in range(2, 26):
        s |= {(62, r), (63, r)}
    for c in range(70, 86):
        s |= {(c, 36), (c, 37)}
    for r in range(36, 50):
        s |= {(70, r), (71, r), (84, r), (85, r)}
    for c in range(10, 30):
        for r in range(40, 56):
            edge = c < 12 or c >= 28 or r < 42 or r >= 54
            if edge and not (c >= 28 and 46 <= r < 50):
                s.add((c, r))
    for c in range(40, 56):
        s.add((c, 8))
    for k in range(10):
        s |= {(36 + k, 44 + k), (37 + k, 44 + k)}
    s |= {(58, 52), (60, 54), (61, 55)}
    return s


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("blocks", help="<prefix>.json from cliff_sheet_cut.py")
    ap.add_argument("-o", "--out", required=True, help="output prefix")
    ap.add_argument("--ground", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ground", "ground_dirt.png"),
                    help="ground tile (default: the game's, art/maps/ground/ground_dirt.png)")
    a = ap.parse_args()
    meta = json.load(open(a.blocks))
    k = 1.0 / meta["texels_per_map_px"]
    sprites = []
    for b in meta["blocks"]:
        im = Image.open(os.path.join(os.path.dirname(a.blocks), b["file"])).convert("RGBA")
        im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
        sprites.append((im, (b["ground"][0] * k, b["ground"][1] * k)))
    W, H = COLS * CW, ROWS * CH
    g = Image.open(a.ground).convert("RGBA").resize((320, 320), Image.LANCZOS)
    bg = Image.new("RGBA", (W, H))
    for y in range(0, H, 320):
        for x in range(0, W, 320):
            bg.paste(g, (x, y))
    cells = sorted(demo_cells(), key=lambda p: (p[1], p[0]))
    for c, r in cells:
        v = (c * 7 + r * 13 + (c * r) % 5) % len(sprites)
        im, gp = sprites[v]
        x = round((c + 0.5) * CW - gp[0])
        y = round((r + 1) * CH - gp[1])
        bg.alpha_composite(im, (x, y)) if x >= 0 and y >= 0 else bg.paste(im, (x, y), im)
    bg = bg.convert("RGB")
    bg.resize((W // 2, H // 2), Image.LANCZOS).save(a.out + "_full.png")
    bg.crop((200, 850, 1100, 1450)).resize((1350, 900), Image.LANCZOS).save(a.out + "_ring.png")
    bg.crop((2150, 750, 2850, 1300)).resize((1050, 825), Image.LANCZOS).save(a.out + "_u.png")
    bg.crop((1050, 950, 2000, 1450)).resize((1425, 750), Image.LANCZOS).save(a.out + "_diag.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
