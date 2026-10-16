#!/usr/bin/env python3
"""Preview: natural rock blocks, one per cliff cell of the cliff_sandbox demo maze, height chosen per cell.

Height rule (the same goes into the game code):
  seed = an end or a corner of a ridge: a cliff cell with <= 1 cliff side neighbour, or with exactly 2
         that are not opposite (an L);
  d    = steps from the nearest seed inside the cliff (4-neighbours); a group without seeds: d = 9;
  kind = d 0 -> low, 1 -> mid, 2 -> tall (mid when the noise < 0.4), >= 3 -> tall (mid when < 0.3), and
         peak on the one cell of a hump where the noise is highest within 3 cells (and > 0.6). Noise = value noise on a 4-cell grid, so peaks and dips come in clumps.
Blocks drawn bottom-last (Y-sort by the cell's south edge), ground point on the middle of the south edge.
Writes <out>_full.png (half size) and crops <out>_ring.png, <out>_u.png, <out>_diag.png, <out>_wall.png.
Exit 0.

Example (after cliff_sheet_cut.py): python3 rock_blocks_preview.py $TMPDIR/cut/cliff_rock.json --jitter-size 0.12 --jitter-x 7 --jitter-y 3 -o $TMPDIR/rock_preview
"""
import argparse
import json
import os
import sys
from collections import deque

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cliff_blocks_preview import COLS, ROWS, CW, CH, demo_cells  # noqa: E402

SIDES = ((1, 0), (-1, 0), (0, 1), (0, -1))


def h01(c, r, salt=0):
    v = (c * 374761393 + r * 668265263 + salt * 2246822519) & 0xFFFFFFFF
    v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((v ^ (v >> 16)) & 0xFFFF) / 65535.0


def value_noise(c, r, step=4):
    """Smooth 0..1 noise: hashes on a coarse grid every `step` cells, bilinear between them."""
    gx, gy = c / step, r / step
    x0, y0 = int(gx // 1), int(gy // 1)
    fx, fy = gx - x0, gy - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = h01(x0, y0, 3) * (1 - fx) + h01(x0 + 1, y0, 3) * fx
    b = h01(x0, y0 + 1, 3) * (1 - fx) + h01(x0 + 1, y0 + 1, 3) * fx
    return a * (1 - fy) + b * fy


def kinds_for(cells):
    seeds = []
    for c, r in cells:
        n = [(dx, dy) for dx, dy in SIDES if (c + dx, r + dy) in cells]
        opposite = len(n) == 2 and n[0][0] + n[1][0] == 0 and n[0][1] + n[1][1] == 0
        if len(n) <= 1 or (len(n) == 2 and not opposite):
            seeds.append((c, r))
    dist = {p: 0 for p in seeds}
    q = deque(seeds)
    while q:
        c, r = q.popleft()
        for dx, dy in SIDES:
            p = (c + dx, r + dy)
            if p in cells and p not in dist:
                dist[p] = dist[(c, r)] + 1
                q.append(p)
    out = {}
    for c, r in cells:
        d = dist.get((c, r), 9)
        nz = value_noise(c, r)
        if d == 0:
            k = "low"
        elif d == 1:
            k = "mid"
        elif d == 2:
            k = "tall" if nz > 0.4 else "mid"
        else:
            k = "tall" if nz >= 0.3 else "mid"
            # One peak per hump: the highest noise among cliff cells within 3 cells, and high enough.
            if nz > 0.6 and all(value_noise(c + dx, r + dy) <= nz for dx in range(-3, 4) for dy in range(-3, 4)
                                if (c + dx, r + dy) in cells and dist.get((c + dx, r + dy), 9) >= 3):
                k = "peak"
        out[(c, r)] = k
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("blocks", help="cliff_rock.json from cliff_sheet_cut.py")
    ap.add_argument("-o", "--out", required=True, help="output prefix")
    ap.add_argument("--scale", type=float, default=1.0, help="block size on the map, x (default 1.0)")
    ap.add_argument("--jitter-size", type=float, default=0.0, help="random block size spread, fraction (default 0)")
    ap.add_argument("--jitter-x", type=float, default=0.0, help="random x shift, map px (default 0)")
    ap.add_argument("--jitter-y", type=float, default=0.0, help="random y shift, map px (default 0)")
    ap.add_argument("--ground", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ground", "ground_dirt.png"),
                    help="ground tile (default: the game's, art/maps/ground/ground_dirt.png)")
    a = ap.parse_args()
    meta = json.load(open(a.blocks))
    k = a.scale / meta["texels_per_map_px"]
    by_kind = {}
    for b in meta["blocks"]:
        im = Image.open(os.path.join(os.path.dirname(a.blocks), b["file"])).convert("RGBA")
        im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
        by_kind.setdefault(b["kind"], []).append((im, (b["ground"][0] * k, b["ground"][1] * k)))
    W, H = COLS * CW, ROWS * CH
    g = Image.open(a.ground).convert("RGBA").resize((320, 320), Image.LANCZOS)
    bg = Image.new("RGBA", (W, H))
    for y in range(0, H, 320):
        for x in range(0, W, 320):
            bg.paste(g, (x, y))
    cells = demo_cells()
    kinds = kinds_for(cells)
    for c, r in sorted(cells, key=lambda p: (p[1], p[0])):
        opts = by_kind[kinds[(c, r)]]
        im, gp = opts[int(h01(c, r, 7) * len(opts)) % len(opts)]
        # Break the 32 px rhythm: size ±--jitter-size, shift ±--jitter-x / ±--jitter-y map px.
        z = 1.0 + (h01(c, r, 11) * 2 - 1) * a.jitter_size
        if z != 1.0:
            im = im.resize((max(1, round(im.width * z)), max(1, round(im.height * z))), Image.LANCZOS)
            gp = (gp[0] * z, gp[1] * z)
        jx = (h01(c, r, 13) * 2 - 1) * a.jitter_x
        jy = (h01(c, r, 17) * 2 - 1) * a.jitter_y
        bg.paste(im, (round((c + 0.5) * CW - gp[0] + jx), round((r + 1) * CH - gp[1] + jy)), im)
    bg = bg.convert("RGB")
    bg.resize((W // 2, H // 2), Image.LANCZOS).save(a.out + "_full.png")
    bg.crop((200, 850, 1100, 1450)).resize((1350, 900), Image.LANCZOS).save(a.out + "_ring.png")
    bg.crop((2150, 750, 2850, 1300)).resize((1050, 825), Image.LANCZOS).save(a.out + "_u.png")
    bg.crop((1050, 950, 2000, 1450)).resize((1425, 750), Image.LANCZOS).save(a.out + "_diag.png")
    bg.crop((250, 150, 1350, 450)).resize((1650, 450), Image.LANCZOS).save(a.out + "_wall.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
