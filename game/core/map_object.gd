@tool
class_name MapObject
extends Node2D
## Anything placed on the map grid: buildings, veins, props, spawn points.
## The node origin is the object's ground point (Y-sort key). In the editor, drag the object —
## it snaps to the grid cell under it; or type `cell` in the Inspector.
## Placement rule = map_03_editor.html drawObj(): ground point = cell origin +
## ((w/2 + shift.x)·cell_w, (h/2 + shift.y)·cell_h); sprite scale = `map_scale`.

## Top-left cell of the footprint.
@export var cell := Vector2i(0, 0):
	set(v):
		cell = v
		_place()

var _placed_at := Vector2.INF
## Build-mode preview (Builder): drawn on the map, but not a part of it — GameMap.objects() skips it,
## so it blocks no cells, joins no groups and nothing targets it. Set before adding to the tree.
var ghost := false


## Footprint in cells. Override in subclasses.
func get_footprint() -> Vector2i:
	return Vector2i(1, 1)


## Shift of the ground point from the footprint centre, in cells. Override.
func get_map_shift() -> Vector2:
	return Vector2.ZERO


## Sprite px → map px. Override.
func get_map_scale() -> float:
	return 1.0


## Radius (cells, beyond the footprint) that clears the corruption around it; 0 = none. Override.
func get_clear_radius() -> float:
	return 0.0


## Extra path cost for enemies to pass through (they chew through buildings); 0 = free. Override.
func get_path_cost() -> float:
	return 0.0


## Whether the footprint occupies cells (decor props do not).
func occupies_cells() -> bool:
	return true


## Drawn mirrored left-right (a drill in a vein's left slot). Override.
func get_map_flip() -> bool:
	return false


func _map_scale_vec() -> Vector2:
	var s := get_map_scale()
	return Vector2(-s if get_map_flip() else s, s)


## Drone landing points: Marker2D children named DronePad* (set in the object's own scene, so every
## object of the type has them), in the parent's (map) space. A mirrored object mirrors them too.
func drone_pads() -> PackedVector2Array:
	var out := PackedVector2Array()
	for c in get_children():
		if c is Marker2D and String(c.name).begins_with("DronePad"):
			out.append(transform * (c as Marker2D).position)
	return out


## Editor: a ring with a dot on every drone pad (call from _draw of objects that have pads).
func draw_drone_pads() -> void:
	if not Engine.is_editor_hint():
		return
	var k := 1.0 / maxf(0.001, absf(get_map_scale()))
	for c in get_children():
		if c is Marker2D and String(c.name).begins_with("DronePad"):
			var p := (c as Marker2D).position
			draw_set_transform(p, 0.0, Vector2(1.0, 0.75))
			draw_arc(Vector2.ZERO, 14.0 * k, 0.0, TAU, 32, Color(0.4, 0.9, 1.0, 0.95), 3.0 * k, true)
			draw_circle(Vector2.ZERO, 4.0 * k, Color(0.4, 0.9, 1.0, 0.95))
			draw_set_transform(Vector2.ZERO)


func ground_point_for(c: Vector2i) -> Vector2:
	var f := get_footprint()
	var sh := get_map_shift()
	return Vector2((c.x + f.x * 0.5 + sh.x) * MapGrid.CELL.x, (c.y + f.y * 0.5 + sh.y) * MapGrid.CELL.y)


func cell_for_point(p: Vector2) -> Vector2i:
	var f := get_footprint()
	var sh := get_map_shift()
	return Vector2i(int(round(p.x / MapGrid.CELL.x - f.x * 0.5 - sh.x)), int(round(p.y / MapGrid.CELL.y - f.y * 0.5 - sh.y)))


## Map px square of the cells it takes, where it is drawn (build / selection highlights). Override
## when the object does not stand on its cells (a drill in a vein slot).
func footprint_rect() -> Rect2:
	return Rect2(Vector2(cell) * MapGrid.CELL, Vector2(get_footprint()) * MapGrid.CELL)


func footprint_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var f := get_footprint()
	for r in f.y:
		for c in f.x:
			out.append(cell + Vector2i(c, r))
	return out


func _enter_tree() -> void:
	_place()


func _place() -> void:
	if not is_inside_tree():
		return
	scale = _map_scale_vec()
	position = ground_point_for(cell)
	_placed_at = position


## Editor: snap to the grid when dragged. Call from subclasses' _process (they usually animate).
func editor_snap() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if position != _placed_at:
		var c := cell_for_point(position)
		if c != cell:
			cell = c
		else:
			_place()
	if scale != _map_scale_vec():
		scale = _map_scale_vec()


func _process(_dt: float) -> void:
	editor_snap()
