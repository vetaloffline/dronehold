@tool
class_name DrillRig
extends Resource
## Parameters of the laser drill (one .tres for all standalone drills; a drill in a vein slot uses
## the copy inside CrystalVeinRig.drill). Defaults = art/objects/buildings/drill/drill_rig.json
## (tuned in drill_anim.html). Pixels are in drill_body.png space (1800×1100); the arm PNGs share
## its origin. Angles in degrees, clockwise positive, relative to the assembled pose.

@export_group("Map fit")
## Ground point of the drill (Y-sort key), body px (map_03_editor.html SPR.b_drill.base).
@export var ground_point := Vector2(1078, 936)
## Body px → map px when the drill stands alone.
@export_range(0.02, 1.0, 0.005) var map_scale := 0.1:
	set(v): map_scale = v; emit_changed()
## Shift of the ground point from the cell centre, cells.
@export var map_shift := Vector2(0.0, 1.0):
	set(v): map_shift = v; emit_changed()

@export_group("Geometry")
## Shoulder joint on the body, body px.
@export var shoulder_on_body := Vector2(1000, 225)
## Ground under the shoulder (start of the arm shadow), body px.
@export var shoulder_ground := Vector2(1010, 680)
## Arm segment 1: joint (pivot) and its far end, arm px.
@export var seg1_pivot := Vector2(615, 140)
@export var seg1_end := Vector2(300, 275)
@export var seg2_pivot := Vector2(450, 405)
@export var seg2_end := Vector2(308, 608)
## Head: wrist joint and the laser lens centre, arm px.
@export var seg3_pivot := Vector2(308, 608)
@export var seg3_lens := Vector2(96, 932)

@export_group("Pose up, °")
## Плече, лікоть, голова в позі «піднято».
@export_range(-40, 80, 1) var up_shoulder := 80.0
@export_range(-80, 60, 1) var up_elbow := -65.0
@export_range(-80, 80, 1) var up_head := 9.0

@export_group("Pose fire, °")
## Плече, лікоть, голова в позі «стріляє». У слоті жили голова цілиться сама, а `fire_head` — поправка.
@export_range(-40, 80, 1) var fire_shoulder := 31.0
@export_range(-80, 60, 1) var fire_elbow := -31.0
@export_range(-80, 80, 1) var fire_head := 2.0

@export_group("Timing, s")
## Опускання / підйом.
@export_range(0.1, 3.0, 0.05) var t_move := 0.5
## Заряд лінзи.
@export_range(0.0, 3.0, 0.05) var t_charge := 0.6
## Стріляє.
@export_range(0.2, 8.0, 0.1) var t_fire := 2.5
## Охолодження.
@export_range(0.0, 3.0, 0.05) var t_cool := 0.5
## Чекає вгорі.
@export_range(0.0, 6.0, 0.1) var t_wait := 1.0
## Тремтіння при пострілі.
@export_range(0.0, 3.0, 0.05) var recoil := 0.5

@export_group("Beam")
## Точка виходу променя: зсув від лінзи в системі голови, px.
@export var tip_offset := Vector2(5, 0)
## Кут променя відносно труби, ° (тільки окремий бур).
@export_range(-45, 45, 0.5) var aim_deg := -9.0
## Рівень землі для удару, body px (тільки окремий бур; у тюнері 1095 на полотні з відступом 120).
@export_range(500, 1200, 1) var ground_y := 975.0
## Макс. довжина променя, px (тільки окремий бур).
@export_range(50, 1500, 10) var max_len := 1020.0
## Товщина білого ядра променя.
@export_range(0.5, 20.0, 0.5) var core_w := 12.0
## Товщина сяйва.
@export_range(2, 80, 1) var glow_w := 60.0
## Яскравість сяйва.
@export_range(0.0, 1.0, 0.01) var glow_a := 0.58
## Мерехтіння: сила і швидкість.
@export_range(0.0, 1.0, 0.01) var flicker_a := 0.8
@export_range(0.0, 60.0, 0.5) var flicker_speed := 33.0
## Розгін променя, с.
@export_range(0.0, 1.0, 0.01) var start_s := 0.0
@export var color_beam := Color("#ff2a2a")
@export var color_core := Color("#fff1e6")

@export_group("Lens")
## Сяйво лінзи: радіус і яскравість.
@export_range(0, 120, 1) var lens_glow_r := 66.0
@export_range(0.0, 1.0, 0.01) var lens_glow_a := 1.0

@export_group("Hot spot")
## Розжарена пляма в точці удару: радіус, яскравість, пульсація.
@export_range(0, 200, 1) var hot_r := 83.0
@export_range(0.0, 1.0, 0.01) var hot_a := 0.58
@export_range(0.0, 1.0, 0.01) var hot_pulse := 0.17
@export var color_hot := Color("#ff7a2a")

@export_group("Sparks")
## Скільки іскор за кадр.
@export_range(0, 30, 1) var spark_rate := 6
@export_range(50, 1500, 10) var spark_speed := 520.0
## Розкид, °.
@export_range(0, 360, 1) var spark_spread := 162.0
## Напрям, ° (0 = вгору).
@export_range(-180, 180, 1) var spark_dir := 20.0
@export_range(0, 3000, 10) var spark_gravity := 720.0
## Життя, с.
@export_range(0.05, 2.0, 0.01) var spark_life := 0.72
@export_range(0.5, 10.0, 0.1) var spark_size := 4.3
## Довжина хвоста (× швидкість).
@export_range(0.0, 0.1, 0.002) var spark_tail := 0.026
@export var color_spark := Color("#ff5030")

@export_group("Arm shadow")
## Зсув тіні вліво на 1 px висоти.
@export_range(-2.0, 0.0, 0.05) var shadow_tx := -0.3
## Зсув тіні вниз на 1 px висоти.
@export_range(-0.5, 1.0, 0.05) var shadow_ty := 0.2
## Товщина тіні.
@export_range(0.2, 1.5, 0.05) var shadow_k := 0.85
## Прозорість.
@export_range(0.0, 1.0, 0.05) var shadow_opacity := 0.35
@export var shadow_color := Color8(3, 11, 26)


func cycle_len() -> float:
	return maxf(0.001, t_move * 2.0 + t_charge + t_fire + t_cool + t_wait)
