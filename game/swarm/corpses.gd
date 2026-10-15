class_name Corpses
extends Node2D
## Death animations of one crowd (Swarm / LasherSwarm own one, runtime only).
## Corpses are data, not nodes: their own SwarmSim (position, face, seed; `rate` = own frame-time factor;
## `phase` = share of the life, no step()) drawn by SwarmView in deaths mode, in bands like the living crowd.
## Layer: first child of the map's Shadows (z −1, not Y-sorted) → every corpse lies under the living,
## their shadows and the buildings. Children, in draw order: blood splats and pools, corpse shadows,
## corpse bands, landed pieces; `FlyingPieces` (z_index 1, as shot effects) draws pieces and drops in the air.
## Pieces (DeathRig.pieces_texture, lasher limbs) fly out in every direction, hop 1…6 times, then roll far
## or slide and stop; they bleed (drops in the air, a splat per hit, a smear while sliding). Blood: a spray
## of drops from DeathRig.blood_from, each leaves a splat; a pool grows under the remains. Every death rolls
## its own force, pull, spray angle, drop count, pool size and frame time (DeathRig «Per death»); pieces fly
## × `bullet_scatter` after a bullet, × `blast_scatter` after a grenade; blood × `bullet_blood_scatter` after
## a bullet. Pieces, drops and splats are flat arrays;
## all of them melt with the remains (DeathRig.life()). Approved in the web preview 2026-10-14.

const SHADER := preload("res://game/swarm/death.gdshader")
## Splat textures: main ellipse radius SPLAT_PX in a SPLAT_SIZE image (blobs reach ~1.45 of it).
const SPLAT_PX := 20.0
const SPLAT_SIZE := Vector2i(64, 48)
const SPLATS := 4          # textures 0…3: splats; 4…5: pools
const DROP_PX := 4.0       # drop texture: fill radius in a 12 px image
const SPLAT_CAP := 1500
const DROP_CAP := 1500
const ROLL := 1
const REST := 2

static var _tex_cache := {}

var rig: DeathRig
var sim: SwarmSim
var view: SwarmView
## Pieces: ground point (x, gy), height z, speeds, angle, spin, kind, age, mirror, hops left, bounce,
## ground speed kept per hop, friction, ROLL / REST flags, roll direction, time to the next blood drop.
var _x := PackedFloat32Array()
var _gy := PackedFloat32Array()
var _z := PackedFloat32Array()
var _vx := PackedFloat32Array()
var _vgy := PackedFloat32Array()
var _vz := PackedFloat32Array()
var _ang := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _kind := PackedInt32Array()
var _age := PackedFloat32Array()
var _flip := PackedFloat32Array()
var _hops := PackedInt32Array()
var _bounce := PackedFloat32Array()
var _keep := PackedFloat32Array()
var _fric := PackedFloat32Array()
var _flags := PackedInt32Array()
var _rdir := PackedFloat32Array()
var _trail := PackedFloat32Array()
## Drops in the air: ground point, height, speeds, radius, age.
var _dx := PackedFloat32Array()
var _dgy := PackedFloat32Array()
var _dz := PackedFloat32Array()
var _dvx := PackedFloat32Array()
var _dvgy := PackedFloat32Array()
var _dvz := PackedFloat32Array()
var _dr := PackedFloat32Array()
var _dage := PackedFloat32Array()
## Splats on the ground: centre, radius, age (since the death), grow time, texture.
var _sx := PackedFloat32Array()
var _sy := PackedFloat32Array()
var _sr := PackedFloat32Array()
var _sage := PackedFloat32Array()
var _sgrow := PackedFloat32Array()
var _stex := PackedInt32Array()
## Living map_scale() at the last tick (pieces atlas is in living atlas px).
var _k := 1.0
var _splat_node: Node2D
var _shadows: Node2D
var _bodies: Node2D
var _ground: Node2D
var _air: Node2D
var _tex: Array[ImageTexture] = []
var _drop_tex: ImageTexture


## Adds itself as the first child of map.shadows() (that node is ready before the swarms, so it is not
## busy setting up children when Swarm._ready calls this).
func setup(map: GameMap, death_rig: DeathRig, shadow_alpha: float, prefix: String) -> void:
	rig = death_rig
	var layer := map.shadows()
	layer.add_child(self)
	layer.move_child(self, 0)
	_splat_node = _layer("Blood")
	_shadows = _layer("Shadows")
	_bodies = _layer("Bodies")
	_ground = _layer("Pieces")
	_air = _layer("FlyingPieces")
	_air.z_as_relative = false
	_air.z_index = 1
	_splat_node.draw.connect(_draw_splats)
	_ground.draw.connect(_draw_pieces.bind(_ground, false))
	_air.draw.connect(_draw_air)
	_make_textures()
	sim = SwarmSim.new()
	sim.setup(rig.capacity, map.grid.cols, map.grid.rows)
	view = SwarmView.new()
	view.setup_deaths(_bodies, _shadows, map.grid, rig, SHADER, shadow_alpha, prefix)


