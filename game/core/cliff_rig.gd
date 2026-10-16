@tool
class_name CliffRig
extends Resource
## How cliffs look on the map (shared by every Cliffs node: game/core/cliff_rig.tres). Change a value in the
## Inspector — every cliff rebuilds at once.

@export var blocks: CliffBlocks:
	set(v): blocks = v; emit_changed()

@export_group("Size")
## Block size on the map ×, wall columns.
@export_range(0.3, 2.0, 0.01) var wall_scale := 1.0:
	set(v): wall_scale = v; emit_changed()
## Block size on the map ×, natural rock.
@export_range(0.3, 2.0, 0.01) var rock_scale := 1.0:
	set(v): rock_scale = v; emit_changed()
## Random size spread per cell (0.12 = ±12 %), so a row is not a ruler.
@export_range(0.0, 0.5, 0.01) var jitter_size := 0.12:
	set(v): jitter_size = v; emit_changed()
## Random shift per cell, map px.
@export_range(0.0, 16.0, 0.5, "suffix:px") var jitter_x := 7.0:
	set(v): jitter_x = v; emit_changed()
@export_range(0.0, 12.0, 0.5, "suffix:px") var jitter_y := 3.0:
	set(v): jitter_y = v; emit_changed()

@export_group("Rock height")
## Size of the humps and dips along a ridge, cells (noise grid step).
@export_range(1.0, 16.0, 0.5) var hump_cells := 4.0:
	set(v): hump_cells = v; emit_changed()
## Noise above this on the top of a hump → a peak.
@export_range(0.0, 1.0, 0.01) var peak_noise := 0.6:
	set(v): peak_noise = v; emit_changed()
## A peak is the highest cell within this many cells (fewer = more peaks).
@export_range(1, 8) var peak_radius := 3:
	set(v): peak_radius = v; emit_changed()
## Noise below this deep in a ridge → a dip (mid block instead of tall).
@export_range(0.0, 1.0, 0.01) var dip_noise := 0.3:
	set(v): dip_noise = v; emit_changed()
## Change it to get other humps and peaks from the same cells.
@export var hump_seed := 0:
	set(v): hump_seed = v; emit_changed()

@export_group("Decor on top")
## Trees and bushes on a cliff cell stand this far below the block's top edge, map px.
@export_range(0.0, 40.0, 0.5, "suffix:px") var stand_inset := 10.0:
	set(v): stand_inset = v; emit_changed()
