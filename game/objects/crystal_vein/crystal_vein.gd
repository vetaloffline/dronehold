@tool
class_name CrystalVein
extends MapObject
## Crystal vein: monolith with three floating shards, glows and shard shadows; one drill slot.
## Same drawing as crystal_vein_anim.html: shard shadows → vein → monolith glow (ADD) →
## per shard: glow (ADD) → shard. The vein shadow is a ground layer (z −1).
## Node origin = ground point; everything inside is in crystal_vein.png px minus the ground point.

## Cell of the drill slot relative to the vein cell: right-back corner (map_03_editor.html VEIN_SLOT)
## or, mirrored, left-back. One slot per vein: the map picks the side (`drill_side`).
const SLOT := Vector2i(6, -2)
const SLOT_LEFT := Vector2i(-2, -2)

enum Side { RIGHT, LEFT }
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

## Which side of this vein its drill stands on (set per vein on the map). Left: the drill is drawn
## mirrored and fires to the right, at the vein (rig.drill_offset_left / hit_point_left).
## In the editor the vein shows its slot: a 2×2 frame (green — buildable, red — not) and an arrow.
@export var drill_side := Side.RIGHT:
	set(v):
		drill_side = v
		if _slot_marker:
			_slot_marker.queue_redraw()

var _slot_marker: Node2D

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
	return cell + (SLOT_LEFT if drill_side == Side.LEFT else SLOT)


func drill_mirrored() -> bool:
	return drill_side == Side.LEFT


## Vein px of the drill's px origin: p_vein = drill_origin + (±p_drill.x, p_drill.y)·drill_scale.
func drill_origin() -> Vector2:
	return rig.drill_offset_left if drill_mirrored() else rig.drill_offset


## Where the laser hits, vein px.
func drill_hit() -> Vector2:
	return rig.hit_point_left if drill_mirrored() else rig.hit_point


## Drill px → vein px for the drill in this vein's slot (mirrored on the left).
func drill_px_to_vein(q: Vector2) -> Vector2:
	return drill_origin() + Vector2(-q.x if drill_mirrored() else q.x, q.y) * rig.drill_scale


## Vein px → drill px (inverse of drill_px_to_vein).
func vein_px_to_drill(p: Vector2) -> Vector2:
	var q := (p - drill_origin()) / rig.drill_scale
	return Vector2(-q.x, q.y) if drill_mirrored() else q


## Where the laser hits, in this node's local space.
func hit_point_local() -> Vector2:
	return drill_hit() - rig.ground_point


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
	if Engine.is_editor_hint():
		# Not saved into the scene; on top of everything so the vein does not hide it.
		_slot_marker = Node2D.new()
		_slot_marker.z_index = 20
		add_child(_slot_marker, false, Node.INTERNAL_MODE_FRONT)
		_slot_marker.draw.connect(_draw_slot)
	_shard_shadows.draw.connect(_draw_shard_shadows)
	_monolith_glow.draw.connect(_draw_monolith_glow)
	for i in _glows.size():
		_glows[i].draw.connect(_draw_shard_glow.bind(i))
	_animate()


func _process(dt: float) -> void:
	editor_snap()
	_t += dt
	_animate()
	if _slot_marker:
		_slot_marker.queue_redraw()


## Editor: both places this vein's drill can go. The chosen side (`drill_side`) — a bright frame with an
## arrow towards the vein (green — buildable, red — not; hidden once a drill stands there); the other
## side — a faint dashed frame, so you see the option. Switch with Drill Side in the Inspector.
func _draw_slot() -> void:
	if rig == null:
		return
	for side in [Side.RIGHT, Side.LEFT]:
		_draw_one_slot(side, side == drill_side)


func _draw_one_slot(side: Side, chosen: bool) -> void:
	var slot := cell + (SLOT_LEFT if side == Side.LEFT else SLOT)
	var map := get_parent().get_parent() as GameMap if get_parent() else null
	var ok := true
	if map and map.grid:
		for dy in 2:
			for dx in 2:
				var c := slot + Vector2i(dx, dy)
				ok = ok and map.grid.inside(c.x, c.y) and map.grid.can_build(c.x, c.y)
	if chosen:
		for n in get_parent().get_children():
			if n is Drill and (n as Drill).cell == slot:
				return
	var to_local := transform.affine_inverse()
	var a: Vector2 = to_local * (Vector2(slot) * MapGrid.CELL)
	var b: Vector2 = to_local * (Vector2(slot + Vector2i(2, 2)) * MapGrid.CELL)
	var r := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())
	var col := Color(0.3, 1.0, 0.45) if ok else Color(1.0, 0.3, 0.3)
	var w := 3.0 / maxf(0.001, get_map_scale())
	if not chosen:
		# The other side: faint dashed frame.
		var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for k in 4:
			_slot_marker.draw_dashed_line(pts[k], pts[(k + 1) % 4], Color(col, 0.5), w * 0.7, w * 4.0)
		return
	_slot_marker.draw_rect(r, Color(col, 0.18))
	_slot_marker.draw_rect(r, Color(col, 0.95), false, w)
	# Arrow from the slot towards the vein: the way the drill will fire.
	var from := r.get_center()
	var to := from + Vector2(r.size.x * (-0.9 if side == Side.RIGHT else 0.9), r.size.y * 0.5)
	_slot_marker.draw_line(from, to, Color(col, 0.95), w, true)
	var d := (to - from).normalized()
	var nrm := Vector2(-d.y, d.x)
	var head := r.size.x * 0.22
	_slot_marker.draw_colored_polygon(PackedVector2Array([to + d * head, to + nrm * head * 0.6, to - nrm * head * 0.6]), Color(col, 0.95))


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
