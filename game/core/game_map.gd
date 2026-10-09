@tool
class_name GameMap
extends Node2D
## A map scene: ground, build grid, corruption, world objects, enemy spawns, swarm.
## Layout of the scene (see docs/godot-editor.md):
##   Ground (chunks) · Rot (corruption) · Shadows (swarm shadows) · World (Y-sort: objects,
##   props, swarm) · Overlay (grid, editor only) · Swarm
## The grid (cell kinds: ground / pass / rock / plateau) is a resource file next to the map
## (map_NN_grid.tres), painted in the map editor. «Скинути сітку зі схеми» refills it from the layout
## image (cliff / pit → rock) and wipes the hand painting.

signal map_changed

@export var layout: Texture2D
@export_range(0.05, 0.95, 0.01) var threshold := 0.5
@export var grid: MapGrid
@export_tool_button("Скинути сітку зі схеми") var rebuild_grid_action := rebuild_grid
## Without a layout: an open grid of this many cells (test scenes). Ignored when `layout` is set.
@export var open_size := Vector2i.ZERO

@export_group("Corruption")
@export_range(0.0, 1.0, 0.01) var rot_alpha := 0.85:
	set(v): rot_alpha = v; _update_rot()
## Soft edge of the cleared circle, cells.
@export_range(0.0, 10.0, 0.1) var rot_soft := 3.0:
	set(v): rot_soft = v; _update_rot()

@export_group("Editor overlay")
@export var show_grid := true:
	set(v): show_grid = v; _redraw_overlay()
@export var show_blocked := true:
	set(v): show_blocked = v; _redraw_overlay()
@export var show_footprints := true:
	set(v): show_footprints = v; _redraw_overlay()
## Show the overlay in the running game too (debug).
@export var overlay_in_game := false

const MAX_CLEARS := 64
const KIND_NAMES := {
	MapGrid.Kind.GROUND: "земля", MapGrid.Kind.PASS: "прохід",
	MapGrid.Kind.ROCK: "скеля / прірва", MapGrid.Kind.PLATEAU: "плато",
}

var _objects_key := ""


func _enter_tree() -> void:
	# Before the children are ready: Swarm needs the grid in its _ready.
	if grid == null and layout == null and open_size.x > 0 and open_size.y > 0:
		grid = MapGrid.open(open_size.x, open_size.y)


func _ready() -> void:
	if grid == null and layout != null:
		rebuild_grid()
	_update_rot()
	_redraw_overlay()
	var ov := get_node_or_null("Overlay") as CanvasItem
	if ov and not Engine.is_editor_hint():
		ov.visible = overlay_in_game


func rebuild_grid() -> void:
	if layout == null:
		push_warning("GameMap: no layout image")
		return
	var t0 := Time.get_ticks_msec()
	var g := MapGrid.from_layout(layout.get_image(), threshold)
	if grid != null and grid.resource_path != "":
		# Keep the same .tres (the scene points at it): refill it and save.
		grid.cols = g.cols
		grid.rows = g.rows
		grid.threshold = g.threshold
		grid.kinds = g.kinds
		grid.refresh()
		ResourceSaver.save(grid)
	else:
		grid = g
	print("GameMap: grid %dx%d, rock %d, %d ms" % [grid.cols, grid.rows, grid.count_kind(MapGrid.Kind.ROCK), Time.get_ticks_msec() - t0])
	_redraw_overlay()
	map_changed.emit()


func world() -> Node2D:
	return get_node_or_null("World") as Node2D


func shadows() -> Node2D:
	return get_node_or_null("Shadows") as Node2D


func objects() -> Array[MapObject]:
	var out: Array[MapObject] = []
	var w := world()
	if w:
		for n in w.get_children():
			if n is MapObject:
				out.append(n)
	var sp := get_node_or_null("Spawns")
	if sp:
		for n in sp.get_children():
			if n is MapObject:
				out.append(n)
	return out


func spawn_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for o in objects():
		if o.is_in_group("enemy_spawn"):
			out.append(o.position)
	return out


## Cells enemies walk to (footprints of objects in group "enemy_target", e.g. the core).
func target_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for o in objects():
		if o.is_in_group("enemy_target"):
			out.append_array(o.footprint_cells())
	return out


## cell index -> extra cost of passing through buildings.
func building_costs() -> Dictionary:
	var out := {}
	if grid == null:
		return out
	for o in objects():
		var k := o.get_path_cost()
		if k <= 0.0 or o.is_in_group("enemy_target"):
			continue
		for c in o.footprint_cells():
			if grid.inside(c.x, c.y):
				out[c.y * grid.cols + c.x] = k
	return out


func build_flow_field() -> FlowField:
	var f := FlowField.new()
	f.build(grid, target_cells(), building_costs())
	return f


## Why an object can not stand where it is ("" = fine). Same rules as map_03_editor.html canPlace().
func placement_problem(o: MapObject) -> String:
	if grid == null:
		return ""
	if o.is_in_group("enemy_spawn") or not o.occupies_cells():
		for c in o.footprint_cells():
			if not grid.inside(c.x, c.y):
				return "за межами карти"
		return ""
	var occ := {}
	for other in objects():
		if other == o or not other.occupies_cells() or other.is_in_group("enemy_spawn"):
			continue
		for c in other.footprint_cells():
			occ[c] = other
	for c in o.footprint_cells():
		if not grid.inside(c.x, c.y):
			return "за межами карти"
		if not (o is Prop) and not grid.can_build(c.x, c.y):
			return "клітинка %d,%d: тут не будують (%s)" % [c.x, c.y, KIND_NAMES[grid.kind(c.x, c.y)]]
		if occ.has(c):
			return "клітинка %d,%d: зайнято (%s)" % [c.x, c.y, (occ[c] as Node).name]
	return ""


func _process(_dt: float) -> void:
	# Objects moved / added / removed → refresh the overlay and the corruption.
	var key := ""
	for o in objects():
		key += "%s%s;" % [o.cell, o.get_footprint()]
	if key != _objects_key:
		_objects_key = key
		_update_rot()
		_redraw_overlay()
		if not Engine.is_editor_hint():
			map_changed.emit()


## Redraw the grid overlay (after painting cell kinds).
func refresh_overlay() -> void:
	_redraw_overlay()


func _redraw_overlay() -> void:
	var ov := get_node_or_null("Overlay") as CanvasItem
	if ov:
		ov.queue_redraw()


func _update_rot() -> void:
	var rot := get_node_or_null("Rot") as CanvasItem
	if rot == null or grid == null:
		return
	var mat := rot.material as ShaderMaterial
	if mat == null:
		return
	var clears := PackedVector4Array()
	clears.resize(MAX_CLEARS)
	var n := 0
	for o in objects():
		var rad := o.get_clear_radius()
		if rad <= 0.0 or n >= MAX_CLEARS:
			continue
		var f := o.get_footprint()
		var centre := grid.cell_origin(o.cell) + Vector2(f.x * MapGrid.CELL.x, f.y * MapGrid.CELL.y) * 0.5
		var r := (rad + maxf(f.x, f.y) * 0.5) * MapGrid.CELL.x
		clears[n] = Vector4(centre.x, centre.y, r, rot_soft * MapGrid.CELL.x)
		n += 1
	mat.set_shader_parameter("clears", clears)
	mat.set_shader_parameter("clear_count", n)
	mat.set_shader_parameter("alpha", rot_alpha)
	mat.set_shader_parameter("map_size", (rot as Control).size if rot is Control else grid.size_px())
	mat.set_shader_parameter("cam_k", MapGrid.CELL.y / MapGrid.CELL.x)
