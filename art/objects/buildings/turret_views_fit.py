"""Fit Codex-drawn turret head views (made from guide templates) to the approved heads.

Usage: python turret_views_fit.py machine_gun <out_dir> <deg>=<raw.png> [<deg>=<raw.png> …]
       python turret_views_fit.py machine_gun --check     (leave-one-out test on the approved views)
For each raw: largest connected component → scale to the alpha area of the approved heads around
that angle → 418×418 canvas with the housing (point over the base ring) where the approved heads
have it around that angle. Prints housing, muzzle and the measured barrel angle (ground degrees,
housing → muzzle, camera squash 0.75) for the rig. Needs Pillow and numpy.

- housing = centroid of the light (non-barrel) pixels + an offset learned on the approved heads,
  interpolated by angle;
- barrel axis = principal axis of the dark barrel pixels; muzzle = the alpha pixel farthest along
  it from the housing, with the mean error on the approved heads subtracted.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SIZE = 418
CAM_K = 0.75
APPROVED = {
    "machine_gun": [
        (0, "000", (120, 189), (361, 194)),
        (22.5, "022_5", (141, 188), (393, 296)),
        (45, "045", (158, 182), (381, 323)),
        (67.5, "067_5", (178, 166), (328, 366)),
        (90, "090", (212, 137), (207, 316)),
        (112.5, "112_5", (231, 159), (102, 370)),
        (135, "135", (267, 176), (43, 328)),
        (157.5, "157_5", (279, 193), (23, 297)),
        (180, "180", (297, 189), (56, 195)),
        (202.5, "202_5", (281, 203), (17, 119)),
        (225, "225", (253, 228), (48, 83)),
        (247.5, "247_5", (234, 230), (81, 76)),
        (270, "270", (206, 244), (212, 101)),
        (292.5, "292_5", (195, 228), (312, 70)),
        (315, "315", (165, 225), (365, 83)),
        (337.5, "337_5", (145, 207), (404, 120)),
    ],
    "grenade_launcher": [
        (0, "000", (212, 226), (348, 52)), (45, "045", (194, 237), (310, 66)), (90, "090", (216, 241), (211, 56)),
        (135, "135", (224, 237), (107, 66)), (180, "180", (206, 225), (69, 52)), (225, "225", (207, 236), (122, 50)),
        (270, "270", (214, 233), (211, 44)), (315, "315", (210, 236), (295, 48)),
    ],
}
# Mortar tube rises steeply: housing → muzzle on screen does not show the azimuth. Its axis is
# taken from the template geometry (tube up at TUBE_EL, forward along the azimuth), and the
# azimuth is the nominal one (the template holds it within a few degrees).
TUBE = {"grenade_launcher": (52.0, 220.0)}


def tube_dir(name, deg):
    el, length = TUBE[name]
    a, e = math.radians(deg), math.radians(el)
    d = np.array([length * math.cos(e) * math.cos(a), length * math.cos(e) * math.sin(a) * CAM_K - length * math.sin(e)])
    return d / np.linalg.norm(d)


def ground_angle(h, m):
    return math.degrees(math.atan2((m[1] - h[1]) / CAM_K, m[0] - h[0])) % 360


def largest_component(a, thr=24):
    m = a > thr
    h, w = m.shape
    lab = np.zeros((h, w), np.int32)
    best, best_n, cur = 0, 0, 0
    for y0, x0 in zip(*np.nonzero(m)):
        if lab[y0, x0]:
            continue
        cur += 1
        stack = [(y0, x0)]
        lab[y0, x0] = cur
        n = 0
        while stack:
            y, x = stack.pop()
            n += 1
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not lab[ny, nx]:
                    lab[ny, nx] = cur
                    stack.append((ny, nx))
        if n > best_n:
            best, best_n = cur, n
    return lab == best


def features(im):
    a = np.array(im).astype(float)
    alpha = a[..., 3] > 24
    dark = alpha & (a[..., :3].max(-1) < 70)
    light = alpha & ~dark
    ys, xs = np.nonzero(light)
    centroid = np.array([xs.mean(), ys.mean()])
    dy, dx = np.nonzero(dark)
    p = np.stack([dx, dy], 1).astype(float)
    p -= p.mean(0)
    w, v = np.linalg.eigh(np.cov(p.T))
    axis = v[:, 1]
    return alpha, centroid, axis, alpha.sum()


def muzzle_along(alpha, h, axis):
    ys, xs = np.nonzero(alpha)
    proj = (xs - h[0]) * axis[0] + (ys - h[1]) * axis[1]
    sel = proj >= proj.max() - 4
    return np.array([xs[sel].mean(), ys[sel].mean()])


def interp(table, deg):
    """table: list of (angle, value np.array); linear in angle, circular."""
    t = sorted(table, key=lambda e: e[0])
    t = t + [(t[0][0] + 360, t[0][1])]
    d = deg % 360
    if d < t[0][0]:
        d += 360
    for (a0, v0), (a1, v1) in zip(t, t[1:]):
        if a0 <= d <= a1:
            f = (d - a0) / (a1 - a0) if a1 > a0 else 0
            return v0 + f * (v1 - v0)
    return t[-1][1]


def azimuth(name, deg, h, m):
    return float(deg) if name in TUBE else ground_angle(h, m)


def learn(name, skip=None):
    rows = []
    for deg, tag, h, m in APPROVED[name]:
        if deg == skip:
            continue
        im = Image.open(os.path.join(HERE, name, f"{name}_head_{tag}.png")).convert("RGBA")
        alpha, cen, axis, area = features(im)
        if name in TUBE:
            axis = tube_dir(name, deg)
        elif axis @ np.subtract(m, h) < 0:
            axis = -axis
        est_m = muzzle_along(alpha, h, axis)
        rows.append((azimuth(name, deg, h, m), np.subtract(h, cen), area, np.subtract(m, est_m)))
    off = [(r[0], r[1]) for r in rows]
    area = [(r[0], np.array([r[2]])) for r in rows]
    bias_m = np.mean([r[3] for r in rows], axis=0)
    return off, area, bias_m


def fit(im, deg, off, area, bias_m, name):
    a = np.array(im)
    keep = largest_component(a[..., 3])
    a[..., 3] = np.where(keep, a[..., 3], 0)
    im = Image.fromarray(a)
    _, _, _, ar = features(im)
    s = math.sqrt(float(interp(area, deg)[0]) / ar)
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    im = im.crop(im.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox())
    alpha, cen, axis, _ = features(im)
    want_dir = np.array([math.cos(math.radians(deg)), math.sin(math.radians(deg)) * CAM_K])
    if name in TUBE:
        axis = tube_dir(name, deg)
    elif axis @ want_dir < 0:
        axis = -axis
    h_local = cen + interp(off, deg)
    # Canvas: put the housing at the canvas centre-ish so nothing is clipped, then report it.
    ox = int(round(SIZE / 2 - (im.width / 2)))
    oy = int(round(SIZE / 2 - (im.height / 2)))
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.alpha_composite(im, (max(0, ox), max(0, oy)))
    h = h_local + (max(0, ox), max(0, oy))
    alpha2 = np.array(out)[..., 3] > 24
    m = muzzle_along(alpha2, h, axis) + bias_m
    return out, h, m, s


def main():
    name = sys.argv[1]
    if sys.argv[2] == "--check":
        for deg, tag, h, m in APPROVED[name]:
            off, area, bias_m = learn(name, skip=deg)
            im = Image.open(os.path.join(HERE, name, f"{name}_head_{tag}.png")).convert("RGBA")
            alpha, cen, axis, _ = features(im)
            if name in TUBE:
                axis = tube_dir(name, deg)
            elif axis @ np.subtract(m, h) < 0:
                axis = -axis
            eh = cen + interp(off, azimuth(name, deg, h, m))
            em = muzzle_along(alpha, eh, axis) + bias_m
            print(f"{deg:5.1f}: housing err {np.linalg.norm(eh - h):5.1f} px, muzzle err {np.linalg.norm(em - m):5.1f} px")
        return
    out_dir = sys.argv[2]
    off, area, bias_m = learn(name)
    os.makedirs(out_dir, exist_ok=True)
    for arg in sys.argv[3:]:
        deg_s, path = arg.split("=", 1)
        deg = float(deg_s)
        out, h, m, s = fit(Image.open(path).convert("RGBA"), deg, off, area, bias_m, name)
        tag = f"{deg:05.1f}".replace(".", "_")
        out.save(os.path.join(out_dir, f"{name}_head_{tag}.png"))
        print(f"{deg:5.1f}: scale {s:.3f} housing ({h[0]:.0f}, {h[1]:.0f}) muzzle ({m[0]:.0f}, {m[1]:.0f}) "
              f"measured angle {azimuth(name, deg, h, m):5.1f}")


main()