func _layer(n: String) -> Node2D:
	var node := Node2D.new()
	node.name = n
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(node)
	return node


func free_view() -> void:
	if view:
		view.free_nodes()


## Start a corpse per death of `deaths` (SwarmSim.deaths, DEATH_STRIDE floats each). `w` = living width, map px.
func add(deaths: PackedFloat32Array, w: float) -> void:
	var st := SwarmSim.DEATH_STRIDE
	for j in range(0, deaths.size() - st + 1, st):
		var x := deaths[j]
		var y := deaths[j + 1]
		var face := deaths[j + 2]
		var rate := randf_range(rig.rnd_frame_time.x, rig.rnd_frame_time.y)
		var id := sim.spawn(Vector2(x, y), rate, 1.0, deaths[j + 3], 0.0)
		if id < 0:
			continue
		sim.face[sim.slot_of_id[id]] = face
		var blast := deaths[j + 4] == SwarmSim.CAUSE_BLAST
		var force := randf_range(rig.rnd_force.x, rig.rnd_force.y)
		var sc := rig.blast_scatter if blast else rig.bullet_scatter
		# A grenade pulls everything away from the blast; a bullet to a random side.
		var pull_dir := deaths[j + 5] if blast else randf() * TAU
		var pull := randf_range(rig.rnd_pull.x, rig.rnd_pull.y)
		_spawn_pieces(x, y, w, force, sc, pull_dir, pull)
		_spawn_blood(x, y, face, w, force, 1.0 if blast else rig.bullet_blood_scatter)


## Age the corpses, drop the finished ones and fill the bands. `k` = living map_scale(), `w` = living
## width (map px), `sh_k` = living shadow (w, h, x, y) × width.
func tick(dt: float, k: float, w: float, sh_k: Vector4, view_rect: Rect2) -> void:
	_k = k
	# Backwards: remove_slot() moves the last slot (already aged) into i.
	for i in range(sim.count - 1, -1, -1):
		sim.phase[i] += dt / maxf(rig.life(sim.rate[i]), 0.001)
		if sim.phase[i] >= 1.0:
			sim.remove_slot(i)
	sim.bin()
	view.update_deaths(sim, rig, k * rig.px_scale, w, sh_k, view_rect)
	_tick_pieces(dt, w)
	_tick_drops(dt, w)
	_tick_splats(dt)
	if _splat_node:
		_splat_node.queue_redraw()
		_ground.queue_redraw()
		_air.queue_redraw()


func piece_count() -> int:
	return _x.size()


func drop_count() -> int:
	return _dx.size()


func splat_count() -> int:
	return _sx.size()


func _spawn_pieces(x: float, y: float, w: float, force: float, sc: float, pull_dir: float, pull: float) -> void:
	if rig.pieces_texture == null:
		return
	var base := rig.piece_speed * w * force * sc
	var push := Vector2(cos(pull_dir), sin(pull_dir)) * pull * base
	for kind in mini(rig.piece_counts.size(), rig.piece_rects.size()):
		for n in rig.piece_counts[kind]:
			var dir := randf() * TAU
			# 0.25…1.75 of the speed, skewed to short: some land close, some far.
			var sp := (0.25 + 1.5 * pow(randf(), 1.3)) * base
			var roll := randf() < rig.piece_roll_share
			_x.append(x + cos(dir) * 0.15 * w)
			_gy.append(y + sin(dir) * 0.15 * w * 0.75)
			_z.append(rig.piece_lift * w * randf_range(0.6, 1.2))
			_vx.append(cos(dir) * sp + push.x)
			_vgy.append((sin(dir) * sp + push.y) * 0.75)
			_vz.append(randf_range(0.4, 1.4) * rig.piece_up * w * sqrt(force))
			_ang.append(randf() * TAU)
			_spin.append(randf_range(-1.0, 1.0) * rig.piece_spin * randf_range(0.5, 1.5))
			_kind.append(kind)
			_age.append(0.0)
			_flip.append(1.0 if randf() < 0.5 else -1.0)
			_hops.append(_pick_hops())
			_bounce.append(rig.piece_bounce * randf_range(0.8, 1.5))
			_keep.append(randf_range(rig.piece_keep.x, rig.piece_keep.y))
			var f := rig.piece_roll_friction if roll else rig.piece_slide_friction
			_fric.append(randf_range(f.x, f.y) * w * sc)
			_flags.append(ROLL if roll else 0)
			_rdir.append(1.0 if randf() < 0.5 else -1.0)
			_trail.append(0.0)


