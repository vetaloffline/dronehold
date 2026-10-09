@tool
class_name Slime
extends Node2D
## One slime, exactly the tuner's model (slime_crawl.html stepSlime(): spring per frame, random
## pause per blink series). Drop it on a map to tune `rig` live: it crawls back and forth.
## The crowd in the game is drawn by Swarm (MultiMesh); both read the same SlimeRig.

const SHADER := preload("res://game/objects/slime/slime.gdshader")

@export var rig: SlimeRig = preload("res://game/objects/slime/slime_rig.tres"):
	set(v):
		rig = v
		_setup()
## Crawls this many cells, then turns around.
@export_range(0.0, 40.0, 0.5) var walk_cells := 8.0
## Speed multiplier of the crawl cycle (rate).
@export_range(0.1, 4.0, 0.05) var rate := 1.0
## Skin from the atlas; −1 = random.
@export_range(-1, 3, 1) var skin := -1:
	set(v):
		skin = v
		_setup()

var _body: Sprite2D
var _mat: ShaderMaterial
var _p := 0.0
var _sx := 1.0
var _sy := 1.0
var _vx := 0.0
var _vy := 0.0
var _prev_tx := NAN
var _dir := 1.0
var _walked := 0.0
var _bt := 0.0
var _b_wait := 2.2
var _skin_now := -1


func _ready() -> void:
	_setup()
	_bt = -randf() * (rig.blink_pause if rig else 2.0)


func _setup() -> void:
	if not is_inside_tree() or rig == null:
		return
	if _body == null:
		_body = Sprite2D.new()
		_body.name = "Body"
		_body.centered = false
		_body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_body.material = _mat
		add_child(_body)
	_body.texture = rig.texture
	if _skin_now < 0 or skin >= 0:
		_skin_now = rig.skin_of(randf()) if skin < 0 else mini(skin, rig.skin_count - 1)
	_body.region_enabled = true
	_body.region_rect = rig.frame_rect(_skin_now)
	_body.offset = -rig.pivot
	rig.apply_to_material(_mat)
	_b_wait = rig.blink_pause


func _process(dt: float) -> void:
	if rig == null or _body == null:
		return
	dt = minf(dt, 0.05)
	rig.apply_to_material(_mat)
	var w := rig.width_px()
	# Blink: series by blink_order, then pause + random.
	_bt += dt
	if _bt > rig.blink_series_len() + _b_wait:
		_bt = 0.0
		_b_wait = rig.blink_pause + randf() * rig.blink_rand
	_mat.set_shader_parameter("closure_override", Vector3(rig.lid_of(_bt, 0), rig.lid_of(_bt, 1), rig.lid_of(_bt, 2)))
	# Crawl.
	_p = fmod(_p + dt * rate / rig.period, 1.0)
	var f := rig.profile(_p)
	var tx := 1.0 + rig.stretch * f
	var ty := 1.0 - rig.squash * f
	if rig.jelly > 0.0:
		var k := 40.0 + 360.0 * rig.jelly
		var c := 2.0 * sqrt(k) * rig.damp
		_vx += (k * (tx - _sx) - c * _vx) * dt
		_sx += _vx * dt
		_vy += (k * (ty - _sy) - c * _vy) * dt
		_sy += _vy * dt
	else:
		_sx = tx
		_sy = ty
	var d_tx := 0.0 if is_nan(_prev_tx) else tx - _prev_tx
	_prev_tx = tx
	var adv := rig.inch * w * 0.5 * absf(d_tx) + rig.slide * MapGrid.CELL.x * rate * dt
	_body.position.x += _dir * adv
	_walked += adv
	if walk_cells > 0.0 and _walked >= walk_cells * MapGrid.CELL.x:
		_walked = 0.0
		_dir = -_dir
	var q := fposmod(_p - rig.lean_phase, 1.0)
	var skew := -deg_to_rad(rig.lean) * rig.profile(q) * _dir
	var k2 := rig.map_scale()
	_body.scale = Vector2(_sx * _dir * k2, _sy * k2)
	_body.skew = skew
	queue_redraw()


func _draw() -> void:
	if rig == null or _body == null:
		return
	var w := rig.width_px()
	var centre := Vector2(_body.position.x + rig.shadow_x * w * _dir, rig.shadow_y * w)
	var rx := rig.shadow_w * w * _sx * 0.5
	var ry := rig.shadow_h * w * 0.5
	var pts := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		pts.append(centre + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, Color(0.078, 0.031, 0.11, rig.shadow_alpha))
