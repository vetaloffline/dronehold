"""Шаблон пози для циклу бігу «бичувальника» (art/concept/14_lasher_v1.png): 8 кадрів сіткою 4×2.

3D-модель (x — вперед, y — вгору, z — вбік до камери), проекція камерою гри: коло на землі → еліпс
1 : 0,75, монстр розвернутий до камери на YAW градусів (голова ближче до глядача, як на концепті).

Хід — рись: діагональні пари лап (ближня передня + дальня задня, дальня передня + ближня задня)
ступають разом, кожна пара — пів циклу на землі (стопа їде назад рівно, не ковзає), пів у повітрі (дуга).
Тіло найнижче в момент приземлення пари (кадри 0 і 4), найвище посередині кроку (2 і 6). Кінчики щупалець
відстають від тіла на 1 кадр (інерція) і гойдаються вперед-назад. Паща закрита в кадрі 0, відкрита в 4.

Кольори: тіло сіре, голова темно-сіра, щелепа червона (= перед), ближні лапи темні, дальні світлі,
щупальця сині (лише щоб відрізнити від лап).
"""
import argparse
import json
import math
import os

from PIL import Image, ImageDraw

FRAMES = 8
COLS, ROWS = 4, 2
CELL = 384
SHEET_W, SHEET_H = 1536, 1024
TOP = (SHEET_H - ROWS * CELL) // 2

K = 0.75                       # стиск землі камерою
COS_E = math.sqrt(1 - K * K)   # стиск висоти
YAW = math.radians(22)
ORIGIN = (167, 235)            # точка під центром тіла на землі, у клітинці

BODY_H = 78                    # висота центру тіла над землею
BODY_R = (92, 46, 58)          # півосі тіла: вперед, вгору, вбік
STRIDE = 84
LIFT = 30
L1, L2 = 72, 88
BOB = 9
TIP_SWING = 30
TIP_SWAY = 22

BG = (255, 255, 255)
GRID = (205, 205, 205)
SHADOW = (225, 225, 225)
BODY = (150, 150, 150)
EDGE = (60, 60, 60)
HEAD = (95, 95, 95)
JAW = (220, 30, 30)
LEG_NEAR = (70, 70, 70)
LEG_FAR = (185, 185, 185)
TENT_NEAR = (45, 95, 215)
TENT_FAR = (140, 170, 235)

# ім'я, стегно (x, z), центр стопи (x, z), зсув фази, передня?
LEGS = [
    ("far_rear", (-50, -40), (-70, -80), 0.0, False),
    ("far_front", (45, -42), (80, -80), 0.5, True),
    ("near_rear", (-50, 40), (-70, 80), 0.5, False),
    ("near_front", (45, 42), (80, 80), 0.0, True),
]


def proj(p):
    x, y, z = p
    xr = x * math.cos(YAW) - z * math.sin(YAW)
    zr = x * math.sin(YAW) + z * math.cos(YAW)
    return (ORIGIN[0] + xr, ORIGIN[1] + zr * K - y * COS_E)


def hull(pts):
    pts = sorted(set(pts))
    if len(pts) < 3:
        return pts

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


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def mul(a, s):
    return tuple(x * s for x in a)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def norm(a):
    return mul(a, 1 / math.sqrt(dot(a, a)))


def foot_pos(phase, cx, cz):
    p = phase % 1.0
    if p < 0.5:
        s = p / 0.5
        return (cx + STRIDE / 2 - STRIDE * s, 0.0, cz)
    s = (p - 0.5) / 0.5
    e = 0.5 - 0.5 * math.cos(math.pi * s)
    return (cx - STRIDE / 2 + STRIDE * e, LIFT * math.sin(math.pi * s), cz)


def knee_pos(hip, foot, front, side):
    v = sub(foot, hip)
    d = min(math.sqrt(dot(v, v)), L1 + L2 - 1)
    u = norm(v)
    a = (L1 * L1 - L2 * L2 + d * d) / (2 * d)
    h = math.sqrt(max(L1 * L1 - a * a, 0))
    # коліно як у краба: вгору, назовні і вперед (передні) / назад (задні)
    pref = ((0.5 if front else -0.5), 0.45, 1.0 * side)
    n = sub(pref, mul(u, dot(pref, u)))
    return add(add(hip, mul(u, a)), mul(norm(n), h))


