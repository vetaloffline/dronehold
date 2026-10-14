"""Прибирає з parts/lasher_body.png червоне кільце-гніздо ззаду тіла (Codex домалював зайве гніздо, на тілі
воно читалося як обрубок хвоста; людина 2026-10-14).

Кільце займає y ≈ 228…322 і x 0…66 (заміряно по рядках альфи); пластини над і під ним не чіпаються.
Зріз — опукла дуга: x(y) = cut − bulge·√(1 − ((y − yc) / r)²), зліва від неї все прозоре, по дузі —
темне обведення --edge px, як у решти контуру. Плоть закінчується заокругленим краєм, а не рівним зрізом.
Запускати на сирій частині (lasher_parts_cut.py з lasher_parts_sheet.png): вдруге дуга обведення зсунеться.
"""
import argparse
import math
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUTLINE = (24, 16, 14, 255)


def main():
    ap = argparse.ArgumentParser(
        description="Відрізає кільце-гніздо ззаду тіла lasher опуклою дугою й обводить зріз.",
        epilog="Приклад: python3 lasher_body_fix.py   Exit 0 — файл записано.",
    )
    ap.add_argument("--body", default=os.path.join(HERE, "parts", "lasher_body.png"),
                    help="PNG тіла (за замовчуванням parts/lasher_body.png; перезаписується)")
    ap.add_argument("--cut", type=float, default=62.0, help="x дуги на її кінцях, px частини (62)")
    ap.add_argument("--bulge", type=float, default=12.0, help="наскільки дуга виступає вліво посередині, px (12)")
    ap.add_argument("--yc", type=float, default=276.5, help="y середини кільця, px (276.5)")
    ap.add_argument("--r", type=float, default=50.5, help="пів висоти смуги зрізу, px (50.5: y 226…327)")
    ap.add_argument("--edge", type=int, default=4, help="товщина обведення по зрізу, px (4)")
    args = ap.parse_args()

    im = Image.open(args.body).convert("RGBA")
    px = im.load()
    w, h = im.size
    removed = 0
    for y in range(int(args.yc - args.r), int(args.yc + args.r) + 1):
        if y < 0 or y >= h:
            continue
        u = (y - args.yc) / args.r
        xb = int(round(args.cut - args.bulge * math.sqrt(max(0.0, 1.0 - u * u))))
        for x in range(0, min(xb, w)):
            if px[x, y][3] > 0:
                px[x, y] = (0, 0, 0, 0)
                removed += 1
        if xb < w and px[xb, y][3] > 128:
            for x in range(xb, min(xb + args.edge, w)):
                px[x, y] = OUTLINE
    im.save(args.body)
    print(f"прибрано {removed} px, {args.body}")


if __name__ == "__main__":
    main()
