class_name MainMenu
extends Control
## Start screen. Background world (picture + flying drones) covers the screen like CSS «cover»;
## menu on the left, sound toggle bottom right. Buttons live in the scene (Menu/Buttons): each has
## metadata `scene` (what to open) and optionally `turret` (which turret the test range starts with).
## Add a button in the editor: duplicate one (Ctrl+D), change its text and metadata.

const MENU := "res://game/ui/main_menu.tscn"
const CLICK := preload("res://art/objects/ui/main_menu/ui_click.wav")
## Background picture size, px (menu_bg.webp).
const BG_SIZE := Vector2(1672, 941)
## Which part of the picture stays visible when the screen is narrower / wider: 0 = left, 1 = right.
const BG_ALIGN := Vector2(0.7, 0.5)
const MENU_LEFT := 70.0

@onready var _world: Node2D = $World
@onready var _menu: Control = $Menu
@onready var _sound: TextureButton = $Sound
@onready var _version: Label = $Version


func _ready() -> void:
	Settings.apply()
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	_version.text = "v" + (ver if ver != "" else "0.1")  # empty until set in Project Settings
	for b in $Menu/Buttons.get_children():
		if b is Button:
			_juice(b)
			b.pressed.connect(_open.bind(b))
	_sound.button_pressed = not Settings.sound_on()
	_sound.toggled.connect(func(muted: bool) -> void:
		Settings.set_sound_on(not muted)
		click())
	_juice(_sound)
	resized.connect(_layout)
	_layout()


func _open(b: Button) -> void:
	click()
	if b.has_meta("turret"):
		TurretSandbox.start_kind = b.get_meta("turret")
	get_tree().change_scene_to_file(b.get_meta("scene"))


## Background covers the whole screen; the menu keeps clear of a phone notch (safe area).
func _layout() -> void:
	var k := maxf(size.x / BG_SIZE.x, size.y / BG_SIZE.y)
	_world.scale = Vector2(k, k)
	_world.position = (size - BG_SIZE * k) * BG_ALIGN
	_menu.offset_left = MENU_LEFT + safe_left(size.x)
	_menu.offset_right = _menu.offset_left + _menu.get_combined_minimum_size().x


## Left inset of the display safe area (phone notch), in canvas px of a canvas `canvas_w` wide
## (0 on PC). The game HUD uses it too.
static func safe_left(canvas_w: float) -> float:
	var win := DisplayServer.window_get_size()
	if win.x <= 0:
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if safe.size.x <= 0 or screen.x != win.x:
		return 0.0  # windowed: no notch
	return safe.position.x * canvas_w / win.x


## Hover / press feel: slightly brighter on hover, shrinks a bit while held.
func _juice(c: BaseButton) -> void:
	c.button_down.connect(func() -> void:
		c.pivot_offset = c.size * 0.5
		c.create_tween().tween_property(c, "scale", Vector2.ONE * 0.96, 0.06))
	c.button_up.connect(func() -> void:
		c.create_tween().tween_property(c, "scale", Vector2.ONE, 0.08))
	if c is TextureButton:
		c.mouse_entered.connect(func() -> void: c.self_modulate = Color(1.15, 1.15, 1.15))
		c.mouse_exited.connect(func() -> void: c.self_modulate = Color.WHITE)


## UI click; the player lives on the tree root, so it is not cut when the scene changes.
func click() -> void:
	var p := AudioStreamPlayer.new()
	p.stream = CLICK
	get_tree().root.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## «Меню» button for other scenes (top right corner of a CanvasLayer).
static func back_button() -> Button:
	var b := Button.new()
	b.text = "Меню"
	b.custom_minimum_size = Vector2(140, 56)
	b.add_theme_font_size_override("font_size", 24)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: b.get_tree().change_scene_to_file(MENU))
	return b
