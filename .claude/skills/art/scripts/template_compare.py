#!/usr/bin/env python3
"""Measure a Codex result against the pose template it was generated from.

    python3 template_compare.py <template.png> <result.png> [--out <dir>]

Both images are turned into silhouettes (alpha, or "differs from the corner colour" when the
image has no transparency). Prints bbox, centre, size ratio, main-axis angle of each silhouette
and IoU after aligning centres and scale; writes <result>_vs_template.png (template outline in
red over the result). The main-axis angle is a rough check of the overall turn. For an exact
angle (barrel, nose, arm) measure the part itself with a per-asset script, like
art/objects/buildings/turret_views_fit.py.
"""
import argparse
import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter


def silhouette(path):
    im = Image.open(path).convert("RGBA")
    a = np.asarray(im).astype(np.int32)
    alpha = a[..., 3]
    if (alpha < 250).mean() > 0.05:
        mask = alpha > 128
    else:
        corner = a[0, 0, :3]
        mask = np.abs(a[..., :3] - corner).sum(axis=2) > 60
    return im, mask


def stats(mask):
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return None
    cx, cy = xs.mean(), ys.mean()
    cov = np.cov(np.vstack([xs - cx, ys - cy]))
    vals, vecs = np.linalg.eigh(cov)
    vx, vy = vecs[:, np.argmax(vals)]
    # screen angle, 0 = right, 90 = down (towards the camera), folded to 0..180 (an axis has no head)
    ang = math.degrees(math.atan2(vy, vx)) % 180.0
    elong = math.sqrt(vals.max() / max(vals.min(), 1e-9))
    return {"bbox": (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())), "c": (cx, cy),
            "w": int(xs.max() - xs.min() + 1), "h": int(ys.max() - ys.min() + 1),
            "area": len(xs), "angle": ang, "elong": elong}


def aligned_iou(tm, rm, ts, rs):
    scale = math.sqrt(rs["area"] / ts["area"])
    h, w = rm.shape
    th, tw = tm.shape
    small = Image.fromarray(tm.astype(np.uint8) * 255)
    big = small.resize((max(1, round(tw * scale)), max(1, round(th * scale))), Image.BILINEAR)
    ox = round(rs["c"][0] - ts["c"][0] * scale)
    oy = round(rs["c"][1] - ts["c"][1] * scale)
    canvas = Image.new("L", (w, h), 0)
    canvas.paste(big, (ox, oy))
    moved = np.asarray(canvas) > 127
    inter = (moved & rm).sum()
    union = (moved | rm).sum()
    return inter / union if union else 0.0, moved, scale


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="example:\n  python3 .claude/skills/art/scripts/template_compare.py "
               "art/drafts/<session id>/units/drone/drone_template.png "
               "art/drafts/<session id>/units/drone/drone_views_v1.png\n"
               "  -> prints both silhouettes' numbers and IoU, writes drone_views_v1_vs_template.png")
    ap.add_argument("template", help="pose template PNG the result was generated from (Image 1 given to Codex)")
    ap.add_argument("result", help="generated PNG to measure")
    ap.add_argument("--out", default=None, help="folder for <result>_vs_template.png (default: next to the result)")
    a = ap.parse_args()

    _, tm = silhouette(a.template)
    rim, rm = silhouette(a.result)
    ts, rs = stats(tm), stats(rm)
    if not ts or not rs:
        print("FAIL: empty silhouette in " + ("template" if not ts else "result"))
        return 1
    for name, s in (("template", ts), ("result", rs)):
        print(f"{name}: bbox {s['bbox']}, size {s['w']}x{s['h']}, centre ({s['c'][0]:.0f}, {s['c'][1]:.0f}), "
              f"main axis {s['angle']:.1f}° (elongation {s['elong']:.2f})")
    d = (rs["angle"] - ts["angle"] + 90) % 180 - 90
    iou, moved, scale = aligned_iou(tm, rm, ts, rs)
    print(f"main-axis difference: {d:+.1f}°"
          + ("  (silhouettes are nearly round — the axis angle means little)"
             if min(ts["elong"], rs["elong"]) < 1.15 else ""))
    print(f"scale result/template: {scale:.3f}; centre shift (result - template): "
          f"({rs['c'][0] - ts['c'][0]:+.0f}, {rs['c'][1] - ts['c'][1]:+.0f}) px")
    print(f"IoU after aligning centre and scale: {iou:.2f}")

    out_dir = a.out or os.path.dirname(os.path.abspath(a.result))
    os.makedirs(out_dir, exist_ok=True)
    base = Image.new("RGBA", rim.size, (232, 232, 232, 255))
    view = Image.alpha_composite(base, rim)
    edge = np.asarray(Image.fromarray(moved.astype(np.uint8) * 255)
                      .filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(3))) > 0
    arr = np.asarray(view).copy()
    arr[edge] = (230, 30, 30, 255)
    out = os.path.join(out_dir, os.path.splitext(os.path.basename(a.result))[0] + "_vs_template.png")
    Image.fromarray(arr).save(out)
    print(f"overlay: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
