"""Шаблон пози для смерті слизня (вибух): 5 кадрів сіткою 3×2 на 1536×1024, 6-та клітинка порожня.

Каркас: тонкі контури без заливки (заливку Codex копіює як форму — lasher_run_sheet_v1). Контур тіла —
з альфи art/objects/enemies/slime/slime_a.png. Точка на землі (pivot) однакова в усіх кадрах, під нею
світлий еліпс землі (тільки як прив'язка; тінь малює гра).

Кадри: 0 — роздувся; 1 — тріскає (тріщини, плями виривання); 2 — вибух (краплі й очі летять від центру,
лишилась низька купка); 3 — краплі падають на землю, купка розпливлась; 4 — калюжа слизу з бризками.
"""
import argparse
import json
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, *[".."] * 4))
SRC = os.path.join(REPO, "art/objects/enemies/slime/slime_a.png")

SHEET_W, SHEET_H = 1536, 1024
COLS, ROWS, CELL = 3, 2, 512
FRAMES = 5
BODY_W = 260                 # ширина тіла в клітинці, px
PIVOT = (256, 330)           # точка на землі в клітинці
PIVOT_K = (0.5, 0.88)        # точка на землі всередині кропу (як у slime_skins.py)
K = 0.75                     # стиск землі камерою

BG = (255, 255, 255)
GRID = (210, 210, 210)
GROUND = (232, 232, 232)
EDGE = (55, 55, 55)
ARROW = (40, 90, 200)
EYE = (220, 30, 30)


def body_mask():
    im = Image.open(SRC).convert("RGBA")
    a = im.getchannel("A").point(lambda v: 255 if v > 8 else 0)
    crop = a.crop(a.getbbox())
    s = BODY_W / crop.width
    return crop.resize((BODY_W, round(crop.height * s)), Image.LANCZOS).point(lambda v: 255 if v > 127 else 0)


def outline(mask, width=3):
    # Поле в 8 px: на краю картинки MinFilter не їсть пікселі → контур рвався там, де тіло торкається краю.
    pad = Image.new("L", (mask.width + 16, mask.height + 16), 0)
    pad.paste(mask, (8, 8))
    edge = ImageChops.subtract(pad, pad.filter(ImageFilter.MinFilter(2 * width + 1)))
    return edge.crop((8, 8, 8 + mask.width, 8 + mask.height))


def paste_body(cell, mask, sx, sy):
    """Тіло, розтягнуте від точки на землі в sx × sy."""
    m = mask.resize((max(1, round(mask.width * sx)), max(1, round(mask.height * sy))), Image.LANCZOS)
    m = m.point(lambda v: 255 if v > 127 else 0)
    x = round(PIVOT[0] - m.width * PIVOT_K[0])
    y = round(PIVOT[1] - m.height * PIVOT_K[1])
    cell.paste(EDGE, (x, y), outline(m))
    return (x, y, x + m.width, y + m.height)


def arrow(d, a, b, color=ARROW, w=4):
    d.line([a, b], fill=color, width=w)
    ang = math.atan2(b[1] - a[1], b[0] - a[0])
    for s in (-1, 1):
        d.line([b, (b[0] - 14 * math.cos(ang + s * 0.5), b[1] - 14 * math.sin(ang + s * 0.5))], fill=color, width=w)


def blob(d, c, r, stretch=1.0, ang=0.0):
    """Крапля-еліпс, витягнута вздовж руху."""
    pts = []
    for i in range(24):
        t = 2 * math.pi * i / 24
        x, y = r * stretch * math.cos(t), r * math.sin(t)
        pts.append((c[0] + x * math.cos(ang) - y * math.sin(ang), c[1] + x * math.sin(ang) + y * math.cos(ang)))
    d.polygon(pts, outline=EDGE, width=3)


def eye(d, c, r):
    d.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), outline=EYE, width=3)
    d.ellipse((c[0] - r / 3, c[1] - r / 3, c[0] + r / 3, c[1] + r / 3), outline=EYE, width=3)


def ground(d, rx):
    d.ellipse((PIVOT[0] - rx, PIVOT[1] - rx * K * 0.5, PIVOT[0] + rx, PIVOT[1] + rx * K * 0.5), fill=GROUND)


def fly(rng, n, center, r0, r1, drop):
    """n крапель по колу від центру: (позиція, радіус, кут руху). drop — зсув униз (падають)."""
    out = []
    for i in range(n):
        ang = 2 * math.pi * (i + rng.uniform(-0.3, 0.3)) / n
        dist = rng.uniform(r0, r1)
        p = (center[0] + dist * math.cos(ang), center[1] + dist * math.sin(ang) * K + drop)
        out.append((p, rng.uniform(10, 26), ang))
    return out


