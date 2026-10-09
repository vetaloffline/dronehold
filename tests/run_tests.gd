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
	check(nn[0] > 0.1, "no two slimes on one spot, nearest min %.2f" % nn[0])


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
