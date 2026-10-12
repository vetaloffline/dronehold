@tool
class_name RelayRig
extends BlockRig
## The relay: game numbers of BlockRig (hp, path cost, cleared radius, store) + its art — a base
## sprite with its ground shadow and a radar dish on the mast top in N views that spins slowly
## (views switch by angle, like a turret head in "snap" mode). One relay_rig.tres for every relay.
## Art: art/objects/buildings/relay/ (approved 2026-10-12, cut by relay_cut.py; dish views —
## dish_fit.py). "px спрайта" = px of the base PNG.

@export_group("Art")
@export var base: Texture2D:
	set(v): base = v; emit_changed()
## Ground shadow of the base (Codex), same canvas as `base`.
@export var base_shadow: Texture2D:
	set(v): base_shadow = v; emit_changed()
@export_range(0.0, 1.5, 0.01) var base_shadow_alpha := 1.0:
	set(v): base_shadow_alpha = v; emit_changed()
## Ground point (footprint centre) in the base PNG, px спрайта.
@export var ground := Vector2(508, 655):
	set(v): ground = v; emit_changed()
## Base PNG px → map px (the base is 762 px wide for a 2-cell footprint: 64 / 762).
@export_range(0.02, 0.5, 0.001) var map_scale := 0.084:
	set(v): map_scale = v; emit_changed()

@export_group("Dish")
## Dish views around the circle, in the order of `dish_azimuths`.
@export var dishes: Array[Texture2D] = []:
	set(v): dishes = v; emit_changed()
## Ground azimuth of each view, ° (0 = right, 90 = to the camera), measured on the art (dish_fit.py).
## Empty = evenly 360° / N from 0.
@export var dish_azimuths := PackedFloat32Array():
	set(v): dish_azimuths = v; emit_changed()
## Turning point of the dish in every view PNG (turntable bottom centre), dish px.
@export var dish_pivot := Vector2(280, 400):
	set(v): dish_pivot = v; emit_changed()
## Where the dish turns on the mast (collar cap centre), px спрайта.
@export var housing := Vector2(512, 61):
	set(v): housing = v; emit_changed()
## Spin speed, °/s (positive = counter-clockwise seen from above: right → away → left → to camera).
@export_range(-360.0, 360.0, 1.0) var spin_speed := 30.0:
	set(v): spin_speed = v; emit_changed()
## Dish angle when the relay appears (and in the build menu card), °.
@export_range(0.0, 360.0, 0.5) var start_angle := 29.2:
	set(v): start_angle = v; emit_changed()

@export_group("Dish shadow")
## The dish's shadow is the current view's sprite in black, flattened and shifted onto the slab
## (sun upper right → falls left), drawn over the base and under the dish.
@export_range(0.0, 1.0, 0.01) var dish_shadow_alpha := 0.3:
	set(v): dish_shadow_alpha = v; emit_changed()
## Shift from the dish to its shadow, px спрайта.
@export var dish_shadow_offset := Vector2(-190, 470):
	set(v): dish_shadow_offset = v; emit_changed()
## Vertical squash of the shadow (lies on the ground).
@export_range(0.1, 1.0, 0.01) var dish_shadow_squash := 0.5:
	set(v): dish_shadow_squash = v; emit_changed()


func view_count() -> int:
	return dishes.size()


func view_angle(i: int) -> float:
	if dish_azimuths.size() == dishes.size() and i < dish_azimuths.size():
		return dish_azimuths[i]
	return i * 360.0 / maxi(1, dishes.size())


## The view whose azimuth is nearest to `deg`.
func nearest_view(deg: float) -> int:
	var best := 0
	var best_d := INF
	for i in dishes.size():
		var d := absf(angle_difference(deg_to_rad(deg), deg_to_rad(view_angle(i))))
		if d < best_d:
			best_d = d
			best = i
	return best
