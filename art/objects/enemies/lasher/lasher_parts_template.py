"""Шаблон розкладки частин «бичувальника» для cut-out анімації: кожна частина окремо, з проміжками.

Частини (сірі блоки, перед — червоний):
  body   — тіло з головою, у тому ж ракурсі, що й модель бігу (lasher_run_template.py: земля 1 : 0,75,
           поворот до камери 22°), без лап, щупалець і нижньої щелепи;
  jaw    — нижня щелепа, шарнір зліва;
  thigh  — стегно лапи, горизонтально: шарнір стегна зліва, коліно справа;
  shin   — гомілка з кігтем: коліно зліва, кіготь справа (загнутий вниз);
  tent   — щупальце рівною смугою: основа зліва, звужується вправо;
  hook   — гак на кінець щупальця: кріплення зліва.
Одна пара thigh + shin іде на всі 4 лапи (дальні — темніші), одне tent + hook — на обидва щупальця.
JSON — прямокутники частин і шарніри в пікселях шаблону; справжні шарніри міряються на результаті Codex.
"""
import argparse
import json
import math
import os

from PIL import Image, ImageDraw

W, H = 1536, 1024
BG = (255, 255, 255)
BODY = (150, 150, 150)
HEAD = (95, 95, 95)
EDGE = (60, 60, 60)
FRONT = (220, 30, 30)
PART = (120, 120, 120)

K = 0.75
COS_E = math.sqrt(1 - K * K)
YAW = math.radians(22)
S = 2.6                         # масштаб тіла проти lasher_run_template.py
BODY_R = (92, 46, 58)
BODY_C = (390, 330)             # центр тіла на шаблоні


def proj(p):
    x, y, z = p
    xr = x * math.cos(YAW) - z * math.sin(YAW)
    zr = x * math.sin(YAW) + z * math.cos(YAW)
    return (BODY_C[0] + S * xr, BODY_C[1] + S * (zr * K - y * COS_E))


def hull(pts):
    pts = sorted(set(pts))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lo, hi = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], p) <= 0:
            hi.pop()
        hi.append(p)
    return lo[:-1] + hi[:-1]


