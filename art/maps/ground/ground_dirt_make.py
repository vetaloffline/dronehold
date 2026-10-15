"""Make a seamless ground tile from a Codex draft: min-cut wrap seams, colour matched to the current map ground.

Seams: the draft is cut to (W - band) x (H - band). The wrapped edge is rebuilt from the cut-off band: on the
seam the band of the far edge (continuous with the opposite side) changes into the near edge along the path
of least colour difference (dynamic programming), feathered by --feather px. Columns first, then rows.
Colour: per-channel mean / std of the tile matched to the reference crops (detail kept, tone and saturation
taken from the map), then the result resized to --size.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageFilter


def min_cut_path(diff):
    """diff: (rows, band) -> column index per row of the cheapest top-to-bottom path."""
    rows, band = diff.shape
    cost = diff.copy()
    for y in range(1, rows):
        prev = cost[y - 1]
        left = np.r_[np.inf, prev[:-1]]
        right = np.r_[prev[1:], np.inf]
        cost[y] += np.minimum(prev, np.minimum(left, right))
    path = np.zeros(rows, int)
    path[-1] = int(np.argmin(cost[-1]))
    for y in range(rows - 2, -1, -1):
        x = path[y + 1]
        lo, hi = max(0, x - 1), min(band, x + 2)
        path[y] = lo + int(np.argmin(cost[y, lo:hi]))
    return path


def wrap_columns(a, band, feather):
    """Make left/right edges continuous. a: (H, W, 3) float. Returns (H, W - band, 3)."""
    w = a.shape[1] - band
    far = a[:, w:]          # continues column w-1 (right side of the output)
    near = a[:, :band]      # continues column band (inside of the output)
    diff = np.abs(far - near).sum(2)
    # keep the cut away from the band ends so both sides blend in
    margin = feather + 2
    diff[:, :margin] += 1e6
    diff[:, -margin:] += 1e6
    path = min_cut_path(diff)
    xs = np.arange(band)[None, :]
    t = np.clip((xs - path[:, None] + feather / 2) / max(feather, 1), 0, 1)[..., None]
    out = a[:, :w].copy()
    out[:, :band] = far * (1 - t) + near * t
    return out


def match_colour(a, ref):
    m, s = a.reshape(-1, 3).mean(0), a.reshape(-1, 3).std(0)
    rm, rs = ref.reshape(-1, 3).mean(0), ref.reshape(-1, 3).std(0)
    return (a - m) / s * rs + rm


def main():
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Example: python3 ground_dirt_make.py ground_dirt_raw.png -r ground_dirt_ref_1.png ground_dirt_ref_2.png "
               "-o ground_dirt.png\nWrites the tile and <out>_3x3.png (tiled preview). Exit 0 ok, 2 bad args.",
    )
    p.add_argument("raw", help="Codex draft PNG (square)")
    p.add_argument("-r", "--refs", nargs="*", default=[],
                   help="crops of the current ground for colour matching; none = keep draft colours")
    p.add_argument("-o", "--out", required=True, help="output tile PNG")
    p.add_argument("--band", type=int, default=160, help="seam band in draft px (default 160)")
    p.add_argument("--feather", type=int, default=12, help="soft width of the seam cut in px (default 12)")
    p.add_argument("--size", type=int, default=1024, help="output tile side in px (default 1024)")
    p.add_argument("--sharpen", type=int, default=0,
                   help="unsharp-mask percent after resize, 0 = off (default 0)")
    args = p.parse_args()

    a = np.asarray(Image.open(args.raw).convert("RGB")).astype(np.float64)
    if min(a.shape[:2]) <= 2 * args.band:
        print("band too wide for this image", file=sys.stderr)
        sys.exit(2)
    if args.refs:
        ref = np.concatenate([np.asarray(Image.open(f).convert("RGB")).astype(np.float64).reshape(-1, 3)
                              for f in args.refs])
        a = match_colour(a, ref)
    a = wrap_columns(a, args.band, args.feather)
    a = wrap_columns(a.transpose(1, 0, 2), args.band, args.feather).transpose(1, 0, 2)
    im = Image.fromarray(np.clip(a, 0, 255).round().astype(np.uint8))
    im = im.resize((args.size, args.size), Image.LANCZOS)
    if args.sharpen:
        im = im.filter(ImageFilter.UnsharpMask(radius=1.2, percent=args.sharpen, threshold=2))
    im.save(args.out)

    s = args.size
    sheet = Image.new("RGB", (3 * s, 3 * s))
    for i in range(3):
        for j in range(3):
            sheet.paste(im, (j * s, i * s))
    root, _ = os.path.splitext(args.out)
    sheet.save(root + "_3x3.png")
    print(args.out, im.size, "->", root + "_3x3.png")


if __name__ == "__main__":
    main()
