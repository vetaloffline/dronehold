"""Шаблон пози для смерті «бичувальника» (lasher): куля прошиває голову, голова й верх тулуба розлітаються.
5 кадрів сіткою 3×2 на 1536×1024, 6-та клітинка порожня. Тільки тіло з головою (і щелепа в кадрі 0):
лапи й щупальця відлітають кодом окремими частинами з art/objects/enemies/lasher/parts/.

Каркас: тонкі контури без заливки. Контур тіла — з альфи parts/lasher_body.png, щелепа — parts/lasher_jaw.png
на шарнірі, як у lasher_run_build.py (шарнір (670, 415), масштаб 0,48, кут 6°). Масштаб і місце тіла
відносно точки на землі (pivot) — як у кадрі 0 lasher_run_atlas.png (тіло ~213 з 320 px кадру, низ тіла на
pivot, лівий край на 99 px лівіше), ×300/213. Без лап тіло падає на землю: центр опускається на висоту
бігу (BODY_H · COS_E з lasher_run_template.py ≈ 84 px шаблону).

Кадри: 0 — влучання (червоне кільце на очах, червона стрілка — шлях кулі); 1 — голова розлетілась на
уламки, тулуб цілий без голови; 2 — верх тулуба (пластини зі шпичаками) розірвано й летить угору й
убік, лишився низ тулуба; 3 — уламки падають, низ тулуба падає на землю; 4 — рештки низу тулуба лежать
на землі, кілька пластин поруч, калюжа.
"""
import argparse
import json
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, *[".."] * 4))
PARTS = os.path.join(REPO, "art/objects/enemies/lasher/parts")

SHEET_W, SHEET_H = 1536, 1024
COLS, ROWS, CELL = 3, 2, 512
FRAMES = 5
BODY_W = 300                  # ширина тіла (кроп альфи) у клітинці, px
PIVOT = (230, 300)            # точка на землі в клітинці
BODY_LEFT = 139               # лівий край тіла лівіше pivot, px (99 × 300/213)
DROP = 84                     # на скільки опускається тіло, коли лап нема, px
HEAD_X = 560                  # голова — пікселі тіла правіше цього x (px lasher_body.png)
BACK_Y = 260                  # верх тулуба — вище цього y (px lasher_body.png)
JAW_HINGE, JAW_PIVOT, JAW_SCALE, JAW_DEG = (670, 415), (26, 46), 0.48, 6.0
IMPACT = (650, 345)           # точка влучання — на очах (px lasher_body.png)
K = 0.75

BG = (255, 255, 255)
GRID = (210, 210, 210)
GROUND = (232, 232, 232)
EDGE = (55, 55, 55)
ARROW = (40, 90, 200)
HIT = (220, 30, 30)


def alpha(name):
    return Image.open(os.path.join(PARTS, name)).convert("RGBA").getchannel("A").point(lambda v: 255 if v > 8 else 0)


def outline(mask, width=3):
    # Поле в 8 px: на краю картинки MinFilter не їсть пікселі → контур рвався там, де тіло торкається краю.
    pad = Image.new("L", (mask.width + 16, mask.height + 16), 0)
    pad.paste(mask, (8, 8))
    edge = ImageChops.subtract(pad, pad.filter(ImageFilter.MinFilter(2 * width + 1)))
    return edge.crop((8, 8, 8 + mask.width, 8 + mask.height))


def body_masks():
    """Маски тіла в px lasher_body.png: ціле (з щелепою), без голови, низ тулуба."""
    body = alpha("lasher_body.png")
    jaw = alpha("lasher_jaw.png")
    jw = jaw.resize((round(jaw.width * JAW_SCALE), round(jaw.height * JAW_SCALE)), Image.LANCZOS)
    full = Image.new("L", (body.width + 200, body.height + 120), 0)
    full.paste(body, (0, 0))
    # Щелепа: шарнір JAW_PIVOT ставиться на JAW_HINGE, поворот за годинниковою на JAW_DEG.
    rot = jw.rotate(-JAW_DEG, center=(JAW_PIVOT[0] * JAW_SCALE, JAW_PIVOT[1] * JAW_SCALE), expand=False)
    full.paste(255, (round(JAW_HINGE[0] - JAW_PIVOT[0] * JAW_SCALE), round(JAW_HINGE[1] - JAW_PIVOT[1] * JAW_SCALE)), rot)
    # Рвані краї — зигзаг, не пряма (пряму Codex малює як зріз коробки).
    w, h = body.width, body.height
    headless = body.copy()
    rng = random.Random(3)
    zig = [(HEAD_X + rng.uniform(-30, 35), h * i / 10) for i in range(11)]
    ImageDraw.Draw(headless).polygon(zig + [(w, h), (w, 0)], fill=0)
    lower = headless.copy()
    zig = [(w * i / 14, BACK_Y + rng.uniform(-25, 40)) for i in range(15)]
    ImageDraw.Draw(lower).polygon(zig + [(w, 0), (0, 0)], fill=0)
    return full, headless, lower, body.getbbox()


