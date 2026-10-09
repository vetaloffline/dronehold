class_name CargoDrone
extends Node2D
## Cargo drone (game only): carries crystals from drills to the nearest store (group "storage").
## Rules (docs/concept.md «Дрони», 2026-10-09):
## - Work: of the drills with crystals not yet promised to other drones, the nearest one. The drone
##   promises itself up to rig.capacity of them (Drill.claimed), so two drones do not fly for the same 5.
## - Landing: on a DronePad of the drill / store (MapObject.drone_pads()). One drone per pad. All pads
##   taken — it hangs next to the nearest one and waits until a pad frees up.
## - Drill: sits rig.load_time, takes the crystals into its own storage (`cargo`), flies to the store,
##   sits rig.unload_time, the wallet gets `cargo`, «+N» pops up over the store.
## - Nothing to do: hangs in the air next to the core and looks for work every rig.think_every s.
## - Flight: round the drone layer (MapGrid.no_fly, purple in the map editor) and tall decor, along a
##   DroneNav path (A* over cells, straightened); no way round — straight.
## Node position = the point on the ground under the drone (Y-sort); the sprite is lifted by `height`.

const DEFAULT_RIG := preload("res://game/objects/cargo_drone/cargo_drone_rig.tres")
## Ground squash of the camera (cell 24 / 32): ground angles ↔ screen.
const CAM_K := 0.75

enum Mode { AIR, LANDING, GROUND, TAKEOFF }
enum Task { NONE, TO_DRILL, TO_STORE, IDLE }

@export var rig: CargoDroneRig = DEFAULT_RIG
## Which idle spot around the core this drone takes (spreads idle drones apart).
@export var slot := 0

var map: GameMap
var height := 0.0
## Ground angle of the flight direction, ° (0 = right, 90 = towards the camera): picks the view.
var heading := 90.0
var cargo := 0
var mode := Mode.AIR
var task := Task.NONE
var target: MapObject
## Crystals promised to this drone by `target` (a drill).
var claim := 0
var goal := Vector2.INF
var land_at_goal := false
## Points still to fly through to `goal` (the last one is `goal`).
var route := PackedVector2Array()
var _pad := ""
var _t := 0.0
var _think := 0.0
var _time := 0.0
var _body: Sprite2D

## Reserved pads: "object id:pad index" → drone.
static var _pads := {}
## One DroneNav per map, rebuilt when the map changes (map_changed).
static var _navs := {}


func _ready() -> void:
	_time = randf() * 10.0
	_body = Sprite2D.new()
	_body.name = "Body"
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_body)
	if map == null:
		map = _find_map()
	height = rig.fly_h if mode == Mode.AIR else 0.0
	_pose()


func _find_map() -> GameMap:
	var n := get_parent()
	while n and not (n is GameMap):
		n = n.get_parent()
	return n as GameMap


func _exit_tree() -> void:
	_release_pad()
	_release_claim()


func _process(dt: float) -> void:
	step(minf(dt, 0.1))


## One tick of the drone (tests call it with a fixed dt).
func step(dt: float) -> void:
	_time += dt
	if target and not is_instance_valid(target):
		target = null
		claim = 0
		_release_pad()
		if mode == Mode.AIR:
			land_at_goal = false
	match mode:
		Mode.AIR:
			height = rig.fly_h
			if goal != Vector2.INF:
				_fly(dt)
			if not land_at_goal:
				_think -= dt
				if _think <= 0.0:
					_think = rig.think_every
					think()
		Mode.LANDING, Mode.TAKEOFF:
			_t += dt / maxf(rig.climb, 0.01)
			var e := smoothstep(0.0, 1.0, minf(_t, 1.0))
			height = rig.fly_h * (1.0 - e if mode == Mode.LANDING else e)
			if _t >= 1.0:
				if mode == Mode.LANDING:
					mode = Mode.GROUND
					height = 0.0
				else:
					mode = Mode.AIR
					think()
				_t = 0.0
		Mode.GROUND:
			_t += dt
			_on_ground()
	_pose()


func _fly(dt: float) -> void:
	if route.is_empty():
		route = PackedVector2Array([goal])
	var to := route[0]
	var d := to - position
	var dist := d.length()
	if dist < 0.5:
		position = to
		route.remove_at(0)
		if route.is_empty():
			if land_at_goal:
				mode = Mode.LANDING
				_t = 0.0
			else:
				route = PackedVector2Array([goal])
		return
	heading = rad_to_deg(atan2(d.y / CAM_K, d.x))
	# Full speed; brakes over the last ~40 px before the goal (not at the turns on the way).
	var left := dist if route.size() == 1 else 1e9
	var v := rig.speed * clampf(left / 40.0, 0.25, 1.0)
	position += d / dist * minf(dist, v * dt)


## Fly to `p` (round what drones do not fly over); land there or hang there.
func _set_goal(p: Vector2, land: bool) -> void:
	land_at_goal = land
	if p == goal and not route.is_empty():
		return
	goal = p
	var nav := nav_of(map)
	route = nav.path(position, p) if nav else PackedVector2Array([p])


## The map's DroneNav (built on first use, again after every map_changed).
static func nav_of(m: GameMap) -> DroneNav:
	if m == null or m.grid == null:
		return null
	var key := m.get_instance_id()
	if not _navs.has(key):
		_navs[key] = DroneNav.for_map(m)
		m.map_changed.connect(func() -> void: _navs.erase(key), CONNECT_ONE_SHOT)
	return _navs[key]


