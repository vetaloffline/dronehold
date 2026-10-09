@tool
class_name Drill
extends MapObject
## Laser drill. Cycle (drill_anim.html): lower → charge → fire → cool → raise → wait.
## Standalone it fires along the barrel at the ground (rig.pose_fire, rig.laser). In the slot of a
## CrystalVein (its cell = vein.drill_slot_cell()) it sits where the vein says, at the vein's scale
## × drill_scale, aims the head at the vein's hit point and uses vein.rig.drill
## (crystal_vein_drill_scene.html).
## Node origin = ground point; inside, everything is drill_body.png px minus the ground point.
## Draw order: body shadow, arm shadow (ground, z −1) → body → hot spot (standalone) → arm 3, 2, 1
## → beam, lens glow, sparks (ADD; z +1 in a vein slot so the vein does not cover them).

@export var rig: DrillRig:
	set(v):
		if rig and rig.changed.is_connected(_place):
			rig.changed.disconnect(_place)
		rig = v
		if rig:
			rig.changed.connect(_place)
		_place()

## Vein whose slot this drill stands in (null = standalone).
var vein: CrystalVein = null
var _vein_key := Vector2.INF
var _t := 0.0
## Per spark: x, y, vx, vy, age, life (drill px).
var _sparks := PackedFloat32Array()
## Frame state shared with the draw callbacks (drill body px).
var _lens := Vector2.ZERO
var _hit := Vector2.ZERO
var _charge := 0.0
var _beam_on := 0.0
var _flick := 1.0
## Vein px → drill px (sizes of sparks / hot spot in a vein slot are in vein px).
var _u := 1.0

@onready var _body := $Body as Sprite2D
@onready var _hot := $HotSpot as Node2D
@onready var _arms := $Arms as Node2D
@onready var _shoulder := $Arms/Shoulder as Node2D
@onready var _elbow := $Arms/Shoulder/Elbow as Node2D
@onready var _wrist := $Arms/Shoulder/Elbow/Wrist as Node2D
@onready var _arm_sprites: Array[Sprite2D] = [$Arms/Shoulder/Arm1, $Arms/Shoulder/Elbow/Arm2, $Arms/Shoulder/Elbow/Wrist/Arm3]
@onready var _arm_shadow := $ArmShadow as CanvasItem
@onready var _shadow_segs: Array[Sprite2D] = [$ArmShadow/Seg1, $ArmShadow/Seg2, $ArmShadow/Seg3]
@onready var _fx := $Fx as Node2D


func get_footprint() -> Vector2i:
	return Vector2i(2, 2)


func get_map_shift() -> Vector2:
	return rig.map_shift if rig else Vector2.ZERO


func get_map_scale() -> float:
	if vein and vein.rig:
		return vein.get_map_scale() * vein.rig.drill_scale
	return rig.map_scale if rig else 1.0


func get_clear_radius() -> float:
	return 4.0


func get_path_cost() -> float:
	return 8.0


## The drill parameters in effect: the vein's copy in a slot, else the own rig.
func active_rig() -> DrillRig:
	if vein and vein.rig and vein.rig.drill:
		return vein.rig.drill
	return rig


func find_vein(c: Vector2i) -> CrystalVein:
	var p := get_parent()
	if p == null:
		return null
	for n in p.get_children():
		if n is CrystalVein and n != self and (n as CrystalVein).rig and (n as CrystalVein).drill_slot_cell() == c:
			return n
	return null


func _slot_point(v: CrystalVein) -> Vector2:
	return v.vein_px_to_parent(v.rig.drill_offset + rig.ground_point * v.rig.drill_scale)


func ground_point_for(c: Vector2i) -> Vector2:
	var v: CrystalVein = find_vein(c) if rig else null
	if v:
		return _slot_point(v)
	return super(c)


## Dragging near a vein's slot snaps into it; elsewhere — the plain grid.
func cell_for_point(p: Vector2) -> Vector2i:
	var par := get_parent()
	if par and rig:
		for n in par.get_children():
			if n is CrystalVein and (n as CrystalVein).rig:
				var v := n as CrystalVein
				if p.distance_to(_slot_point(v)) < MapGrid.CELL.y * 1.5:
					return v.drill_slot_cell()
	return super(p)


