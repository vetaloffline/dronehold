@tool
class_name MenuDrone
extends Node2D
## A menu drone that loops over its route: the Marker2D children are the stops, in tree order.
## At every stop it lands, sits `sit` s, takes off and flies to the next one (last → first).
## Editor: drag the points; Ctrl+D on a point adds one after it; it flies in the editor too.
## Positions are background px (the parent «World» is scaled to cover the screen).

const DEFAULT_RIG := preload("res://game/objects/menu_drone/menu_drone_rig.tres")

@export var rig: MenuDroneRig = DEFAULT_RIG:
	set(v):
		if rig and rig.changed.is_connected(_on_rig_changed):
			rig.changed.disconnect(_on_rig_changed)
		rig = v
		if rig:
			rig.changed.connect(_on_rig_changed)
		_on_rig_changed()
## Flight speed, background px/s.
@export_range(10, 400, 5) var speed := 110.0
## Seconds sitting at each stop.
@export_range(0.0, 15.0, 0.1) var sit := 2.5
## Start offset 0..1: which stop it starts at and how long it has already sat there.
@export_range(0.0, 1.0, 0.01) var phase := 0.0:
	set(v): phase = v; restart()
## Route colour in the editor (dashed line + point numbers).
@export var route_color := Color(1.0, 0.82, 0.29)
## Draw the route in the running game too (debug).
@export var show_route_in_game := false

enum Mode { SIT, TAKEOFF, FLY, LAND }

var mode := Mode.SIT
var ground := Vector2.ZERO   ## the point on the ground under the drone
var height := 0.0
var face := 1.0
var _i := 0                  ## index of the stop it sits at / flies to
var _t := 0.0
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _vx := 0.0
var _time := 0.0
var _seed := 0.0

var _body: Node2D           ## at (ground.x, ground.y - height): tilt + mirror
var _sprite: Sprite2D
var _glows: Array[Sprite2D] = []


func _ready() -> void:
	_seed = float(get_index()) * 2.7
	if rig and not rig.changed.is_connected(_on_rig_changed):
		rig.changed.connect(_on_rig_changed)
	_build()
	restart()


## Stops of the route in tree order.
func stops() -> PackedVector2Array:
	var out := PackedVector2Array()
	for c in get_children():
		if c is Marker2D:
			out.append((c as Marker2D).position)
	return out


## Back to the start state (sitting at the stop picked by `phase`).
func restart() -> void:
	var s := stops()
	if s.is_empty():
		return
	_i = roundi(phase * s.size()) % s.size()
	ground = s[_i]
	mode = Mode.SIT
	_t = sit * phase
	height = 0.0
	_vx = 0.0


func _process(dt: float) -> void:
	if rig == null or _body == null:
		return
	_time += dt
	step(minf(dt, 0.05))
	_pose()
	queue_redraw()


## One tick of the loop: sit → take off → fly → land → sit at the next stop …
func step(dt: float) -> void:
	var s := stops()
	if s.size() < 2:
		mode = Mode.SIT
		height = 0.0
		if s.size() == 1:
			ground = s[0]
		return
	_vx = 0.0
	match mode:
		Mode.SIT:
			height = 0.0
			_t -= dt
			if _t <= 0.0:
				mode = Mode.TAKEOFF
				_t = 0.0
		Mode.TAKEOFF, Mode.LAND:
			_t += dt / maxf(rig.climb, 0.01)
			var e := smoothstep(0.0, 1.0, minf(_t, 1.0))
			height = rig.fly_h * (e if mode == Mode.TAKEOFF else 1.0 - e)
			if _t >= 1.0 and mode == Mode.TAKEOFF:
				_i = (_i + 1) % s.size()
				_from = ground
				_to = s[_i]
				if absf(_to.x - _from.x) > 4.0:
					face = signf(_to.x - _from.x)
				mode = Mode.FLY
				_t = 0.0
			elif _t >= 1.0:
				mode = Mode.SIT
				_t = sit
		Mode.FLY:
			var length := maxf(1.0, _from.distance_to(_to))
			_t += dt * speed / length
			# Speeds up, brakes before the stop.
			var p := _from.lerp(_to, smoothstep(0.0, 1.0, minf(_t, 1.0)))
			_vx = (p.x - ground.x) / maxf(dt, 0.0001)
			ground = p
			height = rig.fly_h
			if _t >= 1.0:
				mode = Mode.LAND
				_t = 0.0


