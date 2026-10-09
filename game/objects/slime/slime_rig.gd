@tool
class_name SlimeRig
extends Resource
## Shared parameters of the slime (one .tres for all slimes: change it — every slime changes).
## Crawl / blink defaults were tuned in slime_crawl.html (removed, git ba44ef0).
## Skins: atlas art/objects/enemies/slime/slime_skins.png (built by slime_skins.py), frames side by
## side, all with the same pivot. A new slime takes a random skin. Pixels are frame px.

## Skin atlas: frames of `frame_w` px side by side.
@export var texture: Texture2D:
	set(v): texture = v; emit_changed()
@export var frame_w := 1064.0:
	set(v): frame_w = v; emit_changed()
@export_range(1, 4, 1) var skin_count := 2:
	set(v): skin_count = v; emit_changed()
## Ground point in a frame, px.
@export var pivot := Vector2(532, 557):
	set(v): pivot = v; emit_changed()
## Body width in a frame, px (it becomes `size_cells` on the map).
@export var sprite_w := 1000.0:
	set(v): sprite_w = v; emit_changed()
## Width on the map, in cells (cell = 32 px).
@export_range(0.1, 3.0, 0.01) var size_cells := 0.8:
	set(v): size_cells = v; emit_changed()

@export_group("Crawl")
## One crawl cycle, s (at rate 1).
@export_range(0.2, 3.0, 0.01) var period := 0.9:
	set(v): period = v; emit_changed()
## Share of the cycle spent stretching forward.
@export_range(0.05, 0.95, 0.01) var lunge := 0.4:
	set(v): lunge = v; emit_changed()
@export_range(0.0, 0.5, 0.01) var stretch := 0.14:
	set(v): stretch = v; emit_changed()
@export_range(0.0, 0.5, 0.01) var squash := 0.12:
	set(v): squash = v; emit_changed()
## Lean of the top (skew), degrees.
@export_range(0.0, 30.0, 0.5) var lean := 8.0:
	set(v): lean = v; emit_changed()
## Lean lag, share of the cycle.
@export_range(0.0, 1.0, 0.01) var lean_phase := 0.2:
	set(v): lean_phase = v; emit_changed()
## Jelly spring strength (0 = off).
@export_range(0.0, 1.0, 0.01) var jelly := 0.55:
	set(v): jelly = v; emit_changed()
@export_range(0.05, 1.0, 0.01) var damp := 0.35:
	set(v): damp = v; emit_changed()
## Inchworm step (0 = slides evenly).
@export_range(0.0, 1.0, 0.01) var inch := 0.85:
	set(v): inch = v; emit_changed()
## Even slide, cells/s.
@export_range(0.0, 3.0, 0.05) var slide := 0.15:
	set(v): slide = v; emit_changed()

@export_group("Shadow ellipse")
## Sizes and shifts are × slime width.
@export_range(0.3, 1.6, 0.01) var shadow_w := 0.95:
	set(v): shadow_w = v; emit_changed()
@export_range(0.05, 0.6, 0.01) var shadow_h := 0.3:
	set(v): shadow_h = v; emit_changed()
@export_range(-0.5, 0.5, 0.01) var shadow_x := -0.08:
	set(v): shadow_x = v; emit_changed()
@export_range(-0.3, 0.3, 0.01) var shadow_y := -0.07:
	set(v): shadow_y = v; emit_changed()
@export_range(0.0, 1.0, 0.01) var shadow_alpha := 0.38:
	set(v): shadow_alpha = v; emit_changed()

@export_group("Eyes")
## 3 eyes per skin (skin 0: [0..2], skin 1: [3..5] …): x, y, rx, ry in frame px. Order inside a
## skin: left, middle, right.
@export var eyes: Array[Vector4] = [
	Vector4(642, 365, 65, 57), Vector4(746, 258, 72, 65), Vector4(875, 350, 39, 34),
	Vector4(663, 322, 46, 30), Vector4(759, 260, 56, 45), Vector4(824, 334, 30, 26)]:
	set(v): eyes = v; emit_changed()
## Per eye: bit mask of the eyes of the same skin cut out of its lid (bit j = eye j of the skin).
@export var eye_over := PackedInt32Array([0, 0, 0, 0, 0, 0]):
	set(v): eye_over = v; emit_changed()
## Blink series order (eye index inside a skin).
@export var blink_order := PackedInt32Array([0, 2, 1]):
	set(v): blink_order = v; emit_changed()

@export_group("Blink")
@export_range(0.02, 0.4, 0.01) var blink_close := 0.07:
	set(v): blink_close = v; emit_changed()
@export_range(0.0, 0.4, 0.01) var blink_hold := 0.05:
	set(v): blink_hold = v; emit_changed()
