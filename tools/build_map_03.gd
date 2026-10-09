extends SceneTree
## Builds res://game/maps/map_03/map_03.tscn from the art: ground chunks, grid from the layout,
## corruption, World (Y-sort), spawns, swarm, and the objects.
##   godot --headless --path . --script res://tools/build_map_03.gd [-- map_03.json]
## Objects: from a map JSON saved by the old HTML editor («Зберегти map.json», version 4), or —
## without it — the editor's demo() placement (nearest free cell to the same map fractions).
## After this the scene is edited in Godot; re-running overwrites it.

const OUT := "res://game/maps/map_03/map_03.tscn"
const LAYOUT := "res://art/maps/map_03/map_03_layout.png"
const GROUND_DIR := "res://game/maps/map_03/ground/"
const CHUNK := 2048
const VEIN_SLOT := Vector2i(3, -1)
const SCENES := {
	"core": "res://game/objects/core/core.tscn",
	"vein": "res://game/objects/crystal_vein/crystal_vein.tscn",
	"drill": "res://game/objects/drill/drill.tscn",
	"turret": "res://game/objects/machine_gun/machine_gun.tscn",
	"launcher": "res://game/objects/grenade_launcher/grenade_launcher.tscn",
	"spawn": "res://game/core/spawn_point.tscn",
	"prop": "res://game/core/prop.tscn",
}
const FOOT := {"core": Vector2i(3, 3), "vein": Vector2i(3, 3), "spawn": Vector2i(1, 1), "turret": Vector2i(1, 1),
	"launcher": Vector2i(1, 1), "drill": Vector2i(1, 1), "wall": Vector2i(1, 1), "relay": Vector2i(1, 1)}

var grid: MapGrid
var occ := {}
var slots := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var json_path := args[0] if args.size() > 0 else ""
	var root := GameMap.new()
	root.name = "Map03"
	root.layout = load(LAYOUT)
	root.rebuild_grid()
	grid = root.grid
	_add_ground(root)
	_add_rot(root)
	var shadows := Node2D.new()
	shadows.name = "Shadows"
	shadows.z_index = -1
	_own(root, shadows, root)
	var world := Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	_own(root, world, root)
	var spawns := Node2D.new()
	spawns.name = "Spawns"
	_own(root, spawns, root)
	var overlay := Node2D.new()
	overlay.name = "Overlay"
	overlay.set_script(load("res://game/core/grid_overlay.gd"))
	overlay.z_index = 10
	_own(root, overlay, root)
	var swarm := Swarm.new()
	swarm.name = "Swarm"
	_own(root, swarm, root)
	if json_path != "":
		_from_json(root, json_path)
	else:
		_demo(root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT)
	print("build_map_03: saved %s, err %d, objects %d" % [OUT, err, root.objects().size()])
	root.free()
	quit(0 if err == OK else 1)


func _own(root: Node, n: Node, parent: Node) -> void:
	parent.add_child(n)
	n.owner = root


func _add_ground(root: GameMap) -> void:
	var g := Node2D.new()
	g.name = "Ground"
	# Below the objects' shadows (z −1) and the corruption (z −2).
	g.z_index = -3
	_own(root, g, root)
	for r in 2:
		for c in 3:
			var s := Sprite2D.new()
			s.name = "Ground_%d_%d" % [r, c]
			s.texture = load(GROUND_DIR + "ground_%d_%d.webp" % [r, c])
			s.centered = false
			s.position = Vector2(c * CHUNK, r * CHUNK)
			_own(root, s, g)


func _add_rot(root: GameMap) -> void:
	var rect := ColorRect.new()
	rect.name = "Rot"
	# The ground (5016×2823) is a bit larger than the grid (78×58 cells): cover all of it.
	rect.size = Vector2(5016, 2823)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://game/core/rot.gdshader")
	mat.set_shader_parameter("blotch_noise", _noise(11, FastNoiseLite.FRACTAL_FBM, 0.006))
	mat.set_shader_parameter("vein_noise", _noise(23, FastNoiseLite.FRACTAL_RIDGED, 0.004))
	rect.material = mat
	rect.z_index = -2
	_own(root, rect, root)


