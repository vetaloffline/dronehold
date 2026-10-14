"""Bring the 16 generated head views to the size of the 3D model and one housing point.

Each view: largest connected piece -> one uniform factor 1/zoom for the whole sprite (zoom = Codex zoom
against the model, measured by light_mg_measure.py) -> housing at the same pixel on a shared canvas.
Parts are never scaled separately. Then every view is cropped by one common box (housing stays put).

    python3 light_mg_place.py <k>=<view.png> … (all 16)
    -> light_mg_head_<az>.png, light_mg_views.json (housing, muzzle, view_azimuths for the rig),
       light_mg_views_sheet.png (all 16 on the approved base, one scale, table of numbers).
    Inputs: the Codex views from art/drafts/…/views/ (drafts are not kept; the list is in prompts.md).
"""
import importlib.util
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = HERE                              # heads next to this script


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


T = load("tpl", "light_mg_template.py")
M = load("measure", "light_mg_measure.py")

CANVAS = T.SIZE
HOUSING = T.ORIGIN                     # template px; model scale T.SCALE (template px per head px)
PAD = 12


def name_of(az):
    return ("%05.1f" % az).replace(".", "_") if az % 1 else "%03d" % az


def largest(im):
    a = np.asarray(im)[..., 3] > 0
    lab, n = ndi.label(a, structure=np.ones((3, 3)))
    if n > 1:
        sizes = ndi.sum(a, lab, range(1, n + 1))
        keep = lab == (1 + int(np.argmax(sizes)))
        arr = np.asarray(im).copy()
        arr[~ndi.binary_dilation(keep, iterations=2), 3] = 0     # keep the soft edge of the main piece
        im = Image.fromarray(arr)
    return im


def main(pairs):
    os.makedirs(OUT, exist_ok=True)
    M.main(pairs)                                                # fresh measurements of the final files
    meas = {r["k"]: r for r in json.load(open(os.path.join(HERE, "views", "measure.json")))}
    placed = {}
    for pair in pairs:
        k, path = pair.split("=", 1)
        k = int(k)
        r = meas[k]
        im = largest(Image.open(path).convert("RGBA"))
        f = 1.0 / r["zoom"]                                      # one factor for the whole sprite
        im = im.resize((round(im.width * f), round(im.height * f)), Image.LANCZOS)
        hx, hy = r["housing"][0] * f, r["housing"][1] * f
        can = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
        can.alpha_composite(im, (round(HOUSING[0] - hx), round(HOUSING[1] - hy)))
        placed[k] = (can, r)
    # one common crop box for all views
    boxes = [np.asarray(c)[..., 3].nonzero() for c, _ in placed.values()]
    x0 = max(0, min(int(b[1].min()) for b in boxes) - PAD)
    y0 = max(0, min(int(b[0].min()) for b in boxes) - PAD)
    x1 = min(CANVAS, max(int(b[1].max()) for b in boxes) + PAD + 1)
    y1 = min(CANVAS, max(int(b[0].max()) for b in boxes) + PAD + 1)
    housing = (HOUSING[0] - x0, HOUSING[1] - y0)
    rows = []
    for k in sorted(placed):
        can, r = placed[k]
        az = 22.5 * k
        can.crop((x0, y0, x1, y1)).save(os.path.join(OUT, f"light_mg_head_{name_of(az)}.png"))
        # muzzle from the model at the measured azimuth (brake tip, barrel axis), template px of the crop
        f_, s_, u_ = T.frame(r["measured"])
        tip = f_ * (T.BARREL_F[1] + T.BRAKE["len"]) + u_ * T.BARREL_Z
        mx, my = T.proj(tip)
        rows.append(dict(k=k, az=az, measured=r["measured"], error=r["error"], iou=r["iou"], zoom=r["zoom"],
                         housing=list(housing), muzzle=[round(mx - x0), round(my - y0)]))
    meta = dict(size=[x1 - x0, y1 - y0], scale=T.SCALE, housing=list(housing),
                view_azimuths=[r["measured"] for r in rows],
                muzzle=[r["muzzle"] for r in rows], views=rows)
    json.dump(meta, open(os.path.join(OUT, "light_mg_views.json"), "w"), indent=1)
    # human sheet: each view on the approved base, same scale, numbers under the cell;
    # frames are built on the full canvas and cropped by the union of the base and all heads
    base = Image.open(T.BASE)
    bs = T.SCALE * T.BASE_PER_HEAD
    base_s = base.resize((round(base.width * bs), round(base.height * bs)), Image.LANCZOS)
    bpos = (round(HOUSING[0] - T.BASE_HOUSING[0] * bs), round(HOUSING[1] - T.BASE_HOUSING[1] * bs))
    full_base = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    full_base.alpha_composite(base_s, bpos)
    ys, xs = np.asarray(full_base)[..., 3].nonzero()
    ux0, uy0 = min(x0, int(xs.min())) - PAD, min(y0, int(ys.min())) - PAD
    ux1, uy1 = max(x1, int(xs.max())) + PAD, max(y1, int(ys.max())) + PAD
    cell = 340
    sheet = Image.new("RGB", (cell * 4, (cell + 34) * 4), (245, 245, 245))
    font = ImageFont.load_default()
    for r in rows:
        k = r["k"]
        im = Image.new("RGBA", (CANVAS, CANVAS), (232, 232, 232, 255))
        im.alpha_composite(full_base)
        im.alpha_composite(Image.open(os.path.join(OUT, f"light_mg_head_{name_of(r['az'])}.png")), (x0, y0))
        im = im.crop((ux0, uy0, ux1, uy1))
        im.thumbnail((cell, cell), Image.LANCZOS)
        x, y = (k % 4) * cell, (k // 4) * (cell + 34)
        sheet.paste(im.convert("RGB"), (x + (cell - im.width) // 2, y + (cell - im.height) // 2))
        ok = abs(r["error"]) <= 5
        ImageDraw.Draw(sheet).text((x + 8, y + cell + 6),
                                   f"#{k + 1} az {r['az']}  measured {r['measured']}  err {r['error']:+.1f}  IoU {r['iou']:.2f}",
                                   fill=(0, 0, 0) if ok else (200, 0, 0), font=font)
    sheet.save(os.path.join(OUT, "light_mg_views_sheet.png"))
    bad = [r for r in rows if abs(r["error"]) > 5]
    print(f"canvas {x1 - x0}x{y1 - y0}, housing {housing}; {len(rows) - len(bad)}/{len(rows)} within ±5°")


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="example (the 16 views used for the approved set are listed in prompts.md):\n"
               "  python3 art/objects/buildings/light_mg/light_mg_place.py 0=…/light_mg_head_000_v2.png 1=…/light_mg_head_022_5_v2.png … 15=…/light_mg_head_337_5_v2.png\n"
               "  -> re-measures every view (light_mg_measure.py), writes the heads, light_mg_views.json, light_mg_views_sheet.png;\n"
               "     the last line: 'canvas WxH, housing (x, y); N/16 within ±5°'; exit 0 always")
    ap.add_argument("views", nargs="+", metavar="K=PNG",
                    help="view index K (0…15, target azimuth 22.5·K) and its generated head picture; pass all 16")
    main(ap.parse_args().views)
