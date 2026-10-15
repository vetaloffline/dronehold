@tool
class_name DeathRig
extends Resource
## Death animation of a swarm enemy (one .tres per enemy kind, shared by all of them).
## Frames: atlas built by art/objects/enemies/death_atlas.py from the Codex sheet; the grid, pivot and
## px_scale below are from its JSON (<name>_death_atlas.json). Frame 0 lies exactly on the living sprite.
## After the frames the remains lie for `hold` s, then melt away in `fade` s.
## Pieces (lasher): limbs from lasher_pieces_atlas.png fly off in arcs, hop, roll or slide, and melt with
## the remains. Blood: a spray of drops that leave splats, and a pool under the remains (Corpses).
## Approved in the web preview 2026-10-14 (art/drafts/…/lasher_gore/preview/index.html).

## Death atlas: `cols` × `rows` frames of `frame_w` × `frame_h` px, frame 0 top left, row by row.
@export var texture: Texture2D:
	set(v): texture = v; emit_changed()
@export_range(1, 32, 1) var frames := 5:
	set(v): frames = v; emit_changed()
@export_range(1, 32, 1) var cols := 5:
	set(v): cols = v; emit_changed()
@export_range(1, 32, 1) var rows := 1:
	set(v): rows = v; emit_changed()
@export var frame_w := 256.0:
	set(v): frame_w = v; emit_changed()
@export var frame_h := 256.0:
	set(v): frame_h = v; emit_changed()
## Ground point in a frame, px (the living enemy's pivot carried over).
@export var pivot := Vector2(128, 200):
	set(v): pivot = v; emit_changed()
## Px of the living enemy's atlas per px of this atlas: the corpse is drawn at map_scale() × px_scale.
@export_range(0.01, 20.0, 0.0001) var px_scale := 1.0:
	set(v): px_scale = v; emit_changed()
## Corpses at once; more deaths at the same time vanish without the animation.
@export_range(1, 10000, 1) var capacity := 512

@export_group("Timing")
## One frame, s.
@export_range(0.01, 1.0, 0.005) var frame_time := 0.07:
	set(v): frame_time = v; emit_changed()
## The last frame (remains) lies, s.
@export_range(0.0, 30.0, 0.1) var hold := 2.0:
	set(v): hold = v; emit_changed()
## Then melts to transparent, s.
@export_range(0.05, 10.0, 0.05) var fade := 1.0:
	set(v): fade = v; emit_changed()
## Each frame shifted down by this many px of this atlas (remains fall to the ground). Missing = 0.
@export var frame_drop := PackedFloat32Array():
	set(v): frame_drop = v; emit_changed()
## Shadow ellipse of each frame × the living one (it shrinks as the body bursts). Missing = 1.
@export var frame_shadow := PackedFloat32Array():
	set(v): frame_shadow = v; emit_changed()

