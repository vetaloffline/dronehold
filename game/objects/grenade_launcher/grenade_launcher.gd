@tool
class_name GrenadeLauncher
extends Turret
## Grenade launcher (machine_gun_scene.html, mo*): turns by 8 views (approved) or tilts its tube
## left-right (tilt mode); lobs a shell on an arc to where the target was; the blast does full damage
## within `blast_core` and wounds (ring_near → ring_far) up to `blast`. Tilt mode: cradle + telescopic tube that slides in on each shot.

@export var rig: GrenadeLauncherRig:
	set(v):
		rig = v
		_place()

const SPARK_GRAVITY := 1100.0
const BLAST_SPARK_SPEED := 700.0
const BLAST_LIFE := 0.9
const SPARK_WIDTH := 3.0
const TUBE_OVERLAP := 12.0

var _tilt := 0.0
var _shot := 99.0
var _shells := []
var _blasts := []
var _sparks := []

@onready var _cradle := get_node_or_null("Cradle") as Sprite2D
@onready var _cradle_shadow := get_node_or_null("CradleShadow") as Sprite2D
@onready var _tube := get_node_or_null("Tube") as Node2D
@onready var _shaft := get_node_or_null("Tube/Shaft") as Sprite2D
@onready var _cap := get_node_or_null("Tube/Cap") as Sprite2D
@onready var _outer := get_node_or_null("Tube/Outer") as Sprite2D


func get_rig() -> TurretRig:
	return rig


func display_name() -> String:
	return "Гранатомет"


func get_clear_radius() -> float:
	return 3.0


func flash_time() -> float:
	return 0.14


func view_mode() -> int:
	return 0  # the launcher never rotates its sprite on screen (tuner pickViews: "snap")


func show_views() -> bool:
	return rig.launcher_mode == 0


func _tilt_mode() -> bool:
	return rig.launcher_mode == 1


func aim(target: Vector2, dt: float) -> bool:
	if not _tilt_mode():
		return super(target, dt)
	var m2l := rig.map_to_local()
	var want := deg_to_rad(rig.tilt_max) * clampf(target.x / (rig.tilt_range * m2l), -1.0, 1.0)
	var m := deg_to_rad(rig.rot_speed) * dt
	_tilt += clampf(want - _tilt, -m, m)
	var dist := target.length() * rig.map_scale
	return absf(want - _tilt) < deg_to_rad(rig.tolerance) and dist < rig.range_px


func before_fire(dt: float) -> void:
	_shot += dt


# ---------- tilt geometry (tuner tiltPlace / retraction)

func _retraction() -> float:
	var t := _shot
	if t < rig.tube_retract_t:
		return rig.tube_retract * t / rig.tube_retract_t
	return rig.tube_retract * maxf(0.0, 1.0 - (t - rig.tube_retract_t) / rig.tube_extend_t)


func _tilt_place() -> Dictionary:
	var hs := rig.head_scale
	var at := ring_local() + Vector2(rig.head_x * hs, -rig.lift * hs)
	var piv := at + Vector2(rig.tilt_pivot.x - rig.tilt_housing.x, rig.tilt_pivot.y - rig.tilt_housing.y + rig.tilt_pivot_y) * hs
	var outer_len := (rig.tilt_pivot.y - rig.tilt_outer_top) * rig.tube_outer_s
	var shaft_len := maxf(4.0, (rig.tilt_shaft_rows.y - rig.tilt_shaft_rows.x) + rig.tube_extend - _retraction())
	var cap_len := rig.tilt_cap_rows.y - rig.tilt_cap_rows.x
	var muzzle_d := (outer_len + shaft_len + cap_len - rig.tilt_muzzle_in_cap) * hs
	return {
		"at": at, "piv": piv, "outer": outer_len, "shaft": shaft_len, "cap": cap_len,
		"muzzle": piv + Vector2(sin(_tilt), -cos(_tilt)) * muzzle_d,
	}


func muzzle_local() -> Vector2:
	if _tilt_mode():
		return _tilt_place().muzzle
	return super()


# ---------- shells

func fire(target: Vector2, tip: Vector2) -> void:
	_shot = 0.0
	_shells.append({"g0": Vector2(tip.x, 0.0), "to": target, "z0": -tip.y, "t": 0.0})


func _shell_pos(s: Dictionary) -> Dictionary:
	var g: Vector2 = s.g0.lerp(s.to, s.t)
	var z: float = s.z0 * (1.0 - s.t) + 4.0 * rig.arc * rig.map_to_local() * s.t * (1.0 - s.t)
	return {"g": g, "z": z, "p": g - Vector2(0.0, z)}


func step_fx(dt: float) -> void:
	var t2l := rig.tuner_to_local()
	var keep := []
	for s in _shells:
		s.t += dt / rig.flight
		if s.t < 1.0:
			keep.append(s)
			continue
		_blasts.append({"p": s.to, "age": 0.0})
		# Sparks fly as far as the blast reaches (BLAST_SPARK_SPEED was tuned for a 45 px blast).
		var spark_k := clampf(rig.blast / 45.0, 1.0, 3.0)
		for j in 60:
			_sparks.append(make_spark(s.to, BLAST_SPARK_SPEED * spark_k * t2l, Color8(255, 170, 60) if _rng.randf() < 0.5 else Color8(255, 90, 40), 0.6))
		var sim := swarm_sim()
		if sim:
			sim.damage_blast(to_map(s.to), rig.blast_core, rig.damage, rig.blast, rig.ring_near, rig.ring_far)
	_shells = keep
	var bl := []
	for b in _blasts:
		b.age += dt
		if b.age <= BLAST_LIFE:
			bl.append(b)
	_blasts = bl
	_sparks = step_sparks(_sparks, dt, SPARK_GRAVITY * t2l)


