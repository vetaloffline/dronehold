#!/usr/bin/env python3
"""Four map layout concepts (base, crystal veins, spawn points, cliffs) as cell data + schematic previews.

Every layout is 128x96 cells of 32x24 px (the game grid). Cells: wall (stone columns, map edge), rock
(natural cliff inside), objects: core 6x6, veins 6x6 with a 2x2 drill slot (right: cell + (6, 0), left:
cell + (-2, 0), crystal_vein.gd), slime spawns 2x2, lasher spawns 2x2.
Checks per layout (rules from docs/concept.md):
  - path: shortest walk from each spawn to the core around wall / rock / veins, the rule of
    game/swarm/flow_field.gd (8 neighbours, diagonal √2, no corner cutting); cells and seconds at 0.72 cells/s;
  - relays: a vein's drill slot is buildable when the centre of each slot cell is within 17 cells of the
    core centre (core radius); else ceil((far - 17) / 8) relays (each relay at the edge of a radius adds
    up to 8 cells: radius 9 from its centre, placed 1 cell inside);
  - overlaps: objects on wall / rock or on each other -> error.
Writes <out>/concept_<key>.png (one schematic each, 3/4 squashed like the game), <out>/concepts_sheet.png
(2x2) and <out>/concepts.json (cells + objects + checks, the input for building the chosen map).
Exit 0 ok, 1 a layout has an error, 2 bad args.

Example: python3 map_concepts.py -o .
"""
import argparse
import json
import math
import os
import sys
import heapq

from PIL import Image, ImageDraw, ImageFont

COLS, ROWS = 128, 96
CW, CH = 32, 24
SLIME_SPEED = 0.72
CORE_R, RELAY_STEP = 17.0, 8.0
DIAG = 1.41421356
FONT = "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"


class Layout:
    def __init__(self, key, title, idea):
        self.key, self.title, self.idea = key, title, idea
        self.wall, self.rock = set(), set()
        self.core = None
        self.veins = []      # (x, y, side)
        self.slime = []      # (x, y)
        self.lasher = []     # (x, y)
        self.relays = []     # suggested relay spots (x, y), drawn only

    def perimeter(self, t=2):
        for r in range(ROWS):
            for c in range(COLS):
                if c < t or r < t or c >= COLS - t or r >= ROWS - t:
                    self.wall.add((c, r))

    def rect(self, x0, y0, x1, y1):
        for r in range(y0, y1 + 1):
            for c in range(x0, x1 + 1):
                if 0 <= c < COLS and 0 <= r < ROWS:
                    self.rock.add((c, r))

    def line(self, pts, t=2):
        """Rock ridge along a polyline, t cells thick (square stamp every half cell)."""
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            n = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
            for i in range(n + 1):
                x = x0 + (x1 - x0) * i / n
                y = y0 + (y1 - y0) * i / n
                self.rect(int(round(x)), int(round(y)), int(round(x)) + t - 1, int(round(y)) + t - 1)

    def gap(self, x0, y0, x1, y1):
        for r in range(y0, y1 + 1):
            for c in range(x0, x1 + 1):
                self.rock.discard((c, r))

    def vein(self, x, y, side="R"):
        self.veins.append((x, y, side))

    @staticmethod
    def slot(v):
        x, y, side = v
        # game/objects/crystal_vein/crystal_vein.gd SLOT (6, 0) / SLOT_LEFT (−2, 0)
        return (x + 6, y) if side == "R" else (x - 2, y)


def cells_of(x, y, w, h):
    return {(x + i, y + j) for j in range(h) for i in range(w)}


