@tool
extends Node2D
## Editor overlay of a GameMap: grid lines, blocked cells (cliff / pit), object footprints —
## green when the object may stand there, red when not (GameMap.placement_problem()).

const GRID_COLOR := Color(1, 1, 1, 0.22)
const BLOCKED_COLOR := Color(1, 0.16, 0.16, 0.22)
const OK_COLOR := Color(0.24, 1, 0.47, 0.9)
const BAD_COLOR := Color(1, 0.24, 0.24, 0.95)


func _draw() -> void:
	var map := get_parent() as GameMap
	if map == null or map.grid == null:
		return
	var g := map.grid
	var size := g.size_px()
	if map.show_blocked:
		for r in g.rows:
			for c in g.cols:
				if g.blocked[r * g.cols + c] == 1:
					draw_rect(Rect2(g.cell_origin(Vector2i(c, r)), MapGrid.CELL), BLOCKED_COLOR)
	if map.show_grid:
		for c in g.cols + 1:
			draw_line(Vector2(c * MapGrid.CELL.x, 0), Vector2(c * MapGrid.CELL.x, size.y), GRID_COLOR, 1.0)
		for r in g.rows + 1:
			draw_line(Vector2(0, r * MapGrid.CELL.y), Vector2(size.x, r * MapGrid.CELL.y), GRID_COLOR, 1.0)
	if map.show_footprints:
		for o in map.objects():
			var f := o.get_footprint()
			var rect := Rect2(g.cell_origin(o.cell), Vector2(f.x, f.y) * MapGrid.CELL)
			var ok := map.placement_problem(o) == ""
			draw_rect(rect, OK_COLOR if ok else BAD_COLOR, false, 3.0 if not ok else 1.5)
			if not ok:
				draw_rect(rect, Color(BAD_COLOR, 0.2))


func _process(_dt: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()
