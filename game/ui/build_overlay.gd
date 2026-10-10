class_name BuildOverlay
extends Node2D
## Build mode marks on the ground (map Shadows layer, under the buildings), concept
## art/concept/12_build_v1.png:
## - the ghost's footprint: a square of its cells, green — can build, red — can not, with a faint grid
##   of the cells around it;
## - with the drill chosen: every free vein slot as a pulsing cyan dashed square;
## - a wall line: its cells (green / red when the money is short), a ring on every tapped point; a
##   point the wall can not reach flashes red;
## - while the build mode is open (`show_map`): a light grid over the whole visible map and the cells
##   where nothing can be built tinted red (Builder.blocked_cells), so it is clear where to tap.

const OK_COLOR := Color(0.3, 1.0, 0.45)
const BAD_COLOR := Color(1.0, 0.3, 0.3)
const SLOT_COLOR := Color(0.35, 0.9, 1.0)
## Cells of faint grid around the ghost's footprint.
const GRID_AROUND := 3
## Build mode map layer: grid lines and the tint of cells where nothing can be built.
const MAP_GRID_COLOR := Color(1, 1, 1, 0.32)
const MAP_BLOCKED_COLOR := Color(1.0, 0.18, 0.18, 0.34)

## Footprint cells of the ghost (empty = no ghost) and the map px square to light up (its cells).
var cells := Rect2i()
var square := Rect2()
var ok := true
## Free drill slots to show: squares where a drill will stand, map px.
var slots: Array[Rect2] = []
## Wall line: its cells, the tapped points, whether it can be paid; a cell that flashes red and how
## long it still flashes, s.
var line: Array[Vector2i] = []
var points: Array[Vector2i] = []
var line_ok := true
var bad_cell := Vector2i(-1, -1)
var _bad_t := 0.0
## Grid + red cells over the whole map (the build mode is open).
var show_map := false
var grid: MapGrid
## 1 px per cell, red where nothing can be built; drawn stretched over the map (nearest filter).
var _blocked_tex: ImageTexture
## What _blocked_tex shows (Builder.blocked_cells), kept for blocked_shown().
var _blocked := PackedByteArray()
var _t := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Turn the map layer on / off; `blocked` = Builder.blocked_cells() of grid `g`.
func show_blocked(on: bool, g: MapGrid = null, blocked := PackedByteArray()) -> void:
	show_map = on
	if on and g:
		grid = g
		_blocked = blocked
		var img := Image.create(g.cols, g.rows, false, Image.FORMAT_RGBA8)
		var clear := Color(0, 0, 0, 0)
		for r in g.rows:
			for c in g.cols:
				img.set_pixel(c, r, MAP_BLOCKED_COLOR if blocked[r * g.cols + c] == 1 else clear)
		if _blocked_tex and _blocked_tex.get_size() == Vector2(g.cols, g.rows):
			_blocked_tex.update(img)
		else:
			_blocked_tex = ImageTexture.create_from_image(img)
	queue_redraw()


## Is cell (c, r) tinted red right now (tests)?
func blocked_shown(c: int, r: int) -> bool:
	if not show_map or grid == null or not grid.inside(c, r):
		return false
	return _blocked[r * grid.cols + c] == 1


func _process(dt: float) -> void:
	_t += dt
	_bad_t = maxf(0.0, _bad_t - dt)
	if _bad_t > 0.0 or not line.is_empty() or show_map or cells.size != Vector2i.ZERO or not slots.is_empty():
		queue_redraw()


func show_line(cells_: Array[Vector2i], points_: Array[Vector2i], ok_: bool) -> void:
	line = cells_
	points = points_.duplicate()
	line_ok = ok_
	queue_redraw()


## Flash cell `c` red (a line point the wall can not reach).
func flash_bad(c: Vector2i) -> void:
	bad_cell = c
	_bad_t = 0.8
	queue_redraw()


func show_state(footprint: Rect2i, at: Rect2, can: bool, free_slots: Array[Rect2]) -> void:
	cells = footprint
	square = at
	ok = can
	slots = free_slots
	queue_redraw()


