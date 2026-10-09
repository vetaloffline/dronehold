class_name DebugHud
extends CanvasLayer
## FPS and swarm numbers on screen + buttons to change the crowd size (for measuring on a phone).

@export var swarm: Swarm
## Buttons that change the crowd size (off in the turret test range: they would cull its slimes).
@export var show_count_buttons := true

var _label: Label


func _ready() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(16, 16)
	add_child(box)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	box.add_child(_label)
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(MainMenu.back_button())
	if not show_count_buttons:
		return
	for spec in [["÷10", 0.1], ["−10", -10], ["+10", 10], ["×10", 10.0]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(110, 72)
		b.add_theme_font_size_override("font_size", 28)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_change.bind(spec[1]))
		row.add_child(b)
	var row2 := HBoxContainer.new()
	box.add_child(row2)
	for n in [1000, 10000, 100000]:
		var b := Button.new()
		b.text = "Стрес %dк" % (n / 1000)
		b.custom_minimum_size = Vector2(170, 72)
		b.add_theme_font_size_override("font_size", 28)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_stress.bind(n))
		row2.add_child(b)


func _change(v) -> void:
	if swarm == null:
		return
	var n := swarm.target_count
	if v is float:
		n = int(round(n * v))
	else:
		n += int(v)
	swarm.target_count = clampi(n, 0, swarm.capacity)


func _stress(n: int) -> void:
	if swarm:
		swarm.fill_random(mini(n, swarm.capacity))


func _process(_dt: float) -> void:
	var t := "FPS %d" % Engine.get_frames_per_second()
	if swarm and swarm.sim:
		t += "   слизнів %d / %d   на екрані %d" % [swarm.sim.count, swarm.target_count, swarm.view.visible_count]
		t += "\nсимуляція %.2f мс   малювання %.2f мс   дійшли %d   вбито %d" % [
			swarm.sim_ms, swarm.view_ms, swarm.sim.reached_total, swarm.sim.killed_total]
	_label.text = t
