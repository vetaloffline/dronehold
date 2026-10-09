class_name Builder
extends RefCounted
## Build rules (docs/concept.md «Будівництво», 2026-10-09), shared by the build menu and the tests:
## - A building goes on free buildable cells (GameMap.placement_problem) and not onto a vein's drill
##   slot — that one is kept for the drill.
## - The drill goes only into the slot of a crystal vein that has no drill yet.
## - It costs item.cost from the wallet, taken when the player confirms (✔), not when the ghost appears.

const NO_MONEY := "не вистачає кристалів"
const NOT_A_SLOT := "бур — тільки в підсвічений слот біля жили"
const SLOT_KEPT := "тут слот бура"


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


## The vein whose free slot is under map point `p` (a tap with the drill chosen), else null. The slot
## is the square where a drill with rig `r` will stand (Drill.slot_rect()), a bit larger for a finger.
static func slot_at(map: GameMap, p: Vector2, r: DrillRig) -> CrystalVein:
	for v in free_slots(map):
		if Drill.slot_rect(v, r).grow(8.0).has_point(p):
			return v
	return null


## Per cell (index r * cols + c), 1 = nothing can be built on it for `item`: terrain that is not
## buildable, cells taken by objects, and — for anything but the drill — the free drill slots.
## The build mode paints these red over the whole map.
static func blocked_cells(map: GameMap, item: BuildItem) -> PackedByteArray:
	var g := map.grid
	var out := PackedByteArray()
	out.resize(g.cols * g.rows)
	for r in g.rows:
		for c in g.cols:
			if not g.can_build(c, r):
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
	if wallet and not wallet.can_pay(item.cost):
		return NO_MONEY
	return ""


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