def check(L):
    errs = []
    solid = L.wall | L.rock
    objs = [("core", cells_of(*L.core, 6, 6))]
    for i, v in enumerate(L.veins):
        objs.append((f"vein {i + 1}", cells_of(v[0], v[1], 6, 6)))
        objs.append((f"slot {i + 1}", cells_of(*Layout.slot(v), 2, 2)))
    for i, s in enumerate(L.slime):
        objs.append((f"slime {i + 1}", cells_of(*s, 2, 2)))
    for i, s in enumerate(L.lasher):
        objs.append((f"lasher {i + 1}", cells_of(*s, 2, 2)))
    taken = {}
    for name, cs in objs:
        if cs & solid:
            errs.append(f"{name} on cliff")
        for c in cs:
            if c in taken:
                errs.append(f"{name} overlaps {taken[c]}")
                break
        for c in cs:
            taken[c] = name
    blocked = solid | set().union(*[cells_of(v[0], v[1], 6, 6) for v in L.veins])
    core_cells = cells_of(*L.core, 6, 6)
    # Same rule as game/swarm/flow_field.gd: 8 neighbours, diagonal √2, no corner cutting.
    steps = [(1, 0, 1.0), (-1, 0, 1.0), (0, 1, 1.0), (0, -1, 1.0),
             (1, 1, DIAG), (1, -1, DIAG), (-1, 1, DIAG), (-1, -1, DIAG)]
    free = lambda c: 0 <= c[0] < COLS and 0 <= c[1] < ROWS and c not in blocked
    dist = {c: 0.0 for c in core_cells}
    heap = [(0.0, c) for c in core_cells]
    while heap:
        dc, c = heapq.heappop(heap)
        if dc > dist[c]:
            continue
        for dx, dy, w in steps:
            n = (c[0] + dx, c[1] + dy)
            if not free(n) or (dx and dy and not (free((c[0] + dx, c[1])) and free((c[0], c[1] + dy)))):
                continue
            if dc + w < dist.get(n, 1e18):
                dist[n] = dc + w
                heapq.heappush(heap, (dc + w, n))
    paths = []
    for kind, pts in (("slime", L.slime), ("lasher", L.lasher)):
        for s in pts:
            starts = [c for c in cells_of(*s, 2, 2) if c in dist]
            if not starts:
                errs.append(f"{kind} spawn {s} can not reach the core")
                continue
            c = min(starts, key=lambda p: dist[p])
            path = [c]
            while dist[c] > 0:
                c = min(((c[0] + dx, c[1] + dy) for dx, dy, _ in steps), key=lambda p: dist.get(p, 1e18))
                path.append(c)
            d0 = dist[path[0]]
            paths.append({"kind": kind, "spawn": s, "cells": round(d0), "sec": round(d0 / SLIME_SPEED), "path": path})
    cc = (L.core[0] + 3, L.core[1] + 3)
    veins = []
    for i, v in enumerate(L.veins):
        sx, sy = Layout.slot(v)
        far = max(math.hypot(x + 0.5 - cc[0], y + 0.5 - cc[1]) for x in (sx, sx + 1) for y in (sy, sy + 1))
        relays = 0 if far <= CORE_R else math.ceil((far - CORE_R) / RELAY_STEP)
        veins.append({"vein": i + 1, "cell": [v[0], v[1]], "side": v[2], "slot_far": round(far, 1), "relays": relays})
    return errs, paths, veins


