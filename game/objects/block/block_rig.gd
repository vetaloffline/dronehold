@tool
class_name BlockRig
extends Resource
## Numbers and colours of a placeholder building drawn as a plain block over its footprint
## (wall, relay — until they get art; the wall idea: art/concept/12_wall_idea.png).

@export var footprint := Vector2i(2, 2)
## Block height on the screen, map px.
@export_range(0.0, 120.0, 1.0) var height := 26.0
@export var top_color := Color(0.62, 0.64, 0.68)
@export var side_color := Color(0.38, 0.40, 0.45)
@export var edge_color := Color(0.16, 0.17, 0.2)

@export_group("Game")
@export_range(1.0, 5000.0, 1.0) var max_hp := 300.0
## Extra cost for slimes to pass through a footprint cell (FlowField: a cell costs 1 + this), so they
## walk round unless the detour is longer than this many cells. Turrets and drills: 8.
@export_range(0.0, 1000.0, 1.0) var path_cost := 60.0
## Radius that clears the corruption, cells beyond the footprint.
@export_range(0.0, 30.0, 0.5) var clear_radius := 0.0
## A store (group "storage"): drones bring crystals here as to the core.
@export var store := false
