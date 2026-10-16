@tool
class_name Prop
extends MapObject
## Decor from art/maps/props (rocks, trees, bushes, rock decor for cliffs: spires, rockfall, arch…). Pick `kind`
## in the Inspector.
## Placement = map_03_editor.html drawObj() for props: sprite scale = w·cell_w·fill / body_w,
## ground point at the footprint centre, 0.85 of its height down.
## The data (texture, ground point, size) is copied from props.json when `kind` changes and is
## saved in the scene, so the game never reads the JSON.
## On a cliff cell (Cliffs, docs/concept.md «Скелі») it stands on the top of that cell's rock block: drawn
## `cliff_lift` px higher (Cliffs.top_y_at, the mean over its cliff cells, + `lift`), and its ground point
## moves to the south edge of its lowest cliff row − 0.5 px, so Y-sort draws it after that row of blocks
## and before the next one. Cliffs calls refresh_cliff() after every rebuild.

const PROPS_JSON := "res://art/maps/props/props.json"
const PROPS_DIR := "res://art/maps/props/"
## Kinds the drones fly round when `flight` is Auto: trees and big rocks (rule of 2026-10-09).
const FLY_ROUND_KINDS := ["tree_tall", "tree_mid", "tree_small", "trees_3", "trees_5", "tree_dead",
	"rock_m1", "rock_m2", "rock_m3", "rock_spire", "rock_mesa",
	"cliff_spire", "cliff_twin_spires", "cliff_crest", "cliff_rockfall", "cliff_slab", "cliff_split", "cliff_ledge",
	"cliff_arch"]

@export_enum("rock_s1", "rock_s2", "rock_s3", "rock_m1", "rock_m2", "rock_m3", "rock_spire", "rock_mesa", "rock_pit", "tree_tall", "tree_mid", "tree_small", "trees_3", "trees_5", "tree_dead", "bush_round", "bush_wide", "stump", "cliff_spire", "cliff_twin_spires", "cliff_crest", "cliff_rockfall", "cliff_slab", "cliff_split", "cliff_scree", "cliff_ledge", "cliff_arch", "cliff_fallen_pillar")
var kind := "rock_s1":
	set(v):
		kind = v
		if Engine.is_editor_hint():
			_load_kind()
		_apply()
## Decor does not occupy cells (you can build over it).
@export var decor := false
## Cargo drones fly round it (tall trees, big rocks) or over it (small stones, bushes, stumps).
## Auto = by `kind` (FLY_ROUND_KINDS).
@export_enum("Auto", "Fly round", "Fly over") var flight := 0
## Size of the body relative to its footprint (map editor «propFill»).
@export_range(0.3, 2.0, 0.01) var fill := 1.0:
	set(v): fill = v; _apply()
## Fine-tune of the height on a cliff, map px (+ = higher). Nothing on open ground.
@export_range(-40.0, 40.0, 0.5, "suffix:px") var lift := 0.0:
	set(v): lift = v; _apply()

@export_group("From props.json")
@export var foot := Vector2i(1, 1)
@export var ground := Vector2(120, 122)
@export var body_w := 136.0
@export var texture: Texture2D


func get_footprint() -> Vector2i:
	return foot


## Cargo drones do not fly over its cells (DroneNav).
func blocks_flight() -> bool:
	if flight == 1:
		return true
	if flight == 2:
		return false
	return kind in FLY_ROUND_KINDS


func get_map_scale() -> float:
	return foot.x * MapGrid.CELL.x * fill / maxf(1.0, body_w)


func occupies_cells() -> bool:
	return not decor


func get_path_cost() -> float:
	return 0.0 if decor else FlowField.INF


func ground_point_for(c: Vector2i) -> Vector2:
	var p := Vector2((c.x + foot.x * 0.5) * MapGrid.CELL.x, (c.y + foot.y * 0.85) * MapGrid.CELL.y)
	var top := _cliff_top(c)
	if top.y >= 0:
		# After the row of cliff blocks it stands on (row nodes sit at the south edge − 1 px).
		p.y = (top.y + 1) * MapGrid.CELL.y - 0.5
	return p


func cell_for_point(p: Vector2) -> Vector2i:
	var c := Vector2i(int(round(p.x / MapGrid.CELL.x - foot.x * 0.5)), int(round(p.y / MapGrid.CELL.y - foot.y * 0.85)))
	# On a cliff the ground point is moved down (ground_point_for): look one row up too.
	for d in [Vector2i.ZERO, Vector2i(0, -1)]:
		if ground_point_for(c + d).distance_to(p) < 1.0:
			return c + d
	return c


## Map px the sprite is drawn above its ground point (on a cliff block); 0 on open ground.
var cliff_lift := 0.0


## Where it would stand on cliffs at cell `c`: x = map y of the block tops (mean over its cliff cells),
## y = its lowest cliff row; y = −1 when none of its cells is a cliff.
func _cliff_top(c: Vector2i) -> Vector2:
	var cl := Cliffs.of_map(_map())
	if cl == null:
		return Vector2(0.0, -1.0)
	var sum := 0.0
	var n := 0
	var row := -1
	for r in foot.y:
		for q in foot.x:
			var t := cl.top_y_at(c + Vector2i(q, r))
			if not is_nan(t):
				sum += t
				n += 1
				row = maxi(row, c.y + r)
	return Vector2(sum / n, row) if n > 0 else Vector2(0.0, -1.0)


func _map() -> GameMap:
	var n := get_parent()
	while n and not (n is GameMap):
		n = n.get_parent()
	return n as GameMap


## Look again whether it stands on a cliff (Cliffs calls it after placing its blocks).
func refresh_cliff() -> void:
	_apply()


func _place() -> void:
	super()
	var top := _cliff_top(cell)
	cliff_lift = position.y - top.x + lift if top.y >= 0 else 0.0


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
			# props.json `foot` counts 64×48 cells (old HTML editor); the grid is 32×24. Newer entries (rock decor,
			# art/maps/rock_decor/rock_decor_props.py) give `foot_cells` in 32×24 cells — odd sizes fit there.
			if p.has("foot_cells"):
				foot = Vector2i(int(p["foot_cells"][0]), int(p["foot_cells"][1]))
			else:
				foot = Vector2i(int(p["foot"][0]), int(p["foot"][1])) * 2
			ground = Vector2(p["ground"][0], p["ground"][1])
			body_w = float(p["body_w"])
			texture = load(PROPS_DIR + String(p["file"])) as Texture2D
			return


func _apply() -> void:
	_place()
	queue_redraw()


func _draw() -> void:
	if texture:
		draw_texture(texture, -ground - Vector2(0.0, cliff_lift / maxf(0.001, get_map_scale())))
