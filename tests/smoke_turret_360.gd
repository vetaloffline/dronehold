extends SceneTree
## Every turret must kill a lone slime in each of 16 directions (360° without dead zones).
##   godot --headless --path . --script res://tests/smoke_turret_360.gd
## Exit 0 and «turret 360: 0 failed» = ok.

const DIRS := 16
const RADIUS := 250.0
const TIMEOUT_S := 12.0

var _sb: Node
var _swarm: Swarm
var _kinds := ["Кулемет", "Гранатомет"]
var _k := 0
var _dir := -1
var _wait := 0.0
var _kills_before := 0
var _failed := 0
var _missed: Array[String] = []
var _frame := 0


func _initialize() -> void:
	_sb = (load("res://game/sandbox/turret_sandbox.tscn") as PackedScene).instantiate()
	root.add_child(_sb)


func _next_dir() -> void:
	_dir += 1
	_swarm.sim.clear()
	_swarm.sim.bin()
	var c: Vector2 = (_sb.get_node("Map") as GameMap).grid.size_px() * 0.5
	var a := TAU * _dir / DIRS
	_swarm.spawn_at(c + Vector2(cos(a) * RADIUS, sin(a) * RADIUS * 0.75))
	_kills_before = _swarm.sim.killed_total
	_wait = 0.0


func _process(dt: float) -> bool:
	_frame += 1
	if _frame == 2:
		_swarm = _sb.get_node("Map/Swarm") as Swarm
		_swarm.frozen = true
		_sb.call("_put_turret", _kinds[_k])
		return false
	if _frame < 6:
		return false
	if _dir < 0:
		_next_dir()
		return false
	_wait += dt
	var killed := _swarm.sim.killed_total > _kills_before
	if killed or _wait > TIMEOUT_S:
		if not killed:
			_failed += 1
			_missed.append("%s %d°" % [_kinds[_k], int(360.0 * _dir / DIRS)])
		if _dir + 1 >= DIRS:
			print("%s: %d of %d directions killed" % [_kinds[_k], DIRS - _missed.filter(func(m): return m.begins_with(_kinds[_k])).size(), DIRS])
			_k += 1
			if _k >= _kinds.size():
				if not _missed.is_empty():
					printerr("FAIL: missed ", _missed)
				print("turret 360: %d failed" % _failed)
				quit(1 if _failed > 0 else 0)
				return true
			_sb.call("_put_turret", _kinds[_k])
			_dir = -1
			_frame = 2
			return false
		_next_dir()
	return false
