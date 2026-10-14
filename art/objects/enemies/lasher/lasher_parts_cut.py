"""Перевірка й нарізка аркуша частин lasher від Codex.

1. Зв'язні шматки альфи (alpha > 40, площа ≥ --min-area). Дрібні краплі слизу, відірвані від частини,
   приєднуються до найближчого великого шматка, якщо до нього ≤ --merge px.
2. Шматки ↔ частини шаблону (`lasher_parts_template.json`) один до одного, мінімальна сума відстаней центрів.
3. Вихід: <out>/lasher_<частина>.png (обрізано по альфі) + таблиця: частина, шматків, розмір, центр.
Exit 0 — рівно 6 частин, кожна — один шматок; exit 1 — якась частина відсутня, злиплася чи розірвана.
"""
import argparse
import itertools
import json
import os

from PIL import Image

NAMES = ["body", "jaw", "thigh", "shin", "tent", "hook"]


def components(alpha, thr):
    w, h = alpha.size
    px = alpha.load()
    seen = bytearray(w * h)
    out = []
    for y0 in range(h):
        for x0 in range(w):
            if seen[y0 * w + x0] or px[x0, y0] <= thr:
                continue
            stack, pts = [(x0, y0)], []
            seen[y0 * w + x0] = 1
            while stack:
                x, y = stack.pop()
                pts.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and px[nx, ny] > thr:
                        seen[ny * w + nx] = 1
                        stack.append((nx, ny))
            out.append(pts)
    return out


def bbox(pts):
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def main():
    ap = argparse.ArgumentParser(
        description="Рахує й вирізає 6 частин lasher з аркуша Codex, зіставляє з шаблоном частин.",
        epilog="Приклад: python3 lasher_parts_cut.py lasher_parts_sheet.png --template lasher_parts_template.json "
               "--out parts   Exit 0 — 6 частин по одному шматку; exit 1 — ні.",
    )
    ap.add_argument("sheet", help="PNG аркуша частин (прозорий фон)")
    ap.add_argument("--template", required=True, help="lasher_parts_template.json")
    ap.add_argument("--out", required=True, help="папка для lasher_<частина>.png")
    ap.add_argument("--min-area", type=int, default=1500, help="площа великого шматка, px (за замовчуванням 1500)")
    ap.add_argument("--merge", type=int, default=40, help="макс. відстань дрібного шматка до великого, px (40)")
    args = ap.parse_args()

    im = Image.open(args.sheet).convert("RGBA")
    tpl = json.load(open(args.template))["parts"]
    comps = components(im.split()[3], 40)
    big = [c for c in comps if len(c) >= args.min_area]
    small = [c for c in comps if 20 <= len(c) < args.min_area]
    groups = [list(c) for c in big]
    boxes = [bbox(c) for c in big]
    for c in small:
        bx = bbox(c)
        best, dist = None, None
        for i, b in enumerate(boxes):
            dx = max(b[0] - bx[2], bx[0] - b[2], 0)
            dy = max(b[1] - bx[3], bx[1] - b[3], 0)
            dd = max(dx, dy)
            if dist is None or dd < dist:
                best, dist = i, dd
        if best is not None and dist <= args.merge:
            groups[best].extend(c)

    # частина ↔ шматок один до одного з найменшою сумою квадратів відстаней між центрами прямокутників
    # (Codex зсуває частини на 100–200 px, тож «найближчий» по одному плутає сусідів)
    found = {n: [] for n in NAMES}
    stray = []
    centers = {n: ((tpl[n]["box"][0] + tpl[n]["box"][2]) / 2, (tpl[n]["box"][1] + tpl[n]["box"][3]) / 2) for n in NAMES}
    gc = []
    for g in groups:
        x0, y0, x1, y1 = bbox(g)
        gc.append(((x0 + x1) / 2, (y0 + y1) / 2))
    if len(groups) == len(NAMES):
        best = min(itertools.permutations(range(len(groups))),
                   key=lambda perm: sum((centers[n][0] - gc[perm[i]][0]) ** 2 + (centers[n][1] - gc[perm[i]][1]) ** 2
                                        for i, n in enumerate(NAMES)))
        for i, n in enumerate(NAMES):
            found[n].append(groups[best[i]])
    else:
        print(f"великих шматків {len(groups)}, а частин {len(NAMES)}")
        stray = groups

    os.makedirs(args.out, exist_ok=True)
    ok = True
    src = im.load()
    print("частина  шматків  розмір      центр")
    for n in NAMES:
        gs = found[n]
        if len(gs) != 1:
            ok = False
        if not gs:
            print(f"{n:<8} 0        —")
            continue
        pts = [p for g in gs for p in g]
        x0, y0, x1, y1 = bbox(pts)
        part = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
        pp = part.load()
        for x, y in pts:
            pp[x - x0, y - y0] = src[x, y]
        part.save(os.path.join(args.out, f"lasher_{n}.png"))
        print(f"{n:<8} {len(gs):<8} {x1 - x0}x{y1 - y0:<6} ({(x0 + x1) // 2}, {(y0 + y1) // 2})")
    if stray:
        ok = False
        print("поза місцями шаблону:", [bbox(g) for g in stray])
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
