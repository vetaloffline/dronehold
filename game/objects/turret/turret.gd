@tool
class_name Turret
extends MapObject
## Turret with a base and 8 head views — the common part of machine_gun_scene.html:
## aiming (turn speed, tolerance), view choice by angle, recoil, muzzle flash, head / base shadows,
## the editor demo target and swarm targeting. Subclasses add the projectile (fire / fx).
##
## Local space of the node = base sprite px; the origin is the ground point under the ring.
## Children (see the .tscn): BaseShadow, HeadShadow0/1, Base, Head0/1, Fx (additive), FxTop.

## In the editor, shoot at a target moving on the tuner's ellipse.
@export var editor_demo_target := true

const RESCAN_S := 0.2

var _ang := deg_to_rad(90.0)
var _cd := 0.0
var _rec := 0.0
var _flash := 0.0
var _time := 0.0
var _target_id := -1
## Snap mode: the view whose barrel cone holds the target (−1 = none / editor demo).
var _aim_view := -1
var _rescan := 0.0
var _swarm: Node
var _rng := RandomNumberGenerator.new()
static var _glow_tex: Texture2D

@onready var _base_shadow := get_node_or_null("BaseShadow") as Sprite2D
@onready var _base := get_node_or_null("Base") as Sprite2D
@onready var _heads: Array[Sprite2D] = [get_node_or_null("Head0") as Sprite2D, get_node_or_null("Head1") as Sprite2D]
@onready var _head_shadows: Array[Sprite2D] = [get_node_or_null("HeadShadow0") as Sprite2D, get_node_or_null("HeadShadow1") as Sprite2D]
@onready var _fx := get_node_or_null("Fx") as Node2D
@onready var _fx_top := get_node_or_null("FxTop") as Node2D


func get_rig() -> TurretRig:
	return null


## Name on the info card. Override.
func display_name() -> String:
	return name


func get_map_scale() -> float:
	var r := get_rig()
	return r.map_scale if r else 1.0


func get_footprint() -> Vector2i:
	return Vector2i(2, 2)


func get_path_cost() -> float:
	return 8.0


func _ready() -> void:
	_rng.seed = hash(name) ^ 7
	if _fx and not _fx.draw.is_connected(_draw_fx):
		_fx.draw.connect(_draw_fx)
	if _fx_top and not _fx_top.draw.is_connected(_draw_fx_top):
		_fx_top.draw.connect(_draw_fx_top)
	var r := get_rig()
	if ghost and r and not r.heads.is_empty() and r.housing.size() >= r.heads.size():
		update_sprites()  # a build-mode ghost does not run _process: put the sprites in place once


# ---------- geometry (tuner geo / pickViews / headPlace, in px спрайта)

## Screen direction of a ground angle (after the camera squash).
func scr_ang(a: float) -> float:
	var r := get_rig()
	return atan2(sin(a) * r.cam_k, cos(a))


func ring_local() -> Vector2:
	var r := get_rig()
	return r.ring - r.ground_in_base()


## [[view index, weight, screen rotation], …] for the current angle.
func pick_views(mode: int) -> Array:
	var r := get_rig()
	var n := r.view_count()
	var a := fposmod(rad_to_deg(_ang), 360.0)
	var near := r.nearest_view(a)
	# Neighbours around `a` for blending: i0 at or before it, i1 after.
	var i0 := near if wrapf(a - r.view_angle(near), -180.0, 180.0) >= 0.0 else posmod(near - 1, n)
	var i1 := (i0 + 1) % n
	var span := fposmod(r.view_angle(i1) - r.view_angle(i0), 360.0)
	var f := clampf(fposmod(a - r.view_angle(i0), 360.0) / maxf(span, 0.001), 0.0, 1.0)
	match mode:
		1:
			var rot := r.turn_strength * wrapf(scr_ang(_ang) - scr_ang(deg_to_rad(r.view_angle(near))), -PI, PI)
			return [[near, 1.0, rot]]
		2:
			return [[i0, 1.0 - f, 0.0], [i1, f, 0.0]]
	return [[near, 1.0, 0.0]]


func view_mode() -> int:
	return get_rig().view_mode


## Where the head sprite's housing point goes, px спрайта.
func head_at(view: int) -> Vector2:
	var r := get_rig()
	var hs := r.head_scale
	var sa := scr_ang(_ang)
	var back := Vector2(-cos(sa), -sin(sa)) * _rec
	var off := r.view_offsets[view] if view < r.view_offsets.size() else Vector2.ZERO
	return ring_local() + back + Vector2((r.head_x + off.x) * hs, -r.lift * hs + off.y * hs)


func muzzle_local() -> Vector2:
	var r := get_rig()
	var out := Vector2.ZERO
	for p in pick_views(view_mode()):
		var v: int = p[0]
		var at := head_at(v)
		var mz := (r.muzzle[v] - r.housing[v]) * r.head_scale
		out += (at + mz.rotated(p[2])) * float(p[1])
	return out


# ---------- targets