func _pick_hops() -> int:
	var total := 0.0
	for p in rig.piece_hops:
		total += p
	if total <= 0.0:
		return 0
	var r := randf() * total
	for i in rig.piece_hops.size():
		r -= rig.piece_hops[i]
		if r <= 0.0:
			return i + 1
	return rig.piece_hops.size()


func _spawn_blood(x: float, y: float, face: float, w: float, force: float, sc: float) -> void:
	if rig.blood_drops <= 0:
		return
	var n := int(round(rig.blood_drops * randf_range(rig.rnd_drops.x, rig.rnd_drops.y)))
	var turn := randf_range(-rig.rnd_spray, rig.rnd_spray)
	var ca := cos(turn)
	var sa := sin(turn)
	for i in n:
		var ux := randf_range(rig.blood_forward.x, rig.blood_forward.y) * w * 1.1 * force * sc
		var uy := randf_range(-rig.blood_side, rig.blood_side) * w * force * sc
		_add_drop(x + rig.blood_from.x * w * face, y, rig.blood_from.y * w,
				(ux * ca - uy * sa) * face, (ux * sa + uy * ca) * 0.75,
				randf_range(0.2, 1.5) * rig.blood_up * w * sqrt(force),
				randf_range(rig.blood_drop_r.x, rig.blood_drop_r.y) * w / 40.0, 0.0)
	_add_splat(x + rig.blood_pool_at.x * w * face, y + rig.blood_pool_at.y * w,
			rig.blood_pool_r * w * randf_range(rig.rnd_pool.x, rig.rnd_pool.y), 0.0, rig.blood_pool_grow,
			SPLATS + randi() % 2)


func _add_drop(x: float, gy: float, z: float, vx: float, vgy: float, vz: float, r: float, age: float) -> void:
	if _dx.size() >= DROP_CAP:
		return
	_dx.append(x)
	_dgy.append(gy)
	_dz.append(z)
	_dvx.append(vx)
	_dvgy.append(vgy)
	_dvz.append(vz)
	_dr.append(r)
	_dage.append(age)


func _add_splat(x: float, y: float, r: float, age: float, grow: float, tex: int) -> void:
	if _sx.size() >= SPLAT_CAP:
		return
	_sx.append(x)
	_sy.append(y)
	_sr.append(r)
	_sage.append(age)
	_sgrow.append(grow)
	_stex.append(tex)


func _tick_pieces(dt: float, w: float) -> void:
	var n := _x.size()
	if n == 0:
		return
	var life := rig.life()
	var g := rig.piece_gravity * w
	var bleeds := rig.piece_bleeds and rig.blood_drops > 0
	var drop_r := w / 40.0
	for i in n:
		_age[i] += dt
		if _flags[i] & REST:
			continue
		if _z[i] > 0.0 or _vz[i] > 0.0:
			_vz[i] -= g * dt
			_z[i] += _vz[i] * dt
			_x[i] += _vx[i] * dt
			_gy[i] += _vgy[i] * dt
			_ang[i] += _spin[i] * dt
			if bleeds:
				_trail[i] -= dt
				if _trail[i] <= 0.0:
					_trail[i] = 0.035
					_add_drop(_x[i], _gy[i], _z[i], _vx[i] * 0.15 + randf_range(-0.08, 0.08) * w,
							randf_range(-0.04, 0.04) * w, randf_range(-0.05, 0.1) * w,
							randf_range(0.5, 0.9) * drop_r, _age[i])
			if _z[i] <= 0.0:
				_z[i] = 0.0
				if bleeds:
					_add_splat(_x[i], _gy[i], randf_range(0.05, 0.08) * w, _age[i], 0.08, randi() % SPLATS)
				if _hops[i] > 0:
					_hops[i] -= 1
					_vz[i] = maxf(-_vz[i] * _bounce[i], rig.piece_min_hop * w * randf_range(0.8, 1.2))
					_vx[i] *= _keep[i]
					_vgy[i] *= _keep[i]
					_spin[i] *= randf_range(-0.9, 0.9)
				else:
					_vz[i] = 0.0
		else:
			# On the ground after the hops: a roller turns with its speed, a slider stops fast.
			var v := Vector2(_vx[i], _vgy[i]).length()
			var dec := _fric[i] * dt
			if v <= dec:
				_vx[i] = 0.0
				_vgy[i] = 0.0
				_spin[i] = 0.0
				_flags[i] |= REST
			else:
				var s := (v - dec) / v
				_vx[i] *= s
				_vgy[i] *= s
				if _flags[i] & ROLL:
					_spin[i] = _rdir[i] * v / (0.08 * w)
				else:
					_spin[i] *= s
				_x[i] += _vx[i] * dt
				_gy[i] += _vgy[i] * dt
				_ang[i] += _spin[i] * dt
				if bleeds:
					_trail[i] -= dt
					if _trail[i] <= 0.0:
						_trail[i] = 0.05
						_add_splat(_x[i], _gy[i], randf_range(0.02, 0.035) * w, _age[i], 0.08, randi() % SPLATS)
	# All pieces of a death share its age, deaths come in order → the finished ones are at the front.
	var done := 0
	while done < n and _age[done] >= life:
		done += 1
	if done > 0:
		_drop_front_pieces(done)


