extends SceneTree
## Start the game like a player: menu → «Тест турелі» → 0 slimes → a click spawns one → «Меню».
##   godot --headless --path . --script res://tests/smoke_menu.gd
## Exit 0 and «menu: 0 failed» = ok.

var _frame := 0
var _failed := 0


func _initialize() -> void:
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))


func check(cond: bool, what: String) -> void:
	if not cond:
		_failed += 1
		printerr("FAIL: ", what)
	else:
		print("ok: ", what)


func _buttons(n: Node) -> Array[Button]:
	var out: Array[Button] = []
	for c in n.find_children("*", "Button", true, false):
		out.append(c as Button)
	return out


func _press(text_start: String) -> bool:
	for b in _buttons(current_scene):
		if b.text.begins_with(text_start):
			b.pressed.emit()
			return true
	return false


func _process(_dt: float) -> bool:
	_frame += 1
	match _frame:
		5:
			check(current_scene != null and current_scene.name == "MainMenu", "the game starts in the menu")
			check(_press("Тест кулемета"), "menu has «Тест кулемета»")
		20:
			check(current_scene.name == "TurretSandbox", "«Тест кулемета» opens the test range")
			var sw := current_scene.get_node("Map/Swarm") as Swarm
			check(sw.sim.count == 0, "the range starts with 0 slimes")
			# A left click at a point on the field.
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = root.get_visible_rect().size * Vector2(0.3, 0.5)
			click.global_position = click.position
			root.push_input(click)
		25:
			var sw := current_scene.get_node("Map/Swarm") as Swarm
			check(sw.sim.count == 1, "a click spawns one slime (got %d)" % sw.sim.count)
			check(_press("Меню"), "the range has «Меню»")
		40:
			check(current_scene.name == "MainMenu", "«Меню» goes back")
			print("menu: %d failed" % _failed)
			quit(1 if _failed > 0 else 0)
			return true
	return false
