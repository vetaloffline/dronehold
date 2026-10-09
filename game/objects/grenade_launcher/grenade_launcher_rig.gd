@tool
class_name GrenadeLauncherRig
extends TurretRig
## Гранатомет. Дефолти — mo* з machine_gun_scene_params.json; довжини переведено в px карти
## (× map_scale 0.27 / tuner_scale 0.9 = × 0.3).

func _init() -> void:
	# mo* defaults (the shared exports above carry the machine gun's values).
	ring = Vector2(215, 190)
	ring_h = 140.0
	map_scale = 0.27
	tuner_scale = 0.9
	head_scale = 0.85
	lift = 80.0
	turn_strength = 0.0
	rot_speed = 120.0
	tolerance = 5.0
	range_px = 540.0
	fire_rate = 0.7
	damage = 6.0
	recoil = 18.0
	recoil_return = 0.3
	flash = 80.0
	# Tuner: target ellipse centre (1691, 650), launcher at (1380, 760); × 0.3.
	demo_center = Vector2(93.3, -33.0)
	demo_radius = Vector2(270.0, 99.0)


## Як повертається: 8 ракурсів голови (апрувнуто) або нахил труби вліво-вправо (2D).
@export_enum("views", "tilt") var launcher_mode := 0

@export_group("Shell")
## Час польоту, с.
@export_range(0.3, 4.0, 0.05) var flight := 1.3
## Висота дуги, px карти (тюнер 600).
@export_range(10.0, 500.0, 1.0) var arc := 180.0
## Радіус вибуху, px карти (тюнер 150).
@export_range(5.0, 150.0, 0.5) var blast := 45.0
## Розмір снаряда, px карти (тюнер 12).
@export_range(0.5, 15.0, 0.1) var shell := 3.6

@export_group("Tilt mode")
@export var tilt_cradle: Texture2D
@export var tilt_outer: Texture2D
@export var tilt_shaft: Texture2D
@export var tilt_cap: Texture2D
## Точка кріплення люльки й шарнір нахилу в px голови.
@export var tilt_housing := Vector2(214, 233)
@export var tilt_pivot := Vector2(214, 150)
## Верх гільзи, рядки ствола і ковпака, дуло в ковпаку — px голови.
@export var tilt_outer_top := 92.0
@export var tilt_shaft_rows := Vector2(56, 92)
@export var tilt_cap_rows := Vector2(22, 56)
@export var tilt_muzzle_in_cap := 10.0
## Нахил: максимум, °.
@export_range(5.0, 80.0, 1.0) var tilt_max := 50.0
## Нахил: дистанція до максимуму, px карти (тюнер 900).
@export_range(10.0, 800.0, 1.0) var tilt_range := 270.0
## Висув верхньої частини (довжина), px голови.
@export_range(0.0, 300.0, 1.0) var tube_extend := 70.0
## Ширина верхньої частини.
@export_range(0.5, 1.1, 0.01) var tube_inner_w := 0.84
## При пострілі в'їжджає на, px голови.
@export_range(0.0, 300.0, 1.0) var tube_retract := 80.0
## В'їзд, с.
@export_range(0.01, 0.5, 0.01) var tube_retract_t := 0.05
## Розкладання назад, с.
@export_range(0.05, 2.0, 0.01) var tube_extend_t := 0.45
## Масштаб гільзи по довжині.
@export_range(0.5, 2.0, 0.01) var tube_outer_s := 1.0
## Шарнір нахилу: зсув Y, px голови.
@export_range(-100.0, 100.0, 1.0) var tilt_pivot_y := 0.0