func _noise(seed_value: int, fractal: int, freq: float) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = fractal
	n.frequency = freq
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 512
	t.height = 512
	t.seamless = true
	t.generate_mipmaps = true
	return t


func _place(root: GameMap, kind: String, cell: Vector2i, extra := {}) -> Node:
	var path: String = SCENES.get(kind, "")
	if path == "" or not ResourceLoader.exists(path):
		push_warning("build_map_03: no scene for %s (%s), skipped" % [kind, path])
		return null
	var n := (load(path) as PackedScene).instantiate()
	for k in extra:
		n.set(k, extra[k])
	if kind == "prop":
		# Outside the editor the `kind` setter does not read props.json — do it here.
		n.call("_load_kind")
	n.set("cell", cell)
	n.name = "%s_%d_%d" % [kind.capitalize().replace(" ", ""), cell.x, cell.y]
	_own(root, n, root.get_node("Spawns") if kind == "spawn" else root.world())
	if kind != "spawn" and not (kind == "prop" and extra.get("decor", false)):
		var f: Vector2i = n.get_footprint() if n.has_method("get_footprint") else FOOT.get(kind, Vector2i.ONE)
		for r in f.y:
			for c in f.x:
				occ[cell + Vector2i(c, r)] = kind
	if kind == "vein":
		slots[cell + VEIN_SLOT] = true
	return n


func _can_place(kind: String, c: int, r: int) -> bool:
	var f: Vector2i = FOOT[kind]
	if kind == "drill":
		return slots.has(Vector2i(c, r)) and not occ.has(Vector2i(c, r))
	for y in range(r, r + f.y):
		for x in range(c, c + f.x):
			if not grid.inside(x, y):
				return false
			if kind != "spawn" and grid.is_blocked(x, y):
				return false
			if occ.has(Vector2i(x, y)):
				return false
			if kind != "spawn" and kind != "vein" and kind != "core" and slots.has(Vector2i(x, y)):
				return false
	return true


## map_03_editor.html demo(): nearest placeable cell to (fx, fy) of the map, square spiral.
func _put(root: GameMap, kind: String, fx: float, fy: float) -> Node:
	var c0 := int(round(fx * grid.cols))
	var r0 := int(round(fy * grid.rows))
	for ring in maxi(grid.cols, grid.rows):
		for dr in range(-ring, ring + 1):
			for dc in range(-ring, ring + 1):
				if maxi(absi(dc), absi(dr)) != ring:
					continue
				var c := c0 + dc
				var r := r0 + dr
				if kind == "vein" and not _can_place("turret", c + VEIN_SLOT.x, r + VEIN_SLOT.y):
					continue
				if _can_place(kind, c, r):
					return _place(root, kind, Vector2i(c, r))
	return null


func _demo(root: GameMap) -> void:
	_put(root, "core", 0.3, 0.55)
	var v := _put(root, "vein", 0.2, 0.75)
	_put(root, "vein", 0.62, 0.3)
	if v:
		_place(root, "drill", (v.get("cell") as Vector2i) + VEIN_SLOT)
	_put(root, "turret", 0.36, 0.5)
	_put(root, "launcher", 0.33, 0.62)
	_put(root, "spawn", 0.97, 0.5)
	_put(root, "spawn", 0.5, 0.02)


func _from_json(root: GameMap, path: String) -> void:
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (j is Dictionary):
		push_error("build_map_03: can not read %s" % path)
		return
	for o in j.get("objects", []):
		_place(root, String(o["type"]), Vector2i(int(o["cell"][0]), int(o["cell"][1])))
	for o in j.get("test_buildings", []):
		_place(root, String(o["type"]), Vector2i(int(o["cell"][0]), int(o["cell"][1])))
	for o in j.get("props", []):
		_place(root, "prop", Vector2i(int(o["cell"][0]), int(o["cell"][1])), {"kind": String(o["prop"]), "decor": not o.get("blocks", true)})