def bezier(p0, p1, p2, n=24):
    out = []
    for i in range(n + 1):
        t = i / n
        out.append(tuple((1 - t) ** 2 * a + 2 * (1 - t) * t * b + t * t * c for a, b, c in zip(p0, p1, p2)))
    return out


def frame_geometry(f):
    t = f / FRAMES
    bob = -BOB * math.cos(2 * math.pi * 2 * t)
    lag = math.cos(2 * math.pi * 2 * (t - 0.125))  # відставання 1/8 циклу (= 1 кадр з 8) за будь-якого FRAMES
    sway = math.sin(2 * math.pi * t)
    body = (0.0, BODY_H + bob, 0.0)
    legs = {}
    for name, (hx, hz), (fx, fz), off, front in LEGS:
        side = 1 if hz > 0 else -1
        hip = (hx, body[1] - 12, hz)
        foot = foot_pos(t + off, fx, fz)
        legs[name] = {"hip": hip, "knee": knee_pos(hip, foot, front, side), "foot": foot}
    mouth = 5 + 32 * (0.5 - 0.5 * math.cos(2 * math.pi * t))
    tentacles = {}
    for name, base, ctrl, tip in [
        ("rear", (-5, 42, -22), (55, 185, -38), (135, 125, -55)),
        ("front", (5, 42, 22), (65, 180, 38), (145, 110, 50)),
    ]:
        b = (base[0], body[1] + base[1], base[2])
        c = (ctrl[0] - 0.5 * TIP_SWAY * sway, body[1] + ctrl[1] - 0.5 * TIP_SWING * lag, ctrl[2])
        tp = (tip[0] - TIP_SWAY * sway, body[1] + tip[1] - TIP_SWING * lag, tip[2])
        tentacles[name] = {"base": b, "ctrl": c, "tip": tp}
    return {"body": body, "legs": legs, "mouth_deg": mouth, "tentacles": tentacles}