def render(L, paths, veins, scale=0.25):
    W, H = int(COLS * CW * scale), int(ROWS * CH * scale)
    cw, ch = CW * scale, CH * scale
    im = Image.new("RGB", (W, H + 150), (30, 30, 34))
    d = ImageDraw.Draw(im, "RGBA")
    d.rectangle((0, 0, W, H), fill=(196, 150, 96))
    box = lambda x, y, w, h: (x * cw, y * ch, (x + w) * cw - 1, (y + h) * ch - 1)
    for (c, r) in L.rock:
        d.rectangle(box(c, r, 1, 1), fill=(118, 116, 108))
    for (c, r) in L.wall:
        d.rectangle(box(c, r, 1, 1), fill=(72, 62, 54))
    cx, cy = (L.core[0] + 3) * cw, (L.core[1] + 3) * ch
    d.ellipse((cx - CORE_R * cw, cy - CORE_R * ch, cx + CORE_R * cw, cy + CORE_R * ch), fill=(90, 170, 255, 40), outline=(90, 170, 255, 200), width=2)
    for p in paths:
        col = (230, 40, 40, 150) if p["kind"] == "slime" else (255, 140, 0, 150)
        pts = [((x + 0.5) * cw, (y + 0.5) * ch) for x, y in p["path"]]
        for k in range(0, len(pts) - 1, 2):
            d.line((pts[k], pts[k + 1]), fill=col, width=2)
    for (x, y) in L.relays:
        d.ellipse(((x + 1 - 9) * cw, (y + 1 - 9) * ch, (x + 1 + 9) * cw, (y + 1 + 9) * ch), outline=(90, 170, 255, 120), width=1)
        d.rectangle(box(x, y, 2, 2), fill=(90, 170, 255, 200))
    font = ImageFont.truetype(FONT, 13)
    small = ImageFont.truetype(FONT, 11)
    for v, info in zip(L.veins, veins):
        d.rectangle(box(v[0], v[1], 6, 6), fill=(70, 120, 230), outline=(200, 230, 255))
        sx, sy = Layout.slot(v)
        d.rectangle(box(sx, sy, 2, 2), fill=(250, 210, 60))
        d.text(((v[0] + 0.6) * cw, (v[1] + 1.2) * ch), f"{info['vein']}", fill=(255, 255, 255), font=font)
    d.rectangle(box(*L.core, 6, 6), fill=(40, 200, 255), outline=(255, 255, 255), width=2)
    for (x, y) in L.slime:
        d.rectangle(box(x, y, 2, 2), fill=(230, 40, 40), outline=(255, 255, 255))
    for (x, y) in L.lasher:
        d.rectangle(box(x, y, 2, 2), fill=(255, 140, 0), outline=(255, 255, 255))
    t = ImageFont.truetype(FONT, 18)
    d.text((10, H + 8), f"{L.key}. {L.title}", fill=(255, 255, 255), font=t)
    d.text((10, H + 34), L.idea, fill=(210, 210, 210), font=small)
    sl = [p for p in paths if p["kind"] == "slime"]
    la = [p for p in paths if p["kind"] == "lasher"]
    line1 = "Шлях до ядра: слизні " + ", ".join(f"{p['cells']} кл / {p['sec'] // 60}:{p['sec'] % 60:02d}" for p in sl)
    if la:
        line1 += "; lasher " + ", ".join(f"{p['cells']} кл" for p in la)
    d.text((10, H + 78), line1, fill=(255, 200, 200), font=small)
    d.text((10, H + 98), "Жили (ретрансляторів до бура): " + ", ".join(f"{v['vein']}: {v['relays']}" for v in veins),
           fill=(200, 220, 255), font=small)
    d.text((10, H + 122), "■ ядро + радіус 17   ■ жила + слот бура   ■ слизні   ■ lasher   ■ скеля   ■ стіна-колони   ┄ шлях ворога",
           fill=(160, 160, 160), font=small)
    return im


