extends SceneTree
## Builds map A from its layout (art/maps/map_a/map_a.json, made by art/maps/map_a/map_a_natural.py):
##   game/maps/map_a/map_a.tscn       the map: tiled ground, rot, cliff cells (wall at the edge, rock inside)
##                                    + Cliffs, core, veins with drill side, slime / lasher spawns, swarms;
##                                    rot, overlay and swarm settings copied from map_03
##   game/maps/map_a/map_a_grid.tres  an all-ground 128×96 grid (cliffs turn into rock in the game)
##   (game/main.tscn plays this map: its MapA node is an instance of map_a.tscn)
## Overwrites both — hand edits made in Godot are lost. Editor open → run on a copy of the repo
## (.claude/rules/editor-and-perf.md):
##   godot --headless --path <copy> --script res://tools/build_map_a.gd


func own(n: Node, owner_node: Node) -> void:
	n.owner = owner_node
	if n.scene_file_path != "":
		return
	for c in n.get_children():
		own(c, owner_node)


func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/maps/map_a/map_a.json"))
	var cols: int = data["size"][0]
	var rows: int = data["size"][1]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://game/maps/map_a"))
	print("grid ", ResourceSaver.save(MapGrid.open(cols, rows), "res://game/maps/map_a/map_a_grid.tres"))
	var grid := load("res://game/maps/map_a/map_a_grid.tres") as MapGrid

	var m03 := (load("res://game/maps/map_03/map_03.tscn") as PackedScene).instantiate()
	var map := GameMap.new()
	map.name = "MapA"
	map.grid = grid
	var ground := TiledGround.new()
	ground.name = "Ground"
	ground.z_index = -3
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ground.texture = load("res://art/maps/ground/ground_dirt.png")
	map.add_child(ground)
	var rot := m03.get_node("Rot").duplicate() as ColorRect
	rot.offset_right = cols * MapGrid.CELL.x
	rot.offset_bottom = rows * MapGrid.CELL.y
	map.add_child(rot)
	var shadows := Node2D.new()
	shadows.name = "Shadows"
	shadows.z_index = -1
	map.add_child(shadows)
	var world := Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	map.add_child(world)
	var cells := (load("res://game/core/cliff_cells.tscn") as PackedScene).instantiate() as CliffCells
	map.add_child(cells)
	for c in data["wall"]:
		cells.set_cell(Vector2i(c[0], c[1]), 0, Vector2i(0, 0))
	for c in data["rock"]:
		cells.set_cell(Vector2i(c[0], c[1]), 0, Vector2i(1, 0))
	var cliffs := (load("res://game/core/cliffs.tscn") as PackedScene).instantiate()
	world.add_child(cliffs)
	var core := (load("res://game/objects/core/core.tscn") as PackedScene).instantiate() as MapObject
	core.name = "Core"
	core.cell = Vector2i(data["core"][0], data["core"][1])
	world.add_child(core)
	var k := 1
	for v in data["veins"]:
		var vein := (load("res://game/objects/crystal_vein/crystal_vein.tscn") as PackedScene).instantiate() as CrystalVein
		vein.name = "Vein%d" % k
		k += 1
		vein.drill_side = CrystalVein.Side.LEFT if v[2] == "L" else CrystalVein.Side.RIGHT
		vein.cell = Vector2i(v[0], v[1])
		world.add_child(vein)
	var spawns := Node2D.new()
	spawns.name = "Spawns"
	map.add_child(spawns)
	k = 1
	for s in data["slime"]:
		var sp := (load("res://game/core/spawn_point.tscn") as PackedScene).instantiate() as MapObject
		sp.name = "Spawn%d" % k
		k += 1
		sp.cell = Vector2i(s[0], s[1])
		spawns.add_child(sp)
	k = 1
	for s in data["lasher"]:
		var sp := (load("res://game/core/lasher_spawn_point.tscn") as PackedScene).instantiate() as MapObject
		sp.name = "LasherSpawn%d" % k
		k += 1
		sp.cell = Vector2i(s[0], s[1])
		spawns.add_child(sp)
	for n in ["Overlay", "Swarm", "LasherSwarm"]:
		var d := m03.get_node(n).duplicate()
		if "map" in d:
			d.set("map", map)
		map.add_child(d)
	for c in map.get_children():
		own(c, map)
	var ps := PackedScene.new()
	print("pack map ", ps.pack(map))
	print("save map ", ResourceSaver.save(ps, "res://game/maps/map_a/map_a.tscn"))
	map.free()
	m03.free()
	quit(0)
