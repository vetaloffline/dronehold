"""Split the approved relay sprite into base / base shadow / dish (0 deg view).

In: relay_v1_clean.png (approved 2026-10-12), relay_base_nodish_raw_v1.png (Codex precise edit of it
with the dish, neck and turntable removed and the collar cap drawn; same canvas, measured shift 0,0).
Out (next to this script, or to argv[1]):
  relay_base.png         base + mast; the collar top where the dish was is taken from the edit
  relay_base_shadow.png  the ground shadow (semi-transparent dark pixels away from the body),
                         filled solid under the body so it can be shifted
  relay_dish_000.png     the dish part (turntable + neck + dish + emitter), same canvas
  relay_cut.json         boxes, housing point (centre of the collar cap plate), counts
Shadow rule (skill art/references/light-and-shadows.md): alpha < 215 and r+g+b < 200.
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else HERE
orig = np.array(Image.open(os.path.join(HERE, "relay_v1_clean.png")).convert("RGBA")).astype(np.float32)
edit = np.array(Image.open(os.path.join(HERE, "relay_base_nodish_raw_v1.png")).convert("RGBA")).astype(np.float32)
H, W = orig.shape[:2]
yy, xx = np.mgrid[0:H, 0:W]

# Dish region: the top of the sprite down to the collar cap (collar top face ends ~y 420).
ROI = (yy < 420) & (xx > 430) & (xx < 900)
oa, ea = orig[..., 3], edit[..., 3]
diff = np.abs(orig[..., :3] - edit[..., :3]).mean(-1)
cand = ROI & (oa > 24) & ((ea < 60) | (diff > 38))
cand = ndi.binary_opening(cand, iterations=2)
lab, n = ndi.label(cand)
sizes = ndi.sum(cand, lab, range(1, n + 1))
dish = lab == (1 + int(np.argmax(sizes)))
dish = ndi.binary_fill_holes(ndi.binary_closing(dish, iterations=4))
# Turntable + neck (dark grey like the edit's cap plate, so the diff misses them): the cylinder
# measured on a x4 zoom — axis x 635, bottom ellipse centre y 378, rx 55, ry 29 (with its outline);
# everything above that ellipse inside its width goes with the dish.
TT = dict(cx=635.0, cy=378.0, rx=55.0, ry=29.0)
inside = np.clip(1 - ((xx - TT["cx"]) / TT["rx"]) ** 2, 0, None)
# Above the turntable's top (y 352) only the neck (x 598..668), not the collar's back rim beside it.
tt = (np.abs(xx - TT["cx"]) <= TT["rx"]) & (yy >= 352) & (yy <= TT["cy"] + TT["ry"] * np.sqrt(inside))
tt |= (xx >= 598) & (xx <= 668) & (yy >= 250) & (yy < 352)
tt &= oa > 24
dish = dish | tt
# Grow by 2 px so the dark outline of the dish goes with it, but only into pixels the edit lacks or differs.
grow = ndi.binary_dilation(dish, iterations=2) & ROI & ((ea < 60) | (diff > 20))
dish = dish | grow

# Base: original; under the dish (grown 3 px, feathered) the edit.
patch = ndi.binary_dilation(dish, iterations=3).astype(np.float32)
patch = ndi.gaussian_filter(patch, 1.2)
patch = np.clip(patch * 1.4, 0, 1)[..., None]
base = orig * (1 - patch) + edit * patch

# Dish part: original pixels inside the mask, alpha softened on the cut line only.
dsoft = np.clip(ndi.gaussian_filter(dish.astype(np.float32), 0.7) * 1.3, 0, 1)
dish_img = orig.copy()
dish_img[..., 3] = orig[..., 3] * dsoft
dish_img[..., 3][dish_img[..., 3] < 8] = 0

# Shadow: semi-transparent dark pixels at least 3 px away from the solid body.
solid = base[..., 3] >= 215
body_zone = ndi.binary_dilation(solid, iterations=3)
rgbsum = base[..., :3].sum(-1)
shadow_px = (base[..., 3] > 8) & (base[..., 3] < 215) & (rgbsum < 200) & ~body_zone
sh_alpha = base[..., 3] * shadow_px
# Fill solid under the body (and the 3 px rim) with the shadow's typical alpha.
typ = float(np.median(base[..., 3][shadow_px])) if shadow_px.any() else 120.0
under = ndi.binary_fill_holes(body_zone)
sh_alpha = np.where(under, np.maximum(sh_alpha, typ), sh_alpha)
shadow = np.zeros_like(base)
shadow[..., 3] = sh_alpha
base_body = base.copy()
base_body[..., 3] = np.where(shadow_px, 0, base[..., 3])


def save(a, name):
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(OUT, name))


save(base_body, "relay_base.png")
save(shadow, "relay_base_shadow.png")
save(dish_img, "relay_dish_000.png")

bb = lambda m: [int(np.nonzero(m)[1].min()), int(np.nonzero(m)[0].min()), int(np.nonzero(m)[1].max()), int(np.nonzero(m)[0].max())]
# Housing = the dish's turning point on the mast = the turntable axis on the collar cap (TT centre).
info = dict(canvas=[W, H], dish_bbox=bb(dish_img[..., 3] > 24), base_bbox=bb(base_body[..., 3] > 24),
            shadow_bbox=bb(shadow_px), shadow_px=int(shadow_px.sum()), shadow_alpha_median=typ,
            turntable=TT, housing=[TT["cx"], TT["cy"]])
json.dump(info, open(os.path.join(OUT, "relay_cut.json"), "w"), indent=1)
print(json.dumps(info))
