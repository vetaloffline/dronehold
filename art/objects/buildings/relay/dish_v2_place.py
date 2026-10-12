"""Place measured dish views into the template frame (hinge at the housing) and build a sheet.

    python3 dish_v2_place.py KK [KK ...]   -> placed/relay_dish_KK.png, placed_sheet.png

Uses measure/relay_dish_KK_v*.json (latest version): the whole sprite (dish + strut + hinge together) is
scaled by 1/scale and shifted so the fitted model lands on the template; one uniform transform per view,
so the dish keeps its own proportions and every view ends up at the model size. The sheet shows each
placed view on a mock spire, all at the same scale, with the measured numbers.
"""
import glob
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dish_v2_template as T  # noqa: E402


def latest(k):
    """The best attempt of view k (smallest measured angle error)."""
    js = sorted(glob.glob(os.path.join(HERE, "measure", f"relay_dish_{k:02d}_v*.json")))
    ms = [json.load(open(j)) for j in js]
    return min(ms, key=lambda m: abs(m["err"])) if ms else None


def place(m):
    cut = Image.open(m["cut"]).convert("RGBA")
    f = T.SIZE / cut.width
    canvas = Image.new("RGBA", (T.SIZE, T.SIZE), (0, 0, 0, 0))
    canvas.paste(cut.resize((T.SIZE, round(cut.height * f)), Image.LANCZOS), (0, 0))
    s = m["scale"]
    hx, hy = T.ORIGIN[0] + m["shift"][0], T.ORIGIN[1] + m["shift"][1]
    big = canvas.resize((round(T.SIZE / s), round(T.SIZE / s)), Image.LANCZOS)
    out = Image.new("RGBA", (T.SIZE, T.SIZE), (0, 0, 0, 0))
    out.paste(big, (round(T.ORIGIN[0] - hx / s), round(T.ORIGIN[1] - hy / s)), big)
    return out


def main():
    ks = [int(a) for a in sys.argv[1:]] or list(range(16))
    os.makedirs(os.path.join(HERE, "placed"), exist_ok=True)
    cell, font = 360, ImageFont.load_default()
    cols = 4
    rows_n = (len(ks) + cols - 1) // cols
    sheet = Image.new("RGB", (cell * cols, (cell + 44) * rows_n), (245, 245, 245))
    for i, k in enumerate(ks):
        m = latest(k)
        if not m:
            continue
        p = place(m)
        p.save(os.path.join(HERE, "placed", f"relay_dish_{k:02d}.png"))
        bg = Image.new("RGBA", (T.SIZE, T.SIZE), (232, 232, 232, 255))
        T.mock_tower(bg)
        im = Image.alpha_composite(bg, p).convert("RGB").resize((cell, cell), Image.LANCZOS)
        x, y = (i % cols) * cell, (i // cols) * (cell + 44)
        sheet.paste(im, (x, y))
        d = ImageDraw.Draw(sheet)
        col = (0, 0, 0) if m["ok"] else (200, 0, 0)
        d.text((x + 8, y + cell + 6), f"#{k + 1} target {m['target']} measured {m['measured']} ({m['err']:+})",
               fill=col, font=font)
        d.text((x + 8, y + cell + 22), f"Codex zoom {m['scale']}  shift {m['shift']}  IoU {m['iou_fit']}",
               fill=col, font=font)
    sheet.save(os.path.join(HERE, "placed_sheet.png"))
    print("sheet:", os.path.join(HERE, "placed_sheet.png"))


if __name__ == "__main__":
    main()
