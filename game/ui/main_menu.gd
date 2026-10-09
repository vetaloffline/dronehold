class_name MainMenu
extends Control
## Start screen: pick what to run.

## [button, scene, turret for the test range or ""].
const SCENES := [
	["Гра: карта map_03", "res://game/main.tscn", ""],
	["Тест кулемета: клік — слизень", "res://game/sandbox/turret_sandbox.tscn", "Кулемет"],
	["Тест гранатомета: клік — слизень", "res://game/sandbox/turret_sandbox.tscn", "Гранатомет"],
]
const MENU := "res://game/ui/main_menu.tscn"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.05, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 24)
	add_child(box)
	var title := Label.new()
	title.text = "Dronehold"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	box.add_child(title)
	for s in SCENES:
		var b := Button.new()
		b.text = s[0]
		b.custom_minimum_size = Vector2(560, 90)
		b.add_theme_font_size_override("font_size", 32)
		b.pressed.connect(func() -> void:
			if s[2] != "":
				TurretSandbox.start_kind = s[2]
			get_tree().change_scene_to_file(s[1]))
		box.add_child(b)


## «Меню» button for other scenes (top right corner of a CanvasLayer).
static func back_button() -> Button:
	var b := Button.new()
	b.text = "Меню"
	b.custom_minimum_size = Vector2(140, 56)
	b.add_theme_font_size_override("font_size", 24)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: b.get_tree().change_scene_to_file(MENU))
	return b