func _air() -> float:
	return clampf(height / rig.fly_h, 0.0, 1.0) if rig.fly_h > 0.0 else 0.0


func _pose() -> void:
	var air := _air()
	var h := height + sin(_time * rig.bob_speed + _seed) * rig.bob_amp * air
	_body.position = ground - Vector2(0, h)
	_body.rotation = clampf(_vx * rig.tilt_per_speed, -rig.max_tilt, rig.max_tilt)
	_body.scale = Vector2(face, 1.0)
	var glow := lerpf(rig.glow_sit, rig.glow_fly, air) * (0.8 + 0.2 * sin(_time * rig.glow_pulse + _seed))
	for g in _glows:
		g.modulate = Color(rig.glow_color, glow)


func _draw() -> void:
	if rig == null:
		return
	# Shadow ellipse: tight and dark sitting, smaller and lighter up in the air.
	var air := _air()
	var s := 1.0 - rig.shadow_shrink * air
	var col := Color(0, 0, 0, lerpf(rig.shadow_alpha_ground, rig.shadow_alpha_air, air))
	draw_set_transform(ground + Vector2(-4.0 * air, 0), 0.0,
			Vector2(rig.width * rig.shadow_w * s, rig.width * rig.shadow_h * s))
	draw_circle(Vector2.ZERO, 1.0, col)
	draw_set_transform(Vector2.ZERO)
	if Engine.is_editor_hint() or show_route_in_game:
		_draw_route()


func _draw_route() -> void:
	var s := stops()
	for k in s.size():
		if s.size() > 1 and (k < s.size() - 1 or s.size() > 2):
			draw_dashed_line(s[k], s[(k + 1) % s.size()], route_color, 3.0, 10.0)
	var font := ThemeDB.fallback_font
	for k in s.size():
		draw_circle(s[k], 12.0, route_color)
		draw_string(font, s[k] + Vector2(-5, 6), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.07, 0.07, 0.07))


func _build() -> void:
	if _body:
		_body.queue_free()
	# Not owned by the scene: built at runtime (and in the editor), never saved into the .tscn.
	_body = Node2D.new()
	_body.name = "Body"
	add_child(_body, false, Node.INTERNAL_MODE_BACK)
	_sprite = Sprite2D.new()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_body.add_child(_sprite)
	_glows.clear()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for _n in 3:
		var g := Sprite2D.new()
		g.texture = _glow_texture()
		g.material = add
		_body.add_child(g)
		_glows.append(g)
	_on_rig_changed()


func _on_rig_changed() -> void:
	if _sprite == null or rig == null:
		return
	_sprite.texture = rig.texture
	if rig.texture == null:
		return
	var tex := rig.texture.get_size()
	var k := rig.width / tex.x
	var hh := tex.y * k
	# Pivot = bottom centre (the nozzles touch the ground when it sits).
	_sprite.scale = Vector2(k, k)
	_sprite.position = Vector2(0, -hh * 0.5)
	for n in _glows.size():
		var g := _glows[n]
		g.visible = n < rig.nozzles.size()
		if g.visible:
			g.position = Vector2(rig.nozzles[n].x * rig.width, rig.nozzles[n].y * hh)
			g.scale = Vector2.ONE * (rig.glow_radius * 2.0 / 32.0)


static var _glow_tex: GradientTexture2D

static func _glow_texture() -> GradientTexture2D:
	if _glow_tex == null:
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = gr
		_glow_tex.width = 32
		_glow_tex.height = 32
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
	return _glow_tex
