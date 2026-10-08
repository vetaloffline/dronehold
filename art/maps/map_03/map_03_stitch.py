"""Stitch detailed tiles into one seamless map.

1. Each tile is resized back to its crop size.
2. Tone lock: keep the tile's fine detail, take the low frequencies (colour, light) from the shared base,
   so every tile has identical tone -> no tonal seams.
3. Blend overlaps with a wide feather; inside the overlap the cut follows a minimum-difference path
   (dynamic programming), feathered around it, so cliffs and trees are not doubled.

usage: python3 -I map_03_stitch.py <work_dir> [tile names to use, default all present]

Kept as the recipe for the next maps. Its inputs were intermediate and are not in git: base_up.png (the first
whole-map pass from Codex, upscaled), <tile>_detail.png (each tile re-detailed by Codex); the crop boxes are in
map_03_tiles.json (copy it to <work_dir>/tiles.json). Output: <work_dir>/ground.png.
"""
import json
import sys

import numpy as np
from PIL import Image, ImageFilter

D = sys.argv[1]
tiles = json.load(open(f"{D}/tiles.json"))
base = Image.open(f"{D}/base_up.png").convert("RGB")
FW, FH = base.size
LOW = 24          # blur radius that separates "tone" from "detail"
FEATHER = 60      # half-width of the soft band around the cut, px


def align(im, base_crop, w, h):
    """Find scale + shift that best lays the generated tile over its base crop (on blurred, downsampled images)."""
    k = 8
    small_b = blur(base_crop, 6)[::k, ::k]
    best = None
    for sc in (0.96, 0.98, 1.0, 1.02, 1.04):
        tw, th = int(round(w * sc)), int(round(h * sc))
        t = np.asarray(im.resize((tw, th), Image.LANCZOS), dtype=np.float32)
        tb = blur(t, 6)
        for dy in range(-48, 49, 8):
            for dx in range(-48, 49, 8):
                # the tile pixel (u, v) lands on crop pixel (u + ox, v + oy)
                ox, oy = (w - tw) // 2 + dx, (h - th) // 2 + dy
                canvas = np.full((h, w, 3), np.nan, dtype=np.float32)
                y0, x0 = max(0, oy), max(0, ox)
                y1, x1 = min(h, oy + th), min(w, ox + tw)
                canvas[y0:y1, x0:x1] = tb[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
                c = canvas[::k, ::k]
                m = ~np.isnan(c[..., 0])
                if m.mean() < 0.85:
                    continue
                err = np.abs(c[m] - small_b[m]).mean()
                if best is None or err < best[0]:
                    best = (err, sc, ox, oy, t)
    err, sc, ox, oy, t = best
    out = base_crop.copy()                       # gaps (if any) filled from the base
    th, tw = t.shape[:2]
    y0, x0 = max(0, oy), max(0, ox)
    y1, x1 = min(h, oy + th), min(w, ox + tw)
    out[y0:y1, x0:x1] = t[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
    print(f"  align: scale {sc}, shift ({ox - (w - tw) // 2}, {oy - (h - th) // 2}), err {err:.1f}")
    return out


def blur(a, r):
    return np.asarray(Image.fromarray(a.clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r)), dtype=np.float32)


def tone_lock(tile, base_crop):
    t = tile.astype(np.float32)
    return t - blur(t, LOW) + blur(base_crop.astype(np.float32), LOW)


def min_cut_vertical(diff):
    """Cheapest top-to-bottom path through diff (h x w). Returns x per row."""
    h, w = diff.shape
    cost = diff.copy()
    for y in range(1, h):
        prev = cost[y - 1]
        left = np.r_[np.inf, prev[:-1]]
        right = np.r_[prev[1:], np.inf]
        cost[y] += np.minimum(np.minimum(left, prev), right)
    path = np.zeros(h, dtype=int)
    path[-1] = int(np.argmin(cost[-1]))
    for y in range(h - 2, -1, -1):
        x = path[y + 1]
        lo, hi = max(0, x - 1), min(w, x + 2)
        path[y] = lo + int(np.argmin(cost[y, lo:hi]))
    return path


def seam_weight(diff, vertical):
    """Weight 0..1 for the NEW tile inside the overlap: 0 before the cut, 1 after, soft around it."""
    d = diff if vertical else diff.T
    path = min_cut_vertical(d)
    h, w = d.shape
    xs = np.arange(w)[None, :]
    wgt = np.clip((xs - path[:, None]) / (2 * FEATHER) + 0.5, 0, 1)
    return wgt if vertical else wgt.T


acc = np.asarray(base, dtype=np.float32).copy()
have = np.zeros((FH, FW), dtype=bool)
used = []
for t in tiles:
    try:
        im = Image.open(f"{D}/{t['name']}_detail.png").convert("RGB")
    except FileNotFoundError:
        continue
    x, y, w, h = t["x"], t["y"], t["w"], t["h"]
    im = align(im, np.asarray(base, dtype=np.float32)[y:y + h, x:x + w], w, h)
    im = tone_lock(im, acc[y:y + h, x:x + w] * 0 + np.asarray(base, dtype=np.float32)[y:y + h, x:x + w])
    region = acc[y:y + h, x:x + w]
    old = have[y:y + h, x:x + w]
    wgt = np.ones((h, w), dtype=np.float32)
    if old.any():
        diff = np.abs(region - im).sum(axis=2)
        cols = old.any(axis=0)
        rows = old.any(axis=1)
        # overlap with the tile on the left: vertical cut over the overlapping columns
        if cols[0] and not cols.all():
            ox = int(np.argmin(cols)) if not cols.all() else w
            sub = diff[:, :ox]
            wv = np.ones((h, w), dtype=np.float32)
            wv[:, :ox] = seam_weight(sub, vertical=True)
            wgt = np.minimum(wgt, wv)
        # overlap with the tile above: horizontal cut over the overlapping rows
        if rows[0] and not rows.all():
            oy = int(np.argmin(rows))
            sub = diff[:oy, :]
            wh = np.ones((h, w), dtype=np.float32)
            wh[:oy, :] = seam_weight(sub, vertical=False)
            wgt = np.minimum(wgt, wh) if (cols[0] and not cols.all()) else wh
        wgt = np.where(old, wgt, 1.0)
    acc[y:y + h, x:x + w] = region * (1 - wgt[..., None]) + im * wgt[..., None]
    have[y:y + h, x:x + w] = True
    used.append(t["name"])

out = Image.fromarray(acc.clip(0, 255).astype(np.uint8))
out.save(f"{D}/ground.png")
print("stitched", used, out.size)
