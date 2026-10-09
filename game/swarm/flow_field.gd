class_name FlowField
extends RefCounted
## One shared path for the whole swarm: Dijkstra from the target cells over the grid, then an
## arrow per cell towards the cheapest neighbour. An enemy only reads the arrow of its own cell,
## so its cost does not grow with the map or with the number of enemies.
## Rebuild only when the map changes (a building placed or destroyed).

const INF := 1.0e20
const DIAG := 1.41421356
## 8 neighbours: dc, dr, step cost.
const NB := [
	[1, 0, 1.0], [-1, 0, 1.0], [0, 1, 1.0], [0, -1, 1.0],
	[1, 1, DIAG], [1, -1, DIAG], [-1, 1, DIAG], [-1, -1, DIAG],
]

var cols := 0
var rows := 0
## Extra cost to enter a cell (buildings: enemies would rather go around, but chew through when
## that is cheaper). INF = impassable.
var cost := PackedFloat32Array()
## Path cost to the nearest target.
var dist := PackedFloat32Array()
## Unit direction per cell, screen px space (x, y interleaved).
var dir := PackedFloat32Array()


## `grid` blocked cells are impassable; `building_cost` maps cell index -> extra cost.
func build(grid: MapGrid, targets: Array[Vector2i], building_cost := {}) -> void:
	cols = grid.cols
	rows = grid.rows
	var n := cols * rows
	cost.resize(n)
	var blocked := grid.blocked
	for i in n:
		cost[i] = INF if blocked[i] == 1 else 1.0
	for i in building_cost:
		if cost[i] < INF:
			cost[i] = 1.0 + float(building_cost[i])
	_dijkstra(targets)
	_directions()


func _dijkstra(targets: Array[Vector2i]) -> void:
	var n := cols * rows
	dist.resize(n)
	dist.fill(INF)
	# Binary heap of cell indices keyed by dist (lazy deletion).
	var heap_i := PackedInt32Array()
	var heap_d := PackedFloat32Array()
	for t in targets:
		if t.x < 0 or t.y < 0 or t.x >= cols or t.y >= rows:
			continue
		var ti := t.y * cols + t.x
		dist[ti] = 0.0
		_push(heap_i, heap_d, ti, 0.0)
	while heap_i.size() > 0:
		var d := heap_d[0]
		var i := _pop(heap_i, heap_d)
		if d > dist[i]:
			continue
		var c := i % cols
		var r := i / cols
		for nb in NB:
			var nc: int = c + nb[0]
			var nr: int = r + nb[1]
			if nc < 0 or nr < 0 or nc >= cols or nr >= rows:
				continue
			var j := nr * cols + nc
			if cost[j] >= INF:
				continue
			# No corner cutting: a diagonal step needs both side cells open.
			if nb[0] != 0 and nb[1] != 0:
				if cost[r * cols + nc] >= INF or cost[nr * cols + c] >= INF:
					continue
			var nd: float = d + nb[2] * cost[j]
			if nd < dist[j]:
				dist[j] = nd
				_push(heap_i, heap_d, j, nd)


func _directions() -> void:
	var n := cols * rows
	dir.resize(n * 2)
	dir.fill(0.0)
	for i in n:
		if dist[i] >= INF or dist[i] == 0.0:
			continue
		var c := i % cols
		var r := i / cols
		var best := dist[i]
		var bx := 0
		var by := 0
		for nb in NB:
			var nc: int = c + nb[0]
			var nr: int = r + nb[1]
			if nc < 0 or nr < 0 or nc >= cols or nr >= rows:
				continue
			var j := nr * cols + nc
			if dist[j] >= best:
				continue
			if nb[0] != 0 and nb[1] != 0:
				if cost[r * cols + nc] >= INF or cost[nr * cols + c] >= INF:
					continue
			best = dist[j]
			bx = nb[0]
			by = nb[1]
		var v := Vector2(bx * MapGrid.CELL.x, by * MapGrid.CELL.y).normalized()
		dir[i * 2] = v.x
		dir[i * 2 + 1] = v.y


func reachable(c: int, r: int) -> bool:
	return c >= 0 and r >= 0 and c < cols and r < rows and dist[r * cols + c] < INF


static func _push(hi: PackedInt32Array, hd: PackedFloat32Array, i: int, d: float) -> void:
	hi.append(i)
	hd.append(d)
	var k := hi.size() - 1
	while k > 0:
		var p := (k - 1) >> 1
		if hd[p] <= hd[k]:
			break
		var ti := hi[p]; hi[p] = hi[k]; hi[k] = ti
		var td := hd[p]; hd[p] = hd[k]; hd[k] = td
		k = p


static func _pop(hi: PackedInt32Array, hd: PackedFloat32Array) -> int:
	var top := hi[0]
	var last := hi.size() - 1
	hi[0] = hi[last]
	hd[0] = hd[last]
	hi.resize(last)
	hd.resize(last)
	var k := 0
	while true:
		var l := k * 2 + 1
		var r := l + 1
		var m := k
		if l < last and hd[l] < hd[m]:
			m = l
		if r < last and hd[r] < hd[m]:
			m = r
		if m == k:
			break
		var ti := hi[m]; hi[m] = hi[k]; hi[k] = ti
		var td := hd[m]; hd[m] = hd[k]; hd[k] = td
		k = m
	return top
