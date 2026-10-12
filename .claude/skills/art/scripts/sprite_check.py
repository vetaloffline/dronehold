#!/usr/bin/env python3
"""Self-check of a generated sprite before showing it to the user.

    python3 sprite_check.py <sprite.png> [--out <dir>] [--margin 4]

Prints facts (size, alpha, bbox, margins, white background, dark halo) and writes
<name>_check.png: the sprite on a light, a game-ground and a checker background, side by side,
plus a 2x crop of the edge. Read shows alpha as black, so look at this preview, not the raw PNG.
Exit code 1 if a hard check failed (no real alpha, opaque background, touches the frame).
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

LIGHT = (232, 232, 232)
GROUND = (58, 42, 74)  # infected violet ground of the game


def composite(im, bg):
    base = Image.new("RGBA", im.size, bg + (255,))
    return Image.alpha_composite(base, im).convert("RGB")


def checker(size, cell=16):
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w]
    tile = ((xx // cell + yy // cell) % 2).astype(np.uint8)
    arr = np.where(tile[..., None] == 1, 200, 150).astype(np.uint8).repeat(3, axis=2)
    return Image.fromarray(arr, "RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sprite")
    ap.add_argument("--out", default=None, help="folder for the preview (default: next to sprite)")
    ap.add_argument("--margin", type=int, default=4, help="min transparent gap to the frame, px")
    a = ap.parse_args()

    im = Image.open(a.sprite)
    print(f"file: {a.sprite}")
    print(f"size: {im.size[0]}x{im.size[1]}  mode: {im.mode}")
    im = im.convert("RGBA")
    rgba = np.asarray(im).astype(np.int32)
    alpha = rgba[..., 3]
    h, w = alpha.shape
    fails = []

    opaque = alpha > 0
    share_transparent = 1.0 - opaque.mean()
    print(f"transparent pixels: {share_transparent:.1%}")
    if share_transparent < 0.05:
        fails.append("no real transparency (background is opaque)")

    corners = [rgba[0, 0], rgba[0, -1], rgba[-1, 0], rgba[-1, -1]]
    opaque_corners = sum(1 for c in corners if c[3] > 0)
    white_corners = sum(1 for c in corners if c[3] > 0 and min(c[:3]) > 235)
    if opaque_corners:
        print(f"opaque corners: {opaque_corners}/4 (white: {white_corners})")
        fails.append("background in the corners is not transparent"
                     + (" — looks like a white background, cut it out" if white_corners >= 3 else ""))

    if opaque.any():
        ys, xs = np.nonzero(opaque)
        x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
        margins = {"left": x0, "top": y0, "right": w - 1 - x1, "bottom": h - 1 - y1}
        print(f"bbox: x {x0}..{x1}, y {y0}..{y1}  ({x1 - x0 + 1}x{y1 - y0 + 1})")
        print("margins: " + ", ".join(f"{k} {v}" for k, v in margins.items()))
        cut = [k for k, v in margins.items() if v < a.margin]
        if cut:
            fails.append(f"touches the frame / margin < {a.margin}px: {', '.join(cut)}")

        # dark halo: semi-transparent, dark pixels right at the silhouette edge
        semi = (alpha > 0) & (alpha < 200)
        lum = (rgba[..., 0] * 299 + rgba[..., 1] * 587 + rgba[..., 2] * 114) // 1000
        dark_semi = semi & (lum < 45)
        edge_count = int(semi.sum())
        dark_share = dark_semi.sum() / edge_count if edge_count else 0.0
        print(f"semi-transparent edge pixels: {edge_count}, dark among them: {dark_share:.1%}")
        if dark_share > 0.5 and edge_count > 200:
            print("WARN: many dark semi-transparent pixels — dark halo or a soft shadow baked in; "
                  "check the light preview")
    else:
        fails.append("image is fully transparent")
        x0 = y0 = 0
        x1, y1 = w - 1, h - 1

    out_dir = a.out or os.path.dirname(os.path.abspath(a.sprite))
    os.makedirs(out_dir, exist_ok=True)
    name = os.path.splitext(os.path.basename(a.sprite))[0]
    panels = [composite(im, LIGHT), composite(im, GROUND),
              Image.alpha_composite(checker(im.size).convert("RGBA"), im).convert("RGB")]
    scale = min(1.0, 700 / max(w, h))
    panels = [p.resize((int(w * scale), int(h * scale)), Image.LANCZOS) for p in panels]
    # 2x crop around the right edge of the bbox (lit side): crispness and halo are visible there
    cw = min(200, x1 - x0 + 1)
    ch = min(200, y1 - y0 + 1)
    cy = (y0 + y1) // 2
    crop_box = (max(0, x1 - cw + 20), max(0, cy - ch // 2),
                min(w, x1 + 20), min(h, cy + ch // 2))
    crop = composite(im, LIGHT).crop(crop_box)
    crop = crop.resize((crop.width * 2, crop.height * 2), Image.NEAREST)
    total_w = sum(p.width for p in panels) + crop.width + 10 * 4
    total_h = max(max(p.height for p in panels), crop.height) + 20
    sheet = Image.new("RGB", (total_w, total_h), (255, 255, 255))
    x = 10
    for p in panels + [crop]:
        sheet.paste(p, (x, 10))
        x += p.width + 10
    out = os.path.join(out_dir, f"{name}_check.png")
    sheet.save(out)
    print(f"preview: {out}")

    if fails:
        print("FAIL: " + "; ".join(fails))
        return 1
    print("OK: hard checks passed (style, light, crispness — check by eye on the preview)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
