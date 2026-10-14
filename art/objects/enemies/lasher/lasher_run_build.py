"""Збирає кадри бігу lasher з частин (parts/) за рухом моделі lasher_run_template.py.

Рух (стопи, коліна, підскок тіла, щупальця з інерцією, щелепа) — frame_geometry() шаблону, без змін.
Частини кладуться афінно: сегмент лапи — від шарніра до шарніра (поворот + довжина вздовж осі, товщина
стала), щупальце — скибками вздовж кривої Безьє, гак — на кінці щупальця по дотичній, щелепа — поворот
навколо шарніра. Масштаб і зсув «модель → пікселі частин» — за двома ближніми стегнами на тілі.

Шарніри частин заміряні на parts/ (центри темних дірок червоних кілець, lasher_parts_cut.py + пошук
дірок): див. RIG нижче. Гнізда дальніх лап і щупалець на тілі не намальовані — вони беруться з моделі.
"""
import argparse
import importlib.util
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))

RIG = {
    "body": {"near_rear": (178, 423), "near_front": (530, 476), "jaw_hinge": (670, 415),
             # основи щупалець — на спині за шипами (верх альфи на x=330 / 440 мінус ~100 px шипів)
             "tent_base": {"rear": (330, 150), "front": (440, 175)}},
    "jaw": {"pivot": (26, 46), "tip": (420, 100)},
    "thigh": {"pivot": (27, 92), "end": (358, 121)},
    "shin": {"pivot": (29, 83), "end": None},      # кінчик кігтя — найдальша точка альфи від шарніра
    "tent": {"pivot": (32, 85), "end": None},      # кінець — найправіша точка альфи
    "hook": {"pivot": (26, 49)},
}


def load_template():
    sys.dont_write_bytecode = True  # без __pycache__ поруч з артом
    spec = importlib.util.spec_from_file_location("tpl", os.path.join(HERE, "lasher_run_template.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def far_point(img, frm):
    a = img.split()[3].load()
    w, h = img.size
    best, bd = None, -1
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if a[x, y] > 128:
                d = (x - frm[0]) ** 2 + (y - frm[1]) ** 2
                if d > bd:
                    best, bd = (x, y), d
    return best


def right_point(img):
    a = img.split()[3].load()
    w, h = img.size
    for x in range(w - 1, -1, -1):
        ys = [y for y in range(h) if a[x, y] > 128]
        if ys:
            return (x, sum(ys) / len(ys))


def place(canvas, part, src_a, src_b, dst_a, dst_b, thick):
    """Кладе part так, що src_a→dst_a, src_b→dst_b; поперек осі масштаб thick."""
    sx, sy = src_b[0] - src_a[0], src_b[1] - src_a[1]
    dx, dy = dst_b[0] - dst_a[0], dst_b[1] - dst_a[1]
    ls, ld = math.hypot(sx, sy), math.hypot(dx, dy)
    us = (sx / ls, sy / ls)
    ud = (dx / ld, dy / ld)
    k = ld / ls
    # dst = dst_a + ud * (k * <p - src_a, us>) + nd * (thick * <p - src_a, ns>)
    ns = (-us[1], us[0])
    nd = (-ud[1], ud[0])
    # обернене: p = src_a + us * (<q - dst_a, ud> / k) + ns * (<q - dst_a, nd> / thick)
    a = ud[0] / k * us[0] + nd[0] / thick * ns[0]
    b = ud[1] / k * us[0] + nd[1] / thick * ns[0]
    d = ud[0] / k * us[1] + nd[0] / thick * ns[1]
    e = ud[1] / k * us[1] + nd[1] / thick * ns[1]
    c = src_a[0] - a * dst_a[0] - b * dst_a[1]
    f = src_a[1] - d * dst_a[0] - e * dst_a[1]
    out = part.transform(canvas.size, Image.AFFINE, (a, b, c, d, e, f), resample=Image.BICUBIC)
    canvas.alpha_composite(out)


def rot_place(canvas, part, pivot, dst, angle_deg, scale):
    rad = math.radians(angle_deg)
    u = (math.cos(rad), math.sin(rad))
    place(canvas, part, pivot, (pivot[0] + 100, pivot[1]), dst, (dst[0] + 100 * scale * u[0], dst[1] + 100 * scale * u[1]), scale)


def darken(img, f):
    r, g, b, a = img.split()
    rgb = ImageEnhance.Brightness(Image.merge("RGB", (r, g, b))).enhance(f)
    return Image.merge("RGBA", (*rgb.split(), a))


def bend_strip(canvas, strip, pivot, end, curve, thick, slices=60):
    """Гне рівну смугу (pivot→end по x) вздовж ламаної curve (точки на полотні)."""
    seg = [math.hypot(curve[i + 1][0] - curve[i][0], curve[i + 1][1] - curve[i][1]) for i in range(len(curve) - 1)]
    total = sum(seg)

    def at(t):
        s = t * total
        for i, L in enumerate(seg):
            if s <= L or i == len(seg) - 1:
                u = s / L if L else 0
                return (curve[i][0] + (curve[i + 1][0] - curve[i][0]) * u, curve[i][1] + (curve[i + 1][1] - curve[i][1]) * u)
            s -= L

    x0, x1 = pivot[0], end[0]
    for i in range(slices):
        t0, t1 = i / slices, min((i + 1.6) / slices, 1.0)
        sa = (x0 + (x1 - x0) * t0, pivot[1])
        sb = (x0 + (x1 - x0) * t1, pivot[1])
        box = (int(min(sa[0], sb[0])) - 2, 0, int(max(sa[0], sb[0])) + 2, strip.height)
        piece = Image.new("RGBA", strip.size, (0, 0, 0, 0))
        piece.paste(strip.crop(box), (box[0], 0))
        place(canvas, piece, sa, sb, at(t0), at(t1), thick)
    a, b = at(0.97), at(1.0)
    return b, math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))


