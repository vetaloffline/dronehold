class_name SwarmSim
extends RefCounted
## The whole crowd as flat arrays — no node per enemy (AGENTS.md). This is the hot loop; its data
## layout is the contract, so it can be moved to C++ (GDExtension) without touching the rest.
##
## Each tick:
##   1. move: flow-field arrow of the slime's cell × crawl step, plus "pressure" — push out of
##      crowded cells (density gradient) and away from the centre of the own cell;
##   2. bin: counting sort of slimes into grid cells → per-cell count, centroid, member list.
## Neighbour queries (turrets, explosions) read the bins, never scan all slimes.

## Slot data, index 0..count-1 (dense; a dead slime is swapped with the last one).
var count := 0
var capacity := 0
var px := PackedFloat32Array()
var py := PackedFloat32Array()
var phase := PackedFloat32Array()
var rate := PackedFloat32Array()
var hp := PackedFloat32Array()
## +1 faces right, −1 faces left (sprite mirrored).
var face := PackedFloat32Array()
## Random 0..1 per slime (blink timing).
var seed := PackedFloat32Array()
## Stable ids: slots move on removal, ids do not. Turrets keep an id.
var id_of := PackedInt32Array()
var slot_of_id := PackedInt32Array()
var _free_ids := PackedInt32Array()

## Bins (rebuilt every tick).
var cols := 0
var rows := 0
var cell_of := PackedInt32Array()
var cell_count := PackedInt32Array()
var cell_start := PackedInt32Array()
var cell_sum_x := PackedFloat32Array()
var cell_sum_y := PackedFloat32Array()
## Slot indices sorted by cell.
var order := PackedInt32Array()

## Tunables (set by Swarm).
var cell_capacity := 2.0
var push_strength := 1.0
var spread_strength := 1.0

var reached_total := 0
var killed_total := 0


func setup(cap: int, grid_cols: int, grid_rows: int) -> void:
	capacity = cap
	# Packed arrays are values (copy on write): resize each member directly, not through a list.
	px.resize(cap)
	py.resize(cap)
	phase.resize(cap)
	rate.resize(cap)
	hp.resize(cap)
	face.resize(cap)
	seed.resize(cap)
	id_of.resize(cap)
	slot_of_id.resize(cap)
	slot_of_id.fill(-1)
	_free_ids.clear()
	for i in range(cap - 1, -1, -1):
		_free_ids.append(i)
	cell_of.resize(cap)
	order.resize(cap)
	cols = grid_cols
	rows = grid_rows
	var n := cols * rows
	cell_count.resize(n)
	cell_start.resize(n + 1)
	cell_sum_x.resize(n)
	cell_sum_y.resize(n)
	count = 0


## Returns the stable id, or −1 when full.
func spawn(pos: Vector2, r: float, health: float, rnd: float, ph: float) -> int:
	if count >= capacity:
		return -1
	var i := count
	var id := _free_ids[_free_ids.size() - 1]
	_free_ids.resize(_free_ids.size() - 1)
	px[i] = pos.x
	py[i] = pos.y
	rate[i] = r
	hp[i] = health
	phase[i] = ph
	face[i] = 1.0
	seed[i] = rnd
	id_of[i] = id
	slot_of_id[id] = i
	count += 1
	return id


func remove_slot(i: int) -> void:
	var last := count - 1
	var id := id_of[i]
	slot_of_id[id] = -1
	_free_ids.append(id)
	if i != last:
		px[i] = px[last]
		py[i] = py[last]
		phase[i] = phase[last]
		rate[i] = rate[last]
		hp[i] = hp[last]
		face[i] = face[last]
		seed[i] = seed[last]
		id_of[i] = id_of[last]
		slot_of_id[id_of[i]] = i
		cell_of[i] = cell_of[last]
	count = last


func clear() -> void:
	while count > 0:
		remove_slot(count - 1)


func alive(id: int) -> bool:
	return id >= 0 and id < capacity and slot_of_id[id] >= 0


func position_of(id: int) -> Vector2:
	var i := slot_of_id[id]
	return Vector2(px[i], py[i])


## Returns true when the slime died.
func damage(id: int, amount: float) -> bool:
	var i := slot_of_id[id]
	if i < 0:
		return false
	hp[i] -= amount
	if hp[i] <= 0.0:
		remove_slot(i)
		killed_total += 1
		return true
	return false


