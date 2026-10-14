"""Pose templates for the light machine gun head: 16 views around the vertical axis of the neck.

What turns: hub + neck + gun body + front shield + side drum + handle + barrel. The base (feet, ring,
orange collar, axle) is static, one sprite; the centre of the collar top face is the mount point
(housing). The neck stands ON the axis at the housing, so in every view the head starts at the same
pixel and can't float.

World: X right, Y towards the camera, Z up; origin = housing (bottom of the neck hub, on the axis).
Screen: x = X*s + ox, y = (K*Y - C*Z)*s + oy, C = sqrt(1 - K^2).
Azimuth on the ground: 0 = right, 90 = towards the camera (as the turrets, turret_rig.gd).
Units: px of the approved head light_mg_head_codex.png.
K measured on the approved base light_mg_base_codex.png: collar top face 334 x 170 px -> 0.509.
Head shape measured on light_mg_head_codex.png (barrel azimuth 136.4 deg, barrel horizontal at Z 537).

    python3 light_mg_template.py calib   -> calib_overlay.png + IoU of the model vs the approved head
    python3 light_mg_template.py color   -> tplc/tplc_NN.png colour renders (for precise-object-edit) + color_sheet.png
    python3 light_mg_template.py         -> tpl/tpl_NN.png (for Codex), tpl/templates.json,
                                            check_sheet.png (for the human: all 16 on the real base)
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "tpl")

K = 0.509
C = math.sqrt(1 - K * K)
V = np.array([0.0, C, K])                                   # towards the camera
LIGHT = np.array([0.55, -0.35, 0.76]); LIGHT /= np.linalg.norm(LIGHT)   # sun upper right

# --- shape, head px (calibrated on the approved head, see `calib`) ---
HUB_R, HUB_H = 125.0, 45.0            # flat hub at the bottom of the neck
NECK_R = 75.0
BODY_Z = (430.0, 600.0)               # gun body: bottom, top
BODY_F = (-530.0, 320.0)              # along the barrel: back end, front (shield) plane
BODY_W = 200.0                        # half-width
SHIELD_T = 60.0                       # shield thickness (in front of the body)
SHIELD_W = 230.0                      # half-width
SHIELD_Z = (323.0, 827.0)
DRUM = dict(f=-27.0, side=-1, z=448.0, r=110.0, len=50.0)      # round drum on the right side
HANDLE = dict(f=(-390.0, -370.0), w=30.0, z=(640.0, 740.0))  # carry handle on the top rear
BARREL_Z = 537.0
BARREL_F = (SHIELD_T + BODY_F[1], 1270.0)                       # from the shield front to the brake
BARREL_R = 22.0
BRAKE = dict(len=130.0, r=38.0)                                  # muzzle brake at the end

AZ0 = 136.4                           # measured azimuth of the approved head
APPROVED = os.path.join(HERE, "light_mg_head_codex.png")
APPROVED_HOUSING = (1072.0, 830.0)    # hub bottom centre on the approved head, px
BASE = os.path.join(HERE, "light_mg_base_codex.png")
BASE_HOUSING = (838.0, 627.0)         # centre of the collar top face on the approved base, px
BASE_PER_HEAD = 0.385 / 0.335         # base px per head px (both fitted to concept D)

VIEWS = [22.5 * k for k in range(16)]
SIZE = 1024
SCALE = 0.32                          # template px per head px; the same for all 16 views
ORIGIN = (512, 560)                   # housing in every template


def proj(p, scale=SCALE, origin=ORIGIN):
    return (p[0] * scale + origin[0], (K * p[1] - C * p[2]) * scale + origin[1])


def frame(az):
    a = math.radians(az)
    f = np.array([math.cos(a), math.sin(a), 0.0])
    s = np.array([-math.sin(a), math.cos(a), 0.0])
    return f, s, np.array([0.0, 0.0, 1.0])


def box(f, s, u, f0, f1, w0, w1, z0, z1, kind):
    def P(a, b, c):
        return f * a + s * b + u * c
    v = [P(a, b, c) for a in (f0, f1) for b in (w0, w1) for c in (z0, z1)]
    # v index: a*4 + b*2 + c
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return [(np.array([v[i] for i in q]), kind) for q in quads]


def cylinder(p0, p1, r, b1, b2, kind, seg=24):
    out = []
    ring = [(b1 * math.cos(2 * math.pi * i / seg) + b2 * math.sin(2 * math.pi * i / seg)) * r for i in range(seg)]
    for i in range(seg):
        d0, d1 = ring[i], ring[(i + 1) % seg]
        out.append((np.array([p0 + d0, p0 + d1, p1 + d1, p1 + d0]), kind))
    for c in (p0, p1):
        out.append((np.array([c + d for d in ring]), kind))
    return out


def faces(az, color=False):
    f, s, u = frame(az)
    out = []
    z = u
    out += cylinder(np.zeros(3), z * HUB_H, HUB_R, f, s, "hub")
    out += cylinder(z * HUB_H, z * BODY_Z[0], NECK_R, f, s, "neck")
    out += box(f, s, u, BODY_F[0], BODY_F[1], -BODY_W, BODY_W, BODY_Z[0], BODY_Z[1], "body")
    out += box(f, s, u, BODY_F[1], BODY_F[1] + SHIELD_T, -SHIELD_W, SHIELD_W, SHIELD_Z[0], SHIELD_Z[1], "shield")
    dc = f * DRUM["f"] + s * (DRUM["side"] * BODY_W) + z * DRUM["z"]
    out += cylinder(dc, dc + s * (DRUM["side"] * DRUM["len"]), DRUM["r"], f, z, "drum")
    hf0, hf1 = HANDLE["f"]
    out += box(f, s, u, hf0, hf1, -HANDLE["w"], HANDLE["w"], HANDLE["z"][0], HANDLE["z"][1], "handle")
    b0 = f * BARREL_F[0] + z * BARREL_Z
    b1 = f * BARREL_F[1] + z * BARREL_Z
    out += cylinder(b0, b1, BARREL_R, s, z, "barrel", seg=14)
    out += cylinder(b1, b1 + f * BRAKE["len"], BRAKE["r"], s, z, "barrel", seg=14)
    if color:                         # design details for the colour render (approved head look)
        sf = BODY_F[1] + SHIELD_T
        for sg in (-1, 1):            # orange plates on both edges of the shield front
            out += box(f, s, u, sf - 5.0, sf + 18.0, sg * (SHIELD_W - 70.0), sg * SHIELD_W,
                       SHIELD_Z[0] + 40.0, SHIELD_Z[1] + 15.0, "orange")
        out += box(f, s, u, BODY_F[1] - 60.0, BODY_F[1] + 10.0, -45.0, 45.0,   # sight box with the blue light
                   SHIELD_Z[1] - 40.0, SHIELD_Z[1] + 45.0, "sight")
        out += box(f, s, u, BODY_F[1] + 10.0, BODY_F[1] + 14.0, -28.0, 28.0,
                   SHIELD_Z[1] - 25.0, SHIELD_Z[1] + 30.0, "blue")
        de = dc + s * (DRUM["side"] * DRUM["len"])
        out += cylinder(de, de + s * (DRUM["side"] * 6.0), DRUM["r"] * 0.78, f, z, "orange")
        out += cylinder(de + s * (DRUM["side"] * 6.0), de + s * (DRUM["side"] * 10.0), DRUM["r"] * 0.55, f, z, "drum")
        for f0 in (BARREL_F[0] + 40.0, BARREL_F[1] - 60.0):  # orange bands on the barrel
            out += cylinder(f * f0 + z * BARREL_Z, f * (f0 + 35.0) + z * BARREL_Z, BARREL_R + 7.0, s, z, "orange", seg=14)
    return out


COLORS = {"hub": (90, 92, 100), "neck": (110, 112, 120), "body": (150, 152, 160), "shield": (196, 198, 204),
          "drum": (120, 122, 130), "handle": (110, 112, 120), "barrel": (225, 30, 30)}
# colour render: the approved head's materials (dark-grey body, light-grey shield, orange plates, blue light)
COLORS_DESIGN = {"hub": (42, 43, 50), "neck": (48, 49, 56), "body": (74, 76, 86), "shield": (206, 201, 192),
                 "drum": (62, 64, 72), "handle": (56, 58, 66), "barrel": (58, 58, 66), "orange": (238, 122, 28),
                 "sight": (66, 68, 78), "blue": (40, 150, 255)}


def shade(poly, kind, colors=COLORS):
    a, b, c = poly[0], poly[1], poly[2]
    nrm = np.cross(b - a, c - a)
    ln = np.linalg.norm(nrm)
    nrm = np.array([0.0, 0.0, 1.0]) if ln < 1e-9 else nrm / ln
    if nrm @ V < 0:
        nrm = -nrm
    k = 0.55 + 0.45 * max(0.0, float(nrm @ LIGHT))
    return tuple(int(min(255, ch * k)) for ch in colors[kind])


def render(az, compass=True, bg=(255, 255, 255, 0), scale=SCALE, origin=ORIGIN, size=(SIZE, SIZE), color=False):
    im = Image.new("RGBA", size, bg)
    d = ImageDraw.Draw(im)
    if compass:
        rr = HUB_R * 2.2
        ring = [proj(np.array([rr * math.cos(t), rr * math.sin(t), 0.0]), scale, origin) for t in np.linspace(0, 2 * math.pi, 120)]
        d.line(ring + [ring[0]], fill=(40, 70, 220, 255), width=3)
        a = math.radians(az)
        tip = proj(np.array([rr * math.cos(a), rr * math.sin(a), 0.0]), scale, origin)
        d.line([proj(np.zeros(3), scale, origin), tip], fill=(40, 70, 220, 255), width=5)
        for sgn in (-1, 1):
            b = a + math.pi + sgn * 0.45
            d.line([tip, proj(np.array([rr * math.cos(a) + 40 * math.cos(b), rr * math.sin(a) + 40 * math.sin(b), 0.0]),
                              scale, origin)], fill=(40, 70, 220, 255), width=5)
    fs = faces(az, color)
    order = sorted(fs, key=lambda q: float(q[0].mean(axis=0) @ V))
    for poly, kind in order:
        pts = [proj(p, scale, origin) for p in poly]
        col = shade(poly, kind, COLORS_DESIGN if color else COLORS) + (255,)
        d.polygon(pts, fill=col, outline=col)
    return im


def calib():
    ap = Image.open(APPROVED)
    am = np.asarray(ap)[..., 3] > 128
    model = render(AZ0, compass=False, scale=1.0, origin=APPROVED_HOUSING, size=ap.size)
    mm = np.asarray(model)[..., 3] > 0
    iou = (am & mm).sum() / (am | mm).sum()
    over = Image.new("RGBA", ap.size, (232, 232, 232, 255))
    over.alpha_composite(ap)
    tint = np.zeros((ap.size[1], ap.size[0], 4), np.uint8)
    edge = mm & ~ndi.binary_erosion(mm, iterations=4)
    tint[edge] = (255, 0, 0, 255)
    over.alpha_composite(Image.fromarray(tint))
    over.convert("RGB").resize((ap.width // 2, ap.height // 2)).save(os.path.join(HERE, "calib_overlay.png"))
    print(f"IoU model vs approved head at az {AZ0}: {iou:.3f}  (approved {am.sum()} px, model {mm.sum()} px)")


def main():
    os.makedirs(OUT, exist_ok=True)
    rows = []
    for k, az in enumerate(VIEWS):
        render(az).save(os.path.join(OUT, f"tpl_{k:02d}.png"))
        m = np.asarray(render(az, compass=False))[..., 3] > 0
        lab, ncomp = ndi.label(m, structure=np.ones((3, 3)))
        ys, xs = np.nonzero(m)
        hx, hy = ORIGIN
        rows.append(dict(k=k, az=az, components=int(ncomp), housing_inside=bool(m[int(hy) - 2, int(hx)]),
                         bbox=[int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
                         margin=int(min(xs.min(), ys.min(), SIZE - 1 - xs.max(), SIZE - 1 - ys.max()))))
    meta = dict(K=K, scale=SCALE, origin=ORIGIN, housing=ORIGIN, az0=AZ0, step=22.5,
                barrel=dict(z=BARREL_Z, f=BARREL_F, brake=BRAKE["len"]), views=rows)
    with open(os.path.join(OUT, "templates.json"), "w") as fh:
        json.dump(meta, fh, indent=1)

    # human sheet: 4x4, each template on the real approved base, housing cross, azimuth under the cell
    base = Image.open(BASE)
    bs = SCALE * BASE_PER_HEAD
    base_s = base.resize((round(base.width * bs), round(base.height * bs)), Image.LANCZOS)
    bx, by = ORIGIN[0] - BASE_HOUSING[0] * bs, ORIGIN[1] - BASE_HOUSING[1] * bs
    cell = 360
    sheet = Image.new("RGB", (cell * 4, (cell + 30) * 4), (245, 245, 245))
    font = ImageFont.load_default()
    for r in rows:
        k = r["k"]
        im = Image.new("RGBA", (SIZE, SIZE), (232, 232, 232, 255))
        im.alpha_composite(base_s, (round(bx), round(by)))
        im = Image.alpha_composite(im, render(VIEWS[k], compass=True))
        dd = ImageDraw.Draw(im)
        hx, hy = ORIGIN
        dd.line([hx - 18, hy, hx + 18, hy], fill=(0, 160, 0, 255), width=4)
        dd.line([hx, hy - 18, hx, hy + 18], fill=(0, 160, 0, 255), width=4)
        im = im.convert("RGB").resize((cell, cell), Image.LANCZOS)
        x, y = (k % 4) * cell, (k // 4) * (cell + 30)
        sheet.paste(im, (x, y))
        ok = r["components"] == 1 and r["housing_inside"] and r["margin"] >= 8
        ImageDraw.Draw(sheet).text((x + 8, y + cell + 8),
                                   f"#{k + 1}  az {r['az']}  parts {r['components']}  {'OK' if ok else 'FAIL'}",
                                   fill=(0, 0, 0) if ok else (200, 0, 0), font=font)
    sheet.save(os.path.join(HERE, "check_sheet.png"))
    bad = [r for r in rows if not (r["components"] == 1 and r["housing_inside"] and r["margin"] >= 8)]
    for r in rows:
        print(r)
    print("FAIL" if bad else "OK", f"{len(rows) - len(bad)}/16 views: one piece, neck on the housing, margin >= 8 px")


def color_renders():
    """Colour renders of the same model for Codex (precise-object-edit: keep silhouette, repaint materials)."""
    out = os.path.join(HERE, "tplc")
    os.makedirs(out, exist_ok=True)
    for k, az in enumerate(VIEWS):
        render(az, compass=False, color=True).save(os.path.join(out, f"tplc_{k:02d}.png"))
    sheet = Image.new("RGB", (256 * 4, 256 * 4), (232, 232, 232))
    for k, az in enumerate(VIEWS):
        im = Image.new("RGBA", (SIZE, SIZE), (232, 232, 232, 255))
        im.alpha_composite(render(az, compass=False, color=True))
        sheet.paste(im.convert("RGB").resize((256, 256), Image.LANCZOS), ((k % 4) * 256, (k // 4) * 256))
    sheet.save(os.path.join(HERE, "color_sheet.png"))
    print("tplc/tplc_00..15.png + color_sheet.png")


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="examples:\n"
               "  python3 art/objects/buildings/light_mg/light_mg_template.py calib   -> IoU printed, calib_overlay.png\n"
               "  python3 art/objects/buildings/light_mg/light_mg_template.py color   -> tplc/, color_sheet.png\n"
               "  python3 art/objects/buildings/light_mg/light_mg_template.py         -> tpl/, check_sheet.png; "
               "exit 0 always, the last line says OK or FAIL (16/16 views: one piece, neck on the housing, margin >= 8 px)")
    ap.add_argument("mode", nargs="?", default="templates", choices=["templates", "calib", "color"],
                    help="templates (default): grey pose templates for Codex + the human sheet; "
                         "calib: the model at the approved head's azimuth over that head (IoU); "
                         "color: colour renders of the same model for precise-object-edit")
    a = ap.parse_args()
    {"calib": calib, "color": color_renders}.get(a.mode, main)()
