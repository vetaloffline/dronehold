class_name MapEditor
extends Node2D
## Map editor (development tool, removed for release): paint cell kinds — ground / pass / rock /
## plateau — over the map and save them into the map's grid file (map_NN_grid.tres).
## Second layer («Дрон» mode): where cargo drones do not fly (purple), saved in the same file.
##   PC: left — paint, right / middle drag — camera, wheel — zoom.
##   Phone: one finger — paint, two fingers — move / zoom.
##   Keys: 1–4 kind (in «Дрон»: 1 — не літати, 2 — літати), D cells / drone, [ ] brush size,
##   R brush / rectangle, Ctrl+Z undo, Ctrl+S save.
## Slimes keep crawling, so you see at once how they go around what you paint.
## Saving works when the game runs from Godot (res:// is read-only in an exported build).

const KIND_ORDER := [MapGrid.Kind.GROUND, MapGrid.Kind.PASS, MapGrid.Kind.ROCK, MapGrid.Kind.PLATEAU]
const KIND_LABELS := {
	MapGrid.Kind.GROUND: "Земля — будувати, ходять",
	MapGrid.Kind.PASS: "Прохід — не будувати, ходять",
	MapGrid.Kind.ROCK: "Скеля — нічого",
	MapGrid.Kind.PLATEAU: "Плато — будувати, не ходять",
}
## Swatch colours (opaque versions of the overlay colours; ground — green).
const KIND_SWATCH := {
	MapGrid.Kind.GROUND: Color(0.35, 0.8, 0.35),
	MapGrid.Kind.PASS: Color(1, 0.85, 0.2),
	MapGrid.Kind.ROCK: Color(1, 0.25, 0.25),
	MapGrid.Kind.PLATEAU: Color(0.3, 0.55, 1),
}
## Drone layer brushes: no-fly (purple) / fly (clears it).
const FLY_SWATCH := {true: Color(0.62, 0.22, 1.0), false: Color(0.35, 0.8, 0.35)}
const FLY_LABELS := {true: "Не літати — дрон облітає", false: "Літати — дрон пролітає"}
enum Layer { CELLS, DRONE }
const SIZES := [1, 2, 3, 5, 8]
const UNDO_MAX := 100
const SLIMES_ON := 50

@onready var _map := $Map03 as GameMap
@onready var _swarm := $Map03/Swarm as Swarm
@onready var _camera := $Camera as MapCamera

var kind: MapGrid.Kind = MapGrid.Kind.PASS
## Which layer the brush paints: cell kinds or the drone no-fly layer.
var layer := Layer.CELLS
## Drone layer brush: true paints no-fly, false clears it.
var no_fly := true
var brush := 2
var rect_tool := false
var dirty := false

var _stroke := {}            ## cell index → value before this stroke (kind or no-fly 0/1)
var _painting := false
var _last_cell := Vector2i(-9999, -9999)
var _rect_from := Vector2i.ZERO
var _undo: Array[Dictionary] = []  ## {"layer": Layer, "cells": {index: old value}}
var _saved := PackedByteArray()   ## kinds on disk (to revert when leaving without saving)
var _saved_fly := PackedByteArray()  ## drone layer on disk
var _hover := Vector2i(-1, -1)
var _touches := {}
var _leave_armed := false
var _message := ""

var _cursor: Node2D
var _info: Label
var _kind_buttons := {}
var _fly_buttons := {}
var _layer_buttons := {}
var _kinds_box: Control
var _fly_box: Control
var _size_buttons := {}
var _tool_button: Button
var _slimes_button: Button
var _grid_button: Button


func _ready() -> void:
	_saved = _map.grid.kinds.duplicate()
	_saved_fly = _map.grid.no_fly.duplicate()
	var ov := _map.get_node_or_null("Overlay") as CanvasItem
	if ov:
		ov.visible = true
	_map.show_grid = true
	_map.show_blocked = true
	_cursor = Node2D.new()
	_cursor.z_index = 20
	_cursor.draw.connect(_draw_cursor)
	_map.add_child(_cursor)
	for o in _map.objects():
		if o.is_in_group("enemy_target"):
			_camera.position = o.position
			break
	_build_ui()
	_refresh_ui()


# ---- painting ---------------------------------------------------------------------------------

func cell_under(screen_pos: Vector2) -> Vector2i:
	return _map.grid.cell_at(get_viewport().get_canvas_transform().affine_inverse() * screen_pos)