func update_sprites() -> void:
	super()
	var tilt := _tilt_mode()
	for n in [_cradle, _cradle_shadow, _tube]:
		if n:
			(n as CanvasItem).visible = tilt
	if not tilt or _cradle == null or _tube == null:
		return
	var tp := _tilt_place()
	var hs := rig.head_scale
	var hh := rig.head_height()
	for s in [_cradle, _cradle_shadow]:
		if s == null:
			continue
		var sp := s as Sprite2D
		sp.texture = rig.tilt_cradle
		sp.centered = false
		sp.offset = -rig.tilt_housing
		sp.scale = Vector2(hs, hs)
		sp.position = tp.at
	if _cradle_shadow:
		_cradle_shadow.position = tp.at + Vector2(rig.sun.x * hh, rig.sun.y * hh + hh * rig.head_shadow_drop)
		_cradle_shadow.modulate = Color(0, 0, 0, rig.head_shadow_alpha)
	_tube.position = tp.piv
	_tube.rotation = _tilt
	_tube.scale = Vector2(hs, hs)
	var cx := rig.tilt_pivot.x
	var w := 418.0
	if rig.tilt_shaft:
		w = rig.tilt_shaft.get_width()
	var sr := rig.tilt_shaft_rows
	var sh_top: float = -tp.outer - tp.shaft
	_region(_shaft, rig.tilt_shaft, Rect2(0, sr.x, w, sr.y - sr.x), Vector2(-cx * rig.tube_inner_w, sh_top), Vector2(rig.tube_inner_w, (tp.shaft + TUBE_OVERLAP) / (sr.y - sr.x)))
	var cr := rig.tilt_cap_rows
	_region(_cap, rig.tilt_cap, Rect2(0, cr.x, w, cr.y - cr.x), Vector2(-cx * rig.tube_inner_w, sh_top - tp.cap), Vector2(rig.tube_inner_w, 1.0))
	var oh := rig.tilt_pivot.y - rig.tilt_outer_top + 3.0
	_region(_outer, rig.tilt_outer, Rect2(0, rig.tilt_outer_top, w, oh), Vector2(-cx, -tp.outer), Vector2(1.0, (tp.outer + 3.0) / oh))


static func _region(s: Sprite2D, tex: Texture2D, rect: Rect2, pos: Vector2, sc: Vector2) -> void:
	if s == null:
		return
	s.texture = tex
	s.centered = false
	s.region_enabled = true
	s.region_rect = rect
	s.offset = Vector2.ZERO
	s.position = pos
	s.scale = sc


## Ground layer (before the children): blast scorch, shell shadows.
func _draw() -> void:
	if rig == null:
		return
	var m2l := rig.map_to_local()
	var t2l := rig.tuner_to_local()
	var bl := rig.blast * m2l
	var core := maxf(rig.blast_core * m2l, bl * 0.2)
	for b in _blasts:
		var k: float = b.age / BLAST_LIFE
		# Scorch over the whole blast (darker in the killing core); the shock ring runs out to the edge.
		ellipse(self, b.p, bl * 0.65, bl * 0.65 * rig.cam_k, Color8(20, 10, 5, int(255 * 0.22 * (1.0 - k))))
		ellipse(self, b.p, core * 1.3, core * 1.3 * rig.cam_k, Color8(20, 10, 5, int(255 * 0.35 * (1.0 - k))))
		var ring := core + (bl - core) * sqrt(k)
		ellipse_ring(self, b.p, ring, ring * rig.cam_k, Color8(255, 200, 120, int(255 * (1.0 - k))), (10.0 * (1.0 - k) + 2.0) * t2l)
	var sh := rig.shell * m2l
	for s in _shells:
		var p := _shell_pos(s)
		var z: float = p.z
		ellipse(self, p.g + Vector2(rig.sun.x * z, rig.sun.y * z), sh * 1.2, sh * 0.6, Color8(3, 11, 26, 89))


func _draw_fx() -> void:
	super()
	if rig == null:
		return
	# Fireball as wide as the blast (the wound zone), white-hot centre the size of the killing core.
	var bl := rig.blast * rig.map_to_local()
	var core := maxf(rig.blast_core, rig.blast * 0.2) * rig.map_to_local()
	var up := Vector2(0.0, -20.0 * rig.tuner_to_local())
	for b in _blasts:
		var k: float = b.age / BLAST_LIFE
		if k < 0.4:
			var f := 1.0 - k / 0.4
			glow(_fx, b.p + up, bl * (0.75 + 0.25 * k / 0.4), Color8(255, 140, 50), 0.8 * f)
			glow(_fx, b.p + up, core * 1.8, Color8(255, 200, 110), 0.95 * f)
			glow(_fx, b.p + up, core * 0.9, Color8(255, 245, 210), f)
	draw_sparks(_fx, _sparks, SPARK_WIDTH * rig.tuner_to_local())


## Shells in the air (normal blend, above the world).
func _draw_fx_top() -> void:
	if rig == null:
		return
	var sh := rig.shell * rig.map_to_local()
	for s in _shells:
		var p: Vector2 = _shell_pos(s).p
		_fx_top.draw_circle(p, sh, Color("#2d2f33"))
		_fx_top.draw_circle(p - Vector2(sh, sh) * 0.3, sh * 0.35, Color("#f6c454"))