@export_range(0.02, 0.5, 0.01) var blink_open := 0.11:
	set(v): blink_open = v; emit_changed()
## From eye to eye, s.
@export_range(0.0, 1.0, 0.01) var blink_gap := 0.18:
	set(v): blink_gap = v; emit_changed()
## Pause between series, s.
@export_range(0.2, 8.0, 0.1) var blink_pause := 2.2:
	set(v): blink_pause = v; emit_changed()
## Random addition to the pause, s.
@export_range(0.0, 4.0, 0.1) var blink_rand := 1.5:
	set(v): blink_rand = v; emit_changed()
@export var lid_top := Color("#a24cf2"):
	set(v): lid_top = v; emit_changed()
@export var lid_bottom := Color("#6418b8"):
	set(v): lid_bottom = v; emit_changed()
@export var lid_rim := Color("#2a0650"):
	set(v): lid_rim = v; emit_changed()
## Lid rim width, sprite px.
@export_range(0.0, 20.0, 1.0) var lid_rim_px := 7.0:
	set(v): lid_rim_px = v; emit_changed()


## Push eyes, blink timing and lid colours into a slime.gdshader material.
func apply_to_material(mat: ShaderMaterial) -> void:
	if texture:
		mat.set_shader_parameter("tex_size", texture.get_size())
	var n_eyes := mini(eyes.size(), mini(skin_count * 3, 12))
	var arr := PackedVector4Array()
	var ov := PackedInt32Array()
	arr.resize(12)
	ov.resize(12)
	for i in n_eyes:
		arr[i] = eyes[i] + Vector4((i / 3) * frame_w, 0, 0, 0)
		ov[i] = eye_over[i] if i < eye_over.size() else 0
	mat.set_shader_parameter("eyes", arr)
	mat.set_shader_parameter("over", ov)
	mat.set_shader_parameter("eye_count", n_eyes)
	var pos := Vector3.ZERO
	for n in blink_order.size():
		if blink_order[n] >= 0 and blink_order[n] < 3:
			pos[blink_order[n]] = n
	mat.set_shader_parameter("order_pos", pos)
	mat.set_shader_parameter("b_close", blink_close)
	mat.set_shader_parameter("b_hold", blink_hold)
	mat.set_shader_parameter("b_open", blink_open)
	mat.set_shader_parameter("b_gap", blink_gap)
	mat.set_shader_parameter("b_pause", blink_pause)
	mat.set_shader_parameter("b_rand", blink_rand)
	mat.set_shader_parameter("lid_top", lid_top)
	mat.set_shader_parameter("lid_bottom", lid_bottom)
	mat.set_shader_parameter("lid_rim", lid_rim)
	mat.set_shader_parameter("rim_px", lid_rim_px)


## Frame rect of a skin in the atlas.
func frame_rect(skin: int) -> Rect2:
	var h := texture.get_size().y if texture else 1.0
	return Rect2(skin * frame_w, 0, frame_w, h)


## Skin from a 0..1 random value.
func skin_of(rnd: float) -> int:
	return clampi(int(rnd * skin_count), 0, skin_count - 1)


## UV shift of a skin's frame (MultiMesh custom data .y).
func skin_uv_shift(skin: int) -> float:
	var w := texture.get_size().x if texture else 1.0
	return skin * frame_w / w


## Width of the slime on the map, px.
func width_px() -> float:
	return size_cells * MapGrid.CELL.x


## Sprite → map scale.
func map_scale() -> float:
	return width_px() / sprite_w


## f(p): −1 squashed → +1 stretched over `lunge` of the cycle, back over the rest.
func profile(p: float) -> float:
	var u := 0.5 * p / lunge if p < lunge else 0.5 + 0.5 * (p - lunge) / (1.0 - lunge)
	return -cos(TAU * u)


## Mean speed at rate 1, cells/s (slime_crawl.html avgSpeed()). Game: rate = speed / avg_speed().
func avg_speed() -> float:
	return (inch * size_cells * 2.0 * stretch + slide * period) / period


## Length of one blink series, s.
func blink_series_len() -> float:
	return (blink_order.size() - 1) * blink_gap + blink_close + blink_hold + blink_open


## Closure of eye `i` (0 open … 1 closed) at time `t` since the series start (slime_crawl.html lidOf()).
func lid_of(t_series: float, i: int) -> float:
	var k := 0
	for n in blink_order.size():
		if blink_order[n] == i:
			k = n
	var t := t_series - k * blink_gap
	if t < 0.0:
		return 0.0
	if t < blink_close:
		return smoothstep(0.0, 1.0, t / blink_close)
	if t < blink_close + blink_hold:
		return 1.0
	if t < blink_close + blink_hold + blink_open:
		return 1.0 - smoothstep(0.0, 1.0, (t - blink_close - blink_hold) / blink_open)
	return 0.0
