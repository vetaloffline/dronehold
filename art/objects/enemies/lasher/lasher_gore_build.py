#!/usr/bin/env python3
"""Атлас кривавої смерті lasher і атлас кінцівок-уламків з рваними зрізами (апрув людини 2026-10-14, веб-превʼю).

Аркуш смерті (lasher_death_sheet.png, Codex, спроба 2): 1536×1024, сітка 3×2 по 512 px, 5 кадрів. Кров кадру 0
заходить у клітинку 1, тож кадри ріжуться не клітинками, а зв'язними шматками: кожен шматок (alpha > CLEAN) — у
клітинку, де більшість його пікселів; alpha ≤ CLEAN стирається (ледь видимі лінії сітки від Codex). Кадри — на
одне полотно (об'єднання рамок) і в масштаб атласу бігу: ширина рамки НЕ червоних пікселів кадру 0 (броня, кістка)
= та сама ширина тіла (parts/lasher_body.png × 0,255 у (33, 47)). Codex перемалював тіло, тож рамки замало:
поправка FIT_SCALE / FIT_DX заміряна підбором за кольором проти кадру 0 бігу (масштаб 1,14, зсув +16 px, середня
різниця 44 з 255) → px_scale = FIT_SCALE.

Кінцівки (lasher_limbs_gore_sheet.png, Codex precise-object-edit): частини з parts/ лежали на полотні 1536×1024 у
LIMBS (лівий верхній кут), Codex зробив рвані криваві зрізи, розкладку не зрушив (2–6 px). Кожен шматок — до
найближчої рамки частини. Розмір як на живому lasher (lasher_run_build.py): лапи ×0,85, гак ×0,85, щелепа ×0,48;
щупальце на тілі — дуга 555…648 px з 1008 px смуги → довжина ×0,6, товщина ×0,95, і воно розрізане навпіл між
4-м і 5-м шипом (TENT_CUT); на кожен кінець розрізу ставиться рваний зріз з основи, зменшений під товщину там.

Приклад: python3 lasher_gore_build.py            (пише поруч)
         python3 lasher_gore_build.py --out $TMPDIR/x
Пише: lasher_death_atlas.png + .json, lasher_pieces_atlas.png + .json; друкує значення для
game/objects/lasher/lasher_death_rig.tres. Exit 0 — готово, 1 — нема вхідного файлу.
"""
import argparse
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
FIT_SCALE, FIT_DX = 1.14, 16.0     # підбір за кольором кадру 0 проти кадру 0 бігу (див. опис)
CELL, COLS, FRAMES = 512, 3, 5
CLEAN = 24
PAD = 6
BODY_K, BODY_AT = 0.255, (33, 47)
LIMBS = {"tent": (248, 60), "thigh": (80, 330), "shin": (560, 300), "hook": (1150, 300), "jaw": (560, 700)}
# Size as on the living lasher (lasher_run_build.py): legs 0.85 (thigh drawn 331 px, on the body ≤ 279;
# thickness 0.8 there), hook 0.85, jaw 0.48. The tentacle on the body is a 555…648 px arc of the 1008 px
# strip → length 0.6, thickness 0.95, and it is cut in two (base / tip) with a torn stump on each cut end.
LIMB_MULT = {"thigh": 0.85, "shin": 0.85, "hook": 0.85, "jaw": 0.48}
TENT_LEN, TENT_THICK = 0.6, 0.95
TENT_CUT = 808            # sheet x between the 4th and 5th spike: tube 146…210 (64 px)
TENT_BASE_COL = 330       # sheet x just after the stump: tube 91…208 (117 px)
STUMP = (210, 315)        # sheet x of the torn stump drawn by Codex at the base
ORDER = ["thigh", "shin", "tent_base", "tent_tip", "hook", "jaw"]


def box_of(mask):
    ys, xs = np.nonzero(mask)
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1) if len(xs) else None


def non_red(arr):
    r, g, b, a = [arr[..., i].astype(int) for i in range(4)]
    red = (r > g + 70) & (r > b + 50)
    return (a > 128) & ~red


