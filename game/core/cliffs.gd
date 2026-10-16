@tool
class_name Cliffs
extends Node2D
## Cliffs from painted cells (docs/concept.md «Скелі»). The cells live in a CliffCells layer (`cells`,
## painted in the Godot editor); every painted cell gets one drawn rock block (CliffBlocks atlas,
## art/maps/cliffs/). Blocks are wider than a cell and overlap their neighbours, so cells painted side by
## side read as one cliff; Y-sort hides the front of a block behind the block south of it, so the same set
## of blocks fits any shape — no separate pieces for corners or ends.
## Two tiles in the layer: x = 0 — wall (stone columns, for the map edge), x = 1 — natural rock (inside the
## map). Rock height per cell (CliffRig «Rock height»):
##   seed = an end or a corner of a ridge: a rock cell with ≤ 1 rock side neighbour, or with 2 that are
##          not opposite (an L);
##   d    = steps from the nearest seed through rock cells (4-neighbours); no seed in the group → 9;
##   kind = d 0 → low, 1 → mid, 2 → tall (mid when the noise < 0.4), ≥ 3 → tall (mid when the noise <
##          dip_noise); peak on the cell of a hump where the noise is highest within peak_radius cells and
##          above peak_noise. Noise = value noise on a hump_cells grid, so humps and dips come in clumps.
## So a ridge slopes down at its ends and rises and falls along its length. The choice of block, size and
## shift per cell is a hash of the cell: the same cells always give the same cliff.
## Y-sort: one internal child per cell row at the row's south edge (− 1 px: a slime in the same row is
## drawn in front); inside a row blocks go left to right.
## Decor (Prop) on a cliff cell stands on the top of that cell's block (top_y_at) and is sorted after its row;
## after every rebuild the props in World are told to look again (Prop.refresh_cliff).
## In the game the cliff cells become ROCK (no building, no walking) and no-fly for drones; in the editor
## the grid is not touched (the map's grid file keeps its hand painting).
## The node sits at (0, 0) under World; the cells layer at (0, 0) of the GameMap.

const CELL := MapGrid.CELL
const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## Tile atlas x in the CliffCells tile set.
enum Tile { WALL, ROCK }

## The painted cells. Empty = the first CliffCells child of the GameMap.
@export var cells: CliffCells:
	set(v):
		_unhook()
		cells = v
		_hook()
		_queue_rebuild()
@export var rig: CliffRig:
	set(v):
		if rig and rig.changed.is_connected(_queue_rebuild):
			rig.changed.disconnect(_queue_rebuild)
		rig = v
		if rig and is_inside_tree():
			rig.changed.connect(_queue_rebuild)
		_queue_rebuild()

@export_group("Perimeter")
## Thickness of the ring «Обгородити периметр» paints (wall tile), cells.
@export_range(1, 20) var perimeter_cells := 2
@export_tool_button("Обгородити периметр") var perimeter_action := fill_perimeter
@export_tool_button("Стерти всі скелі") var clear_action := clear_cells

## Row → [[atlas rect, target rect], …] left to right.
var _rows := {}
## Cell → [block index, size ×, shift] of the block placed there.
var _at := {}
## Row → internal row node.
var _nodes := {}
var _queued := false
var _hooked: CliffCells


func _ready() -> void:
	y_sort_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_hook()
	if rig and not rig.changed.is_connected(_queue_rebuild):
		rig.changed.connect(_queue_rebuild)
	if not Engine.is_editor_hint():
		var m := _map()
		var c := _cells()
		if c and m and m.grid:
			apply_to_grid(m.grid, c.get_used_cells())
			c.visible = false
			m.map_changed.emit()
	rebuild()


func _map() -> GameMap:
	var n := get_parent()
	while n and not (n is GameMap):
		n = n.get_parent()
	return n as GameMap


func _cells() -> CliffCells:
	if cells:
		return cells
	var m := _map()
	if m:
		for n in m.get_children():
			if n is CliffCells:
				return n
	return null


func _hook() -> void:
	if not is_inside_tree():
		return
	var c := _cells()
	if c == _hooked:
		return
	_unhook()
	if c:
		c.cells_changed.connect(_queue_rebuild)
		_hooked = c


func _unhook() -> void:
	if _hooked and is_instance_valid(_hooked) and _hooked.cells_changed.is_connected(_queue_rebuild):
		_hooked.cells_changed.disconnect(_queue_rebuild)
	_hooked = null


