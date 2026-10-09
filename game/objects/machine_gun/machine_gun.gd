@tool
class_name MachineGun
extends Turret
## Machine gun (machine_gun_scene.html, mg*): 8 head views switched by angle, tracers with spread,
## casings, sparks where the bullet lands. A bullet damages its target when the tracer arrives.

@export var rig: MachineGunRig:
	set(v):
		rig = v
		_place()

# Constants of the tuner, in tuner canvas px (converted with rig.tuner_to_local()).
const CASING_GRAVITY := 1400.0
const SPARK_GRAVITY := 1100.0
const HIT_SPARK_SPEED := 380.0
const SPARK_WIDTH := 3.0

var _tracers := []
var _casings := []
var _sparks := []


func get_rig() -> TurretRig:
	return rig


func get_clear_radius() -> float:
	return 2.5


func fire(target: Vector2, tip: Vector2) -> void:
	var m2l := rig.map_to_local()
	var sp := rig.spread * m2l
	var to := target + Vector2((_rng.randf() - 0.5) * sp, (_rng.randf() - 0.5) * sp * rig.cam_k)
	var d := to - tip
	var l := maxf(d.length(), 1.0)
	_tracers.append({"p": tip, "u": d / l, "left": l, "id": _target_id})
	if rig.casings:
		var t2l := rig.tuner_to_local()
		var side := _ang + PI / 2.0
		var speed := (120.0 + _rng.randf() * 80.0) * t2l
		_casings.append({
			"g": Vector2.ZERO, "v": Vector2(cos(side) * speed, sin(side) * speed * rig.cam_k),
			"z": rig.head_height(), "vz": (200.0 + _rng.randf() * 120.0) * t2l,
			"life": 1.2, "age": 0.0, "rot": _rng.randf() * 6.0,
		})


func step_fx(dt: float) -> void:
	var t2l := rig.tuner_to_local()
	var move := rig.tracer_speed * rig.map_to_local() * dt
	var keep := []
	for b in _tracers:
		var d := minf(b.left, move)
		b.p += b.u * d
		b.left -= d
		if b.left > 0.0:
			keep.append(b)
			continue
		for j in 4:
			_sparks.append(make_spark(b.p, HIT_SPARK_SPEED * t2l, Color8(255, 210, 120), 0.25))
		var sim := swarm_sim()
		if sim and sim.alive(b.id):
			sim.damage(b.id, rig.damage)
	_tracers = keep
	var cas := []
	for c in _casings:
		c.age += dt
		if c.age > c.life:
			continue
		c.vz -= CASING_GRAVITY * t2l * dt
		c.z += c.vz * dt
		if c.z < 0.0:
			c.z = 0.0
			c.vz *= -0.35
			c.v *= 0.6
		c.g += c.v * dt
		c.rot += 14.0 * dt
		cas.append(c)
	_casings = cas
	_sparks = step_sparks(_sparks, dt, SPARK_GRAVITY * t2l)


## Ground layer (drawn before the children): casings.
func _draw() -> void:
	if rig == null:
		return
	var t2l := rig.tuner_to_local()
	for c in _casings:
		draw_set_transform(c.g - Vector2(0.0, c.z), c.rot)
		draw_rect(Rect2(Vector2(-5, -2) * t2l, Vector2(10, 4) * t2l), Color8(230, 180, 70, int(255 * (1.0 - c.age / c.life))))
	draw_set_transform(Vector2.ZERO)


func _draw_fx() -> void:
	super()
	if rig == null:
		return
	var m2l := rig.map_to_local()
	var w := rig.tracer_width * m2l
	var l := rig.tracer_len * m2l
	for b in _tracers:
		_fx.draw_line(b.p, b.p - b.u * l, Color8(255, 220, 120, 242), w)
	draw_sparks(_fx, _sparks, SPARK_WIDTH * rig.tuner_to_local())