func _place() -> void:
	if not is_inside_tree():
		return
	vein = find_vein(cell) if rig else null
	_vein_key = vein.ground_point_for(vein.cell) if vein else Vector2.INF
	super()
	_apply_geometry()


func _ready() -> void:
	_hot.draw.connect(_draw_hot)
	_fx.draw.connect(_draw_fx)
	if rig:
		_t = randf() * rig.cycle_len()
	_apply_geometry()


func _apply_geometry() -> void:
	if rig == null or not is_node_ready():
		return
	var g := rig.ground_point
	_body.offset = -g
	($BodyShadow as Sprite2D).offset = -g
	_shoulder.position = rig.shoulder_on_body - g
	_elbow.position = rig.seg1_end - rig.seg1_pivot
	_wrist.position = rig.seg2_end - rig.seg2_pivot
	var pivots: Array[Vector2] = [rig.seg1_pivot, rig.seg2_pivot, rig.seg3_pivot]
	for i in 3:
		_arm_sprites[i].offset = -pivots[i]
		_shadow_segs[i].offset = -pivots[i]


func _process(dt: float) -> void:
	editor_snap()
	if rig == null or not is_node_ready():
		return
	# The vein moved / appeared / went away → re-place.
	var v := find_vein(cell)
	var key := v.ground_point_for(v.cell) if v else Vector2.INF
	if v != vein or key != _vein_key:
		_place()
	_t += dt
	_animate(minf(dt, 0.05))


## Joints of the arm in body px for joint angles a1, a2, a3 (radians, a2/a3 relative).
func _kin(r: DrillRig, a1: float, a2: float, a3: float) -> Dictionary:
	var s := r.shoulder_on_body
	var elbow := s + (r.seg1_end - r.seg1_pivot).rotated(a1)
	var wrist := elbow + (r.seg2_end - r.seg2_pivot).rotated(a1 + a2)
	var tip := wrist + (r.seg3_lens - r.seg3_pivot).rotated(a1 + a2 + a3)
	return {"s": s, "elbow": elbow, "wrist": wrist, "tip": tip, "A1": a1, "A2": a1 + a2, "A3": a1 + a2 + a3}


## Relative head angle that points the barrel at `hit` (crystal_vein_drill_scene.html aimHead()).
func _aim_head(r: DrillRig, a1: float, a2: float, hit: Vector2) -> float:
	var k := _kin(r, a1, a2, 0.0)
	var wrist: Vector2 = k.wrist
	var want := (hit - wrist).angle()
	var head_base := (r.seg3_lens - r.seg3_pivot).angle()
	return want - head_base - (a1 + a2)


## Affine map of an arm segment onto its shadow (drill_anim.html segShadowMatrix()).
static func _seg_shadow(pj: Vector2, qj: Vector2, ps: Vector2, qs: Vector2, k: float) -> Transform2D:
	var u0 := qj - pj
	var v0 := qs - ps
	var lu := u0.length()
	var lv := v0.length()
	if lu < 0.001 or lv < 0.001:
		return Transform2D(Vector2.ZERO, Vector2.ZERO, ps)
	var u := u0 / lu
	var v := v0 / lv
	var n := Vector2(-u.y, u.x)
	var m := Vector2(-v.y, v.x)
	var s := lv / lu
	var a := s * v.x * u.x + k * m.x * n.x
	var b := s * v.x * u.y + k * m.x * n.y
	var c := s * v.y * u.x + k * m.y * n.x
	var d := s * v.y * u.y + k * m.y * n.y
	return Transform2D(Vector2(a, c), Vector2(b, d), Vector2(ps.x - (a * pj.x + b * pj.y), ps.y - (c * pj.x + d * pj.y)))


static func _ease(x: float) -> float:
	return 4.0 * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 2.0) / 2.0


## Phase index (0 lower, 1 charge, 2 fire, 3 cool, 4 raise, 5 wait), share 0..1, elapsed s.
static func phase_at(r: DrillRig, t: float) -> Array:
	var d := [r.t_move, r.t_charge, r.t_fire, r.t_cool, r.t_move, r.t_wait]
	var k := fmod(t, r.cycle_len())
	for i in d.size():
		var dur: float = d[i]
		if k < dur:
			return [i, k / dur if dur > 0.0 else 1.0, k]
		k -= dur
	return [5, 1.0, 0.0]