## Damage every slime within `radius` of `pos` (reads only the cells the circle touches).
func damage_radius(pos: Vector2, radius: float, amount: float) -> int:
	var hit := PackedInt32Array()
	var c0 := maxi(0, int(floor((pos.x - radius) / MapGrid.CELL.x)))
	var c1 := mini(cols - 1, int(floor((pos.x + radius) / MapGrid.CELL.x)))
	var r0 := maxi(0, int(floor((pos.y - radius) / MapGrid.CELL.y)))
	var r1 := mini(rows - 1, int(floor((pos.y + radius) / MapGrid.CELL.y)))
	var r2 := radius * radius
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var ci := r * cols + c
			for k in range(cell_start[ci], cell_start[ci] + cell_count[ci]):
				var i := order[k]
				if i >= count:
					continue
				var dx := px[i] - pos.x
				var dy := py[i] - pos.y
				if dx * dx + dy * dy <= r2:
					hit.append(id_of[i])
	var killed := 0
	for id in hit:
		if damage(id, amount):
			killed += 1
	return killed


## Nearest slime id within `max_range`, searching rings of cells outwards; −1 if none.
func nearest(pos: Vector2, max_range: float) -> int:
	return nearest_in_cone(pos, max_range, Vector2.ZERO, -2.0)


## Nearest slime within `max_range` whose direction from `pos` is inside the cone around unit
## `dir` (cos of the half angle `cos_half`; −2 = any direction). −1 if none.
## `y_squash`: the cone is tested with dy / y_squash (camera squash → ground directions).
func nearest_in_cone(pos: Vector2, max_range: float, dir: Vector2, cos_half: float, y_squash := 1.0) -> int:
	var any_dir := cos_half < -1.0
	var cc := int(floor(pos.x / MapGrid.CELL.x))
	var cr := int(floor(pos.y / MapGrid.CELL.y))
	var best := -1
	var best_d := max_range * max_range
	var max_ring := int(ceil(max_range / MapGrid.CELL.y)) + 1
	for ring in max_ring + 1:
		# Anything in this ring is at least (ring − 1) cells away: stop once that beats the best.
		var ring_min := (ring - 1) * MapGrid.CELL.y
		if best >= 0 and ring_min > 0.0 and ring_min * ring_min > best_d:
			break
		for r in range(cr - ring, cr + ring + 1):
			if r < 0 or r >= rows:
				continue
			var edge_row := r == cr - ring or r == cr + ring
			var step := 1 if edge_row else maxi(1, ring * 2)
			var c := cc - ring
			while c <= cc + ring:
				if c >= 0 and c < cols:
					var ci := r * cols + c
					for k in range(cell_start[ci], cell_start[ci] + cell_count[ci]):
						var i := order[k]
						if i >= count:
							continue
						var dx := px[i] - pos.x
						var dy := py[i] - pos.y
						var d := dx * dx + dy * dy
						var gy := dy / y_squash
						if d < best_d and (any_dir or dx * dir.x + gy * dir.y >= cos_half * sqrt(dx * dx + gy * gy)):
							best_d = d
							best = id_of[i]
				c += step
	return best


