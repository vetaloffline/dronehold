"""Measure generated light machine gun head views against the 3D model of light_mg_template.py.

For each view: render the model's silhouette at azimuths target-25 … target+25 (step 1°) and scales
0.80 … 1.25 of the size-matched first guess, find the best overlap (IoU) with the generated head by FFT
correlation on a 1/4 grid; then refine at ±3° (step 0.5°) and ±6 % scale (step 1 %) on a 1/2 grid.
The best azimuth = the measured barrel direction, the best scale = Codex zoom against the model,
the shift gives where the housing (bottom of the neck hub) ended up in the generated picture.
Checked on the approved head (true azimuth 136.4°): measured 136.0°, zoom 3.14 against 3.125.

    python3 light_mg_measure.py <k>=<view.png> [<k>=<view.png> …]   (k = 0…15, view az = 22.5*k)
    -> prints a table; writes views/measure.json next to this script (merged with earlier runs by k) and
       <name>_vs_model.png next to each view (model outline in red)
"""
import importlib.util
import json
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tpl", os.path.join(HERE, "light_mg_template.py"))
T = importlib.util.module_from_spec(spec)
spec.loader.exec_module(T)

Q = 4                     # work on a 1/Q grid
AZ_SPAN, AZ_STEP = 25, 1.0
SCALES = np.arange(0.80, 1.26, 0.03)       # around the first guess


def mask_of(path):
    im = Image.open(path).convert("RGBA")
    a = np.asarray(im)[..., 3] > 128
    lab, n = ndi.label(a, structure=np.ones((3, 3)))
    if n > 1:                                   # keep the largest piece (drop specks)
        sizes = ndi.sum(a, lab, range(1, n + 1))
        a = lab == (1 + int(np.argmax(sizes)))
    return im, a


def model_mask(az, scale, size, q=Q):
    """Model silhouette with the housing at the frame centre, on the 1/q grid."""
    s = T.SCALE * scale / q
    origin = (size[0] / 2, size[1] / 2)
    im = T.render(az, compass=False, scale=s, origin=origin, size=size)
    return np.asarray(im)[..., 3] > 0


def diag(m):
    ys, xs = np.nonzero(m)
    return math.hypot(xs.max() - xs.min(), ys.max() - ys.min())


def best_fit(target, az, dzs, scales, q):
    """Model on a canvas twice the target size (housing at its centre) so a long barrel is never cut;
    linear FFT correlation over all shifts; IoU at the best shift for every (azimuth, scale)."""
    H, W = target.shape
    P = (3 * H, 3 * W)
    tf = np.fft.rfft2(target.astype(float), P)
    tsum = target.sum()
    best = None
    for dz in dzs:
        for sc in scales:
            m = model_mask(az + dz, sc, (2 * W, 2 * H), q)
            corr = np.fft.irfft2(tf * np.conj(np.fft.rfft2(m.astype(float), P)), P)
            idx = np.unravel_index(int(np.argmax(corr)), corr.shape)
            inter = corr[idx]
            iou = inter / (tsum + m.sum() - inter)
            if best is None or iou > best[0]:
                dy, dx = idx
                dy = dy if dy < H else dy - P[0]
                dx = dx if dx < W else dx - P[1]
                best = (iou, dz, sc, dx + W, dy + H)      # housing in target px of this grid
    return best


def main(pairs):
    out = []
    for pair in pairs:
        k, path = pair.split("=", 1)
        k = int(k)
        az = 22.5 * k
        im, a = mask_of(path)
        def grid(q):
            return np.asarray(Image.fromarray(a.astype(np.uint8) * 255).resize((im.width // q, im.height // q))) > 127
        small = grid(Q)
        s0 = diag(small) / diag(model_mask(az, 1.0, (2 * small.shape[1], 2 * small.shape[0])))   # same silhouette size
        _, dz, sc, _, _ = best_fit(small, az, np.arange(-AZ_SPAN, AZ_SPAN + 1e-6, AZ_STEP), s0 * SCALES, Q)
        # refine on a finer grid around the coarse best
        fine = grid(Q // 2)
        iou, dz, sc, dx, dy = best_fit(fine, az, np.arange(dz - 3, dz + 3.01, 0.5), sc * np.arange(0.94, 1.061, 0.01), Q // 2)
        housing = (dx * (Q // 2), dy * (Q // 2))
        # overlay: model outline at the fitted pose on the full-size picture
        s = T.SCALE * sc
        mm = np.asarray(T.render(az + dz, compass=False, scale=s, origin=housing, size=im.size))[..., 3] > 0
        edge = mm & ~ndi.binary_erosion(mm, iterations=3)
        over = Image.new("RGBA", im.size, (232, 232, 232, 255))
        over.alpha_composite(im)
        tint = np.zeros((im.height, im.width, 4), np.uint8)
        tint[edge] = (255, 0, 0, 255)
        over.alpha_composite(Image.fromarray(tint))
        name = os.path.splitext(os.path.basename(path))[0]
        over.convert("RGB").save(os.path.join(os.path.dirname(path), f"{name}_vs_model.png"))
        row = dict(k=k, target=az, measured=round(az + dz, 1), error=round(dz, 1), zoom=round(float(sc), 3),
                   iou=round(float(iou), 3), housing=[round(housing[0]), round(housing[1])], size=list(im.size),
                   ok=bool(abs(dz) <= 5))
        out.append(row)
        print(f"#{k + 1:2d} target {az:6.1f}  measured {az + dz:6.1f}  err {dz:+5.1f}  zoom {sc:.2f}  "
              f"IoU {iou:.3f}  housing {row['housing']}  {'OK' if row['ok'] else 'OUT of ±5°'}")
    jp = os.path.join(HERE, "views", "measure.json")
    os.makedirs(os.path.dirname(jp), exist_ok=True)
    old = json.load(open(jp)) if os.path.exists(jp) else []
    keep = {r["k"]: r for r in old}
    keep.update({r["k"]: r for r in out})
    json.dump([keep[k] for k in sorted(keep)], open(jp, "w"), indent=1)


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="example:\n"
               "  python3 art/objects/buildings/light_mg/light_mg_measure.py 4=art/drafts/<session id>/buildings/light_mg/views/light_mg_head_090_v1.png\n"
               "  -> '# 5 target 90.0 measured 90.0 err +0.0 zoom 1.36 IoU 0.862 housing [626, 688] OK'; "
               "exit 0 always, a view off by more than ±5° is marked 'OUT of ±5°'")
    ap.add_argument("views", nargs="+", metavar="K=PNG",
                    help="view index K (0…15, target azimuth 22.5·K, 0 = right, 90 = towards the camera) "
                         "and the generated head picture; several pairs allowed")
    main(ap.parse_args().views)
