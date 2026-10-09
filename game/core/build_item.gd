@tool
class_name BuildItem
extends Resource
## One card of the build menu: what it builds and what it costs (cost is a dictionary, AGENTS.md).

@export var title := ""
@export var scene: PackedScene
@export var cost := {"crystal": 50}
## Only into the free slot of a crystal vein (the drill), not on any free cells.
@export var vein_slot_only := false
