extends SceneTree
## Headless tests. Run:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exit code 0 = all passed.

var _failed := 0
var _passed := 0


func _init() -> void:
	_test_grid_from_layout()
	_test_cell_kinds()
	_test_flow_field()
	_test_swarm_ids_and_bins()
	_test_swarm_queries()
	_test_crawl_speed()
	_test_swarm_reaches_target()
	_test_crowd_spacing()
	_test_crowd_gets_through()
	_test_multimesh_buffer_layout()
	_test_wallet()
	_test_drill_beams()
	_test_bullet_pierce()
	_test_grenade_blast()
	_test_drone_nav()
	_test_wall()
	_test_wall_line()
	_test_wall_holds_slimes()
	print("tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: ", what)


func _test_grid_from_layout() -> void:
	var tex := load("res://art/maps/map_03/map_03_layout.png") as Texture2D
	var g := MapGrid.from_layout(tex.get_image(), 0.5)
	check(g.cols == 156 and g.rows == 117, "grid 156x117, got %dx%d" % [g.cols, g.rows])
	# Reference: the editor's coverage() rule ported to Python over the same PNG (the port gives
	# 1197 on the old 64×48 cells, as the editor did; 4968 on 32×24).
	check(g.count_kind(MapGrid.Kind.ROCK) == 4968, "rock cells 4968, got %d" % g.count_kind(MapGrid.Kind.ROCK))
	check(g.blocked_count() == 4968, "slimes can not walk the rock cells, got %d" % g.blocked_count())
	check(g.count_kind(MapGrid.Kind.GROUND) == g.cols * g.rows - 4968, "the rest is ground")
	# Drone layer from the same layout: cliffs only (pits are flown over), so a part of the rock cells.
	var nf := MapGrid.cliffs_from_layout(tex.get_image(), g.cols, g.rows, 0.5)
	var cliff := nf.count(1)
	var outside := 0
	for i in nf.size():
		if nf[i] == 1 and g.kinds[i] != MapGrid.Kind.ROCK:
			outside += 1
	check(cliff > 0 and cliff < 4968, "no-fly cells = cliffs: %d of 4968 rock cells" % cliff)
	check(outside == 0, "every no-fly cell is a rock cell (%d are not)" % outside)


func _small_grid(cols: int, rows: int, walls: Array) -> MapGrid:
	var g := MapGrid.open(cols, rows)
	for w in walls:
		g.set_kind(w.x, w.y, MapGrid.Kind.ROCK)
	return g


func _test_cell_kinds() -> void:
	# Each kind = two rules: build / walk.
	var g := MapGrid.open(4, 1)
	g.set_kind(1, 0, MapGrid.Kind.PASS)
	g.set_kind(2, 0, MapGrid.Kind.ROCK)
	g.set_kind(3, 0, MapGrid.Kind.PLATEAU)
	check(g.can_build(0, 0) and g.can_walk(0, 0), "ground: build + walk")
	check(not g.can_build(1, 0) and g.can_walk(1, 0), "pass: walk only")
	check(not g.can_build(2, 0) and not g.can_walk(2, 0), "rock: neither")
	check(g.can_build(3, 0) and not g.can_walk(3, 0), "plateau: build only")
	check(g.blocked == PackedByteArray([0, 0, 1, 1]), "blocked follows walk, got %s" % g.blocked)
	check(not g.can_build(-1, 0) and not g.can_walk(4, 0), "outside the map: neither")
	# Slimes go around a plateau; a pass lets them through.
	var w := MapGrid.open(5, 3)
	for r in 3:
		w.set_kind(2, r, MapGrid.Kind.PLATEAU)
	var f := FlowField.new()
	var t: Array[Vector2i] = [Vector2i(4, 1)]
	f.build(w, t)
	check(not f.reachable(0, 1), "a plateau wall stops slimes")
	w.set_kind(2, 1, MapGrid.Kind.PASS)
	f.build(w, t)
	check(f.reachable(0, 1), "a pass cell in the plateau lets them through")
	# Saved and loaded: kinds survive, blocked is rebuilt.
	var path := "user://test_grid.tres"
	if ResourceSaver.save(w, path) == OK:
		var back := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MapGrid
		check(back.kinds == w.kinds and back.blocked == w.blocked, "grid .tres round trip")
	else:
		print("skip: can not write user:// (sandbox)")


