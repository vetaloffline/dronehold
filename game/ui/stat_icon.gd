@tool
class_name StatIcon
extends Control
## Line icon of a stat on the info card, drawn in code (art/concept/11_turret_info_v1.png):
## damage — crossed bullets, rate — three bullets, range — crosshair, blast — burst in a ring,
## crystal — a cut gem, clock — a dial; check / cross — the build mode ✔ / ✖ buttons.

enum Kind { DAMAGE, RATE, RANGE, BLAST, CRYSTAL, CLOCK, CHECK, CROSS }

@export var kind := Kind.DAMAGE:
	set(v): kind = v; queue_redraw()
@export var color := Color(0.88, 0.95, 1.0):
	set(v): color = v; queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var w := maxf(2.0, s * 0.07)
	match kind:
		Kind.DAMAGE:
			_bullet(c, s * 0.8, deg_to_rad(-45.0), s * 0.16)
			_bullet(c, s * 0.8, deg_to_rad(-135.0), s * 0.16)
			for a in [0.0, 90.0, 180.0, 270.0]:
				var d := Vector2.from_angle(deg_to_rad(a + 45.0))
				draw_line(c + d * s * 0.36, c + d * s * 0.48, color, w * 0.8, true)
		Kind.RATE:
			for i in 3:
				_bullet(c + Vector2((i - 1) * s * 0.26, 0), s * 0.78, deg_to_rad(-90.0), s * 0.17)
		Kind.RANGE:
			draw_arc(c, s * 0.34, 0.0, TAU, 40, color, w, true)
			draw_circle(c, s * 0.07, color)
			for a in [0.0, 90.0, 180.0, 270.0]:
				var d := Vector2.from_angle(deg_to_rad(a))
				draw_line(c + d * s * 0.18, c + d * s * 0.48, color, w, true)
		Kind.BLAST:
			# 8-point burst inside a dashed ring (the blast radius).
			var pts := PackedVector2Array()
			for i in 16:
				var rr := s * (0.26 if i % 2 == 0 else 0.12)
				pts.append(c + Vector2.from_angle(TAU * i / 16.0 - PI / 2.0) * rr)
			draw_colored_polygon(pts, color)
			for i in 12:
				var a0 := TAU * i / 12.0
				draw_arc(c, s * 0.44, a0, a0 + TAU / 24.0, 4, color, w * 0.8, true)
		Kind.CRYSTAL:
			var top := c + Vector2(0, -s * 0.46)
			var bottom := c + Vector2(0, s * 0.46)
			var l := c + Vector2(-s * 0.28, -s * 0.06)
			var r := c + Vector2(s * 0.28, -s * 0.06)
			draw_colored_polygon(PackedVector2Array([top, r, bottom, l]), Color(0.45, 0.78, 1.0))
			draw_colored_polygon(PackedVector2Array([top, r, c + Vector2(0, -s * 0.06)]), Color(0.8, 0.94, 1.0))
			draw_polyline(PackedVector2Array([top, r, bottom, l, top]), color, w * 0.6, true)
		Kind.CLOCK:
			draw_arc(c, s * 0.4, 0.0, TAU, 40, color, w, true)
			draw_line(c, c + Vector2(0, -s * 0.26), color, w, true)
			draw_line(c, c + Vector2(s * 0.2, s * 0.06), color, w, true)
			draw_circle(c, w * 0.7, color)
		Kind.CHECK:
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.32, 0.0), c + Vector2(-s * 0.08, s * 0.24),
				c + Vector2(s * 0.34, -s * 0.24)]), color, s * 0.14, true)
		Kind.CROSS:
			draw_line(c + Vector2(-s * 0.26, -s * 0.26), c + Vector2(s * 0.26, s * 0.26), color, s * 0.14, true)
			draw_line(c + Vector2(s * 0.26, -s * 0.26), c + Vector2(-s * 0.26, s * 0.26), color, s * 0.14, true)


## A bullet along `ang` (tip forward): casing + pointed head, length `l`, width `bw`.
func _bullet(centre: Vector2, l: float, ang: float, bw: float) -> void:
	var f := Vector2.from_angle(ang)
	var n := Vector2(-f.y, f.x)
	var back := centre - f * l * 0.5
	var shoulder := back + f * l * 0.62
	var tip := centre + f * l * 0.5
	draw_colored_polygon(PackedVector2Array([
		back + n * bw * 0.5, shoulder + n * bw * 0.5, tip, shoulder - n * bw * 0.5, back - n * bw * 0.5,
	]), color)
	draw_line(shoulder + n * bw * 0.6, shoulder - n * bw * 0.6, Color(0.035, 0.06, 0.1), maxf(1.0, bw * 0.18))
