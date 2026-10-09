"""Cut one regenerated drone view (white bg) and fit it to the old view: same bbox width, shared
canvas size, centred on the alpha centroid. Usage: src old_view_png out_png"""
import sys
from collections import deque
import numpy as np
from PIL import Image

src, old_path, out = sys.argv[1:4]
c = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
h, w, _ = c.shape
near_white = c.min(axis=2) >= 232
bg = np.zeros((h, w), bool)
q = deque()
for y in range(h):
    for x in (0, w - 1):
        if near_white[y, x] and not bg[y, x]:
            bg[y, x] = True
            q.append((y, x))
for x in range(w):
    for y in (0, h - 1):
        if near_white[y, x] and not bg[y, x]:
            bg[y, x] = True
            q.append((y, x))
while q:
    y, x = q.popleft()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ny, nx = y + dy, x + dx
        if 0 <= ny < h and 0 <= nx < w and not bg[ny, nx] and near_white[ny, nx]:
            bg[ny, nx] = True
            q.append((ny, nx))
keep = ~bg
alpha = keep.astype(np.float32)
inner = keep.copy()
for _ in range(3):
    e = inner.copy()
    e[1:] &= inner[:-1]
    e[:-1] &= inner[1:]
    e[:, 1:] &= inner[:, :-1]
    e[:, :-1] &= inner[:, 1:]
    inner = e
band = keep & ~inner
a = ((255.0 - c).max(axis=2) / 255.0).clip(0.0, 1.0)
alpha[band] = a[band]
rgb = c.copy()
safe = np.maximum(alpha, 1e-3)[..., None]
rgb[band] = ((c - (1.0 - alpha[..., None]) * 255.0) / safe)[band]
rgba = Image.fromarray(np.dstack([rgb.clip(0, 255), alpha * 255.0]).astype(np.uint8))
bb = rgba.getchannel("A").point(lambda v: 255 if v > 12 else 0).getbbox()
tile = rgba.crop(bb)
old = Image.open(old_path)
ob = old.getchannel("A").point(lambda v: 255 if v > 12 else 0).getbbox()
k = (ob[2] - ob[0]) / tile.width
tile = tile.resize((round(tile.width * k), round(tile.height * k)), Image.LANCZOS)
al = np.asarray(tile.getchannel("A")).astype(np.float32) / 255.0
ys, xs = np.nonzero(al > 0.05)
wgt = al[ys, xs]
cy, cx = (ys * wgt).sum() / wgt.sum(), (xs * wgt).sum() / wgt.sum()
canvas = Image.new("RGBA", old.size, (0, 0, 0, 0))
canvas.paste(tile, (round(old.width / 2 - cx), round(old.height / 2 - cy)), tile)
canvas.save(out)
print("%s: scale %.3f, size %dx%d (old bbox %dx%d)" % (out.split("/")[-1], k, tile.width, tile.height, ob[2] - ob[0], ob[3] - ob[1]))
