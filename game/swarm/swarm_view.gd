class_name SwarmView
extends RefCounted
## Draws the swarm with MultiMesh: one MultiMeshInstance2D per horizontal band of the map
## (a grid row / BANDS_PER_ROW; 24 px with 32×24 cells — the same band height as before).
## Bands are children of the Y-sorted World, so slimes sort against buildings by band; inside a band instances are written bottom-last. Off-screen bands are hidden and not
## filled — only visible slimes cost render work. One draw call per visible band.
##
## Buffer per instance (MultiMesh TRANSFORM_2D + custom data, 12 floats; layout checked against
## drivers/gles3/storage/mesh_storage.cpp _multimesh_instance_set_transform_2d):
##   [x.x, y.x, 0, origin.x,  x.y, y.y, 0, origin.y,  custom.r, .g, .b, .a]
## Transform = Godot Transform2D(scale (sx·face, sy), skew) as in slime_crawl.html:
##   x = (sx, 0), y = (−sin(skew)·sy, cos(skew)·sy).

const STRIDE := 12
const SUB_BUCKETS := 6
## Bands per grid row: more = finer sorting against buildings, but one draw call more per band.
const BANDS_PER_ROW := 1

var band_h := MapGrid.CELL.y / BANDS_PER_ROW
var bands := 0
var _body: Array[MultiMeshInstance2D] = []
var _shadow: Array[MultiMeshInstance2D] = []
var _buf: Array[PackedFloat32Array] = []
var _sbuf: Array[PackedFloat32Array] = []
var _cap := PackedInt32Array()
var material: ShaderMaterial
var visible_count := 0
var _map_w := 0.0


func setup(world: Node2D, shadows: Node2D, grid: MapGrid, rig: SlimeRig, shader: Shader) -> void:
	free_nodes()
	_map_w = grid.size_px().x
	bands = int(ceil(grid.size_px().y / band_h))
	material = ShaderMaterial.new()
	material.shader = shader
	rig.apply_to_material(material)
	var tex_size := rig.texture.get_size() if rig.texture else Vector2(1, 1)
	# One frame of the skin atlas; the shader shifts UV to the slime's skin.
	var body_mesh := _quad(-rig.pivot, Vector2(rig.frame_w, tex_size.y), Vector2(rig.frame_w / tex_size.x, 1.0))
	var shadow_mesh := _quad(Vector2(-0.5, -0.5), Vector2(1, 1), Vector2(1, 1))
	var shadow_tex := _ellipse_texture()
	_cap.resize(bands)
	_cap.fill(0)
	for b in bands:
		var mi := MultiMeshInstance2D.new()
		mi.name = "SwarmBand%d" % b
		mi.position = Vector2(0, (b + 1) * band_h)
		mi.texture = rig.texture
		mi.material = material
		mi.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mi.multimesh = _new_mm(body_mesh)
		mi.visible = false
		world.add_child(mi)
		_body.append(mi)
		var sh := MultiMeshInstance2D.new()
		sh.name = "SwarmShadow%d" % b
		sh.position = mi.position
		sh.texture = shadow_tex
		sh.modulate = Color(0.078, 0.031, 0.11, rig.shadow_alpha)
		sh.multimesh = _new_mm(shadow_mesh)
		sh.visible = false
		shadows.add_child(sh)
		_shadow.append(sh)
		_buf.append(PackedFloat32Array())
		_sbuf.append(PackedFloat32Array())


func free_nodes() -> void:
	for n in _body + _shadow:
		if is_instance_valid(n):
			n.queue_free()
	_body.clear()
	_shadow.clear()
	_buf.clear()
	_sbuf.clear()
	bands = 0  # update() draws nothing until setup() builds the bands again


func refresh_material(rig: SlimeRig) -> void:
	if material:
		rig.apply_to_material(material)
	for sh in _shadow:
		sh.modulate.a = rig.shadow_alpha


