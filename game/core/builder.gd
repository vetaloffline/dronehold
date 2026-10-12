class_name Builder
extends RefCounted
## Build rules (docs/concept.md «Будівництво», 2026-10-09), shared by the build menu and the tests:
## - A building goes on free buildable cells (GameMap.placement_problem) and not onto a vein's drill
##   slot — that one is kept for the drill.
## - The drill goes only into the slot of a crystal vein that has no drill yet.
## - Everything (the drill too) goes only inside the build radius of the core or a relay
##   (docs/concept.md «Склади і радіус будівництва»): the centre of every footprint cell within
##   MapObject.build_radius_cells() of a source's footprint centre. Each source counts on its own.
## - It costs item.cost from the wallet, taken when the player confirms (✔), not when the ghost appears.

const NO_MONEY := "не вистачає кристалів"
const NOT_A_SLOT := "бур — тільки в підсвічений слот біля жили"
const SLOT_KEPT := "тут слот бура"
const OUT_OF_RADIUS := "поза радіусом будівництва"


## A new object of `item` at `cell`, not in the tree yet. `ghost` = build-mode preview: it is drawn,
## but the map does not count it (MapObject.ghost) and it does not run (no shooting, no mining).
static func make(item: BuildItem, cell: Vector2i, ghost := false) -> MapObject:
	var o := item.scene.instantiate() as MapObject
	o.ghost = ghost
	o.cell = cell
	if ghost:
		o.name = "Ghost"
		o.process_mode = Node.PROCESS_MODE_DISABLED
	return o


## Veins whose drill slot is still free (no drill stands there).
static func free_slots(map: GameMap) -> Array[CrystalVein]:
	var taken := {}
	for o in map.objects():
		if o is Drill:
			taken[o.cell] = true
	var out: Array[CrystalVein] = []
	for o in map.objects():
		var v := o as CrystalVein
		if v and v.rig and not taken.has(v.drill_slot_cell()):
			out.append(v)
	return out


## The 2×2 cells of a vein's drill slot.
static func slot_cells(v: CrystalVein) -> Array[Vector2i]:
	var s := v.drill_slot_cell()
	return [s, s + Vector2i(1, 0), s + Vector2i(0, 1), s + Vector2i(1, 1)]


## Map px square of a vein's slot (its 2×2 cells; the drill stands on them).
static func slot_rect(v: CrystalVein) -> Rect2:
	return Rect2(Vector2(v.drill_slot_cell()) * MapGrid.CELL, MapGrid.CELL * 2.0)


## The vein whose free slot is under map point `p` (a tap with the drill chosen), else null. A bit
## larger than the slot, for a finger.
static func slot_at(map: GameMap, p: Vector2) -> CrystalVein:
	for v in free_slots(map):
		if slot_rect(v).grow(8.0).has_point(p):
			return v
	return null


## Objects on the map that give a build radius (the core, relays; ghosts are not on the map).
static func radius_sources(map: GameMap) -> Array[MapObject]:
	var out: Array[MapObject] = []
	for o in map.objects():
		if o.build_radius_cells() > 0.0:
			out.append(o)
	return out


## Is the centre of cell `c` inside the build radius of one of `sources`?
static func _cell_in(sources: Array[MapObject], c: Vector2i) -> bool:
	var p := Vector2(c) + Vector2(0.5, 0.5)
	for s in sources:
		var rad := s.build_radius_cells()
		if p.distance_squared_to(s.build_centre_cells()) <= rad * rad:
			return true
	return false


## Per cell (index r * cols + c), 1 = inside the build radius of the core or a relay.
static func radius_cells(map: GameMap) -> PackedByteArray:
	var g := map.grid
	var out := PackedByteArray()
	out.resize(g.cols * g.rows)
	for s in radius_sources(map):
		var mid := s.build_centre_cells()
		var rad := s.build_radius_cells()
		var r0 := maxi(0, floori(mid.y - rad))
		var r1 := mini(g.rows - 1, ceili(mid.y + rad))
		var c0 := maxi(0, floori(mid.x - rad))
		var c1 := mini(g.cols - 1, ceili(mid.x + rad))
		for r in range(r0, r1 + 1):
			for c in range(c0, c1 + 1):
				if (Vector2(c, r) + Vector2(0.5, 0.5)).distance_squared_to(mid) <= rad * rad:
					out[r * g.cols + c] = 1
	return out


## Are all `cells` inside the build radius (each one of some source)?
static func in_radius(map: GameMap, cells: Array[Vector2i]) -> bool:
	var sources := radius_sources(map)
	for c in cells:
		if not _cell_in(sources, c):
			return false
	return true


