@tool
class_name CliffBlocks
extends Resource
## The drawn cliff blocks: one atlas (art/maps/cliffs/cliff_atlas.png) and where each block sits in it.
## Written by art/maps/cliffs/cliff_atlas.py (game/core/cliff_blocks.tres) — do not edit by hand, it is
## overwritten when the atlas is rebuilt. Look settings live in CliffRig.

enum Group { WALL, ROCK }
enum Kind { LOW, MID, TALL, PEAK }

@export var atlas: Texture2D
## Block rectangles in the atlas, px.
@export var rects: Array[Rect2] = []
## Ground point of each block in its rectangle (the foot of the rock face), px.
@export var grounds := PackedVector2Array()
## Top of each block (where decor stands), y in its rectangle, px: median top of the middle 60 % of its width,
## so a narrow spire does not count.
@export var tops := PackedFloat32Array()
## Atlas px per map px of each block (Codex drew walls ×4, rocks ×3).
@export var texels := PackedFloat32Array()
## Group per block (Group: wall columns for the map edge, natural rock for the inside).
@export var groups := PackedByteArray()
## Height kind per block (Kind; wall blocks are TALL).
@export var kinds := PackedByteArray()


## Indices of the blocks of a group (and kind, −1 = any kind).
func pick_list(group: int, kind := -1) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in rects.size():
		if groups[i] == group and (kind < 0 or kinds[i] == kind):
			out.append(i)
	return out