## Decide what to do now (in the air): deliver, go for crystals, or idle by the core.
func think() -> void:
	if cargo > 0:
		var st := nearest_store()
		if st:
			_go(st, Task.TO_STORE)
		else:
			_idle()
		return
	if task == Task.TO_DRILL and target and claim > 0:
		_go(target, Task.TO_DRILL)
		return
	_release_claim()
	var d := pick_drill()
	if d:
		claim = mini(rig.capacity, d.stored - d.claimed)
		d.claimed += claim
		_go(d, Task.TO_DRILL)
	else:
		_idle()


## Fly to a free pad of `o` (reserve it) or, if all are taken, hang by the nearest one.
func _go(o: MapObject, t: Task) -> void:
	if target != o:
		_release_pad()
	task = t
	target = o
	if _pad != "":
		return  # already flying to our pad
	var pads := o.drone_pads()
	if pads.is_empty():
		_set_goal(o.position, true)
		return
	var best := -1
	var best_d := INF
	var near := -1
	var near_d := INF
	for i in pads.size():
		var dd := position.distance_to(pads[i])
		if dd < near_d:
			near_d = dd
			near = i
		if not pad_taken(o, i) and dd < best_d:
			best_d = dd
			best = i
	if best >= 0:
		_pad = pad_key(o, best)
		_pads[_pad] = self
		_set_goal(pads[best], true)
	else:
		var p := pads[near]
		# Keep the waiting spot once picked (re-thinking every 0.25 s must not move it).
		if not land_at_goal and goal != Vector2.INF and goal.distance_to(p) <= rig.wait_offset + 1.0:
			return
		var away := (position - p).normalized() if position.distance_to(p) > 1.0 else Vector2.UP
		_set_goal(p + away * rig.wait_offset, false)


func _idle() -> void:
	task = Task.IDLE
	target = null
	_release_pad()
	var st := nearest_store()
	if st == null:
		goal = Vector2.INF
		route = PackedVector2Array()
		return
	var a := TAU * float(slot) / 8.0 + 0.4
	var r := rig.idle_radius * MapGrid.CELL.x
	_set_goal(st.position + Vector2(cos(a) * r, sin(a) * r * CAM_K), false)


func _on_ground() -> void:
	match task:
		Task.TO_DRILL:
			if _t < rig.load_time:
				return
			var d := target as Drill
			if d:
				# Everything not promised to other drones, up to the own storage.
				var free := d.stored - (d.claimed - claim)
				cargo = d.take(mini(rig.capacity, maxi(0, free)))
				d.claimed = maxi(0, d.claimed - claim)
			claim = 0
		Task.TO_STORE:
			if _t < rig.unload_time:
				return
			if cargo > 0 and target:
				var w := Wallet.of(self)
				if w:
					w.add("crystal", cargo)
				var par := get_parent() as Node2D
				if par:
					FloatText.pop(par, target.position - Vector2(0, 80), "+%d" % cargo, FloatText.CRYSTAL)
			cargo = 0
	task = Task.NONE
	_take_off()


func _take_off() -> void:
	_release_pad()
	mode = Mode.TAKEOFF
	_t = 0.0


func _release_pad() -> void:
	if _pad != "" and _pads.get(_pad) == self:
		_pads.erase(_pad)
	_pad = ""


func _release_claim() -> void:
	if claim > 0 and target is Drill and is_instance_valid(target):
		(target as Drill).claimed = maxi(0, (target as Drill).claimed - claim)
	claim = 0


static func pad_key(o: Object, i: int) -> String:
	return "%d:%d" % [o.get_instance_id(), i]


static func pad_taken(o: Object, i: int) -> bool:
	var d: Variant = _pads.get(pad_key(o, i))
	return d != null and is_instance_valid(d)


## Nearest drill that still has crystals nobody has promised to take.
func pick_drill() -> Drill:
	if map == null:
		return null
	var best: Drill = null
	var best_d := INF
	for o in map.objects():
		var d := o as Drill
		if d and d.vein and d.stored - d.claimed > 0:
			var dd := position.distance_to(d.position)
			if dd < best_d:
				best_d = dd
				best = d
	return best


## Nearest store (core, later relays): the one function every drone uses (AGENTS.md).
func nearest_store() -> MapObject:
	var best: MapObject = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("storage"):
		var o := n as MapObject
		if o and o.is_inside_tree():
			var dd := position.distance_to(o.position)
			if dd < best_d:
				best_d = dd
				best = o
	return best


## Index of the view (0…7 → 0°, 45° … 315°) for the current heading.
func view_index() -> int:
	return int(round(fposmod(heading, 360.0) / 45.0)) % 8


func _pose() -> void:
	if _body == null or rig == null or rig.views.size() < 8:
		return
	_body.texture = rig.views[view_index()]
	_body.scale = Vector2.ONE * rig.map_scale
	var air := clampf(height / rig.fly_h, 0.0, 1.0) if rig.fly_h > 0.0 else 0.0
	var bob := sin(_time * rig.bob_speed + float(slot)) * rig.bob_amp * air
	_body.position = Vector2(0, -rig.rest_lift - height - bob)
	queue_redraw()


## Shadow ellipse on the ground (smaller and lighter when up in the air).
func _draw() -> void:
	if rig == null or rig.views.is_empty():
		return
	var w := rig.views[0].get_width() * rig.map_scale
	var air := clampf(height / rig.fly_h, 0.0, 1.0) if rig.fly_h > 0.0 else 0.0
	var s := 1.0 - 0.3 * air
	draw_set_transform(Vector2(-4.0 * air, 0.0), 0.0, Vector2(w * rig.shadow_w * s, w * rig.shadow_h * s))
	draw_circle(Vector2.ZERO, 1.0, Color(0, 0, 0, lerpf(rig.shadow_alpha_ground, rig.shadow_alpha_air, air)))
	draw_set_transform(Vector2.ZERO)