## Move every slime one tick. Returns the number that reached a target cell (they are removed).
## Hot loop: the arrays are moved into locals for the loop (no member lookups, and a sole owner
## means no copy-on-write), then moved back.
func step(dt: float, field: FlowField, grid: MapGrid, crawl: SlimeCrawl, width_px: float) -> int:
	var period := crawl.period
	var cycle := crawl.inch_cycle()
	var dist_lut := crawl.dist_lut
	var slide_dt := crawl.slide * MapGrid.CELL.x * dt
	# Divide (not multiply by 1/48): 1/48 is inexact and puts slimes on a row edge in the
	# wrong row compared with MapGrid.cell_at().
	var cw_px := MapGrid.CELL.x
	var ch_px := MapGrid.CELL.y
	var push_k := push_strength * MapGrid.CELL.x * dt / maxf(0.1, cell_capacity)
	var spread_k := spread_strength * width_px * dt / maxf(0.1, cell_capacity)
	var jitter_k := spread_strength * width_px * dt
	var phase_k := dt / period
	var smax := SlimeCrawl.SAMPLES - 1
	var sn := float(SlimeCrawl.SAMPLES)
	var nc_max := cols - 1
	var nr_max := rows - 1
	var w := cols
	var dirs := field.dir
	var dists := field.dist
	var blocked := grid.blocked
	var counts := cell_count
	var sum_x := cell_sum_x
	var sum_y := cell_sum_y
	var rates := rate
	var seeds := seed
	var lpx := px
	var lpy := py
	var lph := phase
	var lface := face
	px = PackedFloat32Array()
	py = PackedFloat32Array()
	phase = PackedFloat32Array()
	face = PackedFloat32Array()
	var reached := PackedInt32Array()
	for i in count:
		var x := lpx[i]
		var y := lpy[i]
		var c := clampi(int(x / cw_px), 0, nc_max)
		var r := clampi(int(y / ch_px), 0, nr_max)
		var ci := r * w + c
		if dists[ci] == 0.0:
			reached.append(i)
			continue
		# Crawl: phase → inchworm distance this tick.
		var rt := rates[i]
		var p0 := lph[i]
		var p1 := p0 + rt * phase_k
		var wrap := 0.0
		if p1 >= 1.0:
			p1 -= floor(p1)
			wrap = cycle
		lph[i] = p1
		var s0 := mini(int(p0 * sn), smax)
		var s1 := mini(int(p1 * sn), smax)
		var adv := (dist_lut[s1] - dist_lut[s0] + wrap) * width_px + slide_dt * rt
		var vx := dirs[ci * 2] * adv
		var vy := dirs[ci * 2 + 1] * adv
		# Pressure: out of denser neighbour cells, and away from the own cell's centre.
		var cnt := counts[ci]
		if cnt > 0:
			var d_l := counts[ci - 1] if c > 0 else cnt
			var d_r := counts[ci + 1] if c < nc_max else cnt
			var d_u := counts[ci - w] if r > 0 else cnt
			var d_d := counts[ci + w] if r < nr_max else cnt
			vx += (d_l - d_r) * push_k
			vy += (d_u - d_d) * push_k
			if cnt > 1:
				var ox := x - sum_x[ci] / cnt
				var oy := y - sum_y[ci] / cnt
				var ol := sqrt(ox * ox + oy * oy)
				if ol > 0.001:
					var k := (cnt - 1) * spread_k / ol
					vx += ox * k
					vy += oy * k
				else:
					vx += (seeds[i] - 0.5) * jitter_k
		# Do not step into cliffs / pits: try both axes, then each alone.
		var nx := x + vx
		var ny := y + vy
		var ncx := clampi(int(nx / cw_px), 0, nc_max)
		var nry := clampi(int(ny / ch_px), 0, nr_max)
		if blocked[nry * w + ncx] == 1:
			if blocked[r * w + ncx] == 0:
				ny = y
			elif blocked[nry * w + c] == 0:
				nx = x
			else:
				nx = x
				ny = y
		lpx[i] = nx
		lpy[i] = ny
		if vx > 0.05:
			lface[i] = 1.0
		elif vx < -0.05:
			lface[i] = -1.0
	px = lpx
	py = lpy
	phase = lph
	face = lface
	for k in range(reached.size() - 1, -1, -1):
		remove_slot(reached[k])
	reached_total += reached.size()
	bin()
	return reached.size()


## Counting sort of slots into cells.
func bin() -> void:
	var n := cols * rows
	var counts := cell_count
	var sum_x := cell_sum_x
	var sum_y := cell_sum_y
	var cof := cell_of
	cell_count = PackedInt32Array()
	cell_sum_x = PackedFloat32Array()
	cell_sum_y = PackedFloat32Array()
	cell_of = PackedInt32Array()
	counts.fill(0)
	sum_x.fill(0.0)
	sum_y.fill(0.0)
	# Divide (not multiply by 1/48): 1/48 is inexact and puts slimes on a row edge in the
	# wrong row compared with MapGrid.cell_at().
	var cw_px := MapGrid.CELL.x
	var ch_px := MapGrid.CELL.y
	var nc_max := cols - 1
	var nr_max := rows - 1
	var w := cols
	var lpx := px
	var lpy := py
	for i in count:
		var x := lpx[i]
		var y := lpy[i]
		var ci := clampi(int(y / ch_px), 0, nr_max) * w + clampi(int(x / cw_px), 0, nc_max)
		cof[i] = ci
		counts[ci] += 1
		sum_x[ci] += x
		sum_y[ci] += y
	var starts := cell_start
	cell_start = PackedInt32Array()
	var acc := 0
	for ci in n:
		starts[ci] = acc
		acc += counts[ci]
	starts[n] = acc
	var cursor := starts.duplicate()
	var ord := order
	order = PackedInt32Array()
	for i in count:
		var ci := cof[i]
		ord[cursor[ci]] = i
		cursor[ci] += 1
	cell_count = counts
	cell_sum_x = sum_x
	cell_sum_y = sum_y
	cell_of = cof
	cell_start = starts
	order = ord