func _test_flow_field() -> void:
	# 7x5, a wall in column 3 rows 0..3: the path from the left must go under it (row 4).
	var walls := []
	for r in 4:
		walls.append(Vector2i(3, r))
	var g := _small_grid(7, 5, walls)
	var f := FlowField.new()
	var targets: Array[Vector2i] = [Vector2i(6, 0)]
	f.build(g, targets)
	check(f.dist[0 * 7 + 6] == 0.0, "target dist 0")
	check(f.dist[0 * 7 + 3] >= FlowField.INF, "wall unreachable")
	check(f.reachable(0, 0), "left side reachable around the wall")
	# From (2,0) the arrow must not point into the wall (x must not grow while in row 0..3 at col 2).
	var i := 0 * 7 + 2
	check(not (f.dir[i * 2] > 0.5 and absf(f.dir[i * 2 + 1]) < 0.1), "arrow at (2,0) does not point into the wall")
	# Under the wall (3,4) the arrow points right / up-right.
	var j := 4 * 7 + 3
	check(f.dir[j * 2] > 0.5, "arrow under the wall points right")
	# Walled-in target: nothing reachable.
	var g2 := _small_grid(5, 5, [Vector2i(1, 2), Vector2i(3, 2), Vector2i(2, 1), Vector2i(2, 3)])
	var f2 := FlowField.new()
	var t2: Array[Vector2i] = [Vector2i(2, 2)]
	f2.build(g2, t2)
	check(not f2.reachable(0, 0), "walled-in target unreachable")
	# Building cost: a cheap detour wins over chewing through.
	var g3 := _small_grid(5, 3, [])
	var f3 := FlowField.new()
	var t3: Array[Vector2i] = [Vector2i(4, 1)]
	f3.build(g3, t3, {1 * 5 + 2: 50.0})
	check(f3.dist[1 * 5 + 0] < 10.0, "detour around a costly building")


func _test_swarm_ids_and_bins() -> void:
	var s := SwarmSim.new()
	s.setup(8, 4, 4)
	var ids := []
	for k in 5:
		ids.append(s.spawn(Vector2(10 + k * MapGrid.CELL.x, 10), 1.0, 5.0, 0.5, 0.0))
	check(s.count == 5, "spawned 5")
	s.remove_slot(1)
	check(s.count == 4, "count after remove")
	check(not s.alive(ids[1]), "removed id is dead")
	for k in [0, 2, 3, 4]:
		check(s.alive(ids[k]), "id %d alive" % k)
		check(is_equal_approx(s.position_of(ids[k]).x, 10 + k * MapGrid.CELL.x), "id %d keeps its position" % k)
	s.bin()
	var total := 0
	for v in s.cell_count:
		total += v
	check(total == 4, "bins hold every slime")
	check(s.cell_count[0] == 1 and s.cell_count[1] == 0, "cell 1 is empty after removal")
	# Full: spawn returns -1.
	s.clear()
	for k in 8:
		s.spawn(Vector2(1, 1), 1.0, 1.0, 0.0, 0.0)
	check(s.spawn(Vector2(1, 1), 1.0, 1.0, 0.0, 0.0) == -1, "spawn when full returns -1")


