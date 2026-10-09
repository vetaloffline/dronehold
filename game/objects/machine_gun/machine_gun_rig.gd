@tool
class_name MachineGunRig
extends TurretRig
## Кулемет. Дефолти — mg* з machine_gun_scene_params.json; довжини переведено в px карти
## (× map_scale 0.3 / tuner_scale 0.87).
## Урон (docs/concept.md «Урон», 2026-10-09): 10 за кулю, темп як був (12 куль/с); слизень — 3 hp,
## куля прошиває до 3 слизнів підряд.

func _init() -> void:
	damage = 10.0
	range_px = 480.0  # 15 клітинок по 32 px (рішення 2026-10-09)


@export_group("Bullet")
## Пробиття: куля, що вбила слизня, летить далі з рештою урону (10 → 7 → 4 → 1).
@export var pierce := true
## Наскільки близько до лінії кулі має бути центр слизня, щоб влучило, px карти (тіло ~0,4 ширини).
@export_range(1.0, 40.0, 0.5) var pierce_radius := 10.0
## Не більше влучань однією кулею (швидкодія).
@export_range(1, 32, 1) var pierce_max := 8

@export_group("Tracers")
## Трасер: швидкість, px карти/с (тюнер 3200).
@export_range(100.0, 4000.0, 1.0) var tracer_speed := 1103.45
## Трасер: довжина, px карти (тюнер 80).
@export_range(1.0, 120.0, 0.1) var tracer_len := 27.59
## Трасер: товщина, px карти (тюнер 4).
@export_range(0.2, 6.0, 0.05) var tracer_width := 1.38
## Розкид куль, px карти (тюнер 22).
@export_range(0.0, 60.0, 0.1) var spread := 7.59
## Гільзи.
@export var casings := true
