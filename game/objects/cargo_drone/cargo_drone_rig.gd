@tool
class_name CargoDroneRig
extends Resource
## Shared look and numbers of the cargo drones (one .tres for all).
## Views: art/objects/units/drone/drone_000…315.png (8 headings, 0° = right, 90° = towards the camera),
## canvas 321×295, the drone's middle at the canvas centre.

@export var views: Array[Texture2D] = []

@export_group("Size")
## Sprite scale on the map (drone ≈ 1.6 cells wide).
@export_range(0.05, 0.6, 0.005) var map_scale := 0.17
## Flight height above the ground, map px.
@export_range(0.0, 150.0, 1.0) var fly_h := 38.0
## Seconds to take off / land.
@export_range(0.1, 3.0, 0.05) var climb := 0.45
## Map px from the ground to the drone's middle when it sits (the nozzles touch the ground).
@export_range(0.0, 60.0, 0.5) var rest_lift := 22.0

@export_group("Work")
## Flight speed, map px/s.
@export_range(10.0, 800.0, 5.0) var speed := 150.0
## Crystals carried per trip (the drone's own storage).
@export_range(1, 100, 1) var capacity := 5
## Seconds sitting on the pad while loading at a drill / unloading at a store.
@export_range(0.0, 5.0, 0.05) var load_time := 0.8
@export_range(0.0, 5.0, 0.05) var unload_time := 0.6
## How often a waiting or idle drone looks again for work / a free pad, s.
@export_range(0.05, 2.0, 0.05) var think_every := 0.25
## Idle drones hang around the core at this distance, cells.
@export_range(1.0, 15.0, 0.5) var idle_radius := 5.0
## A drone waiting for a pad hangs this far from it, map px.
@export_range(0.0, 200.0, 1.0) var wait_offset := 40.0

@export_group("Motion")
@export_range(0.0, 20.0, 0.5) var bob_amp := 2.5
@export_range(0.0, 10.0, 0.1) var bob_speed := 3.2

@export_group("Shadow ellipse")
## Size × the drone's width on the map; alpha on the ground / at flight height.
@export_range(0.1, 1.0, 0.01) var shadow_w := 0.42
@export_range(0.05, 0.5, 0.01) var shadow_h := 0.16
@export_range(0.0, 1.0, 0.01) var shadow_alpha_ground := 0.4
@export_range(0.0, 1.0, 0.01) var shadow_alpha_air := 0.22
