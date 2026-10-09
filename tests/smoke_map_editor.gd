extends SceneTree
## Map editor: menu button → paint with the mouse → rules change → undo → leave without saving.
## Does not call «Зберегти» (it would overwrite the map's grid file in the repo).
##   godot --headless --path . --script res://tests/smoke_map_editor.gd
## Exit 0 and «map editor: 0 failed» = ok.

var _frame := 0
var _failed := 0
var _ed: MapEditor
var _before := PackedByteArray()
var _spot := Vector2i.ZERO


var _fly_before := PackedByteArray()
var _kind_c := MapGrid.Kind.GROUND


func _initialize() -> void:
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))


func check(cond: bool, what: String) -> void:
	if not cond:
		_failed += 1
		printerr("FAIL: ", what)
	else:
		print("ok: ", what)


func _screen_of(cell: Vector2i) -> Vector2:
	var g := (_ed.get_node("Map03") as GameMap).grid
	return root.get_canvas_transform() * g.cell_center(cell)


func _mouse(cell: Vector2i, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = _screen_of(cell)
	e.global_position = e.position
	root.push_input(e, true)


func _move(cell: Vector2i) -> void:
	var e := InputEventMouseMotion.new()
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.position = _screen_of(cell)
	e.global_position = e.position
	root.push_input(e, true)


func _process(_dt: float) -> bool:
	_frame += 1
	match _frame:
		5:
			var found := false
			for b in current_scene.find_children("*", "Button", true, false):
				if (b as Button).text == "Редактор карти":
					(b as Button).pressed.emit()
					found = true
			check(found, "menu has «Редактор карти»")
		20:
			_ed = current_scene as MapEditor
			check(_ed != null, "«Редактор карти» opens the editor")
			if _ed == null:
				return _finish()
			var map := _ed.get_node("Map03") as GameMap
			_before = map.grid.kinds.duplicate()
			# An open ground cell in the middle of the screen, 2 cells clear around it.
			var mid := map.grid.cell_at(root.get_canvas_transform().affine_inverse() * (root.get_visible_rect().size * 0.5))
			_spot = Vector2i(-1, -1)
			for r in range(mid.y - 6, mid.y + 6):
				for c in range(mid.x - 6, mid.x + 6):
					var ok := true
					for dr in range(-2, 3):
						for dc in range(-2, 4):
							ok = ok and map.grid.kind(c + dc, r + dr) == MapGrid.Kind.GROUND
					if ok and _spot.x < 0:
						_spot = Vector2i(c, r)
			check(_spot.x >= 0, "found open ground on screen (%s)" % _spot)
			# A slime standing there must be removed when the cell becomes rock.
			var sw := map.get_node("Swarm") as Swarm
			sw.spawn_per_sec = 0.0
			sw.target_count = 10
			sw.sim.clear()
			sw.frozen = true
			sw.sim.spawn(map.grid.cell_center(_spot + Vector2i(1, 0)), 1.0, 1.0, 0.0, 0.0)
			check(sw.sim.count == 1, "a test slime stands on the spot")
			_ed.set_kind(MapGrid.Kind.ROCK)
			_ed.set_brush(1)
			_ed.set_rect_tool(false)
			_mouse(_spot, true)
			_move(_spot + Vector2i(1, 0))
			_move(_spot + Vector2i(3, 0))
			_mouse(_spot + Vector2i(3, 0), false)
		24:
			var map := _ed.get_node("Map03") as GameMap
			var g := map.grid
			var painted := true
			for dc in 4:
				painted = painted and g.kind(_spot.x + dc, _spot.y) == MapGrid.Kind.ROCK
			check(painted, "a mouse drag paints 4 cells in a row (no gaps)")
			check(g.kind(_spot.x, _spot.y + 1) == MapGrid.Kind.GROUND, "brush 1 paints only its row")
			check(not g.can_build(_spot.x, _spot.y) and g.is_blocked(_spot.x, _spot.y), "rock: no build, no walk")
			check(_ed.dirty, "editor knows there are unsaved changes")
			check((map.get_node("Swarm") as Swarm).sim.count == 0, "the slime inside the new rock is removed")
			# Rectangle of plateau, then undo it.
			_ed.set_kind(MapGrid.Kind.PLATEAU)
			_ed.set_rect_tool(true)
			_mouse(_spot + Vector2i(0, 1), true)
			_move(_spot + Vector2i(2, 2))
			_mouse(_spot + Vector2i(2, 2), false)
		28:
			var g := (_ed.get_node("Map03") as GameMap).grid
			var all := true
			for r in range(1, 3):
				for c in 3:
					all = all and g.kind(_spot.x + c, _spot.y + r) == MapGrid.Kind.PLATEAU
			check(all, "rectangle paints 3×2 plateau")
			check(g.can_build(_spot.x, _spot.y + 1) and g.is_blocked(_spot.x, _spot.y + 1), "plateau: build, no walk")
			_ed.undo()
			check(g.kind(_spot.x, _spot.y + 1) == MapGrid.Kind.GROUND, "undo takes the rectangle back")
			check(g.kind(_spot.x, _spot.y) == MapGrid.Kind.ROCK, "undo keeps the earlier stroke")
			# Drone layer: «Дрон» mode paints only where drones do not fly; the cell kinds stay.
			var map := _ed.get_node("Map03") as GameMap
			_fly_before = g.no_fly.duplicate()
			check(g.no_fly.size() == g.cols * g.rows and g.no_fly_count() > 0, "drone layer is filled from the layout's cliffs (%d cells)" % g.no_fly_count())
			_ed.set_layer(MapEditor.Layer.DRONE)
			check(map.show_no_fly and not map.show_blocked, "«Дрон» shows the purple layer instead of the cell kinds")
			_ed.set_no_fly(true)
			_ed.set_rect_tool(false)
			var c := _spot + Vector2i(0, 4)
			_kind_c = g.kind(c.x, c.y)
			_mouse(c, true)
			_mouse(c, false)
		32:
			var g := (_ed.get_node("Map03") as GameMap).grid
			var c := _spot + Vector2i(0, 4)
			check(g.fly_blocked(c.x, c.y), "drone brush marks the cell no-fly")
			check(g.kind(c.x, c.y) == _kind_c, "the cell kind is not touched by the drone brush")
			_ed.undo()
			check(not g.fly_blocked(c.x, c.y), "undo takes the drone stroke back")
			check(g.kind(_spot.x, _spot.y) == MapGrid.Kind.ROCK, "undo of a drone stroke keeps the cell strokes")
			_ed.set_layer(MapEditor.Layer.CELLS)
			# Leave without saving: first press warns, second leaves and restores the grid.
			_ed.call("_leave")
			check(current_scene == _ed, "first «Меню» with unsaved changes only warns")
			_ed.call("_leave")
		40:
			check(current_scene != null and current_scene.name == "MainMenu", "second «Меню» goes back")
			var g := (load("res://game/maps/map_03/map_03_grid.tres") as MapGrid)
			check(g.kinds == _before, "leaving without saving restores the grid")
			check(g.no_fly == _fly_before or g.no_fly.is_empty(), "…and the drone layer")
			return _finish()
	return false


func _finish() -> bool:
	print("map editor: %d failed" % _failed)
	quit(1 if _failed > 0 else 0)
	return true
