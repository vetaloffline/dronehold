"""Light machine gun base for the game: the same scale as the heads, cast shadow as its own layer.

Input: light_mg_base_codex.png (approved Codex base, shadow baked in). Output:
- light_mg_base.png        — the pedestal without the ground shadow;
- light_mg_base_shadow.png — the shadow alone (filled solid under the pedestal), same canvas;
- light_mg_base.json       — ring (collar top centre = where the head's housing goes) and ring_h
                             (px from the ring down to the ground point) for light_mg_rig.tres.

Scale: template px per head px (light_mg_template.SCALE) x head px per base px (BASE_PER_HEAD), so the
base and the heads (light_mg_place.py) are in one pixel space and head_scale = 1 in the rig.
Shadow pixels: alpha < 215 and r+g+b < 200 (.claude/skills/art/references/light-and-shadows.md).
Ground point: centre of the feet ellipse = bottom of the front foot - half the feet width x K.

    python3 light_mg_base_export.py
"""
import importlib.util
import json
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tpl", os.path.join(HERE, "light_mg_template.py"))
T = importlib.util.module_from_spec(spec)
spec.loader.exec_module(T)

PAD = 8


def main():
    src = Image.open(T.BASE).convert("RGBA")
    a = np.asarray(src).astype(int)
    alpha, rgb = a[..., 3], a[..., :3].sum(axis=2)
    shadow = (alpha > 0) & (alpha < 215) & (rgb < 200)
    obj = (alpha > 0) & ~shadow

    # ground point and ring in source px
    ys, xs = np.nonzero(obj)
    feet_rx = (xs.max() - xs.min()) / 2.0
    ground_y = ys.max() - feet_rx * T.K
    ring_src = np.array(T.BASE_HOUSING)

    # layers in source px
    base_l = a.copy()
    base_l[~obj] = 0
    sh = a.copy()
    sh[~shadow] = 0
    col = np.median(a[shadow][:, :3], axis=0)
    fill_a = np.percentile(alpha[shadow], 90)
    under = obj & ~shadow
    sh[under, :3] = col
    sh[under, 3] = fill_a

    s = T.SCALE * T.BASE_PER_HEAD
    size = (round(src.width * s), round(src.height * s))
    base_i = Image.fromarray(base_l.astype(np.uint8)).resize(size, Image.LANCZOS)
    sh_i = Image.fromarray(sh.astype(np.uint8)).resize(size, Image.LANCZOS)
    m = (np.asarray(base_i)[..., 3] > 0) | (np.asarray(sh_i)[..., 3] > 0)
    ys, xs = np.nonzero(m)
    box = (int(max(0, xs.min() - PAD)), int(max(0, ys.min() - PAD)),
           int(min(size[0], xs.max() + PAD + 1)), int(min(size[1], ys.max() + PAD + 1)))
    base_i.crop(box).save(os.path.join(HERE, "light_mg_base.png"))
    sh_i.crop(box).save(os.path.join(HERE, "light_mg_base_shadow.png"))

    ring = ring_src * s - np.array(box[:2])
    ring_h = (ground_y - ring_src[1]) * s
    meta = dict(scale=round(s, 4), size=[box[2] - box[0], box[3] - box[1]],
                ring=[round(float(ring[0]), 1), round(float(ring[1]), 1)], ring_h=round(float(ring_h), 1),
                ground=[round(float(ring[0]), 1), round(float(ring[1] + ring_h), 1)],
                feet_width=round(float(feet_rx * 2 * s), 1))
    json.dump(meta, open(os.path.join(HERE, "light_mg_base.json"), "w"), indent=1)
    print(meta)


if __name__ == "__main__":
    main()
