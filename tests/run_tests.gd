extends SceneTree
## Headless tests. Run:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exit code 0 = all passed.

var _failed := 0
var _passed := 0


func _init() -> void:
	_test_grid_from_layout()
	_test_flow_field()
	_test_swarm_ids_and_bins()
	_test_swarm_queries()
	_test_crawl_speed()
	_test_swarm_reaches_target()
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
	check(g.cols == 78 and g.rows == 58, "grid 78x58, got %dx%d" % [g.cols, g.rows])
	# Reference: the editor's coverage() rule computed in Python over the same PNG.
	check(g.blocked_count() == 1197, "blocked cells 1197, got %d" % g.blocked_count())


func _small_grid(cols: int, rows: int, walls: Array) -> MapGrid:
	var g := MapGrid.new()
	g.cols = cols
	g.rows = rows
	g.blocked.resize(cols * rows)
	g.blocked.fill(0)
	for w in walls:
		g.blocked[w.y * cols + w.x] = 1
	return g


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
		ids.append(s.spawn(Vector2(10 + k * 64, 10), 1.0, 5.0, 0.5, 0.0))
	check(s.count == 5, "spawned 5")
	s.remove_slot(1)
	check(s.count == 4, "count after remove")
	check(not s.alive(ids[1]), "removed id is dead")
	for k in [0, 2, 3, 4]:
		check(s.alive(ids[k]), "id %d alive" % k)
		check(is_equal_approx(s.position_of(ids[k]).x, 10 + k * 64), "id %d keeps its position" % k)
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
	s.spawn(Vector2(112, 72), 1.0, 1.0, 0.0, 0.0)
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
			if g.is_blocked(int(s.px[i] / 64.0), int(s.py[i] / 48.0)):
				in_wall += 1
		if s.count == 0:
			break
	check(s.count == 0, "all slimes reached the target around the wall, left %d" % s.count)
	check(in_wall == 0, "no slime ever stood in a wall (%d)" % in_wall)
	check(s.reached_total == 30, "reached_total 30, got %d" % s.reached_total)


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
