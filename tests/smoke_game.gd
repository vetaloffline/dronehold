extends SceneTree
## Runs the real game scene headless and checks the swarm; then a timing run at 1k / 10k / 100k.
##   godot --headless --path . --script res://tests/smoke_game.gd
## Exit code 0 = ok. Timings are for this machine's CPU (headless: no GPU work measured).

var _main: Node
var _swarm: Swarm
var _lasher: LasherSwarm
var _lasher_dist := 0.0
## Max corpses / flying pieces of the lasher crowd seen at once (death animation, Corpses).
var _lasher_corpses := 0
var _lasher_pieces := 0
var _frame := 0
var _failed := 0
var _start_dist := 0.0
var _stage := 0
var _bench := [1000, 10000, 100000]
var _bench_i := 0
var _bench_frames := 0
var _bench_sim := 0.0
var _bench_view := 0.0
var _mined := 0
var _left_drill: Drill
## The test's own objects (the map is edited by hand, so the test does not rely on its node names).
var _drill: Drill
var _turret: Turret
var _core: Core
var _vein_l: CrystalVein


func _initialize() -> void:
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_swarm = _main.get_node("Map03/Swarm") as Swarm
	_lasher = _main.get_node_or_null("Map03/LasherSwarm") as LasherSwarm


func check(cond: bool, what: String) -> void:
	if not cond:
		_failed += 1
		printerr("FAIL: ", what)
	else:
		print("ok: ", what)