func _animate(dt: float) -> void:
	var r := active_rig()
	var in_slot := vein != null and vein.rig != null
	var g := rig.ground_point
	var ph := phase_at(r, _t)
	var phase_i: int = ph[0]
	var pk: float = ph[1]
	var el: float = ph[2]

	if in_slot:
		_hit = (vein.rig.hit_point - vein.rig.drill_offset) / vein.rig.drill_scale
		_u = 1.0 / vein.rig.drill_scale
	else:
		_u = 1.0
	var fire_head := deg_to_rad(r.fire_head)
	if in_slot and vein.rig.auto_aim:
		fire_head += _aim_head(r, deg_to_rad(r.fire_shoulder), deg_to_rad(r.fire_elbow), _hit)
	var up := [deg_to_rad(r.up_shoulder), deg_to_rad(r.up_elbow), deg_to_rad(r.up_head)]
	var fr := [deg_to_rad(r.fire_shoulder), deg_to_rad(r.fire_elbow), fire_head]
	var m := 0.0
	if phase_i == 0:
		m = _ease(pk)
	elif phase_i == 4:
		m = 1.0 - _ease(pk)
	elif phase_i >= 1 and phase_i <= 3:
		m = 1.0
	var a := [lerpf(up[0], fr[0], m), lerpf(up[1], fr[1], m), lerpf(up[2], fr[2], m)]
	_charge = 0.0
	_beam_on = 0.0
	if phase_i == 1:
		_charge = pk
	elif phase_i == 2:
		_charge = 1.0
		_beam_on = minf(1.0, el / r.start_s) if r.start_s > 0.0 else 1.0
	elif phase_i == 3:
		_charge = 1.0 - pk
	var j := Vector2.ZERO
	if phase_i == 2:
		a[2] += deg_to_rad(sin(_t * 80.0) * 0.6 * r.recoil)
		j = Vector2(sin(_t * 110.0) * 1.2 * r.recoil, cos(_t * 130.0) * 0.8 * r.recoil)
	var R := _kin(r, a[0], a[1], a[2])
	var wrist: Vector2 = R.wrist
	_lens = (R.tip as Vector2) + r.tip_offset.rotated(R.A3) + j
	if not in_slot:
		var barrel := (_lens - (wrist + j)).angle() + deg_to_rad(r.aim_deg)
		var dir := Vector2(cos(barrel), sin(barrel))
		var L := r.max_len
		if dir.y > 0.01:
			L = minf(L, (r.ground_y - _lens.y) / dir.y)
		_hit = _lens + dir * maxf(0.0, L)
	_flick = 1.0 + r.flicker_a * (sin(_t * r.flicker_speed * 6.3) * 0.6 + (randf() - 0.5) * 0.8)

	# Arms (jitter on the arm, 0.3 of it on the body).
	_body.position = j * 0.3
	_arms.position = j
	_shoulder.rotation = a[0]
	_elbow.rotation = a[1]
	_wrist.rotation = a[2]

	# Arm shadow: joints dropped onto the ground row interpolated by arm length.
	var Rf := _kin(r, fr[0], fr[1], fr[2])
	var l1 := (r.seg1_end - r.seg1_pivot).length()
	var l2 := (r.seg2_end - r.seg2_pivot).length()
	var l3 := (r.seg3_lens - r.seg3_pivot).length()
	var frac := [0.0, l1 / (l1 + l2 + l3), (l1 + l2) / (l1 + l2 + l3), 1.0]
	var J: Array[Vector2] = [R.s, R.elbow, R.wrist, R.tip]
	var SP: Array[Vector2] = []
	var tip_f: Vector2 = Rf.tip
	for i in 4:
		var gy: float = r.shoulder_ground.y + frac[i] * (tip_f.y - r.shoulder_ground.y)
		var h := gy - J[i].y
		SP.append(Vector2(J[i].x + r.shadow_tx * h, gy + r.shadow_ty * h))
	var at: Array[Vector2] = [R.s, R.elbow, R.wrist]
	var ang := [R.A1, R.A2, R.A3]
	var to_local := Transform2D(0.0, -g)
	for i in 3:
		var M := _seg_shadow(J[i], J[i + 1], SP[i], SP[i + 1], r.shadow_k)
		_shadow_segs[i].transform = to_local * M * Transform2D(float(ang[i]), at[i])
	_arm_shadow.self_modulate = Color(1, 1, 1, r.shadow_opacity)
	for s in _shadow_segs:
		var mat := s.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("color", r.shadow_color)

	# Sparks (drill px; in a vein slot their numbers are vein px → × _u).
	if _beam_on > 0.5:
		var n := int(round(r.spark_rate * _beam_on))
		for i in n:
			var sa := deg_to_rad(-90.0 + r.spark_dir + (randf() - 0.5) * r.spark_spread)
			var sp := r.spark_speed * (0.35 + randf() * 0.65) * _u
			_sparks.append_array(PackedFloat32Array([_hit.x, _hit.y, cos(sa) * sp, sin(sa) * sp, 0.0, r.spark_life * (0.5 + randf())]))
	var k := 0
	var alive := PackedFloat32Array()
	while k < _sparks.size():
		var age := _sparks[k + 4] + dt
		if age <= _sparks[k + 5]:
			var vy := _sparks[k + 3] + r.spark_gravity * _u * dt
			alive.append_array(PackedFloat32Array([_sparks[k] + _sparks[k + 2] * dt, _sparks[k + 1] + vy * dt, _sparks[k + 2], vy, age, _sparks[k + 5]]))
		k += 6
	_sparks = alive

	_fx.z_index = 1 if in_slot else 0
	_hot.queue_redraw()
	_fx.queue_redraw()


