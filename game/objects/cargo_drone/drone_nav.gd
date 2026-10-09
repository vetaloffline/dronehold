class_name DroneNav
extends RefCounted
## Flight paths of the cargo drones around what they do not fly over: the drone layer of the grid
## (MapGrid.no_fly, purple in the map editor) and the cells under tall decor (Prop.blocks_flight()).
## A* over cells (AStarGrid2D, no corner cutting), then straightened: from each point the drone flies
## straight to the farthest later point it can reach without crossing a blocked cell (CLEARANCE px to
## each side, so the wings do not touch a cliff). No way round — the path is just [goal] (flies straight).

const CLEARANCE := 12.0

var grid: MapGrid
var astar := AStarGrid2D.new()
## 1 = blocked for drones (no_fly or tall decor). Index = r * cols + c.
var solid := PackedByteArray()


## Nav for `grid`; `extra` = more blocked cells (Vector2i), e.g. under tall decor.
static func build(g: MapGrid, extra: Array[Vector2i] = []) -> DroneNav:
	var n := DroneNav.new()
	n.grid = g
	n.solid.resize(g.cols * g.rows)
	for r in g.rows:
		for c in g.cols:
			if g.fly_blocked(c, r):
				n.solid[r * g.cols + c] = 1
	for e in extra:
		if g.inside(e.x, e.y):
			n.solid[e.y * g.cols + e.x] = 1
	n.astar.region = Rect2i(0, 0, g.cols, g.rows)
	n.astar.cell_size = MapGrid.CELL
	n.astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	n.astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	n.astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	n.astar.update()
	for r in g.rows:
		for c in g.cols:
			if n.solid[r * g.cols + c] == 1:
				n.astar.set_point_solid(Vector2i(c, r), true)
	return n


## Nav of a map: its grid + the cells under tall decor anywhere under the map (Prop.blocks_flight()).
static func for_map(map: GameMap) -> DroneNav:
	var extra: Array[Vector2i] = []
	for n in map.find_children("*", "Prop", true, false):
		var p := n as Prop
		if p.blocks_flight():
			extra.append_array(p.footprint_cells())
	return build(map.grid, extra)


func is_solid(c: Vector2i) -> bool:
	return not grid.inside(c.x, c.y) or solid[c.y * grid.cols + c.x] == 1


## Map px points to fly through from `from` to `to` (the last point is `to`).
func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := _free_near(grid.cell_at(from))
	var b := _free_near(grid.cell_at(to))
	if a.x < 0 or b.x < 0 or clear(from, to):
		return PackedVector2Array([to])
	var cells := astar.get_id_path(a, b)
	if cells.is_empty():
		return PackedVector2Array([to])
	var pts := PackedVector2Array([from])
	for c in cells:
		pts.append(grid.cell_center(c))
	pts.append(to)
	return _straighten(pts)


## Can a drone fly straight from `a` to `b`? (samples the line and two lines CLEARANCE px to the sides)
func clear(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return not is_solid(grid.cell_at(a))
	var side := Vector2(-d.y, d.x) / l * CLEARANCE
	var steps := int(ceil(l / 6.0))
	for i in steps + 1:
		var p := a + d * (float(i) / steps)
		for o in [Vector2.ZERO, side, -side]:
			if is_solid(grid.cell_at(p + o)):
				return false
	return true


func _straighten(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := 0
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1 and not clear(pts[i], pts[j]):
			j -= 1
		out.append(pts[j])
		i = j
	return out


## `c` or the nearest cell that is not blocked (within 6 rings); (-1, -1) if none.
func _free_near(c: Vector2i) -> Vector2i:
	for ring in 7:
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var q := c + Vector2i(dx, dy)
				if grid.inside(q.x, q.y) and not is_solid(q):
					return q
	return Vector2i(-1, -1)
