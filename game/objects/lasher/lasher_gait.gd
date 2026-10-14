class_name LasherGait
extends RefCounted
## The run cycle as SwarmSim.step() reads a crawl (same members as SlimeCrawl: period, slide, dist_lut,
## inch_cycle()). The lasher runs evenly: distance grows linearly with the phase, `stride` frame widths
## per cycle — the frames were drawn for exactly that (lasher_run_template.py), so feet do not slide.

var dist_lut := PackedFloat32Array()
var period := 1.0
var slide := 0.0
var _rig: LasherRig


func _init(rig: LasherRig) -> void:
	_rig = rig
	rebuild()


func rebuild() -> void:
	period = _rig.period
	dist_lut.resize(SlimeCrawl.SAMPLES)
	for s in SlimeCrawl.SAMPLES:
		dist_lut[s] = _rig.stride * (s + 1) / float(SlimeCrawl.SAMPLES)


## Distance of one full cycle, frame widths.
func inch_cycle() -> float:
	return _rig.stride
