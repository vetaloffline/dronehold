@tool
class_name Wall
extends BlockBuilding
## A 1×1 piece of wall that joins its neighbours (docs/concept.md «Будівництво»). A pillar stands only
## where the wall ends, turns or branches (has_pillar); a straight run between two pillars is one
## continuous span. Every piece draws the span from its own centre to the wall on its right and to the
## wall below (each pair once, by the left / upper piece), cut where a pillar stands, so pieces never
## overlap whatever order they are drawn in. Y-sort: a span into depth is drawn by the upper piece, in
## front of its pillar; the lower piece (further down) covers its end.
## A build-mode ghost joins other ghosts and real walls; a real wall joins only real walls.
## Without piece textures in the rig it is drawn as the plain block (BlockBuilding).

## Walls by cell, per parent node: parent id → {cell: [Wall, …]}.
static var _by_cell := {}

var _key := Vector2i(-99999, -99999)


func wall_rig() -> WallRig:
	return rig as WallRig


func _enter_tree() -> void:
	super._enter_tree()
	_register()


func _exit_tree() -> void:
	_unregister()


func _place() -> void:
	super()
	if is_inside_tree() and _key != cell:
		_unregister()
		_register()


func _cells() -> Dictionary:
	var p := get_parent()
	if p == null:
		return {}
	var id := p.get_instance_id()
	if not _by_cell.has(id):
		_by_cell[id] = {}
	return _by_cell[id]


func _register() -> void:
	var d := _cells()
	_key = cell
	if not d.has(cell):
		d[cell] = []
	(d[cell] as Array).append(self)
	_poke_neighbours()


func _unregister() -> void:
	var d := _cells()
	if d.has(_key):
		(d[_key] as Array).erase(self)
		if (d[_key] as Array).is_empty():
			d.erase(_key)
		_poke_neighbours()
	_key = Vector2i(-99999, -99999)


## Pieces up to 2 cells away depend on this one: the left / upper ones draw spans to it, and whether a
## neighbour has a pillar (where their spans stop) depends on its neighbours.
func _poke_neighbours() -> void:
	var d := _cells()
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if absi(dx) + absi(dy) > 2:
				continue
			for w in d.get(_key + Vector2i(dx, dy), []):
				if is_instance_valid(w):
					(w as Wall).queue_redraw()
	queue_redraw()


## Is there a wall this piece joins at `c`?
func joins(c: Vector2i) -> bool:
	for w in _cells().get(c, []):
		if is_instance_valid(w) and w != self and (ghost or not (w as Wall).ghost):
			return true
	return false


## A pillar here: the wall ends, turns or branches here (not in the middle of a straight run).
func has_pillar() -> bool:
	return pillar_at(cell)


func pillar_at(c: Vector2i) -> bool:
	var l := _has_wall(c + Vector2i(-1, 0))
	var r := _has_wall(c + Vector2i(1, 0))
	var u := _has_wall(c + Vector2i(0, -1))
	var d := _has_wall(c + Vector2i(0, 1))
	return not ((l and r and not u and not d) or (u and d and not l and not r))


## A wall at `c` this piece sees (itself included): a ghost sees ghosts and real walls, a real wall only
## real walls.
func _has_wall(c: Vector2i) -> bool:
	for w in _cells().get(c, []):
		if is_instance_valid(w) and (w == self or ghost or not (w as Wall).ghost):
			return true
	return false


func _draw() -> void:
	var r := wall_rig()
	if r == null or r.pillar == null:
		super()
		return
	var k := r.art_scale
	var right := joins(cell + Vector2i(1, 0))
	var down := joins(cell + Vector2i(0, 1))
	var me := has_pillar()
	var ps := r.pillar.get_size() * k
	var pw := ps.x
	var pd := (ps.y - r.pillar_ground.y * k) * 2.0
	_shadow(r, me, right, down, pw, pd)
	if right:
		# Along x: from the own centre (or the own pillar's face) to the neighbour's centre (or its pillar's
		# face), tiled from the "along" sprite (stretching would widen the bricks).
		var x0 := pw * 0.5 if me else 0.0
		var x1 := MapGrid.CELL.x - (pw * 0.5 if pillar_at(cell + Vector2i(1, 0)) else 0.0)
		var tw := r.along.get_width() * k
		var th := r.along.get_height() * k
		var y := -r.along_ground.y * k
		var n := maxi(1, ceili((x1 - x0) / tw - 0.15))
		var seg := (x1 - x0) / n
		for i in n:
			draw_texture_rect(r.along, Rect2(x0 + seg * i, y, seg + 0.5, th), false)
	if me:
		draw_texture_rect(r.pillar, Rect2(-r.pillar_ground * k, ps), false)
	if down:
		# In depth: the top face of the "depth" sprite stretched from here to the lower piece, lifted by the
		# span height (its front end is behind the pillar that ends the run).
		var y0 := pd * 0.5 if me else 0.0
		var y1 := MapGrid.CELL.y - (pd * 0.5 if pillar_at(cell + Vector2i(0, 1)) else 0.0)
		var dw := r.depth.get_width() * k
		var lift := r.span_h * k
		var src := Rect2(0, 0, r.depth.get_width(), r.depth_top)
		draw_texture_rect_region(r.depth, Rect2(-dw * 0.5, y0 - lift, dw, y1 - y0), src)
	if r.max_hp > 0.0 and hp < r.max_hp and hp > 0.0:
		var top := -r.pillar_ground.y * k - 8.0
		var bar := Rect2(-12.0, top, 24.0, 4.0)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp / r.max_hp, bar.size.y)), Color(0.35, 0.95, 0.35))


## Cast shadow (sun upper right, falls left), in parts that do not overlap the neighbours' (see-through
## shadows that overlap show darker steps): under the pillar, stretched left by its height ×
## shadow_len; under the span to the right; under the span down. Each piece owns the ground from its
## centre to the right / down neighbour's centre.
func _shadow(r: WallRig, me: bool, right: bool, down: bool, pw: float, pd: float) -> void:
	var k := r.art_scale
	var sh := (r.pillar.get_height() * k - pd) * r.shadow_len
	var ssh := (r.span_h * k) * r.shadow_len
	var col := Color(0, 0, 0, r.shadow_alpha)
	if me:
		draw_rect(Rect2(-pw * 0.5 - sh, -pd * 0.5, pw + sh, pd), col)
	if right:
		var x0 := pw * 0.5 if me else 0.0
		var x1 := MapGrid.CELL.x - (pw * 0.5 + sh if pillar_at(cell + Vector2i(1, 0)) else 0.0)
		var ad := pd * 0.6
		if x1 > x0:
			draw_rect(Rect2(x0, -ad * 0.5, x1 - x0, ad), col)
	if down:
		var dw := r.depth.get_width() * k
		var y0 := pd * 0.5 if me else 0.0
		var y1 := MapGrid.CELL.y - (pd * 0.5 if pillar_at(cell + Vector2i(0, 1)) else 0.0)
		draw_rect(Rect2(-dw * 0.5 - ssh, y0, dw + ssh, y1 - y0), col)
