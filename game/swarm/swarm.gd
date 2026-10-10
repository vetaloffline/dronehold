@tool
class_name Swarm
extends Node
## The enemy crowd of a map. Holds the data (SwarmSim), the shared path (FlowField), the crawl
## table (SlimeCrawl) and the drawing (SwarmView). Turrets find it in group "swarm" and use
## `sim` (nearest / damage / damage_radius).
## Everything here is tunable in the Inspector; in the editor a small crowd crawls as a preview.

signal reached(count: int)

const SLIME_SHADER := preload("res://game/objects/slime/slime.gdshader")
const DEFAULT_RIG := preload("res://game/objects/slime/slime_rig.tres")

@export var map: GameMap
## Shared slime parameters (open to tune look, eyes, blink, crawl).
@export var rig: SlimeRig = DEFAULT_RIG:
	set(v):
		if rig and rig.changed.is_connected(_on_rig_changed):
			rig.changed.disconnect(_on_rig_changed)
		rig = v
		if rig and is_inside_tree():
			rig.changed.connect(_on_rig_changed)
			_on_rig_changed()

@export_group("Count")
## How many slimes are kept alive on the map.
@export_range(0, 100000, 1, "or_greater") var target_count := 50
## New slimes per second until target_count is reached.
@export_range(0.0, 500.0, 0.5, "or_greater") var spawn_per_sec := 8.0
## Array size (memory is reserved once).
@export_range(100, 500000, 100, "or_greater") var capacity := 200000

@export_group("Movement")
## Mean speed, cells/s. The crawl cycle speeds up to match (rate = speed / rig.avg_speed()).
@export_range(0.05, 5.0, 0.01, "or_greater") var speed_cells := 0.72
## ± share of random speed difference between slimes.
@export_range(0.0, 0.6, 0.01) var speed_spread := 0.25
## Slimes per cell before the crowd starts pushing outwards (below it they pile up freely).
## 0 = auto: as many bodies (see `body`) as fit in a cell.
@export_range(0.0, 40.0, 0.25) var cell_capacity := 0.0
## Push out of overfull cells (cells/s per slime over capacity).
@export_range(0.0, 5.0, 0.05) var push_strength := 1.0
## How fast slimes in one cell settle to their spacing (1/s; higher = stiffer).
@export_range(0.0, 60.0, 0.5) var spread_strength := 40.0
## Physical body of a slime, share of the picture width: neighbours keep this far apart, so with
## 0.8 their pictures overlap by 20 % — a pile. 1 = pictures just touch. Below ~0.7 the simple
## physics lets slimes sink into each other (measured: 0.5 → neighbours 0.2–0.4 width apart).
@export_range(0.2, 1.2, 0.01) var body := 0.8
## How strongly slimes pull towards neighbours ahead, up to 2× the spacing away (1/s; 0 = off): the crowd
## gathers into a pile instead of keeping the distance it was spawned with.
@export_range(0.0, 20.0, 0.5) var cohesion := 3.0

## Slimes stand still (targets for testing); they are still drawn and can be shot.
@export var frozen := false

@export_group("Combat")
@export_range(0.1, 1000.0, 0.1, "or_greater") var health := 3.0

@export_group("Editor preview")
@export var preview_in_editor := true
@export_range(0, 500, 1) var editor_count := 20

var sim: SwarmSim
var field: FlowField
var crawl: SlimeCrawl
var view: SwarmView
## Smoothed and last-frame timings, ms (debug HUD).
var sim_ms := 0.0
var view_ms := 0.0
var last_sim_ms := 0.0
var last_view_ms := 0.0
var _spawn_cells: Array[Vector2i] = []
var _spawn_acc := 0.0
var _spawn_i := 0
var _ready_ok := false


func _ready() -> void:
	add_to_group("swarm")
	if map == null:
		map = get_parent() as GameMap
	if map == null or map.grid == null or rig == null:
		push_warning("Swarm: needs a GameMap parent with a grid and a SlimeRig")
		return
	if not rig.changed.is_connected(_on_rig_changed):
		rig.changed.connect(_on_rig_changed)
	map.map_changed.connect(_rebuild_field)
	crawl = SlimeCrawl.new(rig)
	sim = SwarmSim.new()
	sim.setup(capacity if not Engine.is_editor_hint() else maxi(editor_count, 1) * 2, map.grid.cols, map.grid.rows)
	_apply_tunables()
	view = SwarmView.new()
	view.setup(map.world(), map.shadows(), map.grid, rig, SLIME_SHADER)
	_rebuild_field()
	_ready_ok = true


func _exit_tree() -> void:
	if view:
		view.free_nodes()


