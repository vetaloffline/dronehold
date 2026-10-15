"""Template for a pit with a simple outline (pit_round, pit_square), seen by the game camera (squash 0.75).

Run: python3 pits_template.py [--shape round|square] [--name pit_round] [--w 300] [--scale 3]
Writes <name>_template.png (1536x1024, grey blocks on white: rim ring, dark hole, far wall band) and
<name>_template.json (centre and half sizes in template px) next to this script. Exit 0.
"""
import argparse
import json
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SQUASH = 0.75


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
                                epilog="Example: python3 pits_template.py --shape square --name pit_square")
    p.add_argument("--shape", choices=["round", "square"], default="round", help="hole outline (default round)")
    p.add_argument("--name", default="pit_round", help="output name prefix (default pit_round)")
    p.add_argument("--w", type=float, default=300.0, help="hole width in map px (default 300)")
    p.add_argument("--scale", type=float, default=3.0, help="template px per map px (default 3)")
    a = p.parse_args()

    W, H = 1536, 1024
    cx, cy = W / 2, H / 2
    rx = a.w * a.scale / 2
    ry = rx * SQUASH
    rim = 18 * a.scale  # stone ring around the hole, map px 18
    im = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(im)
    def shape(dr, box, fill):
        if a.shape == "round":
            dr.ellipse(box, fill=fill)
        else:  # square on the ground: a rectangle w x 0.75 w on screen, slightly rounded corners
            dr.rounded_rectangle(box, radius=10 * a.scale, fill=fill)

    shape(d, (cx - rx - rim, cy - ry - rim * SQUASH, cx + rx + rim, cy + ry + rim * SQUASH), (170, 170, 170))
    # far wall: the inner side of the far half is visible to the camera = hole minus the hole moved down
    wall = 0.45 * ry
    hole = Image.new("L", (W, H), 0)
    shape(ImageDraw.Draw(hole), (cx - rx, cy - ry, cx + rx, cy + ry), 255)
    deep = Image.new("L", (W, H), 0)
    shape(ImageDraw.Draw(deep), (cx - rx, cy - ry + wall, cx + rx, cy + ry + wall), 255)
    im.paste((105, 105, 110), mask=hole)
    im.paste((40, 40, 45), mask=Image.composite(deep, Image.new("L", (W, H), 0), hole))
    im.save(os.path.join(HERE, a.name + "_template.png"))
    json.dump({"shape": a.shape, "centre": [cx, cy], "rx": rx, "ry": ry, "rim": rim, "map_px_per_template_px": 1 / a.scale},
              open(os.path.join(HERE, a.name + "_template.json"), "w"), indent=1)
    print(a.name + "_template.png", (W, H), "hole", round(2 * rx), "x", round(2 * ry))


if __name__ == "__main__":
    main()
