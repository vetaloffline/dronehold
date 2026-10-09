@tool
class_name SpawnPoint
extends MapObject
## Where enemies appear. Visible only in the editor (red marker).


func _enter_tree() -> void:
	add_to_group("enemy_spawn", true)
	super._enter_tree()


func get_footprint() -> Vector2i:
	return Vector2i(2, 2)


func _ready() -> void:
	visible = Engine.is_editor_hint()


func _draw() -> void:
	var size := Vector2(get_footprint()) * MapGrid.CELL
	var r := Rect2(-size * 0.5, size)
	draw_rect(r, Color(1, 0.3, 0.3, 0.35))
	draw_rect(r, Color(1, 0.3, 0.3, 0.9), false, 2.0)
	draw_line(Vector2(-12, -12), Vector2(12, 12), Color.WHITE, 2.0)
	draw_line(Vector2(-12, 12), Vector2(12, -12), Color.WHITE, 2.0)