## Cells the brush covers around `c` (N×N square, `c` in the middle).
func brush_cells(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var o := c - Vector2i((brush - 1) / 2, (brush - 1) / 2)
	for r in brush:
		for q in brush:
			out.append(o + Vector2i(q, r))
	return out


func paint_cell(c: Vector2i) -> void:
	var g := _map.grid
	if not g.inside(c.x, c.y):
		return
	var i := c.y * g.cols + c.x
	if layer == Layer.DRONE:
		if g.fly_blocked(c.x, c.y) == no_fly:
			return
		if not _stroke.has(i):
			_stroke[i] = 1 if g.fly_blocked(c.x, c.y) else 0
		g.set_no_fly(c.x, c.y, no_fly)
		return
	if g.kind(c.x, c.y) == kind:
		return
	if not _stroke.has(i):
		_stroke[i] = g.kinds[i]
	g.set_kind(c.x, c.y, kind)


func begin_stroke(c: Vector2i) -> void:
	_painting = true
	_stroke = {}
	_last_cell = c
	_rect_from = c
	if not rect_tool:
		for b in brush_cells(c):
			paint_cell(b)
		_map.refresh_overlay()


func move_stroke(c: Vector2i) -> void:
	if not _painting or c == _last_cell:
		return
	if not rect_tool:
		# Every cell on the way, so a fast drag leaves no gaps.
		var steps := maxi(absi(c.x - _last_cell.x), absi(c.y - _last_cell.y))
		for k in range(1, steps + 1):
			var p := Vector2(_last_cell).lerp(Vector2(c), float(k) / steps).round()
			for b in brush_cells(Vector2i(p)):
				paint_cell(b)
		_map.refresh_overlay()
	_last_cell = c
	_cursor.queue_redraw()


func end_stroke() -> void:
	if not _painting:
		return
	_painting = false
	if rect_tool:
		var a := Vector2i(mini(_rect_from.x, _last_cell.x), mini(_rect_from.y, _last_cell.y))
		var b := Vector2i(maxi(_rect_from.x, _last_cell.x), maxi(_rect_from.y, _last_cell.y))
		for r in range(a.y, b.y + 1):
			for q in range(a.x, b.x + 1):
				paint_cell(Vector2i(q, r))
		_map.refresh_overlay()
	if _stroke.is_empty():
		return
	_undo.append({"layer": layer, "cells": _stroke})
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()
	_stroke = {}
	_changed()


## Second finger came down: this was a camera gesture, not painting — take the dab back.
func cancel_stroke() -> void:
	_painting = false
	_revert({"layer": layer, "cells": _stroke})
	_stroke = {}
	_map.refresh_overlay()


func undo() -> void:
	if _undo.is_empty():
		_message = "Нема що скасовувати"
	else:
		_revert(_undo.pop_back())
		_changed()
	_refresh_ui()


func _revert(stroke: Dictionary) -> void:
	var g := _map.grid
	var cells: Dictionary = stroke.cells
	for i in cells:
		if stroke.layer == Layer.DRONE:
			g.set_no_fly(i % g.cols, i / g.cols, cells[i] == 1)
		else:
			g.set_kind(i % g.cols, i / g.cols, cells[i])


## After a stroke / undo: slimes take the new paths, and the ones now inside a wall are removed.
func _changed() -> void:
	dirty = _map.grid.kinds != _saved or _map.grid.no_fly != _saved_fly
	_leave_armed = false
	_map.refresh_overlay()
	_map.map_changed.emit()
	var s := _swarm.sim
	if s:
		for i in range(s.count - 1, -1, -1):
			var c := _map.grid.cell_at(Vector2(s.px[i], s.py[i]))
			if _map.grid.is_blocked(c.x, c.y):
				s.remove_slot(i)
	_refresh_ui()


func save() -> void:
	var g := _map.grid
	var err := ResourceSaver.save(g, g.resource_path)
	if err == OK:
		_saved = g.kinds.duplicate()
		_saved_fly = g.no_fly.duplicate()
		dirty = false
		_message = "Збережено: %s" % g.resource_path
	else:
		_message = "Не вдалося зберегти (помилка %d). Зберігати можна, коли гра запущена з Godot." % err
	_refresh_ui()


func _leave() -> void:
	if dirty and not _leave_armed:
		_leave_armed = true
		_message = "Є незбережені зміни. «Меню» ще раз — вийти без збереження."
		_refresh_ui()
		return
	if dirty:
		# The grid resource is shared with the game scene: put back what is on disk.
		_map.grid.kinds = _saved.duplicate()
		_map.grid.no_fly = _saved_fly.duplicate()
		_map.grid.refresh()
	get_tree().change_scene_to_file(MainMenu.MENU)


# ---- input ------------------------------------------------------------------------------------

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = true
			if _touches.size() == 1:
				begin_stroke(cell_under(e.position))
			elif _painting:
				cancel_stroke()
		else:
			_touches.erase(e.index)
			if _touches.is_empty():
				end_stroke()
	elif e is InputEventScreenDrag:
		if _touches.size() == 1:
			move_stroke(cell_under(e.position))
	elif e is InputEventMouseButton and e.device != InputEvent.DEVICE_ID_EMULATION:
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				begin_stroke(cell_under(e.position))
			else:
				end_stroke()
	elif e is InputEventMouseMotion and e.device != InputEvent.DEVICE_ID_EMULATION:
		_hover = cell_under(e.position)
		if _painting:
			move_stroke(_hover)
		_cursor.queue_redraw()
		_refresh_ui()
	elif e is InputEventKey and e.pressed and not e.echo:
		_key(e as InputEventKey)


func _key(k: InputEventKey) -> void:
	var ctrl := k.ctrl_pressed or k.meta_pressed
	if ctrl and k.keycode == KEY_Z:
		undo()
	elif ctrl and k.keycode == KEY_S:
		save()
	elif k.keycode == KEY_D:
		set_layer(Layer.CELLS if layer == Layer.DRONE else Layer.DRONE)
	elif layer == Layer.DRONE and (k.keycode == KEY_1 or k.keycode == KEY_2):
		set_no_fly(k.keycode == KEY_1)
	elif k.keycode >= KEY_1 and k.keycode <= KEY_4:
		set_kind(KIND_ORDER[k.keycode - KEY_1])
	elif k.keycode == KEY_BRACKETLEFT:
		set_brush(SIZES[maxi(0, SIZES.find(brush) - 1)])
	elif k.keycode == KEY_BRACKETRIGHT:
		set_brush(SIZES[mini(SIZES.size() - 1, SIZES.find(brush) + 1)])
	elif k.keycode == KEY_R:
		set_rect_tool(not rect_tool)


func set_kind(k: MapGrid.Kind) -> void:
	kind = k
	_refresh_ui()


## «Клітинки» — cell kinds (slimes / building), «Дрон» — where drones do not fly.
func set_layer(l: Layer) -> void:
	layer = l
	_map.show_blocked = l == Layer.CELLS
	_map.show_no_fly = l == Layer.DRONE
	_map.refresh_overlay()
	_refresh_ui()


func set_no_fly(on: bool) -> void:
	no_fly = on
	_refresh_ui()


func set_brush(n: int) -> void:
	brush = n
	_refresh_ui()


func set_rect_tool(on: bool) -> void:
	rect_tool = on
	_refresh_ui()


# ---- drawing ----------------------------------------------------------------------------------

func _draw_cursor() -> void:
	var col := (FLY_SWATCH[no_fly] if layer == Layer.DRONE else KIND_SWATCH[kind]) as Color
	if _painting and rect_tool:
		var a := Vector2i(mini(_rect_from.x, _last_cell.x), mini(_rect_from.y, _last_cell.y))
		var b := Vector2i(maxi(_rect_from.x, _last_cell.x), maxi(_rect_from.y, _last_cell.y))
		var r := Rect2(_map.grid.cell_origin(a), Vector2(b - a + Vector2i.ONE) * MapGrid.CELL)
		_cursor.draw_rect(r, Color(col, 0.3))
		_cursor.draw_rect(r, col, false, 3.0)
		return
	if not _map.grid.inside(_hover.x, _hover.y):
		return
	var cells := brush_cells(_hover)
	if rect_tool:
		cells = [_hover]
	var o := _map.grid.cell_origin(cells[0])
	_cursor.draw_rect(Rect2(o, Vector2(cells[-1] - cells[0] + Vector2i.ONE) * MapGrid.CELL), col, false, 2.0)


# ---- UI ---------------------------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	top.add_child(_button("Меню", _leave))
	top.add_child(_button("Зберегти", save))
	top.add_child(_button("Скасувати", undo))
	var layers := HBoxContainer.new()
	box.add_child(layers)
	var layer_group := ButtonGroup.new()
	for spec in [[Layer.CELLS, "Клітинки"], [Layer.DRONE, "Дрон"]]:
		var lb := _button(spec[1], set_layer.bind(spec[0]))
		lb.toggle_mode = true
		lb.button_group = layer_group
		lb.custom_minimum_size.x = 150
		layers.add_child(lb)
		_layer_buttons[spec[0]] = lb
	var kbox := VBoxContainer.new()
	box.add_child(kbox)
	_kinds_box = kbox
	var kinds := ButtonGroup.new()
	for k in KIND_ORDER:
		var b := _button(KIND_LABELS[k], set_kind.bind(k))
		b.toggle_mode = true
		b.button_group = kinds
		b.icon = _swatch(KIND_SWATCH[k])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		kbox.add_child(b)
		_kind_buttons[k] = b
	var fbox := VBoxContainer.new()
	box.add_child(fbox)
	_fly_box = fbox
	var fly_group := ButtonGroup.new()
	for on in [true, false]:
		var fb := _button(FLY_LABELS[on], set_no_fly.bind(on))
		fb.toggle_mode = true
		fb.button_group = fly_group
		fb.icon = _swatch(FLY_SWATCH[on])
		fb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		fbox.add_child(fb)
		_fly_buttons[on] = fb
	var sizes := HBoxContainer.new()
	box.add_child(sizes)
	var size_group := ButtonGroup.new()
	for n in SIZES:
		var b := _button(str(n), set_brush.bind(n))
		b.toggle_mode = true
		b.button_group = size_group
		b.custom_minimum_size.x = 64
		sizes.add_child(b)
		_size_buttons[n] = b
	_tool_button = _button("", func() -> void: set_rect_tool(not rect_tool))
	box.add_child(_tool_button)
	var row := HBoxContainer.new()
	box.add_child(row)
	_grid_button = _button("", func() -> void:
		_map.show_grid = not _map.show_grid
		_refresh_ui())
	row.add_child(_grid_button)
	_slimes_button = _button("", _toggle_slimes)
	row.add_child(_slimes_button)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 20)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.x = 440
	box.add_child(_info)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 60)
	b.add_theme_font_size_override("font_size", 22)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	# Selected brush / size must stand out: blue with a white frame.
	var on := StyleBoxFlat.new()
	on.bg_color = Color(0.2, 0.42, 0.78)
	on.set_border_width_all(3)
	on.border_color = Color.WHITE
	on.set_content_margin_all(6)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	return b