def draw_frame(f, mask):
    cell = Image.new("RGB", (CELL, CELL), BG)
    d = ImageDraw.Draw(cell)
    rng = random.Random(7)
    center = (PIVOT[0], PIVOT[1] - 70)
    info = {"frame": f}
    if f == 0:
        ground(d, 150)
        info["body_box"] = paste_body(cell, mask, 1.12, 1.35)
    elif f == 1:
        ground(d, 160)
        box = paste_body(cell, mask, 1.2, 1.55)
        info["body_box"] = box
        top = box[1]
        for dx in (-60, -15, 35, 75):          # тріщини зверху вниз
            x, y = PIVOT[0] + dx, top + 20 + abs(dx) * 0.35
            pts = [(x, y)]
            for _ in range(4):
                x += rng.uniform(-14, 14); y += rng.uniform(14, 24)
                pts.append((x, y))
            d.line(pts, fill=EDGE, width=3)
        for i in range(8):                     # слиз рветься назовні
            ang = math.pi + math.pi * i / 7
            a = (center[0] + 120 * math.cos(ang), center[1] - 20 + 95 * math.sin(ang))
            b = (center[0] + 160 * math.cos(ang), center[1] - 20 + 130 * math.sin(ang))
            arrow(d, a, b)
    elif f in (2, 3):
        ground(d, 190 if f == 2 else 210)
        sx, sy = (0.75, 0.4) if f == 2 else (0.95, 0.22)
        info["body_box"] = paste_body(cell, mask, sx, sy)
        drops = fly(rng, 11, center, 120, 165, 0) if f == 2 else fly(rng, 11, center, 175, 215, 60)
        info["drops"] = []
        for k, (p, r, ang) in enumerate(drops):
            if k in (1, 5, 8):
                eye(d, p, r + 4)
            else:
                blob(d, p, r, 1.6, ang)
            a = (center[0] + 60 * math.cos(ang), center[1] + 60 * math.sin(ang) * K)
            b = (p[0] - (r + 6) * math.cos(ang), p[1] - (r + 6) * math.sin(ang) * K)
            if f == 3:
                a, b = (p[0], p[1] - 55), (p[0], p[1] - r - 6)   # падають
            arrow(d, a, b)
            info["drops"].append([round(p[0]), round(p[1]), round(r)])
    else:
        ground(d, 210)
        pts = []                               # калюжа з пелюстками, лежить на землі
        for i in range(120):
            t = 2 * math.pi * i / 120
            r = 165 * (1 + 0.12 * math.sin(5 * t + 0.7) + 0.05 * math.sin(8 * t))
            pts.append((PIVOT[0] + r * math.cos(t), PIVOT[1] - 8 + r * math.sin(t) * K * 0.62))
        d.polygon(pts, outline=EDGE, width=3)
        for k in range(7):                     # бризки навколо
            t = 2 * math.pi * (k + 0.4) / 7
            p = (PIVOT[0] + 205 * math.cos(t), PIVOT[1] - 8 + 205 * math.sin(t) * K * 0.62)
            blob(d, p, 9 + 3 * (k % 3), 1.5, t)
        eye(d, (PIVOT[0] - 50, PIVOT[1] - 18), 16)
        eye(d, (PIVOT[0] + 40, PIVOT[1] - 4), 12)
        info["puddle_rx"] = 165
    return cell, info


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Приклад: python3 slime_death_template.py\n"
               "Пише поруч зі скриптом slime_death_template.png (аркуш 1536×1024) і slime_death_template.json "
               "(сітка, pivot, рамки тіла). Exit 0 — готово, 1 — нема slime_a.png.")
    ap.add_argument("--out", default=HERE, help="папка для PNG/JSON (за замовчуванням — папка скрипта)")
    args = ap.parse_args()
    if not os.path.exists(SRC):
        print("нема", SRC)
        return 1
    mask = body_mask()
    sheet = Image.new("RGB", (SHEET_W, SHEET_H), BG)
    frames = []
    for f in range(FRAMES):
        cell, info = draw_frame(f, mask)
        ox, oy = (f % COLS) * CELL, (f // COLS) * CELL
        sheet.paste(cell, (ox, oy))
        info["cell"] = [ox, oy]
        frames.append(info)
    d = ImageDraw.Draw(sheet)
    for c in range(1, COLS):
        d.line([(c * CELL, 0), (c * CELL, SHEET_H)], fill=GRID, width=2)
    d.line([(0, CELL), (SHEET_W, CELL)], fill=GRID, width=2)
    sheet.save(os.path.join(args.out, "slime_death_template.png"))
    meta = {"size": [SHEET_W, SHEET_H], "cols": COLS, "rows": ROWS, "cell": CELL, "frames": FRAMES,
            "pivot_in_cell": PIVOT, "body_w": BODY_W, "frame_info": frames}
    with open(os.path.join(args.out, "slime_death_template.json"), "w") as fh:
        json.dump(meta, fh, indent=1)
    print("ok", os.path.join(args.out, "slime_death_template.png"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
