"""Cut the 3 wall pieces from a sheet (Codex output or the template) and assemble test walls the way
the game will: per wall cell, in Y order — span to the right neighbour, the pillar, span to the lower
neighbour. Pieces are fitted exactly onto the template boxes (so the joints meet).
  python3 wall_assemble.py <sheet.png> <out_dir>
Writes out_dir/wall_pillar.png, wall_along.png, wall_depth.png (+ wall_pieces.json: ground point of
each piece in its own px) and out_dir/wall_test.png."""
from PIL import Image
import numpy as np, json, sys, os
from collections import deque

T = json.load(open(os.path.join(os.path.dirname(__file__), "wall_template.json")))
CW, CH = T["cell"]
P, A, D, SH = T["pillar"], T["along"], T["depth"], T["span_h"]
G = T["ground"]
# Template boxes: (x0, y0, x1, y1) in sheet px and the ground point.
BOX = {
	"pillar": (G["pillar"][0] - P["w"] / 2, G["pillar"][1] - P["d"] / 2 - P["h"], G["pillar"][0] + P["w"] / 2, G["pillar"][1] + P["d"] / 2),
	"along": (G["along"][0] + A["x0"], G["along"][1] - A["d"] / 2 - SH, G["along"][0] + A["x1"], G["along"][1] + A["d"] / 2),
	"depth": (G["depth"][0] - D["w"] / 2, G["depth"][1] + D["y0"] - SH, G["depth"][0] + D["w"] / 2, G["depth"][1] + D["y1"]),
}


def alpha_of(im):
	a = np.asarray(im.convert("RGBA")).astype(float)
	if a[..., 3].min() < 250:
		return a[..., 3] > 40
	# no alpha: everything far from white
	rgb = a[..., :3]
	return (255 - rgb).max(axis=2) > 60


def components(mask):
	h, w = mask.shape
	seen = np.zeros_like(mask, bool)
	out = []
	for y0 in range(0, h, 2):
		for x0 in range(0, w, 2):
			if mask[y0, x0] and not seen[y0, x0]:
				q = deque([(y0, x0)]); seen[y0, x0] = True
				xs, ys, n = [x0, x0], [y0, y0], 0
				while q:
					y, x = q.popleft(); n += 1
					xs[0] = min(xs[0], x); xs[1] = max(xs[1], x); ys[0] = min(ys[0], y); ys[1] = max(ys[1], y)
					for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
						yy, xx = y + dy, x + dx
						if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not seen[yy, xx]:
							seen[yy, xx] = True; q.append((yy, xx))
				out.append((n, (xs[0], ys[0], xs[1] + 1, ys[1] + 1)))
	return out


def cut(sheet_path, out_dir):
	im = Image.open(sheet_path).convert("RGBA")
	if im.size != (1536, 1024):
		im = im.resize((1536, 1024), Image.LANCZOS)
	m = alpha_of(im)
	names = ["pillar", "along", "depth"]
	info = {}
	for name in names:
		x0, y0, x1, y1 = BOX[name]
		# Look for the piece near its template box (Codex keeps the layout roughly).
		wx0, wy0, wx1, wy1 = [int(v) for v in (max(0, x0 - 70), max(0, y0 - 90), min(1536, x1 + 70), min(1024, y1 + 70))]
		sub = m[wy0:wy1, wx0:wx1]
		ys, xs = np.nonzero(sub)
		bb = (wx0 + xs.min(), wy0 + ys.min(), wx0 + xs.max() + 1, wy0 + ys.max() + 1)
		piece = im.crop(bb)
		if np.asarray(piece)[..., 3].min() >= 250:
			# white background → alpha from distance to white
			arr = np.asarray(piece).astype(float)
			al = np.clip(((255 - arr[..., :3]).max(axis=2) - 12) * 6, 0, 255)
			arr[..., 3] = al
			piece = Image.fromarray(arr.astype(np.uint8), "RGBA")
		x0, y0, x1, y1 = BOX[name]
		tw, th = int(round(x1 - x0)), int(round(y1 - y0))
		print(f"{name}: sheet bbox {bb} size {bb[2]-bb[0]}x{bb[3]-bb[1]} → template {tw}x{th}")
		piece = piece.resize((tw, th), Image.LANCZOS)
		gx, gy = G[name]
		info[name] = {"ground": [gx - x0, gy - y0], "size": [tw, th]}
		piece.save(os.path.join(out_dir, f"wall_{name}.png"))
	json.dump(info, open(os.path.join(out_dir, "wall_pieces.json"), "w"), indent=1)
	return info


def assemble(out_dir, info, path):
	pcs = {k: Image.open(os.path.join(out_dir, f"wall_{k}.png")) for k in info}
	layouts = [
		["#####"],
		["#....", "#....", "#....", "#####"],
		["#....", "##...", ".##..", "..##.", "...##"],
		["..#..", "..#..", "#####", "..#..", "..#.."],
		["#.#.#"],
	]
	k = 0.5
	cw, ch = CW * k, CH * k
	tiles = []
	for lay in layouts:
		rows, cols = len(lay), len(lay[0])
		W, H = int(cols * cw + 2 * cw), int(rows * ch + 3 * ch)
		img = Image.new("RGBA", (W, H), (178, 140, 86, 255))
		cells = {(c, r) for r in range(rows) for c in range(cols) if lay[r][c] == "#"}
		ox, oy = cw, 2 * ch
		def put(name, c, r):
			p = pcs[name]
			g = info[name]["ground"]
			s = p.resize((int(p.width * k), int(p.height * k)), Image.LANCZOS)
			gx, gy = ox + (c + 0.5) * cw, oy + (r + 0.5) * ch
			img.alpha_composite(s, (int(round(gx - g[0] * k)), int(round(gy - g[1] * k))))
		for (c, r) in sorted(cells, key=lambda t: (t[1], t[0])):
			if (c + 1, r) in cells:
				put("along", c, r)
			put("pillar", c, r)
			if (c, r + 1) in cells:
				put("depth", c, r)
		tiles.append(img)
	W = sum(t.width for t in tiles) + 20 * len(tiles)
	H = max(t.height for t in tiles)
	sheet = Image.new("RGBA", (W, H), (60, 60, 60, 255))
	x = 0
	for t in tiles:
		sheet.alpha_composite(t, (x, 0)); x += t.width + 20
	sheet.save(path)
	print(path)


if __name__ == "__main__":
	sheet, out = sys.argv[1], sys.argv[2]
	os.makedirs(out, exist_ok=True)
	info = cut(sheet, out)
	assemble(out, info, os.path.join(out, "wall_test.png"))
