"""Ріже аркуш смерті від Codex (сітка 3×2 по 512 px, 5 кадрів) на кадри й робить превʼю для перевірки.

Пише в --out: <name>_f0.png … _f4.png (кадр 512×512, прозорий), <name>_cells.png (кадри на фіолетовій землі
гри з контуром шаблону червоним і хрестиком pivot), <name>.gif (кадри по --ms мс, останній стоїть 600 мс).
Друкує для кожного кадру: рамку альфи, відступ від краю клітинки, IoU з шаблоном, пікселі в 6-й клітинці.

Приклад:
  python3 death_cut.py --sheet slime_death_v1.png --template slime_death_template.png \\
      --json slime_death_template.json --name slime_death_v1 --out cut_v1
Exit: 0 — порізано; 1 — нема файлу або аркуш не 1536×1024.
"""
import argparse
import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

GROUND = (74, 40, 92, 255)    # фіолетова заражена земля гри (як у sprite_check.py, на око)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sheet", required=True, help="аркуш від Codex, PNG 1536×1024 з прозорістю")
    ap.add_argument("--template", required=True, help="шаблон (PNG) для накладки контуру й IoU")
    ap.add_argument("--json", required=True, help="JSON шаблону: cols, cell, frames, pivot_in_cell")
    ap.add_argument("--name", required=True, help="префікс вихідних файлів")
    ap.add_argument("--out", required=True, help="папка для кадрів і превʼю (створюється)")
    ap.add_argument("--ms", type=int, default=90, help="тривалість кадру в GIF, мс (90)")
    args = ap.parse_args()
    for p in (args.sheet, args.template, args.json):
        if not os.path.exists(p):
            print("нема", p)
            return 1
    meta = json.load(open(args.json))
    sheet = Image.open(args.sheet).convert("RGBA")
    if sheet.size != tuple(meta["size"]):
        print("розмір аркуша", sheet.size, "≠", meta["size"])
        return 1
    tpl = Image.open(args.template).convert("L")
    os.makedirs(args.out, exist_ok=True)
    cols, cell, n = meta["cols"], meta["cell"], meta["frames"]
    pv = meta["pivot_in_cell"]
    frames, previews = [], []
    for f in range(n + 1):
        ox, oy = (f % cols) * cell, (f // cols) * cell
        fr = sheet.crop((ox, oy, ox + cell, oy + cell))
        a = np.array(fr)[..., 3]
        if f == n:
            print(f"клітинка 6 (має бути порожня): пікселів alpha>128 = {int((a > 128).sum())}")
            break
        box = Image.fromarray(((a > 128) * 255).astype(np.uint8)).getbbox()
        # Шаблон: темні лінії → заповнена фігура (грубо: закрити контури й залити) — для IoU беремо
        # тільки рамку ліній, тож IoU тут — рамок, не силуетів.
        t = np.array(tpl.crop((ox, oy, ox + cell, oy + cell)))
        tl = (t < 120)
        ty, tx = np.nonzero(tl)
        tbox = (tx.min(), ty.min(), tx.max() + 1, ty.max() + 1) if len(tx) else None
        iou = None
        if box and tbox:
            ix = max(0, min(box[2], tbox[2]) - max(box[0], tbox[0])) * max(0, min(box[3], tbox[3]) - max(box[1], tbox[1]))
            ua = (box[2] - box[0]) * (box[3] - box[1]) + (tbox[2] - tbox[0]) * (tbox[3] - tbox[1]) - ix
            iou = ix / ua
        margin = (box[0], box[1], cell - box[2], cell - box[3]) if box else None
        print(f"кадр {f}: альфа {box}, шаблон {tbox}, IoU рамок {iou:.2f}" if iou is not None else f"кадр {f}: альфа {box}",
              f"відступ л/в/п/н {margin}")
        fr.save(os.path.join(args.out, f"{args.name}_f{f}.png"))
        frames.append(fr)
        pre = Image.new("RGBA", (cell, cell), GROUND)
        pre.alpha_composite(fr)
        edge = Image.fromarray((tl * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))
        pre.paste((255, 40, 40, 255), (0, 0), edge.point(lambda v: 110 if v else 0))
        d = ImageDraw.Draw(pre)
        d.line((pv[0] - 10, pv[1], pv[0] + 10, pv[1]), fill=(255, 255, 0, 255), width=2)
        d.line((pv[0], pv[1] - 10, pv[0], pv[1] + 10), fill=(255, 255, 0, 255), width=2)
        d.text((8, 8), str(f), fill=(255, 255, 255, 255))
        previews.append(pre)
    strip = Image.new("RGBA", (cell * len(previews), cell))
    for i, p in enumerate(previews):
        strip.paste(p, (i * cell, 0))
    strip.save(os.path.join(args.out, f"{args.name}_cells.png"))
    gif = []
    for fr in frames:
        g = Image.new("RGBA", (cell, cell), GROUND)
        g.alpha_composite(fr)
        gif.append(g.convert("RGB"))
    gif[0].save(os.path.join(args.out, f"{args.name}.gif"), save_all=True, append_images=gif[1:],
                duration=[args.ms] * (len(gif) - 1) + [600], loop=0)
    print("ok", args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
