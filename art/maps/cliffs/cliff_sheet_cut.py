#!/usr/bin/env python3
"""Cut a Codex sheet of cliff blocks (4x2: wall columns or natural rock) into one PNG per block, by connected
pieces, not by grid cells.

Codex shifts blocks off the template, so a grid crop catches the rubble of the block above. Instead:
opaque pixels (alpha > --alpha) are split into connected pieces (8-neighbours, scipy); every piece goes to
the template block whose foot point is nearest to the piece's centre; tiny pieces (< --min px) are dropped.
Ground point of a block = the foot of its rock face, measured: scanning up from the bottom, the first row
where the block is at least --foot-fill wide (of its widest row), x = middle of that row. Height = foot
minus the top of the block (map px).

Writes <out>/<prefix>_<i>.png and <out>/<prefix>.json:
  {"texels_per_map_px", "blocks": [{"file", "size", "ground": [x, y], "kind", "height", "measured_h"}]}
kind: from the template (peak / tall / mid / low), or --kind.
Exit 0 ok, 1 a block came out empty, 2 bad args.

Example: python3 cliff_sheet_cut.py cliff_rock_sheet.png -t rock_blocks_template.json -o $TMPDIR/cliff_cut -p cliff_rock
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sheet", help="Codex sheet PNG with alpha")
    ap.add_argument("-t", "--template", required=True, help="rock_blocks_template.json")
    ap.add_argument("-o", "--out", required=True, help="output folder")
    ap.add_argument("-p", "--prefix", default="cliff_block", help="file name prefix (default cliff_block)")
    ap.add_argument("--kind", default="wall", help="kind for blocks the template does not name (default wall)")
    ap.add_argument("--alpha", type=int, default=24, help="opaque threshold 0..255 (default 24)")
    ap.add_argument("--min", type=int, default=30, help="drop pieces smaller than this many px (default 30)")
    ap.add_argument("--foot-fill", type=float, default=0.55, help="row width / widest row for the foot (default 0.55)")
    a = ap.parse_args()
    if not os.path.isfile(a.sheet) or not os.path.isfile(a.template):
        print("no such file", file=sys.stderr)
        return 2
    t = json.load(open(a.template))
    im = Image.open(a.sheet).convert("RGBA")
    kx, ky = im.width / t["size"][0], im.height / t["size"][1]
    rgba = np.array(im)
    alpha = rgba[:, :, 3]
    lab, n = ndimage.label(alpha > a.alpha, structure=np.ones((3, 3)))
    feet = np.array([[b["foot"][0] * kx, b["foot"][1] * ky] for b in t["blocks"]])
    owner = np.zeros(n + 1, dtype=int) - 1
    sizes = ndimage.sum(np.ones_like(lab), lab, range(n + 1))
    cents = ndimage.center_of_mass(np.ones_like(lab), lab, range(1, n + 1))
    for i, (cy, cx) in enumerate(cents, start=1):
        if sizes[i] < a.min:
            continue
        # Nearest foot, measured from the piece centre to the block's vertical span above its foot.
        d = [abs(cx - fx) + max(0.0, cy - fy) * 2 + max(0.0, (fy - 300 * ky) - cy) for fx, fy in feet]
        owner[i] = int(np.argmin(d))
    os.makedirs(a.out, exist_ok=True)
    out, bad = [], 0
    for bi, b in enumerate(t["blocks"]):
        mask = np.isin(lab, np.nonzero(owner == bi)[0])
        if not mask.any():
            print(f"block {bi}: empty", file=sys.stderr)
            bad += 1
            continue
        ys, xs = np.nonzero(mask)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        piece = rgba[y0:y1, x0:x1].copy()
        piece[:, :, 3] = np.where(mask[y0:y1, x0:x1], piece[:, :, 3], 0)
        widths = mask[y0:y1, x0:x1].sum(axis=1)
        need = widths.max() * a.foot_fill
        fy = next(y for y in range(len(widths) - 1, -1, -1) if widths[y] >= need)
        row = np.nonzero(mask[y0 + fy, x0:x1])[0]
        gx = (row.min() + row.max()) / 2.0
        name = f"{a.prefix}_{bi}.png"
        Image.fromarray(piece).save(os.path.join(a.out, name))
        out.append({"file": name, "size": [int(x1 - x0), int(y1 - y0)], "ground": [round(gx, 1), float(fy)],
                    "kind": b.get("kind", a.kind), "height": b.get("height", 48),
                    "measured_h": round(fy / (t["texels_per_map_px"] * ky), 1)})
    with open(os.path.join(a.out, a.prefix + ".json"), "w") as f:
        json.dump({"texels_per_map_px": t["texels_per_map_px"] * kx, "blocks": out}, f, indent=1)
        f.write("\n")
    print(f"{len(out)} blocks -> {a.out}")
    for o in out:
        print(f"  {o['file']}: {o['kind']:5s} template {o['height']} map px, measured {o['measured_h']} (incl. top), size {o['size']}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