## Cliff cells become ROCK (no building, no walking) and no-fly. Cells outside the grid are skipped.
static func apply_to_grid(g: MapGrid, used: Array[Vector2i]) -> void:
	for c in used:
		if g.inside(c.x, c.y):
			g.set_kind(c.x, c.y, MapGrid.Kind.ROCK)
			g.set_no_fly(c.x, c.y, true)


func _queue_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	rebuild.call_deferred()


## Place the blocks again from the painted cells.
func rebuild() -> void:
	_queued = false
	_hook()
	var c := _cells()
	var m := _map()
	var wall := {}
	var rock := {}
	if c and m and m.grid:
		for p in c.get_used_cells():
			if m.grid.inside(p.x, p.y):
				if c.get_cell_atlas_coords(p).x == Tile.ROCK:
					rock[p] = true
				else:
					wall[p] = true
	_rows = place(wall, rock) if rig and rig.blocks and rig.blocks.atlas else {}
	if _rows.is_empty():
		_at = {}
	for r in _nodes.keys():
		if not _rows.has(r):
			(_nodes[r] as Node2D).queue_free()
			_nodes.erase(r)
	for r in _rows:
		var n: Node2D = _nodes.get(r)
		if n == null:
			n = Node2D.new()
			n.name = "Row%d" % r
			n.position = Vector2(0.0, (r + 1) * CELL.y - 1.0)
			n.draw.connect(_draw_row.bind(r))
			add_child(n, false, Node.INTERNAL_MODE_BACK)
			_nodes[r] = n
		n.queue_redraw()
	if m and m.world():
		for o in m.world().get_children():
			if o is Prop:
				(o as Prop).refresh_cliff()


## The Cliffs node of a map (null when it has none).
static func of_map(m: GameMap) -> Cliffs:
	if m == null or m.world() == null:
		return null
	for o in m.world().get_children():
		if o is Cliffs:
			return o
	return null


## Map y where decor stands on the block of `c` (its top edge + stand_inset); NAN when no block is there.
func top_y_at(c: Vector2i) -> float:
	if not _at.has(c) or rig == null or rig.blocks == null:
		return NAN
	var b: Array = _at[c]
	var i: int = b[0]
	var z: float = b[1]
	var shift: Vector2 = b[2]
	var bl := rig.blocks
	if i >= bl.tops.size():
		return NAN
	return (c.y + 1) * CELL.y + shift.y - (bl.grounds[i].y - bl.tops[i]) * z + rig.stand_inset


func _draw_row(r: int) -> void:
	var n: Node2D = _nodes.get(r)
	if n == null or rig == null or rig.blocks == null or rig.blocks.atlas == null:
		return
	var tex := rig.blocks.atlas
	for b in _rows.get(r, []):
		n.draw_texture_rect_region(tex, b[1], b[0])


## Row → [[atlas rect, target rect local to the row node], …] for the wall and rock cells.
func place(wall: Dictionary, rock: Dictionary) -> Dictionary:
	var bl := rig.blocks
	var kinds := rock_kinds(rock)
	var walls := bl.pick_list(CliffBlocks.Group.WALL)
	var by_kind := {}
	for k in 4:
		by_kind[k] = bl.pick_list(CliffBlocks.Group.ROCK, k)
	var all_cells := wall.keys() + rock.keys()
	all_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out := {}
	_at = {}
	for p: Vector2i in all_cells:
		var list: PackedInt32Array
		var scale_k := rig.wall_scale
		if rock.has(p):
			list = by_kind[kinds[p]]
			if list.is_empty():
				list = bl.pick_list(CliffBlocks.Group.ROCK)
			scale_k = rig.rock_scale
		else:
			list = walls
		if list.is_empty():
			continue
		var i := list[int(hash01(p.x, p.y, 7) * list.size()) % list.size()]
		var z := scale_k * (1.0 + (hash01(p.x, p.y, 11) * 2.0 - 1.0) * rig.jitter_size) / bl.texels[i]
		var shift := Vector2((hash01(p.x, p.y, 13) * 2.0 - 1.0) * rig.jitter_x, (hash01(p.x, p.y, 17) * 2.0 - 1.0) * rig.jitter_y)
		# Ground point of the block on the middle of the cell's south edge; local to the row node.
		var at := Vector2((p.x + 0.5) * CELL.x, 1.0) + shift - bl.grounds[i] * z
		_at[p] = [i, z, shift]
		if not out.has(p.y):
			out[p.y] = []
		out[p.y].append([bl.rects[i], Rect2(at, bl.rects[i].size * z)])
	return out


