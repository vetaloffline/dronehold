@tool
class_name StatIcon
extends Control
## Line icon of a stat on the info card, drawn in code (art/concept/11_turret_info_v1.png):
## damage — crossed bullets, rate — three bullets, range — crosshair, blast — burst in a ring,
## crystal — a cut gem, clock — a dial; check / cross — the build mode ✔ / ✖ buttons;
## hp — a shield with a cross, clear — a building square in a dashed ground ellipse (cleared ground),
## pad — a landing ring with an arrow down onto it (drone pads), build — a plus inside a solid ground
## ellipse (the build radius).
## New kinds go at the end: scenes store the kind as a number.

enum Kind { DAMAGE, RATE, RANGE, BLAST, CRYSTAL, CLOCK, CHECK, CROSS, HP, CLEAR, PAD, BUILD }

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
		Kind.HP:
			var pts := PackedVector2Array([c + Vector2(0, -s * 0.44), c + Vector2(s * 0.36, -s * 0.3),
				c + Vector2(s * 0.32, s * 0.08), c + Vector2(0, s * 0.46), c + Vector2(-s * 0.32, s * 0.08),
				c + Vector2(-s * 0.36, -s * 0.3)])
			pts.append(pts[0])
			draw_polyline(pts, color, w, true)
			draw_line(c + Vector2(0, -s * 0.2), c + Vector2(0, s * 0.18), color, w * 1.3, true)
			draw_line(c + Vector2(-s * 0.18, -s * 0.01), c + Vector2(s * 0.18, -s * 0.01), color, w * 1.3, true)
		Kind.CLEAR:
			# Dashed ground ellipse (squashed like the cleared ground) round a small building square.
			draw_set_transform(c, 0.0, Vector2(1.0, 0.75))
			for i in 14:
				var a0 := TAU * i / 14.0
				draw_arc(Vector2.ZERO, s * 0.46, a0, a0 + TAU / 28.0, 4, color, w * 0.9, true)
			draw_set_transform(Vector2.ZERO)
			draw_rect(Rect2(c - Vector2(s * 0.13, s * 0.1), Vector2(s * 0.26, s * 0.2)), color)
		Kind.PAD:
			draw_set_transform(c + Vector2(0, s * 0.22), 0.0, Vector2(1.0, 0.45))
			draw_arc(Vector2.ZERO, s * 0.42, 0.0, TAU, 32, color, w * 1.6, true)
			draw_set_transform(Vector2.ZERO)
			draw_circle(c + Vector2(0, s * 0.22), s * 0.06, color)
			draw_line(c + Vector2(0, -s * 0.46), c + Vector2(0, -s * 0.02), color, w, true)
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.13, -s * 0.15), c + Vector2(0, -s * 0.02),
				c + Vector2(s * 0.13, -s * 0.15)]), color, w, true)
		Kind.BUILD:
			# Solid ground ellipse (squashed like the build radius edge) with a plus: «build here».
			draw_set_transform(c, 0.0, Vector2(1.0, 0.75))
			draw_arc(Vector2.ZERO, s * 0.46, 0.0, TAU, 40, color, w, true)
			draw_set_transform(Vector2.ZERO)
			draw_line(c + Vector2(0, -s * 0.2), c + Vector2(0, s * 0.2), color, w * 1.4, true)
			draw_line(c + Vector2(-s * 0.2, 0), c + Vector2(s * 0.2, 0), color, w * 1.4, true)


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