def place(cell, mask, bbox, s, dy=0.0, sy=1.0):
    """Маска в px lasher_body.png → клітинка: масштаб s, низ кропу тіла на pivot + dy, стиск по y sy."""
    m = mask.resize((max(1, round(mask.width * s)), max(1, round(mask.height * s * sy))), Image.LANCZOS)
    m = m.point(lambda v: 255 if v > 127 else 0)
    cell.paste(EDGE, (round(PIVOT[0] - BODY_LEFT - bbox[0] * s), round(PIVOT[1] + dy - bbox[3] * s * sy)), outline(m))
    return transform(bbox, s, dy, sy)


def transform(bbox, s, dy=0.0, sy=1.0):
    """px lasher_body.png → px клітинки (як у place)."""
    x = round(PIVOT[0] - BODY_LEFT - bbox[0] * s)
    y = round(PIVOT[1] + dy - bbox[3] * s * sy)
    return lambda p: (x + p[0] * s, y + p[1] * s * sy)


def arrow(d, a, b, color=ARROW, w=4):
    d.line([a, b], fill=color, width=w)
    ang = math.atan2(b[1] - a[1], b[0] - a[0])
    for sgn in (-1, 1):
        d.line([b, (b[0] - 14 * math.cos(ang + sgn * 0.5), b[1] - 14 * math.sin(ang + sgn * 0.5))], fill=color, width=w)


def shard(d, rng, c, r, spike=False):
    """Уламок пластини: неправильний 5-кутник; spike — зі шпичаком угору."""
    pts = []
    for i in range(5):
        t = 2 * math.pi * (i + rng.uniform(-0.2, 0.2)) / 5 + rng.uniform(0, 1)
        rr = r * rng.uniform(0.7, 1.1)
        pts.append((c[0] + rr * math.cos(t), c[1] + rr * math.sin(t) * 0.7))
    d.polygon(pts, outline=EDGE, width=3)
    if spike:
        top = min(pts, key=lambda p: p[1])
        d.polygon([(top[0] - 8, top[1] + 4), (top[0] + 8, top[1] + 4), (top[0] + 2, top[1] - r * 0.9)], outline=EDGE, width=3)


def ground(d, rx):
    d.ellipse((PIVOT[0] - rx, PIVOT[1] - rx * K * 0.45, PIVOT[0] + rx, PIVOT[1] + rx * K * 0.45), fill=GROUND)


def fragments(origin, dirs, dist, drop):
    return [(origin[0] + dist * math.cos(a) * m, origin[1] + dist * math.sin(a) * m + drop, r, sp)
            for a, m, r, sp in dirs]


# Уламки: (кут руху, множник відстані, розмір, зі шпичаком). Кути: 0 — вправо, −90° — вгору.
HEAD_DIRS = [(math.radians(a), m, r, False) for a, m, r in
             [(-150, 0.9, 20), (-110, 1.1, 24), (-70, 1.0, 18), (-30, 0.8, 22), (10, 0.9, 16), (60, 0.7, 18)]]
BACK_DIRS = [(math.radians(a), m, r, True) for a, m, r in
             [(-165, 1.0, 30), (-130, 1.15, 34), (-95, 1.2, 30), (-60, 1.1, 32), (-25, 0.95, 28), (-195, 0.8, 26)]]


