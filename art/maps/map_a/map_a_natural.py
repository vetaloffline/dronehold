#!/usr/bin/env python3
"""Concept A «Ущелина», natural shapes: nothing square.

  - map edge: wall (stone columns) 2 cells + up to --edge-extra more by smooth noise, corners rounded in;
  - main ridge: a Catmull-Rom curve from the left edge to the bottom edge, half-width 1.2..3 cells by noise;
    at the passes it tapers to nothing over --taper cells (a natural gorge, not a cut);
  - islands: blobs whose radius wobbles with the angle; small outcrops in the field.
Checks and schematic: map_concepts.py (paths by the game's flow-field rule, relays per vein, overlaps).
Game look: blocks placed by the rules of game/core/cliffs.gd (rock height by distance from ridge ends +
humps, block / size / shift by hash) from the cut blocks of art/maps/cliffs (cliff_sheet_cut.py output).
Writes <out>/map_a_scheme.png, <out>/map_a_preview.png (half size) + crops, <out>/map_a.json — the input of
the scene generator (game/maps/map_a/map_a.tscn was built from it; rebuilding the scene wipes hand edits).
Exit 0 ok, 1 a check failed, 2 bad args.

Example (cut first: art/maps/cliffs/prompts.md): python3 map_a_natural.py --cut $TMPDIR/cliff_cut -o $TMPDIR/map_a
"""
import argparse
import json
import math
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "art", "maps", "cliffs"))
from map_concepts import COLS, ROWS, CW, CH, Layout, check, render  # noqa: E402
from rock_blocks_preview import h01, kinds_for  # noqa: E402


def vnoise(x, salt, step=6.0):
    """Smooth 0..1 noise along one axis."""
    g = x / step
    i = math.floor(g)
    f = g - i
    f = f * f * (3 - 2 * f)
    return h01(i, 0, salt) * (1 - f) + h01(i + 1, 0, salt) * f


def catmull(pts, step=0.25):
    out = []
    p = [pts[0]] + pts + [pts[-1]]
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        seg = math.dist(p1, p2)
        n = max(1, int(seg / step))
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in (0, 1)))
    out.append(pts[-1])
    return out


def stamp(cells, x, y, r):
    for cy in range(int(y - r) - 1, int(y + r) + 2):
        for cx in range(int(x - r) - 1, int(x + r) + 2):
            if (cx + 0.5 - x) ** 2 + (cy + 0.5 - y) ** 2 <= r * r and 0 <= cx < COLS and 0 <= cy < ROWS:
                cells.add((cx, cy))


def ridge(L, pts, w0, w1, salt, passes=(), taper=6.0, gap=3.0):
    """Rock along a smooth curve; half-width w0..w1 by noise; zero within `gap` of a pass, ramps over `taper`."""
    curve = catmull(pts)
    s = 0.0
    prev = curve[0]
    for (x, y) in curve:
        s += math.dist(prev, (x, y))
        prev = (x, y)
        w = w0 + (w1 - w0) * vnoise(s, salt)
        for px, py in passes:
            d = math.hypot(x - px, y - py)
            if d < gap:
                w = 0.0
            elif d < gap + taper:
                k = (d - gap) / taper
                w *= k * k * (3 - 2 * k)
        if w > 0.45:
            stamp(L.rock, x, y, w)


def blob(L, cx, cy, r, salt, stretch=(1.0, 1.0)):
    for y in range(int(cy - r * stretch[1]) - 3, int(cy + r * stretch[1]) + 4):
        for x in range(int(cx - r * stretch[0]) - 3, int(cx + r * stretch[0]) + 4):
            dx, dy = (x + 0.5 - cx) / stretch[0], (y + 0.5 - cy) / stretch[1]
            a = math.atan2(dy, dx)
            rr = r * (0.75 + 0.5 * vnoise((a + math.pi) * 3.0, salt, 1.0))
            if dx * dx + dy * dy <= rr * rr and 0 <= x < COLS and 0 <= y < ROWS:
                L.rock.add((x, y))


