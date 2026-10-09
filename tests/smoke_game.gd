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
			if _frame == 2:
				check(_swarm.sim != null and _swarm.field != null, "swarm is set up")
				check(map.target_cells().size() == 36, "core gives 36 target cells (6×6)")
				check(map.spawn_points().size() >= 1, "map has spawn points")
				check(_swarm._spawn_cells.size() == map.spawn_points().size(), "every spawn point has a reachable cell nearby")
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
			if _frame == 600:
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
