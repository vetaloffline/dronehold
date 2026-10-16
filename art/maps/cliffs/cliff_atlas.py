#!/usr/bin/env python3
"""Pack the cut cliff blocks (wall columns + natural rock) into one atlas for the game, and write the
CliffBlocks resource that points into it.

One atlas = one texture for every cliff on the map, so the 2D renderer can batch them (phone). Blocks are
packed in shelves (tallest first) with --pad px of transparent gap so mipmaps do not bleed.
Input: the folders/JSONs written by cliff_sheet_cut.py. Group = wall for the --wall JSON, rock for --rock.
Kinds: low 0, mid 1, tall 2, peak 3 (wall blocks are tall).

Writes:
  <atlas>                      PNG atlas (default art/maps/cliffs/cliff_atlas.png)
  <res>                        game/core/cliff_blocks.tres (CliffBlocks: atlas, rects, grounds, tops,
                               texels, groups, kinds) — overwritten, it holds no hand-tuned values
Top of a block (where decor stands): per column of the middle --top-span of its width, the first row with
alpha > 128; the median of those rows (block px). A narrow spire on a peak does not lift it.
Exit 0 ok, 2 bad args.

Example:
  python3 cliff_sheet_cut.py cliff_wall_sheet.png -t cliff_blocks_template.json -o $TMPDIR/cut -p cliff_wall
  python3 cliff_sheet_cut.py cliff_rock_sheet.png -t rock_blocks_template.json -o $TMPDIR/cut -p cliff_rock
  python3 cliff_atlas.py --wall $TMPDIR/cut/cliff_wall.json --rock $TMPDIR/cut/cliff_rock.json
"""
import argparse
import json
import os
import sys

from PIL import Image

KINDS = {"low": 0, "mid": 1, "tall": 2, "peak": 3, "wall": 2}
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wall", required=True, help="cliff_wall.json from cliff_sheet_cut.py")
    ap.add_argument("--rock", required=True, help="cliff_rock.json from cliff_sheet_cut.py")
    ap.add_argument("--atlas", default=os.path.join(HERE, "cliff_atlas.png"), help="atlas PNG (default: next to this script)")
    ap.add_argument("--res", default=os.path.join(ROOT, "game", "core", "cliff_blocks.tres"),
                    help="CliffBlocks .tres (default game/core/cliff_blocks.tres)")
    ap.add_argument("--width", type=int, default=2048, help="atlas width, px (default 2048)")
    ap.add_argument("--top-span", type=float, default=0.6, help="middle share of the width measured for the top (default 0.6)")
    ap.add_argument("--pad", type=int, default=8, help="gap between blocks, px (default 8)")
    a = ap.parse_args()
    blocks = []
    for group, path in ((0, a.wall), (1, a.rock)):
        if not os.path.isfile(path):
            print(f"no such file: {path}", file=sys.stderr)
            return 2
        meta = json.load(open(path))
        for b in meta["blocks"]:
            im = Image.open(os.path.join(os.path.dirname(path), b["file"])).convert("RGBA")
            a_ = im.getchannel("A")
            w, h = im.size
            tops_ = []
            for x in range(int(w * (1 - a.top_span) / 2), int(w * (1 + a.top_span) / 2)):
                col = [a_.getpixel((x, y)) for y in range(h)]
                y = next((y for y, v in enumerate(col) if v > 128), None)
                if y is not None:
                    tops_.append(y)
            tops_.sort()
            blocks.append({"im": im, "ground": b["ground"], "texels": meta["texels_per_map_px"],
                           "top": tops_[len(tops_) // 2] if tops_ else 0,
                           "group": group, "kind": KINDS[b["kind"]]})
    order = sorted(range(len(blocks)), key=lambda i: -blocks[i]["im"].height)
    x, y, shelf = a.pad, a.pad, 0
    for i in order:
        w, h = blocks[i]["im"].size
        if x + w + a.pad > a.width:
            x, y, shelf = a.pad, y + shelf + a.pad, 0
        blocks[i]["rect"] = (x, y, w, h)
        x += w + a.pad
        shelf = max(shelf, h)
    height = y + shelf + a.pad
    atlas = Image.new("RGBA", (a.width, height), (0, 0, 0, 0))
    for b in blocks:
        atlas.paste(b["im"], b["rect"][:2])
    atlas.save(a.atlas)
    res_atlas = "res://" + os.path.relpath(os.path.abspath(a.atlas), ROOT)
    rects = ", ".join("Rect2(%d, %d, %d, %d)" % b["rect"] for b in blocks)
    grounds = ", ".join("%g, %g" % tuple(b["ground"]) for b in blocks)
    texels = ", ".join("%g" % b["texels"] for b in blocks)
    tops = ", ".join("%g" % b["top"] for b in blocks)
    groups = ", ".join(str(b["group"]) for b in blocks)
    kinds = ", ".join(str(b["kind"]) for b in blocks)
    with open(a.res, "w") as f:
        f.write('[gd_resource type="Resource" script_class="CliffBlocks" load_steps=3 format=3]\n\n')
        f.write('[ext_resource type="Script" path="res://game/core/cliff_blocks.gd" id="1_script"]\n')
        f.write('[ext_resource type="Texture2D" path="%s" id="2_atlas"]\n\n' % res_atlas)
        f.write('[resource]\nscript = ExtResource("1_script")\natlas = ExtResource("2_atlas")\n')
        f.write("rects = Array[Rect2]([%s])\n" % rects)
        f.write("grounds = PackedVector2Array(%s)\n" % grounds)
        f.write("tops = PackedFloat32Array(%s)\n" % tops)
        f.write("texels = PackedFloat32Array(%s)\n" % texels)
        f.write("groups = PackedByteArray(%s)\n" % groups)
        f.write("kinds = PackedByteArray(%s)\n" % kinds)
    print(f"atlas {a.width}x{height}, {len(blocks)} blocks -> {a.atlas}, {a.res}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