func _draw_hot() -> void:
	if rig == null or (vein and vein.rig) or _beam_on <= 0.0:
		return
	var r := active_rig()
	var pulse := 1.0 + r.hot_pulse * sin(_t * 20.0)
	var h := _hit - rig.ground_point
	CrystalVein.draw_glow(_hot, h, r.hot_r * pulse * _beam_on, r.color_hot, r.hot_a * _beam_on)
	CrystalVein.draw_glow(_hot, h, r.hot_r * 0.35 * pulse * _beam_on, r.color_core, r.hot_a * _beam_on)


func _draw_fx() -> void:
	if rig == null:
		return
	var r := active_rig()
	var g := rig.ground_point
	var T := _lens - g
	var H := _hit - g
	if _beam_on > 0.0:
		var pulse := 1.0 + r.hot_pulse * sin(_t * 20.0)
		if vein and vein.rig:
			# In the vein scene the hot spot and the crystal heat are drawn on top.
			CrystalVein.draw_glow(_fx, H, r.hot_r * 3.0 * pulse * _beam_on * _u, r.color_hot, vein.rig.crystal_heat * 0.5 * _beam_on)
			CrystalVein.draw_glow(_fx, H, r.hot_r * pulse * _beam_on * _u, r.color_hot, r.hot_a * _beam_on)
			CrystalVein.draw_glow(_fx, H, r.hot_r * 0.35 * pulse * _beam_on * _u, r.color_core, r.hot_a * _beam_on)
		var hb := T.lerp(H, _beam_on)
		var layers := [[r.glow_w, r.glow_a * 0.45, r.color_beam], [r.glow_w * 0.45, r.glow_a, r.color_beam], [r.core_w, 1.0, r.color_core]]
		for L in layers:
			_fx.draw_line(T, hb, Color(L[2] as Color, float(L[1])), maxf(0.5, float(L[0]) * _flick), true)
	if _charge > 0.0:
		CrystalVein.draw_glow(_fx, T, r.lens_glow_r * _charge * (_flick if _beam_on > 0.0 else 1.0), r.color_beam, r.lens_glow_a * _charge)
		CrystalVein.draw_glow(_fx, T, r.lens_glow_r * 0.3 * _charge, r.color_core, r.lens_glow_a * _charge)
	var k := 0
	while k < _sparks.size():
		var al := 1.0 - _sparks[k + 4] / _sparks[k + 5]
		var p := Vector2(_sparks[k], _sparks[k + 1]) - g
		var v := Vector2(_sparks[k + 2], _sparks[k + 3])
		_fx.draw_line(p, p - v * r.spark_tail, Color(r.color_spark, al), r.spark_size * (0.6 + al * 0.6) * _u, true)
		k += 6
