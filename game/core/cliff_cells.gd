@tool
class_name CliffCells
extends TileMapLayer
## Where the cliffs are: cells painted in the Godot editor (tile set cliff_cells.tres — one red tile of
## 32×24, the grid cell). Cliffs (game/core/cliffs.gd) builds the rock from these cells.
## TileMapLayer.changed does not fire on erase_cell / tile_map_data (checked headless on 4.7.2), but the
## engine calls _update_cells after every cell change (paint, erase, clear, undo) — so it is the signal.

signal cells_changed


func _update_cells(_coords: Array[Vector2i], _forced_cleanup: bool) -> void:
	cells_changed.emit()
