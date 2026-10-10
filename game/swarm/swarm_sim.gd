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
## Slimes per cell before pushing out; 0 = auto: as many bodies as fit in a cell.
var cell_capacity := 0.0
var push_strength := 1.0
var spread_strength := 40.0
## Physical body: share of the picture width (0.8 = pictures of neighbours overlap by 20 % — a pile). Neighbours keep body width apart.
var body := 0.8
## Pull towards neighbours ahead that are up to 2× the spacing away (1/s): the crowd keeps together.
var cohesion := 3.0

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


## hp of a live slime (0 if dead).
func hp_of(id: int) -> float:
	var i := slot_of_id[id] if id >= 0 and id < slot_of_id.size() else -1
	return hp[i] if i >= 0 else 0.0


## Damage one slime from a bullet's damage pool: kills it if the pool covers its hp (the pool loses
## that hp), else wounds it with the whole pool. Returns what is left of the pool.
func hit_with_pool(id: int, pool: float) -> float:
	var h := hp_of(id)
	if h <= 0.0 or pool <= 0.0:
		return pool
	if pool >= h:
		damage(id, h)
		return pool - h
	damage(id, pool)
	return 0.0


## A bullet with `pool` damage flies on from `from` along `dir` (unit, map px) for `length` px and
## hits every slime whose centre is within `radius` of the line, nearest first, until the pool runs
## out or `max_hits` is reached (docs/concept.md «Пробиття»). `skip_id` = the slime already hit.
## Returns {"stop": px along the line where it stopped (length if it flew through), "kills", "left"}.
func pierce(from: Vector2, dir: Vector2, length: float, pool: float, radius: float, max_hits: int, skip_id := -1) -> Dictionary:
	var out := {"stop": length, "kills": 0, "left": pool}
	if pool <= 0.0 or length <= 0.0:
		out.stop = 0.0
		return out
	# Cells under the line, widened by `radius` (sample every half cell).
	var cells := {}
	var step := minf(MapGrid.CELL.x, MapGrid.CELL.y) * 0.5
	var n := int(ceil(length / step))
	for s in n + 1:
		var p := from + dir * minf(s * step, length)
		var c0 := maxi(0, int(floor((p.x - radius) / MapGrid.CELL.x)))
		var c1 := mini(cols - 1, int(floor((p.x + radius) / MapGrid.CELL.x)))
		var r0 := maxi(0, int(floor((p.y - radius) / MapGrid.CELL.y)))
		var r1 := mini(rows - 1, int(floor((p.y + radius) / MapGrid.CELL.y)))
		for r in range(r0, r1 + 1):
			for c in range(c0, c1 + 1):
				cells[r * cols + c] = true
	# Slimes on the line, sorted by distance along it (ids, not slots: a kill moves slots).
	var cand := []
	for ci in cells:
		for k in range(cell_start[ci], cell_start[ci] + cell_count[ci]):
			var i := order[k]
			if i >= count or id_of[i] == skip_id:
				continue
			var v := Vector2(px[i], py[i]) - from
			var t := v.dot(dir)
			if t < 0.0 or t > length or absf(v.cross(dir)) > radius:
				continue
			cand.append([t, id_of[i]])
	cand.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	var left := pool
	var hits := 0
	for e in cand:
		var id: int = e[1]
		if hp_of(id) <= 0.0:
			continue
		left = hit_with_pool(id, left)
		hits += 1
		if hp_of(id) <= 0.0:
			out.kills += 1
		if left <= 0.0 or hits >= max_hits:
			out.stop = e[0]
			break
	out.left = left
	return out


## Grenade blast: `core_damage` within `core_r` of `pos`, then from `ring_near` falling to `ring_far`
## at `radius` (docs/concept.md «Гранатомет»). Returns how many died.
func damage_blast(pos: Vector2, core_r: float, core_damage: float, radius: float, ring_near: float, ring_far: float) -> int:
	var hit := []
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
				var d2 := dx * dx + dy * dy
				if d2 <= r2:
					hit.append([id_of[i], sqrt(d2)])
	var killed := 0
	for e in hit:
		var d: float = e[1]
		var amount := core_damage
		if d > core_r:
			amount = lerpf(ring_near, ring_far, (d - core_r) / maxf(0.001, radius - core_r))
		if damage(e[0], amount):
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
## Cells slimes can not enter besides the map's cliffs and pits (`grid.blocked`): GameMap.walk_blocked()
## — the walls too (index r * cols + c, 1 = solid). Empty = only grid.blocked. A slime that stands in a
## solid cell (a wall was built on it) may walk out of it.
var solid := PackedByteArray()