func _swatch(c: Color) -> ImageTexture:
	var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


func _toggle_slimes() -> void:
	if _swarm.target_count > 0:
		_swarm.target_count = 0
		_swarm.sim.clear()
	else:
		_swarm.target_count = SLIMES_ON
	_refresh_ui()


func _refresh_ui() -> void:
	if _info == null:
		return
	(_kind_buttons[kind] as Button).set_pressed_no_signal(true)
	(_fly_buttons[no_fly] as Button).set_pressed_no_signal(true)
	(_layer_buttons[layer] as Button).set_pressed_no_signal(true)
	_kinds_box.visible = layer == Layer.CELLS
	_fly_box.visible = layer == Layer.DRONE
	(_size_buttons[brush] as Button).set_pressed_no_signal(true)
	_tool_button.text = "Інструмент: прямокутник" if rect_tool else "Інструмент: пензель %d×%d" % [brush, brush]
	_grid_button.text = "Сітка: є" if _map.show_grid else "Сітка: нема"
	_slimes_button.text = "Слизні: є" if _swarm.target_count > 0 else "Слизні: нема"
	var g := _map.grid
	var hover := ""
	if g.inside(_hover.x, _hover.y):
		hover = "клітинка %d, %d — %s%s\n" % [_hover.x, _hover.y, GameMap.KIND_NAMES[g.kind(_hover.x, _hover.y)],
			", дрон не літає" if g.fly_blocked(_hover.x, _hover.y) else ""]
	var bad := 0
	for o in _map.objects():
		if _map.placement_problem(o) != "":
			bad += 1
	_info.text = "%sземля %d · прохід %d · скеля %d · плато %d · дрон не літає %d\n%s%s%s" % [
		hover, g.count_kind(MapGrid.Kind.GROUND), g.count_kind(MapGrid.Kind.PASS),
		g.count_kind(MapGrid.Kind.ROCK), g.count_kind(MapGrid.Kind.PLATEAU), g.no_fly_count(),
		"● не збережено\n" if dirty else "",
		"Об'єктів не на місці: %d (червона рамка)\n" % bad if bad > 0 else "",
		_message]
