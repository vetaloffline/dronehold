"""Pose template for 8 drone views: 3x3 sheet, cell = compass direction of the heading.
Heading azimuth on the ground: 0 = right, 90 = towards the camera (down), like TurretRig.
Camera: ground y squashed by K = 0.75, height drawn up by H = sqrt(1 - K^2)."""
import math, sys
from PIL import Image, ImageDraw

K = 0.75
H = math.sqrt(1 - K * K)
CELL = 420
S = 70  # px per model unit
CELLS = {0: (2, 1), 45: (2, 2), 90: (1, 2), 135: (0, 2), 180: (0, 1), 225: (0, 0), 270: (1, 0), 315: (2, 0)}

def boxes():
    # (centre x along heading, centre y across, z bottom, half len, half width, height, colour tag)
    out = [(0.0, 0.0, 0.25, 0.85, 0.42, 0.38, "body")]
    for fx in (-0.62, 0.62):
        for fy in (-0.78, 0.78):
            out.append((fx, fy, 0.18, 0.28, 0.24, 0.42, "pod"))
    out.append((0.98, 0.0, 0.33, 0.14, 0.2, 0.2, "nose"))  # front marker (the headlight side)
    return out

def project(p, az, cx, cy):
    x, y, z = p
    a = math.radians(az)
    gx = x * math.cos(a) - y * math.sin(a)
    gy = x * math.sin(a) + y * math.cos(a)
    return (cx + gx * S, cy + gy * S * K - z * S * H)

def depth(p, az):
    x, y, z = p
    a = math.radians(az)
    return x * math.sin(a) + y * math.cos(a) + z * 0.01  # further down on screen = nearer

COL = {"body": (200, 200, 200), "pod": (150, 150, 150), "nose": (230, 40, 40)}

def draw_box(d, b, az, cx, cy):
    x0, y0, z0, hl, hw, h, tag = b
    c = COL[tag]
    xs = (x0 - hl, x0 + hl); ys = (y0 - hw, y0 + hw); zs = (z0, z0 + h)
    v = lambda i, j, k: (xs[i], ys[j], zs[k])
    faces = [  # (verts, shade)
        ([v(0,0,1), v(1,0,1), v(1,1,1), v(0,1,1)], 1.0),
        ([v(0,0,0), v(1,0,0), v(1,0,1), v(0,0,1)], 0.7),
        ([v(0,1,0), v(1,1,0), v(1,1,1), v(0,1,1)], 0.7),
        ([v(0,0,0), v(0,1,0), v(0,1,1), v(0,0,1)], 0.55),
        ([v(1,0,0), v(1,1,0), v(1,1,1), v(1,0,1)], 0.85 if tag != "nose" else 1.0),
    ]
    faces.sort(key=lambda f: sum(depth(p, az) for p in f[0]) / 4)
    for verts, sh in faces:
        col = tuple(int(ch * sh) for ch in c)
        if tag == "body" and verts == faces[-1][0]:
            pass
        d.polygon([project(p, az, cx, cy) for p in verts], fill=col, outline=(60, 60, 60))

def main(out):
    img = Image.new("RGB", (CELL * 3, CELL * 3), (255, 255, 255))
    d = ImageDraw.Draw(img)
    for az, (cx_i, cy_i) in CELLS.items():
        cx = cx_i * CELL + CELL / 2
        cy = cy_i * CELL + CELL / 2 + 20
        # ground arrow along the heading
        a = math.radians(az)
        tip = (cx + math.cos(a) * S * 1.9, cy + math.sin(a) * S * 1.9 * K)
        d.line([(cx, cy), tip], fill=(230, 40, 40), width=6)
        bs = boxes()
        bs.sort(key=lambda b: depth((b[0], b[1], b[2]), az))
        for b in bs:
            draw_box(d, b, az, cx, cy)
        d.text((cx_i * CELL + 10, cy_i * CELL + 10), f"{az} deg", fill=(0, 0, 0))
    img.save(out)

main(sys.argv[1])
