@tool
class_name LasherSwarm
extends Node
## The lasher crowd of a map: its own SwarmSim (the same arrays and step() as the slimes — data, not a
## node per enemy), the run gait (LasherGait) and SwarmView in frames mode (run-cycle atlas).
## Spawns only at SpawnPoint with enemy = "lasher" (lasher_spawn_point.tscn). In group "swarm" like
## Swarm: turrets search every crowd of the group.

signal reached(count: int)

const SHADER := preload("res://game/objects/lasher/lasher.gdshader")
const DEFAULT_RIG := preload("res://game/objects/lasher/lasher_rig.tres")
const DEFAULT_DEATH_RIG := preload("res://game/objects/lasher/lasher_death_rig.tres")

@export var map: GameMap
## Shared lasher parameters (atlas, size, run cycle, shadow).
@export var rig: LasherRig = DEFAULT_RIG:
	set(v):
		if rig and rig.changed.is_connected(_on_rig_changed):
			rig.changed.disconnect(_on_rig_changed)
		rig = v
		if rig and is_inside_tree():
			rig.changed.connect(_on_rig_changed)
			_on_rig_changed()
## Death animation (head and back burst, limbs fly off). Empty = a killed enemy vanishes at once. Read in _ready.
@export var death_rig: DeathRig = DEFAULT_DEATH_RIG

@export_group("Count")
## How many lashers are kept alive on the map.
@export_range(0, 10000, 1, "or_greater") var target_count := 5
## New lashers per second until target_count is reached.
@export_range(0.0, 50.0, 0.05, "or_greater") var spawn_per_sec := 0.25
## Array size (memory is reserved once).
@export_range(10, 100000, 10, "or_greater") var capacity := 2000

@export_group("Movement")
## Mean speed, cells/s. The run cycle speeds up to match (rate = speed / rig.avg_speed()), so the feet
## do not slide.
@export_range(0.05, 5.0, 0.01, "or_greater") var speed_cells := 0.6
## ± share of random speed difference between lashers.
@export_range(0.0, 0.6, 0.01) var speed_spread := 0.1
## As in Swarm: crowd per cell before pushing out (0 = auto), push, spacing spring, body, cohesion.
@export_range(0.0, 40.0, 0.25) var cell_capacity := 0.0
@export_range(0.0, 5.0, 0.05) var push_strength := 1.0
@export_range(0.0, 60.0, 0.5) var spread_strength := 40.0
## Physical body, share of the frame width.
@export_range(0.2, 1.2, 0.01) var body := 0.8
@export_range(0.0, 20.0, 0.5) var cohesion := 3.0
## Lashers stand still (targets for testing); they are still drawn and can be shot.
@export var frozen := false

@export_group("Combat")
@export_range(0.1, 10000.0, 0.1, "or_greater") var health := 25.0

@export_group("Editor preview")
@export var preview_in_editor := true
@export_range(0, 100, 1) var editor_count := 3

var sim: SwarmSim
var field: FlowField
var gait: LasherGait
var view: SwarmView
## Death animations (runtime only; null in the editor or without death_rig).
var corpses: Corpses
var _spawn_cells: Array[Vector2i] = []
var _spawn_acc := 0.0
var _spawn_i := 0
var _ready_ok := false


func _ready() -> void:
	add_to_group("swarm")
	if map == null:
		map = get_parent() as GameMap
	if map == null or map.grid == null or rig == null or rig.texture == null:
		push_warning("LasherSwarm: needs a GameMap parent with a grid and a LasherRig with an atlas")
		return
	if not rig.changed.is_connected(_on_rig_changed):
		rig.changed.connect(_on_rig_changed)
	map.map_changed.connect(_rebuild_field)
	gait = LasherGait.new(rig)
	sim = SwarmSim.new()
	sim.setup(capacity if not Engine.is_editor_hint() else maxi(editor_count, 1) * 2, map.grid.cols, map.grid.rows)
	_apply_tunables()
	view = SwarmView.new()
	view.setup_frames(map.world(), map.shadows(), map.grid, rig, SHADER)
	if death_rig and death_rig.texture and not Engine.is_editor_hint():
		corpses = Corpses.new()
		corpses.name = "LasherCorpses"
		corpses.setup(map, death_rig, rig.shadow_alpha, "LasherDeath")
		sim.record_deaths = true
	_rebuild_field()
	_ready_ok = true


func _exit_tree() -> void:
	if view:
		view.free_nodes()
	if corpses and is_instance_valid(corpses):
		corpses.free_view()


## Back in the tree (editor scene tabs): build the bands again, deferred (see Swarm._enter_tree).
func _enter_tree() -> void:
	if _ready_ok and view:
		view.setup_frames.call_deferred(map.world(), map.shadows(), map.grid, rig, SHADER)


func _rebuild_field() -> void:
	if map and map.grid:
		field = map.build_flow_field()
		if sim:
			sim.solid = map.walk_blocked()
		_spawn_cells = Swarm.spawn_cells(map, field, "lasher")


func _on_rig_changed() -> void:
	if gait:
		gait.rebuild()
	if view:
		view.refresh_shadow(rig.shadow_alpha)
	if corpses:
		corpses.view.refresh_shadow(rig.shadow_alpha)


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
	_spawn(dt, want)
	if frozen:
		sim.bin()
	else:
		var n := sim.step(dt, field, map.grid, gait, rig.width_px())
		if n > 0:
			reached.emit(n)
	var vr := Swarm.visible_map_rect(self, map)
	view.update_frames(sim, rig, vr)
	if corpses:
		corpses.add(sim.deaths, rig.width_px())
		sim.deaths.clear()
		corpses.tick(dt, rig.map_scale(), rig.width_px(), Vector4(rig.shadow_w, rig.shadow_h, rig.shadow_x, rig.shadow_y), vr)


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


## One lasher at a map point (if the cell leads to a target). Returns false when it can not.
func spawn_at(pos: Vector2) -> bool:
	if not _ready_ok:
		return false
	var ok := _spawn_one(pos)
	sim.bin()
	return ok