def draw_frame(img, ox, oy, g, skel=False):
    """skel=True — каркас: тонкі контури й лінії без заливки, щоб Codex не копіював форму блоків."""
    d = ImageDraw.Draw(img)
    lw = (lambda w: max(4, w // 3)) if skel else (lambda w: w)

    def P(p):
        x, y = proj(p)
        return (ox + x, oy + y)

    # тінь на землі
    if not skel:
        ring = [i * math.pi / 24 for i in range(48)]
        d.polygon([P((110 * math.cos(a), 0, 75 * math.sin(a))) for a in ring], fill=SHADOW)

    def leg(lg, color, width):
        pts = [P(lg["hip"]), P(lg["knee"]), P(lg["foot"])]
        d.line(pts, fill=color, width=lw(width), joint="curve")
        for jx, jy in pts:
            r = 7 if skel else width / 2
            d.ellipse((jx - r, jy - r, jx + r, jy + r), fill=color)

    def tentacle(tn, color):
        pts = [P(p) for p in bezier(tn["base"], tn["ctrl"], tn["tip"])]
        d.line(pts, fill=color, width=lw(17), joint="curve")
        tx, ty = pts[-1]
        dx, dy = tx - pts[-4][0], ty - pts[-4][1]
        ang = math.degrees(math.atan2(dy, dx))
        r = 24
        d.arc((tx - r, ty - r, tx + r, ty + r), ang - 20, ang + 200, fill=color, width=lw(10))

    bx, by, bz = g["body"]
    a, b, c = BODY_R
    shell = []
    for i in range(16):
        for j in range(1, 16):
            th, ph = 2 * math.pi * i / 16, math.pi * j / 16
            shell.append((bx + a * math.sin(ph) * math.cos(th), by + b * math.cos(ph),
                          bz + c * math.sin(ph) * math.sin(th)))
    shell += [(bx, by + b, bz), (bx, by - b, bz)]

    leg(g["legs"]["far_rear"], LEG_FAR, 12)
    leg(g["legs"]["far_front"], LEG_FAR, 12)
    tentacle(g["tentacles"]["rear"], TENT_FAR)

    d.polygon(hull([P(p) for p in shell]), fill=None if skel else BODY, outline=EDGE, width=3)
    for i in range(0 if skel else 7):
        x = bx - 70 + i * 22
        top_y = by + b * math.sqrt(max(1 - (x / a) ** 2, 0))
        d.polygon([P((x - 9, top_y - 4, 0)), P((x + 2, top_y + 26, 0)), P((x + 9, top_y - 4, 0))], fill=EDGE)

    head = [(hx, hy, hz) for hx in (bx + 70, bx + 128) for hy in (by - 28, by + 20) for hz in (-32, 32)]
    d.polygon(hull([P(p) for p in head]), fill=None if skel else HEAD, outline=EDGE, width=2)
    m = math.radians(g["mouth_deg"])
    hinge = (bx + 80, by - 26, 0)
    ln = 48
    tip = (hinge[0] + ln * math.cos(m), hinge[1] - ln * math.sin(m), 0)
    jaw = [add(hinge, (0, 0, -16)), add(hinge, (0, 0, 16)), add(tip, (0, 0, 10)), add(tip, (0, 0, -10))]
    d.polygon([P(p) for p in jaw], fill=None if skel else JAW, outline=JAW, width=4)

    tentacle(g["tentacles"]["front"], TENT_NEAR)
    leg(g["legs"]["near_rear"], LEG_NEAR, 16)
    leg(g["legs"]["near_front"], LEG_NEAR, 16)


def to_json(g):
    def pt(p):
        return {"world": [round(v, 2) for v in p], "screen": [round(v, 2) for v in proj(p)]}
    return {
        "body": pt(g["body"]),
        "mouth_deg": round(g["mouth_deg"], 2),
        "legs": {k: {j: pt(p) for j, p in v.items()} for k, v in g["legs"].items()},
        "tentacles": {k: {j: pt(p) for j, p in v.items()} for k, v in g["tentacles"].items()},
    }


def main():
    ap = argparse.ArgumentParser(
        description="Шаблон пози: 8 кадрів циклу бігу lasher у камері гри (2.5D, земля 1:0.75), "
                    "сітка 4x2 на 1536x1024 + JSON геометрії + GIF.",
        epilog="Приклад: python3 lasher_run_template.py --out .   Exit 0 — файли записані.",
    )
    ap.add_argument("--skeleton", action="store_true",
                    help="каркас (тонкі контури без заливки) → файли з суфіксом _skel; за замовчуванням — блоки")
    ap.add_argument("--out", default=os.path.dirname(os.path.abspath(__file__)),
                    help="папка для lasher_run_template.png/.json/.gif (за замовчуванням — папка скрипта)")
    args = ap.parse_args()
    name = "lasher_run_template" + ("_skel" if args.skeleton else "")

    sheet = Image.new("RGB", (SHEET_W, SHEET_H), BG)
    d = ImageDraw.Draw(sheet)
    frames, meta = [], []
    for f in range(FRAMES):
        col, row = f % COLS, f // COLS
        ox, oy = col * CELL, TOP + row * CELL
        g = frame_geometry(f)
        draw_frame(sheet, ox, oy, g, args.skeleton)
        one = Image.new("RGB", (CELL, CELL), BG)
        draw_frame(one, 0, 0, g, args.skeleton)
        frames.append(one)
        meta.append({"frame": f, "cell": [ox, oy, CELL, CELL], **to_json(g)})
    for c in range(1, COLS):
        d.line([(c * CELL, TOP), (c * CELL, TOP + ROWS * CELL)], fill=GRID, width=2)
    for r in range(ROWS + 1):
        d.line([(0, TOP + r * CELL), (SHEET_W, TOP + r * CELL)], fill=GRID, width=2)

    png = os.path.join(args.out, name + ".png")
    sheet.save(png)
    frames[0].save(os.path.join(args.out, name + ".gif"), save_all=True,
                   append_images=frames[1:], duration=90, loop=0)
    with open(os.path.join(args.out, name + ".json"), "w") as fh:
        json.dump({"frames": FRAMES, "cols": COLS, "rows": ROWS, "cell": CELL, "top": TOP, "k": K,
                   "yaw_deg": math.degrees(YAW), "gait": "trot", "items": meta}, fh, indent=1)
    print(png)


if __name__ == "__main__":
    main()