func _test_swarm_queries() -> void:
	var s := SwarmSim.new()
	s.setup(16, 10, 10)
	var a := s.spawn(Vector2(100, 100), 1.0, 5.0, 0.0, 0.0)
	var b := s.spawn(Vector2(300, 100), 1.0, 5.0, 0.0, 0.0)
	var c := s.spawn(Vector2(120, 110), 1.0, 5.0, 0.0, 0.0)
	s.bin()
	check(s.nearest(Vector2(125, 112), 500.0) == c, "nearest picks the closest")
	check(s.nearest(Vector2(600, 400), 50.0) == -1, "nearest respects the range")
	check(s.nearest(Vector2(290, 100), 500.0) == b, "nearest in another cell")
	var killed := s.damage_radius(Vector2(110, 105), 40.0, 10.0)
	check(killed == 2 and not s.alive(a) and not s.alive(c) and s.alive(b), "explosion kills the two near ones")
	check(not s.damage(b, 1.0) and s.alive(b), "1 damage does not kill")
	# Cone: from (100,100) looking right, b at (300,100) is inside 10°, looking down nothing.
	s.bin()
	var cos10 := cos(deg_to_rad(10.0))
	check(s.nearest_in_cone(Vector2(100, 100), 500.0, Vector2.RIGHT, cos10) == b, "cone finds the slime ahead")
	check(s.nearest_in_cone(Vector2(100, 100), 500.0, Vector2.DOWN, cos10) == -1, "cone ignores slimes outside it")


func _test_crawl_speed() -> void:
	# A slime crawling along an open corridor must average rig.avg_speed() cells/s.
	var rig := load("res://game/objects/slime/slime_rig.tres") as SlimeRig
	var crawl := SlimeCrawl.new(rig)
	var g := _small_grid(200, 3, [])
	var f := FlowField.new()
	var t: Array[Vector2i] = [Vector2i(199, 1)]
	f.build(g, t)
	var s := SwarmSim.new()
	s.setup(4, g.cols, g.rows)
	s.spawn(Vector2(112, MapGrid.CELL.y * 1.5), 1.0, 1.0, 0.0, 0.0)
	s.bin()
	var dt := 1.0 / 60.0
	var secs := rig.period * 20.0
	var steps := int(round(secs / dt))
	for k in steps:
		s.step(dt, f, g, crawl, rig.width_px())
	var cells := (s.px[0] - 112.0) / MapGrid.CELL.x
	var speed := cells / (steps * dt)
	check(absf(speed - rig.avg_speed()) / rig.avg_speed() < 0.03, "crawl speed %.4f vs avg_speed %.4f" % [speed, rig.avg_speed()])


func _test_swarm_reaches_target() -> void:
	var rig := load("res://game/objects/slime/slime_rig.tres") as SlimeRig
	var crawl := SlimeCrawl.new(rig)
	var g := _small_grid(12, 6, [Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3)])
	var f := FlowField.new()
	var t: Array[Vector2i] = [Vector2i(10, 1)]
	f.build(g, t)
	var s := SwarmSim.new()
	s.setup(64, g.cols, g.rows)
	for k in 30:
		s.spawn(Vector2(40 + (k % 5) * 6, 60 + (k / 5) * 6), 6.0, 1.0, randf(), randf())
	s.bin()
	var in_wall := 0
	for k in 60 * 120:
		s.step(1.0 / 60.0, f, g, crawl, rig.width_px())
		for i in s.count:
			if g.is_blocked(int(s.px[i] / MapGrid.CELL.x), int(s.py[i] / MapGrid.CELL.y)):
				in_wall += 1
		if s.count == 0:
			break
	check(s.count == 0, "all slimes reached the target around the wall, left %d" % s.count)
	check(in_wall == 0, "no slime ever stood in a wall (%d)" % in_wall)
	check(s.reached_total == 30, "reached_total 30, got %d" % s.reached_total)


