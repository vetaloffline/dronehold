extends SceneTree
## Turret test range headless: slimes put at «click» points, both turrets kill them, freeze works.
##   godot --headless --path . --script res://tests/smoke_sandbox.gd
## Exit 0 and «sandbox: 0 failed» = ok.

var _sb: Node
var _swarm: Swarm
var _frame := 0
var _failed := 0
var _kills_mg := 0
var _frozen_pos := Vector2.ZERO


func _initialize() -> void:
	_sb = (load("res://game/sandbox/turret_sandbox.tscn") as PackedScene).instantiate()
	root.add_child(_sb)


func check(cond: bool, what: String) -> void:
	if not cond:
		_failed += 1
		printerr("FAIL: ", what)
	else:
		print("ok: ", what)


func _ring(n: int, rx: float, ry: float) -> int:
	var c: Vector2 = (_sb.get_node("Map") as GameMap).grid.size_px() * 0.5
	var put := 0
	for k in n:
		var a := TAU * k / n
		if _swarm.spawn_at(c + Vector2(cos(a) * rx, sin(a) * ry)):
			put += 1
	return put


func _process(_dt: float) -> bool:
	_frame += 1
	if _frame > 4000:
		printerr("FAIL: did not finish")
		quit(1)
		return true
	match _frame:
		1:
			_swarm = _sb.get_node("Map/Swarm") as Swarm
		5:
			check(_ring(30, 330.0, 240.0) == 30, "30 slimes placed by «clicks»")
		900:
			_kills_mg = _swarm.sim.killed_total
			check(_kills_mg > 0, "machine gun kills (%d)" % _kills_mg)
			_swarm.sim.clear()
			_sb.call("_put_turret", "Гранатомет")
		905:
			check(_ring(30, 300.0, 220.0) == 30, "30 more slimes for the launcher")
		1800:
			check(_swarm.sim.killed_total > _kills_mg, "grenade launcher kills (%d)" % (_swarm.sim.killed_total - _kills_mg))
			_swarm.sim.clear()
			_sb.call("_toggle_freeze")
			_swarm.spawn_at(Vector2(60, 60))
		1802:
			_frozen_pos = _swarm.sim.position_of(_swarm.sim.id_of[0])
		1900:
			check(_swarm.sim.count == 0 or _swarm.sim.position_of(_swarm.sim.id_of[0]) == _frozen_pos, "frozen slime does not move")
			print("sandbox: %d failed" % _failed)
			quit(1 if _failed > 0 else 0)
			return true
	return false
