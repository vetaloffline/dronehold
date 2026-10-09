@tool
class_name CrystalVeinRig
extends Resource
## Shared parameters of the crystal vein (one .tres for all veins). Defaults =
## art/objects/resources/crystal_vein/crystal_vein_rig.json (tuned in crystal_vein_anim.html and
## crystal_vein_drill_scene.html). Pixels are in crystal_vein.png space (1536×1024); all vein layers
## share it.

@export_group("Map fit")
## Ground point of the vein (Y-sort key), vein px (map_03_editor.html SPR.vein.base).
@export var ground_point := Vector2(824, 980)
## Vein px → map px.
@export_range(0.02, 1.0, 0.005) var map_scale := 0.24:
	set(v): map_scale = v; emit_changed()
## Shift of the ground point from the footprint centre, cells (32×24).
@export var map_shift := Vector2(0.0, 2.8):
	set(v): map_shift = v; emit_changed()

@export_group("Monolith glow")
## Сяйво моноліту: центр, радіус, яскравість, швидкість пульсу (Гц), колір. ADD.
@export var monolith_center := Vector2(800, 469)
@export_range(0, 700, 1) var monolith_radius := 432.0
@export_range(0.0, 1.0, 0.01) var monolith_alpha := 0.18
@export_range(0.0, 5.0, 0.05) var monolith_pulse_hz := 0.6
@export var monolith_color := Color("#3d8cff")

@export_group("Shards")
@export var shards: Array[CrystalShardRig] = []

@export_group("Shard glow")
## Сяйво кристаликів: радіус при масштабі 0.3, яскравість, пульсація, колір. ADD.
@export_range(0, 300, 1) var shard_glow_r := 83.0
@export_range(0.0, 1.0, 0.01) var shard_glow_a := 0.55
@export_range(0.0, 1.0, 0.01) var shard_glow_pulse := 0.51
@export var shard_glow_color := Color("#4fb6ff")

@export_group("Shard shadow")
## Тінь кристаликів: прозорість, радіус при масштабі 0.3, зсув вліво на 1 px висоти,
## як сильно меншає з висотою.
@export_range(0.0, 1.0, 0.01) var shard_shadow_a := 0.28
@export_range(5, 200, 1) var shard_shadow_r := 48.0
@export_range(-1.5, 0.5, 0.01) var shard_shadow_dx := -0.3
@export_range(0.0, 1.0, 0.01) var shard_shadow_shrink := 0.45
@export var shard_shadow_color := Color8(3, 11, 26)

@export_group("Drill slot")
## Один бур на жилу. Простір бура → простір жили: p_vein = offset + p_drill·scale.
@export var drill_offset := Vector2(880, 160)
@export_range(0.2, 1.5, 0.01) var drill_scale := 0.5
## Куди б'є лазер, px жили.
@export var hit_point := Vector2(892, 580)
## Голова бура сама цілиться в точку удару (+ drill.fire_head як поправка).
@export var auto_aim := true
## Кристал розжарюється: сяйво навколо точки удару.
@export_range(0.0, 1.0, 0.01) var crystal_heat := 0.49
## Параметри бура в слоті (пози, час, промінь, іскри, тінь руки). Розміри іскор і плями — px жили.
@export var drill: DrillRig
