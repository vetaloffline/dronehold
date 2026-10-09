@tool
class_name CoreRig
extends Resource
## Shared parameters of the core (one .tres for all cores: change it — every core changes).
## Defaults = art/objects/buildings/core/core_shadow_editor.html DEF (the approved core_shadow.png:
## the Codex cast layer untouched + the contact layer).
## Pixels are in core.png coordinates (all core PNGs are 1536×1024 in the same space).

enum ShadowSource { CODEX, SILHOUETTE }

## Ground point of the building (bottom centre); transforms of the cast shadow pivot around it.
@export var pivot := Vector2(762, 992):
	set(v): pivot = v; emit_changed()

@export_group("Map")
## Sprite → map scale (map_03_editor.html SPR.core.s).
@export_range(0.02, 1.2, 0.005) var map_scale := 0.2:
	set(v): map_scale = v; emit_changed()
## Ground point shift from the 3×3 footprint centre, cells (SPR.core.dx, dy).
@export var map_shift := Vector2(0, 1.2):
	set(v): map_shift = v; emit_changed()

@export_group("Cast shadow")
## Codex = core_shadow_cast.png as drawn; Silhouette = the building tinted to `shadow_color`.
@export var source := ShadowSource.CODEX:
	set(v): source = v; emit_changed()
## Shift, px.
@export var shift := Vector2.ZERO:
	set(v): shift = v; emit_changed()
## Scale X.
@export_range(0.2, 2.5, 0.01) var scale_x := 1.0:
	set(v): scale_x = v; emit_changed()
## Scale Y (flatten).
@export_range(0.05, 2.0, 0.01) var scale_y := 1.0:
	set(v): scale_y = v; emit_changed()
## Skew X: x' = x + skew · y (y is negative above the pivot).
@export_range(-3.0, 3.0, 0.01) var skew_x := 0.0:
	set(v): skew_x = v; emit_changed()
## Rotation, degrees.
@export_range(-180, 180, 1) var rotation_deg := 0.0:
	set(v): rotation_deg = v; emit_changed()
## Opacity.
@export_range(0.0, 1.0, 0.01) var opacity := 1.0:
	set(v): opacity = v; emit_changed()
## Blur, px (approximated with a mipmap bias).
@export_range(0, 40, 1) var blur := 0.0:
	set(v): blur = v; emit_changed()
## Silhouette colour (core_shadow_editor.html makeSil(): rgb(3,11,26)).
@export var shadow_color := Color8(3, 11, 26):
	set(v): shadow_color = v; emit_changed()

@export_group("Contact shadow")
## Opacity of the contact shadow under the building.
@export_range(0.0, 1.0, 0.01) var contact_opacity := 1.0:
	set(v): contact_opacity = v; emit_changed()


## Cast shadow transform relative to the ground point (core_shadow_editor.html drawShadow():
## translate(pivot + d) · rotate · skewX · scale · translate(−pivot); the last step is the sprite offset).
func cast_transform() -> Transform2D:
	var ks := Transform2D(Vector2(scale_x, 0.0), Vector2(skew_x * scale_y, scale_y), Vector2.ZERO)
	return Transform2D(deg_to_rad(rotation_deg), shift) * ks