def draw_frame(f, masks, s):
    full, headless, lower, bbox = masks
    cell = Image.new("RGB", (CELL, CELL), BG)
    d = ImageDraw.Draw(cell)
    rng = random.Random(11 + f)
    ground(d, 200)
    info = {"frame": f}
    to_cell = transform(bbox, s)
    head_c = to_cell((700, 330))
    back_c = to_cell((360, 170))
    if f == 0:
        to_cell = place(cell, full, bbox, s)
        hit = to_cell(IMPACT)
        d.ellipse((hit[0] - 16, hit[1] - 16, hit[0] + 16, hit[1] + 16), outline=HIT, width=5)
        arrow(d, (hit[0] + 150, hit[1] - 120), (hit[0] + 18, hit[1] - 14), color=HIT, w=5)
        info["impact"] = [round(hit[0]), round(hit[1])]
    elif f == 1:
        place(cell, headless, bbox, s)
        for x, y, r, sp in fragments(head_c, HEAD_DIRS, 70, 0):
            shard(d, rng, (x, y), r, sp)
        for a, m, r, sp in HEAD_DIRS:
            arrow(d, (head_c[0] + 20 * math.cos(a), head_c[1] + 20 * math.sin(a)),
                  (head_c[0] + (70 * m - r) * math.cos(a), head_c[1] + (70 * m - r) * math.sin(a)))
    elif f == 2:
        place(cell, lower, bbox, s, dy=DROP * 0.25)
        for x, y, r, sp in fragments(back_c, BACK_DIRS, 70, 0):
            shard(d, rng, (x, y), r, sp)
        for a, m, r, sp in BACK_DIRS:
            arrow(d, (back_c[0] + 5 * math.cos(a), back_c[1] + 5 * math.sin(a) + 40),
                  (back_c[0] + (70 * m - r * 0.6) * math.cos(a), back_c[1] + (70 * m - r * 0.6) * math.sin(a) + 10))
        for x, y, r, sp in fragments(head_c, HEAD_DIRS, 120, 20):
            shard(d, rng, (x, y), r * 0.9, sp)
    elif f == 3:
        place(cell, lower, bbox, s, dy=DROP * 0.75)
        for x, y, r, sp in fragments(back_c, BACK_DIRS, 140, 70) + fragments(head_c, HEAD_DIRS, 150, 70):
            shard(d, rng, (x, y), r * 0.9, sp)
            arrow(d, (x, y - r - 45), (x, y - r - 6))
    else:
        place(cell, lower, bbox, s, dy=DROP + 10, sy=0.8)
        pts = []
        for i in range(120):
            t = 2 * math.pi * i / 120
            r = 150 * (1 + 0.1 * math.sin(4 * t + 1.0) + 0.05 * math.sin(7 * t))
            pts.append((PIVOT[0] + 20 + r * math.cos(t), PIVOT[1] + 28 + r * math.sin(t) * K * 0.4))
        d.polygon(pts, outline=EDGE, width=2)
        for k, (a, m, r, sp) in enumerate(BACK_DIRS[:4] + HEAD_DIRS[:3]):
            t = 2 * math.pi * (k + 0.3) / 7
            c = (PIVOT[0] + 20 + 175 * math.cos(t), PIVOT[1] + 28 + 175 * math.sin(t) * K * 0.45)
            shard(d, rng, c, r * 0.8, False)
    return cell, info


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Приклад: python3 lasher_death_template.py\n"
               "Пише lasher_death_template.png (аркуш 1536×1024) і lasher_death_template.json (сітка, pivot, "
               "масштаб тіла, точка влучання). Exit 0 — готово, 1 — нема частин у parts/.")
    ap.add_argument("--out", default=HERE, help="папка для PNG/JSON (за замовчуванням — папка скрипта)")
    args = ap.parse_args()
    if not os.path.exists(os.path.join(PARTS, "lasher_body.png")):
        print("нема", PARTS)
        return 1
    masks = body_masks()
    bbox = masks[3]
    s = BODY_W / (bbox[2] - bbox[0])
    sheet = Image.new("RGB", (SHEET_W, SHEET_H), BG)
    frames = []
    for f in range(FRAMES):
        cell, info = draw_frame(f, masks, s)
        ox, oy = (f % COLS) * CELL, (f // COLS) * CELL
        sheet.paste(cell, (ox, oy))
        info["cell"] = [ox, oy]
        frames.append(info)
    d = ImageDraw.Draw(sheet)
    for c in range(1, COLS):
        d.line([(c * CELL, 0), (c * CELL, SHEET_H)], fill=GRID, width=2)
    d.line([(0, CELL), (SHEET_W, CELL)], fill=GRID, width=2)
    sheet.save(os.path.join(args.out, "lasher_death_template.png"))
    meta = {"size": [SHEET_W, SHEET_H], "cols": COLS, "rows": ROWS, "cell": CELL, "frames": FRAMES,
            "pivot_in_cell": PIVOT, "body_scale": round(s, 4), "body_left": BODY_LEFT, "drop": DROP,
            "run_atlas_body_w": 213, "frame_info": frames}
    with open(os.path.join(args.out, "lasher_death_template.json"), "w") as fh:
        json.dump(meta, fh, indent=1)
    print("ok", os.path.join(args.out, "lasher_death_template.png"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
