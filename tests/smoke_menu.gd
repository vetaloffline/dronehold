extends SceneTree
## Start the game like a player: menu → «Тест кулемета» → 0 slimes → a click spawns one → «Меню»
## → «Грати» (level 1: map_03 with the crystal counter) → «Меню».
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


## Look, drones and the sound toggle of the main menu.
func _check_menu() -> void:
	var m := current_scene
	var gold := m.get_node("Menu/Buttons/Play") as Button
	check(gold.theme_type_variation == &"GoldButton" and gold.get_theme_stylebox("normal") is StyleBoxTexture, "the first button «Грати» is gold (theme GoldButton)")
	check(gold.get_index() == 0 and gold.text == "Грати", "«Грати» is on top")
	var dark := m.get_node("Menu/Buttons/MachineGunTest") as Button
	check(dark.theme_type_variation == &"DarkButton" and dark.get_theme_stylebox("normal") is StyleBoxTexture, "the others are dark (theme DarkButton)")
	check((m.get_node("World/Background") as Sprite2D).texture != null, "menu background is set")
	var world := m.get_node("World") as Node2D
	var vis := root.get_visible_rect().size
	var bg := (m.get_node("World/Background") as Sprite2D).texture.get_size() * world.scale
	check(bg.x >= vis.x - 1 and bg.y >= vis.y - 1, "background covers the screen (%s ≥ %s)" % [bg, vis])
	var drones := m.find_children("*", "MenuDrone", true, false)
	check(drones.size() == 3, "3 drones in the menu (got %d)" % drones.size())
	# Drone 1 starts sitting at point 1 (phase 0): it must take off, fly to point 2, land there.
	var d := drones[0] as MenuDrone
	var stops := d.stops()
	d.restart()
	var start := d.ground
	var max_h := 0.0
	var landed_at := Vector2.INF
	for _n in 400:  # 400 × 0.05 s = 20 s
		d.step(0.05)
		max_h = maxf(max_h, d.height)
		if d.mode == MenuDrone.Mode.SIT and d.ground.distance_to(start) > 1.0:
			landed_at = d.ground
			break
	check(start.distance_to(stops[0]) < 0.5, "drone 1 starts at point 1")
	check(max_h >= d.rig.fly_h - 0.01, "drone takes off to flight height (%.1f)" % max_h)
	check(landed_at.distance_to(stops[1]) < 0.5, "drone lands at point 2 (%s)" % landed_at)
	# Sound toggle: pressed = muted, Master bus muted, remembered in user://settings.cfg.
	var master := AudioServer.get_bus_index("Master")
	var was_on := Settings.sound_on()
	var snd := m.get_node("Sound") as TextureButton
	snd.button_pressed = true
	check(AudioServer.is_bus_mute(master) and not Settings.sound_on(), "sound button mutes and remembers")
	snd.button_pressed = false
	check(not AudioServer.is_bus_mute(master) and Settings.sound_on(), "sound button unmutes")
	Settings.set_sound_on(was_on)


func _process(_dt: float) -> bool:
	_frame += 1
	match _frame:
		5:
			check(current_scene != null and current_scene.name == "MainMenu", "the game starts in the menu")
			_check_menu()
			check(not _press("Гра:"), "no «Гра: карта map_03» in the menu")
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
			check(_press("Грати"), "menu has «Грати»")
		60:
			check(current_scene.name == "Main", "«Грати» opens the game (level 1)")
			check(current_scene.has_node("Map03") and current_scene.has_node("GameHud") and Wallet.of(current_scene) != null, "the game has map_03, the crystal counter and a wallet")
			check(_press("Меню"), "the game has «Меню»")
		80:
			check(current_scene.name == "MainMenu", "«Меню» from the game goes back")
			print("menu: %d failed" % _failed)
			quit(1 if _failed > 0 else 0)
			return true
	return false
