"""Measure a Codex dish view against the 3D template model, honestly (no scale fitting applied).

    python3 dish_v2_measure.py <k> <raw.png>      -> raw/relay_dish_KK_vN_cut.png, measure/KK_vN.json,
                                                      measure/KK_vN_overlay.png

1. Background: if the corners are opaque near-white, cut it out (flood fill from the border, colour-to-alpha
   on a 3 px edge band), as art/objects/units/drone/drone_views_cut.py.
2. Canvas: resized to the template size (1024) by ONE factor (canvas / 1024), the same for every view.
3. Measure: for azimuths target +-25 deg (step 0.5) the model mask is aligned to the result by centroid and
   sqrt(area) scale -> best IoU gives the measured azimuth, its scale and shift. Reported, not applied.
4. Pass: |az error| <= 5 deg and opaque pixels within 12 px of the hinge after the shift. The Codex zoom
   (scale) is reported and undone by one factor for the whole sprite in dish_v2_place.py.
"""
import json
import math
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dish_v2_template as T  # noqa: E402


def cut_white(im):
    a = np.asarray(im.convert("RGBA")).astype(np.float32)
    corners = [a[0, 0], a[0, -1], a[-1, 0], a[-1, -1]]
    if sum(c[3] > 0 for c in corners) < 3:
        return im.convert("RGBA"), False
    rgb = a[..., :3]
    near = rgb.min(axis=2) >= 232
    h, w = near.shape
    bg = np.zeros_like(near)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if near[y, x] and not bg[y, x]:
                bg[y, x] = True; q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if near[y, x] and not bg[y, x]:
                bg[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
            if 0 <= ny < h and 0 <= nx < w and not bg[ny, nx] and near[ny, nx]:
                bg[ny, nx] = True; q.append((ny, nx))
    keep = ~bg
    alpha = keep.astype(np.float32)
    band = keep & ~ndi.binary_erosion(keep, iterations=3)
    soft = np.clip((255.0 - rgb.min(axis=2)) / (255.0 - 200.0), 0, 1)
    alpha[band] = soft[band]
    out = a.copy()
    out[..., 3] = alpha * 255
    return Image.fromarray(out.astype(np.uint8), "RGBA"), True


def largest(mask):
    lab, n = ndi.label(mask, structure=np.ones((3, 3)))
    if n <= 1:
        return mask
    sizes = ndi.sum(mask, lab, range(1, n + 1))
    return lab == (int(np.argmax(sizes)) + 1)


def model_tip(az):
    n, _, _ = T.axis(az)
    vertex = n * T.C0 - n * T.DEPTH
    return T.proj(vertex + n * T.EMIT)


def model_table():
    """Per 0.5 deg: (feed tip - part centroid) / sqrt(part area) of the model, cached in model_table.json."""
    path = os.path.join(HERE, "model_table.json")
    if os.path.exists(path):
        return json.load(open(path))
    tab = []
    for az in np.arange(0, 360, 0.5):
        m = T.part_mask(az)
        ys, xs = np.nonzero(m)
        tx, ty = model_tip(az)
        r = math.sqrt(m.sum())
        tab.append(dict(az=float(az), vx=(tx - xs.mean()) / r, vy=(ty - ys.mean()) / r))
    json.dump(tab, open(path, "w"))
    return tab


def feed_tip(rgba, rm, ox, oy, s, az):
    """Centroid of the glowing cyan blob nearest to where the silhouette fit puts the feed tip."""
    r, g, b, a = (rgba[..., i].astype(int) for i in range(4))
    cyan = (a > 200) & (g > 190) & (b > 225) & (r < 170) & rm
    lab, n = ndi.label(cyan, structure=np.ones((3, 3)))
    if n == 0:
        return None
    px, py = model_tip(az)
    px, py = px * s + ox, py * s + oy
    best = None
    for i, sl in enumerate(ndi.find_objects(lab), 1):
        ys, xs = np.nonzero(lab[sl] == i)
        if len(xs) < 30:
            continue
        cx, cy = xs.mean() + sl[1].start, ys.mean() + sl[0].start
        dd = (cx - px) ** 2 + (cy - py) ** 2
        if best is None or dd < best[0]:
            best = (dd, cx, cy)
    return None if best is None else (best[1], best[2])


def main():
    k = int(sys.argv[1]); raw = sys.argv[2]
    name = os.path.splitext(os.path.basename(raw))[0]
    im = Image.open(raw)
    cut, was_white = cut_white(im)
    os.makedirs(os.path.join(HERE, "raw"), exist_ok=True)
    os.makedirs(os.path.join(HERE, "measure"), exist_ok=True)
    cut_path = os.path.join(HERE, "raw", name + "_cut.png")
    cut.save(cut_path)
    f = T.SIZE / cut.width
    norm = cut.resize((T.SIZE, round(cut.height * f)), Image.LANCZOS)
    canvas = Image.new("RGBA", (T.SIZE, T.SIZE), (0, 0, 0, 0)); canvas.paste(norm, (0, 0))
    rm = largest(np.asarray(canvas)[..., 3] > 128)
    ys, xs = np.nonzero(rm); rc = (xs.mean(), ys.mean()); ra = rm.sum()

    target = T.VIEWS[k]
    best = None
    for az in np.arange(target - 25, target + 25.01, 0.5):
        mm = T.part_mask(az)
        my, mx = np.nonzero(mm); mc = (mx.mean(), my.mean())
        s = math.sqrt(ra / mm.sum())
        # model mask scaled by s about its centroid, moved onto the result centroid
        small = Image.fromarray(mm.astype(np.uint8) * 255)
        big = small.resize((round(T.SIZE * s), round(T.SIZE * s)), Image.BILINEAR)
        ox, oy = round(rc[0] - mc[0] * s), round(rc[1] - mc[1] * s)
        c = Image.new("L", (T.SIZE, T.SIZE), 0); c.paste(big, (ox, oy))
        moved = np.asarray(c) > 127
        iou = (moved & rm).sum() / max(1, (moved | rm).sum())
        if best is None or iou > best[0]:
            hx, hy = T.ORIGIN[0] * s + ox, T.ORIGIN[1] * s + oy
            best = (iou, float(az), s, ox, oy, hx, hy, moved)
    iou, az, s, ox, oy, hx, hy, moved = best
    # IoU at the target pose with no fitting at all (template as drawn, canvas only normalised)
    tm = T.part_mask(target)
    iou_raw = (tm & rm).sum() / max(1, (tm | rm).sum())
    # contact: opaque result pixels within 12 px of where the hinge ended up
    yy, xx = np.ogrid[:T.SIZE, :T.SIZE]
    near_h = (xx - hx) ** 2 + (yy - hy) ** 2 <= 12 ** 2
    contact = bool((rm & near_h).any())
    err_sil = (az - target + 180) % 360 - 180
    # main azimuth measure: the glowing feed tip relative to the part centroid (a face-on dish has an almost
    # round silhouette, so the silhouette angle is weak there; the tip vector is not)
    tip = feed_tip(np.asarray(canvas), rm, ox, oy, s, az)
    if tip is not None:
        v = ((tip[0] - rc[0]) / math.sqrt(ra), (tip[1] - rc[1]) / math.sqrt(ra))
        tab = model_table()
        d = [(v[0] - e["vx"]) ** 2 + (v[1] - e["vy"]) ** 2 for e in tab]
        az_tip = tab[int(np.argmin(d))]["az"]
        err = (az_tip - target + 180) % 360 - 180
    else:
        az_tip, err = None, err_sil
    # both angle measures must agree with the target (one alone let a crooked face-on view through)
    ok = abs(err) <= 5 and abs(err_sil) <= 5 and contact   # Codex zoom is undone in dish_v2_place.py
    res = dict(k=k, target=round(target % 360, 1), measured=round((az_tip if az_tip is not None else az) % 360, 1),
               err=round(err, 1), by="feed tip" if tip is not None else "silhouette",
               measured_silhouette=round(az % 360, 1), err_silhouette=round(err_sil, 1),
               tip=[round(tip[0]), round(tip[1])] if tip is not None else None,
               scale=round(s, 3), shift=[round(hx - T.ORIGIN[0]), round(hy - T.ORIGIN[1])],
               iou_fit=round(float(iou), 3), iou_raw=round(float(iou_raw), 3), hinge_contact=contact,
               white_bg_cut=was_white, raw=raw, cut=cut_path, ok=bool(ok))
    with open(os.path.join(HERE, "measure", name + ".json"), "w") as fh:
        json.dump(res, fh, indent=1)
    # overlay: result on light grey, fitted model outline red, target template outline blue, hinge green
    view = Image.alpha_composite(Image.new("RGBA", (T.SIZE, T.SIZE), (232, 232, 232, 255)), canvas)
    arr = np.asarray(view).copy()
    for m, col in ((tm, (40, 70, 220, 255)), (moved, (230, 30, 30, 255))):
        e = np.asarray(Image.fromarray(m.astype(np.uint8) * 255).filter(ImageFilter.FIND_EDGES)
                       .filter(ImageFilter.MaxFilter(3))) > 0
        arr[e] = col
    ov = Image.fromarray(arr)
    d = ImageDraw.Draw(ov)
    d.line([hx - 16, hy, hx + 16, hy], fill=(0, 160, 0, 255), width=4)
    d.line([hx, hy - 16, hx, hy + 16], fill=(0, 160, 0, 255), width=4)
    ov.save(os.path.join(HERE, "measure", name + "_overlay.png"))
    print(json.dumps(res))


if __name__ == "__main__":
    main()
