"""Trim pit sprites from Codex (1536x1024 with mostly empty canvas) to their visible pixels plus a margin.

For each <name>_raw.png next to this script (or the files given) writes <name>.png: the crop to the box of
pixels with alpha > --alpha, widened by --margin px on every side (clamped to the canvas). Prints the crop box
and the size. Exit 0 ok, 1 a file has no visible pixels.
"""
import argparse
import glob
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
                                epilog="Example: python3 pits_trim.py            (all *_raw.png here)\n"
                                       "         python3 pits_trim.py pit_oval_raw.png --margin 12")
    p.add_argument("files", nargs="*", help="raw PNGs named <name>_raw.png (default: all *_raw.png next to the script)")
    p.add_argument("--margin", type=int, default=8, help="empty px kept around the sprite (default 8)")
    p.add_argument("--alpha", type=int, default=8, help="alpha above this counts as visible (default 8)")
    a = p.parse_args()

    files = a.files or sorted(glob.glob(os.path.join(HERE, "*_raw.png")))
    bad = 0
    for f in files:
        im = Image.open(f).convert("RGBA")
        box = im.getchannel("A").point(lambda v: 255 if v > a.alpha else 0).getbbox()
        if box is None:
            print(f, "no visible pixels", file=sys.stderr)
            bad = 1
            continue
        m = a.margin
        box = (max(0, box[0] - m), max(0, box[1] - m), min(im.width, box[2] + m), min(im.height, box[3] + m))
        out = f[: -len("_raw.png")] + ".png"
        im.crop(box).save(out)
        print(os.path.basename(out), "box", box, "size", (box[2] - box[0], box[3] - box[1]))
    sys.exit(bad)


if __name__ == "__main__":
    main()