func _crowd_at_gap(n: int) -> Array:
	# Wall with a 1-cell gap, target behind it; `n` slimes spawned on the left.
	var rig := load("res://game/objects/slime/slime_rig.tres") as SlimeRig
	var g := _small_grid(24, 14, [])
	for r in 14:
		if r != 7:
			g.set_kind(14, r, MapGrid.Kind.ROCK)
	var f := FlowField.new()
	var t: Array[Vector2i] = [Vector2i(23, 7)]
	f.build(g, t)
	var s := SwarmSim.new()
	s.setup(512, g.cols, g.rows)
	var sw := Swarm.new()
	s.cell_capacity = sw.cell_capacity
	s.push_strength = sw.push_strength
	s.spread_strength = sw.spread_strength
	s.body = sw.body
	s.cohesion = sw.cohesion
	sw.free()
	seed(3)
	for k in n:
		s.spawn(Vector2(randf_range(20, 400), randf_range(20, 320)), 1.0 + randf_range(-0.25, 0.25), 1.0, randf(), randf())
	s.bin()
	return [s, f, g, SlimeCrawl.new(rig), rig.width_px()]


func _test_crowd_spacing() -> void:
	# Jammed at the gap: a pile — the 3 nearest neighbours ≈ 0.75 picture width away (body 0.8),
	# not one slime per cell (the old model: ≈ 1 width and more).
	var c := _crowd_at_gap(200)
	var s: SwarmSim = c[0]
	var w: float = c[4]
	for k in 60 * 25:
		s.step(1.0 / 60.0, c[1], c[2], c[3], w)
	var wall_x := 14 * MapGrid.CELL.x
	var nn := PackedFloat32Array()
	var d3 := PackedFloat32Array()
	for i in s.count:
		if s.px[i] > wall_x:
			continue
		var near := PackedFloat32Array()
		for j in s.count:
			if j != i and s.px[j] < wall_x:
				near.append(Vector2(s.px[i] - s.px[j], (s.py[i] - s.py[j]) / 0.75).length())
		near.sort()
		nn.append(near[0] / w)
		d3.append((near[0] + near[1] + near[2]) / 3.0 / w)
	nn.sort()
	d3.sort()
	var med := d3[d3.size() / 2]
	print("crowd: 3 nearest / width: p25 %.2f median %.2f p75 %.2f; nearest min %.2f (%d slimes)" % [d3[d3.size() / 4], med, d3[d3.size() * 3 / 4], nn[0], d3.size()])
	check(med > 0.62 and med < 0.86, "jammed crowd is a pile: 3 nearest ≈ 0.75 width, got %.2f" % med)
	# Almost no two slimes on one spot. Since 2026-10-09 the step is checked against cliffs / walls
	# along its whole length (a crowd step is often over half a cell): it no longer cuts rock corners
	# by the gap, the pile there is a bit denser and a few (was 0, now ~4 %) end up nearly on top of
	# each other.
	var close := 0
	for v in nn:
		if v < 0.1:
			close += 1
	check(close <= nn.size() / 20, "almost no two slimes on one spot: %d of %d closer than 0.1 width (≤ 5 %%)" % [close, nn.size()])


func _test_crowd_gets_through() -> void:
	# The pile must drain through a 1-cell gap (cohesion must not hold the leaders back) and no
	# slime may end up inside the wall (float32 rounding at the wall edge used to put them there).
	var c := _crowd_at_gap(60)
	var s: SwarmSim = c[0]
	var g: MapGrid = c[2]
	var in_wall := 0
	for k in 60 * 75:
		s.step(1.0 / 60.0, c[1], g, c[3], c[4])
		for i in s.count:
			if g.is_blocked(int(s.px[i] / MapGrid.CELL.x), int(s.py[i] / MapGrid.CELL.y)):
				in_wall += 1
		if s.count == 0:
			break
	check(s.count == 0, "60 slimes get through a 1-cell gap in 75 s, left %d" % s.count)
	check(in_wall == 0, "no slime inside the wall (%d)" % in_wall)


