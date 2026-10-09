class_name FloatText
extends Node2D
## «+5» with an icon that pops up in the world, floats up and fades (mined crystals, later damage).
## FloatText.pop(parent, position, "+5", FloatText.CRYSTAL)

const CRYSTAL := preload("res://art/objects/resources/crystal_vein/crystal_shard_1.png")
const THEME := preload("res://game/ui/menu_theme.tres")

## Size on the map, px: text height and icon height.
const FONT_SIZE := 52
const ICON_H := 50.0
const RISE := 90.0
const LIFE := 1.4

var text := ""
var icon: Texture2D
var color := Color(0.86, 0.97, 1.0)
var _t := 0.0
var _from := Vector2.ZERO


static func pop(parent: Node, at: Vector2, txt: String, ico: Texture2D = null) -> FloatText:
	var f := FloatText.new()
	f.text = txt
	f.icon = ico
	f.position = at
	f.z_index = 100
	parent.add_child(f)
	return f


func _ready() -> void:
	_from = position


func _process(dt: float) -> void:
	_t += dt
	var k := minf(_t / LIFE, 1.0)
	position = _from - Vector2(0, RISE * (1.0 - pow(1.0 - k, 3.0)))
	# Pops in a bit larger, settles, fades out over the last 40 %.
	var s := 1.0 + 0.35 * maxf(0.0, 1.0 - _t / 0.15)
	scale = Vector2(s, s)
	modulate.a = 1.0 - clampf((k - 0.6) / 0.4, 0.0, 1.0)
	if k >= 1.0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var font := THEME.default_font
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var iw := 0.0
	if icon:
		iw = ICON_H * icon.get_width() / icon.get_height()
	var gap := 6.0 if icon else 0.0
	var x := -(tw + iw + gap) * 0.5
	var base := FONT_SIZE * 0.35
	draw_string_outline(font, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 12, Color(0.02, 0.05, 0.12, 0.95))
	draw_string(font, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
	if icon:
		draw_texture_rect(icon, Rect2(x + tw + gap, -ICON_H * 0.5, iw, ICON_H), false)
