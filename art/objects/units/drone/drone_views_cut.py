"""Cut the 3x3 drone sheet (white background) into 8 transparent views on one canvas,
each centred on the alpha centroid. Prints bbox sizes per view."""
import sys, os
from collections import deque
from PIL import Image
import numpy as np

src, out_dir = sys.argv[1], sys.argv[2]
img = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
H, W, _ = img.shape
cw, ch = W // 3, H // 3
CELLS = {0: (2, 1), 45: (2, 2), 90: (1, 2), 135: (0, 2), 180: (0, 1), 225: (0, 0), 270: (1, 0), 315: (2, 0)}

def cut(cell):
    x0, y0 = cell[0] * cw, cell[1] * ch
    c = img[y0:y0 + ch, x0:x0 + cw]
    h, w, _ = c.shape
    near_white = (c.min(axis=2) >= 232)
    # Background = near-white connected to the cell border.
    bg = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if near_white[y, x] and not bg[y, x]:
                bg[y, x] = True; q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if near_white[y, x] and not bg[y, x]:
                bg[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not bg[ny, nx] and near_white[ny, nx]:
                bg[ny, nx] = True; q.append((ny, nx))
    fg = ~bg
    # Largest connected component of the foreground (drop stray neighbour fragments).
    lab = np.zeros((h, w), np.int32); n = 0; sizes = {}
    for y in range(h):
        for x in range(w):
            if fg[y, x] and lab[y, x] == 0:
                n += 1; lab[y, x] = n; q = deque([(y, x)]); s = 0
                while q:
                    yy, xx = q.popleft(); s += 1
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = yy + dy, xx + dx
                        if 0 <= ny < h and 0 <= nx < w and fg[ny, nx] and lab[ny, nx] == 0:
                            lab[ny, nx] = n; q.append((ny, nx))
                sizes[n] = s
    keep = lab == max(sizes, key=sizes.get)
    # Colour-to-alpha against white on the 3 px edge band, opaque inside.
    alpha = keep.astype(np.float32)
    rgb = c.copy()
    inner = keep.copy()
    for _ in range(3):
        e = inner.copy()
        e[1:] &= inner[:-1]; e[:-1] &= inner[1:]; e[:, 1:] &= inner[:, :-1]; e[:, :-1] &= inner[:, 1:]
        inner = e
    band = keep & ~inner
    a = ((255.0 - c).max(axis=2) / 255.0).clip(0.0, 1.0)
    alpha[band] = a[band]
    safe = np.maximum(alpha, 1e-3)[..., None]
    rgb[band] = ((c - (1.0 - alpha[..., None]) * 255.0) / safe)[band]
    rgba = np.dstack([rgb.clip(0, 255), alpha * 255.0]).astype(np.uint8)
    ys, xs = np.nonzero(alpha > 0.05)
    wsum = alpha[ys, xs]
    cy, cx = (ys * wsum).sum() / wsum.sum(), (xs * wsum).sum() / wsum.sum()
    return rgba, (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1), (cx, cy)

views = {az: cut(cell) for az, cell in CELLS.items()}
half_w = max(max(cx - b[0], b[2] - cx) for _, b, (cx, cy) in views.values())
half_h = max(max(cy - b[1], b[3] - cy) for _, b, (cx, cy) in views.values())
CW, CH = int(half_w * 2) + 8, int(half_h * 2) + 8
os.makedirs(out_dir, exist_ok=True)
for az, (rgba, b, (cx, cy)) in views.items():
    tile = Image.fromarray(rgba).crop(b)
    canvas = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    canvas.paste(tile, (int(round(CW / 2 - (cx - b[0]))), int(round(CH / 2 - (cy - b[1])))), tile)
    canvas.save(os.path.join(out_dir, "drone_%03d.png" % az))
    print("view %3d: bbox %dx%d" % (az, b[2] - b[0], b[3] - b[1]))
print("canvas %dx%d" % (CW, CH))
