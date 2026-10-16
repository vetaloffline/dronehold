extends SceneTree
## Turret test range headless: slimes put at «click» points, every turret kills them, freeze works.
## Ground test range: the tiled ground covers its whole field.
## Cliff test range: painted cliff cells become blocks, rock cells and no-fly.
## Map A (game/maps/map_a): objects stand where they may, the first vein is in the core's radius, every
## spawn reaches the core, the game (main.tscn) starts on it.
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
			_kills_mg = _swarm.sim.killed_total
			_swarm.sim.clear()
			_sb.call("_put_turret", "Легкий кулемет")
		1805:
			check(_ring(30, 330.0, 240.0) == 30, "30 more slimes for the light machine gun (inside its 13 cells)")
		2700:
			check(_swarm.sim.killed_total > _kills_mg, "light machine gun kills (%d)" % (_swarm.sim.killed_total - _kills_mg))
			_swarm.sim.clear()
			_sb.call("_toggle_freeze")
			_swarm.spawn_at(Vector2(60, 60))
		2702:
			_frozen_pos = _swarm.sim.position_of(_swarm.sim.id_of[0])
		2800:
			check(_swarm.sim.count == 0 or _swarm.sim.position_of(_swarm.sim.id_of[0]) == _frozen_pos, "frozen slime does not move")
			_check_ground_sandbox()
			_check_cliff_sandbox()
			_check_map_a()
			print("sandbox: %d failed" % _failed)
			quit(1 if _failed > 0 else 0)
			return true
	return false


## Ground test range: one TiledGround under everything, covering the whole field with mipmapped sampling.
func _check_ground_sandbox() -> void:
	var sb := (load("res://game/sandbox/ground_sandbox.tscn") as PackedScene).instantiate()
	root.add_child(sb)
	var map := sb.get_node("Map") as GameMap
	var g := sb.get_node_or_null("Map/Ground") as TiledGround
	check(g != null and g.texture != null, "ground range: Ground is a TiledGround with a texture")
	if g and g.texture:
		check(g.texture.get_size() == Vector2(1024, 1024), "ground tile is 1024×1024 (%s)" % g.texture.get_size())
		check(g.area() == map.grid.size_px(), "ground covers the whole field (%s)" % g.area())
		check(g.z_index == -3 and g.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "ground: z −3, linear mipmap filter")
	check(sb.get_node("Map/World").find_children("*", "MapObject", false, false).size() == 1, "ground range has the test turret")
	sb.free()


## Cliff test range: every painted cell has a block, cliff cells are rock and no-fly, the layer is hidden.
func _check_cliff_sandbox() -> void:
	var sb := (load("res://game/sandbox/cliff_sandbox.tscn") as PackedScene).instantiate()
	root.add_child(sb)
	var map := sb.get_node("Map") as GameMap
	var cells := sb.get_node_or_null("Map/CliffCells") as CliffCells
	var cliffs := sb.get_node_or_null("Map/World/Cliffs") as Cliffs
	check(cells != null and cliffs != null, "cliff range: CliffCells on the map, Cliffs in World")
	if cells == null or cliffs == null:
		sb.free()
		return
	var used := cells.get_used_cells()
	var walls := 0
	for c in used:
		if cells.get_cell_atlas_coords(c).x == Cliffs.Tile.WALL:
			walls += 1
	check(walls > 0 and walls < used.size(), "cliff range: both tiles painted (%d wall, %d rock)" % [walls, used.size() - walls])
	var blocks := 0
	for r in cliffs._rows:
		blocks += (cliffs._rows[r] as Array).size()
	check(blocks == used.size(), "a block per painted cell (%d / %d)" % [blocks, used.size()])
	check(cliffs.get_child_count(true) > 0 and cliffs.y_sort_enabled, "cliff rows are y-sorted children (%d)" % cliffs.get_child_count(true))
	check(map.grid.kind(0, 0) == MapGrid.Kind.ROCK and map.grid.fly_blocked(0, 0) and map.grid.kind(48, 30) == MapGrid.Kind.GROUND,
		"cliff cells are rock and no-fly, open ground stays ground")
	check(not cells.visible and cells.cells_changed.get_connections().size() > 0, "cells layer hidden in the game, Cliffs listens to it")
	# Decor on a rock cell stands on the block top and sorts after that row; on open ground it does not move.
	var on_rock := _prop(map, Vector2i(20, 12))
	var on_ground := _prop(map, Vector2i(48, 20))
	check(on_rock.cliff_lift > 20.0 and is_equal_approx(on_rock.position.y, 14 * MapGrid.CELL.y - 0.5),
		"tree on the rock ridge: lifted %.1f px, sorted after cliff row 13 (y %.1f)" % [on_rock.cliff_lift, on_rock.position.y])
	check(on_ground.cliff_lift == 0.0 and is_equal_approx(on_ground.position.y, (20 + 2 * 0.85) * MapGrid.CELL.y),
		"tree on open ground: no lift, usual ground point (y %.1f)" % on_ground.position.y)
	check(on_rock.cell_for_point(on_rock.position) == on_rock.cell and on_ground.cell_for_point(on_ground.position) == on_ground.cell,
		"dragging snaps back to the same cell on and off the cliff")
	sb.free()


func _prop(map: GameMap, c: Vector2i) -> Prop:
	var p := (load("res://game/core/prop.tscn") as PackedScene).instantiate() as Prop
	p.foot = Vector2i(2, 2)
	p.cell = c
	map.world().add_child(p)
	return p



## Map A (concept «Ущелина», art/maps/map_a/map_a_natural.py): every object stands where it may, the drill slot of
## vein 1 is inside the core's build radius and vein 2's is not (one relay), every spawn reaches the core
## through the passes, the game (main.tscn) starts over the core.
func _check_map_a() -> void:
	var map := (load("res://game/maps/map_a/map_a.tscn") as PackedScene).instantiate() as GameMap
	root.add_child(map)
	var bad: Array[String] = []
	for o in map.objects():
		var why := map.placement_problem(o)
		if why != "":
			bad.append("%s: %s" % [o.name, why])
	check(bad.is_empty(), "map A: every object stands where it may %s" % [bad])
	var v1 := map.get_node("World/Vein1") as CrystalVein
	var v2 := map.get_node("World/Vein2") as CrystalVein
	check(Builder.in_radius(map, Builder.slot_cells(v1)) and not Builder.in_radius(map, Builder.slot_cells(v2)),
		"map A: vein 1 drill slot in the core radius, vein 2 needs a relay")
	var field := map.build_flow_field()
	var unreachable := 0
	for p in map.spawn_points("slime") + map.spawn_points("lasher"):
		var c := map.grid.cell_at(p)
		if not field.reachable(c.x, c.y):
			unreachable += 1
	check(map.spawn_points("slime").size() == 2 and map.spawn_points("lasher").size() == 1 and unreachable == 0,
		"map A: 2 slime + 1 lasher spawns, all reach the core")
	var cells := map.get_node("CliffCells") as CliffCells
	check(map.grid.count_kind(MapGrid.Kind.ROCK) == cells.get_used_cells().size(),
		"map A: %d cliff cells are rock in the game" % cells.get_used_cells().size())
	map.free()
	var play := (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(play)
	var cam := play.get_node("Camera") as Camera2D
	var core := play.get_node("MapA/World/Core") as Node2D
	check(cam.position == core.position, "the game (main.tscn) runs on map A and starts with the camera over the core")
	play.free()
