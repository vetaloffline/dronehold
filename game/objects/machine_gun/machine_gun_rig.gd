@tool
class_name MachineGunRig
extends TurretRig
## Кулемет. Дефолти — mg* з machine_gun_scene_params.json; довжини переведено в px карти
## (× map_scale 0.3 / tuner_scale 0.87).

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
