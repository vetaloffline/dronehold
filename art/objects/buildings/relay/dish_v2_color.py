"""Coloured renders of the dish model for Codex "repaint" mode (pose stays exactly the model's).

Same 3D model, camera and scale as dish_v2_template.py; colours imitate the approved dish: white bowl with
4 dark radial panel lines, white rim with 8 gold clamps, dark navy thickness band with blue light strips,
dark navy back with plate seams, dark strut, gold hinge, dark feed rod with a gold ring and a cyan tip.

    python3 dish_v2_color.py KK [KK ...]   -> codex_in/color_KK.png (white bg), color_sheet.png (+ the real
                                              approved-quality view #1 and its render, for comparison)
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dish_v2_template as T  # noqa: E402

WHITE = (236, 238, 242)
NAVY = (44, 52, 78)
BLUE = (40, 150, 255)
GOLD = (232, 168, 40)
DARK = (62, 66, 78)
CYAN = (120, 235, 255)


def lit(col, nrm):
    k = 0.62 + 0.38 * max(0.0, float(nrm @ T.LIGHT))
    return tuple(int(min(255, c * k)) for c in col)


def face_normal(poly, n):
    a, b, c = poly[0], poly[1], poly[2]
    v = np.cross(b - a, c - a)
    ln = np.linalg.norm(v)
    v = n.copy() if ln < 1e-9 else v / ln
    if v @ T.V < 0:
        v = -v
    return v


def phi_of(p, ctr, side, up):
    d = p - ctr
    return math.atan2(float(d @ up), float(d @ side)) % (2 * math.pi)


def colour(poly, kind, az):
    n, side, up = T.axis(az)
    ctr = n * T.C0
    nrm = face_normal(poly, n)
    m = poly.mean(axis=0)
    seg = int(phi_of(m, ctr, side, up) / (2 * math.pi) * 16)  # 16 sectors around the dish
    if kind == "bowl":
        return lit(WHITE, nrm)
    if kind == "rim":
        return lit(GOLD if seg % 2 == 0 and int(phi_of(m, ctr, side, up) / (2 * math.pi) * 64) % 8 == 0 else WHITE, nrm)
    if kind == "band":
        return lit(BLUE if seg % 4 == 1 else GOLD if seg % 4 == 3 else NAVY, nrm)
    if kind == "back":
        return lit(NAVY, nrm)
    if kind == "strut":
        return lit(DARK, nrm)
    if kind == "hinge":
        return lit(GOLD, nrm)
    if kind == "feed_gold":
        return lit(GOLD, nrm)
    if kind == "feed_tip":
        return CYAN
    return lit(DARK, nrm)


def feed_faces(az):
    """The feed rod in pieces: dark, gold ring, dark, cyan tip (the model has it as one cylinder)."""
    n, side, up = T.axis(az)
    vertex = n * T.C0 - n * T.DEPTH
    front = float(n @ T.V) > 0
    start = 0.0 if front else (T.DEPTH + 2.0) / T.EMIT   # from behind, the part inside the bowl is hidden
    parts = [(start, 0.45, "feed"), (0.45, 0.6, "feed_gold"), (0.6, 0.86, "feed"), (0.86, 1.0, "feed_tip")]
    out = []
    for t0, t1, kind in parts:
        if t1 <= start:
            continue
        r = T.ER * (1.35 if kind == "feed_tip" else 1.15 if kind == "feed_gold" else 1.0)
        out += T.cylinder(vertex + n * T.EMIT * max(t0, start), vertex + n * T.EMIT * t1, r, side, up, kind, seg=14)
    return out


def render_color(az):
    im = Image.new("RGBA", (T.SIZE, T.SIZE), (255, 255, 255, 0))
    d = ImageDraw.Draw(im)
    fs, n = T.faces(az)
    fs = [f for f in fs if f[1] != "feed"] + feed_faces(az)
    order = sorted(fs, key=lambda f: float(f[0].mean(axis=0) @ T.V))
    n_, side, up = T.axis(az)
    ctr = n_ * T.C0
    front = float(n_ @ T.V) > 0
    for i, (poly, kind) in enumerate(order):
        col = colour(poly, kind, az) + (255,)
        d.polygon([T.proj(p) for p in poly], fill=col, outline=col)
    if front:
        # 4 radial panel lines on the bowl, drawn on top (they sit on the open face)
        for a in (0.3, 0.3 + math.pi / 2, 0.3 + math.pi, 0.3 + 3 * math.pi / 2):
            pts = []
            for rho in np.linspace(0.18 * T.R, T.R, 12):
                p = ctr + side * rho * math.cos(a) + up * rho * math.sin(a) + n_ * (T.DEPTH * (rho / T.R) ** 2 - T.DEPTH)
                pts.append(T.proj(p))
            d.line(pts, fill=(70, 74, 88, 255), width=3)
        # the feed rod is in front of the bowl lines: redraw it
        for poly, kind in order:
            if kind.startswith("feed"):
                col = colour(poly, kind, az) + (255,)
                d.polygon([T.proj(p) for p in poly], fill=col, outline=col)
    return im


def main():
    ks = [int(a) for a in sys.argv[1:]] or list(range(16))
    os.makedirs(os.path.join(HERE, "codex_in"), exist_ok=True)
    cell, font = 400, ImageFont.load_default()
    items = [("render #1 (29.2) — for comparison", render_color(T.VIEWS[0])),
             ("real #1 (approved quality)", Image.open(os.path.join(HERE, "placed", "relay_dish_00.png")).convert("RGBA"))]
    for k in ks:
        im = render_color(T.VIEWS[k])
        w = Image.new("RGBA", im.size, (255, 255, 255, 255)); w.alpha_composite(im)
        w.convert("RGB").save(os.path.join(HERE, "codex_in", f"color_{k:02d}.png"))
        items.append((f"render #{k + 1} ({T.VIEWS[k] % 360:.1f})", im))
    cols = 4
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new("RGB", (cell * cols, (cell + 24) * rows), (245, 245, 245))
    for i, (label, im) in enumerate(items):
        bg = Image.new("RGBA", (T.SIZE, T.SIZE), (232, 232, 232, 255))
        T.mock_tower(bg)
        c = Image.alpha_composite(bg, im).convert("RGB").resize((cell, cell), Image.LANCZOS)
        x, y = (i % cols) * cell, (i // cols) * (cell + 24)
        sheet.paste(c, (x, y))
        ImageDraw.Draw(sheet).text((x + 8, y + cell + 6), label, fill=(0, 0, 0), font=font)
    sheet.save(os.path.join(HERE, "color_sheet.png"))
    print("sheet:", os.path.join(HERE, "color_sheet.png"))


if __name__ == "__main__":
    main()
