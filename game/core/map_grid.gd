@tool
class_name MapGrid
extends Resource
## Build / navigation grid of a map. Cells are CELL px (flattened for the 3/4 camera).
## Every cell has a kind = two rules: can the player build there, can slimes walk there.
##   GROUND   build + walk          PASS     walk only (roads, spawn zones)
##   ROCK     neither (cliff, pit)  PLATEAU  build only (slimes go around)
## First fill: from the layout image — a cell is ROCK when more than `threshold` of it is cliff
## or pit (same rule as art/maps/map_03/map_03_editor.html coverage(), cellBlocked()).
## After that the kinds are painted by hand and saved in the grid .tres.
## A second, separate layer — `no_fly` — is for the cargo drones: 1 = they do not fly over the cell
## (cliffs; pits they fly over). First fill: cliff cells of the layout (cliffs_from_layout); then
## painted by hand in the map editor («Дрон» mode, purple).

const CELL := Vector2(32.0, 24.0)
enum Kind { GROUND, PASS, ROCK, PLATEAU }
## [can build, can walk] per kind.
const RULES := {
	Kind.GROUND: [true, true],
	Kind.PASS: [false, true],
	Kind.ROCK: [false, false],
	Kind.PLATEAU: [true, false],
}
## Layout colours (map_03_editor.html LCOL): ground (150,112,70), cliff (120,118,112), pit (14,12,16).
## Only ground has red > 0.53, so the red channel tells ground from the rest.
const GROUND_RED_MIN := 0.53
## Cliff (red 0.47) vs pit (red 0.05): below this red a not-ground pixel is a pit.
const PIT_RED_MAX := 0.25
## The editor samples the layout at 1/4 resolution.
const LAYOUT_STEP := 4

@export var cols := 0
@export var rows := 0
@export var threshold := 0.5
## Kind per cell (Kind enum). Index = r * cols + c.
@export var kinds := PackedByteArray()
## Drone layer: 1 = cargo drones do not fly over this cell. Index = r * cols + c. Empty = not filled
## yet (GameMap fills it from the layout's cliffs when it loads the map).
@export var no_fly := PackedByteArray()
## 1 = slimes can not walk (ROCK, PLATEAU), 0 = they can. Derived from `kinds` (rebuilt on first
## read after loading); the swarm and the flow field read it in their hot loops.
var blocked: PackedByteArray:
	get:
		if _blocked.size() != kinds.size():
			refresh()
		return _blocked
var _blocked := PackedByteArray()


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
	var k := PackedByteArray()
	k.resize(g.cols * g.rows)
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
			k[r * g.cols + c] = Kind.ROCK if any > thr else Kind.GROUND
	g.kinds = k
	g.refresh()
	return g


## Drone layer from a layout image: a cell is no-fly when more than `thr` of it is cliff (not pit).
static func cliffs_from_layout(image: Image, cols: int, rows: int, thr := 0.5) -> PackedByteArray:
	var w := image.get_width()
	var h := image.get_height()
	var small := image.duplicate() as Image
	if small.is_compressed():
		small.decompress()
	var lw := int(ceil(float(w) / LAYOUT_STEP))
	var lh := int(ceil(float(h) / LAYOUT_STEP))
	small.resize(lw, lh, Image.INTERPOLATE_NEAREST)
	var out := PackedByteArray()
	out.resize(cols * rows)
	for r in rows:
		for c in cols:
			var x0 := int(floor(c * CELL.x / LAYOUT_STEP))
			var x1 := int(ceil((c + 1) * CELL.x / LAYOUT_STEP))
			var y0 := int(floor(r * CELL.y / LAYOUT_STEP))
			var y1 := int(ceil((r + 1) * CELL.y / LAYOUT_STEP))
			var n := 0
			var cliff := 0
			for y in range(y0, mini(y1, lh)):
				for x in range(x0, mini(x1, lw)):
					n += 1
					var red := small.get_pixel(x, y).r
					if red < GROUND_RED_MIN and red >= PIT_RED_MAX:
						cliff += 1
			out[r * cols + c] = 1 if n > 0 and float(cliff) / n > thr else 0
	return out


## Drones do not fly over this cell (outside the map — they do not either).
func fly_blocked(c: int, r: int) -> bool:
	if not inside(c, r):
		return true
	var i := r * cols + c
	return i < no_fly.size() and no_fly[i] == 1


func set_no_fly(c: int, r: int, on: bool) -> void:
	if not inside(c, r):
		return
	if no_fly.size() != cols * rows:
		no_fly.resize(cols * rows)
	no_fly[r * cols + c] = 1 if on else 0


func no_fly_count() -> int:
	return no_fly.count(1)


## Grid with every cell GROUND (test scenes).
static func open(c: int, r: int) -> MapGrid:
	var g := MapGrid.new()
	g.cols = c
	g.rows = r
	var k := PackedByteArray()
	k.resize(c * r)
	k.fill(Kind.GROUND)
	g.kinds = k
	g.refresh()
	return g


## Recompute `blocked` from `kinds` (call after changing `kinds` directly).
func refresh() -> void:
	_blocked.resize(kinds.size())
	for i in kinds.size():
		_blocked[i] = 0 if RULES[kinds[i]][1] else 1
	emit_changed()


func size_px() -> Vector2:
	return Vector2(cols * CELL.x, rows * CELL.y)


func inside(c: int, r: int) -> bool:
	return c >= 0 and r >= 0 and c < cols and r < rows


func kind(c: int, r: int) -> Kind:
	return kinds[r * cols + c] as Kind if inside(c, r) else Kind.ROCK


func set_kind(c: int, r: int, k: Kind) -> void:
	if not inside(c, r):
		return
	var i := r * cols + c
	var _b := blocked  # make sure _blocked is built
	kinds[i] = k
	_blocked[i] = 0 if RULES[k][1] else 1


func can_build(c: int, r: int) -> bool:
	return RULES[kind(c, r)][0]


func can_walk(c: int, r: int) -> bool:
	return RULES[kind(c, r)][1]


## Slimes can not enter (outside the map counts as blocked).
func is_blocked(c: int, r: int) -> bool:
	return not can_walk(c, r)


func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL.x)), int(floor(p.y / CELL.y)))


func cell_origin(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL.x, c.y * CELL.y)


func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL.x, (c.y + 0.5) * CELL.y)


## Cells slimes can not walk.
func blocked_count() -> int:
	return blocked.count(1)


func count_kind(k: Kind) -> int:
	return kinds.count(k)
