class_name TurretSandbox
extends Node2D
## Test range: one turret in the centre, slimes where you click.
##   left click — one slime · hold right — a stream · middle drag / wheel — camera
## Buttons: machine gun / grenade launcher, slimes stand / crawl, clear.
## Run it with «Run current scene» (the clapper ▶ at the top right of the editor).

const TURRETS := {
	"Кулемет": "res://game/objects/machine_gun/machine_gun.tscn",
	"Гранатомет": "res://game/objects/grenade_launcher/grenade_launcher.tscn",
}
## Turret the next opened range starts with (set by the menu).
static var start_kind := "Кулемет"

## Slimes per second while the right button is held.
@export_range(1.0, 60.0, 1.0) var stream_per_sec := 15.0

@onready var _map := $Map as GameMap
@onready var _swarm := $Map/Swarm as Swarm
@onready var _camera := $Camera as MapCamera

var _turret: MapObject
var _kind := "Кулемет"
var _stream := false
var _stream_acc := 0.0
var _info: Label
var _freeze_btn: Button


func _ready() -> void:
	# Clicked slimes must stay: no auto spawning, no culling down to target_count.
	_swarm.target_count = _swarm.capacity
	_swarm.spawn_per_sec = 0.0
	_camera.position = _map.grid.size_px() * 0.5
	_camera.zoom = Vector2.ONE * _camera._min_zoom()
	_build_ui()
	_put_turret(start_kind if TURRETS.has(start_kind) else _kind)


func _put_turret(kind: String) -> void:
	if _turret:
		_turret.queue_free()
	_kind = kind
	_turret = (load(TURRETS[kind]) as PackedScene).instantiate() as MapObject
	_turret.add_to_group("enemy_target", true)
	_turret.cell = Vector2i(_map.grid.cols / 2, _map.grid.rows / 2)
	_map.world().add_child(_turret)
	_refresh()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			_spawn_here()
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			_stream = e.pressed
			_stream_acc = 0.0


func _process(dt: float) -> void:
	if _stream:
		_stream_acc += dt * stream_per_sec
		while _stream_acc >= 1.0:
			_stream_acc -= 1.0
			_spawn_here(MapGrid.CELL.y * 0.6)
	_refresh()


func _spawn_here(jitter := 0.0) -> void:
	var p := get_global_mouse_position()
	if jitter > 0.0:
		p += Vector2(randf_range(-jitter, jitter), randf_range(-jitter, jitter) * 0.75)
	_swarm.spawn_at(p)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -420
	box.offset_top = 16
	box.offset_right = -16
	# Wider text must grow the panel to the left, not off the screen.
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	layer.add_child(box)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 22)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 6)
	box.add_child(_info)
	for kind in TURRETS:
		box.add_child(_button(kind, _put_turret.bind(kind)))
	_freeze_btn = _button("Слизні стоять", _toggle_freeze)
	box.add_child(_freeze_btn)
	box.add_child(_button("Очистити", func() -> void: _swarm.sim.clear()))


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_font_size_override("font_size", 24)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _toggle_freeze() -> void:
	_swarm.frozen = not _swarm.frozen
	_freeze_btn.text = "Слизні повзуть" if _swarm.frozen else "Слизні стоять"


func _refresh() -> void:
	if _info == null or _swarm.sim == null:
		return
	_info.text = "%s\nслизнів %d   вбито %d   дійшли %d\nліва — слизень, права (тримати) — потік\nколесо / середня — камера" % [
		_kind, _swarm.sim.count, _swarm.sim.killed_total, _swarm.sim.reached_total]