def split(img, owner_of):
    """Wipe faint alpha, label pieces, give each to owner_of(ys, xs) -> key. Returns {key: RGBA array}."""
    arr = np.array(img.convert("RGBA"))
    arr[arr[..., 3] <= CLEAN] = 0
    lab, n = ndimage.label(arr[..., 3] > 0, structure=np.ones((3, 3)))
    out = {}
    objs = ndimage.find_objects(lab)
    for i, sl in enumerate(objs, 1):
        m = lab[sl] == i
        ys, xs = np.nonzero(m)
        key = owner_of(ys + sl[0].start, xs + sl[1].start)
        if key is None:
            continue
        dst = out.setdefault(key, np.zeros_like(arr))
        dst[sl][m] = arr[sl][m]
    return out


def build_death(sheet_path, out):
    sheet = Image.open(sheet_path)

    def owner(ys, xs):
        cells = (ys // CELL) * COLS + xs // CELL
        f = int(np.bincount(cells).argmax())
        return f if f < FRAMES else None

    parts = split(sheet, owner)
    crops, boxes = [], []
    for f in range(FRAMES):
        ox, oy = (f % COLS) * CELL, (f // COLS) * CELL
        a = parts[f]
        bx = box_of(a[..., 3] > 0)
        crops.append((a, ox, oy))
        boxes.append((bx[0] - ox, bx[1] - oy, bx[2] - ox, bx[3] - oy))
    u = (min(b[0] for b in boxes) - PAD, min(b[1] for b in boxes) - PAD,
         max(b[2] for b in boxes) + PAD, max(b[3] for b in boxes) + PAD)
    # Living body box by non-red pixels, in run-atlas px.
    body = np.array(Image.open(os.path.join(HERE, "parts/lasher_body.png")).convert("RGBA"))
    lb = box_of(non_red(body))
    living = (BODY_AT[0] + lb[0] * BODY_K, BODY_AT[1] + lb[1] * BODY_K,
              BODY_AT[0] + lb[2] * BODY_K, BODY_AT[1] + lb[3] * BODY_K)
    a0 = crops[0][0][0:CELL, 0:CELL]
    b0 = box_of(non_red(a0))
    s = (living[2] - living[0]) / (b0[2] - b0[0])   # run-atlas px per sheet px
    fw, fh = round((u[2] - u[0]) * s), round((u[3] - u[1]) * s)
    atlas = Image.new("RGBA", (fw * FRAMES, fh), (0, 0, 0, 0))
    big = Image.new("RGBA", (1536 + 2 * CELL, 1024 + 2 * CELL), (0, 0, 0, 0))
    for f, (a, ox, oy) in enumerate(crops):
        im = big.copy()
        im.paste(Image.fromarray(a), (CELL, CELL))
        fr = im.crop((CELL + ox + u[0], CELL + oy + u[1], CELL + ox + u[2], CELL + oy + u[3]))
        atlas.paste(fr.resize((fw, fh), Image.LANCZOS), (f * fw, 0))
    atlas.save(os.path.join(out, "lasher_death_atlas.png"))
    meta = json.load(open(os.path.join(HERE, "lasher_run_atlas.json")))
    lp = meta["pivot"]
    lc = ((living[0] + living[2]) / 2, living[3])
    pc = ((b0[0] + b0[2]) / 2 + (lp[0] - lc[0]) / s, b0[3] + (lp[1] - lc[1]) / s)
    res = {"frames": FRAMES, "cols": FRAMES, "rows": 1, "frame_w": fw, "frame_h": fh,
           "pivot": [round((pc[0] - u[0]) * s - FIT_DX / FIT_SCALE, 1), round((pc[1] - u[1]) * s, 1)],
           "px_scale": FIT_SCALE, "sheet_scale": round(s, 4)}
    with open(os.path.join(out, "lasher_death_atlas.json"), "w") as f:
        json.dump(res, f, indent=1)
        f.write("\n")
    print("смерть", atlas.size, res)


def build_limbs(limbs_path, out):
    gen = Image.open(limbs_path)
    boxes = {}
    for name, (x, y) in LIMBS.items():
        w, h = Image.open(os.path.join(HERE, f"parts/lasher_{name}.png")).size
        boxes[name] = (x, y, x + w, y + h)

    def owner(ys, xs):
        cy, cx = ys.mean(), xs.mean()
        best, bd = None, 1e9
        for name, (x0, y0, x1, y1) in boxes.items():
            dx = max(x0 - cx, 0, cx - x1)
            dy = max(y0 - cy, 0, cy - y1)
            d = dx * dx + dy * dy
            if d < bd:
                best, bd = name, d
        return best if bd < 120 ** 2 else None

    parts = split(gen, owner)
    ims = []
    for name, im in tentacle_halves(parts["tent"]):
        ims.append((name, im.resize((max(1, round(im.width * BODY_K * TENT_LEN)), max(1, round(im.height * BODY_K * TENT_THICK))), Image.LANCZOS)))
    for name in ORDER:
        if name.startswith("tent"):
            continue
        a = parts[name]
        bx = box_of(a[..., 3] > 0)
        im = Image.fromarray(a).crop(bx)
        k = BODY_K * LIMB_MULT[name]
        ims.append((name, im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)))
    ims.sort(key=lambda t: ORDER.index(t[0]))
    gap = 8
    atlas = Image.new("RGBA", (sum(p.width for _, p in ims) + gap * (len(ims) + 1),
                               max(p.height for _, p in ims) + 2 * gap), (0, 0, 0, 0))
    rects, x = {}, gap
    for name, p in ims:
        atlas.paste(p, (x, gap))
        rects[name] = [x, gap, p.width, p.height]
        x += p.width + gap
    atlas.save(os.path.join(out, "lasher_pieces_atlas.png"))
    with open(os.path.join(out, "lasher_pieces_atlas.json"), "w") as f:
        json.dump({"rects": rects, "order": ORDER}, f, indent=1)
        f.write("\n")
    print("уламки", atlas.size, rects)


def tube(a, x):
    ys = np.nonzero(a[:, x, 3] > 128)[0]
    return (ys.min() + ys.max()) / 2, ys.max() - ys.min()


def tentacle_halves(a):
    """Cut the full-res tentacle (sheet coords) at TENT_CUT; each cut end gets the Codex stump scaled to the
    tube there (tip: stump as drawn on its left end; base: mirrored on its right end)."""
    full = Image.fromarray(a)
    stump = full.crop((STUMP[0], 0, STUMP[1], a.shape[0]))
    c_base, t_base = tube(a, TENT_BASE_COL)
    c_cut, t_cut = tube(a, TENT_CUT)
    k = t_cut / t_base
    st = stump.resize((max(1, round(stump.width * k)), max(1, round(stump.height * k))), Image.LANCZOS)
    st_cy = c_base * k                       # tube centre inside the scaled stump
    over = round(st.width * 0.35)            # the stump's right part overlaps the tube
    ys = np.nonzero(a[..., 3] > 0)[0]
    y0, y1 = int(ys.min()) - 40, int(ys.max()) + 40
    xs = np.nonzero(a[..., 3].any(axis=0))[0]
    x_end = int(xs.max()) + 1
    # tip: [cut, end), stump on the left
    tip = Image.new("RGBA", (x_end - TENT_CUT + st.width - over, y1 - y0), (0, 0, 0, 0))
    tip.alpha_composite(full.crop((TENT_CUT, y0, x_end, y1)), (st.width - over, 0))
    tip.alpha_composite(st, (0, round(c_cut - y0 - st_cy)))
    # base: [start, cut), mirrored stump on the right
    x_start = int(xs.min())
    base = Image.new("RGBA", (TENT_CUT - x_start + st.width - over, y1 - y0), (0, 0, 0, 0))
    base.alpha_composite(full.crop((x_start, y0, TENT_CUT, y1)), (0, 0))
    base.alpha_composite(st.transpose(Image.FLIP_LEFT_RIGHT), (TENT_CUT - x_start - over, round(c_cut - y0 - st_cy)))
    out = []
    for name, im in (("tent_base", base), ("tent_tip", tip)):
        out.append((name, im.crop(box_of(np.array(im)[..., 3] > 0))))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sheet", default=os.path.join(HERE, "lasher_death_sheet.png"),
                    help="аркуш смерті від Codex, 1536×1024 (за замовчуванням lasher_death_sheet.png поруч)")
    ap.add_argument("--limbs", default=os.path.join(HERE, "lasher_limbs_gore_sheet.png"),
                    help="кінцівки з рваними зрізами від Codex (за замовчуванням lasher_limbs_gore_sheet.png поруч)")
    ap.add_argument("--out", default=HERE, help="папка для атласів (за замовчуванням поруч зі скриптом)")
    a = ap.parse_args()
    for p in (a.sheet, a.limbs, os.path.join(HERE, "parts/lasher_body.png"), os.path.join(HERE, "lasher_run_atlas.json")):
        if not os.path.exists(p):
            print("нема", p)
            return 1
    os.makedirs(a.out, exist_ok=True)
    build_death(a.sheet, a.out)
    build_limbs(a.limbs, a.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