def main():
    ap = argparse.ArgumentParser(
        description="Шаблон розкладки частин lasher (тіло, щелепа, стегно, гомілка, щупальце, гак) 1536x1024 + JSON.",
        epilog="Приклад: python3 lasher_parts_template.py --out .   Exit 0 — файли записані.",
    )
    ap.add_argument("--out", default=os.path.dirname(os.path.abspath(__file__)),
                    help="папка для lasher_parts_template.png/.json (за замовчуванням — папка скрипта)")
    args = ap.parse_args()

    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    a, b, c = BODY_R

    shell = []
    for i in range(24):
        for j in range(1, 24):
            th, ph = 2 * math.pi * i / 24, math.pi * j / 24
            shell.append((a * math.sin(ph) * math.cos(th), b * math.cos(ph), c * math.sin(ph) * math.sin(th)))
    d.polygon(hull([proj(p) for p in shell]), outline=EDGE, width=4)
    # голова — округла (еліпсоїд), не коробка: кутастий контур Codex малює як куб
    head = []
    for i in range(18):
        for j in range(1, 18):
            th, ph = 2 * math.pi * i / 18, math.pi * j / 18
            head.append((100 + 34 * math.sin(ph) * math.cos(th), -6 + 26 * math.cos(ph), 34 * math.sin(ph) * math.sin(th)))
    d.polygon(hull([proj(p) for p in head]), outline=EDGE, width=3)
    hinge = proj((80, -26, 0))
    snout = proj((128, -10, 0))
    d.line([hinge, snout], fill=FRONT, width=8)

    hips = {
        "far_rear": proj((-50, -12, -40)), "far_front": proj((45, -12, -42)),
        "near_rear": proj((-50, -12, 40)), "near_front": proj((45, -12, 42)),
    }
    tent_bases = {"rear": proj((-5, 42, -22)), "front": proj((5, 42, 22))}
    for p in list(hips.values()) + list(tent_bases.values()):
        d.ellipse((p[0] - 9, p[1] - 9, p[0] + 9, p[1] + 9), outline=EDGE, width=3)

    parts = {}

    # нижня щелепа: шарнір зліва
    jx, jy = 880, 150
    d.polygon([(jx, jy - 25), (jx + 190, jy - 10), (jx + 200, jy + 10), (jx + 20, jy + 35)], outline=EDGE, width=4)
    d.line([(jx + 40, jy - 18), (jx + 195, jy - 6)], fill=FRONT, width=6)
    parts["jaw"] = {"box": [jx - 10, jy - 45, jx + 215, jy + 50], "pivot": [jx, jy], "tip": [jx + 200, jy]}

    # стегно: шарнір стегна зліва, коліно справа
    tx, ty = 880, 330
    d.rounded_rectangle((tx, ty - 32, tx + 230, ty + 32), radius=26, outline=EDGE, width=4)
    parts["thigh"] = {"box": [tx - 10, ty - 45, tx + 240, ty + 45], "pivot": [tx + 26, ty], "end": [tx + 204, ty]}

    # гомілка з кігтем: коліно зліва, кіготь справа
    sx, sy = 880, 500
    d.rounded_rectangle((sx, sy - 30, sx + 200, sy + 30), radius=24, outline=EDGE, width=4)
    d.polygon([(sx + 190, sy - 26), (sx + 290, sy + 10), (sx + 250, sy + 60), (sx + 190, sy + 26)], outline=EDGE, width=4)
    parts["shin"] = {"box": [sx - 10, sy - 45, sx + 300, sy + 75], "pivot": [sx + 24, sy], "end": [sx + 280, sy + 30]}

    # щупальце: рівна смуга, основа зліва, звужується вправо
    y0 = 790
    top = [(60 + i * 46, y0 - 34 + i * 0.7) for i in range(21)]
    bot = [(60 + i * 46, y0 + 34 - i * 0.7) for i in range(21)]
    d.polygon(top + bot[::-1], outline=EDGE, width=4)
    parts["tent"] = {"box": [50, y0 - 55, 1030, y0 + 55], "pivot": [60, y0], "end": [1020, y0]}

    # гак: кріплення зліва, гак загинається вниз і назад
    hx, hy = 1130, 760
    d.rounded_rectangle((hx, hy - 26, hx + 110, hy + 26), radius=20, outline=EDGE, width=4)
    # серп: від кріплення вправо, загинається вниз і назад
    outer = [(hx + 100 + 110 * math.cos(math.radians(t)), hy + 85 + 110 * math.sin(math.radians(t))) for t in range(-90, 135, 5)]
    inner = [(hx + 100 + 70 * math.cos(math.radians(t)), hy + 85 + 70 * math.sin(math.radians(t))) for t in range(-90, 135, 5)]
    d.polygon(outer + inner[::-1] + [(hx + 100, hy - 25)], outline=EDGE, width=4)
    parts["hook"] = {"box": [hx - 10, hy - 75, hx + 260, hy + 185], "pivot": [hx + 20, hy]}

    parts["body"] = {
        "box": [int(min(p[0] for p in [proj(q) for q in shell])) - 20, 60, 800, 560],
        "center": list(BODY_C), "jaw_hinge": list(hinge),
        "hips": {k: list(v) for k, v in hips.items()},
        "tent_bases": {k: list(v) for k, v in tent_bases.items()},
    }

    os.makedirs(args.out, exist_ok=True)
    png = os.path.join(args.out, "lasher_parts_template.png")
    img.save(png)
    with open(os.path.join(args.out, "lasher_parts_template.json"), "w") as fh:
        json.dump({"size": [W, H], "body_scale": S, "yaw_deg": math.degrees(YAW), "k": K, "parts": parts}, fh, indent=1)
    print(png)


if __name__ == "__main__":
    main()