func _drop_front_pieces(k: int) -> void:
	# Packed arrays are values in GDScript (a loop over [_x, …] would slice copies) → one by one.
	_x = _x.slice(k)
	_gy = _gy.slice(k)
	_z = _z.slice(k)
	_vx = _vx.slice(k)
	_vgy = _vgy.slice(k)
	_vz = _vz.slice(k)
	_ang = _ang.slice(k)
	_spin = _spin.slice(k)
	_kind = _kind.slice(k)
	_age = _age.slice(k)
	_flip = _flip.slice(k)
	_hops = _hops.slice(k)
	_bounce = _bounce.slice(k)
	_keep = _keep.slice(k)
	_fric = _fric.slice(k)
	_flags = _flags.slice(k)
	_rdir = _rdir.slice(k)
	_trail = _trail.slice(k)


func _tick_drops(dt: float, w: float) -> void:
	var n := _dx.size()
	if n == 0:
		return
	var life := rig.life()
	var g := rig.piece_gravity * w
	var j := 0
	for i in n:
		var age := _dage[i] + dt
		var vz := _dvz[i] - g * dt
		var z := _dz[i] + vz * dt
		var x := _dx[i] + _dvx[i] * dt
		var gy := _dgy[i] + _dvgy[i] * dt
		if z <= 0.0:
			_add_splat(x, gy, _dr[i] * randf_range(1.3, 2.2), age, 0.08, randi() % SPLATS)
			continue
		if age >= life:
			continue
		# Compact in place: drops land in any order.
		_dx[j] = x
		_dgy[j] = gy
		_dz[j] = z
		_dvx[j] = _dvx[i]
		_dvgy[j] = _dvgy[i]
		_dvz[j] = vz
		_dr[j] = _dr[i]
		_dage[j] = age
		j += 1
	if j < n:
		_dx.resize(j)
		_dgy.resize(j)
		_dz.resize(j)
		_dvx.resize(j)
		_dvgy.resize(j)
		_dvz.resize(j)
		_dr.resize(j)
		_dage.resize(j)


func _tick_splats(dt: float) -> void:
	var n := _sx.size()
	if n == 0:
		return
	for i in n:
		_sage[i] += dt
	# Splats come roughly oldest first; a finished one further back is fully melted (alpha 0) and goes
	# when it reaches the front.
	var life := rig.life()
	var done := 0
	while done < n and _sage[done] >= life:
		done += 1
	if done > 0:
		_sx = _sx.slice(done)
		_sy = _sy.slice(done)
		_sr = _sr.slice(done)
		_sage = _sage.slice(done)
		_sgrow = _sgrow.slice(done)
		_stex = _stex.slice(done)


func _alpha(age: float) -> float:
	return 1.0 - clampf((age - rig.fade_start()) / maxf(rig.fade, 0.001), 0.0, 1.0)


func _draw_splats() -> void:
	if _tex.is_empty():
		return
	var to_rect := Vector2(SPLAT_SIZE) / SPLAT_PX
	for i in _sx.size():
		var a := _alpha(_sage[i])
		if a <= 0.0:
			continue
		var r := _sr[i] * minf(1.0, 0.35 + _sage[i] / maxf(0.05, _sgrow[i]) * 0.65)
		var size := to_rect * r
		_splat_node.draw_texture_rect(_tex[_stex[i]], Rect2(Vector2(_sx[i], _sy[i]) - size * 0.5, size), false, Color(1, 1, 1, a))


