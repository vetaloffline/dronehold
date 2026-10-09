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