func _test_multimesh_buffer_layout() -> void:
	# SwarmView writes MultiMesh.buffer directly: 2D transform (8 floats) + custom data (4).
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.instance_count = 1
	var buf := mm.buffer
	if buf.size() == 0:
		print("skip: multimesh buffer not available in this renderer (headless)")
		return
	mm.set_instance_transform_2d(0, Transform2D(Vector2(1, 2), Vector2(3, 4), Vector2(5, 6)))
	mm.set_instance_custom_data(0, Color(0.25, 0.5, 0.75, 1.0))
	buf = mm.buffer
	print("multimesh buffer: ", buf)
	var want := PackedFloat32Array([1, 3, 0, 5, 2, 4, 0, 6, 0.25, 0.5, 0.75, 1.0])
	check(buf.size() == 12, "buffer stride 12, got %d" % buf.size())
	var ok := buf.size() == 12
	for k in mini(12, buf.size()):
		ok = ok and is_equal_approx(buf[k], want[k])
	check(ok, "buffer layout [x.x y.x 0 o.x  x.y y.y 0 o.y  custom]")


func _test_wallet() -> void:
	var w := Wallet.new()
	check(w.amount("crystal") == 200, "wallet starts with 200 crystals, got %d" % w.amount("crystal"))
	var seen := []
	w.changed.connect(func(res: String, amount: int, delta: int) -> void: seen.append([res, amount, delta]))
	w.add("crystal", 5)
	check(w.amount("crystal") == 205 and seen == [["crystal", 205, 5]], "add 5 → 205 and one signal, got %s" % [seen])
	check(not w.pay({"crystal": 300}) and w.amount("crystal") == 205, "too expensive: nothing taken")
	check(not w.pay({"crystal": 10, "essence": 1}) and w.amount("crystal") == 205, "missing second resource: nothing taken")
	check(w.pay({"crystal": 105}) and w.amount("crystal") == 100, "pay 105 → 100")
	w.free()


func _test_drill_beams() -> void:
	# Beam goes out at lower + charge + fire = 0.5 + 0.6 + 2.5 = 3.6 s, cycle 5.6 s.
	var r := DrillRig.new()
	check(is_equal_approx(r.fire_end(), 3.6) and is_equal_approx(r.cycle_len(), 5.6), "drill timing 3.6 / 5.6 s")
	check(r.beams_done(0.0) == 0 and r.beams_done(3.59) == 0, "no crystals before the first beam ends")
	check(r.beams_done(3.61) == 1 and r.beams_done(9.19) == 1 and r.beams_done(9.21) == 2, "one portion per cycle")
	check(r.beams_done(3.61 + 5.6 * 10) == 11, "a long frame does not lose portions")
	check(r.crystals_per_cycle == 5, "5 crystals a cycle")


func _test_bullet_pierce() -> void:
	# docs/concept.md «Пробиття»: bullet 10, slimes 3 → 3 → 3 → 40 in a row: three die (10 → 7 → 4 → 1),
	# the big one gets 1 and keeps 39.
	var s := SwarmSim.new()
	s.setup(32, 20, 10)
	var row := []
	for k in 3:
		row.append(s.spawn(Vector2(100 + 40 * k, 100), 1.0, 3.0, 0.0, 0.0))
	var big := s.spawn(Vector2(220, 103), 1.0, 40.0, 0.0, 0.0)
	var aside := s.spawn(Vector2(140, 140), 1.0, 3.0, 0.0, 0.0)  # 40 px off the line: not hit
	s.bin()
	var left := s.hit_with_pool(row[0], 10.0)
	check(is_equal_approx(left, 7.0) and not s.alive(row[0]), "first slime dies, 7 left")
	var res := s.pierce(Vector2(100, 100), Vector2.RIGHT, 400.0, left, 10.0, 8, row[0])
	check(not s.alive(row[1]) and not s.alive(row[2]), "the bullet flies on and kills the next two")
	check(s.alive(big) and is_equal_approx(s.hp_of(big), 39.0), "the big one gets the last 1 (hp %.1f)" % s.hp_of(big))
	check(s.alive(aside), "a slime off the line is not hit")
	check(res.kills == 2 and is_equal_approx(float(res.left), 0.0) and is_equal_approx(float(res.stop), 120.0), "stops in the big one: %s" % [res])
	# Pool bigger than everything on the line: flies to the end of the range.
	var s2 := SwarmSim.new()
	s2.setup(8, 20, 10)
	var one := s2.spawn(Vector2(150, 100), 1.0, 3.0, 0.0, 0.0)
	s2.bin()
	var r2 := s2.pierce(Vector2(100, 100), Vector2.RIGHT, 300.0, 10.0, 10.0, 8)
	check(not s2.alive(one) and is_equal_approx(float(r2.stop), 300.0) and is_equal_approx(float(r2.left), 7.0), "nothing more on the line: flies to the end with 7")


