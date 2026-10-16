#!/usr/bin/env python3
"""Map A dressing: pits, trees, bushes, stones placed by rules, checked for play, drawn as in the game.

Rules (cells 32x24, map A from map_a_natural.build()). Only along the cliffs — the strip of FOOT cells at
their foot and their tops; the open field stays empty for the person (2026-10-16: room to build and walk):
  - kept clear of anything that blocks (trees, boulders): core + 3 cells, every vein + drill slot + 6,
    spawns + 6, the 3 gorges (radius 8), the suggested relay spots + 2, the enemy paths ± 4 cells, and the
    core build radius (17 cells);
  - blocking dressing (not on cliff tops) takes at most BUDGET of the ground cells on each side of the ridge;
  - boulders (rock_m*, rock_mesa, rock_spire, rock_pit) at the foot of cliffs, ≤ 8, ≥ 12 cells apart;
  - groves where value noise is high; healthy near the base, dead trees and stumps towards the enemy corner
    (share of distance core → nearest spawn);
  - trees on top of cliffs (Prop climbs on the cliff in the game; no ground cells);
  - small stones, bushes, stumps — decor (build over, walk through), ≥ 3 cells apart;
  - pits (art/maps/pits): PIT_WANT, empty now; the placer and the pit cell rule (more than half of the cell
    under the sprite) stay for later.
Checks: every spawn still reaches the core, path length change per spawn, nothing overlaps.
Writes <out>_full.png (half size), <out>_base.png, <out>_field.png (crops), <out>_scheme.png (cells: pits,
blocking, decor, paths), --json or <out>.json ({"pits": [[name, c, r]], "props": [[kind, c, r, decor]]}) —
art/maps/map_a/map_a_dressing.json is what tools/build_map_a.gd puts into the scene.
Exit 0 ok, 1 a check failed, 2 bad args.

Example (cut cliffs first, art/maps/cliffs/prompts.md):
  python3 map_a_dressing.py --cut $TMPDIR/cliff_cut -o $TMPDIR/dress --json map_a_dressing.json
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "art", "maps", "cliffs"))
from map_a_natural import build, DECOR  # noqa: E402
from map_concepts import COLS, ROWS, CW, CH, CORE_R, Layout, check, cells_of  # noqa: E402
from rock_blocks_preview import h01, kinds_for  # noqa: E402

PITS_DIR = os.path.join(ROOT, "art", "maps", "pits")
PROPS_DIR = os.path.join(ROOT, "art", "maps", "props")
# Texels per map px of each pit sprite (art/maps/pits/prompts.md).
PIT_TEXELS = {"pit_vee": 2.84, "pit_oval": 4.37, "pit_snake": 3.56, "pit_round": 3.0}
# Pit, wanted centre cell: the pit goes to the nearest top-left cell (spiral, ≤ 14 cells) where it touches no
# cliff (± 1), no kept cell and no enemy path (± 4); PITS (top-left cells) is what place() found.
# Pits stand in the open field, which the person dresses (2026-10-16) → none here. Tried and fitting
# with the margins below: ("pit_oval", 105, 25), ("pit_snake", 78, 63), ("pit_round", 110, 72); pit_vee
# (17×12 cells) fits nowhere.
PIT_WANT = []
PITS = []
PASSES = [(20, 41), (50, 53), (79, 83)]
# Most ground cells blocking dressing (pits + trees / rocks not on cliffs) may take, per side of the main ridge.
BUDGET = {"base": 0.04, "enemy": 0.08}
# Width of the strip along the cliffs that gets dressing (cells from the nearest cliff cell).
FOOT = 2
BIG_ROCKS = ["rock_m1", "rock_m2", "rock_m3", "rock_mesa", "rock_spire", "rock_pit"]
HEALTHY = ["tree_tall", "tree_mid", "tree_small", "trees_3", "trees_5", "tree_tall", "tree_mid", "trees_3"]
DEAD = ["tree_dead", "tree_dead", "stump", "tree_small"]
SMALL = ["rock_s1", "rock_s2", "rock_s3", "bush_round", "bush_wide", "rock_s1", "bush_round"]
SMALL_DEAD = ["rock_s1", "rock_s2", "rock_s3", "stump", "rock_s2"]


def props_meta():
    meta = {}
    for p in json.load(open(os.path.join(PROPS_DIR, "props.json"))):
        f = p.get("foot_cells") or [p["foot"][0] * 2, p["foot"][1] * 2]
        meta[p["name"]] = {"foot": tuple(f), "ground": p["ground"], "body_w": p["body_w"], "file": p["file"]}
    return meta


def pit_cells(name, c0, r0):
    im = Image.open(os.path.join(PITS_DIR, name + ".png")).convert("RGBA")
    k = 1.0 / PIT_TEXELS[name]
    w, h = round(im.width * k), round(im.height * k)
    a = np.array(im.getchannel("A").resize((w, h), Image.LANCZOS)) > 128
    out = set()
    for r in range(math.ceil(h / CH)):
        for c in range(math.ceil(w / CW)):
            if a[r * CH:(r + 1) * CH, c * CW:(c + 1) * CW].sum() > CW * CH * 0.5:
                out.add((c0 + c, r0 + r))
    return out


def vnoise2(c, r, salt, step):
    """Smooth 0..1 value noise over cells (bilinear between hashed lattice points, smoothstep)."""
    gx, gy = c / step, r / step
    ix, iy = math.floor(gx), math.floor(gy)
    fx, fy = gx - ix, gy - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = h01(ix, iy, salt) * (1 - fx) + h01(ix + 1, iy, salt) * fx
    b = h01(ix, iy + 1, salt) * (1 - fx) + h01(ix + 1, iy + 1, salt) * fx
    return a * (1 - fy) + b * fy


def grow(cells, n):
    out = set(cells)
    for (c, r) in cells:
        for dr in range(-n, n + 1):
            for dc in range(-n, n + 1):
                out.add((c + dc, r + dr))
    return out


def dist_from(src, blocked):
    """8-neighbour BFS distance (cells) from src over free cells."""
    d = {c: 0 for c in src}
    q = list(src)
    i = 0
    while i < len(q):
        c = q[i]
        i += 1
        for dc in (-1, 0, 1):
            for dr in (-1, 0, 1):
                n = (c[0] + dc, c[1] + dr)
                if n not in d and 0 <= n[0] < COLS and 0 <= n[1] < ROWS and n not in blocked:
                    d[n] = d[c] + 1
                    q.append(n)
    return d


def place(L, meta):
    cliffs = L.wall | L.rock
    core_c = (L.core[0] + 3, L.core[1] + 3)
    in_radius = lambda c: math.hypot(c[0] + 0.5 - core_c[0], c[1] + 0.5 - core_c[1]) <= CORE_R
    keep = grow(cells_of(*L.core, 6, 6), 3)
    for v in L.veins:
        keep |= grow(cells_of(v[0], v[1], 6, 6) | cells_of(*Layout.slot(v), 2, 2), 6)
    for s in L.slime + L.lasher:
        keep |= grow(cells_of(*s, 2, 2), 6)
    for (x, y) in PASSES:
        keep |= {(c, r) for c in range(x - 8, x + 9) for r in range(y - 8, y + 9) if math.hypot(c - x, r - y) <= 8}
    for (x, y) in L.relays:
        keep |= grow(cells_of(x, y, 2, 2), 2)
    errs = []
    _, paths0, _ = check(L)
    no_pit = grow(cliffs, 1) | keep | grow({c for p in paths0 for c in p["path"]}, 4)
    pits = {}
    PITS.clear()
    for name, x, y in PIT_WANT:
        cs0 = pit_cells(name, 0, 0)
        w, h = max(c for c, _ in cs0) + 1, max(r for _, r in cs0) + 1
        best = None
        for rad in range(15):
            for dy in range(-rad, rad + 1):
                for dx in range(-rad, rad + 1):
                    if max(abs(dx), abs(dy)) != rad:
                        continue
                    c0, r0 = x - w // 2 + dx, y - h // 2 + dy
                    cs = {(c + c0, r + r0) for c, r in cs0}
                    taken_pits = set().union(*pits.values()) if pits else set()
                    if all(0 <= c < COLS and 0 <= r < ROWS for c, r in cs) and not cs & no_pit and not grow(cs, 2) & taken_pits:
                        best = (c0, r0, cs)
                        break
                if best:
                    break
            if best:
                break
        if best is None:
            errs.append(f"{name}: no free place near {x, y}")
            continue
        PITS.append((name, best[0], best[1]))
        pits[name] = best[2]
    pit_all = set().union(*pits.values()) if pits else set()
    # Enemy paths with the pits in.
    L2 = build()
    L2.rock |= pit_all
    e2, paths, _ = check(L2)
    errs += e2
    corridor = grow({c for p in paths for c in p["path"]}, 4)
    d_cliff = dist_from(cliffs, set())
    spawns = [(s[0] + 1, s[1] + 1) for s in L.slime + L.lasher]

    def health(c):
        dc = math.hypot(c[0] - core_c[0], c[1] - core_c[1])
        ds = min(math.hypot(c[0] - s[0], c[1] - s[1]) for s in spawns)
        return dc / (dc + ds)

    # Rock decor (map_a_natural.DECOR) already stands there.
    taken = set(pit_all).union(*(cells_of(c, r, *meta[k]["foot"]) for k, c, r in DECOR))
    props = []
    base = base_side(L)
    ground_n = {"base": len(base), "enemy": COLS * ROWS - len(cliffs) - len(base)}
    used = {"base": len(pit_all & base), "enemy": len(pit_all - base)}
    for side in used:
        if used[side] > BUDGET[side] * ground_n[side]:
            errs.append(f"pits alone take {used[side]} cells of the {side} side, over budget")
    order = sorted(((c, r) for r in range(ROWS) for c in range(COLS)), key=lambda c: h01(c[0], c[1], 91))

    def put(kind, c, decor, extra_keep=frozenset(), spacing=0, on_cliff=False):
        fw, fh = meta[kind]["foot"]
        cs = cells_of(c[0], c[1], fw, fh)
        if any(not (0 <= x < COLS and 0 <= y < ROWS) for (x, y) in cs):
            return False
        if cs & taken or cs & pit_all:
            return False
        if on_cliff:
            if not cs <= L.rock:
                return False
        elif cs & cliffs:
            return False
        if not decor and (cs & keep or cs & extra_keep or any(in_radius(x) for x in cs)):
            return False
        if decor and cs & grow(cells_of(*L.core, 6, 6), 1):
            return False
        if spacing and grow(cs, spacing) & {x for p in props if p[4] == spacing for x in p[5]}:
            return False
        if not decor and not on_cliff:
            side = "base" if c in base else "enemy"
            if used[side] + len(cs) > BUDGET[side] * ground_n[side]:
                return False
            used[side] += len(cs)
        props.append([kind, c[0], c[1], decor, spacing, cs])
        taken.update(cs)
        return True

    # Only along the cliffs: the strip at their foot (FOOT cells) and their tops. The open field stays empty —
    # the person dresses it (rule of 2026-10-16: room to build and walk).
    strip = lambda c, kind: all(1 <= d_cliff.get(x, 99) <= FOOT for x in cells_of(c[0], c[1], *meta[kind]["foot"]))

    def pick(pool, c, salt):
        return pool[int(h01(c[0], c[1], salt) * len(pool))]

    # 1. Boulders fallen at the foot of cliffs, a few, far apart.
    n_big = 0
    for c in order:
        if n_big >= 8:
            break
        kind = pick(BIG_ROCKS, c, 92)
        if strip(c, kind) and put(kind, c, False, extra_keep=corridor, spacing=12):
            n_big += 1
    # 2. Groves at the foot of cliffs where the noise is high: healthy near the base, dead towards the enemy.
    for c in order:
        if vnoise2(c[0], c[1], 93, 12.0) <= 0.5 or h01(c[0], c[1], 100) > 0.6:
            continue
        hl = health(c)
        kind = pick(HEALTHY if hl < 0.45 else (DEAD if hl > 0.68 else HEALTHY[:3] + DEAD), c, 95)
        if strip(c, kind):
            put(kind, c, kind == "stump", extra_keep=corridor)
    # 3. Trees on cliff tops (take no ground cells).
    n_top = 0
    for c in order:
        if n_top >= 40:
            break
        if c not in L.rock:
            continue
        inner = all((c[0] + dc, c[1] + dr) in L.rock for dc in range(-1, 3) for dr in range(-1, 3))
        hl = health(c)
        kind = "tree_dead" if hl > 0.68 else ("trees_3" if h01(c[0], c[1], 96) < 0.5 else "tree_tall")
        if inner and put(kind, c, False, on_cliff=True, spacing=3):
            n_top += 1
    # 4. Small stones, bushes, stumps at the foot of cliffs: decor (walk through, build over).
    for c in order:
        if h01(c[0], c[1], 97) > 0.35:
            continue
        kind = pick(SMALL_DEAD if health(c) > 0.68 else SMALL, c, 98)
        if strip(c, kind):
            put(kind, c, True, spacing=3)
    return pits, pit_all, props, paths, errs, corridor, keep, in_radius


def base_side(L):
    """Cells on the core's side of the main ridge: flood from the core over ground, the gorges closed."""
    cliffs = L.wall | L.rock
    shut = {(c, r) for (x, y) in PASSES for c in range(x - 4, x + 5) for r in range(y - 4, y + 5)}
    return set(dist_from(cells_of(*L.core, 6, 6), cliffs | shut)) - shut


