@tool
class_name BlockBuilding
extends MapObject
## Placeholder building drawn by code as a block over its footprint (wall, relay — until they get
## art). It has hit points (`hp`, rig.max_hp): slimes do not bite yet, so for now it only makes
## them walk round (rig.path_cost); at 0 hp it is removed (GameMap notices → map_changed).
## A store (rig.store, the relay): joins "storage", drones land on its DronePad* markers.
## Node origin = ground point = footprint centre; drawn in map px (scale 1).

signal hp_changed(hp: float, max_hp: float)

@export var rig: BlockRig:
	set(v):
		if rig and rig.changed.is_connected(_on_rig_changed):
			rig.changed.disconnect(_on_rig_changed)
		rig = v
		if rig:
			rig.changed.connect(_on_rig_changed)
		_on_rig_changed()
## Name on the info card / build menu.
@export var title := ""

var hp := 0.0


func get_footprint() -> Vector2i:
	return rig.footprint if rig else Vector2i(2, 2)


func get_path_cost() -> float:
	return rig.path_cost if rig else 0.0


func get_clear_radius() -> float:
	return rig.clear_radius if rig else 0.0


func display_name() -> String:
	return title if title != "" else String(name)


func _enter_tree() -> void:
	if rig and rig.store and not ghost:
		add_to_group("storage", true)
	super._enter_tree()


func _ready() -> void:
	hp = rig.max_hp if rig else 0.0


func _on_rig_changed() -> void:
	_place()
	queue_redraw()


## Takes `amount` hit points; at 0 the building is removed. Returns true if that destroyed it.
func damage(amount: float) -> bool:
	if hp <= 0.0 or amount <= 0.0:
		return false
	hp = maxf(0.0, hp - amount)
	hp_changed.emit(hp, rig.max_hp if rig else hp)
	queue_redraw()
	if hp <= 0.0:
		queue_free()
		return true
	return false


func _draw() -> void:
	if rig == null:
		return
	var top := draw_block(self, rig)
	if rig.max_hp > 0.0 and hp < rig.max_hp and hp > 0.0:
		var bar := Rect2(top.position.x + 6.0, top.position.y - 12.0, top.size.x - 12.0, 6.0)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp / rig.max_hp, bar.size.y)), Color(0.35, 0.95, 0.35))
	draw_drone_pads()


## The block of `r` on `ci` around its ground point (0, 0), map px: cast shadow, front, top (a relay
## gets a mast). The build menu card draws it the same way. Returns the top face rect.
static func draw_block(ci: CanvasItem, r: BlockRig, shadow := true) -> Rect2:
	var w := r.footprint.x * MapGrid.CELL.x
	var d := r.footprint.y * MapGrid.CELL.y
	var h := r.height
	# Ground rect of the footprint around the origin; the top face is it lifted by `h`.
	var g := Rect2(-w * 0.5, -d * 0.5, w, d)
	var top := Rect2(g.position - Vector2(0, h), g.size)
	var front := Rect2(Vector2(g.position.x, g.end.y - h), Vector2(w, h))
	if shadow:
		# Cast shadow: sun upper right, falls left.
		var sh := Vector2(-h * 0.6, 0.0)
		ci.draw_colored_polygon(PackedVector2Array([g.position, g.position + sh, Vector2(g.position.x, g.end.y) + sh,
			Vector2(g.position.x, g.end.y)]), Color(0, 0, 0, 0.28))
	ci.draw_rect(front, r.side_color)
	ci.draw_rect(top, r.top_color)
	ci.draw_rect(top.grow(-4.0), r.top_color.lightened(0.12))
	ci.draw_rect(top, r.edge_color, false, 2.0)
	ci.draw_rect(front, r.edge_color, false, 2.0)
	if r.store:
		# Relay: a mast with a light on the roof.
		var c := top.get_center()
		ci.draw_line(c, c - Vector2(0, 22), r.edge_color, 3.0)
		ci.draw_circle(c - Vector2(0, 24), 4.0, Color(0.45, 0.9, 1.0))
	return top


## Box of draw_block() around the ground point (for fitting it into a card picture).
static func block_box(r: BlockRig) -> Rect2:
	var w := r.footprint.x * MapGrid.CELL.x
	var d := r.footprint.y * MapGrid.CELL.y
	var up := r.height + (26.0 if r.store else 0.0)
	return Rect2(-w * 0.5, -d * 0.5 - up, w, d + up)


func _process(_dt: float) -> void:
	editor_snap()
	if Engine.is_editor_hint():
		queue_redraw()