def main():
    ap = argparse.ArgumentParser(
        description="Збирає кадри бігу lasher з частин за рухом lasher_run_template.py; пише кадри, GIF і аркуш.",
        epilog="Приклад: python3 lasher_run_build.py --out $TMPDIR/lasher_run --atlas lasher_run_atlas.png   "
               "(кадри повного розміру ~74 МБ — у --out, не в git; атлас — у git)   "
               "Exit 0 — готово.",
    )
    ap.add_argument("--parts", default=os.path.join(HERE, "parts"), help="папка з lasher_<частина>.png (за замовчуванням parts/ поруч)")
    ap.add_argument("--out", required=True, help="папка результату: lasher_run_NNN.png, lasher_run.gif, lasher_run_sheet.png")
    ap.add_argument("--frames", type=int, default=32, help="кадрів у циклі (32; апрув людини 2026-10-14)")
    ap.add_argument("--leg-thick", type=float, default=0.8, help="товщина сегментів лап проти намальованої (0.8)")
    ap.add_argument("--tent-thick", type=float, default=0.95, help="товщина щупальця проти намальованої (0.95)")
    ap.add_argument("--hook-scale", type=float, default=0.85, help="розмір гака проти намальованого (0.85)")
    ap.add_argument("--jaw-scale", type=float, default=0.48, help="розмір щелепи проти намальованої (0.48: ~200 px, як ряд верхніх зубів x 666…836)")
    ap.add_argument("--ms", type=int, default=50, help="мс на кадр у GIF (50: цикл 32 кадри = 1,6 с)")
    ap.add_argument("--atlas", default=None,
                    help="шлях PNG атласу для гри (сітка --atlas-cols, кадр --atlas-w px) + .json поруч; не задано — без атласу")
    ap.add_argument("--atlas-w", type=int, default=320, help="ширина кадру в атласі, px (320; рішення людини 2026-10-14)")
    ap.add_argument("--atlas-cols", type=int, default=8, help="колонок в атласі (8)")
    args = ap.parse_args()

    tpl = load_template()
    tpl.FRAMES = args.frames
    # дальні лапи: коліно менше назовні (назовні від камери = вгору на екрані → стирчало над спиною)
    knee0 = tpl.knee_pos
    tpl.knee_pos = lambda hip, foot, front, side: knee0(hip, foot, front, side if side > 0 else -0.35)
    P = {n: Image.open(os.path.join(args.parts, f"lasher_{n}.png")).convert("RGBA")
         for n in ("body", "jaw", "thigh", "shin", "tent", "hook")}
    shin_end = far_point(P["shin"], RIG["shin"]["pivot"])
    tent_end = right_point(P["tent"])

    # модель → пікселі: за двома ближніми стегнами (кадр без підскоку)
    g0 = tpl.frame_geometry(0)
    bob0 = g0["body"][1] - tpl.BODY_H
    def hip_model(name):
        h = g0["legs"][name]["hip"]
        return tpl.proj((h[0], h[1] - bob0, h[2]))
    m_r, m_f = hip_model("near_rear"), hip_model("near_front")
    b_r, b_f = RIG["body"]["near_rear"], RIG["body"]["near_front"]
    scale = math.hypot(b_f[0] - b_r[0], b_f[1] - b_r[1]) / math.hypot(m_f[0] - m_r[0], m_f[1] - m_r[1])
    ang_m = math.atan2(m_f[1] - m_r[1], m_f[0] - m_r[0])
    ang_b = math.atan2(b_f[1] - b_r[1], b_f[0] - b_r[0])
    print(f"масштаб модель→px {scale:.2f}, кут стегон модель {math.degrees(ang_m):.1f}° / тіло {math.degrees(ang_b):.1f}°")

    pad = 260
    W = P["body"].width + 2 * pad + 300
    H = P["body"].height + 2 * pad
    body_at = (pad, pad)

    def S(p):
        """модель (x, y, z) → полотно; тіло без підскоку стоїть у body_at."""
        sx, sy = tpl.proj(p)
        return (body_at[0] + b_r[0] + (sx - m_r[0]) * scale, body_at[1] + b_r[1] + (sy - m_r[1]) * scale)

    os.makedirs(args.out, exist_ok=True)
    frames = []
    far_thigh, far_shin = darken(P["thigh"], 0.62), darken(P["shin"], 0.62)
    far_tent, far_hook = darken(P["tent"], 0.75), darken(P["hook"], 0.75)
    for f in range(args.frames):
        g = tpl.frame_geometry(f)
        bob = g["body"][1] - tpl.BODY_H
        lift = (0, -bob * tpl.COS_E * scale)
        cv = Image.new("RGBA", (W, H), (0, 0, 0, 0))

        def leg(name, thigh, shin):
            lg = g["legs"][name]
            hip, knee, foot = S(lg["hip"]), S(lg["knee"]), S(lg["foot"])
            if name in ("near_rear", "near_front"):
                hip = (body_at[0] + RIG["body"][name][0] + lift[0], body_at[1] + RIG["body"][name][1] + lift[1])
            place(cv, thigh, RIG["thigh"]["pivot"], RIG["thigh"]["end"], hip, knee, args.leg_thick)
            place(cv, shin, RIG["shin"]["pivot"], shin_end, knee, foot, args.leg_thick)

        def tentacle(name, strip, hook):
            t = g["tentacles"][name]
            bm = S(t["base"])
            bb = RIG["body"]["tent_base"][name]
            base = (body_at[0] + bb[0] + lift[0], body_at[1] + bb[1] + lift[1])
            pts = [(base[0] + q[0] - bm[0], base[1] + q[1] - bm[1])
                   for q in (S(p) for p in tpl.bezier(t["base"], t["ctrl"], t["tip"], 30))]
            tip, ang = bend_strip(cv, strip, RIG["tent"]["pivot"], tent_end, pts, args.tent_thick)
            rot_place(cv, hook, RIG["hook"]["pivot"], tip, ang, args.hook_scale)

        tentacle("rear", far_tent, far_hook)
        leg("far_rear", far_thigh, far_shin)
        leg("far_front", far_thigh, far_shin)
        hinge = (body_at[0] + RIG["body"]["jaw_hinge"][0] + lift[0], body_at[1] + RIG["body"]["jaw_hinge"][1] + lift[1])
        rot_place(cv, P["jaw"], RIG["jaw"]["pivot"], hinge, 6 + 0.55 * g["mouth_deg"], args.jaw_scale)
        cv.alpha_composite(P["body"], (int(round(body_at[0] + lift[0])), int(round(body_at[1] + lift[1]))))
        leg("near_rear", P["thigh"], P["shin"])
        leg("near_front", P["thigh"], P["shin"])
        tentacle("front", P["tent"], P["hook"])
        frames.append(cv)

    box = None
    for fr in frames:
        b = fr.getbbox()
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    box = (box[0] - 8, box[1] - 8, box[2] + 8, box[3] + 8)
    gif = []
    for i, fr in enumerate(frames):
        c = fr.crop(box)
        c.save(os.path.join(args.out, f"lasher_run_{i:03d}.png"))
        bg = Image.new("RGBA", c.size, (58, 40, 72, 255))
        bg.alpha_composite(c)
        gif.append(bg.convert("RGB"))
    gif[0].save(os.path.join(args.out, "lasher_run.gif"), save_all=True, append_images=gif[1:], duration=args.ms, loop=0)
    small = [g.resize((g.width // 4, g.height // 4), Image.LANCZOS) for g in gif]
    small[0].save(os.path.join(args.out, "lasher_run_small.gif"), save_all=True, append_images=small[1:],
                  duration=args.ms, loop=0)
    cols = 4
    rows = (len(gif) + cols - 1) // cols
    sheet = Image.new("RGB", (gif[0].width * cols, gif[0].height * rows), (58, 40, 72))
    for i, gg in enumerate(gif):
        sheet.paste(gg, ((i % cols) * gg.width, (i // cols) * gg.height))
    sheet.save(os.path.join(args.out, "lasher_run_sheet.png"))
    print("кадр", gif[0].size, "→", args.out)
    if args.atlas:
        write_atlas(args, frames, box, S, scale, tpl)


def write_atlas(args, frames, box, S, scale, tpl):
    """Атлас для рою: кадри зменшені до --atlas-w, сітка --atlas-cols; JSON — що треба lasher_rig.tres."""
    fw = args.atlas_w
    k = fw / (box[2] - box[0])
    fh = int(round((box[3] - box[1]) * k))
    cols = args.atlas_cols
    rows = (len(frames) + cols - 1) // cols
    atlas = Image.new("RGBA", (fw * cols, fh * rows), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        small = fr.crop(box).resize((fw, fh), Image.LANCZOS)
        atlas.paste(small, ((i % cols) * fw, (i // cols) * fh))
    atlas.save(args.atlas)
    # точка опори = земля під центром тіла моделі (0, 0, 0), без підскоку
    g = S((0.0, 0.0, 0.0))
    pivot = [round((g[0] - box[0]) * k, 1), round((g[1] - box[1]) * k, 1)]
    # за цикл рисі тіло проходить 2 кроки (кожна пара лап пів циклу стоїть і відштовхує на STRIDE)
    stride_widths = 2.0 * tpl.STRIDE * scale / (box[2] - box[0])
    meta = {
        "frames": len(frames), "cols": cols, "rows": rows, "frame_w": fw, "frame_h": fh,
        "pivot": pivot, "period_s": round(len(frames) * args.ms / 1000.0, 3),
        "stride_widths": round(stride_widths, 4),
    }
    with open(os.path.splitext(args.atlas)[0] + ".json", "w") as fh_:
        json.dump(meta, fh_, indent=1)
    print("атлас", atlas.size, meta)


if __name__ == "__main__":
    main()
