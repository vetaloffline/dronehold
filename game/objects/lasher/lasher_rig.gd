@tool
class_name LasherRig
extends Resource
## Shared parameters of the lasher (one .tres for all of them).
## Run cycle: atlas art/objects/enemies/lasher/lasher_run_atlas.png, built by lasher_run_build.py from the
## parts in art/objects/enemies/lasher/parts/ (the motion is lasher_run_template.py). The frame grid,
## pivot, cycle length and stride below are from lasher_run_atlas.json. Pixels are atlas frame px.

## Run cycle atlas: `cols` × `rows` frames of `frame_w` × `frame_h` px, frame 0 top left, row by row.
@export var texture: Texture2D:
	set(v): texture = v; emit_changed()
@export_range(1, 64, 1) var frames := 32:
	set(v): frames = v; emit_changed()
@export_range(1, 16, 1) var cols := 8:
	set(v): cols = v; emit_changed()
@export_range(1, 16, 1) var rows := 4:
	set(v): rows = v; emit_changed()
@export var frame_w := 320.0:
	set(v): frame_w = v; emit_changed()
@export var frame_h := 247.0:
	set(v): frame_h = v; emit_changed()
## Ground point under the body in a frame, px (Y-sort key).
@export var pivot := Vector2(139.3, 177.9):
	set(v): pivot = v; emit_changed()
## Width of the whole frame on the map, in cells (cell = 32 px).
@export_range(0.2, 6.0, 0.01) var size_cells := 1.6:
	set(v): size_cells = v; emit_changed()

@export_group("Run")
## One run cycle at rate 1, s (the approved GIF: 32 frames × 50 ms).
@export_range(0.2, 5.0, 0.01) var period := 1.6:
	set(v): period = v; emit_changed()
## Ground covered in one cycle, × frame width (trot: 2 strides; lasher_run_atlas.json).
## Matching it to the speed keeps the feet from sliding.
@export_range(0.05, 2.0, 0.001) var stride := 0.518:
	set(v): stride = v; emit_changed()

@export_group("Shadow ellipse")
## Sizes and shifts are × frame width on the map.
@export_range(0.1, 1.6, 0.01) var shadow_w := 0.68:
	set(v): shadow_w = v; emit_changed()
@export_range(0.05, 0.8, 0.01) var shadow_h := 0.3:
	set(v): shadow_h = v; emit_changed()
@export_range(-0.5, 0.5, 0.01) var shadow_x := 0.0:
	set(v): shadow_x = v; emit_changed()
@export_range(-0.3, 0.3, 0.01) var shadow_y := 0.0:
	set(v): shadow_y = v; emit_changed()
@export_range(0.0, 1.0, 0.01) var shadow_alpha := 0.38:
	set(v): shadow_alpha = v; emit_changed()


## Width on the map, px.
func width_px() -> float:
	return size_cells * MapGrid.CELL.x


## Atlas frame px → map px.
func map_scale() -> float:
	return width_px() / frame_w


## Mean speed at rate 1, cells/s. Game: rate = speed / avg_speed().
func avg_speed() -> float:
	return stride * size_cells / period


## Frame of the cycle at phase p in [0, 1).
func frame_of(p: float) -> int:
	return clampi(int(p * frames), 0, frames - 1)


## UV shift of a frame in the atlas (MultiMesh custom data .z, .w).
func frame_uv(f: int) -> Vector2:
	return Vector2(float(f % cols) / cols, float(f / cols) / rows)