def layouts():
    out = []

    a = Layout("A", "Ущелина", "База в куті. Скельний хребет відгороджує кут, у ньому 3 проходи; вороги з протилежного кута через відкрите поле.")
    a.perimeter()
    a.core = (12, 74)
    a.line([(2, 40), (30, 42), (52, 52), (70, 66), (84, 94)], t=3)
    a.gap(18, 38, 23, 46)
    a.gap(48, 46, 53, 56)
    a.gap(74, 74, 80, 84)
    a.rect(74, 18, 80, 24)
    a.line([(44, 14), (54, 17)], t=2)
    a.line([(98, 52), (104, 60)], t=2)
    a.rect(30, 70, 33, 73)
    a.vein(18, 80, "R")
    a.vein(6, 58, "R")
    a.vein(38, 60, "R")
    a.vein(28, 28, "R")
    a.vein(62, 32, "L")
    a.vein(96, 76, "L")
    a.slime = [(114, 6), (120, 38)]
    a.lasher = [(88, 4)]
    a.relays = [(26, 62), (34, 54)]
    out.append(a)

    b = Layout("B", "Серце", "База в центрі в кільці скель з 4 воротами; вороги з 4 кутів. Дві жили всередині кільця, решта ззовні між воротами.")
    b.perimeter()
    b.core = (61, 45)
    b.line([(36, 26), (90, 26)], t=2)
    b.line([(36, 69), (90, 69)], t=2)
    b.line([(36, 26), (36, 70)], t=2)
    b.line([(90, 26), (90, 70)], t=2)
    b.gap(61, 26, 66, 27)
    b.gap(61, 69, 66, 70)
    b.gap(36, 45, 37, 50)
    b.gap(90, 45, 91, 50)
    b.line([(16, 18), (26, 26)], t=2)
    b.line([(102, 18), (112, 26)], t=2)
    b.line([(16, 76), (26, 68)], t=2)
    b.line([(102, 76), (112, 68)], t=2)
    b.vein(44, 36, "R")
    b.vein(74, 58, "L")
    b.vein(18, 45, "R")
    b.vein(104, 45, "L")
    b.vein(56, 8, "R")
    b.vein(66, 82, "L")
    b.slime = [(6, 6), (120, 6), (120, 88)]
    b.lasher = [(6, 88)]
    out.append(b)

    c = Layout("C", "Серпантин", "Вороги згори. База внизу праворуч за гребінкою скель: вхід зліва, петля вправо й назад — турелі в кишені б'ють по двох проходах.")
    c.perimeter()
    c.core = (88, 80)
    c.line([(84, 52), (126, 52)], t=2)
    c.gap(86, 52, 92, 53)
    c.line([(84, 52), (84, 94)], t=2)
    c.line([(86, 66), (118, 66)], t=2)
    c.line([(20, 30), (34, 36)], t=2)
    c.line([(46, 20), (52, 30)], t=2)
    c.rect(30, 64, 36, 68)
    c.rect(56, 40, 60, 44)
    c.vein(100, 84, "L")
    c.vein(70, 72, "R")
    c.vein(100, 56, "R")
    c.vein(50, 60, "R")
    c.vein(60, 28, "R")
    c.vein(16, 80, "R")
    c.slime = [(70, 4), (110, 4)]
    c.lasher = [(20, 6)]
    out.append(c)

    d = Layout("D", "Два фронти", "База зліва. Слизні зі сходу через поле з камінням, lasher з півночі через ущелину. Плато зі скель у центрі — дві жили під захистом, один вхід.")
    d.perimeter()
    d.core = (12, 44)
    d.line([(2, 22), (126, 22)], t=2)
    d.gap(58, 22, 64, 23)
    d.line([(70, 38), (96, 38)], t=2)
    d.line([(70, 64), (96, 64)], t=2)
    d.line([(96, 38), (96, 65)], t=2)
    d.line([(70, 38), (70, 46)], t=2)
    d.line([(70, 56), (70, 65)], t=2)
    d.rect(104, 30, 108, 33)
    d.rect(110, 54, 114, 58)
    d.rect(40, 74, 46, 77)
    d.rect(52, 30, 54, 36)
    d.vein(22, 50, "R")
    d.vein(8, 30, "R")
    d.vein(78, 44, "R")
    d.vein(80, 54, "L")
    d.vein(44, 82, "R")
    d.vein(34, 30, "R")
    d.slime = [(120, 40), (120, 70)]
    d.lasher = [(60, 6)]
    d.relays = [(30, 40), (44, 46), (58, 48)]
    out.append(d)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-o", "--out", default=".", help="output folder (default: current)")
    a = ap.parse_args()
    if not os.path.isdir(a.out):
        print(f"no such folder: {a.out}", file=sys.stderr)
        return 2
    bad = 0
    ims, data = [], {}
    for L in layouts():
        errs, paths, veins = check(L)
        for e in errs:
            print(f"{L.key}: ERROR {e}")
        bad += len(errs)
        print(f"{L.key} {L.title}: " + "; ".join(f"{p['kind']} {p['spawn']} {p['cells']} cells {p['sec']} s" for p in paths))
        print("   veins: " + ", ".join(f"{v['vein']} far {v['slot_far']} relays {v['relays']}" for v in veins))
        im = render(L, paths, veins)
        im.save(os.path.join(a.out, f"concept_{L.key}.png"))
        ims.append(im)
        data[L.key] = {"title": L.title, "idea": L.idea, "size": [COLS, ROWS], "wall": sorted(L.wall), "rock": sorted(L.rock),
                       "core": L.core, "veins": L.veins, "slime": L.slime, "lasher": L.lasher, "relays": L.relays,
                       "paths": [{k: v for k, v in p.items() if k != "path"} for p in paths], "vein_checks": veins}
    w, h = ims[0].size
    sheet = Image.new("RGB", (w * 2 + 10, h * 2 + 10), (20, 20, 22))
    for i, im in enumerate(ims):
        sheet.paste(im, ((i % 2) * (w + 10), (i // 2) * (h + 10)))
    sheet.save(os.path.join(a.out, "concepts_sheet.png"))
    with open(os.path.join(a.out, "concepts.json"), "w") as f:
        json.dump(data, f)
        f.write("\n")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