## Target in local px, or null. Sets `_target_id` in the game.
func find_target(dt: float) -> Variant:
	var r := get_rig()
	if Engine.is_editor_hint():
		if not editor_demo_target:
			return null
		var a := _time * r.demo_speed
		var m := r.demo_center + Vector2(cos(a) * r.demo_radius.x, sin(a) * r.demo_radius.y)
		return m * r.map_to_local()
	if _swarm == null or not is_instance_valid(_swarm):
		_swarm = get_tree().get_first_node_in_group("swarm")
		if _swarm == null:
			return null
	var sim: SwarmSim = _swarm.get("sim")
	if sim == null:
		return null
	_rescan -= dt
	var keep := sim.alive(_target_id) and sim.position_of(_target_id).distance_to(position) <= r.range_px
	if keep and view_mode() == 0:
		keep = _aim_view >= 0 and in_barrel_cone((sim.position_of(_target_id) - position) * r.map_to_local(), _aim_view)
	if not keep:
		_target_id = -1
		_aim_view = -1
		if _rescan <= 0.0:
			_rescan = RESCAN_S
			_target_id = _cone_target(sim) if view_mode() == 0 else sim.nearest(position, r.range_px)
	if _target_id < 0:
		return null
	return (sim.position_of(_target_id) - position) * r.map_to_local()


## Snap mode: views ordered from the one shown now outwards; the first view with a slime inside
## its barrel cone gives the target. Bullets then leave along the drawn barrel (≤ barrel_cone off).
func _cone_target(sim: SwarmSim) -> int:
	var r := get_rig()
	var now: int = pick_views(0)[0][0]
	var n := r.view_count()
	for k in n:
		# 0, +1, −1, +2, −2 … : the view shown now first, then its neighbours.
		var step := (k + 1) / 2 * (1 if k % 2 == 1 else -1)
		var v := posmod(now + step, n)
		# Cone on the ground around the view's azimuth, from the turret's ground point.
		var az := deg_to_rad(r.view_angle(v))
		var id := sim.nearest_in_cone(position, r.range_px, Vector2(cos(az), sin(az)), cos(deg_to_rad(r.cone_deg(v))), r.cam_k)
		if id >= 0:
			_aim_view = v
			return id
	return -1


## Drawn barrel direction of view `v` on screen: housing → muzzle of its picture.
func barrel_dir(v: int) -> Vector2:
	var r := get_rig()
	return (r.muzzle[v] - r.housing[v]).normalized()


## Muzzle of view `v`, local px.
func tip_of(v: int) -> Vector2:
	var r := get_rig()
	return head_at(v) + (r.muzzle[v] - r.housing[v]) * r.head_scale


## Target (local px, from the ground point) inside the barrel cone of view `v` (−1 = shown now):
## its ground azimuth is within cone_deg(v) of the view's azimuth.
func in_barrel_cone(target: Vector2, v := -1) -> bool:
	var r := get_rig()
	if v < 0:
		v = pick_views(0)[0][0]
	if target.length() < 0.001:
		return false
	var az := rad_to_deg(atan2(target.y / r.cam_k, target.x))
	return absf(wrapf(az - r.view_angle(v), -180.0, 180.0)) <= r.cone_deg(v)


func swarm_sim() -> SwarmSim:
	if Engine.is_editor_hint() or _swarm == null or not is_instance_valid(_swarm):
		return null
	return _swarm.get("sim")


## Local px → map px.
func to_map(local: Vector2) -> Vector2:
	return position + local * get_rig().map_scale


# ---------- loop

func _process(dt: float) -> void:
	editor_snap()
	var r := get_rig()
	if r == null or r.heads.is_empty() or r.housing.size() < r.heads.size() or r.muzzle.size() < r.heads.size():
		return
	dt = minf(dt, 0.1)
	_time += dt
	var target: Variant = find_target(dt)
	var aligned := false
	if target != null:
		aligned = aim(target, dt)
	_rec = maxf(0.0, _rec - r.recoil * dt / r.recoil_return)
	_flash = maxf(0.0, _flash - dt)
	_cd -= dt
	before_fire(dt)
	if aligned and _cd <= 0.0:
		_cd = 1.0 / r.fire_rate
		_rec = r.recoil
		_flash = flash_time()
		fire(target, muzzle_local())
	step_fx(dt)
	update_sprites()
	queue_redraw()
	if _fx:
		_fx.queue_redraw()
	if _fx_top:
		_fx_top.queue_redraw()


## Turn towards the target; true when it may fire.
func aim(target: Vector2, dt: float) -> bool:
	var r := get_rig()
	var want := atan2(target.y / r.cam_k, target.x)
	# Snap: turn the head to the view whose barrel cone holds the target, not to the target itself
	# (else it may stop on the neighbour view and lose the target).
	if view_mode() == 0 and _aim_view >= 0:
		want = deg_to_rad(r.view_angle(_aim_view))
	var diff := wrapf(want - _ang, -PI, PI)
	var m := deg_to_rad(r.rot_speed) * dt
	_ang = wrapf(_ang + clampf(diff, -m, m), -PI, PI)
	var dist := target.length() * r.map_scale
	if dist >= r.range_px:
		return false
	if view_mode() == 0:
		# Snap: the head shows one of N pictures; fire only along the drawn barrel.
		var shown: int = pick_views(0)[0][0]
		return (_aim_view < 0 or shown == _aim_view) and in_barrel_cone(target)
	return absf(wrapf(want - _ang, -PI, PI)) < deg_to_rad(r.tolerance)


