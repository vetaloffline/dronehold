extends Node2D
## Game entry: the map, the camera (starts over the core) and the debug HUD.

## The map of this scene (game/main.tscn: MapA — game/maps/map_a/map_a.tscn).
@export var map: GameMap
@onready var _map := map
@onready var _camera := $Camera as MapCamera


func _ready() -> void:
	for o in _map.objects():
		if o.is_in_group("enemy_target"):
			_camera.position = o.position
			break