## Height kind (CliffBlocks.Kind) per rock cell — the rule in the class comment.
func rock_kinds(rock: Dictionary) -> Dictionary:
	var seeds: Array[Vector2i] = []
	for p: Vector2i in rock:
		var n: Array[Vector2i] = []
		for s in SIDES:
			if rock.has(p + s):
				n.append(s)
		if n.size() <= 1 or (n.size() == 2 and n[0] + n[1] != Vector2i.ZERO):
			seeds.append(p)
	var dist := {}
	var q: Array[Vector2i] = []
	for s in seeds:
		dist[s] = 0
		q.append(s)
	var head := 0
	while head < q.size():
		var p := q[head]
		head += 1
		for s in SIDES:
			var nb := p + s
			if rock.has(nb) and not dist.has(nb):
				dist[nb] = dist[p] + 1
				q.append(nb)
	var out := {}
	for p: Vector2i in rock:
		var d: int = dist.get(p, 9)
		var nz := hump(p.x, p.y)
		var k := CliffBlocks.Kind.TALL
		if d == 0:
			k = CliffBlocks.Kind.LOW
		elif d == 1:
			k = CliffBlocks.Kind.MID
		elif d == 2:
			k = CliffBlocks.Kind.TALL if nz > 0.4 else CliffBlocks.Kind.MID
		else:
			k = CliffBlocks.Kind.TALL if nz >= rig.dip_noise else CliffBlocks.Kind.MID
			if nz > rig.peak_noise and _top_of_hump(p, nz, rock, dist):
				k = CliffBlocks.Kind.PEAK
		out[p] = k
	return out


func _top_of_hump(p: Vector2i, nz: float, rock: Dictionary, dist: Dictionary) -> bool:
	var r := rig.peak_radius
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var o := p + Vector2i(dx, dy)
			if o != p and rock.has(o) and dist.get(o, 9) >= 3 and hump(o.x, o.y) > nz:
				return false
	return true


## Smooth 0..1 noise: hashes on a coarse grid every `hump_cells` cells, smoothstep-bilinear between them.
func hump(c: int, r: int) -> float:
	var step := rig.hump_cells
	var gx := c / step
	var gy := r / step
	var x0 := int(floor(gx))
	var y0 := int(floor(gy))
	var fx := gx - x0
	var fy := gy - y0
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var s := 3 + rig.hump_seed * 101
	var a := lerpf(hash01(x0, y0, s), hash01(x0 + 1, y0, s), fx)
	var b := lerpf(hash01(x0, y0 + 1, s), hash01(x0 + 1, y0 + 1, s), fx)
	return lerpf(a, b, fy)


## 0..1 hash of a cell (+ salt), the same in art/maps/cliffs/rock_blocks_preview.py (h01).
static func hash01(c: int, r: int, salt := 0) -> float:
	var v := (c * 374761393 + r * 668265263 + salt * 2246822519) & 0xFFFFFFFF
	v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
	return float((v ^ (v >> 16)) & 0xFFFF) / 65535.0


# ---- editor buttons --------------------------------------------------------------------------------

## Paint a ring of `perimeter_cells` wall cells round the map edge (Cmd+Z undoes it in the editor).
func fill_perimeter() -> void:
	var m := _map()
	var c := _cells()
	if c == null or m == null or m.grid == null:
		push_warning("Cliffs: needs a CliffCells layer and a GameMap with a grid")
		return
	var before := c.tile_map_data
	var t := perimeter_cells
	for r in m.grid.rows:
		for x in m.grid.cols:
			if x < t or r < t or x >= m.grid.cols - t or r >= m.grid.rows - t:
				c.set_cell(Vector2i(x, r), 0, Vector2i(Tile.WALL, 0))
	_commit(c, "Обгородити периметр", before)


## Erase every cliff cell (Cmd+Z undoes it in the editor).
func clear_cells() -> void:
	var c := _cells()
	if c == null:
		return
	var before := c.tile_map_data
	c.clear()
	_commit(c, "Стерти всі скелі", before)


func _commit(c: CliffCells, action: String, before: PackedByteArray) -> void:
	if not (Engine.is_editor_hint() and Engine.has_singleton("EditorInterface")):
		return
	var ur = Engine.get_singleton("EditorInterface").get_editor_undo_redo()
	ur.create_action(action)
	ur.add_do_property(c, "tile_map_data", c.tile_map_data)
	ur.add_undo_property(c, "tile_map_data", before)
	ur.commit_action(false)
