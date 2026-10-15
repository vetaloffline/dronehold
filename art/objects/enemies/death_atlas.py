"""Атлас смерті слизня з аркуша Codex.

Аркуш смерті (slime/slime_death_sheet.png): 1536×1024, сітка 3×2 по 512 px, 5 кадрів, 6-та клітинка порожня.
Позиції в кадрах Codex тримає узгоджено, тож кадри ріжуться без зсуву: кожен — своя клітинка (кадр зліва від
порожньої клітинки береться ширшим на SPILL px), усі на одне полотно = об'єднання рамок альфи.

Прив'язка до живого слизня: рамка альфи кадру 0 лягає на рамку живого спрайта (ширина й середина низу) — кадр 0
slime_skins.png (скін a), точка опори — pivot з game/objects/slime/slime_rig.tres. Звідси точка опори атласу
смерті і `px_scale` — скільки px атласу живого в 1 px атласу смерті (у грі масштаб трупа = map_scale() × px_scale).

Lasher (кривава смерть і кінцівки з рваними зрізами) — lasher/lasher_gore_build.py.

Приклад: python3 death_atlas.py
Пише: slime/slime_death_atlas.png + .json; друкує значення для slime_death_rig.tres. Exit 0 — готово, 1 — нема файлу.
"""
import argparse
import json
import os
import re

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CELL, COLS, FRAMES = 512, 3, 5
SPILL = 64
PAD = 6


def alpha_box(im, thr=128):
    a = np.asarray(im)[..., 3] > thr
    ys, xs = np.nonzero(a)
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1) if len(xs) else None


def slime_living():
    skins = Image.open(os.path.join(HERE, "slime/slime_skins.png")).convert("RGBA")
    frame_w = 1064                                             # SlimeRig.frame_w (slime_skins.py)
    box = alpha_box(skins.crop((0, 0, frame_w, skins.height)))
    tres = open(os.path.join(REPO, "game/objects/slime/slime_rig.tres")).read()
    m = re.search(r"^pivot = Vector2\(([-\d.]+), ([-\d.]+)\)", tres, re.M)
    return box, (float(m.group(1)), float(m.group(2)))


def build_death(name, sheet_path, out_png, living, out_scale):
    sheet = Image.open(sheet_path).convert("RGBA")
    living_box, living_pivot = living
    crops, boxes = [], []
    for f in range(FRAMES):
        x0, y0 = (f % COLS) * CELL, (f // COLS) * CELL
        x1 = x0 + CELL + (SPILL if f + 1 == FRAMES and (f + 1) % COLS != 0 else 0)
        fr = sheet.crop((x0, y0, x1, y0 + CELL))
        crops.append(fr)
        boxes.append(alpha_box(fr))
    u = (min(b[0] for b in boxes) - PAD, min(b[1] for b in boxes) - PAD,
         max(b[2] for b in boxes) + PAD, max(b[3] for b in boxes) + PAD)
    fw, fh = round((u[2] - u[0]) * out_scale), round((u[3] - u[1]) * out_scale)
    atlas = Image.new("RGBA", (fw * FRAMES, fh), (0, 0, 0, 0))
    for f, fr in enumerate(crops):
        canvas = Image.new("RGBA", (u[2] - u[0], u[3] - u[1]), (0, 0, 0, 0))
        canvas.alpha_composite(fr.crop((max(0, u[0]), max(0, u[1]), min(fr.width, u[2]), min(fr.height, u[3]))),
                               (max(0, -u[0]), max(0, -u[1])))
        atlas.paste(canvas.resize((fw, fh), Image.LANCZOS), (f * fw, 0))
    atlas.save(out_png)
    # Кадр 0 → живий спрайт: ширина і середина низу рамки альфи.
    b0 = boxes[0]
    s = (living_box[2] - living_box[0]) / (b0[2] - b0[0])          # px живого на px аркуша
    lc = ((living_box[0] + living_box[2]) / 2, living_box[3])
    pc = ((b0[0] + b0[2]) / 2 + (living_pivot[0] - lc[0]) / s, b0[3] + (living_pivot[1] - lc[1]) / s)
    pivot = [round((pc[0] - u[0]) * out_scale, 1), round((pc[1] - u[1]) * out_scale, 1)]
    meta = {"frames": FRAMES, "cols": FRAMES, "rows": 1, "frame_w": fw, "frame_h": fh, "pivot": pivot,
            "px_scale": round(s / out_scale, 4),
            "frame_boxes": [[round((b[i] - u[i % 2]) * out_scale) for i in range(4)] for b in boxes]}
    json.dump(meta, open(os.path.splitext(out_png)[0] + ".json", "w"), indent=1)
    print(name, "атлас", atlas.size, {k: v for k, v in meta.items() if k != "frame_boxes"})
    return meta


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--slime-scale", type=float, default=0.5,
                    help="px атласу смерті слизня на px аркуша Codex (0.5: кадр ~255 px, живий слизень у грі ~26 px)")
    args = ap.parse_args()
    for p in ["slime/slime_death_sheet.png", "slime/slime_skins.png"]:
        if not os.path.exists(os.path.join(HERE, p)):
            print("нема", p)
            return 1
    build_death("slime", os.path.join(HERE, "slime/slime_death_sheet.png"),
                os.path.join(HERE, "slime/slime_death_atlas.png"), slime_living(), args.slime_scale)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