## Left click (press + release) at viewport px `a` → `b`.
func _click(a: Vector2, b: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = a if pressed else b
		e.global_position = e.position
		root.push_input(e, true)


func _screen_of(map: GameMap, p: Vector2) -> Vector2:
	return map.get_viewport().get_canvas_transform() * (map.get_global_transform() * p)


## A drill in the slot of one vein, a machine gun next to the core, another vein for the left-slot test.
func _fixtures(map: GameMap) -> void:
	var veins: Array[CrystalVein] = []
	for o in map.objects():
		if o is Core and _core == null:
			_core = o
		elif o is CrystalVein:
			veins.append(o)
	check(_core != null and veins.size() >= 2, "map has a core and at least 2 veins (%d)" % veins.size())
	if _core == null or veins.size() < 2:
		return
	veins[0].drill_side = CrystalVein.Side.RIGHT
	_drill = (load("res://game/objects/drill/drill.tscn") as PackedScene).instantiate() as Drill
	_drill.name = "TestDrill"
	_drill.cell = veins[0].drill_slot_cell()
	map.world().add_child(_drill)
	_vein_l = veins[1]
	_turret = (load("res://game/objects/machine_gun/machine_gun.tscn") as PackedScene).instantiate() as Turret
	_turret.name = "TestTurret"
	_turret.cell = _core.cell + Vector2i(8, 2)
	map.world().add_child(_turret)


func _drones(map: GameMap) -> Array[CargoDrone]:
	var out: Array[CargoDrone] = []
	for n in map.world().get_children():
		if n is CargoDrone:
			out.append(n)
	return out


## Runs `d` for up to `max_s` seconds at 30 fps until `done` returns true; returns the seconds used.
func _run(d: CargoDrone, max_s: float, done: Callable) -> float:
	var t := 0.0
	while t < max_s:
		d.step(1.0 / 30.0)
		t += 1.0 / 30.0
		if done.call():
			return t
	return -1.0


func _test_drones(map: GameMap) -> void:
	var ds := _drones(map)
	check(ds.size() == 2, "the core sends out 2 drones (got %d)" % ds.size())
	if ds.size() < 2:
		return
	var w := Wallet.of(_main)
	var drill := _drill
	var core := _core
	# Every drill on the map empty and stopped (the map's own drill mines too), only the test's one is used.
	var others: Array[Drill] = []
	for o in map.objects():
		if o is Drill:
			(o as Drill).stored = 0
			(o as Drill).claimed = 0
			o.process_mode = Node.PROCESS_MODE_DISABLED  # no new crystals during the test
			if o != drill:
				others.append(o)
	var a := ds[0]
	var b := ds[1]
	# Start clean: both by the core, no orders from the first frames of the game.
	for d in ds:
		d._release_pad()
		d.claim = 0
		d.cargo = 0
		d.task = CargoDrone.Task.NONE
		d.target = null
		d.mode = CargoDrone.Mode.AIR
		d.position = core.position + Vector2(0, 60)
		d.goal = Vector2.INF
		d.route = PackedVector2Array()
	# Nothing to do: hangs in the air next to the core.
	_run(a, 10.0, func() -> bool: return false)
	check(a.task == CargoDrone.Task.IDLE and a.mode == CargoDrone.Mode.AIR and a.position.distance_to(core.position) < 260.0, "no work: drone waits in the air by the core (%.0f px away)" % a.position.distance_to(core.position))
	# 5 crystals in the drill: lands at a drill pad, loads 5, flies to the core, +5 in the wallet.
	drill.stored = 5
	var before := w.amount("crystal")
	var landed := _run(a, 30.0, func() -> bool: return a.mode == CargoDrone.Mode.GROUND and a.task == CargoDrone.Task.TO_DRILL)
	var pad_ok := false
	for p in drill.drone_pads():
		pad_ok = pad_ok or a.position.distance_to(p) < 1.0
	check(landed > 0.0 and pad_ok, "drone lands on a drill pad (%.1f s)" % landed)
	check(b.claim == 0 and drill.claimed == 5, "the 5 crystals are promised to this drone only (claimed %d)" % drill.claimed)
	_run(a, 5.0, func() -> bool: return a.cargo > 0)
	check(a.cargo == 5 and drill.stored == 0 and drill.claimed == 0, "loads 5 into its own storage (cargo %d, drill %d)" % [a.cargo, drill.stored])
	check(w.amount("crystal") == before, "the wallet waits for the delivery (%d)" % w.amount("crystal"))
	var delivered := _run(a, 40.0, func() -> bool: return a.cargo == 0)
	check(delivered > 0.0 and w.amount("crystal") == before + 5, "unloads at the core: +5 in the wallet (%d → %d, %.1f s)" % [before, w.amount("crystal"), delivered])
	var at_core := false
	for p in core.drone_pads():
		at_core = at_core or a.position.distance_to(p) < 1.0
	check(at_core, "it sat on a core pad to unload")
	# One drone per pad: all core pads taken → it hangs by the nearest one, lands when one frees up.
	var blockers: Array[Node] = []
	for i in core.drone_pads().size():
		var n := Node.new()
		root.add_child(n)
		blockers.append(n)
		CargoDrone._pads[CargoDrone.pad_key(core, i)] = n
	_run(a, 3.0, func() -> bool: return a.mode == CargoDrone.Mode.AIR)
	a.cargo = 5
	a.task = CargoDrone.Task.NONE
	a.think()
	_run(a, 20.0, func() -> bool: return false)
	var pads := core.drone_pads()
	var near := INF
	for p in pads:
		near = minf(near, a.position.distance_to(p))
	check(a.mode == CargoDrone.Mode.AIR and not a.land_at_goal and near < a.rig.wait_offset + 2.0, "all pads taken: waits next to the nearest one (%.0f px)" % near)
	CargoDrone._pads.erase(CargoDrone.pad_key(core, 0))
	var got := _run(a, 30.0, func() -> bool: return a.cargo == 0)
	check(got > 0.0 and a.position.distance_to(pads[0]) < 1.0, "a pad frees up → it lands there and unloads")
	for n in blockers:
		n.free()
	drill.process_mode = Node.PROCESS_MODE_INHERIT
	for o in others:
		o.process_mode = Node.PROCESS_MODE_INHERIT


## First cell near the core where `item` can be built (ignoring the money), else (-1, -1).
func _free_cell(map: GameMap, item: BuildItem) -> Vector2i:
	for ring in range(4, 30):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var o := Builder.make(item, _core.cell + Vector2i(dx, dy))
				var ok := Builder.problem(map, item, o, null) == ""
				var c := o.cell
				o.free()
				if ok:
					return c
	return Vector2i(-1, -1)


## A relay put straight onto the map (no build rules) next to vein `v`, its drill slot inside the
## relay's build radius: no vein slot of map_03 is inside the core's. Free it after the test.
func _relay_near(map: GameMap, v: CrystalVein) -> MapObject:
	var relay_i := _item(load("res://game/core/build_catalog.tres") as BuildCatalog, "Ретранслятор")
	var s := v.drill_slot_cell()
	for ring in range(2, 7):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var o := Builder.make(relay_i, s + Vector2i(dx, dy))
				var near := true
				for c in Builder.slot_cells(v):
					near = near and (Vector2(c) + Vector2(0.5, 0.5)).distance_to(o.build_centre_cells()) <= o.build_radius_cells()
				if near and map.placement_problem(o) == "":
					o.name = "TestRelay"
					map.world().add_child(o)
					return o
				o.free()
	return null


## First top-left cell of `item` within `from`…`to` cells (footprint centre to the core's centre)
## where Builder.problem() says `want`, else (-1, -1). `min_in` / `max_in` = how many of its cells
## must be inside the build radius.
func _cell_by_problem(map: GameMap, item: BuildItem, want: String, from: float, to: float, min_in := 0, max_in := 0) -> Vector2i:
	var mid := _core.build_centre_cells()
	var near := Builder.radius_cells(map)
	var g := map.grid
	var o := Builder.make(item, Vector2i.ZERO)  # one probe, moved cell by cell
	var found := Vector2i(-1, -1)
	for r in g.rows:
		for c in g.cols:
			if found.x >= 0:
				break
			o.cell = Vector2i(c, r)
			var d := o.build_centre_cells().distance_to(mid)
			if d < from or d > to:
				continue
			var n_in := 0
			for fc in o.footprint_cells():
				if g.inside(fc.x, fc.y) and near[fc.y * g.cols + fc.x] == 1:
					n_in += 1
			if n_in >= min_in and n_in <= max_in and Builder.problem(map, item, o, null) == want:
				found = o.cell
	o.free()
	return found


## Left end of `n` free buildable cells in a row near the core (for a wall), else (-1, -1).
func _wall_row(map: GameMap, n: int) -> Vector2i:
	var bl := Builder.blocked_cells(map, null)
	for ring in range(5, 40):
		for dx in range(-ring, ring + 1):
			for dy in [-ring, ring]:
				var s := _core.cell + Vector2i(dx, dy)
				var ok := true
				for k in n:
					for down in 4:
						var c := s + Vector2i(k, down)
						ok = ok and map.grid.inside(c.x, c.y) and bl[c.y * map.grid.cols + c.x] == 0
				if ok:
					return s
	return Vector2i(-1, -1)


## Press at the first cell, move through the others, lift at the last (mouse = the finger).
func _drag(map: GameMap, cells: Array) -> void:
	var pts := []
	for c in cells:
		pts.append(_screen_of(map, map.grid.cell_center(c)))
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pts[0]
	down.global_position = pts[0]
	root.push_input(down, true)
	for k in range(1, pts.size()):
		var m := InputEventMouseMotion.new()
		m.position = pts[k]
		m.global_position = pts[k]
		m.relative = pts[k] - pts[k - 1]
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(m, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pts.back()
	up.global_position = pts.back()
	root.push_input(up, true)


func _four_connected_cells(cells: Array) -> bool:
	for k in range(1, cells.size()):
		var a: Vector2i = cells[k - 1]
		var b: Vector2i = cells[k]
		if absi(a.x - b.x) + absi(a.y - b.y) != 1:
			return false
	return true


## Another card: the camera gets its own drag settings back.
func drill_card_restore_cam(bm: BuildMenu, cam: MapCamera) -> void:
	(bm.get_node("Root/Cards/Card1") as Button).pressed.emit()
	check(cam.one_finger_pan and cam.drag_with_any_button and not cam.drag_with_right, "another card: the camera drags with one finger again")


func _item(cat: BuildCatalog, title: String) -> BuildItem:
	for it in cat.items:
		if it.title == title:
			return it
	return null


## Build menu card of the catalog item `title` (card i = catalog.items[i]); by title, so a new card does not
## shift the tests.
func _card(bm: Node, title: String) -> Button:
	var items: Array = bm.catalog.items
	for i in items.size():
		if items[i].title == title:
			return bm.get_node("Root/Cards/Card%d" % i) as Button
	return null


func _test_builder(map: GameMap) -> void:
	var cat := load("res://game/core/build_catalog.tres") as BuildCatalog
	var names := []
	for it in cat.items:
		names.append("%s %d" % [it.title, it.cost.get("crystal", 0)])
	check(names == ["Бур 100", "Кулемет 50", "Легкий кулемет 35", "Гранатомет 120", "Стіна 10", "Ретранслятор 80"], "build menu: 6 items with prices (%s)" % [names])
	var drill_i := _item(cat, "Бур")
	var mg_i := _item(cat, "Кулемет")
	var wall_i := _item(cat, "Стіна")
	var relay_i := _item(cat, "Ретранслятор")
	var w := Wallet.of(_main)
	w.add("crystal", 1000 - w.amount("crystal"))
	var slots := Builder.free_slots(map)
	var slot_veins := []
	for v in slots:
		slot_veins.append(v.drill_slot_cell())
	check(not slot_veins.has(_drill.cell) and slots.size() >= 1, "free drill slots: the vein with a drill is not one (%d free)" % slots.size())
	if slots.is_empty():
		return
	var v := slots[0]
	var built: Array[MapObject] = []
	# Drill: only into a free vein slot inside the build radius.
	var d_out := Builder.make(drill_i, v.drill_slot_cell())
	check(Builder.problem(map, drill_i, d_out, w) == Builder.OUT_OF_RADIUS, "drill in a slot outside the build radius: «%s»" % Builder.OUT_OF_RADIUS)
	d_out.free()
	var fix := _relay_near(map, v)
	check(fix != null, "a relay fixture next to the vein slot")
	if fix:
		built.append(fix)
	var off := Builder.make(drill_i, v.drill_slot_cell() + Vector2i(4, 4))
	check(Builder.problem(map, drill_i, off, w) == Builder.NOT_A_SLOT, "drill off a slot: «%s»" % Builder.NOT_A_SLOT)
	off.free()
	var tap := Builder.slot_rect(v).get_center()
	check(Builder.slot_at(map, tap) == v, "a tap inside the highlighted slot finds its vein")
	var d := Builder.build(map, drill_i, v.drill_slot_cell(), w) as Drill
	check(d != null and d.vein == v and w.amount("crystal") == 900, "drill built in the slot, −100 (wallet %d)" % w.amount("crystal"))
	if d:
		built.append(d)
		check(map.objects().has(d) and not Builder.free_slots(map).has(v), "the built drill is on the map, its slot is no longer free")
		var why := []
		check(Builder.build(map, drill_i, v.drill_slot_cell(), w, why) == null and why == [Builder.NOT_A_SLOT] and w.amount("crystal") == 900, "a second drill into the same slot: refused, nothing taken")
	# Turrets: free buildable cells, not the core, not a drill slot, not rock.
	var on_core := Builder.make(mg_i, _core.cell + Vector2i(2, 2))
	check(Builder.problem(map, mg_i, on_core, w).contains("зайнято"), "machine gun on the core: «%s»" % Builder.problem(map, mg_i, on_core, w))
	on_core.free()
	if Builder.free_slots(map).size() > 0:
		var keep := Builder.make(mg_i, Builder.free_slots(map)[0].drill_slot_cell())
		check(Builder.problem(map, mg_i, keep, w) == Builder.SLOT_KEPT, "machine gun on a drill slot: «%s»" % Builder.SLOT_KEPT)
		keep.free()
	var rock := Vector2i(-1, -1)
	for r in map.grid.rows - 1:
		for c in map.grid.cols - 1:
			if rock.x < 0 and map.grid.kind(c, r) == MapGrid.Kind.ROCK and map.grid.kind(c + 1, r) == MapGrid.Kind.ROCK and map.grid.kind(c, r + 1) == MapGrid.Kind.ROCK and map.grid.kind(c + 1, r + 1) == MapGrid.Kind.ROCK:
				rock = Vector2i(c, r)
	var on_rock := Builder.make(mg_i, rock)
	check(rock.x >= 0 and Builder.problem(map, mg_i, on_rock, w).contains("не будують"), "machine gun on a cliff: «%s»" % Builder.problem(map, mg_i, on_rock, w))
	on_rock.free()
	var cell := _free_cell(map, mg_i)
	check(cell.x >= 0, "there is free ground near the core (%s)" % cell)
	# A ghost is drawn but is not a part of the map: it blocks nothing and does not run.
	var g := Builder.make(mg_i, cell, true)
	map.world().add_child(g)
	check(not map.objects().has(g) and g.process_mode == Node.PROCESS_MODE_DISABLED, "ghost: not on the map's object list, not running")
	var probe := Builder.make(mg_i, cell)
	check(Builder.problem(map, mg_i, probe, w) == "", "the ghost does not block its own cells")
	probe.free()
	g.free()
	w.add("crystal", 30 - w.amount("crystal"))
	var why := []
	check(Builder.build(map, mg_i, cell, w, why) == null and why == [Builder.NO_MONEY] and w.amount("crystal") == 30, "30 crystals, machine gun 50: «%s», nothing taken" % Builder.NO_MONEY)
	w.add("crystal", 1000 - w.amount("crystal"))
	var t := Builder.build(map, mg_i, cell, w)
	check(t is Turret and w.amount("crystal") == 950 and map.objects().has(t), "machine gun built on free ground, −50")
	if t:
		built.append(t)
	# Wall: 300 hp, slimes walk round it (path cost 60 per cell); 0 hp → gone.
	var wc := _free_cell(map, wall_i)
	var wall := Builder.build(map, wall_i, wc, w) as BlockBuilding
	check(wall != null and is_equal_approx(wall.hp, 300.0) and w.amount("crystal") == 940, "wall built, 300 hp, −10")
	if wall:
		var costs := map.building_costs()
		var k := wall.cell.y * map.grid.cols + wall.cell.x
		check(costs.has(k) and float(costs[k]) >= FlowField.SOLID and map.walk_blocked()[k] == 1, "wall cells: solid for slimes, cost ≥ SOLID in the field (got %s)" % [costs.get(k)])
		check(not wall.damage(100.0) and is_equal_approx(wall.hp, 200.0), "wall takes 100 → 200 hp")
		check(wall.damage(500.0) and wall.is_queued_for_deletion(), "0 hp → the wall goes")
	# Relay: a store for the drones (the ghost is not).
	var rg := Builder.make(relay_i, cell, true)
	map.world().add_child(rg)
	check(not rg.is_in_group("storage"), "ghost relay is not a store")
	rg.free()
	var rc := _free_cell(map, relay_i)
	var relay := Builder.build(map, relay_i, rc, w)
	check(relay != null and relay.is_in_group("storage") and relay.drone_pads().size() == 2, "relay built: a store with 2 drone pads")
	if relay:
		built.append(relay)
	# Build radius: the core's 14 cells beyond its 6×6 footprint, a relay's 8 beyond its 2×2, from the
	# footprint centre; every cell of a building must be inside one of them.
	var cr := _core.build_radius_cells()
	check(is_equal_approx(cr, 17.0) and relay != null and is_equal_approx(relay.build_radius_cells(), 9.0), "build radius from the centre: core 14 + 3 = 17, relay 8 + 1 = 9 (got %.1f, %.1f)" % [cr, relay.build_radius_cells() if relay else 0.0])
	var oc := _cell_by_problem(map, mg_i, Builder.OUT_OF_RADIUS, cr + 1.0, cr + 3.0)
	check(oc.x >= 0, "free ground just past the core's build radius: «%s» (%s)" % [Builder.OUT_OF_RADIUS, oc])
	var half := _cell_by_problem(map, relay_i, Builder.OUT_OF_RADIUS, cr - 2.0, cr + 2.0, 1, 3)
	check(half.x >= 0, "a relay half outside the radius: «%s» (%s)" % [Builder.OUT_OF_RADIUS, half])
	if oc.x >= 0:
		# A relay inside the radius, near the edge: the cell past the old edge can be built on now.
		var mg_mid := Vector2(oc) + Vector2(1, 1)
		var r2c := Vector2i(-1, -1)
		var o := Builder.make(relay_i, Vector2i.ZERO)
		for dy in range(-8, 8):
			for dx in range(-8, 8):
				if r2c.x >= 0:
					break
				o.cell = Vector2i(roundi(mg_mid.x) + dx, roundi(mg_mid.y) + dy)
				var covers := true
				for fc in [oc, oc + Vector2i(1, 0), oc + Vector2i(0, 1), oc + Vector2i(1, 1)]:
					covers = covers and (Vector2(fc) + Vector2(0.5, 0.5)).distance_to(o.build_centre_cells()) <= o.build_radius_cells()
				if covers and Builder.problem(map, relay_i, o, null) == "":
					r2c = o.cell
		o.free()
		var r2: BlockBuilding = null
		if r2c.x >= 0:
			r2 = Builder.build(map, relay_i, r2c, w) as BlockBuilding
		check(r2 != null, "a relay inside the core's radius, next to its edge (%s)" % r2c)
		if r2:
			var probe2 := Builder.make(mg_i, oc)
			check(Builder.problem(map, mg_i, probe2, w) == "", "after the relay the cell past the old edge is fine")
			probe2.free()
			var t2 := Builder.build(map, mg_i, oc, w)
			check(t2 is Turret, "machine gun built in the relay's radius")
			if t2:
				built.append(t2)
			check(r2.damage(1.0e6), "the relay is destroyed")
			r2.free()  # it would go at the end of the frame (queue_free)
			var probe4 := Builder.make(mg_i, oc)
			check(map.objects().has(t2) and not Builder.in_radius(map, probe4.footprint_cells()), "the turret built there stays, its cells are outside the radius now")
			probe4.free()
	for o in built:
		o.free()
	w.add("crystal", 200 - w.amount("crystal"))


func _test_build_menu(map: GameMap) -> void:
	var bm := _main.get_node("BuildMenu") as BuildMenu
	var info := _main.get_node("ObjectInfo") as ObjectInfo
	var w := Wallet.of(_main)
	w.add("crystal", 500 - w.amount("crystal"))
	var toggle := bm.get_node("Root/Toggle") as TextureButton
	check(toggle.visible and not bm.is_open and not (bm.get_node("Root/Cards") as Control).visible, "build button on screen, menu closed")
	toggle.pressed.emit()
	check(bm.is_open and (bm.get_node("Root/Cards") as Control).visible and toggle.texture_normal == BuildMenu.CLOSE_TEX, "build button opens the cards and turns into ✕")
	# The whole map: a grid and red cells where nothing can be built.
	var ov0 := map.get_node("Shadows/BuildOverlay") as BuildOverlay
	var ov := ov0
	var rock := Vector2i(-1, -1)
	for r in map.grid.rows:
		for c in map.grid.cols:
			if rock.x < 0 and not map.grid.can_build(c, r):
				rock = Vector2i(c, r)
	var core_c := _core.cell + Vector2i(3, 3)
	var free0 := _free_cell(map, _item(bm.catalog, "Кулемет"))
	check(ov0.show_map and ov0.blocked_shown(rock.x, rock.y) and ov0.blocked_shown(core_c.x, core_c.y) and not ov0.blocked_shown(free0.x, free0.y), "build mode: map grid on, cliff and core cells red, free ground not")
	# Build radius: buildable ground outside it is red, inside it is not; its edge is a cyan line.
	var occ := {}
	for o in map.objects():
		for c in o.footprint_cells():
			occ[c] = true
	var out_c := Vector2i(-1, -1)
	var core_mid := _core.build_centre_cells()
	for r in map.grid.rows:
		for c in map.grid.cols:
			var dd := (Vector2(c, r) + Vector2(0.5, 0.5)).distance_to(core_mid)
			if out_c.x < 0 and dd > _core.build_radius_cells() + 1.0 and dd < _core.build_radius_cells() + 4.0 and map.grid.can_build(c, r) and not occ.has(Vector2i(c, r)) and not ov0.inside_shown(c, r):
				out_c = Vector2i(c, r)
	check(out_c.x >= 0 and ov0.blocked_shown(out_c.x, out_c.y), "free ground past the build radius is red (%s)" % out_c)
	check(ov0.inside_shown(free0.x, free0.y) and ov0.edge_count() > 0, "free ground near the core is inside the radius; the edge is drawn (%d cell sides)" % ov0.edge_count())
	var pics := []
	for i in bm.catalog.items.size():
		var p := bm.get_node("Root/Cards/Card%d/Picture" % i) as ObjectPortrait
		pics.append(p.rig != null or p.block != null or not p._items.is_empty())
	check(pics.size() == 6 and not pics.has(false), "every card has a picture from the building's own sprites (%s)" % [pics])
	check((_card(bm, "Легкий кулемет").get_node("Picture") as ObjectPortrait).rig == (load("res://game/objects/light_mg/light_mg_rig.tres") as TurretRig), "light machine gun card: the in-game light machine gun sprites")
	check((bm.get_node("Root/Cards/Card1/Picture") as ObjectPortrait).rig == (load("res://game/objects/machine_gun/machine_gun_rig.tres") as TurretRig), "machine gun card: the in-game machine gun sprites")
	var mg := bm.get_node("Root/Cards/Card1") as Button
	mg.pressed.emit()
	check(bm.item != null and bm.item.title == "Кулемет" and mg.position.y < 0.0, "tap a card → it is active (lifted)")
	mg.pressed.emit()
	check(bm.item == null and mg.position.y == 0.0, "tap it again → cancelled")
	mg.pressed.emit()
	var cell := _free_cell(map, bm.item)
	var at := _screen_of(map, (Vector2(cell) + Vector2(1, 1)) * MapGrid.CELL)
	_click(at, at + Vector2(3, 2))
	check(bm.ghost != null and bm.ghost.cell == cell and bm.problem == "" and info.selected == null, "tap the map → green ghost on its cells (%s), no selection card" % [bm.ghost.cell if bm.ghost else null])
	check(bm.ghost != null and not map.objects().has(bm.ghost) and w.amount("crystal") == 500, "the ghost is not built yet, nothing paid")
	_click(at, at + Vector2(220, 0))
	check(bm.ghost != null and bm.ghost.cell == cell, "a drag (camera pan) does not move the ghost")
	var slot0 := Builder.free_slots(map)[0].drill_slot_cell() if Builder.free_slots(map).size() > 0 else Vector2i(-1, -1)
	check(slot0.x < 0 or ov0.blocked_shown(slot0.x, slot0.y), "machine gun chosen: a drill slot is red for it")
	check(not ov0.blocked_shown(cell.x, cell.y), "the ghost's cells are not red before building")
	var built := bm.confirm()
	check(built is Turret and map.objects().has(built) and w.amount("crystal") == 450 and bm.ghost == null and bm.item != null, "✔ builds it (−50), the ghost goes, the card stays active")
	check(ov0.blocked_shown(cell.x, cell.y) and ov0.blocked_shown(cell.x + 1, cell.y + 1), "the new turret's cells turn red at once")
	bm.place_at(map.grid.cell_center(cell))
	check(bm.ghost != null and bm.problem != "" and not bm.place_ok and (bm.get_node("Root/Confirm/Ok") as Button).disabled, "a ghost on taken cells is red, ✔ disabled («%s»)" % bm.problem)
	(bm.get_node("Root/Confirm/Cancel") as Button).pressed.emit()
	w.add("crystal", 20 - w.amount("crystal"))
	bm.place_at(map.grid.cell_center(_free_cell(map, bm.item)) + MapGrid.CELL * 0.5)
	check(bm.ghost != null and bm.problem == Builder.NO_MONEY and bm.place_ok and ov.ok and (bm.get_node("Root/Confirm/Ok") as Button).disabled, "a free place but 20 crystals for 50: the ghost stays green, ✔ off")
	w.add("crystal", 450 - w.amount("crystal"))
	bm.place_at(map.grid.cell_center(cell))
	(bm.get_node("Root/Confirm/Cancel") as Button).pressed.emit()
	check(bm.ghost == null, "✖ removes the ghost")
	# Wall: painted by dragging, built all at once.
	var wall_card := _card(bm, "Стіна")
	var cam := _main.get_node("Camera") as MapCamera
	var cam_pos := cam.position
	wall_card.pressed.emit()
	check(bm.item != null and bm.item.line and not cam.one_finger_pan and not cam.drag_with_any_button and cam.drag_with_right, "wall card: one finger / left button paint, the camera drags with two fingers / right button")
	var row := _wall_row(map, 8)
	check(row.x >= 0, "a free straight run of 8 cells near the core (%s)" % row)
	var p0 := row
	var p1 := row + Vector2i(5, 0)
	_drag(map, [p0, row + Vector2i(2, 0), p1])
	check(bm.line_new_cells().size() == 6 and bm._line_ghosts.size() == 6 and cam.position == cam_pos, "a drag over 6 cells paints 6 ghost pieces (gaps between samples filled), the camera stays")
	check((bm.get_node("Root/Confirm/Price/Row/Cost") as Label).text == "60" and not (bm.get_node("Root/Confirm/Ok") as Button).disabled, "price next to ✔: 60")
	_drag(map, [p1 + Vector2i(0, 1), p1 + Vector2i(1, 3)])
	check(bm.line_new_cells().size() == 10 and _four_connected_cells(bm.line_cells().slice(6)), "a second slanted stroke adds a 4-connected staircase (10 pieces)")
	var taps := map.grid.cell_center(p1 + Vector2i(1, 3))
	_click(_screen_of(map, taps), _screen_of(map, taps))
	check(bm.line_new_cells().size() == 9 and not bm.painted.has(p1 + Vector2i(1, 3)), "a tap on a painted cell takes it back")
	var rock_c := Vector2i(-1, -1)
	for r in map.grid.rows:
		for c in map.grid.cols:
			if rock_c.x < 0 and not map.grid.can_build(c, r):
				rock_c = Vector2i(c, r)
	bm.paint_begin(map.grid.cell_center(rock_c - Vector2i(1, 0)))
	bm.paint_to(map.grid.cell_center(rock_c))
	bm.paint_end(false)
	check(not bm.painted.has(rock_c) and ov.bad_cell == rock_c, "dragging over a cliff: the cliff cell is skipped and flashes red")
	bm.painted.erase(rock_c - Vector2i(1, 0))
	bm._after_line_change()
	# Two fingers: the stroke was a camera move — dropped.
	var n_before := bm.painted.size()
	bm.paint_begin(map.grid.cell_center(row + Vector2i(0, 3)))
	bm.paint_to(map.grid.cell_center(row + Vector2i(3, 3)))
	for k in 2:
		var t := InputEventScreenTouch.new()
		t.index = k
		t.pressed = true
		t.position = Vector2(400 + 100 * k, 400)
		root.push_input(t, true)
	check(bm.painted.size() == n_before, "a second finger drops the stroke (it was a camera move)")
	for k in 2:
		var t := InputEventScreenTouch.new()
		t.index = k
		t.pressed = false
		root.push_input(t, true)
	w.add("crystal", 40 - w.amount("crystal"))
	bm._refresh()
	check((bm.get_node("Root/Confirm/Ok") as Button).disabled and bm.problem.contains("90"), "40 crystals for 90: ✔ off, «%s»" % bm.problem)
	check(bm.place_ok and ov.line_ok and (bm.get_node("Root/Confirm/Price/Row/Cost") as Label).get_theme_color("font_color") == BuildMenu.PRICE_BAD, "short of money: the wall plan stays green, only the price is red")
	w.add("crystal", 500 - w.amount("crystal"))
	var before := map.objects().size()
	var piece := bm.confirm()
	check(piece is BlockBuilding and map.objects().size() == before + 9 and w.amount("crystal") == 410 and bm.painted.is_empty() and bm._line_ghosts.is_empty(), "✔ builds all 9 pieces at once (−90)")
	var first: Wall = null
	for o in map.objects():
		if o is Wall and o.cell == p0:
			first = o
	check(first != null and first.joins(p0 + Vector2i(1, 0)) and not first.joins(p0 - Vector2i(1, 0)) and not first.joins(p0 + Vector2i(0, 1)), "a wall piece joins its neighbour on the right, nothing on the left / below")
	var mid: Wall = null
	for o in map.objects():
		if o is Wall and o.cell == p0 + Vector2i(2, 0):
			mid = o
	check(first != null and first.has_pillar() and mid != null and not mid.has_pillar(), "a pillar at the end of a run, none in the middle of a straight run")
	var g := Builder.make(bm.item, p1 + Vector2i(-1, 1), true) as Wall
	map.world().add_child(g)
	var last_piece: Wall = null
	for o in map.objects():
		if o is Wall and o.cell == p1 + Vector2i(-1, 0):
			last_piece = o
	check(g.joins(p1 + Vector2i(-1, 0)) and last_piece != null and not last_piece.joins(p1 + Vector2i(-1, 1)), "a ghost piece joins a real wall; the real wall does not join the ghost")
	g.free()
	# Paint over the old wall: only the new cells are paid.
	_drag(map, [p1 + Vector2i(-2, 0), p1 + Vector2i(-2, -2)])
	check(bm.line_new_cells().size() == 2, "a stroke from the old wall: only 2 new pieces")
	bm.clear_ghost()
	# A stroke over the edge of the build radius: the cell outside is skipped and flashes red.
	var edge_in := Vector2i(-1, -1)
	for r in map.grid.rows:
		for c in map.grid.cols - 1:
			if edge_in.x < 0 and ov.inside_shown(c, r) and not ov.blocked_shown(c, r) and not ov.inside_shown(c + 1, r) and map.grid.can_build(c + 1, r) and not occ.has(Vector2i(c + 1, r)):
				edge_in = Vector2i(c, r)
	check(edge_in.x >= 0, "free ground on both sides of the radius edge (%s)" % edge_in)
	if edge_in.x >= 0:
		bm.paint_begin(map.grid.cell_center(edge_in))
		bm.paint_to(map.grid.cell_center(edge_in + Vector2i(1, 0)))
		bm.paint_end(false)
		check(bm.painted.size() == 1 and bm.painted[0] == edge_in and ov.bad_cell == edge_in + Vector2i(1, 0), "a wall stroke over the radius edge: the cell outside is skipped and flashes red")
		bm.clear_ghost()
	drill_card_restore_cam(bm, cam)
	# The relay ghost shows the build radius it adds: a dashed ellipse around its footprint centre.
	check(bm.ghost == null and ov.reach_px == 0.0, "no ghost: no radius ellipse")
	var relay_card := _card(bm, "Ретранслятор")
	relay_card.pressed.emit()
	var rcell := _free_cell(map, bm.item)
	bm.place_at((Vector2(rcell) + Vector2(1, 1)) * MapGrid.CELL)
	check(bm.ghost != null and bm.ghost.cell == rcell and is_equal_approx(ov.reach_px, 9.0 * MapGrid.CELL.x) and ov.reach_centre == (Vector2(rcell) + Vector2(1, 1)) * MapGrid.CELL, "relay ghost: its future radius ellipse, 9 cells = %.0f px (got %.0f)" % [9.0 * MapGrid.CELL.x, ov.reach_px])
	(bm.get_node("Root/Cards/Card1") as Button).pressed.emit()
	bm.place_at((Vector2(rcell) + Vector2(1, 1)) * MapGrid.CELL)
	check(bm.ghost is Turret and ov.reach_px == 0.0, "a machine gun ghost has no radius ellipse")
	bm.clear_ghost()
	var walls: Array[MapObject] = []
	for o in map.objects():
		if o is Wall:
			walls.append(o)
	for o in walls:
		o.free()
	# Drill: only into a highlighted free slot (inside the build radius: a relay fixture by the vein).
	var all_slots := Builder.free_slots(map)
	var fix: MapObject = null
	if all_slots.size() > 0:
		fix = _relay_near(map, all_slots[0])
	var drill_card := bm.get_node("Root/Cards/Card0") as Button
	drill_card.pressed.emit()
	var slots: Array[CrystalVein] = []
	for v in Builder.free_slots(map):
		if Builder.in_radius(map, Builder.slot_cells(v)):
			slots.append(v)
	check(fix != null and slots.size() > 0 and slots.size() < all_slots.size() and ov.slots.size() == slots.size(), "drill chosen: only the free vein slots inside the build radius light up (%d of %d)" % [ov.slots.size(), all_slots.size()])
	if slots.size() > 0:
		var sc := slots[0].drill_slot_cell()
		check(not ov.blocked_shown(sc.x, sc.y), "drill chosen: its free slot is not red")
	if slots.size() > 0:
		# The slot cells are under the drill as it is drawn: its 2×2 square (ground point − map_shift
		# cells) is less than half a cell off them (until 2026-10-09 it was 2.3 cells below).
		var drawn := Drill.slot_ground_point(slots[0], _drill.rig) - _drill.rig.map_shift * MapGrid.CELL
		var off := (drawn - ov.slots[0].get_center()) / MapGrid.CELL
		check(absf(off.x) < 0.5 and absf(off.y) < 0.5, "a slot lights up under where its drill stands (off by %s cells)" % off)
	check(not bm.place_at(map.grid.cell_center(cell + Vector2i(0, 4))) and bm.ghost == null, "a tap off a slot puts no drill ghost")
	if slots.size() > 0:
		var v := slots[0]
		check(bm.place_at(Builder.slot_rect(v).get_center() + Vector2(10, -6)) and bm.ghost is Drill and (bm.ghost as Drill).vein == v and bm.problem == "", "a tap in the slot → drill ghost in it")
		check(ov.square == Builder.slot_rect(v), "the green square is the slot (the drill's cells)")
		var had := w.amount("crystal")
		var d := bm.confirm()
		check(d is Drill and (d as Drill).vein == v and w.amount("crystal") == had - 100 and ov.slots.size() == slots.size() - 1, "✔ builds the drill (−100), its slot no longer lights up")
		if d:
			d.free()
	if fix:
		fix.free()
	toggle.pressed.emit()
	check(not bm.is_open and bm.item == null and bm.ghost == null and not ov.show_map, "✕ closes the build mode, the map grid goes")
	if built:
		built.free()
	w.add("crystal", 200 - w.amount("crystal"))


func _target() -> Vector2:
	var map := _main.get_node("Map03") as GameMap
	var cells := map.target_cells()
	return map.grid.cell_center(cells[14]) if cells.size() > 14 else Vector2.ZERO


func _mean_dist(sim: SwarmSim = null) -> float:
	var t := _target()
	var s := sim if sim else _swarm.sim
	var d := 0.0
	for i in s.count:
		d += Vector2(s.px[i], s.py[i]).distance_to(t)
	return d / maxf(1, s.count)


func _process(_dt: float) -> bool:
	_frame += 1
	if _swarm == null or _frame > 5000:
		printerr("FAIL: no swarm or the test did not finish in 5000 frames")
		quit(1)
		return true
	var map := _main.get_node("Map03") as GameMap
	match _stage:
		0:
			if _frame == 1:
				_fixtures(map)
			if _frame == 2:
				check(_swarm.sim != null and _swarm.field != null, "swarm is set up")
				check(map.target_cells().size() == 36, "core gives 36 target cells (6×6)")
				check(map.spawn_points().size() >= 1, "map has spawn points")
				check(_swarm._spawn_cells.size() == map.spawn_points().size(), "every spawn point has a reachable cell nearby")
				var w := Wallet.of(_main)
				check(w != null and w.amount("crystal") == 200, "match starts with 200 crystals")
				var drill := _drill
				check(drill.vein != null, "map drill stands in a vein slot")
				drill.mined.connect(func(n: int) -> void: _mined += n)
				# Jump the drill to just before its beam goes out: the next frame pays.
				var r := drill.active_rig()
				drill._t = r.fire_end() + r.beams_done(drill._t) * r.cycle_len() - 0.001
				_swarm.speed_cells = 6.0
				_swarm.target_count = 50
				_swarm.spawn_per_sec = 200.0
				# Lashers: their own crowd, their own spawn points (SpawnPoint.enemy = "lasher").
				check(_lasher != null and _lasher.sim != null and _lasher.field != null, "lasher swarm is set up")
				if _lasher:
					check(map.spawn_points("lasher").size() >= 1, "map has lasher spawn points")
					check(_lasher._spawn_cells.size() == map.spawn_points("lasher").size(), "every lasher spawn point has a reachable cell nearby")
					check(_lasher.view.bands > 0 and _lasher.view._body.size() == _lasher.view.bands, "lasher bands built")
					_lasher.speed_cells = 3.0
					_lasher.target_count = 3
					_lasher.spawn_per_sec = 50.0
			if _frame == 100 and _lasher:
				_lasher_dist = _mean_dist(_lasher.sim)
			if _frame == 150:
				check(_swarm.sim.count == 50, "50 slimes spawned (got %d)" % _swarm.sim.count)
				_start_dist = _mean_dist()
				if _lasher:
					check(_lasher.sim.count == 3, "3 lashers spawned (got %d)" % _lasher.sim.count)
					var d := _mean_dist(_lasher.sim)
					check(d < _lasher_dist or _lasher.sim.reached_total > 0, "lashers run to the core: %.0f → %.0f px" % [_lasher_dist, d])
			if _frame == 160 and _lasher:
				# A lasher standing by the machine gun: the turret looks in every crowd and kills it.
				_lasher.frozen = true
				_lasher.target_count = 4
				check(_lasher.spawn_at(_turret.position + Vector2(90, 30)), "a lasher spawns next to the turret")
			if _frame > 160 and _lasher and _lasher.corpses:
				_lasher_corpses = maxi(_lasher_corpses, _lasher.corpses.sim.count)
				_lasher_pieces = maxi(_lasher_pieces, _lasher.corpses.piece_count())
			if _frame == 300 and _lasher:
				check(_lasher.sim.killed_total >= 1, "the machine gun killed a lasher (killed %d)" % _lasher.sim.killed_total)
				check(_lasher.corpses != null and _lasher_corpses >= 1 and _lasher_pieces >= 15, "a killed lasher leaves a corpse and its limbs fly off (corpses %d, pieces %d)" % [_lasher_corpses, _lasher_pieces])
				check(_lasher.corpses.splat_count() > 0, "the dead lasher bleeds: splats on the ground (%d)" % _lasher.corpses.splat_count())
				var under := map.shadows()
				check(_lasher.corpses.get_parent() == under and _swarm.corpses.get_parent() == under and _lasher.corpses.get_index() < 2 and _swarm.corpses.get_index() < 2, "corpses of both crowds are the first children of Shadows: drawn under the living and their shadows")
				_lasher.target_count = 0
			if _frame > 150:
				var s := _swarm.sim
				for i in s.count:
					var c := map.grid.cell_at(Vector2(s.px[i], s.py[i]))
					if map.grid.is_blocked(c.x, c.y):
						check(false, "slime in a cliff at %s (%.3f, %.3f)" % [c, s.px[i], s.py[i]])
						quit(1)
						return true
			if _frame == 30:
				var t := _turret
				var info := _main.get_node("ObjectInfo") as ObjectInfo
				var hl := map.get_node("Shadows/SelectionHighlight") as SelectionHighlight
				var at := _screen_of(map, t.position - Vector2(0, 20))
				_click(at, at + Vector2(200, 0))
				check(info.selected == null, "a drag over a turret does not select it")
				_click(at, at + Vector2(4, 3))
				check(info.selected == t, "a tap on the turret selects it")
				var card := info.get_node("Root/Card") as Control
				check(card.visible, "the info card shows")
				check((info.get_node("Root/Card/Body/Content/Row/Info/Name") as Label).text == "Кулемет", "card: name «Кулемет»")
				var vals := [info.tile_value(0), info.tile_value(1), info.tile_value(2)]
				check(vals == ["10", "12/с", "15"], "card: damage 10, rate 12/с, range 15 (got %s)" % [vals])
				check(not (info.get_node("Root/Card/Body/Content/Row/Info/Stats/Stat4") as Control).visible, "machine gun: 3 tiles")
				check((info.get_node("Root/Card/Body/Content/Row/Portrait/Picture") as ObjectPortrait).rig == t.get_rig(), "portrait is drawn from the turret's own rig sprites")
				check(hl.target == t and is_equal_approx(hl.range_px, 480.0), "range highlight follows the turret (480 px)")
				var empty := _screen_of(map, t.position + Vector2(t.get_rig().range_px * 0.5, 0))
				_click(empty, empty)
				check(info.selected == null and hl.target == null, "a tap on empty ground clears the selection")
			if _frame == 32:
				# Grenade launcher: a 4th tile with the blast radius, the card gets wider.
				var info := _main.get_node("ObjectInfo") as ObjectInfo
				var card := info.get_node("Root/Card") as Control
				var w3 := card.offset_right - card.offset_left
				var gl := (load("res://game/objects/grenade_launcher/grenade_launcher.tscn") as PackedScene).instantiate() as Turret
				gl.cell = Vector2i(60, 58)
				map.world().add_child(gl)
				info.select(gl)
				var vals := [info.tile_value(0), info.tile_value(1), info.tile_value(2), info.tile_value(3)]
				check((info.get_node("Root/Card/Body/Content/Row/Info/Stats/Stat4") as Control).visible and vals == ["20", "0.5/с", "25", "4"], "grenade launcher card: 20, 0.5/с, 25, blast 4 (got %s)" % [vals])
				check(card.offset_right - card.offset_left > w3 + 100.0, "the card widens for the 4th tile (%.0f → %.0f)" % [w3, card.offset_right - card.offset_left])
				info.select(null)
				gl.free()
			if _frame == 33:
				# Relay: tap → hp / cleared radius / drone pads; the ground shows the cleared ellipse.
				var info := _main.get_node("ObjectInfo") as ObjectInfo
				var hl := map.get_node("Shadows/SelectionHighlight") as SelectionHighlight
				var cat := load("res://game/core/build_catalog.tres") as BuildCatalog
				var relay_i := _item(cat, "Ретранслятор")
				var relay := Builder.make(relay_i, _free_cell(map, relay_i)) as BlockBuilding
				map.world().add_child(relay)
				check(is_equal_approx(relay.clear_radius_px(), 160.0) and is_equal_approx(_core.clear_radius_px(), 544.0), "cleared radius px: relay (4 + 1)·32 = 160, core (14 + 3)·32 = 544 (got %.0f, %.0f)" % [relay.clear_radius_px(), _core.clear_radius_px()])
				var at := _screen_of(map, relay.position - Vector2(0, 10))
				_click(at, at)
				check(info.selected == relay, "a tap on the relay selects it")
				check((info.get_node("Root/Card/Body/Content/Row/Info/Name") as Label).text == "Ретранслятор", "card: name «Ретранслятор»")
				var vals := [info.tile_value(0), info.tile_value(1), info.tile_value(2), info.tile_value(3)]
				check(vals == ["200/200", "5", "2", "9"], "relay card: hp 200/200, cleared 5 cells, 2 pads, build radius 9 (got %s)" % [vals])
				check((info.get_node("Root/Card/Body/Content/Row/Info/Stats/Stat4") as Control).visible, "relay: 4 tiles")
				var pic := info.get_node("Root/Card/Body/Content/Row/Portrait/Picture") as ObjectPortrait
				check(pic.rig == null and pic.block == null and pic._items.size() == 2, "relay portrait: a snapshot of its base and dish sprites (%d)" % pic._items.size())
				check(hl.target == relay and hl.clear and is_equal_approx(hl.range_px, 160.0), "highlight: the relay's cleared ellipse (160 px)")
				relay.damage(50.0)
				info._process(0.0)
				check(info.tile_value(0) == "150/200", "relay hp updates live: %s" % info.tile_value(0))
				info.select(null)
				check(not hl.clear and hl.target == null, "selection cleared")
				# Sprites from the rig: base on the ground point, dish on the mast top.
				var rr := relay as Relay
				var ra := rr.art()
				check(rr != null and rr.has_art() and is_equal_approx(rr.scale.x, ra.map_scale), "relay is drawn from sprites at map_scale %.3f" % ra.map_scale)
				var dish := rr.get_node("Dish") as Sprite2D
				check(dish.visible and dish.texture == ra.dishes[rr.dish_view] and dish.position.is_equal_approx(ra.housing - ra.ground) and dish.offset == -ra.dish_pivot, "dish: view %d at the housing" % rr.dish_view)
				check((rr.get_node("Base") as Sprite2D).position == -ra.ground and (rr.get_node("BaseShadow") as Sprite2D).texture == ra.base_shadow, "base and its shadow on the ground point")
				# Spin with 16 views (the same texture 16 times; the drawn views wait for approval).
				var r16 := ra.duplicate() as RelayRig
				var tex: Array[Texture2D] = []
				var azs := PackedFloat32Array()
				for i in 16:
					tex.append(ra.dishes[0])
					azs.append(fposmod(29.2 + 22.5 * i, 360.0))
				r16.dishes = tex
				r16.dish_azimuths = azs
				r16.spin_speed = 45.0
				rr.rig = r16
				rr.dish_angle = 29.2
				rr._update_dish()
				var v0 := rr.dish_view
				rr._process(1.0)  # +45°: two views on
				check(v0 == 0 and rr.dish_view == 2 and is_equal_approx(rr.dish_angle, 74.2), "spin 45°/s: after 1 s view 0 → 2 (angle %.1f, view %d)" % [rr.dish_angle, rr.dish_view])
				check(r16.nearest_view(29.2 - 11.0) == 0 and r16.nearest_view(29.2 - 12.0) == 15 and r16.nearest_view(359.0) == 15, "nearest view wraps round 360°")
				var sh := rr.get_node("DishShadow") as Sprite2D
				check(sh.texture == dish.texture and sh.position.is_equal_approx(dish.position + r16.dish_shadow_offset) and is_equal_approx(sh.scale.y, r16.dish_shadow_squash), "dish shadow follows the view, shifted and flattened")
				# The real rig: 16 drawn views, one full turn a second (all 16 views in 1 s).
				rr.rig = ra
				check(ra.dishes.size() == 16 and ra.dish_azimuths.size() == 16 and is_equal_approx(ra.spin_speed, 360.0), "relay rig: 16 dish views, 360°/s (got %d views, %.0f°/s)" % [ra.dishes.size(), ra.spin_speed])
				rr.dish_angle = ra.dish_azimuths[1]
				rr._update_dish()
				var seen := {}
				for i in 16:
					rr._process(1.0 / 16.0)
					seen[rr.dish_view] = true
				check(seen.size() == 16 and is_equal_approx(rr.dish_angle, ra.dish_azimuths[1]), "spin 360°/s: all 16 views within 1 s, back to the start (%d views, angle %.1f)" % [seen.size(), rr.dish_angle])
				relay.free()
			if _frame == 34:
				# Drill: tap → its storage on the card; full storage stops the drill.
				var info := _main.get_node("ObjectInfo") as ObjectInfo
				var drill := _drill
				var at := _screen_of(map, drill.position - Vector2(0, 10))
				_click(at, at)
				check(info.selected == drill, "a tap on the drill selects it")
				check((info.get_node("Root/Card/Body/Content/Row/Info/Name") as Label).text == "Бур", "card: name «Бур»")
				check(info.tile_value(0) == "%d/50" % drill.stored and info.tile_value(1) == "+5", "card: storage %s, per cycle %s" % [info.tile_value(0), info.tile_value(1)])
				drill.stored = 50
				drill._t = drill._next_cycle_start() - 0.02  # just before the end of the cycle
			if _frame == 36:
				# A vein with its slot on the left: a drill put there is mirrored and fires right.
				var v := _vein_l
				v.drill_side = CrystalVein.Side.LEFT
				_left_drill = (load("res://game/objects/drill/drill.tscn") as PackedScene).instantiate() as Drill
				_left_drill.cell = v.drill_slot_cell()
				map.world().add_child(_left_drill)
			if _frame == 40:
				var v := _vein_l
				var d := _left_drill
				check(v.drill_slot_cell() == v.cell + Vector2i(-2, 0), "left slot = vein cell + (−2, 0)")
				check(d.vein == v and d.get_map_flip() and d.scale.x < 0.0 and d.scale.y > 0.0, "drill in the left slot is mirrored (scale %s)" % d.scale)
				var hit := d.get_parent().to_local(d.to_global(d._hit - d.rig.ground_point)) as Vector2
				var want := v.vein_px_to_parent(v.rig.hit_point_left)
				check(hit.distance_to(want) < 1.0, "mirrored drill fires at the vein's left hit point (%s vs %s)" % [hit, want])
				check(hit.x > d.position.x, "it fires to the right, at the vein")
				# Drone pads come from drill.tscn / core.tscn (set by hand): the left drill mirrors the right one's.
				var rp := _drill.drone_pads()
				var lp := d.drone_pads()
				var mirrored := rp.size() == lp.size() and rp.size() > 0
				for i in mini(rp.size(), lp.size()):
					var r_off := (rp[i] - _drill.position) / _drill.scale.y
					var l_off := (lp[i] - d.position) / d.scale.y
					mirrored = mirrored and absf(r_off.x + l_off.x) < 0.5 and absf(r_off.y - l_off.y) < 0.5
				check(mirrored, "left drill: drone pads mirror the right drill's (%d pads)" % rp.size())
				var pads := _core.drone_pads()
				var distinct := pads.size() > 0
				for i in pads.size():
					for j in range(i + 1, pads.size()):
						distinct = distinct and pads[i] != pads[j]
				check(distinct, "core has drone pads, all in different places (%d)" % pads.size())
				_left_drill.free()
				v.drill_side = CrystalVein.Side.RIGHT
			if _frame == 44:
				# The editor takes the map out of the tree and puts it back when you switch scene tabs.
				_main.remove_child(map)
				_main.add_child(map)
				_main.move_child(map, 0)
			if _frame == 47:
				var v := _swarm.view
				check(v.bands > 0 and v._body.size() == v.bands and v._shadow.size() == v.bands, "swarm bands rebuilt after leaving and re-entering the tree (%d bands, %d nodes)" % [v.bands, v._body.size()])
			if _frame == 60:
				var info := _main.get_node("ObjectInfo") as ObjectInfo
				var drill := _drill
				check(drill.stored == 50 and drill.is_full(), "full storage: no more crystals (stored %d)" % drill.stored)
				check(info.tile_value(0) == "50/50", "card updates live: %s" % info.tile_value(0))
				var held := drill._t
				check(fmod(held, drill.active_rig().cycle_len()) > drill.active_rig().cycle_len() - 0.01, "full drill waits at the end of its cycle (t %.3f)" % held)
				check(drill.take(10) == 10 and drill.stored == 40 and not drill.is_full(), "a drone can take 10 → 40 left")
				info.select(null)
			if _frame == 20:
				var w := Wallet.of(_main)
				var drill := _drill
				check(_mined == 5 and drill.stored == 5, "one drill beam = +5 crystals into the drill's storage (mined %d, stored %d)" % [_mined, drill.stored])
				check(w.amount("crystal") == 200, "the drill does not pay the wallet itself (wallet %d)" % w.amount("crystal"))
				var pops := 0
				for n in map.get_node("World").get_children():
					if n is FloatText:
						pops += 1
				check(pops == 1, "«+5» pops up over the vein (%d)" % pops)
			if _frame == 6:
				# Drones are stepped by hand below (fixed dt), not by the engine.
				for d in _drones(map):
					d.process_mode = Node.PROCESS_MODE_DISABLED
			if _frame == 70:
				_test_drones(map)
			if _frame == 80:
				_test_builder(map)
			if _frame == 84:
				_test_build_menu(map)
			if _frame == 600:
				var hud := _main.get_node("GameHud") as GameHud
				check(int(round(hud.shown)) == Wallet.of(_main).amount("crystal"), "HUD counter rolled up to the wallet (%d)" % int(round(hud.shown)))
				var d := _mean_dist()
				check(d < _start_dist or _swarm.sim.reached_total > 0, "crowd moves to the core: %.0f → %.0f px, reached %d" % [_start_dist, d, _swarm.sim.reached_total])
				_stage = 1
				_swarm.spawn_per_sec = 0.0
		1:
			if _bench_frames == 0:
				_swarm.sim.clear()
				_swarm.capacity = 200000
				_swarm.fill_random(_bench[_bench_i])
				_bench_sim = 0.0
				_bench_view = 0.0
			_bench_frames += 1
			if _bench_frames > 10:
				_bench_sim += _swarm.last_sim_ms
				_bench_view += _swarm.last_view_ms
			if _bench_frames == 40:
				print("bench %6d slimes: sim %.2f ms, view %.2f ms (visible %d)" % [
					_swarm.sim.count, _bench_sim / 30.0, _bench_view / 30.0, _swarm.view.visible_count])
				_bench_frames = 0
				_bench_i += 1
				if _bench_i >= _bench.size():
					print("smoke: %d failed" % _failed)
					quit(1 if _failed > 0 else 0)
					return true
	return false
