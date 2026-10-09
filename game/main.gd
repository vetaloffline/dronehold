extends Node2D
## Game entry: the map, the camera (starts over the core) and the debug HUD.

@onready var _map := $Map03 as GameMap
@onready var _camera := $Camera as MapCamera


func _ready() -> void:
	for o in _map.objects():
		if o.is_in_group("enemy_target"):
			_camera.position = o.position
			break
