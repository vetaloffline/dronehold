@tool
class_name TurretRig
extends Resource
## Shared parameters of a turret with N head views (machine gun, grenade launcher): view i points
## at ground angle i·360/N (0° = right, 90° = to the camera).
## Defaults = art/objects/buildings/machine_gun/machine_gun_scene_params.json (tuned in
## machine_gun_scene.html). One .tres per turret type: change it — every turret of the type changes.
##
## Units:
## - "px спрайта" — pixels of the 418×418 base / head PNGs (the head is scaled by `head_scale`).
## - "px карти" — map pixels (cell = 64×48). The tuner worked in canvas px of its own scene, where
##   the base was drawn at `tuner_scale`; on the map it is drawn at `map_scale`, so
##   map px = tuner px × map_scale / tuner_scale. Lengths below are already converted.

const VIEWS := [0, 45, 90, 135, 180, 225, 270, 315]  # the original 8 (art file names)

@export_group("Art")
@export var base: Texture2D
@export var base_shadow: Texture2D
## Ракурси голови по колу: 0° = вправо, 90° = до камери, крок 360°/кількість (8, 16, 32…).
@export var heads: Array[Texture2D] = []
## Для кожного ракурсу: точка голови над кільцем (housing з `*_views.json`).
@export var housing := PackedVector2Array()
## Для кожного ракурсу: дуло в спрайті голови (muzzle з `*_views.json`).
@export var muzzle := PackedVector2Array()
## Реальний напрям ствола кожного ракурсу на землі, ° (0 = вправо, 90 = до камери), по зростанню.
## Заміряно на картинках (art/objects/buildings/turret_views_fit.py). Порожньо = рівномірно 360°/N.
@export var view_azimuths := PackedFloat32Array()
## Кільце (кріплення голови) на основі, px спрайта.
@export var ring := Vector2(212, 157)
## Висота кільця над точкою землі, px спрайта (земля = ring + (0, ring_h)).
@export var ring_h := 150.0

@export_group("Map")
## Масштаб спрайта на карті (підгонка з map_03_editor.html).
@export_range(0.05, 1.5, 0.005) var map_scale := 0.3
## Масштаб пушки в сцені тюнера (mgS / moS) — тільки для перерахунку одиниць.
@export_range(0.2, 2.0, 0.01) var tuner_scale := 0.87

@export_group("Head")
## Голова відносно основи (mgHS).
@export_range(0.3, 1.6, 0.01) var head_scale := 0.77
## Голова над кільцем, px голови (mgLift).
@export_range(-100.0, 250.0, 1.0) var lift := 87.0
## Голова: зсув X, px голови (mgHX).
@export_range(-150.0, 150.0, 1.0) var head_x := 0.0
## Зсув голови для кожного ракурсу, px голови (mgOx… / mgOy…).
@export var view_offsets := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
## Як перемикаються ракурси: ривками / ривками + доворот спрайта / перетікання.
@export_enum("snap", "turn", "blend") var view_mode := 0
## Доворот спрайта: сила 0–1 (тільки режим "turn").
@export_range(0.0, 1.0, 0.01) var turn_strength := 0.41

@export_group("Aim")
## Швидкість повороту, °/с.
@export_range(10.0, 720.0, 1.0) var rot_speed := 275.0
## Стріляє, коли ціль у межах, ° (режими turn / blend).
@export_range(1.0, 45.0, 1.0) var tolerance := 8.0
## Режим snap: стріляє тільки по цілі в цьому конусі навколо намальованого ствола, ° (на екрані).
## 0 = авто: половина кроку між ракурсами (+0.5°) — тоді стріляє на всі 360° без мертвих зон.
@export_range(0.0, 25.0, 0.5) var barrel_cone := 0.0
## Дальність, px карти (тюнер: 1310 px × 0.3 / 0.87).
@export_range(20.0, 2000.0, 1.0) var range_px := 451.72
## Пострілів за секунду.
@export_range(0.2, 30.0, 0.1) var fire_rate := 12.0
## Шкода за постріл (у слизня 10 hp).
@export_range(0.0, 100.0, 0.1) var damage := 1.0

@export_group("Recoil and flash")
## Віддача, px спрайта.
@export_range(0.0, 60.0, 1.0) var recoil := 5.0
## Повернення після віддачі, с.
@export_range(0.02, 1.0, 0.01) var recoil_return := 0.05
## Спалах: радіус, px спрайта.
@export_range(0.0, 200.0, 1.0) var flash := 60.0

@export_group("Shadows")
## Сплющення землі камерою (cell 48 / 64).
@export_range(0.2, 1.0, 0.01) var cam_k := 0.75
## Тінь: зсув на 1 px висоти (сонце справа вгорі → тінь вліво).
@export var sun := Vector2(-0.13, -0.2)
## Тінь голови: прозорість.
@export_range(0.0, 1.0, 0.01) var head_shadow_alpha := 0.35
## Тінь голови: наскільки опущена до землі (0–1.5).
@export_range(0.0, 1.5, 0.01) var head_shadow_drop := 0.92
## Тінь основи: прозорість.
@export_range(0.0, 1.5, 0.01) var base_shadow_alpha := 1.0

@export_group("Editor demo target")
## Центр еліпса демо-цілі відносно пушки, px карти.
@export var demo_center := Vector2(367.24, -17.24)
## Радіуси еліпса, px карти (тюнер tRx / tRy).
@export var demo_radius := Vector2(310.34, 113.79)
## Швидкість руху цілі, рад/с (тюнер tSpeed).
@export_range(0.0, 2.0, 0.01) var demo_speed := 0.67


## Ground point in base sprite px (the node origin).
func ground_in_base() -> Vector2:
	return ring + Vector2(0.0, ring_h)


## Tuner canvas px → px спрайта (the turret's local space).
func tuner_to_local() -> float:
	return 1.0 / tuner_scale


## Map px → px спрайта.
func map_to_local() -> float:
	return 1.0 / map_scale


## Height of the head above the ground, px спрайта (tuner geo().headH / s).
func head_height() -> float:
	return ring_h + lift * head_scale


func view_count() -> int:
	return heads.size()


## Ground azimuth of view `i`, degrees (measured, or even spacing).
func view_angle(i: int) -> float:
	if view_azimuths.size() == heads.size() and i < view_azimuths.size():
		return view_azimuths[i]
	return i * 360.0 / maxi(1, heads.size())


## Barrel cone half angle of view `v` on the ground, degrees. Auto: half the larger gap to its
## neighbours (+0.5°), so every direction is covered by the nearest view — no dead zones.
func cone_deg(v: int) -> float:
	if barrel_cone > 0.0:
		return barrel_cone
	var n := maxi(1, heads.size())
	var a := view_angle(v)
	var prev := fposmod(a - view_angle(posmod(v - 1, n)), 360.0)
	var next := fposmod(view_angle((v + 1) % n) - a, 360.0)
	if n == 1:
		return 180.0
	return maxf(prev, next) * 0.5 + 0.5


## View whose azimuth is nearest to `deg`.
func nearest_view(deg: float) -> int:
	var best := 0
	var best_d := 1e9
	for i in heads.size():
		var d := absf(wrapf(deg - view_angle(i), -180.0, 180.0))
		if d < best_d:
			best_d = d
			best = i
	return best
