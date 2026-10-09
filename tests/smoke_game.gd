extends SceneTree
## Runs the real game scene headless and checks the swarm; then a timing run at 1k / 10k / 100k.
##   godot --headless --path . --script res://tests/smoke_game.gd
## Exit code 0 = ok. Timings are for this machine's CPU (headless: no GPU work measured).

var _main: Node
var _swarm: Swarm
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
	drill.stored = 0
	drill.claimed = 0
	drill.process_mode = Node.PROCESS_MODE_DISABLED  # no new crystals during the test
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


func _item(cat: BuildCatalog, title: String) -> BuildItem:
	for it in cat.items:
		if it.title == title:
			return it
	return null


func _test_builder(map: GameMap) -> void:
	var cat := load("res://game/core/build_catalog.tres") as BuildCatalog
	var names := []
	for it in cat.items:
		names.append("%s %d" % [it.title, it.cost.get("crystal", 0)])
	check(names == ["Бур 100", "Кулемет 50", "Гранатомет 120", "Стіна 10", "Ретранслятор 80"], "build menu: 5 items with prices (%s)" % [names])
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
	# Drill: only into a free vein slot.
	var off := Builder.make(drill_i, v.drill_slot_cell() + Vector2i(4, 4))
	check(Builder.problem(map, drill_i, off, w) == Builder.NOT_A_SLOT, "drill off a slot: «%s»" % Builder.NOT_A_SLOT)
	off.free()
	var tap := Drill.slot_rect(v, _drill.rig).get_center()
	check(Builder.slot_at(map, tap, _drill.rig) == v, "a tap inside the highlighted slot finds its vein")
	var built: Array[MapObject] = []
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
		check(costs.has(k) and is_equal_approx(float(costs[k]), 60.0), "wall cells cost slimes 60 extra (got %s)" % [costs.get(k)])
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
	var rock := Vector2i(-1, -1)
	for r in map.grid.rows:
		for c in map.grid.cols:
			if rock.x < 0 and not map.grid.can_build(c, r):
				rock = Vector2i(c, r)
	var core_c := _core.cell + Vector2i(3, 3)
	var free0 := _free_cell(map, _item(bm.catalog, "Кулемет"))
	check(ov0.show_map and ov0.blocked_shown(rock.x, rock.y) and ov0.blocked_shown(core_c.x, core_c.y) and not ov0.blocked_shown(free0.x, free0.y), "build mode: map grid on, cliff and core cells red, free ground not")
	var pics := []
	for i in 5:
		var p := bm.get_node("Root/Cards/Card%d/Picture" % i) as ObjectPortrait
		pics.append(p.rig != null or p.block != null or not p._items.is_empty())
	check(pics == [true, true, true, true, true], "every card has a picture from the building's own sprites (%s)" % [pics])
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
	check(bm.ghost != null and bm.problem != "" and (bm.get_node("Root/Confirm/Ok") as Button).disabled, "a ghost on taken cells is red, ✔ disabled («%s»)" % bm.problem)
	(bm.get_node("Root/Confirm/Cancel") as Button).pressed.emit()
	check(bm.ghost == null, "✖ removes the ghost")
	# Drill: only into a highlighted free slot.
	var drill_card := bm.get_node("Root/Cards/Card0") as Button
	drill_card.pressed.emit()
	var slots := Builder.free_slots(map)
	var ov := map.get_node("Shadows/BuildOverlay") as BuildOverlay
	check(slots.size() > 0 and ov.slots.size() == slots.size(), "drill chosen: the free vein slots light up (%d)" % ov.slots.size())
	if slots.size() > 0:
		var sc := slots[0].drill_slot_cell()
		check(not ov.blocked_shown(sc.x, sc.y), "drill chosen: its free slot is not red")
	if slots.size() > 0:
		var want := Drill.slot_ground_point(slots[0], _drill.rig) - _drill.rig.map_shift * MapGrid.CELL
		check(ov.slots[0].get_center().distance_to(want) < 0.5, "a slot lights up where its drill will stand, not on the bare slot cells")
	check(not bm.place_at(map.grid.cell_center(cell + Vector2i(0, 4))) and bm.ghost == null, "a tap off a slot puts no drill ghost")
	if slots.size() > 0:
		var v := slots[0]
		check(bm.place_at(Drill.slot_rect(v, _drill.rig).get_center() + Vector2(10, -6)) and bm.ghost is Drill and (bm.ghost as Drill).vein == v and bm.problem == "", "a tap in the slot → drill ghost in it")
		check(ov.square.get_center().distance_to(bm.ghost.position - _drill.rig.map_shift * MapGrid.CELL) < 1.0, "the green square is under the drill ghost (its ground point map_shift cells below the centre)")
		var d := bm.confirm()
		check(d is Drill and (d as Drill).vein == v and w.amount("crystal") == 350 and ov.slots.size() == slots.size() - 1, "✔ builds the drill (−100), its slot no longer lights up")
		if d:
			d.free()
	toggle.pressed.emit()
	check(not bm.is_open and bm.item == null and bm.ghost == null and not ov.show_map, "✕ closes the build mode, the map grid goes")
	if built:
		built.free()
	w.add("crystal", 200 - w.amount("crystal"))


func _target() -> Vector2:
	var map := _main.get_node("Map03") as GameMap
	var cells := map.target_cells()
	return map.grid.cell_center(cells[14]) if cells.size() > 14 else Vector2.ZERO


func _mean_dist() -> float:
	var t := _target()
	var s := _swarm.sim
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
			if _frame == 150:
				check(_swarm.sim.count == 50, "50 slimes spawned (got %d)" % _swarm.sim.count)
				_start_dist = _mean_dist()
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
				check(v.drill_slot_cell() == v.cell + Vector2i(-2, -2), "left slot = vein cell + (−2, −2)")
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