## Fill the bands that intersect `view` (map px).
func update(sim: SwarmSim, crawl: SlimeCrawl, rig: SlimeRig, view: Rect2) -> void:
	visible_count = 0
	if bands == 0:
		return
	var k := rig.map_scale()
	var w := rig.width_px()
	var top_margin := w * 1.2
	var b0 := clampi(int(floor((view.position.y - band_h) / band_h)), 0, bands - 1)
	var b1 := clampi(int(floor((view.end.y + top_margin) / band_h)), 0, bands - 1)
	var c0 := clampi(int(floor((view.position.x - w) / MapGrid.CELL.x)), 0, sim.cols - 1)
	var c1 := clampi(int(floor((view.end.x + w) / MapGrid.CELL.x)), 0, sim.cols - 1)
	for b in bands:
		if b < b0 or b > b1:
			_body[b].visible = false
			_shadow[b].visible = false
	var scale_lut := crawl.scale_lut
	var lean_lut := crawl.lean_lut
	var lean_rad := crawl.lean_rad
	var sh_w := rig.shadow_w * w
	var sh_h := rig.shadow_h * w
	var sh_x := rig.shadow_x * w
	var sh_y := rig.shadow_y * w
	var sub_h := band_h / SUB_BUCKETS
	var r0 := b0 / BANDS_PER_ROW
	var r1 := mini(sim.rows - 1, b1 / BANDS_PER_ROW)
	for r in range(r0, r1 + 1):
		# Collect visible slots of this row, split into its bands and sub-buckets by y.
		var lists: Array[PackedInt32Array] = []
		for q in SUB_BUCKETS * BANDS_PER_ROW:
			lists.append(PackedInt32Array())
		var row_top := r * MapGrid.CELL.y
		for c in range(c0, c1 + 1):
			var ci := r * sim.cols + c
			for o in range(sim.cell_start[ci], sim.cell_start[ci] + sim.cell_count[ci]):
				var i := sim.order[o]
				if i >= sim.count:
					continue
				var q := clampi(int((sim.py[i] - row_top) / sub_h), 0, SUB_BUCKETS * BANDS_PER_ROW - 1)
				lists[q].append(i)
		for half in BANDS_PER_ROW:
			var b := r * BANDS_PER_ROW + half
			if b < b0 or b > b1:
				continue
			var n := 0
			for q in SUB_BUCKETS:
				n += lists[half * SUB_BUCKETS + q].size()
			var body := _body[b]
			var shadow := _shadow[b]
			if n == 0:
				body.visible = false
				shadow.visible = false
				continue
			_ensure_capacity(b, n)
			# Take the buffers out of the arrays so writes do not trigger a copy-on-write.
			var buf := _buf[b]
			var sbuf := _sbuf[b]
			_buf[b] = PackedFloat32Array()
			_sbuf[b] = PackedFloat32Array()
			var base_y := (b + 1) * band_h
			var j := 0
			for q in SUB_BUCKETS:
				for i in lists[half * SUB_BUCKETS + q]:
					var s := mini(int(sim.phase[i] * SlimeCrawl.SAMPLES), SlimeCrawl.SAMPLES - 1)
					var sx := scale_lut[s * 2]
					var sy := scale_lut[s * 2 + 1]
					var f := sim.face[i]
					var sk := -lean_rad * lean_lut[s] * f
					var x := sim.px[i]
					var y := sim.py[i] - base_y
					var o := j * STRIDE
					buf[o] = sx * f * k
					buf[o + 1] = -sin(sk) * sy * k
					buf[o + 2] = 0.0
					buf[o + 3] = x
					buf[o + 4] = 0.0
					buf[o + 5] = cos(sk) * sy * k
					buf[o + 6] = 0.0
					buf[o + 7] = y
					buf[o + 8] = sim.seed[i]
					buf[o + 9] = rig.skin_uv_shift(rig.skin_of(sim.seed[i]))
					buf[o + 10] = 0.0
					buf[o + 11] = 0.0
					sbuf[o] = sh_w * sx
					sbuf[o + 1] = 0.0
					sbuf[o + 2] = 0.0
					sbuf[o + 3] = x + sh_x * f
					sbuf[o + 4] = 0.0
					sbuf[o + 5] = sh_h
					sbuf[o + 6] = 0.0
					sbuf[o + 7] = y + sh_y
					j += 1
			# Unused tail: zero scale, so nothing is drawn.
			for t in range(j * STRIDE, buf.size(), STRIDE):
				buf[t] = 0.0
				buf[t + 5] = 0.0
				sbuf[t] = 0.0
				sbuf[t + 5] = 0.0
			body.multimesh.visible_instance_count = n
			shadow.multimesh.visible_instance_count = n
			body.multimesh.buffer = buf
			shadow.multimesh.buffer = sbuf
			_buf[b] = buf
			_sbuf[b] = sbuf
			body.visible = true
			shadow.visible = true
			visible_count += n


func _ensure_capacity(b: int, n: int) -> void:
	if _cap[b] >= n:
		return
	var cap := maxi(16, nearest_po2(n))
	_cap[b] = cap
	for mi in [_body[b], _shadow[b]]:
		var mm := (mi as MultiMeshInstance2D).multimesh
		mm.instance_count = 0
		mm.use_custom_data = true
		mm.instance_count = cap
		mm.custom_aabb = AABB(Vector3(-64, -band_h - 256, -1), Vector3(_map_w + 128, band_h + 320, 2))
	var buf := PackedFloat32Array()
	buf.resize(cap * STRIDE)
	_buf[b] = buf
	var sbuf := PackedFloat32Array()
	sbuf.resize(cap * STRIDE)
	_sbuf[b] = sbuf


func _new_mm(mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = mesh
	return mm


## Quad from `origin` of `size` px with UV 0..uv_max.
static func _quad(origin: Vector2, size: Vector2, uv_max: Vector2) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([
		origin, origin + Vector2(size.x, 0), origin + size, origin + Vector2(0, size.y)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(uv_max.x, 0), uv_max, Vector2(0, uv_max.y)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Filled ellipse with a 1-texel soft edge (the tuner draws a plain filled ellipse).
static func _ellipse_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color.WHITE)
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.94, Color.WHITE)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t
