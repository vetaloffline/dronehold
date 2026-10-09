@tool
class_name MapGrid
extends Resource
## Build / navigation grid of a map. Cells are CELL px (flattened for the 3/4 camera).
## A cell is blocked when more than `threshold` of it is cliff or pit in the layout image —
## the same rule as art/maps/map_03/map_03_editor.html (coverage(), cellBlocked()).

const CELL := Vector2(64.0, 48.0)
## Layout colours (map_03_editor.html LCOL): ground (150,112,70), cliff (120,118,112), pit (14,12,16).
## Only ground has red > 0.53, so the red channel tells ground from the rest.
const GROUND_RED_MIN := 0.53
## The editor samples the layout at 1/4 resolution.
const LAYOUT_STEP := 4

@export var cols := 0
@export var rows := 0
@export var threshold := 0.5
## 1 = blocked (cliff / pit), 0 = open. Index = r * cols + c.
@export var blocked := PackedByteArray()


static func from_layout(image: Image, thr := 0.5) -> MapGrid:
	var g := MapGrid.new()
	g.threshold = thr
	var w := image.get_width()
	var h := image.get_height()
	g.cols = int(floor(w / CELL.x))
	g.rows = int(floor(h / CELL.y))
	var small := image.duplicate() as Image
	if small.is_compressed():
		small.decompress()
	var lw := int(ceil(float(w) / LAYOUT_STEP))
	var lh := int(ceil(float(h) / LAYOUT_STEP))
	small.resize(lw, lh, Image.INTERPOLATE_NEAREST)
	g.blocked.resize(g.cols * g.rows)
	for r in g.rows:
		for c in g.cols:
			var x0 := int(floor(c * CELL.x / LAYOUT_STEP))
			var x1 := int(ceil((c + 1) * CELL.x / LAYOUT_STEP))
			var y0 := int(floor(r * CELL.y / LAYOUT_STEP))
			var y1 := int(ceil((r + 1) * CELL.y / LAYOUT_STEP))
			var n := 0
			var bad := 0
			for y in range(y0, mini(y1, lh)):
				for x in range(x0, mini(x1, lw)):
					n += 1
					if small.get_pixel(x, y).r < GROUND_RED_MIN:
						bad += 1
			var any := float(bad) / n if n > 0 else 1.0
			g.blocked[r * g.cols + c] = 1 if any > thr else 0
	return g


## Grid with every cell open (test scenes).
static func open(c: int, r: int) -> MapGrid:
	var g := MapGrid.new()
	g.cols = c
	g.rows = r
	g.blocked.resize(c * r)
	g.blocked.fill(0)
	return g


func size_px() -> Vector2:
	return Vector2(cols * CELL.x, rows * CELL.y)


func inside(c: int, r: int) -> bool:
	return c >= 0 and r >= 0 and c < cols and r < rows


func is_blocked(c: int, r: int) -> bool:
	return not inside(c, r) or blocked[r * cols + c] == 1


func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL.x)), int(floor(p.y / CELL.y)))


func cell_origin(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL.x, c.y * CELL.y)


func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL.x, (c.y + 0.5) * CELL.y)


func blocked_count() -> int:
	var n := 0
	for v in blocked:
		n += v
	return n
