@tool
class_name MenuDroneRig
extends Resource
## Shared look of the menu drones (one .tres for all: change it — every drone changes).
## Defaults = the approved HTML draft (art/drafts/menu/drones.js, 2026-10-09).
## Lengths are background px (art/objects/ui/main_menu/menu_bg.webp, 1672×941).

@export var texture: Texture2D:
	set(v): texture = v; emit_changed()
## Drone width on the background, px.
@export_range(20, 200, 1) var width := 78.0:
	set(v): width = v; emit_changed()
## Flight height above the ground, px.
@export_range(0, 200, 1) var fly_h := 50.0:
	set(v): fly_h = v; emit_changed()
## Seconds to take off / land.
@export_range(0.1, 3.0, 0.05) var climb := 0.7:
	set(v): climb = v; emit_changed()

@export_group("Motion")
## Lean into the flight direction: radians per px/s of horizontal speed, and its limit.
@export_range(0.0, 0.01, 0.0001) var tilt_per_speed := 1.0 / 900.0:
	set(v): tilt_per_speed = v; emit_changed()
@export_range(0.0, 0.6, 0.01) var max_tilt := 0.16:
	set(v): max_tilt = v; emit_changed()
## Hover bob in the air: amplitude px, speed rad/s.
@export_range(0.0, 20.0, 0.5) var bob_amp := 3.0:
	set(v): bob_amp = v; emit_changed()
@export_range(0.0, 10.0, 0.1) var bob_speed := 3.1:
	set(v): bob_speed = v; emit_changed()

@export_group("Thrusters")
## Nozzles: offset from the sprite bottom centre, × sprite width / height (measured on drone.png).
@export var nozzles := PackedVector2Array([Vector2(-0.366, -0.27), Vector2(0.012, 0.0), Vector2(0.366, -0.30)]):
	set(v): nozzles = v; emit_changed()
@export var glow_color := Color(0.59, 0.9, 1.0):
	set(v): glow_color = v; emit_changed()
@export_range(1.0, 40.0, 0.5) var glow_radius := 9.0:
	set(v): glow_radius = v; emit_changed()
## Glow strength sitting / flying, and pulse speed rad/s.
@export_range(0.0, 1.0, 0.01) var glow_sit := 0.15:
	set(v): glow_sit = v; emit_changed()
@export_range(0.0, 1.0, 0.01) var glow_fly := 0.75:
	set(v): glow_fly = v; emit_changed()
@export_range(0.0, 40.0, 0.5) var glow_pulse := 17.0:
	set(v): glow_pulse = v; emit_changed()

@export_group("Shadow ellipse")
## Size × drone width; alpha on the ground / at flight height; shrink at flight height.
@export_range(0.1, 1.0, 0.01) var shadow_w := 0.46:
	set(v): shadow_w = v; emit_changed()
@export_range(0.05, 0.5, 0.01) var shadow_h := 0.17:
	set(v): shadow_h = v; emit_changed()
@export_range(0.0, 1.0, 0.01) var shadow_alpha_ground := 0.38:
	set(v): shadow_alpha_ground = v; emit_changed()
@export_range(0.0, 1.0, 0.01) var shadow_alpha_air := 0.22:
	set(v): shadow_alpha_air = v; emit_changed()
@export_range(0.0, 0.9, 0.01) var shadow_shrink := 0.35:
	set(v): shadow_shrink = v; emit_changed()