def edge(L, extra, salt):
    """Wall (stone columns) 2 cells at the very edge; natural rock in front of it, 0..extra cells deep by
    noise, and deeper in the corners, so the frame of the map does not read as a rectangle."""
    for r in range(ROWS):
        for c in range(COLS):
            t = {"l": c, "r": COLS - 1 - c, "t": r, "b": ROWS - 1 - r}
            depth = 99.0
            for side, d in t.items():
                along = r if side in "lr" else c
                n = vnoise(along, salt + ord(side), 5.0) * 0.6 + vnoise(along, salt + ord(side) + 50, 13.0) * 0.4
                depth = min(depth, d - 2 - extra * n * n * 1.6)
            for kx, ky in ((0, 0), (COLS - 1, 0), (0, ROWS - 1), (COLS - 1, ROWS - 1)):
                depth = min(depth, math.hypot(c - kx, (r - ky) * 1.3) - 9 - 4 * vnoise(c + r, salt + 9, 5.0))
            if min(t.values()) < 2:
                L.wall.add((c, r))
            elif depth < 0:
                L.rock.add((c, r))


def build():
    L = Layout("A", "Ущелина (природна)", "База в куті. Хребет-крива відгороджує кут, 3 ущелини-проходи; вороги з протилежного кута через поле з камінням.")
    edge(L, 7.0, 40)
    ridge(L, [(-2, 38), (12, 39), (26, 43), (40, 48), (54, 56), (66, 65), (76, 77), (84, 97)], 2.4, 5.0, 11,
          passes=[(20, 41), (50, 53), (79, 83)], taper=5.0, gap=2.6)
    ridge(L, [(40, 14), (50, 12), (58, 17)], 1.5, 3.0, 21)
    ridge(L, [(94, 48), (100, 56), (108, 62)], 1.6, 3.2, 31)
    blob(L, 78, 22, 6.5, 41, (1.4, 1.0))
    blob(L, 33, 73, 2.6, 42)
    blob(L, 90, 38, 3.0, 43)
    blob(L, 64, 84, 5.0, 45, (1.5, 0.9))
    blob(L, 22, 18, 4.0, 46, (1.3, 1.0))
    blob(L, 108, 86, 4.5, 47, (1.4, 0.8))
    blob(L, 52, 34, 3.2, 48, (1.2, 0.9))
    L.rock -= L.wall
    L.core = (12, 72)
    L.vein(18, 80, "R")
    L.vein(10, 56, "R")
    L.vein(38, 61, "R")
    L.vein(28, 28, "R")
    L.vein(62, 32, "L")
    L.vein(94, 74, "L")
    L.slime = [(112, 8), (116, 40)]
    L.lasher = [(86, 12)]
    L.relays = [(26, 62), (34, 54)]
    return L