func _test_grenade_blast() -> void:
	# Core 28 px: 20 damage; ring to 128 px: 2 → 1.5 (wounds a 3 hp slime, two blasts kill it).
	var s := SwarmSim.new()
	s.setup(16, 20, 20)
	var centre := s.spawn(Vector2(200, 200), 1.0, 3.0, 0.0, 0.0)
	var near := s.spawn(Vector2(220, 210), 1.0, 3.0, 0.0, 0.0)  # 22 px: core
	var ring := s.spawn(Vector2(280, 200), 1.0, 3.0, 0.0, 0.0)  # 80 px: ring
	var out := s.spawn(Vector2(340, 200), 1.0, 3.0, 0.0, 0.0)  # 140 px: outside
	var big := s.spawn(Vector2(205, 195), 1.0, 40.0, 0.0, 0.0)
	s.bin()
	var killed := s.damage_blast(Vector2(200, 200), 28.0, 20.0, 128.0, 2.0, 1.5)
	check(killed == 2 and not s.alive(centre) and not s.alive(near), "the core kills (got %d)" % killed)
	check(s.alive(ring) and s.hp_of(ring) > 1.0 and s.hp_of(ring) < 1.5, "the ring only wounds (hp %.2f)" % s.hp_of(ring))
	check(s.alive(out) and is_equal_approx(s.hp_of(out), 3.0), "outside the blast: untouched")
	check(s.alive(big) and is_equal_approx(s.hp_of(big), 20.0), "big slime (40) survives one blast with 20")
	s.bin()
	s.damage_blast(Vector2(200, 200), 28.0, 20.0, 128.0, 2.0, 1.5)
	check(not s.alive(ring) and not s.alive(big), "the second blast finishes the wounded and the big one")


func _test_drone_nav() -> void:
	# A purple (no-fly) wall across the map with a 2-cell gap: the drone goes through the gap.
	var g := MapGrid.open(30, 10)
	for r in 10:
		if r != 4 and r != 5:
			g.set_no_fly(15, r, true)
	var nav := DroneNav.build(g)
	var a := g.cell_center(Vector2i(2, 1))
	var b := g.cell_center(Vector2i(28, 1))
	check(not nav.clear(a, b), "straight line crosses the no-fly wall")
	var path := nav.path(a, b)
	var ok := path.size() >= 2 and path[path.size() - 1] == b
	var prev := a
	var through_gap := false
	for p in path:
		ok = ok and nav.clear(prev, p)
		var c := g.cell_at(p)
		through_gap = through_gap or (c.x >= 14 and c.x <= 16 and (c.y == 4 or c.y == 5))
		prev = p
	check(ok, "every leg of the route is clear of no-fly cells (%d points)" % path.size())
	check(through_gap, "the route goes through the gap in the wall")
	check(path.size() <= 4, "straightened: few turns, not cell by cell (%d points)" % path.size())
	# Tall decor cells block too (extra), and a closed wall means: fly straight.
	var nav2 := DroneNav.build(g, [Vector2i(15, 4), Vector2i(15, 5)])
	check(nav2.path(a, b) == PackedVector2Array([b]), "no way round → straight to the goal")
	check(nav.path(a, g.cell_center(Vector2i(10, 1))) == PackedVector2Array([g.cell_center(Vector2i(10, 1))]), "nothing in the way → one straight leg")
	# Pits are flown over: a pit cell is ROCK for slimes but not no-fly.
	var g2 := MapGrid.open(10, 3)
	g2.set_kind(5, 1, MapGrid.Kind.ROCK)
	check(not g2.fly_blocked(5, 1) and DroneNav.build(g2).clear(g2.cell_center(Vector2i(1, 1)), g2.cell_center(Vector2i(8, 1))), "a rock cell that is not no-fly does not stop the drone")