@export_group("Pieces")
## Limb atlas (lasher_pieces_atlas.png), px of the living enemy's atlas. Empty = no pieces.
@export var pieces_texture: Texture2D
## Region of each kind in pieces_texture (lasher_pieces_atlas.json).
@export var piece_rects: Array[Rect2] = []
## How many of each kind fly off per death (same order as piece_rects).
@export var piece_counts := PackedInt32Array()
## Start height above the ground, × the living width on the map.
@export_range(0.0, 1.0, 0.01) var piece_lift := 0.3
## Sideways speed, × the living width per s: each piece 0.25…1.75 of it (skewed to short), random
## direction on the ground (depth squashed 0.75).
@export_range(0.0, 10.0, 0.05) var piece_speed := 1.6
## Upward speed, × the living width per s (random 0.4…1.4 of it).
@export_range(0.0, 10.0, 0.05) var piece_up := 1.5
## Fall acceleration, × the living width per s².
@export_range(0.0, 50.0, 0.1) var piece_gravity := 7.0
## Spin up to this, rad/s (random direction and 0.5…1.5 of it).
@export_range(0.0, 40.0, 0.5) var piece_spin := 10.0
## Chance of 1, 2, … hops before a piece stays on the ground (normalised; empty = no hops).
@export var piece_hops := PackedFloat32Array([0.1, 0.2, 0.25, 0.2, 0.15, 0.1])
## A hop keeps the hit speed × this (× 0.8…1.5 per piece), but never less than `piece_min_hop`.
@export_range(0.0, 1.0, 0.01) var piece_bounce := 0.0
## Lowest hop, × the living width per s (0.8…1.2 of it): every hop stays visible.
@export_range(0.0, 3.0, 0.01) var piece_min_hop := 0.45
## Ground speed kept per hop, random between x and y.
@export var piece_keep := Vector2(0.55, 0.85)
## Share of pieces that roll after the hops (turn with their speed, go far); the rest slide and stop.
@export_range(0.0, 1.0, 0.01) var piece_roll_share := 0.35
## Ground friction of a roller / a slider, × the living width per s², random between x and y.
@export var piece_roll_friction := Vector2(1.6, 2.6)
@export var piece_slide_friction := Vector2(3.0, 6.0)
## Flying and sliding pieces bleed: drops in the air, a splat on every hit, a smear while sliding.
@export var piece_bleeds := true

@export_group("Blood")
## Drops sprayed per death. 0 = no blood at all (no spray, no pool).
@export_range(0, 400, 1) var blood_drops := 60
## Where the spray starts: x forward (mirrored with the enemy), height above the ground; × the living width.
@export var blood_from := Vector2(0.3, 0.22)
## Spray speed forward, random between x and y, × 1.1 × the living width per s (−x goes back).
@export var blood_forward := Vector2(-0.4, 1.6)
## Spray speed sideways (depth), up to ± this × the living width per s.
@export_range(0.0, 5.0, 0.05) var blood_side := 0.5
## Spray speed up, × the living width per s (random 0.2…1.5 of it).
@export_range(0.0, 10.0, 0.05) var blood_up := 1.5
## Drop radius, map px per 40 px of the living width, random between x and y.
@export var blood_drop_r := Vector2(0.8, 2.08)
## Pool under the remains: centre (x forward, y) and radius, × the living width; grows in `blood_pool_grow` s.
@export var blood_pool_at := Vector2(0.04, 0.03)
@export_range(0.0, 2.0, 0.01) var blood_pool_r := 0.24
@export_range(0.0, 5.0, 0.05) var blood_pool_grow := 0.6
@export var blood_fill := Color("901414")
@export var blood_line := Color("3a0808")
@export var blood_highlight := Color("e04848")

@export_group("Per death")
## Every death rolls its own: force (pieces and spray speed), pull of all pieces to one side (a grenade:
## away from the blast; a bullet: a random side), spray turned by ± `rnd_spray` rad, drops and pool size,
## frame time. Each pair = random between x and y.
@export var rnd_force := Vector2(0.7, 1.35)
@export var rnd_pull := Vector2(0.0, 0.7)
@export_range(0.0, 3.14, 0.01) var rnd_spray := 0.6
@export var rnd_drops := Vector2(0.6, 1.4)
@export var rnd_pool := Vector2(0.85, 1.2)
@export var rnd_frame_time := Vector2(0.9, 1.15)
## Pieces fly this × as far after a bullet kill / a grenade kill (sideways speed and ground friction × it:
## flight and slide both scale by it; hops stay).
@export_range(0.05, 1.0, 0.05) var bullet_scatter := 0.25
@export_range(0.5, 3.0, 0.05) var blast_scatter := 1.2
## Blood spray after a bullet kill, × the grenade one (sideways speed × it).
@export_range(0.05, 1.0, 0.05) var bullet_blood_scatter := 0.5


## Whole life of a corpse, s; `rate` = this corpse's frame time × (rnd_frame_time).
func life(rate := 1.0) -> float:
	return frames * frame_time * rate + hold + fade


## Time the melting starts, s.
func fade_start(rate := 1.0) -> float:
	return frames * frame_time * rate + hold