def clearance(blocked):
    """Cells → distance (cells, 8-neighbour) to the nearest blocked cell or the map edge."""
    edge = {(c, r) for c in range(-1, COLS + 1) for r in (-1, ROWS)} | {(c, r) for c in (-1, COLS) for r in range(ROWS)}
    d = {c: 0 for c in blocked | edge}
    q = list(d)
    i = 0
    while i < len(q):
        c = q[i]
        i += 1
        for dc in (-1, 0, 1):
            for dr in (-1, 0, 1):
                n = (c[0] + dc, c[1] + dr)
                if n not in d and 0 <= n[0] < COLS and 0 <= n[1] < ROWS:
                    d[n] = d[c] + 1
                    q.append(n)
    return d


def report(L, pit_all, props, paths0, paths, in_radius):
    """Room left to walk and build: per side of the ridge, in the core radius, along the enemy paths."""
    cliffs = L.wall | L.rock
    ground = {(c, r) for c in range(COLS) for r in range(ROWS)} - cliffs
    block = set(pit_all) | {x for p in props if not p[3] for x in p[5]}
    block_ground = block & ground
    base = base_side(L)
    print("Room (ground cells = not cliff):")
    for name, zone in (("base side of the ridge", base & ground), ("enemy side", ground - base),
                       ("core build radius", {c for c in ground if in_radius(c)})):
        taken = len(block_ground & zone)
        print(f"  {name}: {len(zone)} cells, dressing blocks {taken} ({100 * taken / max(1, len(zone)):.1f} %)"
              f" — pits {len(pit_all & zone)}, trees / rocks {len((block_ground - pit_all) & zone)}")
    c0, c1 = clearance(cliffs), clearance(cliffs | block)
    print("Enemy paths — dressing next to the path:")
    for p0, p1 in zip(paths0, paths):
        mid = p1["path"][4:-8]
        narrowed = sum(1 for c in mid if c1[c] < min(c0[c], 5))
        print(f"  {p1['kind']} {p1['spawn']}: path cells where dressing leaves < 5 cells of room: {narrowed}")
    print("Gorges — free width across (cells, cliffs only → with dressing):",
          ", ".join(f"{x, y}: {2 * c0[(x, y)] - 1} → {2 * c1[(x, y)] - 1}" for x, y in PASSES))
    deco = sum(1 for p in props if p[3])
    print(f"Objects: blocking {len(props) - deco} (of them on cliff tops {sum(1 for p in props if not p[3] and set(p[5]) <= cliffs)}), "
          f"decor (walk / build over) {deco}, pits {len(PITS)}")