func _draw_air() -> void:
	_draw_pieces(_air, true)
	if _drop_tex == null:
		return
	var to_rect := float(_drop_tex.get_width()) / DROP_PX
	for i in _dx.size():
		var size := Vector2.ONE * _dr[i] * to_rect
		_air.draw_texture_rect(_drop_tex, Rect2(Vector2(_dx[i], _dgy[i] - _dz[i]) - size * 0.5, size), false, Color(1, 1, 1, _alpha(_dage[i])))


## Pieces of one layer: `flying` → still in the air (z > 0 or going up), else on the ground.
func _draw_pieces(node: Node2D, flying: bool) -> void:
	var tex := rig.pieces_texture if rig else null
	if tex == null:
		return
	for i in _x.size():
		if (_z[i] > 0.0 or _vz[i] > 0.0) != flying:
			continue
		var r := rig.piece_rects[_kind[i]]
		node.draw_set_transform(Vector2(_x[i], _gy[i] - _z[i]), _ang[i], Vector2(_k * _flip[i], _k))
		node.draw_texture_rect_region(tex, Rect2(-r.size * 0.5, r.size), r, Color(1, 1, 1, _alpha(_age[i])))
	node.draw_set_transform_matrix(Transform2D.IDENTITY)


## Splat, pool and drop textures in the rig's blood colours, made once per colour set: a main ellipse
## (squashed 0.75) with blobs, dark outline 0.12 of the radius, a glossy highlight up right.
func _make_textures() -> void:
	var key := "%s %s %s" % [rig.blood_fill.to_html(), rig.blood_line.to_html(), rig.blood_highlight.to_html()]
	if not _tex_cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var list: Array[ImageTexture] = []
		for v in SPLATS + 2:
			var pool := v >= SPLATS
			var blobs: Array[Vector3] = []
			for b in (7 if pool else (2 if v % 2 == 0 else 4)):
				var a := rng.randf() * TAU
				var d := rng.randf_range(0.5, 0.7 if pool else 1.05)
				blobs.append(Vector3(cos(a) * d, sin(a) * d, rng.randf_range(0.18, 0.35)))
			list.append(ImageTexture.create_from_image(_splat_image(blobs)))
		_tex_cache[key] = [list, ImageTexture.create_from_image(_drop_image())]
	var pair: Array = _tex_cache[key]
	_tex = pair[0]
	_drop_tex = pair[1]


func _splat_image(blobs: Array[Vector3]) -> Image:
	var img := Image.create(SPLAT_SIZE.x, SPLAT_SIZE.y, false, Image.FORMAT_RGBA8)
	var c := Vector2(SPLAT_SIZE) * 0.5
	var line_px := 0.12 * SPLAT_PX
	for py in SPLAT_SIZE.y:
		for px in SPLAT_SIZE.x:
			var u := (px + 0.5 - c.x) / SPLAT_PX
			var v := (py + 0.5 - c.y) / (SPLAT_PX * 0.75)
			var d := Vector2(u, v).length() - 1.0
			for b in blobs:
				d = minf(d, Vector2(u - b.x, v - b.y).length() - b.z)
			var dpx := d * SPLAT_PX
			var alpha := clampf(0.5 - (dpx - line_px), 0.0, 1.0)
			if alpha <= 0.0:
				continue
			var fill := clampf(0.5 - dpx, 0.0, 1.0)
			var col := rig.blood_line.lerp(rig.blood_fill, fill)
			var hu := (u - 0.25) / 0.22
			var hv := (v + 0.267) / 0.133
			if hu * hu + hv * hv < 1.0:
				col = col.lerp(rig.blood_highlight, 0.7 * fill)
			img.set_pixel(px, py, Color(col.r, col.g, col.b, alpha))
	return img


func _drop_image() -> Image:
	var s := 12
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for py in s:
		for px in s:
			var d := Vector2(px + 0.5 - s * 0.5, py + 0.5 - s * 0.5).length()
			var alpha := clampf(0.5 - (d - DROP_PX * 1.25), 0.0, 1.0)
			if alpha <= 0.0:
				continue
			var col := rig.blood_line.lerp(rig.blood_fill, clampf(0.5 - (d - DROP_PX), 0.0, 1.0))
			img.set_pixel(px, py, Color(col.r, col.g, col.b, alpha))
	return img