def game_look(L, cut, out):
    """Blocks by the rules of game/core/cliffs.gd (rig defaults: jitter 0.12 / 7 / 3 px, scale 1)."""
    groups = {}
    for name, grp in (("cliff_wall.json", "wall"), ("cliff_rock.json", "rock")):
        meta = json.load(open(os.path.join(cut, name)))
        k = 1.0 / meta["texels_per_map_px"]
        for b in meta["blocks"]:
            im = Image.open(os.path.join(cut, b["file"])).convert("RGBA")
            groups.setdefault((grp, b["kind"]), []).append((im, k, b["ground"]))
    W, H = COLS * CW, ROWS * CH
    g = Image.open(os.path.join(ROOT, "art/maps/ground/ground_dirt.png")).convert("RGBA").resize((320, 320), Image.LANCZOS)
    bg = Image.new("RGBA", (W, H))
    for y in range(0, H, 320):
        for x in range(0, W, 320):
            bg.paste(g, (x, y))
    kinds = kinds_for(L.rock)
    items = []
    for (c, r) in L.wall | L.rock:
        key = ("rock", kinds[(c, r)]) if (c, r) in L.rock else ("wall", "wall")
        opts = groups[key]
        im, k, gp = opts[int(h01(c, r, 7) * len(opts)) % len(opts)]
        z = k * (1.0 + (h01(c, r, 11) * 2 - 1) * 0.12)
        jx = (h01(c, r, 13) * 2 - 1) * 7
        jy = (h01(c, r, 17) * 2 - 1) * 3
        items.append(((r + 1) * CH - 1, c, im, z, ((c + 0.5) * CW - gp[0] * z + jx, (r + 1) * CH - gp[1] * z + jy)))
    core = Image.open(os.path.join(ROOT, "art/objects/buildings/core/core_with_shadow.png")).convert("RGBA")
    vein = Image.open(os.path.join(ROOT, "art/objects/resources/crystal_vein/crystal_vein_with_shadow.png")).convert("RGBA")

    def sprite(im, cell, foot, width_cells):
        z = foot[0] * CW * width_cells / im.width
        bbox = im.getchannel("A").getbbox()
        gx, gy = (bbox[0] + bbox[2]) / 2, bbox[3] * 0.93
        x, y = (cell[0] + foot[0] / 2) * CW, (cell[1] + foot[1] * 0.85) * CH
        return (y, -1, im, z, (x - gx * z, y - gy * z))

    items.append(sprite(core, L.core, (6, 6), 1.15))
    for v in L.veins:
        items.append(sprite(vein, v[:2], (6, 6), 1.1))
    for (_, _, im, z, pos) in sorted(items, key=lambda t: (t[0], t[1])):
        s = im.resize((max(1, round(im.width * z)), max(1, round(im.height * z))), Image.LANCZOS)
        bg.paste(s, (round(pos[0]), round(pos[1])), s)
    d = ImageDraw.Draw(bg, "RGBA")
    for pts, col in ((L.slime, (230, 40, 40, 200)), (L.lasher, (255, 140, 0, 200))):
        for (x, y) in pts:
            d.ellipse((x * CW - 6, y * CH - 6, (x + 2) * CW + 6, (y + 2) * CH + 6), outline=col, width=6)
    bg = bg.convert("RGB")
    bg.resize((W // 2, H // 2), Image.LANCZOS).save(os.path.join(out, "map_a_preview.png"))
    bg.crop((0, 1100, 1900, 2304)).save(os.path.join(out, "map_a_preview_base.png"))
    bg.crop((1100, 900, 2900, 2304)).save(os.path.join(out, "map_a_preview_ridge.png"))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cut", required=True, help="folder with cliff_wall.json / cliff_rock.json from cliff_sheet_cut.py")
    ap.add_argument("-o", "--out", default=".", help="output folder (default: current)")
    a = ap.parse_args()
    if not os.path.isfile(os.path.join(a.cut, "cliff_rock.json")) or not os.path.isdir(a.out):
        print("bad --cut or --out", file=sys.stderr)
        return 2
    L = build()
    errs, paths, veins = check(L)
    for e in errs:
        print("ERROR", e)
    print("; ".join(f"{p['kind']} {p['spawn']} {p['cells']} cells {p['sec']} s" for p in paths))
    print("veins: " + ", ".join(f"{v['vein']} far {v['slot_far']} relays {v['relays']}" for v in veins))
    print(f"rock {len(L.rock)} cells, wall {len(L.wall)} cells")
    render(L, paths, veins).save(os.path.join(a.out, "map_a_scheme.png"))
    game_look(L, a.cut, a.out)
    with open(os.path.join(a.out, "map_a.json"), "w") as f:
        json.dump({"size": [COLS, ROWS], "wall": sorted(L.wall), "rock": sorted(L.rock), "core": L.core, "veins": L.veins,
                   "slime": L.slime, "lasher": L.lasher, "paths": [{k: v for k, v in p.items() if k != "path"} for p in paths],
                   "vein_checks": veins}, f)
        f.write("\n")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
