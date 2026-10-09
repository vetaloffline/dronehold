@tool
class_name CrystalShardRig
extends Resource
## One floating shard of the crystal vein. Pixels are in crystal_vein.png space.
## Motion (crystal_vein_rig.json shard_motion): s = sin((t/period + phase)·2π); y = center.y − s·bob_amp;
## rotation = sway·sin((t/(period·1.7) + phase)·2π); scale.x ·= 1 − spin·(0.5 − 0.5·cos((t/(period·1.3) + phase)·2π)).

@export var texture: Texture2D
## Центр польоту, px жили.
@export var center := Vector2(600, 250)
## Висота над землею (для тіні), px.
@export_range(0, 900, 1) var height_for_shadow := 200.0
## Амплітуда вгору-вниз, px.
@export_range(0, 150, 1) var bob_amp := 20.0
## Період, с.
@export_range(0.5, 10.0, 0.1) var period_s := 3.0
## Зсув фази (0–1).
@export_range(0.0, 1.0, 0.01) var phase := 0.0
## Хитання, °.
@export_range(0.0, 45.0, 0.5) var sway_deg := 6.0
## Масштаб.
@export_range(0.05, 1.5, 0.01) var scale := 0.22
## Обертання (стискання по X).
@export_range(0.0, 1.0, 0.01) var spin := 0.0