func flash_time() -> float:
	return 0.05


## Hooks for subclasses.
func before_fire(_dt: float) -> void:
	pass


func fire(_target: Vector2, _tip: Vector2) -> void:
	pass


func step_fx(_dt: float) -> void:
	pass


# ---------- drawing

func update_sprites() -> void:
	var r := get_rig()
	var g := r.ground_in_base()
	for s in [_base, _base_shadow]:
		if s:
			(s as Sprite2D).centered = false
			(s as Sprite2D).position = -g
	if _base:
		_base.texture = r.base
	if _base_shadow:
		_base_shadow.texture = r.base_shadow
		_base_shadow.modulate.a = minf(1.0, r.base_shadow_alpha)
	var views := pick_views(view_mode()) if show_views() else []
	var hh := r.head_height()
	var sh_off := Vector2(r.sun.x * hh, r.sun.y * hh + hh * r.head_shadow_drop)
	for k in 2:
		var head := _heads[k]
		var shadow := _head_shadows[k]
		if head == null:
			continue
		if k >= views.size():
			head.visible = false
			if shadow:
				shadow.visible = false
			continue
		var v: int = views[k][0]
		var w: float = views[k][1]
		var rot: float = views[k][2]
		for s in [head, shadow]:
			if s == null:
				continue
			var sp := s as Sprite2D
			sp.visible = true
			sp.centered = false
			sp.texture = r.heads[v]
			sp.offset = -r.housing[v]
			sp.scale = Vector2(r.head_scale, r.head_scale)
			sp.rotation = rot
		head.position = head_at(v)
		head.modulate = Color(1, 1, 1, w)
		if shadow:
			shadow.position = head.position + sh_off
			shadow.modulate = Color(0, 0, 0, r.head_shadow_alpha * w)


## False when a subclass draws its own head (launcher tilt mode).
func show_views() -> bool:
	return true


## Additive layer: flash (subclasses call super and add their fx).
func _draw_fx() -> void:
	var r := get_rig()
	if r == null or _flash <= 0.0:
		return
	var tip := muzzle_local()
	var f := r.flash * (0.7 + 0.6 * _rng.randf())
	glow(_fx, tip, f, Color8(255, 190, 90), 0.9)
	glow(_fx, tip, f * 0.4, Color8(255, 250, 220), 1.0)


## Normal-blend layer above everything (shells).
func _draw_fx_top() -> void:
	pass


static func glow_texture() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_glow_tex = t
	return _glow_tex


## Radial glow like the tuner's glow(): colour `c` with alpha `a` at the centre, 0 at radius.
static func glow(ci: CanvasItem, at: Vector2, radius: float, c: Color, a: float) -> void:
	if radius <= 0.0 or a <= 0.0:
		return
	c.a = a
	ci.draw_texture_rect(glow_texture(), Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, c)


## Filled ellipse (ground-squashed circles).
static func ellipse(ci: CanvasItem, at: Vector2, rx: float, ry: float, c: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	ci.draw_set_transform(at, 0.0, Vector2(1.0, ry / rx))
	ci.draw_circle(Vector2.ZERO, rx, c)
	ci.draw_set_transform(Vector2.ZERO)


static func ellipse_ring(ci: CanvasItem, at: Vector2, rx: float, ry: float, c: Color, width: float) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	var pts := PackedVector2Array()
	for i in 41:
		var t := TAU * i / 40.0
		pts.append(at + Vector2(cos(t) * rx, sin(t) * ry))
	ci.draw_polyline(pts, c, width, true)


## Spark like the tuner's spark(): random upward fan. Speeds in local px.
func make_spark(at: Vector2, speed: float, c: Color, life: float) -> Dictionary:
	var a := -PI / 2.0 + (_rng.randf() - 0.5) * 2.6
	var v := speed * (0.3 + _rng.randf() * 0.7)
	return {"p": at, "v": Vector2(cos(a) * v, sin(a) * v * 0.8), "age": 0.0, "life": life * (0.5 + _rng.randf()), "c": c}


## Steps sparks in place (gravity in local px/s²); returns the survivors.
static func step_sparks(sparks: Array, dt: float, gravity: float) -> Array:
	var out := []
	for s in sparks:
		s.age += dt
		if s.age > s.life:
			continue
		s.v.y += gravity * dt
		s.p += s.v * dt
		out.append(s)
	return out


static func draw_sparks(ci: CanvasItem, sparks: Array, width: float) -> void:
	for s in sparks:
		var c: Color = s.c
		c.a = 1.0 - s.age / s.life
		ci.draw_line(s.p, s.p - s.v * 0.02, c, width)