func _test_wall() -> void:
	# docs/concept.md «Будівництво»: wall 2×2, 300 hp; slimes walk round it, a full wall across the
	# pass is still a way (they will chew through once they bite; for now they walk through).
	var r := load("res://game/objects/wall/wall_rig.tres") as BlockRig
	check(r.footprint == Vector2i(1, 1) and is_equal_approx(r.max_hp, 300.0) and r.path_cost >= FlowField.SOLID and r.solid, "wall rig: 1×1, 300 hp, solid, path cost ≥ SOLID (%.0f)" % r.path_cost)
	# 9×5 field, a 2-cell wall across rows 1..2 at column 4: round it (rows 0 / 3..4) is cheaper.
	var g := _small_grid(9, 5, [])
	var f := FlowField.new()
	var t: Array[Vector2i] = [Vector2i(8, 2)]
	f.build(g, t, {1 * 9 + 4: r.path_cost, 2 * 9 + 4: r.path_cost})
	check(f.dist[2 * 9 + 0] < 12.0, "slimes go round a wall (dist %.1f)" % f.dist[2 * 9 + 0])
	# A wall across the whole pass (rows 0..4): still reachable, through the wall.
	var across := {}
	for row in 5:
		across[row * 9 + 4] = r.path_cost
	var f2 := FlowField.new()
	f2.build(g, t, across)
	check(f2.reachable(0, 2) and f2.dist[2 * 9 + 0] > r.path_cost, "a wall across the pass: still a way, through it (dist %.1f)" % f2.dist[2 * 9 + 0])
	var w := (load("res://game/objects/wall/wall.tscn") as PackedScene).instantiate() as BlockBuilding
	w.hp = w.rig.max_hp
	check(not w.damage(120.0) and is_equal_approx(w.hp, 180.0) and w.damage(180.0) and w.hp == 0.0, "wall hp: 300 − 120 = 180, then 0 → destroyed")
	w.free()


## Every step of a line moves to a side neighbour (no corner-only joints slimes slip through).
func _four_connected(start: Vector2i, cells: Array[Vector2i]) -> bool:
	var p := start
	for c in cells:
		if absi(c.x - p.x) + absi(c.y - p.y) != 1:
			return false
		p = c
	return true


func _test_wall_line() -> void:
	# docs/concept.md «Будівництво»: the wall is painted; between two touch samples the cells are filled
	# in, each a side neighbour of the one before (no corner-only joints slimes slip through).
	var straight := Builder.cells_between(Vector2i(2, 3), Vector2i(8, 3))
	check(straight.size() == 6 and straight.back() == Vector2i(8, 3) and _four_connected(Vector2i(2, 3), straight), "straight stroke: 6 cells to the new sample (%s)" % [straight])
	var diag := Builder.cells_between(Vector2i(2, 2), Vector2i(8, 8))
	var far := 0.0
	for c in diag:
		far = maxf(far, absf(float(c.x - 2) - float(c.y - 2)) / sqrt(2.0))
	check(diag.size() == 12 and _four_connected(Vector2i(2, 2), diag) and far <= 1.0, "diagonal stroke: a 4-connected staircase of 12 cells hugging the line (off ≤ %.2f)" % far)
	var steep := Builder.cells_between(Vector2i(5, 1), Vector2i(3, 9))
	check(steep.size() == 10 and steep.back() == Vector2i(3, 9) and _four_connected(Vector2i(5, 1), steep), "steep slanted stroke: 10 cells, 4-connected")
	check(Builder.cells_between(Vector2i(4, 4), Vector2i(4, 4)).is_empty(), "same cell: nothing in between")
	var cost := Builder.line_cost(load("res://game/core/build_catalog.tres").items[3], 7)
	check(cost == {"crystal": 70}, "wall price: 10 a piece × 7 = 70 (%s)" % [cost])


