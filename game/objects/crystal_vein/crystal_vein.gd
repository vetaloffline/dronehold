@tool
class_name CrystalVein
extends MapObject
## Crystal vein: monolith with three floating shards, glows and shard shadows; one drill slot.
## Same drawing as crystal_vein_anim.html: shard shadows → vein → monolith glow (ADD) →
## per shard: glow (ADD) → shard. The vein shadow is a ground layer (z −1).
## Node origin = ground point; everything inside is in crystal_vein.png px minus the ground point.

## Cell of the drill slot relative to the vein cell (map_03_editor.html VEIN_SLOT: right-back corner).
const SLOT := Vector2i(6, -2)
## Radial white → transparent, shared by all glows.
static var _glow_tex: GradientTexture2D

@export var rig: CrystalVeinRig:
	set(v):
		if rig and rig.changed.is_connected(_place):
			rig.changed.disconnect(_place)
		rig = v
		if rig:
			rig.changed.connect(_place)
		_place()

var _t := 0.0

@onready var _shard_shadows := $ShardShadows as Node2D
@onready var _monolith_glow := $MonolithGlow as Node2D
@onready var _shards: Array[Sprite2D] = [$Shard1, $Shard2, $Shard3]
@onready var _glows: Array[Node2D] = [$ShardGlow1, $ShardGlow2, $ShardGlow3]


func get_footprint() -> Vector2i:
	return Vector2i(6, 6)


func get_map_shift() -> Vector2:
	return rig.map_shift if rig else Vector2.ZERO


func get_map_scale() -> float:
	return rig.map_scale if rig else 1.0


func get_path_cost() -> float:
	return 8.0


## Cell where this vein's drill stands.
func drill_slot_cell() -> Vector2i:
	return cell + SLOT


## Where the laser hits, in this node's local space.
func hit_point_local() -> Vector2:
	return rig.hit_point - rig.ground_point


## Point of vein px space in the parent's space, computed from `cell` (does not need the node
## to be placed yet).
func vein_px_to_parent(p: Vector2) -> Vector2:
	return ground_point_for(cell) + (p - rig.ground_point) * get_map_scale()


static func glow_texture() -> GradientTexture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 128
		_glow_tex.height = 128
	return _glow_tex


## Radial glow like canvas createRadialGradient(0 → r), alpha `a` in the centre.
static func draw_glow(ci: CanvasItem, at: Vector2, r: float, color: Color, a: float) -> void:
	if r <= 0.0 or a <= 0.0:
		return
	ci.draw_texture_rect(glow_texture(), Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(color, a))


func _ready() -> void:
	_t = randf() * 10.0
	_shard_shadows.draw.connect(_draw_shard_shadows)
	_monolith_glow.draw.connect(_draw_monolith_glow)
	for i in _glows.size():
		_glows[i].draw.connect(_draw_shard_glow.bind(i))
	_animate()


func _process(dt: float) -> void:
	editor_snap()
	_t += dt
	_animate()


func _shard_state(sr: CrystalShardRig) -> Dictionary:
	var per := sr.period_s
	var s := sin((_t / per + sr.phase) * TAU)
	return {
		"pos": Vector2(sr.center.x, sr.center.y - s * sr.bob_amp),
		"lift": s,
		"rot": deg_to_rad(sr.sway_deg) * sin((_t / (per * 1.7) + sr.phase) * TAU),
		"sx": 1.0 - sr.spin * (0.5 - 0.5 * cos((_t / (per * 1.3) + sr.phase) * TAU)),
	}


func _animate() -> void:
	if rig == null or not is_node_ready():
		return
	var g := rig.ground_point
	for i in _shards.size():
		var sp := _shards[i]
		if i >= rig.shards.size() or rig.shards[i] == null:
			sp.visible = false
			continue
		var sr := rig.shards[i]
		var st := _shard_state(sr)
		sp.visible = true
		if sp.texture != sr.texture:
			sp.texture = sr.texture
		sp.position = (st.pos as Vector2) - g
		sp.rotation = st.rot
		sp.scale = Vector2(sr.scale * float(st.sx), sr.scale)
		_glows[i].queue_redraw()
	_shard_shadows.queue_redraw()
	_monolith_glow.queue_redraw()


func _draw_shard_shadows() -> void:
	if rig == null:
		return
	var g := rig.ground_point
	for sr in rig.shards:
		if sr == null:
			continue
		var st := _shard_state(sr)
		var h: float = sr.height_for_shadow + float(st.lift) * sr.bob_amp
		var k := maxf(0.15, 1.0 - rig.shard_shadow_shrink * h / 900.0)
		var sc := sr.scale / 0.3
		var p: Vector2 = (st.pos as Vector2) + Vector2(rig.shard_shadow_dx * h, h) - g
		var rx := rig.shard_shadow_r * k * sc
		var ry := rig.shard_shadow_r * 0.35 * k * sc
		_shard_shadows.draw_set_transform(p, 0.0, Vector2(rx, ry))
		_shard_shadows.draw_circle(Vector2.ZERO, 1.0, Color(rig.shard_shadow_color, rig.shard_shadow_a * k))
	_shard_shadows.draw_set_transform(Vector2.ZERO)


func _draw_monolith_glow() -> void:
	if rig == null:
		return
	var a := rig.monolith_alpha * (0.75 + 0.25 * sin(_t * rig.monolith_pulse_hz * TAU))
	draw_glow(_monolith_glow, rig.monolith_center - rig.ground_point, rig.monolith_radius, rig.monolith_color, a)


func _draw_shard_glow(i: int) -> void:
	if rig == null or i >= rig.shards.size() or rig.shards[i] == null:
		return
	var sr := rig.shards[i]
	var st := _shard_state(sr)
	var a := rig.shard_glow_a * (1.0 - rig.shard_glow_pulse * 0.5 + rig.shard_glow_pulse * 0.5 * float(st.lift))
	draw_glow(_glows[i], (st.pos as Vector2) - rig.ground_point, rig.shard_glow_r * sr.scale / 0.3, rig.shard_glow_color, a)
