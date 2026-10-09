class_name MapCamera
extends Camera2D
## Game camera over a map. Phone: one finger drags, two fingers pinch-zoom (and drag).
## PC: drag with any mouse button, wheel zooms to the cursor, trackpad pan / pinch.

@export var map: GameMap
@export_range(0.1, 1.0, 0.01) var zoom_min := 0.25
@export_range(1.0, 6.0, 0.1) var zoom_max := 3.0
@export_range(1.01, 1.5, 0.01) var wheel_step := 1.12
## Left / right mouse button drags the map. Off: only the middle button (test scenes use clicks).
@export var drag_with_any_button := true
## With `drag_with_any_button` off: the right button drags too (map editor: left paints).
@export var drag_with_right := false
## One finger drags the map. Off: only two fingers (map editor: one finger paints).
@export var one_finger_pan := true

var _touches := {}
var _pinch_dist := 0.0
var _pinch_centre := Vector2.ZERO
var _dragging := false


func _ready() -> void:
	if map and map.grid:
		var size := map.grid.size_px()
		limit_left = 0
		limit_top = 0
		limit_right = int(size.x)
		limit_bottom = int(size.y)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
		_pinch_dist = _touch_dist()
		if _touches.size() == 2:
			_pinch_centre = _touch_centre()
	elif e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() == 1 and one_finger_pan:
			position -= e.relative / zoom
		elif _touches.size() == 2:
			var d := _touch_dist()
			var centre := _touch_centre()
			if _pinch_dist > 0.0 and d > 0.0:
				_zoom_at(d / _pinch_dist, centre)
			if not one_finger_pan:
				position -= (centre - _pinch_centre) / zoom
			_pinch_dist = d
			_pinch_centre = centre
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_zoom_at(wheel_step, e.position)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_zoom_at(1.0 / wheel_step, e.position)
		elif e.button_index == MOUSE_BUTTON_MIDDLE or (drag_with_any_button and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]) \
				or (drag_with_right and e.button_index == MOUSE_BUTTON_RIGHT):
			_dragging = e.pressed
	elif e is InputEventMouseMotion and _dragging and _touches.is_empty():
		position -= e.relative / zoom
	elif e is InputEventPanGesture:
		position += e.delta * 20.0 / zoom
	elif e is InputEventMagnifyGesture:
		_zoom_at(e.factor, e.position)
	_clamp()


## Never zoom out past the map edges.
func _min_zoom() -> float:
	if map == null or map.grid == null:
		return zoom_min
	var vp := get_viewport_rect().size
	var size := map.grid.size_px()
	return maxf(zoom_min, maxf(vp.x / size.x, vp.y / size.y))


func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	var before := get_canvas_transform().affine_inverse() * screen_pos
	var z := clampf(zoom.x * factor, _min_zoom(), zoom_max)
	zoom = Vector2(z, z)
	force_update_scroll()
	var after := get_canvas_transform().affine_inverse() * screen_pos
	position += before - after


func _clamp() -> void:
	if map == null or map.grid == null:
		return
	var size := map.grid.size_px()
	var half := get_viewport_rect().size * 0.5 / zoom
	position.x = clampf(position.x, half.x, maxf(half.x, size.x - half.x))
	position.y = clampf(position.y, half.y, maxf(half.y, size.y - half.y))


func _touch_dist() -> float:
	if _touches.size() < 2:
		return 0.0
	var v: Array = _touches.values()
	return (v[0] as Vector2).distance_to(v[1])


func _touch_centre() -> Vector2:
	var v: Array = _touches.values()
	return ((v[0] as Vector2) + (v[1] as Vector2)) * 0.5
