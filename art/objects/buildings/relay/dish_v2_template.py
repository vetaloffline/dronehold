"""Pose templates v2 for the relay dish: 16 views around the vertical axis of the mount pin.

What turns: hinge knuckle + strut + dish + feed rod. The tower (base, mast, collar, spire) is static,
one sprite; the spire top is the mount point (housing). The hinge sits ON the axis at the housing, so
in every view the strut starts at the same pixel and the dish can't float.

World: X right, Y towards the camera, Z up; origin = housing (spire top, on the axis).
Screen: x = X*s + ox, y = (K*Y - C*Z)*s + oy, C = sqrt(1 - K^2); towards the camera V = (0, C, K).
Azimuth on the ground: 0 = right, 90 = towards the camera (as the turrets).
Units: px of the approved sprite relay_v1_clean.png; K measured there (collar ellipse 55 x 29 -> 0.53).

    python3 dish_v2_template.py            -> tpl/tpl_NN.png (for Codex), tpl/templates.json,
                                              check_sheet.png (for the human: all 16 on a mock spire)
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "tpl")

K = 0.53                       # ground squash of the approved sprite (collar rx 55, ry 29)
C = math.sqrt(1 - K * K)
V = np.array([0.0, C, K])      # towards the camera
LIGHT = np.array([0.55, -0.35, 0.76]); LIGHT /= np.linalg.norm(LIGHT)  # sun upper right

# Shape in approved-sprite px (from the calibration of the approved dish, dish/dish_calibrated.json).
EL = 41.8      # dish tilt up from the ground, deg
R = 131.3      # bowl radius
RIM = 22.2     # flat rim around the bowl
DEPTH = 36.3   # bowl depth
C0 = 102.5     # rim-plane centre: distance from the hinge along the dish axis
THICK = 27.7   # dish thickness behind the rim
EMIT = 137.1   # feed rod length from the bowl vertex
ER = 11.0      # feed rod radius
SR = 15.0      # strut radius
HR = 19.0      # hinge knuckle radius (horizontal axle across the azimuth)
HL = 30.0      # hinge axle half-length

AZ0 = 29.2                     # measured azimuth of the approved dish -> view 0 = approved pose
VIEWS = [AZ0 + 22.5 * k for k in range(16)]
SIZE = 1024
SCALE = 1.6                    # template px per approved px; the same for all 16 views
ORIGIN = (512, 660)            # housing in every template


def proj(p):
    return (p[0] * SCALE + ORIGIN[0], (K * p[1] - C * p[2]) * SCALE + ORIGIN[1])


def axis(az):
    a, e = math.radians(az), math.radians(EL)
    n = np.array([math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)])
    side = np.array([-math.sin(a), math.cos(a), 0.0])        # horizontal, across the azimuth
    up = np.cross(n, side)
    return n, side, up


def cylinder(p0, p1, r, b1, b2, kind, seg=20):
    out = []
    for i in range(seg):
        a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
        d0 = (b1 * math.cos(a0) + b2 * math.sin(a0)) * r
        d1 = (b1 * math.cos(a1) + b2 * math.sin(a1)) * r
        out.append((np.array([p0 + d0, p0 + d1, p1 + d1, p1 + d0]), kind))
    for c in (p0, p1):
        out.append((np.array([c + (b1 * math.cos(2 * math.pi * i / seg) + b2 * math.sin(2 * math.pi * i / seg)) * r
                              for i in range(seg)]), kind))
    return out


def faces(az):
    n, side, up = axis(az)
    hinge = np.zeros(3)
    ctr = hinge + n * C0
    vertex = ctr - n * DEPTH
    out = []
    # hinge knuckle: short horizontal axle across the azimuth, centred on the axis
    out += cylinder(hinge - side * HL, hinge + side * HL, HR, n, up, "hinge")
    # strut: hinge -> back of the dish, along the dish axis
    # ends just inside the back cap so it visibly meets the dish from any side
    out += cylinder(hinge, ctr - n * (THICK - 2.0), SR, side, up, "strut")
    # bowl: paraboloid, rim plane at ctr, vertex at ctr - n*DEPTH
    rings, segs = 10, 56

    def surf(rho, phi):
        return ctr + side * rho * math.cos(phi) + up * rho * math.sin(phi) + n * (DEPTH * (rho / R) ** 2 - DEPTH)
    front = float(n @ V) > 0          # the open (concave) side faces the camera
    if front:                          # from behind, the back cap hides the bowl and the rim
        for j in range(rings):
            r0, r1 = R * j / rings, R * (j + 1) / rings
            for i in range(segs):
                a0, a1 = 2 * math.pi * i / segs, 2 * math.pi * (i + 1) / segs
                out.append((np.array([surf(r0, a0), surf(r0, a1), surf(r1, a1), surf(r1, a0)]), "bowl"))
        for i in range(segs):
            a0, a1 = 2 * math.pi * i / segs, 2 * math.pi * (i + 1) / segs
            e = [side * math.cos(a) + up * math.sin(a) for a in (a0, a1)]
            out.append((np.array([ctr + e[0] * R, ctr + e[1] * R, ctr + e[1] * (R + RIM), ctr + e[0] * (R + RIM)]), "rim"))
    # dish thickness behind the rim (the dark band seen on the approved dish) + flat back cap
    Rr = R + RIM
    for i in range(segs):
        a0, a1 = 2 * math.pi * i / segs, 2 * math.pi * (i + 1) / segs
        e0 = (side * math.cos(a0) + up * math.sin(a0)) * Rr
        e1 = (side * math.cos(a1) + up * math.sin(a1)) * Rr
        if float((e0 + e1) @ V) > 0:   # cull the far half of the band
            out.append((np.array([ctr + e0, ctr + e1, ctr + e1 - n * THICK, ctr + e0 - n * THICK]), "band"))
    if not front:
      out.append((np.array([ctr - n * THICK + (side * math.cos(2 * math.pi * i / segs) + up * math.sin(2 * math.pi * i / segs)) * Rr
                          for i in range(segs)]), "back"))
    # feed rod: from the vertex along the axis; red = the front of the dish
    rod0 = vertex if front else ctr + n * 2.0   # from behind, the part inside the bowl is hidden
    out += cylinder(rod0, vertex + n * EMIT, ER, side, up, "feed", seg=14)
    out.append((np.array([vertex + n * EMIT + (side * math.cos(2 * math.pi * i / 14) + up * math.sin(2 * math.pi * i / 14)) * ER * 1.5
                          for i in range(14)]), "feed"))
    return out, n


def shade(poly, kind, n):
    a, b, c = poly[0], poly[1], poly[2]
    nrm = np.cross(b - a, c - a)
    ln = np.linalg.norm(nrm)
    if ln < 1e-9:
        nrm = n.copy()
    else:
        nrm = nrm / ln
    if kind in ("bowl", "rim"):
        if nrm @ n < 0:
            nrm = -nrm                     # inner normal of the bowl, pointing along the dish axis
        front = nrm @ V > 0
        if not front:
            nrm = -nrm
        base = (196, 198, 204) if front else (58, 64, 84)   # light face, dark back
    elif kind == "feed":
        base = (225, 30, 30)
    elif kind in ("band", "back"):
        base = (58, 64, 84)
    elif kind == "hinge":
        base = (120, 122, 130)
    else:
        base = (138, 140, 148)
    if nrm @ V < 0:
        nrm = -nrm
    k = 0.55 + 0.45 * max(0.0, float(nrm @ LIGHT))
    return tuple(int(min(255, ch * k)) for ch in base)


def render(az, compass=True, bg=(255, 255, 255, 0)):
    im = Image.new("RGBA", (SIZE, SIZE), bg)
    d = ImageDraw.Draw(im)
    fs, n = faces(az)
    if compass:
        # ground compass at the hinge level: ring + arrow along the azimuth (blue, thin)
        rr = (R + RIM) * 1.15
        ring = [proj(np.array([rr * math.cos(t), rr * math.sin(t), 0.0])) for t in np.linspace(0, 2 * math.pi, 120)]
        d.line(ring + [ring[0]], fill=(40, 70, 220, 255), width=3)
        a = math.radians(az)
        tip = proj(np.array([rr * math.cos(a), rr * math.sin(a), 0.0]))
        d.line([proj(np.zeros(3)), tip], fill=(40, 70, 220, 255), width=5)
        for s in (-1, 1):
            b = a + math.pi + s * 0.45
            d.line([tip, proj(np.array([rr * math.cos(a) + 28 * math.cos(b), rr * math.sin(a) + 28 * math.sin(b), 0.0]))],
                   fill=(40, 70, 220, 255), width=5)
    order = sorted(fs, key=lambda f: float(f[0].mean(axis=0) @ V))
    for poly, kind in order:
        pts = [proj(p) for p in poly]
        col = shade(poly, kind, n) + (255,)
        d.polygon(pts, fill=col, outline=col)
    return im


def part_mask(az):
    im = render(az, compass=False)
    return np.asarray(im)[..., 3] > 0


def mock_tower(im):
    """For the human sheet only: collar + spire under the housing, like the static tower will be."""
    d = ImageDraw.Draw(im)
    spire_r, spire_h, col_r = 14, 70, 58
    top = proj(np.zeros(3))
    bot = proj(np.array([0, 0, -spire_h]))
    d.rectangle([top[0] - spire_r * SCALE, top[1], top[0] + spire_r * SCALE, bot[1]], fill=(70, 80, 105, 255))
    cy = bot[1]
    d.ellipse([top[0] - col_r * SCALE, cy - col_r * K * SCALE, top[0] + col_r * SCALE, cy + col_r * K * SCALE],
              fill=(150, 160, 180, 255), outline=(60, 70, 90, 255), width=3)
    d.rectangle([top[0] - spire_r * SCALE, top[1], top[0] + spire_r * SCALE, cy], fill=(70, 80, 105, 255))


def main():
    os.makedirs(OUT, exist_ok=True)
    rows = []
    for k, az in enumerate(VIEWS):
        render(az).save(os.path.join(OUT, f"tpl_{k:02d}.png"))
        m = part_mask(az)
        lab, ncomp = ndi.label(m, structure=np.ones((3, 3)))
        ys, xs = np.nonzero(m)
        hx, hy = proj(np.zeros(3))
        rows.append(dict(k=k, az=round(az % 360, 1), components=int(ncomp),
                         hinge_inside=bool(m[int(round(hy)), int(round(hx))]),
                         bbox=[int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
                         margin=int(min(xs.min(), ys.min(), SIZE - 1 - xs.max(), SIZE - 1 - ys.max()))))
    meta = dict(K=K, scale=SCALE, origin=ORIGIN, housing=ORIGIN, el=EL, R=R, rim=RIM, depth=DEPTH, c0=C0,
                emit=EMIT, az0=AZ0, step=22.5, views=rows)
    with open(os.path.join(OUT, "templates.json"), "w") as f:
        json.dump(meta, f, indent=1)

    # human sheet: 4x4, each template on a mock spire, housing cross, azimuth label under the cell
    cell = 360
    sheet = Image.new("RGB", (cell * 4, (cell + 30) * 4), (245, 245, 245))
    font = ImageFont.load_default()
    for r in rows:
        k = r["k"]
        im = Image.new("RGBA", (SIZE, SIZE), (232, 232, 232, 255))
        mock_tower(im)
        im = Image.alpha_composite(im, render(VIEWS[k], compass=True))
        dd = ImageDraw.Draw(im)
        hx, hy = ORIGIN
        dd.line([hx - 18, hy, hx + 18, hy], fill=(0, 160, 0, 255), width=4)
        dd.line([hx, hy - 18, hx, hy + 18], fill=(0, 160, 0, 255), width=4)
        im = im.convert("RGB").resize((cell, cell), Image.LANCZOS)
        x, y = (k % 4) * cell, (k // 4) * (cell + 30)
        sheet.paste(im, (x, y))
        ok = r["components"] == 1 and r["hinge_inside"] and r["margin"] >= 8
        ImageDraw.Draw(sheet).text((x + 8, y + cell + 8),
                                   f"#{k + 1}  az {r['az']}  parts {r['components']}  {'OK' if ok else 'FAIL'}",
                                   fill=(0, 0, 0) if ok else (200, 0, 0), font=font)
    sheet.save(os.path.join(HERE, "check_sheet.png"))
    bad = [r for r in rows if not (r["components"] == 1 and r["hinge_inside"] and r["margin"] >= 8)]
    for r in rows:
        print(r)
    print("FAIL" if bad else "OK", f"{len(rows) - len(bad)}/16 views: one piece, hinge on the housing, margin >= 8 px")


if __name__ == "__main__":
    main()