func _draw() -> void:
	var k := _screen_k()
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	if show_map and grid:
		_draw_map_layer(k)
	_draw_line_plan(k, pulse)
	for r in slots:
		draw_rect(r, Color(SLOT_COLOR, 0.22 + 0.16 * pulse))
		_dashed_rect(r, Color(SLOT_COLOR, 0.75 + 0.25 * pulse), 4.0 * k, 12.0 * k)
	if cells.size == Vector2i.ZERO:
		return
	var col := OK_COLOR if ok else BAD_COLOR
	# Faint grid around the footprint, fading out.
	var g0 := cells.position - Vector2i(GRID_AROUND, GRID_AROUND)
	var g1 := cells.end + Vector2i(GRID_AROUND, GRID_AROUND)
	var mid := square.get_center()
	var reach := (GRID_AROUND + maxi(cells.size.x, cells.size.y) * 0.5) * MapGrid.CELL.x
	for x in range(g0.x, g1.x + 1):
		for y in range(g0.y, g1.y):
			var a := Vector2(x, y) * MapGrid.CELL
			var b := Vector2(x, y + 1) * MapGrid.CELL
			draw_line(a, b, Color(1, 1, 1, 0.3 * _fade(a.lerp(b, 0.5), mid, reach)), 1.5 * k)
	for y in range(g0.y, g1.y + 1):
		for x in range(g0.x, g1.x):
			var a := Vector2(x, y) * MapGrid.CELL
			var b := Vector2(x + 1, y) * MapGrid.CELL
			draw_line(a, b, Color(1, 1, 1, 0.3 * _fade(a.lerp(b, 0.5), mid, reach)), 1.5 * k)
	draw_rect(square, Color(col, 0.28 + 0.1 * pulse))
	draw_rect(square, Color(col, 0.95), false, 3.0 * k)


func _draw_line_plan(k: float, pulse: float) -> void:
	var col := OK_COLOR if line_ok else BAD_COLOR
	for c in line:
		var r := Rect2(Vector2(c) * MapGrid.CELL, MapGrid.CELL)
		draw_rect(r, Color(col, 0.3 + 0.1 * pulse))
		draw_rect(r, Color(col, 0.9), false, 2.0 * k)
	for i in points.size():
		var at := (Vector2(points[i]) + Vector2(0.5, 0.5)) * MapGrid.CELL
		var last := i == points.size() - 1
		draw_circle(at, (9.0 if last else 7.0) * k, Color(0.05, 0.08, 0.12, 0.85))
		draw_arc(at, (9.0 if last else 7.0) * k, 0.0, TAU, 24, Color.WHITE, 2.5 * k, true)
		draw_circle(at, 3.0 * k, Color.WHITE if last else Color(col, 1.0))
	if _bad_t > 0.0:
		var r := Rect2(Vector2(bad_cell) * MapGrid.CELL, MapGrid.CELL)
		var a := _bad_t / 0.8
		draw_rect(r, Color(BAD_COLOR, 0.6 * a))
		draw_line(r.position, r.end, Color(1, 1, 1, a), 2.5 * k)
		draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color(1, 1, 1, a), 2.5 * k)


## Red cells over the whole map (one texture), grid lines only over the visible part.
func _draw_map_layer(k: float) -> void:
	if _blocked_tex:
		draw_texture_rect(_blocked_tex, Rect2(Vector2.ZERO, grid.size_px()), false)
	var view := _visible_rect().intersection(Rect2(Vector2.ZERO, grid.size_px()))
	if view.size.x <= 0.0 or view.size.y <= 0.0:
		return
	var c0 := int(floor(view.position.x / MapGrid.CELL.x))
	var c1 := int(ceil(view.end.x / MapGrid.CELL.x))
	var r0 := int(floor(view.position.y / MapGrid.CELL.y))
	var r1 := int(ceil(view.end.y / MapGrid.CELL.y))
	var w := 1.5 * k
	for c in range(c0, c1 + 1):
		draw_line(Vector2(c * MapGrid.CELL.x, view.position.y), Vector2(c * MapGrid.CELL.x, view.end.y), MAP_GRID_COLOR, w)
	for r in range(r0, r1 + 1):
		draw_line(Vector2(view.position.x, r * MapGrid.CELL.y), Vector2(view.end.x, r * MapGrid.CELL.y), MAP_GRID_COLOR, w)


## The part of the map on screen, in this node's px.
func _visible_rect() -> Rect2:
	var vp := get_viewport_rect()
	var inv := (get_viewport().get_canvas_transform() * get_global_transform()).affine_inverse()
	var a: Vector2 = inv * vp.position
	var b: Vector2 = inv * vp.end
	return Rect2(a, Vector2.ZERO).expand(b)


static func _fade(p: Vector2, mid: Vector2, reach: float) -> float:
	return clampf(1.0 - p.distance_to(mid) / maxf(1.0, reach), 0.0, 1.0)


func _dashed_rect(r: Rect2, col: Color, w: float, dash: float) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		draw_dashed_line(pts[i], pts[(i + 1) % 4], col, w, dash)


## Map px per screen px (lines keep their width on screen at any zoom).
func _screen_k() -> float:
	var z := get_viewport().get_canvas_transform().get_scale().x * get_global_transform().get_scale().x
	return 1.0 / maxf(0.01, z)
