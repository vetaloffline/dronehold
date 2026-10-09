@tool
class_name Prop
extends MapObject
## Decor from art/maps/props (rocks, trees, bushes). Pick `kind` in the Inspector.
## Placement = map_03_editor.html drawObj() for props: sprite scale = w·cell_w·fill / body_w,
## ground point at the footprint centre, 0.85 of its height down.
## The data (texture, ground point, size) is copied from props.json when `kind` changes and is
## saved in the scene, so the game never reads the JSON.

const PROPS_JSON := "res://art/maps/props/props.json"
const PROPS_DIR := "res://art/maps/props/"

@export_enum("rock_s1", "rock_s2", "rock_s3", "rock_m1", "rock_m2", "rock_m3", "rock_spire", "rock_mesa", "rock_pit", "tree_tall", "tree_mid", "tree_small", "trees_3", "trees_5", "tree_dead", "bush_round", "bush_wide", "stump")
var kind := "rock_s1":
	set(v):
		kind = v
		if Engine.is_editor_hint():
			_load_kind()
		_apply()
## Decor does not occupy cells (you can build over it).
@export var decor := false
## Size of the body relative to its footprint (map editor «propFill»).
@export_range(0.3, 2.0, 0.01) var fill := 1.0:
	set(v): fill = v; _apply()

@export_group("From props.json")
@export var foot := Vector2i(1, 1)
@export var ground := Vector2(120, 122)
@export var body_w := 136.0
@export var texture: Texture2D


func get_footprint() -> Vector2i:
	return foot


func get_map_scale() -> float:
	return foot.x * MapGrid.CELL.x * fill / maxf(1.0, body_w)


func occupies_cells() -> bool:
	return not decor


func get_path_cost() -> float:
	return 0.0 if decor else FlowField.INF


func ground_point_for(c: Vector2i) -> Vector2:
	return Vector2((c.x + foot.x * 0.5) * MapGrid.CELL.x, (c.y + foot.y * 0.85) * MapGrid.CELL.y)


func cell_for_point(p: Vector2) -> Vector2i:
	return Vector2i(int(round(p.x / MapGrid.CELL.x - foot.x * 0.5)), int(round(p.y / MapGrid.CELL.y - foot.y * 0.85)))


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if texture == null and Engine.is_editor_hint():
		_load_kind()
	_apply()


func _load_kind() -> void:
	var txt := FileAccess.get_file_as_string(PROPS_JSON)
	var data = JSON.parse_string(txt)
	if not (data is Array):
		return
	for p in data:
		if p.get("name") == kind:
			foot = Vector2i(int(p["foot"][0]), int(p["foot"][1]))
			ground = Vector2(p["ground"][0], p["ground"][1])
			body_w = float(p["body_w"])
			texture = load(PROPS_DIR + String(p["file"])) as Texture2D
			return


func _apply() -> void:
	_place()
	queue_redraw()


func _draw() -> void:
	if texture:
		draw_texture(texture, -ground)
