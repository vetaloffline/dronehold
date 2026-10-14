@tool
class_name SpawnPoint
extends MapObject
## Where enemies appear. Visible only in the editor: red marker — slimes, orange — lashers
## (lasher_spawn_point.tscn). Each crowd reads only its own points (GameMap.spawn_points(enemy)).

const COLORS := {"slime": Color(1, 0.3, 0.3), "lasher": Color(1, 0.6, 0.1)}

## Which crowd spawns here: Swarm (slimes) or LasherSwarm.
@export_enum("slime", "lasher") var enemy := "slime":
	set(v):
		enemy = v
		queue_redraw()


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
	var col: Color = COLORS.get(enemy, Color.WHITE)
	draw_rect(r, Color(col, 0.35))
	draw_rect(r, Color(col, 0.9), false, 2.0)
	draw_line(Vector2(-12, -12), Vector2(12, 12), Color.WHITE, 2.0)
	draw_line(Vector2(-12, 12), Vector2(12, -12), Color.WHITE, 2.0)
	if enemy == "lasher":
		# Lasher marker: a second ring inside the box, so the two kinds differ beyond colour.
		draw_rect(r.grow(-6.0), Color(col, 0.9), false, 2.0)
