class_name SelectionHighlight
extends Node2D
## Ground highlight of the selected object: a square on the cells it takes and, for a turret, its
## firing range; for a relay, the ground it clears of the corruption.
## The range is drawn as the game measures it: a turret — a circle of rig.range_px map px around the
## turret (Turret.find_target / aim use plain map distance, not a ground-squashed one); the cleared
## ground (`clear` = true) — the ellipse rot.gdshader cuts: MapObject.clear_radius_px() along x,
## × CELL.y / CELL.x along y (GameMap._update_rot cam_k), around the footprint centre.
## Lives on the map's ground layer (under the objects).

const DASH_DEG := 4.0
const GAP_DEG := 2.5

var target: MapObject:
	set(v): target = v; _t = 0.0; queue_redraw()
## Firing range, map px (0 = none: only the square on the cells).
var range_px := 0.0
## range_px is a cleared-ground ellipse (see above), not a firing circle.
var clear := false
var color := Color(0.38, 0.88, 1.0)
var _t := 0.0


func _process(dt: float) -> void:
	if target and not is_instance_valid(target):
		target = null
	if target == null:
		return
	_t += dt
	queue_redraw()


func _draw() -> void:
	if target == null:
		return
	var c := target.position
	# Opens up over 0.25 s, then breathes a little.
	var open := 1.0 - pow(1.0 - minf(_t / 0.25, 1.0), 3.0)
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	# Line widths in screen px whatever the camera zoom.
	var px := 1.0 / maxf(0.01, get_viewport().get_canvas_transform().get_scale().x)
	if range_px > 0.0:
		var k := 1.0
		if clear:
			c = target.footprint_rect().get_center()
			k = MapGrid.CELL.y / MapGrid.CELL.x
		# The ellipse = the circle squashed in y around its centre (line widths squash a little too).
		draw_set_transform(c, 0.0, Vector2(1.0, k))
		var rad := range_px * (0.85 + 0.15 * open)
		draw_circle(Vector2.ZERO, rad, Color(color, 0.12 * open))
		draw_circle(Vector2.ZERO, rad - 7.0 * px, Color(color, 0.12 * open), false, 14.0 * px)
		var a := 0.0
		while a < 360.0:
			draw_arc(Vector2.ZERO, rad, deg_to_rad(a + _t * 4.0), deg_to_rad(a + _t * 4.0 + DASH_DEG), 6, Color(color, (0.75 + 0.2 * pulse) * open), 4.0 * px, true)
			a += DASH_DEG + GAP_DEG
		draw_set_transform(Vector2.ZERO)
	# The building's cells: a square on exactly the cells it takes (2×2 for a turret / drill).
	var cells := target.footprint_rect()
	draw_rect(cells, Color(color, 0.18 * open))
	draw_rect(cells.grow(-3.0 * px), Color(color, 0.25 * open), false, 6.0 * px)
	draw_rect(cells, Color(color, (0.85 + 0.15 * pulse) * open), false, 3.0 * px)