## A swarm on a 24×14 field, target at (23, 7), 60 slimes on the left, walls = solid cells (as
## GameMap.walk_blocked() gives them) that cost FlowField.SOLID+ in the field (as walls do).
func _wall_run(walls: Array, seconds: float) -> Dictionary:
	var rig := load("res://game/objects/slime/slime_rig.tres") as SlimeRig
	var wr := load("res://game/objects/wall/wall_rig.tres") as BlockRig
	var g := _small_grid(24, 14, [])
	var costs := {}
	var solid := g.blocked.duplicate()
	for c in walls:
		costs[c.y * g.cols + c.x] = wr.path_cost
		solid[c.y * g.cols + c.x] = 1
	var f := FlowField.new()
	var t: Array[Vector2i] = [Vector2i(23, 7)]
	f.build(g, t, costs)
	var s := SwarmSim.new()
	s.setup(256, g.cols, g.rows)
	var sw := Swarm.new()
	s.cell_capacity = sw.cell_capacity
	s.push_strength = sw.push_strength
	s.spread_strength = sw.spread_strength
	s.body = sw.body
	s.cohesion = sw.cohesion
	sw.free()
	s.solid = solid
	seed(5)
	for k in 60:
		s.spawn(Vector2(randf_range(20, 200), randf_range(30, 300)), 1.0, 1.0, randf(), randf())
	s.bin()
	var in_wall := 0
	var max_x := 0.0
	for k in int(60 * seconds):
		s.step(1.0 / 60.0, f, g, _crawl_cache, rig.width_px())
		for i in s.count:
			var c := Vector2i(int(s.px[i] / MapGrid.CELL.x), int(s.py[i] / MapGrid.CELL.y))
			if solid[c.y * g.cols + c.x] == 1:
				in_wall += 1
			max_x = maxf(max_x, s.px[i])
		if s.count == 0:
			break
	var xs := PackedFloat32Array()
	for i in s.count:
		xs.append(s.px[i])
	xs.sort()
	return {"left": s.count, "in_wall": in_wall, "max_x": max_x, "median_x": xs[xs.size() / 2] if xs.size() > 0 else 0.0}


var _crawl_cache: SlimeCrawl


func _test_wall_holds_slimes() -> void:
	# docs/concept.md «Будівництво»: a slime never gets over a wall; no way round — they crowd at it.
	_crawl_cache = SlimeCrawl.new(load("res://game/objects/slime/slime_rig.tres") as SlimeRig)
	var across := []
	for r in 14:
		across.append(Vector2i(12, r))
	var a := _wall_run(across, 40.0)
	var wall_x := 12 * MapGrid.CELL.x
	check(a.left == 60 and a.max_x < wall_x and a.in_wall == 0, "wall across the whole field: nobody gets over (left %d, furthest x %.0f < %.0f, in wall %d)" % [a.left, a.max_x, wall_x, a.in_wall])
	check(a.median_x > wall_x - 4.0 * MapGrid.CELL.x, "…they crowd at the wall (median x %.0f, wall at %.0f)" % [a.median_x, wall_x])
	# A gap far from the straight way (row 1): they walk round through it, nobody through the wall.
	var gap := []
	for r in 14:
		if r != 1:
			gap.append(Vector2i(12, r))
	var b := _wall_run(gap, 90.0)
	check(b.left == 0 and b.in_wall == 0, "wall with a gap: all go round through it (left %d, in wall %d)" % [b.left, b.in_wall])
	# Two walls touching only at a corner: no slipping between them diagonally.
	var corner := []
	for r in 7:
		corner.append(Vector2i(12, r))
	for r in range(7, 14):
		corner.append(Vector2i(13, r))
	var c := _wall_run(corner, 40.0)
	check(c.left == 60 and c.in_wall == 0 and c.max_x < 14 * MapGrid.CELL.x, "walls touching at a corner: nobody slips through (left %d, furthest x %.0f)" % [c.left, c.max_x])

