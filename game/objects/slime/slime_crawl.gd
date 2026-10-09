class_name SlimeCrawl
extends RefCounted
## One crawl cycle of the slime, precomputed so thousands of slimes cost a table lookup each.
## The model is slime_crawl.html stepSlime(): target scale (1 + stretch·f, 1 − squash·f) followed
## by a damped spring. The spring is driven by a periodic f, so after a few cycles its output is
## periodic too: simulate it once at rate 1 and keep the last cycle.

const SAMPLES := 256
const WARMUP_CYCLES := 8
const SUBSTEPS := 8

## Scale x, y per sample (interleaved).
var scale_lut := PackedFloat32Array()
## Lean profile f(p − lean_phase) per sample.
var lean_lut := PackedFloat32Array()
## Inchworm distance from phase 0 to the end of each sample, slime widths.
var dist_lut := PackedFloat32Array()
var lean_rad := 0.0
var inch := 0.0
var stretch := 0.0
var slide := 0.0
var period := 1.0
var _rig: SlimeRig


func _init(rig: SlimeRig) -> void:
	_rig = rig
	rebuild()


func rebuild() -> void:
	var rig := _rig
	period = rig.period
	inch = rig.inch
	stretch = rig.stretch
	slide = rig.slide
	lean_rad = deg_to_rad(rig.lean)
	scale_lut.resize(SAMPLES * 2)
	lean_lut.resize(SAMPLES)
	var dt := rig.period / (SAMPLES * SUBSTEPS)
	var k := 40.0 + 360.0 * rig.jelly
	var c := 2.0 * sqrt(k) * rig.damp
	var sx := 1.0
	var sy := 1.0
	var vx := 0.0
	var vy := 0.0
	for cycle in WARMUP_CYCLES + 1:
		for s in SAMPLES:
			for sub in SUBSTEPS:
				var p := (s * SUBSTEPS + sub + 1) / float(SAMPLES * SUBSTEPS)
				var f := rig.profile(fmod(p, 1.0))
				var tx := 1.0 + rig.stretch * f
				var ty := 1.0 - rig.squash * f
				if rig.jelly > 0.0:
					vx += (k * (tx - sx) - c * vx) * dt
					sx += vx * dt
					vy += (k * (ty - sy) - c * vy) * dt
					sy += vy * dt
				else:
					sx = tx
					sy = ty
			if cycle == WARMUP_CYCLES:
				scale_lut[s * 2] = sx
				scale_lut[s * 2 + 1] = sy
	dist_lut.resize(SAMPLES)
	for s in SAMPLES:
		var q := fposmod((s + 1) / float(SAMPLES) - rig.lean_phase, 1.0)
		lean_lut[s] = rig.profile(q)
		dist_lut[s] = inch_dist(minf((s + 1) / float(SAMPLES), 0.999999))


## Index into the tables for phase p in [0, 1).
static func sample_of(p: float) -> int:
	return mini(int(p * SAMPLES), SAMPLES - 1)


## Distance covered by the inchworm step from phase 0 to p, in slime widths.
## Total variation of the target scale: stretch·(f + 1) while lunging, stretch·(3 − f) after
## (slime_crawl.html: adv = inch · W/2 · |Δtx|).
func inch_dist(p: float) -> float:
	var f := _rig.profile(p)
	var v := stretch * (f + 1.0) if p < _rig.lunge else stretch * (3.0 - f)
	return inch * 0.5 * v


## Inchworm distance of one full cycle, slime widths.
func inch_cycle() -> float:
	return inch * 2.0 * stretch