## Per cell (index r * cols + c), 1 = nothing can be built on it for `item`: terrain that is not
## buildable, cells taken by objects, cells outside the build radius (radius_cells) and — for
## anything but the drill — the free drill slots. The build mode paints these red over the whole map.
## `near` = radius_cells(map) if the caller has it already.
static func blocked_cells(map: GameMap, item: BuildItem, near := PackedByteArray()) -> PackedByteArray:
	var g := map.grid
	var out := PackedByteArray()
	out.resize(g.cols * g.rows)
	if near.size() != out.size():
		near = radius_cells(map)
	for r in g.rows:
		for c in g.cols:
			if not g.can_build(c, r) or near[r * g.cols + c] == 0:
				out[r * g.cols + c] = 1
	for o in map.objects():
		if not o.occupies_cells() or o.is_in_group("enemy_spawn"):
			continue
		for c in o.footprint_cells():
			if g.inside(c.x, c.y):
				out[c.y * g.cols + c.x] = 1
	if item == null or not item.vein_slot_only:
		for v in free_slots(map):
			var s := v.drill_slot_cell()
			for dy in 2:
				for dx in 2:
					if g.inside(s.x + dx, s.y + dy):
						out[(s.y + dy) * g.cols + s.x + dx] = 1
	return out


## Why `o` (made by make(), its `cell` set) can not be built ("" = it can). `wallet` null = do not
## check the money.
static func problem(map: GameMap, item: BuildItem, o: MapObject, wallet: Wallet) -> String:
	var slots := {}
	for v in free_slots(map):
		slots[v.drill_slot_cell()] = v
	if item.vein_slot_only:
		if not slots.has(o.cell):
			return NOT_A_SLOT
	else:
		for s in slots:
			for c in o.footprint_cells():
				if c.x >= s.x and c.y >= s.y and c.x < s.x + 2 and c.y < s.y + 2:
					return SLOT_KEPT
	var p := map.placement_problem(o)
	if p != "":
		return p
	if not in_radius(map, o.footprint_cells()):
		return OUT_OF_RADIUS
	if wallet and not wallet.can_pay(item.cost):
		return NO_MONEY
	return ""


## ---------- painted line building (the wall)
## The wall is painted cell by cell (BuildMenu); old walls of the same kind can be joined and painted
## over — those cells are not built again.

## Cells where `item` (a line, e.g. the wall) already stands: they can be joined, not built again.
static func line_existing(map: GameMap, item: BuildItem) -> Dictionary:
	var out := {}
	for o in map.objects():
		if o.scene_file_path == item.scene.resource_path:
			for c in o.footprint_cells():
				out[c] = true
	return out


## Cells from `a` (not included) to `b` (included), each a side neighbour of the one before: a fast or
## slanted finger stroke between two touch samples is filled in as a staircase near the straight line
## (two cells touching only at a corner would let slimes through).
static func cells_between(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c := a
	var d := b - a
	var n := absi(d.x) + absi(d.y)
	var sx := signi(d.x)
	var sy := signi(d.y)
	for k in n:
		# Step along the axis that keeps the cell nearest the line a → b.
		var cx := c + Vector2i(sx, 0)
		var cy := c + Vector2i(0, sy)
		var ex := absf(float((cx.x - a.x) * d.y - (cx.y - a.y) * d.x)) if sx != 0 else INF
		var ey := absf(float((cy.x - a.x) * d.y - (cy.y - a.y) * d.x)) if sy != 0 else INF
		c = cx if ex <= ey else cy
		out.append(c)
	return out


## Total price of `n` new pieces of `item`.
static func line_cost(item: BuildItem, n: int) -> Dictionary:
	var out := {}
	for res in item.cost:
		out[res] = int(item.cost[res]) * n
	return out


## Builds a piece of `item` on every cell of `cells` (old pieces skipped), all or nothing: the whole
## price must be there. Returns the new pieces (empty + `why` filled if nothing was built).
static func build_line(map: GameMap, item: BuildItem, cells: Array[Vector2i], wallet: Wallet, why: Array = []) -> Array[MapObject]:
	var built: Array[MapObject] = []
	var existing := line_existing(map, item)
	var todo: Array[Vector2i] = []
	for c in cells:
		if not existing.has(c) and not todo.has(c):
			todo.append(c)
	if todo.is_empty():
		why.append("нема що будувати")
		return built
	if wallet and not wallet.can_pay(line_cost(item, todo.size())):
		why.append(NO_MONEY)
		return built
	for c in todo:
		var w := []
		var o := build(map, item, c, wallet, w)
		if o:
			built.append(o)
	return built


## Builds `item` at `cell`: checks, takes the cost, adds the object to the map's World.
## Returns the new object, or null (then `why` is filled and nothing is taken).
static func build(map: GameMap, item: BuildItem, cell: Vector2i, wallet: Wallet, why: Array = []) -> MapObject:
	var o := make(item, cell)
	var p := problem(map, item, o, wallet)
	if p == "" and wallet and not wallet.pay(item.cost):
		p = NO_MONEY
	if p != "":
		why.append(p)
		o.free()
		return null
	map.world().add_child(o, true)
	return o