def render(L, meta, pits, props, cut, out):
    groups = {}
    for name, grp in (("cliff_wall.json", "wall"), ("cliff_rock.json", "rock")):
        m = json.load(open(os.path.join(cut, name)))
        k = 1.0 / m["texels_per_map_px"]
        for b in m["blocks"]:
            im = Image.open(os.path.join(cut, b["file"])).convert("RGBA")
            a = np.array(im.getchannel("A")) > 128
            cols = a[:, int(im.width * 0.2):int(im.width * 0.8)]
            tops = [int(np.argmax(col)) for col in cols.T if col.any()]
            groups.setdefault((grp, b["kind"]), []).append((im, k, b["ground"], sorted(tops)[len(tops) // 2]))
    W, H = COLS * CW, ROWS * CH
    g = Image.open(os.path.join(ROOT, "art/maps/ground/ground_dirt.png")).convert("RGBA").resize((320, 320), Image.LANCZOS)
    bg = Image.new("RGBA", (W, H))
    for y in range(0, H, 320):
        for x in range(0, W, 320):
            bg.paste(g, (x, y))
    for name, c, r in PITS:
        im = Image.open(os.path.join(PITS_DIR, name + ".png")).convert("RGBA")
        k = 1.0 / PIT_TEXELS[name]
        s = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
        bg.alpha_composite(s, (c * CW, r * CH))
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
    ims = {}
    allp = [[k, c, r, False] for k, c, r in DECOR] + [p[:4] for p in props]
    for kind, c0, r0, _ in allp:
        m = meta[kind]
        if kind not in ims:
            ims[kind] = Image.open(os.path.join(PROPS_DIR, m["file"])).convert("RGBA")
        im = ims[kind]
        fw, fh = m["foot"]
        z = fw * CW / m["body_w"]
        gx, gy = (c0 + fw / 2) * CW, (r0 + fh * 0.85) * CH
        cs = [(c0 + q, r0 + p) for p in range(fh) for q in range(fw)]
        ts = [tops[x] for x in cs if x in tops]
        lift, sort_y = 0.0, gy
        if ts:
            lift = gy - sum(ts) / len(ts)
            sort_y = (max(r for (q, r) in cs if (q, r) in tops) + 1) * CH - 0.5
        items.append((sort_y, -1, im, z, (gx - m["ground"][0] * z, gy - lift - m["ground"][1] * z)))
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
        bg.alpha_composite(s, (max(0, round(pos[0])), max(0, round(pos[1]))))
    d = ImageDraw.Draw(bg, "RGBA")
    for pts, col in ((L.slime, (230, 40, 40, 200)), (L.lasher, (255, 140, 0, 200))):
        for (x, y) in pts:
            d.ellipse((x * CW - 6, y * CH - 6, (x + 2) * CW + 6, (y + 2) * CH + 6), outline=col, width=6)
    bg = bg.convert("RGB")
    bg.resize((W // 2, H // 2), Image.LANCZOS).save(out + "_full.png")
    bg.crop((0, 1000, 2000, 2304)).save(out + "_base.png")
    bg.crop((2000, 0, 4096, 1400)).save(out + "_field.png")
    bg.crop((1200, 600, 3200, 1900)).save(out + "_middle.png")


def scheme(L, pit_all, props, paths, keep, out):
    s = 8
    im = Image.new("RGB", (COLS * s, ROWS * s), (196, 150, 96))
    d = ImageDraw.Draw(im)
    cell = lambda c, col: d.rectangle((c[0] * s, c[1] * s, c[0] * s + s - 1, c[1] * s + s - 1), fill=col)
    for c in keep:
        if 0 <= c[0] < COLS and 0 <= c[1] < ROWS:
            cell(c, (214, 182, 140))
    for c in L.wall | L.rock:
        cell(c, (110, 105, 100))
    for c in pit_all:
        cell(c, (30, 25, 40))
    for p in props:
        for c in p[5]:
            cell(c, (150, 200, 120) if p[3] else (40, 110, 50))
    cell_r = lambda x, y, w, h, col: d.rectangle((x * s, y * s, (x + w) * s - 1, (y + h) * s - 1), outline=col, width=2)
    cell_r(*L.core, 6, 6, (40, 200, 255))
    for v in L.veins:
        cell_r(v[0], v[1], 6, 6, (70, 110, 230))
    for p in paths:
        col = (230, 40, 40) if p["kind"] == "slime" else (255, 140, 0)
        d.line([((x + 0.5) * s, (y + 0.5) * s) for (x, y) in p["path"]], fill=col, width=2)
    im.save(out + "_scheme.png")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cut", required=True, help="cliff_sheet_cut.py output of the cliff blocks (cliff_wall/rock.json)")
    ap.add_argument("-o", "--out", required=True, help="output prefix of the previews")
    ap.add_argument("--json", default="", help="where to write the placement (default: <out>.json); the scene builder "
                    "tools/build_map_a.gd reads art/maps/map_a/map_a_dressing.json")
    a = ap.parse_args()
    if not os.path.isfile(os.path.join(a.cut, "cliff_rock.json")):
        print("no cliff_rock.json in --cut", file=sys.stderr)
        return 2
    L = build()
    meta = props_meta()
    _, paths0, _ = check(L)
    print("pit wanted centres:", PIT_WANT)
    pits, pit_all, props, paths, errs, _, keep, in_radius = place(L, meta)
    for e in errs:
        print("ERROR", e)
    for p0, p1 in zip(paths0, paths):
        print(f"{p1['kind']} {p1['spawn']}: {p0['cells']} → {p1['cells']} cells ({p1['sec']} s)")
    cnt = {}
    for p in props:
        cnt[p[0]] = cnt.get(p[0], 0) + 1
    print("pits:", PITS, {n: len(cs) for n, cs in pits.items()}, "cells")
    print(f"props {len(props)} (blocking {sum(1 for p in props if not p[3])}, decor {sum(1 for p in props if p[3])}):", cnt)
    report(L, pit_all, props, paths0, paths, in_radius)
    scheme(L, pit_all, props, paths, keep, a.out)
    render(L, meta, pits, props, a.cut, a.out)
    with open(a.json or a.out + ".json", "w") as f:
        json.dump({"pits": [list(p) for p in PITS], "props": [p[:4] for p in props]}, f)
        f.write("\n")
    return 1 if errs else 0


if __name__ == "__main__":
    raise SystemExit(main())