## Back in the tree (the editor does this when you switch scene tabs; _ready does not run again):
## build the bands again, deferred so the map is not adding children while it enters the tree.
func _enter_tree() -> void:
	if _ready_ok and view:
		view.setup.call_deferred(map.world(), map.shadows(), map.grid, rig, SLIME_SHADER)


func _rebuild_field() -> void:
	if map and map.grid:
		field = map.build_flow_field()
		if sim:
			sim.solid = map.walk_blocked()
		_spawn_cells.clear()
		for p in map.spawn_points():
			var c := _nearest_reachable(map.grid.cell_at(p), 8)
			if c.x >= 0:
				_spawn_cells.append(c)


## Spawn points may stand on a cliff (the map editor allows it): use the nearest reachable cell.
func _nearest_reachable(c: Vector2i, max_ring: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for ring in max_ring + 1:
		for dr in range(-ring, ring + 1):
			for dc in range(-ring, ring + 1):
				if maxi(absi(dc), absi(dr)) != ring:
					continue
				if field.reachable(c.x + dc, c.y + dr):
					var d := Vector2(dc, dr).length()
					if d < best_d:
						best_d = d
						best = c + Vector2i(dc, dr)
		if best.x >= 0:
			return best
	return best


func _on_rig_changed() -> void:
	if crawl:
		crawl.rebuild()
	if view:
		view.refresh_material(rig)


func _apply_tunables() -> void:
	sim.cell_capacity = cell_capacity
	sim.push_strength = push_strength
	sim.spread_strength = spread_strength
	sim.body = body
	sim.cohesion = cohesion


func _process(dt: float) -> void:
	if not _ready_ok:
		return
	dt = minf(dt, 0.05)
	var want := target_count
	if Engine.is_editor_hint():
		want = editor_count if preview_in_editor else 0
	_apply_tunables()
	var t0 := Time.get_ticks_usec()
	_spawn(dt, want)
	if frozen:
		sim.bin()
	else:
		var n := sim.step(dt, field, map.grid, crawl, rig.width_px())
		if n > 0:
			reached.emit(n)
	var t1 := Time.get_ticks_usec()
	view.update(sim, crawl, rig, _view_rect())
	var t2 := Time.get_ticks_usec()
	last_sim_ms = (t1 - t0) / 1000.0
	last_view_ms = (t2 - t1) / 1000.0
	sim_ms = lerpf(sim_ms, last_sim_ms, 0.1)
	view_ms = lerpf(view_ms, last_view_ms, 0.1)


func _view_rect() -> Rect2:
	if Engine.is_editor_hint():
		return Rect2(Vector2.ZERO, map.grid.size_px())
	var vp := get_viewport()
	var inv := vp.get_canvas_transform().affine_inverse()
	var r := vp.get_visible_rect()
	return Rect2(inv * r.position, inv.basis_xform(r.size))


func _spawn(dt: float, want: int) -> void:
	while sim.count > want:
		sim.remove_slot(sim.count - 1)
	if sim.count >= want:
		_spawn_acc = 0.0
		return
	if _spawn_cells.is_empty():
		return
	_spawn_acc += dt * spawn_per_sec
	while _spawn_acc >= 1.0 and sim.count < want:
		_spawn_acc -= 1.0
		var c := _spawn_cells[_spawn_i % _spawn_cells.size()]
		_spawn_i += 1
		var at := map.grid.cell_center(c) + Vector2(randf_range(-0.45, 0.45) * MapGrid.CELL.x, randf_range(-0.45, 0.45) * MapGrid.CELL.y)
		_spawn_one(at)


func _spawn_one(at: Vector2) -> bool:
	var c := map.grid.cell_at(at)
	if field == null or not field.reachable(c.x, c.y):
		return false
	var r := speed_cells / maxf(0.001, rig.avg_speed()) * (1.0 + speed_spread * randf_range(-1.0, 1.0))
	return sim.spawn(at, r, health, randf(), randf()) >= 0


## One slime at a map point (if the cell leads to a target). Returns false when it can not.
func spawn_at(pos: Vector2) -> bool:
	if not _ready_ok:
		return false
	var ok := _spawn_one(pos)
	sim.bin()
	return ok


## Stress test: put `n` slimes at once on random reachable cells of the whole map.
func fill_random(n: int) -> void:
	if not _ready_ok:
		return
	target_count = n
	var size := map.grid.size_px()
	var tries := 0
	while sim.count < n and tries < n * 4:
		tries += 1
		_spawn_one(Vector2(randf() * size.x, randf() * size.y))
	sim.bin()
