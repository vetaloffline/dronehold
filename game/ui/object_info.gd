class_name ObjectInfo
extends CanvasLayer
## Tap a turret or a drill → it lights up on the ground (a turret also shows its firing range) and a
## card docks at the bottom of the screen (concept art/concept/11_turret_info_v1.png, approved
## 2026-10-09): picture from the real sprites, name, level and up to 4 stat tiles.
## Turret: damage / rate / range (+ blast for the grenade launcher). Drill: storage / per cycle / cycle.
## Tap empty ground, ✕ or Esc — the card goes. A drag (camera pan) is not a tap: the pointer must
## move less than TAP_SLOP px.

@export var map: GameMap

const TAP_SLOP := 14.0
## How far above the footprint a tap still hits the object (sprites are tall), cells.
const HIT_UP := 2.5
## Card width with 3 stat tiles, px (the scene's Card offsets).
const CARD_W := 820.0
const TILES := ["Stat1", "Stat2", "Stat3", "Stat4"]

var selected: MapObject
var _press := Vector2.INF
var _highlight: SelectionHighlight

@onready var _card := $Root/Card as Control
## Slides inside the card (the card itself is anchored to the bottom of the screen).
@onready var _body := $Root/Card/Body as Control
@onready var _portrait := $Root/Card/Body/Content/Row/Portrait/Picture as ObjectPortrait
@onready var _name := $Root/Card/Body/Content/Row/Info/Name as Label
@onready var _level := $Root/Card/Body/Content/Row/Info/Level as Label
@onready var _stats := $Root/Card/Body/Content/Row/Info/Stats as HBoxContainer
@onready var _close := $Root/Card/Body/Close as Button
@onready var _bg := $Root/Card/Body/Bg as Control


func _ready() -> void:
	_card.visible = false
	_close.pressed.connect(select.bind(null))
	if map:
		_highlight = SelectionHighlight.new()
		_highlight.name = "SelectionHighlight"
		var ground := map.shadows()
		(ground if ground else map).add_child(_highlight)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and selected:
		select(null)
		return
	if not (e is InputEventMouseButton) or e.button_index != MOUSE_BUTTON_LEFT:
		return
	if e.pressed:
		_press = e.position
		return
	if _press == Vector2.INF:
		return
	var moved: float = (e.position - _press).length()
	_press = Vector2.INF
	if moved <= TAP_SLOP:
		select(object_at(screen_to_map(e.position)))


## Viewport px → map px (through the camera).
func screen_to_map(p: Vector2) -> Vector2:
	var to_map := map.get_global_transform().affine_inverse() * map.get_viewport().get_canvas_transform().affine_inverse()
	return to_map * p


static func selectable(o: MapObject) -> bool:
	return o is Turret or o is Drill


## The turret / drill under a map point: a footprint-sized box around its ground point (a drill in a
## vein slot stands at the slot, not on its cells) plus HIT_UP cells above it; nearest wins.
func object_at(p: Vector2) -> MapObject:
	var best: MapObject = null
	var best_d := INF
	for o in map.objects():
		if not selectable(o):
			continue
		var f := Vector2(o.get_footprint()) * MapGrid.CELL
		var top_left := o.position - Vector2(f.x * 0.5, f.y * 0.5 + HIT_UP * MapGrid.CELL.y)
		var rect := Rect2(top_left, Vector2(f.x, f.y + HIT_UP * MapGrid.CELL.y))
		if rect.has_point(p):
			var d := p.distance_to(o.position)
			if d < best_d:
				best_d = d
				best = o
	return best


func select(o: MapObject) -> void:
	if o == selected:
		return
	selected = o
	if _highlight:
		_highlight.target = o
		_highlight.range_px = (o as Turret).get_rig().range_px if o is Turret else 0.0
	if o == null:
		_hide_card()
		return
	_level.text = "Рівень 1"
	if o is Turret:
		var t := o as Turret
		_portrait.rig = t.get_rig()
		_name.text = t.display_name()
	else:
		_portrait.show_sprites(o)
		_name.text = "Бур" if o is Drill else String(o.name)
	_refresh()
	_show_card()


## Stat tiles of the selected object: [[icon kind, value, caption], …] (up to 4).
func stats_of(o: MapObject) -> Array:
	if o is Turret:
		var r := (o as Turret).get_rig()
		var out := [
			[StatIcon.Kind.DAMAGE, _num(r.damage), "Урон"],
			[StatIcon.Kind.RATE, "%s/с" % _num(r.fire_rate), "Темп"],
			[StatIcon.Kind.RANGE, str(int(round(r.range_px / MapGrid.CELL.x))), "Дальність"],
		]
		if r is GrenadeLauncherRig:
			out.append([StatIcon.Kind.BLAST, _num((r as GrenadeLauncherRig).blast / MapGrid.CELL.x), "Вибух"])
		return out
	if o is Drill:
		var d := o as Drill
		return [
			[StatIcon.Kind.CRYSTAL, "%d/%d" % [d.stored, d.rig.storage], "Сховище"],
			[StatIcon.Kind.CRYSTAL, "+%d" % d.rig.crystals_per_cycle, "За цикл"],
			[StatIcon.Kind.CLOCK, "%s с" % _num(d.active_rig().cycle_len()), "Цикл"],
		]
	return []


func _refresh() -> void:
	var st := stats_of(selected)
	for i in TILES.size():
		var tile := _stats.get_node(TILES[i]) as Control
		tile.visible = i < st.size()
		if i < st.size():
			(tile.get_node("Box/Icon") as StatIcon).kind = st[i][0]
			(tile.get_node("Box/Value") as Label).text = st[i][1]
			(tile.get_node("Box/Caption") as Label).text = st[i][2]
	_fit_width(st.size())


## Value shown on tile `i` (tests).
func tile_value(i: int) -> String:
	return (_stats.get_node(TILES[i] + "/Box/Value") as Label).text


## The card is as wide as its tiles: 3 tiles = CARD_W, each more adds one tile.
func _fit_width(n: int) -> void:
	var tile := _stats.get_node(TILES[0]) as Control
	var w := CARD_W + maxi(0, n - 3) * (tile.custom_minimum_size.x + _stats.get_theme_constant("separation"))
	_card.offset_left = -w * 0.5
	_card.offset_right = w * 0.5


static func _num(v: float) -> String:
	return str(int(round(v))) if is_equal_approx(v, round(v)) else "%.1f" % v


func _process(_dt: float) -> void:
	if selected and not is_instance_valid(selected):
		select(null)
	elif selected is Drill:
		_refresh()  # the storage fills while the card is open


func _show_card() -> void:
	_card.visible = true
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.modulate.a = 0.0
	_body.position.y = 40.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_body, "position:y", 0.0, 0.22)
	tw.tween_property(_card, "modulate:a", 1.0, 0.18)


func _hide_card() -> void:
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE  # a fading card does not catch taps on the map
	var tw := create_tween().set_parallel()
	tw.tween_property(_body, "position:y", 40.0, 0.15)
	tw.tween_property(_card, "modulate:a", 0.0, 0.15)
	tw.chain().tween_callback(func() -> void: _card.visible = selected != null)