func step(dt: float, field: FlowField, grid: MapGrid, crawl: SlimeCrawl, width_px: float) -> int:
	var period := crawl.period
	var cycle := crawl.inch_cycle()
	var dist_lut := crawl.dist_lut
	var slide_dt := crawl.slide * MapGrid.CELL.x * dt
	# Divide (not multiply by 1/48): 1/48 is inexact and puts slimes on a row edge in the
	# wrong row compared with MapGrid.cell_at().
	var cw_px := MapGrid.CELL.x
	var ch_px := MapGrid.CELL.y
	# Spring inside a cell: slimes settle `spacing` apart (y counts 1/0.75: the ground is squashed).
	var spacing := maxf(1.0, width_px * body)
	# Auto capacity: bodies of `spacing` on the squashed ground, in one cell.
	var cap := cell_capacity if cell_capacity > 0.0 else MapGrid.CELL.x * MapGrid.CELL.y / (spacing * spacing * 0.75)
	var push_k := push_strength * MapGrid.CELL.x * dt / cap
	var spring_k := minf(1.0, spread_strength * dt)
	# Cohesion: a neighbour a bit too far (up to 2× the spacing) pulls this slime in, weaker.
	var glue := cohesion / maxf(0.1, spread_strength)
	# Wanted distance to the centroid of m others: spacing·(1+√m)/2.
	var want_lut := PackedFloat32Array()
	want_lut.resize(65)
	for m in 65:
		want_lut[m] = spacing * 0.5 * (1.0 + sqrt(float(m)))
	var jitter_k := width_px * dt
	var phase_k := dt / period
	var smax := SlimeCrawl.SAMPLES - 1
	var sn := float(SlimeCrawl.SAMPLES)
	var nc_max := cols - 1
	var nr_max := rows - 1
	var w := cols
	var dirs := field.dir
	var dists := field.dist
	var blocked := solid if solid.size() == cols * rows else grid.blocked
	var max_step := minf(cw_px, ch_px) * 0.45
	var max_step2 := max_step * max_step
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
		# Pressure, only where the crowd is over capacity: out of an overfull cell into a less full
		# neighbour. Below capacity slimes pack freely (a pile, not a grid).
		var cnt := counts[ci]
		if cnt > 0:
			var e := maxf(0.0, cnt - cap)
			var e_l := maxf(0.0, counts[ci - 1] - cap) if c > 0 else e
			var e_r := maxf(0.0, counts[ci + 1] - cap) if c < nc_max else e
			var e_u := maxf(0.0, counts[ci - w] - cap) if r > 0 else e
			var e_d := maxf(0.0, counts[ci + w] - cap) if r < nr_max else e
			vx += (e_l - e_r) * push_k
			vy += (e_u - e_d) * push_k
			# Spacing spring: keep `spacing` from the others — in the own cell (their centroid
			# without this slime) and in the 4 neighbour cells (their centroids). A lone neighbour
			# is exact pair spacing; a group of m counts as wider (spacing·(1+√m)/2). Closer — pushed out,
			# up to 2× farther and ahead — pulled in (cohesion).
			var sx := 0.0
			var sy := 0.0
			# Cohesion pulls only towards neighbours ahead (along the arrow): the ones behind catch up,
			# the leaders are not held back (a pile at a gap would never get through).
			var fdx := dirs[ci * 2]
			var fdy := dirs[ci * 2 + 1]
			# Unrolled (GDScript loops and calls cost more than the maths): own cell, then L R U D.
			if cnt > 1:
				var m := cnt - 1
				var ox := x - (sum_x[ci] - x) / m
				var oy := (y - (sum_y[ci] - y) / m) / 0.75
				var ol := sqrt(ox * ox + oy * oy)
				var want := want_lut[mini(m, 64)]
				if ol < 0.001:
					sx += (seeds[i] - 0.5) * jitter_k
				elif ol < want:
					var k := (want - ol) / ol
					sx += ox * k
					sy += oy * k * 0.75
				elif ol < want * 2.0 and ox * fdx + oy * fdy < 0.0:
					var k := (want - ol) / ol * glue
					sx += ox * k
					sy += oy * k * 0.75
			if c > 0:
				var m := counts[ci - 1]
				if m > 0:
					var ox := x - sum_x[ci - 1] / m
					var oy := (y - sum_y[ci - 1] / m) / 0.75
					var ol := sqrt(ox * ox + oy * oy)
					var want := want_lut[mini(m, 64)]
					if ol < 0.001:
						sx += (seeds[i] - 0.5) * jitter_k
					elif ol < want:
						var k := (want - ol) / ol
						sx += ox * k
						sy += oy * k * 0.75
					elif ol < want * 2.0 and ox * fdx + oy * fdy < 0.0:
						var k := (want - ol) / ol * glue
						sx += ox * k
						sy += oy * k * 0.75
			if c < nc_max:
				var m := counts[ci + 1]
				if m > 0:
					var ox := x - sum_x[ci + 1] / m
					var oy := (y - sum_y[ci + 1] / m) / 0.75
					var ol := sqrt(ox * ox + oy * oy)
					var want := want_lut[mini(m, 64)]
					if ol < 0.001:
						sx += (seeds[i] - 0.5) * jitter_k
					elif ol < want:
						var k := (want - ol) / ol
						sx += ox * k
						sy += oy * k * 0.75
					elif ol < want * 2.0 and ox * fdx + oy * fdy < 0.0:
						var k := (want - ol) / ol * glue
						sx += ox * k
						sy += oy * k * 0.75
			if r > 0:
				var m := counts[ci - w]
				if m > 0:
					var ox := x - sum_x[ci - w] / m
					var oy := (y - sum_y[ci - w] / m) / 0.75
					var ol := sqrt(ox * ox + oy * oy)
					var want := want_lut[mini(m, 64)]
					if ol < 0.001:
						sx += (seeds[i] - 0.5) * jitter_k
					elif ol < want:
						var k := (want - ol) / ol
						sx += ox * k
						sy += oy * k * 0.75
					elif ol < want * 2.0 and ox * fdx + oy * fdy < 0.0:
						var k := (want - ol) / ol * glue
						sx += ox * k
						sy += oy * k * 0.75
			if r < nr_max:
				var m := counts[ci + w]
				if m > 0:
					var ox := x - sum_x[ci + w] / m
					var oy := (y - sum_y[ci + w] / m) / 0.75
					var ol := sqrt(ox * ox + oy * oy)
					var want := want_lut[mini(m, 64)]
					if ol < 0.001:
						sx += (seeds[i] - 0.5) * jitter_k
					elif ol < want:
						var k := (want - ol) / ol
						sx += ox * k
						sy += oy * k * 0.75
					elif ol < want * 2.0 and ox * fdx + oy * fdy < 0.0:
						var k := (want - ol) / ol * glue
						sx += ox * k
						sy += oy * k * 0.75
			vx += sx * spring_k
			vy += sy * spring_k
		# Do not step into cliffs / pits / walls: try both axes, then each alone. Not between two solid
		# cells that touch only at a corner either. (In a solid cell already — walk out freely.)
		# A long step (a crowd pushing hard, a long frame) is checked in pieces under half a cell, else
		# it could land behind a 1-cell wall: the check looks only at where each piece lands.
		var nx := x + vx
		var ny := y + vy
		if blocked[ci] == 0:
			var parts := 1
			var step2 := vx * vx + vy * vy
			if step2 > max_step2:
				parts = int(ceil(sqrt(step2) / max_step))
			var dx := vx / parts
			var dy := vy / parts
			nx = x
			ny = y
			var cc := c
			var cr := r
			for _p in parts:
				var tx := nx + dx
				var ty := ny + dy
				var tcx := clampi(int(tx / cw_px), 0, nc_max)
				var tcy := clampi(int(ty / ch_px), 0, nr_max)
				if blocked[tcy * w + tcx] == 1:
					if blocked[cr * w + tcx] == 0:
						ty = ny
					elif blocked[tcy * w + cc] == 0:
						tx = nx
					else:
						# Straight into the wall: the whole step is off (as before the pieces), so a
						# pressed crowd stays a loose pile instead of packing onto the wall face.
						nx = x
						ny = y
						break
				elif tcx != cc and tcy != cr and blocked[cr * w + tcx] == 1 and blocked[tcy * w + cc] == 1:
					nx = x
					ny = y
					break
				nx = tx
				ny = ty
				cc = clampi(int(nx / cw_px), 0, nc_max)
				cr = clampi(int(ny / ch_px), 0, nr_max)
		lpx[i] = nx
		lpy[i] = ny
		# The arrays are float32: a slime right at a wall (575.99997) rounds onto it (576.0 =
		# the rock cell) and stays stuck there. Check the stored value; if it landed in a wall,
		# stay where it was (that position was valid).
		var sc := clampi(int(lpx[i] / cw_px), 0, nc_max)
		var sr := clampi(int(lpy[i] / ch_px), 0, nr_max)
		if blocked[ci] == 0 and blocked[sr * w + sc] == 1:
			lpx[i] = x
			lpy[i] = y
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
