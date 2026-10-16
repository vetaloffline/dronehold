#!/usr/bin/env python3
"""Preview: the 10 rock decor pieces placed on map A (art/maps/map_a) next to / on top of its cliffs.

Cliff blocks are placed by the rules of game/core/cliffs.gd (map_a_natural.game_look's way); a piece on a rock
cell is lifted onto the top of that cell's block (median top of the block's middle 60 % + 10 px inset, as
Cliffs.top_y_at), a piece on the ground stands on its footprint (ground point like Prop: footprint centre,
0.85 of its height down). Everything is drawn bottom-last (Y-sort).
Writes <out>_full.png (half size) and crops <out>_ridge.png, <out>_field.png. Exit 0, 2 bad args.

Example (cut both sheets first, art/maps/cliffs/prompts.md; decor:
  python3 ../cliffs/cliff_sheet_cut.py rock_decor_sheet.png -t rock_decor_cut_template.json -o $TMPDIR/decor -p rock_decor):
  python3 rock_decor_on_map_a.py --cut $TMPDIR/cliff_cut --decor $TMPDIR/decor -o $TMPDIR/rock_decor_on_map_a
"""
import argparse
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "art", "maps", "map_a"))
sys.path.insert(0, os.path.join(ROOT, "art", "maps", "cliffs"))
from map_a_natural import build, COLS, ROWS, CW, CH, DECOR  # noqa: E402
from rock_blocks_preview import h01, kinds_for  # noqa: E402

KINDS = ["cliff_spire", "cliff_twin_spires", "cliff_crest", "cliff_rockfall", "cliff_slab",
         "cliff_split", "cliff_scree", "cliff_ledge", "cliff_arch", "cliff_fallen_pillar"]
# Placement = map A's decor (map_a_natural.DECOR): piece index, cell; on top when its footprint has cliff cells.
PLACE = [(KINDS.index(k), (c, r)) for k, c, r in DECOR]


def top_of(im):
    a = im.getchannel("A")
    w, h = im.size
    tops = []
    for x in range(int(w * 0.2), int(w * 0.8)):
        for y in range(h):
            if a.getpixel((x, y)) > 128:
                tops.append(y)
                break
    tops.sort()
    return tops[len(tops) // 2] if tops else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cut", required=True, help="cliff_sheet_cut.py output of the cliff blocks (cliff_wall/rock.json)")
    ap.add_argument("--decor", required=True, help="cliff_sheet_cut.py output of the decor sheet (rock_decor.json)")
    ap.add_argument("--scale", type=float, default=1.0, help="decor size × (default 1.0 = as Codex drew it)")
    ap.add_argument("-o", "--out", required=True, help="output prefix")
    a = ap.parse_args()
    if not os.path.isfile(os.path.join(a.decor, "rock_decor.json")):
        print("no rock_decor.json in --decor", file=sys.stderr)
        return 2
    L = build()
    groups = {}
    for name, grp in (("cliff_wall.json", "wall"), ("cliff_rock.json", "rock")):
        meta = json.load(open(os.path.join(a.cut, name)))
        k = 1.0 / meta["texels_per_map_px"]
        for b in meta["blocks"]:
            im = Image.open(os.path.join(a.cut, b["file"])).convert("RGBA")
            groups.setdefault((grp, b["kind"]), []).append((im, k, b["ground"], top_of(im)))
    W, H = COLS * CW, ROWS * CH
    g = Image.open(os.path.join(ROOT, "art/maps/ground/ground_dirt.png")).convert("RGBA").resize((320, 320), Image.LANCZOS)
    bg = Image.new("RGBA", (W, H))
    for y in range(0, H, 320):
        for x in range(0, W, 320):
            bg.paste(g, (x, y))
    kinds = kinds_for(L.rock)
    items, tops = [], {}
    for (c, r) in L.wall | L.rock:
        key = ("rock", kinds[(c, r)]) if (c, r) in L.rock else ("wall", "wall")
        opts = groups[key]
        im, k, gp, top = opts[int(h01(c, r, 7) * len(opts)) % len(opts)]
        z = k * (1.0 + (h01(c, r, 11) * 2 - 1) * 0.12)
        jx = (h01(c, r, 13) * 2 - 1) * 7
        jy = (h01(c, r, 17) * 2 - 1) * 3
        items.append(((r + 1) * CH - 1, c, im, z, ((c + 0.5) * CW - gp[0] * z + jx, (r + 1) * CH - gp[1] * z + jy)))
        tops[(c, r)] = (r + 1) * CH + jy - (gp[1] - top) * z + 10
    dm = json.load(open(os.path.join(a.decor, "rock_decor.json")))
    dk = a.scale / dm["texels_per_map_px"]
    tpl = json.load(open(os.path.join(HERE, "rock_decor_cut_template.json")))["blocks"]
    for i, (c0, r0) in PLACE:
        b = dm["blocks"][i]
        fw, fh = tpl[i]["foot_cells"]
        im = Image.open(os.path.join(a.decor, b["file"])).convert("RGBA")
        gx, gy = (c0 + fw / 2) * CW, (r0 + fh * 0.85) * CH
        lift = 0.0
        sort_y = gy
        cells = [(c0 + q, r0 + p) for p in range(fh) for q in range(fw)]
        on_top = any(c in tops for c in cells)
        if on_top:
            ts = [tops[c] for c in cells if c in tops]
            if not ts:
                print(f"piece {i} at {c0, r0}: not on a cliff", file=sys.stderr)
            else:
                lift = gy - sum(ts) / len(ts)
                sort_y = (max(r for (q, r) in cells if (q, r) in tops) + 1) * CH - 0.5
        items.append((sort_y, -1, im, dk, (gx - b["ground"][0] * dk, gy - lift - b["ground"][1] * dk)))
    for (_, _, im, z, pos) in sorted(items, key=lambda t: (t[0], t[1])):
        s = im.resize((max(1, round(im.width * z)), max(1, round(im.height * z))), Image.LANCZOS)
        bg.paste(s, (round(pos[0]), round(pos[1])), s)
    bg = bg.convert("RGB")
    bg.resize((W // 2, H // 2), Image.LANCZOS).save(a.out + "_full.png")
    bg.crop((500, 700, 2300, 1900)).save(a.out + "_ridge.png")
    bg.crop((1900, 200, 3700, 1500)).save(a.out + "_field.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
