#!/usr/bin/env python3
"""Pose template for the sheet of 10 rock decor pieces (Codex Image 1).

Canvas 1536x1024 = 5 x 2 cells of 307x512, 2 texels per map px. In each cell one piece standing on the
ground: a light ellipse = its footprint on the ground (w x h cells of 32x24 map px), a grey silhouette = how
high it rises and its rough shape (spire, twin spires, jagged crest, pile, slab, split boulder, scree fan,
broken ledge, arch, fallen pillar). The foot point (middle of the footprint's south edge) sits on a dark line.
Writes rock_decor_template.png and rock_decor_template.json (per piece: name, footprint cells, height map px,
foot point px, box). Exit 0.

Example: python3 rock_decor_template.py
"""
import argparse
import json
import math
import os

from PIL import Image, ImageDraw

W, H = 1536, 1024
CW, CH = 307, 512
TEX = 2
FOOT_Y = 440
# name, footprint (cells), height (map px), silhouette kind
PIECES = [
    ("spire", (2, 2), 150, "spire"), ("twin_spires", (3, 2), 130, "twin"), ("jagged_crest", (4, 2), 80, "crest"),
    ("rockfall", (4, 3), 60, "pile"), ("leaning_slab", (2, 2), 90, "slab"),
    ("split_boulder", (3, 2), 70, "split"), ("scree", (4, 2), 22, "scree"), ("broken_ledge", (3, 3), 75, "ledge"),
    ("arch", (4, 3), 120, "arch"), ("fallen_pillar", (4, 2), 40, "fallen"),
]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--out-dir", default=os.path.dirname(os.path.abspath(__file__)),
                    help="where to write the template (default: next to this script)")
    a = ap.parse_args()
    im = Image.new("RGB", (W, H), (255, 255, 255))
    d = ImageDraw.Draw(im)
    out = []
    G, S, E = (210, 210, 210), (120, 120, 120), (40, 40, 40)
    for i, (name, (fw, fh), hpx, kind) in enumerate(PIECES):
        cx = (i % 5) * CW + CW // 2
        foot = (i // 5) * CH + FOOT_Y
        w, h = fw * 32 * TEX, fh * 24 * TEX
        top = foot - h  # back edge of the footprint
        d.ellipse((cx - w / 2, top, cx + w / 2, foot), fill=G, outline=(170, 170, 170))
        H2 = hpx * TEX
        mid = foot - h / 2
        if kind == "spire":
            d.polygon([(cx - w * 0.35, mid + h * 0.3), (cx - 8, mid - H2), (cx + 10, mid - H2 * 0.8), (cx + w * 0.35, mid + h * 0.3)], fill=S, outline=E)
        elif kind == "twin":
            d.polygon([(cx - w * 0.42, mid + h * 0.3), (cx - w * 0.2, mid - H2), (cx - 4, mid - H2 * 0.4), (cx + w * 0.18, mid - H2 * 0.8), (cx + w * 0.42, mid + h * 0.3)], fill=S, outline=E)
        elif kind == "crest":
            pts = [(cx - w * 0.48, mid + h * 0.3)]
            for k, f in enumerate([0.7, 0.95, 0.55, 0.8, 1.0, 0.5, 0.75]):
                x = cx - w * 0.42 + k * w * 0.14 + (6 if k % 2 else -4)
                pts.append((x, mid - H2 * f))
            pts.append((cx + w * 0.48, mid + h * 0.3))
            d.polygon(pts, fill=S, outline=E)
        elif kind == "pile":
            for k, (ox, oy, r) in enumerate([(-0.3, 0.1, 0.18), (0.0, -0.1, 0.24), (0.28, 0.12, 0.17), (-0.05, 0.25, 0.14), (0.2, -0.25, 0.12)]):
                d.ellipse((cx + ox * w - r * w, mid + oy * h - r * w * 0.8, cx + ox * w + r * w, mid + oy * h + r * w * 0.5), fill=S, outline=E)
        elif kind == "slab":
            d.polygon([(cx - w * 0.3, mid + h * 0.35), (cx - w * 0.05, mid - H2), (cx + w * 0.2, mid - H2 * 0.9), (cx + w * 0.35, mid + h * 0.35)], fill=S, outline=E)
        elif kind == "split":
            d.polygon([(cx - w * 0.42, mid + h * 0.3), (cx - w * 0.35, mid - H2), (cx - 6, mid - H2 * 0.9), (cx - 6, mid + h * 0.35)], fill=S, outline=E)
            d.polygon([(cx + 6, mid + h * 0.35), (cx + 6, mid - H2 * 0.85), (cx + w * 0.38, mid - H2 * 0.7), (cx + w * 0.42, mid + h * 0.3)], fill=S, outline=E)
        elif kind == "scree":
            d.polygon([(cx - w * 0.45, mid + h * 0.35), (cx - w * 0.1, mid - h * 0.35 - H2), (cx + w * 0.1, mid - h * 0.35 - H2), (cx + w * 0.45, mid + h * 0.35)], fill=(170, 170, 170), outline=E)
        elif kind == "ledge":
            d.polygon([(cx - w * 0.45, mid + h * 0.3), (cx - w * 0.4, mid - H2 * 0.8), (cx + w * 0.1, mid - H2), (cx + w * 0.45, mid - H2 * 0.6), (cx + w * 0.45, mid + h * 0.3)], fill=S, outline=E)
        elif kind == "arch":
            base = mid + h * 0.3
            outer = [(cx + w * 0.47 * math.cos(t), base - H2 * math.sin(t)) for t in [k * math.pi / 24 for k in range(25)]]
            inner = [(cx + w * 0.2 * math.cos(t), base - H2 * 0.5 * math.sin(t)) for t in [math.pi - k * math.pi / 24 for k in range(25)]]
            d.polygon(outer + inner, fill=S, outline=E)
        elif kind == "fallen":
            d.polygon([(cx - w * 0.47, mid + h * 0.1), (cx - w * 0.42, mid - H2), (cx + w * 0.45, mid - H2 * 0.6 - h * 0.25), (cx + w * 0.48, mid + h * 0.0), (cx + w * 0.2, mid + h * 0.35)], fill=S, outline=E)
        d.line((cx - w / 2 - 20, foot, cx + w / 2 + 20, foot), fill=E, width=3)
        out.append({"name": name, "foot_cells": [fw, fh], "height_map_px": hpx, "foot": [cx, foot],
                    "cell_box": [(i % 5) * CW, (i // 5) * CH, CW, CH]})
    im.save(os.path.join(a.out_dir, "rock_decor_template.png"))
    with open(os.path.join(a.out_dir, "rock_decor_template.json"), "w") as f:
        json.dump({"size": [W, H], "cell": [CW, CH], "texels_per_map_px": TEX, "pieces": out}, f, indent=1)
        f.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
